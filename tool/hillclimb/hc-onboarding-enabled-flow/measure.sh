#!/usr/bin/env bash
# hc-onboarding-enabled-flow (job 461): runs the guided start's widget tests (app/test/onboarding)
# with the frozen dead-end probes (probes_test.dart, copied in for the run) under
# /tmp/fg-hc-measure.lock and prints one JSON line. score = 10 * failing onboarding tests + failing
# probes (each an avoidable dead-end). Lower is better; 0 is the floor.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../scripts/lib.sh
source "$here/../../../scripts/lib.sh"
cd "$REPO_ROOT/app"
exec 3>&1 1>&2

probe=test/onboarding/hc_probes_test.dart
out="$(mktemp)"
trap 'rm -f "$probe" "$out"' EXIT
cp "$here/probes_test.dart" "$probe"
start=$(date +%s%N)
(
  flock 9
  flutter test --reporter json test/onboarding/ >"$out" || true
) 9>/tmp/fg-hc-measure.lock
ms=$(( ($(date +%s%N) - start) / 1000000 ))

node - "$out" "$ms" >&3 <<'JS'
const fs = require('fs');
const [file, ms] = process.argv.slice(2);
const tests = new Map();
const suites = new Map();
let errors = 0;
for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
  if (!line.startsWith('{')) continue;
  const e = JSON.parse(line);
  if (e.type === 'suite') suites.set(e.suite.id, e.suite.path ?? '');
  if (e.type === 'testStart' && !e.test.metadata?.skip && e.test.url !== null) {
    tests.set(e.test.id, { name: e.test.name, suite: suites.get(e.test.suiteID) ?? '' });
  }
  if (e.type === 'testStart' && e.test.url === null) tests.set(e.test.id, { hidden: true });
  if (e.type === 'testDone' && tests.has(e.testID)) tests.get(e.testID).result = e.result;
  if (e.type === 'error' && tests.get(e.testID)?.hidden) errors++;
}
const real = [...tests.values()].filter((t) => !t.hidden && !t.name.startsWith('loading '));
const isProbe = (t) => t.suite.endsWith('hc_probes_test.dart');
const failed = (t) => t.result !== 'success';
const probes = real.filter(isProbe);
const others = real.filter((t) => !isProbe(t));
const testFailures = others.filter(failed).length;
const deadEnds = probes.filter(failed).map((t) => t.name.split(' ')[0]);
console.log(JSON.stringify({
  goal: 'hc-onboarding-enabled-flow',
  score: 10 * testFailures + deadEnds.length + 10 * errors,
  higher_is_better: false,
  parts: {
    test_failures: testFailures,
    tests_run: others.length,
    dead_ends: deadEnds.length,
    dead_end_ids: deadEnds,
    probes_run: probes.length,
    load_errors: errors,
  },
  wall_ms: Number(ms),
}));
JS
