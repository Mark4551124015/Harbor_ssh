part of 'main.dart';

class HarborUpdate {
  final String version;
  final int build;
  final Uri archive;
  final Uri checksums;
  const HarborUpdate(this.version, this.build, this.archive, this.checksums);

  static HarborUpdate? parse(Map<String, dynamic> release, int currentBuild) {
    if (release['draft'] != false || release['prerelease'] != false) {
      return null;
    }
    final assets = (release['assets'] as List? ?? []).whereType<Map>();
    Uri? asset(bool Function(String) select) {
      for (final item in assets) {
        final name = item['name'];
        if (name is! String || !select(name)) continue;
        final url = Uri.tryParse(
          item['browser_download_url']?.toString() ?? '',
        );
        if (url?.scheme == 'https' &&
            url?.host == 'github.com' &&
            url!.path.startsWith(
              '/Mark4551124015/Harbor_ssh/releases/download/',
            )) {
          return url;
        }
      }
      return null;
    }

    final archive = asset(
      (name) =>
          name.startsWith('Harbor-') &&
          name.contains('-macos-universal') &&
          name.endsWith('.zip'),
    );
    final sums = asset((name) => name == 'SHA256SUMS.txt');
    // The release manifest supplies a monotonic build number, independent of
    // whether a release's display name uses beta-1.0.1 or a SemVer tag.
    final build = int.tryParse(release['build']?.toString() ?? '');
    if (build == null ||
        build <= currentBuild ||
        archive == null ||
        sums == null) {
      return null;
    }
    return HarborUpdate(
      release['name']?.toString() ?? 'Harbor',
      build,
      archive,
      sums,
    );
  }
}

extension HarborUpdates on SSHStore {
  Future<List<int>> _updateRequest(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 20));
      request.headers.set('User-Agent', 'Harbor-SSH');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw HttpException('Update server returned ${response.statusCode}.');
      }
      return await response
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk))
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> checkForUpdates({bool automatic = false}) async {
    if (updateBusy) return;
    updateBusy = true;
    updateError = false;
    updateStatus = 'Checking for updates…';
    notifyUpdateListeners();
    try {
      final data =
          jsonDecode(
                utf8.decode(
                  await _updateRequest(
                    Uri.parse(
                      'https://api.github.com/repos/Mark4551124015/Harbor_ssh/releases/latest',
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final assets = (data['assets'] as List).whereType<Map>();
      final manifest = assets
          .where((item) => item['name'] == 'release-manifest.json')
          .firstOrNull;
      if (manifest == null) {
        throw const FormatException(
          'This release does not include update metadata.',
        );
      }
      final url = Uri.parse(manifest['browser_download_url'] as String);
      if (url.scheme != 'https' ||
          url.host != 'github.com' ||
          !url.path.startsWith(
            '/Mark4551124015/Harbor_ssh/releases/download/',
          )) {
        throw const FormatException('Invalid update metadata URL.');
      }
      final metadata =
          jsonDecode(utf8.decode(await _updateRequest(url))) as Map;
      data['build'] = metadata['build'];
      availableUpdate = HarborUpdate.parse(
        data,
        int.tryParse(applicationBuild) ?? 0,
      );
      updateStatus = availableUpdate == null
          ? 'Harbor is up to date.'
          : '${availableUpdate!.version} is available.';
    } catch (_) {
      updateError = true;
      updateStatus = 'Could not check for updates. Please try again.';
    } finally {
      updateBusy = false;
      notifyUpdateListeners();
    }
  }

  Future<void> installUpdate() async {
    final update = availableUpdate;
    if (update == null || updateBusy) return;
    updateBusy = true;
    updateError = false;
    Directory? staging;
    try {
      updateStatus = 'Downloading update…';
      notifyUpdateListeners();
      staging = await Directory.systemTemp.createTemp('harbor-update-');
      final archive = File('${staging.path}/update.zip');
      final sums = utf8.decode(await _updateRequest(update.checksums));
      final filename = update.archive.pathSegments.last;
      final expected = const LineSplitter()
          .convert(sums)
          .map(
            (line) => RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line),
          )
          .whereType<RegExpMatch>()
          .where((match) => match[2] == filename)
          .firstOrNull?[1];
      if (expected == null) {
        throw const FormatException('Update checksum missing.');
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final response = await (await client.getUrl(update.archive)).close();
        if (response.statusCode != 200) {
          throw const HttpException('Download failed.');
        }
        final sink = archive.openWrite();
        var received = 0;
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 30),
          )) {
            sink.add(bytes);
            received += bytes.length;
            if (received > 512 * 1024 * 1024) {
              throw const FormatException('Update is too large.');
            }
            updateStatus = response.contentLength > 0
                ? 'Downloading update… ${(received * 100 / response.contentLength).floor()}%'
                : 'Downloading update… ${(received / 1048576).floor()} MB';
            notifyUpdateListeners();
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }
      updateStatus = 'Verifying update…';
      notifyUpdateListeners();
      final digest = await Process.run('/usr/bin/shasum', [
        '-a',
        '256',
        archive.path,
      ]);
      if (digest.exitCode != 0 ||
          !digest.stdout.toString().startsWith(expected.toLowerCase())) {
        throw const FormatException('Update checksum mismatch.');
      }
      final listing = await Process.run('/usr/bin/unzip', [
        '-Z1',
        archive.path,
      ]);
      final entries = const LineSplitter().convert(listing.stdout.toString());
      if (listing.exitCode != 0 ||
          entries.isEmpty ||
          entries.any(
            (entry) =>
                entry.startsWith('/') ||
                entry.split('/').contains('..') ||
                !(entry.startsWith('Harbor.app/') ||
                    entry.startsWith('__MACOSX/')),
          )) {
        throw const FormatException('Invalid update archive.');
      }
      final extracted = await Process.run('/usr/bin/ditto', [
        '-x',
        '-k',
        archive.path,
        staging.path,
      ]);
      if (extracted.exitCode != 0) {
        throw const FormatException('Could not extract update.');
      }
      updateStatus = 'Installing and restarting…';
      notifyUpdateListeners();
      await const MethodChannel('harbor/files').invokeMethod<void>(
        'installUpdate',
        {'path': '${staging.path}/Harbor.app', 'build': update.build},
      );
      staging = null; // The detached installer owns cleanup after app exit.
    } catch (error) {
      updateError = true;
      updateStatus = error is PlatformException
          ? error.message ?? 'Update failed.'
          : 'Update failed. Please try again.';
    } finally {
      if (staging != null) await staging.delete(recursive: true);
      updateBusy = false;
      notifyUpdateListeners();
    }
  }
}
