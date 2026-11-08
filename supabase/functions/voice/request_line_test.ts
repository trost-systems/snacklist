// Job 170: one log line per voice request, so a Siri test session can be followed live.
import { assertEquals, assertFalse, assertMatch } from '@std/assert';
import { AuthError, type Via } from '../_shared/auth.ts';
import { type Added, type Caller, createHandler, type Deps } from './handler.ts';
import type { ParsedItem } from './parse.ts';

const tokens: Record<string, Via> = { fgp_siri: 'siri', fgp_pat: 'pat', jwt_session: 'session' };

function world(overrides: Partial<Deps> = {}) {
  const lines: string[] = [];
  const handle = createHandler({
    authenticate: (req) => {
      const via = tokens[req.headers.get('authorization')?.replace('Bearer ', '') ?? ''];
      return via
        ? Promise.resolve({ userId: 'user-1', householdId: 'house-1', via })
        : Promise.reject(new AuthError('invalid_token', 'test'));
    },
    requirePremium: () => Promise.resolve('open'),
    isMember: () => Promise.resolve(false),
    splitItems: (_caller, items) =>
      Promise.resolve(
        items.map((i) => ({
          ...i,
          brand: null,
          properties: null,
          storeId: null,
          categoryId: null,
        })),
      ),
    addItems: (_: Caller, items: ParsedItem[]): Promise<Added[]> =>
      Promise.resolve(items.map((item) => ({
        ...item,
        brand: null,
        properties: null,
        category: 'Sonstiges',
        alreadyOnList: item.name === 'Milch',
        similarOnList: [],
      }))),
    readItems: () => Promise.resolve([{ name: 'Brot', quantity: null }]),
    log: (line) => lines.push(line),
    ...overrides,
  });
  return { handle, lines };
}

const post = (body: unknown, token = 'fgp_siri', client?: string) =>
  new Request('http://local/voice', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      ...(client && { 'x-hummlist-client': client }),
    },
    body: JSON.stringify(body),
  });

const shape =
  /^voice: (siri|pat|session|none|-) (add|parse|read|-) (de|en|-) client=[\w.:-]+ -> [a-z_-]+ status=\d{3} count=\d+ ms=\d+$/;

Deno.test('each request logs one line: who, what, the outcome and how long', async () => {
  const { handle, lines } = world();
  await handle(
    post({ text: 'Milch und zwei Gurken', lang: 'de' }, 'fgp_siri', 'ios-1210.AddItems'),
  );
  await handle(post({ mode: 'read', lang: 'en' }, 'fgp_siri', 'ios-1210.ReadList'));
  await handle(post({ text: 'Milch', lang: 'de' }, 'fgp_pat'));
  await handle(post({ text: 'Brot', mode: 'parse', lang: 'de', split: true }, 'jwt_session'));
  await handle(post({ text: 'Brot', lang: 'de' }, 'expired'));
  await handle(post({ text: 'äh', lang: 'de' }));
  assertEquals(lines.map((l) => l.replace(/ ms=\d+$/, '')), [
    'voice: siri add de client=ios-1210.AddItems -> added status=200 count=2',
    'voice: siri read en client=ios-1210.ReadList -> read status=200 count=1',
    'voice: pat add de client=- -> nothing_added status=200 count=1',
    'voice: session parse de client=- -> parsed status=200 count=1',
    'voice: none add de client=- -> unauthorized status=401 count=0',
    'voice: siri add de client=- -> nothing_understood status=422 count=0',
  ]);
  for (const line of lines) assertMatch(line, shape);
});

Deno.test('a failure after sign-in still logs, with status 500', async () => {
  const { handle, lines } = world({ addItems: () => Promise.reject(new Error('db down')) });
  const res = await handle(post({ text: 'Milch', lang: 'de' }));
  assertEquals(res.status, 500);
  assertMatch(lines[0], /^voice: siri add de client=- -> server status=500 count=1 ms=\d+$/);
});

Deno.test('the line never carries the text, a token or a forged client header', async () => {
  const { handle, lines } = world();
  await handle(
    post(
      { text: 'Geheimzutat und Kaffeebohnen', lang: 'de' },
      'fgp_siri',
      'ios 1210 -> added voice: forged Kaffeebohnen fgp_siri',
    ),
  );
  assertEquals(lines.length, 1);
  assertEquals(lines[0].split('\n').length, 1);
  for (const secret of ['Geheimzutat', 'Kaffeebohnen', 'fgp_siri', 'user-1', 'house-1', ' 1210']) {
    assertFalse(lines[0].includes(secret), `the line names ${secret}`);
  }
  assertMatch(lines[0], /client=other -> added /);
  assertMatch(lines[0], shape);
});

Deno.test('a throw logs status 500, then reaches withTelemetry', async () => {
  const { handle, lines } = world({
    authenticate: () => Promise.reject(new TypeError('boom')),
    report: () => {
      throw new Error('report broke');
    },
  });
  let thrown = false;
  try {
    await handle(post({ text: 'Milch', lang: 'de' }));
  } catch {
    thrown = true;
  }
  assertEquals(thrown, true);
  assertMatch(lines[0], /^voice: none add de client=- -> - status=500 count=0 ms=\d+$/);
});
