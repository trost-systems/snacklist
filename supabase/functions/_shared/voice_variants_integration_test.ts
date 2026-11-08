// Job 112, Peter Q79 (Addendum 1 and 3): a plain name said while the same name is open. The open
// items are stored by the real parser (public.add_item), and every request goes through the real
// handlers: the Shortcut, native Siri with ask, and Alexa, in German and English. A brand or a
// note (Bio) asks; product words the parser also keeps in properties (gesalzen, passiert,
// laktosefrei) are another product and add. Runs like add_paths_integration_test.ts: the db gate
// sets FG_DB_TEST=1 and SUPABASE_DB_URL; skipped without them.
import { assert, assertEquals, assertExists, assertFalse } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl, oneRow } from './db.ts';
import { addItems, splitItems } from '../voice/items.ts';
import { type Caller, createHandler as voiceHandler } from '../voice/handler.ts';
import { createHandler as alexaHandler, type Linked } from '../alexa/handler.ts';
import type { Envelope } from '../alexa/verify.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Household = { userId: string; householdId: string };

async function withHousehold(open: string, work: (h: Household) => Promise<void>) {
  const admin = postgres(databaseUrl(), { max: 1, prepare: false });
  const userId = crypto.randomUUID();
  try {
    await admin`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const { id } = oneRow(
        await tx<{ id: string }[]>`select id from public.create_household('112')`,
        'create_household',
      );
      await tx`select 1 from public.add_item(${id}, ${open})`;
      return id;
    });
    await work({ userId, householdId });
  } finally {
    await admin`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await admin`delete from auth.users where id = ${userId}`;
    await admin.end();
  }
}

const openItems = ({ userId, householdId }: Household) =>
  asUser(userId, (tx) =>
    tx<{ name: string; brand: string | null; properties: string | null }[]>`
      select name, brand, properties from public.items
      where household_id = ${householdId} and status = 'active' order by created_at`);

const add = (h: Household) =>
(_: unknown, items: Parameters<typeof addItems>[2], options?: {
  addVariants?: boolean;
}) => asUser(h.userId, (tx) => addItems(tx, h.householdId, items, options));

/** POST /voice: the Shortcut (a PAT, no lang) or native Siri (lang, ask, confirmed). */
async function siri(h: Household, body: Record<string, unknown>) {
  const handle = voiceHandler<Caller>({
    authenticate: () =>
      Promise.resolve({
        userId: h.userId,
        householdId: h.householdId,
        via: body.lang ? 'siri' : 'pat',
      }),
    requirePremium: () => Promise.resolve('open'),
    isMember: () => Promise.resolve(false),
    addItems: add(h),
    splitItems: (auth, parsed) =>
      asUser(auth.userId, (tx) => splitItems(tx, auth.householdId, parsed)),
  });
  const res = await handle(
    new Request('http://local/voice', {
      method: 'POST',
      headers: { authorization: 'Bearer test', 'content-type': 'application/json' },
      body: JSON.stringify(body),
    }),
  );
  return await res.json();
}

type AlexaReply = { speech: string; asks: boolean; again: string };

/** POST /alexa with AddItemIntent (or the session's end), confirmationStatus as given. */
async function alexa(
  h: Household,
  locale: string,
  text: string,
  status?: string,
): Promise<AlexaReply>;
async function alexa(h: Household, locale: string, text: null): Promise<null>;
async function alexa(
  h: Household,
  locale: string,
  text: string | null,
  status = 'NONE',
): Promise<AlexaReply | null> {
  const linked: Linked = { userId: h.userId, householdId: h.householdId, sessionId: 's' };
  const handle = alexaHandler({
    verify: (_headers, raw) =>
      Promise.resolve(JSON.parse(new TextDecoder().decode(raw)) as Envelope),
    authenticate: () => Promise.resolve(linked),
    takeAdds: () => Promise.resolve(true),
    addItems: add(h),
    listItems: () => Promise.resolve([]),
    remember: () => Promise.resolve(),
    revoke: () => Promise.resolve(),
    counted: () => Promise.resolve(),
    report: (e) => {
      throw e;
    },
    log: () => {},
  });
  const user = { userId: 'amzn1.ask.account.TEST', accessToken: 'token' };
  const request = text === null
    ? { type: 'SessionEndedRequest', reason: 'EXCEEDED_MAX_REPROMPTS' }
    : {
      type: 'IntentRequest',
      intent: {
        name: 'AddItemIntent',
        confirmationStatus: status,
        slots: { items: { name: 'items', value: text } },
      },
    };
  const res = await handle(
    new Request('http://local/alexa', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        version: '1.0',
        session: { new: status === 'NONE', sessionId: 's1', user, application: {} },
        context: { System: { user, application: {} } },
        request: {
          requestId: 'r1',
          timestamp: new Date().toISOString(),
          locale,
          ...request,
        },
      }),
    }),
  );
  if (text === null) return null;
  const body = await res.json();
  return {
    speech: body.response.outputSpeech?.text as string,
    asks: body.response.directives?.[0]?.type === 'Dialog.ConfirmIntent',
    again: body.response.directives?.[0]?.updatedIntent?.slots?.items?.value as string,
  };
}

