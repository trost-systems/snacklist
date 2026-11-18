#!/usr/bin/env bash
# Job 86: the App Store in-app purchase review screenshot. The Premium page as the integration lock
# opens it (PW-P4, test_driver/paywall_review.dart, debug build) with the yearly plan and Lifetime at
# the German storefront's prices (24,99 EUR a year, 149,99 EUR once), once with each plan picked and its
# Buy button (out.png and out-lifetime.png). German, light,
# on a 6.7" iPhone simulator (1290x2796), status bar at 9:41. The page asks StoreKit through its
# real channel; the script prints that answer and fails unless StoreKit returned both products.
# Nothing is bought and no server is called. Needs macOS with Xcode; run by
# .github/workflows/paywall-shot.yml. Usage: ios-paywall-shot.sh [out.png]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
die() { echo "ios-paywall-shot: $*" >&2; exit 1; }
out="${1:-$REPO_ROOT/build/paywall-ios-de.png}"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
marks=/tmp/snacklist-paywall-shot
rm -rf "$marks"
mkdir -p "$marks"
cd "$REPO_ROOT/app"
flutter build ios --simulator --debug -t test_driver/paywall_review.dart

# The newest iOS runtime with a 6.7" iPhone, never a one-device runtime such as Xcode 27's
# iOS-27-2-iPhone19-4 (job 306).
read -r runtime type <<<"$(xcrun simctl list runtimes available -j | python3 -c '
import json, re, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and re.search(r"\.iOS-[0-9-]+$", r["identifier"])]
for r in sorted(ios, key=lambda r: [int(n) for n in r["version"].split(".")], reverse=True):
    types = {t["identifier"] for t in r["supportedDeviceTypes"]}
    for name in ("iPhone-16-Plus", "iPhone-15-Plus", "iPhone-15-Pro-Max", "iPhone-14-Pro-Max"):
        if "com.apple.CoreSimulator.SimDeviceType." + name in types:
            print(r["identifier"], "com.apple.CoreSimulator.SimDeviceType." + name); sys.exit()')"
[[ -n ${type:-} ]] || die "no iOS runtime on this Mac runs a 6.7\" iPhone (1290x2796)"
udid="$(xcrun simctl create "Snacklist paywall shot" "$type" "$runtime")"
log "simulator $udid ($type, $runtime)"
trap 'xcrun simctl shutdown "$udid" 2>/dev/null; xcrun simctl delete "$udid"' EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array de-DE
xcrun simctl spawn "$udid" defaults write -g AppleLocale de_DE
xcrun simctl shutdown "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$udid" com.snacklist.app
# PW-P4 has one Buy for the picked plan: the yearly plan picked (the page's default) goes to
# out.png, Lifetime picked to out-lifetime.png. The app picks Lifetime after taken-yearly.
shoot() { # plan file
  for _ in $(seq 1 60); do
    [[ -f $marks/ready-$1 ]] && break
    sleep 2
  done
  [[ -f $marks/ready-$1 ]] || die "the page did not show $1 picked after 2 min"
  log "$(cat "$marks/ready-$1")"
  xcrun simctl io "$udid" screenshot --type=png "$2"
  touch "$marks/taken-$1"
  local size
  size="$(sips -g pixelWidth -g pixelHeight "$2" | awk '/pixel/ {print $2}' | paste -sd x -)"
  [[ $size == 1290x2796 ]] || die "$2 is $size, App Store Connect wants 1290x2796"
  log "wrote $2 ($size)"
}
shoot yearly "$out"
if ! grep -Eq "^storekit: .*yearly: StorePrice" "$marks/ready-yearly" ||
  ! grep -Eq "^storekit: .*lifetime: StorePrice" "$marks/ready-yearly"; then
  die "StoreKit did not return both products"
fi
shoot lifetime "${out%.png}-lifetime.png"
