import { assertEquals } from '@std/assert';
import { SweepError } from '../_shared/feedback_screenshots.ts';
import { createHandler } from './handler.ts';

const NAME = '00000000-0000-4000-8000-0000000000a1/10000000-0000-4000-8000-000000000001.png';

const post = (path = '/feedback-screenshots/sweep', method = 'POST') =>
  new Request(`http://local${path}`, { method });

/** Runs `work` with console.log and console.error captured. */
async function logsOf(work: () => Promise<void>): Promise<string> {
  const lines: string[] = [];
  const { log, error } = console;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(' '));
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(' '));
  try {
    await work();
  } finally {
    console.log = log;
    console.error = error;
  }
  return lines.join('\n');
}

Deno.test('POST /sweep answers how many were removed, with a fixed log line', async () => {
  const logs = await logsOf(async () => {
    const res = await createHandler(() => Promise.resolve(2))(post());
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { removed: 2 });
  });
  assertEquals(logs, 'feedback-screenshots: removed 2');
});

Deno.test('a failed sweep is 503 with its code; the log names no object', async () => {
  const failures: [unknown, string, string][] = [
    [
      new SweepError('storage_failed', '500'),
      'storage_failed',
      'feedback-screenshots: storage_failed 500',
    ],
    [new SweepError('db_error', '57014'), 'db_error', 'feedback-screenshots: db_error 57014'],
    [new Error(`unexpected ${NAME}`), 'failed', 'feedback-screenshots: failed'],
  ];
  for (const [error, code, line] of failures) {
    const logs = await logsOf(async () => {
      const res = await createHandler(() => Promise.reject(error))(post());
      assertEquals(res.status, 503);
      assertEquals(await res.json(), { error: code });
    });
    assertEquals(logs, line);
  }
});

Deno.test('only POST /feedback-screenshots/sweep sweeps', async () => {
  let runs = 0;
  const handle = createHandler(() => {
    runs++;
    return Promise.resolve(0);
  });
  const get = await handle(post('/feedback-screenshots/sweep', 'GET'));
  assertEquals([get.status, get.headers.get('allow')], [405, 'POST, OPTIONS']);
  await get.body?.cancel();
  const other = await handle(post('/feedback-screenshots'));
  assertEquals(other.status, 404);
  await other.body?.cancel();
  const options = await handle(post('/feedback-screenshots/sweep', 'OPTIONS'));
  assertEquals(options.status, 204);
  assertEquals(runs, 0);
});
