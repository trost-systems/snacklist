// A place or a store order that loses a race with a tick, a move or a delete between this
// request's reads and the database function: a refusal the API and MCP can name, not a 500.
import { assertEquals, assertInstanceOf, assertRejects } from '@std/assert';
import type { Tx } from './db.ts';
import { placeItemById, setStoreOrder, setStoreOrderById, ToolError } from './list.ts';

const HOUSEHOLD = 'c0000000-0000-0000-0000-000000000001';
const REWE = { id: 'b0000000-0000-0000-0000-000000000001', name: 'Rewe', 'sort_order': 0 };
const MILCH = { id: 'a0000000-0000-0000-0000-000000000001', name: 'Milch', 'store_id': REWE.id };
const BROT = { id: 'a0000000-0000-0000-0000-000000000002', name: 'Brot', 'store_id': REWE.id };

/** What a database function raised, as postgres.js throws it. */
function raisedError(message: string): Error {
  return Object.assign(new Error(message), { name: 'PostgresError' });
}

/**
 * A transaction whose every query is answered by [answer] from its SQL text and values; a
 * savepoint runs its work on the same fake.
 */
function fakeTx(answer: (sql: string, values: unknown[]) => readonly unknown[]): Tx {
  const tx = (strings: TemplateStringsArray | unknown, ...values: unknown[]) =>
    Promise.resolve().then(() =>
      Array.isArray(strings) ? answer(strings.join('?').replace(/\s+/g, ' '), values) : []
    );
  const savepoint = (work: (sp: unknown) => Promise<unknown>) => work(tx);
  return Object.assign(tx, { savepoint }) as unknown as Tx;
}

/** Milch and Brot open; public.place_item raises [raised]. */
function placing(raised: string): Tx {
  return fakeTx((sql, values) => {
    if (sql.includes('public.place_item')) throw raisedError(raised);
    return [MILCH, BROT].filter((i) => i.id === values[0]);
  });
}

Deno.test('a place whose anchor was ticked meanwhile is the anchor not found', async () => {
  const e = await assertRejects(
    () => placeItemById(placing('invalid_anchor'), HOUSEHOLD, MILCH.id, BROT.id, 'after'),
  );
  assertInstanceOf(e, ToolError);
  assertEquals([e.reason, e.subject], ['not_found', 'anchor']);
});

Deno.test('a place whose item or anchor was deleted meanwhile is the item not found', async () => {
  const e = await assertRejects(
    () => placeItemById(placing('item_not_found'), HOUSEHOLD, MILCH.id, BROT.id, 'before'),
  );
  assertInstanceOf(e, ToolError);
  assertEquals([e.reason, e.subject], ['not_found', 'item']);
});

/**
 * A learned household with Rewe, Milch and Brot open in it, [after] open once
 * public.set_store_order raised [raised].
 */
function ordering(raised: string, after: readonly (typeof MILCH)[] = [MILCH, BROT]): Tx {
  let failed = false;
  return fakeTx((sql) => {
    if (sql.includes('public.set_store_order')) {
      failed = true;
      throw raisedError(raised);
    }
    if (sql.includes('from public.households')) return [{ mode: 'learned' }];
    if (sql.includes('from public.stores')) return [REWE];
    if (sql.includes('from public.lists')) return [{ id: 'l1', name: 'Einkauf', position: 0 }];
    const open = failed ? after : [MILCH, BROT];
    if (sql.includes('any(')) return open.map(({ id }) => ({ id }));
    return sql.includes("status = 'active'") ? open : [];
  });
}

Deno.test('a store order for a store deleted meanwhile is no such store', async () => {
  assertEquals(
    await setStoreOrderById(ordering('store_not_found'), HOUSEHOLD, REWE.id, [MILCH.id]),
    null,
  );
  const e = await assertRejects(() =>
    setStoreOrder(ordering('store_not_found'), HOUSEHOLD, {
      store: 'Rewe',
      items: ['Milch'],
      list: 'Einkauf',
    })
  );
  assertInstanceOf(e, ToolError);
  assertEquals([e.reason, e.subject], ['not_found', 'store']);
});

Deno.test('a store order listing an item ticked meanwhile names that item', async () => {
  const e = await assertRejects(() =>
    setStoreOrderById(ordering('invalid_items', [BROT]), HOUSEHOLD, REWE.id, [MILCH.id, BROT.id])
  );
  assertInstanceOf(e, ToolError);
  assertEquals([e.reason, e.candidates], ['not_in_store', [MILCH.id]]);
});
