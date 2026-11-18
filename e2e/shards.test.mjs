// Tests the shard split of shards.mjs in plain Node (the lint gate runs it: node --test).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { durationsOf, plan, SHARD_ONE_EXTRA_SECONDS, testsOf, unlistable } from './shards.mjs';

const suite = (n, project = 'chromium') =>
  Array.from({ length: n }, (_, i) => ({ id: `[${project}] › f${i % 7}.spec.ts › t${i}`, project }));

test('every test lands in exactly one shard, and the same inputs give the same split', () => {
  const tests = [...suite(97), ...suite(5, 'firefox')];
  const durations = Object.fromEntries(tests.slice(0, 80).map((t, i) => [t.id, (i * 37) % 50 + 1]));
  for (const total of [1, 2, 4, 6]) {
    const shards = plan(tests, durations, total);
    assert.equal(shards.length, total);
    const all = shards.flatMap((s) => s.tests).sort();
    assert.deepEqual(all, tests.map((t) => t.id).sort());
    assert.deepEqual(plan([...tests].reverse(), durations, total), shards);
  }
});

test('shards end close together, shard 1 leaving room for what it runs after its suite', () => {
  const tests = suite(200);
  const durations = Object.fromEntries(tests.map((t, i) => [t.id, (i * 13) % 40 + 2]));
  const shards = plan(tests, durations, 4);
  const estimates = shards.map((s) => s.estimate);
  assert.ok(Math.max(...estimates) - Math.min(...estimates) <= 20, `estimates ${estimates}`);
  const seconds = (s) => s.tests.reduce((sum, id) => sum + durations[id], 0);
  assert.ok(seconds(shards[0]) < seconds(shards[1]) - SHARD_ONE_EXTRA_SECONDS, 'shard 1 runs fewer test seconds');
});

test('a test without a duration counts as the median one', () => {
  const tests = suite(9);
  const durations = Object.fromEntries(tests.slice(0, 8).map((t, i) => [t.id, [200, 1, 3, 90, 7, 40, 2, 5][i]]));
  const median = (5 + 7) / 2;
  assert.deepEqual(plan(tests, durations, 3), plan(tests, { ...durations, [tests[8].id]: median }, 3));
  assert.notDeepEqual(plan(tests, durations, 3), plan(tests, { ...durations, [tests[8].id]: 200 }, 3));
});

test("Firefox's tests, one at a time, spread over the shards", () => {
  const tests = [...suite(4, 'firefox'), ...suite(4)];
  const durations = Object.fromEntries(tests.map((t) => [t.id, t.project === 'firefox' ? 100 : 10]));
  for (const shard of plan(tests, durations, 4)) {
    assert.equal(shard.tests.filter((id) => id.startsWith('[firefox]')).length, 1);
  }
});

test('ids and durations come from the JSON report: describes in the title path, retries summed, medians', () => {
  const report = (ms) => ({
    suites: [{
      title: 'a.spec.ts',
      specs: [{ file: 'a.spec.ts', title: 'top', tests: [{ projectName: 'chromium', results: [{ duration: ms }] }] }],
      suites: [{
        title: 'group',
        specs: [{
          file: 'a.spec.ts',
          title: 'inner',
          tests: [{ projectName: 'webkit', results: [{ duration: ms }, { duration: 1000 }] }],
        }],
      }],
    }],
  });
  assert.deepEqual(testsOf(report(2000)).map((t) => t.id), [
    '[chromium] › a.spec.ts › top',
    '[webkit] › a.spec.ts › group › inner',
  ]);
  assert.deepEqual(durationsOf([report(2000), report(4000), report(9000)]), {
    '[chromium] › a.spec.ts › top': 4,
    '[webkit] › a.spec.ts › group › inner': 5,
  });
});

test('a suite --test-list cannot name test by test is refused, with the reason', () => {
  const t = (project, ...titles) => ({ id: [`[${project}]`, 'a.spec.ts', ...titles].join(' › '), project, titles });
  assert.equal(unlistable([t('chromium', 'adds'), t('chromium', 'group', 'adds'), t('webkit', 'adds')]), '');
  assert.match(unlistable([t('chromium', 'group'), t('chromium', 'group', 'adds')]), /\[chromium\] › a.spec.ts › group also names/);
  assert.match(unlistable([t('chromium', 'list › add')]), /has a '›'/);
  assert.match(unlistable([t('chromium', 'adds ')]), /space at an end/);
});
