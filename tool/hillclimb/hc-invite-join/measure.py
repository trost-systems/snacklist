"""Scores the enabled household join paths (job 460): docs/hillclimb/hc-invite-join.md."""
import collections, datetime, json, pathlib, subprocess, sys

here = pathlib.Path(__file__).parent
repo = here.parents[2]
app = repo / "app"

cells = collections.OrderedDict()
for line in (here / "cells.tsv").read_text().splitlines():
    if not line.strip() or line.startswith("#"):
        continue
    cell, *rest = line.split("\t")
    rows = cells.setdefault(cell, [])
    if rest:
        steps, path, name = rest
        rows.append((int(steps), path, name))

# The regression gate: every test of the join, invite and onboarding code, not only the mapped ones.
gate = ["test/household", "test/onboarding", "test/shell/router_test.dart"]
files = sorted({path for rows in cells.values() for _, path, _ in rows} | set(gate))
proc = subprocess.run(
    ["flutter", "test", "--no-pub", "--machine", *files],
    cwd=app, capture_output=True, text=True,
)
names, results = {}, {}
for raw in proc.stdout.splitlines():
    try:
        event = json.loads(raw)
    except ValueError:
        continue
    if not isinstance(event, dict):
        continue
    if event.get("type") == "testStart":
        test = event["test"]
        names[test["id"]] = test["name"]
    elif event.get("type") == "testDone" and not event.get("hidden"):
        results[event["testID"]] = event["result"] == "success" and not event["skipped"]
ran = [(names[i], ok) for i, ok in results.items() if i in names]
failed = sorted(name for name, ok in ran if not ok)

gaps, steps, missing_rows = [], 0, []
for cell, rows in cells.items():
    if not rows:
        gaps.append(cell)
        continue
    covered = True
    for row_steps, _, want in rows:
        hits = [ok for name, ok in ran if want in name]
        if not hits:
            missing_rows.append(f"{cell}: {want}")
        if not hits or not all(hits):
            covered = False
        steps += row_steps
    if not covered:
        gaps.append(cell)

score = 100 * len(failed) + 10 * len(gaps) + steps
sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=repo,
                     capture_output=True, text=True).stdout.strip()
print(json.dumps({
    "goal": "hc-invite-join", "score": score, "higher_is_better": False,
    "parts": {"failed_tests": len(failed), "gaps": len(gaps), "cells": len(cells),
              "steps": steps, "tests_run": len(ran), "files": len(files),
              "failed": failed, "gap_cells": gaps, "unmatched_rows": missing_rows},
    "score_unit": "100 x failed tests + 10 x uncovered cells + happy-path steps",
    "git": sha, "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}))
sys.exit(0 if ran else 1)
