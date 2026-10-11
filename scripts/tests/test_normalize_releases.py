import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import normalize_releases as migration


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.files = {}
        for suffix in ['zip', 'dmg']:
            name = f'Harbor-1.0.2-beta-macos-universal-unsigned.{suffix}'
            path = root / name
            path.write_bytes(suffix.encode())
            self.files[name] = path
        manifest = root / 'release-manifest.json'
        manifest.write_text(json.dumps({'version': '1.0.2-beta', 'build': '4', 'source_commit': 'commit'}))
        self.files[manifest.name] = manifest
        sums = root / 'SHA256SUMS.txt'
        sums.write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}\n'
                                for name, path in self.files.items()))
        self.files[sums.name] = sums

    def test_assets_match_original_release(self):
        migration.validate_assets(self.files, '1.0.2-beta', 'commit', 4)
        with self.assertRaises(ValueError):
            migration.validate_assets(self.files, '1.0.2-beta', 'different-commit', 4)
        with self.assertRaises(ValueError):
            migration.validate_assets(self.files, '1.0.2-beta', 'commit', 5)

    def test_tampered_or_missing_assets_rejected(self):
        archive = self.files['Harbor-1.0.2-beta-macos-universal-unsigned.zip']
        archive.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            migration.validate_assets(self.files, '1.0.2-beta', 'commit', 4)
        del self.files[archive.name]
        with self.assertRaises(ValueError):
            migration.validate_assets(self.files, '1.0.2-beta', 'commit', 4)

    def test_asset_comparison_requires_equal_hashes_and_sizes(self):
        names = list(self.files)
        assets = [{'name': name, 'size': 10, 'digest': 'sha256:' + 'a' * 64} for name in names]
        source = {'assets': assets}
        target = {'assets': [dict(asset) for asset in assets]}
        migration.matching_assets(source, target, '1.0.2-beta')
        target['assets'][0]['digest'] = 'sha256:' + 'b' * 64
        with self.assertRaises(ValueError):
            migration.matching_assets(source, target, '1.0.2-beta')
        target['assets'][0]['digest'] = 'sha256:' + 'a' * 64
        target['assets'][0]['size'] = 11
        with self.assertRaises(ValueError):
            migration.matching_assets(source, target, '1.0.2-beta')

    def test_all_destinations_are_checked_before_any_deletion(self):
        target = {'id': 1, 'draft': False}
        source = {'id': 2, 'draft': False}
        with patch.object(migration, 'MIGRATIONS', [
                ('old-one', '1.0.1-beta', 'first', 3),
                ('old-two', '1.0.2-beta', 'second', 4)]), \
                patch.object(migration, 'api', side_effect=[target, source, None]) as api, \
                patch.object(migration, 'commit_for', return_value='first'), \
                patch.object(migration, 'matching_assets'), \
                patch.object(migration, 'release_notes_for', return_value='English notes'):
            with self.assertRaises(ValueError):
                migration.normalize()
            self.assertTrue(all(len(call.args) == 1 for call in api.call_args_list))

    def test_cleanup_only_deletes_verified_superseded_release(self):
        target = {'id': 1, 'draft': False}
        source = {'id': 2, 'tag_name': '1.0.2-beta', 'draft': False}
        with patch.object(migration, 'MIGRATIONS', [('1.0.2-beta', '1.0.2-beta', 'commit', 4)]), \
                patch.object(migration, 'api', side_effect=[target, source, {}, {}, {'tag_name': 'v1.0.2-beta'}]) as api, \
                patch.object(migration, 'commit_for', return_value='commit'), \
                patch.object(migration, 'matching_assets') as compare, \
                patch.object(migration, 'release_notes_for', return_value='English notes'):
            migration.normalize()
            compare.assert_called_once_with(source, target, '1.0.2-beta')
            deletes = [call.args for call in api.call_args_list if len(call.args) > 1 and call.args[1] == 'DELETE']
            self.assertEqual(deletes, [('/releases/2', 'DELETE')])

    def test_check_mode_does_not_write(self):
        target = {'id': 1, 'draft': False}
        with patch.object(migration, 'MIGRATIONS', [('v1.0.0-beta.1', '1.0.0-beta.1', 'commit', 1)]), \
                patch.object(migration, 'api', return_value=target) as api, \
                patch.object(migration, 'commit_for', return_value='commit'), \
                patch.object(migration, 'release_notes_for', return_value='English notes'):
            migration.normalize(check_only=True)
            self.assertEqual(api.call_count, 1)
