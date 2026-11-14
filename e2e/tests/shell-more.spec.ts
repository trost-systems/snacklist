import { readFileSync } from 'node:fs';
import { expect, type Locator, test, type Page } from './fixtures';
import { openStores, storeRow } from './catalog';
import {
  addField, addItem, boxOf, itemRow, newEmail, password, screenshot, signUpWithHousehold, typeInto, inviteCodeLabel, wheelTo,
  openEmailSignIn,
  onboardingChip,
  openHouseholds,
} from './helpers';

const moreTab = (page: Page) => page.getByRole('tab', { name: 'Mehr' });

async function openMore(page: Page): Promise<void> {
  await moreTab(page).click();
  await expect(page.getByRole('heading', { name: 'Mehr' })).toBeVisible();
}

test('More opens every entry; Nutzungsdaten is a page; the legal rows sit on More; licenses name Snacklist; sign-out ends at the login', async ({ page }) => {
  const email = newEmail('more');
  await signUpWithHousehold(page, email, { stores: ['Supermarkt', 'Drogerie'] });
  await openMore(page);
  await screenshot(page, 'more-01-phone');
  // More is a lazy list taller than the window (job 21 added Feedback): wheel to what is below.
  await wheelTo(page, page.getByText(/^Version \d+\.\d+\.\d+/));
  await wheelTo(page, page.getByRole('button', { name: /^Partner einladen/ }));

  // Job 22: Einladungen, a page below More: a new invite, its code, revoke.
  await page.getByRole('button', { name: /^Partner einladen/ }).click();
  await expect(page).toHaveURL(/\/more\/invites$/);
  await page.getByRole('button', { name: 'Neue Einladung' }).click();
  await expect(inviteCodeLabel(page).first()).toBeVisible();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);

  // Job 206: joining is the list's household sheet's; More offers no join, and back (and Abbrechen) return to the list.
  await expect(page.getByRole('button', { name: /^Partner einladen/ }), 'More is drawn').toBeVisible();
  await expect(page.getByRole('button', { name: /beitreten/ }), 'no join row on More').toHaveCount(0);
  await page.getByRole('tab', { name: 'Liste' }).click();
  for (const leave of ['Zurück', 'Abbrechen']) {
    await openHouseholds(page, 'Unser Haushalt');
    await page.getByRole('button', { name: 'Mit Code beitreten', exact: true }).click();
    await expect(page).toHaveURL(/\/join$/);
    await expect(page.getByRole('textbox', { name: 'Einladungscode' })).toBeVisible();
    await page.getByRole('button', { name: leave, exact: true }).click();
    await expect(addField(page), `${leave} returns to the list`).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Einladungscode' })).toHaveCount(0);
  }
  await openMore(page);
  await expect(page.getByRole('button', { name: 'Kategorien verwalten' }), 'job 78: under Liste → Anpassen now').toHaveCount(0);

  // Job 78: Liste → Anpassen lists every store, Ohne Laden last; a store opens its details.
  await openStores(page);
  for (const store of ['Supermarkt', 'Drogerie']) {
    // The list hides stores without items (job 17b); this screen lists every store.
    await expect(storeRow(page, store), `${store} is listed though empty`).toBeVisible();
  }
  await expect(storeRow(page, null)).toBeVisible();
  await storeRow(page, 'Supermarkt').click();
  await expect(page.getByRole('heading', { name: 'Supermarkt', exact: true }), 'a store opens its details').toBeVisible();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(addField(page), 'back twice: the list').toBeVisible();
  await openMore(page);

  // Job 29d: Zugänge and Konto are two pages, each with its own route.
  await page.getByRole('button', { name: /^Zugänge/ }).click();
  await expect(page).toHaveURL(/\/more\/access$/);
  await expect(page.getByRole('heading', { name: 'Zugänge' })).toBeVisible();
  await expect(page.getByText('MCP-Server', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Konto löschen', exact: true }), 'Konto is its own page').toHaveCount(0);
  await screenshot(page, 'more-04-access');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);

  await page.getByRole('button', { name: 'Konto', exact: true }).click();
  await expect(page).toHaveURL(/\/more\/account$/);
  await expect(page.getByRole('heading', { name: 'Konto' })).toBeVisible();
  // Selectable text is a group named by its text on web, like the MCP URL.
  await expect(page.getByRole('group', { name: email, exact: true }), 'who is signed in').toBeVisible();
  await expect(page.getByRole('button', { name: /^Meine Daten exportieren/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Konto löschen', exact: true })).toBeVisible();
  await expect(page.getByText('MCP-Server', { exact: true }), 'Zugänge is its own page').toHaveCount(0);
  await screenshot(page, 'more-05-account');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);

  // Job 85: the rows carry no hints. No group on More has a label.
  await expect(page.getByText('Daten exportieren, Konto löschen'), 'no row hints').toHaveCount(0);

  // Job 85: Nutzungsdaten is a page with the usage-data switch (this build has a PostHog key), nothing else.
  const usageRow = page.getByRole('button', { name: 'Nutzungsdaten', exact: true });
  await wheelTo(page, usageRow);
  await usageRow.click();
  await expect(page).toHaveURL(/\/more\/usage-data$/);
  await expect(page.getByRole('heading', { name: 'Nutzungsdaten', exact: true })).toBeVisible();
  await expect(page.getByRole('switch', { name: /^Nutzungsdaten und Fehlerberichte senden/ })
    .or(page.getByRole('checkbox', { name: /^Nutzungsdaten und Fehlerberichte senden/ }))).toBeVisible();
  await expect(page.getByRole('button', { name: 'Datenschutzerklärung', exact: true }), 'the policy is a More row, not here')
    .toHaveCount(0);
  await screenshot(page, 'more-06-usage-data');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);
  await expect(page.getByRole('heading', { name: 'Mehr' })).toBeVisible();

  const legalRows = ['Impressum', 'Datenschutzerklärung', 'Nutzungsbedingungen (EULA)', 'Lizenzen'];
  const signOut = page.getByRole('button', { name: /^Abmelden/ });
  await wheelTo(page, signOut);
  await screenshot(page, 'more-07-legal');
  await expect(page.getByRole('heading', { name: 'Rechtliches', exact: true }), 'no label above the legal rows')
    .toHaveCount(0);
  const top = async (target: Locator) => (await boxOf(target)).y;
  const order = [
    page.getByRole('button', { name: 'Hilfe & Kontakt', exact: true }),
    ...legalRows.map((name) => page.getByRole('button', { name, exact: true })),
    signOut,
  ];
  const ys = [];
  for (const target of order) ys.push(await top(target));
  expect(ys, 'help, then the four legal rows, then Abmelden').toEqual([...ys].sort((a, b) => a - b));

  await page.context().route('https://snacklist.app/**', (route) =>
    route.fulfill({ contentType: 'text/html', body: '<title>snacklist.app</title>' }));
  async function opensSitePage(name: string, url: string) {
    const row = page.getByRole('button', { name, exact: true });
    await wheelTo(page, row);
    const popup = page.waitForEvent('popup');
    await row.click();
    expect((await popup).url(), `${name} is the site page, in a new tab`).toBe(url);
    await (await popup).close();
    await expect(page, 'the app stays on More').toHaveURL(/\/more$/);
  }
  await opensSitePage('Datenschutzerklärung', 'https://snacklist.app/datenschutz');
  // Apple's EULA on iOS; the web build links the support page until there are terms of our own.
  await opensSitePage('Nutzungsbedingungen (EULA)', 'https://snacklist.app/support');

  await page.getByRole('button', { name: 'Lizenzen', exact: true }).click();
  await expect.poll(() => page.locator('body').ariaSnapshot(), { message: 'the licenses page names the app and lists packages' })
    .toMatch(/Snacklist[\s\S]*Flutter[\s\S]*bloc/);
  await screenshot(page, 'more-02-licenses');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);
  await expect(page.getByRole('heading', { name: 'Mehr' })).toBeVisible();

  await wheelTo(page, page.getByRole('button', { name: /^Abmelden/ }));
  await page.getByRole('button', { name: /^Abmelden/ }).click();
  await expect(page.getByRole('button', { name: 'Weiter mit E-Mail' })).toBeVisible();
  await expect(page).toHaveURL(/\/login/);
});

