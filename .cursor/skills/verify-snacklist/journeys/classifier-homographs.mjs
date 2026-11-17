// Feature classifier, sub-feature cl-homographs (job 282): words the stemmer folds onto another
// word land in their own category. Types each word in the add bar, takes the typed row with Enter,
// and checks the heading above the row and the category in the database.
//
//   node journeys/classifier-homographs.mjs <evidence dir>
import process from 'node:process';
import { addField, addSheet, apiAs, capture, headingAbove, instance, itemRow, logger, member, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: classifier-homographs.mjs <evidence dir>');

/** Each word and its category without a Baumarkt (demo-familie has none: tools and garden go to Haushalt). */
const words = [
  ['beer', 'Getränke'],
  ['Bier', 'Getränke'],
  ['Beeren', 'Obst & Gemüse'],
  ['rolls', 'Brot & Backwaren'],
  ['Rolle Küchenpapier', 'Haushalt'],
  ['sage', 'Obst & Gemüse'],
  ['Salbei', 'Obst & Gemüse'],
  ['Säge', 'Haushalt'],
  ['Schäufele', 'Fleisch/Wurst/Fisch'],
  ['Schaufel', 'Haushalt'],
  ['Rohrnudeln', 'Brot & Backwaren'],
];

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L, errors } = await openApp(inst, { lang: 'de' });
const wrong = [];
try {
  await signIn(page, L, user);
  for (const [word] of words) {
    await typeInto(addField(page, L), word);
    await addSheet(page, L).getByRole('button', { name: new RegExp(`^${word}(,|$)`) }).first().waitFor({ timeout: 10_000 });
    await page.keyboard.press('Enter');
    await addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} ${word}`)).waitFor({ timeout: 10_000 });
  }
  await addSheet(page, L).getByRole('button', { name: L('close'), exact: true }).click();
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });

  const { data, error } = await api.from('items').select('name, categorized_via, categories(name)')
    .eq('household_id', user.householdId).eq('status', 'active').in('name', words.map(([w]) => w));
  if (error) throw error;
  for (const [word, want] of words) {
    const row = itemRow(page, word).first();
    await reveal(page, row);
    const heading = await headingAbove(page, row);
    const db = data.find((d) => d.name === word);
    const ok = heading === want && db?.categories?.name === want;
    log(`${ok ? 'ok  ' : 'FAIL'} ${word}: list "${heading}", database "${db?.categories?.name}" (${db?.categorized_via}), want "${want}"`);
    if (!ok) wrong.push(word);
  }
  await page.mouse.wheel(0, -10_000);
  await capture(page, dir, '01-list-top');
  for (let i = 2; i <= 4; i++) {
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(400);
    await capture(page, dir, `0${i}-list`);
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  if (wrong.length) throw new Error(`wrong category: ${wrong.join(', ')}`);
} catch (error) {
  log(`FAIL: ${error.message}`);
  await capture(page, dir, '99-failure').catch(() => {});
  process.exitCode = 1;
} finally {
  await page.context().close();
  await browser.close();
}
if (!process.exitCode) log(`PASS classifier-homographs (evidence: ${dir})`);
