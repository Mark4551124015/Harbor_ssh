import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

class CountingKeyLibrary extends KeyLibrary {
  int loads = 0;
  @override
  Future<List<String>> listKeys() async {
    loads++;
    return [];
  }
}

void main() {
  testWidgets(
    'Group collapse and expansion preserve rows and use equal timing',
    (tester) async {
      var collapsed = false;
      late StateSetter update;
      final hosts = [SSHHost(hostAlias: 'one'), SSHHost(hostAlias: 'two')];
      await tester.pumpWidget(
        MacosApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 240,
                  child: HarborAnimatedHosts(
                    hosts: hosts,
                    collapsed: collapsed,
                    itemBuilder: (host) => Text(host.hostAlias),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(HarborAnimatedHosts);
      final first = tester.element(find.text('one'));
      expect(tester.getSize(list).height, 112);
      update(() => collapsed = true);
      await tester.pump();
      expect(tester.element(find.text('one')), same(first));
      await tester.pump(const Duration(milliseconds: 140));
      final closingHeight = tester.getSize(list).height;
      expect(closingHeight, inExclusiveRange(20, 90));
      expect(find.text('one'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('one'), findsNothing);
      expect(tester.getSize(list).height, 0);
      update(() => collapsed = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.getSize(list).height + closingHeight, closeTo(112, 0.1));
      expect(tester.element(find.text('one')), same(first));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).height, 112);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Quick Connect smoothly sharpens and shrinks without overshoot', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MacosApp(
        home: HarborQuickConnectTransition(
          animation: controller,
          child: const Center(
            child: SizedBox(
              width: 420,
              height: 300,
              child: Text('Quick Connect'),
            ),
          ),
        ),
      ),
    );
    final transition = find.byType(HarborQuickConnectTransition);
    final content = tester.element(find.text('Quick Connect'));
    double scale() => tester
        .widgetList<Transform>(
          find.descendant(of: transition, matching: find.byType(Transform)),
        )
        .last
        .transform
        .entry(0, 0);
    ImageFiltered filter() => tester.widget<ImageFiltered>(
      find.descendant(of: transition, matching: find.byType(ImageFiltered)),
    );
    expect(scale(), closeTo(1.08, 0.001));
    expect(filter().enabled, isTrue);
    controller.forward();
    await tester.pump();
    var previous = scale();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(scale(), inInclusiveRange(1.0, previous));
      expect(tester.element(find.text('Quick Connect')), same(content));
      previous = scale();
    }
    expect(scale(), closeTo(1, 0.001));
    expect(filter().enabled, isFalse);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), inExclusiveRange(1, 1.08));
    expect(filter().enabled, isTrue);
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1.08, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Rapid navigation never flashes a partially visible page to opaque',
    (tester) async {
      var page = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MacosApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return HarborPageTransition(
                child: SizedBox.expand(
                  key: ValueKey(page),
                  child: Text('View $page'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => page = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      double opacity(int page) => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(ValueKey(page)),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      final before = opacity(1);
      expect(before, inExclusiveRange(0, 1));
      update(() => page = 2);
      await tester.pump();
      expect(opacity(1), closeTo(before, 0.001));
      await tester.pump(const Duration(milliseconds: 30));
      expect(opacity(1), closeTo(before, 0.001));
      await tester.pumpAndSettle();
      expect(find.text('View 0'), findsNothing);
      expect(find.text('View 1'), findsNothing);
      expect(find.text('View 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Interrupted page fades retain their backing canvas until the latest completes',
    (tester) async {
      var page = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MacosApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return HarborPageTransition(
                child: SizedBox.expand(
                  key: ValueKey(page),
                  child: Text('Canvas $page'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = tester.element(find.text('Canvas 0'));
      update(() => page = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      update(() => page = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // More than the first transition's duration has elapsed. Its backing page
      // must still exist while the newest canvas is partly transparent.
      expect(tester.element(find.text('Canvas 0')), same(original));
      expect(find.text('Canvas 1'), findsOneWidget);
      update(() => page = 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.element(find.text('Canvas 0')), same(original));
      await tester.pumpAndSettle();
      expect(find.text('Canvas 0'), findsNothing);
      expect(find.text('Canvas 1'), findsNothing);
      expect(find.text('Canvas 2'), findsNothing);
      expect(find.text('Canvas 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Navigation text and icon interpolate together and quick reversal preserves color',
    (tester) async {
      var selected = false;
      late StateSetter update;
      await tester.pumpWidget(
        MacosApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 220,
                  child: HarborNavItem(
                    icon: CupertinoIcons.waveform_path,
                    label: 'Activity',
                    selected: selected,
                    onTap: () {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final nav = find.byType(HarborNavItem);
      Color? textColor() =>
          tester.widget<Text>(find.text('Activity')).style!.color;
      Color? iconColor() => tester
          .widget<Icon>(find.descendant(of: nav, matching: find.byType(Icon)))
          .color;
      final before = textColor();
      update(() => selected = true);
      await tester.pump();
      expect(textColor(), before);
      await tester.pump(const Duration(milliseconds: 70));
      final midway = textColor();
      expect(midway, isNot(before));
      expect(iconColor(), midway);
      update(() => selected = false);
      await tester.pump();
      expect(textColor(), midway);
      await tester.pumpAndSettle();
      expect(textColor(), before);
      expect(
        tester
            .widget<CupertinoButton>(
              find.descendant(of: nav, matching: find.byType(CupertinoButton)),
            )
            .pressedOpacity,
        1,
      );
    },
  );

  testWidgets(
    'Sidebar selection slides within a group and reverses from its current position',
    (tester) async {
      double? target = 0;
      late StateSetter update;
      const backdrop = ValueKey('test-backdrop');
      await tester.pumpWidget(
        MacosApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HarborSelectionSlide(
                  selectedOffset: target,
                  height: 37,
                  color: const Color(0x227799AA),
                  backdropKey: backdrop,
                  children: const [SizedBox(width: 200, height: 200)],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byKey(backdrop)).dy;
      update(() => target = 129);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(backdrop)).dy, origin);
      await tester.pump(const Duration(milliseconds: 70));
      final midway = tester.getTopLeft(find.byKey(backdrop)).dy;
      expect(midway - origin, inExclusiveRange(0, 129));
      update(() => target = 43);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(backdrop)).dy,
        closeTo(midway, 0.001),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(backdrop)).dy - origin,
        closeTo(43, 0.01),
      );
    },
  );

  testWidgets(
    'Cross-group selection fades in place without sliding across unrelated rows',
    (tester) async {
      double? target = 0;
      late StateSetter update;
      const backdrop = ValueKey('test-cross-group-backdrop');
      await tester.pumpWidget(
        MacosApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HarborSelectionSlide(
                  selectedOffset: target,
                  height: 37,
                  color: const Color(0x227799AA),
                  backdropKey: backdrop,
                  children: const [SizedBox(width: 200, height: 200)],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double opacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(backdrop),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      final origin = tester.getTopLeft(find.byKey(backdrop)).dy;
      update(() => target = null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getTopLeft(find.byKey(backdrop)).dy, origin);
      expect(opacity(), inExclusiveRange(0, 1));
      // Return to another row before fade-out completes: retain a fading remnant
      // at the old location, and start the new selection transparent at its target.
      update(() => target = 129);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(backdrop)).dy - origin, 129);
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getTopLeft(find.byKey(backdrop)).dy - origin, 129);
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Leaving Keys preserves state and button states through the fade',
    (tester) async {
      final library = CountingKeyLibrary();
      var page = 0;
      late StateSetter update;
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: SSHStore(load: false),
          child: MacosApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HarborPageTransition(
                  child: page == 0
                      ? HarborKeysPage(
                          key: const ValueKey('keys'),
                          library: library,
                        )
                      : const HarborForwardingPage(key: ValueKey('mapping')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(library.loads, 1);
      final keysState = tester.state(find.byType(HarborKeysPage));
      final importElement = tester.element(
        find.widgetWithText(HarborButton, 'Import'),
      );
      update(() => page = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.state(find.byType(HarborKeysPage)), same(keysState));
      expect(
        tester.element(find.widgetWithText(HarborButton, 'Import')),
        same(importElement),
      );
      expect(library.loads, 1);
      final oldFade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(HarborKeysPage),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(
        oldFade.opacity.value,
        1,
      ); // No opacity dip in the shared page canvas.
      final stopAll = tester.widget<HarborButton>(
        find.widgetWithText(HarborButton, 'Stop all'),
      );
      expect(stopAll.onPressed, isNull);
      final incoming = find.ancestor(
        of: find.byType(HarborForwardingPage),
        matching: find.byType(IgnorePointer),
      );
      expect(tester.widget<IgnorePointer>(incoming.first).ignoring, isTrue);
      await tester.pumpAndSettle();
      expect(library.loads, 1);
      expect(find.byType(HarborKeysPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'Page changes keep geometry and disable outgoing input, reduced=$reduceMotion',
      (tester) async {
        var page = 0;
        var outgoingTaps = 0;
        late StateSetter update;
        await tester.pumpWidget(
          MacosApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SizedBox.expand(
                    child: HarborPageTransition(
                      child: Align(
                        key: ValueKey(page),
                        alignment: Alignment.topLeft,
                        child: GestureDetector(
                          onTap: () => outgoingTaps++,
                          child: SizedBox(
                            width: 100,
                            height: 40,
                            child: Text('Page $page'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(find.text('Page 0'));
        update(() => page = 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.getTopLeft(find.text('Page 1')), origin);
        if (!reduceMotion) {
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey(1)),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(fade.opacity.value, inExclusiveRange(0, 1));
          final outgoing = find.ancestor(
            of: find.byKey(const ValueKey(0)),
            matching: find.byType(IgnorePointer),
          );
          expect(outgoing, findsWidgets);
          expect(tester.widget<IgnorePointer>(outgoing.first).ignoring, isTrue);
        } else {
          expect(find.text('Page 0'), findsNothing);
        }
        await tester.pumpAndSettle();
        expect(find.text('Page 0'), findsNothing);
        expect(outgoingTaps, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
