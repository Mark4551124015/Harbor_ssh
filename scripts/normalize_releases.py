#!/usr/bin/env python3
"""Validate canonical releases and remove superseded release entries."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from release import release_notes_for

REPO = 'Mark4551124015/Harbor_ssh'
API = f'https://api.github.com/repos/{REPO}'
MIGRATIONS = [
    ('v1.0.0-beta.1', '1.0.0-beta.1', '32807db2c1160eb5f83ef64b856bb6c141d9539f', 1),
    ('beta-1.0.1', '1.0.1-beta', '1b554e5550d09281bb1ce2fda94c15efd1f9e566', 3),
    ('1.0.2-beta', '1.0.2-beta', 'a90488b840107c82991ba0b7c0233d304da9333d', 4),
]


def api(path, method='GET', payload=None, binary=None):
    url = path if path.startswith('https://') else API + path
    if not url.startswith((API + '/', f'https://uploads.github.com/repos/{REPO}/')):
        raise ValueError('Unexpected GitHub endpoint.')
    headers = {'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
               'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Harbor-release-migration'}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers['Content-Type'] = 'application/json'
    if binary is not None:
        data = binary
        headers['Content-Type'] = 'application/octet-stream'
    try:
        with urlopen(Request(url, data=data, headers=headers, method=method), timeout=55) as response:
            content = response.read()
            return json.loads(content) if content else {}
    except HTTPError as error:
        if error.code == 404 and method == 'GET':
            return None
        raise


def commit_for(tag):
    ref = api('/git/ref/tags/' + quote(tag, safe=''))
    if ref is None:
        return None
    obj = ref['object']
    while obj['type'] == 'tag':
        obj = api('/git/tags/' + obj['sha'])['object']
    if obj['type'] != 'commit':
        raise ValueError('A release tag must point to a commit.')
    return obj['sha']


def validate_assets(files, version, commit, build):
    expected = {
        f'Harbor-{version}-macos-universal-unsigned.zip',
        f'Harbor-{version}-macos-universal-unsigned.dmg',
        'release-manifest.json', 'SHA256SUMS.txt',
    }
    if set(files) != expected:
        raise ValueError(f'Unexpected assets for {version}: {set(files)}')
    sums = files['SHA256SUMS.txt'].read_text().splitlines()
    checked = set()
    for line in sums:
        checksum, name = line.split('  ', 1)
        if name not in expected - {'SHA256SUMS.txt'}:
            raise ValueError('Unexpected checksum entry.')
        if hashlib.sha256(files[name].read_bytes()).hexdigest() != checksum:
            raise ValueError(f'Checksum mismatch: {name}')
        checked.add(name)
    if checked != expected - {'SHA256SUMS.txt'}:
        raise ValueError('Missing checksums.')
    manifest = json.loads(files['release-manifest.json'].read_text())
    if (manifest['version'], manifest['source_commit'], str(manifest['build'])) != (version, commit, str(build)):
        raise ValueError('Release manifest does not match the original source.')


def matching_assets(source, target, version):
    expected = {
        f'Harbor-{version}-macos-universal-unsigned.zip',
        f'Harbor-{version}-macos-universal-unsigned.dmg',
        'release-manifest.json', 'SHA256SUMS.txt',
    }
    original = {asset['name']: asset for asset in source['assets']}
    canonical = {asset['name']: asset for asset in target['assets']}
    if set(original) != expected or set(canonical) != expected:
        raise ValueError('Both releases must contain every expected asset.')
    for name in expected:
        digest = original[name].get('digest')
        if (not isinstance(digest, str) or not digest.startswith('sha256:')
                or len(digest) != 71 or digest != canonical[name].get('digest')
                or original[name]['size'] != canonical[name]['size']):
            raise ValueError(f'Canonical asset does not match: {name}')


def normalize(check_only=False):
    verified = []
    # Validate every destination before changing or deleting any release.
    for old_tag, version, commit, _ in MIGRATIONS:
        tag = f'v{version}'
        target = api('/releases/tags/' + quote(tag, safe=''))
        if target is None or target['draft'] or commit_for(tag) != commit:
            raise ValueError(f'Canonical release/tag is not ready: {tag}')
        source = None if old_tag == tag else api('/releases/tags/' + quote(old_tag, safe=''))
        if source is not None:
            if source['draft'] or commit_for(old_tag) != commit:
                raise ValueError(f'Original release/tag does not match: {old_tag}')
            matching_assets(source, target, version)
        notes = release_notes_for(version)
        verified.append((target, source, version, notes))
        print(f'Verified canonical release and original assets: {tag}', flush=True)
    if check_only:
        return
    for target, source, version, notes in verified:
        api(f'/releases/{target["id"]}', 'PATCH', {
            'name': version, 'body': notes,
            'make_latest': 'true' if version == '1.0.2-beta' else 'false',
        })
        if source is not None:
            api(f'/releases/{source["id"]}', 'DELETE')
            print(f'Removed superseded release: {source["tag_name"]}', flush=True)
    if api('/releases/latest')['tag_name'] != 'v1.0.2-beta':
        raise ValueError('Canonical current release is not Latest.')
    print('Latest: v1.0.2-beta', flush=True)


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate without changing any releases.')
    args = parser.parse_args()
    if os.environ.get('GITHUB_REPOSITORY') != REPO:
        raise ValueError('Run this migration only in the Harbor repository.')
    normalize(check_only=args.check)


if __name__ == '__main__':
    main()
