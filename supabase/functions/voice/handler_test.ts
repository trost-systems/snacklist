import { assertEquals, assertMatch } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import { type Added, type Caller, confirmation, createHandler, type Deps } from './handler.ts';
import type { ParsedItem } from './parse.ts';

const caller: Caller = { userId: 'u1', householdId: 'h1' };
const fail = (status: 401 | 403) =>
  new AuthError(status === 403 ? 'no_household' : 'invalid_token', 'test');

/** A fake list: "Milch" is already on it, everything else lands in "Sonstiges". */
function fakeDeps(overrides: Partial<Deps> = {}) {
  const calls: ParsedItem[][] = [];
  const deps: Deps = {
    authenticate: (req) => {
      const token = req.headers.get('authorization');
      if (token === 'Bearer fgp_good') return Promise.resolve(caller);
      if (token === 'Bearer app-session') return Promise.resolve({ ...caller, via: 'session' });
      if (token === 'Bearer fgp_siri') return Promise.resolve({ ...caller, via: 'siri' });
      return Promise.reject(fail(401));
    },
    // u1 is in h1 (the default) and h2.
    isMember: (_caller, household) => Promise.resolve(['h1', 'h2'].includes(household)),
    // The lock is off (or the household has premium): everything as before job 50.
    requirePremium: () => Promise.resolve('open'),
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
    addItems: (_caller, items) => {
      calls.push(items);
      return Promise.resolve(items.map((item) => ({
        ...item,
        brand: null,
        properties: null,
        category: 'Sonstiges',
        alreadyOnList: item.name === 'Milch',
        similarOnList: [],
      })));
    },
    ...overrides,
  };
  return { handle: createHandler(deps), calls };
}

/** What the splitter heard, without the brand and details the database adds. */
const heard = (body: { items: ParsedItem[] }) =>
  body.items.map(({ name, quantity }) => ({ name, quantity }));

const post = (body: unknown, init: { token?: string; query?: string; type?: string } = {}) =>
  new Request(`http://local/voice${init.query ?? ''}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${init.token ?? 'fgp_good'}`,
      'content-type': init.type ?? 'application/json',
    },
    body: typeof body === 'string' && init.type ? body : JSON.stringify(body),
  });

Deno.test('adds the split items and confirms them in German', async () => {
  const { handle, calls } = fakeDeps();
  const res = await handle(post({ text: 'Zwei Gurken und Klopapier' }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.speech, 'Hinzugefügt: 2 Gurken, Klopapier.');
  assertEquals(calls, [[{ name: 'Gurken', quantity: '2' }, { name: 'Klopapier', quantity: null }]]);
  assertEquals(body.items[0], {
    name: 'Gurken',
    brand: null,
    properties: null,
    quantity: '2',
    category: 'Sonstiges',
    alreadyOnList: false,
    similarOnList: [],
  });
});

Deno.test('names items that were already on the list', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Milch, zwei Gurken und Klopapier' }));
  assertEquals(
    (await res.json()).speech,
    'Hinzugefügt: 2 Gurken, Klopapier. Schon auf der Liste: Milch.',
  );
});

Deno.test('answers in plain text with ?format=text', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Klopapier' }, { query: '?format=text' }));
  assertEquals(res.headers.get('content-type'), 'text/plain; charset=utf-8');
  assertEquals(await res.text(), 'Hinzugefügt: Klopapier.');
});

Deno.test('accepts a plain-text body', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post('Klopapier', { type: 'text/plain' }));
  assertEquals((await res.json()).speech, 'Hinzugefügt: Klopapier.');
});

Deno.test('parse mode splits without adding', async () => {
  const { handle, calls } = fakeDeps();
  const res = await handle(post({ text: 'Milch und 1 kg Mehl', mode: 'parse' }));
  assertEquals(res.status, 200);
  assertEquals(heard(await res.json()), [
    { name: 'Milch', quantity: null },
    { name: 'Mehl', quantity: '1 kg' },
  ]);
  assertEquals(calls, []);
});

