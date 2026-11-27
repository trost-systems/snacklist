// Feature classifier, sub-feature cl-homographs (job 282 review 0): the duplicate hint after an add
// ("<name> steht schon auf der Liste · Zusammenführen") does not join homographs. Schäufele next to
// Schaufel gets none; a "Bier" renamed to "beer" (the items trigger's rename path) is not Beeren,
// but adding "Bier" next to it is the same item and gets the hint (the control). On the users' build
// (add-sheet-compact and add-match-rows, full) the hint is the merge row shown while the word is typed,
// keyed on the device, which reads homographs as the server does since #748 (before it, Schäufele
// offered „Zusammenführen, 2× Schaufel“), and the word is not added; with both off (VH_FLAGS_OFF=add-sheet-compact,add-match-rows), the note
// after Enter.
//
//   node journeys/classifier-homographs-dup-hint.mjs <evidence dir>
import process from 'node:process';
import { addField, addSheet, apiAs, capture, flagOn, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: classifier-homographs-dup-hint.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, page, L, errors } = await openApp(inst, { lang: 'de' });
const wrong = [];

const matchRows = flagOn('add-match-rows');

async function stored(word) {
  for (let i = 0; i < 40; i++) {
    const { data, error } = await api.from('items').select('id')
      .eq('household_id', user.householdId).eq('status', 'active').eq('name', word);
    if (error) throw error;
    if (data.length) return;
    await page.waitForTimeout(250);
  }
  throw new Error(`${word} was not stored`);
}

async function add(word) {
  await typeInto(addField(page, L), word);
  if (flagOn('add-sheet-compact')) {
    await page.keyboard.press('Enter');
    await stored(word);
    await page.waitForTimeout(1_500);
    return null;
  }
  await addSheet(page, L).getByRole('button', { name: new RegExp(`^${word}(,|$)`) }).first().waitFor({ timeout: 10_000 });
  await page.keyboard.press('Enter');
  await addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} ${word}`)).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(1_500);
  const hint = addSheet(page, L).getByText(/steht schon auf der Liste/);
  return (await hint.count()) ? (await hint.first().textContent()).trim() : null;
}

async function typedHint(word) {
  await typeInto(addField(page, L), word);
  await addSheet(page, L).getByRole('button', { name: new RegExp(`^${word}(,|$)`) }).first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(1_000);
  const merge = addSheet(page, L).getByRole('button', { name: new RegExp(`^${L('dedupeMerge')}, `) });
  const hint = (await merge.count()) ? (await merge.first().getAttribute('aria-label')) ?? (await merge.first().textContent()) : null;
  return hint?.trim() ?? null;
}

async function expectHint(word, want, shot) {
  const hint = matchRows ? await typedHint(word) : await add(word);
  await capture(page, dir, shot);
  const ok = want === null ? hint === null : matchRows ? hint?.includes(want.split(' ')[0]) : hint?.startsWith(want);
  log(`${ok ? 'ok  ' : 'FAIL'} after "${word}": hint ${hint === null ? 'none' : `"${hint}"`}, want ${want === null ? 'none' : `"${want} …"`}`);
  if (!ok) wrong.push(word);
  if (matchRows) {
    await addField(page, L).fill('');
    await page.waitForTimeout(300);
  }
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
