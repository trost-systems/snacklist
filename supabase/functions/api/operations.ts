// What each route does (routes.ts names them): its input, parsed strictly from the request, and
// the work on the list (_shared/list.ts), run as the key's member under RLS.
import { z } from 'zod';
import { oneRow, type Tx } from '../_shared/db.ts';
import {
  addItemIds,
  addStore,
  type AisleKey,
  anchorOf,
  type ApiItem,
  apiItemsById,
  categories,
  changeList,
  counts,
  createList,
  deleteItemById,
  itemById,
  type Keyed,
  listEntries,
  openItems,
  openItemsInWalk,
  type OrderMode,
  orderMode,
  placeItemById,
  RECENT_SHOWN,
  recentItems,
  renameStore,
  resolveFilter,
  setItemStatus,
  setStoreLayout,
  setStoreOrderById,
  STORE_ORDER_MAX,
  storeLayout,
  stores,
  ToolError,
  updateItemById,
  usuals,
  UUID,
  type WalkKey,
} from '../_shared/list.ts';
import { storedText } from '../_shared/stored_text.ts';
import { ApiError } from './errors.ts';
import {
  BATCH,
  PAGE_DEFAULT,
  PAGE_MAX,
  RECENT_MAX,
  SUGGEST_DEFAULT,
  SUGGEST_MAX,
} from './limits.ts';
import type { Operation } from './routes.ts';

/** A request as the router hands it over: the path's id, the query, the parsed JSON body. */
export type Raw = {
  id: string | null;
  query: Record<string, string>;
  /** undefined: no body. */
  body: unknown;
};

export type Result = { status: 200 | 201; body: unknown };

/** The operation's work, bound to its parsed input; runs in the caller's transaction. */
export type Run = (tx: Tx, household: string) => Promise<Result>;

/** Parses a request for one operation (throwing ApiError) into its work. */
type Parse = (raw: Raw) => Run;

/** Parses [value] with [schema] or fails with validation_failed; issues name paths, never values. */
function strict<T>(schema: z.ZodType<T>, value: unknown, where: 'query' | 'body'): T {
  const parsed = schema.safeParse(value);
  if (parsed.success) return parsed.data;
  throw new ApiError(400, 'validation_failed', `The request ${where} is not valid.`, {
    issues: parsed.error.issues.map((issue) => ({
      path: [where, ...issue.path.map(String)].join('.'),
      message: issue.message,
    })),
  });
}

function idOf(raw: Raw): string {
  if (raw.id === null || !UUID.test(raw.id)) {
    throw new ApiError(400, 'invalid_id', 'The id in the path is not a UUID.');
  }
  return raw.id.toLowerCase();
}

const noQuery = z.object({}).strict();
const noBody = z.object({}).strict();

/** A store, category or list, by id or name. */
const ref = storedText.trim().min(1).max(60);

/** A query's `limit`: a whole number from 1 to [max]. */
const limitOf = (max: number) =>
  z.string().regex(/^[0-9]{1,3}$/, 'Expected a whole number').transform(Number)
    .pipe(z.number().int().min(1).max(max));

const listQuery = z.object({
  store: ref.optional(),
  category: ref.optional(),
  list: ref.optional(),
  limit: limitOf(PAGE_MAX).optional(),
  cursor: z.string().max(2048).optional(),
  order: z.enum(['aisle', 'walk']).optional(),
}).strict();

const recentQuery = z.object({ list: ref.optional(), limit: limitOf(RECENT_MAX).optional() })
  .strict();

const suggestQuery = z.object({
  prefix: storedText.max(60).optional(),
  limit: limitOf(SUGGEST_MAX).optional(),
  due: z.enum(['true', 'false']).optional(),
}).strict();

/** A list name as public.list_name takes it. */
const listName = storedText.trim().min(1).max(60);

const listBody = z.object({ name: listName }).strict();

const listEdit = z.object({
  name: listName.optional(),
  position: z.number().int().min(0).max(1000).optional(),
}).strict().refine((b) => b.name !== undefined || b.position !== undefined, {
  message: 'Give at least one field to change',
});

/** A store's plain name as public.store_name takes it; no chain or other retailer field. */
const storeBody = z.object({ name: storedText.trim().min(1).max(40) }).strict();

const layoutBody = z.object({
  categories: z.array(ref).max(200).optional(),
  hidden: z.array(ref).max(200).optional(),
}).strict().refine((b) => b.categories !== undefined || b.hidden !== undefined, {
  message: 'Give the categories in order, the hidden ones, or both',
});

const newItem = z.object({
  name: storedText.trim().min(1).max(120),
  quantity: storedText.trim().min(1).max(40).nullish(),
  brand: storedText.trim().max(60).nullish(),
  properties: storedText.trim().max(120).nullish(),
  category: ref.nullish(),
  store: ref.nullish(),
}).strict();

