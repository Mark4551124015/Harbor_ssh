// Generate documentation screenshots using fictional hosts only.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class PreviewStore extends SSHStore {
  PreviewStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() {
  testWidgets('Render README previews with fictional hosts', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (_) async => {'hueComponent': 0.5},
    );
    await tester.runAsync(() async {
      final bytes = await File(
        '/System/Library/Fonts/Supplemental/Arial.ttf',
      ).readAsBytes();
      for (final family in [
        'PreviewSans',
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    await tester.runAsync(() async {
      final icons = await rootBundle.load(
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      );
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(icons))).load();
      final mono = await File(
        '/System/Library/Fonts/SFNSMono.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Menlo',
      )..addFont(Future.value(ByteData.sublistView(mono)))).load();
    });
    await tester.binding.setSurfaceSize(const Size(1040, 720));
    final store = PreviewStore();
    store.hosts = [
      SSHHost(
        hostAlias: 'edge-gateway',
        hostName: 'edge.example.com',
        user: 'deploy',
      ),
      SSHHost(
        hostAlias: 'api-production',
        hostName: 'api.example.com',
        user: 'deploy',
      ),
      SSHHost(hostAlias: 'database', hostName: 'db.example.com', user: 'ops'),
      SSHHost(
        hostAlias: 'design-lab',
        hostName: 'lab.example.com',
        user: 'developer',
      ),
    ];
    store.hostGroups.addAll({
      'edge-gateway': 'Production',
      'api-production': 'Production',
      'database': 'Production',
      'design-lab': 'Development',
    });
    store.favorites.addAll(['edge-gateway', 'design-lab']);
    store.recentHosts.addAll(['api-production', 'design-lab']);
    store.search('');
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider<SSHStore>.value(
        value: store,
        child: RepaintBoundary(key: boundary, child: const HarborApplication()),
      ),
    );
    for (final dark in [true, false]) {
      await store.updatePreferences(
        store.preferences.copyWith(
          theme: dark ? ThemeMode.dark : ThemeMode.light,
        ),
      );
      if (!dark) await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      InlineSpan readable(InlineSpan span) {
        if (span is! TextSpan) return span;
        final family = span.style?.fontFamily ?? '';
        return TextSpan(
          text: span.text,
          style: family.contains('Icons')
              ? span.style
              : (span.style ?? const TextStyle()).copyWith(
                  fontFamily: family == 'Menlo' ? 'Menlo' : 'PreviewSans',
                ),
          children: span.children?.map(readable).toList(),
        );
      }

      void visit(RenderObject node) {
        if (node is RenderParagraph) node.text = readable(node.text);
        node.visitChildren(visit);
      }

      visit(render);
      await tester.pump();

      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/images/${dark ? 'workbench-dark' : 'settings-light'}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.binding.setSurfaceSize(null);
  });
}
