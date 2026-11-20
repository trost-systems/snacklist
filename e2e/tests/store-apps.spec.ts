// Job 313 (DL1 + SS): behind the PostHog flag `open-store-app`, a store linked to a grocery chain
// gets a key in its list header and an app card on its screen that open the chain's app (on the
// web build: the app's store page; nothing goes to the chain). Stores are matched where they are made, on the stores page and in
// the add sheet's store picker (chains offered while typing, "Ist das …?" once after a plain
// name), and stores made before get asked once from a card on the list. The browser's region
// (de-DE) is the phone's.
import { type Browser, type Page, expect, test } from './fixtures';
import { openStoreDetails, openStores, storeOf, storeRow } from './catalog';
import {
  addSheet, addField, addedNote, closeSheet, fakeCollector, newEmail, openTab, screenshot, signUp, createHousehold, skipInvite, typeInto,
} from './helpers';

const flag = 'open-store-app';

async function newPage(
  browser: Browser,
  { on = true, more = {}, locale }: { on?: boolean; more?: Record<string, boolean>; locale?: string } = {},
): Promise<Page> {
  const context = await browser.newContext(locale === undefined ? {} : { locale });
  await fakeCollector(context, { flags: { [flag]: on, ...more } });
  // The store pages a key opens on the web: answered here, nothing leaves the machine.
  await context.route(/^https:\/\/(play\.google\.com|apps\.apple\.com)\//, (route) =>
    route.fulfill({ status: 200, contentType: 'text/html', body: '<title>chain</title>' }));
  return context.newPage();
}

async function startHousehold(page: Page, tag: string, stores: string[] = []): Promise<void> {
  await signUp(page, newEmail(tag));
  await createHousehold(page, { stores });
  await skipInvite(page);
}

