// Feature quick-add, sub-features qa-feedback-list, qa-added-details and qa-loading (flag
// add-feedback-list, job 276), on demo-familie. Opening the sheet turns the list behind it into one
// list without store and category headings; each add lands under „Gerade hinzugefügt“ just above
// the sheet, and the sheet shows the add's details until the next letter. Menge typed there is saved
// after a pause, Marke typed right before „Schließen“ by the close. While the server's suggestions
// are held back a thin line runs above the field. Closing glides the list back into its stores and
// categories, Kefir under its category.
//
//   launched with VH_DEFINES="FLAGS_ON=add-feedback-list,input-stable-rows"
//   node journeys/add-feedback-list.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { addField, addSheet, apiAs, capture, headingAbove, instance, itemRow, logger, member, nextFrames, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: add-feedback-list.mjs <evidence dir> [--lang de|en]');
const hold = 1500;
const names = lang === 'de' ? ['Kefir', 'Brot'] : ['Kefir', 'Bread'];

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const must = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};
const forget = async () => {
  must(await api.from('items').delete().eq('household_id', user.householdId).in('name', names));
};
const stored = async (name) =>
  must(await api.from('items').select('name, quantity, brand, status').eq('household_id', user.householdId).eq('name', name).eq('status', 'active'))[0] ?? null;
const until = async (what, check) => {
  for (let i = 0; i < 40; i++) {
    const value = await check();
    if (value) return value;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for ${what}`);
};
await forget();

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} on ${inst.webUrl}`);
  await capture(page, dir, '01-list-at-rest');

  await addField(page, L).click();
  await addSheet(page, L).waitFor();
  await page.waitForTimeout(500);
  await capture(page, dir, '02-open-no-headings');

  await page.route(/\/rest\/v1\/rpc\/suggest_entries/, async (route) => {
    await new Promise((r) => setTimeout(r, hold));
    await route.continue();
  });
  await typeInto(addField(page, L), names[0], { perKey: 60 });
  await page.waitForTimeout(400);
  const line = page.locator(`[aria-label="${L('suggestionsLoading')}"]`);
  await line.waitFor({ timeout: 2000 });
  log(`typed "${names[0]}" with the server held back ${hold} ms: the line „${L('suggestionsLoading')}“ shows`);
  await capture(page, dir, '03-loading-line');
  await line.waitFor({ state: 'detached', timeout: hold + 3000 });
  log('the answer landed: the line is gone');

  await addSheet(page, L).getByRole('button', { name: new RegExp(`^${names[0]}, ${L('suggestionTyped')}`) }).first().click();
  const quantity = addSheet(page, L).getByRole('textbox', { name: L('itemQuantity') });
  await quantity.waitFor({ timeout: 5000 });
  await page.waitForTimeout(500);
  log(`added "${names[0]}": the sheet shows its details (${L('itemQuantity')}, ${L('fieldBrand')}, ${L('fieldProperties')})`);
  await capture(page, dir, '04-added-lands-details');

  await typeInto(quantity, '2');
  await page.waitForTimeout(200);
  const early = await stored(names[0]);
  log(`typed Menge "2": 200 ms later the server has quantity ${JSON.stringify(early?.quantity ?? null)}`);
  const saved = await until('the quantity after the pause', async () => (await stored(names[0]))?.quantity === '2' && true);
  log(`after the pause the server has quantity "2" (${saved})`);
  await capture(page, dir, '05-quantity-saved');

  await typeInto(addField(page, L), names[1], { perKey: 60 });
  await addSheet(page, L).getByRole('button', { name: new RegExp(`^${names[1]}, ${L('suggestionTyped')}`) }).first().click();
  await quantity.waitFor({ timeout: 5000 });
  await page.waitForTimeout(500);
  await capture(page, dir, '06-second-add');

  const brand = addSheet(page, L).getByRole('textbox', { name: L('fieldBrand') });
  await typeInto(brand, 'Harry');
  await addSheet(page, L).getByRole('button', { name: L('close'), exact: true }).click();
  await page.waitForTimeout(120);
  await capture(page, dir, '07-closing-mid-glide');
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  await page.waitForTimeout(500);
  await capture(page, dir, '08-closed-grouped');
  const bread = await until('the brand saved by the close', async () => (await stored(names[1]))?.brand === 'Harry' && stored(names[1]));
  log(`typed Marke "Harry" and closed at once: the server has ${JSON.stringify(bread)}`);

  await reveal(page, itemRow(page, names[0]).first());
  await nextFrames(page);
  const heading = await headingAbove(page, itemRow(page, names[0]).first());
  log(`closed: "${names[0]}" sits under the heading "${heading}"`);
  await capture(page, dir, '09-kefir-in-its-category');
  if (!heading) throw new Error('no heading above the add after the close');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await forget();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS add-feedback-list (evidence: ${dir})`);
