// Job 50: the integration lock against a database with the repo's migrations, through the
// functions' production wiring. With app_switches.integration_lock off a household without premium
// adds as before; with it on MCP refuses it, adds nothing, and integration_blocked goes out once
// per hour and integration without any content; a yearly plan opens it for the same credentials,
// its lapse locks it again and deletes nothing. Siri (job 184) and Alexa (job 72) are free: they
// add and read with the switch on, before the plan and after its lapse. The db gate sets
// FG_DB_TEST=1 and SUPABASE_DB_URL; without them this is skipped.
import { assert, assertEquals, assertFalse } from '@std/assert';
import postgres from 'postgres';
import { createMcpHandler } from '@modelcontextprotocol/server';
import { sha256Hex } from './auth.ts';
import { CONSENT_TEXT_VERSION } from './consent_version.ts';
import { asUser } from './db.ts';
import { requirePremiumWith } from './premium.ts';
import { Telemetry } from './telemetry.ts';
import { userEvents } from './user_events.ts';
import { productionDeps } from '../alexa/deps.ts';
import { createHandler as alexaHandler, type Linked } from '../alexa/handler.ts';
import { testSkillId } from '../alexa/test_ca.ts';
import type { Envelope } from '../alexa/verify.ts';
import { buildServer, premiumRequired, reportToolCalls } from '../mcp/tools.ts';
import { productionDeps as voiceDeps } from '../voice/deps.ts';
import { createHandler as voiceHandler } from '../voice/handler.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const admin = () => postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 1, prepare: false });

interface Member {
  userId: string;
  householdId: string;
  install: string;
}

