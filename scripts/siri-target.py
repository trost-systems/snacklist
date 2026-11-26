#!/usr/bin/env python3
"""The release app builds the Siri code and phrases, not only the tests (job 467).

Reads Runner.xcodeproj/project.pbxproj: every tracked Swift file in Runner/AppIntents (the
AppShortcutsProvider among them) is in the Runner target's Sources, the App Shortcut phrases
(AppShortcuts.xcstrings) and the dialogs (Localizable.xcstrings) are in its Resources, and no other
target compiles an AppShortcutsProvider, since iOS reads one per app. A file only in RunnerTests
still passes the Swift tests while the release app ships without it.

Usage: scripts/siri-target.py [ios-dir]
"""
import re
import sys
from pathlib import Path

APP_TARGET = "Runner"
RESOURCES = ("AppShortcuts.xcstrings", "Localizable.xcstrings")
TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"((?:[^"\\]|\\.)*)"|([{}()=;,])|([^\s{}()=;,"]+)', re.S)


def parse(text: str):
    """An old-style (OpenStep) property list, the format of project.pbxproj."""
    tokens = []
    for m in TOKEN.finditer(text):
        if m.group(1) is not None:
            tokens.append(("s", m.group(1)))
        elif m.group(2):
            tokens.append(("p", m.group(2)))
        elif m.group(3):
            tokens.append(("s", m.group(3)))
    pos = 0

    def expect(p: str) -> None:
        nonlocal pos
        if tokens[pos] != ("p", p):
            raise ValueError(f"expected {p!r} at token {pos}, got {tokens[pos]!r}")
        pos += 1

    def value():
        nonlocal pos
        kind, tok = tokens[pos]
        pos += 1
        if (kind, tok) == ("p", "{"):
            result = {}
            while tokens[pos] != ("p", "}"):
                key = value()
                expect("=")
                result[key] = value()
                expect(";")
            pos += 1
            return result
        if (kind, tok) == ("p", "("):
            items = []
            while tokens[pos] != ("p", ")"):
                items.append(value())
                if tokens[pos] == ("p", ","):
                    pos += 1
            pos += 1
            return items
        if kind == "p":
            raise ValueError(f"unexpected {tok!r} at token {pos - 1}")
        return tok

    return value()


def phase_files(objects: dict, target: dict, isa: str) -> set[str]:
    names = set()
    for phase_id in target.get("buildPhases", []):
        phase = objects.get(phase_id, {})
        if phase.get("isa") != isa:
            continue
        for build_id in phase.get("files", []):
            ref = objects.get(objects.get(build_id, {}).get("fileRef", ""), {})
            name = ref.get("path") or ref.get("name")
            if name:
                names.add(Path(name).name)
    return names


def check(ios: Path) -> list[str]:
    pbxproj = ios / "Runner.xcodeproj/project.pbxproj"
    try:
        objects = parse(pbxproj.read_text())["objects"]
    except (OSError, ValueError, KeyError, IndexError) as error:
        return [f"{pbxproj}: unreadable ({error})"]
    targets = {o.get("name"): o for o in objects.values() if o.get("isa") == "PBXNativeTarget"}
    app = targets.get(APP_TARGET)
    if app is None:
        return [f"{pbxproj}: no target {APP_TARGET}"]
    found = []
    intents = sorted((ios / "Runner/AppIntents").glob("*.swift"))
    providers = [p.name for p in intents if re.search(r":\s*AppShortcutsProvider\b", p.read_text())]
    if not providers:
        found.append(f"{ios}/Runner/AppIntents: no AppShortcutsProvider")
    sources = phase_files(objects, app, "PBXSourcesBuildPhase")
    for swift in intents:
        if swift.name not in sources:
            role = "the AppShortcutsProvider, " if swift.name in providers else ""
            found.append(
                f"{pbxproj}: Runner/AppIntents/{swift.name} ({role}Siri's code) is not in the {APP_TARGET} "
                "target's Sources; the release app would ship without it"
            )
    resources = phase_files(objects, app, "PBXResourcesBuildPhase")
    for name in RESOURCES:
        if name not in resources:
            found.append(f"{pbxproj}: {name} is not in the {APP_TARGET} target's Resources")
    for name, target in sorted(targets.items()):
        if name == APP_TARGET:
            continue
        for provider in sorted(phase_files(objects, target, "PBXSourcesBuildPhase") & set(providers)):
            found.append(f"{pbxproj}: target {name} also compiles {provider}; iOS reads one AppShortcutsProvider per app")
    return found


def main() -> int:
    ios = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "app/ios"
    found = check(ios)
    if found:
        print("\n".join(f"siri-target: {p}" for p in found), file=sys.stderr)
        return 1
    print(f"siri-target: {APP_TARGET} builds Runner/AppIntents and carries {', '.join(RESOURCES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
