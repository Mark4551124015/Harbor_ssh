import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harbor-persistence-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  File configFile() => File('${directory.path}/config');
  File libraryFile([String name = 'library.json']) =>
      File('${directory.path}/$name');

  SSHStore newStore({
    File? config,
    File? metadata,
    List<File>? legacy,
    int archiveBudget = 10 * 1024 * 1024,
  }) => SSHStore(
    load: false,
    configFile: config ?? configFile(),
    metadataFile: metadata,
    legacyMetadataFiles: legacy,
    archiveBudget: archiveBudget,
  );

  group('editable SSH options persist through the config file', () {
    test(
      'every option offered by the editor survives save and reload',
      () async {
        final config = configFile();
        await config.writeAsString(
          'Host lab\n  HostName lab.test\n  User deploy\n',
        );
        final first = newStore(config: config, metadata: libraryFile());
        await first.loadConfig();
        final host = first.hosts.single;
        for (final option in harborSSHOptions) {
          host.advancedOptions[option.name] = option.example;
        }
        expect(host.advancedOptions.length, harborSSHOptions.length);

        expect(await first.saveConfig(), isTrue);
        expect(first.configError, isNull);

        final second = newStore(config: config, metadata: libraryFile());
        await second.loadConfig();
        expect(second.hosts.single.advancedOptions, host.advancedOptions);

        // Rewriting an already reloaded host must not lose anything either.
        expect(await second.saveConfig(), isTrue);
        final third = newStore(config: config, metadata: libraryFile());
        await third.loadConfig();
        expect(third.hosts.single.advancedOptions, host.advancedOptions);
      },
    );

    test('option names are recognised regardless of case', () async {
      final config = configFile();
      await config.writeAsString(
        'Host lab\n'
        '  HostName lab.test\n'
        '  compression yes\n'
        '  serveraliveinterval 45\n',
      );
      final loaded = newStore(config: config, metadata: libraryFile());
      await loaded.loadConfig();
      final options = loaded.hosts.single.advancedOptions;
      expect(options['compression'], 'yes');
      expect(options['serveraliveinterval'], '45');
      expect(loaded.isDirty('lab'), isFalse);
    });

    test('an option outside the editor catalogue is not adopted', () async {
      final config = configFile();
      await config.writeAsString(
        'Host lab\n  HostName lab.test\n  NotAnOption value\n',
      );
      final loaded = newStore(config: config, metadata: libraryFile());
      await loaded.loadConfig();
      expect(loaded.hosts.single.advancedOptions, isEmpty);
    });
  });

  group('config failures reach the interface', () {
    test('an unreadable config reports an error and no hosts', () async {
      final config = configFile();
      // Invalid UTF-8 makes the file exist but fail to decode.
      await config.writeAsBytes([0xff, 0xfe, 0xfd, 0x80, 0x00]);
      final loaded = newStore(config: config, metadata: libraryFile());
      await loaded.loadConfig();
      expect(loaded.configError, isNotNull);
      expect(loaded.configError, contains('load'));
      expect(loaded.hosts, isEmpty);
    });

    test('a successful load clears the previous error', () async {
      final config = configFile();
      await config.writeAsBytes([0xff, 0xfe, 0xfd, 0x80, 0x00]);
      final loaded = newStore(config: config, metadata: libraryFile());
      await loaded.loadConfig();
      expect(loaded.configError, isNotNull);

      await config.writeAsString('Host lab\n  HostName lab.test\n');
      await loaded.loadConfig();
      expect(loaded.configError, isNull);
      expect(loaded.hosts.single.hostAlias, 'lab');
    });

    test('a failed save returns false and keeps the host unsaved', () async {
      final config = configFile();
      await config.writeAsString('Host lab\n  HostName lab.test\n');
      final failing = newStore(config: config, metadata: libraryFile());
      await failing.loadConfig();
      // Replacing the config with a directory makes the write fail.
      await config.delete();
      await Directory(config.path).create(recursive: true);
      failing.hosts.single.user = 'deploy';
      failing.markDirty('lab');

      expect(await failing.saveConfig(), isFalse);
      expect(failing.configError, isNotNull);
      expect(failing.configError, contains('save'));
      expect(failing.isDirty('lab'), isTrue);
    });

    test('a successful save reports true and clears the error', () async {
      final config = configFile();
      await config.writeAsString('Host lab\n  HostName lab.test\n');
      final store = newStore(config: config, metadata: libraryFile());
      await store.loadConfig();
      store.hosts.single.user = 'deploy';

      expect(await store.saveConfig(), isTrue);
      expect(store.configError, isNull);
      expect(store.isDirty('lab'), isFalse);
      expect(await config.readAsString(), contains('User deploy'));
    });
  });

  group('config archives', () {
    Directory archiveDirectory(File config) =>
        Directory('${config.parent.path}/config_bk');

    List<String> archiveNames(File config) => archiveDirectory(
      config,
    ).listSync().map((entity) => p.basename(entity.path)).toList()..sort();

    File archiveNamed(File config, String name) =>
        File('${archiveDirectory(config).path}/$name');

    Future<void> writeConfig(File config, String contents) =>
        config.writeAsString(contents);

    test(
      'every save keeps the file it replaced, named after the moment',
      () async {
        final config = configFile();
        await writeConfig(
          config,
          'Host lab\n  HostName lab.test\n  User deploy\n',
        );
        final store = newStore(config: config);
        await store.loadConfig();

        store.hosts.single.user = 'first';
        expect(await store.saveConfig(), isTrue);
        store.hosts.single.user = 'second';
        expect(await store.saveConfig(), isTrue);

        final names = archiveNames(config);
        expect(names, hasLength(2));
        for (final name in names) {
          expect(
            RegExp(r'^config-\d{8}-\d{6}-\d{3}\.bak$').hasMatch(name),
            isTrue,
            reason: name,
          );
        }
        final kept = await Future.wait(
          names.map((name) => archiveNamed(config, name).readAsString()),
        );
        expect(kept, anyElement(contains('User deploy')));
        expect(kept, anyElement(contains('User first')));
        expect(await config.readAsString(), contains('User second'));
      },
    );

    test('keeps rapid saves distinct and in order', () async {
      final config = configFile();
      await writeConfig(
        config,
        'Host lab\n  HostName lab.test\n  User deploy\n',
      );
      final store = newStore(config: config);
      await store.loadConfig();

      for (final user in ['one', 'two', 'three']) {
        store.hosts.single.user = user;
        expect(await store.saveConfig(), isTrue);
      }

      final names = archiveNames(config);
      expect(names.toSet(), hasLength(names.length));
      final kept = await Future.wait(
        names.map((name) => archiveNamed(config, name).readAsString()),
      );
      expect(kept[0], contains('User deploy'));
      expect(kept[1], contains('User one'));
      expect(kept[2], contains('User two'));
    });

    test('drops the oldest copies once the budget is reached', () async {
      final config = configFile();
      await writeConfig(config, 'Host lab\n  HostName lab.test\n');
      final store = newStore(config: config, archiveBudget: 90);
      await store.loadConfig();

      for (final user in ['one', 'two', 'three', 'four']) {
        store.hosts.single.user = user;
        expect(await store.saveConfig(), isTrue);
      }

      final names = archiveNames(config);
      expect(names, isNotEmpty);
      var total = 0;
      for (final name in names) {
        total += await archiveNamed(config, name).length();
      }
      // The newest copy is kept even when it alone exceeds the budget.
      expect(total <= 90 || names.length == 1, isTrue, reason: '$total bytes');
      expect(
        await archiveNamed(config, names.last).readAsString(),
        contains('User three'),
      );
    });

    test('does not archive content that has not changed', () async {
      final config = configFile();
      await writeConfig(
        config,
        'Host lab\n  HostName lab.test\n  User deploy\n',
      );
      final store = newStore(config: config);
      await store.loadConfig();

      // The first save rewrites the file into Harbor's own layout, so give the
      // archive a stable baseline before checking that repeats are skipped.
      expect(await store.saveConfig(), isTrue);
      expect(await store.saveConfig(), isTrue);
      final settled = archiveNames(config).length;
      expect(await store.saveConfig(), isTrue);
      expect(archiveNames(config).length, settled);
    });

    test('stays out of the way when there is no config yet', () async {
      final config = configFile();
      final store = newStore(config: config);
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];

      expect(await store.saveConfig(), isTrue);
      expect(await config.exists(), isTrue);
      expect(await archiveDirectory(config).exists(), isFalse);
    });
  });

  group('legacy bundle identifier library', () {
    Future<File> writeLegacy(Object contents) async {
      final legacy = File('${directory.path}/legacy/host-library.json');
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString(
        contents is String ? contents : jsonEncode(contents),
      );
      return legacy;
    }

    test('is adopted only when the current library is absent', () async {
      final legacy = await writeLegacy({
        'groups': {'lab': 'Work'},
        'favorites': ['lab'],
        'preferences': {'accent': 'Teal'},
      });
      final current = File('${directory.path}/current/host-library.json');
      final migrated = newStore(metadata: current, legacy: [legacy]);
      await migrated.loadMetadata();

      expect(await current.exists(), isTrue);
      expect(migrated.hostGroups['lab'], 'Work');
      expect(migrated.favorites, contains('lab'));
      expect(migrated.preferences.accent, 'Teal');
      expect(migrated.metadataError, isNull);
      // The old file is preserved and no temporary file is left behind.
      expect(await legacy.exists(), isTrue);
      expect(await File('${current.path}.migration.tmp').exists(), isFalse);
    });

    test('never replaces a library that already exists', () async {
      final legacy = await writeLegacy({
        'groups': {'old': 'Old'},
      });
      final current = File('${directory.path}/current/host-library.json');
      await current.parent.create(recursive: true);
      await current.writeAsString(
        jsonEncode({
          'groups': {'new': 'New'},
        }),
      );

      final loaded = newStore(metadata: current, legacy: [legacy]);
      await loaded.loadMetadata();
      expect(loaded.hostGroups, {'new': 'New'});
    });

    test('a malformed legacy library is reported and not copied', () async {
      final legacy = await writeLegacy('{ this is not json');
      final current = File('${directory.path}/current/host-library.json');
      final loaded = newStore(metadata: current, legacy: [legacy]);
      await loaded.loadMetadata();

      expect(loaded.metadataError, isNotNull);
      expect(await current.exists(), isFalse);
    });

    test('legacy data with the wrong shape is rejected', () async {
      final legacy = await writeLegacy({'groups': 'not a map'});
      final current = File('${directory.path}/current/host-library.json');
      final loaded = newStore(metadata: current, legacy: [legacy]);
      await loaded.loadMetadata();

      expect(loaded.metadataError, isNotNull);
      expect(await current.exists(), isFalse);
    });

    test('no legacy file leaves the store usable', () async {
      final current = File('${directory.path}/current/host-library.json');
      final loaded = newStore(
        metadata: current,
        legacy: [File('${directory.path}/missing/host-library.json')],
      );
      await loaded.loadMetadata();

      expect(loaded.metadataError, isNull);
      expect(await current.exists(), isFalse);
      expect(loaded.hostGroups, isEmpty);
    });
  });
}
