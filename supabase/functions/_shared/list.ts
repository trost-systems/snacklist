// The shopping-list operations behind the MCP tools and the API. Every function runs as the
// signed-in user (asUser), so RLS confines it to the caller's households; the household_id filters
// keep it to the one the key or session acts for (a user can be in several, job 169b), and narrow
// the query plan. A household has one or more lists (job 169b W3): the tools act in
// the list a `list` reference names, else in the caller's default list there (job 207,
// public.default_list: their choice, else the first list), where Siri and Alexa act too.
import { oneRow, type Tx } from './db.ts';

export type ToolErrorReason = 'not_found' | 'ambiguous' | 'invalid';

/** What a name or id was meant to find. */
export type Subject = 'item' | 'store' | 'category' | 'list';

/**
 * A request the list cannot carry out. The message is German (the MCP tools show it); the API
 * answers from the structure.
 */
export class ToolError extends Error {
  constructor(
    message: string,
    readonly reason: ToolErrorReason,
    readonly subject: Subject | null,
    /** The names to choose from: every option when not found, the matches when ambiguous. */
    readonly candidates: string[] = [],
    readonly query: string | undefined = undefined,
  ) {
    super(message);
  }
}

const LABELS: Record<Subject, string> = {
  item: 'Eintrag',
  store: 'Laden',
  category: 'Kategorie',
  list: 'Liste',
};

export type Named = { id: string; name: string };

/** An item as the MCP tools show it. */
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
  listId: string;
};

/** An item as the API shows it (docs/API.md "Resources"). */
export type ApiItem = Item & {
  categoryId: string;
  storeId: string | null;
  status: 'open' | 'ticked';
  /** ISO 8601 with Postgres' full precision, e.g. "2026-11-02T08:00:00.123456+00:00". */
  addedAt: string;
};

