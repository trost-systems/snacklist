// What Siri and Alexa read of a household before they add or read aloud, in as few statements as
// the answer allows. Each statement the functions send costs two waits for the database: with
// `prepare: false` (_shared/db.ts) postgres.js asks for a statement's parameter types first, and
// sends nothing else on that connection meanwhile.
import type { Spoken } from '../alexa/speech.ts';
import type { Tx } from '../_shared/db.ts';
import {
  type ListCatalog,
  type ListOption,
  openItems,
  openItemsInWalk,
  type OrderMode,
  ToolError,
} from '../_shared/list.ts';

/** A list of the household, or none (a household without lists), with the household's facts. */
type HouseholdRow =
  & (ListOption | { id: null; name: null; seedKey: null })
  & { defaultId: string | null; mode: OrderMode | null };

/**
 * The household's lists with the caller's default among them, as listCatalog (_shared/list.ts)
 * has them, and its order mode, as orderMode has it: one statement instead of three.
 */
export async function householdLists(
  tx: Tx,
  household: string,
): Promise<{ catalog: ListCatalog; mode: OrderMode }> {
  const rows = await tx<HouseholdRow[]>`
    select l.id, l.name, l.seed_key as "seedKey", d.default_id as "defaultId", d.mode
    from (select public.default_list(${household}) as default_id,
                 (select order_mode from public.households where id = ${household}) as mode) d
    left join public.lists l on l.household_id = ${household}
    order by l.position, l.created_at, l.id`;
  const [first] = rows;
  if (!first?.mode) throw new Error('householdLists: no household');
  const lists: ListOption[] = [];
  for (const { id, name, seedKey } of rows) if (id !== null) lists.push({ id, name, seedKey });
  const defaultList = lists.find((o) => o.id === first.defaultId) ?? lists[0];
  // Every household has a list: none is visible only in a household the caller is not in.
  if (!defaultList) throw new ToolError('Keine Liste in diesem Haushalt.', 'not_found', 'list');
  return { catalog: { lists, defaultList }, mode: first.mode };
}

/**
 * The read-back: the open items of the caller's default list in the order the app and MCP's
 * list_items show them (listItems), without listItems' filters and counts, which a spoken list
 * never uses.
 */
export async function itemsToSay(tx: Tx, household: string): Promise<Spoken[]> {
  const { catalog, mode } = await householdLists(tx, household);
  const shown = { storeId: null, categoryId: null, listId: catalog.defaultList.id };
  const rows = mode === 'learned'
    ? await openItemsInWalk(tx, household, shown)
    : await openItems(tx, household, shown);
  return rows.map(({ name, quantity, brand, properties }) => ({
    name,
    quantity,
    brand,
    properties,
  }));
}
