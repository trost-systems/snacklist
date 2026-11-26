#!/usr/bin/env python3
"""scripts/app-shortcuts-bundle.py on fixture apps: it passes a complete one and fails each gap."""
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

CHECK = Path(__file__).with_name("app-shortcuts-bundle.py")
NEGATIVE = "Add something to my shopping list"
NAMES = {"de": ["Snack List", "Snäcklist", "Snecklist"], "en": ["Snack List", "Snack-list", "Snack Lists"]}
TEMPLATES = {
    "AddItemsIntent": ["Add to ${applicationName}", "Add ${item} to ${applicationName}"],
    "ReadListIntent": ["What's on my ${applicationName}"],
    "OpenListIntent": ["Show my ${applicationName}"],
}


def actionsdata(templates=TEMPLATES, negatives=(NEGATIVE,), entity="ItemSuggestion") -> dict:
    return {
        "actions": {name: {} for name in TEMPLATES},
        "entities": {entity: {}},
        "negativePhrases": [{"phrase": {"key": n, "alternatives": []}} for n in negatives],
        "autoShortcuts": [
            {"actionIdentifier": name, "phraseTemplates": [{"key": k, "alternatives": []} for k in keys]}
            for name, keys in templates.items()
        ],
    }


class AppShortcutsBundle(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.app = Path(tmp.name) / "Runner.app"
        self.write_actions(actionsdata())
        for lang in ("de", "en"):
            self.write_phrases(lang, self.complete(lang))
        self.write_info()
        for lang in ("de", "en"):
            self.write_model(lang, b"model")

    @staticmethod
    def complete(lang: str) -> dict:
        table = {f"#!SET#!_{k}[0]": k.replace("Add", lang) for keys in TEMPLATES.values() for k in keys}
        table[NEGATIVE] = NEGATIVE if lang == "en" else f"{lang}: shopping list"
        return table

    def write_info(self, spoken="Snacklist", names=NAMES) -> None:
        variables = [f"SNACKLIST_NAME_{i}" for i in (1, 2, 3)]
        with (self.app / "Info.plist").open("wb") as f:
            plistlib.dump(
                {"CFBundleSpokenName": spoken, "INAlternativeAppNames": [{"INAlternativeAppName": v} for v in variables]},
                f, fmt=plistlib.FMT_BINARY)
        for lang in ("Base", "de", "en"):
            path = self.app / f"{lang}.lproj/InfoPlist.strings"
            path.parent.mkdir(parents=True, exist_ok=True)
            table = dict(zip(variables, names.get(lang, names["en"])), CFBundleSpokenName=spoken)
            with path.open("wb") as f:
                plistlib.dump(table, f, fmt=plistlib.FMT_BINARY)

    def write_model(self, lang: str, data: bytes) -> None:
        path = self.app / f"{lang}.lproj/nlu.appintents/nlu.lzfse"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def write_actions(self, data: dict) -> None:
        path = self.app / "Metadata.appintents/extract.actionsdata"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def write_phrases(self, lang: str, table: dict) -> None:
        path = self.app / f"{lang}.lproj/AppShortcuts.strings"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as f:
            plistlib.dump(table, f, fmt=plistlib.FMT_BINARY)

    def run_check(self, target=None) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, CHECK, target or self.app], capture_output=True, text=True)

    def assertFails(self, needle: str) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(needle, result.stderr)

    def test_a_complete_app_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OpenListIntent", result.stdout)

    def test_a_signed_ipa_passes(self):
        ipa = self.app.parent / "Snacklist.ipa"
        with zipfile.ZipFile(ipa, "w") as z:
            for f in self.app.rglob("*"):
                z.write(f, Path("Payload") / f.relative_to(self.app.parent))
        result = self.run_check(ipa)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_metadata_fails(self):
        (self.app / "Metadata.appintents/extract.actionsdata").unlink()
        self.assertFails("extract.actionsdata is missing")

    def test_a_missing_shortcut_fails(self):
        self.write_actions(actionsdata({k: v for k, v in TEMPLATES.items() if k != "OpenListIntent"}))
        self.assertFails("no App Shortcut for OpenListIntent")

    def test_a_phrase_without_the_app_name_fails(self):
        self.write_actions(actionsdata({**TEMPLATES, "OpenListIntent": ["Show my list"]}))
        self.assertFails('"Show my list" does not name the app')

    def test_no_negative_phrases_fails(self):
        self.write_actions(actionsdata(negatives=()))
        self.assertFails("no negative phrases")

    def test_no_item_entity_fails(self):
        self.write_actions(actionsdata(entity="Other"))
        self.assertFails("no entity ItemSuggestion")

    def test_a_language_without_phrases_fails(self):
        (self.app / "de.lproj/AppShortcuts.strings").unlink()
        self.assertFails("de.lproj has no compiled AppShortcuts.strings")

    def test_a_compiled_phrase_without_the_app_name_fails(self):
        self.write_phrases("en", {f"#!SET#!_{k}[0]": "Add milk" for keys in TEMPLATES.values() for k in keys})
        self.assertFails('en.lproj AppShortcuts: "Add milk" does not name the app')

    def test_a_compiled_item_phrase_that_lost_its_item_fails(self):
        table = {f"#!SET#!_{k}[0]": k for keys in TEMPLATES.values() for k in keys}
        table["#!SET#!_Add ${item} to ${applicationName}[1]"] = "Füge etwas zu ${applicationName} hinzu"
        self.write_phrases("de", table)
        self.assertFails('"Füge etwas zu ${applicationName} hinzu" must keep ${item}')

    def test_a_negative_phrase_without_german_phrases_fails(self):
        table = self.complete("de")
        del table[NEGATIVE]
        self.write_phrases("de", table)
        self.assertFails(f'de.lproj AppShortcuts: no phrases for the negative "{NEGATIVE}"')

    def test_a_german_negative_left_in_english_fails(self):
        self.write_phrases("de", {**self.complete("de"), NEGATIVE: NEGATIVE})
        self.assertFails(f'de.lproj AppShortcuts: the negative "{NEGATIVE}" is not translated')

    def test_a_negative_phrase_that_names_the_app_fails(self):
        self.write_phrases("en", {**self.complete("en"), f"#!SET#!_{NEGATIVE}[1]": "Add milk to Snacklist"})
        self.assertFails('negative "Add milk to Snacklist" names the app')

    def test_a_german_name_ending_in_liste_fails(self):
        self.write_info(names={**NAMES, "de": ["Snack List", "Snackliste", "Snecklist"]})
        self.assertFails('de.lproj: alternative app name "Snackliste" ends in Liste')

    def test_the_spoken_name_must_be_snacklist(self):
        self.write_info(spoken="Snack List")
        self.assertFails('CFBundleSpokenName is "Snack List", not "Snacklist"')

    def test_a_text_strings_table_reads_too(self):
        lines = [f'"{k}" = "{v}";' for k, v in self.complete("de").items()]
        (self.app / "de.lproj/AppShortcuts.strings").write_text("\n".join(lines), encoding="utf-16")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_language_without_its_phrase_model_fails(self):
        (self.app / "de.lproj/nlu.appintents/nlu.lzfse").unlink()
        self.assertFails("Siri has no de phrase model")
        self.write_model("de", b"model")
        self.write_model("en", b"")
        self.assertFails("Siri has no en phrase model")

    def test_a_template_without_german_phrases_fails(self):
        self.write_phrases("de", {"#!SET#!_Add to ${applicationName}[0]": "Füge etwas zu ${applicationName} hinzu"})
        self.assertFails('de.lproj AppShortcuts: no phrases for "Show my ${applicationName}"')


if __name__ == "__main__":
    unittest.main()
