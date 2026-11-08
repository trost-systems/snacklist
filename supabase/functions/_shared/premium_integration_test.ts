// Job 50: the integration lock against a database with the repo's migrations, through the
// functions' production wiring. With app_switches.integration_lock off a household without premium
// adds as before; with it on Siri and MCP refuse it, add nothing, and integration_blocked goes
// out once per hour and integration without any content; a yearly plan opens both for the same
// credentials, its lapse locks them again and deletes nothing. Alexa is free (job 72): it adds with
// the switch on, before the plan and after its lapse. The db gate sets
// FG_DB_TEST=1 and SUPABASE_DB_URL; without them this is skipped.
import { assert, assertEquals, assertFalse } from '@std/assert';
import postgres from 'postgres';
import { createMcpHandler } from '@modelcontextprotocol/server';
import { sha256Hex } from './auth.ts';
import { asUser } from './db.ts';
import { requirePremiumWith } from './premium.ts';
import { Telemetry } from './telemetry.ts';
import { productionDeps } from '../alexa/deps.ts';
import { createHandler as alexaHandler, type Linked } from '../alexa/handler.ts';
import { testSkillId } from '../alexa/test_ca.ts';
import type { Envelope } from '../alexa/verify.ts';
import { buildServer, premiumRequired } from '../mcp/tools.ts';
import { copy } from '../voice/copy.ts';
import { createHandler as voiceHandler } from '../voice/handler.ts';
import { addItems, splitItems } from '../voice/items.ts';

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
      await tx`select public.record_analytics_consent(${install}::uuid, true, false, true, '2026-11-01')`;
      return row.id;
    });
    await sql`update public.app_switches set enabled = ${lock} where key = 'integration_lock'`;
    await work({ userId, householdId, install }, sql);
  } finally {
    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    await sql`delete from public.purchases where bound_household in (
      select household_id from public.household_members where user_id = ${userId})`;
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

function voice(m: Member, telemetry: Telemetry) {
  const handle = voiceHandler({
    authenticate: () =>
      Promise.resolve({ userId: m.userId, householdId: m.householdId, via: 'pat' as const }),
    requirePremium: requirePremiumWith(telemetry),
    isMember: () => Promise.resolve(false),
    addItems: (auth, parsed) => asUser(auth.userId, (tx) => addItems(tx, auth.householdId, parsed)),
    splitItems: (auth, parsed) =>
      asUser(auth.userId, (tx) => splitItems(tx, auth.householdId, parsed)),
  });
  return async (text: string) => {
    const res = await handle(
      new Request('http://local/voice', {
        method: 'POST',
        headers: { authorization: 'Bearer fgp_x', 'content-type': 'application/json' },
        body: JSON.stringify({ text }),
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
  const auth = { userId: m.userId, householdId: m.householdId, via: 'pat' as const };
  return async (name: string) => {
    const res = await createMcpHandler(() =>
      buildServer(auth, (householdId) => gate({ userId: auth.userId, householdId }, 'mcp'))
    ).fetch(
      new Request('http://edge/mcp', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json, text/event-stream',
          'mcp-protocol-version': '2025-06-18',
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
        'com.hummlist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute',
        9.99, 'EUR', 'DE', ${m.householdId}::uuid, now(), now() + interval '365 days', true, false)`;

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('switch off: a household without premium adds over Siri, Alexa and MCP as before', () =>
  withHousehold(false, async (m, sql) => {
    const t = recorder();
    assertEquals((await voice(m, t)('Milch')).body.speech, 'Hinzugefügt: Milch.');
    assertEquals(await alexa(m, t)('Eier'), 'Ich habe Eier auf die Hummlist gesetzt.');
    assertFalse((await mcp(m, t)('add_items')).isError);
    assertEquals(await items(sql, m.householdId), ['Milch', 'Eier', 'Kaffee']);
    assertEquals(t.queued.filter((e) => e.event === 'integration_blocked'), []);
    assertEquals(
      (await sql`select count(*)::int as n from public.integration_blocks
                 where household_id = ${m.householdId}`)[0].n,
      0,
    );
  }));

test('switch on: Siri and MCP locked, Alexa still adds (free, job 72), integration_blocked once each', () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const siri = voice(m, t);
    const locked = await siri('Milch, zwei Gurken und Klopapier');
    assertEquals(locked, {
      status: 200,
      body: { error: 'premium_required', speech: copy.de.failures.premium_required },
    });
    await siri('Brot');
    assertEquals(
      await alexa(m, t)('Eier'),
      'Ich habe Eier auf die Hummlist gesetzt.',
      'Alexa is never locked',
    );
    const tool = mcp(m, t);
    for (const name of ['add_items', 'list_items']) {
      const result = await tool(name);
      assertEquals(result.isError, true);
      assertEquals(result.content[0].text, premiumRequired.de);
    }
    assertEquals(await items(sql, m.householdId), ['Eier'], 'only the Alexa add went through');

    const blocked = t.queued.filter((e) => e.event === 'integration_blocked');
    assertEquals(
      blocked.map((e) => (e.properties as Record<string, unknown>).integration),
      ['siri', 'mcp'],
      'once per locked integration within the hour',
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

test('a yearly plan opens Siri and MCP with the same credentials; its lapse locks them and deletes nothing', () =>
  withHousehold(true, async (m, sql) => {
    const t = recorder();
    const tx = `y50-${m.householdId.slice(0, 8)}`;
    await sql`insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint)
              values (${m.householdId}, ${m.userId}, 'Kurzbefehl', ${
      crypto.randomUUID().replaceAll('-', '').padEnd(64, '5')
    }, '5050')`;
    assertEquals((await voice(m, t)('Brot')).body.error, 'premium_required');

    await yearly(sql, m, tx);
    assertEquals((await voice(m, t)('Milch')).body.speech, 'Hinzugefügt: Milch.');
    assertEquals(await alexa(m, t)('Eier'), 'Ich habe Eier auf die Hummlist gesetzt.');
    assertFalse((await mcp(m, t)('list_items')).isError);

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '1 second',
                now() - interval '1 minute', false, false)`;
    assertEquals((await voice(m, t)('Brot')).body.error, 'premium_required');
    assertEquals((await mcp(m, t)('list_items')).isError, true);
    assertEquals(
      await alexa(m, t)('Käse'),
      'Ich habe Käse auf die Hummlist gesetzt.',
      'lapsed: Alexa stays open',
    );
    assertEquals(await items(sql, m.householdId), ['Milch', 'Eier', 'Käse'], 'the list is kept');
    const [kept] = await sql<{ tokens: number; rows: number }[]>`
      select (select count(*)::int from public.personal_access_tokens
              where household_id = ${m.householdId} and revoked_at is null) as tokens,
             (select count(*)::int from public.entitlements where household_id = ${m.householdId}) as rows`;
    assertEquals(kept, { tokens: 1, rows: 1 }, 'the token and the plan row stay');

    await sql`select public.purchase_lifecycle('apple', ${tx}, now() + interval '2 seconds',
                now() + interval '365 days', true, false)`;
    assertEquals((await voice(m, t)('Brot')).body.speech, 'Hinzugefügt: Brot.');
    assert(!(await mcp(m, t)('list_items')).isError, 'renewed: open again, nothing to relink');
  }));