const addBody = z.object({ items: z.array(newItem).min(1).max(BATCH), list: ref.optional() })
  .strict();

/** Blank or null clears the field. */
const clearable = (max: number) => storedText.trim().max(max).nullable().optional();

const editBody = z.object({
  name: storedText.trim().min(1).max(120).optional(),
  quantity: clearable(40),
  brand: clearable(60),
  properties: clearable(120),
  category: ref.optional(),
  store: ref.nullable().optional(),
  list: ref.optional(),
}).strict().refine((b) => Object.values(b).some((v) => v !== undefined), {
  message: 'Give at least one field to change',
});

const id = z.string().regex(UUID, 'Expected an item id').transform((s) => s.toLowerCase());

const placeBody = z.object({ before: id.optional(), after: id.optional() }).strict()
  .transform((b, ctx) => {
    const placing = anchorOf(b);
    if (placing) return placing;
    ctx.addIssue({ code: 'custom', message: 'Give exactly one of before and after' });
    return z.NEVER;
  });

const storeOrderBody = z.object({
  items: z.array(id).min(1).max(STORE_ORDER_MAX)
    .refine((ids) => new Set(ids).size === ids.length, 'Each item at most once'),
}).strict();

// Cursors ------------------------------------------------------------------------------------

/**
 * What a page continues after, and the filter (resolved store, category and list ids) it belongs
 * to. The list id travels as `l`, absent in cursors made before lists (no list filter). A walk
 * cursor (`o` "walk") carries the household's order mode (`m`) it was made in.
 */
type Filter = [string | null, string | null, string | null];

type Cursor =
  | { order: 'aisle'; filter: Filter; after: AisleKey }
  | { order: 'walk'; mode: OrderMode; filter: Filter; after: WalkKey };

const MOMENT = /^(?!0000)\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?[+-](0\d|1[0-5]):[0-5]\d$/;

/** A date and time that exist: the pattern alone lets a month 13 or a February 30 through. */
function isMoment(text: string): boolean {
  const local = text.slice(0, 19);
  const at = Date.parse(`${local}Z`);
  return MOMENT.test(text) && !Number.isNaN(at) && new Date(at).toISOString().startsWith(local);
}

const sortKey = z.string().max(32).refine((s) => String(Number(s)) === s);

const filterShape = {
  f: z.tuple([z.string().regex(UUID).nullable(), z.string().regex(UUID).nullable()]),
  l: z.string().regex(UUID).nullable().optional(),
};

/**
 * A key exactly as openItems and openItemsInWalk give it out, so that every value is one Postgres
 * can compare: a boolean, an int4, text, a float8 in its shortest decimal, a timestamptz, a uuid.
 */
const aisleShape = z.object({
  v: z.literal(1),
  ...filterShape,
  k: z.tuple([
    z.int32(),
    storedText.max(200),
    sortKey,
    z.string().refine(isMoment),
    z.string().regex(UUID),
  ]),
}).strict();

const walkShape = z.object({
  v: z.literal(1),
  o: z.literal('walk'),
  m: z.enum(['categories', 'learned']),
  ...filterShape,
  k: z.tuple([
    z.boolean(),
    z.int32(),
    storedText.max(200),
    z.string().regex(UUID),
    z.int32(),
    storedText.max(200),
    sortKey,
    z.string().refine(isMoment),
    z.string().regex(UUID),
  ]),
}).strict();

const base64url = {
  encode: (text: string) =>
    btoa(String.fromCharCode(...new TextEncoder().encode(text)))
      .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, ''),
  decode: (text: string) =>
    new TextDecoder('utf-8', { fatal: true }).decode(
      Uint8Array.from(atob(text.replaceAll('-', '+').replaceAll('_', '/')), (c) => c.charCodeAt(0)),
    ),
};

export function encodeCursor(cursor: Cursor): string {
  const [store, cat, list] = cursor.filter;
  const filter = { f: [store, cat], ...(list === null ? {} : { l: list }) };
  if (cursor.order === 'aisle') {
    const { rank, category, sortKey, addedAt, id } = cursor.after;
    return base64url.encode(JSON.stringify({
      v: 1,
      ...filter,
      k: [rank, category, sortKey, addedAt, id],
    }));
  }
  const a = cursor.after;
  return base64url.encode(JSON.stringify({
    v: 1,
    o: 'walk',
    m: cursor.mode,
    ...filter,
    k: [
      a.noStore,
      a.storeRank,
      a.storeName,
      a.storeId,
      a.rank,
      a.category,
      a.sortKey,
      a.addedAt,
      a.id,
    ],
  }));
}

const invalidCursor = () =>
  new ApiError(
    400,
    'invalid_cursor',
    'The cursor is broken or belongs to another filter or order.',
  );

