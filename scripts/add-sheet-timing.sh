#!/usr/bin/env bash
# Runs the add sheet timing probe (app/test_driver/add_sheet_timing_probe.dart) on the running
# Android emulator: each `<label>=<apk>` once per pass, the passes alternating the APKs so drift
# and warm-up favour neither, one round each (the first pass also samples the CPU). Writes
# <out>/<pass>-<label>.log and prints the A/B table (scripts/add-sheet-timing-table.py).
#   scripts/add-sheet-timing.sh <out> <passes> head=app-profile.apk [base=base.apk]
set -euo pipefail
out=$1 passes=$2
shift 2
mkdir -p "$out"
app=com.snacklist.app
for pass in $(seq 1 "$passes"); do
  for side in "$@"; do
    label=${side%%=*} apk=${side#*=}
    cpu=$([[ $pass == 1 ]] && echo 1 || echo 0)
    log="$out/$pass-$label.log"
    adb uninstall "$app" >/dev/null 2>&1 || true
    adb install "$apk" >/dev/null
    adb logcat -c
    adb logcat -v raw -s flutter:I >"$log" &
    logcat=$!
    adb shell am start -n "$app/.MainActivity" --esal dart_entrypoint_args "--rounds=1,--cpu-rounds=$cpu" >/dev/null
    sleep 5
    started=$SECONDS
    while adb shell pidof "$app" >/dev/null 2>&1; do
      if ((SECONDS - started > 1500)); then
        echo "[add-sheet-timing] pass $pass $label: still running after 25 min" >&2
        break
      fi
      sleep 10
    done
    kill "$logcat" 2>/dev/null || true
    echo "[add-sheet-timing] pass $pass $label: $(grep -c timing-sample "$log" || true) samples, $((SECONDS - started)) s"
    grep -h 'timing-error' "$log" >&2 && exit 1
  done
done
python3 "$(dirname "$0")/add-sheet-timing-table.py" "$out"/*.log
