import type { Page } from '@playwright/test';
import { expect, test } from './fixtures';
import { addItem, apiAs, firstOf, itemRow, newEmail, signUpWithHousehold } from './helpers';

// Job 222: a tick reached the list only when its row had closed (440 ms after the tap), so a page
// that went away before then lost it. The row now ticks when the page is hidden, and the list keeps
// the tick on the device until the server has it. These tests leave the page right after the tap
// (no `tick` or `tickSaved` from helpers.ts, which wait for the row or the write).

async function status(email: string, name: string): Promise<string> {
  const client = await apiAs(email);
  const { data, error } = await client.from('items').select('status').eq('name', name);
  if (error) throw error;
  return firstOf(data, name).status;
}

async function listWith(page: Page, email: string): Promise<void> {
  await signUpWithHousehold(page, email);
  await addItem(page, 'Milch');
  await addItem(page, 'Brot');
  await expect(itemRow(page, 'Brot')).toBeVisible();
  await expect.poll(() => status(email, 'Brot'), { message: 'the server has the add' }).toBe('active');
}

test('a tick is kept when the page reloads while its row still closes', async ({ page }) => {
  const email = newEmail('tick-reload');
  await listWith(page, email);

  await itemRow(page, 'Brot').click();
  await page.reload();
  await expect(itemRow(page, 'Milch'), 'the list loaded').toBeVisible({ timeout: 30_000 });
  await expect(itemRow(page, 'Brot'), 'ticked on this device').toHaveCount(0);
  await expect.poll(() => status(email, 'Brot'), { message: 'the server took the tick' }).toBe('bought');
});

test('a tick is kept when the tab closes while its row still closes', async ({ page, context }) => {
  const email = newEmail('tick-close');
  await listWith(page, email);

  await itemRow(page, 'Brot').click();
  await page.close({ runBeforeUnload: true });
  const again = await context.newPage();
  await again.goto('/');
  await expect(itemRow(again, 'Milch'), 'the list loaded').toBeVisible({ timeout: 30_000 });
  await expect(itemRow(again, 'Brot'), 'ticked on this device').toHaveCount(0);
  await expect.poll(() => status(email, 'Brot'), { message: 'the server took the tick' }).toBe('bought');
});
