import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('appkit_ui_element_colors'),
          (_) async => {'hueComponent': 0.6},
        );
  });
  testWidgets(
    'Server settings edit SSH config without independent tunnel controls',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'harbor-forward-ui-',
      );
      final config = File('${directory.path}/config');
      config.writeAsStringSync(
        'Host demo\n  HostName example.test\n  LocalForward 8080 localhost:80\n  DynamicForward 1080\n',
      );
      final store = SSHStore(
        load: false,
        configFile: config,
        metadataFile: File('${directory.path}/metadata.json'),
      );
      await tester.runAsync(store.loadConfig);
      store.selectHost(store.hosts.single);
      await tester.runAsync(
        () => store.addMapping('demo', 'L', '9090:localhost:90'),
      );
      await tester.runAsync(() => store.addMapping('other', 'D', '9999'));
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(home: HostDetailTabs(initialTab: 4)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Local · 8080:localhost:80'), findsOneWidget);
      expect(find.text('SOCKS5 · 1080'), findsOneWidget);
      expect(find.textContaining('demo · Local forward'), findsNothing);
      expect(find.text('Start'), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Start tunnels'), findsNothing);
      expect(find.byType(HarborForwardingPage), findsNothing);
      expect(find.textContaining('other · SOCKS5'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(HarborConfigForwards),
                matching: find.byIcon(CupertinoIcons.trash),
              )
              .first,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.hosts.single.dynamicForward, isEmpty);
      expect(
        await tester.runAsync(config.readAsString),
        isNot(contains('DynamicForward')),
      );
      expect(
        await tester.runAsync(config.readAsString),
        contains('LocalForward 8080 localhost:80'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Command F searches connections after a server text field receives focus',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'harbor-search-ui-',
      );
      final store = SSHStore(
        load: false,
        metadataFile: File('${directory.path}/metadata.json'),
      );
      final host = SSHHost(hostAlias: 'demo', hostName: 'example.test');
      store.hosts.add(host);
      store.selectHost(host);
      addTearDown(() async {
        store.dispose();
        await directory.delete(recursive: true);
      });
      await tester.binding.setSurfaceSize(const Size(1040, 720));
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
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EditableText).first);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      final search = tester.widget<HarborTextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is HarborTextField &&
              widget.placeholder == 'Find a connection…',
        ),
      );
      expect(search.focusNode!.hasFocus, isTrue);
      expect(find.byType(HarborSettingsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
