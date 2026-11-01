import { expect, type Page, test } from './fixtures';
import { openStoreLayout, storeOf } from './catalog';
import {
  addedNote, addField, addSheet, closeSheet, createInviteCode, joinWithCode, newEmail, openMore, openTab, screenshot, signUp,
  signUpWithHousehold, typeInto,
} from './helpers';

/** A store's row under Mehr → Läden. */
const storeRow = (page: Page, store: string) =>
  page.getByRole('button', { name: `${store} Reihenfolge bearbeiten`, exact: true });

test('OWN STORE: made in the add sheet and picked at once, then renamed and deleted under Mehr → Läden', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('own-store'));
  await addField(page).click();
  await expect(addSheet(page)).toBeVisible();
  await typeInto(addField(page), 'Milch');
  await expect(addSheet(page).getByRole('button', { name: /, Wie getippt(,|$)/ })).toBeVisible();
  await page.getByRole('button', { name: /^Laden: / }).click();
  await page.getByRole('button', { name: 'Neuen Laden anlegen' }).click();
  const field = page.getByRole('textbox', { name: 'Name des Ladens' });
  await expect(field, 'focus moves into the new store\'s field').toBeFocused();
  await typeInto(field, 'Rewe');
  await screenshot(page, '58-01-picker-inline-field');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('button', { name: 'Laden: Rewe' }), 'created and picked').toBeVisible();
  await expect(field).toHaveCount(0);
  await expect(addField(page), 'focus is back in the add field').toBeFocused();
  await screenshot(page, '58-02-picker-created-selected');
  await page.keyboard.press('Enter');
  await expect(addedNote(page).first()).toBeVisible();
  await closeSheet(page);
  await expect.poll(() => storeOf(page, 'Milch'), { message: 'the item is under the Rewe divider' }).toBe('Rewe');

  await openStoreLayout(page, 'Rewe');
  await expect(page.getByText(/ verschieben$/), 'every category, like a preset store\'s layout').toHaveCount(11);
  await page.getByRole('button', { name: 'Zurück' }).click();

  await openMore(page, 'Läden');
  await expect(storeRow(page, 'Rewe')).toBeVisible();
  await page.getByRole('button', { name: 'Optionen für Rewe' }).click();
  await page.getByRole('menuitem', { name: 'Rewe umbenennen' }).click();
  const rename = page.getByRole('textbox', { name: 'Name des Ladens' });
  await expect(rename).toBeFocused();
  await typeInto(rename, 'Rewe Markt');
  await page.keyboard.press('Enter');
  await expect(storeRow(page, 'Rewe Markt')).toBeVisible();
  await screenshot(page, '58-03-stores-renamed');

  await page.getByRole('button', { name: 'Optionen für Rewe Markt' }).click();
  await page.getByRole('menuitem', { name: 'Rewe Markt löschen' }).click();
  await expect(page.getByText('1 offener Artikel kommt zu „Ohne Laden“. Sein Laufweg geht mit.')).toBeVisible();
  await screenshot(page, '58-04-stores-delete-confirm');
  await page.getByRole('button', { name: 'Löschen', exact: true }).click();
  await expect(storeRow(page, 'Rewe Markt')).toHaveCount(0);

  await openTab(page, 'Liste');
  await expect.poll(() => storeOf(page, 'Milch'), { message: 'the item has no store now' }).toBe('Ohne Laden');
});

test('OWN STORE: a store one member adds shows for the other at once, with its layout', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter-store'));
  const code = await createInviteCode(peter);
  const lea = await (await browser.newContext()).newPage();
  await signUp(lea, newEmail('lea-store'));
  await joinWithCode(lea, code);
  await openMore(lea, 'Läden');
  await expect(storeRow(lea, 'Edeka')).toBeVisible();

  await openMore(peter, 'Läden');
  await peter.getByRole('button', { name: 'Neuen Laden anlegen' }).click();
  await typeInto(peter.getByRole('textbox', { name: 'Name des Ladens' }), 'Kaufland');
  await peter.keyboard.press('Enter');
  await expect(storeRow(peter, 'Kaufland')).toBeVisible();

  await expect(storeRow(lea, 'Kaufland'), 'live on the other phone, no reload').toBeVisible();
  await storeRow(lea, 'Kaufland').click();
  await expect(lea.getByText('Kaufland: Reihenfolge')).toBeVisible();
  await expect(lea.getByText(/ verschieben$/)).toHaveCount(11);
});
