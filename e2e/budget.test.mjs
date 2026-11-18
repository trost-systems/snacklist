// Tests the e2e budget's measure and verdict in plain Node (the lint gate runs it: node --test).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { measure, verdict } from './budget.mjs';

const tests = (n) => Array.from({ length: n }, (_, i) => ({ id: `[chromium] › f.spec.ts › t${i}` }));

test('a test without a measured duration counts as the median one', () => {
  const suite = tests(4);
  const durations = { [suite[0].id]: 2, [suite[1].id]: 10, [suite[2].id]: 30 };
  assert.deepEqual(measure(suite, durations), { tests: 4, seconds: 52 });
});

test('over either budget fails, near either warns', () => {
  const budget = { tests: 100, seconds: 1000 };
  assert.deepEqual(verdict({ tests: 90, seconds: 900 }, budget), { level: 'ok', keys: [] });
  assert.deepEqual(verdict({ tests: 98, seconds: 900 }, budget), { level: 'warn', keys: ['tests'] });
  assert.deepEqual(verdict({ tests: 100, seconds: 1000 }, budget), { level: 'warn', keys: ['tests', 'seconds'] });
  assert.deepEqual(verdict({ tests: 101, seconds: 900 }, budget), { level: 'over', keys: ['tests'] });
  assert.deepEqual(verdict({ tests: 90, seconds: 1001 }, budget), { level: 'over', keys: ['seconds'] });
});
