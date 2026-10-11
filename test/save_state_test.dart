import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';

void main() {
  late Directory directory;
  late SSHStore store;
  late SSHHost host;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harbor-save-state-');
    final file = File('${directory.path}/config');
    await file.writeAsString(
      'Host demo\n  HostName example.test\n  User mark\n  Port 2222\n  Compression yes\n  ConnectTimeout 10\n',
    );
    store = SSHStore(
      load: false,
      configFile: file,
      metadataFile: File('${directory.path}/metadata.json'),
    );
    await store.loadConfig();
    host = store.hosts.single;
  });
  tearDown(() async {
    await store.saveMetadata();
    store.dispose();
    await directory.delete(recursive: true);
  });

  test('restoring fields and renamed aliases restores saved status', () {
    expect(store.isDirty('demo'), isFalse);
    var notifications = 0;
    store.addListener(() => notifications++);
    host.port = '2200';
    store.markDirty('demo');
    expect(store.isDirty('demo'), isTrue);
    host.port = '2222';
    store.markDirty('demo');
    expect(store.isDirty('demo'), isFalse);
    expect(notifications, 2);
    store.renameHost(host, 'renamed');
    expect(store.isDirty('renamed'), isTrue);
    store.renameHost(host, 'demo');
    expect(store.isDirty('demo'), isFalse);
  });

  test('advanced option insertion order and restored forwards are clean', () {
    host.advancedOptions.remove('Compression');
    store.markDirty('demo');
    expect(store.isDirty('demo'), isTrue);
    host.advancedOptions['Compression'] = 'yes';
    store.markDirty('demo');
    expect(store.isDirty('demo'), isFalse);
    host.localForwards.add('8080:localhost:80');
    store.markDirty('demo');
    expect(store.isDirty('demo'), isTrue);
    host.localForwards.clear();
    store.markDirty('demo');
    expect(store.isDirty('demo'), isFalse);
  });

  test(
    'new connection stays dirty until saved and uses new baseline',
    () async {
      final added = store.addHost();
      expect(store.isDirty(added.hostAlias), isTrue);
      await store.saveConfig();
      expect(store.isDirty(added.hostAlias), isFalse);
      added.user = 'other';
      store.markDirty(added.hostAlias);
      expect(store.isDirty(added.hostAlias), isTrue);
      added.user = '';
      store.markDirty(added.hostAlias);
      expect(store.isDirty(added.hostAlias), isFalse);
    },
  );

  test('edits and new hosts during save remain unsaved', () async {
    host.user = 'written';
    store.markDirty('demo');
    final saving = store.saveConfig();
    host.user = 'later';
    store.markDirty('demo');
    final added = store.addHost();
    await saving;
    expect(await store.configFile!.readAsString(), contains('User written'));
    expect(store.isDirty('demo'), isTrue);
    expect(store.isDirty(added.hostAlias), isTrue);
    host.user = 'written';
    store.markDirty('demo');
    expect(store.isDirty('demo'), isFalse);
  });

  test('failed save preserves the last successful baseline', () async {
    await store.configFile!.delete();
    await Directory(store.configFile!.path).create();
    host.user = 'changed';
    store.markDirty('demo');
    await store.saveConfig();
    expect(store.isDirty('demo'), isTrue);
    host.user = 'mark';
    store.markDirty('demo');
    expect(store.isDirty('demo'), isFalse);
  });
}