const languages = [
  { lang: 'de', locale: 'de-DE' },
  { lang: 'en', locale: 'en-US' },
] as const;

// Product words: the parser stores them in properties like a note, but they make another product.
for (
  const [open, said, shown] of [
    ['Butter gesalzen', 'Butter', 'Butter gesalzen'],
    ['Tomaten passiert', 'Tomaten', 'Tomaten passiert'],
    ['Milch laktosefrei', 'Milch', 'Milch laktosefrei'],
    ['Butter Weihenstephan gesalzen', 'Butter', 'Butter Weihenstephan gesalzen'],
    ['Bio Milch laktosefrei', 'Milch', 'Milch Bio laktosefrei'],
  ] as const
) {
  for (const { lang, locale } of languages) {
    const paths = {
      // The open one is named in full: never "Hinzugefügt: Butter. Schon auf der Liste: Butter."
      Shortcut: async (h: Household) => {
        const shortcut = await siri(h, { text: said });
        assertEquals(shortcut.speech, `Hinzugefügt: ${said}. Schon auf der Liste: ${shown}.`);
        assertFalse('question' in shortcut);
      },
      'native Siri': async (h: Household) => {
        const native = await siri(h, { text: said, lang, ask: true });
        assertEquals(native.outcome, 'added', JSON.stringify(native));
        assertFalse('question' in native);
        assert(native.speech.endsWith(`: ${shown}.`), native.speech);
      },
      Alexa: async (h: Household) => {
        const fromAlexa = await alexa(h, locale, said);
        assertFalse(fromAlexa.asks, fromAlexa.speech);
        assert(fromAlexa.speech.endsWith(` ${shown}.`), fromAlexa.speech);
      },
    };
    for (const [path, send] of Object.entries(paths)) {
      Deno.test({
        name: `Q79 rule 2 (${lang}, ${path}): "${said}" with "${open}" open adds, no question`,
        ignore: !enabled,
        sanitizeResources: false,
        fn: () =>
          withHousehold(open, async (h) => {
            const [before] = await openItems(h);
            assertExists(before, 'the open item');
            assert(before.properties, `the parser kept a property: ${JSON.stringify(before)}`);
            await send(h);
            const after = await openItems(h);
            assertEquals(after.length, 2, 'added');
            assertEquals(after[0], before, 'the open item is unchanged');
          }),
      });
    }
  }
}

// The open item has a brand or the note Bio: ask; yes adds, no and no answer add nothing.
for (
  const [open, said, shown] of [
    ['Butter Weihenstephan', 'Butter', 'Butter Weihenstephan'],
    ['Bio Tomaten', 'Tomaten', 'Tomaten Bio'],
  ] as const
) {
  for (const { lang, locale } of languages) {
    Deno.test({
      name: `Q79 rule 3 (${lang}): "${said}" with "${open}" open asks; yes, no and no answer`,
      ignore: !enabled,
      sanitizeResources: false,
      fn: () =>
        withHousehold(open, async (h) => {
          const before = await openItems(h);
          const already = lang === 'de' ? 'Schon auf der Liste' : 'Already on the list';
          const shortcut = await siri(h, { text: said });
          assertEquals(shortcut.speech, `Schon auf der Liste: ${shown}.`);
          const native = await siri(h, { text: said, lang, ask: true });
          assertEquals(native.outcome, 'confirm');
          assertEquals(native.speech, `${already}: ${shown}.`, 'what a no says');
          assert(native.question.startsWith(shown), native.question);
          const asked = await alexa(h, locale, said);
          assert(asked.asks, asked.speech);
          assert(asked.speech.startsWith(shown), asked.speech);
          const no = await alexa(h, locale, asked.again, 'DENIED');
          assertFalse(no.asks);
          assert(no.speech.endsWith(`${shown}.`), no.speech);
          await alexa(h, locale, null);
          assertEquals(await openItems(h), before, 'Shortcut, no and no answer add nothing');

          const yes = await siri(h, { text: native.again, lang, confirmed: true });
          assertEquals(yes.outcome, 'added');
          assertEquals((await openItems(h)).length, 2, 'the yes adds a second item');
          assertEquals((await openItems(h))[0], before[0], 'the open item is unchanged');
        }),
    });
  }
}

Deno.test({
  name: 'Q79: Alexa yes adds a second item next to the branded one',
  ignore: !enabled,
  sanitizeResources: false,
  fn: () =>
    withHousehold('Butter Weihenstephan', async (h) => {
      const asked = await alexa(h, 'de-DE', 'Butter');
      const yes = await alexa(h, 'de-DE', asked.again, 'CONFIRMED');
      assertEquals(yes.speech, 'Ich habe Butter auf die Hummlist gesetzt.');
      assertEquals((await openItems(h)).map((i) => [i.name, i.brand]), [
        ['Butter', 'Weihenstephan'],
        ['Butter', null],
      ]);
    }),
});
