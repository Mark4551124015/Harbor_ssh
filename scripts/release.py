#!/usr/bin/env python3
"""Validate, verify and package Harbor. Uses only Python's standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

from sign_macos import MACHO

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?'


def version(root=ROOT):
    match = re.search(r'^version:\s*(\S+)\s*$', (root / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('pubspec.yaml must contain a version.')
    value = match[1]
    release, separator, build = value.partition('+')
    if not re.fullmatch(VERSION_PATTERN, release) or not separator or not build.isdecimal() or int(build) < 1:
        raise ValueError('Expected version x.y.z[-prerelease]+positiveBuildNumber.')
    return release, build


def preflight(tag, official=False, root=ROOT):
    release, build = version(root)
    allowed_tags = {f'v{release}'}
    if release.endswith('-beta'):
        allowed_tags.add(f'beta-{release.removesuffix("-beta")}')
    if tag not in allowed_tags:
        raise ValueError(f'Tag must match pubspec version: v{release}')
    app_info = (root / 'macos/Runner/Configs/AppInfo.xcconfig').read_text()
    if 'com.example' in app_info:
        raise ValueError('Replace template bundle identifier and copyright.')
    if official and not any((root / name).is_file() for name in ['LICENSE', 'LICENSE.md', 'LICENSE.txt']):
        raise ValueError('Choose and add a LICENSE before an official signed release.')
    return release, build


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def verify(app, root=ROOT):
    app = Path(app).resolve()
    with (app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    release, build = version(root)
    # CFBundleShortVersionString must be numeric; prerelease is in archive/tag names.
    if info['CFBundleShortVersionString'] != release.split('-')[0] or str(info['CFBundleVersion']) != build:
        raise ValueError('Built application version does not match pubspec.yaml.')
    if info['CFBundleIdentifier'] != 'com.mark455.harbor':
        raise ValueError('Unexpected application bundle identifier.')
    binaries = []
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as file:
                if file.read(4) in MACHO:
                    binaries.append(path)
    if not binaries:
        raise ValueError('Application contains no Mach-O binaries.')
    architectures = {}
    for binary in binaries:
        arch = run('/usr/bin/lipo', '-archs', binary).split()
        if not {'arm64', 'x86_64'}.issubset(arch):
            raise ValueError(f'Universal binary required: {binary.name}: {arch}')
        architectures[str(binary.relative_to(app))] = arch
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    return {'version': release, 'build': build, 'bundle_id': info['CFBundleIdentifier'],
            'minimum_macos': info['LSMinimumSystemVersion'], 'architectures': architectures}


def checksums(files):
    return ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n'
                   for path in sorted(files))


def package(app, output, notarized=False):
    app, output = Path(app).resolve(), Path(output).resolve()
    metadata = verify(app)
    if notarized:
        run('/usr/bin/xcrun', 'stapler', 'validate', app)
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', app)
    output.mkdir(parents=True, exist_ok=True)
    # Output is deliberately not deleted: refuse to mix artifacts from two releases.
    if any(output.iterdir()):
        raise ValueError(f'Output directory must be empty: {output}')
    suffix = '' if notarized else '-unsigned'
    name = f'Harbor-{metadata["version"]}-macos-universal{suffix}'
    archive, dmg = output / f'{name}.zip', output / f'{name}.dmg'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    with tempfile.TemporaryDirectory(prefix='harbor-dmg-') as temp:
        staging = Path(temp)
        run('/usr/bin/ditto', app, staging / 'Harbor.app')
        (staging / 'Applications').symlink_to('/Applications')
        (staging / 'Read Me.txt').write_text(
            'Drag Harbor.app to Applications.\n' +
            ('Developer ID signed and notarized app.\n' if notarized else
             'Unsigned test build. macOS Gatekeeper may block opening.\n') +
            'Before editing complex SSH config, keep a separate backup.\n')
        run('/usr/bin/hdiutil', 'create', '-volname', 'Harbor', '-srcfolder', staging,
            '-ov', '-format', 'UDZO', dmg)
    run('/usr/bin/hdiutil', 'verify', dmg)
    metadata.update({'notarized': notarized,
                     'source_commit': run('git', '-C', ROOT, 'rev-parse', 'HEAD'),
                     'source_dirty': bool(run('git', '-C', ROOT, 'status', '--porcelain')),
                     'flutter_version': json.loads((ROOT / '.fvmrc').read_text())['flutter']})
    manifest = output / 'release-manifest.json'
    manifest.write_text(json.dumps(metadata, indent=2) + '\n')
    (output / 'SHA256SUMS.txt').write_text(checksums([archive, dmg, manifest]))
    print(json.dumps(metadata, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('build-name')
    pre = sub.add_parser('preflight')
    pre.add_argument('--tag', required=True)
    pre.add_argument('--official', action='store_true')
    adhoc = sub.add_parser('adhoc')
    adhoc.add_argument('app', type=Path)
    check = sub.add_parser('verify')
    check.add_argument('app', type=Path)
    pack = sub.add_parser('package')
    pack.add_argument('app', type=Path)
    pack.add_argument('--output', type=Path, default=Path('dist'))
    pack.add_argument('--notarized', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'build-name':
            print(version()[0].split('-')[0])
        elif args.command == 'preflight':
            print(preflight(args.tag, args.official))
        elif args.command == 'adhoc':
            run('/usr/bin/codesign', '--force', '--deep', '--sign', '-', args.app.resolve())
            print(json.dumps(verify(args.app), indent=2))
        elif args.command == 'verify':
            print(json.dumps(verify(args.app), indent=2))
        else:
            package(args.app, args.output, args.notarized)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Release check failed: {error}\n')


if __name__ == '__main__':
    main()
