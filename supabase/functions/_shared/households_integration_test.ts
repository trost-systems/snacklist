// Job 169b: a user in several households keeps exactly one default while memberships end and
// begin on two connections at once, as two phones or a phone and another member do. The first
// transaction holds its change open until the second was sent. Runs like
// one_open_item_integration_test.ts: the db gate sets FG_DB_TEST=1 and SUPABASE_DB_URL.
import { assertEquals } from '@std/assert';
import postgres from 'postgres';
import { analyticsSubject } from '../alexa/store.ts';
import { CONSENT_TEXT_VERSION } from './consent_version.ts';
import { databaseUrl, householdOf, isMember } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Sql = postgres.Sql;

const connect = () => postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });

/** A user in households A, B and C, joined in that order; A is the default. */
async function withThree(
  work: (
    s: { admin: Sql; one: Sql; two: Sql; user: string; ids: Record<string, string> },
  ) => Promise<void>,
) {
  const admin = connect();
  const one = connect();
  const two = connect();
  const user = crypto.randomUUID();
  const ids: Record<string, string> = {};
  try {
    await admin`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
    for (const [i, name] of ['A', 'B', 'C'].entries()) {
      const [row] = await admin<{ id: string }[]>`
        insert into public.households (name, created_by) values (${name}, ${user}) returning id`;
      ids[name] = row?.id ?? '';
      await admin`insert into public.household_members (household_id, user_id, joined_at)
        values (${ids[name]}, ${user}, now() - make_interval(days => ${3 - i}))`;
    }
    await work({ admin, one, two, user, ids });
  } finally {
    await admin`delete from public.households where created_by = ${user}`;
    await admin`delete from auth.users where id = ${user}`;
    await Promise.all([admin.end(), one.end(), two.end()]);
  }
}

function as<T>(sql: Sql, user: string, work: (tx: postgres.TransactionSql) => Promise<T>) {
  const claims = JSON.stringify({ sub: user, role: 'authenticated' });
  return sql.begin(async (tx) => {
    await tx`select set_config('role', 'authenticated', true),
                    set_config('request.jwt.claims', ${claims}, true)`;
    return await work(tx);
  }) as Promise<T>;
}

const pause = () => new Promise((r) => setTimeout(r, 300));

/** [first] holds its transaction open until [second] was sent and had time to block. */
async function overlapping(
  first: (release: Promise<void>) => Promise<unknown>,
  second: () => Promise<unknown>,
) {
  let release!: () => void;
  const a = first(new Promise<void>((resolve) => (release = resolve)));
  await pause();
  const b = second();
  await pause();
  release();
  await Promise.all([a, b]);
}

const memberships = async (admin: Sql, user: string) => [
  ...await admin<{ name: string; is_default: boolean }[]>`
    select h.name, m.is_default from public.household_members m
    join public.households h on h.id = m.household_id
    where m.user_id = ${user} order by m.joined_at`,
];

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('B is deleted while the user leaves their default A: C becomes the default', () =>
  withThree(async ({ admin, one, two, user, ids }) => {
    await overlapping(
      (release) =>
        two.begin(async (tx) => {
          await tx`delete from public.households where id = ${ids.B ?? ''}`;
          await release;
        }),
      () => as(one, user, (tx) => tx`select public.leave_household(${ids.A ?? ''})`),
    );
    assertEquals(await memberships(admin, user), [{ name: 'C', is_default: true }]);
  }));

test('the user leaves B while A, the default, is deleted: C becomes the default', () =>
  withThree(async ({ admin, one, two, user, ids }) => {
    await overlapping(
      (release) =>
        as(two, user, async (tx) => {
          await tx`select public.leave_household(${ids.B ?? ''})`;
          await release;
        }),
      () => one`delete from public.households where id = ${ids.A ?? ''}`,
    );
    assertEquals(await memberships(admin, user), [{ name: 'C', is_default: true }]);
  }));

test('leaving the default while joining another household: the user keeps one default', () =>
  withThree(async ({ admin, one, two, user, ids }) => {
    await admin`delete from public.household_members
      where user_id = ${user} and household_id in (${ids.B ?? ''}, ${ids.C ?? ''})`;
    const [lea] = await admin<{ id: string }[]>`
      insert into auth.users (id, email) values (gen_random_uuid(), 'lea169@fg-test.invalid') returning id`;
    try {
      const [household] = await as(
        admin,
        lea?.id ?? '',
        (tx) => tx<{ id: string }[]>`select id from public.create_household('Bei Lea')`,
      );
      const [invite] = await as(
        admin,
        lea?.id ?? '',
        (tx) =>
          tx<{ code: string }[]>`select code from public.create_invite(${household?.id ?? ''})`,
      );
      await overlapping(
        (release) =>
          as(two, user, async (tx) => {
            await tx`select public.leave_household(${ids.A ?? ''})`;
            await release;
          }),
        () =>
          as(
            one,
            user,
            (tx) => tx`select public.accept_invite(${invite?.code ?? ''}, p_mode => 'add')`,
          ),
      );
      assertEquals(await memberships(admin, user), [{ name: 'Bei Lea', is_default: true }]);
    } finally {
      await admin`delete from public.households where created_by = ${lea?.id ?? ''}`;
      await admin`delete from auth.users where id = ${lea?.id ?? ''}`;
    }
  }));

test('two creates at once by a user without a household: two households, one default', () =>
  withThree(async ({ admin, one, two, user }) => {
    await admin`delete from public.household_members where user_id = ${user}`;
    await overlapping(
      (release) =>
        as(two, user, async (tx) => {
          await tx`select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Eins')`;
          await release;
        }),
      () =>
        as(
          one,
          user,
          (tx) =>
            tx`select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Zwei')`,
        ),
    );
    const rows = await memberships(admin, user);
    assertEquals(rows.map((r) => r.name).sort(), ['Eins', 'Zwei']);
    assertEquals(rows.filter((r) => r.is_default).length, 1);
  }));

