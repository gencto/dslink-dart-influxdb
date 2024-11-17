import 'dart:async';
import 'package:influxdb_client/api.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:dslink/historian.dart';

import "package:dslink/dslink.dart";
import "package:dslink/utils.dart";

void main(List<String> args) async {
  await historianMain(args, 'influxdb', InfluxDBHistorianAdapter());
}

class InfluxDBHistorianAdapter extends HistorianAdapter {
  @override
  List<Map> getCreateDatabaseParameters() {
    return [
      {'name': 'URL', 'type': 'string', 'placeholder': 'DB'},
      {'name': 'Token', 'type': 'string', 'placeholder': 'U9VGjVS7cZ_...'},
      {'name': 'Org', 'type': 'string', 'placeholder': 'Org'},
      {'name': 'Bucket', 'type': 'string', 'placeholder': 'Bucket'}
    ];
  }

  @override
  Future<HistorianDatabaseAdapter> getDatabase(Map config) async {
    final String name = config['Name'];
    final String url = config['URL'];
    final String token = config['Token'];
    final String org = config['Org'];
    final String bucket = config['Bucket'];
    final bool debug =
        const bool.fromEnvironment("dsa.mode.debug", defaultValue: false);

    late InfluxDBHistorianDatabaseAdapter client;
    await Chain.capture(() async {
      client = InfluxDBHistorianDatabaseAdapter(
        name: name,
        url: url,
        token: token,
        org: org,
        bucket: bucket,
        debug: debug,
      );
    }, when: debug);

    return client;
  }
}

class InfluxDBHistorianDatabaseAdapter extends HistorianDatabaseAdapter {
  final String name;
  final String url;
  final String token;
  final String org;
  final String bucket;
  final bool debug;
  Timer? dbStatsTimer;

  StreamController<ValueEntry> entryStream =
      StreamController<ValueEntry>.broadcast();

  InfluxDBHistorianDatabaseAdapter({
    required this.name,
    required this.url,
    required this.token,
    required this.org,
    required this.bucket,
    required this.debug,
  }) {
    client = InfluxDBClient(
      url: url,
      token: token,
      org: org,
      bucket: bucket,
      debug: debug,
    );
    _setup();
    queryService = client.getQueryService();
  }

  late final InfluxDBClient client;
  late final QueryService queryService;

  void _setup() {
    logger.info('DataBase $name is ready!');
    dbStatsTimer = Timer.periodic(Duration(seconds: 60), (timer) async {
      try {
        final queryApi = client.getQueryService();
        final fluxQuery = '''
          from(bucket: "$bucket")
            |> range(start: -1m)
            |> count()
        ''';

        final queryResults = await queryApi.query(fluxQuery);

        num objectCount = 0;
        await for (var record in queryResults) {
          if (record['_value'] != null) {
            objectCount += record['_value'];
          }
        }

        logger.info(
            'Count of rows written in $name the last of minute: $objectCount');
      } catch (e, s) {
        logger.warning(
            "Failed to create InfluxDBHistorianDatabaseAdapter for $name",
            e,
            s);
      }
    });
  }

  @override
  Future close() async {
    await entryStream.close();
    dbStatsTimer?.cancel();
    client.close();
    logger.info('Conection close for $name');
  }

  @override
  Stream<ValuePair> fetchHistory(
      String group, String path, TimeRange range) async* {
    var query = '''
      from(bucket: "$bucket")
        |> range(start: ${convertToIso8601(range.start.toIso8601String())}, stop: ${convertToIso8601(range.end?.toIso8601String() ?? DateTime.now().toString())})
        |> filter(fn: (r) => r["_measurement"] == "$group")
        |> filter(fn: (r) => r["_field"] == "$path")
    ''';

    
    var result = await queryService.query(query);

    await for (var record in result) {
      yield ValuePair(record['_time'], record['_value']);
    }

    if (range.end == null) {
      await for (ValueEntry entry in entryStream.stream.where((x) {
        return x.path == path;
      })) {
        yield ValuePair(entry.timestamp, entry.value);
      }
    }
  }

  void addToStream(ValueEntry newEntry) {
    entryStream.add(newEntry);
  }

  @override
  Future<HistorySummary> getSummary(String? group, String path) async {
    var query = '''
      from(bucket: "$bucket")
        |> range(start: -1y)
        |> filter(fn: (r) => r["_measurement"] == "$group")
        |> filter(fn: (r) => r["_field"] == "$path")
        |> first()
        |> last()
    ''';

    final QueryService queryService = client.getQueryService();
    var result = await queryService.query(query);

    var firstRecord = [];
    await result.forEach((record) {
      print('${record['_time']}: ${record['_field']} = ${record['_value']}');
      firstRecord.add(ValuePair(record['_time'], record['_value']));
    });

    return HistorySummary(
      first: firstRecord.firstOrNull,
      last: firstRecord.lastOrNull,
    );
  }

  @override
  Future purgeGroup(String group, TimeRange range) async {
    final deleteService = client.getDeleteService();
    final String predicate = '_measurement="$group"';

    return deleteService.delete(
      start: range.start,
      stop: range.end ?? DateTime.now().toUtc(),
      predicate: predicate,
      org: org,
      bucket: bucket,
    );
  }

  @override
  Future purgePath(String group, String path, TimeRange range) async {
    final deleteService = client.getDeleteService();
    final String predicate = '_measurement="$group" AND _field="$path"';

    return deleteService.delete(
      start: range.start,
      stop: range.end ?? DateTime.now().toUtc(),
      predicate: predicate,
      org: org,
      bucket: bucket,
    );
  }

  @override
  Future store(List<ValueEntry> entries) async {
    if (!entryStream.isClosed) {
      entries.forEach(entryStream.add);
    }

    if (entries.isNotEmpty) {
      var points = entries.map((entry) {
        return Point(entry.group)
            .addField(entry.path, entry.value)
            .time(entry.time);
      }).toList();
      try {
        final WriteService writeService = client.getWriteService();
        await writeService.write(points);
      } catch (e, stack) {
        logger.warning("Failed to insert value", e, stack);
      }
    }
  }

  @override
  addWatchPathExtensions(WatchPathNode node) async {
    link.requester
        ?.list(node.valuePath!)
        .listen((RequesterListUpdate update) async {
      var ghr =
          "${link.remotePath}/${node.group?.db?.name}/${node.group?.name}/${node.name}/getHistory";
      var bgh =
          "${link.remotePath}/${node.group?.name}/${node.name}/getHistory";
      if (!update.node.attributes.containsKey("@@getHistory") ||
          update.node.attributes["@@getHistory"] == bgh) {
        link.requester?.set("${node.valuePath}/@@getHistory", {
          "@": "merge",
          "type": "paths",
          "val": [ghr]
        });
      }
    });
  }
}

String? convertToIso8601(String? inputDate) {
  if (inputDate == null) return null;
  inputDate = inputDate.trim();
  DateTime parsedDate = DateTime.parse(inputDate);
  return parsedDate.toUtc().toIso8601String();
}
