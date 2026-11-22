import { assertEquals } from '@std/assert';
import {
  blockedEvents,
  events,
  H1,
  H12,
  H15,
  H2,
  H20,
  H25,
  payingEvents,
  premiumEvents,
} from './fixtures.ts';
import {
  berlinMonth,
  berlinWeek,
  blockedHouseholdsByWeek,
  external,
  payingHouseholdsByDay35,
  payingShareOfWah,
  reordersByHousehold,
  retention,
  revenueByMonth,
  unlockByDay35,
  weeklyActiveHouseholds,
} from './metrics.ts';

const zeros = (n: number) => Array(n).fill(0);

Deno.test('Berlin buckets: Monday starts, in local time across DST', () => {
  assertEquals(berlinWeek('2026-11-01T23:10:00Z'), '2026-11-02');
  assertEquals(berlinWeek('2026-11-01T22:59:00Z'), '2026-10-26');
  assertEquals(berlinWeek('2026-11-08T23:30:00Z'), '2026-11-09');
  // Summer time: 22:30 UTC is already Monday 00:30 in Berlin.
  assertEquals(berlinWeek('2026-07-12T22:30:00Z'), '2026-07-13');
  assertEquals(berlinMonth('2026-11-30T23:30:00Z'), '2026-12-01');
});

Deno.test('internal: every event of an internal install or household goes', () => {
  const kept = external(events);
  for (const e of kept) assertEquals(e.properties.is_internal, false);
  // H5 sent customer-looking events before its phone was marked internal: gone too.
  assertEquals(
    kept.some((e) => e.properties.household_id === '20000000-0000-4000-8000-000000000005'),
    false,
  );
  assertEquals(kept.length, 24);
});

Deno.test('WAH: each household once per Berlin week with an add or a tick', () => {
  assertEquals(
    weeklyActiveHouseholds(events),
    new Map([['2026-11-02', 2], ['2026-11-09', 2], ['2026-11-30', 1]]),
  );
});

Deno.test('day-35 unlock share by install week; late and refunded buys do not count', () => {
  assertEquals(
    unlockByDay35(events),
    new Map([
      ['2026-11-02', { installs: 3, boughtByDay35: 1, share: 33.3 }],
      ['2026-11-09', { installs: 1, boughtByDay35: 0, share: 0 }],
    ]),
  );
});

const withPaying = [...events, ...payingEvents];

Deno.test('paying households by day 35, by household cohort week', () => {
  assertEquals(
    payingHouseholdsByDay35(withPaying),
    new Map([
      // H1 bought on day 19; H2's member bought on day 46 and the other's buy was refunded.
      ['2026-11-02', { households: 2, payingByDay35: 1, share: 50 }],
      ['2026-11-09', { households: 1, payingByDay35: 0, share: 0 }],
      // H10 (two purchases, once) and H14 pay; H11 (refunded), H13 (day 40) and H15 (no
      // consent) do not; the tester household H12 is in neither count.
      ['2027-01-04', { households: 5, payingByDay35: 2, share: 40 }],
    ]),
  );
});

Deno.test('paying share of WAH: paid by the end of each Berlin week', () => {
  assertEquals(
    payingShareOfWah(withPaying),
    new Map([
      ['2026-11-02', { wah: 2, paying: 0, share: 0 }],
      ['2026-11-09', { wah: 2, paying: 0, share: 0 }],
      ['2026-11-30', { wah: 1, paying: 1, share: 100 }],
      // H14 bought at 00:30 on Monday 11 Jan in Berlin: the next week.
      ['2027-01-04', { wah: 5, paying: 1, share: 20 }],
      // H13 is active but buys only in February.
      ['2027-01-11', { wah: 3, paying: 2, share: 66.7 }],
      ['2027-02-15', { wah: 1, paying: 1, share: 100 }],
    ]),
  );
  // The denominator is WAH itself.
  for (const [week, w] of payingShareOfWah(withPaying)) {
    assertEquals(w.wah, weeklyActiveHouseholds(withPaying).get(week));
  }
});

Deno.test('paying: a buyer without analytics consent leaves the household unpaid', () => {
  // Known undercount: no purchase_completed is sent, so H15 counts in WAH and never as paying.
  assertEquals(payingEvents.some((e) => e.properties.household_id === H15), true);
  assertEquals(
    payingEvents.some((e) => e.event.startsWith('purchase_') && e.properties.household_id === H15),
    false,
  );
  const onlyH15 = payingEvents.filter((e) => e.properties.household_id === H15);
  assertEquals(
    payingShareOfWah(onlyH15),
    new Map([['2027-01-04', { wah: 1, paying: 0, share: 0 }]]),
  );
  assertEquals(
    payingHouseholdsByDay35(onlyH15),
    new Map([['2027-01-04', { households: 1, payingByDay35: 0, share: 0 }]]),
  );
});

Deno.test('a free grant is no sale: no revenue, never paying (testers, beta lifetime, job 371)', () => {
  const onlyH12 = payingEvents.filter((e) => e.properties.household_id === H12);
  assertEquals(onlyH12.length > 0, true);
  assertEquals(revenueByMonth(onlyH12), new Map());
  assertEquals(payingShareOfWah(onlyH12), new Map());
  assertEquals(payingHouseholdsByDay35(onlyH12), new Map());
});

