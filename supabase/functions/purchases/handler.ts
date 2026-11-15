// The purchases function (docs/PURCHASES.md): RevenueCat tells it about Snacklist Premium purchases
// (yearly and Lifetime), a yearly plan's renewals, cancellations and expiry, and refunds; it
// unlocks premium for RevenueCat's App User ID (the buyer's user id, job 185; a household id from
// older builds), keeps the plan's state, or takes the unlock away. It never talks to Apple or
// Google itself.
//   GET  /purchases                       whether the webhook is configured (smoke checks)
//   POST /purchases/revenuecat/webhook    RevenueCat's webhook (Authorization:
//                                         REVENUECAT_WEBHOOK_AUTH, compared whole)
//   POST /purchases/revenuecat/deletions  deletes due RevenueCat customers (deletions.ts); the
//                                         daily workflow, with x-deletions-secret:
//                                         REVENUECAT_DELETIONS_SECRET (compared whole; 503 unset)
//   POST /purchases/revenuecat/reconcile  Ops: stores a customer's promotional premium as
//                                         RevenueCat has it now (body {"householdId"}: an App
//                                         User ID, scripts/iap/promotional.ts sends households),
//                                         with the same x-deletions-secret
//   POST /purchases/claim       the app, signed in (its own session, not a PAT or OAuth app): "I
//                               bought this transaction for this household" (H-55)
// Routes match exactly, after the gateway's /functions/v1 prefix.
//   POST /purchases/test/event  local stack only: a RevenueCat event, processed like the webhook's
// Refusals are logged by reason and event type only: never a transaction id, user or household.
import { AuthError } from '../_shared/auth.ts';
import { ranOutOfTime, rowBusy } from '../_shared/db.ts';
import { json, preflight } from '../_shared/http.ts';
import type { AppStore, PurchaseEvent } from '../_shared/purchases.ts';
import type { Subject } from '../_shared/telemetry.ts';
import { parseWebhook, sameSecret, signedBy, testEvent, type WebhookEvent } from './revenuecat.ts';
import type { Lifecycle } from './revenuecat.ts';
import type { Claim, LifecycleOutcome, PromotionalOutcome, Recorded, Revoked } from './store.ts';
import { RevenueCatUnavailable } from './promotional.ts';
import { type Refund, type Sale, type StorePurchase, webhookPath } from './types.ts';
import type { DeletionOutcome } from './deletions.ts';

/** The writes one event may make, all in the transaction that records its id. */
export interface Ledger {
  record(p: StorePurchase): Promise<Recorded>;
  lifecycle(c: Lifecycle): Promise<LifecycleOutcome>;
  revoke(r: Refund): Promise<Revoked | null>;
  reinstate(store: AppStore, transactionId: string): Promise<boolean>;
  /** Reads the customer's promotional premium from RevenueCat and stores it. */
  promotional(appUserId: string): Promise<PromotionalOutcome>;
}

export interface Deps {
  /** Null: not configured, the webhook answers 503. */
  webhook: { authorization: string; signingSecret: string | null } | null;
  /** Inside a local stack: /purchases/test/event is served. */
  local: boolean;
  region: string | null;
  /** Null: REVENUECAT_DELETIONS_SECRET is unset, the deletion route answers 503. */
  deletionsSecret: string | null;
  /** The app's own session; throws AuthError. */
  authenticate(req: Request): Promise<{ userId: string }>;
  /** Takes one claim from the user's allowance; false when it is used up. */
  takeCall(userId: string): Promise<boolean>;
  /**
   * Runs [work] in one transaction with recording [event]'s id: null when the id was recorded
   * before. A failure rolls the id back, so RevenueCat's retry runs it again.
   */
  once<T>(
    event: { id: string; type: string },
    work: (ledger: Ledger) => Promise<T>,
  ): Promise<T | null>;
  /**
   * purchase_claim for [householdId], the household the app bought for; throws AuthError when the
   * user was no member of it at the time of buying.
   */
  claim(
    userId: string,
    householdId: string,
    store: AppStore,
    transactionId: string,
  ): Promise<Claim>;
  /**
   * Stores [appUserId]'s promotional premium as RevenueCat has it now, outside any event. Null
   * without REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID: promotional events answer 503 (and
   * RevenueCat retries), the reconcile route 503.
   */
  reconcile: ((appUserId: string) => Promise<PromotionalOutcome>) | null;
  /** Null without REVENUECAT_SECRET_KEY and REVENUECAT_PROJECT_ID: the route skips. */
  deleteDueCustomers: (() => Promise<DeletionOutcome>) | null;
  /** Whom analytics events for [userId] go to: null unless their latest answer in the app was yes. */
  subject(userId: string): Promise<Subject | null>;
  event(name: PurchaseEvent, sale: Sale, subject: Subject): Promise<void>;
  report(error: unknown): void;
  now(): Date;
}

/** Larger than any RevenueCat event; anything bigger is not one. */
export const maxBodyBytes = 65_536;

