// Feature quick-add, sub-feature qa-added-details (job 315): a store and category picked in the
// added item's details, then „Rückgängig“ on the add. Proves the next add of the name is offered
// and stored as before the first add, from the sheet's typed row and the household's items.
//
//   node journeys/undo-added-details.mjs <evidence dir> [--name Quark] [--store Wochenmarkt] [--category Getränke]
import process from 'node:process';
import { accessibleName, addField, addSheet, apiAs, capture, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const name = opt('name', 'Quark');
const store = opt('store', 'Wochenmarkt');
const category = opt('category', 'Getränke');
if (!dir) throw new Error('usage: undo-added-details.mjs <evidence dir> [--name Quark] [--store Wochenmarkt] [--category Getränke]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L, errors } = await openApp(inst, { videoDir: dir });
const sheet = () => addSheet(page, L);
const typedRow = () => sheet().getByRole('button', { name: new RegExp(`^${name}, ${L('suggestionTyped')}`) }).first();

async function offer(step) {
  await typeInto(addField(page, L), name);
  await typedRow().waitFor({ timeout: 10_000 });
  // The rows settle once the server's answer for the whole word is in.
  await page.waitForTimeout(1500);
  const label = accessibleName(await typedRow().ariaSnapshot());
  log(`${step}: typed row "${label}"`);
  await capture(page, dir, step);
  return label;
}

async function clear() {
  await addField(page, L).fill('');
  await page.keyboard.press('Backspace');
}

async function stored() {
  const { data, error } = await api.from('items').select('name, stores(name), categories(name)')
    .eq('household_id', user.householdId).eq('name', name).eq('status', 'active');
  if (error) throw error;
  return data.map((r) => `${r.stores?.name ?? '-'} / ${r.categories?.name ?? '-'}`);
}

let failed = null;
try {
  const { data: stores, error } = await api.from('stores').select('name').eq('household_id', user.householdId).eq('name', store);
  if (error) throw error;
  if (!stores.length) {
    const { error: added } = await api.rpc('add_store', { p_household: user.householdId, p_name: store });
    if (added) throw added;
  }
  await signIn(page, L, user);
  log(`signed in as ${user.handle} on ${inst.webUrl}`);
  if ((await stored()).length) throw new Error(`"${name}" is on the list already`);

  const before = await offer('01-offer-before');
  await page.keyboard.press('Enter');
  await sheet().getByRole('button', { name: /^Laden: / }).waitFor({ timeout: 10_000 });
  const added = await stored();
  log(`added: ${added.join(', ')}`);

  await sheet().getByRole('button', { name: /^Laden: / }).click();
  await sheet().getByRole('button', { name: store, exact: true }).click();
  await sheet().getByRole('button', { name: /^Kategorie: / }).click();
  await sheet().getByRole('button', { name: category, exact: true }).click();
  for (let i = 0; i < 50 && (await stored()).join() !== `${store} / ${category}`; i++) await page.waitForTimeout(200);
  log(`picked in the details: ${(await stored()).join(', ')}`);
  await capture(page, dir, '02-picked');

  await sheet().getByRole('button', { name: L('undo'), exact: true }).click();
  for (let i = 0; i < 50 && (await stored()).length; i++) await page.waitForTimeout(200);
  if ((await stored()).length) throw new Error('Rückgängig left the item on the list');
  log('Rückgängig: the item is gone');
  await capture(page, dir, '03-undone');

  // The list reloads its suggestion index 2 s after the server's rows change.
  await page.waitForTimeout(3000);
  const after = await offer('04-offer-after-undo');
  await page.keyboard.press('Enter');
  for (let i = 0; i < 50 && !(await stored()).length; i++) await page.waitForTimeout(200);
  const again = await stored();
  log(`added again: ${again.join(', ')}`);
  await capture(page, dir, '05-added-again');
  await sheet().getByRole('button', { name: L('undo'), exact: true }).click();
  await clear();

  if (after !== before) throw new Error(`after Rückgängig the typed row is "${after}", before the add it was "${before}"`);
  if (again.join() !== added.join()) throw new Error(`added again it is stored as ${again.join()}, the first add as ${added.join()}`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