Deno.test('premium by day 35: either product pays, a household once, a refund only its own', () => {
  // H20 yearly, H21 lifetime, H22 both (once), H23 yearly kept and lifetime refunded, H26
  // without premium_source and H27 yearly product_id pay; H24 (only purchase refunded) does
  // not; H25 (Sandbox) is gone.
  assertEquals(
    payingHouseholdsByDay35(premiumEvents),
    new Map([['2027-03-01', { households: 7, payingByDay35: 6, share: 85.7 }]]),
  );
});

Deno.test('premium share of WAH: Yearly counts through purchase + 379 days, Lifetime for good', () => {
  assertEquals(
    payingShareOfWah(premiumEvents),
    new Map([
      ['2027-03-01', { wah: 7, paying: 6, share: 85.7 }],
      // H20, within its 379 days.
      ['2028-03-13', { wah: 1, paying: 1, share: 100 }],
      // H21, H22 (its lifetime) and H26 (no premium_source) pay; H20, H23 and H27 (yearly
      // past 379 days) no longer do.
      ['2028-03-20', { wah: 6, paying: 3, share: 50 }],
    ]),
  );
  assertEquals(external(premiumEvents).some((e) => e.properties.household_id === H25), false);
  const onlyH20 = premiumEvents.filter((e) => e.properties.household_id === H20);
  assertEquals(
    [...payingShareOfWah(onlyH20)].map(([week, w]) => [week, w.paying]),
    [['2027-03-01', 1], ['2028-03-13', 1], ['2028-03-20', 0]],
  );
});

Deno.test('household retention by month (30 days) out to month 11', () => {
  assertEquals(
    retention(events, 30, 12),
    new Map([
      ['2026-11-02', { households: 2, active: [2, 1, ...zeros(10)] }],
      ['2026-11-09', { households: 1, active: [1, ...zeros(11)] }],
    ]),
  );
});

Deno.test('household retention by week', () => {
  assertEquals(
    retention(events, 7, 13),
    new Map([
      ['2026-11-02', { households: 2, active: [2, 0, 0, 0, 1, ...zeros(8)] }],
      ['2026-11-09', { households: 1, active: [1, ...zeros(12)] }],
    ]),
  );
});

Deno.test('net revenue per month: a refund lowers its month, a restore adds nothing', () => {
  assertEquals(
    revenueByMonth(events),
    new Map([
      ['2026-11-01 ', { currency: '', purchases: 0, refunds: 0, restores: 1, gross: 0, net: 0 }],
      ['2026-11-01 EUR', {
        currency: 'EUR',
        purchases: 2,
        refunds: 0,
        restores: 0,
        gross: 19.98,
        net: 14.28,
      }],
      ['2026-12-01 EUR', {
        currency: 'EUR',
        purchases: 1,
        refunds: 1,
        restores: 0,
        gross: 0,
        net: 0,
      }],
    ]),
  );
});

Deno.test('reorders per household, internal households left out', () => {
  assertEquals(
    reordersByHousehold(events),
    new Map([[H1, { defaultOrder: 2, storeLayout: 1, stores: 1 }]]),
  );
  assertEquals(reordersByHousehold(events).has(H2), false);
});

Deno.test('every gate query filters internal installs and households (AC10)', async () => {
  const gates = [
    'wah',
    'unlock_d35',
    'retention_weekly',
    'retention_monthly',
    'revenue_monthly',
    'reorders',
    'paying_households_d35',
    'paying_share_wah',
    'integration_blocked_weekly',
  ];
  const filter = [
    "ifNull(toString(properties.is_internal), '') != 'true'",
    'NOT IN (SELECT id FROM internal_installs)',
    'NOT IN (SELECT id FROM internal_households)',
    "toStartOfWeek(toTimeZone(timestamp, 'Europe/Berlin'), 1)",
  ] as const;
  const internal = await Deno.readTextFile(new URL('queries/internal.sql', import.meta.url));
  const definition = internal.slice(
    internal.indexOf('\nWITH') + 1,
    internal.indexOf("SELECT 'install'"),
  )
    .trim().replace(/\n$/, '');
  for (const gate of gates) {
    const sql = await Deno.readTextFile(new URL(`queries/${gate}.sql`, import.meta.url));
    // The same two lists as internal.sql, then the gate's own steps.
    assertEquals(sql.includes(definition.slice(0, -1)), true, `${gate}: internal lists`);
    for (const line of filter.slice(0, 3)) {
      assertEquals(sql.includes(line), true, `${gate}: ${line}`);
    }
    if (gate === 'wah') {
      assertEquals(sql.includes(filter[3]), true, 'wah: Berlin weeks');
    }
  }
});

Deno.test('integration_blocked (job 50): households per Berlin week, per integration, and paying within 14 days', () => {
  assertEquals(
    blockedHouseholdsByWeek(blockedEvents),
    new Map([
      ['2027-04-05', { households: 2, siri: 1, alexa: 1, mcp: 1, api: 1, payingWithin14Days: 1 }],
      ['2027-04-12', { households: 2, siri: 0, alexa: 1, mcp: 1, api: 0, payingWithin14Days: 0 }],
    ]),
  );
});