/** Opens Liste → Anpassen's "Laden hinzufügen" and types [name]. */
async function typeNewStore(page: Page, name: string): Promise<void> {
  await page.getByRole('button', { name: 'Laden hinzufügen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), name);
}

/** The URL the next popup opens: what a key or „Öffnen“ opened. */
async function opened(page: Page, tap: () => Promise<void>): Promise<string> {
  const popup = page.context().waitForEvent('page');
  await tap();
  const tab = await popup;
  await tab.waitForLoadState('domcontentloaded');
  const url = tab.url();
  await tab.close();
  return url;
}

test('STORE APPS: the stores page offers chains while typing, asks once after a plain name, and a linked store opens its chain', async ({ browser }) => {
  const page = await newPage(browser);
  await startHousehold(page, 'store-apps-page');
  await openStores(page);

  await typeNewStore(page, 'Re');
  const rewe = page.getByRole('button', { name: 'REWE (Deutschland) wählen' });
  await expect(rewe, 'a chain offered after two letters').toBeVisible();
  await screenshot(page, '313-01-stores-suggestion');
  await rewe.click();
  await expect(storeRow(page, 'REWE'), 'made under the chain\'s name').toBeVisible();
  await expect(page.getByRole('dialog'), 'a suggestion asks nothing').toHaveCount(0);

  await typeNewStore(page, 'Lidl am Markt');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Ist das Lidl (Deutschland)?' })).toBeVisible();
  await screenshot(page, '313-02-stores-question');
  await page.getByRole('button', { name: 'Ja', exact: true }).click();
  await expect(storeRow(page, 'Lidl am Markt')).toBeVisible();

  await typeNewStore(page, 'Aldi');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Welches Aldi?' })).toBeVisible();
  await page.getByRole('button', { name: 'ALDI SÜD', exact: true }).click();

  await typeNewStore(page, 'Wochenmarkt');
  await page.keyboard.press('Enter');
  await expect(storeRow(page, 'Wochenmarkt')).toBeVisible();
  await expect(page.getByRole('heading', { name: /^Ist das |^Welches / }), 'a name of no chain is not asked about').toHaveCount(0);

  await storeRow(page, 'Lidl am Markt').click();
  await expect(page.getByText('Zugeordnet: Lidl · Deutschland')).toBeVisible();
  await expect(page.getByText('Lidl Plus', { exact: true })).toBeVisible();
  await screenshot(page, '313-03-store-screen-app-card');
  expect(await opened(page, () => page.getByRole('button', { name: 'Lidl Plus öffnen' }).click()), 'the web build opens the app\'s store page, never the chain\'s site')
    .toBe('https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus');
  await page.getByRole('button', { name: 'Zurück' }).click();

  await storeRow(page, 'Wochenmarkt').click();
  await expect(page.getByRole('button', { name: 'Kette zuordnen' })).toBeVisible();
  await expect(page.getByRole('button', { name: /öffnen$/ }), 'no chain, no app card').toHaveCount(0);
});

test('STORE APPS: the add sheet asks in place, a two-app chain opens the app the store picked, and the list header carries the key', async ({ browser }) => {
  const page = await newPage(browser);
  await startHousehold(page, 'store-apps-sheet');
  await addField(page).click();
  await expect(addSheet(page)).toBeVisible();
  await typeInto(addField(page), 'Gurken');
  await page.getByRole('button', { name: /^Laden: / }).click();
  await page.getByRole('button', { name: 'Neuen Laden anlegen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), 'Billa');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Ist das BILLA (Österreich)?' }), 'no German Billa: the other countries answer').toBeVisible();
  await expect(page.getByRole('button', { name: 'Laden: Billa' }), 'picked for the item already').toBeVisible();
  await screenshot(page, '313-04-sheet-question');
  await page.getByRole('button', { name: 'Ja', exact: true }).click();
  await expect(addField(page), 'the answer hands the keyboard back to the add field').toBeFocused();
  await page.keyboard.press('Enter');
  await expect(addedNote(page).first()).toBeVisible();
  await closeSheet(page);
  await expect.poll(() => storeOf(page, 'Gurken')).toBe('Billa');
  await expect(page.getByRole('button', { name: 'BILLA öffnen' }), 'the default app, in the header').toBeVisible();
  await expect(page.getByRole('group', { name: 'Öffnet die App des Ladens.' }), 'the one-time tip').toBeVisible();
  await screenshot(page, '313-05-list-header-key');
  expect(await opened(page, () => page.getByRole('button', { name: 'BILLA öffnen' }).click()), 'the header key opens the chain')
    .toBe('https://play.google.com/store/apps/details?id=at.billa.service');
  await expect(page.getByRole('group', { name: 'Öffnet die App des Ladens.' }), 'the first key tap ends the tip').toHaveCount(0);

  await openStoreDetails(page, 'Billa');
  await expect(page.getByRole('radiogroup', { name: 'Welche App soll sich öffnen?' })).toBeVisible();
  await page.getByRole('radio', { name: 'jö Bonus Club' }).click();
  await expect(page.getByRole('button', { name: 'jö Bonus Club öffnen' })).toBeVisible();
  await screenshot(page, '313-06-store-screen-app-choice');

  await page.reload();
  await openTab(page, 'Liste');
  await expect(page.getByRole('button', { name: 'jö Bonus Club öffnen' }), 'the choice is the store\'s, kept by the server').toBeVisible();
  await page.getByRole('button', { name: 'Billa, 1 Artikel' }).click();
  await expect(page.getByRole('button', { name: 'jö Bonus Club öffnen' }), 'folding keeps the key').toBeVisible();
  await expect(page.getByText('Gurken'), 'the header folds; the key is no part of it').toHaveCount(0);
  await page.getByRole('button', { name: 'Billa, 1 Artikel' }).click();
  await expect(page.getByRole('checkbox', { name: 'Gurken' })).toBeVisible();
  await page.getByRole('button', { name: 'Erste Schritte ausblenden' }).click();
  for (const size of ['200%', '250%', '310%']) {
    await page.evaluate((fontSize) => { document.documentElement.style.fontSize = fontSize; }, size);
    await expect(page.getByRole('button', { name: 'jö Bonus Club öffnen' }), `the key at ${size} text`).toBeVisible();
    await screenshot(page, `313-08-list-header-${size.replace('%', '')}`);
  }
});

test('STORE APPS: on the users\' build (add-feedback-list) the chains offered and the question in the added item\'s details are in view and take a tap', async ({ browser }) => {
  const page = await newPage(browser, { more: { 'add-feedback-list': true, 'input-stable-rows': true } });
  await page.setViewportSize({ width: 390, height: 844 });
  await startHousehold(page, 'store-apps-details');
  await addField(page).click();
  await typeInto(addField(page), 'Tomaten');
  await page.keyboard.press('Enter');
  await page.getByRole('button', { name: /^Laden: / }).click();
  await page.getByRole('button', { name: 'Neuen Laden anlegen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), 'Re');
  const rewe = page.getByRole('button', { name: 'REWE (Deutschland) wählen' });
  await expect(rewe, 'scrolled into view above the add field').toBeInViewport({ ratio: 1 });
  await screenshot(page, '313-11-details-suggestion');
  await rewe.click();
  await expect(page.getByRole('button', { name: 'Laden: REWE' }), 'made matched and picked').toBeVisible();

  await page.getByRole('button', { name: 'Laden: REWE' }).click();
  await page.getByRole('button', { name: 'Neuen Laden anlegen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), 'Lidl am Markt');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Ist das Lidl (Deutschland)?' })).toBeVisible();
  const yes = page.getByRole('button', { name: 'Ja', exact: true });
  await expect(yes, 'Ja in view, not under the add field').toBeInViewport({ ratio: 1 });
  await expect(page.getByRole('button', { name: 'Nein, so lassen' })).toBeInViewport({ ratio: 1 });
  await screenshot(page, '313-12-details-question');
  await yes.click();
  await expect(page.getByRole('heading', { name: 'Ist das Lidl (Deutschland)?' }), 'answered').toHaveCount(0);
  await closeSheet(page);
  await openStoreDetails(page, 'Lidl am Markt');
  await expect(page.getByText('Zugeordnet: Lidl · Deutschland')).toBeVisible();
});

test('STORE APPS: stores made before are asked one at a time from a card on the list; an answer is never asked again', async ({ browser }) => {
  // Made while the flag was off: with it on, the guided start's chips are matched already (job 321).
  const flags = { [flag]: false };
  const context = await browser.newContext();
  await fakeCollector(context, { flags });
  const page = await context.newPage();
  await startHousehold(page, 'store-apps-card', ['Lidl', 'dm', 'Baumarkt']);
  flags[flag] = true;
  await page.reload();
  await openTab(page, 'Liste');
  const card = page.getByRole('heading', { name: /^Ist dein „/ });
  await expect(card).toHaveAccessibleName('Ist dein „Lidl“ die Kette Lidl (Deutschland)?');
  await expect(page.getByText('Laden 1 von 2'), 'Baumarkt names no chain').toBeVisible();
  await screenshot(page, '313-07-list-card');
  await page.getByRole('button', { name: 'Ja', exact: true }).click();
  await expect(card).toHaveAccessibleName('Ist dein „dm“ die Kette dm (Deutschland)?');
  await expect(page.getByText('Laden 2 von 2')).toBeVisible();
  await page.getByRole('button', { name: 'Nein', exact: true }).click();
  await expect(card).toHaveCount(0);

  await page.reload();
  await openTab(page, 'Liste');
  await expect(page.getByRole('button', { name: 'Anpassen', exact: true })).toBeVisible();
  await expect(card, 'answered stores are not asked again').toHaveCount(0);
  await openStoreDetails(page, 'Lidl');
  await expect(page.getByText('Zugeordnet: Lidl · Deutschland')).toBeVisible();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await storeRow(page, 'dm').click();
  await expect(page.getByRole('button', { name: 'Kette zuordnen' }), '"Nein" left dm unmatched').toBeVisible();
});

test('STORE APPS: the guided start offers the region\'s chains, matched as they are tapped (OB1)', async ({ browser }) => {
  // A browser set to Austria (job 321): its chains as chips, no hint lines, nothing asked afterwards.
  const page = await newPage(browser, { locale: 'de-AT' });
  await signUp(page, newEmail('store-apps-ob1'));
  await page.getByRole('button', { name: 'Haushalt erstellen' }).click();
  await page.getByRole('button', { name: 'Überspringen', exact: true }).click();
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/stores(\?|$)/);
  const chips = page.getByRole('checkbox');
  const austria = ['BILLA', 'SPAR', 'Hofer', 'Lidl', 'PENNY', 'MPREIS', 'dm', 'Baumarkt'];
  await expect(chips).toHaveCount(austria.length);
  for (const [i, name] of austria.entries()) await expect(chips.nth(i)).toHaveAccessibleName(name);
  await expect(page.getByText(/^Wähl die Läden|^Ohne Läden starten/)).toHaveCount(0);
  await screenshot(page, '321-01-stores-at');
  for (const store of ['BILLA', 'Hofer']) await page.getByRole('checkbox', { name: store, exact: true }).click();
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/need(\?|$)/);
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/invite(\?|$)/, { timeout: 20_000 });
  await skipInvite(page);
  await expect(page.getByRole('heading', { name: /^Ist dein „/ }), 'tapped chips are matched already').toHaveCount(0);
  await openStoreDetails(page, 'Hofer');
  await expect(page.getByText('Zugeordnet: Hofer · Österreich')).toBeVisible();
});

test('STORE APPS: flag off, stores are made and shown as before', async ({ browser }) => {
  const page = await newPage(browser, { on: false });
  await startHousehold(page, 'store-apps-off', ['Lidl']);
  await expect(page.getByRole('heading', { name: /^Ist dein „/ })).toHaveCount(0);
  await openStores(page);
  await typeNewStore(page, 'Rewe');
  await expect(page.getByRole('button', { name: /wählen$/ })).toHaveCount(0);
  await page.keyboard.press('Enter');
  await expect(storeRow(page, 'Rewe')).toBeVisible();
  await expect(page.getByRole('heading', { name: /^Ist das / })).toHaveCount(0);
  await storeRow(page, 'Lidl').click();
  await expect(page.getByRole('heading', { name: 'Lidl', exact: true })).toBeVisible();
  await expect(page.getByText(/^Zugeordnet|Kette zuordnen/)).toHaveCount(0);
});
