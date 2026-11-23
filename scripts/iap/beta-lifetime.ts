// Lifetime Snacklist Premium for every account that exists before the public launch (job 371):
// a RevenueCat promotional grant of the premium entitlement to the account's App User ID, its
// auth.users id (docs/PURCHASES.md, "Per-user Premium"), then the purchases function's reconcile
// route, so the user_entitlements row (and the revenuecat_customers note that deletes the customer
// with the account) is stored now, not only when the webhook arrives. Per account: RevenueCat
// already grants for good and the row is stored: nothing; granted but not stored: reconcile;
// otherwise: grant until 2100-01-01 (API v2 grants need an end; the app treats 2100 as for good),
// then reconcile. A rerun skips what is done, so after a failure just run it again.
//
//   deno run --allow-env --allow-net scripts/iap/beta-lifetime.ts [--created-before <iso>] [--apply]
//
// Accounts: confirmed, not anonymous, not deleted, created before --created-before (ISO 8601 with
// Z or an offset), read through the Management API
// (SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF: default the hosted project). Dry run by default:
// with REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID it reads each account's RevenueCat state and
// counts the steps, without them it counts the accounts; without --created-before it counts up to
// the run's moment. --apply needs --created-before set to the public-launch cut-off, the moment the
// sale opens, fixed in advance (PAYWALL_RELEASE.md 5.3a); the privacy notice names it ("every
// confirmed account that existed before the public launch", Legal Review N-344, N-347). Every
// --apply run, the first one before the launch included, passes that same value; and both keys, and
// REVENUECAT_DELETIONS_SECRET (the function's Ops secret); PURCHASES_URL points reconcile at a local
// stack. Prints counts only: no key, secret, id or e-mail.
import { managementApi } from '../../supabase/deploy/migrate.ts';
import { type Fetch, within } from '../../supabase/functions/purchases/deletions.ts';
import {
  fetchPromotional,
  type PromotionalPremium,
  RevenueCatUnavailable,
} from '../../supabase/functions/purchases/promotional.ts';
import {
  grantedForGood,
  grantEntitlement,
  reconcile,
  reconcileUrl,
  required,
  testerGrantEnd,
} from './promotional.ts';

/** What one account needs, from RevenueCat's state and our stored row. */
export type Step = 'done' | 'reconcile' | 'grant';

export function stepFor(atRevenueCat: PromotionalPremium, stored: boolean): Step {
  if (!grantedForGood(atRevenueCat)) return 'grant';
  return stored ? 'done' : 'reconcile';
}

/** An account to give Premium. Never printed. */
export interface Account {
  id: string;
  /** A promotional user_entitlements row for good is stored. */
  stored: boolean;
}

/** Counts only: [done], [reconcile] and [grant] are the planned steps, the rest what happened. */
export interface Tally {
  accounts: number;
  done: number;
  reconcile: number;
  grant: number;
  granted: number;
  reconciled: number;
  failed: number;
}

export interface Deps {
  accounts(cutoff: Date): Promise<Account[]>;
  /** null: no RevenueCat keys; a dry run then only counts the accounts. */
  atRevenueCat: ((id: string) => Promise<PromotionalPremium>) | null;
  grant(id: string): Promise<void>;
  /** Whether the function answered 200 with the premium stored, and its HTTP status. */
  reconcile(id: string): Promise<{ status: number; stored: boolean }>;
  pause(ms: number): Promise<void>;
  log(line: string): void;
}

export interface Options {
  cutoff: Date;
  apply: boolean;
  /** Between accounts, to stay under RevenueCat's rate limit. */
  pauseMs: number;
}