Deno.test('parse mode with split: brand, details, store and category as a typed add gets them', async () => {
  const { handle } = fakeDeps({
    splitItems: (_caller, items) =>
      Promise.resolve(
        items.map((item) =>
          item.name === 'Windeln Pampers Größe 3'
            ? {
              ...item,
              name: 'Windeln',
              brand: 'Pampers',
              properties: 'Größe 3',
              storeId: 'dm',
              categoryId: 'drogerie',
            }
            : { ...item, brand: null, properties: null, storeId: null, categoryId: 'kuehlregal' }
        ),
      ),
  });
  const res = await handle(
    post({ text: 'Windeln Pampers Größe 3 und Milch', mode: 'parse', split: true }),
  );
  assertEquals((await res.json()).items, [
    {
      name: 'Windeln',
      brand: 'Pampers',
      properties: 'Größe 3',
      quantity: null,
      storeId: 'dm',
      categoryId: 'drogerie',
    },
    {
      name: 'Milch',
      brand: null,
      properties: null,
      quantity: null,
      storeId: null,
      categoryId: 'kuehlregal',
    },
  ]);
});

Deno.test('job 169b: the app names the household it shows; the split runs there', async () => {
  const splitIn: string[] = [];
  const asked: string[] = [];
  const { handle } = fakeDeps({
    isMember: (_caller, household) => {
      asked.push(household);
      return Promise.resolve(household === 'h2');
    },
    splitItems: (c, items) => {
      splitIn.push(c.householdId);
      return Promise.resolve(
        items.map((item) => ({
          ...item,
          brand: null,
          properties: null,
          storeId: 's2',
          categoryId: null,
        })),
      );
    },
  });
  const parse = (household?: string) =>
    handle(post(
      { text: 'Zahnpasta', mode: 'parse', split: true, ...(household && { household }) },
      { token: 'app-session' },
    ));
  const res = await parse('h2');
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    speech: 'Verstanden: Zahnpasta.',
    items: [{
      name: 'Zahnpasta',
      quantity: null,
      brand: null,
      properties: null,
      storeId: 's2',
      categoryId: null,
    }],
    truncated: false,
  }, 'the answer keeps its shape');
  assertEquals((await parse()).status, 200, 'without household: the default, as older apps get');
  assertEquals(splitIn, ['h2', 'h1']);
  assertEquals(asked, ['h2']);
});

Deno.test('job 169b: a household the session user is not in is refused, nothing split', async () => {
  let splits = 0;
  const { handle } = fakeDeps({
    splitItems: () => {
      splits++;
      return Promise.reject(new Error('not asked'));
    },
  });
  const res = await handle(
    post({ text: 'Milch', mode: 'parse', split: true, household: 'h9' }, { token: 'app-session' }),
  );
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, 'no_household');
  assertEquals(splits, 0);
});

Deno.test('job 169b: Siri and token callers keep their credential household', async () => {
  for (const token of ['fgp_good', 'fgp_siri']) {
    const addedIn: string[] = [];
    const { handle } = fakeDeps({
      isMember: () => Promise.reject(new Error('not asked')),
      addItems: (c, items) => {
        addedIn.push(c.householdId);
        return Promise.resolve(items.map((item) => ({
          ...item,
          brand: null,
          properties: null,
          category: 'Sonstiges',
          alreadyOnList: false,
          similarOnList: [],
        })));
      },
    });
    const res = await handle(post({ text: 'Milch', household: 'h2' }, { token }));
    assertEquals(res.status, 200, token);
    assertEquals(addedIn, ['h1'], token);
  }
});

Deno.test('parse mode without split answers as before, for installed apps', async () => {
  let splits = 0;
  const { handle } = fakeDeps({
    splitItems: () => {
      splits++;
      return Promise.reject(new Error('not asked'));
    },
  });
  const res = await handle(post({ text: 'Windeln Pampers Größe 3', mode: 'parse' }));
  assertEquals((await res.json()).items, [{ name: 'Windeln Pampers Größe 3', quantity: null }]);
  assertEquals(splits, 0);
});

Deno.test('parse mode with split: a failing split answers the items as heard, reported', async () => {
  const reported: unknown[] = [];
  const { handle } = fakeDeps({
    splitItems: () => Promise.reject(new Error('db down')),
    report: (e) => reported.push(e),
  });
  const res = await handle(
    post({ text: 'Windeln Pampers Größe 3 und Milch', mode: 'parse', split: true }),
  );
  assertEquals(res.status, 200);
  assertEquals((await res.json()).items, [
    { name: 'Windeln Pampers Größe 3', quantity: null },
    { name: 'Milch', quantity: null },
  ]);
  assertEquals(reported.length, 1);
});

