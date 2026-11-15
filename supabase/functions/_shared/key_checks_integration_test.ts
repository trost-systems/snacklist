// Job 241 review 1: checking a key does not wait for the key's or the household's row, and what a
// request does before its caller's turn (inTurn in db.ts) answers at once while that caller's rows
// are held, or while the household or the account is in the middle of its deletion. Each test holds
// rows from a side connection and asks for an answer within a second; the hold ends by itself
// after HOLD_MS, so a wait shows as a late answer, not as a hung run. Runs like
// add_paths_integration_test.ts: the db gate sets FG_DB_TEST=1 and SUPABASE_DB_URL.
import { assert, assertEquals, assertExists } from '@std/assert';
import postgres from 'postgres';
import { handle } from '../api/handler.ts';
import {
  AUTH_FAILURE_WINDOW_SECONDS,
  AUTH_FAILURES,
  BURST,
  PER_DAY,
  PER_MINUTE,
} from '../api/limits.ts';
import { analyticsSubject, remember, takeAdds } from '../alexa/store.ts';
import { productionDeps } from '../purchases/deps.ts';
import { createHandler } from '../purchases/handler.ts';
import { takeCall } from '../purchases/store.ts';
import { authenticate, sha256Hex } from './auth.ts';
import {
  asUser,
  databaseAnswers,
  databaseUrl,
  deleteAccount,
  householdOf,
  isMember,
  serviceDb,
  userExists,
} from './db.ts';
import { integrationGate } from './premium.ts';
import { telemetryFor } from './telemetry.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

/** An answer in time. */
const QUICK_MS = 1000;
/** How long a side connection holds its rows when the answer does not come. */
const HOLD_MS = 4000;

type Member = { userId: string; householdId: string };
type Key = { id: string; token: string };
type Held = (tx: postgres.TransactionSql) => Promise<unknown>;
type Answer<T> = { ms: number; value: T } | { ms: number; error: { code?: string; name?: string } };

const connect = (max: number) => postgres(databaseUrl(), { max, prepare: false });

/**
 * Runs [work] while a side connection holds what [hold] locks, and tells how long it took. The
 * hold ends once work has answered, or after HOLD_MS.
 */
async function whileHeld<T>(hold: Held, work: () => Promise<T>): Promise<Answer<T>> {
  const side = connect(1);
  try {
    let pending: Promise<Answer<T>> | undefined;
    await side.begin(async (tx) => {
      await hold(tx);
      const started = performance.now();
      const ms = () => Math.round(performance.now() - started);
      const answer = work().then(
        (value): Answer<T> => ({ ms: ms(), value }),
        (error): Answer<T> => ({ ms: ms(), error }),
      );
      pending = answer;
      let timer: ReturnType<typeof setTimeout> | undefined;
      const released = new Promise<void>((resolve) => {
        timer = setTimeout(resolve, HOLD_MS);
      });
      await Promise.race([answer, released]);
      clearTimeout(timer);
    });
    assertExists(pending);
    return await pending;
  } finally {
    await side.end();
  }
}

class Undone extends Error {}

/**
 * Runs [work] while [deletion] is in progress: [blockedBy] holds a row it has to wait for, so it
 * keeps the rows it took before that one. The deletion is rolled back afterwards.
 */
