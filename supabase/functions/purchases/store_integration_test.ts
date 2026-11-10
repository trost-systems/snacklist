// Job 43: the purchases function's production wiring (deps.ts) against a database with the repo's
// migrations, driven by RevenueCat-shaped events: a purchase unlocks the household RevenueCat
// names, the partner reads the unlock but not who paid, the buyer's claim sends one
// purchase_completed, a duplicate delivery and a transfer to another household change nothing, a
// refund takes the unlock away and its reversal gives it back, a tombstoned transaction never
// binds, and the claim's rate limit holds. The session check is the shared auth.ts
// (auth_test.ts); here a resolver stands in for it. The db gate sets FG_DB_TEST=1 and
// SUPABASE_DB_URL; without them this is skipped.
import { assertEquals, assertRejects } from '@std/assert';
import postgres from 'postgres';
import { CONSENT_TEXT_VERSION } from '../_shared/consent_version.ts';
import { asUser } from '../_shared/db.ts';
import { telemetryFor } from '../_shared/telemetry.ts';
import { productionDeps } from './deps.ts';
import { createHandler } from './handler.ts';
import { hmacHex, testEvent } from './revenuecat.ts';
import { callsPerMinute } from './store.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const admin = () => postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 1, prepare: false });
const AUTH = 'Bearer integration-webhook';
const TOMBSTONE_KEY = 'integration-tombstone-key';

interface Member {
  userId: string;
  householdId: string;
}

/** Peter and Lea in one household, Max in another, with Peter's analytics yes; removed after. */
async function withHouseholds(
  work: (sql: postgres.Sql, peter: Member, lea: Member, max: Member) => Promise<void>,
) {
  const sql = admin();
  const ids = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  const households: string[] = [];
  try {
    for (const id of ids) {
      await sql`insert into auth.users (id, email) values (${id}, ${`${id}@fg-test.invalid`})`;
    }
    const household = async (userId: string) =>
      await asUser(userId, async (tx) => {
        const [h] = await tx<{ id: string }[]>`select id from public.create_household('Test')`;
        return h.id;
      });
    const home = await household(ids[0]);
    const other = await household(ids[2]);
    households.push(home, other);
    const code = await asUser(ids[0], async (tx) => {
      const [i] = await tx<
        { code: string }[]
      >`select code from public.create_invite(${home}::uuid)`;
      await tx`select public.record_analytics_consent(${crypto.randomUUID()}::uuid, true, false, true, ${CONSENT_TEXT_VERSION})`;
      return i.code;
    });
    const joined = await asUser(
      ids[1],
      (tx) => tx<{ id: string }[]>`select public.join_household(${code}) as id`,
    );
    assertEquals(joined[0].id, home);
    await work(
      sql,
      { userId: ids[0], householdId: home },
      { userId: ids[1], householdId: home },
      { userId: ids[2], householdId: other },
    );
  } finally {
    await sql`delete from public.purchases where bound_household = any(${households}::uuid[])`;
    await sql`delete from public.households where id = any(${households}::uuid[])`;
    await sql`delete from public.revenuecat_deletions where app_user_id = any(${households}::uuid[])`;
    await sql`delete from auth.users where id = any(${ids}::uuid[])`;
    await sql.end();
  }
}

