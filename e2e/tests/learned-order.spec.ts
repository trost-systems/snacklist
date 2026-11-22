// Job 352 (IO4): behind the PostHog flag `learned-order` the household's list follows the order its
// members tick in. The app switches the household to `learned` (`set_order_mode`), each store shows
// one run in walk order without category dividers, the edit sheet's „Neben …“ chip places an item
// (`place_item`), and the server detects trips from the app's ticks (`detect_trips`, pg_cron in
// production, called here) and replays their walks into the items' sort keys. A run whose trip
// question was answered „Nein“ is left out (`decline_shop`, TD-Q5).
import type { SupabaseClient } from '@supabase/supabase-js';
import { type Browser, expect, type Page, test } from './fixtures';
import { sectionHeadings, sectionItems } from './catalog';
import {
  adminClient, apiAs, editSheet, fakeCollector, firstOf, itemRow, must, newEmail, openEdit, openMore, saveEdit,
  signUpWithHousehold, tickSaved,
} from './helpers';

const store = 'Lidl';

/** One item per category, so a categories list shows four dividers in Lidl's section. */
const items = [
  { name: 'Äpfel', category: 'Obst & Gemüse' },
  { name: 'Brot', category: 'Brot & Backwaren' },
  { name: 'Joghurt', category: 'Kühlregal' },
  { name: 'Schokolade', category: 'Süßes & Snacks' },
];

async function newPage(browser: Browser, flags: Record<string, boolean>): Promise<Page> {
  const context = await browser.newContext();
  await fakeCollector(context, { flags });
  return context.newPage();
}

/** With trip mode and Verlauf, as users have them (both rolled out in full). */
const learnedFlags = { 'learned-order': true, 'grocery-log': true, 'trip-mode': true };

type Household = { email: string; api: SupabaseClient; household: string; storeId: string };

/** Signs up with a household at Lidl and puts [items] there over the API. */
async function startHousehold(page: Page, tag: string): Promise<Household> {
  const email = newEmail(tag);
  await signUpWithHousehold(page, email, { stores: [store] });
  const api = await apiAs(email);
  const lidl = firstOf((await api.from('stores').select('id, household_id').eq('name', store)).data, 'Lidl');
  const household = lidl.household_id as string;
  const { data: categories } = await api.from('categories').select('id, name');
  const { error } = await api.from('items').insert(items.map((i) => ({
    household_id: household,
    name: i.name,
    store_id: lidl.id,
    category_id: must(categories?.find((c) => c.name === i.category), i.category).id,
  })));
  if (error) throw error;
  await page.reload();
  await expect(itemRow(page, 'Schokolade')).toBeVisible();
  return { email, api, household, storeId: lidl.id as string };
}

/** The household's open items at Lidl in the server's order (sort_key, then created_at). */
async function serverOrder({ api, storeId }: Household): Promise<string[]> {
  const { data, error } = await api.from('items').select('name').eq('store_id', storeId).eq('status', 'active')
    .order('sort_key').order('created_at').order('id');
  if (error) throw error;
  return (data ?? []).map((r) => r.name as string);
}

async function waitForLearned({ api, household }: Household): Promise<void> {
  await expect.poll(async () => (await api.from('households').select('order_mode').eq('id', household).single()).data?.order_mode,
    { message: 'the flag switched the household to the learned order' }).toBe('learned');
}

/**
 * Ticks [names] off in the app in that order, answering „Kaufst du gerade ein?“ with „Nein“, which
 * sends `decline_shop` (TD-Q5: that run is not detected). Then spreads their events into a walk from
 * [from] on, one tick every 30 s (job 351's rule: 3 steps or more, a median gap of at least 20 s),
 * and puts the items back as the service role, whose update is no app tick. Forward, not back: only
 * ticks after the switch to the learned order and after the app first asked about detection count.
 * Returns how many ticks asked.
 */
