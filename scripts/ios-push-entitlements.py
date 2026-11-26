#!/usr/bin/env python3
"""A store build must be able to receive push (docs/PUSH.md, "Native", job 468).

TestFlight and App Store devices talk to the production APNs: the signed app needs
aps-environment = production, which signing takes from the App Store profile, not from
Runner.entitlements (that says development, for Xcode's debug builds). Firebase's setup for
Flutter also wants the remote-notification background mode in Info.plist.

Reads the entitlements the signature carries (the embedded blob, magic 0xfade7171), so it needs
no codesign and runs anywhere.

Usage: scripts/ios-push-entitlements.py <Snacklist.ipa | Runner.app>
"""
import plistlib
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

ENTITLEMENTS_MAGIC = b"\xfa\xde\x71\x71"


def signed_entitlements(binary: bytes) -> list[dict]:
    """Every XML entitlements blob in the binary's code signature (one per architecture)."""
    found = []
    at = binary.find(ENTITLEMENTS_MAGIC)
    while at != -1:
        header = binary[at + 4:at + 8]
        if len(header) < 4:
            break
        (length,) = struct.unpack(">I", header)
        try:
            value = plistlib.loads(binary[at + 8:at + length])
        except Exception:
            value = None
        if isinstance(value, dict):
            found.append(value)
        at = binary.find(ENTITLEMENTS_MAGIC, at + 4)
    return found


def check(app: Path) -> list[str]:
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    problems = []
    if "remote-notification" not in info.get("UIBackgroundModes", []):
        problems.append(f"{app.name}/Info.plist: UIBackgroundModes lacks remote-notification")
    executable = app / info.get("CFBundleExecutable", app.stem)
    blobs = signed_entitlements(executable.read_bytes())
    if not blobs:
        problems.append(f"{executable.name} carries no signed entitlements")
    for blob in blobs:
        environment = blob.get("aps-environment")
        if environment != "production":
            problems.append(
                f"{executable.name} is signed with aps-environment {environment!r}, not 'production': "
                "TestFlight devices would get no push (is the App Store profile's Push capability on?)"
            )
    return problems


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    with tempfile.TemporaryDirectory() as tmp:
        if target.suffix == ".ipa":
            with zipfile.ZipFile(target) as ipa:
                ipa.extractall(tmp)
            apps = sorted(Path(tmp).glob("Payload/*.app"))
            if not apps:
                print(f"ios-push-entitlements: {target} has no Payload/*.app", file=sys.stderr)
                return 1
            target = apps[0]
        problems = check(target)
    if problems:
        print("\n".join(f"ios-push-entitlements: {p}" for p in problems), file=sys.stderr)
        return 1
    print("ios-push-entitlements: aps-environment production, remote-notification background mode")
    return 0


if __name__ == "__main__":
    sys.exit(main())