export function decodeCursor(text: string): Cursor {
  let value: unknown;
  try {
    value = JSON.parse(base64url.decode(text));
  } catch {
    throw invalidCursor();
  }
  const walk = walkShape.safeParse(value);
  if (walk.success) {
    const { f: [store, cat], l, m, k } = walk.data;
    const [noStore, storeRank, storeName, storeId, rank, category, sortKey, addedAt, id] = k;
    return {
      order: 'walk',
      mode: m,
      filter: [store, cat, l ?? null],
      after: { noStore, storeRank, storeName, storeId, rank, category, sortKey, addedAt, id },
    };
  }
  const aisle = aisleShape.safeParse(value);
  if (!aisle.success) throw invalidCursor();
  const [rank, category, sortKey, addedAt, id] = aisle.data.k;
  const [store, cat] = aisle.data.f;
  return {
    order: 'aisle',
    filter: [store, cat, aisle.data.l ?? null],
    after: { rank, category, sortKey, addedAt, id },
  };
}

// Operations ---------------------------------------------------------------------------------

const item = <K>({ key: _, ...rest }: Keyed<K>): ApiItem => rest;

const ok = (body: unknown): Result => ({ status: 200, body });

/** The store or list the path's {id} names: one of another household, or none, is a 404. */
async function inPath<T>(subject: 'store' | 'list', work: Promise<T>): Promise<T> {
  try {
    return await work;
  } catch (e) {
    if (e instanceof ToolError && e.subject === subject && e.reason === 'not_found') {
      throw new ApiError(404, `${subject}_not_found`, `No such ${subject} in this household.`);
    }
    throw e;
  }
}

const named = (rows: { id: string; name: string; sort_order: number }[]) =>
  ok({
    data: rows.map((r) => ({ id: r.id, name: r.name, sortOrder: r.sort_order })),
    nextCursor: null,
  });

