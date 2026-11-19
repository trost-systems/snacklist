// The report's SQL functions over the service connection. Times go as text: postgres.js drops
// microseconds from Date parameters.
import { oneRow, type Sql } from '../_shared/db.ts';
import type { AppStore, Store, Stored } from './handler.ts';

export function sqlStore(db: () => Sql): Store {
  return {
    async submit(r, now, limits) {
      const [row] = await db()<Stored[]>`
        select id, ref, confirm
        from public.content_report_submit(${r.locale}, ${r.category}, ${r.location}, ${r.reason},
          ${r.name ?? ''}, ${r.email ?? ''}, ${now.toISOString()}::timestamptz,
          ${limits.perHour})`;
      return row ?? null;
    },
    async confirmationSent(id, now) {
      const rows = await db()<{ ok: boolean }[]>`
        select public.content_report_confirmation_sent(${id}::uuid,
          ${now.toISOString()}::timestamptz) as ok`;
      return oneRow(rows, 'content_report_confirmation_sent').ok;
    },
  };
}

export function sqlAppStore(db: () => Sql): AppStore {
  return {
    async submit(userId, r, now, limits) {
      const target = r.target.kind === 'elsewhere' ? null : r.target.id;
      const rows = await db()<(Stored & { refused: 'user' | 'global' | null })[]>`
        select id, ref, confirm, refused
        from public.content_report_submit_app(${userId}::uuid, ${r.locale}, ${r.category},
          ${r.target.kind}, ${target}::uuid, ${r.location}, ${r.reason}, ${r.name ?? ''},
          ${r.email ?? ''}, ${r.screenshot}::bytea, ${now.toISOString()}::timestamptz,
          ${limits.perUserHour}, ${limits.perHour})`;
      const { id, ref, confirm, refused } = oneRow(rows, 'content_report_submit_app');
      return refused ? { refused } : { id, ref, confirm };
    },
  };
}
