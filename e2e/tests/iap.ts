import { readFileSync } from 'node:fs';
import { expect } from './fixtures';
import { adminClient, apiAs, functionJson, functionsUrl } from './helpers';

// RevenueCat's side of a purchase against the local stack (docs/PURCHASES.md, "Testing locally"):
// events go to the real webhook with the local stand-in secret (scripts/iap-local-env.sh), and the
// buyer's claim goes where the app sends it.

const webhookAuth = (() => {
  const env = readFileSync(new URL('../../supabase/functions/.env', import.meta.url), 'utf8');
  const line = env.split('\n').find((l) => l.startsWith('REVENUECAT_WEBHOOK_AUTH='));
  if (!line) throw new Error('supabase/functions/.env has no REVENUECAT_WEBHOOK_AUTH: run scripts/iap-local-env.sh');
  return line.slice('REVENUECAT_WEBHOOK_AUTH='.length).replace(/^"|"$/g, '');
})();

export const yearlyId = 'com.hummlist.app.yearly';
const day = 86_400_000;

/**
 * POSTs a RevenueCat event of [type] for [transactionId], App User ID [appUserId]. Lifetime by
 * default; `productId: yearlyId` for the yearly plan, whose period ends `expiresInDays` from now
 * (365 by default). `extra` adds fields as RevenueCat sends them (cancel_reason, transferred_to).
 */
export async function rcEvent(
  type: string,
  appUserId: string,
  transactionId: string,
  {
    authorization = webhookAuth,
    id = crypto.randomUUID(),
    productId = 'com.hummlist.app.lifetime',
    expiresInDays = 365,
    extra = {},
  }: {
    authorization?: string;
    id?: string;
    productId?: string;
    expiresInDays?: number;
    extra?: Record<string, unknown>;
  } = {},
) {
  const now = Date.now();
  const yearly = productId.startsWith(yearlyId);
  const res = await fetch(`${functionsUrl}/purchases/revenuecat/webhook?forceFunctionRegion=eu-central-1`, {
    method: 'POST',
    headers: { authorization, 'content-type': 'application/json' },
    body: JSON.stringify({
      api_version: '1.0',
      event: {
        id,
        type,
        app_user_id: appUserId,
        original_app_user_id: appUserId,
        aliases: [appUserId],
        product_id: productId,
        entitlement_ids: ['premium'],
        transaction_id: transactionId,
        original_transaction_id: transactionId,
        environment: 'SANDBOX',
        store: 'APP_STORE',
        is_family_share: false,
        period_type: 'NORMAL',
        purchased_at_ms: now - 1000,
        expiration_at_ms: yearly ? now + expiresInDays * day : null,
        event_timestamp_ms: now,
        price_in_purchased_currency: yearly ? 9.99 : 29.99,
        currency: 'EUR',
        country_code: 'DE',
        ...(type === 'CANCELLATION' ? { cancel_reason: 'CUSTOMER_SUPPORT' } : {}),
        ...extra,
      },
    }),
  });
  return { status: res.status, body: await functionJson(res) };
}

/**
 * What the app sends right after RevenueCat's purchase sheet, as [email], for [householdId]: their
 * default household unless named (job 169b: the one shown when buying).
 */
export async function claim(email: string, transactionId: string, householdId?: string) {
  householdId ??= await householdOf(email);
  const api = await apiAs(email);
  const { data } = await api.auth.getSession();
  const res = await fetch(`${functionsUrl}/purchases/claim`, {
    method: 'POST',
    headers: { authorization: `Bearer ${data.session!.access_token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ store: 'apple', householdId, transactionId }),
  });
  return { status: res.status, body: await functionJson(res) };
}

/**
 * [email] buys Hummlist Lifetime for [household] (their default unless named): the claim, then
 * RevenueCat's webhook.
 */
export async function buy(email: string, transactionId: string, household?: string): Promise<string> {
  household ??= await householdOf(email);
  expect((await claim(email, transactionId, household)).status, 'the claim is accepted').toBe(200);
  const res = await rcEvent('NON_RENEWING_PURCHASE', household, transactionId);
  expect(res.status, JSON.stringify(res.body)).toBe(200);
  return res.body.status;
}

/** [email] subscribes to the yearly plan for their household: the claim, then INITIAL_PURCHASE. */
export async function subscribe(email: string, transactionId: string, expiresInDays = 365): Promise<string> {
  expect((await claim(email, transactionId)).status, 'the claim is accepted').toBe(200);
  const res = await rcEvent('INITIAL_PURCHASE', await householdOf(email), transactionId, {
    productId: yearlyId,
    expiresInDays,
  });
  expect(res.status, JSON.stringify(res.body)).toBe(200);
  return res.body.status;
}

/**
 * RevenueCat reports [transactionId] for [household] (else [email]'s default household) again: a
 * restore, a replay.
 */
export async function report(email: string, transactionId: string, household?: string): Promise<string> {
  return (await rcEvent('NON_RENEWING_PURCHASE', household ?? await householdOf(email), transactionId)).body.status;
}

/** [email]'s default household, read as old store builds read it (job 169b: the one row RLS shows). */
export async function householdOf(email: string): Promise<string> {
  const api = await apiAs(email);
  const { data: user } = await api.auth.getUser();
  const { data, error } = await api.from('household_members').select('household_id').eq('user_id', user.user!.id)
    .single();
  if (error) throw error;
  return data.household_id as string;
}

/**
 * Turns the server's archive switch on (job 47, H-70; seeded off): the service role's update,
 * as the Lead does it (NEEDS_LEAD "Job 47"). Only ever on, so parallel specs don't race.
 */
export async function archiveSwitchOn(): Promise<void> {
  const { error } = await adminClient().from('app_switches').update({ enabled: true }).eq('key', 'household_archive');
  if (error) throw error;
}
