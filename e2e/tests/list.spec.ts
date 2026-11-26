import { expect, test } from './fixtures';
import { groupHeadings } from './catalog';
import {
  actionSnackBar, addedNote, addField, addItem, closeSheet, editField, enterItem, itemRow, newEmail, openEdit, pickInSheet, putBack, saveEdit, screenshot,
  signUpWithHousehold, tick, tickSaved, typeInto, usedRow,
} from './helpers';

test.beforeEach(async ({ page }) => {
  await signUpWithHousehold(page, newEmail('list'));
});

test('adds are grouped by category in route order', async ({ page }) => {
  for (const item of ['Klopapier', '2 Vollmilch', 'Äpfel', 'Quietscheentchen', 'Brot']) {
    await addItem(page, item);
  }
  await expect(itemRow(page, 'Quietscheentchen')).toBeVisible();
  await expect(itemRow(page, 'Vollmilch')).toHaveAccessibleName('Vollmilch 2');

  // Until the server classifies the last add, it waits under "Wird einsortiert …".
  await expect.poll(() => groupHeadings(page))
    .toEqual(['Obst & Gemüse', 'Brot & Backwaren', 'Kühlregal', 'Haushalt', 'Sonstiges']);
  await screenshot(page, '02-grouped-list');
});

test('a tick shows "Abgehakt: <name>" with Rückgängig for the last tick; once it is gone, a tap under "Zuletzt verwendet" brings the item back', async ({ page }) => {
  await addItem(page, 'Joghurt');
  await addItem(page, '2 Bananen');
  await expect(itemRow(page, 'Joghurt')).toBeVisible();

  await tick(page, 'Joghurt');
  const joghurt = actionSnackBar(page, 'Abgehakt: Joghurt');
  await expect(joghurt).toBeVisible();
  await screenshot(page, '03a-tick-undo-snackbar');
  await joghurt.getByRole('button', { name: 'Rückgängig' }).click();
  await expect(itemRow(page, 'Joghurt'), 'Rückgängig puts it back').toBeVisible();
  await expect(joghurt).toHaveCount(0);

  await tick(page, 'Joghurt');
  await tick(page, 'Bananen');
  const bananen = actionSnackBar(page, 'Abgehakt: Bananen');
  await expect(bananen, 'the last tick\'s snackbar replaces the one before').toBeVisible();
  await expect(actionSnackBar(page, 'Abgehakt: Joghurt')).toHaveCount(0);
  await expect(bananen, 'it goes away by itself').toHaveCount(0, { timeout: 15_000 });

  await page.getByRole('button', { name: 'Zuletzt verwendet' }).click();
  await expect(usedRow(page, 'Bananen'), 'the row reads like the list\'s, quantity included').toHaveAccessibleName('Bananen 2 Wieder auf die Liste');
  await expect(usedRow(page, 'Joghurt')).toBeVisible();
  await screenshot(page, '03-recently-used');

  await usedRow(page, 'Joghurt').click();
  await expect(itemRow(page, 'Joghurt')).toBeVisible();
  await expect(usedRow(page, 'Joghurt')).toHaveCount(0);
  await screenshot(page, '03b-put-back');

  await tickSaved(page, 'Joghurt');
  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect(itemRow(page, 'Joghurt'), 'the tick persisted on the server').toHaveCount(0);

  await putBack(page, 'Joghurt');
  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect(itemRow(page, 'Joghurt'), 'putting it back persisted on the server').toBeVisible();
});

test('adding an item that is already on the list does not duplicate it', async ({ page }) => {
  await addItem(page, 'Butter');
  await expect(itemRow(page, 'Butter')).toBeVisible();
  await enterItem(page, 'butter');
  await expect(addedNote(page, 'Butter steht schon auf der Liste')).toBeVisible();
  await closeSheet(page);
  await expect(itemRow(page, 'Butter')).toHaveCount(1);
});

test('edit changes name, quantity and category, and they survive a reload', async ({ page }) => {
  await addItem(page, 'Sprudel');
  await openEdit(page, 'Sprudel');
  await typeInto(editField(page, 'Bezeichnung'), 'Mineralwasser');
  await typeInto(editField(page, 'Menge'), '6 Flaschen');
  await pickInSheet(page, 'Kategorie', 'Getränke');
  await screenshot(page, '04-edit-sheet');
  await saveEdit(page);

  await expect(itemRow(page, 'Mineralwasser')).toHaveAccessibleName('Mineralwasser 6 Flaschen');
  await page.reload();
  await expect(itemRow(page, 'Mineralwasser')).toBeVisible();
  const headings = await page.getByRole('heading', { level: 2 }).allTextContents();
  expect(headings).toContain('Getränke');
});
