#!/usr/bin/env python3
"""Add canonical release tags while preserving every existing download URL."""
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
            return json.load(response)
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


def migrate(old_tag, version, commit, build):
    tag = f'v{version}'
    source = api('/releases/tags/' + quote(old_tag, safe=''))
    if source is None or source['draft'] or commit_for(old_tag) != commit:
        raise ValueError(f'Original release/tag does not match: {old_tag}')
    notes = release_notes_for(version)
    if tag == old_tag:
        api(f'/releases/{source["id"]}', 'PATCH', {'name': version, 'body': notes, 'make_latest': 'false'})
        print(f'Normalized title: {tag}', flush=True)
        return
    current = commit_for(tag)
    if current is None:
        # GITHUB_TOKEN-created refs do not trigger another release build.
        api('/git/refs', 'POST', {'ref': f'refs/tags/{tag}', 'sha': commit})
    elif current != commit:
        raise ValueError(f'Refusing to move existing tag {tag}.')
    with tempfile.TemporaryDirectory(prefix='harbor-release-migration-') as directory:
        files = {}
        for asset in source['assets']:
            name = asset['name']
            if Path(name).name != name:
                raise ValueError('Invalid asset filename.')
            url = asset['browser_download_url']
            if not url.startswith(f'https://github.com/{REPO}/releases/download/{old_tag}/'):
                raise ValueError('Invalid original download URL.')
            path = Path(directory) / name
            with urlopen(url, timeout=55) as response, path.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            files[name] = path
        validate_assets(files, version, commit, build)
        target = api('/releases/tags/' + quote(tag, safe=''))
        if target is None:
            target = api('/releases', 'POST', {
                'tag_name': tag, 'name': version, 'body': notes, 'draft': True,
                'prerelease': source['prerelease'], 'make_latest': 'false',
            })
        existing = {asset['name']: asset for asset in target['assets']}
        for name, path in files.items():
            if name in existing:
                # Validate existing bytes before treating a retry as complete.
                with urlopen(existing[name]['browser_download_url'], timeout=55) as response:
                    if hashlib.sha256(response.read()).digest() != hashlib.sha256(path.read_bytes()).digest():
                        raise ValueError(f'Refusing to replace existing asset {name}.')
                continue
            api(target['upload_url'].split('{')[0] + '?name=' + quote(name, safe=''),
                'POST', binary=path.read_bytes())
        api(f'/releases/{target["id"]}', 'PATCH', {
            'name': version, 'body': notes, 'draft': False,
            'prerelease': source['prerelease'], 'make_latest': 'false',
        })
    legacy_notes = (f'This is a legacy download entry. Use [{version}]'
                    f'(https://github.com/{REPO}/releases/tag/{tag}) for the canonical release.\n\n' + notes)
    api(f'/releases/{source["id"]}', 'PATCH', {
        'name': f'{version} (legacy links)', 'body': legacy_notes, 'make_latest': 'false',
    })
    print(f'Published {tag}; preserved {old_tag} and all original assets.', flush=True)


def main():
    if os.environ.get('GITHUB_REPOSITORY') != REPO:
        raise ValueError('Run this migration only in the Harbor repository.')
    for migration in MIGRATIONS:
        migrate(*migration)
    latest = api('/releases/tags/v1.0.2-beta')
    api(f'/releases/{latest["id"]}', 'PATCH', {'make_latest': 'true'})
    if api('/releases/latest')['tag_name'] != 'v1.0.2-beta':
        raise ValueError('Canonical current release is not Latest.')
    print('Latest: v1.0.2-beta', flush=True)


if __name__ == '__main__':
    main()
