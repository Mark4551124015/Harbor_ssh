import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';
import 'mapping_groups_test.dart' show MappingMemoryStore, MappingProcess;

Finder card(ManagedMapping rule) => find.byKey(ValueKey('mapping:${rule.id}'));
Finder header(String group) => find.byKey(ValueKey('mapping-group:$group'));

Future<void> mount(WidgetTester tester, SSHStore store) async {
  await tester.binding.setSurfaceSize(const Size(1040, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<SSHStore>.value(
      value: store,
      child: const HarborApplication(
        home: Padding(
          padding: EdgeInsets.all(20),
          child: HarborForwardingPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, ManagedMapping rule) async {
  await tester.tapAt(tester.getTopLeft(card(rule)) + const Offset(80, 26));
  await tester.pumpAndSettle();
}

Future<void> commandClick(WidgetTester tester, ManagedMapping rule) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await click(tester, rule);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('appkit_ui_element_colors'),
          (_) async => {'hueComponent': 0.6},
        );
  });

  test(
    'Batch reorder and move persist order, identity, tags and live connections',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'harbor-mapping-drag-',
      );
      final metadata = File('${directory.path}/metadata.json');
      final processes = <MappingProcess>[];
      final store = SSHStore(
        load: false,
        metadataFile: metadata,
        processStarter: (_, arguments) async {
          final process = MappingProcess();
          processes.add(process);
          process.output.add(utf8.encode('Entering interactive session.\n'));
          return process;
        },
      );
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      store.hosts.add(SSHHost(hostAlias: 'lab', hostName: 'lab.test'));
      for (final port in ['1101', '1102', '1103', '1104']) {
        await store.addMapping('lab', 'D', port, group: 'A', tags: ['db']);
      }
      final original = store.mappings.toList();
      expect(await store.startMappings([original.first]), isEmpty);
      await store.moveMappings([original[2], original[0]], 'B');
      expect(store.mappings.where((rule) => rule.group == 'B'), [
        original[0],
        original[2],
      ]);
      expect(store.mappingRunning(original.first), isTrue);
      expect(processes.single.completion.isCompleted, isFalse);
      expect(original.first.tags, ['db']);
      await store.moveMappings(
        [original[0], original[2]],
        'A',
        target: original[1],
        after: true,
      );
      expect(store.mappings, [
        original[1],
        original[0],
        original[2],
        original[3],
      ]);
      await store.moveMappings([original[0]], 'A', target: original[0]);
      expect(store.mappings, [
        original[1],
        original[0],
        original[2],
        original[3],
      ]);
      final reloaded = SSHStore(load: false, metadataFile: metadata);
      addTearDown(reloaded.dispose);
      await reloaded.loadMetadata();
      expect(
        reloaded.mappings.map((rule) => rule.id),
        store.mappings.map((rule) => rule.id),
      );
      expect(reloaded.mappingGroupNames, ['A', 'B']);
    },
  );

  testWidgets(
    'Cmd and Shift selection, selected Start/Stop all, blank deselection',
    (tester) async {
      final spawned = <MappingProcess>[];
      final directory = Directory.systemTemp.createTempSync(
        'harbor-selection-',
      );
      final store = SSHStore(
        load: false,
        metadataFile: File('${directory.path}/metadata.json'),
        processStarter: (_, arguments) async {
          final process = MappingProcess();
          spawned.add(process);
          process.output.add(utf8.encode('Entering interactive session.\n'));
          return process;
        },
      );
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      store.hosts.add(SSHHost(hostAlias: 'lab', hostName: 'lab.test'));
      store.mappings.addAll(
        List.generate(
          3,
          (i) => ManagedMapping(
            id: '$i',
            serverAlias: 'lab',
            type: 'D',
            value: '${2100 + i}',
            group: 'A',
          ),
        ),
      );
      await mount(tester, store);
      final rules = store.mappings.toList();
      await click(tester, rules[0]);
      await commandClick(tester, rules[2]);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Start all'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(store.mappingRunning(rules[0]), isTrue);
      expect(store.mappingRunning(rules[1]), isFalse);
      expect(store.mappingRunning(rules[2]), isTrue);
      expect(spawned, hasLength(2));
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Stop all'));
      await tester.pumpAndSettle();
      expect(rules.any(store.mappingRunning), isFalse);
      await click(tester, rules[0]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await click(tester, rules[2]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tapAt(const Offset(800, 900));
      await tester.pumpAndSettle();
      expect(find.text('All mappings'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Start all'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(rules.every(store.mappingRunning), isTrue);
      await click(tester, rules[1]);
      await tester.tap(find.text('Stop all'));
      await tester.pumpAndSettle();
      expect(store.mappingRunning(rules[1]), isFalse);
      expect(store.mappingRunning(rules[0]), isTrue);
      expect(store.mappingRunning(rules[2]), isTrue);
      await tester.tap(find.text('Start all'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(rules.every(store.mappingRunning), isTrue);
      expect(spawned, hasLength(6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Merged drag folds selected cards, highlights group and moves the batch',
    (tester) async {
      final store = MappingMemoryStore();
      addTearDown(store.dispose);
      for (final port in ['3100', '3101', '3102']) {
        await store.addMapping('lab', 'D', port, group: 'A');
      }
      await store.createMappingGroup('B');
      await mount(tester, store);
      final rules = store.mappings.toList();
      await click(tester, rules[0]);
      await commandClick(tester, rules[1]);
      final before = tester.getTopLeft(header('B')).dy;
      final drag = await tester.startGesture(
        tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 25));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.byKey(const ValueKey('mapping-drag-count')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.getTopLeft(header('B')).dy, lessThan(before - 50));
      await drag.moveTo(tester.getTopLeft(header('B')) + const Offset(90, 15));
      await tester.pump(const Duration(milliseconds: 180));
      final container = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: header('B'), matching: find.byType(AnimatedContainer))
            .first,
      );
      expect(
        (container.decoration as BoxDecoration).color,
        isNot(const Color(0x00000000)),
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(rules[0].group, 'B');
      expect(rules[1].group, 'B');
      expect(rules[2].group, 'A');
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('mapping-drag-count')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Insertion line reorders, Escape cancels a later drag', (
    tester,
  ) async {
    final store = MappingMemoryStore();
    addTearDown(store.dispose);
    for (final port in ['4100', '4101', '4102']) {
      await store.addMapping('lab', 'D', port, group: 'A');
    }
    await mount(tester, store);
    final rules = store.mappings.toList();
    var drag = await tester.startGesture(
      tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 25));
    await tester.pump();
    await drag.moveTo(
      tester.getBottomLeft(card(rules[2])) + const Offset(80, -12),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const ValueKey('mapping-insertion-line')),
      findsOneWidget,
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(store.mappings, [rules[1], rules[2], rules[0]]);
    drag = await tester.startGesture(
      tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(tester.getTopLeft(card(rules[1])) + const Offset(80, 12));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drag.up();
    await tester.pumpAndSettle();
    expect(store.mappings, [rules[1], rules[2], rules[0]]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Collapse animates and single selection backdrop slides between cards',
    (tester) async {
      final store = MappingMemoryStore();
      addTearDown(store.dispose);
      for (final port in ['5100', '5101']) {
        await store.addMapping('lab', 'D', port, group: 'A');
      }
      await store.createMappingGroup('B');
      await mount(tester, store);
      final rules = store.mappings.toList();
      await click(tester, rules[0]);
      final backdrop = find
          .byKey(const ValueKey('mapping-selection-backdrop'))
          .first;
      final from = tester.getTopLeft(backdrop).dy;
      await tester.tapAt(
        tester.getTopLeft(card(rules[1])) + const Offset(80, 26),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final middle = tester.getTopLeft(backdrop).dy;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(backdrop).dy;
      expect(middle, greaterThan(from));
      expect(middle, lessThan(end));
      final before = tester.getTopLeft(header('B')).dy;
      await tester.tapAt(tester.getTopLeft(header('A')) + const Offset(80, 15));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final during = tester.getTopLeft(header('B')).dy;
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(header('B')).dy;
      expect(during, lessThan(before));
      expect(during, greaterThan(after));
      expect(card(rules[0]).hitTestable(), findsNothing);
      expect(find.text('All mappings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Dropping on a collapsed group expands it; outside release cancels',
    (tester) async {
      final store = MappingMemoryStore();
      addTearDown(store.dispose);
      await store.addMapping('lab', 'D', '6100', group: 'A');
      await store.addMapping('lab', 'D', '6101', group: 'B');
      await mount(tester, store);
      final rules = store.mappings.toList();
      await tester.tapAt(tester.getTopLeft(header('B')) + const Offset(80, 15));
      await tester.pumpAndSettle();
      expect(card(rules[1]).hitTestable(), findsNothing);
      var drag = await tester.startGesture(
        tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 25));
      await tester.pump();
      await drag.moveTo(tester.getTopLeft(header('B')) + const Offset(80, 15));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(rules[0].group, 'B');
      expect(card(rules[1]).hitTestable(), findsOneWidget);
      final order = store.mappings.toList();
      drag = await tester.startGesture(
        tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 25));
      await tester.pump();
      await drag.moveTo(const Offset(2, 2));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(store.mappings, order);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Drag auto-scroll updates the drop under a stationary pointer', (
    tester,
  ) async {
    final store = MappingMemoryStore();
    addTearDown(store.dispose);
    for (var i = 0; i < 18; i++) {
      await store.addMapping('lab', 'D', '${7100 + i}', group: 'A');
    }
    await mount(tester, store);
    final first = store.mappings.first;
    final before = tester.getTopLeft(card(first)).dy;
    final drag = await tester.startGesture(
      tester.getTopLeft(card(first)) + const Offset(80, 26),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 25));
    await tester.pump();
    await drag.moveTo(const Offset(100, 915));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(HarborForwardingPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.pixels, greaterThan(300));
    expect(tester.getTopLeft(card(first)).dy, lessThan(before - 300));
    final cardsUnderPointer = store.mappings
        .where(
          (rule) =>
              rule != first &&
              tester.getRect(card(rule)).contains(const Offset(100, 915)),
        )
        .toList();
    expect(cardsUnderPointer, hasLength(1));
    final target = cardsUnderPointer.single;
    final after = 915 > tester.getCenter(card(target)).dy;
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      store.mappings.indexOf(first),
      store.mappings.indexOf(target) + (after ? 1 : -1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search focus and clicking outside the page clear selection', (
    tester,
  ) async {
    final store = MappingMemoryStore();
    addTearDown(store.dispose);
    await store.addMapping('lab', 'D', '8100', group: 'A');
    await mount(tester, store);
    await click(tester, store.mappings.first);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    expect(find.text('All mappings'), findsOneWidget);
    await click(tester, store.mappings.first);
    await tester.tapAt(const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(find.text('All mappings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Right-click new group keeps the entire selected batch across the dialog',
    (tester) async {
      final store = MappingMemoryStore();
      addTearDown(store.dispose);
      for (final port in ['9100', '9101', '9102']) {
        await store.addMapping('lab', 'D', port, group: 'A');
      }
      await mount(tester, store);
      final rules = store.mappings.toList();
      await click(tester, rules[0]);
      await commandClick(tester, rules[1]);
      await tester.tapAt(
        tester.getTopLeft(card(rules[0])) + const Offset(80, 26),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      // The third menu entry is Move to group, matching the sidebar keyboard behavior.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New group…').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(HarborAlert),
          matching: find.byType(EditableText),
        ),
        'Batch',
      );
      await tester.pump();
      await tester.tap(find.text('Create group'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(rules[0].group, 'Batch');
      expect(rules[1].group, 'Batch');
      expect(rules[2].group, 'A');
      expect(tester.takeException(), isNull);
    },
  );
}
