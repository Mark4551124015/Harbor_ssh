import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:macos_ssh_tool/main.dart';

class SettingsMemoryStore extends SSHStore {
  SettingsMemoryStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() {
  testWidgets(
    'Settings search finds full rows across categories and highlights matches',
    (tester) async {
      final store = SettingsMemoryStore();
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connections').first);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is HarborTextField &&
              widget.placeholder == 'Search settings…',
        ),
        matching: find.byType(EditableText),
      );
      Future<void> searchFor(String query) async {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
      }

      await searchFor('theme');
      expect(find.text('Theme'), findsOneWidget);
      expect(find.byKey(const ValueKey('setting-match-Theme')), findsOneWidget);
      expect(find.text('Connection timeout'), findsNothing);
      final theme = tester.widget<Text>(find.text('Theme'));
      expect(
        (theme.textSpan! as TextSpan).children!.whereType<TextSpan>().any(
          (span) => span.style?.backgroundColor != null,
        ),
        isTrue,
      );
      await searchFor('keep alive');
      expect(
        find.byKey(const ValueKey('setting-match-Keep-alive interval')),
        findsOneWidget,
      );
      await searchFor('终端');
      expect(
        find.byKey(const ValueKey('setting-match-Open connections in')),
        findsOneWidget,
      );
      await searchFor('server addresses');
      expect(
        find.byKey(const ValueKey('setting-match-Show server addresses')),
        findsOneWidget,
      );
      await searchFor('nothing-matches-this');
      expect(find.text('No matching settings'), findsOneWidget);
      await searchFor('');
      expect(find.text('Make Harbor yours'), findsOneWidget);
      expect(find.byKey(const ValueKey('setting-match-Theme')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Window shortcuts work after settings search takes focus', (
    tester,
  ) async {
    final store = SettingsMemoryStore();
    await tester.binding.setSurfaceSize(const Size(1040, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const HarborApplication(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> command(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    // Command-F can arrive before the settings page has built or finished fading.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(HarborSettingsPage), findsOneWidget);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is HarborTextField && widget.placeholder == 'Search settings…',
    );
    expect(tester.widget<HarborTextField>(search).focusNode!.hasFocus, isTrue);
    await tester.tap(search);
    await tester.pumpAndSettle();
    await command(LogicalKeyboardKey.keyK);
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await command(LogicalKeyboardKey.keyF);
    expect(find.byType(QuickConnectSheet), findsNothing);
    final settingsSearch = tester.widget<HarborTextField>(search);
    expect(settingsSearch.focusNode!.hasFocus, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'Find a connection…',
      ),
      findsNothing,
    );
    await tester.enterText(
      find.descendant(of: search, matching: find.byType(EditableText)),
      'theme',
    );
    await command(LogicalKeyboardKey.keyF);
    expect(
      settingsSearch.controller!.selection.textInside(
        settingsSearch.controller!.text,
      ),
      'theme',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HarborSettingsPage), findsNothing);
    await command(LogicalKeyboardKey.keyF);
    final sidebarSearch = tester.widget<HarborTextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'Find a connection…',
      ),
    );
    expect(sidebarSearch.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(sidebarSearch.focusNode!.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sidebarSearch.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await command(LogicalKeyboardKey.keyN);
    expect(store.hosts, hasLength(1));
  });

  testWidgets('Native menu commands work and Escape returns from settings', (
    tester,
  ) async {
    final store = SettingsMemoryStore();
    await tester.binding.setSurfaceSize(const Size(1040, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: const HarborApplication(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> nativeCommand(String command) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'harbor/commands',
        const StandardMethodCodec().encodeMethodCall(MethodCall(command)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Port mappings'));
    await tester.pumpAndSettle();
    await nativeCommand('search');
    final mappingSearch = tester.widget<HarborTextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'Find a connection…',
      ),
    );
    expect(mappingSearch.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await nativeCommand('settings');
    expect(find.byType(HarborSettingsPage), findsOneWidget);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is HarborTextField && widget.placeholder == 'Search settings…',
    );
    await nativeCommand('search');
    expect(tester.widget<HarborTextField>(search).focusNode!.hasFocus, isTrue);
    expect(mappingSearch.focusNode!.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HarborSettingsPage), findsNothing);
    expect(find.text('Port forwarding'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Port forwarding'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await nativeCommand('quickConnect');
    expect(find.byType(QuickConnectSheet), findsNothing);
    await nativeCommand('quickConnect');
    expect(find.byType(QuickConnectSheet), findsOneWidget);
    await nativeCommand('newConnection');
    expect(store.hosts, isEmpty); // Modal owns commands until dismissed.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickConnectSheet), findsNothing);
    await nativeCommand('newConnection');
    expect(store.hosts, hasLength(1));
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Settings search focus preserves layout in $theme', (
      tester,
    ) async {
      final store = SettingsMemoryStore();
      await store.updatePreferences(HarborPreferences(theme: theme));
      await tester.binding.setSurfaceSize(const Size(720, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.placeholder == 'Search settings…',
      );
      final anchors = [
        search,
        find.text('Settings'),
        find.text('All').first,
        find.text('Make Harbor yours'),
      ];
      final bounds = anchors.map(tester.getRect).toList();
      await tester.tap(search);
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
            reason: 'Search focus must preserve anchor $i at $duration',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Settings categories crossfade while segmented text stays stable',
    (tester) async {
      final store = SettingsMemoryStore();
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HarborSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance').first);
      await tester.pumpAndSettle();
      final controlFinder = find.byType(
        CupertinoSlidingSegmentedControl<ThemeMode>,
      );
      final controlElement = tester.element(controlFinder);
      Color labelColor(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: controlFinder,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText && widget.text.toPlainText() == label,
              ),
            ),
          )
          .text
          .style!
          .color!;
      final before = labelColor('Dark');
      await tester.tap(find.text('Dark'));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.element(controlFinder), same(controlElement));
      expect(store.preferences.theme, ThemeMode.dark);
      final during = labelColor('Dark');
      await tester.pumpAndSettle();
      expect(labelColor('Dark'), during);
      expect(
        before,
        isNot(during),
      ); // Theme changed, selection itself adds no color flash.
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(store.preferences.theme, ThemeMode.light);
      final titleOrigin = tester.getTopLeft(find.text('Settings'));
      await tester.tap(find.text('Connections').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Make Harbor yours'), findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
        find.byType(FadeTransition),
      );
      expect(
        fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      expect(tester.getTopLeft(find.text('Settings')), titleOrigin);
      await tester.pumpAndSettle();
      expect(find.text('Make Harbor yours'), findsNothing);
      expect(find.text('Open connections in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Preferences survive restart without modifying SSH config or mappings',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-settings-');
      addTearDown(() => dir.delete(recursive: true));
      final metadata = File('${dir.path}/library.json');
      final config = File('${dir.path}/config');
      await config.writeAsString('Host lab\n  HostName lab.test\n');
      final store = SSHStore(
        load: false,
        metadataFile: metadata,
        configFile: config,
      );
      await store.addMapping('lab', 'D', '1080');
      store.recentHosts.add('lab');
      await store.updatePreferences(
        const HarborPreferences(
          theme: ThemeMode.dark,
          accent: 'Teal',
          terminal: 'iterm',
          reduceMotion: true,
          startPage: 'mappings',
          recordRecent: false,
          keepAlive: 60,
        ),
      );
      await store.clearRecentHosts();
      final restored = SSHStore(load: false, metadataFile: metadata);
      await restored.loadMetadata();
      expect(restored.preferences.theme, ThemeMode.dark);
      expect(restored.preferences.accent, 'Teal');
      expect(restored.preferences.reduceMotion, isTrue);
      expect(restored.preferences.startPage, 'mappings');
      expect(restored.terminalOpenArguments('/tmp/connect.command'), [
        '-a',
        'iTerm',
        '/tmp/connect.command',
      ]);
      restored.recordRecentHost(
        SSHHost(hostAlias: 'lab', hostName: 'lab.test'),
      );
      expect(restored.recentHosts, isEmpty);
      expect(restored.mappings.single.value, '1080');
      expect(await config.readAsString(), 'Host lab\n  HostName lab.test\n');
    },
  );

  test(
    'Unknown preferences fall back and numeric JSON values remain readable',
    () {
      final prefs = HarborPreferences.fromJson({
        'accent': 'unknown',
        'theme': 'invalid',
        'terminal': false,
        'connectTimeout': 15.0,
        'keepAlive': 60.0,
      });
      expect(prefs.theme, ThemeMode.system);
      expect(prefs.accent, 'Copper');
      expect(prefs.terminal, 'system');
      expect(prefs.connectTimeout, 15);
      expect(prefs.keepAlive, 60);
    },
  );

  testWidgets(
    'Footer opens settings and appearance updates at minimum window size',
    (tester) async {
      final store = SettingsMemoryStore();
      await tester.binding.setSurfaceSize(const Size(960, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LOCAL WORKSPACE'), findsNothing);
      expect(find.text('v${store.applicationVersion}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(HarborSettingsPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accent-Teal')));
      await tester.pumpAndSettle();
      expect(store.preferences.accent, 'Teal');
      await tester.runAsync(
        () => store.updatePreferences(
          store.preferences.copyWith(reduceMotion: true, theme: ThemeMode.dark),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HarborSettingsPage));
      expect(MediaQuery.of(context).disableAnimations, isTrue);
      expect(MacosTheme.of(context).brightness, Brightness.dark);
      final segment = tester
          .widget<CupertinoSlidingSegmentedControl<ThemeMode>>(
            find.byType(CupertinoSlidingSegmentedControl<ThemeMode>).first,
          );
      final selected = tester.widget<RichText>(
        find.descendant(
          of: find.byType(CupertinoSlidingSegmentedControl<ThemeMode>),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == 'Dark',
          ),
        ),
      );
      final foreground = selected.text.style!.color!;
      final background = segment.thumbColor;
      final contrast =
          (foreground.computeLuminance() + 0.05) /
          (background.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      expect(CupertinoTheme.of(context).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
