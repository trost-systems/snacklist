// The push function's SQL over the service connection: it reads every user's devices, which no
// client role may, so it filters by membership itself.
import { oneRow, type Sql } from '../_shared/db.ts';
import type { Store } from './handler.ts';

export function sqlStore(db: () => Sql): Store {
  return {
    async devices(householdId, listId, userIds) {
      const sql = db();
      const known = await sql<{ known: boolean }[]>`
        select exists (
          select from public.lists l
          where l.id = ${listId}::uuid and l.household_id = ${householdId}::uuid
        ) as known`;
      if (!oneRow(known, 'push list check').known) return null;
      const rows = await sql<{ user_id: string; token: string }[]>`
        select t.user_id::text as user_id, t.token
        from public.push_tokens t
        join public.household_members m
          on m.user_id = t.user_id and m.household_id = ${householdId}::uuid
        where t.user_id = any(${[...userIds]}::uuid[])
        order by t.user_id, t.updated_at desc, t.id`;
      return rows.map((r) => ({ userId: r.user_id, token: r.token }));
    },
    async forget(devices) {
      const rows = await db()<{ id: string }[]>`
        delete from public.push_tokens t
        using unnest(${devices.map((d) => d.userId)}::uuid[], ${
        devices.map((d) => d.token)
      }::text[])
          as gone (user_id, token)
        where t.user_id = gone.user_id and t.token = gone.token
        returning t.id`;
      return rows.length;
    },
  };
}
