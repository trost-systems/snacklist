// Job 62: list_items reports the whole list's counts next to the items, whatever the filter, and
// only the caller's household. Job 169b W3: Siri and Alexa act in the household's first list. Runs _shared/list.ts as a signed-in user against the local stack
// (FG_DB_TEST=1, see add_paths_integration_test.ts).
import { assertEquals, assertExists, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl } from './db.ts';
import { addItems, counts, listItems, tickItems, ToolError } from './list.ts';
import { openItems as alexaOpenItems } from '../alexa/store.ts';
import { addItems as addVoiceItems } from '../voice/items.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

Deno.test({
  name: 'list_items counts open and recently ticked items of the whole list, per household',
  ignore: !enabled,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl(), { max: 1, prepare: false });
    const [me, them] = [crypto.randomUUID(), crypto.randomUUID()];
    const users = [me, them];
    try {
      const households: string[] = [];
      for (const user of users) {
        await admin`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
        households.push(
          await asUser(user, async (tx) => {
            const [row] = await tx<{ id: string }[]>`select id from public.create_household('62')`;
            assertExists(row);
            return row.id;
          }),
        );
      }
      const [mine, theirs] = households;
      assertExists(mine);
      assertExists(theirs);
      // Job 64: new households start without stores, so this list names its own.
      await admin`insert into public.stores (household_id, name, sort_order)
                  values (${mine}, 'Lidl', 0), (${mine}, 'dm', 1)`;
      await asUser(them, (tx) => addItems(tx, theirs, [{ name: 'Brot' }, { name: 'Käse' }]));

      await asUser(me, async (tx) => {
        const empty = await listItems(tx, mine, {});
        assertEquals(empty.counts, { open: 0, checkedLast24h: 0 });

        await addItems(tx, mine, [
          { name: 'Milch', store: 'Lidl' },
          { name: 'Zahnpasta', store: 'dm' },
          { name: 'Äpfel', store: 'Lidl' },
          { name: 'Butter' },
          { name: 'Salz' },
        ]);
        const { ticked } = await tickItems(tx, mine, ['Butter', 'butter', 'Salz']);
        assertEquals(ticked.map((i) => i.name).sort(), ['Butter', 'Salz'], 'each ticked item once');
      });
      await admin`update public.items set bought_at = now() - interval '2 days'
                  where household_id = ${mine} and name = 'Salz'`;

      await asUser(me, async (tx) => {
        const all = await listItems(tx, mine, {});
        assertEquals(all.items.length, 3);
        assertEquals(all.counts, { open: 3, checkedLast24h: 1 }, 'Salz was ticked two days ago');

        const lidl = await listItems(tx, mine, { store: 'Lidl' });
        assertEquals(lidl.items.map((i) => i.name).sort(), ['Milch', 'Äpfel']);
        assertEquals(lidl.counts, all.counts, 'a store filter keeps the whole list counts');

        const fruit = await listItems(tx, mine, { category: 'Obst' });
        assertEquals(fruit.items.map((i) => i.name), ['Äpfel']);
        assertEquals(fruit.counts.open, 3);
      });

      await asUser(them, async (tx) => {
        assertEquals((await listItems(tx, theirs, {})).counts, { open: 2, checkedLast24h: 0 });
        assertEquals(
          await counts(tx, mine, null),
          { open: 0, checkedLast24h: 0 },
          "RLS hides another household's items from the counts too",
        );
        await assertRejects(() => listItems(tx, mine, {}), ToolError, 'Keine Liste');
      });
    } finally {
      for (const user of users) {
        await admin`delete from public.households where id in (
          select household_id from public.household_members where user_id = ${user})`;
        await admin`delete from auth.users where id = ${user}`;
      }
      await admin.end();
    }
  },
});

Deno.test({
  name: 'job 169b W3: Siri and Alexa add to and read the first list only',
  ignore: !enabled,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl(), { max: 1, prepare: false });
    const me = crypto.randomUUID();
    try {
      await admin`insert into auth.users (id, email) values (${me}, ${`${me}@fg-test.invalid`})`;
      const household = await asUser(me, async (tx) => {
        const [row] = await tx<{ id: string }[]>`select id from public.create_household('W3')`;
        assertExists(row);
        await tx`select public.create_list(${row.id}, 'Baumarkt', gen_random_uuid())`;
        return row.id;
      });
      // The Baumarkt list goes in front: it is the first list now.
      await asUser(
        me,
        (tx) =>
          tx`select public.move_list(id, 0) from public.lists where name = 'Baumarkt'
           and household_id = ${household}`,
      );
      await asUser(me, (tx) => addItems(tx, household, [{ name: 'Milch' }], 'Einkaufsliste'));
      const said = await asUser(
        me,
        (tx) => addVoiceItems(tx, household, [{ name: 'Milch', quantity: null }]),
      );
      assertEquals(
        said.map((i) => i.alreadyOnList),
        [false],
        'Milch on the other list is no match',
      );
      const [onFirst] = await admin<{ name: string }[]>`
        select l.name from public.items i join public.lists l on l.id = i.list_id
        where i.household_id = ${household} and i.added_by = ${me} order by i.created_at desc limit 1`;
      assertEquals(onFirst?.name, 'Baumarkt', 'Siri adds to the first list');
      assertEquals(
        (await asUser(me, (tx) => alexaOpenItems(tx, household))).map((i) => i.name),
        ['Milch'],
        'Alexa reads the first list',
      );
      assertEquals(
        (await asUser(me, (tx) => listItems(tx, household, {}))).counts.open,
        1,
        'one open item on the first list, the other list not counted',
      );
    } finally {
      await admin`delete from public.households where created_by = ${me}`;
      await admin`delete from auth.users where id = ${me}`;
      await admin.end();
    }
  },
});
