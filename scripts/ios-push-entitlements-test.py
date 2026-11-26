#!/usr/bin/env python3
"""scripts/ios-push-entitlements.py on fixture apps: a store-signed one passes, each gap fails."""
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

CHECK = Path(__file__).with_name("ios-push-entitlements.py")


def signature(entitlements: dict) -> bytes:
    """A code signature's entitlements blob as codesign writes it: magic, length, XML."""
    xml = plistlib.dumps(entitlements, fmt=plistlib.FMT_XML)
    return b"\xfa\xde\x0c\xc0" + b"\x00" * 16 + b"\xfa\xde\x71\x71" + struct.pack(">I", len(xml) + 8) + xml


class IosPushEntitlements(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def app(self, entitlements: dict | None, background_modes=("remote-notification",)) -> Path:
        app = self.root / "Runner.app"
        app.mkdir(exist_ok=True)
        info = {"CFBundleExecutable": "Runner"}
        if background_modes is not None:
            info["UIBackgroundModes"] = list(background_modes)
        with (app / "Info.plist").open("wb") as f:
            plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
        code = b"\xcf\xfa\xed\xfe" + b"\x00" * 64
        (app / "Runner").write_bytes(code + (signature(entitlements) if entitlements is not None else b""))
        return app

    def ipa(self, app: Path) -> Path:
        ipa = self.root / "Snacklist.ipa"
        with zipfile.ZipFile(ipa, "w") as z:
            for f in app.rglob("*"):
                z.write(f, Path("Payload") / f.relative_to(app.parent))
        return ipa

    def run_check(self, target: Path) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, CHECK, target], capture_output=True, text=True)

    def assert_fails(self, target: Path, *words: str) -> None:
        result = self.run_check(target)
        self.assertEqual(result.returncode, 1, result.stdout)
        for word in words:
            self.assertIn(word, result.stderr)

    def test_store_signed_app_passes(self):
        app = self.app({"aps-environment": "production", "com.apple.developer.siri": True})
        for target in (app, self.ipa(app)):
            result = self.run_check(target)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_development_signed_app_fails(self):
        app = self.app({"aps-environment": "development"})
        self.assert_fails(self.ipa(app), "aps-environment 'development', not 'production'")

    def test_app_without_push_entitlement_fails(self):
        self.assert_fails(self.app({"com.apple.developer.siri": True}), "aps-environment None")

    def test_unsigned_app_fails(self):
        self.assert_fails(self.app(None), "carries no signed entitlements")

    def test_magic_at_the_very_end_is_skipped(self):
        app = self.app({"aps-environment": "production"})
        with (app / "Runner").open("ab") as f:
            f.write(b"\xfa\xde\x71\x71\x00")
        self.assertEqual(self.run_check(app).returncode, 0)

    def test_missing_background_mode_fails(self):
        app = self.app({"aps-environment": "production"}, background_modes=("fetch",))
        self.assert_fails(app, "UIBackgroundModes lacks remote-notification")
        self.assert_fails(self.app({"aps-environment": "production"}, background_modes=None), "remote-notification")


if __name__ == "__main__":
    unittest.main()