test('two old creates at once (no request id): one household, the other already_in_household', () =>
  withThree(async ({ admin, one, two, user }) => {
    await admin`delete from public.household_members where user_id = ${user}`;
    const outcomes: string[] = [];
    const create = (sql: Sql, name: string) =>
      as(sql, user, (tx) => tx`select public.create_household(${name})`).then(
        () => outcomes.push('created'),
        (e: { message?: string }) => outcomes.push(e.message ?? 'error'),
      );
    await overlapping(
      async (release) => {
        await two.begin(async (tx) => {
          const claims = JSON.stringify({ sub: user, role: 'authenticated' });
          await tx`select set_config('role', 'authenticated', true),
                          set_config('request.jwt.claims', ${claims}, true)`;
          await tx`select public.create_household('Eins')`;
          outcomes.push('created');
          await release;
        });
      },
      () => create(one, 'Zwei'),
    );
    assertEquals(outcomes.sort(), ['already_in_household', 'created']);
    assertEquals((await memberships(admin, user)).length, 1);
  }));

test('householdOf and the Alexa analytics subject read the default household', () =>
  withThree(async ({ admin, user, ids }) => {
    await as(admin, user, async (tx) => {
      await tx`select public.set_default_household(${ids.B ?? ''})`;
      await tx`select public.record_analytics_consent(gen_random_uuid(), true, false, true,
        ${CONSENT_TEXT_VERSION})`;
    });
    assertEquals(await householdOf(user), ids.B);
    const subject = await analyticsSubject(admin, user);
    assertEquals([subject?.householdId, subject?.role], [ids.B, 'member']);
  }));

test("isMember: any of the user's households, by id in any case; nothing else (voice, job 169b)", () =>
  withThree(async ({ user, ids }) => {
    for (const id of [ids.A ?? '', ids.B ?? '', (ids.C ?? '').toUpperCase()]) {
      assertEquals(await isMember(user, id), true, id);
    }
    for (const id of [crypto.randomUUID(), 'not-a-uuid', '']) {
      assertEquals(await isMember(user, id), false, id);
    }
    assertEquals(await isMember(crypto.randomUUID(), ids.A ?? ''), false, 'another user');
  }));
