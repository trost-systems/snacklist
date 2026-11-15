import { assertEquals, assertRejects } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import { SweepError } from '../_shared/feedback_screenshots.ts';
import { createHandler, type Deps } from './handler.ts';
import { MAX_BYTES, storagePutter, type StoreScreenshot, UploadError } from './upload.ts';

const USER = '00000000-0000-4000-8000-0000000000a1';
const ID = '10000000-0000-4000-8000-0000000000ab';
const NAME = `${USER}/${ID}.png`;
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);

const post = (
  path = '/feedback-screenshots/sweep',
  method = 'POST',
  body: BodyInit | undefined = undefined,
) => new Request(`http://local${path}`, { method, ...(body === undefined ? {} : { body }) });

const signedIn = () => Promise.resolve({ userId: USER });

function deps(overrides: Partial<Deps> = {}): Deps {
  return {
    sweep: () => Promise.resolve(0),
    authenticate: signedIn,
    store: () => Promise.resolve('stored'),
    ...overrides,
  };
}

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
    const res = await createHandler(deps({ sweep: () => Promise.resolve(2) }))(post());
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
      const res = await createHandler(deps({ sweep: () => Promise.reject(error) }))(post());
      assertEquals(res.status, 503);
      assertEquals(await res.json(), { error: code });
    });
    assertEquals(logs, line);
  }
});

Deno.test('only POST /sweep and POST /upload/<id> do anything', async () => {
  let runs = 0;
  const handle = createHandler(deps({
    sweep: () => {
      runs++;
      return Promise.resolve(0);
    },
    store: () => {
      runs++;
      return Promise.resolve('stored');
    },
  }));
  const get = await handle(post('/feedback-screenshots/sweep', 'GET'));
  assertEquals([get.status, get.headers.get('allow')], [405, 'POST, OPTIONS']);
  await get.body?.cancel();
  const getUpload = await handle(post(`/feedback-screenshots/upload/${ID}`, 'GET'));
  assertEquals(getUpload.status, 405);
  await getUpload.body?.cancel();
  for (const path of ['/feedback-screenshots', `/feedback-screenshots/upload/${ID}/x`]) {
    const other = await handle(post(path, 'POST', PNG));
    assertEquals(other.status, 404, path);
    await other.body?.cancel();
  }
  const options = await handle(post('/feedback-screenshots/sweep', 'OPTIONS'));
  assertEquals(options.status, 204);
  assertEquals(runs, 0);
});

Deno.test('an upload stores <user>/<id>.png and answers its name, stored or already there', async () => {
  for (const outcome of ['stored', 'exists'] as const) {
    const calls: [string, string, number][] = [];
    const store: StoreScreenshot = (userId, id, png) => {
      calls.push([userId, id, png.byteLength]);
      return Promise.resolve(outcome);
    };
    const logs = await logsOf(async () => {
      const res = await createHandler(deps({ store }))(
        post(`/feedback-screenshots/upload/${ID}`, 'POST', PNG),
      );
      assertEquals(res.status, 200);
      assertEquals(await res.json(), { name: NAME });
    });
    assertEquals(calls, [[USER, ID, PNG.byteLength]]);
    assertEquals(logs, `feedback-screenshots: upload ${outcome}`);
  }
});

Deno.test('refused uploads: fixed answers and log lines, nothing stored', async () => {
  const big = new Uint8Array(MAX_BYTES + 1);
  big.set(PNG);
  const atLimit = new Uint8Array(MAX_BYTES);
  atLimit.set(PNG);
  const cases: [string, BodyInit | undefined, number, unknown, string][] = [
    [ID.toUpperCase(), PNG, 400, { error: 'bad_request' }, 'bad_request'],
    ['notes', PNG, 400, { error: 'bad_request' }, 'bad_request'],
    [`${ID}.png`, PNG, 400, { error: 'bad_request' }, 'bad_request'],
    [ID, undefined, 400, { error: 'bad_request' }, 'bad_request'],
    [ID, new Uint8Array(), 400, { error: 'bad_request' }, 'bad_request'],
    [ID, new TextEncoder().encode('<svg/>'), 415, { error: 'not_png' }, 'not_png'],
    [ID, PNG.slice(0, 7), 415, { error: 'not_png' }, 'not_png'],
    [ID, big, 413, { error: 'too_large' }, 'too_large'],
    // A stream has no content-length: the cap holds while reading.
    [ID, new Blob([big]).stream(), 413, { error: 'too_large' }, 'too_large'],
  ];
  for (const [id, body, status, answer, code] of cases) {
    let stores = 0;
    const logs = await logsOf(async () => {
      const res = await createHandler(deps({
        store: () => {
          stores++;
          return Promise.resolve('stored');
        },
      }))(post(`/feedback-screenshots/upload/${id}`, 'POST', body));
      assertEquals(res.status, status, `${id} ${code}`);
      assertEquals(await res.json(), answer);
    });
    assertEquals(stores, 0, code);
    assertEquals(logs, `feedback-screenshots: upload ${code}`);
  }
  const res = await createHandler(deps())(
    post(`/feedback-screenshots/upload/${ID}`, 'POST', atLimit),
  );
  assertEquals(res.status, 200, 'exactly 2 MiB passes');
  await res.body?.cancel();
});

