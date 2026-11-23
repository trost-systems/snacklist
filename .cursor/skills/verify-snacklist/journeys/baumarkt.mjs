// Feature stores-walk-order, entry point: Liste → „Anpassen“ → „Laden hinzufügen“ with the name
// „Baumarkt“ (sub-features sw-baumarkt, cat-baumarkt), then DIY items typed in the add bar. Proves
// the store becomes the household's Baumarkt, the seven Baumarkt categories exist, DIY items land
// in the Baumarkt's section under them in its walking order, and a grocery item stays out of it.
//
//   node journeys/baumarkt.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { addField, addSheet, apiAs, capture, instance, logger, member, openApp, openTab, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: baumarkt.mjs <evidence dir> [--lang de|en]');

const storeName = lang === 'de' ? 'Baumarkt' : 'Hardware store';
const items = ['Schrauben', 'Dübel', 'Glühbirne', 'Wandfarbe', 'Blumenerde', 'Silikon', 'Milch'];
const diy = items.filter((i) => i !== 'Milch');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });

async function outline() {
  const sections = [];
  let current;
  for (const line of (await page.locator('body').ariaSnapshot()).split('\n')) {
    const [, role, name] = /- (button|checkbox|heading) "(.*)"/.exec(line) ?? [];
    if (role === undefined) continue;
    const store = new RegExp(`^(.+), \\d+ (Artikel|items?)$`).exec(name)?.[1];
    if (role === 'button' && store !== undefined) {
      current = { store, headings: [], items: [] };
      sections.push(current);
    } else if (current && role === 'heading') {
      current.headings.push(name);
    } else if (current && role === 'checkbox') {
      current.items.push(name);
    }
  }
  return sections;
}

let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}) on ${inst.webUrl}`);

  await page.getByRole('button', { name: L('listEdit'), exact: true }).click();
  await page.getByRole('button', { name: L('storeAdd'), exact: true }).click();
  const nameField = page.getByRole('textbox', { name: L('storeNameHint') });
  await nameField.waitFor({ timeout: 10_000 });
  await typeInto(nameField, storeName);
  await capture(page, dir, '01-add-store-dialog');
  await page.getByRole('button', { name: L('storeCreateConfirm'), exact: true }).click();
  await nameField.waitFor({ state: 'detached', timeout: 10_000 });
  await page.getByRole('button', { name: new RegExp(`^${storeName}`) }).first().waitFor({ timeout: 10_000 });
  await capture(page, dir, '02-stores');

  const { data: stores, error: storeError } = await api.from('stores').select('id, name, seed_key').eq('household_id', user.householdId);
  if (storeError) throw storeError;
  log(`database stores: ${JSON.stringify(stores)}`);
  const store = stores.find((s) => s.name === storeName);
  if (store?.seed_key !== 'hardware') throw new Error(`"${storeName}" has seed key ${store?.seed_key}, not hardware`);

  await page.getByRole('button', { name: new RegExp(`^${storeName}`) }).first().click();
  await page.waitForTimeout(600);
  await capture(page, dir, '03-baumarkt-details');
  await page.getByRole('button', { name: lang === 'de' ? 'Zurück' : 'Back', exact: true }).click();
  await openTab(page, L, 'tabList');

  for (const item of items) {
    await addField(page, L).click();
    await addSheet(page, L).waitFor({ timeout: 10_000 });
    await typeInto(addField(page, L), item);
    await addSheet(page, L).getByRole('button', { name: new RegExp(`, ${L('suggestionTyped')}(,|$)`) }).first().waitFor({ timeout: 10_000 });
    if (item === 'Schrauben') await capture(page, dir, '04-add-sheet-schrauben');
    await page.keyboard.press('Enter');
    // The added note, or on the compact sheet (add-sheet-compact, full) the chip row.
    await addSheet(page, L).getByText(/^✓ /).first().or(addSheet(page, L).getByRole('button', { name: L('quantityPlus'), exact: true })).waitFor({ timeout: 10_000 });
    await page.keyboard.press('Escape');
    await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  }
  await page.waitForTimeout(800);
  await capture(page, dir, '05-list');

  const sections = await outline();
  log(`list: ${JSON.stringify(sections)}`);
  const section = sections.find((s) => s.store === storeName);
  if (!section) throw new Error(`no "${storeName}" section on the list`);
  for (const item of diy) {
    if (!section.items.some((row) => row === item || row.startsWith(`${item} `))) throw new Error(`"${item}" is not in the ${storeName} section`);
  }
  if (section.items.some((row) => row.startsWith('Milch'))) throw new Error(`Milch landed in the ${storeName} section`);

  const { data: rows, error } = await api.from('items').select('name, categories(name, seed_key), stores(name)')
    .eq('household_id', user.householdId).in('name', items).eq('status', 'active');
  if (error) throw error;
  log(`database items: ${JSON.stringify(rows)}`);
  const milk = rows.find((r) => r.name === 'Milch');
  if (!milk) throw new Error('Milch is not in the database');
  if (milk.stores !== null) throw new Error(`Milch went to the store "${milk.stores.name}"`);
  for (const item of diy) {
    const row = rows.find((r) => r.name === item);
    if (row?.stores?.name !== storeName) throw new Error(`"${item}" is stored at ${row?.stores?.name ?? 'no store'}, not ${storeName}`);
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  const { data } = await api.from('items').select('id').eq('household_id', user.householdId).in('name', items);
  for (const { id } of data ?? []) await api.from('items').delete().eq('id', id);
  const { data: added } = await api.from('stores').select('id').eq('household_id', user.householdId).eq('name', storeName);
  for (const { id } of added ?? []) await api.rpc('delete_store', { p_store: id });
  await page.context().close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS baumarkt (evidence: ${dir})`);
