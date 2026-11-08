import { assert, assertEquals } from '@std/assert';
import { buildSnapshot } from '../pipeline/build.ts';
import type { Job, Snapshot } from '../src/snapshot.ts';
import { fakeGh, livePid, now, personEmail, personName, writeFixtureOps } from './fixtures/ops.ts';

async function snapshot(): Promise<{ snap: Snapshot; warnings: string[] }> {
  const { opsDir, repoDir } = await writeFixtureOps();
  const warnings: string[] = [];
  const snap = await buildSnapshot({
    opsDir,
    repoDir,
    gh: fakeGh,
    host: () =>
      Promise.resolve({
        name: 'hz',
        cores: 12,
        load: [3, 2, 1],
        memAvailGb: 50,
        memTotalGb: 62.7,
        diskFreeGb: 280,
      }),
    isWorkerAlive: (pid) => pid === livePid,
    now,
    warn: (m) => warnings.push(m),
  });
  return { snap, warnings };
}

const byId = (snap: Snapshot, id: string): Job => {
  const job = snap.jobs.find((j) => j.id === id);
  if (job === undefined) throw new Error(`no job ${id} in the snapshot`);
  return job;
};

Deno.test('every job lands in the state its files, worker and PR say', async () => {
  const { snap } = await snapshot();
  const states = Object.fromEntries(snap.jobs.map((j) => [j.id, j.state]));
  assertEquals(states, {
    '170-old-open': 'awaiting-merge',
    '201-live-build': 'building',
    '202-live-review': 'reviewing',
    '203-hc-live-fix': 'fixing',
    '204-dead-worker': 'waiting',
    '205-queued': 'queued',
    '206-later': 'waiting',
    '207-limit': 'blocked',
    '208-merged-flake': 'merged',
    '209-open-pr': 'awaiting-merge',
    '210-no-pr': 'done',
    '211-cancelled': 'cancelled',
    '213-fanned-out': 'awaiting-merge',
    '214-draft': 'parked',
    '215-hc-parked': 'parked',
    'vmaint-20261106': 'done',
  });
});

Deno.test('live jobs carry their current step, runner and PR with CI', async () => {
  const { snap } = await snapshot();
  const fix = byId(snap, '203-hc-live-fix');
  assertEquals([fix.step, fix.stepSince, fix.runner, fix.kind], [
    'fix1',
    '2026-11-06T09:30:01.000Z',
    'hz',
    'hillclimb',
  ]);
  assertEquals(fix.pr?.ci, 'pending');
  assertEquals(fix.title, 'PR 306 for job/203-hc-live-fix');
  assertEquals(byId(snap, '201-live-build').title, 'live build');
  assertEquals(byId(snap, '209-open-pr').pr?.ci, 'pass');
  assertEquals(byId(snap, '213-fanned-out').pr?.number, 305);
  assertEquals(byId(snap, 'vmaint-20261106').kind, 'maintenance');
  assertEquals(byId(snap, '208-merged-flake').kind, 'flake');
});

Deno.test("the timeline: steps with ends, a requeued PASS counts as its round's PASS", async () => {
  const { snap } = await snapshot();
  const job = byId(snap, '208-merged-flake');
  assertEquals(job.steps.map((s) => [s.name, s.endedAt !== null]), [
    ['build', true],
    ['review0', true],
    ['fix1', true],
    ['review1', true],
  ]);
  assertEquals(job.verdicts, [
    { round: 0, verdict: 'fix', requeued: false },
    { round: 1, verdict: 'pass', requeued: true },
    { round: 2, verdict: 'pass', requeued: false },
  ]);
  // Its brief got an addendum at 09:45, after the build started: the queue time stays the first log line.
  assertEquals([job.queuedAt, job.startedAt, job.finishedAt], [
    '2026-11-05T08:00:00.000Z',
    '2026-11-05T08:00:00.000Z',
    '2026-11-05T10:30:00.000Z',
  ]);
});

