#!/usr/bin/env python3
"""Verify version/signing/entitlement parity of an exported Apple app, offline."""
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def entitlements(app):
    return plistlib.loads(command('/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)))


def verify_app(app, version, build, expected_family=None):
    info_path = app / ('Contents/Info.plist' if (app / 'Contents').is_dir() else 'Info.plist')
    info = plistlib.loads(info_path.read_bytes())
    require(info['CFBundleShortVersionString'] == version, f'{app.name}: version mismatch')
    require(info['CFBundleVersion'] == build, f'{app.name}: build mismatch')
    if expected_family:
        require(set(info['UIDeviceFamily']) == expected_family, 'Mobile export must support both iPhone and iPad')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    return info, entitlements(app)


def verify_mobile(export, version, build):
    ipas = list(export.glob('*.ipa'))
    require(len(ipas) == 1, 'Expected exactly one exported IPA')
    with tempfile.TemporaryDirectory(prefix='monk-export-check-') as temporary:
        root = pathlib.Path(temporary)
        with zipfile.ZipFile(ipas[0]) as archive:
            # Never allow an archive member to escape this temporary directory.
            for item in archive.infolist():
                require((root / item.filename).resolve().is_relative_to(root.resolve()), 'Unsafe IPA path')
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(ipas[0]), str(root)], check=True)
        apps = list((root / 'Payload').glob('*.app'))
        require(len(apps) == 1, 'Expected one main app in IPA')
        app = apps[0]
        info, grants = verify_app(app, version, build, {1, 2})
        require(grants.get('get-task-allow') is not True, 'Export is development-signed')
        require(grants.get('aps-environment') == 'production', 'Production APNs entitlement missing')
        require(grants.get('com.apple.developer.icloud-container-environment') == 'Production', 'Production CloudKit entitlement missing')
        require(info.get('MonkCloudKitContainerIdentifier') in grants.get('com.apple.developer.icloud-container-identifiers', []), 'Runtime CloudKit container is not signed into the app')
        require('CloudKit' in grants.get('com.apple.developer.icloud-services', []), 'CloudKit service entitlement missing')
        require(grants.get('com.apple.developer.family-controls') is True, 'Family Controls entitlement missing')
        expected_ids = {info['CFBundleIdentifier'] + suffix for suffix in ['.HardBlockShieldUIExtension', '.DeviceActivityMonitor']}
        extensions = list((app / 'PlugIns').glob('*.appex'))
        require(len(extensions) == 2, 'Expected both Screen Time extensions')
        actual_ids = set()
        groups = set(grants.get('com.apple.security.application-groups', []))
        require(bool(groups), 'App Group entitlement missing')
        require(info.get('MonkAppGroupIdentifier') in groups, 'Runtime App Group is not signed into the app')
        for extension in extensions:
            extension_info, extension_grants = verify_app(extension, version, build)
            actual_ids.add(extension_info['CFBundleIdentifier'])
            require(extension_grants.get('com.apple.developer.family-controls') is True, f'{extension.name}: Family Controls missing')
            require(set(extension_grants.get('com.apple.security.application-groups', [])) == groups, f'{extension.name}: App Group differs')
            require(extension_info.get('MonkAppGroupIdentifier') in groups, f'{extension.name}: runtime App Group differs')
        require(actual_ids == expected_ids, 'Extension bundle IDs do not belong to the mobile app')


def verify_mac(export, version, build):
    apps = list(export.glob('*.app'))
    require(len(apps) == 1, 'Expected exactly one exported Mac app')
    app = apps[0]
    info, grants = verify_app(app, version, build)
    require(grants.get('com.apple.developer.icloud-container-environment') == 'Production', 'Production CloudKit entitlement missing')
    require(grants.get('com.apple.security.automation.apple-events') is True, 'Automation entitlement missing')
    require(not any(grants.get(key) is True for key in ['get-task-allow', 'com.apple.security.get-task-allow', 'com.apple.security.cs.get-task-allow']), 'Debug task access must not ship')
    require(grants.get('com.apple.security.cs.disable-library-validation') is not True, 'Debug library-validation exception must not ship')
    signature = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(app)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stderr.decode()
    require('Authority=Developer ID Application:' in signature, 'App is not Developer ID Application signed')
    require(re.search(r'flags=.*\bruntime\b', signature) is not None, 'Hardened runtime missing')
    require((app / 'Contents/embedded.provisionprofile').is_file(), 'Developer ID provisioning profile required for CloudKit')
    profile = plistlib.loads(command('/usr/bin/security', 'cms', '-D', '-i', str(app / 'Contents/embedded.provisionprofile')))
    permitted = profile.get('Entitlements', {})
    containers = set(grants.get('com.apple.developer.icloud-container-identifiers', []))
    require(bool(containers), 'CloudKit container missing')
    require(info.get('MonkCloudKitContainerIdentifier') in containers, 'Runtime CloudKit container is not signed into the app')
    require('CloudKit' in grants.get('com.apple.developer.icloud-services', []), 'CloudKit service entitlement missing')
    require(containers <= set(permitted.get('com.apple.developer.icloud-container-identifiers', [])), 'Provisioning profile does not authorize signed CloudKit container')


def main():
    require(len(sys.argv) == 4 and sys.argv[1] in {'mobile', 'mac'}, 'usage: verify_export.py {mobile|mac} EXPORT_DIR BUILD_NUMBER')
    root = pathlib.Path(__file__).resolve().parents[1]
    version = json.loads((root / 'release/1.0.0.json').read_text())['version']
    export = pathlib.Path(sys.argv[2]).resolve()
    build = sys.argv[3]
    require(export.is_dir(), 'Export directory does not exist')
    (verify_mobile if sys.argv[1] == 'mobile' else verify_mac)(export, version, build)
    print(f'Verified {sys.argv[1]} export {version} ({build}); device acceptance and notarization remain separate gates.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        sys.exit(f'Export verification failed: {error}')
