// The waitlist's SQL functions over the service connection. Times go as text: postgres.js drops
// microseconds from Date parameters.
import type { Sql } from '../_shared/db.ts';
import type { Recipient, Store } from './handler.ts';

export function sqlStore(db: () => Sql): Store {
  const one = (rows: Recipient[]) => rows[0] ?? null;
  return {
    async rateHit(keyHash, now, limits) {
      const [row] = await db()<{ ok: boolean }[]>`
        select public.waitlist_rate_hit(${keyHash}, ${now.toISOString()}::timestamptz,
          ${limits.perKey}, ${limits.total}) as ok`;
      return row.ok;
    },
    async signup(r, now) {
      return one(
        await db()<Recipient[]>`
          select id, email, locale, launch_news as "launchNews"
          from public.waitlist_signup(${r.email}, ${r.emailHmac}, ${r.platform}, ${r.locale},
            ${r.launchNews}, ${r.consentVersion}, ${r.tokenHash}, ${now.toISOString()}::timestamptz)`,
      );
    },
    async confirm(tokenHash, now) {
      return one(
        await db()<Recipient[]>`
          select id, email, locale, launch_news as "launchNews"
          from public.waitlist_confirm(${tokenHash}, ${now.toISOString()}::timestamptz)`,
      );
    },
    async mailed(id, kind, now) {
      const [row] = await db()<{ ok: boolean }[]>`
        select public.waitlist_mailed(${id}::uuid, ${kind}, ${now.toISOString()}::timestamptz) as ok`;
      return row.ok;
    },
    async unsubscribe(id, now) {
      const [row] = await db()<{ ok: boolean }[]>`
        select public.waitlist_unsubscribe(${id}::uuid, ${now.toISOString()}::timestamptz) as ok`;
      return row.ok;
    },
  };
}
