// The report's SQL functions over the service connection. Times go as text: postgres.js drops
// microseconds from Date parameters.
import { oneRow, type Sql } from '../_shared/db.ts';
import type { Store, Stored } from './handler.ts';

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
