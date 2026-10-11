import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class FormsStore extends SSHStore {
  FormsStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

Future<void> pumpForm(WidgetTester tester, SSHStore store, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(1040, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<SSHStore>.value(
      value: store,
      child: MacosApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'New connection focuses its first field after page fades finish',
    (tester) async {
      final store = FormsStore();
      await pumpForm(tester, store, const MainWindow());
      await tester.tap(find.text('New connection'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is HarborTextField &&
            widget.initialValue == store.currentHost!.hostAlias,
      );
      final input = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(input.focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'New group dialog focuses its input rather than the dialog wrapper',
    (tester) async {
      final store = FormsStore();
      await pumpForm(
        tester,
        store,
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showNewGroupDialog(context, store),
            child: const Text('Open group dialog'),
          ),
        ),
      );
      await tester.tap(find.text('Open group dialog'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(EditableText), 'Production');
      await tester.pump();
      await tester.tap(find.text('Create group'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(store.groupNames, contains('Production'));
    },
  );

  testWidgets(
    'Advanced starts empty, searches descriptions, focuses drafts and saves only filled options',
    (tester) async {
      final store = FormsStore();
      final host = SSHHost(hostAlias: 'lab');
      await pumpForm(tester, store, HarborAdvancedOptionsPage(host: host));
      expect(find.text('No custom options'), findsOneWidget);
      expect(find.text('Optional'), findsNothing);
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      final search = find.byType(EditableText);
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      await tester.enterText(search, 'encrypted keepalive');
      await tester.pumpAndSettle();
      expect(find.text('ServerAliveInterval'), findsOneWidget);
      expect(find.text('Compression'), findsNothing);
      await tester.tap(find.text('ServerAliveInterval'));
      await tester.pumpAndSettle();
      expect(host.advancedOptions, isEmpty);
      expect(host.toConfigBlock(), isNot(contains('ServerAliveInterval')));
      final value = find.descendant(
        of: find.byKey(const ValueKey('option-value-ServerAliveInterval')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(value).focusNode.hasFocus, isTrue);
      await tester.enterText(value, '30');
      await tester.pumpAndSettle();
      expect(host.advancedOptions['ServerAliveInterval'], '30');
      expect(host.toConfigBlock(), contains('ServerAliveInterval 30'));
      await tester.tap(find.byTooltip('Remove ServerAliveInterval'));
      await tester.pumpAndSettle();
      expect(host.advancedOptions, isEmpty);
      expect(find.text('No custom options'), findsOneWidget);
    },
  );

  testWidgets(
    'Imported option casing and unknown options remain editable; clearing keeps row order',
    (tester) async {
      final store = FormsStore();
      final host = SSHHost(
        hostAlias: 'lab',
        advancedOptions: {
          'SERVERALIVEINTERVAL': '30',
          'VendorOption': 'custom',
        },
      );
      await pumpForm(tester, store, HarborAdvancedOptionsPage(host: host));
      expect(find.text('VendorOption'), findsOneWidget);
      final first = find.byKey(
        const ValueKey('option-value-SERVERALIVEINTERVAL'),
      );
      final before = tester.getTopLeft(first);
      await tester.enterText(
        find.descendant(of: first, matching: find.byType(EditableText)),
        '',
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first), before);
      expect(host.advancedOptions, {'VendorOption': 'custom'});
      await tester.enterText(
        find.descendant(of: first, matching: find.byType(EditableText)),
        '60',
      );
      await tester.pumpAndSettle();
      expect(host.advancedOptions['SERVERALIVEINTERVAL'], '60');
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is EditableText && widget.focusNode.hasFocus,
        ),
        'ServerAliveInterval',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching options'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(host.toConfigBlock(), contains('VendorOption custom'));
    },
  );

  testWidgets('Adding to a long options list scrolls to the new value field', (
    tester,
  ) async {
    final store = FormsStore();
    final host = SSHHost(
      hostAlias: 'lab',
      advancedOptions: {
        for (var i = 0; i < 8; i++) 'ImportedOption$i': 'value',
      },
    );
    await pumpForm(tester, store, HarborAdvancedOptionsPage(host: host));
    await tester.tap(find.text('Add option'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.focusNode.hasFocus,
      ),
      'RemoteCommand',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('RemoteCommand').last);
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('option-value-RemoteCommand')),
      matching: find.byType(EditableText),
    );
    expect(input, findsOneWidget);
    expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
    expect(input.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'New host rows move and fade in while existing rows retain their state',
    (tester) async {
      final first = SSHHost(hostAlias: 'existing');
      final added = SSHHost(hostAlias: 'added');
      var hosts = [first];
      late StateSetter update;
      await tester.pumpWidget(
        MacosApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return HarborAnimatedHosts(
                    hosts: hosts,
                    itemBuilder: (host) => Text(host.hostAlias),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final existing = tester.element(find.text('existing'));
      final origin = tester.getTopLeft(find.text('existing')).dy;
      update(() => hosts = [added, first]);
      await tester.pump();
      final fade = find
          .ancestor(of: find.text('added'), matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(fade).opacity, 0);
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, 1));
      expect(
        tester.getTopLeft(find.text('existing')).dy - origin,
        inExclusiveRange(0, 56),
      );
      expect(tester.element(find.text('existing')), same(existing));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(fade).opacity, 1);
    },
  );

  testWidgets('New groups enter while existing groups move smoothly', (
    tester,
  ) async {
    var sections = [const MapEntry<String, List<SSHHost>>('Existing', [])];
    late StateSetter update;
    await tester.pumpWidget(
      MacosApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HarborAnimatedSections(
                  sections: sections,
                  collapsed: const {},
                  sectionBuilder: (section) =>
                      SizedBox(height: 40, child: Text(section.key)),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.text('Existing')).dy;
    update(
      () => sections = [const MapEntry('Added', <SSHHost>[]), ...sections],
    );
    await tester.pump();
    final fade = find
        .ancestor(of: find.text('Added'), matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(fade).opacity, 0);
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, 1));
    expect(
      tester.getTopLeft(find.text('Existing')).dy - origin,
      inExclusiveRange(0, 40),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade).opacity, 1);
  });
}
