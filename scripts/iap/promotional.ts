// A household's free Snacklist Premium from RevenueCat promotional grants (docs/PURCHASES.md,
// "Free premium: RevenueCat promotional grants", and "Testers"). The grant lives in RevenueCat (its
// dashboard, Customer → Entitlements → Grant, or `grant` below); the purchases function stores it on
// RevenueCat's webhook. `status` reads RevenueCat's state; `reconcile --apply` asks the function to
// store it now (POST /purchases/revenuecat/reconcile), e.g. for a household granted before the
// webhook knew promotional grants, or after a missed delivery; `grant --apply` gives a tester's
// household premium until 2100-01-01 through API v2 grant_entitlement (only if it has no such grant
// yet, so a rerun changes nothing) and then reconciles.
//
//   deno run --allow-env --allow-net scripts/iap/promotional.ts status --household <uuid>
//   ... promotional.ts reconcile --household <uuid> [--apply]
//   ... promotional.ts grant --household <uuid> [--apply]
//
// Dry run by default. Needs REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID (API v2; read, and for
// grant --apply customer_information:customers:read_write), and for --apply
// REVENUECAT_DELETIONS_SECRET (the function's Ops secret, sent as x-deletions-secret) and
// SUPABASE_PROJECT_REF (default: the hosted project) or PURCHASES_URL (the local stack's
// http://127.0.0.1:54321/functions/v1/purchases). Prints no key, secret or token.
import {
  type Fetch,
  type RevenueCatKey,
  revenueCatTimeoutMs,
  within,
} from '../../supabase/functions/purchases/deletions.ts';
import {
  fetchPromotional,
  type PromotionalPremium,
  RevenueCatUnavailable,
} from '../../supabase/functions/purchases/promotional.ts';

export type Command = {
  action: 'status' | 'reconcile' | 'grant';
  household: string;
  apply: boolean;
};

/** The premium entitlement's id in RevenueCat project proj9cb4a72e (lookup key "premium"). */
export const premiumEntitlementId = 'entl654efcfce4';
/** A tester's grant ends here: RevenueCat's grants need an end; this one is "for good". */
export const testerGrantEnd = new Date('2100-01-01T00:00:00Z');

const usage = 'usage: promotional.ts status --household <uuid> | ' +
  'reconcile --household <uuid> [--apply] | grant --household <uuid> [--apply]';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function parseArgs(args: string[]): Command {
  const [action, ...rest] = args;
  if (action !== 'status' && action !== 'reconcile' && action !== 'grant') throw new Error(usage);
  let household: string | null = null;
  let apply = false;
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--apply' && action !== 'status') apply = true;
    else if (rest[i] === '--household' && rest[i + 1] !== undefined) household = rest[++i];
    else throw new Error(usage);
  }
  household = household?.toLowerCase() ?? null;
  if (!household || !uuid.test(household)) throw new Error('--household: a household id (uuid)');
  return { action, household, apply };
}

export function describe(p: PromotionalPremium): string {
  if (!p.active) return 'no promotional premium at RevenueCat';
  return p.expiresAt
    ? `promotional premium at RevenueCat until ${p.expiresAt.toISOString()}`
    : 'promotional premium at RevenueCat, without end';
}

/** The function's reconcile route for [env]. */
export function reconcileUrl(env: (k: string) => string | undefined): string {
  const local = env('PURCHASES_URL');
  if (local) return `${local.replace(/\/+$/, '')}/revenuecat/reconcile`;
  const ref = env('SUPABASE_PROJECT_REF') ?? 'jdwqrallbpdbshrdhenk';
  if (!/^[a-z0-9]{20}$/.test(ref)) throw new Error('SUPABASE_PROJECT_REF: a project ref');
  return `https://${ref}.supabase.co/functions/v1/purchases/revenuecat/reconcile` +
    '?forceFunctionRegion=eu-central-1';
}

