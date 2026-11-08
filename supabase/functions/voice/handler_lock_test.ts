// Job 50: the integration lock on the voice function (Siri Shortcut and native Siri). A locked
// household is answered with premium_required (200, the spoken placeholder) and nothing is read
// or added; the app's own session (in-app dictation) never asks; a failing check is a server
// error, never an add.
import { assert, assertEquals, assertFalse } from '@std/assert';
import { AuthError, type Via } from '../_shared/auth.ts';
import type { Access, Integration } from '../_shared/premium.ts';
import { copy } from './copy.ts';
import { type Caller, createHandler, type Deps, type VoiceEvent } from './handler.ts';
import type { ParsedItem } from './parse.ts';

const tokens: Record<string, Via> = { fgp_siri: 'siri', fgp_pat: 'pat', jwt_session: 'session' };

function world(access: () => Promise<Access>) {
  const added: ParsedItem[][] = [];
  const asked: [Caller, Integration][] = [];
  const events: VoiceEvent[] = [];
  let reads = 0;
  const deps: Deps = {
    authenticate: (req) => {
      const via = tokens[req.headers.get('authorization')?.replace('Bearer ', '') ?? ''];
      return via
        ? Promise.resolve({ userId: 'u1', householdId: 'h1', via })
        : Promise.reject(new AuthError('invalid_token', 'test'));
    },
    splitItems: (_caller, items) =>
      Promise.resolve(
        items.map((item) => ({
          ...item,
          brand: null,
          properties: null,
          storeId: null,
          categoryId: null,
        })),
      ),
    isMember: () => Promise.resolve(false),
    requirePremium: (caller, integration) => {
      asked.push([caller, integration]);
      return access();
    },
    addItems: (_caller, items) => {
      added.push(items);
      return Promise.resolve(items.map((item) => ({
        ...item,
        brand: null,
        properties: null,
        category: 'Sonstiges',
        alreadyOnList: false,
        similarOnList: [],
      })));
    },
    readItems: () => {
      reads++;
      return Promise.resolve([{ name: 'Milch', quantity: null }]);
    },
    track: (_caller, event) => {
      events.push(event);
      return Promise.resolve();
    },
    report: () => {},
  };
  return { handle: createHandler(deps), added, asked, events, reads: () => reads };
}

const post = (body: unknown, token: string, query = '') =>
  new Request(`http://local/voice${query}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const locked = () => Promise.resolve<Access>('locked');

Deno.test('locked, the Shortcut (no lang): 200 with the German premium sentence, nothing added', async () => {
  const w = world(locked);
  const res = await w.handle(post({ text: 'Milch, zwei Gurken und Klopapier' }, 'fgp_pat'));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    error: 'premium_required',
    speech: copy.de.failures.premium_required,
  });
  assertEquals(w.added, []);
  assertEquals(w.asked.map(([, i]) => i), ['siri']);
  assertEquals(w.events, [{
    event: 'siri_add',
    result: 'fail',
    reason: 'premium_required',
    language: 'de',
    source: 'shortcut',
    count: 0,
  }]);
});

Deno.test('locked, ?format=text: the sentence Siri speaks, as plain text with 200', async () => {
  const w = world(locked);
  const res = await w.handle(post({ text: 'Milch' }, 'fgp_pat', '?format=text'));
  assertEquals(res.status, 200);
  assertEquals(await res.text(), copy.de.failures.premium_required);
  assertEquals(w.added, []);
});

Deno.test('locked, native Siri: outcome premium_required in its language, for add and read', async () => {
  for (const lang of ['de', 'en'] as const) {
    for (const mode of ['add', 'read'] as const) {
      const w = world(locked);
      const res = await w.handle(post({ text: 'milk', mode, lang }, 'fgp_siri'));
      assertEquals(res.status, 200);
      const body = await res.json();
      assertEquals(body.outcome, 'premium_required');
      assertEquals(body.speech, copy[lang].failures.premium_required);
      assertFalse('items' in body, 'no item is named');
      assertEquals(w.added, []);
      assertEquals(w.reads(), 0, 'the list is not read');
      assertEquals(w.events.map((e) => [e.event, e.reason, e.source]), [[
        mode === 'add' ? 'siri_add' : 'siri_read',
        'premium_required',
        'native',
      ]]);
    }
  }
});

Deno.test('the premium sentences say nothing was added', () => {
  assert(copy.de.failures.premium_required.includes('Ich habe nichts hinzugefügt.'));
  assert(copy.en.failures.premium_required.includes("I didn't add anything."));
  assert(copy.de.failures.premium_required.includes('Hummlist Premium'));
});

Deno.test("the app's own session (in-app dictation) never asks the gate", async () => {
  const w = world(locked);
  const res = await w.handle(post({ text: 'Milch und Eier', mode: 'parse' }, 'jwt_session'));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).items.map((i: ParsedItem) => i.name), ['Milch', 'Eier']);
  assertEquals(w.asked, []);
});

Deno.test('open (lock off, yearly, Lifetime or a promotional grant): Siri adds as before', async () => {
  const w = world(() => Promise.resolve('open'));
  const res = await w.handle(post({ text: 'Milch und Eier' }, 'fgp_pat'));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).speech, 'Hinzugefügt: Milch, Eier.');
  assertEquals(w.added.map((items) => items.map((i) => i.name)), [['Milch', 'Eier']]);
  assertEquals(w.asked, [[{ userId: 'u1', householdId: 'h1', via: 'pat' }, 'siri']]);
});

Deno.test('the check fails (database down): the transient error, nothing added', async () => {
  const w = world(() => Promise.reject(new Error('connection refused')));
  const res = await w.handle(post({ text: 'Milch', lang: 'de' }, 'fgp_siri'));
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.outcome, 'server');
  assertEquals(body.speech, copy.de.failures.server);
  assertEquals(w.added, []);
});

Deno.test('a bad token is refused before the gate is asked', async () => {
  const w = world(locked);
  const res = await w.handle(post({ text: 'Milch' }, 'fgp_unknown'));
  assertEquals(res.status, 401);
  await res.body?.cancel();
  assertEquals(w.asked, []);
});
