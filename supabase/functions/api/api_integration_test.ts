// Job 73: the api function through handle() with its production wiring against the local stack
// (FG_DB_TEST=1, see _shared/add_paths_integration_test.ts): keys, limits, idempotency,
// pagination, households, the integration lock and the public_api switch (job 75).
import { assert, assertEquals, assertExists, assertFalse, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { sha256Hex } from '../_shared/auth.ts';
import { asUser, databaseUrl } from '../_shared/db.ts';
import { ADD_BUDGET_MS, SIMILAR_SHOWN } from '../_shared/list.ts';
import { handle } from './handler.ts';
import { routes } from './routes.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Member = { userId: string; householdId: string };
type Item = {
  id: string;
  name: string;
  quantity: string | null;
  status: string;
  store: string | null;
};

function admin() {
  return postgres(databaseUrl(), { max: 2, prepare: false });
}

type Claims = { role: 'authenticated' | 'anon'; sub?: string; [claim: string]: unknown };

/** create_api_token as a caller with [claims]; [household]: the three-argument form. */
async function mintAs(sql: postgres.Sql, claims: Claims, scopes: string[], household?: string) {
  return await sql.begin(async (tx) => {
    await tx`select set_config('role', ${claims.role}, true),
                    set_config('request.jwt.claims', ${JSON.stringify(claims)}, true)`;
    const [row] = household === undefined
      ? await tx<{ id: string; token: string }[]>`
        select id, token from public.create_api_token('test', ${scopes})`
      : await tx<{ id: string; token: string }[]>`
        select id, token from public.create_api_token('test', ${scopes}, ${household})`;
    return row;
  }) as { id: string; token: string };
}

/** The claims of the app's own session: a session id, no OAuth client. */
const appSession = (member: Member): Claims => ({
  sub: member.userId,
  role: 'authenticated',
  session_id: crypto.randomUUID(),
});

/** An API key minted the way the app does: the member's own session, no OAuth client. */
const mint = (sql: postgres.Sql, member: Member, scopes: string[], household?: string) =>
  mintAs(sql, appSession(member), scopes, household);

function api(
  token: string,
  method: string,
  path: string,
  { body, headers = {} }: { body?: unknown; headers?: Record<string, string> } = {},
): Promise<Response> {
  return handle(
    new Request(`http://localhost/api/v1${path}`, {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        ...headers,
      },
      body: body === undefined ? null : JSON.stringify(body),
    }),
  );
}

