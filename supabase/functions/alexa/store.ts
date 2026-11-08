// The alexa function's database work. Items are read and written as the linked user under RLS
// (asUser); the link map, the rate limit and the analytics subject use the service connection
// through functions in migration 20261030140000_alexa.sql that clients cannot call.
import { sha256Hex } from '../_shared/auth.ts';
import { CONSENT_TEXT_VERSION } from '../_shared/consent_version.ts';
import type { Sql, Tx } from '../_shared/db.ts';
import { listItems as mcpListItems } from '../_shared/list.ts';
import type { Spoken } from './speech.ts';

/** Alexa's user id is stored hashed (alexa_links.alexa_user_hash). */
export const alexaUserHash = (alexaUserId: string) => sha256Hex(alexaUserId);

export async function remember(
  sql: Sql,
  alexaUserId: string,
  link: { userId: string; sessionId: string },
  relinked: boolean,
): Promise<number> {
  const [row] = await sql<{ revoked: number }[]>`
    select public.alexa_remember(
      ${await alexaUserHash(alexaUserId)}, ${link.userId}::uuid, ${link.sessionId}::uuid,
      ${relinked}) as revoked`;
  return row.revoked;
}

export async function revoke(sql: Sql, alexaUserId: string): Promise<number> {
  const [row] = await sql<{ revoked: number }[]>`
    select public.alexa_revoke(${await alexaUserHash(alexaUserId)}) as revoked`;
  return row.revoked;
}

/** Items a minute, per user, over Alexa (PM: about 30). */
export const addsPerMinute = 30;

export async function takeAdds(sql: Sql, userId: string, count: number): Promise<boolean> {
  const [row] = await sql<{ ok: boolean }[]>`
    select public.alexa_take_adds(${userId}::uuid, ${count}, ${addsPerMinute}) as ok`;
  return row.ok;
}

/** The household's open items in the app's aisle order (the MCP list_items query). */
export async function openItems(tx: Tx, householdId: string): Promise<Spoken[]> {
  return (await mcpListItems(tx, householdId, {})).items;
}

/**
 * Who an analytics event for [userId] goes to, or null when their latest answer was not a yes to
 * the current consent text ([CONSENT_TEXT_VERSION]): a yes under an older text, or one an app
 * build before 2026-11-01 recorded without a version, is no decision.
 */
export interface AnalyticsSubject {
  installId: string;
  internal: boolean;
  householdId: string;
  role: 'owner' | 'member';
  householdSize: number;
}

export async function analyticsSubject(sql: Sql, userId: string): Promise<AnalyticsSubject | null> {
  const [row] = await sql<
    {
      install_id: string;
      consent: boolean;
      consent_text_version: string | null;
      internal: boolean;
      household_id: string | null;
      role: 'owner' | 'member' | null;
      household_size: number;
    }[]
  >`
    select a.install_id, a.consent, a.consent_text_version, a.internal, m.household_id,
           case when m.role = 'owner' then 'owner' when m.role is not null then 'member' end as role,
           (select count(*)::int from public.household_members o
            where o.household_id = m.household_id) as household_size
    from public.analytics_consents a
    left join public.household_members m on m.user_id = a.user_id and m.is_default
    where a.user_id = ${userId}::uuid
    order by a.decided_at desc, a.install_id
    limit 1`;
  if (!row?.consent || row.consent_text_version !== CONSENT_TEXT_VERSION) return null;
  if (!row.household_id || !row.role) return null;
  return {
    installId: row.install_id,
    internal: row.internal,
    householdId: row.household_id,
    role: row.role,
    householdSize: row.household_size,
  };
}
