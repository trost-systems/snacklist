// Job 172: a voice read-back names and counts the open items of the caller's household only, not
// ticked ones (today's or older) and not another household's. The household is shaped like the
// one Peter heard "26" for: 3 open, 1 ticked today, 23 ticked before. Alexa and Siri run their
// production wiring (deps.ts), MCP's list_items the shared query; local stack, FG_DB_TEST=1.
import { assert, assertEquals, assertExists } from '@std/assert';
import postgres from 'postgres';
import { productionDeps as alexaDeps } from '../alexa/deps.ts';
import { createHandler as alexaHandler } from '../alexa/handler.ts';
import { testSkillId } from '../alexa/test_ca.ts';
import type { Envelope } from '../alexa/verify.ts';
import { productionDeps as voiceDeps } from '../voice/deps.ts';
import { createHandler as voiceHandler } from '../voice/handler.ts';
import { asUser, databaseUrl } from './db.ts';
import { addItems, listItems, tickItems } from './list.ts';
import { telemetryFor } from './telemetry.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const off = telemetryFor('test', { get: () => undefined });

async function alexaRead(userId: string, householdId: string): Promise<string> {
  const handle = alexaHandler({
    ...alexaDeps(
      off,
      (_h, body) => Promise.resolve(JSON.parse(new TextDecoder().decode(body)) as Envelope),
      () => Promise.resolve({ userId, householdId, sessionId: crypto.randomUUID() }),
    ),
    remember: () => Promise.resolve(),
  });
  const res = await handle(
    new Request('http://local/alexa', {
      method: 'POST',
      body: JSON.stringify({
        version: '1.0',
        context: {
          System: { application: { applicationId: testSkillId }, user: { accessToken: 't' } },
        },
        request: {
          type: 'IntentRequest',
          timestamp: new Date().toISOString(),
          locale: 'de-DE',
          intent: { name: 'ReadListIntent' },
        },
      }),
    }),
  );
  return (await res.json()).response.outputSpeech.text;
}

async function siriRead(userId: string, householdId: string) {
  const handle = voiceHandler(
    voiceDeps(off, () => Promise.resolve({ userId, householdId, via: 'siri' as const })),
  );
  const res = await handle(
    new Request('http://local/voice', {
      method: 'POST',
      headers: { authorization: 'Bearer x', 'content-type': 'application/json' },
      body: JSON.stringify({ mode: 'read' }),
    }),
  );
  assertEquals(res.status, 200);
  return await res.json() as { speech: string; items: { name: string }[]; total: number };
}

Deno.test({
  name: 'Alexa, Siri and list_items read only the open items of the caller household',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const admin = postgres(databaseUrl(), { max: 1, prepare: false });
    const [me, them] = [crypto.randomUUID(), crypto.randomUUID()];
    try {
      const households: string[] = [];
      for (const user of [me, them]) {
        await admin`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
        households.push(
          await asUser(user, async (tx) => {
            const [row] = await tx<{ id: string }[]>`select id from public.create_household('172')`;
            assertExists(row);
            return row.id;
          }),
        );
      }
      const [mine, theirs] = households;
      assertExists(mine);
      assertExists(theirs);
      await asUser(them, (tx) => addItems(tx, theirs, [{ name: 'Brot' }, { name: 'Käse' }]));

      const before = Array.from({ length: 23 }, (_, i) => `Vorrat ${i + 1}`);
      await asUser(me, async (tx) => {
        await addItems(tx, mine, [...before, 'Spülmittel'].map((name) => ({ name })));
        await tickItems(tx, mine, [...before, 'Spülmittel']);
        await addItems(tx, mine, [{ name: 'Milch' }, { name: 'Eier' }, { name: 'Tomaten' }]);
      });
      await admin`update public.items set bought_at = now() - interval '3 days'
                  where household_id = ${mine} and name like 'Vorrat %'`;
      const [rows] = await admin<{ all: number; open: number }[]>`
        select count(*)::int as all, count(*) filter (where status = 'active')::int as open
        from public.items where household_id = ${mine}`;
      assertEquals(rows, { all: 27, open: 3 }, 'the household has ticked items next to the open');

      const open = ['Eier', 'Milch', 'Tomaten'];

      const alexa = await alexaRead(me, mine);
      assert(alexa.startsWith('Auf der Hummlist stehen 3 Sachen: '), alexa);
      for (const name of open) assert(alexa.includes(name), alexa);
      for (const name of ['Spülmittel', 'Vorrat', 'Brot', 'Käse']) {
        assert(!alexa.includes(name), alexa);
      }

      const siri = await siriRead(me, mine);
      assertEquals(siri.total, 3);
      assertEquals(siri.items.map((i) => i.name).sort(), open);
      assert(!siri.speech.includes('Spülmittel') && !siri.speech.includes('Brot'), siri.speech);

      const list = await asUser(me, (tx) => listItems(tx, mine, {}));
      assertEquals(list.items.map((i) => i.name).sort(), open);
      assertEquals(list.counts, { open: 3, checkedLast24h: 1 });
    } finally {
      await admin`delete from public.households where id in (
        select household_id from public.household_members where user_id = any(${[me, them]}))`;
      await admin`delete from auth.users where id = any(${[me, them]})`;
      await admin.end();
    }
  },
});
