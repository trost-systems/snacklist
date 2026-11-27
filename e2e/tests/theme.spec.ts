import { expect, test, type Page } from './fixtures';
import { openStores, storeRow } from './catalog';
import {
  apiAs, closeSheet, editSheet, enterItem, firstOf, itemRow, must, newEmail, openEdit, openMore, openTab, screenshot,
  signUpWithHousehold, storeDivider, inviteCodeLabel,
  expectSignedOutStart,
} from './helpers';

// Job 29e: Einstellungen (More) holds the theme, kept on the device, and the language list. Every
// main screen is shot in both themes (docs/screenshots/29e-settings-theme). Job 57: the theme is one
// segmented control, "System", "Hell" and "Dunkel" (radio buttons of one group on web).

/**
 * The relative luminance (0 black, 1 white) of the app's background at a point, read from a
 * screenshot. Decoded in a blank page of its own, out of reach of the app's CSP.
 */
async function luminanceAt(page: Page, x: number, y: number): Promise<number> {
  const png = (await page.screenshot()).toString('base64');
  const probe = await must(page.context().browser(), 'browser').newPage();
  try {
    return await probe.evaluate(async ({ png, x, y }) => {
      const bytes = Uint8Array.from(atob(png), (c) => c.charCodeAt(0));
      const image = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
      const canvas = new OffscreenCanvas(image.width, image.height);
      const context = canvas.getContext('2d');
      if (context === null) throw new Error('no 2d context');
      context.drawImage(image, 0, 0);
      const [r, g, b] = context.getImageData(x, y, 1, 1).data;
      if (r === undefined || g === undefined || b === undefined) throw new Error(`no pixel at ${x}, ${y}`);
      const linear = (c: number) => (c / 255 <= 0.03928 ? c / 255 / 12.92 : ((c / 255 + 0.055) / 1.055) ** 2.4);
      return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
    }, { png, x, y });
  } finally {
    await probe.close();
  }
}

/** The app's surface, at the left edge halfway down: nearly black on dark, nearly white on light. */
async function expectTheme(page: Page, theme: 'light' | 'dark', why: string): Promise<void> {
  const y = Math.round(must(page.viewportSize(), 'viewport').height / 2);
  const shown = expect.poll(() => luminanceAt(page, 2, y), { message: `${why}: ${theme}` });
  await (theme === 'dark' ? shown.toBeLessThan(0.05) : shown.toBeGreaterThan(0.7));
}

const segment = (page: Page, name: 'System' | 'Hell' | 'Dunkel') => page.getByRole('radio', { name, exact: true });

async function openSettings(page: Page): Promise<void> {
  await openMore(page, 'Einstellungen');
  await expect(page).toHaveURL(/\/more\/settings$/);
  await expect(page.getByRole('heading', { name: 'Einstellungen' })).toBeVisible();
}

/** Picks System, Hell or Dunkel. */
async function pickTheme(page: Page, theme: 'system' | 'light' | 'dark'): Promise<void> {
  await openSettings(page);
  const name = { system: 'System', light: 'Hell', dark: 'Dunkel' }[theme] as 'System' | 'Hell' | 'Dunkel';
  await segment(page, name).click();
  await expect(segment(page, name)).toBeChecked();
}

/** Three stores and a row without one, so the store dividers show their tints. */
async function seedStores(page: Page, email: string): Promise<void> {
  const api = await apiAs(email);
  const { data: stores, error } = await api.from('stores').select('id, name, household_id');
  if (error) throw error;
  const store = (name: string) => must(stores.find((s) => s.name === name), `store ${name}`);
  const rows = [
    ['Vollmilch', 'Supermarkt'], ['Bananen', 'Supermarkt'], ['Brot', 'Bäckerei'], ['Butter', 'Supermarkt'], ['Zahnpasta', 'Drogerie'],
    ['Kerzen', null],
  ] as const;
  const { error: inserted } = await api.from('items').insert(rows.map(([name, at]) => ({
    household_id: firstOf(stores, 'store').household_id,
    name,
    store_id: at ? store(at).id : null,
  })));
  if (inserted) throw inserted;
  for (const [name] of rows) await expect(itemRow(page, name)).toBeVisible();
}

