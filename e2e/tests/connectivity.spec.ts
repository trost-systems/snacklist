// Job 166: the sync indicator follows the device's network on its own. Playwright's offline mode fires the
// browser's offline and online events, which the app watches; nothing on the page is touched while it switches.
import { expect, test } from './fixtures';
import { addItem, apiAs, itemRow, newEmail, offlineIndicator, screenshot, signUpWithHousehold, tick } from './helpers';

test('the network going away shows offline without a tap; back, the queued tick syncs and it goes', async ({ page, context }) => {
  const email = newEmail('network');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Brot');
  await addItem(page, 'Milch');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await page.waitForTimeout(1_000);
  await expect(offlineIndicator(page), 'online: nothing').toHaveCount(0);

  await context.setOffline(true);
  // The channel's heartbeat would notice only after 25 s or more; the network event says it at once.
  await expect(offlineIndicator(page), 'offline with no tap and no request').toHaveCount(1, { timeout: 3_000 });
  await screenshot(page, 'network-01-offline');

  await tick(page, 'Brot');
  await expect(itemRow(page, 'Brot'), 'optimistic while offline').toHaveCount(0);

  await context.setOffline(false);
  await expect(offlineIndicator(page), 'back online: gone with no tap').toHaveCount(0, { timeout: 10_000 });
  await screenshot(page, 'network-02-back');
  const api = await apiAs(email);
  await expect(async () => {
    const { data, error } = await api.from('items').select('name,status').eq('name', 'Brot');
    expect(error).toBeNull();
    expect(data, 'the tick made offline reached the server').toEqual([{ name: 'Brot', status: 'bought' }]);
  }).toPass({ timeout: 5_000 });
  await api.auth.signOut({ scope: 'local' });
});