export const operations: Record<Operation, Parse> = {
  listItems: (raw) => {
    const { order = 'aisle', ...query } = strict(listQuery, raw.query, 'query');
    const cursor = query.cursor === undefined ? null : decodeCursor(query.cursor);
    const limit = query.limit ?? PAGE_DEFAULT;
    if (cursor && cursor.order !== order) throw invalidCursor();
    return async (tx, household) => {
      const { store, category, list } = await resolveFilter(tx, household, query);
      const filter: Filter = [store?.id ?? null, category?.id ?? null, list?.id ?? null];
      if (cursor && cursor.filter.some((id, i) => id !== filter[i])) throw invalidCursor();
      const ids = { storeId: filter[0], categoryId: filter[1], listId: filter[2] };
      let data: ApiItem[];
      let nextCursor: string | null = null;
      if (order === 'walk') {
        const mode = await orderMode(tx, household);
        if (cursor?.order === 'walk' && cursor.mode !== mode) throw invalidCursor();
        const after = cursor?.order === 'walk' ? cursor.after : null;
        const rows = await openItemsInWalk(tx, household, ids, { after, limit: limit + 1 });
        const page = rows.slice(0, limit);
        const last = rows.length > limit ? page.at(-1) : undefined;
        data = page.map(item);
        if (last) nextCursor = encodeCursor({ order, mode, filter, after: last.key });
      } else {
        const after = cursor?.order === 'aisle' ? cursor.after : null;
        const rows = await openItems(tx, household, ids, { after, limit: limit + 1 });
        const page = rows.slice(0, limit);
        const last = rows.length > limit ? page.at(-1) : undefined;
        data = page.map(item);
        if (last) nextCursor = encodeCursor({ order, filter, after: last.key });
      }
      return ok({ data, counts: await counts(tx, household, filter[2]), nextCursor });
    };
  },

  getItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    return async (tx, household) => ok({ data: await itemById(tx, household, id) });
  },

  addItems: (raw) => {
    strict(noQuery, raw.query, 'query');
    const { items, list } = strict(addBody, raw.body ?? {}, 'body');
    const wanted = items.map((i) => ({
      name: i.name,
      quantity: i.quantity ?? undefined,
      brand: i.brand ?? undefined,
      properties: i.properties ?? undefined,
      category: i.category ?? undefined,
      store: i.store ?? undefined,
    }));
    return async (tx, household) => {
      const { added, existing, similar } = await addItemIds(tx, household, wanted, list);
      const rows = await apiItemsById(tx, household, [
        ...added,
        ...existing,
        ...similar.flatMap((s) => s.onList),
      ]);
      const byId = new Map(rows.map((r) => [r.id, r]));
      const pick = (ids: string[]) => ids.map((id) => byId.get(id));
      return {
        status: added.length > 0 ? 201 : 200,
        body: {
          data: {
            added: pick(added),
            alreadyOnList: pick(existing),
            similarOnList: similar.map((s) => ({
              itemId: s.added,
              onList: pick(s.onList),
              total: s.total,
            })),
          },
        },
      };
    };
  },

  tickItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    strict(noBody, raw.body ?? {}, 'body');
    return async (tx, household) => ok({ data: await setItemStatus(tx, household, id, 'bought') });
  },

  untickItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    strict(noBody, raw.body ?? {}, 'body');
    return async (tx, household) => ok({ data: await setItemStatus(tx, household, id, 'active') });
  },

  updateItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const edit = strict(editBody, raw.body ?? {}, 'body');
    return async (tx, household) => ok({ data: await updateItemById(tx, household, id, edit) });
  },

  deleteItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    strict(noBody, raw.body ?? {}, 'body');
    return async (tx, household) => ok({ data: await deleteItemById(tx, household, id) });
  },

  placeItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const { anchor, edge } = strict(placeBody, raw.body ?? {}, 'body');
    if (anchor === id) {
      throw new ApiError(400, 'validation_failed', 'The request body is not valid.', {
        issues: [{ path: `body.${edge}`, message: 'An item cannot be placed next to itself' }],
      });
    }
    return async (tx, household) =>
      ok({ data: await placeItemById(tx, household, id, anchor, edge) });
  },

  setStoreOrder: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const { items } = strict(storeOrderBody, raw.body ?? {}, 'body');
    return async (tx, household) => {
      const ordered = await setStoreOrderById(tx, household, id, items);
      if (ordered === null) {
        throw new ApiError(404, 'store_not_found', 'No such store in this household.');
      }
      return ok({ data: ordered });
    };
  },

  listCategories: (raw) => {
    strict(noQuery, raw.query, 'query');
    return async (tx, household) => named(await categories(tx, household));
  },

  listStores: (raw) => {
    strict(noQuery, raw.query, 'query');
    return async (tx, household) => named(await stores(tx, household));
  },

  listLists: (raw) => {
    strict(noQuery, raw.query, 'query');
    return async (tx, household) =>
      ok({ data: await listEntries(tx, household), nextCursor: null });
  },

  createList: (raw) => {
    strict(noQuery, raw.query, 'query');
    const { name } = strict(listBody, raw.body ?? {}, 'body');
    return async (tx, household) => ({
      status: 201,
      body: { data: await createList(tx, household, name) },
    });
  },

  updateList: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const change = strict(listEdit, raw.body ?? {}, 'body');
    return async (tx, household) =>
      ok({ data: await inPath('list', changeList(tx, household, id, change)) });
  },

  recentItems: (raw) => {
    const query = strict(recentQuery, raw.query, 'query');
    return async (tx, household) => {
      const { list } = await resolveFilter(tx, household, { list: query.list });
      const rows = await recentItems(
        tx,
        household,
        list?.id ?? null,
        query.limit ?? RECENT_SHOWN,
      );
      return ok({ data: rows, nextCursor: null });
    };
  },

  suggestItems: (raw) => {
    const query = strict(suggestQuery, raw.query, 'query');
    return async (tx, household) =>
      ok({
        data: await usuals(
          tx,
          household,
          query.prefix ?? '',
          query.limit ?? SUGGEST_DEFAULT,
          query.due === 'true',
        ),
        nextCursor: null,
      });
  },

  addStore: (raw) => {
    strict(noQuery, raw.query, 'query');
    const { name } = strict(storeBody, raw.body ?? {}, 'body');
    return async (tx, household) => {
      const { store, created } = await addStore(tx, household, name);
      return { status: created ? 201 : 200, body: { data: store } };
    };
  },

  updateStore: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const { name } = strict(storeBody, raw.body ?? {}, 'body');
    return async (tx, household) =>
      ok({ data: await inPath('store', renameStore(tx, household, id, name)) });
  },

  getStoreLayout: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    return async (tx, household) => {
      const { categories } = await inPath('store', storeLayout(tx, household, id));
      return ok({ data: categories, nextCursor: null });
    };
  },

  setStoreLayout: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const change = strict(layoutBody, raw.body ?? {}, 'body');
    return async (tx, household) => {
      const { categories } = await inPath(
        'store',
        setStoreLayout(tx, household, id, { order: change.categories, hidden: change.hidden }),
      );
      return ok({ data: categories, nextCursor: null });
    };
  },

  // The household's name, currency and size; never who its members are.
  getHousehold: (raw) => {
    strict(noQuery, raw.query, 'query');
    return async (tx, household) => {
      const rows = await tx<{ id: string; name: string; currency: string; memberCount: number }[]>`
        select h.id, h.name, h.currency, m.member_count as "memberCount"
        from public.households h
        join public.my_households() m on m.id = h.id
        where h.id = ${household}`;
      return ok({ data: oneRow(rows, 'household') });
    };
  },
};
