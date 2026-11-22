import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RecordError, parseGates } from '../releases.mjs';
import { REAL_FLAGS } from './helpers.mjs';

const gates = (flag) => JSON.stringify({ flags: { 'smart-sort': { rollout: 'off', note: '', ...flag } }, holds: {} });
const fails = (flag, pattern) =>
  assert.throws(() => parseGates(gates(flag)), (e) => e instanceof RecordError && pattern.test(e.message), String(pattern));

test('the real releases/flags.json parses', () => {
  assert.ok(Object.keys(parseGates(REAL_FLAGS).flags).length > 0);
});

test('a flag may carry min_version for scripts/posthog/sync-flags.ts (job 332)', () => {
  for (const minVersion of ['1.4.0', '1.4.0+1420', { default: '1.4.0', ios: '1.4.1+1420', android: '1.4.0' }]) {
    assert.deepEqual(parseGates(gates({ 'min_version': minVersion })).flags['smart-sort'].min_version, minVersion);
  }
});

test('a bad min_version fails with the flag and the field', () => {
  fails({ min_version: '1.4' }, /flags\.smart-sort\.min_version: must be a version/);
  fails({ min_version: '1.4.0+0' }, /flags\.smart-sort\.min_version: must be a version/);
  fails({ min_version: 140 }, /flags\.smart-sort\.min_version: must be a version or an object/);
  fails({ min_version: { ios: '1.4.0' } }, /flags\.smart-sort\.min_version\.default: missing/);
  fails({ min_version: { default: '1.4.0', tv: '1.0.0' } }, /flags\.smart-sort\.min_version\.tv: unknown platform/);
  fails({ min_version: { default: '1.4.0', ios: 'v1.4.1' } }, /flags\.smart-sort\.min_version\.ios: must be a version/);
  fails({ minimum: '1.4.0' }, /flags\.smart-sort\.minimum: unknown field/);
});

test('a flag may carry a tester_group for the flag sync (job 366)', () => {
  assert.equal(parseGates(gates({ tester_group: 'learned-order' })).flags['smart-sort'].tester_group, 'learned-order');
  fails({ tester_group: 'Learned Order' }, /flags\.smart-sort\.tester_group/);
  fails({ tester_group: 3 }, /flags\.smart-sort\.tester_group/);
});