/** Lowercase, umlauts folded, everything but letters and digits dropped: "👶 Drogerie" ~ "drogerie". */
export function fold(text: string): string {
  return text.toLowerCase()
    .replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const sole = <T>(options: readonly T[]): T | undefined =>
  options.length === 1 ? options[0] : undefined;

/**
 * Finds one entry by id, its name in any case, or a unique folded or partial name: "kuehlregal",
 * "Kühlregal" and "kühl" all find "Kühlregal", and "aldi süd" finds "Aldi Süd" next to "Aldi Sued".
 */
export function resolve<T extends Named>(
  options: readonly T[],
  query: string,
  subject: Subject,
): T {
  const what = LABELS[subject];
  const byId = UUID.test(query) ? options.find((o) => o.id === query.toLowerCase()) : undefined;
  if (byId) return byId;
  const key = query.trim().replace(/\s+/g, ' ').toLowerCase();
  const named = options.filter((o) => o.name.trim().replace(/\s+/g, ' ').toLowerCase() === key);
  const byName = sole(named);
  if (byName) return byName;
  const q = fold(query);
  const exact = options.filter((o) => fold(o.name) === q);
  const byFolded = sole(exact);
  if (byFolded) return byFolded;
  const partial = q === '' ? [] : options.filter((o) => fold(o.name).includes(q));
  const byPart = exact.length === 0 ? sole(partial) : undefined;
  if (byPart) return byPart;
  const matches = (exact.length > 1 ? exact : partial).map((c) => c.name);
  if (matches.length > 1) {
    throw new ToolError(
      `${what} „${query}“ ist nicht eindeutig: ${matches.join(', ')}.`,
      'ambiguous',
      subject,
      matches,
      query,
    );
  }
  const names = options.map((o) => o.name);
  throw new ToolError(
    `${what} „${query}“ nicht gefunden. Vorhanden: ${names.join(', ') || '(keine)'}.`,
    'not_found',
    subject,
    names,
    query,
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

/** The household's lists in their order. */
export function lists(tx: Tx, household: string): Promise<(Named & { position: number })[]> {
  return tx`select id, name, position from public.lists
            where household_id = ${household} order by position, created_at, id`;
}

/** The caller's default list in the household (job 207): their choice, else the first list. */
async function defaultListId(tx: Tx, household: string): Promise<string | null> {
  const [row] = await tx<{ id: string | null }[]>`select public.default_list(${household}) as id`;
  return row?.id ?? null;
}

/** A list as voice names it: `seedKey` 'main' marks the list every household starts with. */
export type ListOption = Named & { seedKey: string | null };

/** The household's lists in their order and the caller's default list among them (job 207). */
export type ListCatalog = { lists: ListOption[]; defaultList: ListOption };

export async function listCatalog(tx: Tx, household: string): Promise<ListCatalog> {
  const [options, id] = await Promise.all([
    tx<ListOption[]>`select id, name, seed_key as "seedKey" from public.lists
                     where household_id = ${household} order by position, created_at, id`,
    defaultListId(tx, household),
  ]);
  const defaultList = options.find((o) => o.id === id) ?? options[0];
  // Every household has a list: none is visible only in a household the caller is not in.
  if (!defaultList) throw new ToolError('Keine Liste in diesem Haushalt.', 'not_found', 'list');
  return { lists: options, defaultList };
}

/**
 * The list [ref] names in the household (its id, or its exact name in any case), or without a
 * ref the caller's default list. A list of another household is not found.
 */
export async function listOf(tx: Tx, household: string, ref?: string | undefined): Promise<Named> {
  if (ref === undefined) {
    const { id, name } = (await listCatalog(tx, household)).defaultList;
    return { id, name };
  }
  const options = await lists(tx, household);
  const names = options.map((o) => o.name);
  const wanted = ref.trim();
  const byId = UUID.test(wanted) ? options.find((o) => o.id === wanted.toLowerCase()) : undefined;
  if (byId) return byId;
  const named = options.filter((o) => o.name.toLowerCase() === wanted.toLowerCase());
  const [only, ...more] = named;
  if (only && more.length === 0) return only;
  if (only) {
    throw new ToolError(
      `Mehrere Listen heißen „${wanted}“. Gib die id an: ` +
        named.map((l) => `${l.name} (${l.id})`).join(', '),
      'ambiguous',
      'list',
      named.map((l) => l.id),
      ref,
    );
  }
  throw new ToolError(
    `Liste „${wanted}“ nicht gefunden. Vorhanden: ${names.join(', ') || '(keine)'}.`,
    'not_found',
    'list',
    names,
    ref,
  );
}

function activeItems(
  tx: Tx,
  list: string,
): Promise<(Named & { store_id: string | null })[]> {
  return tx`select id, name, store_id from public.items
            where list_id = ${list} and status = 'active' order by created_at`;
}

/** The API item's columns over items i, categories c and stores s. */
const apiColumns = (tx: Tx) =>
  tx`i.id, i.name, i.brand, i.properties, i.quantity, c.name as category,
     c.id as "categoryId", s.name as store, s.id as "storeId",
     case i.status when 'active' then 'open' else 'ticked' end as status,
     to_json(i.created_at) #>> '{}' as "addedAt", i.list_id as "listId"`;

/** The MCP projection of an item, in the tools' key order. */
const toItem = (
  { id, name, brand, properties, quantity, category, store, listId }: ApiItem,
): Item => ({
  id,
  name,
  brand,
  properties,
  quantity,
  category,
  store,
  listId,
});

/** Items by id in any status, once each, in the database's order. */
function itemRows(tx: Tx, ids: readonly string[]): Promise<ApiItem[]> {
  return tx<ApiItem[]>`
    select ${apiColumns(tx)}
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    where i.id = any(${ids}::uuid[])`;
}

/** Items by id in any status, in the order of [ids]. */
export async function apiItemsById(tx: Tx, ids: readonly string[]): Promise<ApiItem[]> {
  const rows = await itemRows(tx, ids);
  return [...new Set(ids)].flatMap((id) => rows.filter((r) => r.id === id));
}

/** The MCP tools' rows: once each and in the database's order, as tick_items has always listed. */
async function itemsById(tx: Tx, ids: readonly string[]): Promise<Item[]> {
  return (await itemRows(tx, ids)).map(toItem);
}

const itemNotFound = (id: string) =>
  new ToolError(`Eintrag „${id}“ nicht gefunden.`, 'not_found', 'item', [], id);

/** One item of the household by id, open or ticked. */
export async function itemById(tx: Tx, household: string, id: string): Promise<ApiItem> {
  const [row] = await tx<ApiItem[]>`
    select ${apiColumns(tx)}
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    where i.id = ${id}::uuid and i.household_id = ${household}`;
  if (!row) throw itemNotFound(id);
  return row;
}

/**
 * The whole list's size, whatever the filter: open items, and items ticked in the last 24 hours
 * (the shopping trip so far); with [list] null, every list of the household. One scan of
 * items_household_status_idx.
 */
export type Counts = { open: number; checkedLast24h: number };

export async function counts(tx: Tx, household: string, list: string | null): Promise<Counts> {
  const rows = await tx<Counts[]>`
    select count(*) filter (where status = 'active')::int as "open",
           count(*) filter (where status = 'bought' and bought_at > now() - interval '24 hours')::int
             as "checkedLast24h"
    from public.items
    where household_id = ${household} and (${list}::uuid is null or list_id = ${list}::uuid)`;
  return oneRow(rows, 'counts');
}

export type Filter = {
  store?: string | undefined;
  category?: string | undefined;
  list?: string | undefined;
};

/** The store, category and list a filter names, each null when not given. */
export async function resolveFilter(
  tx: Tx,
  household: string,
  filter: Filter,
): Promise<{ store: Named | null; category: Named | null; list: Named | null }> {
  return {
    store: filter.store ? resolve(await stores(tx, household), filter.store, 'store') : null,
    category: filter.category
      ? resolve(await categories(tx, household), filter.category, 'category')
      : null,
    list: filter.list === undefined ? null : await listOf(tx, household, filter.list),
  };
}

/**
 * An open item's place in the aisle order, the key a page continues after. sortKey and addedAt
 * are text, so the comparison sees the exact float and microseconds (they go in as text:
 * postgres.js would pass a timestamptz parameter through Date, which keeps milliseconds only).
 * sortKey is the shortest decimal that reads back as the same float8, 'Infinity' for none.
 */
export type Position = {
  rank: number;
  category: string;
  sortKey: string;
  addedAt: string;
  id: string;
};

export type OpenItem = ApiItem & { position: Position };

/**
 * Open items in aisle order. A store view shows the store's own items plus untagged ones, in that
 * store's aisle order; inside a category, the household's walk order (sort_key; null as
 * 'Infinity' sorts last, like nulls, and keeps the keyset one comparable tuple). A null listId
 * shows every list. [page] continues after a position.
 */
export async function openItems(
  tx: Tx,
  household: string,
  filter: { storeId: string | null; categoryId: string | null; listId: string | null },
  page: { after: Position | null; limit: number | null } = { after: null, limit: null },
): Promise<OpenItem[]> {
  const { storeId, categoryId, listId } = filter;
  const { after, limit } = page;
  const rows = await tx<(ApiItem & { rank: number; sortKeyBits: string })[]>`
    select ${apiColumns(tx)},
           coalesce(o.sort_order, c.sort_order) as rank,
           encode(float8send(coalesce(i.sort_key, 'Infinity'::float8)), 'hex') as "sortKeyBits"
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    left join public.store_category_order o
      on o.store_id = ${storeId}::uuid and o.category_id = i.category_id
    where i.household_id = ${household} and i.status = 'active'
      and (${storeId}::uuid is null or i.store_id is null or i.store_id = ${storeId}::uuid)
      and (${categoryId}::uuid is null or i.category_id = ${categoryId}::uuid)
      and (${listId}::uuid is null or i.list_id = ${listId}::uuid)
      ${
    after
      ? tx`and (coalesce(o.sort_order, c.sort_order), c.name,
                coalesce(i.sort_key, 'Infinity'::float8), i.created_at, i.id)
             > (${after.rank}::int, ${after.category}::text, ${after.sortKey}::text::float8,
                ${after.addedAt}::text::timestamptz, ${after.id}::uuid)`
      : tx``
  }
    order by coalesce(o.sort_order, c.sort_order), c.name,
             coalesce(i.sort_key, 'Infinity'::float8), i.created_at, i.id
    ${limit === null ? tx`` : tx`limit ${limit}`}`;
  return rows.map(({ rank, sortKeyBits, ...item }) => ({
    ...item,
    position: {
      rank,
      category: item.category,
      sortKey: exactDecimal(sortKeyBits),
      addedAt: item.addedAt,
      id: item.id,
    },
  }));
}

/**
 * A float8 from its bytes in hex, as the shortest decimal that reads back as the same number.
 * Postgres' own text keeps 15 digits (extra_float_digits is 0 here), fewer than some sort keys
 * have: a page that continued after such a text began with its own last item again.
 */
function exactDecimal(hex: string): string {
  const bytes = new DataView(new ArrayBuffer(8));
  bytes.setBigUint64(0, BigInt(`0x${hex}`));
  return String(bytes.getFloat64(0));
}

/** The open items of one list, the one [filter] names or the default list. */
export async function listItems(
  tx: Tx,
  household: string,
  filter: Filter,
): Promise<
  { list: string; store: string | null; category: string | null; counts: Counts; items: Item[] }
> {
  const { store, category, list } = await resolveFilter(tx, household, filter);
  const shown = list ?? await listOf(tx, household);
  const items = await openItems(tx, household, {
    storeId: store?.id ?? null,
    categoryId: category?.id ?? null,
    listId: shown.id,
  });
  return {
    list: shown.name,
    store: store?.name ?? null,
    category: category?.name ?? null,
    counts: await counts(tx, household, shown.id),
    items: items.map(toItem),
  };
}

export type NewItem = {
  name: string;
  brand?: string | undefined;
  properties?: string | undefined;
  quantity?: string | undefined;
  category?: string | undefined;
  store?: string | undefined;
};

/** A blank optional field is not given: the parsed value stays. */
const given = (value: string | undefined) => value?.trim() || null;

/** What an add did, by item id: the new items, the ones already open, similar open ones. */
export type Added = {
  added: string[];
  existing: string[];
  similar: { added: string; onList: string[] }[];
};

/**
 * Adds items to the list [list] names (else the default list) through public.add_list_item, the shared
 * add path (also Siri's): it splits the name into
 * Bezeichnung, Marke, Eigenschaften and Menge ("Windeln Pampers Größe 3", "2 Gurken"), classifies
 * with the household's learned corrections, picks the store, and returns the existing row for an
 * item already on the list ("Gurke" is "2 Gurken"). An explicit quantity, brand, properties or
 * store replaces the parsed one. An explicit category is applied as an update, so the classifier
 * learns it like a correction in the app. A new item whose spelling variant or synonym is already
 * open ("Karotten" with "Möhren", public.similar_items) is still added and reported under
 * `similar` with the open items; nothing is merged (job 32b).
 */
export async function addItemIds(
  tx: Tx,
  household: string,
  wanted: readonly NewItem[],
  list?: string | undefined,
): Promise<Added> {
  const target = await listOf(tx, household, list);
  const [cats, shops, active] = await Promise.all([
    categories(tx, household),
    stores(tx, household),
    activeItems(tx, target.id),
  ]);
  const seen = new Set(active.map((i) => i.id));
  const added: string[] = [];
  const existing: string[] = [];
  for (const item of wanted) {
    const category = item.category ? resolve(cats, item.category, 'category').id : null;
    const store = item.store ? resolve(shops, item.store, 'store').id : null;
    const [row] = await tx<{ id: string; category_id: string }[]>`
      select id, category_id from public.add_list_item(
        ${household}, ${target.id}, ${item.name}, ${store}, ${given(item.brand)},
        ${given(item.properties)}, ${given(item.quantity)})`;
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
  return { added, existing, similar };
}

/** addItemIds for the MCP tools: the items, and the new item's name under similarOnList. */
export async function addItems(
  tx: Tx,
  household: string,
  wanted: readonly NewItem[],
  list?: string | undefined,
): Promise<{
  added: (Item | undefined)[];
  alreadyOnList: (Item | undefined)[];
  similarOnList: { added: string; onList: (Item | undefined)[] }[];
}> {
  const { added, existing, similar } = await addItemIds(tx, household, wanted, list);
  const rows = await itemsById(tx, [...added, ...existing, ...similar.flatMap((s) => s.onList)]);
  const pick = (ids: string[]) => ids.map((id) => rows.find((r) => r.id === id));
  const nameOf = (id: string) => {
    const row = rows.find((r) => r.id === id);
    if (!row) throw new Error(`added item ${id} not read back`);
    return row.name;
  };
  return {
    added: pick(added),
    alreadyOnList: pick(existing),
    similarOnList: similar.map((s) => ({ added: nameOf(s.added), onList: pick(s.onList) })),
  };
}

/**
 * The open item [ref] names. With a [list] named, by name or id on that list. Without one, an id
 * finds the item on any list of the household (ids come from list_items of any list), a name only
 * on the default list.
 */
async function openItem(
  tx: Tx,
  household: string,
  ref: string,
  list: string | undefined,
  active: readonly (Named & { store_id: string | null })[],
): Promise<Named & { store_id: string | null }> {
  const id = ref.trim();
  if (list === undefined && UUID.test(id)) {
    const [anywhere] = await tx<(Named & { store_id: string | null })[]>`
      select id, name, store_id from public.items
      where id = ${id.toLowerCase()}::uuid and household_id = ${household} and status = 'active'`;
    if (anywhere) return anywhere;
  }
  return resolve(active, ref, 'item');
}

/**
 * Ticks open items by name or id: on the list [list] names, else names on the default list and ids
 * on any list of the household.
 */
export async function tickItems(
  tx: Tx,
  household: string,
  refs: readonly string[],
  list?: string | undefined,
): Promise<{ ticked: Item[]; notFound: { item: string; reason: string }[] }> {
  const active = await activeItems(tx, (await listOf(tx, household, list)).id);
  const ids: string[] = [];
  const notFound: { item: string; reason: string }[] = [];
  for (const ref of refs) {
    try {
      ids.push((await openItem(tx, household, ref, list, active)).id);
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
 * Ticks (bought) or unticks (active) one item of the household by id. An item that already has
 * the status is left alone, so repeating the call changes nothing.
 */
export async function setItemStatus(
  tx: Tx,
  household: string,
  id: string,
  status: 'active' | 'bought',
): Promise<ApiItem> {
  await tx`update public.items set status = ${status}
           where id = ${id}::uuid and household_id = ${household} and status <> ${status}`;
  return await itemById(tx, household, id);
}

export type Move = { category?: string | undefined; store?: string | null | undefined };

const nothingToMove = () =>
  new ToolError('Gib eine Kategorie oder einen Laden an.', 'invalid', null);

/**
 * Changes category and/or store through public.move_item: the item goes to the end of its new
 * group, and the triggers learn both. A store left out stays; null untags.
 */
async function moveOpen(
  tx: Tx,
  household: string,
  item: { id: string; store_id: string | null },
  move: Move,
): Promise<void> {
  const category = move.category === undefined
    ? null
    : resolve(await categories(tx, household), move.category, 'category').id;
  const store = move.store === undefined
    ? item.store_id
    : move.store === null || move.store.trim() === ''
    ? null
    : resolve(await stores(tx, household), move.store, 'store').id;
  await tx`select from public.move_item(${item.id}, ${store}, ${category})`;
}

/**
 * Moves an open item by name or id (the MCP tool): on the list [move.list] names, else a name on
 * the default list and an id on any list of the household.
 */
export async function moveItem(
  tx: Tx,
  household: string,
  move: Move & { item: string; list?: string | undefined },
): Promise<Item> {
  if (move.category === undefined && move.store === undefined) throw nothingToMove();
  const item = await openItem(
    tx,
    household,
    move.item,
    move.list,
    await activeItems(tx, (await listOf(tx, household, move.list)).id),
  );
  await moveOpen(tx, household, item, move);
  return oneRow(await itemsById(tx, [item.id]), 'moved item');
}

/** Moves an open item by id (the API); a ticked or unknown one is not found. */
export async function moveItemById(
  tx: Tx,
  household: string,
  id: string,
  move: Move,
): Promise<ApiItem> {
  if (move.category === undefined && move.store === undefined) throw nothingToMove();
  const [item] = await tx<{ id: string; store_id: string | null }[]>`
    select id, store_id from public.items
    where id = ${id}::uuid and household_id = ${household} and status = 'active'`;
  if (!item) throw itemNotFound(id);
  await moveOpen(tx, household, item, move);
  return await itemById(tx, household, id);
}
