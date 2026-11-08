// Job 51: lang, outcome, mode read and the siri_add / siri_read events of the voice function.
import { assert, assertEquals, assertFalse, assertMatch } from '@std/assert';
import { AuthError, type AuthFailure, type Via } from '../_shared/auth.ts';
import { checkServerEvent, Telemetry } from '../_shared/telemetry.ts';
import { copy, failureCodes } from './copy.ts';
import { type Added, type Caller, createHandler, type Deps, type VoiceEvent } from './handler.ts';
import type { ParsedItem } from './parse.ts';

const tokens: Record<string, Via> = { fgp_siri: 'siri', fgp_pat: 'pat', jwt_session: 'session' };

const asAdded = (onList: string[]) => (_: Caller, items: ParsedItem[]): Promise<Added[]> =>
  Promise.resolve(items.map((item) => ({
    ...item,
    brand: null,
    properties: null,
    category: 'Sonstiges',
    alreadyOnList: onList.includes(item.name),
    similarOnList: [],
  })));

function fakeDeps(overrides: Partial<Deps> = {}) {
  const events: VoiceEvent[] = [];
  const deps: Deps = {
    authenticate: (req) => {
      const token = req.headers.get('authorization')?.replace('Bearer ', '') ?? '';
      const via = tokens[token];
      return via
        ? Promise.resolve({ userId: 'u1', householdId: 'h1', via })
        : Promise.reject(new AuthError('invalid_token', 'test'));
    },
    // The lock is off (or the household has premium): everything as before job 50.
    requirePremium: () => Promise.resolve('open'),
    isMember: () => Promise.resolve(false),
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
    addItems: asAdded(['milk', 'Milch']),
    readItems: () => Promise.resolve([]),
    track: (_caller, event) => {
      events.push(event);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { handle: createHandler(deps), events };
}

const post = (body: unknown, init: { token?: string; query?: string } = {}) =>
  new Request(`http://local/voice${init.query ?? ''}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${init.token ?? 'fgp_siri'}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });

async function answer(handle: (req: Request) => Promise<Response>, req: Request) {
  const res = await handle(req);
  return { status: res.status, body: await res.json() };
}

Deno.test('lang en adds the split items and reads them back in English', async () => {
  const { handle } = fakeDeps();
  const { status, body } = await answer(
    handle,
    post({ text: 'eggs, bread and two cucumbers', lang: 'en' }),
  );
  assertEquals(status, 200);
  assertEquals(body.outcome, 'added');
  assertEquals(body.speech, 'Added eggs, bread and 2 cucumbers to Hummlist.');
  assertEquals(body.items.map((i: Added) => i.name), ['eggs', 'bread', 'cucumbers']);
});

Deno.test('English: one item, and items already on the list', async () => {
  const { handle } = fakeDeps();
  assertEquals(
    (await answer(handle, post({ text: 'add eggs to Hummlist', lang: 'en' }))).body.speech,
    'Added eggs to Hummlist.',
  );
  const { body } = await answer(handle, post({ text: 'milk and eggs', lang: 'en' }));
  assertEquals(body.speech, 'Added eggs to Hummlist. Already on the list: milk.');
  assertEquals(body.outcome, 'added');
});

Deno.test('everything already on the list is nothing_added, still a 200', async () => {
  const { handle } = fakeDeps();
  const en = await answer(handle, post({ text: 'milk', lang: 'en' }));
  assertEquals([en.status, en.body.outcome, en.body.speech], [
    200,
    'nothing_added',
    'Already on the list: milk.',
  ]);
  const de = await answer(handle, post({ text: 'Milch', lang: 'de' }));
  assertEquals([de.status, de.body.outcome, de.body.speech], [
    200,
    'nothing_added',
    'Schon auf der Liste: Milch.',
  ]);
});

Deno.test('English: an open variant is named with the items already on the list', async () => {
  const { handle } = fakeDeps({
    addItems: (_c, items) =>
      asAdded([])(_c, items).then((added) =>
        added.map((a) => ({ ...a, similarOnList: ['Carrots'] }))
      ),
  });
  assertEquals(
    (await answer(handle, post({ text: 'carrot', lang: 'en' }))).body.speech,
    'Added carrot to Hummlist. Already on the list: Carrots.',
  );
});

Deno.test('lang is de unless it is en; a plain-text body is German', async () => {
  const { handle } = fakeDeps();
  for (const lang of [undefined, 'de', 'fr', 'EN', 7]) {
    assertEquals(
      (await answer(handle, post({ text: 'Klopapier', lang }))).body.speech,
      'Hinzugefügt: Klopapier.',
      String(lang),
    );
  }
  const plain = await handle(
    new Request('http://local/voice', {
      method: 'POST',
      headers: { authorization: 'Bearer fgp_pat', 'content-type': 'text/plain' },
      body: 'eggs',
    }),
  );
  assertEquals((await plain.json()).speech, 'Hinzugefügt: Eggs.');
});

Deno.test('a list id is accepted and ignored', async () => {
  const { handle } = fakeDeps();
  const { status, body } = await answer(handle, post({ text: 'eggs', lang: 'en', list: 'any' }));
  assertEquals([status, body.speech], [200, 'Added eggs to Hummlist.']);
});

Deno.test('?format=text answers in the request language', async () => {
  const { handle } = fakeDeps();
  const res = await handle(post({ text: 'eggs', lang: 'en' }, { query: '?format=text' }));
  assertEquals(await res.text(), 'Added eggs to Hummlist.');
});

Deno.test('parse mode in English', async () => {
  const { handle } = fakeDeps();
  const { body } = await answer(
    handle,
    post({ text: 'milk and 2 kg of flour', mode: 'parse', lang: 'en' }),
  );
  assertEquals(body.outcome, 'parsed');
  assertEquals(body.speech, 'Got it: milk and 2 kg of flour.');
  assertEquals(body.items, [{ name: 'milk', quantity: null }, { name: 'flour', quantity: '2 kg' }]);
});

Deno.test('more than thirty in English: the first thirty are added and Siri says so', async () => {
  const { handle } = fakeDeps();
  const sentence = Array.from({ length: 35 }, (_, i) => `thing${i}`).join(', ');
  const { body } = await answer(handle, post({ text: sentence, lang: 'en' }));
  assertEquals(body.items.length, 30);
  assertEquals(body.truncated, true);
  assertMatch(body.speech, / More than thirty at once doesn't work; please say the rest again\.$/);
});

const openItems = (n: number): ParsedItem[] =>
  Array.from({ length: n }, (_, i) => ({ name: `item${i + 1}`, quantity: i === 0 ? '2' : null }));

Deno.test('mode read reads the open items, ten at most, and returns all of them', async () => {
  const cases: [number, 'en' | 'de', string][] = [
    [0, 'en', 'Your Hummlist is empty.'],
    [0, 'de', 'Die Hummlist ist leer.'],
    [1, 'en', 'There is one thing on your Hummlist: 2 item1.'],
    [1, 'de', 'Auf der Hummlist steht eine Sache: 2 item1.'],
    [3, 'en', 'There are 3 things on your Hummlist: 2 item1, item2 and item3.'],
    [3, 'de', 'Auf der Hummlist stehen 3 Sachen: 2 item1, item2 und item3.'],
    [
      11,
      'de',
      'Auf der Hummlist stehen 11 Sachen: 2 item1, item2, item3, item4, item5, item6, item7, item8, item9, item10 und eine weitere.',
    ],
    [
      14,
      'en',
      'There are 14 things on your Hummlist: 2 item1, item2, item3, item4, item5, item6, item7, item8, item9, item10 and 4 more.',
    ],
  ];
  for (const [n, lang, speech] of cases) {
    const { handle, events } = fakeDeps({ readItems: () => Promise.resolve(openItems(n)) });
    const { status, body } = await answer(handle, post({ mode: 'read', lang }));
    assertEquals(status, 200);
    assertEquals(body, { outcome: 'read', speech, items: openItems(n), total: n });
    assertEquals(events, [{
      event: 'siri_read',
      result: 'success',
      reason: 'read',
      language: lang,
      source: 'native',
      count: n,
    }]);
  }
});

Deno.test('mode read: a database failure is outcome server, reported, nothing claimed', async () => {
  const reported: unknown[] = [];
  const { handle, events } = fakeDeps({
    readItems: () => Promise.reject(new Error('down')),
    report: (e) => reported.push(e),
  });
  const { status, body } = await answer(handle, post({ mode: 'read', lang: 'en' }));
  assertEquals([status, body.outcome, body.error], [500, 'server', 'server']);
  assertEquals(body.speech, copy.en.failures.server);
  assertEquals(reported.length, 1);
  assertEquals(events.map((e) => [e.result, e.reason]), [['fail', 'server']]);
});

const failing: [string, () => Request, Partial<Deps>, number, string][] = [
  [
    'a bad credential',
    () => post({ text: 'milk', lang: 'en' }, { token: 'nope' }),
    {},
    401,
    'unauthorized',
  ],
  [
    'no household',
    () => post({ text: 'milk', lang: 'en' }),
    { authenticate: () => Promise.reject(new AuthError('no_household', 'test')) },
    403,
    'no_household',
  ],
  ['empty text', () => post({ text: ' ', lang: 'en' }), {}, 400, 'no_text'],
  ['too long', () => post({ text: 'milk '.repeat(300), lang: 'en' }), {}, 413, 'too_long'],
  [
    'only filler',
    () => post({ text: 'please, thanks', lang: 'en' }),
    {},
    422,
    'nothing_understood',
  ],
  [
    'database down',
    () => post({ text: 'milk', lang: 'en' }),
    { addItems: () => Promise.reject(new Error('boom')) },
    500,
    'server',
  ],
];

for (const [label, request, overrides, status, code] of failing) {
  Deno.test(`English ${status} ${code} for ${label}: outcome and error are the code`, async () => {
    const { handle } = fakeDeps(overrides);
    const { status: got, body } = await answer(handle, request());
    assertEquals(got, status);
    assertEquals([body.outcome, body.error], [code, code]);
    assertEquals(body.speech, copy.en.failures[code as keyof typeof copy.en.failures]);
  });
}

Deno.test('without lang (the Shortcut recipe) the answers carry no outcome, as before', async () => {
  const { handle } = fakeDeps();
  const added = await answer(handle, post({ text: 'Klopapier' }, { token: 'fgp_pat' }));
  assertEquals(added.body, {
    speech: 'Hinzugefügt: Klopapier.',
    items: [{
      name: 'Klopapier',
      quantity: null,
      brand: null,
      properties: null,
      category: 'Sonstiges',
      alreadyOnList: false,
      similarOnList: [],
    }],
    truncated: false,
  });
  const failed = await answer(handle, post({ text: 'Bitte, danke' }, { token: 'fgp_pat' }));
  assertEquals(failed.body, {
    error: 'nothing_understood',
    speech:
      'Ich habe nichts verstanden, was auf die Liste soll. Sag zum Beispiel: Milch, zwei Gurken und Klopapier.',
  });
  const get = await answer(handle, new Request('http://local/voice'));
  assertEquals(get.body, { error: 'method', speech: 'Bitte schick den Text per POST.' });
  const tagged = await answer(
    handle,
    post({ text: 'Bitte, danke', lang: 'de' }, { token: 'fgp_pat' }),
  );
  assertEquals(tagged.body, { outcome: 'nothing_understood', ...failed.body });
});

Deno.test('every failure code has a German and an English answer', () => {
  for (const lang of ['de', 'en'] as const) {
    assertEquals(Object.keys(copy[lang].failures).sort(), [...failureCodes].sort(), lang);
    for (const code of failureCodes) {
      assert(copy[lang].failures[code].trim().length > 10, `${lang} ${code}`);
    }
  }
  assertEquals(
    copy.de.failures.premium_required,
    'Sprachbefehle sind Teil von Hummlist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt.',
  );
  assertEquals(
    copy.en.failures.premium_required,
    "Voice commands are part of Hummlist Premium. You can unlock it in the app under More, Hummlist Premium. I didn't add anything.",
  );
});

Deno.test('English failures say that nothing was added', () => {
  for (
    const code of [
      'unauthorized',
      'no_household',
      'no_text',
      'too_long',
      'server',
      'premium_required',
    ] as const
  ) {
    assertMatch(copy.en.failures[code], /nothing was added|didn't add anything/, code);
  }
});

Deno.test('with the gate open (lock off) no request answers premium_required', async () => {
  const reasons: AuthFailure[] = [
    'missing_token',
    'invalid_token',
    'no_household',
    'session_required',
    'user_deleted',
  ];
  const variants: Partial<Deps>[] = [
    {},
    { addItems: () => Promise.reject(new Error('boom')) },
    { readItems: () => Promise.reject(new Error('boom')) },
    { authenticate: () => Promise.reject(new Error('jwks down')) },
    ...reasons.map((r) => ({ authenticate: () => Promise.reject(new AuthError(r, 'test')) })),
  ];
  const texts = [undefined, '', 'milk', 'Milch, Eier und Brot', 'please', 'x '.repeat(600)];
  const outcomes = new Set<string>();
  for (const overrides of variants) {
    const { handle } = fakeDeps(overrides);
    for (const token of Object.keys(tokens)) {
      for (const mode of ['add', 'parse', 'read', 'other']) {
        for (const lang of ['de', 'en']) {
          for (const text of texts) {
            for (const query of ['', '?format=text']) {
              const res = await handle(post({ text, mode, lang }, { token, query }));
              const body = query ? { outcome: res.headers.get('content-type') } : await res.json();
              if (query) await res.body?.cancel();
              outcomes.add(body.outcome);
            }
          }
        }
      }
    }
  }
  assertFalse(outcomes.has('premium_required'));
  for (const seen of ['added', 'nothing_added', 'parsed', 'read', 'server', 'unauthorized']) {
    assert(outcomes.has(seen), seen);
  }
});

Deno.test('events: siri_add for the Siri credential and the Shortcut, nothing for the app', async () => {
  const { handle, events } = fakeDeps();
  await answer(handle, post({ text: 'milk, eggs and bread', lang: 'en' }, { token: 'fgp_siri' }));
  await answer(handle, post({ text: 'Milch' }, { token: 'fgp_pat' }));
  await answer(handle, post({ text: 'please', lang: 'en' }, { token: 'fgp_siri' }));
  await answer(handle, post({ text: '' }, { token: 'fgp_pat' }));
  await answer(handle, post({ text: 'Milch', mode: 'parse' }, { token: 'fgp_siri' }));
  await answer(handle, post({ text: 'Milch' }, { token: 'jwt_session' }));
  await answer(handle, post({ text: 'Milch' }, { token: 'nope' }));
  assertEquals(events, [
    {
      event: 'siri_add',
      result: 'success',
      reason: 'added',
      language: 'en',
      source: 'native',
      count: 3,
    },
    {
      event: 'siri_add',
      result: 'success',
      reason: 'nothing_added',
      language: 'de',
      source: 'shortcut',
      count: 1,
    },
    {
      event: 'siri_add',
      result: 'fail',
      reason: 'nothing_understood',
      language: 'en',
      source: 'native',
      count: 0,
    },
    {
      event: 'siri_add',
      result: 'fail',
      reason: 'no_text',
      language: 'de',
      source: 'shortcut',
      count: 0,
    },
  ]);
});

Deno.test('a failing add: the event, the error report and the log carry no item text', async () => {
  const sent: string[] = [];
  const telemetry = new Telemetry(
    'voice',
    { key: 'phc_testprojectkey0123456789', host: 'https://eu.i.posthog.com', internal: false },
    ((_url: string, init?: RequestInit) => {
      sent.push(String(init?.body));
      return Promise.resolve(new Response('{}'));
    }) as typeof fetch,
  );
  const subject = { installId: '0b6f7a52-6c1e-4f4e-9d55-3f1f0c2a9e01', householdId: null };
  const logged: unknown[][] = [];
  const log = console.error;
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    const { handle } = fakeDeps({
      addItems: (_c, items) =>
        Promise.reject(
          new TypeError(`cannot add ${items.map((i) => i.name).join(' ')} "Hafermilch"`),
        ),
      report: (e) => telemetry.exception(e),
      track: (_c, { event, ...properties }) => {
        assert(telemetry.event(event, subject, properties), 'the catalog takes the event');
        return Promise.resolve();
      },
    });
    const { status, body } = await answer(
      handle,
      post({ text: 'Hafermilch and Zimtschnecken', lang: 'en' }),
    );
    assertEquals([status, body.outcome], [500, 'server']);
    await telemetry.flush();
  } finally {
    console.error = log;
  }
  const batch = JSON.parse(sent[0]).batch as {
    event: string;
    properties: Record<string, unknown>;
  }[];
  assertEquals(batch.map((e) => e.event), ['$exception', 'siri_add']);
  assertEquals(batch[1].properties.reason, 'server');
  assertEquals(batch[1].properties.count, 2);
  const everything = sent.join('') + JSON.stringify(logged.map((args) => args.map(String)));
  for (const secret of ['Hafermilch', 'Zimtschnecken']) {
    assertFalse(everything.includes(secret), secret);
  }
  assert(logged.length > 0, 'the failure is logged');
});

Deno.test('every event the handler builds passes the server catalog', () => {
  const subject = {
    distinct_id: '0b6f7a52-6c1e-4f4e-9d55-3f1f0c2a9e01',
  };
  const adds = ['added', 'nothing_added', 'no_text', 'too_long', 'nothing_understood', 'server'];
  for (const reason of adds) {
    for (const language of ['en', 'de']) {
      for (const source of ['native', 'shortcut']) {
        checkServerEvent('siri_add', {
          ...subject,
          result: 'fail',
          reason,
          language,
          source,
          count: 30,
        });
      }
    }
  }
  for (const reason of ['read', 'server']) {
    checkServerEvent('siri_read', {
      ...subject,
      result: 'success',
      reason,
      language: 'en',
      source: 'native',
      count: 250,
    });
  }
});

/** Butter Weihenstephan is open: a plain "Butter" is held unless the request is the yes. */
const withBrandedButter =
  (calls: { addVariants?: boolean }[] = []): Deps['addItems'] => (_caller, items, options = {}) => {
    calls.push(options);
    return Promise.resolve(items.map((item): Added => {
      const butter = item.name.toLowerCase() === 'butter' && !options.addVariants;
      return butter
        ? {
          name: 'Butter',
          quantity: null,
          brand: 'Weihenstephan',
          properties: null,
          category: 'Kühlregal',
          alreadyOnList: true,
          similarOnList: [],
          held: item,
        }
        : {
          ...item,
          brand: null,
          properties: null,
          category: 'Sonstiges',
          alreadyOnList: false,
          similarOnList: [],
          held: null,
        };
    }));
  };

Deno.test('Q79: a client that can ask gets one yes/no question for a branded open item', async () => {
  const { handle, events } = fakeDeps({ addItems: withBrandedButter() });
  const de = await answer(handle, post({ text: 'Milch und Butter', lang: 'de', ask: true }));
  assertEquals(de.status, 200);
  assertEquals(de.body.outcome, 'confirm');
  assertEquals(
    de.body.question,
    'Hinzugefügt: Milch. Butter Weihenstephan steht schon drauf. Soll ich Butter trotzdem dazuschreiben?',
  );
  assertEquals(de.body.speech, 'Hinzugefügt: Milch. Schon auf der Liste: Butter Weihenstephan.');
  assertEquals(de.body.again, 'Butter');
  assertEquals(events.at(-1)?.reason, 'added', 'the event keeps its reasons');

  const en = await answer(handle, post({ text: 'two butter', lang: 'en', ask: true }));
  assertEquals(en.body.outcome, 'confirm');
  assertEquals(
    en.body.question,
    'Butter Weihenstephan is already on the list. Should I add 2 butter anyway?',
  );
  assertEquals(en.body.speech, 'Already on the list: Butter Weihenstephan.');
  assertEquals(en.body.again, '2 butter');
  assertEquals(events.at(-1)?.reason, 'nothing_added');
});

Deno.test('Q79: the yes resends the held items with confirmed and adds them as said', async () => {
  const calls: { addVariants?: boolean }[] = [];
  const { handle } = fakeDeps({ addItems: withBrandedButter(calls) });
  const { body } = await answer(
    handle,
    post({ text: 'Butter', lang: 'de', ask: true, confirmed: true }),
  );
  assertEquals(calls.at(-1), { addVariants: true });
  assertEquals(body.outcome, 'added');
  assertEquals(body.speech, 'Hinzugefügt: Butter.');
});

Deno.test('Q79: no question without ask (Shortcut, older apps): nothing added, already there', async () => {
  const calls: { addVariants?: boolean }[] = [];
  const { handle } = fakeDeps({ addItems: withBrandedButter(calls) });
  const native = await answer(handle, post({ text: 'Butter', lang: 'de' }));
  assertEquals(native.body.outcome, 'nothing_added');
  assertEquals(native.body.speech, 'Schon auf der Liste: Butter Weihenstephan.');
  assertFalse('question' in native.body);
  const shortcut = await answer(handle, post({ text: 'Butter', ask: true }, { token: 'fgp_pat' }));
  assertEquals(shortcut.body, {
    speech: 'Schon auf der Liste: Butter Weihenstephan.',
    items: shortcut.body.items,
    truncated: false,
  });
  assertEquals(calls.map((c) => c.addVariants), [false, false], 'confirmed only counts with lang');
  assertFalse(
    [...native.body.items, ...shortcut.body.items].some((i: object) => 'held' in i),
    'held stays on the server: the answer keeps its shape',
  );
});