async function walk(page: Page, h: Household, names: string[], from: number): Promise<number> {
  const admin = adminClient();
  const newest = async () => {
    const { data, error } = await admin.from('item_events').select('id').eq('household_id', h.household)
      .order('id', { ascending: false }).limit(1);
    if (error) throw error;
    return Number(data?.[0]?.id ?? 0);
  };
  const after = await newest();
  let asked = 0;
  const no = page.getByRole('button', { name: 'Nein, nur abgehakt', exact: true });
  for (const name of names) {
    await expect(itemRow(page, name)).toBeVisible();
    await tickSaved(page, name);
    if (await no.waitFor({ timeout: 1_500 }).then(() => true, () => false)) {
      asked++;
      await expect(
        page.getByText('Nach „Nein“ fragen wir eine Stunde lang nicht mehr, und dieser Einkauf wird nicht erkannt.', { exact: true }),
        'the question says it goes quiet and the shop is not detected',
      ).toBeVisible();
      const declined = page.waitForResponse((r) => new URL(r.url()).pathname === '/rest/v1/rpc/decline_shop' && r.ok());
      await no.click();
      await expect(no).toHaveCount(0);
      await declined;
    }
  }
  const { data: rows } = await h.api.from('items').select('id, name').eq('household_id', h.household).in('name', names);
  const ids = names.map((n) => must(rows?.find((r) => r.name === n), n).id as string);
  const { data: events, error } = await admin.from('item_events').select('id, item_id')
    .eq('household_id', h.household).eq('action', 'bought').eq('source', 'app').in('item_id', ids).gt('id', after);
  if (error) throw error;
  for (const [i, id] of ids.entries()) {
    const event = must(events?.find((e) => e.item_id === id), `the tick of ${names[i]}`);
    const at = from + i * 30_000;
    const { error: moved } = await admin.from('item_events')
      .update({ client_at: new Date(at).toISOString(), created_at: new Date(at + 400).toISOString() }).eq('id', event.id);
    if (moved) throw moved;
  }
  const { error: back } = await admin.from('items').update({ status: 'active' }).in('id', ids);
  if (back) throw back;
  await page.reload();
  await expect(itemRow(page, must(names[0], 'a name'))).toBeVisible();
  return asked;
}

/**
 * The app's first my_trip_detection turned detection on, and the switch to the learned order set
 * where the household's detection starts: both at sign-up, after the walks' moved times. Counts
 * ticks from [since] on.
 */
async function countFrom(h: Household, since: number): Promise<void> {
  const admin = adminClient();
  const at = new Date(since).toISOString();
  const user = must((await h.api.auth.getUser()).data.user, 'the signed-in user').id;
  const { error: on } = await admin.from('trip_detection_settings').update({ detect_ticks_from: at }).eq('user_id', user);
  if (on) throw on;
  const { error: from } = await admin.from('trip_detection_state').update({ detect_from: at }).eq('household_id', h.household);
  if (from) throw from;
}

/**
 * A walk answered „Nein“, then the same walk again 45 minutes later: a new run (more than 30
 * minutes apart), ticked while the 60-minute snooze holds, so nothing asks and nothing is declined.
 * Detection finds only the second one.
 */
async function walkTwice(page: Page, h: Household, names: string[]): Promise<void> {
  const start = Date.now();
  await countFrom(h, start - 60_000);
  expect(await walk(page, h, names, start), 'the first tick asks and „Nein“ answers').toBe(1);
  expect(await walk(page, h, names, start + 45 * 60_000), 'inside the snooze nothing asks').toBe(0);
}

async function detect({ household }: Household): Promise<number> {
  const { data, error } = await adminClient().rpc('detect_trips', { p_household: household });
  if (error) throw error;
  return data as number;
}

async function detectedSessions({ household }: Household): Promise<{ id: string; removed_at: string | null }[]> {
  const { data, error } = await adminClient().from('trip_sessions').select('id, removed_at')
    .eq('household_id', household).eq('source', 'detected');
  if (error) throw error;
  return data ?? [];
}

const verlauf = (page: Page) => page.getByRole('tab', { name: 'Verlauf', exact: true });
const detectedTrip = (page: Page) => page.getByRole('button', { name: /Aus deinen Häkchen erkannt/ });

