import type { Tx } from '../_shared/db.ts';
import { listOf } from '../_shared/list.ts';
import type { Added, SplitItem } from './handler.ts';
import type { ParsedItem } from './parse.ts';

type Row = {
  id: string;
  name: string;
  brand: string | null;
  properties: string | null;
  quantity: string | null;
  category: string;
};

/**
 * Properties that only note how an item is made, not what it is: an open "Tomaten Bio" is still
 * "Tomaten". Every other property the parser keeps (gesalzen, passiert, laktosefrei, flavours,
 * sizes) makes another product. Peter Q79, docs/DECISIONS.md "Job 112": when unsure, add.
 */
const noteWords = new Set(['bio']);

/** No brand or properties: the very item a plain name means. */
const plain = (row: Row) => !row.brand && !row.properties;

/** The same item with its own brand or a note, nothing that makes it another product. */
const variant = (row: Row) =>
  !plain(row) &&
  (row.properties ?? '').split(',').map((p) => p.trim().toLowerCase()).filter(Boolean)
    .every((p) => noteWords.has(p));

/**
 * Adds the items to the household's first list (Siri and Alexa know no other) through
 * `add_list_item` (the parser, classifier, learned memory, store memory,
 * duplicate check) in one transaction. The splitter already read each amount, so the spoken
 * quantity goes in as the explicit one; brand and properties come from the parser. A new item
 * whose spelling variant or synonym is already open ("Karotten" with "Möhren") is still added
 * and names it in `similarOnList` (`public.similar_items`, job 32b); nothing is merged. A plain
 * name said while the same name, singular or plural, is open with a brand or a note ("Butter"
 * with "Butter Weihenstephan", "Tomate" with "Tomaten Bio") is held: nothing is added,
 * the open item is reported as already on the list with the request under `held`, so the caller
 * can ask whether to add it anyway. `addVariants` is that yes: held names are added as said.
 * An open item with a product word ("Butter gesalzen") is another product: the name is added.
 * Existing items are never changed.
 */
export async function addItems(
  tx: Tx,
  householdId: string,
  items: ParsedItem[],
  { addVariants = false }: { addVariants?: boolean } = {},
): Promise<Added[]> {
  const list = (await listOf(tx, householdId)).id;
  const active = await tx<{ id: string }[]>`
    select id from public.items where list_id = ${list} and status = 'active'`;
  const known = new Set(active.map((row) => row.id));
  const added: (Added & { id: string })[] = [];
  for (const item of items) {
    const named = addVariants ? [] : await tx<Row[]>`
      select o.id, o.name, o.brand, o.properties, o.quantity, c.name as category
      from public.parse_item(${householdId}, ${item.name}) p
      join public.items o on o.list_id = ${list} and o.status = 'active'
        and public.item_name_key(o.name) = public.item_name_key(p.name)
      join public.categories c on c.id = o.category_id
      where p.brand is null and p.properties is null
      order by o.created_at`;
    const open = named.find(plain) ?? named.find(variant);
    const [row] = open ? [open] : await tx<Row[]>`
      select a.id, a.name, a.brand, a.properties, a.quantity, c.name as category
      from public.add_list_item(${householdId}, ${list}, ${item.name}, p_quantity => ${item.quantity}) a
      join public.categories c on c.id = a.category_id`;
    // "Gurke und zwei Gurken" fold into one row; it is reported once.
    if (!row || added.some((a) => a.id === row.id)) continue;
    const alreadyOnList = known.has(row.id);
    const held = open && variant(open) ? item : null;
    const similar = alreadyOnList || addVariants ? [] : await tx<{ name: string }[]>`
      select concat_ws(' ', name, brand, replace(properties, ', ', ' ')) as name
      from public.similar_items(${row.id})`;
    added.push({ ...row, alreadyOnList, similarOnList: similar.map((s) => s.name), held });
  }
  return added.map(({ id: _, ...rest }) => rest);
}

/**
 * Splits brand, details, store and category off each item through `parse_item`, the parser `add_item` and
 * the app's typed add use: "Windeln Pampers Größe 3" is Windeln, Pampers, Größe 3, at dm. The
 * spoken quantity wins, as in `addItems`.
 */
export async function splitItems(
  tx: Tx,
  householdId: string,
  items: ParsedItem[],
): Promise<SplitItem[]> {
  const split: SplitItem[] = [];
  for (const item of items) {
    const [row] = await tx<SplitItem[]>`
      select name, brand, properties, quantity, store_id as "storeId", category_id as "categoryId"
      from public.parse_item(${householdId}, ${item.name})`;
    // A line parse_item reads no name from stays as heard, never dropped.
    split.push(
      row?.name
        ? { ...row, quantity: item.quantity ?? row.quantity }
        : { ...item, brand: null, properties: null, storeId: null, categoryId: null },
    );
  }
  return split;
}