Deno.test('a requeued job waits since its status changed, not since its brief', async () => {
  const { snap } = await snapshot();
  const job = snap.jobs.find((j) => j.id === '205-queued');
  assertEquals([job?.queuedAt, job?.statusSince], ['2026-11-07T07:00:00.000Z', '2026-11-07T09:30:00.000Z']);
});

Deno.test('lanes, merges, CI, flaky, usage and the lead list', async () => {
  const { snap } = await snapshot();
  assertEquals(snap.lanes, [{ runner: 'hz', capacity: 4, busy: 3 }]);
  assertEquals(snap.merges.daily.reduce((n, d) => n + d.count, 0), 5);
  assertEquals(snap.merges.medianQueuedToMergedH, 29);
  assertEquals(snap.ci.daily.find((d) => d.date === '2026-11-04'), { date: '2026-11-04', pass: 1, fail: 1 });
  assertEquals(snap.ci.daily.at(-1)?.date, '2026-11-07');
  assertEquals(snap.flaky.open, 1);
  assertEquals(snap.flaky.weekly.at(-1), { week: '2026-11-02', opened: 1, closed: 1 });
  assertEquals(snap.usage, { weeklyUtil: 0.4, pace: 0.475, resetAt: '2026-11-10T22:00:00.000Z' });
  assertEquals(snap.needsLead.map((n) => [n.source, n.ref]), [
    ['job', '213-fanned-out'],
    ['job', '209-open-pr'],
    ['job', '170-old-open'],
    ['NEEDS_LEAD.md', 'job-2-a-question-for-the-lead'],
  ]);
});

Deno.test('an open PR older than every merged or closed one still waits for the lead', async () => {
  const { snap } = await snapshot();
  const job = byId(snap, '170-old-open');
  assertEquals([job.state, job.pr?.number, job.pr?.state], ['awaiting-merge', 170, 'open']);
  assert(snap.needsLead.some((n) => n.source === 'job' && n.ref === '170-old-open'));
});

Deno.test('merged 7d counts the rolling 7 x 24 h, the bars keep calendar days', async () => {
  const { snap } = await snapshot();
  // #290 merged 6 d 23 h before now, on a Berlin day just outside the last 7 bars.
  assertEquals(snap.merges.last7d, 4);
  assertEquals(snap.merges.daily.slice(-7).reduce((n, d) => n + d.count, 0), 3);
  assertEquals(snap.merges.daily.find((d) => d.date === '2026-10-31')?.count, 1);
  assertEquals(snap.merges.prior7d, 1);
});

Deno.test('a registered hill-climb doc that is missing is reported, not invented', async () => {
  const { snap, warnings } = await snapshot();
  assertEquals(snap.hillclimbs.map((h) => h.id), ['hc-strictness']);
  assertEquals(warnings.length, 8);
});

const jobKeys = [
  'finishedAt',
  'id',
  'kind',
  'pr',
  'queuedAt',
  'runner',
  'startedAt',
  'state',
  'statusSince',
  'step',
  'stepSince',
  'steps',
  'title',
  'verdicts',
];

Deno.test('privacy: names, emails and prose from briefs, BOARD and reviews never reach the JSON', async () => {
  const { snap } = await snapshot();
  const json = JSON.stringify(snap);
  for (
    const secret of [
      personName,
      'Mustermann',
      personEmail,
      '@example.org',
      'Milch',
      'Must fix',
      'Lead requeue',
    ]
  ) {
    assert(!json.includes(secret), `snapshot contains "${secret}"`);
  }
  assertEquals(Object.keys(snap).sort(), [
    'ci',
    'flaky',
    'generatedAt',
    'hillclimbs',
    'host',
    'jobs',
    'lanes',
    'merges',
    'needsLead',
    'schema',
    'usage',
  ]);
  for (const job of snap.jobs) assertEquals(Object.keys(job).sort(), jobKeys);
});
