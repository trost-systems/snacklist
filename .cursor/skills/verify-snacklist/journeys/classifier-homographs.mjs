// Feature classifier, sub-feature cl-homographs (job 282): words the stemmer folds onto another
// word land in their own category. Types each word in the add bar, takes the typed row with Enter,
// and checks the category in the database and, where the list shows category headings (with
// hide-categories off: VH_FLAGS_OFF=hide-categories), the heading above the row. On the users'
// build (add-sheet-compact full) an add shows the chip row instead of the added note.
//
//   node journeys/classifier-homographs.mjs <evidence dir>
import process from 'node:process';
import { addField, addSheet, apiAs, capture, flagOn, headingAbove, instance, itemRow, logger, member, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

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
const compact = flagOn('add-feedback-list') && flagOn('add-sheet-compact');
const headings = !flagOn('hide-categories');
try {
  await signIn(page, L, user);
  for (const [word] of words) {
    await typeInto(addField(page, L), word);
    await addSheet(page, L).getByRole('button', { name: new RegExp(`^${word}(,|$)`) }).first().waitFor({ timeout: 10_000 });
    await page.keyboard.press('Enter');
    if (compact) {
      for (let i = 0; i < 40; i++) {
        const { data: added } = await api.from('items').select('id').eq('household_id', user.householdId).eq('status', 'active').eq('name', word);
        if (added?.length) break;
        await page.waitForTimeout(250);
      }
    } else {
      await addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} ${word}`)).waitFor({ timeout: 10_000 });
    }
  }
  if (compact) await addField(page, L).press('Enter');
  else await addSheet(page, L).getByRole('button', { name: L('close'), exact: true }).click();
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });

  const { data, error } = await api.from('items').select('name, categorized_via, categories(name)')
    .eq('household_id', user.householdId).eq('status', 'active').in('name', words.map(([w]) => w));
  if (error) throw error;
  for (const [word, want] of words) {
    const row = itemRow(page, word).first();
    await reveal(page, row);
    const heading = headings ? await headingAbove(page, row) : null;
    const db = data.find((d) => d.name === word);
    const ok = (!headings || heading === want) && db?.categories?.name === want;
    log(`${ok ? 'ok  ' : 'FAIL'} ${word}: list ${headings ? `"${heading}"` : 'without headings'}, database "${db?.categories?.name}" (${db?.categorized_via}), want "${want}"`);
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
