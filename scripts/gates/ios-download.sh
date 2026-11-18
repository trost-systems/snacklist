#!/usr/bin/env bash
# The app's own Swift (the on-device speech check, job 4b; the Siri intents, job 51) compiles for
# the simulator, which also validates the App Shortcut phrases. The built app carries the app icon
# (light, dark, tinted, and the Icon Composer layered icon) and the launch screen's colour and mark
# from design/app-icon/build.mjs. Then RunnerTests runs on the newest iPhone simulator installed,
# and its StoreKit tests on an iOS 26.2 one, downloaded while it builds, whose storekitd still gives
# the local test store to an ad-hoc signed build (DECISIONS 127, job 306). Needs macOS.
# One build serves the checks and the tests: building twice (flutter build ios, then xcodebuild
# test) let a slow runner hit the job's 40-minute limit (job 118, scripts/ci-ios-phases.sh).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
require_ci_flutter
cd "$REPO_ROOT/app"
# The StoreKit tests need storekitd to take Snacklist.storekit. From iOS 26.4 on it refuses that to
# this ad-hoc signed build ("not installed for development"); iOS 26.2's still takes it, so they
# run on a 26.2 simulator, and every one of them must pass (DECISIONS 127;
# scripts/ios-storekit-probe.sh checks other runtimes).
# The xcode-27 image ships only iOS 27 runtimes, whose storekitd answers from the sandbox's US
# storefront and never returns a purchase (job 306): the gate downloads 26.2 (8.4 GB, about 13 min)
# while it builds.
storekit_ios=26.2
storekit_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
for r in json.load(sys.stdin)["runtimes"]:
    if r["platform"] == "iOS" and r["isAvailable"] and r["version"].split(".")[:2] == sys.argv[1].split("."):
        iphones = {t["name"]: t["identifier"] for t in r["supportedDeviceTypes"] if t["productFamily"] == "iPhone"}
        name = next((n for n in ("iPhone 17 Pro", "iPhone 16 Pro", "iPhone 16") if n in iphones), list(iphones)[-1])
        print(r["identifier"], iphones[name]); break' "$storekit_ios"
}
storekit_download=/tmp/snacklist-storekit-runtime.log
if [[ -z $(storekit_runtime) ]]; then
  xcodebuild -downloadPlatform iOS -buildVersion "$storekit_ios" >"$storekit_download" 2>&1 &
  storekit_download_pid=$!
fi
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

# A runtime installed while xcodebuild tests can lose it its simulator, as a simulator created then
# did (job 127): the download ends first.
if [[ -n ${storekit_download_pid:-} ]]; then
  log "phase storekit_download"
  wait "$storekit_download_pid" || { tail -c 2000 "$storekit_download" >&2; echo "ios: downloading the iOS $storekit_ios simulator runtime failed" >&2; exit 1; }
fi
# Booting while it builds made the build 3 to 7 min slower on 3-core runners (job 118).
log "phase boot $udid"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

log "phase tests"
result=/tmp/snacklist-runner-tests.xcresult
rm -rf "$result"
xcodebuild test-without-building -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "id=$udid" -derivedDataPath "$derived" -skip-testing:RunnerTests/LifetimeStoreKitTests -parallel-testing-enabled NO \
  -resultBundlePath "$result" || status=$?
[[ -d $result ]] || exit "${status:-1}"
xcrun xcresulttool get test-results summary --path "$result" | tee /tmp/snacklist-runner-tests.json
python3 -c '
import json, sys
s = json.load(open("/tmp/snacklist-runner-tests.json"))
print("passed %s, failed %s, skipped %s" % (s.get("passedTests"), s.get("failedTests"), s.get("skippedTests")))
sys.exit(0 if s.get("result") == "Passed" and s.get("passedTests", 0) > 0 else 1)'
[[ -z ${status:-} ]] || exit "$status"

log "phase storekit_boot iOS $storekit_ios"
read -r runtime devicetype <<<"$(storekit_runtime)"
[[ -n ${runtime:-} ]] || { echo "ios: the runner image has no iOS $storekit_ios simulator runtime for the StoreKit tests; run scripts/ios-storekit-probe.sh on it to find a runtime whose storekitd takes Snacklist.storekit and set storekit_ios (DECISIONS 127)" >&2; exit 1; }
storekit_udid="$(xcrun simctl create "Snacklist StoreKit" "$devicetype" "$runtime")"
# Created and booted after the main tests: xcodebuild there lost its own simulator ("Unable to find
# a device") while this one was being created and booted (job 127).
xcrun simctl boot "$storekit_udid"
xcrun simctl bootstatus "$storekit_udid" -b

log "phase storekit_tests"
storekit_result=/tmp/snacklist-storekit-tests.xcresult
storekit_log=/tmp/snacklist-storekit-tests.log
rm -rf "$storekit_result"
# Minutes after this first boot of the runtime, an xcodebuild started on the loaded runner can see
# no simulator at all, while simctl lists this one. The default search gave up after about a
# minute ("Unable to find a device", 6 of 40 runs); xcodebuild picks the simulator up once its
# list fills, so it searches for 5 min (DECISIONS 164).
storekit_search=300
xcodebuild test-without-building -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "id=$storekit_udid,arch=arm64" -destination-timeout "$storekit_search" -derivedDataPath "$derived" \
  -only-testing:RunnerTests/LifetimeStoreKitTests -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -resultBundlePath "$storekit_result" 2>&1 | tee "$storekit_log" || status=$?
if grep -q "Unable to find a device matching the provided destination specifier" "$storekit_log"; then
  echo "ios: xcodebuild listed no iOS $storekit_ios simulator $storekit_udid within ${storekit_search} s; no StoreKit test ran (DECISIONS 164)" >&2
  exit 1
fi
[[ -d $storekit_result ]] || exit "${status:-1}"
xcrun xcresulttool get test-results tests --path "$storekit_result" >/tmp/snacklist-storekit-tests.json
python3 - "$storekit_ios" <<'PY'
import json, sys
cases = []
def walk(node):
    if node.get("nodeType") == "Test Case":
        cases.append(node)
    for child in node.get("children", []):
        walk(child)
for node in json.load(open("/tmp/snacklist-storekit-tests.json"))["testNodes"]:
    walk(node)
for case in cases:
    why = "; ".join(c.get("name", "") for c in case.get("children", [])) if case.get("result") != "Passed" else ""
    print("%s %s%s" % (case.get("result"), case.get("nodeIdentifier"), ": " + why if why else ""))
if not cases or any(c.get("result") != "Passed" for c in cases):
    sys.exit("ios: every LifetimeStoreKitTests case must pass on iOS %s (a skip means storekitd refused Snacklist.storekit)" % sys.argv[1])
PY
exit "${status:-0}"
