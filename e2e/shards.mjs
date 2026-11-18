// Job 304: CI's e2e shards split by measured time, not by test count. Playwright's --shard gives
// each shard an equal number of tests in file order, so one shard ran 2 min longer than the next.
// Every shard plans the same split from the same inputs (the suite's --list and
// shard-durations.json) and runs its own part through --test-list; a test missing from the
// durations counts as the median one. Durations only move tests between shards, never drop one.
//
//   node shards.mjs list <current>/<total> <out-file>   the test list for one shard (e2e gate);
//     exit 3 when some test cannot be named in a test list, and the shards split by count
//   node shards.mjs durations <playwright-results.json>...   new shard-durations.json on stdout
//   node shards.mjs show <total>   the planned shards' estimated times
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import process from 'node:process';

// What shard 1 runs after its suite: integration-lock.spec.ts alone (31-33 s) and the fg sync
// smoke test (33-34 s), CI runs 44242102263 and 44236144523.
export const SHARD_ONE_EXTRA_SECONDS = 65;
// playwright.config.ts: two workers in CI, Firefox's tests one at a time.
const WORKERS = 2;
const SERIAL_PROJECTS = new Set(['firefox']);

const DURATIONS = new URL('./shard-durations.json', import.meta.url);

/** A test's id, also its line in a --test-list file: `[project] › file › describe › title`. */
const testId = (project, file, titles) => [`[${project}]`, file, ...titles].join(' › ');

/** Every test in a Playwright JSON report (--list or a run), with its result durations. */
export function testsOf(report) {
  const tests = [];
  const walk = (suite, titles) => {
    for (const spec of suite.specs ?? []) {
      for (const test of spec.tests) {
        tests.push({
          id: testId(test.projectName, spec.file, [...titles, spec.title]),
          titles: [...titles, spec.title],
          project: test.projectName,
          seconds: test.results.reduce((sum, r) => sum + r.duration, 0) / 1000,
        });
      }
    }
    for (const child of suite.suites ?? []) walk(child, [...titles, child.title]);
  };
  for (const file of report.suites) walk(file, []);
  return tests;
}

export const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

/** Each test's median duration over the given runs' reports, in seconds. */
export function durationsOf(reports) {
  const runs = new Map();
  for (const report of reports) {
    for (const { id, seconds } of testsOf(report)) runs.set(id, [...(runs.get(id) ?? []), seconds]);
  }
  return Object.fromEntries([...runs].sort(([a], [b]) => (a < b ? -1 : 1)).map(([id, s]) => [id, Math.round(median(s) * 10) / 10]));
}

/**
 * Why --test-list cannot name each test on its own line, or ''. Playwright splits a line at '›',
 * trims each title, and takes the titles as a prefix of the test's: a test whose title path
 * starts with another's is selected by that one's line too.
 */
export function unlistable(tests) {
  const titles = tests.map((t) => t.id.split(' › '));
  const bad = tests.find((t) => t.titles.some((title) => title.includes('›') || title !== title.trim()));
  if (bad) return `the title of ${bad.id} has a '›' or space at an end`;
  const ids = new Set(tests.map((t) => t.id));
  for (const path of titles) {
    for (let n = 3; n < path.length; n++) {
      const prefix = path.slice(0, n).join(' › ');
      if (ids.has(prefix)) return `${prefix} also names ${path.join(' › ')}`;
    }
  }
  return '';
}

/** A shard's estimated wall time: its tests on the workers, the serial project's on one. */
const estimate = (shard) => shard.fixed + Math.max(shard.seconds / WORKERS, shard.serialSeconds);

/**
 * Splits the tests into `total` shards, longest first onto the shard that ends earliest. Each test
 * lands in exactly one shard; the result depends only on the ids, projects and durations.
 */
