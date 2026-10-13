import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The test font has identical metrics at every weight. Use the real macOS
    // font when available so this regression catches weight-induced movement.
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (Platform.isMacOS && font.existsSync()) {
      final loader = FontLoader('.AppleSystemUIFont');
      loader.addFont(font.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  testWidgets(
    'Server header keeps its bounds while buttons gain and lose focus',
    (tester) async {
      final store = SSHStore(load: false);
      final host = SSHHost(
        hostAlias: 'demo',
        hostName: 'example.test',
        dynamicForward: '1080',
      );
      store.hosts.add(host);
      store.selectHost(host);
      store.markDirty(host.hostAlias);
      addTearDown(store.dispose);
      final oldStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = oldStrategy);
      await tester.binding.setSurfaceSize(const Size(960, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HostDetailTabs()),
        ),
      );
      await tester.pumpAndSettle();
      final terminal = find.widgetWithText(HarborButton, 'Open Terminal');
      final save = find.widgetWithText(HarborButton, 'Save');
      final anchors = [
        terminal,
        save,
        find.text('Save'),
        find.text('demo'),
        find.text('Overview'),
      ];
      final bounds = anchors.map(tester.getRect).toList();
      for (final button in [terminal, save, terminal]) {
        final content = find.descendant(
          of: button,
          matching: find.byType(AnimatedScale),
        );
        final focus = Focus.of(tester.element(content));
        focus.requestFocus();
        for (final duration in [
          Duration.zero,
          const Duration(milliseconds: 16),
          const Duration(milliseconds: 80),
          const Duration(milliseconds: 200),
        ]) {
          await tester.pump(duration);
          for (var i = 0; i < anchors.length; i++) {
            expect(
              tester.getRect(anchors[i]),
              bounds[i],
              reason: 'Header anchor $i moved at $duration',
            );
          }
        }
        expect(focus.hasFocus, isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'Tab selection slides without shifting labels, reducedMotion=$reducedMotion',
      (tester) async {
        final store = SSHStore(load: false);
        addTearDown(store.dispose);
        store.preferences = store.preferences.copyWith(
          reduceMotion: reducedMotion,
        );
        var selected = 0;
        await tester.pumpWidget(
          ChangeNotifierProvider<SSHStore>.value(
            value: store,
            child: HarborApplication(
              home: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: SizedBox(
                    width: 600,
                    child: HarborSlidingTabs(
                      labels: const [
                        'Overview',
                        'General',
                        'Connection',
                        'Advanced',
                        'Port mapping',
                      ],
                      selectedIndex: selected,
                      onSelected: (value) => setState(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final indicator = find.byKey(const ValueKey('host-tab-selection'));
        final start = tester.getRect(indicator);
        final target = tester.getRect(find.byKey(const ValueKey('host-tab:3')));
        final anchors = List.generate(
          5,
          (index) => tester.getRect(find.byKey(ValueKey('host-tab:$index'))),
        );
        await tester.tap(find.byKey(const ValueKey('host-tab:3')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(indicator, findsOneWidget);
        final middle = tester.getRect(indicator);
        if (reducedMotion) {
          expect(middle, target);
        } else {
          expect(middle.left, greaterThan(start.left));
          expect(middle.left, lessThan(target.left));
        }
        for (var index = 0; index < anchors.length; index++) {
          expect(
            tester.getRect(find.byKey(ValueKey('host-tab:$index'))),
            anchors[index],
          );
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(indicator), target);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final size in [const Size(960, 680), const Size(1200, 800)]) {
    testWidgets(
      'Server tab geometry stays fixed through hover and selection at $size',
      (tester) async {
        final store = SSHStore(load: false);
        final host = SSHHost(hostAlias: 'demo', hostName: 'example.test');
        store.hosts.add(host);
        store.selectHost(host);
        addTearDown(store.dispose);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ChangeNotifierProvider<SSHStore>.value(
            value: store,
            child: const HarborApplication(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('demo').first);
        await tester.pumpAndSettle();
        final tabs = [
          for (var i = 0; i < 5; i++) find.byKey(ValueKey('host-tab:$i')),
        ];
        final anchors = <Finder>[
          for (final tab in tabs) ...[
            tab,
            find.descendant(of: tab, matching: find.byType(Text)),
          ],
          find.widgetWithText(HarborButton, 'Open Terminal'),
          find.widgetWithText(HarborButton, 'Saved'),
        ];
        final bounds = anchors.map(tester.getRect).toList();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        for (final index in [1, 2, 3, 4, 0, 4, 2]) {
          await mouse.moveTo(tester.getCenter(tabs[index]));
          await tester.pumpAndSettle();
          await tester.tap(tabs[index]);
          for (final duration in [
            Duration.zero,
            const Duration(milliseconds: 16),
            const Duration(milliseconds: 80),
            const Duration(milliseconds: 300),
          ]) {
            await tester.pump(duration);
            for (var i = 0; i < anchors.length; i++) {
              expect(
                tester.getRect(anchors[i]),
                bounds[i],
                reason: 'Tab $index moved anchor $i at $duration',
              );
            }
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
