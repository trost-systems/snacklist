// Job 397 (AU1): one personal key for MCP and the API against the local stack (FG_DB_TEST=1).
// authenticate() is what the mcp and voice functions call; handle() is the api function. With
// app_switches.unified_keys off, keys stay apart as before; on, each takes the other's keys, and
// a read-only key stays read-only on both.
import { assertEquals, assertExists, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { handle } from '../api/handler.ts';
import { authenticate, AuthError } from './auth.ts';
import { asUser, databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Member = { userId: string; householdId: string };
type Key = { id: string; token: string };

const bearer = (token: string, path = 'http://localhost/mcp') =>
  new Request(path, { method: 'POST', headers: { authorization: `Bearer ${token}` } });

/** A key minted the way the app does: the member's own session, no OAuth client. */
async function mint(
  sql: postgres.Sql,
  member: Member,
  call: 'create_api_token' | 'create_personal_access_token',
  scopes: string[] = [],
): Promise<Key> {
  return await sql.begin(async (tx) => {
    const claims = { sub: member.userId, role: 'authenticated', 'session_id': crypto.randomUUID() };
    await tx`select set_config('role', 'authenticated', true),
                    set_config('request.jwt.claims', ${JSON.stringify(claims)}, true)`;
    const [row] = call === 'create_api_token'
      ? await tx<
        Key[]
      >`select id, token from public.create_api_token('test', ${scopes}, ${member.householdId})`
      : await tx<
        Key[]
      >`select id, token from public.create_personal_access_token('test', ${member.householdId})`;
    assertExists(row);
    return row;
  });
}

function api(token: string, method: string, body?: unknown): Promise<Response> {
  return handle(
    new Request('http://localhost/api/v1/items', {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? null : JSON.stringify(body),
    }),
  );
}

async function withMember(work: (sql: postgres.Sql, member: Member) => Promise<void>) {
  const sql = postgres(databaseUrl(), { max: 2, prepare: false });
  const userId = crypto.randomUUID();
  const keys = ['integration_lock', 'public_api', 'unified_keys'];
  const switches = await sql<{ key: string; enabled: boolean }[]>`
    select key, enabled from public.app_switches where key in ${sql(keys)}`;
  const log = console.log;
  console.log = () => {};
  try {
    await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<
        { id: string }[]
      >`select id from public.create_household(p_name => '397')`;
      assertExists(row);
      return row.id;
    });
    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    await sql`update public.app_switches set enabled = true where key = 'public_api'`;
    await sql`update public.app_switches set enabled = false where key = 'unified_keys'`;
    await work(sql, { userId, householdId });
  } finally {
    console.log = log;
    for (const { key, enabled } of switches) {
      await sql`update public.app_switches set enabled = ${enabled} where key = ${key}`;
    }
    await sql`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await sql`delete from auth.users where id = ${userId}`;
    await sql.end();
  }
}

const unified = (sql: postgres.Sql, on: boolean) =>
  sql`update public.app_switches set enabled = ${on} where key = 'unified_keys'`;

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('switch off: an MCP token works on MCP only, an API key on the API only', () =>
  withMember(async (sql, member) => {
    const mcp = await mint(sql, member, 'create_personal_access_token');
    const key = await mint(sql, member, 'create_api_token', ['read']);

    assertEquals(await authenticate(bearer(mcp.token)), {
      userId: member.userId,
      householdId: member.householdId,
      via: 'pat',
      scopes: ['read', 'write'],
    });
    const refused = await assertRejects(() => authenticate(bearer(key.token)), AuthError);
    assertEquals([refused.reason, refused.detail], ['invalid_token', 'unknown_key']);

    assertEquals((await api(mcp.token, 'GET')).status, 401);
    assertEquals((await api(key.token, 'GET')).status, 200);
  }));

test('switch on: one key works on both, with its scopes', () =>
  withMember(async (sql, member) => {
    const mcp = await mint(sql, member, 'create_personal_access_token');
    const readOnly = await mint(sql, member, 'create_api_token', ['read']);
    const readWrite = await mint(sql, member, 'create_api_token', ['read', 'write']);
    await unified(sql, true);

    assertEquals(await authenticate(bearer(readOnly.token)), {
      userId: member.userId,
      householdId: member.householdId,
      via: 'pat',
      scopes: ['read'],
    });
    assertEquals((await authenticate(bearer(readWrite.token))).via, 'pat');
    assertEquals(await authenticate(bearer(mcp.token)), {
      userId: member.userId,
      householdId: member.householdId,
      via: 'pat',
      scopes: ['read', 'write'],
    });

    assertEquals((await api(mcp.token, 'GET')).status, 200, 'an MCP token reads on the API');
    const added = await api(mcp.token, 'POST', { items: [{ name: 'Milch' }] });
    assertEquals(added.status, 201, 'an MCP token writes on the API');
    const denied = await api(readOnly.token, 'POST', { items: [{ name: 'Brot' }] });
    assertEquals(denied.status, 403);
    assertEquals((await denied.json()).error.code, 'insufficient_scope');

    await unified(sql, false);
    assertEquals((await api(mcp.token, 'GET')).status, 401, 'off again: apart again');
    await assertRejects(() => authenticate(bearer(readOnly.token)), AuthError);
  }));
