import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

class ContextMappingStore extends SSHStore {
  ContextMappingStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Empty mapping groups persist and moving mappings preserves identity and tags',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harbor-empty-mapping-groups-',
      );
      final file = File('${directory.path}/library.json');
      final store = SSHStore(load: false, metadataFile: file);
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      await store.createMappingGroup('Empty');
      await store.addMapping(
        'lab',
        'D',
        '1080',
        group: 'Work',
        tags: ['proxy'],
      );
      final mapping = store.mappings.single;
      final id = mapping.id;
      await store.setMappingGroup(mapping, 'Empty');
      expect(mapping.id, id);
      expect(mapping.tags, ['proxy']);
      expect(store.mappingGroupNames, ['Empty', 'Work']);
      final reloaded = SSHStore(load: false, metadataFile: file);
      addTearDown(reloaded.dispose);
      await reloaded.loadMetadata();
      expect(reloaded.mappingGroupNames, ['Empty', 'Work']);
      await reloaded.renameMappingGroup('Work', 'Renamed');
      expect(reloaded.mappingGroupNames, ['Empty', 'Renamed']);
      await reloaded.renameMappingGroup('Empty', '');
      expect(reloaded.mappingGroupNames, ['Renamed']);
      expect(reloaded.mappings.single.group, isEmpty);
      expect(reloaded.mappings.single.id, id);
    },
  );

  testWidgets(
    'Background and group menus create and rename empty groups and preselect new mappings',
    (tester) async {
      final store = ContextMappingStore();
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
      addTearDown(store.dispose);
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborForwardingPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        const Offset(650, 600),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.byType(HarborContextMenu), findsOneWidget);
      expect(find.text('New mapping'), findsOneWidget);
      await tester.tap(find.text('New group…'));
      await tester.pumpAndSettle();
      final groupInput = find.descendant(
        of: find.byType(HarborAlert),
        matching: find.byType(EditableText),
      );
      await tester.enterText(groupInput, 'Empty');
      await tester.pump();
      await tester.tap(find.text('Create group'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(store.mappingGroupNames, ['Empty']);
      expect(find.byKey(const ValueKey('mapping-group:Empty')), findsOneWidget);
      expect(store.mappings, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('mapping-group:Empty')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename group…'));
      await tester.pumpAndSettle();
      await tester.enterText(groupInput, 'Renamed');
      await tester.tap(find.text('Save group'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(store.mappingGroupNames, ['Renamed']);
      await tester.tap(
        find.byKey(const ValueKey('mapping-group:Renamed')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New mapping'));
      await tester.pumpAndSettle();
      expect(find.text('Add port mapping'), findsOneWidget);
      final groupField = find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField && widget.placeholder == 'Ungrouped',
      );
      expect(
        tester.widget<HarborTextField>(groupField).controller!.text,
        'Renamed',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mapping menu edits, moves with keyboard, creates destination groups and removes groups safely',
    (tester) async {
      final store = ContextMappingStore();
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
      await store.addMapping(
        'lab',
        'D',
        '1080',
        group: 'Work',
        tags: ['proxy'],
      );
      await store.createMappingGroup('Destination');
      final mapping = store.mappings.single;
      final id = mapping.id;
      addTearDown(store.dispose);
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborForwardingPage()),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('mapping:$id'));
      await tester.tap(
        find.text('localhost:1080'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit mapping…'));
      await tester.pumpAndSettle();
      expect(find.text('Edit port mapping'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to group'));
      await tester.pumpAndSettle();
      final menu = find.byType(HarborContextMenu);
      await tester.tap(
        find.descendant(of: menu, matching: find.text('Destination')),
      );
      await tester.pumpAndSettle();
      expect(mapping.group, 'Destination');
      expect(mapping.id, id);
      expect(mapping.tags, ['proxy']);
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      // Reuse the sidebar menu's keyboard support to open the move submenu.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: menu, matching: find.text('Ungrouped')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: menu, matching: find.text('New group…')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(HarborAlert),
          matching: find.byType(EditableText),
        ),
        'New destination',
      );
      await tester.pump();
      await tester.tap(find.text('Create group'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(mapping.group, 'New destination');
      await tester.tap(
        find.byKey(const ValueKey('mapping-group:New destination')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove group…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove group'));
      await tester.pumpAndSettle();
      expect(mapping.group, isEmpty);
      expect(store.mappings.single.id, id);
      expect(store.mappingGroupNames, isNot(contains('New destination')));
      expect(tester.takeException(), isNull);
    },
  );
}
