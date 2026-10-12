import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';

class ManifestHttpClient extends Fake implements HttpClient {
  final HttpClient delegate;
  final Uri local;
  final List<Uri> requests;
  ManifestHttpClient(this.delegate, this.local, this.requests);
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests.add(url);
    return delegate.getUrl(local);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

class ManifestUpdateStore extends SSHStore {
  final Uri local;
  final List<Uri> requests = [];
  ManifestUpdateStore(this.local) : super(load: false) {
    updateHttpClientFactory = (_) async =>
        ManifestHttpClient(HttpClient(), local, requests);
  }
}

void main() {
  Map<String, dynamic> release({int build = 4}) => {
    'name': 'beta-1.0.2',
    'build': '$build',
    'draft': false,
    'prerelease': false,
    'assets': [
      for (final name in [
        'Harbor-1.0.2-beta-macos-universal-unsigned.zip',
        'SHA256SUMS.txt',
      ])
        {
          'name': name,
          'browser_download_url':
              'https://github.com/Mark4551124015/Harbor_ssh/releases/download/beta-1.0.2/$name',
        },
    ],
  };
  test(
    'Checking updates requests only the static manifest and discovers the release',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write(
          jsonEncode({
            'version': '1.0.3-beta.1',
            'build': 5,
            'bundle_id': 'com.mark455.harbor',
            'notarized': false,
          }),
        );
        await request.response.close();
      });
      final store = ManifestUpdateStore(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      addTearDown(store.dispose);
      store.applicationBuild = '4';
      await store.checkForUpdates(automatic: true);
      expect(store.updateError, isFalse);
      expect(store.availableUpdate?.build, 5);
      expect(store.pendingUpdatePrompt, 5);
      expect(store.requests.map((url) => url.toString()), [
        HarborUpdate.manifestUrl,
      ]);
      store.applicationBuild = '5';
      await store.checkForUpdates();
      expect(store.availableUpdate, isNull);
      expect(store.updateStatus, 'Harbor is up to date.');
    },
  );
  test(
    'Updates use increasing build numbers and require public release assets',
    () {
      expect(HarborUpdate.parse(release(), 3)?.build, 4);
      expect(HarborUpdate.parse(release(build: 3), 3), isNull);
      expect(HarborUpdate.parse(release(build: 2), 3), isNull);
      expect(HarborUpdate.parse(release()..['draft'] = true, 3), isNull);
      expect(HarborUpdate.parse(release()..['prerelease'] = true, 3), isNull);
      expect(HarborUpdate.parse(release()..['assets'] = [], 3), isNull);
    },
  );
  test('Updates reject download URLs outside the Harbor repository', () {
    final data = release();
    (data['assets'] as List).first['browser_download_url'] =
        'https://github.com/other/repo/releases/download/test/app.zip';
    expect(HarborUpdate.parse(data, 3), isNull);
  });
  test(
    'Static manifest discovers existing canonical releases without an API',
    () {
      final manifest = <String, dynamic>{
        'version': '1.0.3-beta.1',
        'build': '5',
        'bundle_id': 'com.mark455.harbor',
        'notarized': false,
      };
      final update = HarborUpdate.fromManifest(manifest, 4)!;
      expect(update.version, '1.0.3-beta.1');
      expect(
        update.archive.toString(),
        'https://github.com/Mark4551124015/Harbor_ssh/releases/download/v1.0.3-beta.1/Harbor-1.0.3-beta.1-macos-universal-unsigned.zip',
      );
      expect(update.checksums.path, endsWith('/v1.0.3-beta.1/SHA256SUMS.txt'));
      expect(HarborUpdate.fromManifest(manifest, 5), isNull);
      expect(Uri.parse(HarborUpdate.manifestUrl).host, 'github.com');
      expect(HarborUpdate.manifestUrl, contains('/releases/latest/download/'));
      manifest['archive_url'] = 'https://other.test/payload.zip';
      expect(
        () => HarborUpdate.fromManifest(manifest, 4),
        throwsFormatException,
      );
      manifest.remove('archive_url');
      manifest['bundle_id'] = 'com.other.app';
      expect(
        () => HarborUpdate.fromManifest(manifest, 4),
        throwsFormatException,
      );
    },
  );
  test('Static manifest accepts explicit signed archive URLs', () {
    final manifest = <String, dynamic>{
      'version': '1.0.4',
      'build': 6,
      'bundle_id': 'com.mark455.harbor',
      'notarized': true,
      'archive_url':
          'https://github.com/Mark4551124015/Harbor_ssh/releases/download/v1.0.4/Harbor-1.0.4-macos-universal.zip',
      'checksums_url':
          'https://github.com/Mark4551124015/Harbor_ssh/releases/download/v1.0.4/SHA256SUMS.txt',
    };
    expect(
      HarborUpdate.fromManifest(manifest, 5)!.archive.path,
      endsWith('/Harbor-1.0.4-macos-universal.zip'),
    );
    manifest['build'] = 'invalid';
    expect(() => HarborUpdate.fromManifest(manifest, 5), throwsFormatException);
  });
  test('Automatic checks preference roundtrips and defaults on', () {
    expect(const HarborPreferences().autoCheckUpdates, isTrue);
    final prefs = const HarborPreferences().copyWith(autoCheckUpdates: false);
    expect(
      HarborPreferences.fromJson(prefs.toJson()).autoCheckUpdates,
      isFalse,
    );
    expect(HarborPreferences.fromJson({}).autoCheckUpdates, isTrue);
  });
}