/** An analytics event due once the event's transaction committed. */
interface Due {
  name: PurchaseEvent;
  sale: Sale;
  userId: string;
  internal: boolean;
}

/**
 * A lifecycle event for a transaction not recorded yet is answered 503 for this long after it
 * happened: its INITIAL_PURCHASE may still be on its way, and RevenueCat delivers it again later.
 */
export const lifecycleWaitMs = 2 * 3_600_000;

/** Thrown inside the event's transaction, so its id rolls back with it. */
class NotRecordedYet extends Error {}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** The routes, as the function sees its path (without the gateway's /functions/v1). */
export const routes = {
  status: '/purchases',
  webhook: webhookPath,
  deletions: '/purchases/revenuecat/deletions',
  reconcile: '/purchases/revenuecat/reconcile',
  claim: '/purchases/claim',
  testEvent: '/purchases/test/event',
} as const;

const log = (fields: Record<string, string | null>) =>
  console.log(JSON.stringify({ fn: 'purchases', ...fields }));

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const notConfigured = () => json({ error: 'not_configured' }, { status: 503 });
  const badRequest = () => json({ error: 'bad_request' }, { status: 400 });
  // RevenueCat's API failed: nothing was stored, the event id rolled back, RevenueCat retries.
  const unavailable = () => json({ error: 'revenuecat_unavailable' }, { status: 502 });
  const notRecordedYet = () => json({ error: 'not_recorded_yet' }, { status: 503 });

  async function send(due: Due | null) {
    if (!due) return;
    try {
      const subject = await deps.subject(due.userId);
      if (!subject) return;
      await deps.event(due.name, due.sale, {
        installId: subject.installId,
        householdId: due.sale.householdId ?? subject.householdId,
        // A sandbox purchase is never revenue, nor one in a granted household: internal (docs/ANALYTICS.md).
        internal: subject.internal === true || due.sale.environment === 'Sandbox' || due.internal,
      });
    } catch (e) {
      // Analytics never fails a purchase.
      deps.report(e);
    }
  }

  async function process(e: WebhookEvent): Promise<Response> {
    const { action } = e;
    // Never moves anything (H-56); the type is all that is logged.
    if (e.type === 'TRANSFER' || e.type === 'PRODUCT_CHANGE') log({ event: e.type });
    if (action.do === 'ignore' && action.refused) log({ event: e.type, refused: action.refused });
    // A promotional grant is read from RevenueCat's API; without the key we can't, so RevenueCat
    // delivers again once it is set.
    if (action.do === 'promotional' && !deps.reconcile) return notConfigured();
    let done;
    try {
      done = await apply(e);
    } catch (err) {
      if (err instanceof RevenueCatUnavailable) {
        log({ event: e.type, promotional: 'revenuecat_unavailable' });
        return unavailable();
      }
      if (err instanceof NotRecordedYet) {
        log({ event: e.type, lifecycle: 'not_recorded_yet' });
        return notRecordedYet();
      }
      throw err;
    }
    if (!done) return json({ status: 'duplicate' });
    await send(done.due);
    return json({ status: done.status });
  }

  function apply(e: WebhookEvent) {
    const { action } = e;
    return deps.once(
      e,
      async (ledger): Promise<{ status: string; due: Due | null }> => {
        switch (action.do) {
          case 'ignore':
            return { status: 'ignored', due: null };
          case 'record': {
            const p = action.purchase;
            const r = await ledger.record(p);
            if (r.outcome !== 'granted' && r.outcome !== 'restored') {
              log({ event: e.type, refused: r.outcome });
            }
            if (r.secondYearly) log({ event: e.type, flag: 'second_yearly' });
            const due = r.sendCompleted && r.buyer
              ? {
                name: 'purchase_completed' as const,
                sale: { ...p, householdId: r.householdId },
                userId: r.buyer,
                internal: r.internal,
              }
              : null;
            return { status: r.outcome, due };
          }
          case 'lifecycle': {
            const outcome = await ledger.lifecycle(action.change);
            if (
              outcome === 'unknown' &&
              deps.now().getTime() - action.change.eventAt.getTime() < lifecycleWaitMs
            ) {
              throw new NotRecordedYet();
            }
            if (outcome !== 'updated') log({ event: e.type, lifecycle: outcome });
            return { status: outcome, due: null };
          }
          case 'revoke': {
            const row = await ledger.revoke(action.refund);
            const due = row?.userId
              ? {
                name: 'purchase_refunded' as const,
                sale: row,
                userId: row.userId,
                internal: row.internal,
              }
              : null;
            return { status: row ? 'revoked' : 'unchanged', due };
          }
          case 'reinstate':
            return {
              status: await ledger.reinstate(action.store, action.transactionId)
                ? 'reinstated'
                : 'unchanged',
              due: null,
            };
          case 'promotional': {
            // No purchases row and no analytics event: a grant is no sale.
            const outcome = await ledger.promotional(action.appUserId);
            if (outcome === 'no_household' || outcome === 'no_user') {
              log({ event: e.type, refused: outcome });
            }
            return { status: outcome, due: null };
          }
        }
      },
    );
  }

  async function webhook(req: Request): Promise<Response> {
    const secrets = deps.webhook;
    if (!secrets) return notConfigured();
    if (!await sameSecret(req.headers.get('authorization') ?? '', secrets.authorization)) {
      return json({ error: 'invalid_token' }, { status: 401 });
    }
    if (Number(req.headers.get('content-length') ?? 0) > maxBodyBytes) return badRequest();
    const raw = new Uint8Array(await req.arrayBuffer());
    if (raw.length > maxBodyBytes) return badRequest();
    if (
      secrets.signingSecret &&
      !await signedBy(
        secrets.signingSecret,
        req.headers.get('x-revenuecat-webhook-signature'),
        raw,
        deps.now(),
      )
    ) {
      return json({ error: 'bad_signature' }, { status: 401 });
    }
    let body: unknown;
    try {
      body = JSON.parse(new TextDecoder().decode(raw));
    } catch {
      return badRequest();
    }
    const event = parseWebhook(body, deps.now());
    return event ? await process(event) : badRequest();
  }

  async function claimRoute(req: Request): Promise<Response> {
    let who: { userId: string };
    try {
      who = await deps.authenticate(req);
    } catch (e) {
      if (e instanceof AuthError) return json({ error: e.reason }, { status: e.status });
      throw e;
    }
    const b = await req.json().catch(() => null) as Record<string, unknown> | null;
    const store = b?.store === 'apple' || b?.store === 'google' ? b.store : null;
    const transactionId = typeof b?.transactionId === 'string' && b.transactionId.length > 0 &&
        b.transactionId.length <= 200
      ? b.transactionId
      : null;
    const householdId = typeof b?.householdId === 'string' && uuid.test(b.householdId)
      ? b.householdId
      : null;
    if (!store || !transactionId || !householdId) return badRequest();
    let c: Claim;
    try {
      if (!await deps.takeCall(who.userId)) return json({ error: 'rate_limited' }, { status: 429 });
      c = await deps.claim(who.userId, householdId, store, transactionId);
    } catch (e) {
      // No member of that household when buying.
      if (e instanceof AuthError) return json({ error: e.reason }, { status: e.status });
      // The account is being deleted, or the caller's earlier claims are still waiting.
      if (rowBusy(e) || ranOutOfTime(e)) return json({ error: 'busy' }, { status: 503 });
      throw e;
    }
    if (c.completed) {
      await send({
        name: 'purchase_completed',
        sale: c.completed,
        userId: who.userId,
        internal: c.completed.internal,
      });
    }
    return json({ status: c.status });
  }

  async function localEvent(req: Request): Promise<Response> {
    if (!deps.webhook) return notConfigured();
    const body = testEvent(await req.json().catch(() => null), deps.now());
    const event = body && parseWebhook(body, deps.now());
    return event ? await process(event) : badRequest();
  }

  async function deletions(req: Request): Promise<Response> {
    if (!deps.deletionsSecret) return notConfigured();
    if (!await sameSecret(req.headers.get('x-deletions-secret') ?? '', deps.deletionsSecret)) {
      return json({ error: 'invalid_token' }, { status: 401 });
    }
    if (!deps.deleteDueCustomers) return json({ status: 'not_configured' });
    const outcome = await deps.deleteDueCustomers();
    log({ deletions: JSON.stringify(outcome) });
    return json(outcome, { status: outcome.failed > 0 ? 502 : 200 });
  }

  async function reconcile(req: Request): Promise<Response> {
    if (!deps.deletionsSecret) return notConfigured();
    if (!await sameSecret(req.headers.get('x-deletions-secret') ?? '', deps.deletionsSecret)) {
      return json({ error: 'invalid_token' }, { status: 401 });
    }
    if (!deps.reconcile) return notConfigured();
    const b = await req.json().catch(() => null) as Record<string, unknown> | null;
    const householdId = typeof b?.householdId === 'string' && uuid.test(b.householdId)
      ? b.householdId
      : null;
    if (!householdId) return badRequest();
    try {
      const outcome = await deps.reconcile(householdId);
      log({ reconcile: outcome });
      return json({ status: outcome });
    } catch (err) {
      if (err instanceof RevenueCatUnavailable) return unavailable();
      throw err;
    }
  }

  return async (req) => {
    const pre = preflight(req);
    if (pre) return pre;
    log({ region: deps.region });
    const path = new URL(req.url).pathname.replace(/\/+$/, '').replace(
      /^\/functions\/v1(?=\/)/,
      '',
    );
    if (req.method === 'GET' && path === routes.status) {
      return json({ configured: deps.webhook !== null });
    }
    if (req.method === 'POST') {
      if (path === routes.webhook) return await webhook(req);
      if (path === routes.deletions) return await deletions(req);
      if (path === routes.reconcile) return await reconcile(req);
      if (path === routes.claim) return await claimRoute(req);
      if (path === routes.testEvent && deps.local) return await localEvent(req);
    }
    return json({ error: 'not_found' }, { status: 404 });
  };
}