test('LEARNED ORDER: no category dividers, the server\'s walk order, and „Ganz vorne“ puts an item first for good', async ({ browser }) => {
  const page = await newPage(browser, learnedFlags);
  const h = await startHousehold(page, 'learned-place');
  await waitForLearned(h);
  await page.reload();
  await expect(itemRow(page, 'Schokolade')).toBeVisible();

  const order = await serverOrder(h);
  expect([...order].sort(), 'every item has its place').toEqual(items.map((i) => i.name).sort());
  await expect.poll(() => sectionItems(page, store), { message: 'Lidl\'s rows in the server\'s walk order' }).toEqual(order);
  expect(await sectionHeadings(page, store), 'no category dividers').toEqual([]);

  const last = must(order.at(-1), 'last item');
  await openEdit(page, last);
  const chip = editSheet(page).getByRole('button', { name: /^Platz in der Liste: Neben / });
  await expect(chip, 'the place chip names the item before it').toHaveAccessibleName(`Platz in der Liste: Neben ${order.at(-2)}`);
  await expect(editSheet(page).getByRole('button', { name: /^Kategorie: / }), 'no category chip').toHaveCount(0);
  await chip.click();
  const placed = page.waitForResponse((r) => new URL(r.url()).pathname === '/rest/v1/rpc/place_item' && r.ok());
  await editSheet(page).getByRole('button', { name: 'Ganz vorne', exact: true }).click();
  await expect(editSheet(page).getByRole('button', { name: 'Platz in der Liste: Ganz vorne' })).toBeVisible();
  await saveEdit(page);
  await placed;

  const moved = [last, ...order.slice(0, -1)];
  await expect.poll(() => sectionItems(page, store), { message: 'first on the list at once' }).toEqual(moved);
  expect(await serverOrder(h), 'and on the server').toEqual(moved);
  await page.reload();
  await expect(itemRow(page, last)).toBeVisible();
  await expect.poll(() => sectionItems(page, store), { message: 'still first after a reload' }).toEqual(moved);
});

