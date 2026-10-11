import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

class MappingProcess implements Process {
  final output = StreamController<List<int>>();
  final completion = Completer<int>();
  @override
  Stream<List<int>> get stderr => output.stream;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Future<int> get exitCode => completion.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!completion.isCompleted) completion.complete(255);
    unawaited(output.close());
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MappingMemoryStore extends SSHStore {
  MappingMemoryStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Mapping metadata is backward compatible and keeps identity when edited',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-mapping-groups-',
      );
      final metadata = File('${directory.path}/library.json');
      final store = SSHStore(load: false, metadataFile: metadata);
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      final legacy = ManagedMapping.fromJson({
        'id': 'old',
        'server': 'lab',
        'type': 'D',
        'value': '1080',
      });
      expect(legacy.group, isEmpty);
      expect(legacy.tags, isEmpty);
      await store.addMapping(
        'lab',
        'L',
        '8080:localhost:80',
        group: ' Work ',
        tags: ['db', 'prod', 'db', ' '],
      );
      final rule = store.mappings.single;
      final id = rule.id;
      await store.updateMapping(
        rule,
        'lab',
        'L',
        '8081:localhost:80',
        group: 'Dev',
        tags: ['db', 'local'],
      );
      expect(rule.id, id);
      await store.renameMappingGroup('Dev', 'Testing');
      final reloaded = SSHStore(load: false, metadataFile: metadata);
      addTearDown(reloaded.dispose);
      await reloaded.loadMetadata();
      expect(reloaded.mappings.single.id, id);
      expect(reloaded.mappings.single.group, 'Testing');
      expect(reloaded.mappings.single.tags, ['db', 'local']);
      expect(reloaded.mappings.single.value, '8081:localhost:80');
      await reloaded.renameMappingGroup('Testing', '');
      expect(reloaded.mappings.single.group, isEmpty);
    },
  );

  test(
    'Group start preserves running members, isolates other groups and reports conflicts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-mapping-start-',
      );
      final spawned = <List<String>>[];
      final store = SSHStore(
        load: false,
        metadataFile: File('${directory.path}/library.json'),
        processStarter: (executable, arguments) async {
          spawned.add(arguments);
          final process = MappingProcess();
          process.output.add(utf8.encode('Entering interactive session.\n'));
          return process;
        },
      );
      store.hosts = [
        SSHHost(
          hostAlias: 'lab',
          hostName: 'lab.test',
          localForwards: ['9000:localhost:90'],
        ),
      ];
      addTearDown(() async {
        await store.shutdownProxies();
        store.dispose();
        await directory.delete(recursive: true);
      });
      await store.addMapping('lab', 'L', '8080:localhost:80', group: 'Work');
      await store.addMapping('lab', 'D', '1080', group: 'Work');
      await store.addMapping(
        'lab',
        'L',
        '8080:localhost:81',
        group: 'Conflict',
      );
      await store.addMapping('lab', 'D', '1081', group: 'Other');
      expect(await store.startMappingGroup('Work'), isEmpty);
      expect(spawned.length, 2);
      expect(store.mappings.take(2).every(store.mappingRunning), isTrue);
      expect(
        spawned.every(
          (args) =>
              args.contains('/dev/null') && !args.contains('9000:localhost:90'),
        ),
        isTrue,
      );
      expect(await store.startMappingGroup('Work'), isEmpty);
      expect(spawned.length, 2);
      final id = store.mappings.first.id;
      await store.updateMapping(
        store.mappings.first,
        'lab',
        'L',
        '8080:localhost:80',
        group: 'Work',
        tags: ['prod'],
      );
      expect(store.mappingRunning(store.mappings.first), isTrue);
      expect(store.mappings.first.id, id);
      expect(await store.startMappingGroup('Conflict'), hasLength(1));
      expect(store.mappingRunning(store.mappings.last), isFalse);
      expect(await store.startMappingGroup('Other'), isEmpty);
      await store.stopMappingGroup('Work');
      expect(store.mappings.take(2).any(store.mappingRunning), isFalse);
      expect(store.mappingRunning(store.mappings.last), isTrue);
    },
  );

  test('Group stop cancels pending spawns', () async {
    final directory = await Directory.systemTemp.createTemp(
      'harbor-group-cancel-',
    );
    final pending = Completer<Process>();
    final store = SSHStore(
      load: false,
      metadataFile: File('${directory.path}/library.json'),
      processStarter: (_, _) => pending.future,
    );
    store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
    await store.addMapping('lab', 'D', '1080', group: 'Work');
    final starting = store.startMappingGroup('Work');
    await Future<void>.delayed(Duration.zero);
    expect(store.mappingLoading(store.mappings.single), isTrue);
    await store.stopMappingGroup('Work');
    final process = MappingProcess();
    pending.complete(process);
    await starting;
    expect(process.completion.isCompleted, isTrue);
    expect(store.mappingRunning(store.mappings.single), isFalse);
    await store.shutdownProxies();
    store.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Server forwards retain local, remote and SOCKS settings across save and launch commands',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-config-forwards-',
      );
      final file = File('${directory.path}/config');
      await file.writeAsString(
        'Host lab\n  HostName lab.test\n  LocalForward 8080 localhost:80\n  RemoteForward 8081 localhost:81\n  RemoteForward 8082 localhost:82\n  DynamicForward 1080\n',
      );
      final store = SSHStore(load: false, configFile: file);
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      await store.loadConfig();
      final host = store.hosts.single;
      expect(host.remoteForwards, ['8081:localhost:81', '8082:localhost:82']);
      host.remoteForwards[0] = '8083:localhost:83';
      expect(store.isDirty('lab'), isTrue);
      expect(await store.saveConfig(), isTrue);
      await store.loadConfig();
      expect(store.hosts.single.remoteForwards, [
        '8083:localhost:83',
        '8082:localhost:82',
      ]);
      final command = store.hosts.single.getPreviewCommand();
      expect(command, contains('-R 8083:localhost:83'));
      expect(command, contains('-L 8080:localhost:80'));
      expect(command, contains('-D 1080'));
    },
  );

  testWidgets(
    'Global mappings group and filter tags without changing group membership',
    (tester) async {
      final store = MappingMemoryStore();
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
      await store.addMapping(
        'lab',
        'L',
        '8080:localhost:80',
        group: 'Work',
        tags: ['prod'],
      );
      await store.addMapping('lab', 'D', '1080', group: 'Work', tags: ['dev']);
      await store.addMapping('lab', 'D', '1081', group: 'Home', tags: ['home']);
      addTearDown(store.dispose);
      await tester.binding.setSurfaceSize(const Size(720, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborForwardingPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Start group'), findsNWidgets(2));
      await tester.tap(find.text('#prod').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('mapping:${store.mappings[0].id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('mapping:${store.mappings[1].id}')),
        findsNothing,
      );
      expect(find.text('Home'), findsNothing);
      expect(find.text('0/2 running'), findsOneWidget);
      await tester.tap(find.text('All tags'));
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'Search servers, groups, tags or ports…',
      );
      await tester.enterText(
        find.descendant(of: search, matching: find.byType(EditableText)),
        '1081',
      );
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