async function whileDeleting<T>(
  blockedBy: Held,
  deletion: Held,
  work: () => Promise<T>,
): Promise<Answer<T>> {
  const deleter = connect(1);
  let deleting: Promise<unknown> = Promise.resolve(new Undone());
  try {
    return await whileHeld(async (tx) => {
      await blockedBy(tx);
      const [backend] = await deleter<{ pid: number }[]>`select pg_backend_pid() as pid`;
      assertExists(backend);
      deleting = deleter.begin(async (going) => {
        await deletion(going);
        throw new Undone();
      }).catch((e) => e);
      for (let tries = 0;; tries++) {
        const waiting = await tx`
          select from pg_stat_activity where pid = ${backend.pid} and wait_event_type = 'Lock'`;
        if (waiting.length === 1) break;
        assert(tries < 150, 'the deletion never waited for the held row');
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
    }, work);
  } finally {
    const end = await deleting;
    await deleter.end();
    assert(end instanceof Undone, `the deletion: ${end}`);
  }
}

/** [answer]'s value, which came within QUICK_MS. */
function quick<T>(answer: Answer<T>, what: string): T {
  if ('error' in answer) {
    throw new Error(`${what}: ${answer.error.name} ${answer.error.code} after ${answer.ms} ms`);
  }
  assert(answer.ms < QUICK_MS, `${what}: answered after ${answer.ms} ms, with the rows held`);
  return answer.value;
}

/** [answer]'s error code, which came within QUICK_MS. */
function quickError<T>(answer: Answer<T>, what: string): string | undefined {
  assert('error' in answer, `${what}: answered, expected an error`);
  assert(answer.ms < QUICK_MS, `${what}: failed after ${answer.ms} ms, with the rows held`);
  return answer.error.code;
}

const session = (member: Member) => ({
  sub: member.userId,
  role: 'authenticated',
  session_id: crypto.randomUUID(),
});

/** An API key, minted the way the app does. */
const mint = (sql: postgres.Sql, member: Member): Promise<Key> =>
  sql.begin(async (tx) => {
    await tx`select set_config('role', 'authenticated', true),
                    set_config('request.jwt.claims', ${JSON.stringify(session(member))}, true)`;
    const [row] = await tx<Key[]>`
      select id, token from public.create_api_token('test', array['read', 'write'])`;
    assertExists(row);
    return row;
  }) as Promise<Key>;

/** An access token for MCP and voice. */
const mintAccessToken = (sql: postgres.Sql, member: Member): Promise<string> =>
  sql.begin(async (tx) => {
    await tx`select set_config('role', 'authenticated', true),
                    set_config('request.jwt.claims', ${JSON.stringify(session(member))}, true)`;
    const [row] = await tx<{ token: string }[]>`
      select token from public.create_personal_access_token('test')`;
    assertExists(row);
    return row.token;
  }) as Promise<string>;

const begin = async (sql: postgres.Sql, key: Key): Promise<string | undefined> => {
  const [row] = await sql<{ outcome: string }[]>`
    select outcome from public.api_begin(${await sha256Hex(key.token)}::text, 'key-checks-test',
      ${BURST}, ${PER_MINUTE}, ${PER_DAY}, ${AUTH_FAILURES}, ${AUTH_FAILURE_WINDOW_SECONDS})`;
  return row?.outcome;
};

const resolve = async (sql: postgres.Sql, token: string): Promise<string | undefined> => {
  const [row] = await sql<{ user_id: string }[]>`
    select user_id from public.authenticate_access_token(${await sha256Hex(token)})`;
  return row?.user_id;
};

const lastUsed = async (sql: postgres.Sql, userId: string): Promise<(string | null)[]> =>
  (await sql<{ last_used_at: string | null }[]>`
    select last_used_at::text from public.personal_access_tokens where user_id = ${userId}`)
    .map((r) => r.last_used_at);

const get = (token: string): Promise<Response> =>
  handle(
    new Request('http://localhost/api/v1/items', { headers: { authorization: `Bearer ${token}` } }),
  );

const statusOf = async (answer: Promise<Response>): Promise<number> => {
  const res = await answer;
  await res.body?.cancel();
  return res.status;
};

const withBearer = (token: string) =>
  new Request('http://localhost/voice', { headers: { authorization: `Bearer ${token}` } });

/** Rows of the member's keys, household and list. */
const membersRows = (member: Member): Held => async (tx) => {
  await tx`select from public.personal_access_tokens where user_id = ${member.userId}
           for no key update`;
  await tx`select from public.households where id = ${member.householdId} for no key update`;
  await tx`select from public.profiles where id = ${member.userId} for no key update`;
  await tx`select from public.household_members where user_id = ${member.userId} for update`;
  await tx`select from public.items where household_id = ${member.householdId} for update`;
  await tx`select from public.stores where household_id = ${member.householdId} for update`;
  await tx`select from public.categories where household_id = ${member.householdId} for update`;
  await tx`select public.lock_household_items(${member.householdId}::uuid)`;
};

const keyRows = (member: Member): Held => (tx) =>
  tx`select from public.personal_access_tokens where user_id = ${member.userId} for no key update`;

async function withMembers(
  work: (sql: postgres.Sql, members: [Member, Member]) => Promise<void>,
) {
  const sql = connect(2);
  const users = [crypto.randomUUID(), crypto.randomUUID()] as const;
  const switches = await sql<{ key: string; enabled: boolean }[]>`
    select key, enabled from public.app_switches where key in ('integration_lock', 'public_api')`;
  const log = console.log;
  console.log = () => {};
  try {
    const join = async (userId: string): Promise<Member> => {
      await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
      const householdId = await asUser(userId, async (tx) => {
        const [row] = await tx<{ id: string }[]>`
          select id from public.create_household(p_name => '241', p_default_stores => true)`;
        assertExists(row);
        return row.id;
      });
      await sql`insert into public.items (household_id, list_id, name)
                values (${householdId}, public.first_list(${householdId}), 'Milch')`;
      return { userId, householdId };
    };
    const members: [Member, Member] = [await join(users[0]), await join(users[1])];
    await setSwitch(sql, 'integration_lock', false);
    await setSwitch(sql, 'public_api', true);
    await work(sql, members);
  } finally {
    console.log = log;
    for (const { key, enabled } of switches) await setSwitch(sql, key, enabled);
    for (const userId of users) {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${userId})`;
      await sql`delete from auth.users where id = ${userId}`;
    }
    await sql.end();
  }
}

const setSwitch = (sql: postgres.Sql, key: string, on: boolean) =>
  sql`update public.app_switches set enabled = ${on} where key = ${key}`;

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test("a key check answers while another transaction holds the key's row", () =>
  withMembers(async (sql, [mine]) => {
    const fresh = await mint(sql, mine);
    const used = await mint(sql, mine);
    const token = await mintAccessToken(sql, mine);
    assertEquals(await begin(sql, used), 'ok');
    await sql`update public.personal_access_tokens set last_used_at = null
              where user_id = ${mine.userId}`;

    for (const key of [fresh, used]) {
      assertEquals(quick(await whileHeld(keyRows(mine), () => begin(sql, key)), 'api_begin'), 'ok');
    }
    assertEquals(
      quick(
        await whileHeld(keyRows(mine), () => resolve(sql, token)),
        'authenticate_access_token',
      ),
      mine.userId,
    );
    assertEquals(
      await lastUsed(sql, mine.userId),
      [null, null, null],
      'a held row keeps its last use',
    );

    assertEquals(await begin(sql, fresh), 'ok');
    assertEquals(await begin(sql, used), 'ok');
    assertEquals(await resolve(sql, token), mine.userId);
    assertEquals(
      (await lastUsed(sql, mine.userId)).filter((at) => at === null),
      [],
      'the next check of a free row writes it',
    );
  }));

test("requests with a key whose row is held are answered at once, and so is another household's", () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine);
    const other = await mint(sql, theirs);
    const token = await mintAccessToken(sql, mine);

    const api = await whileHeld(keyRows(mine), async () => {
      const sent = Array.from({ length: BURST }, () => statusOf(get(key.token)));
      const started = performance.now();
      const bystander = await statusOf(get(other.token));
      return { bystander, ms: performance.now() - started, mine: await Promise.all(sent) };
    });
    const answered = quick(api, 'the API with the key row held');
    assertEquals(answered.bystander, 200);
    assertEquals(answered.mine, Array.from({ length: BURST }, () => 200));

    const access = await whileHeld(keyRows(mine), async () => {
      const sent = Array.from({ length: 30 }, () => authenticate(withBearer(token)));
      const bystander = await asUser(theirs.userId, async (tx) => {
        const rows = await tx<{ name: string }[]>`select name from public.items`;
        return rows.map((r) => r.name);
      });
      return { bystander, mine: (await Promise.all(sent)).map((auth) => auth.userId) };
    });
    const resolved = quick(access, 'access tokens with the key row held');
    assertEquals(resolved.bystander, ['Milch']);
    assertEquals(resolved.mine, Array.from({ length: 30 }, () => mine.userId));
  }));

test("what a request does before its turn answers while the member's rows are held", () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine);
    const token = await mintAccessToken(sql, mine);
    const held = membersRows(mine);
    const caller = { userId: mine.userId, householdId: mine.householdId };
    const pool = serviceDb();

    assertEquals(
      quick(await whileHeld(held, () => statusOf(get(key.token))), 'GET /v1/items'),
      200,
    );
    assertEquals(
      quick(await whileHeld(held, () => authenticate(withBearer(token))), 'access token').userId,
      mine.userId,
    );
    assertEquals(
      quick(await whileHeld(held, () => householdOf(mine.userId)), 'householdOf'),
      mine.householdId,
    );
    assert(quick(await whileHeld(held, () => isMember(mine.userId, mine.householdId)), 'isMember'));
    assert(quick(await whileHeld(held, () => userExists(mine.userId)), 'userExists'));
    assertEquals(
      quick(await whileHeld(held, () => integrationGate(pool, caller, 'mcp')), 'gate, open'),
      { locked: false, report: false },
    );
    await setSwitch(sql, 'integration_lock', true);
    assertEquals(
      quick(await whileHeld(held, () => integrationGate(pool, caller, 'mcp')), 'gate, locked'),
      { locked: true, report: true },
    );
    assertEquals(
      quick(await whileHeld(held, () => integrationGate(pool, caller, 'mcp')), 'gate, again'),
      { locked: true, report: false },
    );
    await setSwitch(sql, 'integration_lock', false);
    assertEquals(
      quick(await whileHeld(held, () => analyticsSubject(pool, mine.userId)), 'analyticsSubject'),
      null,
    );
    assert(quick(await whileHeld(held, () => takeAdds(pool, mine.userId, 1)), 'Alexa allowance'));
    assert(quick(await whileHeld(held, () => takeCall(pool, mine.userId)), 'claim allowance'));
  }));

test('a key check and the gate end at once while the household or the key is being deleted', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const key = await mint(sql, mine);
    const fresh = await mint(sql, mine);
    const other = await mint(sql, theirs);
    const token = await mintAccessToken(sql, mine);
    const caller = { userId: mine.userId, householdId: mine.householdId };
    assertEquals(await begin(sql, key), 'ok');
    await setSwitch(sql, 'integration_lock', true);
    assertEquals(await integrationGate(sql, caller, 'api'), { locked: true, report: true });
    await setSwitch(sql, 'integration_lock', false);

    // The household's deletion, come as far as its lists: the keys and their counts are taken.
    const aList: Held = (tx) =>
      tx`select from public.lists where household_id = ${mine.householdId} for no key update`;
    const household: Held = (tx) =>
      tx`delete from public.households where id = ${mine.householdId}`;
    for (const k of [key, fresh]) {
      assertEquals(
        quickError(await whileDeleting(aList, household, () => begin(sql, k)), 'api_begin'),
        '55P03',
      );
    }
    const api = await whileDeleting(aList, household, async () => {
      const sent = Array.from({ length: 6 }, async () => {
        const res = await get(key.token);
        return [res.status, (await res.json()).error.code];
      });
      const bystander = await statusOf(get(other.token));
      return { bystander, mine: await Promise.all(sent) };
    });
    const answered = quick(api, 'the API, the household being deleted');
    assertEquals(answered.bystander, 200);
    assertEquals(answered.mine, Array.from({ length: 6 }, () => [503, 'unavailable']));
    assertEquals(
      quick(
        await whileDeleting(aList, household, () => authenticate(withBearer(token))),
        'access token',
      ).userId,
      mine.userId,
      'a deletion counts once it is committed',
    );
    await setSwitch(sql, 'integration_lock', true);
    assertEquals(
      quickError(
        await whileDeleting(aList, household, () => integrationGate(sql, caller, 'api')),
        'gate',
      ),
      '55P03',
    );
    assertEquals(
      await integrationGate(sql, caller, 'api'),
      { locked: true, report: false },
      'the deletion was undone, the report of this hour stands',
    );
    await setSwitch(sql, 'integration_lock', false);
    assertEquals(await begin(sql, key), 'ok', 'nothing was taken or kept by the calls that ended');

    // The same for a deletion that holds only the key's or the household's row so far, and for
    // one that took the day's count first: whichever order a deletion takes its rows in.
    const keyGoing: Held = (tx) =>
      tx`select from public.personal_access_tokens where user_id = ${mine.userId} for update`;
    const householdGoing: Held = async (tx) => {
      await tx`select from public.households where id = ${mine.householdId} for update`;
      await tx`delete from public.api_household_days where household_id = ${mine.householdId}`;
    };
    for (const [going, what] of [[keyGoing, 'key'], [householdGoing, 'household']] as const) {
      assertEquals(quickError(await whileHeld(going, () => begin(sql, key)), what), '55P03');
    }
    await setSwitch(sql, 'integration_lock', true);
    assertEquals(
      quickError(
        await whileHeld(householdGoing, () => integrationGate(sql, caller, 'api')),
        'gate',
      ),
      '55P03',
    );
  }));

test('a key check and the gate that wait for a lock all the same end after two seconds', () =>
  withMembers(async (sql, [mine]) => {
    const key = await mint(sql, mine);
    assertEquals(await begin(sql, key), 'ok');
    await setSwitch(sql, 'integration_lock', true);
    const caller = { userId: mine.userId, householdId: mine.householdId };
    assertEquals(await integrationGate(sql, caller, 'api'), { locked: true, report: true });

    const answers = [
      await whileHeld(
        (tx) => tx`select from public.api_token_buckets where token_id = ${key.id} for update`,
        () => begin(sql, key),
      ),
      await whileHeld(
        (tx) =>
          tx`select from public.integration_blocks where household_id = ${mine.householdId}
             for update`,
        () => integrationGate(sql, caller, 'api'),
      ),
    ];
    for (const answer of answers) {
      assert('error' in answer, 'the call ended');
      assertEquals(answer.error.code, '55P03');
      assert(answer.ms >= 1900 && answer.ms < 3000, `after ${answer.ms} ms`);
    }
  }));

/** What [call] ends with for [member]: 'ok', or the refusal's name. */
const outcome = (member: Member, call: (tx: postgres.TransactionSql) => Promise<unknown>) =>
  asUser(member.userId, call).then(() => 'ok', (e) => String(e.message));

test("a call that is refused does not wait for the household's rows", () =>
  withMembers(async (sql, [mine, other]) => {
    const [milk] = await sql<{ id: string; list_id: string }[]>`
      select id, list_id from public.items where household_id = ${mine.householdId}`;
    assertExists(milk);
    // The other one's household row too: what its owner asks for and cannot have holds nothing.
    const held: Held = async (tx) => {
      await membersRows(mine)(tx);
      await tx`select public.lock_memberships(${mine.userId}::uuid)`;
      await tx`select from public.households where id = ${other.householdId} for no key update`;
    };
    const answers = async (
      who: Member,
      calls: Record<string, (tx: postgres.TransactionSql) => Promise<unknown>>,
    ) => {
      const got: Record<string, string> = {};
      for (const [name, call] of Object.entries(calls)) {
        got[name] = quick(await whileHeld(held, () => outcome(who, call)), name);
      }
      return got;
    };

    assertEquals(
      await answers(other, {
        set_member_role: (tx) =>
          tx`select public.set_member_role(${mine.householdId}, ${mine.userId}, 'admin')`,
        leave_household: (tx) => tx`select public.leave_household(${mine.householdId})`,
        remove_member: (tx) => tx`select public.remove_member(${mine.householdId}, ${mine.userId})`,
        'remove_member, from their own household': (tx) =>
          tx`select public.remove_member(${other.householdId}, ${mine.userId})`,
        'set_member_role, in their own household': (tx) =>
          tx`select public.set_member_role(${other.householdId}, ${mine.userId}, 'admin')`,
        claim_item: (tx) => tx`select public.claim_item(${milk.id}, null)`,
        lock_household_items: (tx) => tx`select public.lock_household_items(${mine.householdId})`,
        'an add': (tx) =>
          tx`insert into public.items (household_id, list_id, name)
             values (${mine.householdId}, ${milk.list_id}, 'Brot')`,
      }),
      {
        set_member_role: 'not_member',
        leave_household: 'not_member',
        remove_member: 'not_member',
        'remove_member, from their own household': 'not_member',
        'set_member_role, in their own household': 'not_member',
        claim_item: 'not_a_member',
        lock_household_items: 'ok',
        'an add': 'not_a_member',
      },
      'someone outside the household',
    );

    await sql`insert into public.household_members (household_id, user_id, role)
              values (${mine.householdId}, ${other.userId}, 'member')`;
    assertEquals(
      await answers(other, {
        set_member_role: (tx) =>
          tx`select public.set_member_role(${mine.householdId}, ${mine.userId}, 'admin')`,
        remove_member: (tx) => tx`select public.remove_member(${mine.householdId}, ${mine.userId})`,
      }),
      { set_member_role: 'not_owner', remove_member: 'not_admin' },
      'a plain member',
    );
  }));

test("a household's key checks are answered while someone outside it asks for its roles and to leave it", () =>
  withMembers(async (sql, [mine, other]) => {
    const key = await mint(sql, mine);
    const hash = await sha256Hex(key.token);
    const callers = connect(4);
    try {
      let checking = true;
      let outside = 0;
      const ends: Record<string, number> = {};
      const keepCalling = async (call: (tx: postgres.TransactionSql) => Promise<unknown>) => {
        while (checking) {
          const end = await callers.begin(async (tx) => {
            await tx`select set_config('role', 'authenticated', true),
                            set_config('request.jwt.claims', ${
              JSON.stringify(session(other))
            }, true)`;
            await call(tx);
          }).then(() => 'ok', (e) => String(e.message));
          ends[end] = (ends[end] ?? 0) + 1;
          outside++;
        }
      };
      const role = (tx: postgres.TransactionSql) =>
        tx`select public.set_member_role(${mine.householdId}, ${mine.userId}, 'admin')`;
      const leave = (tx: postgres.TransactionSql) =>
        tx`select public.leave_household(${mine.householdId})`;
      const calling = [role, leave, role, leave].map(keepCalling);

      // At least 400 checks, and as many more as it takes for 400 calls from outside to end.
      const checks: Record<string, number> = {};
      for (let n = 0; n < 400 || outside < 400; n++) {
        const end = await sql<{ outcome: string }[]>`
          select outcome from public.api_begin(${hash}::text, 'key-checks-test', 1000000, 1000000,
            1000000, ${AUTH_FAILURES}, ${AUTH_FAILURE_WINDOW_SECONDS})`
          .then(([row]) => row?.outcome ?? 'none', (e) => String(e.code));
        checks[end] = (checks[end] ?? 0) + 1;
      }
      checking = false;
      await Promise.all(calling);

      assertEquals(Object.keys(checks), ['ok']);
      assertEquals(Object.keys(ends), ['not_member']);
    } finally {
      await callers.end();
    }
  }));

test('the allowances and the Alexa link end at once while the account is being deleted', () =>
  withMembers(async (sql, [mine, theirs]) => {
    const pool = serviceDb();
    const purchases = createHandler(productionDeps(
      { webhook: null, local: true, region: null, revenueCat: null, deletionsSecret: null },
      telemetryFor('purchases', { get: () => undefined }),
      { authenticate: () => Promise.resolve({ userId: mine.userId }) },
    ));
    const claim = async () => {
      const res = await purchases(
        new Request('http://local/functions/v1/purchases/claim', {
          method: 'POST',
          headers: { authorization: 'Bearer s' },
          body: JSON.stringify({
            store: 'apple',
            householdId: mine.householdId,
            transactionId: 'key-checks',
          }),
        }),
      );
      return [res.status, await res.json()];
    };
    const link = { userId: mine.userId, sessionId: crypto.randomUUID() };
    const code = (work: Promise<unknown>) => work.then(() => 'answered', (e) => e.code);

    // The account's deletion, come as far as a list of another household that names the user.
    await sql`update public.lists set created_by = ${mine.userId}
              where household_id = ${theirs.householdId}`;
    const aList: Held = (tx) =>
      tx`select from public.lists where household_id = ${theirs.householdId} for no key update`;
    const account: Held = (tx) => tx`select public.delete_account(${mine.userId}::uuid)`;

    for (
      const [what, call] of [
        ['claim allowance', () => takeCall(pool, mine.userId)],
        ['Alexa allowance', () => takeAdds(pool, mine.userId, 1)],
        ['Alexa link', () => remember(pool, 'key-checks-alexa-user', link, false)],
      ] as const
    ) {
      // Once with the user's rows not written yet, once with them written.
      for (const _ of ['first', 'again']) {
        const during = await whileDeleting(aList, account, async () => {
          const calls = [1, 2, 3].map(() => code(call()));
          return { database: await databaseAnswers(), codes: await Promise.all(calls) };
        });
        assertEquals(
          quick(during, what),
          { database: true, codes: ['55P03', '55P03', '55P03'] },
          what,
        );
        await call();
      }
    }
    assertEquals(
      quick(await whileDeleting(aList, account, claim), 'POST /claim'),
      [503, { error: 'busy' }],
    );
    assert(await userExists(mine.userId), 'the deletion was undone');
  }));

test("a member's purchase claims and account deletions take one connection at a time", () =>
  withMembers(async (_sql, [mine]) => {
    const deps = productionDeps(
      { webhook: null, local: true, region: null, revenueCat: null, deletionsSecret: null },
      telemetryFor('purchases', { get: () => undefined }),
    );
    const household: Held = (tx) =>
      tx`select from public.households where id = ${mine.householdId} for no key update`;
    const settled = <T>(work: Promise<T>) => work.then((value) => value, () => null);

    let claims: Promise<unknown[]> | undefined;
    const duringClaims = await whileHeld(household, async () => {
      claims = Promise.all(
        [1, 2, 3].map((n) =>
          settled(deps.claim(mine.userId, mine.householdId, 'apple', `key-checks-${n}`))
        ),
      );
      return await databaseAnswers();
    });
    assert(quick(duringClaims, 'the database, three claims waiting'));
    assertExists(claims);
    assertEquals(
      (await claims).map((c) => (c as { status?: string } | null)?.status),
      ['waiting', 'waiting', 'waiting'],
    );

    let deletions: Promise<unknown[]> | undefined;
    const duringDeletions = await whileHeld(household, async () => {
      deletions = Promise.all([1, 2, 3].map(() => settled(deleteAccount(mine.userId))));
      return await databaseAnswers();
    });
    assert(quick(duringDeletions, 'the database, three deletions waiting'));
    assertExists(deletions);
    assertEquals((await deletions)[0], 'deleted');
    assertEquals(await userExists(mine.userId), false);
  }));

test('ten API keys a user, also for calls that arrive together', () =>
  withMembers(async (sql, [mine]) => {
    const many = connect(15);
    try {
      const made = await Promise.all(
        Array.from({ length: 15 }, () => mint(many, mine).then(() => 'made', (e) => e.message)),
      );
      assertEquals(made.filter((m) => m === 'made').length, 10);
      assertEquals(
        made.filter((m) => m !== 'made'),
        Array.from({ length: 5 }, () => 'too_many_tokens'),
      );
      const [row] = await sql<{ n: number }[]>`
        select count(*)::int as n from public.personal_access_tokens
        where user_id = ${mine.userId} and kind = 'api' and revoked_at is null`;
      assertEquals(row?.n, 10);
    } finally {
      await many.end();
    }
  }));
