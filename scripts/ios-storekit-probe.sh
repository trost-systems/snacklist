#!/usr/bin/env bash
# Does storekitd take StoreKit's local test store (Snacklist.storekit) from this Mac's simulator
# build? Builds the app once, then runs LifetimeStoreKitTests on a fresh iPhone simulator of each
# given iOS runtime (downloaded with xcodebuild if missing) and prints per runtime what storekitd
# said and how the tests ended. `--scheme-config` also tries the scheme's Test-action StoreKit
# configuration on the newest runtime. Rerun it on a new runner image (DECISIONS 127): if a runtime
# says "accepted", the ios gate can run the tests there. Evidence goes to /tmp/storekit-probe.
#
# Usage: scripts/ios-storekit-probe.sh [--scheme-config] <ios-version>...   e.g. 26.5 18.6
set -uo pipefail
source "$(dirname "$0")/lib.sh"
scheme_config=0
[[ ${1:-} == --scheme-config ]] && { scheme_config=1; shift; }
[[ $# -gt 0 ]] || { echo "usage: $0 [--scheme-config] <ios-version>..." >&2; exit 2; }
cd "$REPO_ROOT/app" || exit 1
out=/tmp/storekit-probe
rm -rf "$out" && mkdir -p "$out"
derived=build/ios/derived

runtime_id() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
for r in json.load(sys.stdin)["runtimes"]:
    if r["platform"] == "iOS" and r["isAvailable"] and (r["version"] == want or r["version"].startswith(want + ".")):
        print(r["identifier"]); break' "$1"
}

# Runs xcodebuild in the background so a hung test can't eat the job: macOS has no timeout(1).
run_tests() {
  local udid=$1 name=$2
  local start; start="$(date '+%Y-%m-%d %H:%M:%S')"
  xcodebuild test-without-building -workspace ios/Runner.xcworkspace -scheme Runner \
    -destination "id=$udid" -destination-timeout 300 -derivedDataPath "$derived" -only-testing:RunnerTests/LifetimeStoreKitTests \
    -parallel-testing-enabled NO -test-timeouts-enabled YES -resultBundlePath "$out/$name.xcresult" \
    >"$out/$name.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 132); do kill -0 "$pid" 2>/dev/null || break; sleep 5; done
  kill -0 "$pid" 2>/dev/null && { echo "$name: xcodebuild still running after 11 min, stopped"; kill "$pid"; }
  wait "$pid"
  xcrun simctl spawn "$udid" log show --start "$start" --style compact \
    --predicate 'process == "storekitd" OR category == "SKTestSession"' >"$out/$name-sim.log" 2>&1
  local verdict=accepted
  grep -q "Test Case" "$out/$name.log" || verdict="unknown (no test ran)"
  grep -q "not installed for development" "$out/$name-sim.log" && verdict="refused (not installed for development)"
  grep -q "Error saving configuration file" "$out/$name-sim.log" && verdict="$verdict, SKTestSession could not save"
  local tests
  tests="$(grep -E "Test Case .*(passed|failed|skipped)" "$out/$name.log" | sed -E "s/.*LifetimeStoreKitTests ([A-Za-z0-9]+)\]' ([a-z]+).*/\1 \2/" | paste -sd, -)"
  echo "$name: storekitd $verdict; tests: ${tests:-none ran}" | tee -a "$out/results.txt"
}

log "phase build"
first_udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
for r, ds in json.load(sys.stdin)["devices"].items():
    for d in ds:
        if ".SimRuntime.iOS-" in r and d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()')"
flutter build ios --config-only --simulator --debug
xcodebuild build-for-testing -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "id=$first_udid" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=NO -quiet || exit 1

last_udid=""
for version in "$@"; do
  log "phase iOS $version"
  rt="$(runtime_id "$version")"
  if [[ -z $rt ]]; then
    xcodebuild -downloadPlatform iOS -buildVersion "$version" >"$out/download-$version.log" 2>&1 ||
      { echo "ios-$version: download failed ($(tail -1 "$out/download-$version.log"))" | tee -a "$out/results.txt"; continue; }
    rt="$(runtime_id "$version")"
  fi
  [[ -n $rt ]] || { echo "ios-$version: no runtime after download" | tee -a "$out/results.txt"; continue; }
  device="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
r = next(r for r in json.load(sys.stdin)["runtimes"] if r["identifier"] == sys.argv[1])
iphones = {t["name"]: t["identifier"] for t in r["supportedDeviceTypes"] if t["productFamily"] == "iPhone"}
print(iphones[next((n for n in ("iPhone 17 Pro", "iPhone 16 Pro", "iPhone 16") if n in iphones), list(iphones)[-1])])' "$rt")"
  udid="$(xcrun simctl create "storekit-probe-$version" "$device" "$rt")" ||
    { echo "ios-$version: $device can't run $rt" | tee -a "$out/results.txt"; continue; }
  xcrun simctl boot "$udid" && xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "iOS $version: $rt on $device ($udid)"
  run_tests "$udid" "ios-$version"
  last_udid=$udid
done

if [[ $scheme_config == 1 && -n $last_udid ]]; then
  log "phase scheme StoreKit configuration"
  scheme=ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
  cp "$scheme" "$out/Runner.xcscheme.orig"
  python3 - "$scheme" "$PWD/ios/Snacklist.storekit" <<'PY'
import sys
path, storekit = sys.argv[1:]
s = open(path).read()
ref = f'      <StoreKitConfigurationFileReference\n         identifier = "{storekit}">\n      </StoreKitConfigurationFileReference>\n'
s = s.replace("   </TestAction>", ref + "   </TestAction>", 1)
open(path, "w").write(s)
PY
  run_tests "$last_udid" scheme-config
  cp "$out/Runner.xcscheme.orig" "$scheme"
fi
log "results"
cat "$out/results.txt"
