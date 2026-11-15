// Job 190: prices on the list's rows, a subtotal per store and the list's total under the list,
// in the household's currency, behind the PostHog flag `prices-and-trip-total` (Free, no
// entitlement). A price never ticks the item. The whole household sees prices, totals and the
// currency live.
import { type Browser, type Locator, type Page, expect, test } from './fixtures';
import { setStore, storeOf } from './catalog';
import {
  addItem, type ConsentChoice, createInviteCode, editField, expectFieldValue, fakeCollector, itemRow, joinWithCode, newEmail, openEdit,
  openMore, openTab, saveEdit, screenshot, signUp, createHousehold, skipInvite, typeInto, wheelTo,
  within,
} from './helpers';

const flag = 'prices-and-trip-total';

/** A money pattern: "2,38 €" is written with a no-break space, which `\s` matches. */
const money = (text: string): string => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/ /g, '\\s');

/** A row's price chip, its own button: "Preis für Milch" without a price, else with the line's total. */
const priceChip = (page: Page, name: string, amount?: string): Locator =>
  page.getByRole('button', {
    name: new RegExp(amount === undefined ? `^Preis für ${name}(: .*)?$` : `^Preis für ${name}: ${money(amount)}, ändern$`),
  });

/** The bar under the list: "Einkaufssumme 5,83 €, 2 mit Preis, 0 offen". */
const totalBar = (page: Page, amount?: string, priced?: number, open?: number): Locator =>
  page.getByText(new RegExp(
    amount === undefined ? '^Einkaufssumme ' : `^Einkaufssumme ${money(amount)}, ${priced} mit Preis, ${open} offen$`,
  ));

/** A store section's last line: "Summe Lidl 2,38 €". */
const subtotal = (page: Page, store: string, amount: string): Locator =>
  page.getByText(new RegExp(`^Summe ${store} ${money(amount)}$`));

/**
 * The editor's line under the fields ("Zusammen 2,38 € · Summe danach 2,38 €"). On the web it is
 * not text of its own: the open row's group carries it in its name.
 */
const editorLine = (page: Page, line: RegExp): Locator =>
  page.getByRole('group', { name: line }).or(page.getByText(line)).first();

const priceField = (page: Page): Locator => page.getByRole('textbox', { name: 'Preis', exact: true });

/**
 * A signed-in page in its own context whose PostHog flags say [flagOn] for prices, analytics
 * allowed unless [consent] says decline.
 */
async function member(
  browser: Browser,
  email: string,
  { flagOn = true, consent = 'accept' }: { flagOn?: boolean; consent?: ConsentChoice } = {},
): Promise<Page> {
  const context = await browser.newContext();
  await fakeCollector(context, { flags: { [flag]: flagOn } });
  const page = await context.newPage();
  await signUp(page, email, '/', { consent });
  return page;
}

/** Opens [name]'s price editor from its chip, types [price] and saves with Fertig. */
async function enterPrice(page: Page, name: string, price: string): Promise<void> {
  await priceChip(page, name).click();
  await typeInto(priceField(page), price);
  await page.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(priceField(page), 'the editor closes on Fertig').toHaveCount(0);
}

test('without the flag a row has no price chip and the list no total', async ({ browser }) => {
  const page = await member(browser, newEmail('prices-off'), { flagOn: false });
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Milch');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(priceChip(page, 'Milch'), 'no price chip').toHaveCount(0);
  await expect(totalBar(page), 'no total bar').toHaveCount(0);
  await openMore(page, 'Unser Haushalt');
  await expect(page).toHaveURL(/\/more\/household$/);
  await expect(page.getByText('Währung', { exact: true }), 'no currency on the household page').toHaveCount(0);
});

// Legal §18 FL1' (job 257): an install that declined analytics gets the flags PostHog serves the
// one id all such installs share, so a flag released to 100 % reaches it too.
for (const flagOn of [true, false]) {
  test(`declined analytics, the flag served ${flagOn ? 'on' : 'off'}: ${flagOn ? 'a' : 'no'} price chip`, async ({ browser }) => {
    const page = await member(browser, newEmail('prices-declined'), { flagOn, consent: 'decline' });
    await createHousehold(page);
    await skipInvite(page);
    await addItem(page, 'Milch');
    await expect(itemRow(page, 'Milch')).toBeVisible();
    await expect(priceChip(page, 'Milch')).toHaveCount(flagOn ? 1 : 0);
  });
}

