// Feature categories, sub-feature cat-hidden (flag hide-categories, job 350): no category name on
// the list, in the add sheet, the edit sheet, „Läden“ or a store's screen, and the list's rows in
// the same order as without the flag. Writes the rows top to bottom to <dir>/order.json; run it
// once on a build with the flag (--hidden) and once without, and compare the two files.
//
//   VH_DEFINES="FLAGS_ON=hide-categories" helpers/launch.sh
//   node journeys/hide-categories.mjs <evidence dir> --hidden [--lang de|en]
//   helpers/launch.sh && node journeys/hide-categories.mjs <evidence dir> [--lang de|en]
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { addField, addSheet, apiAs, capture, instance, itemRow, logger, member, openApp, openTab, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const hidden = rest.includes('--hidden');
if (!dir) throw new Error('usage: hide-categories.mjs <evidence dir> [--hidden] [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { data: categories, error } = await api.from('categories').select('name').eq('household_id', user.householdId);
if (error) throw error;
const { data: stores } = await api.from('stores').select('id, name').eq('household_id', user.householdId).order('sort_order');
// A tall phone: every row of the seeded list is built, so the order is the whole list's.
const { browser, page, L, errors } = await openApp(inst, { lang, viewport: { width: 390, height: 2400 }, videoDir: dir });

/**
 * What the page says that names a category: a heading, label or text that is a category's name
 * („Haushalt“, not „Unser Haushalt“), or „Kategorie“ anywhere (the chip and its options).
 */
async function categoryText(where) {
  const aria = (await page.locator('body').ariaSnapshot()).toLowerCase();
  const names = new Set();
  for (const line of aria.split('\n')) {
    for (const [, quoted] of line.matchAll(/"([^"]*)"/g)) names.add(quoted.trim());
    const text = /^\s*- text: (.*)$/.exec(line)?.[1];
    if (text) names.add(text.trim());
  }
  const found = [
    ...categories.map((c) => c.name.toLowerCase()).filter((n) => names.has(n)),
    ...(aria.includes(L('chipCategoryShort').toLowerCase()) ? [L('chipCategoryShort')] : []),
  ];
  log(`${where}: category words ${found.length ? found.join(', ') : 'none'}`);
  return found;
}

let failed = null;
try {
  await signIn(page, L, user);
  await addField(page, L).waitFor();
  await page.waitForTimeout(1_000);
  const rows = await page.getByRole('checkbox').all();
  const boxes = await Promise.all(rows.map(async (r) => ({ y: (await r.boundingBox())?.y ?? -1, name: await r.getAttribute('aria-label') ?? (await r.textContent()) })));
  const order = boxes.filter((b) => b.y >= 0).sort((a, b) => a.y - b.y).map((b) => b.name.split('\n')[0]);
  writeFileSync(join(dir, 'order.json'), `${JSON.stringify(order, null, 2)}\n`);
  const headings = await Promise.all((await page.getByRole('heading', { level: 2 }).all()).map((h) => h.textContent()));
  log(`flag ${hidden ? 'on' : 'off'}; ${order.length} rows; headings: ${headings.map((h) => h.trim()).join(' | ')}`);
  await capture(page, dir, '01-list');
  const onList = await categoryText('list');
  if (hidden && onList.length) throw new Error(`the list names categories: ${onList.join(', ')}`);
  if (!hidden && !onList.length) throw new Error('flag off but no category on the list');

  await page.setViewportSize({ width: 390, height: 844 });
  await typeInto(addField(page, L), 'Milch');
  await addSheet(page, L).waitFor();
  await page.waitForTimeout(800);
  await capture(page, dir, '02-add-sheet-typing');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1_000);
  await capture(page, dir, '03-add-sheet-after-add');
  const inSheet = await categoryText('add sheet after an add');
  if (hidden && inSheet.length) throw new Error(`the add sheet names categories: ${inSheet.join(', ')}`);
  await page.keyboard.press('Escape');
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 5_000 }).catch(() => {});
  await page.waitForTimeout(500);

  const sheet = page.getByRole('group', { name: L('editSheet'), exact: true });
  const first = itemRow(page, order[0]).first();
  await first.click({ button: 'right' });
  await sheet.waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);
  await capture(page, dir, '04-edit-sheet');
  const inEdit = await categoryText('edit sheet');
  if (hidden && inEdit.length) throw new Error(`the edit sheet names categories: ${inEdit.join(', ')}`);
  await sheet.getByRole('button', { name: L('cancel'), exact: true }).click();
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });

  await openTab(page, L, 'tabList');
  await page.getByRole('button', { name: L('listEdit') }).first().click();
  await page.getByRole('heading', { name: L('storesTitle') }).first().waitFor({ timeout: 10_000 }).catch(() => {});
  await page.waitForTimeout(800);
  await capture(page, dir, '05-stores');
  const noStore = await page.getByRole('button', { name: L('noStore'), exact: true }).count();
  log(`„${L('noStore')}“ rows on Läden: ${noStore}`);
  const inStores = await categoryText('stores');
  if (hidden && (inStores.length || noStore)) throw new Error('Läden still names categories or shows Ohne Laden');

  const store = stores?.[0];
  if (store) {
    await page.getByRole('button', { name: store.name, exact: true }).first().click();
    await page.waitForTimeout(1_000);
    await capture(page, dir, '06-store');
    const inStore = await categoryText(`store ${store.name}`);
    if (hidden && inStore.length) throw new Error(`the store screen names categories: ${inStore.join(', ')}`);
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  log('PASS');
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
  log(`FAIL: ${e.message}`);
} finally {
  await browser.close();
}
if (failed) process.exit(1);
