import { expect, test, type Page } from './fixtures';
import { addField, addItem, answerConsent, apiAs, cutOff, editField, itemRow, newEmail, offlineIndicator, openEdit, openEmailSignIn, openMore, password, saveEdit, screenshot, signUpWithHousehold, tick, typeInto, within, expectSignedOutStart } from './helpers';

/** The list snapshot the app keeps in localStorage, or null. */
function cachedList(page: Page): Promise<{ server: unknown[]; pending: unknown[] } | null> {
  return page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /\blist\./.test(k));
    if (!key) return null;
    const raw = localStorage.getItem(key);
    if (raw === null) return null;
    let value = JSON.parse(raw);
    if (typeof value === 'string') value = JSON.parse(value);
    return value;
  });
}

/** Makes the stored session look expired, so the start also has to survive a failed token refresh. */
async function expireStoredSession(page: Page): Promise<void> {
  const expired = await page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /^sb-.*-auth-token$/.test(k));
    if (!key) return false;
    const raw = localStorage.getItem(key);
    if (raw === null) throw new Error(`no ${key}`);
    const session = JSON.parse(raw);
    session.expires_at = Math.floor(Date.now() / 1000) - 60;
    localStorage.setItem(key, JSON.stringify(session));
    return true;
  });
  expect(expired, 'the auth session is in localStorage').toBe(true);
}

test('a cold start without Supabase shows the cached list, queues changes across reloads, and syncs later', async ({ page, browser }) => {
  const email = newEmail('offline');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Brot');
  await addItem(page, 'Milch');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect.poll(async () => {
    const list = await cachedList(page);
    return list && [list.server.length, list.pending.length];
  }, { message: 'the synced list is cached' }).toEqual([2, 0]);

  const network = await cutOff(page);
  await expireStoredSession(page);
  const reloaded = Date.now();
  await page.reload();
  // Fails fast: no hidden library retries (they took 7 s per read) before the cache shows.
  await within(3_000, (timeout) => expect(itemRow(page, 'Brot'), 'the cached list shows offline').toBeVisible({ timeout }));
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(addField(page)).toBeFocused();
  // Job 212: the server may only be slow, so a start says offline after a 10 s grace, not at the first failure.
  await expect(offlineIndicator(page), 'no banner while the start may be slow').toHaveCount(0);
  await page.waitForTimeout(Math.max(0, reloaded + 8_000 - Date.now()));
  await expect(offlineIndicator(page), 'still none 8 s after the reload').toHaveCount(0);
  await within(15_000, (timeout) => expect(offlineIndicator(page), 'offline once the grace is over').toHaveCount(1, { timeout }));
  expect(Date.now() - reloaded, 'not before the grace').toBeGreaterThanOrEqual(9_000);

  await addItem(page, 'Käse');
  // Job 111: the device reads the amount (number words, job 104); the server splits brand and
  // details once it syncs.
  await addItem(page, 'zwei Windeln Pampers Größe 3');
  // A rename before the sync is split the same way.
  await addItem(page, 'Shampoo Nivea Größe 4');
  await openEdit(page, 'Shampoo Nivea Größe 4');
  await typeInto(editField(page, 'Bezeichnung'), 'Shampoo Nivea Größe 5');
  await saveEdit(page);
  await expect(itemRow(page, 'Shampoo Nivea Größe 5')).toBeVisible();
  await tick(page, 'Brot');
  await expect(itemRow(page, 'Käse')).toBeVisible();
  await expect(itemRow(page, 'Brot')).toHaveCount(0);

  await page.reload();
  await expect(itemRow(page, 'Käse'), 'queued ops survive a reload while offline').toBeVisible();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(itemRow(page, 'Brot')).toHaveCount(0);
  await expect(addField(page)).toBeFocused();
  await screenshot(page, 'offline-01-cold-start-from-cache');

  await network.restore();
  const api = await apiAs(email);
  await expect.poll(async () => {
    const { data } = await api.from('items').select('name, brand, properties, quantity, status').order('name');
    return data;
  }, { message: 'the queued ops reach the server, an offline add split as online', timeout: 20_000 }).toEqual([
    { name: 'Brot', brand: null, properties: null, quantity: null, status: 'bought' },
    { name: 'Käse', brand: null, properties: null, quantity: null, status: 'active' },
    { name: 'Milch', brand: null, properties: null, quantity: null, status: 'active' },
    { name: 'Shampoo', brand: 'Nivea', properties: 'Größe 5', quantity: null, status: 'active' },
    { name: 'Windeln', brand: 'Pampers', properties: 'Größe 3', quantity: '2', status: 'active' },
  ]);
  await expect(itemRow(page, 'Windeln'), 'the list shows the split row').toHaveAccessibleName(/^Windeln Pampers · Größe 3 2$/);
  await screenshot(page, 'offline-02-synced-split');
  await expect(offlineIndicator(page)).toHaveCount(0, { timeout: 15_000 });

  const other = await (await browser.newContext()).newPage();
  await other.goto('/login');
  await openEmailSignIn(other);
  await typeInto(other.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(other.getByRole('textbox', { name: 'Passwort' }), password);
  await other.getByRole('button', { name: 'Anmelden', exact: true }).click();
  // A new install: the analytics consent first (job 19).
  await answerConsent(other);
  await expect(itemRow(other, 'Käse'), 'another session of the same user sees the synced list').toBeVisible();
  await expect(itemRow(other, 'Milch')).toBeVisible();
  await expect(itemRow(other, 'Brot')).toHaveCount(0);
});

test('signing out drops the cached list', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('offline-out'));
  await addItem(page, 'Geheimzutat');
  await expect(itemRow(page, 'Geheimzutat')).toBeVisible();
  await expect.poll(async () => (await cachedList(page))?.server.length, { message: 'the list is cached' }).toBe(1);

  await openMore(page, 'Abmelden');
  await expectSignedOutStart(page);
  await expect.poll(
    () => page.evaluate(() => Object.keys(localStorage).filter((k) => /\b(list|household)\./.test(k)).length),
    { message: 'nothing of the list stays on the device' },
  ).toBe(0);
});

test('a write the server answers with an expired token is retried, not dropped', async ({ page }) => {
  const email = newEmail('expired');
  await signUpWithHousehold(page, email);
  let refused = 0;
  // The token can lapse between the client's refresh check and the server, e.g. on a phone woken from sleep.
  await page.route('**/rest/v1/rpc/put_item', async (route) => {
    if (route.request().method() !== 'POST' || refused > 0) return route.fallback();
    refused++;
    await route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ code: 'PGRST303', details: null, hint: null, message: 'JWT expired' }),
    });
  });
  await addItem(page, 'Brot');
  const api = await apiAs(email);
  await expect.poll(async () => {
    const { data } = await api.from('items').select('name');
    return data;
  }, { message: 'the refused add reaches the server on the retry', timeout: 15_000 }).toEqual([{ name: 'Brot' }]);
  expect(refused, 'the first write was refused').toBe(1);
  await expect(page.getByText(/^Änderung abgelehnt/)).toHaveCount(0);
  await expect(itemRow(page, 'Brot')).toBeVisible();
});
