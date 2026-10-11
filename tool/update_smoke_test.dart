// Builds an older, isolated app that exercises the production updater against
// the published release. Use --dart-define=HARBOR_SMOKE_DIR=/tmp/harbor-update-smoke-...
// and --build-name 1.0.0 --build-number 2. Never launch from the normal install.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const directory = String.fromEnvironment('HARBOR_SMOKE_DIR');
  if (!directory.startsWith('/tmp/harbor-update-smoke-')) {
    throw StateError('An isolated HARBOR_SMOKE_DIR is required.');
  }
  final root = Directory(directory);
  await root.create(recursive: true);
  final config = File('$directory/config');
  await config.writeAsString('');
  final store = SSHStore(
    load: false,
    metadataFile: File('$directory/metadata.json'),
    configFile: config,
  );
  runApp(
    ChangeNotifierProvider<SSHStore>.value(
      value: store,
      child: const HarborApplication(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await const MethodChannel(
      'harbor/files',
    ).invokeMethod<void>('firstFrameReady');
    await store.loadApplicationInfo();
    await store.checkForUpdates();
    final report = File('$directory/report.json');
    await report.writeAsString(
      jsonEncode({
        'oldVersion': store.applicationVersion,
        'oldBuild': store.applicationBuild,
        'newVersion': store.availableUpdate?.version,
        'newBuild': store.availableUpdate?.build,
        'status': store.updateStatus,
        'pid': pid,
      }),
    );
    if (store.availableUpdate == null) return;
    await store.installUpdate();
    // Reached only before termination or on failure; record the last status.
    await report.writeAsString(
      jsonEncode({
        'oldVersion': store.applicationVersion,
        'oldBuild': store.applicationBuild,
        'newVersion': store.availableUpdate?.version,
        'newBuild': store.availableUpdate?.build,
        'status': store.updateStatus,
        'failed': store.updateError,
        'pid': pid,
      }),
    );
  });
}