Deno.test({
  name: 'RevenueCat events unlock the household they name, and only that one',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withHouseholds(async (sql, peter, lea, max) => {
      const telemetry = telemetryFor('purchases', {
        get: (k) =>
          ({
            POSTHOG_PROJECT_API_KEY: 'phc_testprojectkey0123456789',
            POSTHOG_HOST: 'https://eu.i.posthog.com',
          })[k],
      });
      let caller: Member = peter;
      const deps = productionDeps(
        {
          webhook: { authorization: AUTH, signingSecret: null, tombstoneKey: TOMBSTONE_KEY },
          local: true,
          region: null,
          revenueCat: null,
          deletionsSecret: null,
        },
        telemetry,
        { authenticate: () => Promise.resolve(caller) },
      );
      const handler = createHandler(deps);
      const post = async (path: string, body: unknown, authorization = AUTH) => {
        const res = await handler(
          new Request(`http://local/functions/v1/purchases${path}`, {
            method: 'POST',
            headers: { authorization },
            body: JSON.stringify(body),
          }),
        );
        return { status: res.status, body: await res.json() };
      };
      const eventIds: string[] = [];
      const tx = `43${Date.now()}`;
      const tombstoned = `${tx}9`;
      const event = (type: string, appUserId: string, transactionId = tx) => {
        const e = testEvent({ type, appUserId, transactionId }, new Date())!;
        eventIds.push((e.event as { id: string }).id);
        return e;
      };
      const deliver = async (type: string, appUserId: string, transactionId = tx) =>
        (await post('/revenuecat/webhook', event(type, appUserId, transactionId))).body;
      const unlocks = (who: Member) =>
        asUser(
          who.userId,
          (t) => t<{ household_id: string }[]>`select household_id from public.entitlements`,
        )
          .then((rows) => rows.map((r) => r.household_id));
      const queued = () => telemetry.queued.map((e) => e.event);

      try {
        const bought = event('NON_RENEWING_PURCHASE', peter.householdId);
        assertEquals((await post('/revenuecat/webhook', bought)).body, { status: 'granted' });
        assertEquals((await post('/revenuecat/webhook', bought)).body, { status: 'duplicate' });
        assertEquals(await unlocks(lea), [peter.householdId]);
        // H-55: the partner sees the unlock, not who paid.
        await assertRejects(() =>
          asUser(lea.userId, (t) => t`select granted_by from public.entitlements`)
        );
        assertEquals(await unlocks(max), []);
        assertEquals(queued(), []);

        // The buyer's claim, after the webhook: purchase_completed, once.
        assertEquals(
          (await post('/claim', {
            store: 'apple',
            householdId: peter.householdId,
            transactionId: tx,
          }, 'Bearer s')).body,
          {
            status: 'recorded',
          },
        );
        assertEquals(
          (await post('/claim', {
            store: 'apple',
            householdId: peter.householdId,
            transactionId: tx,
          }, 'Bearer s')).body,
          {
            status: 'recorded',
          },
        );
        // Max was never in Peter's household: the claim for it records nothing.
        caller = max;
        assertEquals(
          (await post('/claim', {
            store: 'apple',
            householdId: peter.householdId,
            transactionId: tx,
          }, 'Bearer s'))
            .status,
          403,
        );
        caller = lea;
        assertEquals(
          (await post('/claim', {
            store: 'apple',
            householdId: peter.householdId,
            transactionId: tx,
          }, 'Bearer s')).body,
          {
            status: 'taken',
          },
        );
        assertEquals(queued(), ['purchase_completed']);
        const completed = telemetry.queued[0].properties as Record<string, unknown>;
        assertEquals(completed.premium_source, 'lifetime');
        assertEquals(
          [completed.is_internal, completed.price, completed.household_id],
          [true, 29.99, peter.householdId],
        );

        // H-56: a restore or transfer into another household binds nothing there.
        assertEquals(await deliver('NON_RENEWING_PURCHASE', max.householdId), {
          status: 'used_elsewhere',
        });
        assertEquals(await deliver('TRANSFER', max.householdId), { status: 'ignored' });
        assertEquals(await unlocks(max), []);
        assertEquals(await deliver('NON_RENEWING_PURCHASE', crypto.randomUUID(), `${tx}1`), {
          status: 'no_household',
        });

        assertEquals(await deliver('CANCELLATION', peter.householdId), { status: 'revoked' });
        assertEquals(await deliver('CANCELLATION', peter.householdId), { status: 'unchanged' });
        assertEquals(await unlocks(lea), []);
        assertEquals(queued(), ['purchase_completed', 'purchase_refunded']);
        assertEquals(await deliver('REFUND_REVERSED', peter.householdId), {
          status: 'reinstated',
        });
        assertEquals(await unlocks(lea), [peter.householdId]);

        // The local route runs the same path.
        assertEquals(
          (await post('/test/event', { appUserId: lea.householdId, transactionId: tx }, '')).body,
          { status: 'restored' },
        );

        await sql`insert into public.purchase_tombstones (transaction_hmac)
                  values (${await hmacHex(TOMBSTONE_KEY, tombstoned)})`;
        assertEquals(await deliver('NON_RENEWING_PURCHASE', peter.householdId, tombstoned), {
          status: 'tombstoned',
        });
        const [row] = await sql<{ transaction_hmac: string }[]>`
          select transaction_hmac from public.purchases where transaction_id = ${tx}`;
        assertEquals(row.transaction_hmac, await hmacHex(TOMBSTONE_KEY, tx));
        assertEquals(
          (await sql`select from public.revenuecat_events where id = any(${eventIds})`).length,
          eventIds.length,
        );

        for (let i = 0; i < callsPerMinute; i++) await deps.takeCall(lea.userId);
        assertEquals(
          (await post('/claim', {
            store: 'apple',
            householdId: peter.householdId,
            transactionId: tx,
          }, 'Bearer s')).status,
          429,
        );
      } finally {
        await sql`delete from public.purchase_tombstones
                  where transaction_hmac = ${await hmacHex(TOMBSTONE_KEY, tombstoned)}`;
        await sql`delete from public.revenuecat_events where id = any(${eventIds})`;
      }
    });
  },
});