Deno.test('parse mode, the in-app dictation, reads a count said after the item', async () => {
  const { handle } = fakeDeps();
  for (
    const [text, lang, items] of [
      ['Gurken zwei und Milch', 'de', [{ name: 'Gurken', quantity: '2' }, {
        name: 'Milch',
        quantity: null,
      }]],
      ['cucumbers two and milk', 'en', [{ name: 'cucumbers', quantity: '2' }, {
        name: 'milk',
        quantity: null,
      }]],
    ] as const
  ) {
    const res = await handle(post({ text, mode: 'parse', lang }));
    assertEquals<readonly ParsedItem[]>(heard(await res.json()), items, text);
  }
});

const errors: [string, () => Request, Partial<Deps>, number, string, RegExp][] = [
  [
    'wrong token',
    () => post({ text: 'Milch' }, { token: 'nope' }),
    {},
    401,
    'unauthorized',
    /Zugriffstoken/,
  ],
  [
    'no household',
    () => post({ text: 'Milch' }),
    { authenticate: () => Promise.reject(fail(403)) },
    403,
    'no_household',
    /keinem Haushalt/,
  ],
  ['GET', () => new Request('http://local/voice'), {}, 405, 'method', /POST/],
  ['empty text', () => post({ text: '  ' }), {}, 400, 'no_text', /keinen Text/],
  ['no text field', () => post({ words: 'Milch' }), {}, 400, 'no_text', /keinen Text/],
  [
    'broken JSON',
    () => post('{"text": ', { type: 'application/json' }),
    {},
    400,
    'no_text',
    /keinen Text/,
  ],
  [
    'only filler',
    () => post({ text: 'Bitte, danke' }),
    {},
    422,
    'nothing_understood',
    /nichts verstanden/,
  ],
  ['too long', () => post({ text: 'Milch '.repeat(300) }), {}, 413, 'too_long', /zu lang/],
  [
    'database down',
    () => post({ text: 'Milch' }),
    { addItems: () => Promise.reject(new Error('boom')) },
    500,
    'server',
    /nicht geklappt/,
  ],
  [
    'auth backend down',
    () => post({ text: 'Milch' }),
    { authenticate: () => Promise.reject(new Error('jwks down')) },
    500,
    'server',
    /nicht geklappt/,
  ],
];

for (const [label, request, overrides, status, error, speech] of errors) {
  Deno.test(`answers ${status} ${error} for ${label}`, async () => {
    const { handle, calls } = fakeDeps(overrides);
    const res = await handle(request());
    assertEquals(res.status, status);
    const body = await res.json();
    assertEquals(body.error, error);
    assertMatch(body.speech, speech);
    assertEquals(calls, []);
  });
}

Deno.test('a 500 is reported to error tracking, a 4xx is not', async () => {
  const reported: unknown[] = [];
  const boom = new Error('boom');
  const report = (e: unknown) => reported.push(e);
  const failing = fakeDeps({ addItems: () => Promise.reject(boom), report });
  await (await failing.handle(post({ text: 'Milch' }))).body?.cancel();
  const fine = fakeDeps({ report });
  await (await fine.handle(post({ text: 'Bitte, danke' }))).body?.cancel();
  await (await fine.handle(post({ text: 'Milch' }, { token: 'nope' }))).body?.cancel();
  assertEquals(reported, [boom]);
});

Deno.test('a 401 tells the client to send a bearer token', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'Milch' }, { token: 'nope' }));
  assertEquals(res.headers.get('www-authenticate'), 'Bearer');
  await res.body?.cancel();
});

Deno.test('answers CORS preflight', async () => {
  const { handle } = fakeDeps();
  const res = await handle(new Request('http://local/voice', { method: 'OPTIONS' }));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('access-control-allow-origin'), '*');
});

Deno.test('confirmation lists only what was said back', () => {
  const item = (name: string, alreadyOnList: boolean, quantity: string | null = null): Added => ({
    name,
    brand: null,
    properties: null,
    quantity,
    category: 'Kühlregal',
    alreadyOnList,
    similarOnList: [],
  });
  assertEquals(confirmation([item('Milch', true)]), 'Schon auf der Liste: Milch.');
  assertEquals(
    confirmation([item('Mehl', false, '1 kg'), item('Eier', false)]),
    'Hinzugefügt: 1 kg Mehl, Eier.',
  );
});