async function withMembers(
  work: (sql: postgres.Sql, members: [Member, Member]) => Promise<void>,
) {
  const sql = admin();
  const users = [crypto.randomUUID(), crypto.randomUUID()] as const;
  const switches = await sql<{ key: string; enabled: boolean }[]>`
    select key, enabled from public.app_switches where key in ('integration_lock', 'public_api')`;
  const log = console.log;
  console.log = () => {};
  try {
    const join = async (userId: string): Promise<Member> => {
      await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
      const householdId = await asUser(userId, async (tx) => {
        const [row] = await tx<
          { id: string }[]
        >`select id from public.create_household(p_name => '73', p_default_stores => true)`;
        assertExists(row);
        return row.id;
      });
      return { userId, householdId };
    };
    const members: [Member, Member] = [await join(users[0]), await join(users[1])];
    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    await setPublicApi(sql, true);
    await work(sql, members);
  } finally {
    console.log = log;
    for (const { key, enabled } of switches) {
      await sql`update public.app_switches set enabled = ${enabled} where key = ${key}`;
    }
    for (const userId of users) {
      await sql`delete from public.purchases where bound_user = ${userId}`;
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${userId})`;
      await sql`delete from auth.users where id = ${userId}`;
    }
    await sql.end();
  }
}

const setPublicApi = (sql: postgres.Sql, on: boolean) =>
  sql`update public.app_switches set enabled = ${on} where key = 'public_api'`;

/** Fills a key's bucket again, so one test can make more than a burst of requests. */
const refill = (sql: postgres.Sql, tokenId: string) =>
  sql`update public.api_token_buckets set tokens = 20, refilled_at = now() where token_id = ${tokenId}`;

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('add, read, tick, untick and move through the API, one household only', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const other = await mint(sql, theirs, ['read', 'write']);

    const first = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: '2 Gurken' }, { name: 'Zahnpasta', store: 'dm' }] },
    });
    assertEquals(first.status, 201);
    const added = (await first.json()).data.added as Item[];
    assertEquals(added.map((i) => [i.name, i.quantity, i.status]), [
      ['Gurken', '2', 'open'],
      ['Zahnpasta', null, 'open'],
    ]);
    assertEquals(added[1]?.store, 'dm');
    const [gurken] = added;
    assertExists(gurken);
    assert(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?\+00:00$/.test(
        (gurken as unknown as { addedAt: string }).addedAt,
      ),
    );

    const again = await api(key.token, 'POST', '/items', { body: { items: [{ name: 'Gurke' }] } });
    assertEquals(again.status, 200, 'nothing new: 200');
    const againBody = (await again.json()).data;
    assertEquals(againBody.added, []);
    assertEquals(againBody.alreadyOnList.map((i: Item) => i.id), [gurken.id]);

    const unknownStore = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Brot' }, { name: 'Wein', store: 'Rewe' }] },
    });
    assertEquals(unknownStore.status, 422);
    const unknownError = (await unknownStore.json()).error;
    assertEquals(unknownError.code, 'store_not_found');
    assert(unknownError.details.candidates.includes('dm'));
    const [brot] = await sql<{ count: number }[]>`
      select count(*)::int from public.items where household_id = ${mine.householdId} and name = 'Brot'`;
    assertEquals(brot?.count, 0, 'the batch failed as a whole');

    const one = await api(key.token, 'GET', `/items/${gurken.id}`);
    assertEquals((await one.json()).data.name, 'Gurken');

    for (const expected of ['ticked', 'ticked']) {
      const res = await api(key.token, 'POST', `/items/${gurken.id}/tick`);
      assertEquals(res.status, 200);
      assertEquals((await res.json()).data.status, expected);
    }
    const ticked = await api(key.token, 'GET', `/items/${gurken.id}`);
    assertEquals((await ticked.json()).data.status, 'ticked', 'a ticked item can still be read');
    const moveTicked = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { store: null },
    });
    assertEquals(moveTicked.status, 404);
    assertEquals((await moveTicked.json()).error.code, 'item_not_found');
    for (const expected of ['open', 'open']) {
      const res = await api(key.token, 'POST', `/items/${gurken.id}/untick`);
      assertEquals((await res.json()).data.status, expected);
    }

    const moved = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { category: 'Kühlregal', store: 'Lidl' },
    });
    assertEquals(moved.status, 200);
    const movedItem = (await moved.json()).data;
    assertEquals([movedItem.category, movedItem.store], ['Kühlregal', 'Lidl']);
    const untagged = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { store: null },
    });
    assertEquals((await untagged.json()).data.store, null);

    const stores = await (await api(key.token, 'GET', '/stores')).json();
    assertEquals(stores.nextCursor, null);
    assert(stores.data.some((s: { name: string; sortOrder: number }) => s.name === 'dm'));
    assertEquals(Object.keys(stores.data[0]), ['id', 'name', 'sortOrder']);
    const cats = await (await api(key.token, 'GET', '/categories')).json();
    assert(cats.data.some((c: { name: string }) => c.name === 'Kühlregal'));

    for (
      const [method, path, body] of [
        ['GET', `/items/${gurken.id}`, undefined],
        ['POST', `/items/${gurken.id}/tick`, undefined],
        ['PATCH', `/items/${gurken.id}`, { store: null }],
        ['PATCH', `/items/${gurken.id}`, { name: 'Fremd' }],
        ['DELETE', `/items/${gurken.id}`, undefined],
      ] as const
    ) {
      const res = await api(other.token, method, path, { body });
      assertEquals(res.status, 404, `${method} ${path} from another household`);
      assertEquals((await res.json()).error.code, 'item_not_found');
    }
    const theirList = await (await api(other.token, 'GET', '/items')).json();
    assertEquals(theirList.data, []);
    assertEquals(theirList.counts, { open: 0, checkedLast24h: 0 });
    const [item] = await sql<{ status: string; name: string }[]>`
      select status, name from public.items where id = ${gurken.id}`;
    assertEquals(
      [item?.status, item?.name],
      ['active', 'Gurken'],
      'the other household could not tick, rename or delete it',
    );
  }));

test('pages follow the aisle order with stable cursors that belong to their filter', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const names = ['Milch', 'Äpfel', 'Brot', 'Butter', 'Käse', 'Bananen', 'Nudeln', 'Reis'];
    await api(key.token, 'POST', '/items', { body: { items: names.map((name) => ({ name })) } });

    const whole = await (await api(key.token, 'GET', '/items?limit=100')).json();
    assertEquals(whole.data.length, names.length);
    assertEquals(whole.nextCursor, null);
    const order = whole.data.map((i: Item) => i.id);

    const seen: string[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const query: string = cursor ? `?limit=3&cursor=${cursor}` : '?limit=3';
      const page = await (await api(key.token, 'GET', `/items${query}`)).json();
      assertEquals(page.counts, { open: names.length, checkedLast24h: 0 });
      seen.push(...page.data.map((i: Item) => i.id));
      cursor = page.nextCursor;
      pages++;
    } while (cursor);
    assertEquals(pages, 3);
    assertEquals(seen, order, 'the pages together are the list, in order, once each');

    const firstPage = await (await api(key.token, 'GET', '/items?limit=3')).json();
    await api(key.token, 'POST', `/items/${firstPage.data[0].id}/tick`);
    await api(key.token, 'POST', `/items/${firstPage.data[1].id}/tick`);
    const next =
      await (await api(key.token, 'GET', `/items?limit=3&cursor=${firstPage.nextCursor}`))
        .json();
    assertEquals(
      next.data.map((i: Item) => i.id),
      order.slice(3, 6),
      'items ticked before the position do not shift the next page',
    );
    assertEquals(next.counts.open, names.length - 2);

    const otherFilter = await api(
      key.token,
      'GET',
      `/items?store=dm&cursor=${firstPage.nextCursor}`,
    );
    assertEquals(otherFilter.status, 400);
    assertEquals((await otherFilter.json()).error.code, 'invalid_cursor');

    const dm = await (await api(key.token, 'GET', '/items?store=DM')).json();
    assert(dm.data.length > 0);
    assertEquals(dm.counts, { open: names.length - 2, checkedLast24h: 2 }, 'the whole list');
    const missing = await api(key.token, 'GET', '/items?store=Rewe');
    assertEquals((await missing.json()).error.code, 'store_not_found');
  }));

test('job 169b W3: lists, the list filter with its cursors, adds to a list, listId on items', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    await asUser(
      mine.userId,
      (tx) => tx`select public.create_list(${mine.householdId}, 'Baumarkt', gen_random_uuid())`,
    );
    await asUser(
      theirs.userId,
      (tx) => tx`select public.create_list(${theirs.householdId}, 'Fremd', gen_random_uuid())`,
    );

    const lists = await (await api(key.token, 'GET', '/lists')).json();
    assertEquals(
      lists.data.map((l: { name: string; sortOrder: number }) => [l.name, l.sortOrder]),
      [['Einkaufsliste', 0], ['Baumarkt', 1]],
      "only the key's household, in order",
    );
    assertEquals(
      lists.data.map((l: { default: boolean }) => l.default),
      [true, false],
      'without a choice the first list is the default',
    );
    const [first, hardware] = lists.data as { id: string }[];
    assertExists(first);
    assertExists(hardware);

    await api(key.token, 'POST', '/items', { body: { items: [{ name: 'Milch' }] } });
    const toHardware = await api(key.token, 'POST', '/items', {
      body: {
        list: 'baumarkt',
        items: [{ name: 'Milch' }, { name: 'Schrauben' }, { name: 'Dübel' }],
      },
    });
    assertEquals(toHardware.status, 201);
    const added = (await toHardware.json()).data.added as (Item & { listId: string })[];
    assertEquals(
      added.map((i) => i.name),
      ['Milch', 'Schrauben', 'Dübel'],
      'Milch is open elsewhere only',
    );
    assert(added.every((i) => i.listId === hardware.id), 'items carry their listId');

    const all = await (await api(key.token, 'GET', '/items')).json();
    assertEquals(all.data.length, 4, "without list, every list's items");
    assertEquals(all.counts.open, 4);
    const only = await (await api(key.token, 'GET', `/items?list=${hardware.id}&limit=2`)).json();
    assertEquals(only.counts.open, 3, "with list, that list's counts");
    const rest = await (await api(
      key.token,
      'GET',
      `/items?list=${hardware.id}&limit=2&cursor=${only.nextCursor}`,
    )).json();
    assertEquals(
      [...only.data, ...rest.data].map((i: Item) => i.name).sort(),
      ['Dübel', 'Milch', 'Schrauben'],
      'the cursor continues inside the list',
    );
    const elsewhere = await api(key.token, 'GET', `/items?limit=2&cursor=${only.nextCursor}`);
    assertEquals((await elsewhere.json()).error.code, 'invalid_cursor', 'a cursor keeps its list');

    const foreign = await api(key.token, 'POST', '/items', {
      body: { list: 'Fremd', items: [{ name: 'Brot' }] },
    });
    assertEquals(foreign.status, 422);
    const error = (await foreign.json()).error;
    assertEquals(error.code, 'list_not_found');
    assertEquals(error.details.candidates, ['Einkaufsliste', 'Baumarkt']);
    assertEquals(
      (await (await api(key.token, 'GET', '/items')).json()).data.length,
      4,
      'nothing added',
    );
  }));

test('Idempotency-Key replays the first answer, refuses another request, serialises twins', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const body = { items: [{ name: 'Hafermilch' }] };
    const headers = { 'idempotency-key': `k-${crypto.randomUUID()}` };

    const first = await api(key.token, 'POST', '/items', { body, headers });
    assertEquals(first.status, 201);
    const firstBody = await first.text();
    const replay = await api(key.token, 'POST', '/items', { body, headers });
    assertEquals(replay.status, 201);
    assertEquals(replay.headers.get('idempotent-replayed'), 'true');
    assertEquals(await replay.text(), firstBody, 'the replay is byte for byte the first answer');
    assertFalse(first.headers.has('idempotent-replayed'));

    const reused = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Sojamilch' }] },
      headers,
    });
    assertEquals(reused.status, 422);
    assertEquals((await reused.json()).error.code, 'idempotency_key_reused');

    const failing = { 'idempotency-key': `k-${crypto.randomUUID()}` };
    const failed = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Wein', store: 'Rewe' }] },
      headers: failing,
    });
    assertEquals(failed.status, 422);
    const retried = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Wein', store: 'Rewe' }] },
      headers: failing,
    });
    assertEquals((await retried.json()).error.code, 'store_not_found', 'an error stored nothing');

    const twins = { 'idempotency-key': `k-${crypto.randomUUID()}` };
    const pair = await Promise.all([
      api(key.token, 'POST', '/items', {
        body: { items: [{ name: 'Zwillingskekse' }] },
        headers: twins,
      }),
      api(key.token, 'POST', '/items', {
        body: { items: [{ name: 'Zwillingskekse' }] },
        headers: twins,
      }),
    ]);
    assertEquals(pair.map((r) => r.status), [201, 201], 'both get the first answer');
    assertEquals(pair.filter((r) => r.headers.get('idempotent-replayed') === 'true').length, 1);
    const [a, b] = await Promise.all(pair.map((r) => r.json()));
    assertEquals(a, b);
    const rows = await sql`select from public.items
      where household_id = ${mine.householdId} and name = 'Zwillingskekse'`;
    assertEquals(rows.length, 1);

    const tickKey = { 'idempotency-key': `k-${crypto.randomUUID()}` };
    const id = a.data.added[0].id;
    const tick = await api(key.token, 'POST', `/items/${id}/tick`, { headers: tickKey });
    const tickAgain = await api(key.token, 'POST', `/items/${id}/tick`, { headers: tickKey });
    assertEquals(tickAgain.headers.get('idempotent-replayed'), 'true');
    assertEquals(await tickAgain.json(), await tick.json());
    const untickSameKey = await api(key.token, 'POST', `/items/${id}/untick`, { headers: tickKey });
    assertEquals(untickSameKey.status, 422, 'another path with the same key');
  }));

test('limits: the burst runs out into 429, unknown keys from one address into auth_throttled', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read']);
    const statuses: Response[] = [];
    for (let i = 0; i < 25; i++) {
      const res = await api(key.token, 'GET', '/categories');
      await res.body?.cancel();
      statuses.push(res);
    }
    assertEquals(statuses[0]?.headers.get('x-ratelimit-limit'), '20');
    assertEquals(statuses[0]?.headers.get('x-ratelimit-remaining'), '19');
    assert(statuses.slice(0, 20).every((r) => r.status === 200), 'the burst is 20');
    const limited = statuses.find((r) => r.status === 429);
    assertExists(limited);
    assert(statuses.indexOf(limited) <= 22, 'refilled at one a second, the burst runs out');
    assertEquals(limited.headers.get('x-ratelimit-remaining'), '0');
    assertEquals(limited.headers.get('x-ratelimit-limit'), '20');
    assert(Number(limited.headers.get('retry-after')) >= 1);
    assert(Number(limited.headers.get('x-ratelimit-reset')) >= 1);

    const ip = `198.51.100.${Math.floor(Math.random() * 250)}-${crypto.randomUUID()}`;
    const quiet = `203.0.113.${Math.floor(Math.random() * 250)}-${crypto.randomUUID()}`;
    try {
      const bad = 'fgp_' + 'x'.repeat(43);
      for (let i = 0; i < 20; i++) {
        const res = await api(bad, 'GET', '/items', {
          headers: { 'x-real-ip': ip, 'x-forwarded-for': `198.51.100.${i}` },
        });
        assertEquals(res.status, 401, 'a new X-Forwarded-For per request changes nothing');
        assertEquals(res.headers.get('x-ratelimit-remaining'), String(19 - i));
        await res.body?.cancel();
      }
      const blocked = await api(bad, 'GET', '/items', {
        headers: { 'x-real-ip': ip, 'x-forwarded-for': '192.0.2.99' },
      });
      assertEquals(blocked.status, 429);
      assertEquals((await blocked.json()).error.code, 'auth_throttled');
      assert(Number(blocked.headers.get('retry-after')) > 500);
      await refill(sql, key.id);
      const valid = await api(key.token, 'GET', '/items', { headers: { 'x-real-ip': ip } });
      assertEquals(valid.status, 200, 'a valid key from the blocked address still works');
      await valid.body?.cancel();

      const ended = await mint(sql, mine, ['read']);
      await sql`update public.personal_access_tokens set revoked_at = now() where id = ${ended.id}`;
      for (let i = 0; i < 30; i++) {
        const res = await api(ended.token, 'GET', '/items', { headers: { 'x-real-ip': quiet } });
        assertEquals(res.status, 401, 'a revoked key polling is never throttled');
        await res.body?.cancel();
      }
      await refill(sql, key.id);
      const neighbour = await api(key.token, 'GET', '/items', { headers: { 'x-real-ip': quiet } });
      assertEquals(neighbour.status, 200, 'and a valid key behind the same address gets 200');
      await neighbour.body?.cancel();
      const stranger = await api(bad, 'GET', '/items', { headers: { 'x-real-ip': quiet } });
      assertEquals(
        stranger.headers.get('x-ratelimit-remaining'),
        '19',
        'the revoked key counted nothing',
      );
      await stranger.body?.cancel();
    } finally {
      const hashes = [await sha256Hex(ip), await sha256Hex(quiet)];
      await sql`delete from public.api_auth_failures where ip_hash in (
                  select encode(extensions.digest(s.salt || convert_to(a, 'UTF8'), 'sha256'), 'hex')
                  from public.invite_preview_salt s, unnest(${hashes}::text[]) a)`;
    }
  }));

test('a revoked key is 401; the integration lock without Premium is 402 until it is off', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    await sql`update public.app_switches set enabled = true where key = 'integration_lock'`;
    const locked = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Kaffee' }] },
    });
    assertEquals(locked.status, 402);
    const { error } = await locked.json();
    assertEquals(error.code, 'premium_required');
    assertEquals(
      error.message,
      'You need Snacklist Premium to use the API. Unlock it in the Snacklist app. ' +
        'Nothing was read or changed.',
    );
    const rows = await sql`select from public.items where household_id = ${mine.householdId}`;
    assertEquals(rows.length, 0, 'nothing was changed');

    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    const open = await api(key.token, 'GET', '/items');
    assertEquals(open.status, 200, 'the same key works once the household may use the API');
    await open.body?.cancel();

    await sql`update public.personal_access_tokens set revoked_at = now() where id = ${key.id}`;
    const revoked = await api(key.token, 'GET', '/items');
    assertEquals(revoked.status, 401);
    assertEquals((await revoked.json()).error.code, 'invalid_token');
  }));

test("job 328: with the integration lock on, the key holder's own Premium opens the API", () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    await sql`update public.app_switches set enabled = true where key = 'integration_lock'`;
    const tx = `u328-${mine.userId.slice(0, 8)}`;
    await sql`select public.purchase_record_user('apple', ${tx}, ${tx}, ${await sha256Hex(tx)},
          'com.snacklist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute',
          24.99, 'EUR', 'DE', ${mine.userId}::uuid, now(), now() + interval '365 days', true, false)`;
    const added = await api(key.token, 'POST', '/items', { body: { items: [{ name: 'Kaffee' }] } });
    assertEquals(added.status, 201);
    await added.body?.cancel();
    const read = await api(key.token, 'GET', '/items');
    assertEquals(read.status, 200);
    assertEquals((await read.json()).data.map((i: Item) => i.name), ['Kaffee']);
  }));

test("job 328 review 0: another member's Premium does not open the API for you", () =>
  withMembers(async (sql, [mine, theirs]) => {
    await sql`insert into public.household_members (household_id, user_id, role)
              values (${mine.householdId}, ${theirs.userId}, 'member')`;
    const key = await mint(sql, mine, ['read', 'write'], mine.householdId);
    const theirKey = await mint(sql, theirs, ['read', 'write'], mine.householdId);
    await sql`update public.app_switches set enabled = true where key = 'integration_lock'`;
    const tx = `m328-${theirs.userId.slice(0, 8)}`;
    await sql`select public.purchase_record_user('apple', ${tx}, ${tx}, ${await sha256Hex(tx)},
          'com.snacklist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute',
          24.99, 'EUR', 'DE', ${theirs.userId}::uuid, now(), now() + interval '365 days', true, false)`;

    const locked = await api(key.token, 'GET', '/items');
    assertEquals(locked.status, 402, "the partner's plan is theirs");
    const { error } = await locked.json();
    assertEquals(
      [error.code, error.message],
      [
        'premium_required',
        'You need Snacklist Premium to use the API. Unlock it in the Snacklist app. ' +
        'Nothing was read or changed.',
      ],
    );
    const open = await api(theirKey.token, 'GET', '/items');
    assertEquals(open.status, 200, 'the buyer, in the same household');
    await open.body?.cancel();
  }));

test('switched off, no key can be made and a key from before gets 404 until it is on', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const added = await api(key.token, 'POST', '/items', { body: { items: [{ name: 'Tee' }] } });
    assertEquals(added.status, 201);
    await added.body?.cancel();

    await setPublicApi(sql, false);
    const error = await assertRejects(() => mint(sql, mine, ['read'])) as postgres.PostgresError;
    assertEquals([error.code, error.message], ['42501', 'api_disabled']);
    const [tokens] = await sql<{ keys: number }[]>`
      select count(*)::int as keys from public.personal_access_tokens where user_id = ${mine.userId}`;
    assertEquals(tokens?.keys, 1, 'only the key from before');

    const [before] = await sql<{ last_used_at: Date }[]>`
      select last_used_at from public.personal_access_tokens where id = ${key.id}`;
    assertExists(before);
    for (const [method, body] of [['GET', undefined], ['POST', { items: [{ name: 'Kaffee' }] }]]) {
      const off = await api(key.token, method as string, '/items', { body });
      assertEquals(off.status, 404, `${method} while off`);
      assertEquals(await off.json(), {
        error: { code: 'not_found', message: 'No such endpoint.' },
      });
      assertEquals([...off.headers.keys()].filter((h) => h.startsWith('x-ratelimit-')), []);
    }
    const [after] = await sql<{ last_used_at: Date }[]>`
      select last_used_at from public.personal_access_tokens where id = ${key.id}`;
    assertExists(after);
    assertEquals(after.last_used_at, before.last_used_at, 'a request while off is not a use');
    const names = await sql<{ name: string }[]>`
      select name from public.items where household_id = ${mine.householdId}`;
    assertEquals(names.map((r) => r.name), ['Tee'], 'nothing was added while off');

    await setPublicApi(sql, true);
    const on = await api(key.token, 'GET', '/items');
    assertEquals(on.status, 200, 'the same key works once the API is on');
    assertEquals((await on.json()).data.map((i: Item) => i.name), ['Tee']);
  }));

test('a read key reads on every route and changes nothing; a read-write key does both', () =>
  withMembers(async (sql, [mine]) => {
    const writer = await mint(sql, mine, ['read', 'write']);
    const reader = await mint(sql, mine, ['read']);
    const added = await api(writer.token, 'POST', '/items', {
      body: { items: [{ name: 'Milch' }] },
    });
    const [milk] = (await added.json()).data.added as Item[];
    assertExists(milk);
    const bodies: Record<string, unknown> = {
      addItems: { items: [{ name: 'Brot' }] },
      updateItem: { store: null },
      createList: { name: 'Baumarkt' },
      updateList: { position: 0 },
      addStore: { name: 'Rewe' },
      updateStore: { name: 'dm' },
      setStoreLayout: { categories: [] },
    };
    const [[list], [store]] = await Promise.all([
      sql<{ id: string }[]>`select id from public.lists where household_id = ${mine.householdId}`,
      sql<{ id: string }[]>`select id from public.stores
                            where household_id = ${mine.householdId} and name = 'dm'`,
    ]);
    assertExists(list);
    assertExists(store);
    const idFor = (path: string) =>
      path.startsWith('/v1/lists/') ? list.id : path.startsWith('/v1/stores/') ? store.id : milk.id;
    const call = (token: string, route: (typeof routes)[number]) =>
      api(token, route.method, route.path.replace('/v1', '').replace('{id}', idFor(route.path)), {
        body: bodies[route.operation],
      });
    const state = async () =>
      (await Promise.all([
        sql`select id, name, status, store_id, category_id, updated_at from public.items
            where household_id = ${mine.householdId} order by id`,
        sql`select id, name, position from public.lists
            where household_id = ${mine.householdId} order by id`,
        sql`select id, name, sort_order from public.stores
            where household_id = ${mine.householdId} order by id`,
        sql`select store_id, category_id, sort_order, hidden from public.store_category_order
            where household_id = ${mine.householdId} order by store_id, category_id`,
      ])).map((rows) => [...rows]);

    const before = await state();
    for (const route of routes) {
      const res = await call(reader.token, route);
      const where = `${route.method} ${route.path}`;
      if (route.scope === 'read') {
        assertEquals(res.status, 200, where);
        await res.body?.cancel();
      } else {
        assertEquals(res.status, 403, where);
        const error = (await res.json()).error;
        assertEquals([error.code, error.details], ['insufficient_scope', { required: 'write' }]);
      }
    }
    assertEquals(await state(), before, 'the read key changed nothing');

    // The delete last: the routes after it would not find the item.
    const deleteLast = [...routes].sort((a, b) =>
      Number(a.method === 'DELETE') - Number(b.method === 'DELETE')
    );
    for (const route of deleteLast) {
      const res = await call(writer.token, route);
      assert(res.ok, `${route.method} ${route.path} with a read-write key: ${res.status}`);
      await res.body?.cancel();
    }
  }));

test('a member of two households: a key acts in the household it was made for, until they leave it', () =>
  withMembers(async (sql, [mine, theirs]) => {
    await sql`insert into public.household_members (household_id, user_id, role)
              values (${theirs.householdId}, ${mine.userId}, 'member')`;
    const key = await mint(sql, mine, ['read', 'write'], mine.householdId);
    const theirKey = await mint(sql, theirs, ['read', 'write']);
    const own = await api(key.token, 'POST', '/items', { body: { items: [{ name: 'Eigenes' }] } });
    const [ownItem] = (await own.json()).data.added as Item[];
    const there = await api(theirKey.token, 'POST', '/items', {
      body: { items: [{ name: 'Fremdkäse', store: 'dm' }] },
    });
    const [foreign] = (await there.json()).data.added as Item[];
    assertExists(ownItem);
    assertExists(foreign);
    const theirIds = async (table: 'lists' | 'stores' | 'categories') => {
      const [row] = await sql<{ id: string }[]>`
        select id from public.${sql(table)} where household_id = ${theirs.householdId} limit 1`;
      assertExists(row);
      return row.id;
    };
    const [list, store, category] = [
      await theirIds('lists'),
      await theirIds('stores'),
      await theirIds('categories'),
    ];

    for (
      const [method, path, body, status, code] of [
        ['GET', `/items/${foreign.id}`, undefined, 404, 'item_not_found'],
        ['POST', `/items/${foreign.id}/tick`, undefined, 404, 'item_not_found'],
        ['PATCH', `/items/${foreign.id}`, { store: null }, 404, 'item_not_found'],
        ['POST', '/items', { list, items: [{ name: 'Eindringling' }] }, 422, 'list_not_found'],
        ['POST', '/items', { items: [{ name: 'Eindringling', store }] }, 422, 'store_not_found'],
        [
          'POST',
          '/items',
          { items: [{ name: 'Eindringling', category }] },
          422,
          'category_not_found',
        ],
        ['GET', `/items?list=${list}`, undefined, 422, 'list_not_found'],
        ['GET', `/items?store=${store}`, undefined, 422, 'store_not_found'],
        ['PATCH', `/items/${ownItem.id}`, { store }, 422, 'store_not_found'],
        ['PATCH', `/items/${ownItem.id}`, { category }, 422, 'category_not_found'],
      ] as const
    ) {
      const res = await api(key.token, method, path, { body });
      const where = `${method} ${path} ${JSON.stringify(body ?? null)}`;
      assertEquals(res.status, status, where);
      assertEquals((await res.json()).error.code, code, where);
    }
    const listed = await (await api(key.token, 'GET', '/items')).json();
    assertEquals(listed.data.map((i: Item) => i.name), ['Eigenes'], 'its own household only');
    assertEquals(listed.counts, { open: 1, checkedLast24h: 0 }, 'counts of that household only');
    const untouched = await sql<{ name: string; status: string; store: string | null }[]>`
      select i.name, i.status, s.name as store from public.items i
      left join public.stores s on s.id = i.store_id where i.household_id = ${theirs.householdId}`;
    assertEquals(
      untouched.map((r) => ({ ...r })),
      [{ name: 'Fremdkäse', status: 'active', store: 'dm' }],
      'the other household is as it was',
    );

    const second = await mint(sql, mine, ['read'], theirs.householdId);
    const viaSecond = await (await api(second.token, 'GET', '/items')).json();
    assertEquals(
      viaSecond.data.map((i: Item) => i.name),
      ['Fremdkäse'],
      'a key made for the second household reads that one',
    );
    await asUser(mine.userId, (tx) => tx`select public.leave_household(${theirs.householdId})`);
    const left = await api(second.token, 'GET', '/items');
    assertEquals(left.status, 401, 'leaving a household ends the keys made for it');
    assertEquals((await left.json()).error.code, 'invalid_token');
    const stays = await api(key.token, 'GET', '/items');
    assertEquals(stays.status, 200, "the key for the member's other household goes on");
    await stays.body?.cancel();
  }));

test("only an API key opens the API, and only the app's own session of a member makes one", () =>
  withMembers(async (sql, [mine, theirs]) => {
    const session = appSession(mine);
    const key = await mint(sql, mine, ['read', 'write']);
    const pat = await sql.begin(async (tx) => {
      await tx`select set_config('role', 'authenticated', true),
                      set_config('request.jwt.claims', ${JSON.stringify(session)}, true)`;
      const [row] = await tx<{ token: string }[]>`
        select token from public.create_personal_access_token('test')`;
      return row;
    });
    assertExists(pat);
    const withPat = await api(pat.token, 'GET', '/items');
    assertEquals(withPat.status, 401, 'an access token for MCP or Siri is not an API key');
    assertEquals((await withPat.json()).error.code, 'invalid_token');
    const asAccessToken = await sql`
      select from public.authenticate_access_token(${await sha256Hex(key.token)})`;
    assertEquals(asAccessToken.length, 0, 'and an API key is not an access token');
    for (const authorization of [`Basic ${key.token}`, key.token]) {
      const res = await api('', 'GET', `/items?access_token=${key.token}`, {
        headers: { authorization },
      });
      assertEquals(res.status, 401, 'the key counts only as a Bearer token');
      assertEquals((await res.json()).error.code, 'missing_token');
    }

    const refused = async (
      claims: Claims,
      scopes: string[],
      expected: [code: string, message: string],
      household?: string,
    ) => {
      const error = await assertRejects(() =>
        mintAs(sql, claims, scopes, household)
      ) as postgres.PostgresError;
      assertEquals([error.code, error.message], expected, JSON.stringify({ claims, scopes }));
    };
    await refused(session, ['write'], ['22023', 'invalid_scopes']);
    await refused(session, [], ['22023', 'invalid_scopes']);
    await refused(session, ['read', 'admin'], ['22023', 'invalid_scopes']);
    await refused({ ...session, client_id: crypto.randomUUID() }, ['read'], [
      '42501',
      'session_required',
    ]);
    await refused({ sub: mine.userId, role: 'authenticated' }, ['read'], [
      '42501',
      'session_required',
    ]);
    await refused(session, ['read'], ['42501', 'not_a_member'], theirs.householdId);
    await refused({ role: 'anon' }, ['read'], [
      '42501',
      'permission denied for function create_api_token',
    ]);
    const [keys] = await sql<{ n: number }[]>`
      select count(*)::int as n from public.personal_access_tokens
      where kind = 'api' and user_id in (${mine.userId}, ${theirs.userId})`;
    assertEquals(keys?.n, 1, 'no refused call left a key');
  }));

/** A cursor as the API encodes one. */
const cursorOf = (value: unknown) =>
  btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(value))))
    .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');

test('pages meet exactly whatever the sort keys; input Postgres cannot read is 400, not a failure', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    // Keys a household gets by sorting by hand: more digits than Postgres prints by default,
    // two that print alike, one that prints rounded up past the next item's.
    const keys = {
      Drittel: '0.3',
      Summe: '0.30000000000000004',
      Anfang: '1024',
      Mitte: '100352.0009765625',
      Ende: '100352.0029296875',
      Danach: '100352.0029296876',
    };
    await api(key.token, 'POST', '/items', {
      body: { items: Object.keys(keys).map((name) => ({ name })) },
    });
    for (const [name, sortKey] of Object.entries(keys)) {
      await sql`
        update public.items set sort_key = ${sortKey}::float8, category_id = (
          select id from public.categories where household_id = ${mine.householdId}
          order by sort_order limit 1)
        where household_id = ${mine.householdId} and name = ${name}`;
    }

    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      await refill(sql, key.id);
      const query: string = cursor ? `?limit=1&cursor=${cursor}` : '?limit=1';
      const page = await (await api(key.token, 'GET', `/items${query}`)).json();
      seen.push(...page.data.map((i: Item) => i.name));
      cursor = page.nextCursor;
    } while (cursor && seen.length <= Object.keys(keys).length);
    assertEquals(seen, Object.keys(keys), 'one item a page: each once, in order, and it ends');

    const first = await (await api(key.token, 'GET', '/items?limit=1')).json();
    const real = JSON.parse(new TextDecoder().decode(
      Uint8Array.from(
        atob(first.nextCursor.replaceAll('-', '+').replaceAll('_', '/')),
        (c) => c.charCodeAt(0),
      ),
    ));
    const continued = async (k: unknown[]) => {
      await refill(sql, key.id);
      const res = await api(key.token, 'GET', `/items?cursor=${cursorOf({ ...real, k })}`);
      const body = await res.json();
      return `${res.status} ${body.error?.code ?? 'ok'}`;
    };
    const [rank, category, sortKey, addedAt, id] = real.k as [
      number,
      string,
      string,
      string,
      string,
    ];
    for (
      const k of [
        [2 ** 31, category, sortKey, addedAt, id],
        [rank, 'a\u0000b', sortKey, addedAt, id],
        [rank, category, '1e999', addedAt, id],
        [rank, category, '1e-400', addedAt, id],
        [rank, category, '9'.repeat(400), addedAt, id],
        [rank, category, sortKey, '2026-02-30T08:00:00+00:00', id],
        [rank, category, sortKey, '2026-11-02T08:00:00+16:00', id],
        [rank, category, sortKey, '0000-01-01T00:00:00+00:00', id],
      ]
    ) {
      assertEquals(await continued(k), '400 invalid_cursor', JSON.stringify(k));
    }
    // The outermost values a cursor may hold are ones Postgres reads.
    for (
      const k of [
        [-(2 ** 31), category, sortKey, addedAt, id],
        [2 ** 31 - 1, category, sortKey, addedAt, id],
        [rank, category, '-Infinity', addedAt, id],
        [rank, category, 'NaN', addedAt, id],
        [rank, category, '5e-324', addedAt, id],
        [rank, category, '1.7976931348623157e+308', addedAt, id],
        [rank, category, sortKey, '0001-01-01T00:00:00+15:59', id],
        [rank, category, sortKey, '9999-12-31T23:59:59.999999-15:59', id],
      ]
    ) {
      assertEquals(await continued(k), '200 ok', JSON.stringify(k));
    }

    for (
      const [path, body] of [
        ['/items', { items: [{ name: 'a\u0000b' }] }],
        ['/items', { items: [{ name: 'Tee', brand: 'a\u0000b' }] }],
        ['/items', { items: [{ name: 'Tee', properties: '\u0000' }] }],
        ['/items', { items: [{ name: 'Tee', quantity: '1\u0000' }] }],
        ['/items', { items: [{ name: 'Tee', store: 'd\u0000m' }] }],
        ['/items', { list: 'a\u0000', items: [{ name: 'Tee' }] }],
      ] as const
    ) {
      await refill(sql, key.id);
      const res = await api(key.token, 'POST', path, { body });
      assertEquals(res.status, 400, JSON.stringify(body));
      assertEquals((await res.json()).error.code, 'validation_failed');
    }
    const byQuery = await api(key.token, 'GET', '/items?store=d%00m');
    assertEquals(byQuery.status, 400);
    await byQuery.body?.cancel();
    const names = await sql<{ name: string }[]>`
      select name from public.items where household_id = ${mine.householdId} and name = 'Tee'`;
    assertEquals(names.length, 0, 'nothing was added');
  }));

type Similar = { itemId: string; onList: Item[]; total: number };

/** Names that differ only in a number inside the word: one product for the duplicate hint. */
const variety = (n: number) => `Sorte${n}x`;

/** Open items [from]..[to] of `variety` on the member's list, the lowest number the oldest. */
async function seedVarieties(sql: postgres.Sql, member: Member, from: number, to: number) {
  await sql`
    insert into public.items (household_id, list_id, name, created_at)
    select ${member.householdId}, public.first_list(${member.householdId}), 'Sorte' || g || 'x',
           now() - interval '1 day' + g * interval '1 second'
    from generate_series(${from}::int, ${to}::int) g`;
  const [keys] = await sql<{ n: number }[]>`
    select count(distinct canonical_key)::int as n from public.items
    where household_id = ${member.householdId}`;
  assertEquals(keys?.n, 1, 'the varieties share one canonical key');
}

test("job 336: a member's own insert with an endless created_at does not break paging", () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read']);
    const names = ['Unendlich', 'Minus', 'Fern', 'Heute'];
    await asUser(
      mine.userId,
      (tx) =>
        tx`insert into public.items (household_id, list_id, name, created_at)
         select ${mine.householdId}, public.first_list(${mine.householdId}), v.name, v.at::timestamptz
         from (values ('Unendlich', 'infinity'), ('Minus', '-infinity'), ('Fern', '10000-01-01Z'),
                      ('Heute', now()::text)) v (name, at)`,
    );
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      await refill(sql, key.id);
      const query: string = cursor ? `?limit=1&cursor=${cursor}` : '?limit=1';
      const res = await api(key.token, 'GET', `/items${query}`);
      assertEquals(res.status, 200, `page ${seen.length + 1}`);
      const page = await res.json();
      seen.push(...page.data.map((i: Item) => i.name));
      cursor = page.nextCursor;
    } while (cursor && seen.length <= names.length);
    assertEquals(seen.toSorted(), names.toSorted(), 'every item once, and it ends');
  }));

test('an add names at most three similar open items per added item, oldest first, with their number', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    await seedVarieties(sql, mine, 1, 12);
    const res = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: variety(101) }, { name: variety(102) }, { name: 'Zahnseide' }] },
    });
    assertEquals(res.status, 201);
    const { added, similarOnList } = (await res.json()).data as {
      added: Item[];
      similarOnList: Similar[];
    };
    assertEquals(added.map((i) => i.name), [variety(101), variety(102), 'Zahnseide']);
    assertEquals(
      similarOnList.map((s) => [s.itemId, s.onList.map((i) => i.name), s.total]),
      [added[0], added[1]].map((i) => [i?.id, [1, 2, 3].map(variety), 13]),
      'the three oldest of the twelve seeded and the other added one',
    );
    assertEquals(SIMILAR_SHOWN, 3);
  }));

test('an add answers within its size and time whatever is on the list', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const batch = (from: number) => ({
      items: Array.from({ length: 50 }, (_, i) => ({ name: variety(from + i) })),
    });
    const post = async (from: number) => {
      const started = performance.now();
      const res = await api(key.token, 'POST', '/items', { body: batch(from) });
      const text = await res.text();
      return { status: res.status, text, ms: performance.now() - started };
    };
    const openItems = async () => {
      const [row] = await sql<{ n: number }[]>`
        select count(*)::int as n from public.items where household_id = ${mine.householdId}`;
      return row?.n;
    };

    const first = await post(1);
    assertEquals(first.status, 201);
    await seedVarieties(sql, mine, 51, 1000);
    const later = await post(1001);

    assert(
      later.ms <= ADD_BUDGET_MS + 4000,
      `${Math.round(later.ms)} ms against a long list (${
        Math.round(first.ms)
      } ms against an empty one)`,
    );
    assert(
      later.text.length <= first.text.length * 1.2,
      `${later.text.length} bytes against a long list, ${first.text.length} against an empty one`,
    );
    if (later.status === 201) {
      const { added, similarOnList } = JSON.parse(later.text).data as {
        added: Item[];
        similarOnList: Similar[];
      };
      assertEquals(added.length, 50);
      for (const s of similarOnList) {
        assertEquals([s.onList.length, s.total], [SIMILAR_SHOWN, 1049]);
      }
      assertEquals(await openItems(), 1050);
    } else {
      assertEquals(later.status, 503, later.text);
      assertEquals(JSON.parse(later.text).error.code, 'timeout');
      assertEquals(await openItems(), 1000, 'stopped for its time, the add changed nothing');
    }
  }));

test("one member's requests at once hold one connection; another household is answered meanwhile", () =>
  withMembers(async (sql, [loud, quiet]) => {
    const loudKey = await mint(sql, loud, ['read', 'write']);
    const quietKey = await mint(sql, quiet, ['read']);
    const names = ['Milch', 'Brot', 'Butter', 'Salz', 'Mehl', 'Reis'];
    // Once all with an Idempotency-Key and once all without: the two ways an add runs.
    for (const idempotent of [true, false]) {
      let taken = () => {};
      const locked = new Promise<void>((resolve) => {
        taken = resolve;
      });
      let release = () => {};
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      const holder = admin();
      const holding = holder.begin(async (tx) => {
        await tx`select public.lock_household_items(${loud.householdId})`;
        taken();
        await released;
      });
      await locked;

      const adds = names.map((name, i) =>
        api(loudKey.token, 'POST', '/items', {
          body: { items: [{ name }] },
          headers: idempotent ? { 'idempotency-key': `at-once-${i}` } : {},
        })
      );
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const answered = await Promise.race([
          api(quietKey.token, 'GET', '/items').then((res) => res.status),
          new Promise<string>((resolve) => {
            timer = setTimeout(() => resolve('still waiting for a connection after 3 s'), 3000);
          }),
        ]);
        assertEquals(answered, 200, "the other household's read while the adds wait");
      } finally {
        clearTimeout(timer);
        release();
        await holding;
        await Promise.allSettled(adds);
        await holder.end();
      }

      assertEquals((await Promise.all(adds)).map((res) => res.status), names.map(() => 201));
      const open = await sql<{ name: string }[]>`
        delete from public.items where household_id = ${loud.householdId} returning name`;
      assertEquals(open.map((r) => r.name).toSorted(), names.toSorted());
    }
  }));

test('job 344: PATCH edits the text fields and the list like the app; a twin is 409', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    await asUser(
      mine.userId,
      (tx) => tx`select public.create_list(${mine.householdId}, 'Baumarkt', gen_random_uuid())`,
    );
    const added = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: '2 Gurken' }, { name: 'Milch' }, { name: 'Hafermilch' }] },
    });
    const [gurken, milch, hafer] = (await added.json()).data.added as Item[];
    assertExists(gurken);
    assertExists(milch);
    assertExists(hafer);

    const edited = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { name: ' Salatgurken ', quantity: null, brand: 'Bio', properties: 'lose' },
    });
    assertEquals(edited.status, 200);
    const item = (await edited.json()).data;
    assertEquals(
      [item.name, item.quantity, item.brand, item.properties, item.status],
      ['Salatgurken', null, 'Bio', 'lose', 'open'],
    );
    const cleared = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { brand: ' ', properties: null, quantity: '3' },
    });
    const clearedItem = (await cleared.json()).data;
    assertEquals(
      [clearedItem.brand, clearedItem.properties, clearedItem.quantity],
      [null, null, '3'],
      'blank or null clears',
    );

    const moved = await api(key.token, 'PATCH', `/items/${gurken.id}`, {
      body: { list: 'baumarkt', category: 'Kühlregal' },
    });
    assertEquals(moved.status, 200);
    const movedItem = (await moved.json()).data;
    const [hardware] = await sql<{ id: string }[]>`
      select id from public.lists where household_id = ${mine.householdId} and name = 'Baumarkt'`;
    assertEquals([movedItem.listId, movedItem.category], [hardware?.id, 'Kühlregal']);

    const twin = await api(key.token, 'PATCH', `/items/${hafer.id}`, { body: { name: 'milch' } });
    assertEquals(twin.status, 409);
    assertEquals((await twin.json()).error, {
      code: 'conflict',
      message: 'An open item with this name, brand and details is already on the list.',
    });
    const [still] = await sql<
      { name: string }[]
    >`select name from public.items where id = ${hafer.id}`;
    assertEquals(still?.name, 'Hafermilch', 'the refused rename changed nothing');

    const noList = await api(key.token, 'PATCH', `/items/${hafer.id}`, { body: { list: 'Fest' } });
    assertEquals(noList.status, 422);
    assertEquals((await noList.json()).error.code, 'list_not_found');
  }));

test('job 344: DELETE removes an item in any status and keeps what the household learned', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const added = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Basilikum' }, { name: 'Brot' }] },
    });
    const [basil, bread] = (await added.json()).data.added as Item[];
    assertExists(basil);
    assertExists(bread);
    assert((basil as unknown as { category: string }).category !== 'Kühlregal');
    await api(key.token, 'PATCH', `/items/${basil.id}`, { body: { category: 'Kühlregal' } });

    const deleted = await api(key.token, 'DELETE', `/items/${basil.id}`);
    assertEquals(deleted.status, 200);
    const gone = (await deleted.json()).data;
    assertEquals([gone.id, gone.name, gone.category], [basil.id, 'Basilikum', 'Kühlregal']);
    assertEquals((await api(key.token, 'GET', `/items/${basil.id}`)).status, 404);
    const again = await api(key.token, 'DELETE', `/items/${basil.id}`);
    assertEquals(again.status, 404);
    assertEquals((await again.json()).error.code, 'item_not_found');

    const readded = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Basilikum' }] },
    });
    const [back] = (await readded.json()).data.added as { category: string }[];
    assertEquals(back?.category, 'Kühlregal', 'the delete kept the lesson');

    await api(key.token, 'POST', `/items/${bread.id}/tick`);
    const headers = { 'idempotency-key': `d-${crypto.randomUUID()}` };
    const ticked = await api(key.token, 'DELETE', `/items/${bread.id}`, { headers });
    assertEquals(ticked.status, 200);
    assertEquals((await ticked.json()).data.status, 'ticked', 'a ticked item can be deleted');
    const replay = await api(key.token, 'DELETE', `/items/${bread.id}`, { headers });
    assertEquals(replay.status, 200, 'a retry with the key replays the answer');
    assertEquals(replay.headers.get('idempotent-replayed'), 'true');
    await replay.body?.cancel();
    const [count] = await sql<{ count: number }[]>`
      select count(*)::int from public.items where id in (${basil.id}, ${bread.id})`;
    assertEquals(count?.count, 0);
  }));

test('job 344: GET /v1/household names the household, its currency and size, no members', () =>
  withMembers(async (sql, [mine, theirs]) => {
    await sql`insert into public.household_members (household_id, user_id, role)
              values (${mine.householdId}, ${theirs.userId}, 'member')`;
    const key = await mint(sql, mine, ['read']);
    const res = await api(key.token, 'GET', '/household');
    assertEquals(res.status, 200);
    assertEquals(await res.json(), {
      data: { id: mine.householdId, name: '73', currency: 'EUR', memberCount: 2 },
    });
    const theirKey = await mint(sql, theirs, ['read'], theirs.householdId);
    const theirs1 = (await (await api(theirKey.token, 'GET', '/household')).json()).data;
    assertEquals([theirs1.id, theirs1.memberCount], [theirs.householdId, 1], "the key's household");
  }));

type Recent = Item & { listId: string; tickedAt: string };

test("job 345: GET /v1/items/recent is the app's Zuletzt verwendet, one household only", () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const other = await mint(sql, theirs, ['read', 'write']);
    const add = async (name: string) => {
      const res = await api(key.token, 'POST', '/items', { body: { items: [{ name }] } });
      const [item] = (await res.json()).data.added as Item[];
      assertExists(item, name);
      return item;
    };
    const tick = async (item: Item) =>
      assertEquals((await api(key.token, 'POST', `/items/${item.id}/tick`)).status, 200);
    const recent = async (query = '', token = key.token) => {
      const res = await api(token, 'GET', `/items/recent${query}`);
      assertEquals(res.status, 200, query);
      const body = await res.json();
      assertEquals(body.nextCursor, null);
      return body.data as Recent[];
    };

    const firstMilk = await add('Milch');
    await tick(firstMilk);
    const bread = await add('Brot');
    await tick(bread);
    const milk = await add('Milch');
    await tick(milk);
    const butter = await add('Butter');
    await tick(butter);
    await add('Butter');

    const shown = await recent();
    assertEquals(
      shown.map((i) => [i.name, i.id, i.status]),
      [['Milch', milk.id, 'ticked'], ['Brot', bread.id, 'ticked']],
      'newest first, Milch once (its newest purchase), Butter left out: it is open again',
    );
    assert(shown.every((i) => !Number.isNaN(Date.parse(i.tickedAt))), 'tickedAt is a time');
    assertEquals((await recent('?limit=1')).map((i) => i.name), ['Milch']);

    const [list] = await sql<{ id: string; name: string }[]>`
      select id, name from public.lists where household_id = ${mine.householdId}`;
    assertExists(list);
    assertEquals((await recent(`?list=${encodeURIComponent(list.name)}`)).length, 2);
    await sql`insert into public.lists (household_id, name, position)
              values (${mine.householdId}, 'Baumarkt', 1)`;
    assertEquals(await recent('?list=Baumarkt'), [], 'another list has its own');

    assertEquals(await recent('', other.token), [], 'another household sees none of it');
    const unknown = await api(key.token, 'GET', '/items/recent?list=Garten');
    assertEquals(unknown.status, 422);
    assertEquals((await unknown.json()).error.code, 'list_not_found');
    for (const bad of ['?limit=0', '?limit=51', '?store=dm']) {
      const res = await api(key.token, 'GET', `/items/recent${bad}`);
      assertEquals(res.status, 400, bad);
      assertEquals((await res.json()).error.code, 'validation_failed', bad);
    }
  }));

test("job 345: GET /v1/suggestions answers public.suggest_items, the app's usuals ranking", () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const other = await mint(sql, theirs, ['read']);
    for (const name of ['Brot', 'Brötchen', 'Milch', 'Bio-Brot']) {
      const res = await api(key.token, 'POST', '/items', { body: { items: [{ name }] } });
      const [item] = (await res.json()).data.added as Item[];
      assertExists(item);
      if (name !== 'Milch') await api(key.token, 'POST', `/items/${item.id}/tick`);
    }
    const suggestions = async (query: string, token = key.token) => {
      const res = await api(token, 'GET', `/suggestions${query}`);
      assertEquals(res.status, 200, query);
      return (await res.json()).data as Record<string, unknown>[];
    };
    const direct = (prefix: string, limit: number) =>
      asUser(
        mine.userId,
        (tx) =>
          tx`select name, quantity, uses, to_json(last_used) #>> '{}' as "lastUsed", due
           from public.suggest_items(${mine.householdId}, ${prefix}, ${limit})`,
      );

    const all = await suggestions('');
    assertEquals(all, [...await direct('', 10)], 'the same rows in the same order');
    assertFalse(all.some((u) => u.name === 'Milch'), 'what is open on a list is left out');
    const br = await suggestions('?prefix=br&limit=5');
    assertEquals(br, [...await direct('br', 5)]);
    assertEquals(
      br.map((u) => u.name).slice(0, 2).sort(),
      ['Brot', 'Brötchen'],
      'names starting with it first, then a word starting with it',
    );
    assertEquals(br.at(-1)?.name, 'Bio-Brot');
    assertEquals(Object.keys(br[0] ?? {}).sort(), ['due', 'lastUsed', 'name', 'quantity', 'uses']);
    assertEquals(await suggestions('?prefix=br', other.token), [], "only the key's household");
    for (const bad of ['?limit=0', '?limit=51', `?prefix=${'x'.repeat(61)}`, '?list=x']) {
      const res = await api(key.token, 'GET', `/suggestions${bad}`);
      assertEquals(res.status, 400, bad);
    }
  }));

type List = { id: string; name: string; sortOrder: number; default: boolean };

test('job 345: POST and PATCH /v1/lists make and change lists like the app, up to 50', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const other = await mint(sql, theirs, ['read', 'write']);
    const lists = async (token = key.token) =>
      (await (await api(token, 'GET', '/lists')).json()).data as List[];
    const [first] = await lists();
    assertExists(first);

    const made = await api(key.token, 'POST', '/lists', { body: { name: '  Bau   markt ' } });
    assertEquals(made.status, 201);
    const baumarkt = (await made.json()).data as List;
    assertEquals([baumarkt.name, baumarkt.sortOrder, baumarkt.default], ['Bau markt', 1, false]);
    assertEquals((await lists()).map((l) => l.name), [first.name, 'Bau markt']);

    const headers = { 'idempotency-key': crypto.randomUUID() };
    const once = await api(key.token, 'POST', '/lists', { body: { name: 'Garten' }, headers });
    const twice = await api(key.token, 'POST', '/lists', { body: { name: 'Garten' }, headers });
    assertEquals([once.status, twice.status], [201, 201]);
    assertEquals(twice.headers.get('idempotent-replayed'), 'true');
    assertEquals((await once.json()).data, (await twice.json()).data);
    assertEquals((await lists()).filter((l) => l.name === 'Garten').length, 1);

    const renamed = await api(key.token, 'PATCH', `/lists/${baumarkt.id}`, {
      body: { name: 'Baumarkt', position: 0 },
    });
    assertEquals(renamed.status, 200);
    assertEquals(
      (await renamed.json()).data,
      { ...baumarkt, name: 'Baumarkt', sortOrder: 0, default: true },
      'first now, it is the default of a member who never picked one, as in the app',
    );
    assertEquals((await lists()).map((l) => [l.name, l.sortOrder]), [
      ['Baumarkt', 0],
      [first.name, 1],
      ['Garten', 2],
    ]);
    await asUser(mine.userId, (tx) => tx`select public.set_default_list(${first.id})`);
    await api(key.token, 'PATCH', `/lists/${first.id}`, { body: { position: 2 } });
    assertEquals((await lists()).find((l) => l.default)?.id, first.id, 'a picked default stays');

    const [theirList] = await lists(other.token);
    assertExists(theirList);
    for (const id of [theirList.id, crypto.randomUUID()]) {
      const res = await api(key.token, 'PATCH', `/lists/${id}`, { body: { name: 'Meins' } });
      assertEquals(res.status, 404);
      assertEquals((await res.json()).error.code, 'list_not_found');
    }
    assertEquals((await lists(other.token))[0]?.name, theirList.name, 'theirs is untouched');

    for (
      const body of [{}, { name: '' }, { name: 'x'.repeat(61) }, { position: -1 }, { sortOrder: 1 }]
    ) {
      const res = await api(key.token, 'PATCH', `/lists/${baumarkt.id}`, { body });
      assertEquals(res.status, 400, JSON.stringify(body));
    }
    const tooLong = await api(key.token, 'POST', '/lists', { body: { name: ' '.repeat(3) } });
    assertEquals(tooLong.status, 400);
    // JS trim keeps U+0085, Postgres finds the name blank: a 400, not a failure.
    await refill(sql, key.id);
    for (
      const [path, method] of [['/lists', 'POST'], [`/lists/${baumarkt.id}`, 'PATCH'], [
        '/stores',
        'POST',
      ]] as const
    ) {
      const blank = await api(key.token, method, path, { body: { name: '\u0085' } });
      assertEquals(
        [blank.status, (await blank.json()).error.code],
        [400, 'validation_failed'],
        path,
      );
    }

    await sql`insert into public.lists (household_id, name, position)
              select ${mine.householdId}, 'Liste ' || n, 2 + n from generate_series(1, 47) n`;
    await refill(sql, key.id);
    const full = await api(key.token, 'POST', '/lists', { body: { name: 'Eine zu viel' } });
    assertEquals(full.status, 409);
    assertEquals((await full.json()).error, {
      code: 'too_many_lists',
      message: 'The household has 50 lists, as many as it may. Nothing was changed.',
      details: { limit: 50 },
    });
    assertEquals((await lists()).length, 50);
  }));

type Store = { id: string; name: string; sortOrder: number };
type Layout = { id: string; name: string; sortOrder: number; hidden: boolean };

test('job 345: stores by plain name only, their walk order, one household, up to 50', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine, ['read', 'write']);
    const other = await mint(sql, theirs, ['read', 'write']);
    const stores = async (token = key.token) =>
      (await (await api(token, 'GET', '/stores')).json()).data as Store[];

    const made = await api(key.token, 'POST', '/stores', { body: { name: 'Rewe' } });
    assertEquals(made.status, 201);
    const rewe = (await made.json()).data as Store;
    assertEquals(Object.keys(rewe).sort(), ['id', 'name', 'sortOrder'], 'no chain, country or app');
    const again = await api(key.token, 'POST', '/stores', { body: { name: ' rewe ' } });
    assertEquals(again.status, 200, 'a name the household has is that store');
    assertEquals((await again.json()).data, rewe);
    for (
      const body of [
        { name: 'Rewe', chain: 'rewe' },
        { name: 'Rewe', country: 'DE' },
        { name: '' },
        {
          name: 'x'.repeat(41),
        },
      ]
    ) {
      const res = await api(key.token, 'POST', '/stores', { body });
      assertEquals(res.status, 400, JSON.stringify(body));
    }
    const [row] = await sql`
      select retailer_chain, retailer_country, retailer_app from public.stores where id = ${rewe.id}`;
    assertEquals(
      row,
      { retailer_chain: null, retailer_country: null, retailer_app: null },
      'no retailer chain is set',
    );

    const renamed = await api(key.token, 'PATCH', `/stores/${rewe.id}`, {
      body: { name: 'REWE City' },
    });
    assertEquals(renamed.status, 200);
    assertEquals((await renamed.json()).data, { ...rewe, name: 'REWE City' });
    const taken = await api(key.token, 'PATCH', `/stores/${rewe.id}`, { body: { name: 'DM' } });
    assertEquals(taken.status, 409);
    assertEquals(
      (await taken.json()).error.message,
      'Another store of the household has this name.',
    );

    await refill(sql, key.id);
    const theirs1 = (await stores(other.token))[0];
    assertExists(theirs1);
    for (
      const [method, path, body] of [
        ['PATCH', `/stores/${theirs1.id}`, { name: 'Meins' }],
        ['GET', `/stores/${theirs1.id}/layout`, undefined],
        ['PUT', `/stores/${theirs1.id}/layout`, { categories: ['Kühlregal'] }],
        ['PATCH', `/stores/${crypto.randomUUID()}`, { name: 'Meins' }],
      ] as const
    ) {
      const res = await api(key.token, method, path, { body });
      assertEquals(res.status, 404, `${method} ${path}`);
      assertEquals((await res.json()).error.code, 'store_not_found');
    }
    assertEquals((await stores(other.token))[0], theirs1, 'theirs is untouched');

    const layout = async () =>
      (await (await api(key.token, 'GET', `/stores/${rewe.id}/layout`)).json()).data as Layout[];
    const before = await layout();
    assertEquals(before.length, 11);
    assert(before.every((c) => !c.hidden));
    const set = await api(key.token, 'PUT', `/stores/${rewe.id}/layout`, {
      body: { categories: ['kühlregal', 'Getränke'], hidden: ['Drogerie'] },
    });
    assertEquals(set.status, 200);
    const after = (await set.json()).data as Layout[];
    assertEquals(after, await layout());
    assertEquals(
      after.map((c) => c.name),
      [
        'Kühlregal',
        'Getränke',
        ...before.map((c) => c.name).filter((n) => !['Kühlregal', 'Getränke'].includes(n)),
      ],
      'the named first, the rest in their order',
    );
    assertEquals(after.filter((c) => c.hidden).map((c) => c.name), ['👶 Drogerie']);
    const keep = await api(key.token, 'PUT', `/stores/${rewe.id}/layout`, {
      body: { categories: ['Getränke'] },
    });
    assertEquals(
      ((await keep.json()).data as Layout[]).filter((c) => c.hidden).map((c) => c.name),
      ['👶 Drogerie'],
      'hidden stays unless given',
    );

    await refill(sql, key.id);
    const items = await api(key.token, 'POST', '/items', {
      body: { items: [{ name: 'Brot' }, { name: 'Milch' }, { name: 'Wasser' }] },
    });
    assertEquals(items.status, 201);
    const walk = await api(key.token, 'GET', `/items?store=${encodeURIComponent('REWE City')}`);
    assertEquals(
      ((await walk.json()).data as Item[]).map((i) => i.name),
      ['Wasser', 'Milch', 'Brot'],
      'GET /v1/items with the store walks its new order',
    );

    const kuehl = after.find((c) => c.name === 'Kühlregal');
    assertExists(kuehl);
    for (
      const [body, status, code] of [
        [{ categories: ['Kühlregal', kuehl.id] }, 400, 'validation_failed'],
        [{ categories: ['Garten'] }, 422, 'category_not_found'],
        [{}, 400, 'validation_failed'],
      ] as const
    ) {
      const res = await api(key.token, 'PUT', `/stores/${rewe.id}/layout`, { body });
      assertEquals(
        [res.status, (await res.json()).error.code],
        [status, code],
        JSON.stringify(body),
      );
    }
    assertEquals(
      (await layout()).map((c) => c.name)[0],
      'Getränke',
      'a refused PUT changes nothing',
    );

    await sql`insert into public.stores (household_id, name, sort_order)
              select ${mine.householdId}, 'Laden ' || n, 100 + n from generate_series(1, 46) n`;
    await refill(sql, key.id);
    assertEquals((await stores()).length, 50);
    const full = await api(key.token, 'POST', '/stores', { body: { name: 'Aldi' } });
    assertEquals(full.status, 409);
    assertEquals((await full.json()).error.code, 'too_many_stores');
    const known = await api(key.token, 'POST', '/stores', { body: { name: 'lidl' } });
    assertEquals(known.status, 200, 'a known name still answers at the cap');
    assertEquals((await stores()).length, 50, 'nothing was added');
  }));

test("job 345 review 0: a member of two households: the new routes stay in the key's household", () =>
  withMembers(async (sql, [mine, theirs]) => {
    // RLS lets this member see both households: only the household filters keep the key in its own.
    await sql`insert into public.household_members (household_id, user_id, role)
              values (${theirs.householdId}, ${mine.userId}, 'member')`;
    const key = await mint(sql, mine, ['read', 'write'], mine.householdId);
    const theirKey = await mint(sql, theirs, ['read', 'write']);
    const addAndTick = async (token: string, name: string) => {
      const res = await api(token, 'POST', '/items', { body: { items: [{ name }] } });
      const [item] = (await res.json()).data.added as Item[];
      assertExists(item, name);
      assertEquals((await api(token, 'POST', `/items/${item.id}/tick`)).status, 200);
    };
    await addAndTick(key.token, 'Eigenmilch');
    await addAndTick(theirKey.token, 'Fremdbrot');

    const names = async (path: string) => {
      const res = await api(key.token, 'GET', path);
      assertEquals(res.status, 200, path);
      return ((await res.json()).data as { name: string }[]).map((r) => r.name);
    };
    assertEquals(await names('/items/recent'), ['Eigenmilch'], 'recent without list');
    const [ownList] = await sql<{ id: string }[]>`
      select id from public.lists where household_id = ${mine.householdId}`;
    assertExists(ownList);
    assertEquals(
      await names(`/items/recent?list=${ownList.id}`),
      ['Eigenmilch'],
      'recent with list',
    );
    assertEquals(await names('/suggestions'), ['Eigenmilch'], 'suggestions');
    assertEquals(await names('/suggestions?prefix=fremd'), [], 'no usual of the other household');

    const theirState = () =>
      Promise.all([
        sql`select id, name, position from public.lists where household_id = ${theirs.householdId}
            order by id`,
        sql`select id, name, sort_order from public.stores where household_id = ${theirs.householdId}
            order by id`,
        sql`select store_id, category_id, sort_order, hidden from public.store_category_order
            where household_id = ${theirs.householdId} order by store_id, category_id`,
      ]).then((all) => all.map((rows) => [...rows]));
    const before = await theirState();
    const [[theirList], [theirStore]] = await Promise.all([
      sql<{ id: string }[]>`select id from public.lists where household_id = ${theirs.householdId}`,
      sql<{ id: string }[]>`select id from public.stores
                            where household_id = ${theirs.householdId} order by sort_order`,
    ]);
    assertExists(theirList);
    assertExists(theirStore);
    await refill(sql, key.id);
    for (
      const [method, path, body, status, code] of [
        ['GET', `/items/recent?list=${theirList.id}`, undefined, 422, 'list_not_found'],
        [
          'PATCH',
          `/lists/${theirList.id}`,
          { name: 'Gekapert', position: 0 },
          404,
          'list_not_found',
        ],
        ['PATCH', `/stores/${theirStore.id}`, { name: 'Gekapert' }, 404, 'store_not_found'],
        ['GET', `/stores/${theirStore.id}/layout`, undefined, 404, 'store_not_found'],
        [
          'PUT',
          `/stores/${theirStore.id}/layout`,
          { categories: ['Sonstiges'] },
          404,
          'store_not_found',
        ],
      ] as const
    ) {
      const res = await api(key.token, method, path, { body });
      assertEquals(
        [res.status, (await res.json()).error.code],
        [status, code],
        `${method} ${path}`,
      );
    }

    const list =
      (await (await api(key.token, 'POST', '/lists', { body: { name: 'Baumarkt' } })).json())
        .data;
    const store =
      (await (await api(key.token, 'POST', '/stores', { body: { name: 'Rewe' } })).json())
        .data;
    const [madeList] = await sql<{ household_id: string }[]>`
      select household_id from public.lists where id = ${list.id}`;
    const [madeStore] = await sql<{ household_id: string }[]>`
      select household_id from public.stores where id = ${store.id}`;
    assertEquals(
      [madeList?.household_id, madeStore?.household_id],
      [mine.householdId, mine.householdId],
      "made in the key's household",
    );
    assertEquals(await theirState(), before, 'the other household is as it was');
  }));