Deno.test('over a quota: 403 quota', async () => {
  const logs = await logsOf(async () => {
    const res = await createHandler(deps({ store: () => Promise.resolve('quota') }))(
      post(`/feedback-screenshots/upload/${ID}`, 'POST', PNG),
    );
    assertEquals(res.status, 403);
    assertEquals(await res.json(), { error: 'quota' });
  });
  assertEquals(logs, 'feedback-screenshots: upload quota');
});

Deno.test('the session decides first: 401 without one, 403 for API and MCP tokens', async () => {
  const failures: [AuthError, number][] = [
    [new AuthError('missing_token', 'fehlt'), 401],
    [new AuthError('invalid_token', 'ungültig', 'signature'), 401],
    [new AuthError('session_required', 'nur in der App'), 403],
  ];
  for (const [error, status] of failures) {
    let stores = 0;
    const logs = await logsOf(async () => {
      const res = await createHandler(deps({
        authenticate: () => Promise.reject(error),
        store: () => {
          stores++;
          return Promise.resolve('stored');
        },
      }))(post(`/feedback-screenshots/upload/${ID}`, 'POST', PNG));
      assertEquals(res.status, status);
      assertEquals((await res.json()).error, error.reason);
      assertEquals(res.headers.get('www-authenticate'), status === 401 ? 'Bearer' : null);
    });
    assertEquals(stores, 0);
    assertEquals(logs, `feedback-screenshots: upload ${error.reason}`);
  }
});

Deno.test('a failed store is 503 with its code; the log names no object or user', async () => {
  const failures: [unknown, string, string][] = [
    [
      new UploadError('storage_failed', '500'),
      'storage_failed',
      'feedback-screenshots: upload storage_failed 500',
    ],
    [
      new UploadError('db_error', '55P03'),
      'db_error',
      'feedback-screenshots: upload db_error 55P03',
    ],
    [new Error(`unexpected ${NAME}`), 'db_error', 'feedback-screenshots: upload db_error unknown'],
  ];
  for (const [error, code, line] of failures) {
    const logs = await logsOf(async () => {
      const res = await createHandler(deps({ store: () => Promise.reject(error) }))(
        post(`/feedback-screenshots/upload/${ID}`, 'POST', PNG),
      );
      assertEquals(res.status, 503);
      assertEquals(await res.json(), { error: code });
    });
    assertEquals(logs, line);
  }
  const logs = await logsOf(async () => {
    const res = await createHandler(deps({ authenticate: () => Promise.reject(new Error(USER)) }))(
      post(`/feedback-screenshots/upload/${ID}`, 'POST', PNG),
    );
    assertEquals([res.status, await res.json()], [503, { error: 'db_error' }]);
  });
  assertEquals(logs, 'feedback-screenshots: upload db_error auth');
});

Deno.test('storagePutter: never overwrites; a duplicate is "exists" in both of its shapes', async () => {
  const seen: Request[] = [];
  const answering = (status: number, body: unknown): typeof fetch => (input, init) => {
    seen.push(new Request(input, init));
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  const put = (f: typeof fetch) => storagePutter('http://kong', 'sb_secret_x', f)(NAME, PNG);
  assertEquals(await put(answering(200, { Key: NAME })), 'stored');
  const [request] = seen;
  assertEquals(request?.url, `http://kong/storage/v1/object/feedback-screenshots/${NAME}`);
  assertEquals(request?.headers.get('x-upsert'), 'false');
  assertEquals(request?.headers.get('authorization'), 'Bearer sb_secret_x');
  assertEquals(
    await put(answering(400, { statusCode: '409', error: 'Duplicate', message: 'exists' })),
    'exists',
  );
  assertEquals(await put(answering(409, { error: 'Duplicate' })), 'exists');
  const failed = await assertRejects(() => put(answering(400, { statusCode: '413' })), UploadError);
  assertEquals([failed.code, failed.detail], ['storage_failed', '400']);
  const offline = await assertRejects(
    () => put(() => Promise.reject(new TypeError('connection refused'))),
    UploadError,
  );
  assertEquals([offline.code, offline.detail], ['storage_failed', 'fetch']);
});
