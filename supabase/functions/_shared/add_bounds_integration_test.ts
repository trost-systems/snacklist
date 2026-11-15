// Job 241: what one add may cost and answer on the shared add path (MCP, the API, voice): at most
// SIMILAR_SHOWN similar open items per added item with their number, a time budget for a batch,
// and the statement limit of every transaction as the caller. Runs like
// add_paths_integration_test.ts: the db gate sets FG_DB_TEST=1 and SUPABASE_DB_URL.
import { assert, assertEquals, assertExists, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl, OutOfTime, ranOutOfTime, STATEMENT_TIMEOUT } from './db.ts';
import { addItemIds, addItems as mcpAddItems, SIMILAR_SHOWN } from './list.ts';
import { addItems as voiceAddItems } from '../voice/items.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

/** Names that differ only in a number inside the word: one product for the duplicate hint. */
const variety = (n: number) => `Sorte${n}x`;

/** A household whose list holds the open items variety(1)..variety([open]), 1 the oldest. */
async function withVarieties(
  open: number,
  work: (userId: string, householdId: string) => Promise<void>,
) {
  const admin = postgres(databaseUrl(), { max: 1, prepare: false });
  const userId = crypto.randomUUID();
  try {
    await admin`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`select id from public.create_household('241')`;
      assertExists(row);
      return row.id;
    });
    await admin`
      insert into public.items (household_id, list_id, name, created_at)
      select ${householdId}, public.first_list(${householdId}), 'Sorte' || g || 'x',
             now() - interval '1 day' + g * interval '1 second'
      from generate_series(1, ${open}::int) g`;
    await work(userId, householdId);
  } finally {
    await admin`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await admin`delete from auth.users where id = ${userId}`;
    await admin.end();
  }
}

const openNames = (userId: string, householdId: string) =>
  asUser(userId, async (tx) => {
    const rows = await tx<{ name: string }[]>`
      select name from public.items
      where household_id = ${householdId} and status = 'active' order by created_at, id`;
    return rows.map((r) => r.name);
  });

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('MCP add_items names the three oldest similar open items and how many there are', () =>
  withVarieties(5, async (userId, householdId) => {
    const result = await asUser(
      userId,
      (tx) => mcpAddItems(tx, householdId, [{ name: variety(9) }, { name: 'Zahnseide' }]),
    );
    assertEquals(result.added.map((i) => i?.name), [variety(9), 'Zahnseide']);
    assertEquals(
      result.similarOnList.map((s) => [s.added, s.onList.map((i) => i?.name), s.total]),
      [[variety(9), [1, 2, 3].map(variety), 5]],
    );
    assertEquals(SIMILAR_SHOWN, 3);
  }));

test('voice names the three oldest similar open items', () =>
  withVarieties(5, async (userId, householdId) => {
    const added = await asUser(
      userId,
      (tx) => voiceAddItems(tx, householdId, [{ name: variety(9), quantity: null }]),
    );
    assertEquals(
      added.map((a) => [a.name, a.alreadyOnList, a.similarOnList]),
      [[variety(9), false, [1, 2, 3].map(variety)]],
    );
  }));

test('a batch past its time stops between two adds and leaves the list as it was', () =>
  withVarieties(2, async (userId, householdId) => {
    const wanted = [{ name: 'Milch' }, { name: 'Brot' }, { name: 'Butter' }];
    let openWhenStopped = 0;
    await assertRejects(
      () =>
        asUser(userId, async (tx) => {
          const clock = performance.now;
          const started = clock.call(performance);
          let asked = 0;
          performance.now = () => started + (asked++ === 0 ? 0 : 60_000);
          try {
            return await addItemIds(tx, householdId, wanted, undefined, started + 1000);
          } catch (e) {
            const [row] = await tx<{ n: number }[]>`
              select count(*)::int as n from public.items where household_id = ${householdId}`;
            openWhenStopped = row?.n ?? 0;
            throw e;
          } finally {
            performance.now = clock;
          }
        }),
      OutOfTime,
    );
    assertEquals(openWhenStopped, 3, 'the first add ran, the second found the time gone');
    assertEquals(await openNames(userId, householdId), [1, 2].map(variety), 'rolled back');

    const inTime = await asUser(userId, (tx) => addItemIds(tx, householdId, wanted));
    assertEquals(inTime.added.length, 3);
  }));

test('a transaction as the caller carries the statement limit; a statement over it ran out of time', () =>
  withVarieties(0, async (userId) => {
    const shown = await asUser(userId, async (tx) => {
      const [row] = await tx<{ statement_timeout: string }[]>`show statement_timeout`;
      return row?.statement_timeout;
    });
    assertEquals(shown, STATEMENT_TIMEOUT);

    const failure = await asUser(userId, async (tx) => {
      await tx`select set_config('statement_timeout', '50ms', true)`;
      await tx`select pg_sleep(2)`;
    }).then(() => null, (e: unknown) => e);
    assert(ranOutOfTime(failure), `a cancelled statement: ${failure}`);
    assert(ranOutOfTime(new OutOfTime()));
    assert(!ranOutOfTime(new Error('other')));
    assert(
      !ranOutOfTime(Object.assign(new Error('dup'), { name: 'PostgresError', code: '23505' })),
    );
  }));

test("one caller's transactions at once hold one connection; another caller's runs meanwhile", () =>
  withVarieties(1, (loud, loudHousehold) =>
    withVarieties(1, async (quiet, quietHousehold) => {
      const names = ['Milch', 'Brot', 'Butter', 'Salz', 'Mehl'];
      let taken = () => {};
      const locked = new Promise<void>((resolve) => {
        taken = resolve;
      });
      let release = () => {};
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      const holder = postgres(databaseUrl(), { max: 1, prepare: false });
      const holding = holder.begin(async (tx) => {
        await tx`select public.lock_household_items(${loudHousehold})`;
        taken();
        await released;
      });
      await locked;

      const adds = names.map((name) =>
        asUser(loud, (tx) => mcpAddItems(tx, loudHousehold, [{ name }]))
      );
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const served = await Promise.race([
          openNames(quiet, quietHousehold),
          new Promise<string>((resolve) => {
            timer = setTimeout(() => resolve('still waiting for a connection after 3 s'), 3000);
          }),
        ]);
        assertEquals(served, [variety(1)], "the other caller's read while the adds wait");
      } finally {
        clearTimeout(timer);
        release();
        await holding;
        await Promise.allSettled(adds);
        await holder.end();
      }

      await Promise.all(adds);
      assertEquals(
        await openNames(loud, loudHousehold),
        [variety(1), ...names],
        'each ran in its turn, in the order it came',
      );
    })));
