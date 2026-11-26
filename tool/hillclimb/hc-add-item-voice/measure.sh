#!/usr/bin/env bash
# hc-add-item-voice (job 457): the add sheet with the flags users have. Prints one JSON line on
# stdout; logs go to stderr. Lower score is better. docs/hillclimb/hc-add-item-voice.md has the
# frozen weights and the noise band.
#
#   tool/hillclimb/hc-add-item-voice/measure.sh [runs]
#     runs: probe runs (app/test/list/add_item_probe_test.dart), default 5; parts are medians
#   HC_NO_GATE=1  skip the add-path tests (their failures then count as -1, not in the score)
#
# score = key_ms_p50 + enter_ms_p50 + 50 * (rank_keys_new + rank_keys_bought)
#         + 1000 * (gate_failures + adds_missed)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-5}"
work="$(mktemp -d /tmp/hc457-add.XXXXXX)"
trap 'rm -rf "$work"' EXIT
export PATH="${FLUTTER_DIR:-$HOME/flutter-3.50.0}/bin:$PATH"
cd "$root/app"

gate=(
  test/list/add_sheet_test.dart test/list/add_sheet_compact_test.dart
  test/list/add_sheet_stable_test.dart test/list/add_sheet_catalog_test.dart
  test/list/add_sheet_chains_test.dart test/list/add_sheet_chains_details_test.dart
  test/list/add_match_rows_test.dart test/list/match_rows_test.dart
  test/list/add_field_autofocus_test.dart test/list/add_feedback_list_test.dart
  test/list/dedupe_hint_test.dart test/list/entry_test.dart test/list/quantity_test.dart
  test/list/dictation_test.dart test/list/device_dictation_test.dart
  test/list/scripted_speech_test.dart test/list/suggest_entries_fuzz_test.dart
  test/list/suggest_parity_test.dart test/list/catalog_index_test.dart
  test/list/merge_rows_test.dart test/list/recently_used_open_test.dart
)
failures=-1
if [[ ${HC_NO_GATE:-} != 1 ]]; then
  echo "measure: add-path gate (${#gate[@]} files)" >&2
  flutter test --reporter json "${gate[@]}" >"$work/gate.json" 2>/dev/null || true
  failures="$(python3 -c '
import json, sys
bad = done = 0
for line in open(sys.argv[1]):
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "testDone" and not e.get("hidden"):
        done += 1
        if e.get("result") != "success" and not e.get("skipped"): bad += 1
    if e.get("type") == "error" and e.get("testID") is None: bad += 1
print(bad if done > 100 else 999, done, file=sys.stderr); print(bad if done > 100 else 999)' "$work/gate.json")"
fi

echo "measure: $runs probe runs under /tmp/fg-hc-measure.lock" >&2
for ((i = 0; i < runs; i++)); do
  HC_ADD_PROBE=1 flock /tmp/fg-hc-measure.lock flutter test test/list/add_item_probe_test.dart \
    2>&1 | sed -n 's/^HC_ADD_PROBE //p' >>"$work/runs.jsonl"
done

python3 - "$work/runs.jsonl" "$failures" "$(cut -d' ' -f1-3 /proc/loadavg)" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'PY'
import json, statistics, sys
runs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
if not runs:
    sys.exit("measure: the probe printed nothing")
med = lambda k: statistics.median(r[k] for r in runs)
failures = int(sys.argv[2])
parts = {
    "key_ms_p50": round(med("key_us_p50") / 1000, 2),
    "enter_ms_p50": round(med("enter_us_p50") / 1000, 2),
    "key_ms_p95": round(med("key_us_p95") / 1000, 2),
    "enter_ms_p95": round(med("enter_us_p95") / 1000, 2),
    "rank_keys_new": runs[0]["rank_keys_new"],
    "rank_keys_bought": runs[0]["rank_keys_bought"],
    "adds_missed": runs[0]["adds_expected"] - min(r["adds"] for r in runs),
    "gate_failures": failures,
}
score = (parts["key_ms_p50"] + parts["enter_ms_p50"]
         + 50 * (parts["rank_keys_new"] + parts["rank_keys_bought"])
         + 1000 * (max(failures, 0) + parts["adds_missed"]))
print(json.dumps({
    "goal": "hc-add-item-voice", "score": round(score, 2), "higher_is_better": False,
    "parts": parts, "runs": len(runs), "keys_timed": runs[0]["keys_timed"],
    "enters_timed": runs[0]["enters_timed"], "rank_terms": runs[0]["rank_terms"],
    "spread_key_ms": [round(r["key_us_p50"] / 1000, 2) for r in runs],
    "spread_enter_ms": [round(r["enter_us_p50"] / 1000, 2) for r in runs],
    "load": sys.argv[3], "commit": sys.argv[4],
}))
PY
