#!/usr/bin/env python3
"""Validate the version, Apple target membership, privacy and release contracts.

This check deliberately needs neither Xcode nor Apple credentials. It does not
claim that signing, CloudKit Production, or real-device enforcement has passed.
"""
import json
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(path):
    return (ROOT / path).read_text()


def object_block(project, identifier):
    match = re.search(r'\t\t' + re.escape(identifier) + r' /\*[^\n]*\*/ = \{\n(.*?)\n\t\t\};', project, re.S)
    require(match is not None, f'Missing Xcode object {identifier}')
    return match.group(1)


def assignments(path):
    result = {}
    for line in text(path).splitlines():
        match = re.fullmatch(r'([A-Z][A-Z_0-9]*)\s*=\s*(.*?)\s*', line)
        if match:
            result[match.group(1)] = match.group(2)
    return result


def validate():
    manifest = json.loads(text('release/1.0.0.json'))
    versions = assignments('Configurations/Version.xcconfig')
    require(re.fullmatch(r'\d+\.\d+\.\d+', versions.get('MONK_VERSION', '')), 'MONK_VERSION must be major.minor.patch')
    require(manifest['version'] == versions['MONK_VERSION'], 'Release manifest and version config differ')
    for name in ['MONK_MOBILE_BUILD', 'MONK_MAC_BUILD']:
        require(re.fullmatch(r'[1-9][0-9]*', versions.get(name, '')), f'{name} must be a positive integer')
    require('#include "Version.xcconfig"' in text('Configurations/Monk.xcconfig'), 'Common config must include the version config')
    require(manifest['status'] in {'unreleased', 'released'}, 'Unknown release status')
    require(set(manifest['platforms']) == {'iphone', 'ipad', 'mac'}, 'Manifest must identify all three platform releases')
    require(manifest['platforms']['iphone']['target'] == manifest['platforms']['ipad']['target'] == 'Monk', 'iPhone/iPad must share the universal target')
    require(manifest['platforms']['mac']['target'] == 'MonkMac', 'Mac target mismatch')
    if manifest['status'] == 'released':
        require(all(p['readyForDistribution'] for p in manifest['platforms'].values()), 'Released platforms must be signed off')
        require(all(manifest['evidence'].get(gate) for gate in manifest['requiredEvidence']), 'A released manifest must link evidence for every gate')
    project = text('Monk.xcodeproj/project.pbxproj')
    configurations = {
        'MONK_MOBILE_BUILD': ['7420C2682E5CE57400784214', '7420C2692E5CE57400784214', '74F1E0312FFF5FE200784214', '74F1E0322FFF5FE200784214', 'C10000000000000000000025', 'C10000000000000000000026'],
        'MONK_MAC_BUILD': ['A10000000000000000000008', 'A10000000000000000000009', 'B10000000000000000000008', 'B10000000000000000000009'],
    }
    for counter, ids in configurations.items():
        for identifier in ids:
            block = object_block(project, identifier)
            require('MARKETING_VERSION = "$(MONK_VERSION)";' in block, f'{identifier}: version not centralized')
            require(f'CURRENT_PROJECT_VERSION = "$({counter})";' in block, f'{identifier}: incorrect platform build counter')
    for path in ['HardBlockShieldExtension/Info.plist', 'MonkDeviceActivityMonitor/Info.plist', 'MonkMac/Info.plist']:
        info = plistlib.loads((ROOT / path).read_bytes())
        require(info['CFBundleShortVersionString'] == '$(MARKETING_VERSION)', f'{path}: version hardcoded')
        require(info['CFBundleVersion'] == '$(CURRENT_PROJECT_VERSION)', f'{path}: build hardcoded')
    for identifier in configurations['MONK_MOBILE_BUILD']:
        require('TARGETED_DEVICE_FAMILY = "1,2";' in object_block(project, identifier), 'Mobile app/extensions must support iPhone and iPad')
    for identifier in ['7420C2652E5CE57400784214', '7420C2662E5CE57400784214']:
        require('baseConfigurationReference = K10000000000000000000006' in object_block(project, identifier), 'Root configurations must inherit Monk.xcconfig')
    source_phases = [object_block(project, identifier) for identifier in ['7420C2422E5CE57200784214', 'A10000000000000000000004']]
    shared_paths = ['Shared/MonkConfiguration.swift', 'Shared/CrossDeviceApplication.swift', 'Shared/CrossDeviceApplicationCatalog.swift', 'Shared/FocusSyncState.swift', 'Shared/CloudKitSyncOutbox.swift']
    for path in shared_paths:
        require((ROOT / path).is_file(), f'Shared contract source missing: {path}')
        require(all(f'{path} in Sources' in phase for phase in source_phases), f'{path} must compile in both apps')
    mac_scheme = ET.parse(ROOT / 'Monk.xcodeproj/xcshareddata/xcschemes/MonkMac.xcscheme').getroot()
    tests = mac_scheme.findall('./TestAction/Testables/TestableReference/BuildableReference')
    require(any(t.get('BlueprintName') == 'MonkMacTests' for t in tests), 'Shared Mac scheme must run MonkMacTests')
    require(mac_scheme.find('ArchiveAction').get('buildConfiguration') == 'Release', 'Mac archives must use Release')
    require(mac_scheme.find('./TestAction/EnvironmentVariables/EnvironmentVariable[@key="MONK_TESTING"]').get('value') == '1', 'Tests must disable real app enforcement startup')
    mobile_scheme = ET.parse(ROOT / 'Monk.xcodeproj/xcshareddata/xcschemes/Monk.xcscheme').getroot()
    require(mobile_scheme.find('ArchiveAction').get('buildConfiguration') == 'Release', 'Mobile archives must use Release')
    mobile_entitlements = plistlib.loads((ROOT / 'Monk/Monk.entitlements').read_bytes())
    mac_entitlements = plistlib.loads((ROOT / 'MonkMac/MonkMac.entitlements').read_bytes())
    require(mobile_entitlements['com.apple.developer.icloud-container-identifiers'] == mac_entitlements['com.apple.developer.icloud-container-identifiers'] == ['$(MONK_CLOUDKIT_CONTAINER)'], 'Apps must share configured CloudKit container')
    for path in ['Monk/Monk.entitlements', 'HardBlockShieldExtension/HardBlockShieldExtension.entitlements', 'MonkDeviceActivityMonitor/MonkDeviceActivityMonitor.entitlements']:
        grants = plistlib.loads((ROOT / path).read_bytes())
        require(grants.get('com.apple.developer.family-controls') is True, f'{path}: Family Controls missing')
        require(grants.get('com.apple.security.application-groups') == ['$(MONK_APP_GROUP)'], f'{path}: App Group mismatch')
    require(mac_entitlements.get('com.apple.security.app-sandbox') is not True, 'Mac enforcement release is direct distribution, not sandboxed')
    require(mac_entitlements.get('com.apple.security.automation.apple-events') is True, 'Mac Automation entitlement missing')
    require(mac_entitlements.get('com.apple.security.cs.disable-library-validation') is not True, 'Debug exception must not ship')
    for path in ['Monk/PrivacyInfo.xcprivacy', 'MonkMac/PrivacyInfo.xcprivacy']:
        privacy = plistlib.loads((ROOT / path).read_bytes())
        require(privacy['NSPrivacyTracking'] is False, f'{path}: tracking must remain disabled')
    for path in list(ROOT.rglob('*.plist')) + list(ROOT.rglob('*.entitlements')):
        if not any(part in {'.git', '.derived-data', 'build', 'DerivedData', '.build'} for part in path.parts):
            plistlib.loads(path.read_bytes())
    print(f'Repository contracts validated for Monk {manifest["version"]} ({manifest["status"]}). Signing, device and Production gates are not certified.')


if __name__ == '__main__':
    try:
        validate()
    except (ValueError, KeyError, AttributeError, ET.ParseError, plistlib.InvalidFileException) as error:
        sys.exit(f'Repository validation failed: {error}')
