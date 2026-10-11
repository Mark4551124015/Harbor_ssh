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

    def test_wrong_original_tag_cannot_mutate_releases(self):
        with patch.object(migration, 'api', return_value={'draft': False}) as api, \
                patch.object(migration, 'commit_for', return_value='wrong'):
            with self.assertRaises(ValueError):
                migration.migrate('1.0.2-beta', '1.0.2-beta', 'commit', 4)
            self.assertEqual(api.call_count, 1)

    def test_existing_canonical_tag_cannot_be_moved(self):
        with patch.object(migration, 'api', return_value={'draft': False}) as api, \
                patch.object(migration, 'commit_for', side_effect=['commit', 'different']), \
                patch.object(migration, 'release_notes_for', return_value='English notes'):
            with self.assertRaises(ValueError):
                migration.migrate('1.0.2-beta', '1.0.2-beta', 'commit', 4)
            self.assertEqual(api.call_count, 1)

    def test_cancel_only_rebuilds_for_exact_migrated_aliases(self):
        commit = migration.MIGRATIONS[-1][2]
        runs = {'workflow_runs': [
            {'id': 1, 'event': 'push', 'status': 'queued', 'head_branch': 'v1.0.2-beta', 'head_sha': commit},
            {'id': 2, 'event': 'push', 'status': 'completed', 'head_branch': 'v1.0.2-beta', 'head_sha': commit},
            {'id': 3, 'event': 'push', 'status': 'in_progress', 'head_branch': 'main', 'head_sha': commit},
            {'id': 4, 'event': 'push', 'status': 'queued', 'head_branch': 'v1.0.2-beta', 'head_sha': 'different'},
        ]}
        with patch.object(migration, 'api', return_value=runs) as api:
            migration.cancel_duplicate_builds()
            self.assertEqual(api.call_count, 2)
            self.assertEqual(api.call_args.args, ('/actions/runs/1/cancel', 'POST'))

    def test_already_canonical_release_only_changes_title_and_notes(self):
        source = {'id': 7, 'draft': False, 'prerelease': True}
        with patch.object(migration, 'api', return_value=source) as api, \
                patch.object(migration, 'commit_for', return_value='commit'), \
                patch.object(migration, 'release_notes_for', return_value='English notes'):
            migration.migrate('v1.0.0-beta.1', '1.0.0-beta.1', 'commit', 1)
            self.assertEqual(api.call_args.args, ('/releases/7', 'PATCH', {
                'name': '1.0.0-beta.1', 'body': 'English notes', 'make_latest': 'false'}))
