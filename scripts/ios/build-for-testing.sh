# shellcheck shell=bash
# Sourced by the ios and ios-storekit gates (job 304): the app and RunnerTests built once for the
# newest iPhone simulator installed, as `udid` and the products under `derived`. The ios gate's
# checks read the built app; both gates test it with xcodebuild test-without-building.
# Expects lib.sh sourced and the working directory app/.
log "phase config"
flutter build ios --config-only --simulator --debug
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.rsplit("iOS", 1)[-1])]
ios = sorted((r for r in devices if ".SimRuntime.iOS-" in r), key=version, reverse=True)
print(next(d["udid"] for r in ios for d in devices[r] if d["name"].startswith("iPhone")))')"
log "phase build"
derived=build/ios/derived
xcodebuild build-for-testing -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=NO
