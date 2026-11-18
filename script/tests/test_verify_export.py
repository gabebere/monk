"""Release checks reject unsafe or mismatched exports without accessing credentials."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'verify_export.py'
SPEC = importlib.util.spec_from_file_location('verify_export', SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ExportVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='monk-export-tests-')
        self.root = Path(self.temporary.name)
        self.app = self.root / 'MonkOS.app'
        (self.app / 'Contents').mkdir(parents=True)
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '4',
            'CFBundleIdentifier': 'com.example.Monk.mac',
            'MonkCloudKitContainerIdentifier': 'iCloud.com.example.Monk',
        }))
        (self.app / 'Contents/embedded.provisionprofile').write_bytes(b'fixture')
        self.grants = {
            'com.apple.developer.icloud-container-environment': 'Production',
            'com.apple.developer.icloud-container-identifiers': ['iCloud.com.example.Monk'],
            'com.apple.security.automation.apple-events': True,
            'com.apple.developer.icloud-services': ['CloudKit'],
        }
        self.profile = {'Entitlements': {
            'com.apple.developer.icloud-container-identifiers': ['iCloud.com.example.Monk'],
        }}

    def tearDown(self):
        self.temporary.cleanup()

    def run_verification(self):
        def command(*args):
            if args[0] == '/usr/bin/security':
                return plistlib.dumps(self.profile)
            raise AssertionError(args)
        signature = b'Authority=Developer ID Application: Test (EXAMPLE123)\nCodeDirectory v=20500 size=10 flags=0x10000(runtime)\n'
        with patch.object(release, 'entitlements', return_value=self.grants), \
             patch.object(release, 'command', side_effect=command), \
             patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'', signature)):
            release.verify_mac(self.root, '1.0.0', '4')

    def test_production_cloudkit_developer_id_export_is_accepted(self):
        self.run_verification()

    def test_development_cloudkit_export_is_rejected(self):
        self.grants['com.apple.developer.icloud-container-environment'] = 'Development'
        with self.assertRaisesRegex(ValueError, 'Production CloudKit'):
            self.run_verification()

    def test_runtime_container_must_match_the_signed_entitlement(self):
        self.grants['com.apple.developer.icloud-container-identifiers'] = ['iCloud.another']
        with self.assertRaisesRegex(ValueError, 'Runtime CloudKit'):
            self.run_verification()

    def test_debug_library_validation_exception_is_rejected(self):
        self.grants['com.apple.security.cs.disable-library-validation'] = True
        with self.assertRaisesRegex(ValueError, 'library-validation'):
            self.run_verification()

    def test_debug_task_access_is_rejected(self):
        self.grants['com.apple.security.get-task-allow'] = True
        with self.assertRaisesRegex(ValueError, 'Debug task access'):
            self.run_verification()

    def test_cloudkit_profile_for_another_container_is_rejected(self):
        self.profile['Entitlements']['com.apple.developer.icloud-container-identifiers'] = ['iCloud.another']
        with self.assertRaisesRegex(ValueError, 'does not authorize'):
            self.run_verification()

    def test_wrong_build_is_rejected_before_signing_commands(self):
        with patch.object(release.subprocess, 'run') as codesign:
            with self.assertRaisesRegex(ValueError, 'build mismatch'):
                release.verify_app(self.app, '1.0.0', '5')
        codesign.assert_not_called()

    def test_mobile_export_must_include_both_device_families(self):
        app = self.root / 'Monk.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '4',
            'UIDeviceFamily': [1],
        }))
        with patch.object(release.subprocess, 'run') as codesign:
            with self.assertRaisesRegex(ValueError, 'both iPhone and iPad'):
                release.verify_app(app, '1.0.0', '4', {1, 2})
        codesign.assert_not_called()


if __name__ == '__main__':
    unittest.main()