export function plan(tests, durations, total) {
  const known = tests.map((t) => durations[t.id]).filter((s) => s !== undefined);
  const fallback = known.length ? median(known) : 1;
  const weighted = tests.map((t) => ({ ...t, seconds: durations[t.id] ?? fallback }))
    .sort((a, b) => b.seconds - a.seconds || (a.id < b.id ? -1 : 1));
  const shards = Array.from({ length: total }, (_, i) => ({
    tests: [],
    seconds: 0,
    serialSeconds: 0,
    fixed: i === 0 ? SHARD_ONE_EXTRA_SECONDS : 0,
  }));
  for (const test of weighted) {
    const after = (shard) =>
      estimate({
        ...shard,
        seconds: shard.seconds + test.seconds,
        serialSeconds: shard.serialSeconds + (SERIAL_PROJECTS.has(test.project) ? test.seconds : 0),
      });
    const best = shards.reduce((a, b) => (after(b) < after(a) ? b : a));
    best.tests.push(test.id);
    best.seconds += test.seconds;
    if (SERIAL_PROJECTS.has(test.project)) best.serialSeconds += test.seconds;
  }
  return shards.map((s) => ({ tests: s.tests, estimate: Math.round(estimate(s)) }));
}

/** The suite as this checkout's config lists it (the stack must answer, as for a run, or `env` name one). */
export function listSuite(extra = [], env = process.env) {
  const out = execFileSync('npx', ['playwright', 'test', '--list', '--reporter=json', ...extra], {
    cwd: new URL('.', import.meta.url),
    env,
    encoding: 'utf8',
    maxBuffer: 1 << 26,
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const report = JSON.parse(out);
  if (report.errors?.length) throw new Error(`playwright --list: ${report.errors.map((e) => e.message).join('; ')}`);
  return testsOf(report);
}

export const readDurations = () => JSON.parse(readFileSync(DURATIONS, 'utf8'));

function parseShard(arg) {
  const m = /^(\d+)\/(\d+)$/.exec(arg ?? '');
  const current = Number(m?.[1]);
  const total = Number(m?.[2]);
  if (!m || current < 1 || current > total) throw new Error(`a shard is <current>/<total>, not '${arg}'`);
  return { current, total };
}

function main([command, ...args]) {
  if (command === 'list') {
    const { current, total } = parseShard(args[0]);
    const out = args[1];
    if (!out) throw new Error('usage: node shards.mjs list <current>/<total> <out-file>');
    const suite = listSuite();
    // The same answer on every shard: then all of them fall back to Playwright's --shard together.
    const why = unlistable(suite);
    if (why) {
      console.log(`::warning::e2e shards by count, not time: ${why} (e2e/shards.mjs)`);
      process.exit(3);
    }
    const shard = plan(suite, readDurations(), total)[current - 1];
    writeFileSync(out, shard.tests.map((id) => `${id}\n`).join(''));
    // --test-list matches a title path as a prefix: what Playwright selects must be this list.
    const selected = shard.tests.length ? listSuite(['--test-list', resolve(out)]).map((t) => t.id) : [];
    const want = new Set(shard.tests);
    if (selected.length !== want.size || !selected.every((id) => want.has(id))) {
      throw new Error(`the test list for shard ${current}/${total} selects ${selected.length} tests, not its ${want.size}`);
    }
    console.log(`shard ${current}/${total}: ${shard.tests.length} tests, about ${shard.estimate} s`);
  } else if (command === 'durations') {
    if (!args.length) throw new Error('usage: node shards.mjs durations <playwright-results.json>...');
    const reports = args.map((f) => JSON.parse(readFileSync(f, 'utf8')));
    process.stdout.write(`${JSON.stringify(durationsOf(reports), null, 2)}\n`);
  } else if (command === 'show') {
    const total = Number(args[0]);
    plan(listSuite(), readDurations(), total).forEach((s, i) =>
      console.log(`shard ${i + 1}/${total}: ${s.tests.length} tests, about ${s.estimate} s`)
    );
  } else {
    throw new Error('usage: node shards.mjs list|durations|show ...');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (e) {
    console.error(`shards.mjs: ${e instanceof Error ? e.message : e}`);
    process.exit(1);
  }
}
