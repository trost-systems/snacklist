// What each route does (routes.ts names them): its input, parsed strictly from the request, and
// the work on the list (_shared/list.ts), run as the key's member under RLS.
import { z } from 'zod';
import type { Tx } from '../_shared/db.ts';
import {
  addItemIds,
  type ApiItem,
  apiItemsById,
  categories,
  counts,
  itemById,
  lists,
  moveItemById,
  type OpenItem,
  openItems,
  type Position,
  resolveFilter,
  setItemStatus,
  stores,
  UUID,
} from '../_shared/list.ts';
import { ApiError } from './errors.ts';
import { BATCH, PAGE_DEFAULT, PAGE_MAX } from './limits.ts';
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
const ref = z.string().trim().min(1).max(60);

const listQuery = z.object({
  store: ref.optional(),
  category: ref.optional(),
  list: ref.optional(),
  limit: z.string().regex(/^[0-9]{1,3}$/, 'Expected a whole number').transform(Number)
    .pipe(z.number().int().min(1).max(PAGE_MAX)).optional(),
  cursor: z.string().max(2048).optional(),
}).strict();

const newItem = z.object({
  name: z.string().trim().min(1).max(120),
  quantity: z.string().trim().min(1).max(40).nullish(),
  brand: z.string().trim().max(60).nullish(),
  properties: z.string().trim().max(120).nullish(),
  category: ref.nullish(),
  store: ref.nullish(),
}).strict();

const addBody = z.object({ items: z.array(newItem).min(1).max(BATCH), list: ref.optional() })
  .strict();

const moveBody = z.object({ category: ref.optional(), store: ref.nullable().optional() }).strict()
  .refine((b) => b.category !== undefined || b.store !== undefined, {
    message: 'Give category, store or both',
  });

// Cursors ------------------------------------------------------------------------------------

/**
 * What a page continues after, and the filter (resolved store, category and list ids) it belongs
 * to. The list id travels as `l`, absent in cursors made before lists (no list filter).
 */
type Cursor = { filter: [string | null, string | null, string | null]; after: Position };

const cursorShape = z.object({
  v: z.literal(1),
  f: z.tuple([z.string().regex(UUID).nullable(), z.string().regex(UUID).nullable()]),
  l: z.string().regex(UUID).nullable().optional(),
  k: z.tuple([
    z.number().int(),
    z.string().max(200),
    z.string().regex(/^(-?[0-9]+(\.[0-9]+)?(e[+-]?[0-9]+)?|-?Infinity)$/),
    z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?[+-]\d{2}:\d{2}$/),
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
  const { rank, category, sortKey, addedAt, id } = cursor.after;
  const [store, cat, list] = cursor.filter;
  return base64url.encode(JSON.stringify({
    v: 1,
    f: [store, cat],
    ...(list === null ? {} : { l: list }),
    k: [rank, category, sortKey, addedAt, id],
  }));
}

const invalidCursor = () =>
  new ApiError(400, 'invalid_cursor', 'The cursor is broken or belongs to another filter.');

export function decodeCursor(text: string): Cursor {
  let value: unknown;
  try {
    value = JSON.parse(base64url.decode(text));
  } catch {
    throw invalidCursor();
  }
  const parsed = cursorShape.safeParse(value);
  if (!parsed.success) throw invalidCursor();
  const [rank, category, sortKey, addedAt, id] = parsed.data.k;
  const [store, cat] = parsed.data.f;
  return {
    filter: [store, cat, parsed.data.l ?? null],
    after: { rank, category, sortKey, addedAt, id },
  };
}

// Operations ---------------------------------------------------------------------------------

const item = ({ position: _, ...rest }: OpenItem): ApiItem => rest;

const ok = (body: unknown): Result => ({ status: 200, body });

const named = (rows: { id: string; name: string; sort_order: number }[]) =>
  ok({
    data: rows.map((r) => ({ id: r.id, name: r.name, sortOrder: r.sort_order })),
    nextCursor: null,
  });

export const operations: Record<Operation, Parse> = {
  listItems: (raw) => {
    const query = strict(listQuery, raw.query, 'query');
    const cursor = query.cursor === undefined ? null : decodeCursor(query.cursor);
    const limit = query.limit ?? PAGE_DEFAULT;
    return async (tx, household) => {
      const { store, category, list } = await resolveFilter(tx, household, query);
      const filter: [string | null, string | null, string | null] = [
        store?.id ?? null,
        category?.id ?? null,
        list?.id ?? null,
      ];
      if (cursor && cursor.filter.some((id, i) => id !== filter[i])) throw invalidCursor();
      const rows = await openItems(
        tx,
        household,
        { storeId: filter[0], categoryId: filter[1], listId: filter[2] },
        { after: cursor?.after ?? null, limit: limit + 1 },
      );
      const page = rows.slice(0, limit);
      const last = rows.length > limit ? page.at(-1) : undefined;
      return ok({
        data: page.map(item),
        counts: await counts(tx, household, filter[2]),
        nextCursor: last ? encodeCursor({ filter, after: last.position }) : null,
      });
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
      const rows = await apiItemsById(tx, [
        ...added,
        ...existing,
        ...similar.flatMap((s) => s.onList),
      ]);
      const pick = (ids: string[]) => ids.map((id) => rows.find((r) => r.id === id));
      return {
        status: added.length > 0 ? 201 : 200,
        body: {
          data: {
            added: pick(added),
            alreadyOnList: pick(existing),
            similarOnList: similar.map((s) => ({ itemId: s.added, onList: pick(s.onList) })),
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

  moveItem: (raw) => {
    const id = idOf(raw);
    strict(noQuery, raw.query, 'query');
    const move = strict(moveBody, raw.body ?? {}, 'body');
    return async (tx, household) => ok({ data: await moveItemById(tx, household, id, move) });
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
      named((await lists(tx, household)).map((l) => ({ ...l, sort_order: l.position })));
  },
};