Deno.test('a new item with a similar one open is added, and Siri says what is open (job 32b)', async () => {
  const { handle } = fakeDeps({
    addItems: () =>
      Promise.resolve([
        {
          name: 'Karotten',
          brand: null,
          properties: null,
          quantity: '500 g',
          category: 'Obst & Gemüse',
          alreadyOnList: false,
          similarOnList: ['Möhren'],
        },
        {
          name: 'Milch',
          brand: null,
          properties: null,
          quantity: null,
          category: 'Kühlregal',
          alreadyOnList: false,
          similarOnList: [],
        },
      ]),
  });
  const body = await (await handle(post({ text: '500 g Karotten und Milch' }))).json();
  assertEquals(
    body.speech,
    'Hinzugefügt: 500 g Karotten, Milch. Schon auf der Liste: Möhren.',
  );
  assertEquals(body.items[0].similarOnList, ['Möhren']);
  assertEquals(body.items[0].alreadyOnList, false);
});

Deno.test('open variants join the exact duplicates in one sentence, each name once (job 68)', () => {
  const item = (name: string, alreadyOnList: boolean, similarOnList: string[] = []): Added => ({
    name,
    brand: null,
    properties: null,
    quantity: null,
    category: 'Obst & Gemüse',
    alreadyOnList,
    similarOnList,
  });
  assertEquals(
    confirmation([item('Karotten', false, ['Möhren']), item('Mohrrüben', false, ['Möhren'])]),
    'Hinzugefügt: Karotten, Mohrrüben. Schon auf der Liste: Möhren.',
  );
  assertEquals(
    confirmation([item('Karotten', false, ['Möhren']), item('Milch', true)]),
    'Hinzugefügt: Karotten. Schon auf der Liste: Milch, Möhren.',
  );
  assertEquals(
    confirmation([item('Möhren', true), item('Karotten', false, ['Möhren'])]),
    'Hinzugefügt: Karotten. Schon auf der Liste: Möhren.',
  );
  assertEquals(
    confirmation([item('Karotten', false, ['Möhren']), item('Milch', true)], 'en'),
    'Added Karotten to Hummlist. Already on the list: Milch and Möhren.',
  );
  assertEquals(
    confirmation([item('Milch', true), item('Eier', true)], 'en'),
    'Already on the list: Milch and Eier.',
  );
});

Deno.test('the confirmation reads brand and properties back after the name', async () => {
  const { handle } = fakeDeps({
    addItems: () =>
      Promise.resolve([
        {
          name: 'Windeln',
          brand: 'Pampers',
          properties: 'Größe 3, Big Pack',
          quantity: null,
          category: '👶 Drogerie',
          alreadyOnList: false,
          similarOnList: [],
        },
        {
          name: 'Milch',
          brand: null,
          properties: '1,5 %',
          quantity: '2 l',
          category: 'Kühlregal',
          alreadyOnList: false,
          similarOnList: [],
        },
      ]),
  });
  const body = await (await handle(post({ text: 'Windeln Pampers Größe 3 Big Pack' }))).json();
  assertEquals(body.speech, 'Hinzugefügt: Windeln Pampers Größe 3 Big Pack, 2 l Milch 1,5 %.');
  assertEquals(body.items[0].brand, 'Pampers');
  assertEquals(body.items[0].properties, 'Größe 3, Big Pack');
});

Deno.test('more than thirty items: the first thirty are added and Siri says so', async () => {
  const { handle, calls } = fakeDeps();
  const sentence = Array.from({ length: 40 }, (_, i) => `Ding${i}`).join(', ');
  const res = await handle(post({ text: sentence }));
  const body = await res.json();
  assertEquals(calls[0].length, 30);
  assertEquals(body.truncated, true);
  assertMatch(body.speech, /Mehr als dreißig auf einmal gehen nicht/);
});

Deno.test('thirty items exactly are not reported as cut', async () => {
  const { handle } = fakeDeps();
  const sentence = Array.from({ length: 30 }, (_, i) => `Ding${i}`).join(', ');
  const body = await (await handle(post({ text: sentence }))).json();
  assertEquals(body.truncated, false);
  assertEquals(body.items.length, 30);
});
