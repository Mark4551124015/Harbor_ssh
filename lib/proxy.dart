part of 'main.dart';

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

class HarborProxy {
  final String type;
  final String host;
  final int port;
  HarborProxy(this.type, this.host, this.port) {
    if (!['http', 'socks'].contains(type) ||
        port < 1 ||
        port > 65535 ||
        host.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(host) ||
        host.startsWith('-')) {
      throw const FormatException(
        'Enter a valid proxy hostname and port (1–65535).',
      );
    }
  }
  String get authority => '${host.contains(':') ? '[$host]' : host}:$port';
  static HarborProxy? fromEnvironment(
    Uri url,
    Map<String, String> environment,
  ) {
    final bypass = HttpClient.findProxyFromEnvironment(
      url,
      environment: {
        ...environment,
        'http_proxy': 'http://harbor-proxy.invalid:1',
        'https_proxy': 'http://harbor-proxy.invalid:1',
      },
    );
    if (bypass == 'DIRECT') return null;
    final value =
        environment['${url.scheme}_proxy'] ??
        environment['${url.scheme.toUpperCase()}_PROXY'] ??
        environment['all_proxy'] ??
        environment['ALL_PROXY'];
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'The proxy URL must contain a hostname and port without credentials.',
      );
    }
    if (!['http', 'socks5', 'socks5h', 'socks'].contains(uri.scheme)) {
      throw const FormatException('Use an HTTP CONNECT or SOCKS5 proxy.');
    }
    return HarborProxy(
      uri.scheme == 'http' ? 'http' : 'socks',
      uri.host,
      uri.hasPort
          ? uri.port
          : uri.scheme == 'http'
          ? 8080
          : 1080,
    );
  }

  String netcat(String target, String targetPort) => [
    '/usr/bin/nc',
    '-X',
    type == 'socks' ? '5' : 'connect',
    '-x',
    authority,
    target,
    targetPort,
  ].map(_shellQuote).join(' ');
}

class ConnectionProxyPreferences {
  final String mode;
  final String host;
  final int port;
  const ConnectionProxyPreferences({
    this.mode = 'off',
    this.host = '127.0.0.1',
    this.port = 7899,
  });
  factory ConnectionProxyPreferences.fromJson(dynamic value) {
    final prefs = HarborPreferences.fromJson(value);
    return ConnectionProxyPreferences(
      mode: prefs.proxyMode,
      host: prefs.proxyHost,
      port: prefs.proxyPort,
    );
  }
  Map<String, dynamic> toJson() => {
    'proxyMode': mode,
    'proxyHost': host,
    'proxyPort': port,
  };
  ConnectionProxyPreferences copyWith({
    String? mode,
    String? host,
    int? port,
  }) => ConnectionProxyPreferences(
    mode: mode ?? this.mode,
    host: host ?? this.host,
    port: port ?? this.port,
  );
}

extension HarborProxyRouting on SSHStore {
  Future<HarborProxy?> resolveProxy(
    Uri url, {
    required bool enabled,
    HarborPreferences? configuration,
  }) async {
    final prefs = configuration ?? preferences;
    if (!enabled || prefs.proxyMode == 'off') return null;
    if (prefs.proxyMode != 'system') {
      return HarborProxy(
        prefs.proxyMode,
        prefs.proxyHost.trim(),
        prefs.proxyPort,
      );
    }
    try {
      final result = await const MethodChannel('harbor/files')
          .invokeMapMethod<String, dynamic>('systemProxy', {
            'url': url.toString(),
          });
      if (result?['type'] == 'http' || result?['type'] == 'socks') {
        return HarborProxy(
          result!['type'] as String,
          result['host'] as String,
          result['port'] as int,
        );
      }
      if (result?['configured'] == true) {
        return null; // Respect system bypass rules.
      }
    } on MissingPluginException {
      // CLI tests and previews can use the process environment.
    }
    return HarborProxy.fromEnvironment(url, Platform.environment);
  }

