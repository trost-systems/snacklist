#!/usr/bin/env bash
# The app's own Swift (the on-device speech check, job 4b; the Siri intents, job 51) compiles for
# the simulator, which also validates the App Shortcut phrases. The built app carries the app icon
# (light, dark, tinted, and the Icon Composer layered icon) and the launch screen's colour and mark
# from design/app-icon/build.mjs. Then RunnerTests runs on the newest iPhone simulator installed,
# its StoreKit tests against the local test store the scheme's Test action names (Snacklist.storekit;
# DECISIONS 127, job 306). Needs macOS.
# One build serves the checks and the tests: building twice (flutter build ios, then xcodebuild
# test) let a slow runner hit the job's 40-minute limit (job 118, scripts/ci-ios-phases.sh).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
require_ci_flutter
cd "$REPO_ROOT/app"
log "phase config"
flutter build ios --config-only --simulator --debug
# The newest iPhone, never on a one-device runtime such as Xcode 27's iOS-27-2-iPhone19-4 (job 306).
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.rsplit("iOS", 1)[-1])]
ios = sorted((r for r in devices if re.search(r"\.SimRuntime\.iOS-[0-9-]+$", r)), key=version, reverse=True)
print(next(d["udid"] for r in ios for d in devices[r] if d["name"].startswith("iPhone")))')"
log "phase build"
derived=build/ios/derived
xcodebuild build-for-testing -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=NO
log "phase checks"
app="$derived/Build/Products/Debug-iphonesimulator/Runner.app"
# The Home Screen widget ships inside the app (docs/HOME_WIDGETS.md, scripts/ios/home-widget-target.rb).
[[ -f $app/PlugIns/HomeWidget.appex/HomeWidget ]] ||
  { echo "ios: Runner.app does not embed PlugIns/HomeWidget.appex" >&2; exit 1; }
# App Store Connect rejects an extension whose version differs from the app's.
for key in CFBundleShortVersionString CFBundleVersion; do
  app_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Info.plist")"
  widget_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/PlugIns/HomeWidget.appex/Info.plist")"
  [[ $app_value == "$widget_value" ]] ||
    { echo "ios: HomeWidget.appex $key is '$widget_value', the app's '$app_value'" >&2; exit 1; }
done
# Siri matches the App Shortcut phrases with the training Xcode writes into Metadata.appintents:
# German knows the app name the way German Siri may write it, but never as "… Liste", Reminders'
# grammar (job 97), and no language may train an unresolved InfoPlist.strings variable as the
# name (job 71).
ssu="$app/Metadata.appintents/root.ssu.yaml"
grep -q -E 'Sn(ä|\\u00[Ee]4|\\x[Ee]4)cklist' "$ssu" || { echo "ios: $ssu does not train the German alternative app names (de.lproj/InfoPlist.strings)" >&2; exit 1; }
if grep -n -i -E "sn(a|ä|e)ck ?-?liste" "$ssu"; then echo "ios: $ssu trains a German app name ending in Liste" >&2; exit 1; fi
if grep -n SNACKLIST_NAME "$ssu"; then echo "ios: $ssu trains a variable as the app name; give every lproj an InfoPlist.strings" >&2; exit 1; fi
# App Store Connect wants SiriKit example phrases in every language for each declared intent
# (ITMS-90626): the built app must carry them, not only the source tree.
"$REPO_ROOT/scripts/siri-vocabulary.py" "$app"
# And the App Shortcuts Siri matches: Metadata.appintents and the de/en phrase sets (job 97).
"$REPO_ROOT/scripts/app-shortcuts-bundle.py" "$app"
xcrun --sdk iphonesimulator assetutil --info "$app/Assets.car" >build/ios/assets.json
# Each wanted asset needs a rendition whose JSON mentions every listed word (the appearance).
python3 - build/ios/assets.json <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))
want = {'AppIcon': ['Dark', 'Tint'], 'LaunchBackground': ['Dark'], 'LaunchImage': ['Dark']}
missing = []
for name, words in want.items():
    found = [json.dumps(e) for e in entries if e.get('Name') == name]
    missing += [f'{name} ({w})' for w in words if not any(w in f for f in found)] if found else [name]
# The Icon Composer bundle (AppIcon.icon, the iOS 26 layered icon) compiles to icon stacks.
stacks = {e.get('Appearance') for e in entries if e.get('Name') == 'AppIcon' and e.get('AssetType') == 'IconImageStack'}
missing += [f'AppIcon.icon stack ({a})' for a in ('UIAppearanceLight', 'UIAppearanceDark', 'ISAppearanceTintable') if a not in stacks]
if missing:
    sys.exit('Assets.car lacks ' + ', '.join(missing) + '; build/ios/assets.json has the catalog')
print('Assets.car has', ', '.join(want), 'and the AppIcon.icon stacks')
PY

# Booting while it builds made the build 3 to 7 min slower on 3-core runners (job 118).
log "phase boot $udid"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

log "phase tests"
result=/tmp/snacklist-runner-tests.xcresult
rm -rf "$result"
xcodebuild test-without-building -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "id=$udid" -derivedDataPath "$derived" -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -resultBundlePath "$result" || status=$?
[[ -d $result ]] || exit "${status:-1}"
xcrun xcresulttool get test-results tests --path "$result" >/tmp/snacklist-runner-tests.json
# Every case must pass. A skipped StoreKit case means storekitd did not take Snacklist.storekit: on
# iOS 27 without the scheme's StoreKit configuration, Ask to Buy waited on the App Store sandbox
# (job 306); before, iOS 26.4 refused it to the ad-hoc signed build (DECISIONS 127).
python3 - <<'PY'
import json, sys
cases = []
def walk(node):
    if node.get("nodeType") == "Test Case":
        cases.append(node)
    for child in node.get("children", []):
        walk(child)
for node in json.load(open("/tmp/snacklist-runner-tests.json"))["testNodes"]:
    walk(node)
results = [c.get("result") for c in cases]
print("passed %d, failed %d, skipped %d" % tuple(results.count(r) for r in ("Passed", "Failed", "Skipped")))
for case in cases:
    if case.get("result") != "Passed":
        why = "; ".join(c.get("name", "") for c in case.get("children", []))
        print("%s %s: %s" % (case.get("result"), case.get("nodeIdentifier"), why))
storekit = [c for c in cases if "LifetimeStoreKitTests" in c.get("nodeIdentifier", "")]
if not cases or any(r != "Passed" for r in results) or len(storekit) < 3:
    sys.exit("ios: every RunnerTests case must pass, the %d LifetimeStoreKitTests among them" % len(storekit))
PY
exit "${status:-0}"
