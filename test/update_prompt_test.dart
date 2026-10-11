import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class PromptStore extends SSHStore {
  PromptStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

final newer = HarborUpdate(
  'beta-1.0.2',
  4,
  Uri(scheme: 'https', host: 'github.com', path: '/update.zip'),
  Uri(scheme: 'https', host: 'github.com', path: '/SHA256SUMS.txt'),
);

void main() {
  test(
    'Ignored update persists, skipping only applies to this session',
    () async {
      final directory = await Directory.systemTemp.createTemp('harbor-ignore-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/metadata.json');
      final store = SSHStore(load: false, metadataFile: file);
      store.pendingUpdatePrompt = 4;
      expect(store.shouldPromptForUpdate, isTrue);
      store.skipUpdatePrompt();
      store.pendingUpdatePrompt = 4;
      expect(store.shouldPromptForUpdate, isFalse);
      final nextLaunch = SSHStore(load: false, metadataFile: file);
      nextLaunch.pendingUpdatePrompt = 4;
      expect(nextLaunch.shouldPromptForUpdate, isTrue);
      await nextLaunch.ignoreUpdatePrompt();
      final restored = SSHStore(load: false, metadataFile: file);
      await restored.loadMetadata();
      restored.pendingUpdatePrompt = 4;
      expect(restored.shouldPromptForUpdate, isFalse);
      restored.pendingUpdatePrompt = 5;
      expect(restored.shouldPromptForUpdate, isTrue);
    },
  );
  for (final choice in ['跳过本次更新', '忽略']) {
    testWidgets('Startup update prompt supports $choice without repeating', (
      tester,
    ) async {
      final store = PromptStore()
        ..availableUpdate = newer
        ..pendingUpdatePrompt = 4;
      await tester.binding.setSurfaceSize(const Size(1040, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<SSHStore>.value(
          value: store,
          child: const HarborApplication(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('跳过本次更新'), findsOneWidget);
      expect(find.text('忽略'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsNothing);
      expect(store.shouldPromptForUpdate, isFalse);
      if (choice == '忽略') expect(store.preferences.ignoredUpdateBuild, 4);
      store.notifyUpdateListeners();
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
