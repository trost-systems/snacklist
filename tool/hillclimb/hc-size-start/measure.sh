#!/usr/bin/env bash
# HC1 hc-size-start (job 100): Android download size plus cold start, as one score (lower is
# better). Prints one JSON line on stdout; logs go to stderr. docs/hillclimb/hc-size-start.md
# explains the parts, the weights and the baseline they are normalised to (baseline.json).
#
#   tool/hillclimb/hc-size-start/measure.sh [runs]     # runs: launches per measurement, default 15
#
# Needs: Flutter, JAVA_HOME (or ~/opt/jdk-17*), the Android SDK in ANDROID_HOME (or
# ~/android-sdk), clang/CMake/GTK headers for `flutter build linux`, xvfb-run, python3.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-15}"
port=60081
# CI's SDK when it sits next to the default one (scripts/lib.sh does the same).
export PATH="${FLUTTER_DIR:-$HOME/flutter}/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}" ANDROID_SDK_ROOT="${ANDROID_HOME:-$HOME/android-sdk}"
if [[ -z ${JAVA_HOME:-} ]]; then
  JAVA_HOME="$(ls -d "$HOME"/opt/jdk-17* | head -1)"
  export JAVA_HOME
fi

bundletool="$HOME/opt/bundletool/bundletool-all-1.18.1.jar"
if [[ ! -s $bundletool ]]; then
  mkdir -p "$(dirname "$bundletool")"
  curl -sSfL --retry 3 -o "$bundletool" \
    https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar
fi
echo "675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c  $bundletool" | sha256sum -c --quiet >&2

work="$(mktemp -d /tmp/hc100-measure.XXXXXX)"
trap 'rm -rf "$work"' EXIT
cd "$root/app"
flutter pub get >/dev/null

echo "measure: building the release app bundle" >&2
flutter build appbundle --release --analyze-size --target-platform android-arm64 \
  --code-size-directory="$work/size" >"$work/aab.log" 2>&1 || { tail -40 "$work/aab.log" >&2; exit 1; }
aab=build/app/outputs/bundle/release/app-release.aab
# A Play download for one phone: arm64, German, 420 dpi, Android 14.
echo '{"supportedAbis":["arm64-v8a"],"supportedLocales":["de-DE"],"screenDensity":420,"sdkVersion":34}' >"$work/spec.json"
"$JAVA_HOME/bin/java" -jar "$bundletool" build-apks --bundle="$aab" --output="$work/app.apks" \
  --device-spec="$work/spec.json" >&2 2>&1
download="$("$JAVA_HOME/bin/java" -jar "$bundletool" get-size total --apks="$work/app.apks" \
  --device-spec="$work/spec.json" | tail -1 | cut -d, -f2)"
aab_bytes="$(stat -c %s "$aab")"

echo "measure: building the Linux profile startup probe" >&2
flutter build linux --profile -t test_driver/startup_probe.dart \
  --dart-define=SUPABASE_URL="http://127.0.0.1:$port" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_probe >"$work/linux.log" 2>&1 ||
  { tail -40 "$work/linux.log" >&2; exit 1; }

echo "measure: $runs launches under /tmp/fg-hc-measure.lock" >&2
start="$(flock /tmp/fg-hc-measure.lock xvfb-run -a -s "-screen 0 1280x800x24" \
  python3 "$here/startup.py" build/linux/x64/profile/bundle "$port" "$runs" | grep '^{' | tail -1)"

python3 - "$here/baseline.json" "$download" "$aab_bytes" "$start" "$runs" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'EOF'
import datetime, json, os, sys
baseline_path, download, aab, start, runs, sha = sys.argv[1:]
start = json.loads(start)
parts = {
    "android_download_bytes": int(download),
    "first_frame_ms": start["first_frame_ms"],
    "list_interactive_ms": start["interactive_ms"],
    "list_shown_ms": start["list_shown_ms"],
    "aab_bytes": int(aab),
    "runs": int(runs),
    "seed": 0,
    "samples": start["samples"],
}
weights = {"android_download_bytes": 0.4, "first_frame_ms": 0.3, "list_interactive_ms": 0.3}
score = None
if os.path.exists(baseline_path):
    base = json.load(open(baseline_path))
    score = round(sum(w * parts[k] / base[k] for k, w in weights.items()), 4)
print(json.dumps({
    "goal": "hc-size-start",
    "score": score,
    "higher_is_better": False,
    "parts": parts,
    "git": sha,
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}))
EOF
