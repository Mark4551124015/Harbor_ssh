import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class EmptyKeyLibrary extends KeyLibrary {
  @override
  Future<List<String>> listKeys() async => [];
}

class PendingKeyLibrary extends KeyLibrary {
  Completer<List<String>> pending = Completer<List<String>>();
  int loads = 0;
  @override
  Future<List<String>> listKeys() {
    loads++;
    return pending.future;
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Keys and forwarding header actions stay aligned during navigation, dark=$dark',
      (tester) async {
        final store = SSHStore(load: false);
        store.preferences = HarborPreferences(
          theme: dark ? ThemeMode.dark : ThemeMode.light,
        );
        var keys = true;
        late StateSetter update;
        await tester.binding.setSurfaceSize(const Size(660, 620));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ChangeNotifierProvider<SSHStore>.value(
            value: store,
            child: HarborApplication(
              home: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return HarborPageTransition(
                    child: keys
                        ? HarborKeysPage(
                            key: const ValueKey('keys'),
                            library: EmptyKeyLibrary(),
                          )
                        : const Padding(
                            key: ValueKey('mappings'),
                            padding: EdgeInsets.all(24),
                            child: HarborForwardingPage(),
                          ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Rect bounds(String label) =>
            tester.getRect(find.widgetWithText(HarborButton, label));
        final secondary = bounds('Import');
        final primary = bounds('Generate key');
        update(() => keys = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(bounds('Stop all'), secondary);
        expect(bounds('Add mapping'), primary);
        await tester.pumpAndSettle();
        expect(bounds('Stop all'), secondary);
        expect(bounds('Add mapping'), primary);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Import and Refresh keep their fill while key loading disables them',
    (tester) async {
      final library = PendingKeyLibrary();
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: SSHStore(load: false),
          child: MacosApp(home: HarborKeysPage(library: library)),
        ),
      );
      Color fill(String label) =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: find.widgetWithText(HarborButton, label),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      HarborButton button(String label) =>
          tester.widget<HarborButton>(find.widgetWithText(HarborButton, label));
      Color foreground(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: find.widgetWithText(HarborButton, label),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText && widget.text.toPlainText() == label,
              ),
            ),
          )
          .text
          .style!
          .color!;
      final loadingFill = {
        for (final label in ['Import', 'Refresh']) label: fill(label),
      };
      final loadingText = {
        for (final label in loadingFill.keys) label: foreground(label),
      };
      expect(button('Import').busy, isTrue);
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(library.loads, 1);
      library.pending.complete([]);
      await tester.pumpAndSettle();
      for (final label in loadingFill.keys) {
        expect(button(label).busy, isFalse);
        expect(fill(label), loadingFill[label]);
        expect(foreground(label), loadingText[label]);
      }
      library.pending = Completer<List<String>>();
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      for (final label in loadingFill.keys) {
        expect(button(label).busy, isTrue);
        expect(fill(label), loadingFill[label]);
        expect(foreground(label), loadingText[label]);
      }
      library.pending.complete([]);
      await tester.pumpAndSettle();
      for (final label in loadingFill.keys) {
        expect(fill(label), loadingFill[label]);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Key management renders at narrow width and opens generation form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(660, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = SSHStore(load: false);
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: MacosApp(home: HarborKeysPage(library: EmptyKeyLibrary())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No SSH keys yet'), findsOneWidget);
      await tester.tap(find.text('Generate key'));
      await tester.pumpAndSettle();
      expect(find.text('Generate SSH key'), findsOneWidget);
      expect(find.text('Passphrase (optional)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Generate SSH key'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Key library generates, imports and identifies key pairs without overwriting',
    () async {
      final root = await Directory.systemTemp.createTemp('harbor-key-test-');
      addTearDown(() => root.delete(recursive: true));
      final source = KeyLibrary(directory: Directory('${root.path}/source'));
      final target = KeyLibrary(directory: Directory('${root.path}/target'));
      final key = await source.generate(
        'test_ed25519',
        'ed25519',
        'test-passphrase',
      );
      expect(await File('$key.pub').exists(), isTrue);
      expect((await File(key).stat()).mode & 0x1ff, 0x180);
      expect(await source.fingerprint(key), contains('SHA256:'));
      expect(await source.keyType(key), 'Ed25519');
      await File('${source.directory.path}/config').writeAsString('Host test');
      await File(
        '${source.directory.path}/known_hosts',
      ).writeAsString('unrelated');
      expect(await source.listKeys(), [key]);
      final imported = await target.importKey(key);
      expect(await File(imported).readAsBytes(), await File(key).readAsBytes());
      expect(
        await File('$imported.pub').readAsString(),
        await File('$key.pub').readAsString(),
      );
      expect((await File(imported).stat()).mode & 0x1ff, 0x180);
      await expectLater(target.importKey(key), throwsFormatException);
      await expectLater(
        source.generate('test_ed25519', 'ed25519', ''),
        throwsFormatException,
      );
      await expectLater(
        source.generate('../escaped', 'ed25519', ''),
        throwsFormatException,
      );
      await expectLater(
        target.importKey('${source.directory.path}/config'),
        throwsFormatException,
      );
      expect(
        await File('${source.directory.path}/config').readAsString(),
        'Host test',
      );
      // Type remains available for an encrypted key with no companion public file.
      await File('$key.pub').delete();
      expect(await source.keyType(key), 'Ed25519');
      final rsa = await source.generate('neutral_filename', 'rsa', '');
      await File('$rsa.pub').delete();
      expect(await source.keyType(rsa), 'RSA');
      final malformed = File('${source.directory.path}/malformed');
      await malformed.writeAsString(
        '-----BEGIN OPENSSH PRIVATE KEY-----\ninvalid\n-----END OPENSSH PRIVATE KEY-----',
      );
      expect(await source.keyType(malformed.path), 'Unknown type');
      await File('${malformed.path}.pub').writeAsBytes([0xff, 0xfe]);
      expect(await source.keyType(malformed.path), 'Unknown type');
    },
  );
}