test('a price does not tick the item; the household sees prices, store subtotals and the total live', async ({ browser }) => {
  const peter = await member(browser, newEmail('prices-peter'));
  await createHousehold(peter, { stores: ['Lidl', 'dm'] });
  await skipInvite(peter);
  await addItem(peter, '2 Milch');
  await addItem(peter, 'Zahnpasta');
  await addItem(peter, 'Brot');
  await setStore(peter, 'Milch', 'Lidl');
  await setStore(peter, 'Zahnpasta', 'dm');
  await setStore(peter, 'Brot', 'Lidl');
  await expect.poll(() => storeOf(peter, 'Milch')).toBe('Lidl');
  await expect.poll(() => storeOf(peter, 'Zahnpasta')).toBe('dm');
  const code = await createInviteCode(peter);

  const lea = await member(browser, newEmail('prices-lea'));
  await joinWithCode(lea, code, 'Unser Haushalt');
  await expect(itemRow(lea, 'Milch')).toBeVisible();
  await expect(totalBar(lea, '0,00 €', 0, 3), 'no prices yet: three open').toBeVisible();

  // 2 Milch at 1,19 € each: the stepper starts at the row's 2, the line is 2,38 €.
  await priceChip(peter, 'Milch').click();
  await typeInto(priceField(peter), '1,19');
  await expect(editorLine(peter, /Zusammen 2,38\s€ · Summe danach 2,38\s€$/), 'the other value and the total after it').toBeVisible();
  await screenshot(peter, 'prices-02-editor');
  await peter.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(priceChip(peter, 'Milch', '2,38 €'), 'the row shows the line total').toBeVisible();
  await expect(itemRow(peter, 'Milch'), 'a price does not tick the item').toBeVisible();
  await expect(itemRow(peter, 'Milch')).not.toBeChecked();

  await enterPrice(peter, 'Zahnpasta', '3,45');
  await expect(priceChip(peter, 'Zahnpasta', '3,45 €')).toBeVisible();
  await expect(subtotal(peter, 'Lidl', '2,38 €')).toBeVisible();
  await expect(subtotal(peter, 'dm', '3,45 €')).toBeVisible();
  await expect(totalBar(peter, '5,83 €', 2, 1), 'the total over both stores, Brot still open').toBeVisible();
  await screenshot(peter, 'prices-01-list');

  await within(3_000, (timeout) => expect(priceChip(lea, 'Milch', '2,38 €'), 'the price shows for the partner').toBeVisible({ timeout }));
  await within(3_000, (timeout) => expect(priceChip(lea, 'Zahnpasta', '3,45 €')).toBeVisible({ timeout }));
  await expect(subtotal(lea, 'Lidl', '2,38 €'), 'the partner\'s Lidl subtotal').toBeVisible();
  await expect(subtotal(lea, 'dm', '3,45 €'), 'the partner\'s dm subtotal').toBeVisible();
  await expect(totalBar(lea, '5,83 €', 2, 1), 'the partner\'s total, without a reload').toBeVisible();
  await expect(itemRow(lea, 'Milch')).not.toBeChecked();
  await screenshot(lea, 'prices-03-partner-live');

  await enterPrice(peter, 'Brot', '-0,25');
  await within(3_000, (timeout) => expect(totalBar(lea, '5,58 €', 3, 0), 'a negative line (a deposit) counts').toBeVisible({ timeout }));
  await expect(subtotal(lea, 'Lidl', '2,13 €')).toBeVisible();
});

