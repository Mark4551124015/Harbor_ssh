import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

class TagsMemoryStore extends SSHStore {
  TagsMemoryStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() {
  test(
    'Server tags persist, search, follow renames and stay separate from mapping tags',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-server-tags-',
      );
      final config = File('${directory.path}/config');
      final metadata = File('${directory.path}/library.json');
      await config.writeAsString(
        'Host lab\n  HostName lab.test\nHost prod\n  HostName prod.test\n',
      );
      final store = SSHStore(
        load: false,
        configFile: config,
        metadataFile: metadata,
      );
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      await store.loadConfig();
      final host = store.hosts.first;
      await store.setHostTags(host, [' work ', 'db', 'work', '']);
      await store.setHostTags(store.hosts.last, ['production']);
      await store.addMapping('lab', 'D', '1080', tags: ['proxy']);
      expect(store.tagsFor(host), ['db', 'work']);
      await store.setHostIcon(host, null);
      expect(store.tagsFor(host), ['db', 'work']);
      expect(store.isDirty('lab'), isFalse);
      expect(await config.readAsString(), isNot(contains('work')));
      store.search('work');
      expect(store.filteredHosts, [host]);
      store.search('#WORK');
      expect(store.filteredHosts, [host]);
      store.search('#prod');
      expect(store.filteredHosts, isEmpty);
      store.search('#production');
      expect(store.filteredHosts.single.hostAlias, 'prod');
      store.search('');
      store.renameHost(host, 'renamed');
      await store.saveMetadata();
      await store.saveConfig();
      expect(store.tagsFor(host), ['db', 'work']);
      expect(store.hostTags.containsKey('lab'), isFalse);
      final reloaded = SSHStore(
        load: false,
        configFile: config,
        metadataFile: metadata,
      );
      addTearDown(reloaded.dispose);
      await reloaded.loadMetadata();
      await reloaded.loadConfig();
      expect(reloaded.tagsFor(reloaded.hosts.first), ['db', 'work']);
      expect(reloaded.mappings.single.tags, ['proxy']);
      expect(reloaded.mappings.single.serverAlias, 'renamed');
      store.deleteHost(host);
      await store.saveConfig();
      await store.saveMetadata();
      expect(store.hostTags.containsKey('renamed'), isFalse);
      expect(store.hostTags['prod'], ['production']);
    },
  );

  testWidgets(
    'Server tag editor saves and removes tags at minimum window size',
    (tester) async {
      final store = TagsMemoryStore();
      final host = SSHHost(hostAlias: 'lab', hostName: 'lab.test');
      store.hosts.add(host);
      store.selectHost(host);
      addTearDown(store.dispose);
      await tester.binding.setSurfaceSize(const Size(960, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HostDetailTabs(initialTab: 1)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit tags…'));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'work, production',
      );
      await tester.enterText(
        find.descendant(of: input, matching: find.byType(EditableText)),
        'work, db, work',
      );
      await tester.tap(find.text('Save tags'));
      await tester.pumpAndSettle();
      expect(store.tagsFor(host), ['db', 'work']);
      expect(find.text('#db #work'), findsOneWidget);
      expect(store.isDirty('lab'), isFalse);
      await tester.tap(find.text('Edit tags…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: input, matching: find.byType(EditableText)),
        '',
      );
      await tester.tap(find.text('Save tags'));
      await tester.pumpAndSettle();
      expect(store.tagsFor(host), isEmpty);
      expect(find.text('No tags'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
