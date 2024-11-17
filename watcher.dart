import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:watcher/watcher.dart';

Future<void> main() async {
  final watcher = DirectoryWatcher('bin');
  Process? serverProcess;

  Future<void> startDSLink() async {
    serverProcess = await Process.start(
      'dart',
      [
        'run',
        'bin/dslink.dart',
        '--broker',
        '${Platform.environment['BROKER']}',
        '--log',
        'debug',
        '${bool.fromEnvironment("dsa.mode.debug", defaultValue: false)}',
      ],
    );
    serverProcess?.stdout.transform(utf8.decoder).listen((data) {
      print(data);
    });
    serverProcess?.stderr.transform(utf8.decoder).listen((data) {
      print(data);
    });
  }

  Future<void> restartDSLink() async {
    if (serverProcess != null) {
      serverProcess?.kill();
      serverProcess = null;
    }
    await startDSLink();
  }

  watcher.events.listen((event) async {
    print('File change detected: ${event.path}');
    await restartDSLink();
  });

  // Start the server initially
  await startDSLink();
}
