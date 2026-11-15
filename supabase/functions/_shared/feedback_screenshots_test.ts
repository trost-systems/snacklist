import { assertEquals, assertRejects } from '@std/assert';
import {
  type RemoveObjects,
  storageRemover,
  SweepError,
  sweepFeedbackScreenshots,
  type SweepStore,
} from './feedback_screenshots.ts';

const NAME = '00000000-0000-4000-8000-0000000000a1/10000000-0000-4000-8000-000000000001.png';

function fakeStore(due: string[], failRemoved = false) {
  const marked: string[][] = [];
  const store: SweepStore = {
    due: (limit) => Promise.resolve(due.slice(0, limit)),
    removed: (names) => {
      if (failRemoved) return Promise.reject(Object.assign(new Error(NAME), { code: '40001' }));
      marked.push([...names]);
      return Promise.resolve();
    },
  };
  return { store, marked };
}

Deno.test('the sweep removes what is due, then drops it from the queue', async () => {
  const { store, marked } = fakeStore([NAME, 'b/c.png']);
  const asked: string[][] = [];
  const remove: RemoveObjects = (names) => {
    asked.push([...names]);
    return Promise.resolve(1);
  };
  assertEquals(await sweepFeedbackScreenshots(store, remove), 1);
  assertEquals(asked, [[NAME, 'b/c.png']]);
  assertEquals(marked, [[NAME, 'b/c.png']], 'names already gone leave the queue too');
});

Deno.test('the sweep is bounded and calls nothing when nothing is due', async () => {
  const { store } = fakeStore(['a', 'b', 'c']);
  const asked: string[][] = [];
  const remove: RemoveObjects = (names) => {
    asked.push([...names]);
    return Promise.resolve(names.length);
  };
  assertEquals(await sweepFeedbackScreenshots(store, remove, 2), 2);
  assertEquals(asked, [['a', 'b']]);
  const empty = fakeStore([]);
  assertEquals(await sweepFeedbackScreenshots(empty.store, remove), 0);
  assertEquals(asked.length, 1);
  assertEquals(empty.marked, []);
});

Deno.test('a failed removal keeps the names queued', async () => {
  const { store, marked } = fakeStore([NAME]);
  const remove: RemoveObjects = () => Promise.reject(new SweepError('storage_failed', '500'));
  const e = await assertRejects(() => sweepFeedbackScreenshots(store, remove), SweepError);
  assertEquals(e.code, 'storage_failed');
  assertEquals(marked, []);
});

Deno.test('a database failure is db_error with the SQLSTATE only, never a name', async () => {
  const { store } = fakeStore([NAME], true);
  const e = await assertRejects(
    () => sweepFeedbackScreenshots(store, () => Promise.resolve(1)),
    SweepError,
  );
  assertEquals(e.message, 'feedback-screenshots: db_error 40001');
});

Deno.test('the Storage API gets one DELETE with the names and the secret key', async () => {
  const seen: { url: string; init: RequestInit | undefined }[] = [];
  const remove = storageRemover('http://kong:8000', 'sb_secret_test', (input, init) => {
    seen.push({ url: String(input), init });
    return Promise.resolve(Response.json([{ name: NAME }]));
  });
  assertEquals(await remove([NAME, 'x/y.png']), 1);
  const [call] = seen;
  assertEquals(call?.url, 'http://kong:8000/storage/v1/object/feedback-screenshots');
  assertEquals(call?.init?.method, 'DELETE');
  const headers = new Headers(call?.init?.headers);
  assertEquals(headers.get('apikey'), 'sb_secret_test');
  assertEquals(headers.get('authorization'), 'Bearer sb_secret_test');
  assertEquals(JSON.parse(String(call?.init?.body)), { prefixes: [NAME, 'x/y.png'] });
});

Deno.test('a Storage API error or an unreachable API is storage_failed with the status only', async () => {
  const answers: [() => Promise<Response>, string][] = [
    [() => Promise.resolve(Response.json({ message: NAME }, { status: 500 })), '500'],
    [() => Promise.resolve(new Response('not json')), '200'],
    [() => Promise.reject(new TypeError('connection refused')), 'fetch'],
  ];
  for (const [answer, detail] of answers) {
    const remove = storageRemover('http://kong:8000', 'k', answer);
    const e = await assertRejects(() => remove([NAME]), SweepError);
    assertEquals([e.code, e.detail], ['storage_failed', detail]);
  }
});
