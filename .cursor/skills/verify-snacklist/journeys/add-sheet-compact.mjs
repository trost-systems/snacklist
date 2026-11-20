// Feature quick-add, sub-features qa-compact, qa-compact-chips, qa-compact-behind and
// qa-compact-close (flag add-sheet-compact on top of add-feedback-list, job 322, AS1), on
// demo-familie. After an add the sheet shows one row of chips under the grab handle (Menge with −
// and +, store, category, details) and no added note, Undo or close key; each pick or step is saved
// at once and lands in the database. The list behind the sheet is empty before the first add, then
// shows only the last two adds. An add of what is on the list keeps today's "already on the list"
// note. Enter in the empty field closes the sheet, and so does a tap on the list behind it, also on
// one of the two rows there, which stays as it is.
//
//   VH_DEFINES="FLAGS_ON=add-sheet-compact" helpers/launch.sh
//   node journeys/add-sheet-compact.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { addField, addSheet, apiAs, capture, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: add-sheet-compact.mjs <evidence dir> [--lang de|en]');
const names = lang === 'de' ? ['Kefir', 'Quark', 'Senf'] : ['Kefir', 'Cottage cheese', 'Mustard'];
const details = 'Bio, 1 l';
const testStore = 'Hofladen Sonnenhang';

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const must = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};
const stored = async (name) =>
  must(await api.from('items').select('name, quantity, properties, status, store_id, category_id, stores(name), categories(name)')
    .eq('household_id', user.householdId).eq('name', name).eq('status', 'active'))[0] ?? null;
