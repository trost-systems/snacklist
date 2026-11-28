// Job 207: AddToListIntent's list slot, or a list phrase Alexa heard inside the items, names the
// list an add goes to; without one it goes to the user's default list. An unknown or ambiguous
// name adds to the default list and says so; Q79's yes stays on the list the question was about.
import { assertEquals } from '@std/assert';
import type { ListCatalog, ListOption } from '../_shared/list.ts';
import type { Added } from '../voice/handler.ts';
import type { ParsedItem } from '../voice/parse.ts';
import { createHandler, type Deps } from './handler.ts';
import { testSkillId } from './test_ca.ts';
import type { Envelope } from './verify.ts';

const main: ListOption = {
  id: '00000000-0000-4000-8000-0000000000b1',
  name: 'Einkaufsliste',
  seedKey: 'main',
};
const alltag: ListOption = {
  id: '00000000-0000-4000-8000-0000000000b2',
  name: 'Alltag',
  seedKey: null,
};
const geburtstag: ListOption = {
  id: '00000000-0000-4000-8000-0000000000b3',
  name: 'Geburtstag',
  seedKey: null,
};
const party: ListOption = {
  id: '00000000-0000-4000-8000-0000000000b4',
  name: 'Party',
  seedKey: null,
};
const party2: ListOption = {
  id: '00000000-0000-4000-8000-0000000000b5',
  name: 'party',
  seedKey: null,
};

/** Peter's household: the seeded list first, Alltag his default. */
const peters: ListCatalog = { lists: [main, alltag, geburtstag], defaultList: alltag };

interface Reply {
  sessionAttributes?: Record<string, unknown>;
  response: {
    outputSpeech?: { text: string };
    directives?: { type: string; updatedIntent?: Record<string, unknown> }[];
  };
}

function world(catalog: ListCatalog = peters) {
  const adds: { list: string; names: string[]; addVariants: boolean }[] = [];
  const deps: Deps = {
    verify: (_headers, body) =>
      Promise.resolve(JSON.parse(new TextDecoder().decode(body)) as Envelope),
    authenticate: () => Promise.resolve({ userId: 'peter', householdId: 'h1', sessionId: 's' }),
    takeAdds: () => Promise.resolve(true),
    lists: () => Promise.resolve(catalog),
    addItems: (_linked, items: ParsedItem[], { list, addVariants = false }) => {
      adds.push({ list, names: items.map((i) => i.name), addVariants });
      return Promise.resolve(items.map((item): Added => {
        const held = item.name === 'Butter' && !addVariants;
        return {
          ...item,
          brand: held ? 'Weihenstephan' : null,
          properties: null,
          category: 'Sonstiges',
          alreadyOnList: held,
          similarOnList: [],
          ...(held && { held: item }),
        };
      }));
    },
    listItems: () => Promise.resolve([]),
    remember: () => Promise.resolve(),
    revoke: () => Promise.resolve(),
    counted: () => Promise.resolve(),
    report: (e) => {
      throw e;
    },
    log: () => {},
  };
  const handle = createHandler(deps);
  const send = async (
    intent: { name: string; items?: string; list?: string; status?: string },
    { locale = 'de-DE', attributes }: { locale?: string; attributes?: Record<string, unknown> } =
      {},
  ): Promise<Reply> => {
    const user = { userId: 'amzn1.ask.account.PETER', accessToken: 'tok' };
    const phraseSlot = intent.name === 'AddToListIntent' ? 'itemphrase' : 'items';
    const slots: Record<string, { name: string; value?: string }> = {
      [phraseSlot]: {
        name: phraseSlot,
        ...(intent.items !== undefined && { value: intent.items }),
      },
      ...(intent.name === 'AddToListIntent' && {
        list: { name: 'list', ...(intent.list !== undefined && { value: intent.list }) },
      }),
    };
    const res = await handle(
      new Request('http://local/alexa', {
        method: 'POST',
        body: JSON.stringify({
          version: '1.0',
          session: {
            new: !attributes,
            application: { applicationId: testSkillId },
            attributes,
            user,
          },
          context: { System: { application: { applicationId: testSkillId }, user } },
          request: {
            type: 'IntentRequest',
            requestId: 'amzn1.echo-api.request.1',
            timestamp: new Date().toISOString(),
            locale,
            intent: { name: intent.name, confirmationStatus: intent.status ?? 'NONE', slots },
          },
        }),
      }),
    );
    return await res.json();
  };
  return { send, adds };
}

const said = (r: Reply) => r.response.outputSpeech?.text;

Deno.test("Peter's sentence, in AddToListIntent's slots or swallowed into AddItemIntent's, lands on Geburtstag", async () => {
  const { send, adds } = world();
  const slotted = await send({ name: 'AddToListIntent', items: 'luftballons', list: 'geburtstag' });
  const swallowed = await send({
    name: 'AddItemIntent',
    items: 'luftballons zur geburtstag liste',
  });
  assertEquals(adds, [
    { list: geburtstag.id, names: ['Luftballons'], addVariants: false },
    { list: geburtstag.id, names: ['Luftballons'], addVariants: false },
  ]);
  for (const reply of [slotted, swallowed]) {
    assertEquals(said(reply), 'Ich habe Luftballons auf die Liste Geburtstag gesetzt.');
  }
});

