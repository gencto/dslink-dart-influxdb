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
      {'name': 'url', 'type': 'string'},
      {'name': 'token', 'type': 'string'},
      {'name': 'org', 'type': 'string'},
      {'name': 'bucket', 'type': 'string'}
    ];
  }

  @override
  Future<HistorianDatabaseAdapter> getDatabase(Map config) async {
    String url = config['url'];
    String token = config['token'];
    String org = config['org'];
    String bucket = config['bucket'];

    late InfluxDBHistorianDatabaseAdapter client;
    await Chain.capture(() async {
      client = InfluxDBHistorianDatabaseAdapter(
        url: url,
        token: token,
        org: org,
        bucket: bucket,
      );
    }, when: const bool.fromEnvironment("dsa.mode.debug", defaultValue: false));

    return client;
  }
}

class InfluxDBHistorianDatabaseAdapter extends HistorianDatabaseAdapter {
  final String url;
  final String token;
  final String org;
  final String bucket;
  Timer? dbStatsTimer;

  StreamController<ValueEntry> entryStream =
      StreamController<ValueEntry>.broadcast();

  InfluxDBHistorianDatabaseAdapter({
    required this.url,
    required this.token,
    required this.org,
    required this.bucket,
  }) {
    client = InfluxDBClient(
      url: url,
      token: token,
      org: org,
      bucket: bucket,
      debug: false,
    );
    _setup();
  }

  late final InfluxDBClient client;

  void _setup() {
    logger.info('DataBase is ready!');
    dbStatsTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
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

        logger.info('Count of rows written in the last minute: $objectCount');
      } catch (e, s) {
        logger.warning(
            "Failed to create InfluxDBHistorianDatabaseAdapter", e, s);
      }
    });
  }

  @override
  Future close() async {
    await entryStream.close();
    dbStatsTimer?.cancel();
    client.close();
  }

  @override
  Stream<ValuePair> fetchHistory(
      String group, String path, TimeRange range) async* {
    var query = '''
      from(bucket: "$bucket")
        |> range(start: ${convertToIso8601(range.start.toIso8601String())}, stop: ${convertToIso8601(range.end?.toIso8601String())})
        |> filter(fn: (r) => r["_field"] == "$path")
    ''';

    final QueryService queryService = client.getQueryService();
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
        |> filter(fn: (r) => r._field == "$path")
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
    // InfluxDB does not have a direct delete feature like SQL
    return Future.value();
  }

  @override
  Future purgePath(String group, String path, TimeRange range) async {
    // InfluxDB does not have a direct delete feature like SQL
    return Future.value();
  }

  @override
  Future store(List<ValueEntry> entries) async {
    if (!entryStream.isClosed) {
      entries.forEach(entryStream.add);
    }

    if (entries.isNotEmpty) {
      var points = entries.map((entry) {
        return Point('measurement')
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
