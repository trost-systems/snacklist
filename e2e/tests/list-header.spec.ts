import { expect, test, type Page, type Route } from './fixtures';
import { addItem, apiAs, boxOf, cutOff, failingIndicator, householdChip, itemRow, listBarHeight, newEmail, offlineIndicator, screenshot, signUpWithHousehold, tick } from './helpers';

/** The sync indicator's accessible names; it shows nothing while online, even with changes in flight. */
const offline = offlineIndicator;
const failing = failingIndicator;
const retrying = (page: Page) => page.getByRole('button', { name: 'Wird erneut versucht', exact: true });
const edit = (page: Page) => page.getByRole('button', { name: 'Anpassen', exact: true });

test('the bar above the list keeps its height in every sync state and names the household only in its chip, no count', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('topbar'));
  await addItem(page, 'Brot');
  await addItem(page, 'Milch');
  await addItem(page, 'Seife');
  await expect(itemRow(page, 'Seife')).toBeVisible();

  // Job 169b: the household's name is the switcher chip, and nowhere else in the bar.
  await expect(page.getByText('Unser Haushalt'), 'the name once').toHaveCount(1);
  await expect(householdChip(page, 'Unser Haushalt'), 'as the chip').toBeVisible();
  await expect(page.getByText(/^\d+ Artikel$/), 'no item count').toHaveCount(0);

  // The explainer card is the list's first entry, right under the bar, and stays while items are ticked
  // (a store divider would move when its last item goes). It must not move while the indicator comes and goes.
  const card = page.getByRole('button', { name: 'Verstanden', exact: true });
  const top = async () => (await boxOf(card)).y;
  const synced = await top();
  const anpassen = await boxOf(edit(page));
  expect(synced, 'the list starts under the bar').toBeGreaterThan(listBarHeight);
  expect(synced, 'right under it').toBeLessThan(listBarHeight + 48);
  await screenshot(page, 'topbar-01-synced');

  // Hold every item write until released: the tick stays pending, and online that shows nothing.
  let release!: () => void;
  const held = new Promise<void>((resolve) => { release = resolve; });
  const items = '**/rest/v1/items**';
  await page.route(items, async (route) => {
    if (route.request().method() !== 'GET') await held;
    await route.fallback();
  });
  await tick(page, 'Milch');
  await page.waitForTimeout(1_000);
  await expect(offline(page), 'pending online: no indicator').toHaveCount(0);
  await expect(failing(page), 'pending online: no indicator').toHaveCount(0);
  release();
  await page.unroute(items);

  const network = await cutOff(page);
  await tick(page, 'Seife');
  await expect(offline(page), 'offline opens the card').toHaveCount(1, { timeout: 10_000 });
  expect(await top(), 'offline: the list did not move').toBe(synced);
  expect(await boxOf(edit(page)), 'offline: Anpassen did not move').toEqual(anpassen);
  await screenshot(page, 'topbar-02-offline-open');

  // About 3 s later it is the pill at the top left: still one node with the full sentence.
  await expect(async () => {
    const pill = await boxOf(offline(page));
    expect(pill.x + pill.width, 'the pill sits left of Anpassen').toBeLessThan(anpassen.x);
  }).toPass({ timeout: 8_000 });
  await expect(offline(page)).toHaveCount(1);
  await screenshot(page, 'topbar-03-offline-pill');

  await offline(page).click();
  await expect(async () => {
    const open = await boxOf(offline(page));
    expect(open.y, 'a tap opens the card below the bar').toBeGreaterThan(anpassen.y + anpassen.height - 1);
  }).toPass({ timeout: 3_000 });

  await network.restore();
  await expect(offline(page), 'back online: gone, no confirmation').toHaveCount(0, { timeout: 20_000 });
  await expect(page.getByText(/Synchronisiert/), 'no confirmation snackbar').toHaveCount(0);
  expect(await top(), 'back online: the list did not move').toBe(synced);
  expect(await boxOf(edit(page)), 'back online: Anpassen did not move').toEqual(anpassen);
});

test('a server that answers with errors shows sync failing, keeps the change and retries on a tap', async ({ page }) => {
  const email = newEmail('syncfail');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Kaffee');
  await expect(itemRow(page, 'Kaffee')).toBeVisible();

  // Every write answers 503, as a gateway in trouble does; reads still work, so the app is not offline.
  const writes = '**/rest/v1/**';
  const unavailable = { status: 503, contentType: 'text/plain', body: 'Service Unavailable' };
  let lastFail = 0;
  let failed: (() => void) | undefined;
  let hold: ((route: Route) => void) | undefined;
  await page.route(writes, async (route) => {
    if (route.request().method() === 'GET') return route.fallback();
    // Each resync also POSTs rpc/suggest_items; only the tick's item write is timed and held.
    if (!route.request().url().includes('/rest/v1/items')) return route.fulfill(unavailable);
    if (hold) {
      hold(route);
      hold = undefined;
      return undefined;
    }
    lastFail = Date.now();
    await route.fulfill(unavailable);
    failed?.();
    failed = undefined;
    return undefined;
  });
  await tick(page, 'Kaffee');
  await expect(failing(page), 'sync failing shows once the 3 s retry is refused too').toHaveCount(1, { timeout: 10_000 });
  await expect(offline(page)).toHaveCount(0);
  // A dropped change would put the open row back.
  await expect(itemRow(page, 'Kaffee'), 'the tick stays').toHaveCount(0);
  await expect(page.getByText(/^Änderung abgelehnt/), 'not dropped as refused').toHaveCount(0);
  await screenshot(page, 'topbar-04-failing-open');
  const collapsed = async () => {
    const pill = await boxOf(failing(page));
    expect(pill.y + pill.height, 'collapsed into the bar').toBeLessThanOrEqual(listBarHeight);
  };
  await expect(collapsed).toPass({ timeout: 8_000 });
  await screenshot(page, 'topbar-05-failing-pill');

  // The list retries 3 s after each failed write, timed from the app's receipt of the 503 and with a
  // resync before it writes again: an item write sooner than 3 s after one is the tap's.
  // Held unanswered, it keeps the retry in flight for the label to be read.
  await new Promise<void>((resolve) => {
    failed = resolve;
  });
  const since = lastFail;
  const tapped = new Promise<{ route: Route; at: number }>((resolve) => {
    hold = (route) => resolve({ route, at: Date.now() });
  });
  await failing(page).click();
  const write = await Promise.race([
    tapped,
    new Promise<never>((_, reject) => setTimeout(() => reject(new Error('the tap sent no item write within 5 s')), 5_000)),
  ]);
  expect(write.at - since, 'the tap wrote before the 3 s retry could').toBeLessThan(3_000);
  await expect(retrying(page), 'the pill says it tries again').toHaveCount(1);
  await expect(failing(page)).toHaveCount(0);
  await write.route.fulfill(unavailable);
  await expect(failing(page), 'still failing: back to the pill').toHaveCount(1);
  await expect(retrying(page)).toHaveCount(0);
  await expect(collapsed).toPass({ timeout: 2_000 });

  await page.unroute(writes);
  await expect(failing(page), 'the next retry went through and the indicator left').toHaveCount(0, { timeout: 10_000 });
  const api = await apiAs(email);
  await expect(async () => {
    const { data } = await api.from('items').select('status').eq('name', 'Kaffee');
    expect(data).toEqual([{ status: 'bought' }]);
  }).toPass({ timeout: 10_000 });
});