test('a member changes the household currency and the partner\'s amounts follow live', async ({ browser }) => {
  const peter = await member(browser, newEmail('currency-peter'));
  await createHousehold(peter);
  await skipInvite(peter);
  await addItem(peter, 'Milch');
  const code = await createInviteCode(peter);
  const lea = await member(browser, newEmail('currency-lea'));
  await joinWithCode(lea, code, 'Unser Haushalt');
  await expect(totalBar(lea, '0,00 €', 0, 1), 'EUR by default').toBeVisible();

  await openMore(peter, 'Unser Haushalt');
  const currency = peter.getByRole('button', { name: /^EUR · €/ });
  await wheelTo(peter, currency);
  await currency.click();
  await peter.getByRole('radio', { name: 'CHF', exact: true }).click();
  await expect(peter.getByRole('button', { name: /^CHF/ })).toBeVisible();

  await within(3_000, (timeout) => expect(totalBar(lea, '0,00 CHF', 0, 1), 'the partner\'s total turns to CHF live').toBeVisible({ timeout }));

  await openTab(peter, 'Liste');
  await enterPrice(peter, 'Milch', '1,50');
  await expect(priceChip(peter, 'Milch', '1,50 CHF'), 'a new price is in the new currency').toBeVisible();
  await within(3_000, (timeout) => expect(priceChip(lea, 'Milch', '1,50 CHF')).toBeVisible({ timeout }));
  await expect(totalBar(lea, '1,50 CHF', 1, 0)).toBeVisible();
  await screenshot(lea, 'prices-04-currency-chf');
});

test('the price field drops letters as they are typed', async ({ browser }) => {
  const page = await member(browser, newEmail('prices-letters'));
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Milch');
  await priceChip(page, 'Milch').click();
  const field = priceField(page);
  await field.click();
  await expect(field).toBeFocused();
  await page.keyboard.type('1a2b,5xc9');
  await expect(field, 'letters and a third decimal are dropped').toHaveValue('12,59');
  await page.keyboard.insertText('Milch');
  await expect(field, 'pasted letters are dropped').toHaveValue('12,59');
  await page.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(priceChip(page, 'Milch', '12,59 €')).toBeVisible();
});

test('a scale weight replaces the planned one; a typed total keeps its unit price when the quantity changes', async ({ browser }) => {
  const page = await member(browser, newEmail('prices-weight'));
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Bananen');
  await openEdit(page, 'Bananen');
  await typeInto(editField(page, 'Menge'), '846 g');
  await saveEdit(page);
  await expect(itemRow(page, 'Bananen 846 g'), 'the planned weight on the list').toBeVisible();

  await priceChip(page, 'Bananen').click();
  const weight = page.getByRole('textbox', { name: 'Gewicht in kg', exact: true });
  await expectFieldValue(weight, '0,846');
  await typeInto(priceField(page), '1,99');
  await typeInto(weight, '1,02');
  await page.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(itemRow(page, 'Bananen 1,02 kg'), 'the scale weight replaced the planned one').toBeVisible();
  await expect(priceChip(page, 'Bananen', '2,03 €'), '1,99 € per kg times 1,02 kg').toBeVisible();

  await addItem(page, '2 Joghurt');
  await priceChip(page, 'Joghurt').click();
  await page.getByRole('radio', { name: 'Gesamt', exact: true }).click();
  await typeInto(priceField(page), '1,38');
  await expect(editorLine(page, /Das sind 0,69\s€ pro Stück · /)).toBeVisible();
  await page.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(priceChip(page, 'Joghurt', '1,38 €')).toBeVisible();
  await openEdit(page, 'Joghurt');
  await typeInto(editField(page, 'Menge'), '3');
  await saveEdit(page);
  await expect(priceChip(page, 'Joghurt', '2,07 €'), 'the unit price stays, the line scales').toBeVisible();
  await expect(totalBar(page, '4,10 €', 2, 0)).toBeVisible();
});

test('the stepper changes only the count of a quantity like "2 x 500 g"', async ({ browser }) => {
  const page = await member(browser, newEmail('prices-stepper'));
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Nudeln');
  await openEdit(page, 'Nudeln');
  await typeInto(editField(page, 'Menge'), '2 x 500 g');
  await saveEdit(page);
  await expect(itemRow(page, 'Nudeln 2 x 500 g')).toBeVisible();

  await priceChip(page, 'Nudeln').click();
  await page.getByRole('button', { name: 'Eins mehr', exact: true }).click();
  await typeInto(priceField(page), '0,99');
  await page.getByRole('button', { name: 'Fertig', exact: true }).click();
  await expect(itemRow(page, 'Nudeln 3 x 500 g'), 'only the count changed, not "3 500 g"').toBeVisible();
  await expect(priceChip(page, 'Nudeln', '2,97 €'), '0,99 € per pack times 3').toBeVisible();
});
