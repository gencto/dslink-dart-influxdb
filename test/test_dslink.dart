import 'package:dslink/dslink.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:io';

late LinkProvider link;

const String databaseName = 'testdb';
const String watchGroupName = 'testGroup';

void main() {
  setUpAll(() async {
    link = LinkProvider(
      ["--broker", "${Platform.environment['BROKER']}", "--log", "debug"],
      'testing-influxdb',
      defaultLogLevel: 'DEBUG',
      isResponder: true,
      isRequester: true,
    );

    await link.connect();
  });

  tearDownAll(() async {
    link.close();
  });

  group('InfluxDB DSLink Tests', () {
    test('Create Database', () async {
      final completer = Completer<void>();

      await link.onRequesterReady.then((Requester? req) {
        expect(req, isNotNull);

        if (req != null) {
          req.invoke(
            '/downstream/influxdb/addDatabase',
            {
              'Name': databaseName,
              'URL': Platform.environment['DB_URL'],
              'Token': Platform.environment['DB_TOKEN'],
              'Org': Platform.environment['DB_ORG'],
              'Bucket': Platform.environment['DB_BUCKET'],
            },
            Permission.CONFIG,
            (Request request) async {
              await successfullCreateDatabase(request);
              completer.complete();
            },
          );
        }
      });

      await completer.future;
    });

    test('Create Watch Group', () async {
      final completer = Completer<void>();

      await link.onRequesterReady.then((Requester? req) {
        expect(req, isNotNull);

        req?.invoke(
          '/downstream/influxdb/$databaseName/createWatchGroup',
          {
            'Name': watchGroupName,
          },
          Permission.CONFIG,
          (Request request) async {
            await successfullCreateGroup(request);
            completer.complete();
          },
        );
      });

      await completer.future;
    });

    test('Add Watch Paths', () async {
      final completer = Completer<void>();

      await link.onRequesterReady.then((Requester? req) {
        expect(req, isNotNull);
        const List<String> paths = [
          '/sys/dataInPerSecond',
          '/sys/dataOutPerSecond',
          '/sys/handledRequests',
        ];

        for (var path in paths) {
          req?.invoke(
            '/downstream/influxdb/$databaseName/$watchGroupName/addWatchPath',
            {
              'Path': path,
            },
            Permission.CONFIG,
            (Request request) async {
              await successfullCreateWatchPath(request);
              if (paths.last == path) {
                completer.complete();
              }
            },
          );
        }
      });

      await completer.future;
    });
  });
}

Future<void> successfullCreateDatabase(Request request) async {
  expect(
    await request.requester.getRemoteNode('/downstream/influxdb/$databaseName'),
    isNotNull,
    reason: 'Error during database creation',
  );
  expect(
    request.data?.isNotEmpty,
    isTrue,
    reason: 'No response updates received',
  );
  print('Database $databaseName created successfully');
}

Future<void> successfullCreateGroup(Request request) async {
  expect(
    await request.requester
        .getRemoteNode('/downstream/influxdb/$databaseName/$watchGroupName'),
    isNotNull,
    reason: 'Error during watch group creation',
  );
  expect(
    request.data?.isNotEmpty,
    isTrue,
    reason: 'No response updates received',
  );
  print('Watch group $watchGroupName created successfully');
}

Future<void> successfullCreateWatchPath(Request request) async {
  expect(
    request.requester
        .list('/downstream/influxdb/$databaseName/$watchGroupName'),
    isNotNull,
    reason: 'Error during watch path addition',
  );
  expect(
    request.data?.isNotEmpty,
    isTrue,
    reason: 'No response updates received',
  );
  print('Watch path added successfully');
}
