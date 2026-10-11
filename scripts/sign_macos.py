#!/usr/bin/env python3
"""Developer ID sign and notarize a built app, using an isolated temporary keychain."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

MACHO = {bytes.fromhex(value) for value in ['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}


def invoke(*args, capture=False):
    return subprocess.run([str(arg) for arg in args], check=True,
                          capture_output=capture, text=True)


def main():
    names = ['MACOS_CERTIFICATE_BASE64', 'MACOS_CERTIFICATE_PASSWORD',
             'MACOS_SIGNING_IDENTITY', 'APPLE_ID', 'APPLE_APP_PASSWORD', 'APPLE_TEAM_ID']
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise ValueError('Missing signing secrets: ' + ', '.join(missing))
    app = Path(sys.argv[1]).resolve()
    if not (app / 'Contents/Info.plist').is_file():
        raise ValueError('Expected an application bundle.')
    identity = os.environ['MACOS_SIGNING_IDENTITY']
    if not identity.startswith('Developer ID Application:'):
        raise ValueError('Use a Developer ID Application identity, not App Store signing.')
    with tempfile.TemporaryDirectory(prefix='harbor-sign-') as temporary:
        temp = Path(temporary)
        certificate, keychain = temp / 'certificate.p12', temp / 'signing.keychain-db'
        certificate.write_bytes(base64.b64decode(os.environ['MACOS_CERTIFICATE_BASE64'], validate=True))
        certificate.chmod(0o600)
        password = secrets.token_urlsafe(32)
        invoke('security', 'create-keychain', '-p', password, keychain)
        try:
            invoke('security', 'set-keychain-settings', '-lut', '3600', keychain)
            invoke('security', 'unlock-keychain', '-p', password, keychain)
            invoke('security', 'import', certificate, '-k', keychain, '-P',
                   os.environ['MACOS_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            invoke('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
                   '-s', '-k', password, keychain, capture=True)
            certificate.unlink()
            signing = ['codesign', '--force', '--timestamp', '--options', 'runtime',
                       '--sign', identity, '--keychain', keychain]
            # Sign nested Mach-O code and framework envelopes from the inside out.
            files = sorted((path for path in app.rglob('*') if path.is_file() and not path.is_symlink()),
                           key=lambda path: len(path.parts), reverse=True)
            for path in files:
                with path.open('rb') as file:
                    magic = file.read(4)
                if magic in MACHO:
                    invoke(*signing, path)
            envelopes = sorted((path for path in app.rglob('*') if path.is_dir()
                                and not path.is_symlink() and path.suffix in ['.framework', '.app', '.xpc']),
                               key=lambda path: len(path.parts), reverse=True)
            for path in envelopes:
                invoke(*signing, path)
            entitlements = Path(__file__).resolve().parent / 'distribution.entitlements'
            invoke(*signing, '--entitlements', entitlements, app)
            invoke('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
            payload = temp / 'Harbor-notarization.zip'
            invoke('ditto', '-c', '-k', '--keepParent', app, payload)
            # Store credentials in the temporary keychain so the password is not repeated in logs.
            invoke('xcrun', 'notarytool', 'store-credentials', 'harbor-notary', '--keychain', keychain,
                   '--apple-id', os.environ['APPLE_ID'], '--password', os.environ['APPLE_APP_PASSWORD'],
                   '--team-id', os.environ['APPLE_TEAM_ID'], capture=True)
            response = invoke('xcrun', 'notarytool', 'submit', payload, '--keychain', keychain,
                              '--keychain-profile', 'harbor-notary', '--wait', '--timeout', '30m',
                              '--output-format', 'json', capture=True)
            result = json.loads(response.stdout)
            if result.get('status') != 'Accepted':
                raise ValueError(f'Apple notarization failed: {result.get("status")}, submission {result.get("id")}')
            invoke('xcrun', 'stapler', 'staple', app)
            invoke('xcrun', 'stapler', 'validate', app)
            invoke('spctl', '--assess', '--type', 'execute', app)
        finally:
            invoke('security', 'delete-keychain', keychain, capture=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Don't echo command arguments containing signing/notary credentials.
        print(f'Signing failed ({type(error).__name__}). Check secrets and the preceding tool output.', file=sys.stderr)
        sys.exit(1)
