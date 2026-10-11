import hashlib
from pathlib import Path
import sys
import plistlib
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        config = self.root / 'macos/Runner/Configs'
        config.mkdir(parents=True)
        (config / 'AppInfo.xcconfig').write_text('PRODUCT_BUNDLE_IDENTIFIER = com.mark455.harbor')
        (self.root / 'pubspec.yaml').write_text('version: 1.2.3+4\n')

    def test_tag_version_mismatch_and_injection_rejected(self):
        self.assertEqual(release.preflight('v1.2.3', root=self.root), ('1.2.3', '4'))
        for tag in ['v1.2.4', '1.2.3', 'v1.2.3; touch /tmp/no', '../v1.2.3']:
            with self.assertRaises(ValueError):
                release.preflight(tag, root=self.root)

    def test_official_release_needs_license_and_real_identifier(self):
        with self.assertRaises(ValueError):
            release.preflight('v1.2.3', True, self.root)
        (self.root / 'LICENSE').write_text('Selected license')
        self.assertEqual(release.preflight('v1.2.3', True, self.root), ('1.2.3', '4'))
        (self.root / 'macos/Runner/Configs/AppInfo.xcconfig').write_text('com.example.app')
        with self.assertRaises(ValueError):
            release.preflight('v1.2.3', root=self.root)

    def test_prerelease_and_invalid_build_versions(self):
        (self.root / 'pubspec.yaml').write_text('version: 1.2.3-beta.1+9\n')
        self.assertEqual(release.preflight('v1.2.3-beta.1', root=self.root), ('1.2.3-beta.1', '9'))
        for invalid in ['1.2.3', '1.2.3+0', '1.2.3+abc', '1.2+1', '../bad+1']:
            (self.root / 'pubspec.yaml').write_text(f'version: {invalid}\n')
            with self.assertRaises(ValueError):
                release.version(self.root)

    def test_beta_tag_uses_v_prefix_and_preserves_version_order(self):
        for value in ['1.0.2-beta', '1.0.3-beta.1', '1.0.3-beta.2']:
            (self.root / 'pubspec.yaml').write_text(f'version: {value}+4\n')
            self.assertEqual(release.preflight(f'v{value}', root=self.root), (value, '4'))
            for invalid in [value, 'beta-1.0.2', 'v1.0.4-beta.1', f'v{value}+4']:
                with self.assertRaises(ValueError):
                    release.preflight(invalid, root=self.root)

    def test_release_notes_match_exact_version_only(self):
        (self.root / 'CHANGELOG.md').write_text(
            '# Changelog\n\n## 1.2.3\n\n### Added\n\n- Current changes.\n\n'
            '## 1.2.2\n\n- Old changes.\n')
        self.assertEqual(release.release_notes(self.root), '### Added\n\n- Current changes.\n')
        (self.root / 'pubspec.yaml').write_text('version: 1.2.4+5\n')
        with self.assertRaises(ValueError):
            release.release_notes(self.root)

    def test_checksums_are_deterministic_and_detect_changes(self):
        first, second = self.root / 'a.zip', self.root / 'b.dmg'
        first.write_bytes(b'first')
        second.write_bytes(b'second')
        expected = hashlib.sha256(b'first').hexdigest()
        before = release.checksums([second, first])
        self.assertTrue(before.startswith(f'{expected}  a.zip\n'))
        first.write_bytes(b'changed')
        self.assertNotEqual(before, release.checksums([first, second]))

    def test_package_rejects_nonempty_output(self):
        output = self.root / 'dist'
        output.mkdir()
        (output / 'old.zip').write_bytes(b'old')
        with patch.object(release, 'verify', return_value={'version': '1.2.3'}):
            with self.assertRaises(ValueError):
                release.package(self.root / 'Harbor.app', output)
        self.assertEqual((output / 'old.zip').read_bytes(), b'old')

    def fake_app(self):
        app = self.root / 'Harbor.app'
        contents = app / 'Contents'
        contents.mkdir(parents=True)
        with (contents / 'Info.plist').open('wb') as file:
            plistlib.dump({'CFBundleIdentifier': 'com.mark455.harbor',
                          'CFBundleShortVersionString': '1.2.3',
                          'CFBundleVersion': '4', 'CFBundleExecutable': 'Harbor',
                          'LSMinimumSystemVersion': '10.15'}, file)
        binary = contents / 'MacOS/Harbor'
        binary.parent.mkdir()
        binary.write_bytes(bytes.fromhex('cffaedfe') + b'fake executable')
        return app

    def test_verify_rejects_single_architecture(self):
        app = self.fake_app()
        with patch.object(release, 'run', return_value='arm64'):
            with self.assertRaisesRegex(ValueError, 'Universal binary required'):
                release.verify(app, self.root)

    def test_verify_rejects_wrong_app_version(self):
        app = self.fake_app()
        (self.root / 'pubspec.yaml').write_text('version: 1.2.4+5\n')
        with self.assertRaisesRegex(ValueError, 'version does not match'):
            release.verify(app, self.root)

    def test_verify_checks_signature_after_architectures(self):
        app = self.fake_app()
        with patch.object(release, 'run', return_value='arm64 x86_64') as command:
            result = release.verify(app, self.root)
        self.assertEqual(result['bundle_id'], 'com.mark455.harbor')
        self.assertEqual(command.call_args.args[:4],
                         ('/usr/bin/codesign', '--verify', '--deep', '--strict'))


if __name__ == '__main__':
    unittest.main()