  Future<HttpClient> createUpdateHttpClient(Uri url) async {
    final proxy = await resolveProxy(url, enabled: preferences.updatesUseProxy);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    // Explicit DIRECT disables Dart's implicit environment proxy handling.
    client.findProxy = (_) =>
        proxy?.type == 'http' ? 'PROXY ${proxy!.authority}' : 'DIRECT';
    if (proxy?.type == 'socks') {
      try {
        final address =
            InternetAddress.tryParse(proxy!.host) ??
            (await InternetAddress.lookup(
              proxy.host,
            ).timeout(const Duration(seconds: 15))).first;
        SocksTCPClient.assignToHttpClient(client, [
          ProxySettings(address, proxy.port),
        ]);
      } catch (_) {
        client.close(force: true);
        rethrow;
      }
    }
    return client;
  }

  Future<List<String>> sshNetworkProxyArguments(SSHHost host) async {
    final settings = proxyFor(host);
    if (settings.mode == 'off') return [];
    // An explicit per-host transport remains authoritative.
    if (host.advancedOptions.keys.any(
      (key) => key.toLowerCase() == 'proxycommand',
    )) {
      return [];
    }
    final jumps = <SSHHost>[];
    if (host.proxyJump.isNotEmpty && host.proxyJump != 'none') {
      for (final value in host.proxyJump.split(',')) {
        final match = RegExp(
          r'^(?:([^@]+)@)?(\[[^\]]+\]|[^:]+)(?::(\d+))?$',
        ).firstMatch(value.trim());
        if (match == null) {
          throw const FormatException('Invalid SSH jump address.');
        }
        final alias = match[2]!;
        final configured = hosts
            .where((entry) => entry.hostAlias == alias)
            .firstOrNull;
        jumps.add(
          SSHHost(
            hostAlias: alias,
            hostName:
                configured?.hostName ?? alias.replaceAll(RegExp(r'[\[\]]'), ''),
            user: match[1] ?? configured?.user ?? '',
            port: match[3] ?? configured?.port ?? '22',
            identityFile: configured?.identityFile ?? '',
            advancedOptions: configured?.advancedOptions ?? {},
          ),
        );
      }
    }
    final first = jumps.isEmpty ? host : jumps.first;
    final proxy = await resolveProxy(
      Uri(
        scheme: 'https',
        host: first.hostName,
        port: int.tryParse(first.port) ?? 22,
      ),
      enabled: true,
      configuration: HarborPreferences(
        proxyMode: settings.mode,
        proxyHost: settings.host,
        proxyPort: settings.port,
      ),
    );
    if (proxy == null) return [];
    if (jumps.isEmpty) {
      return ['-o', 'ProxyCommand=${proxy.netcat('%h', '%p')}'];
    }
    // Build the jump chain using OpenSSH itself, and proxy only the first hop.
    // Intermediate destinations are literals so nested ProxyCommands do not
    // accidentally expand another hop's %h/%p placeholders.
    var transport = proxy.netcat(first.hostName, first.port);
    for (var index = 0; index < jumps.length; index++) {
      final jump = jumps[index];
      final next = index + 1 < jumps.length ? jumps[index + 1] : null;
      final destination = next == null
          ? '%h:%p'
          : '${next.hostName.contains(':') ? '[${next.hostName}]' : next.hostName}:${next.port}';
      transport = [
        '/usr/bin/ssh',
        '-p',
        jump.port,
        if (jump.identityFile.isNotEmpty) ...['-i', jump.identityFile],
        '-o',
        'ProxyCommand=$transport',
        for (final option in jump.advancedOptions.entries)
          if (![
            'proxycommand',
            'proxyjump',
          ].contains(option.key.toLowerCase())) ...[
            '-o',
            '${option.key}=${option.value}',
          ],
        '-W',
        destination,
        '--',
        '${jump.user.isEmpty ? '' : '${jump.user}@'}${jump.hostName}',
      ].map(_shellQuote).join(' ');
    }
    return ['-o', 'ProxyCommand=$transport'];
  }
}
