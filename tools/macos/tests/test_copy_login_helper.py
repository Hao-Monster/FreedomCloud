"""Exercise build-only copying with mocked macOS commands, never Keychain."""

import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "copy_login_helper.py"
SPEC = importlib.util.spec_from_file_location("copy_login_helper", SCRIPT)
helper_script = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper_script)


class CopyLoginHelperTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.products = Path(self.temporary.name)
        self.resources = self.products / "LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources"
        self.resources.mkdir(parents=True)
        self.archive = self.resources / "LaunchAtLoginHelper.zip"
        self.archive.write_bytes(b"verified-test-fixture")
        (self.resources / "LaunchAtLogin.entitlements").write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
        self.environment = {
            "BUILT_PRODUCTS_DIR": str(self.products),
            "CONTENTS_FOLDER_PATH": "FlClashX.app/Contents",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.follow.clash",
            "MACOSX_DEPLOYMENT_TARGET": "11.0",
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGN_ENTITLEMENTS": "Runner/Release.entitlements",
        }
        self.helper = self.products / "FlClashX.app/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
        self.commands = []
        self.fail_codesign = False
        self.fail_verify = False
        self.fail_copy = False
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        checksum_patch = patch.dict(helper_script.HELPER_CHECKSUMS, {"LaunchAtLoginHelper": digest})
        checksum_patch.start()
        self.addCleanup(checksum_patch.stop)
        command_patch = patch.object(helper_script.subprocess, "run", side_effect=self.run_command)
        command_patch.start()
        self.addCleanup(command_patch.stop)

    def run_command(self, command, *, check):
        self.assertTrue(check)
        self.commands.append(command)
        if command[0] == "/usr/bin/ditto":
            self.assertEqual(command[1:4], ["-x", "-k", str(self.archive)])
            if self.fail_copy:
                raise subprocess.CalledProcessError(1, command)
            contents = self.helper / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            (contents / "MacOS/LaunchAtLoginHelper").write_bytes(b"fixture-executable")
            (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "upstream.helper", "CFBundleExecutable": "LaunchAtLoginHelper"}))
        elif command[0] == "/usr/bin/codesign":
            if self.fail_codesign or (self.fail_verify and "--verify" in command):
                raise subprocess.CalledProcessError(1, command)
        else:
            self.fail(f"Unexpected external command: {command}")

    def test_unsigned_copies_helper_without_signing(self):
        helper_script.copy_helper(self.environment)
        self.assertTrue((self.helper / "Contents/MacOS/LaunchAtLoginHelper").is_file())
        info = plistlib.loads((self.helper / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.follow.clash-LaunchAtLoginHelper")
        self.assertEqual(len(self.commands), 1)
        self.assertEqual(self.commands[0][0], "/usr/bin/ditto")
        self.assertTrue((self.resources / "LaunchAtLogin.entitlements").is_file())

    def test_debug_host_keeps_separate_helper_identity(self):
        self.environment["PRODUCT_BUNDLE_IDENTIFIER"] = "com.follow.clash.debug"
        helper_script.copy_helper(self.environment)
        info = plistlib.loads((self.helper / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.follow.clash.debug-LaunchAtLoginHelper")

    def test_older_deployment_uses_verified_runtime_helper(self):
        self.environment["MACOSX_DEPLOYMENT_TARGET"] = "10.13"
        self.archive = self.resources / "LaunchAtLoginHelper-with-runtime.zip"
        self.archive.write_bytes(b"runtime-test-fixture")
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with patch.dict(helper_script.HELPER_CHECKSUMS, {"LaunchAtLoginHelper-with-runtime": digest}):
            helper_script.copy_helper(self.environment)
        self.assertEqual(self.commands[0][3], str(self.archive))

    def test_runtime_helper_selection_at_deployment_boundary(self):
        for target, helper_name in [("10.14.3", "LaunchAtLoginHelper-with-runtime"), ("10.14.4", "LaunchAtLoginHelper")]:
            with self.subTest(target=target):
                self.environment["MACOSX_DEPLOYMENT_TARGET"] = target
                self.archive = self.resources / f"{helper_name}.zip"
                self.archive.write_bytes(b"boundary-test-fixture")
                digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
                with patch.dict(helper_script.HELPER_CHECKSUMS, {helper_name: digest}):
                    helper_script.copy_helper(self.environment)
                self.assertEqual(self.commands[-1][3], str(self.archive))

    def test_signed_copy_preserves_entitlements_runtime_and_verifies(self):
        self.environment.update(CODE_SIGNING_ALLOWED="YES", EXPANDED_CODE_SIGN_IDENTITY_NAME="Developer ID Application: Fixture (TEAM)")
        helper_script.copy_helper(self.environment)
        self.assertEqual(len(self.commands), 3)
        self.assertIn(f"--entitlements={self.resources / 'LaunchAtLogin.entitlements'}", self.commands[1])
        self.assertIn("--options=runtime", self.commands[1])
        self.assertIn("--sign=Developer ID Application: Fixture (TEAM)", self.commands[1])
        self.assertEqual(self.commands[1][-1], str(self.helper))
        self.assertEqual(self.commands[2][1:4], ["--verify", "--strict", "--verbose=2"])

    def test_missing_identity_fails_before_copy(self):
        self.environment["CODE_SIGNING_ALLOWED"] = "YES"
        self.helper.mkdir(parents=True)
        marker = self.helper / "keep.txt"
        marker.write_text("existing build")
        with self.assertRaisesRegex(ValueError, "EXPANDED_CODE_SIGN_IDENTITY_NAME"):
            helper_script.copy_helper(self.environment)
        self.assertEqual(self.commands, [])
        self.assertEqual(marker.read_text(), "existing build")

    def test_copy_failure_propagates_before_signing(self):
        self.fail_copy = True
        with self.assertRaises(subprocess.CalledProcessError):
            helper_script.copy_helper(self.environment)
        self.assertEqual(len(self.commands), 1)

    def test_unspecified_signing_does_not_fall_back_to_unsigned(self):
        self.environment.pop("CODE_SIGNING_ALLOWED")
        with self.assertRaisesRegex(ValueError, "EXPANDED_CODE_SIGN_IDENTITY_NAME"):
            helper_script.copy_helper(self.environment)
        self.assertEqual(self.commands, [])

    def test_signing_failure_propagates_without_unsigned_fallback(self):
        self.environment.update(CODE_SIGNING_ALLOWED="YES", EXPANDED_CODE_SIGN_IDENTITY_NAME="Fixture")
        self.fail_codesign = True
        with self.assertRaises(subprocess.CalledProcessError):
            helper_script.copy_helper(self.environment)
        self.assertEqual(len(self.commands), 2)

    def test_verification_failure_propagates(self):
        self.environment.update(CODE_SIGNING_ALLOWED="YES", EXPANDED_CODE_SIGN_IDENTITY_NAME="Fixture")
        self.fail_verify = True
        with self.assertRaises(subprocess.CalledProcessError):
            helper_script.copy_helper(self.environment)
        self.assertEqual(len(self.commands), 3)

    def test_wrong_checksum_preserves_existing_helper(self):
        self.helper.mkdir(parents=True)
        marker = self.helper / "keep.txt"
        marker.write_text("existing build")
        self.archive.write_bytes(b"modified archive")
        with self.assertRaisesRegex(ValueError, "Wrong checksum"):
            helper_script.copy_helper(self.environment)
        self.assertEqual(marker.read_text(), "existing build")
        self.assertEqual(self.commands, [])

    def test_missing_entitlements_rejected(self):
        (self.resources / "LaunchAtLogin.entitlements").unlink()
        with self.assertRaisesRegex(ValueError, "entitlements"):
            helper_script.copy_helper(self.environment)
        self.assertEqual(self.commands, [])

    def test_output_path_cannot_escape_build_products(self):
        self.environment["CONTENTS_FOLDER_PATH"] = "../FlClashX.app/Contents"
        with self.assertRaisesRegex(ValueError, "CONTENTS_FOLDER_PATH"):
            helper_script.copy_helper(self.environment)
        self.assertEqual(self.commands, [])

    def test_cli_reports_nonzero_for_invalid_build_environment(self):
        environment = os.environ.copy()
        environment.pop("BUILT_PRODUCTS_DIR", None)
        with subprocess.Popen([sys.executable, str(SCRIPT)], env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            stdout, stderr = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 1)
        self.assertEqual(stdout, "")
        self.assertIn("error: LaunchAtLogin helper preparation failed", stderr)
        self.assertEqual(self.commands, [])


if __name__ == "__main__":
    unittest.main()