/** A user with a fresh household who said yes to analytics, the switch as given, removed after. */
async function withHousehold(lock: boolean, work: (m: Member, sql: postgres.Sql) => Promise<void>) {
  const sql = admin();
  const userId = crypto.randomUUID();
  const install = crypto.randomUUID();
  try {
    await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`select id from public.create_household('50')`;
      await tx`select public.record_analytics_consent(${install}::uuid, true, false, true, ${CONSENT_TEXT_VERSION})`;
      return row.id;
    });
    await sql`update public.app_switches set enabled = ${lock} where key = 'integration_lock'`;
    await work({ userId, householdId, install }, sql);
  } finally {
    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    await sql`delete from public.purchases where bound_household in (
      select household_id from public.household_members where user_id = ${userId})`;
    await sql`delete from public.purchases where bound_user = ${userId}`;
    await sql`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await sql`delete from auth.users where id = ${userId}`;
    await sql.end();
  }
}

function recorder() {
  return new Telemetry('test', {
    key: 'phc_test',
    host: 'https://eu.i.posthog.com',
    internal: true,
  });
}

const items = (sql: postgres.Sql, householdId: string) =>
  sql<{ name: string }[]>`select name from public.items where household_id = ${householdId}
                          order by created_at, name`.then((rows) => rows.map((r) => r.name));

/** Siri through the voice function's production deps, signed in with the app's Siri credential. */
function voice(m: Member, telemetry: Telemetry) {
  const handle = voiceHandler(
    voiceDeps(
      telemetry,
      () => Promise.resolve({ userId: m.userId, householdId: m.householdId, via: 'siri' as const }),
    ),
  );
  return async (text: string, mode: 'add' | 'read' = 'add') => {
    const res = await handle(
      new Request('http://local/voice', {
        method: 'POST',
        headers: { authorization: 'Bearer fgp_x', 'content-type': 'application/json' },
        body: JSON.stringify({ text, mode, lang: 'de' }),
      }),
    );
    return { status: res.status, body: await res.json() };
  };
}

function alexa(m: Member, telemetry: Telemetry) {
  const linked: Linked = { userId: m.userId, householdId: m.householdId, sessionId: m.install };
  const handle = alexaHandler({
    ...productionDeps(
      telemetry,
      (_h, body) => Promise.resolve(JSON.parse(new TextDecoder().decode(body)) as Envelope),
      () => Promise.resolve(linked),
    ),
    remember: () => Promise.resolve(),
  });
  return async (value: string) => {
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
            intent: { name: 'AddItemIntent', slots: { items: { name: 'items', value } } },
          },
        }),
      }),
    );
    return (await res.json()).response.outputSpeech.text as string;
  };
}

function mcp(m: Member, telemetry: Telemetry) {
  const gate = requirePremiumWith(telemetry);
  const send = userEvents(telemetry);
  const auth = { userId: m.userId, householdId: m.householdId, via: 'pat' as const };
  return async (name: string) => {
    const res = await createMcpHandler(() =>
      buildServer(
        auth,
        (householdId) => gate({ userId: auth.userId, householdId }, 'mcp'),
        reportToolCalls(send, auth.userId),
      )
    ).fetch(
      new Request('http://edge/mcp', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json, text/event-stream',
          'mcp-protocol-version': '2025-11-25',
        },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'tools/call',
          params: { name, arguments: name === 'add_items' ? { items: [{ name: 'Kaffee' }] } : {} },
        }),
      }),
    );
    assertEquals(res.status, 200);
    const text = await res.text();
    const data = text.split('\n').find((l) => l.startsWith('data: '));
    return JSON.parse(data ? data.slice(6) : text).result as {
      isError?: boolean;
      content: { text: string }[];
    };
  };
}

const yearly = async (sql: postgres.Sql, m: Member, tx: string) =>
  await sql`select public.purchase_record('apple', ${tx}, ${tx}, ${await sha256Hex(tx)},
        'com.snacklist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute',
        9.99, 'EUR', 'DE', ${m.householdId}::uuid, now(), now() + interval '365 days', true, false)`;

/** Job 185: the user's own plan (App User ID = user id), in no household. */
const ownYearly = async (sql: postgres.Sql, m: Member, tx: string) =>
  await sql`select public.purchase_record_user('apple', ${tx}, ${tx}, ${await sha256Hex(tx)},
        'com.snacklist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute',
        9.99, 'EUR', 'DE', ${m.userId}::uuid, now(), now() + interval '365 days', true, false)`;

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('switch off: a household without premium adds over Siri, Alexa and MCP as before', () =>
  withHousehold(false, async (m, sql) => {
    const t = recorder();
    assertEquals((await voice(m, t)('Milch')).body.speech, 'Hinzugefügt: Milch.');
    assertEquals(await alexa(m, t)('Eier'), 'Ich habe Eier auf die Snacklist gesetzt.');
    assertFalse((await mcp(m, t)('add_items')).isError);
    assertEquals(await items(sql, m.householdId), ['Milch', 'Eier', 'Kaffee']);
    assertEquals(t.queued.filter((e) => e.event === 'integration_blocked'), []);
    assertEquals(
      t.queued.filter((e) => e.event === 'mcp_tool_call'),
      [],
      'N-147: mcp_tool_call capture is off',
    );
    assertEquals(
      (await sql`select count(*)::int as n from public.integration_blocks
                 where household_id = ${m.householdId}`)[0].n,
      0,
    );
  }));

test('switch on: Siri and Alexa add and read without premium (free, jobs 184 and 72), MCP locked, integration_blocked once', () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const siri = voice(m, t);
    const added = await siri('Milch, zwei Gurken und Klopapier');
    assertEquals(added.status, 200);
    assertEquals(added.body.outcome, 'added');
    assertEquals(
      await alexa(m, t)('Eier'),
      'Ich habe Eier auf die Snacklist gesetzt.',
      'Alexa is never locked',
    );
    const read = await siri('', 'read');
    assertEquals([read.status, read.body.outcome, read.body.total], [200, 'read', 4]);
    const tool = mcp(m, t);
    for (const name of ['add_items', 'list_items']) {
      const result = await tool(name);
      assertEquals(result.isError, true);
      assertEquals(result.content[0].text, premiumRequired.de);
    }
    assertEquals(
      await items(sql, m.householdId),
      ['Gurken', 'Klopapier', 'Milch', 'Eier'],
      'the Siri and Alexa adds went through, the MCP add did not',
    );
    assertEquals(
      (await sql`select integration from public.integration_blocks
                 where household_id = ${m.householdId}`).map((r) => r.integration),
      ['mcp'],
      'Siri leaves no integration_blocks row',
    );

    const blocked = t.queued.filter((e) => e.event === 'integration_blocked');
    assertEquals(
      blocked.map((e) => (e.properties as Record<string, unknown>).integration),
      ['mcp'],
      'once per locked integration within the hour',
    );
    assertEquals(
      t.queued.filter((e) => e.event === 'mcp_tool_call'),
      [],
      'N-147: mcp_tool_call capture is off, including locked calls',
    );
    for (const e of blocked) {
      const p = e.properties as Record<string, unknown>;
      assertEquals(p.household_id, m.householdId);
      assertEquals(p.distinct_id, m.install);
      const text = JSON.stringify(e);
      for (const word of ['Milch', 'Gurken', 'Eier', 'Kaffee', 'add_items']) {
        assertFalse(text.includes(word), `no ${word} in the event`);
      }
    }
  }));

test('a yearly plan opens MCP with the same credentials; its lapse locks it and deletes nothing, Siri stays open', () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const tx = `y50-${m.householdId.slice(0, 8)}`;
    await sql`insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint)
              values (${m.householdId}, ${m.userId}, 'Kurzbefehl', ${
      crypto.randomUUID().replaceAll('-', '').padEnd(64, '5')
    }, '5050')`;
    assertEquals((await mcp(m, t)('list_items')).isError, true);

    await yearly(sql, m, tx);
    assertEquals((await voice(m, t)('Milch')).body.speech, 'Hinzugefügt: Milch.');
    assertEquals(await alexa(m, t)('Eier'), 'Ich habe Eier auf die Snacklist gesetzt.');
    assertFalse((await mcp(m, t)('list_items')).isError);

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '1 second',
                now() - interval '1 minute', false, false)`;
    assertEquals((await mcp(m, t)('list_items')).isError, true);
    assertEquals(
      (await voice(m, t)('Brot')).body.outcome,
      'added',
      'lapsed: Siri stays open',
    );
    assertEquals(
      await alexa(m, t)('Käse'),
      'Ich habe Käse auf die Snacklist gesetzt.',
      'lapsed: Alexa stays open',
    );
    assertEquals(
      await items(sql, m.householdId),
      ['Milch', 'Eier', 'Brot', 'Käse'],
      'the list is kept',
    );
    const [kept] = await sql<{ tokens: number; rows: number }[]>`
      select (select count(*)::int from public.personal_access_tokens
              where household_id = ${m.householdId} and revoked_at is null) as tokens,
             (select count(*)::int from public.entitlements where household_id = ${m.householdId}) as rows`;
    assertEquals(kept, { tokens: 1, rows: 1 }, 'the token and the plan row stay');

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '2 seconds',
                now() + interval '365 days', true, false)`;
    assert(!(await mcp(m, t)('list_items')).isError, 'renewed: open again, nothing to relink');
  }));

test("job 185: a user's own yearly plan opens MCP; its lapse locks it, Siri, Alexa and the list stay", () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const tx = `u185-${m.userId.slice(0, 8)}`;
    await ownYearly(sql, m, tx);
    assertEquals((await voice(m, t)('Milch')).body.speech, 'Hinzugefügt: Milch.');
    assertFalse((await mcp(m, t)('list_items')).isError);

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '1 second',
                now() - interval '1 minute', false, false)`;
    assertEquals(
      (await voice(m, t)('Brot')).body.speech,
      'Hinzugefügt: Brot.',
      'lapsed: Siri stays free',
    );
    assertEquals((await mcp(m, t)('list_items')).isError, true);
    assertEquals(await alexa(m, t)('Eier'), 'Ich habe Eier auf die Snacklist gesetzt.');
    await asUser(m.userId, (u) =>
      u`update public.items set status = 'bought'
         where household_id = ${m.householdId} and name = 'Milch'`);
    assertEquals(
      (await sql<{ status: string }[]>`select status::text from public.items
         where household_id = ${m.householdId} and name = 'Milch'`)[0]?.status,
      'bought',
      'lapsed: the user still checks items off',
    );

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '2 seconds',
                now() + interval '365 days', true, false)`;
    assertFalse((await mcp(m, t)('list_items')).isError, 'renewed: MCP open again');
  }));

test("job 328 review 0: another member's own plan does not open MCP for you", () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const partner: Member = { ...m, userId: crypto.randomUUID() };
    try {
      await sql`insert into auth.users (id, email)
                values (${partner.userId}, ${`${partner.userId}@fg-test.invalid`})`;
      await sql`insert into public.household_members (household_id, user_id, role)
                values (${m.householdId}, ${partner.userId}, 'member')`;
      await ownYearly(sql, partner, `m328-${partner.userId.slice(0, 8)}`);

      const mine = await mcp(m, t)('list_items');
      assertEquals([mine.isError, mine.content[0]?.text], [true, premiumRequired.de]);
      assertFalse(
        (await mcp(partner, t)('list_items')).isError,
        'the buyer, in the same household',
      );
    } finally {
      await sql`delete from public.purchases where bound_user = ${partner.userId}`;
      await sql`delete from public.household_members where user_id = ${partner.userId}`;
      await sql`delete from auth.users where id = ${partner.userId}`;
    }
  }));