/** Whether [p] already gives premium at least until [testerGrantEnd]: then `grant` does nothing. */
export function grantedForGood(p: PromotionalPremium): boolean {
  return p.active && (p.expiresAt === null || p.expiresAt >= testerGrantEnd);
}

/**
 * Grants the RevenueCat customer [appUserId] (a household's or an account's id) the premium
 * entitlement until [testerGrantEnd] (POST .../customers/{id}/actions/grant_entitlement). A customer
 * RevenueCat doesn't know yet (404: it never opened the purchase screen) is created first
 * (POST .../customers).
 * Throws [RevenueCatUnavailable] for a refusal, and when RevenueCat takes longer than [timeoutMs].
 */
export async function grantEntitlement(
  key: RevenueCatKey,
  appUserId: string,
  untimed: Fetch,
  timeoutMs = revenueCatTimeoutMs,
): Promise<void> {
  const timed = within(untimed, timeoutMs);
  const fetch: Fetch = (url, init) =>
    timed(url, init).catch(() => {
      throw new RevenueCatUnavailable(null);
    });
  const project = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(key.projectId)}`;
  const headers = {
    authorization: `Bearer ${key.secretKey}`,
    accept: 'application/json',
    'content-type': 'application/json',
  };
  const grant = () =>
    fetch(`${project}/customers/${encodeURIComponent(appUserId)}/actions/grant_entitlement`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        entitlement_id: premiumEntitlementId,
        expires_at: testerGrantEnd.getTime(),
      }),
    });
  let res = await grant();
  if (res.status === 404) {
    await res.body?.cancel();
    const created = await fetch(`${project}/customers`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ id: appUserId }),
    });
    await created.body?.cancel();
    if (created.status !== 201 && created.status !== 200 && created.status !== 409) {
      throw new RevenueCatUnavailable(created.status);
    }
    res = await grant();
  }
  await res.body?.cancel();
  if (res.status !== 201 && res.status !== 200) throw new RevenueCatUnavailable(res.status);
}

/**
 * Asks the purchases function at [url] to store [appUserId]'s promotional premium as RevenueCat has
 * it now. The body field is named householdId for history; it takes any App User ID.
 */
export async function reconcile(
  appUserId: string,
  to: { url: string; secret: string },
  fetch: Fetch = globalThis.fetch,
): Promise<{ status: number; body: string }> {
  const res = await fetch(to.url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-deletions-secret': to.secret },
    body: JSON.stringify({ householdId: appUserId }),
  });
  return { status: res.status, body: await res.text() };
}

export function required(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`set ${name}`);
  return v;
}

async function reconcileOrExit(household: string): Promise<void> {
  const url = reconcileUrl((k) => Deno.env.get(k));
  const { status, body } = await reconcile(household, {
    url,
    secret: required('REVENUECAT_DELETIONS_SECRET'),
  });
  console.log(`purchases function: HTTP ${status} ${body.slice(0, 200)}`);
  if (status !== 200) Deno.exit(1);
}

if (import.meta.main) {
  try {
    const command = parseArgs(Deno.args);
    const key = {
      secretKey: required('REVENUECAT_SECRET_KEY'),
      projectId: required('REVENUECAT_PROJECT_ID'),
    };
    const now = await fetchPromotional(key, command.household, fetch, new Date());
    console.log(describe(now));
    if (command.action === 'reconcile') {
      if (!command.apply) console.log('dry run: --apply asks the purchases function to store this');
      else await reconcileOrExit(command.household);
    } else if (command.action === 'grant') {
      if (grantedForGood(now)) {
        console.log(
          'already granted: nothing to do (reconcile --apply stores it if the app lacks it)',
        );
      } else if (!command.apply) {
        console.log(
          `dry run: --apply grants premium until ${testerGrantEnd.toISOString()}, then reconciles`,
        );
      } else {
        await grantEntitlement(key, command.household, fetch);
        console.log(describe(await fetchPromotional(key, command.household, fetch, new Date())));
        await reconcileOrExit(command.household);
      }
    }
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    Deno.exit(1);
  }
}