Deno.test({
  name: "A yearly plan's lifecycle: renewals, cancellations, billing issues and expiry, in order",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withHouseholds(async (sql, peter, lea, max) => {
      const telemetry = telemetryFor('purchases', { get: () => undefined });
      let caller: Member = peter;
      const handler = createHandler(productionDeps(
        {
          webhook: { authorization: AUTH, signingSecret: null, tombstoneKey: TOMBSTONE_KEY },
          local: true,
          region: null,
          revenueCat: null,
          deletionsSecret: null,
        },
        telemetry,
        { authenticate: () => Promise.resolve(caller) },
      ));
      const eventIds: string[] = [];
      const tx = `49${Date.now()}`;
      const yearlyId = 'com.snacklist.app.yearly';
      const deliver = async (
        type: string,
        more: Record<string, unknown> = {},
        appUserId = peter.householdId,
      ) => {
        const e = testEvent(
          { type, appUserId, transactionId: tx, productId: yearlyId, ...more },
          new Date(),
        )!;
        eventIds.push((e.event as { id: string }).id);
        const res = await handler(
          new Request('http://local/functions/v1/purchases/revenuecat/webhook', {
            method: 'POST',
            headers: { authorization: AUTH },
            body: JSON.stringify(e),
          }),
        );
        return (await res.json()).status;
      };
      const premium = async (household: string) => {
        const [r] = await sql<{ source: string | null; expires_at: Date | null; has: boolean }[]>`
          select p.source, p.expires_at, public.household_has_premium(${household}::uuid) as has
          from (select 1) one left join public.household_premium(${household}::uuid) p on true`;
        return r;
      };
      const days = (d: Date | null) =>
        d === null ? null : Math.round((d.getTime() - Date.now()) / 86_400_000);
      const memberRows = (who: Member) =>
        asUser(
          who.userId,
          (t) =>
            t<{ premium_source: string; auto_renew: boolean | null; expires_at: Date | null }[]>`
              select premium_source, auto_renew, expires_at from public.entitlements`,
        );
      const mine = (who: Member) =>
        asUser(who.userId, async (t) => {
          const [r] = await t<
            { p: Record<string, unknown> }[]
          >`select public.my_yearly_plan() as p`;
          return r.p;
        });

      try {
        assertEquals(await deliver('INITIAL_PURCHASE'), 'granted');
        let p = await premium(peter.householdId);
        assertEquals([p.source, days(p.expires_at), p.has], ['yearly', 365, true]);
        // The partner reads source, end and renewal; not who pays (H-55).
        assertEquals(
          (await memberRows(lea)).map((r) => [r.premium_source, r.auto_renew, days(r.expires_at)]),
          [['yearly', true, 365]],
        );
        await assertRejects(() =>
          asUser(lea.userId, (t) => t`select granted_by from public.entitlements`)
        );
        // The buyer claims it; only they are the subscriber.
        assertEquals(
          (await (await handler(
            new Request('http://local/functions/v1/purchases/claim', {
              method: 'POST',
              headers: { authorization: 'Bearer s' },
              body: JSON.stringify({
                store: 'apple',
                householdId: peter.householdId,
                transactionId: tx,
              }),
            }),
          )).json()).status,
          'recorded',
        );
        assertEquals((await mine(peter)).subscriber, true);
        assertEquals((await mine(lea)).subscriber, false);

        // UNSUBSCRIBE: auto-renew off, premium stays until the end (H-81).
        assertEquals(await deliver('CANCELLATION', { cancelReason: 'UNSUBSCRIBE' }), 'updated');
        p = await premium(peter.householdId);
        assertEquals([p.source, days(p.expires_at)], ['yearly', 365]);
        assertEquals((await memberRows(lea))[0].auto_renew, false);
        assertEquals(await deliver('UNCANCELLATION'), 'updated');
        assertEquals((await memberRows(lea))[0].auto_renew, true);

        // Out of order: an older EXPIRATION after a newer RENEWAL changes nothing.
        assertEquals(await deliver('RENEWAL', { expiresInDays: 730 }), 'restored');
        assertEquals(
          await deliver('EXPIRATION', { expiresInDays: -1, eventAgoMs: 3_600_000 }),
          'stale',
        );
        p = await premium(peter.householdId);
        assertEquals([p.source, days(p.expires_at)], ['yearly', 730]);

        // A billing issue keeps premium through the grace period, only the subscriber is told.
        assertEquals(
          await deliver('BILLING_ISSUE', { expiresInDays: 0, graceDays: 14 }),
          'updated',
        );
        p = await premium(peter.householdId);
        assertEquals(days(p.expires_at), 14);
        assertEquals([(await mine(peter)).billing_issue, (await mine(lea)).billing_issue], [
          true,
          false,
        ]);
        // RevenueCat's CANCELLATION (BILLING_ERROR) next to it has the period's end only: the grace
        // period stays.
        assertEquals(
          await deliver('CANCELLATION', { cancelReason: 'BILLING_ERROR', expiresInDays: 0 }),
          'updated',
        );
        p = await premium(peter.householdId);
        assertEquals([p.has, days(p.expires_at)], [true, 14]);
        // Without a grace period it ends with the period.
        assertEquals(await deliver('BILLING_ISSUE', { expiresInDays: 0 }), 'updated');
        assertEquals((await premium(peter.householdId)).has, false);
        // A late RENEWAL (account hold recovered) brings it back.
        assertEquals(await deliver('RENEWAL', { expiresInDays: 365 }), 'restored');
        assertEquals((await premium(peter.householdId)).has, true);
        assertEquals((await mine(peter)).billing_issue, false);

        // TRANSFER and a restore into another household move nothing (H-56).
        assertEquals(await deliver('TRANSFER', { transferTo: max.householdId }), 'ignored');
        // A RENEWAL under another App User ID still renews the plan where it is bound.
        assertEquals(
          await deliver('RENEWAL', { expiresInDays: 500 }, max.householdId),
          'used_elsewhere',
        );
        assertEquals((await premium(max.householdId)).has, false);
        p = await premium(peter.householdId);
        assertEquals([p.has, days(p.expires_at)], [true, 500]);

        // EXPIRATION ends it at read time; the row, the household and its list stay.
        await sql`insert into public.items (household_id, name) values (${peter.householdId}, 'Milch')`;
        assertEquals(await deliver('EXPIRATION', { expiresInDays: -1 }), 'updated');
        assertEquals((await premium(peter.householdId)).has, false);
        assertEquals((await memberRows(lea)).length, 1);
        assertEquals(
          (await sql`select from public.items where household_id = ${peter.householdId}`).length,
          1,
        );
        assertEquals((await mine(peter)).subscriber, false);

        // Lifetime bought while yearly was active wins; yearly's end no longer matters.
        assertEquals(await deliver('RENEWAL', { expiresInDays: 30 }), 'restored');
        const lifetime = testEvent(
          { appUserId: peter.householdId, transactionId: `${tx}L` },
          new Date(),
        )!;
        eventIds.push((lifetime.event as { id: string }).id);
        await handler(
          new Request('http://local/functions/v1/purchases/revenuecat/webhook', {
            method: 'POST',
            headers: { authorization: AUTH },
            body: JSON.stringify(lifetime),
          }),
        );
        p = await premium(peter.householdId);
        assertEquals([p.source, p.expires_at], ['lifetime', null]);
        assertEquals(await deliver('EXPIRATION', { expiresInDays: -1 }), 'updated');
        assertEquals((await premium(peter.householdId)).source, 'lifetime');

        // An event for a transaction never seen writes nothing. A recent one is refused with its id
        // unstored, so RevenueCat delivers it again once the purchase may be recorded.
        const unknown = async (eventAgoMs: number) => {
          const e = testEvent(
            {
              type: 'EXPIRATION',
              appUserId: max.householdId,
              transactionId: `${tx}X`,
              productId: yearlyId,
              eventAgoMs,
            },
            new Date(),
          )!;
          const id = (e.event as { id: string }).id;
          eventIds.push(id);
          const res = await handler(
            new Request('http://local/functions/v1/purchases/revenuecat/webhook', {
              method: 'POST',
              headers: { authorization: AUTH },
              body: JSON.stringify(e),
            }),
          );
          const stored = await sql`select from public.revenuecat_events where id = ${id}`;
          return [res.status, (await res.json()).status ?? null, stored.length];
        };
        assertEquals(await unknown(60_000), [503, null, 0]);
        assertEquals(await unknown(3 * 3_600_000), [200, 'unknown', 1]);
        assertEquals(
          (await sql`select from public.purchases where transaction_id = ${`${tx}X`}`).length,
          0,
        );
        caller = lea;
      } finally {
        await sql`delete from public.revenuecat_events where id = any(${eventIds})`;
      }
    });
  },
});

