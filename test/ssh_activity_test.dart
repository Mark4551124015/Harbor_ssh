import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:provider/provider.dart';

void main() {
  const processes = '''
  10 1 01:20 /Applications/iTerm.app/Contents/MacOS/iTerm2
  11 10 01:19 /bin/zsh
  12 11 00:30 /usr/bin/ssh
  13 1 02:00 /usr/bin/ssh-agent
  14 1 01:00 /usr/sbin/sshd
  15 1 00:20 ssh
  16 1 00:10 /Applications/Harbor.app/Contents/MacOS/Harbor
  17 16 00:05 ssh
''';
  const sockets = '''
p12
cssh
f4
n10.0.0.2:50000->198.51.100.1:2222
TST=ESTABLISHED
f5
n10.0.0.2:50000->198.51.100.1:2222
TST=ESTABLISHED
f6
n127.0.0.1:1080
TST=LISTEN
p15
f4
n[::1]:50001->[2001:db8::1]:22
TST=SYN_SENT
p17
f4
n[::1]:50002->[2001:db8::2]:22
TST=ESTABLISHED
''';
  test(
    'SSH discovery excludes agents and daemons, follows terminal ancestry',
    () {
      final entries = SSHActivityMonitor.parse(processes, sockets);
      expect(entries.map((e) => e.pid), [12, 15, 17]);
      expect(entries.map((e) => e.source), ['iTerm', 'External', 'Harbor']);
      expect(entries.first.elapsed, '00:30');
    },
  );
  test(
    'TCP records deduplicate descriptors and separate listeners and connecting sockets',
    () {
      final entries = SSHActivityMonitor.parse(processes, sockets);
      expect(entries.first.endpoints, ['198.51.100.1:2222']);
      expect(entries.first.listeners, ['127.0.0.1:1080']);
      expect(entries[1].connected, isFalse);
      expect(entries[1].status, 'No TCP observed');
      expect(entries.last.endpoints, ['[2001:db8::2]:22']);
    },
  );
  test('Missing socket data and cyclic parent chains remain safe', () {
    final entries = SSHActivityMonitor.parse(
      '1 2 00:01 ssh\n2 1 00:01 zsh\nmalformed',
      'p1\nf2\nTST=ESTABLISHED',
    );
    expect(entries.single.source, 'External');
    expect(entries.single.connected, isFalse);
    expect(SSHActivityMonitor.parse('', ''), isEmpty);
  });
  test(
    'Port probe makes three actual TCP connections and closes sockets',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var connections = 0;
      final subscription = server.listen((socket) {
        connections++;
        socket.destroy();
      });
      try {
        final samples = await SSHPortProbe.measure('127.0.0.1:${server.port}');
        expect(samples, hasLength(3));
        expect(samples.every((value) => value >= 0), isTrue);
        // Server acceptance can trail completion of the client handshake.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connections, 3);
      } finally {
        await subscription.cancel();
        await server.close();
      }
    },
  );
  test('Port probe rejects invalid endpoints', () async {
    await expectLater(SSHPortProbe.measure('invalid'), throwsFormatException);
    await expectLater(
      SSHPortProbe.measure('127.0.0.1:0'),
      throwsFormatException,
    );
  });

  for (final dark in [false, true]) {
    testWidgets(
      'Activity updates preserve homepage layout and open details ($dark)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(960, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final monitor = SSHActivityMonitor();
        final store = SSHStore(load: false);
        addTearDown(monitor.dispose);
        addTearDown(store.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<SSHStore>.value(
            value: store,
            child: MacosApp(
              theme: MacosThemeData.light(),
              darkTheme: MacosThemeData.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: HarborWorkbench(
                onSelect: (_) {},
                monitor: monitor,
                onViewActivity: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final section = find.byType(HarborActivityList);
        final before = tester.getRect(section);
        monitor.entries = SSHActivityMonitor.parse(processes, sockets);
        monitor.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.getRect(section), before);
        expect(find.text('ACTIVE SSH'), findsOneWidget);
        await tester.ensureVisible(find.text('198.51.100.1:2222'));
        await tester.tap(find.text('198.51.100.1:2222'));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Test port latency'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Quick Connect closing fades across the full animation with a curve',
    (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 320),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HarborQuickConnectTransition(
            animation: controller,
            child: const SizedBox(width: 200, height: 100),
          ),
        ),
      );
      controller.forward();
      await tester.pumpAndSettle();
      controller.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final quarter = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(quarter, lessThan(1));
      expect(quarter, greaterThan(0.75));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        inInclusiveRange(0.45, 0.55),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    },
  );
}
