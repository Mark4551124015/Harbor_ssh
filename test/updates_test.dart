import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ssh_tool/main.dart';

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
