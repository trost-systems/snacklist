// Job 376: the push function's store (store.ts) and handler against a database with the repo's
// migrations. Anna and Ben share a household, Max has his own: a send to all three for Anna's list
// reaches Anna's and Ben's devices only, a list of Max's household or no list is unknown_list, and
// a token FCM calls unregistered is deleted, unless it moved to another account meanwhile. Devices
// are registered through register_push_token, as the app does. The db gate sets FG_DB_TEST=1 and
// SUPABASE_DB_URL; without them this is skipped.
import { assertEquals } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from '../_shared/db.ts';
import type { FcmMessage } from './fcm.ts';
import { createHandler } from './handler.ts';
import { sqlStore } from './store.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const SECRET = 'integration-push-secret';

type Sql = postgres.Sql;

async function asUser<T>(
  sql: Sql,
  userId: string,
  work: (tx: postgres.TransactionSql) => Promise<T>,
) {
  return await sql.begin(async (tx) => {
    await tx`select set_config('role', 'authenticated', true),
      set_config('request.jwt.claims', ${
      JSON.stringify({ sub: userId, role: 'authenticated' })
    }, true)`;
    return await work(tx);
  }) as T;
}

async function household(sql: Sql, userId: string): Promise<{ id: string; list: string }> {
  const [row] = await asUser(sql, userId, async (tx) => {
    const [h] = await tx<{ id: string }[]>`select id from public.create_household('Push')`;
    return await tx<{ id: string; list: string }[]>`
      select household_id as id, id as list from public.lists where household_id = ${
      h?.id ?? null
    }`;
  });
  if (!row) throw new Error('create_household made no list');
  return row;
}

const register = (sql: Sql, userId: string, token: string, platform = 'android') =>
  asUser(sql, userId, (tx) => tx`select public.register_push_token(${token}, ${platform})`);

Deno.test({
  name: 'push targets the household members among the recipients and forgets dead tokens',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    const [anna, ben, max] = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
    const run = crypto.randomUUID();
    const token = (name: string) => `test-token-${name}-${run}`;
    const households: string[] = [];
    try {
      for (const id of [anna, ben, max]) {
        await sql`insert into auth.users (id, email) values (${id}, ${`${id}@fg-test.invalid`})`;
      }
      const home = await household(sql, anna);
      const other = await household(sql, max);
      households.push(home.id, other.id);
      const [invite] = await asUser(
        sql,
        anna,
        (tx) => tx<{ code: string }[]>`select code from public.create_invite(${home.id}::uuid)`,
      );
      await asUser(sql, ben, (tx) => tx`select public.join_household(${invite?.code ?? ''})`);

      await register(sql, anna, token('anna-phone'), 'ios');
      await register(sql, anna, token('anna-tablet'));
      await register(sql, ben, token('ben'));
      await register(sql, max, token('max'));

      const store = sqlStore(() => sql);
      const everyone = [anna, ben, max];
      const found = await store.devices(home.id, home.list, everyone);
      assertEquals(
        found?.map((d) => d.token).toSorted(),
        [token('anna-phone'), token('anna-tablet'), token('ben')].toSorted(),
        "Anna's and Ben's devices, not Max's",
      );
      assertEquals(await store.devices(home.id, other.list, everyone), null, "Max's list");
      assertEquals(await store.devices(home.id, crypto.randomUUID(), everyone), null, 'no list');
      assertEquals(await store.devices(home.id, home.list, [ben]), [{
        userId: ben,
        token: token('ben'),
      }]);

      // A token that moved to Max is not Anna's to forget.
      await register(sql, max, token('anna-tablet'));
      assertEquals(await store.forget([{ userId: anna, token: token('anna-tablet') }]), 0);
      await register(sql, anna, token('anna-tablet'));

      const sent: FcmMessage[] = [];
      const handler = createHandler({
        secret: SECRET,
        sender: {
          send(message) {
            sent.push(message);
            return Promise.resolve(
              message.token === token('anna-tablet')
                ? { outcome: 'unregistered' }
                : { outcome: 'sent' },
            );
          },
        },
        store,
        now: () => new Date(),
      });
      const res = await handler(
        new Request('http://localhost/push', {
          method: 'POST',
          headers: { 'x-push-secret': SECRET },
          body: JSON.stringify({
            household_id: home.id,
            list_id: home.list,
            recipients: everyone.map((user_id) => ({
              user_id,
              title: 'Milch',
              body: 'Einkaufsliste',
            })),
          }),
        }),
      );
      assertEquals(await res.json(), {
        status: 'sent',
        devices: 3,
        sent: 2,
        failed: 1,
        removed: 1,
      });
      assertEquals(sent.every((m) => m.data.list_id === home.list), true);
      const left = await sql<{ token: string }[]>`
        select token from public.push_tokens where user_id = any(${everyone}::uuid[]) order by token`;
      assertEquals(
        left.map((r) => r.token),
        [token('anna-phone'), token('ben'), token('max')].toSorted(),
        'the unregistered token is gone, the others stay',
      );
    } finally {
      await sql`delete from public.households where id = any(${households}::uuid[])`;
      await sql`delete from auth.users where id = any(${[anna, ben, max]}::uuid[])`;
      await sql.end();
    }
  },
});
