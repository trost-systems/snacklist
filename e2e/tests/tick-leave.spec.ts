import { type BrowserContext, expect, test, type Page } from './fixtures';
import { addItem, apiAs, firstOf, itemRow, newEmail, signUpWithHousehold } from './helpers';

// Job 222: a tick reached the list only when its row had closed (440 ms after the tap), so a page
// that went away before then lost it. The list now saves the tick with its queue at the tap, the row
// ticks when the page is hidden, and the device keeps the tick until the server has it. These tests
// leave the page right after the tap (no `tick` or `tickSaved` from helpers.ts, which wait for the
// row or the write).

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

/**
 * The list in a new tab, and whether the device held a queued tick before the app started there
 * (the app sends the tick and saves again at once). A lost tick then says which half lost it: the
 * save before the page went, or the start after it.
 */
async function reopened(context: BrowserContext): Promise<{ again: Page; ticked: string }> {
  const again = await context.newPage();
  await again.addInitScript(() => {
    if (sessionStorage.getItem('tick-leave.queued') !== null) return;
    const queued = Object.keys(localStorage).some((key) => key.startsWith('list.') && /op\\*":\\*"status/.test(localStorage.getItem(key) ?? ''));
    sessionStorage.setItem('tick-leave.queued', queued ? 'yes' : 'no');
  });
  await again.goto('/');
  await expect(itemRow(again, 'Milch'), 'the list loaded').toBeVisible({ timeout: 30_000 });
  const queued = await again.evaluate(() => sessionStorage.getItem('tick-leave.queued'));
  return { again, ticked: `ticked on this device (a queued tick in its cache before the start: ${queued ?? 'not read'})` };
}

test('a tick is kept when the page reloads while its row still closes', async ({ page, browserName }) => {
  // A CI runner's WebKit draws in software, a frame every 200 ms or so: each step takes a second.
  // These two took 33 to 50 s of their 60 in CI; the reload test took 59 s on a loaded box (job 222).
  test.slow(browserName === 'webkit');
  const email = newEmail('tick-reload');
  await listWith(page, email);

  await itemRow(page, 'Brot').click();
  await page.reload();
  await expect(itemRow(page, 'Milch'), 'the list loaded').toBeVisible({ timeout: 30_000 });
  await expect(itemRow(page, 'Brot'), 'ticked on this device').toHaveCount(0);
  await expect.poll(() => status(email, 'Brot'), { message: 'the server took the tick' }).toBe('bought');
});

// On WebKit this test is no proof of the fix: it passes on the code before it too (3 of 3 in review
// 0). Its close seems to outlast the row's 440 ms; nobody measured that. Chromium and Firefox fail
// there; so does the reload test in all three.
test('a tick is kept when the tab closes while its row still closes', async ({ page, context, browserName }) => {
  test.slow(browserName === 'webkit');
  const email = newEmail('tick-close');
  await listWith(page, email);

  await itemRow(page, 'Brot').click();
  await page.close({ runBeforeUnload: true });
  const { again, ticked } = await reopened(context);
  await expect(itemRow(again, 'Brot'), ticked).toHaveCount(0);
  await expect.poll(() => status(email, 'Brot'), { message: 'the server took the tick' }).toBe('bought');
});

// The first microtask the page starts after `beforeunload` is busy until 1.5 s after it, as a slow
// frame would be. Dart runs what it awaits in such microtasks.
function busyOnceLeaving(): void {
  let until = 0;
  globalThis.addEventListener('beforeunload', () => {
    until = performance.now() + 1500;
  }, { capture: true });
  const queue = globalThis.queueMicrotask.bind(globalThis);
  globalThis.queueMicrotask = (callback: VoidFunction): void =>
    queue(() => {
      while (performance.now() < until) {
        // Busy.
      }
      callback();
    });
}

// Review 1 of job 222: a closing Firefox tab ends the script that is running, without its
// `finally`, and then fires `pagehide` and `visibilitychange` (measured). In the traced app nothing
// that was awaited ran after that, so a tick saved only then, by the hidden row, was never written;
// Dart's microtask loop seems not to start again (read from its source, not stepped through). The
// test above lost its tick in 4 of 108 CI runs, by all signs that way, when the close fell into a
// frame; here every close does. The tick is saved on the device at the tap, so it no longer
// depends on what the page still runs as it ends. With the save at the hide only, this test lost
// the tick in every run on all three engines (16 runs; why on Chromium and WebKit was not traced).
test('a tick is kept when the tab closes into a busy frame', async ({ page, context, browserName }) => {
  test.slow(browserName === 'webkit');
  await context.addInitScript(busyOnceLeaving);
  const email = newEmail('tick-busy-close');
  await listWith(page, email);

  await itemRow(page, 'Brot').click();
  await page.close({ runBeforeUnload: true });
  const { again, ticked } = await reopened(context);
  await expect(itemRow(again, 'Brot'), ticked).toHaveCount(0);
  await expect.poll(() => status(email, 'Brot'), { message: 'the server took the tick' }).toBe('bought');
});