const until = async (what, check) => {
  for (let i = 0; i < 40; i++) {
    const value = await check();
    if (value) return value;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for ${what}`);
};
// The picks teach the classifier; each item gets the category it was added with back before it
// goes, so other journeys find the household as seeded.
const firstCategories = new Map();
const forget = async () => {
  for (const [name, category] of firstCategories) {
    must(await api.from('items').update({ category_id: category }).eq('household_id', user.householdId).eq('name', name).eq('status', 'active'));
  }
  must(await api.from('items').delete().eq('household_id', user.householdId).in('name', names));
  must(await api.from('stores').delete().eq('household_id', user.householdId).eq('name', testStore));
};
await forget();
const target = { id: must(await api.rpc('add_store', { p_household: user.householdId, p_name: testStore })), name: testStore };

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
const sheet = addSheet(page, L);
const add = async (name) => {
  await typeInto(addField(page, L), name);
  await page.keyboard.press('Enter');
  const row = await until(`${name} in the database`, () => stored(name));
  if (!firstCategories.has(name)) firstCategories.set(name, row.category_id);
  await page.waitForTimeout(400);
  return row;
};
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}) on ${inst.webUrl}`);

  await addField(page, L).click();
  await sheet.waitFor();
  await page.waitForTimeout(500);
  await capture(page, dir, '01-opened-list-behind-empty');
  const closeButtons = await sheet.getByRole('button', { name: L('close'), exact: true }).count();
  log(`opened: ${closeButtons} button named "${L('close')}" in the sheet (the grab handle)`);
  if (closeButtons !== 1) throw new Error(`expected only the grab handle as ${L('close')}, found ${closeButtons}`);

  const first = await add(names[0]);
  await capture(page, dir, '02-first-add-chips');
  const added = await sheet.getByText(L('addedItem', { name: '' }).trim()).count();
  const undo = await sheet.getByRole('button', { name: L('undo'), exact: true }).count();
  log(`after the add: ${added} added note, ${undo} ${L('undo')} button; stored ${JSON.stringify(first)}`);
  if (added || undo) throw new Error('the compact sheet still shows the added note or Undo');
  const sheetBox = await sheet.boundingBox();
  const fieldBox = await addField(page, L).boundingBox();
  log(`sheet top ${sheetBox.y.toFixed(0)} px, add field bottom ${(fieldBox.y + fieldBox.height).toFixed(0)} px: editing takes ${(fieldBox.y + fieldBox.height - sheetBox.y).toFixed(0)} px`);

  await sheet.getByRole('button', { name: L('quantityPlus'), exact: true }).click();
  const stepped = await until('the + step saved', async () => ((await stored(names[0]))?.quantity === '2' ? stored(names[0]) : null));
  log(`+ saved quantity "${stepped.quantity}"`);

  await sheet.getByRole('button', { name: new RegExp(`^${L('chipStore', { name: '' })}`) }).first().click();
  await page.waitForTimeout(400);
  await capture(page, dir, '03-store-options-one-line');
  await sheet.getByRole('button', { name: target.name, exact: true }).click();
  const moved = await until(`store ${target.name} saved`, async () => ((await stored(names[0]))?.store_id === target.id ? stored(names[0]) : null));
  log(`store picked: ${moved.stores?.name}`);

  await sheet.getByRole('button', { name: new RegExp(`^${L('chipCategory', { name: '' })}`) }).first().click();
  await page.waitForTimeout(400);
  await capture(page, dir, '04-category-options-one-line');
  const categories = must(await api.from('categories').select('id, name').eq('household_id', user.householdId));
  // Stored by its German name, shown in the app's language.
  const category = categories.find((c) => c.name === 'Getränke');
  const option = sheet.getByRole('button', { name: lang === 'de' ? 'Getränke' : 'Drinks', exact: true });
  await option.scrollIntoViewIfNeeded();
  await option.click();
  const filed = await until(`category ${category.name} saved`, async () => ((await stored(names[0]))?.category_id === category.id ? stored(names[0]) : null));
  log(`category picked: ${filed.categories?.name}`);

  await sheet.getByRole('button', { name: new RegExp(`^${L('fieldProperties')}`) }).click();
  const field = sheet.getByRole('textbox', { name: L('fieldProperties') });
  await field.waitFor();
  await typeInto(field, details);
  await capture(page, dir, '05-details-field');
  await page.keyboard.press('Enter');
  const described = await until('details saved', async () => ((await stored(names[0]))?.properties === details ? stored(names[0]) : null));
  log(`details saved: "${described.properties}"`);
  await page.waitForTimeout(300);
  await capture(page, dir, '06-details-on-chip');

  await add(names[1]);
  await add(names[2]);
  await capture(page, dir, '07-third-add-last-two-behind');

  // The rows behind the open sheet have no semantics; the newest sits right above its top edge.
  const top = (await sheet.boundingBox()).y;
  await page.mouse.click(120, top - 20);
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });
  await page.waitForTimeout(600);
  const tapped = await stored(names[2]);
  log(`a tap on the row behind the sheet (${names[2]}) closed it; the row is ${tapped?.status ?? 'gone'}`);
  if (tapped?.status !== 'active') throw new Error(`the tap behind the sheet changed ${names[2]}: ${JSON.stringify(tapped)}`);
  await capture(page, dir, '07b-closed-by-tap-on-row');
  await addField(page, L).click();
  await sheet.waitFor();

  await typeInto(addField(page, L), names[0]);
  await page.keyboard.press('Enter');
  const note = sheet.getByText(L('alreadyOnList', { name: names[0] }));
  await note.waitFor({ timeout: 10_000 });
  log(`duplicate: "${await note.textContent()}"`);
  await capture(page, dir, '08-already-on-list');

  await addField(page, L).click();
  await page.keyboard.press('Enter');
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });
  log('Enter in the empty field closed the sheet');
  await page.waitForTimeout(500);
  await capture(page, dir, '09-closed-by-empty-enter');

  await addField(page, L).click();
  await sheet.waitFor();
  await page.waitForTimeout(500);
  await page.mouse.click(195, 200);
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });
  log('a tap on the empty list behind the sheet closed it');
  await capture(page, dir, '10-closed-by-tap-behind');

  const all = await Promise.all(names.map(stored));
  log(`database: ${JSON.stringify(all)}`);
  if (all.some((row) => !row)) throw new Error('an add is missing in the database');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await forget().catch((error) => log(`cleanup: ${error.message}`));
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS add-sheet-compact (evidence: ${dir})`);
