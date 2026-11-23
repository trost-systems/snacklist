// Features list-manage and quick-add: screenshots of the list, the add sheet, More, the stores
// screen, one store's details and the "Ohne Laden" categories (only with hide-categories off:
// VH_FLAGS_OFF=hide-categories), for before/after evidence. Adds two
// generic stores (Wochenmarkt, Bäckerei) to the household first; no retailer names (Legal N-23).
//
//   node journeys/list-manage.mjs <evidence dir> [--lang de|en] [--dark]
import process from 'node:process';
import { addField, addSheet, apiAs, capture, flagOn, instance, logger, member, openApp, openTab, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: list-manage.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const storeNames = lang === 'de' ? ['Wochenmarkt', 'Bäckerei'] : ['Farmers market', 'Bakery'];
for (const name of storeNames) {
  const { error } = await api.rpc('add_store', { p_household: user.householdId, p_name: name });
  if (error) throw error;
}
const { browser, page, L, errors } = await openApp(inst, { lang, dark });
let failed = null;
try {
  await signIn(page, L, user);
  await capture(page, dir, '01-list');

  await addField(page, L).click();
  await typeInto(addField(page, L), lang === 'de' ? 'Milch' : 'Milk');
  await addSheet(page, L).getByRole('button').first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(400);
  await capture(page, dir, '02-add-sheet');
  await page.keyboard.press('Escape');
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });

  await openTab(page, L, 'tabMore');
  await page.waitForTimeout(400);
  await capture(page, dir, '03-more');

  await openTab(page, L, 'tabList');
  await page.getByRole('button', { name: L('listEdit'), exact: true }).click();
  await page.getByRole('button', { name: new RegExp(storeNames[0]) }).first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(400);
  await capture(page, dir, '04-stores');

  await page.getByRole('button', { name: new RegExp(storeNames[0]) }).first().click();
  await page.waitForTimeout(600);
  await capture(page, dir, '05-store-details');

  const back = () => page.getByRole('button', { name: lang === 'de' ? 'Zurück' : 'Back', exact: true }).click();
  await back();
  if (flagOn('hide-categories')) {
    log(`no „${L('noStore')}“ categories screen (hide-categories on, as users have it)`);
  } else {
    await page.getByRole('button', { name: new RegExp(`^${L('noStore')}`) }).first().click();
    await page.waitForTimeout(600);
    await capture(page, dir, '06-no-store-categories');
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  for (const name of storeNames) {
    const { data } = await api.from('stores').select('id').eq('household_id', user.householdId).eq('name', name);
    for (const { id } of data ?? []) await api.rpc('delete_store', { p_store: id });
  }
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
