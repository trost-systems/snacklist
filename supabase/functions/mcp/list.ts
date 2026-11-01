// The shopping-list operations behind the MCP tools. Every function runs inside asUser(), so RLS
// confines it to the caller's household; household_id filters only narrow the query plan.
import type { Tx } from '../_shared/db.ts';

export class ToolError extends Error {}

export type Named = { id: string; name: string };

export type Item = {
  id: string;
  name: string;
  /** Marke, e.g. "Pampers". */
  brand: string | null;
  /** Eigenschaften, comma-separated, e.g. "Größe 3, Big Pack". */
  properties: string | null;
  quantity: string | null;
  category: string;
  store: string | null;
};

/** Lowercase, umlauts folded, everything but letters and digits dropped: "👶 Drogerie" ~ "drogerie". */
export function fold(text: string): string {
  return text.toLowerCase()
    .replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Finds one entry by id, its name in any case, or a unique folded or partial name: "kuehlregal",
 * "Kühlregal" and "kühl" all find "Kühlregal", and "aldi süd" finds "Aldi Süd" next to "Aldi Sued".
 */
export function resolve<T extends Named>(options: readonly T[], query: string, what: string): T {
  const byId = UUID.test(query) ? options.find((o) => o.id === query.toLowerCase()) : undefined;
  if (byId) return byId;
  const key = query.trim().replace(/\s+/g, ' ').toLowerCase();
  const named = options.filter((o) => o.name.trim().replace(/\s+/g, ' ').toLowerCase() === key);
  if (named.length === 1) return named[0];
  const q = fold(query);
  const exact = options.filter((o) => fold(o.name) === q);
  if (exact.length === 1) return exact[0];
  const partial = q === '' ? [] : options.filter((o) => fold(o.name).includes(q));
  if (exact.length === 0 && partial.length === 1) return partial[0];
  const candidates = exact.length > 1 ? exact : partial;
  if (candidates.length > 1) {
    throw new ToolError(
      `${what} „${query}“ ist nicht eindeutig: ${candidates.map((c) => c.name).join(', ')}.`,
    );
  }
  throw new ToolError(
    `${what} „${query}“ nicht gefunden. Vorhanden: ${
      options.map((o) => o.name).join(', ') || '(keine)'
    }.`,
  );
}

export function categories(tx: Tx, household: string): Promise<(Named & { sort_order: number })[]> {
  return tx`select id, name, sort_order from public.categories
            where household_id = ${household} order by sort_order, name`;
}

export function stores(tx: Tx, household: string): Promise<(Named & { sort_order: number })[]> {
  return tx`select id, name, sort_order from public.stores
            where household_id = ${household} order by sort_order, name`;
}

function activeItems(
  tx: Tx,
  household: string,
): Promise<(Named & { store_id: string | null })[]> {
  return tx`select id, name, store_id from public.items
            where household_id = ${household} and status = 'active' order by created_at`;
}

function itemsById(tx: Tx, ids: readonly string[]): Promise<Item[]> {
  return tx`
    select i.id, i.name, i.brand, i.properties, i.quantity, c.name as category, s.name as store
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    where i.id = any(${ids}::uuid[])`;
}

export async function listItems(
  tx: Tx,
  household: string,
  filter: { store?: string; category?: string },
): Promise<{ store: string | null; category: string | null; items: Item[] }> {
  const store = filter.store ? resolve(await stores(tx, household), filter.store, 'Laden') : null;
  const category = filter.category
    ? resolve(await categories(tx, household), filter.category, 'Kategorie')
    : null;
  const storeId = store?.id ?? null;
  const categoryId = category?.id ?? null;
  // A store view shows the store's own items plus untagged ones, in that store's aisle order;
  // inside a category, the household's walk order (sort_key).
  const items = await tx<Item[]>`
    select i.id, i.name, i.brand, i.properties, i.quantity, c.name as category, s.name as store
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    left join public.store_category_order o
      on o.store_id = ${storeId}::uuid and o.category_id = i.category_id
    where i.household_id = ${household} and i.status = 'active'
      and (${storeId}::uuid is null or i.store_id is null or i.store_id = ${storeId}::uuid)
      and (${categoryId}::uuid is null or i.category_id = ${categoryId}::uuid)
    order by coalesce(o.sort_order, c.sort_order), c.name, i.sort_key, i.created_at, i.id`;
  return { store: store?.name ?? null, category: category?.name ?? null, items };
}

export type NewItem = {
  name: string;
  brand?: string;
  properties?: string;
  quantity?: string;
  category?: string;
  store?: string;
};

/** A blank optional field is not given: the parsed value stays. */
const given = (value: string | undefined) => value?.trim() || null;

/**
 * Adds items through public.add_item, the shared add path (also Siri's): it splits the name into
 * Bezeichnung, Marke, Eigenschaften and Menge ("Windeln Pampers Größe 3", "2 Gurken"), classifies
 * with the household's learned corrections, picks the store, and returns the existing row for an
 * item already on the list ("Gurke" is "2 Gurken"). An explicit quantity, brand, properties or
 * store replaces the parsed one. An explicit category is applied as an update, so the classifier
 * learns it like a correction in the app. A new item whose spelling variant or synonym is already
 * open ("Karotten" with "Möhren", public.similar_items) is still added and reported under
 * `similarOnList` with the open items; nothing is merged (job 32b).
 */
export async function addItems(
  tx: Tx,
  household: string,
  wanted: readonly NewItem[],
): Promise<{
  added: Item[];
  alreadyOnList: Item[];
  similarOnList: { added: string; onList: Item[] }[];
}> {
  const [cats, shops, active] = await Promise.all([
    categories(tx, household),
    stores(tx, household),
    activeItems(tx, household),
  ]);
  const seen = new Set(active.map((i) => i.id));
  const added: string[] = [];
  const existing: string[] = [];
  for (const item of wanted) {
    const category = item.category ? resolve(cats, item.category, 'Kategorie').id : null;
    const store = item.store ? resolve(shops, item.store, 'Laden').id : null;
    const [row] = await tx<{ id: string; category_id: string }[]>`
      select id, category_id from public.add_item(
        ${household}, ${item.name}, ${store}, ${given(item.brand)}, ${given(item.properties)},
        ${given(item.quantity)})`;
    if (!row) continue;
    if (seen.has(row.id)) {
      existing.push(row.id);
      continue;
    }
    seen.add(row.id);
    added.push(row.id);
    if (category && category !== row.category_id) {
      await tx`update public.items set category_id = ${category} where id = ${row.id}`;
    }
  }
  const similar: { added: string; onList: string[] }[] = [];
  for (const id of added) {
    const open = await tx<{ id: string }[]>`select id from public.similar_items(${id})`;
    if (open.length) similar.push({ added: id, onList: open.map((o) => o.id) });
  }
  const rows = await itemsById(tx, [...added, ...existing, ...similar.flatMap((s) => s.onList)]);
  const pick = (ids: string[]) => ids.map((id) => rows.find((r) => r.id === id)!);
  return {
    added: pick(added),
    alreadyOnList: pick(existing),
    similarOnList: similar.map((s) => ({ added: pick([s.added])[0].name, onList: pick(s.onList) })),
  };
}

export async function tickItems(
  tx: Tx,
  household: string,
  refs: readonly string[],
): Promise<{ ticked: Item[]; notFound: { item: string; reason: string }[] }> {
  const active = await activeItems(tx, household);
  const ids: string[] = [];
  const notFound: { item: string; reason: string }[] = [];
  for (const ref of refs) {
    try {
      ids.push(resolve(active, ref, 'Eintrag').id);
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      notFound.push({ item: ref, reason: e.message });
    }
  }
  if (ids.length > 0) {
    await tx`update public.items set status = 'bought' where id = any(${ids}::uuid[])`;
  }
  return { ticked: await itemsById(tx, ids), notFound };
}

/**
 * Changes category and/or store through public.move_item: the item goes to the end of its new
 * group, and the triggers learn both. A store left out stays; null untags.
 */
export async function moveItem(
  tx: Tx,
  household: string,
  move: { item: string; category?: string; store?: string | null },
): Promise<Item> {
  if (move.category === undefined && move.store === undefined) {
    throw new ToolError('Gib eine Kategorie oder einen Laden an.');
  }
  const item = resolve(await activeItems(tx, household), move.item, 'Eintrag');
  const category = move.category === undefined
    ? null
    : resolve(await categories(tx, household), move.category, 'Kategorie').id;
  const store = move.store === undefined
    ? item.store_id
    : move.store === null || move.store.trim() === ''
    ? null
    : resolve(await stores(tx, household), move.store, 'Laden').id;
  await tx`select from public.move_item(${item.id}, ${store}, ${category})`;
  const [moved] = await itemsById(tx, [item.id]);
  return moved;
}
