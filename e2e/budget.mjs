// Job 309 (OC3b): the e2e suite's budget. Every PR waits for the e2e shards, and the suite grew
// from 153 to 290 tests in 17 days of November 2026. The lint gate fails when the suite lists more
// tests, or more estimated seconds (shard-durations.json, a new test at the median), than
// budget.json allows, and warns from 98 % of either. Behaviour one screen shows belongs in a
// Flutter widget test; an e2e test is for what needs the stack, the browser or two clients. A PR
// that needs more raises budget.json and says why in its description (docs/CI.md, The e2e budget).
//
//   node budget.mjs   the suite against budget.json; exit 1 over it
import { readFileSync } from 'node:fs';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { listSuite, median, readDurations } from './shards.mjs';

export const WARN_AT = 0.98;

/** The suite's size: its tests and their estimated seconds, a test without a duration at the median. */
export function measure(tests, durations) {
  const known = tests.map((t) => durations[t.id]).filter((s) => s !== undefined);
  const fallback = known.length ? median(known) : 0;
  const seconds = tests.reduce((sum, t) => sum + (durations[t.id] ?? fallback), 0);
  return { tests: tests.length, seconds: Math.round(seconds) };
}

/** 'over' when either measure is above its budget, 'warn' from WARN_AT of either, else 'ok'. */
export function verdict(size, budget) {
  const over = ['tests', 'seconds'].filter((k) => size[k] > budget[k]);
  if (over.length) return { level: 'over', keys: over };
  const near = ['tests', 'seconds'].filter((k) => size[k] >= budget[k] * WARN_AT);
  return near.length ? { level: 'warn', keys: near } : { level: 'ok', keys: [] };
}

function main() {
  const budget = JSON.parse(readFileSync(new URL('./budget.json', import.meta.url), 'utf8'));
  // Listing loads the config and every spec, which read the stack's URL and keys but call nothing.
  const env = {
    SUPABASE_URL: 'http://127.0.0.1:54321',
    SUPABASE_PUBLISHABLE_KEY: 'listing-only',
    MAILPIT_URL: 'http://127.0.0.1:54324',
    ...Object.fromEntries(Object.entries(process.env).filter(([, v]) => v)),
  };
  const size = measure(listSuite([], env), readDurations());
  const { level, keys } = verdict(size, budget);
  const line = `e2e budget: ${size.tests} of ${budget.tests} tests, about ${size.seconds} of ${budget.seconds} s (e2e/budget.json)`;
  if (level === 'ok') return console.log(line);
  const advice = 'Behaviour one screen shows belongs in a widget test (app/test); if this needs e2e, raise e2e/budget.json and say why in the PR (docs/CI.md, The e2e budget).';
  if (level === 'warn') return console.log(`::warning::${line}: near the budget in ${keys.join(' and ')}. ${advice}`);
  console.error(`${line}: over the budget in ${keys.join(' and ')}. ${advice}`);
  process.exit(1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
