import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';
import 'widget_test.dart' show TunnelTestProcess;

void main() {
  test(
    'Quit stops owned mappings and cancels a mapping still spawning',
    () async {
      final ready = TunnelTestProcess();
      final spawning = Completer<Process>();
      var starts = 0;
      final store = SSHStore(
        load: false,
        processStarter: (_, __) async {
          if (starts++ == 0) return ready;
          return spawning.future;
        },
      );
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'example.test')];
      final running = store.startProxy(
        'lab',
        forwardType: 'L',
        forwardValue: '8080:localhost:80',
      );
      await Future<void>.delayed(Duration.zero);
      ready.output.add(utf8.encode('Entering interactive session.\n'));
      expect(await running, isNull);
      final starting = store.startProxy(
        'lab',
        forwardType: 'L',
        forwardValue: '8081:localhost:80',
      );
      final shutdown = store.shutdownProxies();
      expect(ready.killed, isTrue);
      final late = TunnelTestProcess();
      spawning.complete(late);
      await shutdown;
      expect(await starting, 'Mapping startup cancelled.');
      expect(late.killed, isTrue);
      expect(store.isConnected('lab'), isFalse);
      expect(await store.startProxy('lab'), 'Application is quitting.');
    },
  );

  test(
    'Terminal arguments preserve spaces and cannot execute shell substitutions',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-command-');
      addTearDown(() => dir.delete(recursive: true));
      final marker = '${dir.path}/injected';
      final host = SSHHost(
        hostAlias: 'test',
        hostName: 'host; touch $marker',
        user: 'user',
        identityFile: '/tmp/key with spaces',
        proxyJump: 'jump\$(touch $marker)',
        advancedOptions: {'ProxyCommand': 'echo \$(touch $marker)'},
      );
      final command = host.getPreviewCommand();
      // Substitute a shell function for ssh; never make a network connection.
      final script = File('${dir.path}/check.sh');
      await script.writeAsString('ssh() { printf "%s\\n" "\$@"; }\n$command\n');
      final result = await Process.run('/bin/bash', [script.path]);
      expect(result.exitCode, 0);
      expect(await File(marker).exists(), isFalse);
      final args = const LineSplitter().convert(result.stdout as String);
      expect(args, contains('/tmp/key with spaces'));
      expect(args, contains('jump\$(touch $marker)'));
      expect(args, contains('user@host; touch $marker'));
      expect(args, contains('--'));
    },
  );

  test(
    'Supported config roundtrip retains jumps, forwards and a backup',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-config-');
      addTearDown(() => dir.delete(recursive: true));
      final config = File('${dir.path}/config');
      const original =
          'Host lab\n  HostName lab.test\n  User deploy\n  Port 2222\n  ProxyJump gateway\n  IdentityFile /tmp/key\n  LocalForward 8080 localhost:80\n  DynamicForward 1080\n  ConnectTimeout 30\n  ServerAliveInterval 60\n';
      await config.writeAsString(original);
      final store = SSHStore(load: false, configFile: config);
      await store.loadConfig();
      expect(store.hosts.single.localForwards, ['8080:localhost:80']);
      store.hosts.single.hostName = 'new.test';
      await store.saveConfig();
      // The save keeps a copy of the file it replaced.
      final archives = Directory(
        '${config.parent.path}/config_bk',
      ).listSync().whereType<File>().toList();
      expect(archives, hasLength(1));
      expect(await archives.single.readAsString(), original);
      final restored = SSHStore(load: false, configFile: config);
      await restored.loadConfig();
      expect(restored.hosts.single.hostName, 'new.test');
      expect(restored.hosts.single.proxyJump, 'gateway');
      expect(restored.hosts.single.advancedOptions['ConnectTimeout'], '30');
      expect(restored.hosts.single.dynamicForward, '1080');
    },
  );

  test(
    'Queued metadata writes retain the final state after rapid edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('harbor-write-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.json');
      final store = SSHStore(load: false, metadataFile: file);
      final writes = <Future<void>>[];
      for (final name in ['Production', 'Development', 'Research']) {
        writes.add(store.createGroup(name));
      }
      writes.add(
        store.updatePreferences(const HarborPreferences(accent: 'Teal')),
      );
      await Future.wait(writes);
      final restored = SSHStore(load: false, metadataFile: file);
      await restored.loadMetadata();
      expect(
        restored.groupNames,
        containsAll(['Production', 'Development', 'Research']),
      );
      expect(restored.preferences.accent, 'Teal');
      expect(await File('${file.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'Stopping a mapping while its process spawns cancels it and allows retry',
    () async {
      final spawning = Completer<Process>();
      final process = TunnelTestProcess();
      final store = SSHStore(
        load: false,
        processStarter: (_, __) => spawning.future,
      );
      store.hosts = [SSHHost(hostAlias: 'lab', hostName: 'lab.test')];
      final mapping = ManagedMapping(
        id: 'cancel',
        serverAlias: 'lab',
        type: 'D',
        value: '1080',
      );
      final starting = store.toggleMapping(mapping);
      expect(store.mappingLoading(mapping), isTrue);
      await store.stopMapping(mapping);
      spawning.complete(process);
      expect(await starting, contains('cancelled'));
      expect(process.killed, isTrue);
      expect(store.mappingLoading(mapping), isFalse);
      expect(store.mappingRunning(mapping), isFalse);
    },
  );

  test(
    'Failed tunnel returns stderr, resets state and respects host overrides',
    () async {
      final process = TunnelTestProcess();
      late List<String> command;
      final store = SSHStore(
        load: false,
        processStarter: (_, args) async {
          command = args;
          scheduleMicrotask(() {
            process.output.add(utf8.encode('Permission denied (publickey).\n'));
            process.completion.complete(255);
            unawaited(process.output.close());
          });
          return process;
        },
      );
      store.preferences = const HarborPreferences(
        connectTimeout: 10,
        keepAlive: 30,
      );
      store.hosts = [
        SSHHost(
          hostAlias: 'lab',
          hostName: 'lab.test',
          advancedOptions: {
            'ConnectTimeout': '60',
            'ServerAliveInterval': '90',
          },
        ),
      ];
      final mapping = ManagedMapping(
        id: 'fail',
        serverAlias: 'lab',
        type: 'D',
        value: '1080',
      );
      expect(await store.toggleMapping(mapping), contains('Permission denied'));
      expect(
        command,
        containsAll(['ConnectTimeout=60', 'ServerAliveInterval=90']),
      );
      expect(command, isNot(contains('ConnectTimeout=10')));
      expect(command, isNot(contains('ServerAliveInterval=30')));
      expect(store.mappingRunning(mapping), isFalse);
      expect(store.mappingLoading(mapping), isFalse);
    },
  );
}