Deno.test('the list slot keeps a trailing Liste and wins over a phrase in the items', async () => {
  const { send, adds } = world();
  await send({ name: 'AddToListIntent', items: 'kerzen', list: 'Geburtstag Liste' });
  await send({ name: 'AddToListIntent', items: 'kerzen zur alltag liste', list: 'geburtstag' });
  assertEquals(adds.map((a) => [a.list, a.names]), [
    [geburtstag.id, ['Kerzen']],
    [geburtstag.id, ['Kerzen']],
  ]);
});

Deno.test('no list named: the default list, not the first, and Alexa names it', async () => {
  const { send, adds } = world();
  const reply = await send({ name: 'AddItemIntent', items: 'milch und eier' });
  assertEquals(adds.map((a) => a.list), [alltag.id]);
  // Several lists: "zur einkaufsliste" in a sample never reaches us, so say where it went (review 0).
  assertEquals(said(reply), 'Ich habe Milch und Eier auf die Liste Alltag gesetzt.');
});

Deno.test('the only list: the speech of before', async () => {
  const { send } = world({ lists: [main], defaultList: main });
  const reply = await send({ name: 'AddItemIntent', items: 'milch' });
  assertEquals(said(reply), 'Ich habe Milch auf die Snacklist gesetzt.');
});

Deno.test('unknown or ambiguous: the default list, and Alexa says so', async () => {
  const { send, adds } = world({ lists: [main, alltag, party, party2], defaultList: alltag });
  const unknown = await send({ name: 'AddToListIntent', items: 'luftballons', list: 'geburtstag' });
  const ambiguous = await send({ name: 'AddToListIntent', items: 'luftballons', list: 'party' });
  const english = await send(
    { name: 'AddToListIntent', items: 'balloons', list: 'birthday' },
    { locale: 'en-GB' },
  );
  assertEquals(adds.map((a) => a.list), [alltag.id, alltag.id, alltag.id]);
  assertEquals(
    said(unknown),
    'Eine Liste „geburtstag“ habe ich nicht gefunden. Ich habe Luftballons auf die Liste Alltag gesetzt.',
  );
  assertEquals(
    said(ambiguous),
    '„party“ passt zu mehreren Listen. Ich habe Luftballons auf die Liste Alltag gesetzt.',
  );
  assertEquals(
    said(english),
    "I couldn't find a list called birthday. I put balloons on the Alltag list.",
  );
});

Deno.test('English: add balloons to the Birthday list', async () => {
  const birthday: ListOption = { ...geburtstag, name: 'Birthday' };
  const { send, adds } = world({ lists: [main, birthday], defaultList: main });
  const slotted = await send(
    { name: 'AddToListIntent', items: 'balloons', list: 'birthday' },
    { locale: 'en-US' },
  );
  const swallowed = await send(
    { name: 'AddItemIntent', items: 'balloons to the birthday list' },
    { locale: 'en-US' },
  );
  assertEquals(adds.map((a) => [a.list, a.names]), [
    [birthday.id, ['balloons']],
    [birthday.id, ['balloons']],
  ]);
  assertEquals([said(slotted), said(swallowed)], [
    'I put balloons on the Birthday list.',
    'I put balloons on the Birthday list.',
  ]);
});

Deno.test('Q79 on a named list: the question keeps the intent and its list, the yes lands there', async () => {
  const { send, adds } = world();
  const ask = await send({
    name: 'AddToListIntent',
    items: 'milch und butter',
    list: 'geburtstag',
  });
  assertEquals(
    said(ask),
    'Ich habe Milch auf die Liste Geburtstag gesetzt. Butter Weihenstephan steht schon auf der ' +
      'Liste Geburtstag. Soll ich Butter trotzdem dazuschreiben?',
  );
  assertEquals(ask.sessionAttributes, { list: geburtstag.id });
  assertEquals(ask.response.directives, [{
    type: 'Dialog.ConfirmIntent',
    updatedIntent: {
      name: 'AddToListIntent',
      confirmationStatus: 'NONE',
      slots: {
        itemphrase: { name: 'itemphrase', value: 'Butter', confirmationStatus: 'NONE' },
        list: { name: 'list', value: 'geburtstag', confirmationStatus: 'NONE' },
      },
    },
  }]);
  // The session attribute decides, even when the items alone would go to the default list.
  const yes = await send(
    { name: 'AddItemIntent', items: 'Butter', status: 'CONFIRMED' },
    { attributes: ask.sessionAttributes ?? {} },
  );
  assertEquals(adds.map((a) => [a.list, a.addVariants]), [
    [geburtstag.id, false],
    [geburtstag.id, true],
  ]);
  assertEquals(said(yes), 'Ich habe Butter auf die Liste Geburtstag gesetzt.');
});

Deno.test('a list slot without items asks for them on AddToListIntent, the list kept', async () => {
  const { send, adds } = world();
  const reply = await send({ name: 'AddToListIntent', list: 'geburtstag' });
  assertEquals(adds, []);
  assertEquals(reply.response.directives?.[0]?.updatedIntent, {
    name: 'AddToListIntent',
    confirmationStatus: 'NONE',
    slots: {
      itemphrase: { name: 'itemphrase', confirmationStatus: 'NONE' },
      list: { name: 'list', value: 'geburtstag', confirmationStatus: 'NONE' },
    },
  });
});
