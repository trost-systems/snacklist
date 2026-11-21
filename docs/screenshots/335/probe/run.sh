#!/bin/bash
# Usage: run.sh <ios-major|newest> <app path> <out dir>
set -uo pipefail
want=$1 app=$2 out=$3 target=$4
mkdir -p "$out"
xcodebuild -version > "$out/xcode.txt"
xcrun simctl list runtimes > "$out/runtimes.txt"
udid=$(xcrun simctl list devices available -j | WANT="$want" python3 -c '
import json, os, re, sys
devs = json.load(sys.stdin)["devices"]
want = os.environ["WANT"]
def ver(r): return [int(n) for n in re.findall(r"\d+", r.rsplit("iOS", 1)[-1])]
rts = sorted((r for r in devs if re.search(r"\.SimRuntime\.iOS-[0-9-]+$", r)), key=ver, reverse=True)
if want != "newest": rts = [r for r in rts if ver(r)[0] == int(want)]
for r in rts:
    for d in devs[r]:
        if d["name"].startswith("iPhone"):
            print(d["udid"], r, d["name"], sep="\t"); sys.exit(0)
sys.exit("no runtime for " + want)') || exit 1
echo "$udid" > "$out/device.txt"; udid=${udid%%$'\t'*}
cat "$out/device.txt"
xcrun simctl boot "$udid"; xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl install "$udid" "$target"
bundle=dev.probe.probe335
xcrun simctl listapps "$udid" > "$out/listapps.plist"
plutil -convert json -o "$out/listapps.json" "$out/listapps.plist" || true
data=$(xcrun simctl get_app_container "$udid" "$bundle" data)
others="dev.probe.target335 com.apple.Maps com.apple.shortcuts com.apple.Health com.apple.mobilecal com.apple.mobilenotes"
schemes="snacklistnotinstalled335:// probetarget335:// maps:// shortcuts:// x-apple-health:// calshow:// mobilenotes://"
ops="canLaunchUrl externalNonBrowserApplication externalApplication platformDefault"
n=0
for s in $schemes; do for op in $ops; do
  n=$((n+1)); id=$(printf '%02d' $n)-${s%%:*}-$op
  for b in $bundle $others; do xcrun simctl terminate "$udid" "$b" 2>/dev/null; done
  sleep 1
  mkdir -p "$data/tmp"; echo "$id|$op|$s" > "$data/tmp/case.txt"
  xcrun simctl launch "$udid" "$bundle" > /dev/null
  sleep 7
  xcrun simctl io "$udid" screenshot "$out/$id.png" > /dev/null 2>&1
  xcrun simctl spawn "$udid" launchctl list | grep -o 'UIKitApplication:[^[]*' | sort > "$out/$id.running.txt"
  if [[ -f $data/tmp/result_$id.json ]]; then cp "$data/tmp/result_$id.json" "$out/"; else echo '{"missing":true}' > "$out/result_$id.json"; fi
  echo "$id $(cat "$out/result_$id.json") running: $(tr '\n' ' ' < "$out/$id.running.txt")"
done; done