/** Shoots the main screens: the list, the add and edit sheets, a dialog, a snackbar and More's pages. */
async function tour(page: Page, theme: 'light' | 'dark'): Promise<void> {
  const shot = async (n: string, name: string) => {
    // Off the tab bar, whose tooltips would show in the shot.
    await page.mouse.move(0, 0);
    await screenshot(page, `theme-${theme}-${n}-${name}`);
  };
  await openTab(page, 'Liste');
  await expect(storeDivider(page, 'Supermarkt')).toBeVisible();
  await expectTheme(page, theme, 'the list');
  await shot('01', 'list');

  await enterItem(page, 'Äpfel');
  await shot('02', 'add-sheet');
  await closeSheet(page);

  await openEdit(page, 'Vollmilch');
  await shot('03', 'edit-sheet');
  await editSheet(page).getByRole('button', { name: 'Abbrechen' }).click();
  await expect(editSheet(page)).toHaveCount(0);

  // Job 22: the invite dialog became More's Einladungen page.
  await openMore(page, 'Leute einladen');
  await page.getByRole('button', { name: 'Neue Einladung' }).click();
  await expect(inviteCodeLabel(page).first()).toBeVisible();
  await shot('04', 'invites');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expectTheme(page, theme, 'More');
  await shot('05', 'more');

  await openSettings(page);
  await shot('06', 'settings');
  await page.getByRole('button', { name: /^Sprache/ }).click();
  await expect(page).toHaveURL(/\/more\/settings\/language$/);
  await shot('07', 'language');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await page.getByRole('button', { name: 'Zurück' }).click();

  // Job 78: stores and categories are the List tab's Anpassen.
  await openStores(page);
  await shot('08', 'stores');
  await storeRow(page, null).click();
  await expect(page.getByRole('heading', { name: 'Ohne Laden', exact: true })).toBeVisible();
  await shot('09', 'categories');
  await openTab(page, 'Liste');
  await openTab(page, 'Mehr');
  await expect(page).toHaveURL(/\/more$/);

  await page.getByRole('button', { name: /^Zugänge/ }).click();
  await expect(page.getByText('MCP-Server', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Kopieren' }).first().click();
  // The snackbar's text, not the screen-reader announcement of it.
  const copied = page.locator('span').filter({ hasText: /^Kopiert$/ });
  await expect(copied).toBeVisible();
  await shot('10', 'access-snackbar');
  // Gone before the next shots.
  await expect(copied).toHaveCount(0);
  await page.getByRole('button', { name: 'Zurück' }).click();

  await page.getByRole('button', { name: 'Konto', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Konto löschen', exact: true })).toBeVisible();
  await shot('11', 'account');
  await page.getByRole('button', { name: 'Zurück' }).click();
}

test('Dunkel switches every screen at once and survives a reload; System follows the device live', async ({ page }) => {
  test.setTimeout(240_000);
  const email = newEmail('theme');
  await page.goto('/login');
  await expect(page.getByRole('button', { name: 'Weiter mit E-Mail' })).toBeVisible();
  await expectTheme(page, 'light', 'the login of a light browser');
  await screenshot(page, 'theme-light-12-login');
  await signUpWithHousehold(page, email, { stores: ['Supermarkt', 'Bäckerei', 'Drogerie'] });
  await seedStores(page, email);

  await openSettings(page);
  await expect(segment(page, 'System'), 'the device setting by default').toBeChecked();
  await expect(segment(page, 'Hell')).not.toBeChecked();
  await expect(segment(page, 'Dunkel')).not.toBeChecked();
  await expectTheme(page, 'light', 'a light browser, the default');
  await tour(page, 'light');

  await pickTheme(page, 'light');
  await expectTheme(page, 'light', 'following off keeps what showed');
  await pickTheme(page, 'dark');
  await expectTheme(page, 'dark', 'at once, without a reload');
  await tour(page, 'dark');
  await page.reload();
  // The reload stays on the page it was on (More).
  await openTab(page, 'Liste');
  await expect(itemRow(page, 'Vollmilch')).toBeVisible();
  await expectTheme(page, 'dark', 'kept on the device');

  await page.emulateMedia({ colorScheme: 'dark' });
  await pickTheme(page, 'light');
  await expectTheme(page, 'light', 'Hell wins over a dark device');

  await pickTheme(page, 'system');
  await expectTheme(page, 'dark', 'follows the dark device');
  await expect(segment(page, 'System'), 'still System').toBeChecked();
  await page.emulateMedia({ colorScheme: 'light' });
  await expectTheme(page, 'light', 'and back, live');

  await pickTheme(page, 'dark');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await page.getByRole('button', { name: /^Abmelden/ }).click();
  await expectSignedOutStart(page);
  await expectTheme(page, 'dark', 'the pick outlives the session');
  await screenshot(page, 'theme-dark-12-start');
});