test('LEARNED ORDER: TD-Q5 a walk answered „Nein“ is not detected; the next walk becomes a detected trip, the list follows it, the card goes for good, „Kein Einkauf“ removes it', async ({ browser }) => {
  const page = await newPage(browser, learnedFlags);
  const h = await startHousehold(page, 'learned-walk');
  await waitForLearned(h);
  await page.reload();
  const before = await serverOrder(h);
  await expect.poll(() => sectionItems(page, store)).toEqual(before);
  const [first, second, third, fourth] = before;
  if (!first || !second || !third || !fourth) throw new Error(`four items, not ${before.join(', ')}`);

  // The last of the four first: it trades places towards the front, ahead of the one walked last.
  const walked = [fourth, first, second, third];
  const start = Date.now();
  await countFrom(h, start - 60_000);
  expect(await walk(page, h, walked, start), 'the first tick asks and „Nein“ answers').toBe(1);
  expect(await detect(h), 'TD-Q5: the walk answered „Nein“ is no trip').toBe(0);
  expect(await detectedSessions(h), 'TD-Q5: no detected trip').toEqual([]);
  expect(await serverOrder(h), 'TD-Q5: and no change in the order').toEqual(before);

  // 45 minutes after the declined walk's last tick: a run of its own, while the snooze still holds.
  expect(await walk(page, h, walked, start + 45 * 60_000), 'inside the snooze nothing asks').toBe(0);
  expect(await detect(h), 'the walk without a question is one detected trip').toBe(1);
  const after = await serverOrder(h);
  expect(after.indexOf(fourth), `${fourth}, walked before ${third}, now stands before it`).toBeLessThan(after.indexOf(third));
  expect(after[0], `${first} was walked before ${second} and ${third} and stays ahead of them`).toBe(first);

  await page.reload();
  await expect(itemRow(page, fourth)).toBeVisible();
  await expect.poll(() => sectionItems(page, store), { message: 'the list shows the walked order' }).toEqual(after);
  const card = page.getByRole('heading', { name: `Einkauf bei ${store} erkannt`, exact: true });
  await expect(card, 'the first-trip card names the store').toBeVisible();
  await page.getByRole('button', { name: 'Verstanden', exact: true }).click();
  await expect(card).toHaveCount(0);
  await expect.poll(async () => (await h.api.rpc('my_trip_detection')).data?.card_seen, { message: 'seen on the server' }).toBe(true);
  await page.reload();
  await expect(itemRow(page, fourth)).toBeVisible();
  await expect(card, 'gone for good').toHaveCount(0);

  await verlauf(page).click();
  await expect(detectedTrip(page), 'Verlauf shows the trip as detected').toBeVisible();
  await detectedTrip(page).click();
  await expect(page).toHaveURL(/\/history\/trip\/[0-9a-f-]{36}$/);
  await page.getByRole('button', { name: 'Kein Einkauf', exact: true }).click();
  await expect(page.getByText('Kein Einkauf? Die Häkchen bleiben, aber die Reihenfolge lernt nicht mehr daraus.')).toBeVisible();
  await page.getByRole('button', { name: 'Entfernen', exact: true }).click();
  await expect(page).not.toHaveURL(/\/trip\//);
  await expect(page.getByText('Entfernt', { exact: true }).first(), 'the snackbar').toBeVisible();
  await expect(detectedTrip(page)).toHaveCount(0);
  const [removed] = await detectedSessions(h);
  expect(removed?.removed_at, 'removed on the server, kept so detection never finds it again').not.toBeNull();
  expect(await serverOrder(h), 'the order no longer learns from it').toEqual(before);
  expect(await detect(h), 'its ticks are not detected again').toBe(0);
});

test('LEARNED ORDER: switching detection off in Einstellungen removes the person\'s detected trips', async ({ browser }) => {
  const page = await newPage(browser, learnedFlags);
  const h = await startHousehold(page, 'learned-off');
  await waitForLearned(h);
  await page.reload();
  const order = await serverOrder(h);
  await walkTwice(page, h, [...order].reverse());
  expect(await detect(h)).toBe(1);

  await openMore(page, 'Einstellungen');
  const toggle = page.getByRole('switch', { name: /^Einkäufe aus meinen Häkchen erkennen/ });
  await expect(toggle).toBeChecked();
  const saved = page.waitForResponse((r) => new URL(r.url()).pathname === '/rest/v1/rpc/set_trip_detection' && r.ok());
  await toggle.click();
  await saved;
  await expect(toggle).not.toBeChecked();
  expect(await detectedSessions(h), 'the detected trip is gone from the database').toEqual([]);
  expect((await h.api.rpc('my_trip_detection')).data?.on, 'off on the server').toBe(false);
  expect(await serverOrder(h), 'its walk no longer orders the list').toEqual(order);

  await page.reload();
  await expect(toggle, 'off after a reload').not.toBeChecked();
  await verlauf(page).click();
  await expect(page.getByText('Noch keine Einkäufe', { exact: true }), 'Verlauf is empty again').toBeVisible();
  expect(await detect(h), 'ticks from before the switch never count').toBe(0);
});

test('LEARNED ORDER off: category dividers as before, and a tick is an app tick without its tap time', async ({ browser }) => {
  const page = await newPage(browser, {});
  const h = await startHousehold(page, 'learned-flag-off');
  await expect.poll(() => sectionHeadings(page, store), { message: 'one divider per category' }).toHaveLength(items.length);
  expect((await h.api.from('households').select('order_mode').eq('id', h.household).single()).data?.order_mode).toBe('categories');

  await tickSaved(page, 'Brot');
  const { data: events, error } = await adminClient().from('item_events').select('source, client_at')
    .eq('household_id', h.household).eq('action', 'bought');
  if (error) throw error;
  const event = firstOf(events, 'the tick\'s event');
  expect(events, 'one event').toHaveLength(1);
  expect(event.source).toBe('app');
  expect(event.client_at, 'no tap time kept for someone whose app never showed the detection switch (N-319)').toBeNull();
});
