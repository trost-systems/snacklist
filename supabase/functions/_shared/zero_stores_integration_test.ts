// Job 58 (ADDENDUM 3): a household that skipped the stores in onboarding has none. Every path that
// reads or adds items copes: MCP (list_stores, add/list/move with and without a store; the AI
// assistants use these), voice and Siri, and Alexa's read-back. Runs the functions' real code as a
// signed-in user against the local stack (FG_DB_TEST=1, see add_paths_integration_test.ts).
import { assertEquals, assertExists, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl } from './db.ts';
import { addItems as mcpAddItems, listItems, stores, ToolError, updateItem } from './list.ts';
import { addItems as voiceAddItems } from '../voice/items.ts';
import { openItems } from '../alexa/store.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

async function withStorelessHousehold(
  work: (userId: string, householdId: string) => Promise<void>,
) {
  const admin = postgres(databaseUrl(), { max: 1, prepare: false });
  const userId = crypto.randomUUID();
  try {
    await admin`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`
        select id from public.create_household(p_name => '58', p_default_stores => false)`;
      assertExists(row);
      return row.id;
    });
    await work(userId, householdId);
  } finally {
    await admin`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await admin`delete from auth.users where id = ${userId}`;
    await admin.end();
  }
}

Deno.test({
  name:
    'MCP with no stores: list_stores is empty, adds and lists work, a store name is the friendly error',
  ignore: !enabled,
  sanitizeResources: false,
  fn: () =>
    withStorelessHousehold(async (userId, householdId) => {
      await asUser(userId, async (tx) => {
        assertEquals([...await stores(tx, householdId)], []);
        // Zahnpasta and Balea would go to dm in a household that has it.
        const { added } = await mcpAddItems(tx, householdId, [{ name: 'Zahnpasta' }, {
          name: 'Balea Duschgel',
        }]);
        assertEquals(added.map((i) => i?.store), [null, null]);
        const listed = await listItems(tx, householdId, {});
        assertEquals(listed.items.map((i) => i.name).sort(), ['Duschgel', 'Zahnpasta']);
        const moved = await updateItem(tx, householdId, { item: 'Zahnpasta' }, { store: null });
        assertEquals(moved.store, null);
      });
      await assertRejects(
        () =>
          asUser(userId, (tx) => mcpAddItems(tx, householdId, [{ name: 'Brot', store: 'Lidl' }])),
        ToolError,
        'Laden „Lidl“ nicht gefunden. Vorhanden: (keine).',
      );
      await assertRejects(
        () => asUser(userId, (tx) => listItems(tx, householdId, { store: 'dm' })),
        ToolError,
        'Vorhanden: (keine)',
      );
    }),
});

Deno.test({
  name: 'voice, Siri and Alexa with no stores: adds land without a store, the read-back lists them',
  ignore: !enabled,
  sanitizeResources: false,
  fn: () =>
    withStorelessHousehold(async (userId, householdId) => {
      const added = await asUser(
        userId,
        (tx) =>
          voiceAddItems(tx, householdId, [{ name: 'Zahnpasta', quantity: null }, {
            name: 'Milch',
            quantity: '2',
          }]),
      );
      assertEquals(added.map((i) => i.name), ['Zahnpasta', 'Milch']);
      const spoken = await asUser(userId, (tx) => openItems(tx, householdId));
      assertEquals(spoken.map((i) => i.name).sort(), ['Milch', 'Zahnpasta']);
    }),
});
