import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

void main() {
  test('Favorites and groups persist and follow a renamed host', () async {
    final dir = await Directory.systemTemp.createTemp('ssh-library-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final store = SSHStore(load: false, metadataFile: file);
    final host = SSHHost(hostAlias: 'lab', hostName: 'lab.example');
    store.hosts = [host];
    store.search('');
    await store.toggleFavorite(host);
    await store.setGroup(host, ' Research ');
    store.renameHost(host, 'lab-new');
    await store.saveMetadata();
    final restored = SSHStore(load: false, metadataFile: file);
    await restored.loadMetadata();
    expect(restored.isFavorite(host), isTrue);
    expect(restored.favorites.contains('lab'), isFalse);
    expect(restored.groupFor(host), 'Research');
    await restored.setGroup(host, '');
    await restored.toggleFavorite(host);
    final removed = SSHStore(load: false, metadataFile: file);
    await removed.loadMetadata();
    expect(removed.isFavorite(host), isFalse);
    expect(removed.groupFor(host), 'Ungrouped');
  });

  test('Filtering by group preserves a visible selection', () async {
    final dir = await Directory.systemTemp.createTemp('ssh-selection-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store =
        SSHStore(load: false, metadataFile: File('${dir.path}/library.json'));
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

  testWidgets('Quick connect searches groups and supports arrows and Escape',
      (tester) async {
    final store = SSHStore(load: false);
    store.hosts = [
      SSHHost(hostAlias: 'alpha', hostName: 'a.example'),
      SSHHost(hostAlias: 'beta', hostName: 'b.example')
    ];
    store.hostGroups['beta'] = 'Research';
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MacosApp(
            home: Builder(
                builder: (context) => Center(
                    child: PushButton(
                        controlSize: ControlSize.regular,
                        onPressed: () => showMacosSheet(
                            context: context,
                            builder: (_) => ChangeNotifierProvider.value(
                                value: store,
                                child: const QuickConnectSheet())),
                        child: const Text('Open')))))));
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
  testWidgets('Command K opens quick connect from the main window',
      (tester) async {
    final store = SSHStore(load: false);
    store.hosts = [SSHHost(hostAlias: 'test-host', hostName: 'example.test')];
    store.search('');
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MacosApp(home: MainWindow())));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsNothing);
  });
}
