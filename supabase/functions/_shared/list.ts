// The shopping-list operations behind the MCP tools and the API. Every function runs as the
// signed-in user (asUser), so RLS confines it to the caller's households; the household_id filters
// keep it to the one the key or session acts for (a user can be in several, job 169b), and narrow
// the query plan. A household has one or more lists (job 169b W3): the tools act in
// the list a `list` reference names, else in the caller's default list there (job 207,
// public.default_list: their choice, else the first list), where Siri and Alexa act too.
import { oneRow, OutOfTime, type Tx } from './db.ts';

/**
 * Why a request failed. `conflict`: a write that clashes with the list's state, such as a rename
 * onto an open twin. `limit`: the household has as many lists or stores as it may.
 * `anchor_in_other_store`: a place next to an item of another store section (learned households).
 * `order_mode`: a store order in a household that sorts by categories. `not_in_store`: items a
 * store order lists that are no open items of that store (candidates).
 */
export type ToolErrorReason =
  | 'not_found'
  | 'ambiguous'
  | 'invalid'
  | 'conflict'
  | 'limit'
  | 'anchor_in_other_store'
  | 'order_mode'
  | 'not_in_store';

/** What a name or id was meant to find; `anchor` is the item a place is next to. */
export type Subject = 'item' | 'anchor' | 'store' | 'category' | 'list';

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
  anchor: 'Eintrag',
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
  /**
   * 1-based rank among the open items of its list in its store section (or "No store"), in the
   * household's order; null for a ticked item.
   */
  position: number | null;
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
  throw notFound(subject, query, options.map((o) => o.name));
}

