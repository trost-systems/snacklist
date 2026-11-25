// What the voice paths read (read.ts) is what _shared/list.ts reads: the lists and the default list
// as listCatalog has them and the order mode as orderMode has it, and a read-back that says what
// MCP's list_items lists, item for item and in its order, by categories and by learned places,
// nothing of another list or a ticked item, also when the caller's default is another list.
// Local stack, FG_DB_TEST=1.
import { assertEquals, assertExists, assertNotEquals } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl } from '../_shared/db.ts';
import { listCatalog, listItems, orderMode } from '../_shared/list.ts';
import { householdLists, itemsToSay } from './read.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

const names = [
  'Milch',
  '2 l Apfelsaft',
  'Windeln Pampers Größe 3',
  'Butter Weihenstephan',
  'Tomaten Bio',
  'Klopapier',
  'Brot',
  'Kaffee',
  'Zahnpasta',
  'Bananen',
];

Deno.test({
  name: 'the read-back lists what list_items lists, in both orders',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const user = crypto.randomUUID();
    try {
      await sql`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
      const { household, other } = await asUser(user, async (tx) => {
        const [h] = await tx<{ id: string }[]>`select id from public.create_household('read')`;
        assertExists(h);
        const [list] = await tx<{ id: string }[]>`select public.default_list(${h.id}) as id`;
        const [other] = await tx<{ id: string }[]>`
          select id from public.create_list(${h.id}, 'Apotheke', ${crypto.randomUUID()})`;
        assertExists(list);
        assertExists(other);
        for (const name of names) {
          await tx`select from public.add_list_item(${h.id}, ${list.id}, ${name})`;
        }
        await tx`select from public.add_list_item(${h.id}, ${other.id}, 'Pflaster')`;
        await tx`update public.items set status = 'bought', bought_at = now()
                 where household_id = ${h.id} and name = 'Brot'`;
        // Two items at a store: walked store by store, they come first.
        const [store] = await tx<{ id: string }[]>`select public.add_store(${h.id}, 'Laden') as id`;
        assertExists(store);
        await tx`update public.items set store_id = ${store.id}
                 where household_id = ${h.id} and name in ('Klopapier', 'Kaffee')`;
        return { household: h.id, other: other.id };
      });
      const expected = async () =>
        (await asUser(user, (tx) => listItems(tx, household, {}))).items.map(
          ({ name, quantity, brand, properties }) => ({ name, quantity, brand, properties }),
        );
      const said = () => asUser(user, (tx) => itemsToSay(tx, household));
      const sameAsList = async () => {
        const [read, catalog, mode] = await asUser(user, (tx) =>
          Promise.all([
            householdLists(tx, household),
            listCatalog(tx, household),
            orderMode(tx, household),
          ]));
        // listCatalog's lists are postgres.js's Result, an Array.
        assertEquals(read, { catalog: { ...catalog, lists: [...catalog.lists] }, mode });
      };
      await sameAsList();

      const byCategory = await said();
      assertEquals(byCategory.length, names.length - 1, 'the open items of the default list');
      assertEquals(byCategory, await expected());

      await asUser(user, (tx) => tx`select public.set_order_mode(${household}, 'learned')`);
      const walked = await said();
      assertEquals(walked, await expected());
      assertNotEquals(walked, byCategory, 'the two orders differ for this list');
      await sameAsList();

      await asUser(user, (tx) => tx`select public.set_default_list(${other})`);
      await sameAsList();
      assertEquals(await said(), [
        { name: 'Pflaster', quantity: null, brand: null, properties: null },
      ]);
      assertEquals(await said(), await expected());
    } finally {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${user})`;
      await sql`delete from auth.users where id = ${user}`;
      await sql.end();
    }
  },
});
