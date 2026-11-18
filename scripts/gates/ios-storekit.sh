#!/usr/bin/env bash
# Job 304: RunnerTests' StoreKit tests (LifetimeStoreKitTests), in a job of their own beside the
# ios gate's: their simulator's first boot and xcodebuild's wait for it took 6 to 18 of that
# job's 23 to 35 min (scripts/ci-ios-phases.sh). The build is the ios gate's
# (scripts/ios/build-for-testing.sh); the tests run on an iOS 26.2 simulator, whose storekitd still
# gives the local test store to an ad-hoc signed build (DECISIONS 127). Needs macOS.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
require_ci_flutter
cd "$REPO_ROOT/app"
source "$REPO_ROOT/scripts/ios/build-for-testing.sh"

# The StoreKit tests need storekitd to take Snacklist.storekit. From iOS 26.4 on it refuses that to
# this ad-hoc signed build ("not installed for development"); iOS 26.2's still takes it, so they
# run on a 26.2 simulator, and every one of them must pass (DECISIONS 127;
# scripts/ios-storekit-probe.sh checks other runtimes).
storekit_ios=26.2
log "phase storekit_boot iOS $storekit_ios"
storekit_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
for r in json.load(sys.stdin)["runtimes"]:
    if r["platform"] == "iOS" and r["isAvailable"] and r["version"].split(".")[:2] == sys.argv[1].split("."):
        iphones = {t["name"]: t["identifier"] for t in r["supportedDeviceTypes"] if t["productFamily"] == "iPhone"}
        name = next((n for n in ("iPhone 17 Pro", "iPhone 16 Pro", "iPhone 16") if n in iphones), list(iphones)[-1])
        print(r["identifier"], iphones[name]); break' "$storekit_ios"
}
read -r runtime devicetype <<<"$(storekit_runtime)"
# Downloading it here would cost several GB inside the job's 40 minutes: fail and say so.
[[ -n ${runtime:-} ]] || { echo "ios-storekit: the runner image has no iOS $storekit_ios simulator runtime for the StoreKit tests; run scripts/ios-storekit-probe.sh on it to find a runtime whose storekitd takes Snacklist.storekit and set storekit_ios (DECISIONS 127)" >&2; exit 1; }
storekit_udid="$(xcrun simctl create "Snacklist StoreKit" "$devicetype" "$runtime")"
# Created and booted after the build: booting while it builds made the build 3 to 7 min slower on
# 3-core runners (job 118).
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
  echo "ios-storekit: xcodebuild listed no iOS $storekit_ios simulator $storekit_udid within ${storekit_search} s; no StoreKit test ran (DECISIONS 164)" >&2
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
    sys.exit("ios-storekit: every LifetimeStoreKitTests case must pass on iOS %s (a skip means storekitd refused Snacklist.storekit)" % sys.argv[1])
PY
exit "${status:-0}"
