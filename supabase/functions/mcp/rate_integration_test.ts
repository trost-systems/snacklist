// Job 336: the mcp function's per-user limit against the database, as production counts it
// (productionDeps.takeCall into public.mcp_take_call). Runs with FG_DB_TEST=1 and SUPABASE_DB_URL
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
        Array.from({ length: BURST + 5 }, () => productionDeps.takeCall(user)),
      );
      // A second of refill can let one more through on a slow run.
      const passed = waits.filter((w) => w === null).length;
      assert(passed === BURST || passed === BURST + 1, `${passed} passed`);
      assert(waits.every((w) => w === null || w >= 1), `waits ${waits.join(',')}`);
      assertEquals(await productionDeps.takeCall(other), null, 'another user is not held up');
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
      () => productionDeps.takeCall(crypto.randomUUID()),
      AuthError,
    );
    assertEquals(error.reason, 'user_deleted');
  },
});