/** No [subject] answers [query]; [names] are the ones there are. */
function notFound(subject: Subject, query: string, names: string[]): ToolError {
  return new ToolError(
    `${LABELS[subject]} „${query}“ nicht gefunden. Vorhanden: ${names.join(', ') || '(keine)'}.`,
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

/** How a household orders its list (job 352): by category, or by places learned per store. */
export type OrderMode = 'categories' | 'learned';

export async function orderMode(tx: Tx, household: string): Promise<OrderMode> {
  const rows = await tx<{ mode: OrderMode }[]>`
    select order_mode as mode from public.households where id = ${household}`;
  return oneRow(rows, 'orderMode').mode;
}

/**
 * An open item's place inside its store section, over items i, categories c, households h and
 * the item's own store's category order os: in a categories household that store's category walk
 * order, then the walk order inside the category (sort_key; null as 'Infinity' sorts last and
 * keeps the keyset one comparable tuple); in a learned household sort_key alone, which is then
 * the item's place in its store.
 */
const inSection = (tx: Tx) =>
  tx`case when h.order_mode = 'learned' then 0 else coalesce(os.sort_order, c.sort_order) end,
     case when h.order_mode = 'learned' then '' else c.name end,
     coalesce(i.sort_key, 'Infinity'::float8), i.created_at, i.id`;

/** The joins inSection reads, besides categories c. */
const sectionJoins = (tx: Tx) =>
  tx`join public.households h on h.id = i.household_id
     left join public.store_category_order os
       on os.store_id = i.store_id and os.category_id = i.category_id`;

/** Every open item's position in the household: its rank in its list's store section. */
const positions = (tx: Tx, household: string) =>
  tx`select i.id,
            row_number() over (partition by i.list_id, i.store_id order by ${inSection(tx)})::int
              as position
     from public.items i
     join public.categories c on c.id = i.category_id
     ${sectionJoins(tx)}
     where i.household_id = ${household} and i.status = 'active'`;

/** Items i with their categories c, stores s and positions p. */
const itemsFrom = (tx: Tx, household: string) =>
  tx`public.items i
     join public.categories c on c.id = i.category_id
     left join public.stores s on s.id = i.store_id
     left join (${positions(tx, household)}) p on p.id = i.id`;

/** The API item's columns over itemsFrom. */
const apiColumns = (tx: Tx) =>
  tx`i.id, i.name, i.brand, i.properties, i.quantity, c.name as category,
     c.id as "categoryId", s.name as store, s.id as "storeId", p.position,
     case i.status when 'active' then 'open' else 'ticked' end as status,
     to_json(i.created_at) #>> '{}' as "addedAt", i.list_id as "listId"`;

/** The MCP projection of an item, in the tools' key order. */
const toItem = (
  { id, name, brand, properties, quantity, category, store, position, listId }: ApiItem,
): Item => ({
  id,
  name,
  brand,
  properties,
  quantity,
  category,
  store,
  position,
  listId,
});

/** Items of the household by id in any status, once each, in the database's order. */
function itemRows(tx: Tx, household: string, ids: readonly string[]): Promise<ApiItem[]> {
  return tx<ApiItem[]>`
    select ${apiColumns(tx)}
    from ${itemsFrom(tx, household)}
    where i.id = any(${ids}::uuid[]) and i.household_id = ${household}`;
}

/** Items of the household by id in any status, in the order of [ids]. */
export async function apiItemsById(
  tx: Tx,
  household: string,
  ids: readonly string[],
): Promise<ApiItem[]> {
  const rows = await itemRows(tx, household, ids);
  return [...new Set(ids)].flatMap((id) => rows.filter((r) => r.id === id));
}

/** The MCP tools' rows: once each and in the database's order, as tick_items has always listed. */
async function itemsById(tx: Tx, household: string, ids: readonly string[]): Promise<Item[]> {
  return (await itemRows(tx, household, ids)).map(toItem);
}

const itemNotFound = (id: string) =>
  new ToolError(`Eintrag „${id}“ nicht gefunden.`, 'not_found', 'item', [], id);

/** One item of the household by id, open or ticked; with [list], only on that list. */
async function itemRow(
  tx: Tx,
  household: string,
  id: string,
  list: string | null = null,
): Promise<ApiItem | undefined> {
  const [row] = await tx<ApiItem[]>`
    select ${apiColumns(tx)}
    from ${itemsFrom(tx, household)}
    where i.id = ${id}::uuid and i.household_id = ${household}
      and (${list}::uuid is null or i.list_id = ${list}::uuid)`;
  return row;
}

/** One item of the household by id, open or ticked. */
export async function itemById(tx: Tx, household: string, id: string): Promise<ApiItem> {
  const row = await itemRow(tx, household, id);
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
export type AisleKey = {
  rank: number;
  category: string;
  sortKey: string;
  addedAt: string;
  id: string;
};

/** The store id of "No store" in a WalkKey, which sorts after every store. */
export const NO_STORE = '00000000-0000-0000-0000-000000000000';

/**
 * An open item's place in the walk order: its store section (stores in their order, "No store"
 * last), then its place inside the section (inSection; rank and category are 0 and '' in a
 * learned household).
 */
export type WalkKey = {
  noStore: boolean;
  storeRank: number;
  storeName: string;
  storeId: string;
  rank: number;
  category: string;
  sortKey: string;
  addedAt: string;
  id: string;
};

export type Keyed<K> = ApiItem & { key: K };

export type ItemFilter = {
  storeId: string | null;
  categoryId: string | null;
  listId: string | null;
};

export type Page<K> = { after: K | null; limit: number | null };

/**
 * The open items a filter shows: a store view shows the store's own items plus untagged ones; a
 * null listId shows every list.
 */
const shown = (tx: Tx, household: string, { storeId, categoryId, listId }: ItemFilter) =>
  tx`i.household_id = ${household} and i.status = 'active'
     and (${storeId}::uuid is null or i.store_id is null or i.store_id = ${storeId}::uuid)
     and (${categoryId}::uuid is null or i.category_id = ${categoryId}::uuid)
     and (${listId}::uuid is null or i.list_id = ${listId}::uuid)`;

/**
 * Open items in aisle order (the API's v1 default): categories in the walking order of the
 * filtered store (else the household's), inside a category the walk order. [page] continues after
 * a key.
 */
export async function openItems(
  tx: Tx,
  household: string,
  filter: ItemFilter,
  page: Page<AisleKey> = { after: null, limit: null },
): Promise<Keyed<AisleKey>[]> {
  const { after, limit } = page;
  const rows = await tx<(ApiItem & { rank: number; sortKeyBits: string })[]>`
    select ${apiColumns(tx)},
           coalesce(o.sort_order, c.sort_order) as rank,
           encode(float8send(coalesce(i.sort_key, 'Infinity'::float8)), 'hex') as "sortKeyBits"
    from ${itemsFrom(tx, household)}
    left join public.store_category_order o
      on o.store_id = ${filter.storeId}::uuid and o.category_id = i.category_id
    where ${shown(tx, household, filter)}
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
    key: {
      rank,
      category: item.category,
      sortKey: exactDecimal(sortKeyBits),
      addedAt: item.addedAt,
      id: item.id,
    },
  }));
}

/** Open items in walk order: store by store in the stores' order, "No store" last (WalkKey). */
export async function openItemsInWalk(
  tx: Tx,
  household: string,
  filter: ItemFilter,
  page: Page<WalkKey> = { after: null, limit: null },
): Promise<Keyed<WalkKey>[]> {
  const { after, limit } = page;
  const walk = tx`s.id is null, coalesce(s.sort_order, 0), coalesce(s.name, ''),
                  coalesce(s.id, ${NO_STORE}::uuid), ${inSection(tx)}`;
  const rows = await tx<
    (
      & ApiItem
      & { storeRank: number; rank: number; sectionCategory: string; sortKeyBits: string }
    )[]
  >`
    select ${apiColumns(tx)}, coalesce(s.sort_order, 0) as "storeRank",
           case when h.order_mode = 'learned' then 0 else coalesce(os.sort_order, c.sort_order) end
             as rank,
           case when h.order_mode = 'learned' then '' else c.name end as "sectionCategory",
           encode(float8send(coalesce(i.sort_key, 'Infinity'::float8)), 'hex') as "sortKeyBits"
    from ${itemsFrom(tx, household)}
    ${sectionJoins(tx)}
    where ${shown(tx, household, filter)}
      ${
    after
      ? tx`and (${walk}) > (${after.noStore}::boolean, ${after.storeRank}::int,
                ${after.storeName}::text, ${after.storeId}::uuid, ${after.rank}::int,
                ${after.category}::text, ${after.sortKey}::text::float8,
                ${after.addedAt}::text::timestamptz, ${after.id}::uuid)`
      : tx``
  }
    order by ${walk}
    ${limit === null ? tx`` : tx`limit ${limit}`}`;
  return rows.map(
    ({ storeRank, rank, sectionCategory, sortKeyBits, ...item }) => ({
      ...item,
      key: {
        noStore: item.storeId === null,
        storeRank,
        storeName: item.store ?? '',
        storeId: item.storeId ?? NO_STORE,
        rank,
        category: sectionCategory,
        sortKey: exactDecimal(sortKeyBits),
        addedAt: item.addedAt,
        id: item.id,
      },
    }),
  );
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

/**
 * The open items of one list, the one [filter] names or the default list: in a learned
 * household in walk order (`order` "walk"), else in aisle order as before (`order` "aisle").
 */
export async function listItems(
  tx: Tx,
  household: string,
  filter: Filter,
): Promise<
  {
    list: string;
    order: 'walk' | 'aisle';
    store: string | null;
    category: string | null;
    counts: Counts;
    items: Item[];
  }
> {
  const { store, category, list } = await resolveFilter(tx, household, filter);
  const target = list ?? await listOf(tx, household);
  const ids = { storeId: store?.id ?? null, categoryId: category?.id ?? null, listId: target.id };
  const walk = await orderMode(tx, household) === 'learned';
  const items = walk
    ? await openItemsInWalk(tx, household, ids)
    : await openItems(tx, household, ids);
  return {
    list: target.name,
    order: walk ? 'walk' : 'aisle',
    store: store?.name ?? null,
    category: category?.name ?? null,
    counts: await counts(tx, household, target.id),
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

/** Similar open items an add names per new item. */
export const SIMILAR_SHOWN = 3;

/** How long the adds of one request may take together. */
export const ADD_BUDGET_MS = 5000;

/**
 * What an add did, by item id: the new items, the ones already open, and per new item the first
 * SIMILAR_SHOWN similar open ones, with how many there are in `total`.
 */
export type Added = {
  added: string[];
  existing: string[];
  similar: { added: string; onList: string[]; total: number }[];
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
 * `similar` with the oldest of the open items; nothing is merged (job 32b). Past [until] (on
 * performance.now()'s clock) it throws OutOfTime instead of starting the next step.
 */
export async function addItemIds(
  tx: Tx,
  household: string,
  wanted: readonly NewItem[],
  list?: string | undefined,
  until: number = performance.now() + ADD_BUDGET_MS,
): Promise<Added> {
  const inTime = () => {
    if (performance.now() > until) throw new OutOfTime();
  };
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
    inTime();
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
  inTime();
  const near = await tx<{ added: string; id: string; total: number }[]>`
    select a.id as added, s.id, s.total
    from unnest(${added}::uuid[]) with ordinality as a (id, position)
    cross join lateral (
      select o.id, count(*) over ()::int as total,
             row_number() over (order by o.created_at, o.id) as rank
      from public.similar_items(a.id) o
    ) s
    where s.rank <= ${SIMILAR_SHOWN}
    order by a.position, s.rank`;
  const similar = new Map<string, { added: string; onList: string[]; total: number }>();
  for (const row of near) {
    const entry = similar.get(row.added) ?? { added: row.added, onList: [], total: row.total };
    entry.onList.push(row.id);
    similar.set(row.added, entry);
  }
  return { added, existing, similar: [...similar.values()] };
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
  similarOnList: { added: string; onList: (Item | undefined)[]; total: number }[];
}> {
  const { added, existing, similar } = await addItemIds(tx, household, wanted, list);
  const rows = await itemsById(tx, household, [
    ...added,
    ...existing,
    ...similar.flatMap((s) => s.onList),
  ]);
  const byId = new Map(rows.map((r) => [r.id, r]));
  const pick = (ids: string[]) => ids.map((id) => byId.get(id));
  const nameOf = (id: string) => {
    const row = byId.get(id);
    if (!row) throw new Error(`added item ${id} not read back`);
    return row.name;
  };
  return {
    added: pick(added),
    alreadyOnList: pick(existing),
    similarOnList: similar.map((s) => ({
      added: nameOf(s.added),
      onList: pick(s.onList),
      total: s.total,
    })),
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

type NotFound = { item: string; reason: string };

/**
 * The open items [refs] name, like tick_items finds them: on the list [list] names, else names on
 * the default list and ids on any list of the household. A ref that finds none is in notFound.
 */
async function openIds(
  tx: Tx,
  household: string,
  refs: readonly string[],
  list: string | undefined,
): Promise<{ ids: string[]; notFound: NotFound[] }> {
  const active = await activeItems(tx, (await listOf(tx, household, list)).id);
  const ids: string[] = [];
  const notFound: NotFound[] = [];
  for (const ref of refs) {
    try {
      ids.push((await openItem(tx, household, ref, list, active)).id);
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      notFound.push({ item: ref, reason: e.message });
    }
  }
  return { ids, notFound };
}

/**
 * Marks the transaction's ticks and unticks as an agent's (item_events.source): only the app's
 * own ticks teach the walk order and make trips (job 352, T5a).
 */
async function markAgentTicks(tx: Tx): Promise<void> {
  await tx`select set_config('fg.tick_source', 'agent', true)`;
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
): Promise<{ ticked: Item[]; notFound: NotFound[] }> {
  const { ids, notFound } = await openIds(tx, household, refs, list);
  if (ids.length > 0) {
    await markAgentTicks(tx);
    await tx`update public.items set status = 'bought'
             where id = any(${ids}::uuid[]) and household_id = ${household}`;
  }
  return { ticked: await itemsById(tx, household, ids), notFound };
}

/**
 * Deletes open items found like tickItems finds them, the app's plain delete: the household keeps
 * what it learned from them (only the app's undo of an add forgets). Answers the rows as they were.
 */
export async function removeItems(
  tx: Tx,
  household: string,
  refs: readonly string[],
  list?: string | undefined,
): Promise<{ removed: Item[]; notFound: NotFound[] }> {
  const { ids, notFound } = await openIds(tx, household, refs, list);
  const removed = await itemsById(tx, household, ids);
  if (ids.length > 0) {
    await tx`delete from public.items where id = any(${ids}::uuid[]) and household_id = ${household}`;
  }
  return { removed, notFound };
}

/** How many ticked names untickItems resolves a name among: the most recently ticked. */
const UNTICK_NAMES = 50;

/**
 * Unticks ticked items. An id finds one on the list [list] names, without [list] on any list of
 * the household. A name finds the most recently ticked row of that name on the list [list] names,
 * else on the default list, unless the item is open there already: a repeat changes nothing.
 */
export async function untickItems(
  tx: Tx,
  household: string,
  refs: readonly string[],
  list?: string | undefined,
): Promise<{ unticked: Item[]; notFound: NotFound[] }> {
  const shown = await listOf(tx, household, list);
  const ticked = await tx<Named[]>`
    select id, name from (
      select distinct on (lower(name)) id, name, bought_at, created_at from public.items
      where household_id = ${household} and list_id = ${shown.id} and status = 'bought'
      order by lower(name), bought_at desc nulls last, created_at desc
    ) latest
    order by bought_at desc nulls last, created_at desc
    limit ${UNTICK_NAMES}`;
  const ids: string[] = [];
  const notFound: NotFound[] = [];
  for (const ref of refs) {
    const id = ref.trim().toLowerCase();
    if (UUID.test(id)) {
      const [row] = await tx<{ status: string }[]>`
        select status from public.items
        where id = ${id}::uuid and household_id = ${household}
          and (${list === undefined}::boolean or list_id = ${shown.id}::uuid)`;
      if (row?.status === 'bought') {
        ids.push(id);
        continue;
      }
      if (row) {
        notFound.push({ item: ref, reason: `Eintrag „${ref}“ ist nicht abgehakt.` });
        continue;
      }
    }
    try {
      const row = resolve(ticked, ref, 'item');
      // A repeat would otherwise bring back an older ticked twin: every purchase leaves one.
      const [open] = await tx<Named[]>`
        select o.id, o.name from public.items o, public.items t
        where t.id = ${row.id} and o.household_id = ${household} and o.list_id = t.list_id
          and o.status = 'active' and o.id <> t.id
          and public.open_item_key(o.name, o.brand, o.properties) =
            public.open_item_key(t.name, t.brand, t.properties)
        limit 1`;
      if (open) {
        notFound.push({ item: ref, reason: `„${open.name}“ steht schon offen auf der Liste.` });
        continue;
      }
      ids.push(row.id);
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      notFound.push({ item: ref, reason: e.message });
    }
  }
  if (ids.length > 0) {
    await markAgentTicks(tx);
    await tx`update public.items set status = 'active'
             where id = any(${ids}::uuid[]) and household_id = ${household} and status = 'bought'`;
  }
  return { unticked: await itemsById(tx, household, ids), notFound };
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
  await markAgentTicks(tx);
  await tx`update public.items set status = ${status}
           where id = ${id}::uuid and household_id = ${household} and status <> ${status}`;
  return await itemById(tx, household, id);
}

/**
 * One item with its status: an id finds it open or ticked on the list [list] names, without
 * [list] on any list of the household; a name finds an open item on that list or the default list.
 */
export async function getItem(
  tx: Tx,
  household: string,
  ref: string,
  list?: string | undefined,
): Promise<Item & { status: 'open' | 'ticked'; addedAt: string }> {
  const shown = await listOf(tx, household, list);
  const id = ref.trim().toLowerCase();
  const byId = UUID.test(id)
    ? await itemRow(tx, household, id, list === undefined ? null : shown.id)
    : undefined;
  const row = byId ??
    await itemById(tx, household, resolve(await activeItems(tx, shown.id), ref, 'item').id);
  return { ...toItem(row), status: row.status, addedAt: row.addedAt };
}

export type Move = { category?: string | undefined; store?: string | null | undefined };

/**
 * A change to an open item, the app's edit, move and move to another list in one: the text
 * fields given (null or blank clears quantity, brand and properties), the list a `list`
 * reference names, and category and store as Move.
 */
export type ItemEdit = Move & {
  name?: string | undefined;
  quantity?: string | null | undefined;
  brand?: string | null | undefined;
  properties?: string | null | undefined;
  list?: string | undefined;
};

const cleared = (value: string | null) => value?.trim() || null;

/**
 * Changes category and/or store through public.move_item, and the triggers learn both: in a
 * categories household the item goes to the end of its new group; in a learned one a new store
 * gives it its place in that store's order, a new category alone keeps its place. A store left
 * out stays; null untags.
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
 * Edits an open item with the writes the app makes, so the triggers learn and guard alike: an
 * update of the given text columns, one of list_id, then public.move_item. A rename or move that
 * gives it the key of another open item on its list is a conflict (items_rename_duplicate).
 */
async function editOpen(
  tx: Tx,
  household: string,
  item: Named & { store_id: string | null },
  edit: ItemEdit,
): Promise<void> {
  const columns: Record<string, string | null> = {};
  if (edit.name !== undefined) columns.name = edit.name.trim();
  if (edit.quantity !== undefined) columns.quantity = cleared(edit.quantity);
  if (edit.brand !== undefined) columns.brand = cleared(edit.brand);
  if (edit.properties !== undefined) columns.properties = cleared(edit.properties);
  const moves = edit.category !== undefined || edit.store !== undefined;
  if (Object.keys(columns).length === 0 && edit.list === undefined && !moves) {
    throw new ToolError('Gib an, was sich ändern soll.', 'invalid', null);
  }
  const name = columns.name ?? item.name;
  try {
    if (Object.keys(columns).length > 0) {
      await tx`update public.items set ${tx(columns)}
               where id = ${item.id} and household_id = ${household}`;
    }
    if (edit.list !== undefined) {
      const target = await listOf(tx, household, edit.list);
      await tx`update public.items set list_id = ${target.id}
               where id = ${item.id} and household_id = ${household} and list_id <> ${target.id}`;
    }
  } catch (e) {
    const { name: kind, code, message } = (e ?? {}) as Record<string, unknown>;
    if (kind === 'PostgresError' && code === '23505' && message === 'already_on_list') {
      throw new ToolError(
        `„${name}“ steht schon offen auf der Liste.`,
        'conflict',
        'item',
        [],
        name,
      );
    }
    throw e;
  }
  if (moves) await moveOpen(tx, household, item, edit);
}

/**
 * Edits an open item by name or id (the MCP tools): found on the list [at.list] names, else a name
 * on the default list and an id on any list of the household. [edit.list] is where it moves.
 */
export async function updateItem(
  tx: Tx,
  household: string,
  at: { item: string; list?: string | undefined },
  edit: ItemEdit,
): Promise<Item> {
  const item = await openItem(
    tx,
    household,
    at.item,
    at.list,
    await activeItems(tx, (await listOf(tx, household, at.list)).id),
  );
  await editOpen(tx, household, item, edit);
  return oneRow(await itemsById(tx, household, [item.id]), 'edited item');
}

/** Edits an open item by id (the API); a ticked or unknown one is not found. */
export async function updateItemById(
  tx: Tx,
  household: string,
  id: string,
  edit: ItemEdit,
): Promise<ApiItem> {
  const [item] = await tx<(Named & { store_id: string | null })[]>`
    select id, name, store_id from public.items
    where id = ${id}::uuid and household_id = ${household} and status = 'active'`;
  if (!item) throw itemNotFound(id);
  await editOpen(tx, household, item, edit);
  return await itemById(tx, household, id);
}

export type Edge = 'before' | 'after';

/** The anchor and edge of a place given as `before` or `after`; null unless exactly one is. */
export function anchorOf(
  given: { before?: string | undefined; after?: string | undefined },
): { anchor: string; edge: Edge } | null {
  const { before, after } = given;
  if (before !== undefined && after === undefined) return { anchor: before, edge: 'before' };
  if (after !== undefined && before === undefined) return { anchor: after, edge: 'after' };
  return null;
}

/** Items per store order (MCP set_store_order, PUT /v1/stores/{id}/order). */
export const STORE_ORDER_MAX = 200;

const orderModeRefusal = () =>
  new ToolError(
    'Dieser Haushalt sortiert nach Kategorien, nicht nach einer eigenen Reihenfolge pro Laden. ' +
      'Einzelne Einträge setzt place_item.',
    'order_mode',
    null,
  );

const anchorNotFound = (anchor: string) =>
  new ToolError(`Eintrag „${anchor}“ nicht gefunden.`, 'not_found', 'anchor', [], anchor);

/**
 * public.place_item's refusals as ToolErrors; anything else as it is. Item and anchor were open
 * when this request read them: `invalid_anchor` and `item_not_found` mean a tick or a delete came
 * in between.
 */
function placeRefusal(e: unknown, item: Named, anchor: Named): unknown {
  switch (raised(e)) {
    case 'anchor_in_other_store':
      return new ToolError(
        `„${anchor.name}“ steht in einem anderen Laden als „${item.name}“. Ein Eintrag kommt nur ` +
          'neben einen Eintrag desselben Ladens; den Laden ändert move_item.',
        'anchor_in_other_store',
        'anchor',
        [],
        anchor.name,
      );
    case 'order_mode':
      return orderModeRefusal();
    case 'invalid_anchor':
      return anchorNotFound(anchor.name);
    case 'item_not_found':
      return new ToolError(
        `„${item.name}“ oder „${anchor.name}“ gibt es nicht mehr.`,
        'not_found',
        'item',
        [],
        item.id,
      );
    default:
      return e;
  }
}

/**
 * Puts the open [item] right before or after the open [anchor] through public.place_item. In a
 * learned household that is a manual place in the store's order, and the anchor must be in the
 * same store section; in a categories household the item takes the anchor's store and category,
 * as a drag in the app does. Placing again next to the same anchor changes nothing.
 */
async function place(tx: Tx, item: Named, anchor: Named, edge: Edge): Promise<void> {
  if (item.id === anchor.id) {
    throw new ToolError(
      `„${item.name}“ kann nicht neben sich selbst stehen.`,
      'invalid',
      'anchor',
      [],
      anchor.name,
    );
  }
  try {
    await tx`select from public.place_item(${item.id}, ${anchor.id}, ${edge})`;
  } catch (e) {
    throw placeRefusal(e, item, anchor);
  }
}

/**
 * Places an open item by name or id next to another (the MCP tool): both on the list
 * [placing.list] names, else names on the default list and ids on any list of the household.
 */
export async function placeItem(
  tx: Tx,
  household: string,
  placing: { item: string; anchor: string; edge: Edge; list?: string | undefined },
): Promise<Item> {
  const active = await activeItems(tx, (await listOf(tx, household, placing.list)).id);
  const item = await openItem(tx, household, placing.item, placing.list, active);
  const anchor = await openItem(tx, household, placing.anchor, placing.list, active);
  await place(tx, item, anchor, placing.edge);
  return oneRow(await itemsById(tx, household, [item.id]), 'placed item');
}

/** An open item of the household by id, or null. */
async function openById(
  tx: Tx,
  household: string,
  id: string,
): Promise<(Named & { store_id: string | null }) | null> {
  const [row] = await tx<(Named & { store_id: string | null })[]>`
    select id, name, store_id from public.items
    where id = ${id}::uuid and household_id = ${household} and status = 'active'`;
  return row ?? null;
}

/** Places an open item by id next to the open [anchor] (the API). */
export async function placeItemById(
  tx: Tx,
  household: string,
  id: string,
  anchorId: string,
  edge: Edge,
): Promise<ApiItem> {
  const item = await openById(tx, household, id);
  if (!item) throw itemNotFound(id);
  const anchor = await openById(tx, household, anchorId);
  if (!anchor) throw anchorNotFound(anchorId);
  await place(tx, item, anchor, edge);
  return await itemById(tx, household, id);
}

/** The names of [items] that are no open items of [store]; null when all are. */
async function notInStore(
  tx: Tx,
  household: string,
  store: Named,
  items: readonly Named[],
): Promise<ToolError | null> {
  const inStore = new Set(
    (await tx<{ id: string }[]>`
      select id from public.items
      where id = any(${items.map((i) => i.id)}::uuid[]) and household_id = ${household}
        and status = 'active' and store_id = ${store.id}`).map((r) => r.id),
  );
  const outside = [...new Set(items.filter((i) => !inStore.has(i.id)).map((i) => i.name))];
  return outside.length === 0 ? null : new ToolError(
    `Nicht offen im Laden „${store.name}“: ${outside.join(', ')}.`,
    'not_in_store',
    'item',
    outside,
  );
}

/**
 * Sets the order of a store's open items through public.set_store_order (learned households
 * only): [ids] first in their order, as manual places; the store's other open items keep their
 * order after them. Every id must be an open item of that store. Returns the store's open items
 * in their new order; null when the store was deleted meanwhile.
 */
async function orderStore(
  tx: Tx,
  household: string,
  store: Named,
  items: readonly Named[],
): Promise<ApiItem[] | null> {
  if (await orderMode(tx, household) !== 'learned') throw orderModeRefusal();
  const outside = await notInStore(tx, household, store, items);
  if (outside) throw outside;
  const ids = [...new Set(items.map((i) => i.id))];
  try {
    // A savepoint, so that a refusal leaves the transaction open to name the items it was about.
    await tx.savepoint((sp) =>
      sp`select from public.set_store_order(${household}, ${store.id}, ${ids}::uuid[])`
    );
  } catch (e) {
    switch (raised(e)) {
      case 'order_mode':
        throw orderModeRefusal();
      case 'store_not_found':
        return null;
      case 'invalid_items':
        // An item was ticked, moved or deleted since the check above.
        throw await notInStore(tx, household, store, items) ?? e;
      default:
        throw e;
    }
  }
  const walk = await openItemsInWalk(tx, household, {
    storeId: store.id,
    categoryId: null,
    listId: null,
  });
  return walk.filter((i) => i.storeId === store.id).map(({ key: _, ...item }) => item);
}

/**
 * Sets a store's order by names or ids (the MCP tool): names on the list [order.list] names, else
 * on the default list; ids on any list of the household.
 */
export async function setStoreOrder(
  tx: Tx,
  household: string,
  order: { store: string; items: readonly string[]; list?: string | undefined },
): Promise<{ store: string; items: Item[] }> {
  const store = resolve(await stores(tx, household), order.store, 'store');
  const active = await activeItems(tx, (await listOf(tx, household, order.list)).id);
  const items: Named[] = [];
  for (const ref of order.items) items.push(await openItem(tx, household, ref, order.list, active));
  const ordered = await orderStore(tx, household, store, items);
  if (!ordered) {
    throw notFound(
      'store',
      order.store,
      (await stores(tx, household)).map((s) => s.name),
    );
  }
  return { store: store.name, items: ordered.map(toItem) };
}

/** Sets a store's order by ids (the API); null when the household has no such store. */
export async function setStoreOrderById(
  tx: Tx,
  household: string,
  storeId: string,
  ids: readonly string[],
): Promise<ApiItem[] | null> {
  const store = (await stores(tx, household)).find((s) => s.id === storeId);
  if (!store) return null;
  return await orderStore(tx, household, store, ids.map((id) => ({ id, name: id })));
}

/** Deletes an item of the household by id, open or ticked, like the app; answers it as it was. */
export async function deleteItemById(tx: Tx, household: string, id: string): Promise<ApiItem> {
  const item = await itemById(tx, household, id);
  await tx`delete from public.items where id = ${id}::uuid and household_id = ${household}`;
  return item;
}

/**
 * Folds the open item [merge] names into the one [keep] names through public.merge_items, the
 * app's "Zusammenführen": kept keeps its name, the quantities add up ("2" and "3" make "5"), a
 * missing brand or properties come from the other, which is deleted. Both are found like tickItems
 * finds them, and must be on the same list. Answers kept as it is now and merged as it was.
 */
export async function mergeItems(
  tx: Tx,
  household: string,
  refs: { keep: string; merge: string; list?: string | undefined },
): Promise<{ kept: Item; merged: Item }> {
  const active = await activeItems(tx, (await listOf(tx, household, refs.list)).id);
  const keep = await openItem(tx, household, refs.keep, refs.list, active);
  const other = await openItem(tx, household, refs.merge, refs.list, active);
  if (keep.id === other.id) {
    throw new ToolError(
      `„${refs.keep}“ und „${refs.merge}“ sind derselbe Eintrag.`,
      'invalid',
      'item',
    );
  }
  const rows = await itemsById(tx, household, [keep.id, other.id]);
  const kept = oneRow(rows.filter((r) => r.id === keep.id), 'item to keep');
  const merged = oneRow(rows.filter((r) => r.id === other.id), 'item to merge');
  // The app merges only rows of the list it shows; ids alone could reach two lists.
  if (kept.listId !== merged.listId) {
    throw new ToolError(
      `„${refs.keep}“ und „${refs.merge}“ stehen auf verschiedenen Listen. Zusammengeführt wird ` +
        'nur auf einer Liste.',
      'invalid',
      'item',
    );
  }
  try {
    await tx`select public.merge_items(gen_random_uuid(), ${keep.id}::uuid, ${other.id}::uuid)`;
  } catch (e) {
    const { name, code } = (e ?? {}) as Record<string, unknown>;
    if (name === 'PostgresError' && code === '22001') {
      throw new ToolError(
        'Die zusammengeführte Menge wäre zu lang (höchstens 40 Zeichen).',
        'invalid',
        'item',
      );
    }
    // Ticked or deleted by someone else since they were found.
    if (name === 'PostgresError' && (code === 'P0002' || code === '22023')) {
      throw new ToolError(
        `„${refs.keep}“ oder „${refs.merge}“ ist nicht mehr offen.`,
        'not_found',
        'item',
      );
    }
    throw e;
  }
  return { kept: oneRow(await itemsById(tx, household, [keep.id]), 'kept item'), merged };
}

/** The message of a Postgres error (the exception's name in our functions), else undefined. */
const raised = (e: unknown): unknown =>
  (e as { name?: unknown } | null)?.name === 'PostgresError'
    ? (e as { message?: unknown }).message
    : undefined;

/**
 * A list or store write refused by the database for its name (blank once Postgres folds whitespace
 * JS trim keeps, such as U+0085) or because the row went meanwhile, as the ToolError it is.
 */
function refusedWrite(e: unknown, subject: 'list' | 'store'): ToolError | undefined {
  switch (raised(e)) {
    case 'invalid_name':
    case 'store_name_empty':
    case 'store_name_too_long':
      return new ToolError('Der Name ist leer oder zu lang.', 'invalid', subject);
    case 'list_not_found':
    case 'not_a_member':
      return new ToolError(`${LABELS[subject]} nicht gefunden.`, 'not_found', subject);
  }
  return undefined;
}

/** A ticked item as "Zuletzt verwendet" shows it, with when it was ticked. */
export type RecentItem = ApiItem & { tickedAt: string };

/** How many things the app's "Zuletzt verwendet" shows (recentlyUsed in app/lib/list/model.dart). */
export const RECENT_SHOWN = 20;

/**
 * The newest ticked rows recentItems groups (the app groups the household's newest 50 it loaded).
 * Only these are folded and compared; finding them is still a top-N sort over the scope's ticked
 * rows, which grows with the household's history (about 0.2 s at 50,000, review 0).
 */
const RECENT_WINDOW = 200;

/**
 * The app's "Zuletzt verwendet" (recentlyUsed in app/lib/list/model.dart) on the server: ticked
 * items, newest first, one per thing (canonical_key, else the name folded like the app's
 * foldName), its newest purchase, and none for a thing that is open again, among the newest
 * RECENT_WINDOW ticked rows. A null [listId] looks at every list of the household at once.
 */
export async function recentItems(
  tx: Tx,
  household: string,
  listId: string | null,
  limit: number,
): Promise<RecentItem[]> {
  const thing = (column: string) =>
    tx.unsafe(`coalesce(${column}.canonical_key, regexp_replace(
      replace(replace(replace(replace(lower(btrim(${column}.name)), 'ä', 'ae'), 'ö', 'oe'),
        'ü', 'ue'), 'ß', 'ss'), '\\s+', ' ', 'g'))`);
  return await tx<RecentItem[]>`
    with bought as materialized (
      select i.id, i.canonical_key, i.name, coalesce(i.bought_at, i.updated_at) as at
      from public.items i
      where i.household_id = ${household} and i.status = 'bought'
        and (${listId}::uuid is null or i.list_id = ${listId}::uuid)
      order by coalesce(i.bought_at, i.updated_at) desc, i.id
      limit ${RECENT_WINDOW}
    ), open as (
      select ${thing('o')} as thing
      from public.items o
      where o.household_id = ${household} and o.status = 'active'
        and (${listId}::uuid is null or o.list_id = ${listId}::uuid)
    ), latest as (
      select distinct on (${thing('b')}) b.id, b.at
      from bought b
      where ${thing('b')} not in (select open.thing from open)
      order by ${thing('b')}, b.at desc, b.id
    )
    select ${apiColumns(tx)}, to_json(l.at) #>> '{}' as "tickedAt"
    from ${itemsFrom(tx, household)}
    join latest l on l.id = i.id
    order by l.at desc, i.id
    limit ${limit}`;
}

/** recentItems for the MCP tools: the list [list] names, else the default list. */
export async function listRecent(
  tx: Tx,
  household: string,
  list: string | undefined,
  limit: number,
): Promise<{ list: string; items: (Item & { tickedAt: string })[] }> {
  const shown = await listOf(tx, household, list);
  const rows = await recentItems(tx, household, shown.id, limit);
  return { list: shown.name, items: rows.map((r) => ({ ...toItem(r), tickedAt: r.tickedAt })) };
}

/** Something the household buys again and again; `due` when its usual interval is up. */
export type Usual = {
  name: string;
  quantity: string | null;
  uses: number;
  lastUsed: string;
  due: boolean;
};

/**
 * The household's usuals through public.suggest_items, the ranking the app's add sheet shows
 * (often and recently used first; with a prefix, names starting with it, then names with a word
 * starting with it). Things open on a list are left out.
 */
export async function usuals(
  tx: Tx,
  household: string,
  prefix: string,
  limit: number,
): Promise<Usual[]> {
  return await tx<Usual[]>`
    select name, quantity, uses, to_json(last_used) #>> '{}' as "lastUsed", due
    from public.suggest_items(${household}, ${prefix}, ${limit})`;
}

/** A list as the API shows it; `default` is where an add without a list goes. */
export type ListEntry = { id: string; name: string; sortOrder: number; default: boolean };

/** The household's lists in their order, the caller's default list marked. */
export async function listEntries(tx: Tx, household: string): Promise<ListEntry[]> {
  const [rows, { defaultList }] = await Promise.all([
    lists(tx, household),
    listCatalog(tx, household),
  ]);
  return rows.map((l) => ({
    id: l.id,
    name: l.name,
    sortOrder: l.position,
    default: l.id === defaultList.id,
  }));
}

async function listEntry(tx: Tx, household: string, id: string): Promise<ListEntry> {
  return oneRow((await listEntries(tx, household)).filter((l) => l.id === id), 'list');
}

/** Lists per household, public.create_list's guard. */
export const LIST_CAP = 50;

/** A new list after the others through public.create_list, the app's path. */
export async function createList(tx: Tx, household: string, name: string): Promise<ListEntry> {
  let id: string;
  try {
    const rows = await tx<{ id: string }[]>`
      select id from public.create_list(${household}, ${name}, gen_random_uuid())`;
    id = oneRow(rows, 'created list').id;
  } catch (e) {
    if (raised(e) === 'too_many_lists') {
      throw new ToolError(
        `Der Haushalt hat schon ${LIST_CAP} Listen, mehr gehen nicht.`,
        'limit',
        'list',
      );
    }
    throw refusedWrite(e, 'list') ?? e;
  }
  return await listEntry(tx, household, id);
}

/**
 * Renames the list [ref] names and/or moves it to [position] (0 is first, past the end is last),
 * through public.rename_list and public.move_list like the app.
 */
export async function changeList(
  tx: Tx,
  household: string,
  ref: string,
  change: { name?: string | undefined; position?: number | undefined },
): Promise<ListEntry> {
  if (change.name === undefined && change.position === undefined) {
    throw new ToolError('Gib an, was sich ändern soll.', 'invalid', null);
  }
  const list = await listOf(tx, household, ref);
  try {
    if (change.name !== undefined) {
      await tx`select from public.rename_list(${list.id}, ${change.name})`;
    }
    if (change.position !== undefined) {
      await tx`select from public.move_list(${list.id}, ${change.position})`;
    }
  } catch (e) {
    throw refusedWrite(e, 'list') ?? e;
  }
  return await listEntry(tx, household, list.id);
}

/** A store as the API shows it: its plain name only, never a chain (retailer rules). */
export type StoreEntry = { id: string; name: string; sortOrder: number };

const storeEntry = ({ id, name, sort_order }: Named & { sort_order: number }): StoreEntry => ({
  id,
  name,
  sortOrder: sort_order,
});

/**
 * Stores per household that the API and the MCP tools add up to. The app has no cap; this one
 * keeps an automation from filling the household, each store writing a layout row per category.
 */
export const STORE_CAP = 50;

/**
 * A store through public.add_store, the app's path: dm, Lidl, Edeka and a Baumarkt get their
 * layout. A name the household has already (any case, umlauts folded) answers that store, with
 * `created` false.
 */
export async function addStore(
  tx: Tx,
  household: string,
  name: string,
): Promise<{ store: StoreEntry; created: boolean }> {
  const before = await stores(tx, household);
  const rows = await tx<{ id: string }[]>`select public.add_store(${household}, ${name}) as id`
    .catch((e) => {
      throw refusedWrite(e, 'store') ?? e;
    });
  const id = oneRow(rows, 'added store').id;
  const created = !before.some((s) => s.id === id);
  // The throw rolls the insert back with the caller's transaction.
  if (created && before.length >= STORE_CAP) {
    throw new ToolError(
      `Der Haushalt hat schon ${STORE_CAP} Läden, mehr gehen nicht.`,
      'limit',
      'store',
    );
  }
  const after = await stores(tx, household);
  return { store: storeEntry(oneRow(after.filter((s) => s.id === id), 'store')), created };
}

/** Renames the store [ref] names through public.rename_store; a name another store has is a conflict. */
export async function renameStore(
  tx: Tx,
  household: string,
  ref: string,
  name: string,
): Promise<StoreEntry> {
  const store = resolve(await stores(tx, household), ref, 'store');
  try {
    await tx`select from public.rename_store(${store.id}, ${name})`;
  } catch (e) {
    if (raised(e) === 'store_name_taken') {
      throw new ToolError(
        `Ein anderer Laden heißt schon „${name.trim()}“.`,
        'conflict',
        'store',
        [],
        name,
      );
    }
    throw refusedWrite(e, 'store') ?? e;
  }
  const after = await stores(tx, household);
  return storeEntry(oneRow(after.filter((s) => s.id === store.id), 'store'));
}

/** A category in a store's walk order; `hidden`: the store does not carry it. */
export type LayoutEntry = { id: string; name: string; sortOrder: number; hidden: boolean };

/** Every category of the household in the store's walk order, the order list_items uses. */
async function layoutOf(tx: Tx, household: string, store: string): Promise<LayoutEntry[]> {
  return await tx<LayoutEntry[]>`
    select c.id, c.name, coalesce(o.sort_order, c.sort_order) as "sortOrder",
           coalesce(o.hidden, false) as hidden
    from public.categories c
    left join public.store_category_order o on o.store_id = ${store} and o.category_id = c.id
    where c.household_id = ${household}
    order by coalesce(o.sort_order, c.sort_order), c.name`;
}

/** The walk order of the store [ref] names. */
export async function storeLayout(
  tx: Tx,
  household: string,
  ref: string,
): Promise<{ store: StoreEntry; categories: LayoutEntry[] }> {
  const store = resolve(await stores(tx, household), ref, 'store');
  return { store: storeEntry(store), categories: await layoutOf(tx, household, store.id) };
}

/**
 * Sets the walk order of the store [ref] names through public.set_store_layout, the app's store
 * screen: the [order] categories first, in that order, then the others in their current order.
 * [hidden], when given, are all the categories the store does not carry; else they stay.
 */
export async function setStoreLayout(
  tx: Tx,
  household: string,
  ref: string,
  change: { order?: readonly string[] | undefined; hidden?: readonly string[] | undefined },
): Promise<{ store: StoreEntry; categories: LayoutEntry[] }> {
  if (change.order === undefined && change.hidden === undefined) {
    throw new ToolError(
      'Gib eine Reihenfolge oder die ausgeblendeten Kategorien an.',
      'invalid',
      null,
    );
  }
  const store = resolve(await stores(tx, household), ref, 'store');
  const current = await layoutOf(tx, household, store.id);
  const pick = (refs: readonly string[]) => {
    const found = refs.map((r) => resolve(current, r, 'category'));
    const twice = found.find((c, i) => found.findIndex((d) => d.id === c.id) !== i);
    if (twice) {
      throw new ToolError(`Kategorie „${twice.name}“ steht doppelt.`, 'invalid', 'category');
    }
    return found.map((c) => c.id);
  };
  const first = pick(change.order ?? []);
  const ids = [...first, ...current.map((c) => c.id).filter((id) => !first.includes(id))];
  const hidden = change.hidden === undefined
    ? current.filter((c) => c.hidden).map((c) => c.id)
    : pick(change.hidden);
  try {
    await tx`select from public.set_store_layout(${store.id}, ${ids}::uuid[], ${hidden}::uuid[])`;
  } catch (e) {
    // A category added or deleted since the read.
    if (raised(e) === 'invalid_category_order') {
      throw new ToolError(
        'Die Kategorien haben sich gerade geändert. Versuch es noch einmal.',
        'conflict',
        'category',
      );
    }
    throw e;
  }
  return { store: storeEntry(store), categories: await layoutOf(tx, household, store.id) };
}