test('the Impressum is two taps from the list: Mehr, Impressum (DDG §5); old /more/legal links land on More', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('imprint'));
  await expect(addField(page)).toBeVisible();
  await page.context().route('https://snacklist.app/**', (route) =>
    route.fulfill({ contentType: 'text/html', body: '<title>snacklist.app</title>' }));
  await moreTab(page).click();
  const imprint = page.getByRole('button', { name: 'Impressum', exact: true });
  await wheelTo(page, imprint);
  const popup = page.waitForEvent('popup');
  await imprint.click();
  expect((await popup).url(), 'the imprint on the site, in a new tab').toBe('https://snacklist.app/impressum');
  await (await popup).close();
  await expect(page, 'the app stays on More').toHaveURL(/\/more$/);

  await page.goto('/more/legal');
  await expect(page, 'the Rechtliches page is gone; its link lands on More').toHaveURL(/\/more$/);
  await expect(page.getByRole('heading', { name: 'Mehr' })).toBeVisible();
  await wheelTo(page, imprint);
  await expect(imprint).toBeVisible();
});

test('old /settings links open the right page; back from a deep link goes to More', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('deeplink'));
  await page.goto('/settings?section=account');
  await expect(page).toHaveURL(/\/more\/account$/);
  await expect(page.getByRole('button', { name: 'Konto löschen', exact: true })).toBeVisible();
  await expect(moreTab(page), 'inside the More tab').toBeVisible();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);
  await expect(page.getByRole('heading', { name: 'Mehr' })).toBeVisible();

  await page.goto('/settings');
  await expect(page).toHaveURL(/\/more\/access$/);
  await expect(page.getByText('MCP-Server', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more$/);
});

