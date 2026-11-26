#!/usr/bin/env python3
"""scripts/siri-target.py on copies of the real Xcode project: it passes today's and fails each way
a pbxproj edit could drop Siri from the release app."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).with_name("siri-target.py")
IOS = Path(__file__).resolve().parent.parent / "app/ios"
PROVIDER_BUILD = "51A1E0082EF0000000000000 /* SnacklistIntents.swift in Sources */,"
CATALOG_BUILD = "51A1E00C2EF0000000000000 /* AppShortcuts.xcstrings in Resources */,"


class SiriTarget(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.ios = Path(tmp.name)
        shutil.copytree(IOS / "Runner.xcodeproj", self.ios / "Runner.xcodeproj")
        shutil.copytree(IOS / "Runner/AppIntents", self.ios / "Runner/AppIntents")
        self.pbxproj = self.ios / "Runner.xcodeproj/project.pbxproj"

    def edit(self, old: str, new: str) -> None:
        text = self.pbxproj.read_text()
        self.assertEqual(text.count(old), 1, old)
        self.pbxproj.write_text(text.replace(old, new))

    def sources_of(self, target: str) -> str:
        """The `files = (` line of the target's Sources phase, found by the phase id."""
        text = self.pbxproj.read_text()
        block = text[text.index(f"/* {target} */ = {{\n\t\t\tisa = PBXNativeTarget;") :]
        phase = block[block.index("buildPhases = (") :].split("/* Sources */")[0].split()[-1]
        start = text.index(f"\t\t{phase} /* Sources */ = {{")
        return text[start : text.index("files = (\n", start) + len("files = (\n")]

    def run_check(self) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, CHECK, self.ios], capture_output=True, text=True)

    def assertFails(self, needle: str) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(needle, result.stderr)

    def test_the_real_project_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_the_provider_only_in_the_tests_fails(self):
        self.edit(f"\t\t\t\t{PROVIDER_BUILD}\n", "")
        head = self.sources_of("RunnerTests")
        self.edit(head, f"{head}\t\t\t\t{PROVIDER_BUILD}\n")
        self.assertFails("SnacklistIntents.swift (the AppShortcutsProvider, Siri's code) is not in the Runner target's Sources")

    def test_any_intents_file_missing_from_the_app_fails(self):
        self.edit("\t\t\t\t92A1E0022EF0000000000000 /* SiriKitLists.swift in Sources */,\n", "")
        self.assertFails("SiriKitLists.swift (Siri's code) is not in the Runner target's Sources")

    def test_the_phrase_catalog_outside_the_app_fails(self):
        self.edit(f"\t\t\t\t{CATALOG_BUILD}\n", "")
        self.assertFails("AppShortcuts.xcstrings is not in the Runner target's Resources")

    def test_a_second_provider_in_the_widget_fails(self):
        head = self.sources_of("HomeWidget")
        self.edit(head, f"{head}\t\t\t\t{PROVIDER_BUILD.replace('51A1E008', '51A1E0FF')}\n")
        self.edit(
            "/* Begin PBXBuildFile section */\n",
            "/* Begin PBXBuildFile section */\n\t\t51A1E0FF2EF0000000000000 /* SnacklistIntents.swift in Sources */ = "
            "{isa = PBXBuildFile; fileRef = 51A1E0072EF0000000000000 /* SnacklistIntents.swift */; };\n",
        )
        self.assertFails("target HomeWidget also compiles SnacklistIntents.swift")


if __name__ == "__main__":
    unittest.main()