Deno.test({
  name: 'A tombstoned yearly transaction never binds again; a second yearly plan stays its own row',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withHouseholds(async (sql, peter) => {
      const handler = createHandler(productionDeps(
        {
          webhook: { authorization: AUTH, signingSecret: null, tombstoneKey: TOMBSTONE_KEY },
          local: true,
          region: null,
          revenueCat: null,
          deletionsSecret: null,
        },
        telemetryFor('purchases', { get: () => undefined }),
      ));
      const tx = `49t${Date.now()}`;
      const eventIds: string[] = [];
      const deliver = async (transactionId: string, expiresInDays: number) => {
        const e = testEvent({
          appUserId: peter.householdId,
          transactionId,
          productId: 'com.snacklist.app.yearly:yearly',
          expiresInDays,
        }, new Date())!;
        eventIds.push((e.event as { id: string }).id);
        const res = await handler(
          new Request('http://local/functions/v1/purchases/revenuecat/webhook', {
            method: 'POST',
            headers: { authorization: AUTH },
            body: JSON.stringify(e),
          }),
        );
        return (await res.json()).status;
      };
      try {
        await sql`insert into public.purchase_tombstones (transaction_hmac)
                  values (${await hmacHex(TOMBSTONE_KEY, tx)})`;
        assertEquals(await deliver(tx, 365), 'tombstoned');
        assertEquals(await deliver(`${tx}a`, 100), 'granted');
        assertEquals(await deliver(`${tx}b`, 300), 'granted');
        const rows = await sql<{ expires_at: Date; store: string; product_id: string }[]>`
          select expires_at, store, product_id from public.purchases
          where bound_household = ${peter.householdId} order by expires_at`;
        assertEquals(rows.map((r) => [r.store, r.product_id]), [
          ['google', 'com.snacklist.app.yearly'],
          ['google', 'com.snacklist.app.yearly'],
        ]);
        const [p] = await sql<{ expires_at: Date }[]>`
          select expires_at from public.household_premium(${peter.householdId}::uuid)`;
        assertEquals(p.expires_at.getTime(), rows[1].expires_at.getTime());
      } finally {
        await sql`delete from public.purchase_tombstones
                  where transaction_hmac = ${await hmacHex(TOMBSTONE_KEY, tx)}`;
        await sql`delete from public.revenuecat_events where id = any(${eventIds})`;
      }
    });
  },
});

