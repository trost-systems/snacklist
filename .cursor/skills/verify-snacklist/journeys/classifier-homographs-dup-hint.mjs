// Feature classifier, sub-feature cl-homographs (job 282 review 0): the duplicate hint after an add
// ("<name> steht schon auf der Liste · Zusammenführen") does not join homographs. Schäufele next to
// Schaufel gets none; a "Bier" renamed to "beer" (the items trigger's rename path) is not Beeren,
// but adding "Bier" next to it is the same item and gets the hint (the control).
//
//   node journeys/classifier-homographs-dup-hint.mjs <evidence dir>
import process from 'node:process';
import { addField, addSheet, apiAs, capture, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: classifier-homographs-dup-hint.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L, errors } = await openApp(inst, { lang: 'de' });
const wrong = [];

async function add(word) {
  await typeInto(addField(page, L), word);
  await addSheet(page, L).getByRole('button', { name: new RegExp(`^${word}(,|$)`) }).first().waitFor({ timeout: 10_000 });
  await page.keyboard.press('Enter');
  await addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} ${word}`)).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(1_500);
  const hint = addSheet(page, L).getByText(/steht schon auf der Liste/);
  return (await hint.count()) ? (await hint.first().textContent()).trim() : null;
}

async function expectHint(word, want, shot) {
  const hint = await add(word);
  await capture(page, dir, shot);
  const ok = want === null ? hint === null : hint?.startsWith(want);
  log(`${ok ? 'ok  ' : 'FAIL'} after "${word}": hint ${hint === null ? 'none' : `"${hint}"`}, want ${want === null ? 'none' : `"${want} …"`}`);
  if (!ok) wrong.push(word);
}

try {
  await signIn(page, L, user);
  await add('Schaufel');
  await expectHint('Schäufele', null, '01-schaeufele-after-schaufel');

  await add('Bier');
  const { error } = await api.from('items').update({ name: 'beer' })
    .eq('household_id', user.householdId).eq('name', 'Bier').eq('status', 'active');
  if (error) throw error;
  log('renamed "Bier" to "beer" through the items table');
  await page.waitForTimeout(2_000);
  await expectHint('Beeren', null, '02-beeren-after-renamed-beer');
  await expectHint('Bier', 'beer steht schon', '03-bier-after-beer-control');

  const { data, error: readError } = await api.from('items').select('name, canonical_key')
    .eq('household_id', user.householdId).eq('status', 'active').in('name', ['Schaufel', 'Schäufele', 'beer', 'Beeren', 'Bier']);
  if (readError) throw readError;
  log(`database: ${JSON.stringify(data)}`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  if (wrong.length) throw new Error(`wrong hint after: ${wrong.join(', ')}`);
} catch (error) {
  log(`FAIL: ${error.message}`);
  await capture(page, dir, '99-failure').catch(() => {});
  process.exitCode = 1;
} finally {
  await page.context().close();
  await browser.close();
}
if (!process.exitCode) log(`PASS classifier-homographs-dup-hint (evidence: ${dir})`);
