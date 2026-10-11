import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:macos_ssh_tool/main.dart';
import 'package:socks5_proxy/socks_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Exercise real loopback proxy servers.
  test('Proxy preferences roundtrip and reject invalid persisted ports', () {
    final prefs = const HarborPreferences().copyWith(
      proxyMode: 'socks',
      proxyHost: 'localhost',
      proxyPort: 1080,
      sshUseProxy: true,
      updatesUseProxy: false,
    );
    final restored = HarborPreferences.fromJson(prefs.toJson());
    expect(restored.proxyMode, 'socks');
    expect(restored.proxyHost, 'localhost');
    expect(restored.proxyPort, 1080);
    expect(restored.sshUseProxy, isTrue);
    expect(restored.updatesUseProxy, isFalse);
    expect(HarborPreferences.fromJson({'proxyPort': -1}).proxyPort, 7899);
    expect(
      () => HarborProxy('http', 'x; touch /tmp/bad', 80),
      throwsFormatException,
    );
  });
  test('System environment handles SOCKS and bypass rules', () {
    final url = Uri.parse('https://github.com');
    expect(
      HarborProxy.fromEnvironment(url, {
        'ALL_PROXY': 'socks5h://127.0.0.1:1080',
      })?.type,
      'socks',
    );
    expect(
      HarborProxy.fromEnvironment(url, {
        'https_proxy': 'http://localhost:8080',
        'no_proxy': 'github.com',
      }),
      isNull,
    );
    expect(
      HarborProxy.fromEnvironment(url, {
        'HTTPS_PROXY': 'http://localhost:8080',
      })?.port,
      8080,
    );
  });
  test(
    'System routing respects macOS bypass instead of environment fallback',
    () async {
      const channel = MethodChannel('harbor/files');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {'type': 'direct', 'configured': true},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = SSHStore(load: false);
      expect(
        await store.resolveProxy(
          Uri.parse('https://github.com'),
          enabled: true,
        ),
        isNull,
      );
    },
  );
  test(
    'SSH HTTP and SOCKS routing keeps jump hosts and explicit transports',
    () async {
      final store = SSHStore(load: false);
      store.preferences = const HarborPreferences(
        proxyMode: 'socks',
        sshUseProxy: true,
        updatesUseProxy: false,
        proxyPort: 1080,
      );
      final host = SSHHost(hostAlias: 'lab', hostName: 'server.test');
      final args = await store.sshNetworkProxyArguments(host);
      expect(args.last, contains("'-X' '5'"));
      expect(args.last, contains("'%h' '%p'"));
      host.proxyJump = 'gateway';
      store.hosts = [
        host,
        SSHHost(
          hostAlias: 'gateway',
          hostName: 'jump.test',
          user: 'alice',
          port: '2222',
          identityFile: '/tmp/key with spaces',
        ),
      ];
      final proxied = await store.sshNetworkProxyArguments(host);
      expect(proxied.last, contains('jump.test'));
      expect(proxied.last, contains('2222'));
      expect(proxied.last, contains('alice@jump.test'));
      expect(proxied.last, contains('%h:%p'));
      expect(
        host.getPreviewCommand(networkArguments: proxied),
        isNot(contains(' -J ')),
      );
      host.advancedOptions['ProxyCommand'] = 'custom transport';
      expect(await store.sshNetworkProxyArguments(host), isEmpty);
      host.advancedOptions.clear();
      host.proxyJump = '';
      store.preferences = store.preferences.copyWith(proxyMode: 'http');
      expect(
        (await store.sshNetworkProxyArguments(host)).last,
        contains("'-X' 'connect'"),
      );
      store.preferences = store.preferences.copyWith(sshUseProxy: false);
      expect(await store.sshNetworkProxyArguments(host), isEmpty);
    },
  );
  test(
    'HTTP proxy and updates switch route real requests independently',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      addTearDown(() => proxy.close(force: true));
      origin.listen((request) {
        request.response.write('direct');
        unawaited(request.response.close());
      });
      proxy.listen((request) {
        request.response.write('proxied');
        unawaited(request.response.close());
      });
      final url = Uri.parse('http://127.0.0.1:${origin.port}/update');
      final store = SSHStore(load: false);
      store.preferences = HarborPreferences(
        proxyMode: 'http',
        proxyPort: proxy.port,
        sshUseProxy: false,
      );
      Future<String> get() async {
        final client = await store.createUpdateHttpClient(url);
        try {
          return await utf8.decodeStream(
            await (await client.getUrl(url)).close(),
          );
        } finally {
          client.close(force: true);
        }
      }

      expect(await get(), 'proxied');
      store.preferences = store.preferences.copyWith(updatesUseProxy: false);
      expect(await get(), 'direct');
      store.preferences = store.preferences.copyWith(
        updatesUseProxy: true,
        proxyMode: 'off',
      );
      expect(await get(), 'direct');
    },
  );
  test('SOCKS5 update client tunnels real HTTP traffic', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    origin.listen((request) {
      request.response.write('socks works');
      unawaited(request.response.close());
    });
    final proxy = SocksServer();
    var forwarded = 0;
    final subscription = proxy.connections.listen((connection) async {
      forwarded++;
      await connection.forward();
    });
    await proxy.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await subscription.cancel();
      await proxy.stop();
    });
    final store = SSHStore(load: false);
    store.preferences = HarborPreferences(
      proxyMode: 'socks',
      proxyPort: proxy.proxies.values.single.port,
    );
    final client = await store.createUpdateHttpClient(
      Uri.parse('http://127.0.0.1:${origin.port}'),
    );
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${origin.port}'),
      )).close();
      expect(await utf8.decodeStream(response), 'socks works');
      expect(forwarded, 1);
    } finally {
      client.close(force: true);
    }
  });
}