Deno.test({
  name: "A promotional grant unlocks the household while RevenueCat's API says it runs",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withHouseholds(async (sql, peter, lea, max) => {
      // RevenueCat's API, as GET /v2/projects/{project}/customers/{id}/subscriptions answers.
      let grant: { ends_at: number | null } | null = { ends_at: Date.now() + 30 * 86_400_000 };
      const asked: string[] = [];
      const fetch = (url: string) => {
        asked.push(url);
        const items = grant
          ? [{
            store: 'promotional',
            gives_access: true,
            ends_at: grant.ends_at,
            entitlements: { items: [{ id: 'entl1', lookup_key: 'premium' }] },
          }]
          : [];
        return Promise.resolve(Response.json({ items, next_page: null }));
      };
      const handler = createHandler(productionDeps(
        {
          webhook: { authorization: AUTH, signingSecret: null, tombstoneKey: TOMBSTONE_KEY },
          local: true,
          region: null,
          revenueCat: { secretKey: 'sk_integration', projectId: 'projtest' },
          deletionsSecret: 'integration-ops',
        },
        telemetryFor('purchases', { get: () => undefined }),
        { fetch },
      ));
      const eventIds: string[] = [];
      const deliver = async (type: string) => {
        const id = crypto.randomUUID();
        eventIds.push(id);
        const res = await handler(
          new Request('http://local/functions/v1/purchases/revenuecat/webhook', {
            method: 'POST',
            headers: { authorization: AUTH },
            body: JSON.stringify({
              api_version: '1.0',
              event: {
                id,
                type,
                app_user_id: peter.householdId,
                store: 'PROMOTIONAL',
                environment: 'PRODUCTION',
                entitlement_ids: ['premium'],
                period_type: 'PROMOTIONAL',
                event_timestamp_ms: Date.now(),
              },
            }),
          }),
        );
        return (await res.json()).status;
      };
      const premium = async (household: string) =>
        (await sql<{ p: boolean }[]>`select public.household_has_premium(${household}::uuid) as p`)[
          0
        ]
          .p;
      try {
        assertEquals(await deliver('NON_RENEWING_PURCHASE'), 'granted');
        assertEquals(asked, [
          `https://api.revenuecat.com/v2/projects/projtest/customers/${peter.householdId}/subscriptions?limit=100`,
        ]);
        assertEquals(await premium(peter.householdId), true);
        assertEquals(await premium(max.householdId), false);
        assertEquals(
          (await sql`select 1 from public.purchases where bound_household = ${peter.householdId}`)
            .length,
          0,
        );
        // Lea, a member, reads it through RLS.
        const rows = await asUser(
          lea.userId,
          (tx) => tx<{ premium_source: string }[]>`select premium_source from public.entitlements`,
        );
        assertEquals(rows.map((r) => r.premium_source), ['promotional']);
        // Revoked in RevenueCat: the next event, whatever its type, ends it.
        grant = null;
        assertEquals(await deliver('CANCELLATION'), 'removed');
        assertEquals(await premium(peter.householdId), false);
        // Ops' reconcile reads the same way.
        grant = { ends_at: null };
        const res = await handler(
          new Request('http://local/functions/v1/purchases/revenuecat/reconcile', {
            method: 'POST',
            headers: { 'x-deletions-secret': 'integration-ops' },
            body: JSON.stringify({ householdId: peter.householdId }),
          }),
        );
        assertEquals(await res.json(), { status: 'granted' });
        assertEquals(await premium(peter.householdId), true);
      } finally {
        await sql`delete from public.revenuecat_events where id = any(${eventIds})`;
      }
    });
  },
});