test('switching to English in Einstellungen changes the whole UI at once and survives a reload', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('lang'));
  await addItem(page, 'Milch');
  await page.keyboard.press('Escape');
  await openMore(page);
  // Job 29e: the language is a list below Einstellungen, each language in its own name.
  await page.getByRole('button', { name: /^Einstellungen/ }).click();
  await expect(page).toHaveURL(/\/more\/settings$/);
  await page.getByRole('button', { name: /^Sprache Wie Gerät \(Deutsch\)/ }).click();
  await expect(page).toHaveURL(/\/more\/settings\/language$/);
  await expect(page.getByRole('radio', { name: /^Wie Gerät/ })).toBeChecked();
  await page.getByRole('radio', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Language' }), 'live, without a restart').toBeVisible();
  await expect(page.getByRole('radio', { name: 'English', exact: true })).toBeChecked();
  await expect(page.getByRole('tab', { name: 'List' })).toBeVisible();
  await screenshot(page, 'more-03-english');
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Language' }), 'kept on the device').toBeVisible();
  await page.getByRole('button', { name: 'Back' }).click();
  await expect(page.getByRole('button', { name: /^Language English/ }), 'Settings names the pick').toBeVisible();
  await page.getByRole('tab', { name: 'List' }).click();
  await expect(page.getByRole('textbox', { name: 'What do you need?' })).toBeVisible();
  await expect(page.getByText('Chilled'), 'a seeded category shows its English name').toBeVisible();
  await page.getByRole('tab', { name: 'More' }).click();
  await expect(page).toHaveURL(/\/more\/settings$/);
  await page.getByRole('button', { name: /^Language/ }).click();
  await page.getByRole('radio', { name: 'Deutsch', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Sprache' })).toBeVisible();
});

/** German UI texts: every app_de.arb message that English words differently, as literal pieces. */
function germanTexts(): string[] {
  const de = JSON.parse(readFileSync(new URL('../../app/l10n/app_de.arb', import.meta.url), 'utf8')) as Record<string, unknown>;
  const en = JSON.parse(readFileSync(new URL('../../app/l10n/app_en.arb', import.meta.url), 'utf8')) as Record<string, unknown>;
  const pieces = new Set<string>();
  for (const [key, value] of Object.entries(de)) {
    if (key.startsWith('@') || typeof value !== 'string' || value === en[key]) continue;
    // Placeholders and plural forms (nested braces) split a message into the literal text around them.
    let depth = 0;
    let outside = '';
    for (const char of value) {
      if (char === '{') depth++;
      if (depth === 0) outside += char;
      else if (char === '}' && depth === 1) outside += '\u0000';
      if (char === '}') depth--;
    }
    for (const piece of outside.split('\u0000')) {
      const text = piece.trim();
      // A piece English shares ("Version" in „Version {version} ist im Store.“) is no German tell.
      if (text.length >= 5 && /\p{L}{4}/u.test(text) && !String(en[key]).includes(text)) pieces.add(text);
    }
  }
  return [...pieces];
}

test.describe('with an English browser', () => {
  test.use({ locale: 'en-US' });

  async function expectNoGerman(page: Page, where: string, german: string[]) {
    const tree = await page.locator('body').ariaSnapshot();
    const found = german.filter((text) => tree.includes(text));
    expect(found, `${where}: German UI text`).toEqual([]);
  }

  test('the app starts in English and no German UI text shows anywhere', async ({ page }) => {
    const german = germanTexts();
    expect(german.length, 'the scan has German texts to look for').toBeGreaterThan(100);
    await page.goto('/');
    await expect(page).toHaveURL(/\/start$/);
    await expect(page.getByRole('button', { name: 'Get started' })).toBeVisible();
    await expectNoGerman(page, 'first screen', german);
    await page.getByRole('button', { name: 'Already have an account? Sign in' }).click();
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole('button', { name: 'Continue with email' })).toBeVisible();
    await expectNoGerman(page, 'login', german);
    await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
    await expectNoGerman(page, 'login email form', german);
    await typeInto(page.getByRole('textbox', { name: 'Email' }), newEmail('english'));
    await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
    await page.getByRole('button', { name: 'Sign up' }).click();
    // Job 19: the analytics consent comes first, in English too.
    await expect(page.getByRole('button', { name: 'Allow', exact: true })).toBeVisible();
    await expectNoGerman(page, 'analytics consent', german);
    await page.getByRole('button', { name: "Don't allow", exact: true }).click();
    // Job 22: onboarding's steps, in English too.
    await expect(page.getByRole('button', { name: /^Create a household/ })).toBeVisible();
    await expectNoGerman(page, 'welcome', german);
    // Job 168b: the guided start's steps.
    await page.getByRole('button', { name: /^Create a household/ }).click();
    await expect(page).toHaveURL(/\/start\/who$/);
    await expect(onboardingChip(page, 'Partner')).toBeVisible();
    await expectNoGerman(page, 'who', german);
    await page.getByRole('button', { name: 'Skip', exact: true }).click();
    await expect(page.getByRole('textbox', { name: 'Household name' })).toBeVisible();
    await expectNoGerman(page, 'household name', german);
    await page.getByRole('button', { name: 'Continue', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Add your own store' })).toBeVisible();
    await expectNoGerman(page, 'stores', german);
    await page.getByRole('button', { name: 'Skip', exact: true }).click();
    await expect(page.getByRole('textbox', { name: 'Anything else?' })).toBeVisible();
    await expectNoGerman(page, 'what you need', german);
    await page.getByRole('button', { name: 'Continue', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Invite someone', exact: true })).toBeVisible();
    await expectNoGerman(page, 'invite', german);
    await page.getByRole('button', { name: 'Invite someone', exact: true }).click();
    await expect(page.getByText(/^valid until /)).toBeVisible();
    await expectNoGerman(page, 'invite card', german);
    await page.getByRole('button', { name: 'Go to the list' }).click();

    const field = page.getByRole('textbox', { name: 'What do you need?' });
    await expect(field).toBeFocused();
    await typeInto(field, 'Milch');
    await expect(page.getByRole('group', { name: 'Add', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Milch, As typed/ })).toBeVisible();
    await expectNoGerman(page, 'add sheet', german);
    await screenshot(page, 'en-01-add-sheet');
    await page.keyboard.press('Enter');
    await page.keyboard.press('Escape');
    await expect(itemRow(page, 'Milch')).toBeVisible();
    await expectNoGerman(page, 'list', german);
    await screenshot(page, 'en-02-list');

    await itemRow(page, 'Milch').click({ button: 'right' });
    await expect(page.getByRole('group', { name: 'Edit', exact: true })).toBeVisible();
    await expectNoGerman(page, 'edit sheet', german);
    await page.getByRole('button', { name: 'Cancel' }).click();

    await page.getByRole('tab', { name: 'More' }).click();
    await expect(page.getByRole('heading', { name: 'More' })).toBeVisible();
    await expectNoGerman(page, 'More', german);
    await page.getByRole('button', { name: /^Access/ }).click();
    await expect(page.getByText('MCP server', { exact: true })).toBeVisible();
    await expectNoGerman(page, 'access', german);
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('button', { name: /^Account/ }).click();
    await expect(page.getByRole('button', { name: 'Delete account' })).toBeVisible();
    await expectNoGerman(page, 'account', german);
    await screenshot(page, 'en-03-settings');
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('button', { name: 'Usage data', exact: true }).click();
    await expect(page.getByRole('switch', { name: /^Send usage data and error reports/ })
      .or(page.getByRole('checkbox', { name: /^Send usage data and error reports/ }))).toBeVisible();
    await expectNoGerman(page, 'usage data', german);
    await page.getByRole('button', { name: 'Back' }).click();
    await wheelTo(page, page.getByRole('button', { name: /^Sign out/ }));
    for (const name of ['Imprint', 'Privacy policy', 'Terms of Use (EULA)', 'Licenses']) {
      await expect(page.getByRole('button', { name, exact: true }), `${name} on More`).toBeVisible();
    }
    await expect(page.getByRole('heading', { name: 'Legal', exact: true }), 'no label above the legal rows').toHaveCount(0);
    await expectNoGerman(page, 'More, the legal rows', german);
    await wheelTo(page, page.getByRole('button', { name: /^Settings/ }));
    await page.getByRole('button', { name: /^Settings/ }).click();
    await expect(page.getByRole('radio', { name: 'Dark', exact: true })).toBeVisible();
    await expectNoGerman(page, 'settings', german);
    await page.getByRole('button', { name: /^Language Device \(English\)/ }).click();
    // The row's line, what the device gives, is part of the radio's name.
    await expect(page.getByRole('radio', { name: 'Device language Currently English', exact: true })).toBeChecked();
    await expectNoGerman(page, 'language list', german);
  });
});

test('wide screens: a rail, a sheet as wide as the list column, More in two panes', async ({ page }) => {
  await page.setViewportSize({ width: 1366, height: 1024 });
  await signUpWithHousehold(page, newEmail('wide'));
  const railList = page.getByRole('tab', { name: 'Liste', exact: true });
  await expect(railList, 'the rail has the tabs').toBeVisible();
  const rail = await boxOf(railList);
  expect(rail.x, 'the rail is on the left').toBeLessThan(120);

  await typeInto(addField(page), 'Butter');
  const sheet = page.getByRole('group', { name: 'Hinzufügen', exact: true });
  await expect(sheet).toBeVisible();
  const box = await boxOf(sheet);
  expect(box.width, 'the sheet keeps to the list column').toBeLessThanOrEqual(641);
  const field = await boxOf(addField(page));
  expect(Math.abs(box.x + box.width / 2 - (field.x + field.width / 2)), 'the input sits under the sheet').toBeLessThan(80);
  await screenshot(page, 'wide-01-sheet-1366');
  await page.keyboard.press('Escape');

  await page.getByRole('tab', { name: 'Mehr', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Konto', exact: true }), 'the sections on the left').toBeVisible();
  await expect(page.getByText('MCP-Server', { exact: true }), 'and a page beside them').toBeVisible();
  const list = await boxOf(page.getByRole('button', { name: 'Konto', exact: true }));
  const detail = await boxOf(page.getByText('MCP-Server', { exact: true }));
  expect(detail.x, 'two panes side by side').toBeGreaterThan(list.x + list.width - 1);
  await page.getByRole('button', { name: 'Konto', exact: true }).click();
  await expect(page).toHaveURL(/\/more\/account$/);
  await expect(page.getByRole('button', { name: 'Konto löschen', exact: true })).toBeInViewport();
  await expect(page.getByText('MCP-Server', { exact: true }), 'the pane shows Konto alone').toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Zurück' }), 'beside the list there is nothing to go back to').toHaveCount(0);
  await screenshot(page, 'wide-02-more-1366');
  // Job 85: the legal rows stay in the left pane, the Impressum one tap away.
  await wheelTo(page, page.getByRole('button', { name: 'Impressum', exact: true }));
  await expect(page.getByRole('button', { name: 'Impressum', exact: true })).toBeInViewport();
  await wheelTo(page, page.getByRole('button', { name: /^Zugänge/ }));
  await page.getByRole('button', { name: /^Zugänge/ }).click();
  await expect(page).toHaveURL(/\/more\/access$/);
  await expect(page.getByText('MCP-Server', { exact: true })).toBeVisible();

  // Job 29e: Einstellungen beside the list, its language list too, with a way back to it.
  await page.getByRole('button', { name: /^Einstellungen/ }).click();
  await expect(page).toHaveURL(/\/more\/settings$/);
  await expect(page.getByRole('radio', { name: 'Dunkel', exact: true })).toBeVisible();
  await page.getByRole('button', { name: /^Sprache Wie Gerät/ }).click();
  await expect(page).toHaveURL(/\/more\/settings\/language$/);
  await expect(page.getByRole('radio', { name: 'English', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Konto', exact: true }), 'the list stays').toBeVisible();
  await screenshot(page, 'wide-04-language-1366');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect(page).toHaveURL(/\/more\/settings$/);

  await page.setViewportSize({ width: 820, height: 1180 });
  await page.getByRole('tab', { name: 'Liste' }).click();
  await expect(addField(page)).toBeVisible();
  await screenshot(page, 'wide-03-list-820');
});
