// Job 336: the mcp function's per-user limit against the database, as production counts it
// (productionDeps.takeCall into public.mcp_take). Runs with FG_DB_TEST=1 and SUPABASE_DB_URL
// (db gate).
import { assert, assertEquals, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { AuthError } from '../_shared/auth.ts';
import { databaseUrl } from '../_shared/db.ts';
import { BURST, productionDeps } from './handler.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

Deno.test({
  name: 'concurrent MCP requests of one user: the burst goes through, the rest wait',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const [user, other] = [crypto.randomUUID(), crypto.randomUUID()];
    try {
      for (const id of [user, other]) {
        await sql`insert into auth.users (id, email) values (${id}, ${`${id}@fg-test.invalid`})`;
      }
      const waits = await Promise.all(
        Array.from({ length: BURST + 5 }, () => productionDeps.takeCall(user, 0)),
      );
      // A second of refill can let one more through on a slow run.
      const passed = waits.filter((w) => w === null).length;
      assert(passed === BURST || passed === BURST + 1, `${passed} passed`);
      assert(waits.every((w) => w === null || w >= 1), `waits ${waits.join(',')}`);
      assertEquals(await productionDeps.takeCall(other, 0), null, 'another user is not held up');
    } finally {
      await sql`delete from auth.users where id in (${user}, ${other})`;
      await sql.end();
    }
  },
});

Deno.test({
  name: 'an account gone since authentication is a user_deleted AuthError, not a failure',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const error = await assertRejects(
      () => productionDeps.takeCall(crypto.randomUUID(), 0),
      AuthError,
    );
    assertEquals(error.reason, 'user_deleted');
  },
});

Deno.test({
  name: "only tool calls use the account's day; a refused one is given back; the 1001st waits",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const user = crypto.randomUUID();
    const day = async () =>
      (await sql<{ requests: number }[]>`
        select requests from public.account_days where user_id = ${user}`)[0]?.requests ?? 0;
    try {
      await sql`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
      assertEquals(await productionDeps.takeCall(user, 0), null, 'initialize, tools/list, ping');
      assertEquals(await day(), 0, 'protocol requests leave the day alone');
      assertEquals(await productionDeps.takeCall(user, 2), null, 'a batch of two tool calls');
      assertEquals(await day(), 2, 'each tool call is one');
      await productionDeps.refundCalls(user, 1);
      assertEquals(await day(), 1, 'a locked call is given back');
      await sql`update public.account_days set requests = 1000 where user_id = ${user}`;
      await sql`update public.mcp_rate set tokens = 20 where user_id = ${user}`;
      const wait = await productionDeps.takeCall(user, 1);
      assert(wait !== null && wait > 1, 'the 1001st tool call waits for the next UTC day');
      assertEquals(await day(), 1000, 'and takes nothing');
      assertEquals(await productionDeps.takeCall(user, 0), null, 'protocol requests still go');
    } finally {
      await sql`delete from auth.users where id = ${user}`;
      await sql.end();
    }
  },
});