export async function run(deps: Deps, opts: Options): Promise<Tally> {
  const tally: Tally = {
    accounts: 0,
    done: 0,
    reconcile: 0,
    grant: 0,
    granted: 0,
    reconciled: 0,
    failed: 0,
  };
  const accounts = await deps.accounts(opts.cutoff);
  tally.accounts = accounts.length;
  deps.log(selectionRule);
  deps.log(
    `accounts created before ${opts.cutoff.toISOString()} or using MCP or the API: ${accounts.length}`,
  );
  const read = deps.atRevenueCat;
  if (!read) {
    if (opts.apply) throw new Error('--apply needs RevenueCat');
    deps.log('RevenueCat not checked: set REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID');
    return tally;
  }
  for (const [i, account] of accounts.entries()) {
    if (i > 0) await deps.pause(opts.pauseMs);
    let step: Step;
    try {
      step = stepFor(await read(account.id), account.stored);
    } catch (e) {
      tally.failed++;
      deps.log(`read failed: ${failure(e)}`);
      continue;
    }
    tally[step]++;
    if (!opts.apply || step === 'done') continue;
    if (step === 'grant') {
      try {
        await deps.grant(account.id);
        tally.granted++;
      } catch (e) {
        tally.failed++;
        deps.log(`grant failed: ${failure(e)}`);
        continue;
      }
    }
    try {
      const r = await deps.reconcile(account.id);
      if (r.stored) tally.reconciled++;
      else {
        tally.failed++;
        deps.log(`reconcile failed: HTTP ${r.status}${r.status === 200 ? ', not stored' : ''}`);
      }
    } catch (e) {
      tally.failed++;
      deps.log(`reconcile failed: ${failure(e)}`);
    }
  }
  deps.log(
    `${opts.apply ? 'applied' : 'dry run'}: ${tally.done} done, ${tally.reconcile} to reconcile, ` +
      `${tally.grant} to grant; granted ${tally.granted}, reconciled ${tally.reconciled}, ` +
      `failed ${tally.failed}`,
  );
  return tally;
}

/** RevenueCatUnavailable's message is its status; anything else could carry a body or an id. */
function failure(e: unknown): string {
  if (e instanceof RevenueCatUnavailable) return e.message;
  if (e instanceof DOMException && e.name === 'TimeoutError') return 'timeout';
  return 'error';
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const usage =
  'usage: beta-lifetime.ts [--created-before <ISO 8601 with Z or offset>] [--apply, needs --created-before]';
const isoWithZone = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

export function parseArgs(args: string[], now: Date): { cutoff: Date; apply: boolean } {
  let cutoff: Date | undefined;
  let apply = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const value = args[i + 1];
    if (arg === '--apply') apply = true;
    else if (arg === '--created-before' && value !== undefined) {
      const d = new Date(value);
      if (!isoWithZone.test(value) || Number.isNaN(d.getTime())) {
        throw new Error('--created-before: an ISO 8601 time with Z or an offset');
      }
      cutoff = d;
      i++;
    } else throw new Error(usage);
  }
  if (apply && cutoff === undefined) {
    throw new Error(
      '--apply needs --created-before <the public-launch cut-off> (Legal Review N-347)',
    );
  }
  return { cutoff: cutoff ?? now, apply };
}

/** What the run selects, printed with every run (docs/DECISIONS.md "Job 419"). */
export const selectionRule =
  'selection: every confirmed, non-anonymous, non-deleted account created before the cut-off, ' +
  'plus every such account that used MCP or the API (a used token, an OAuth connection, or a ' +
  'counted request: personal_access_tokens.last_used_at, auth.sessions of an OAuth client, ' +
  'mcp_rate, account_days)';

/**
 * The accounts created before [cutoff] or that used MCP or the API, each with whether its
 * lifetime row is stored. Use is read from what the server keeps: a token's last_used_at (set by
 * every API and MCP request with a key), an OAuth connection (the only way a connector reaches
 * MCP), and the per-account counters (mcp_rate from job 336, account_days from job 419). An
 * account that used MCP or the API gets Lifetime whenever it was created: the lock is not on yet
 * (Legal Review, must-fix 17).
 */
