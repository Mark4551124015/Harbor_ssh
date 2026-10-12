import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class DeletionTestStore extends SSHStore {
  DeletionTestStore() : super(load: false);
  int deletions = 0;
  @override
  void deleteHost(SSHHost host) {
    deletions++;
  }
}

class GroupTestStore extends SSHStore {
  GroupTestStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

class TunnelTestProcess implements Process {
  final output = StreamController<List<int>>();
  final completion = Completer<int>();
  bool killed = false;
  @override
  Stream<List<int>> get stderr => output.stream;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Future<int> get exitCode => completion.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!completion.isCompleted) completion.complete(255);
    unawaited(output.close());
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Mappings start and stop independently and retain jump/key options',
    () async {
      final arguments = <List<String>>[];
      final processes = <TunnelTestProcess>[];
      final store = SSHStore(
        load: false,
        processStarter: (exe, args) async {
          expect(exe, 'ssh');
          arguments.add(args);
          final process = TunnelTestProcess();
          processes.add(process);
          process.output.add(utf8.encode('Entering interactive session.\n'));
          return process;
        },
      );
      final host = SSHHost(
        hostAlias: 'lab',
        hostName: 'example.test',
        proxyJump: 'jump',
        identityFile: '/tmp/key',
        localForwards: ['8080:localhost:80', '5432:database:5432'],
      );
      store.hosts = [host];
      store.search('');
      expect(
        await store.toggleForward(host, 'L', host.localForwards[0]),
        isNull,
      );
      expect(
        await store.toggleForward(host, 'L', host.localForwards[1]),
        isNull,
      );
      expect(
        arguments[0],
        containsAll([
          '-J',
          'jump',
          '-i',
          '/tmp/key',
          '-L',
          '8080:localhost:80',
        ]),
      );
      expect(arguments[0], isNot(contains('5432:database:5432')));
      await store.stopForward(host, 'L', host.localForwards[0]);
      expect(processes[0].killed, isTrue);
      expect(processes[1].killed, isFalse);
      expect(store.isForwardRunning(host, 'L', host.localForwards[1]), isTrue);
      await store.stopProxy(host.hostAlias);
      expect(processes[1].killed, isTrue);
      expect(store.isConnected(host.hostAlias), isFalse);
    },
  );
  test(
    'Managed mappings persist separately and run independent commands',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-mappings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final config = File('${directory.path}/config');
      await config.writeAsString('untouched config');
      final metadata = File('${directory.path}/library.json');
      final commands = <List<String>>[];
      final processes = <TunnelTestProcess>[];
      final store = SSHStore(
        load: false,
        metadataFile: metadata,
        configFile: config,
        processStarter: (_, args) async {
          commands.add(args);
          final process = TunnelTestProcess();
          processes.add(process);
          Future.microtask(
            () =>
                process.output.add(utf8.encode('Entering interactive session')),
          );
          return process;
        },
      );
      store.hosts = [
        SSHHost(
          hostAlias: 'lab',
          hostName: 'lab.test',
          dynamicForward: '9999',
          localForwards: ['8888:localhost:88'],
        ),
      ];
      await store.addMapping('lab', 'D', '1080');
      await store.addMapping('lab', 'D', '1081');
      final restored = SSHStore(load: false, metadataFile: metadata);
      await restored.loadMetadata();
      expect(restored.mappings.map((item) => item.value), ['1080', '1081']);
      for (final mapping in store.mappings) {
        expect(await store.toggleMapping(mapping), isNull);
      }
      expect(
        commands.first,
        containsAll(['-F', '/dev/null', '-D', '1080', 'lab.test']),
      );
      expect(commands.first, isNot(contains('9999')));
      expect(commands.first, isNot(contains('8888:localhost:88')));
      await store.removeMapping(store.mappings.first);
      expect(processes.first.killed, isTrue);
      expect(processes.last.killed, isFalse);
      expect(await config.readAsString(), 'untouched config');
      expect(store.hosts.first.dynamicForward, '9999');
      await store.stopMapping(store.mappings.single);
    },
  );
  test(
    'Remote forwards run independently and scope listening ports to their server',
    () async {
      final arguments = <List<String>>[];
      final processes = <TunnelTestProcess>[];
      final store = SSHStore(
        load: false,
        processStarter: (_, args) async {
          arguments.add(args);
          final process = TunnelTestProcess();
          processes.add(process);
          process.output.add(utf8.encode('Entering interactive session'));
          return process;
        },
      );
      store.hosts = [
        SSHHost(hostAlias: 'one', hostName: 'one.test'),
        SSHHost(hostAlias: 'two', hostName: 'two.test'),
      ];
      final local = ManagedMapping(
        id: 'local',
        serverAlias: 'one',
        type: 'L',
        value: '8080:localhost:80',
      );
      final first = ManagedMapping(
        id: 'remote1',
        serverAlias: 'one',
        type: 'R',
        value: '8080:localhost:3000',
      );
      final second = ManagedMapping(
        id: 'remote2',
        serverAlias: 'two',
        type: 'R',
        value: '8080:localhost:4000',
      );
      final duplicate = ManagedMapping(
        id: 'remote3',
        serverAlias: 'one',
        type: 'R',
        value: '8080:localhost:5000',
      );
      store.mappings.addAll([local, first, second, duplicate]);
      expect(await store.toggleMapping(local), isNull);
      expect(await store.toggleMapping(first), isNull);
      expect(await store.toggleMapping(second), isNull);
      expect(
        arguments[1],
        containsAll(['-R', '8080:localhost:3000', 'one.test']),
      );
      expect(
        await store.toggleMapping(duplicate),
        contains('Server port 8080'),
      );
      expect(processes.length, 3);
      for (final mapping in store.mappings) {
        await store.stopMapping(mapping);
      }
    },
  );

  testWidgets('Dragging near sidebar edges scrolls down and up', (
    tester,
  ) async {
    final store = GroupTestStore();
    store.hosts = [
      for (var index = 0; index < 35; index++)
        SSHHost(hostAlias: 'host-$index', hostName: '$index.test'),
    ];
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    final sidebar = find.byType(ResizableSidebar);
    final scrollable = find
        .descendant(of: sidebar, matching: find.byType(Scrollable))
        .first;
    final scroll = tester.state<ScrollableState>(scrollable).position;
    final viewport = tester.getRect(scrollable);
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is LibraryHostRow && identical(widget.host, store.hosts.first),
    );
    final gesture = await tester.startGesture(tester.getCenter(row));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 4));
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final down = scroll.pixels;
    expect(down, greaterThan(150));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.top + 4));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.pixels, lessThan(down));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mapping lifecycle keeps page and row geometry fixed', (
    tester,
  ) async {
    final process = TunnelTestProcess();
    final store = SSHStore(
      load: false,
      processStarter: (_, _) async => process,
    );
    store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
    store.mappings.add(
      ManagedMapping(
        id: 'stable',
        serverAlias: 'lab',
        type: 'L',
        value: '8080:localhost:80',
      ),
    );
    store.search('');
    await tester.binding.setSurfaceSize(const Size(960, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Port mappings'));
    await tester.pumpAndSettle();
    final heading = tester.getRect(find.text('Port forwarding'));
    final row = tester.getRect(find.byKey(const ValueKey('mapping:stable')));
    final button = tester.getRect(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(find.byKey(const ValueKey('mapping:stable'))), row);
    expect(tester.getRect(find.text('Port forwarding')), heading);
    process.output.add(utf8.encode('Entering interactive session'));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('mapping:stable'))), row);
    expect(tester.getRect(find.text('Port forwarding')), heading);
    expect(tester.getCenter(find.text('Stop')).dy, button.center.dy);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('mapping:stable'))), row);
    expect(tester.getRect(find.text('Port forwarding')), heading);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Global forwarding page chooses server and manages mappings', (
    tester,
  ) async {
    final store = GroupTestStore();
    final first = SSHHost(
      hostAlias: 'production',
      hostName: 'prod.test',
      localForwards: ['9090:localhost:90'],
    );
    final host = SSHHost(hostAlias: 'lab', hostName: 'example.test');
    store.hosts = [first, host];
    await store.addMapping('production', 'L', '9090:localhost:90');
    store.search('');
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(
          home: Padding(
            padding: EdgeInsets.all(24),
            child: HarborForwardingPage(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add mapping'));
    await tester.pumpAndSettle();
    expect(find.text('production · Local forward'), findsOneWidget);
    await tester.tap(find.byType(HarborServerSelector));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(MacosTextField).last, 'example.test');
    await tester.pumpAndSettle();
    await tester.tap(find.text('lab').last);
    await tester.pumpAndSettle();
    final inputs = find.descendant(
      of: find.byType(HarborAlert),
      matching: find.byType(MacosTextField),
    );
    await tester.enterText(inputs.at(0), '70000');
    await tester.pump();
    expect(
      find.text('Enter a local port between 1 and 65535.'),
      findsOneWidget,
    );
    await tester.enterText(inputs.at(0), '8080');
    await tester.enterText(inputs.at(2), '80');
    await tester.ensureVisible(inputs.at(3));
    await tester.enterText(inputs.at(3), 'Research');
    await tester.ensureVisible(inputs.at(4));
    await tester.enterText(inputs.at(4), 'db, work, db');
    await tester.pump();
    await tester.tap(find.text('Add mapping').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(host.localForwards, isEmpty);
    expect(store.mappings.last.serverAlias, 'lab');
    expect(store.mappings.last.value, '8080:localhost:80');
    expect(store.mappings.last.group, 'Research');
    expect(store.mappings.last.tags, ['db', 'work']);
    expect(find.text('lab · Local forward'), findsOneWidget);
    expect(find.text('Stopped'), findsNWidgets(2));
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('mapping:${store.mappings.last.id}')),
        matching: find.byTooltip('Remove mapping'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.mappings.length, 1);
    expect(host.localForwards, isEmpty);
  });

  testWidgets('Sidebar supports range and additive selection with batch drag', (
    tester,
  ) async {
    final store = GroupTestStore();
    final hosts = [
      for (final name in ['alpha', 'beta', 'gamma'])
        SSHHost(hostAlias: name, hostName: '$name.test'),
    ];
    store.hosts = hosts;
    store.explicitGroups.add('Research');
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HarborNavItem),
        matching: find.text('Quick connect'),
      ),
      findsNothing,
    );
    Finder row(SSHHost host) => find.byWidgetPredicate(
      (widget) => widget is LibraryHostRow && identical(widget.host, host),
    );
    int selectedCount() => tester
        .widgetList<LibraryHostRow>(find.byType(LibraryHostRow))
        .where((row) => row.selected)
        .length;
    await tester.tap(row(hosts.first));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row(hosts.last));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(selectedCount(), 3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(row(hosts[1]));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selectedCount(), 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(row(hosts[1]));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(selectedCount(), 3);
    final target = find.byWidgetPredicate(
      (widget) => widget is HarborGroupHeader && widget.name == 'Research',
    );
    final gesture = await tester.startGesture(
      tester.getCenter(row(hosts.first)),
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final folded = find.byWidgetPredicate(
      (widget) =>
          widget is HarborAnimatedHosts && widget.hosts.contains(hosts.first),
    );
    expect(tester.getSize(folded).height, 56);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(hosts.map(store.groupFor), ['Research', 'Research', 'Research']);
    expect(selectedCount(), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Favorite drag preserves size and supports row and section ordering',
    (tester) async {
      final store = GroupTestStore();
      final first = SSHHost(hostAlias: 'first', hostName: 'first.test');
      final second = SSHHost(hostAlias: 'second', hostName: 'second.test');
      store.hosts = [first, second];
      store.favorites.addAll(['first', 'second']);
      store.explicitGroups.add('Research');
      store.search('');
      await tester.binding.setSurfaceSize(const Size(1100, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const MacosApp(home: MainWindow()),
        ),
      );
      await tester.pumpAndSettle();
      final secondRow = find
          .byWidgetPredicate(
            (widget) =>
                widget is LibraryHostRow && identical(widget.host, second),
          )
          .first;
      final firstRow = find
          .byWidgetPredicate(
            (widget) =>
                widget is LibraryHostRow && identical(widget.host, first),
          )
          .first;
      final originalSize = tester.getSize(secondRow);
      final drag = await tester.startGesture(tester.getCenter(secondRow));
      await drag.moveBy(const Offset(15, 0));
      await tester.pump();
      final preview = find
          .byWidgetPredicate(
            (widget) =>
                widget is LibraryHostRow && identical(widget.host, second),
          )
          .last;
      expect(tester.getSize(preview), originalSize);
      await drag.moveTo(tester.getCenter(firstRow));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(store.orderedHosts('Favorites', [first, second]), [second, first]);
      final favoriteHeader = find.byWidgetPredicate(
        (widget) => widget is HarborGroupHeader && widget.name == 'Favorites',
      );
      final researchHeader = find.byWidgetPredicate(
        (widget) => widget is HarborGroupHeader && widget.name == 'Research',
      );
      final sectionDrag = await tester.startGesture(
        tester.getCenter(favoriteHeader),
      );
      await sectionDrag.moveBy(const Offset(15, 0));
      await tester.pump();
      await sectionDrag.moveTo(tester.getCenter(researchHeader));
      await tester.pump();
      await sectionDrag.up();
      await tester.pumpAndSettle();
      expect(
        store.sectionOrder.indexOf('Favorites'),
        greaterThan(store.sectionOrder.indexOf('Research')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('Favorite and section ordering persists', () async {
    final dir = await Directory.systemTemp.createTemp('harbor-order-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final store = SSHStore(load: false, metadataFile: file);
    final first = SSHHost(hostAlias: 'first');
    final second = SSHHost(hostAlias: 'second');
    store.hosts = [first, second];
    store.favorites.addAll(['first', 'second']);
    await store.moveHostBefore(second, first, 'Favorites');
    await store.moveSection('Favorites', 'Research', ['Favorites', 'Research']);
    final restored = SSHStore(load: false, metadataFile: file);
    await restored.loadMetadata();
    expect(restored.orderedHosts('Favorites', [first, second]), [
      second,
      first,
    ]);
    expect(restored.sectionOrder, ['Research', 'Favorites']);
  });

  testWidgets('Context rename rejects duplicates and preserves host metadata', (
    tester,
  ) async {
    final store = GroupTestStore();
    final host = SSHHost(hostAlias: 'original', hostName: 'example.test');
    store.hosts = [host, SSHHost(hostAlias: 'occupied')];
    store.favorites.add('original');
    store.hostGroups['original'] = 'Research';
    store.hostIcons['original'] = 'Cloud';
    store.recentHosts.add('original');
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(LibraryHostRow).first,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    final input = find.byType(MacosTextField).last;
    await tester.enterText(input, 'occupied');
    await tester.pump();
    expect(
      find.text('A connection with this name already exists.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<HarborButton>(find.widgetWithText(HarborButton, 'Rename'))
          .onPressed,
      isNull,
    );
    await tester.enterText(input, 'renamed');
    await tester.pump();
    await tester.tap(find.text('Rename'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(host.hostAlias, 'renamed');
    expect(store.isFavorite(host), isTrue);
    expect(store.groupFor(host), 'Research');
    expect(store.hostIcons['renamed'], 'Cloud');
    expect(store.recentHosts, ['renamed']);
  });
  testWidgets('Context submenu supports keyboard selection at a window edge', (
    tester,
  ) async {
    var chosen = false;
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MacosApp(
        home: HarborContextMenu(
          position: const Offset(995, 695),
          onDismiss: () {},
          entries: [
            HarborMenuEntry(
              'Move to group',
              CupertinoIcons.folder,
              children: [
                HarborMenuEntry(
                  'Production',
                  CupertinoIcons.folder,
                  onSelected: () => chosen = true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(chosen, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sidebar resizes and hosts drag into groups; group menu creates a connection',
    (tester) async {
      final store = GroupTestStore();
      final host = SSHHost(hostAlias: 'drag-host', hostName: 'example.test');
      store.hosts = [host];
      store.hostGroups[host.hostAlias] = 'Alpha';
      store.explicitGroups.add('Beta');
      store.search('');
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const MacosApp(home: MainWindow()),
        ),
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
      final before = tester.getSize(find.byType(ResizableSidebar)).width;
      await tester.drag(handle, const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ResizableSidebar)).width,
        greaterThan(before),
      );
      expect(store.sidebarWidth, greaterThan(before));
      final beta = find.byWidgetPredicate(
        (widget) => widget is HarborGroupHeader && widget.name == 'Beta',
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LibraryHostRow).first),
      );
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(beta));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.groupFor(host), 'Beta');
      await tester.tap(beta, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New connection').last);
      await tester.pumpAndSettle();
      expect(store.currentHost?.hostAlias, 'NewHost');
      expect(store.groupFor(store.currentHost!), 'Beta');
      expect(find.text('Host Alias (Display Name)'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(store.currentHost?.hostAlias, 'NewHost-2');
      await tester.tap(
        find.byType(LibraryHostRow).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy SSH command'), findsNothing);
    },
  );
  test(
    'Deleting a host cleans metadata and preserves another selected host',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-delete-test-');
      addTearDown(() => dir.delete(recursive: true));
      final store = SSHStore(
        load: false,
        configFile: File('${dir.path}/config'),
        metadataFile: File('${dir.path}/library.json'),
      );
      final first = SSHHost(hostAlias: 'one');
      final second = SSHHost(hostAlias: 'two');
      store.hosts = [first, second];
      store.search('');
      store.selectHost(second);
      await store.toggleFavorite(first);
      await store.setHostIcon(first, 'Cloud');
      await store.setGroup(first, 'Research');
      store.recentHosts.add('one');
      store.deleteHost(first);
      await store.saveConfig();
      await store.saveMetadata();
      expect(store.currentHost, same(second));
      expect(store.favorites, isEmpty);
      expect(store.hostIcons, isEmpty);
      expect(store.recentHosts, isEmpty);
      expect(store.groupNames, contains('Research'));
    },
  );

  test('Empty groups persist without hosts', () async {
    final dir = await Directory.systemTemp.createTemp('empty-group-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final store = SSHStore(load: false, metadataFile: file);
    await store.createGroup('Production');
    await store.setSidebarWidth(290);
    final restored = SSHStore(load: false, metadataFile: file);
    await restored.loadMetadata();
    expect(restored.groupNames, ['Production']);
    expect(restored.sidebarWidth, 290);
    final host = SSHHost(hostAlias: 'grouped');
    restored.hosts = [host];
    await restored.setGroup(host, 'Production');
    await restored.renameGroup('Production', 'Live');
    expect(restored.groupFor(host), 'Live');
    expect(restored.groupNames, ['Live']);
    await restored.removeGroup('Live');
    expect(restored.groupFor(host), 'Ungrouped');
    expect(restored.hosts, [host]);
  });

  test(
    'Terminal command file keeps SSH options and removes temporary files',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-command-test-');
      final file = File('${dir.path}/connect.command');
      await file.writeAsString(terminalCommandScript('printf done'));
      final result = await Process.run('/bin/zsh', [file.path]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'done');
      expect(await dir.exists(), isFalse);
      expect(
        terminalCommandScript("ssh -J 'jump' -i key -L 8080:localhost:80 host"),
        contains("exec ssh -J 'jump' -i key -L 8080:localhost:80 host"),
      );
    },
  );
  testWidgets(
    'Host context menu creates a persistent group and moves the host',
    (tester) async {
      final store = GroupTestStore();
      final host = SSHHost(hostAlias: 'context-host', hostName: 'example.test');
      store.hosts = [host];
      store.search('');
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const MacosApp(home: MainWindow()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(LibraryHostRow).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New group…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(MacosTextField).last, 'Production');
      await tester.pump();
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(store.groupFor(host), 'Production');
      expect(store.groupNames, contains('Production'));
    },
  );

  test('ProxyJump survives SSH config loading and saving', () async {
    final dir = await Directory.systemTemp.createTemp('ssh-jump-test-');
    addTearDown(() => dir.delete(recursive: true));
    final config = File('${dir.path}/config');
    await config.writeAsString(
      'Host internal\n  HostName 10.0.0.2\n  ProxyJump alice@bastion:2222,relay\n',
    );
    final store = SSHStore(load: false, configFile: config);
    await store.loadConfig();
    final host = store.hosts.single;
    expect(host.proxyJump, 'alice@bastion:2222,relay');
    expect(host.getPreviewCommand(), contains("-J alice@bastion:2222,relay"));
    await store.saveConfig();
    expect(
      await config.readAsString(),
      contains('ProxyJump alice@bastion:2222,relay'),
    );
    host.proxyJump = '';
    expect(host.toConfigBlock(), isNot(contains('ProxyJump')));
    expect(host.getPreviewCommand(), isNot(contains('-J')));
  });

  testWidgets('Editing preserves cursor position through parent rebuilds', (
    tester,
  ) async {
    var value = 'alpha';
    await tester.pumpWidget(
      MacosApp(
        home: StatefulBuilder(
          builder: (context, update) => Center(
            child: HarborTextField(
              initialValue: value,
              onChanged: (text) => update(() => value = text),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MacosTextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'alXpha',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(value, 'alXpha');
    expect(editable.controller.selection.baseOffset, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete dialog requires explicit confirmation', (tester) async {
    final store = DeletionTestStore();
    final host = SSHHost(hostAlias: 'production');
    await tester.pumpWidget(
      MacosApp(
        home: Builder(
          builder: (context) => Center(
            child: HarborButton(
              label: 'Remove',
              onPressed: () => confirmDeleteHost(context, store, host),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.textContaining('production'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.deletions, 0);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HarborAlert), findsNothing);
    expect(store.deletions, 0);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete connection'));
    await tester.pumpAndSettle();
    expect(store.deletions, 1);
  });

  testWidgets('Glass button activates once by pointer and keyboard', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MacosApp(
        home: Center(
          child: HarborButton(label: 'Connect', onPressed: () => calls++),
        ),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pumpWidget(
      const MacosApp(
        home: Center(child: HarborButton(label: 'Connect', onPressed: null)),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  test('Favorites and groups persist and follow a renamed host', () async {
    final dir = await Directory.systemTemp.createTemp('ssh-library-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final store = SSHStore(load: false, metadataFile: file);
    final host = SSHHost(hostAlias: 'lab', hostName: 'lab.example');
    store.hosts = [host];
    store.search('');
    store.recentHosts.add('lab');
    await store.toggleFavorite(host);
    await store.setHostIcon(host, 'Cloud');
    await store.setGroup(host, ' Research ');
    store.renameHost(host, 'lab-new');
    await store.saveMetadata();
    final restored = SSHStore(load: false, metadataFile: file);
    await restored.loadMetadata();
    expect(restored.isFavorite(host), isTrue);
    expect(restored.favorites.contains('lab'), isFalse);
    expect(restored.groupFor(host), 'Research');
    expect(restored.recentHosts, ['lab-new']);
    expect(restored.hostIcons['lab-new'], 'Cloud');
    expect(restored.hostIcons.containsKey('lab'), isFalse);
    await restored.setGroup(host, '');
    await restored.toggleFavorite(host);
    final removed = SSHStore(load: false, metadataFile: file);
    await removed.loadMetadata();
    expect(removed.isFavorite(host), isFalse);
    expect(removed.groupFor(host), 'Ungrouped');
  });

  test('Group color and icon persist and follow a rename', () async {
    final dir = await Directory.systemTemp.createTemp('harbor-group-style-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final store = SSHStore(load: false, metadataFile: file);
    await store.createGroup('Production');
    await store.setGroupColor('Production', 'Rose');
    await store.setGroupIcon('Production', 'Briefcase');
    expect(store.colorForGroup('Production'), harborGroupPalette['Rose']);
    expect(store.iconForGroup('Production'), CupertinoIcons.briefcase_fill);
    await store.renameGroup('Production', 'Live');
    final restored = SSHStore(load: false, metadataFile: file);
    await restored.loadMetadata();
    expect(restored.colorForGroup('Live'), harborGroupPalette['Rose']);
    expect(restored.iconForGroup('Live'), CupertinoIcons.briefcase_fill);
    expect(restored.groupColors.containsKey('Production'), isFalse);
    await restored.removeGroup('Live');
    expect(restored.groupColors, isEmpty);
    expect(restored.groupIcons, isEmpty);
  });

  testWidgets('Group context menu customizes color and icon', (tester) async {
    final store = GroupTestStore();
    final host = SSHHost(hostAlias: 'styled', hostName: 'styled.test');
    store.hosts = [host];
    store.hostGroups[host.hostAlias] = 'Alpha';
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    final group = find.byWidgetPredicate(
      (widget) => widget is HarborGroupHeader && widget.name == 'Alpha',
    );
    await tester.tap(group, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group appearance…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rose'));
    await tester.tap(find.byTooltip('Briefcase'));
    await tester.pumpAndSettle();
    expect(store.groupColors['Alpha'], 'Rose');
    expect(store.groupIcons['Alpha'], 'Briefcase');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(HarborAlert), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ungrouped is a plain section pinned last and collapsible', (
    tester,
  ) async {
    final store = GroupTestStore();
    final grouped = SSHHost(hostAlias: 'grouped', hostName: 'g.test');
    final loose = SSHHost(hostAlias: 'loose', hostName: 'l.test');
    store.hosts = [grouped, loose];
    store.hostGroups[grouped.hostAlias] = 'Zeta';
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    Finder header(String name) => find.byWidgetPredicate(
      (widget) => widget is HarborGroupHeader && widget.name == name,
    );
    final ungrouped = header('Ungrouped');
    expect(ungrouped, findsOneWidget);
    expect(tester.widget<HarborGroupHeader>(ungrouped).plain, isTrue);
    // Pinned below a group that sorts after it alphabetically.
    expect(
      tester.getTopLeft(ungrouped).dy,
      greaterThan(tester.getTopLeft(header('Zeta')).dy),
    );
    Finder looseRow() => find.byWidgetPredicate(
      (widget) => widget is LibraryHostRow && identical(widget.host, loose),
    );
    expect(looseRow(), findsOneWidget);
    await tester.tap(ungrouped);
    await tester.pumpAndSettle();
    expect(looseRow(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Ungrouped cannot be reordered by section drag', () async {
    final store = GroupTestStore();
    await store.moveSection('Research', 'Favorites', [
      'Favorites',
      'Research',
      'Ungrouped',
    ]);
    expect(store.sectionOrder.contains('Ungrouped'), isFalse);
    expect(store.sectionOrder, ['Favorites', 'Research']);
    await store.moveSection('Ungrouped', 'Favorites', [
      'Favorites',
      'Research',
      'Ungrouped',
    ]);
    expect(store.sectionOrder, ['Favorites', 'Research']);
  });

  test('Filtering by group preserves a visible selection', () async {
    final dir = await Directory.systemTemp.createTemp('ssh-selection-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = SSHStore(
      load: false,
      metadataFile: File('${dir.path}/library.json'),
    );
    final first = SSHHost(hostAlias: 'one');
    final second = SSHHost(hostAlias: 'two');
    store.hosts = [first, second];
    store.search('');
    store.selectIndex(1);
    await store.setGroup(second, 'Research');
    store.search('Research');
    expect(store.currentHost, same(second));
    store.selectHost(first);
    expect(store.currentHost, same(first));
    expect(store.filteredHosts.length, 2);
  });

  testWidgets('Quick connect searches groups and supports arrows and Escape', (
    tester,
  ) async {
    final store = SSHStore(load: false);
    store.hosts = [
      SSHHost(hostAlias: 'alpha', hostName: 'a.example'),
      SSHHost(hostAlias: 'beta', hostName: 'b.example'),
    ];
    store.hostGroups['beta'] = 'Research';
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: MacosApp(
          home: Builder(
            builder: (context) => Center(
              child: PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => showMacosSheet(
                  context: context,
                  builder: (_) => ChangeNotifierProvider<SSHStore>.value(
                    value: store,
                    child: const QuickConnectSheet(),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.enterText(find.byType(MacosTextField), 'Research');
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing);
    expect(find.text('beta'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsNothing);
  });
  testWidgets('Command K opens quick connect from the main window', (
    tester,
  ) async {
    final store = SSHStore(load: false);
    store.hosts = [SSHHost(hostAlias: 'test-host', hostName: 'example.test')];
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const MacosApp(home: MainWindow()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final transition = find.byType(HarborQuickConnectTransition);
    final filter = find.descendant(
      of: transition,
      matching: find.byType(ImageFiltered),
    );
    // Blur only the panel, not a window-sized transparent canvas.
    expect(tester.getSize(filter).width, lessThan(650));
    expect(tester.getSize(filter).height, lessThan(550));
    expect(tester.widget<ImageFiltered>(filter).enabled, isTrue);
    expect(
      find.descendant(of: filter, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(QuickConnectSheet),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<ImageFiltered>(filter).enabled, isFalse);
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'Harbor workbench and details render at minimum width, dark=$dark',
      (tester) async {
        final store = SSHStore(load: false);
        store.hosts = [
          SSHHost(hostAlias: 'lab-host', hostName: 'lab.example'),
          SSHHost(hostAlias: 'compute', hostName: 'compute.example'),
        ];
        store.hostGroups['lab-host'] = 'Research';
        store.recentHosts.add('lab-host');
        store.search('');
        await tester.binding.setSurfaceSize(const Size(960, 680));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ChangeNotifierProvider<SSHStore>.value(
            value: store,
            child: MacosApp(
              theme: MacosThemeData.light(),
              darkTheme: MacosThemeData.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: const MainWindow(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HarborWorkbench), findsOneWidget);
        expect(find.byType(HarborMark), findsWidgets);
        await tester.tap(find.byType(LibraryHostRow).first);
        await tester.pumpAndSettle();
        expect(find.byType(HostDetailTabs), findsOneWidget);
        expect(find.text('Open Terminal'), findsOneWidget);
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();
        expect(find.byType(HarborActivityPage), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(HarborWorkbench), findsOneWidget);
        await tester.tap(find.text('Port mappings'));
        await tester.pumpAndSettle();
        expect(find.byType(HarborForwardingPage), findsOneWidget);
        expect(find.byType(HostDetailTabs), findsNothing);
        await tester.tap(find.text('Workbench'));
        await tester.pumpAndSettle();
        expect(find.byType(HarborWorkbench), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
