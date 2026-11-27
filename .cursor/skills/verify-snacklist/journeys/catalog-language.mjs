// Feature quick-add (qa-device-catalog) and language (job 470): the add sheet's catalogue rows
// follow the app language. German: "mil" offers Milch and no English word. Switched live under
// Mehr › Einstellungen › Sprache to English, without a reload: "mil" offers Milk and no German
// term, and more English words. English adds land in their aisle in the database (classifier
// cl-english): eggplant in produce, nappies in drugstore. Phrases complete from their first
// words ("toilet p": Toilet paper, "chicken br": Chicken breast, not Chicken brie).
//
//   node journeys/catalog-language.mjs <evidence dir>
import process from 'node:process';
import { accessibleName, addField, addSheet, apiAs, capture, instance, labels, logger, member, openApp, openTab, signIn, typeInto } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: catalog-language.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L: de, errors } = await openApp(inst, { lang: 'de', videoDir: dir });
const en = labels('en');
let failed = null;

/** The catalogue rows the sheet shows for [text], by name. */
async function catalogRows(L, text) {
  await addField(page, L).fill('');
  await typeInto(addField(page, L), text);
  const typedRow = addSheet(page, L).getByRole('button', { name: new RegExp(`, ${L('suggestionTyped')}(,|$)`) }).first();
  await typedRow.waitFor({ timeout: 10_000 });
  // The server's answer follows the device's rows about 120 ms after the last key.
  await page.waitForTimeout(800);
  const names = (await addSheet(page, L).ariaSnapshot()).split('\n')
    .filter((line) => line.includes(`, ${L('suggestionCatalog')}`))
    .map((line) => accessibleName(line).split(', ')[0]);
  log(`${L === de ? 'de' : 'en'} "${text}": catalogue rows ${JSON.stringify(names)}`);
  return names;
}

function expectRows(names, has, hasNot) {
  for (const name of has) if (!names.includes(name)) throw new Error(`no "${name}" in ${JSON.stringify(names)}`);
  for (const name of hasNot) if (names.includes(name)) throw new Error(`"${name}" in ${JSON.stringify(names)}`);
}

async function addTyped(L, text) {
  await addField(page, L).fill('');
  await typeInto(addField(page, L), text);
  await addField(page, L).press('Enter');
  for (let i = 0; i < 40; i++) {
    const { data, error } = await api.from('items').select('name, categorized_via, categories(seed_key)')
      .eq('household_id', user.householdId).eq('name', text).eq('status', 'active');
    if (error) throw error;
    if (data.length === 1 && data[0].categorized_via) return data[0];
    await page.waitForTimeout(250);
  }
  throw new Error(`"${text}" did not reach the database`);
}

try {
  await signIn(page, de, user);
  log(`signed in as ${user.handle} (de) on ${inst.webUrl}`);
  expectRows(await catalogRows(de, 'mil'), ['Milch'], ['Milk']);
  await capture(page, dir, '01-de-mil');
  await addField(page, de).press('Escape');

  await openTab(page, de, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${de('settingsTitle')}`) }).click();
  await page.getByRole('button', { name: new RegExp(`^${de('language')}`) }).click();
  await page.getByRole('radio', { name: 'English', exact: true }).click();
  await page.getByRole('heading', { name: en('language') }).waitFor({ timeout: 10_000 });
  log('switched to English under Mehr › Einstellungen › Sprache, no reload');
  await openTab(page, en, 'tabList');

  expectRows(await catalogRows(en, 'mil'), ['Milk'], ['Milch', 'Milchreis']);
  await capture(page, dir, '02-en-mil');
  expectRows(await catalogRows(en, 'tomat'), ['Tomatoes'], ['Tomate']);
  await capture(page, dir, '03-en-tomat');
  expectRows(await catalogRows(en, 'peanut butt'), ['Peanut butter'], ['Peanut buttermilk']);
  await capture(page, dir, '04-en-peanut-butter');
  expectRows(await catalogRows(en, 'toilet p'), ['Toilet paper'], []);
  await capture(page, dir, '04b-en-toilet-p');
  expectRows(await catalogRows(en, 'chicken br'), ['Chicken breast'], ['Chicken brie', 'Chicken bread']);
  expectRows(await catalogRows(en, 'Milch'), [], ['Mulch']);

  for (const [name, seed] of [['eggplant', 'produce'], ['nappies', 'drugstore'], ['peanut butter', 'pantry']]) {
    const row = await addTyped(en, name);
    log(`database: ${JSON.stringify(row)}`);
    if (row.categories?.seed_key !== seed) throw new Error(`"${name}" is ${row.categories?.seed_key}, not ${seed}`);
  }
  await capture(page, dir, '05-en-added');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  log('PASS');
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
