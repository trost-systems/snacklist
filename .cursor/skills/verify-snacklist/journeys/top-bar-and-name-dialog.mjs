// Features list-manage and stores-walk-order: the list's top bar and a store's rename dialog, for
// before/after evidence (job 152). The bar synced, with a partner's new items and offline; then
// the rename dialog, full height and with the page cut to what an iPhone keyboard leaves free.
// Logs the gap between the name field and the dialog's buttons. Adds a generic store first and
// deletes it after (no retailer names, N-23).
//
//   node journeys/top-bar-and-name-dialog.mjs <evidence dir> [--lang de|en] [--dark] [--se]
//
// --se: an iPhone SE page (320×568, 253 px keyboard). Fails when the keyboard leaves the field
// partly hidden.
import process from 'node:process';
import { answerShopAsk, apiAs, capture, instance, itemRow, logger, member, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
const se = rest.includes('--se');
if (!dir) throw new Error('usage: top-bar-and-name-dialog.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const partner = member(inst, 'noah');
const api = await apiAs(inst, user);
const partnerApi = await apiAs(inst, partner);
const storeName = lang === 'de' ? 'Wochenmarkt' : 'Farmers market';
const { error } = await api.rpc('add_store', { p_household: user.householdId, p_name: storeName });
if (error) throw error;
const phone = se ? { width: 320, height: 568 } : { width: 390, height: 844 };
// An iPhone's keyboard with its suggestion bar.
const keyboard = se ? 253 : 336;
const { browser, context, page, L, errors } = await openApp(inst, { lang, dark, viewport: phone });
let failed = null;
const partnerItem = lang === 'de' ? 'Zitronen' : 'Lemons';
try {
  await signIn(page, L, user);
  await page.waitForTimeout(600);
  const edit = page.getByRole('button', { name: L('listEdit'), exact: true });
  log(`Anpassen box ${JSON.stringify(await edit.boundingBox())}`);
  await capture(page, dir, '01-top-bar');

  const { error: addError } = await partnerApi
    .from('items')
    .insert({ household_id: user.householdId, name: partnerItem, added_by: partner.id });
  if (addError) throw addError;
  await itemRow(page, partnerItem).first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  log(`Anpassen box with new items ${JSON.stringify(await edit.boundingBox())}`);
  await capture(page, dir, '02-top-bar-new-items');

  // A tick while offline queues a change: the bar shows the sync icon until it is sent.
  await context.setOffline(true);
  const ticked = itemRow(page, partnerItem).first();
  await ticked.click();
  await answerShopAsk(page, L, 'shopAskNo');
  await page.getByRole('button', { name: /^Offline:/ }).first().waitFor({ timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(800);
  log(`Anpassen box offline ${JSON.stringify(await edit.boundingBox())}`);
  await capture(page, dir, '03-top-bar-offline');
  await context.setOffline(false);
  await page.waitForTimeout(3_000);

  await edit.click();
  await page.getByRole('button', { name: new RegExp(storeName) }).first().click();
  const rename = page.getByRole('button', { name: L('storeRename', { store: storeName }), exact: true });
  await rename.click();
  const field = page.getByRole('textbox', { name: L('storeNameHint') });
  await field.waitFor({ timeout: 10_000 });
  await page.waitForTimeout(600);
  const gap = async () => {
    const f = await field.boundingBox();
    const cancel = await page.getByRole('button', { name: L('cancel'), exact: true }).boundingBox();
    return Math.round(cancel.y - (f.y + f.height));
  };
  log(`gap field -> buttons, full height: ${await gap()} px`);
  // Flutter clips a semantics box to its scroll view: a field cut off by the buttons is shorter.
  const fullHeight = (await field.boundingBox()).height;
  await capture(page, dir, '04-rename-dialog');

  await page.setViewportSize({ width: phone.width, height: phone.height - keyboard });
  await page.waitForTimeout(800);
  log(`gap field -> buttons, ${keyboard} px keyboard: ${await gap()} px`);
  const shown = (await field.boundingBox()).height;
  log(`field shown ${shown} of ${fullHeight} px`);
  if (shown < fullHeight - 1) throw new Error(`the field is cut off: ${shown} of ${fullHeight} px shown`);
  await capture(page, dir, '05-rename-dialog-keyboard');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  const { data } = await api.from('stores').select('id').eq('household_id', user.householdId).eq('name', storeName);
  for (const { id } of data ?? []) await api.rpc('delete_store', { p_store: id });
  await api.from('items').delete().eq('household_id', user.householdId).eq('name', partnerItem);
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