export function accountsQuery(cutoff: Date): string {
  return `select u.id, exists (
  select 1 from public.user_entitlements e
  where e.user_id = u.id and e.kind = 'premium' and e.source = 'promotional'
    and (e.expires_at is null or e.expires_at >= '${testerGrantEnd.toISOString()}'::timestamptz)
) as stored
from auth.users u
where (u.created_at < '${cutoff.toISOString()}'::timestamptz
    or exists (select 1 from public.personal_access_tokens t
               where t.user_id = u.id and t.kind in ('pat', 'api') and t.last_used_at is not null)
    or exists (select 1 from auth.sessions s
               where s.user_id = u.id and s.oauth_client_id is not null)
    or exists (select 1 from public.mcp_rate r where r.user_id = u.id)
    or exists (select 1 from public.account_days d where d.user_id = u.id))
  and u.is_anonymous is not true
  and u.deleted_at is null
  and u.confirmed_at is not null
order by u.created_at`;
}

export function parseAccounts(rows: unknown[]): Account[] {
  return rows.map((row) => {
    const r = row as { id?: unknown; stored?: unknown } | null;
    if (typeof r?.id !== 'string' || !uuid.test(r.id) || typeof r.stored !== 'boolean') {
      throw new Error('accounts: a row without a user id or stored flag');
    }
    return { id: r.id, stored: r.stored };
  });
}

/** The reconcile route's outcomes that leave the promotional premium stored (store.ts). */
const storedOutcomes = new Set(['granted', 'updated', 'unchanged']);

export function reconciled(status: number, body: string): { status: number; stored: boolean } {
  let outcome: unknown = null;
  try {
    outcome = (JSON.parse(body) as { status?: unknown } | null)?.status;
  } catch {
    outcome = null;
  }
  return { status, stored: status === 200 && storedOutcomes.has(String(outcome)) };
}

const pauseMs = 500;
const reconcileTimeoutMs = 30_000;

function revenueCatKey(): { secretKey: string; projectId: string } | null {
  const secretKey = Deno.env.get('REVENUECAT_SECRET_KEY');
  const projectId = Deno.env.get('REVENUECAT_PROJECT_ID');
  if (!secretKey && !projectId) return null;
  if (!secretKey || !projectId) {
    throw new Error('set both REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID, or neither');
  }
  return { secretKey, projectId };
}

if (import.meta.main) {
  try {
    const opts = parseArgs(Deno.args, new Date());
    const token = required('SUPABASE_ACCESS_TOKEN');
    const ref = Deno.env.get('SUPABASE_PROJECT_REF') ?? 'jdwqrallbpdbshrdhenk';
    if (!/^[a-z0-9]{20}$/.test(ref)) throw new Error('SUPABASE_PROJECT_REF: a project ref');
    const key = opts.apply
      ? {
        secretKey: required('REVENUECAT_SECRET_KEY'),
        projectId: required('REVENUECAT_PROJECT_ID'),
      }
      : revenueCatKey();
    const to = opts.apply
      ? {
        url: reconcileUrl((k) => Deno.env.get(k)),
        secret: required('REVENUECAT_DELETIONS_SECRET'),
      }
      : null;
    const query = managementApi(ref, token);
    const timedFetch: Fetch = within(fetch, reconcileTimeoutMs);
    const tally = await run({
      accounts: async (cutoff) => {
        const rows = await query(accountsQuery(cutoff)).catch((e: unknown) => {
          const status = /^Management API (\d+)/.exec(e instanceof Error ? e.message : '')?.[1];
          throw new Error(`accounts: Management API ${status ?? 'unreachable'}`);
        });
        return parseAccounts(rows);
      },
      atRevenueCat: key && ((id) => fetchPromotional(key, id, fetch, new Date())),
      grant: (id) => {
        if (!key) throw new Error('--apply needs RevenueCat');
        return grantEntitlement(key, id, fetch);
      },
      reconcile: async (id) => {
        if (!to) throw new Error('--apply needs REVENUECAT_DELETIONS_SECRET');
        const { status, body } = await reconcile(id, to, timedFetch);
        return reconciled(status, body);
      },
      pause: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
      log: (line) => console.log(line),
    }, { ...opts, pauseMs });
    if (tally.failed > 0) Deno.exit(1);
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    Deno.exit(1);
  }
}
