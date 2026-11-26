// Feature quick-add, sub-feature qa-match-rows (flag add-match-rows on top of add-sheet-compact,
// job 324, AM2), on demo-familie. Typing what is already on the shown list shows marked rows in the
// sheet, one per outcome: merge (the item as it would be, „2× Nudeln“), tick off, back on the list
// for a ticked one, and the plain + row. Enter on an open match adds a separate item; each outcome
// is one tap and lands in the database. „Milch“ never offers „Hafermilch“. The list behind the
// sheet does not scroll (widget test). Rows follow the list when another member deletes the item.
//
//   helpers/launch.sh   (add-sheet-compact and add-match-rows are full since 2026-11-25)
//   node journeys/add-match-rows.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { addField, addSheet, apiAs, capture, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: add-match-rows.mjs <evidence dir> [--lang de|en]');
const words = lang === 'de'
  ? { item: 'Kefir', plural: ['Äpfel', 'Apfel'], oat: 'Hafermilch', milk: 'Milch' }
  : { item: 'Kefir', plural: ['Apples', 'Apple'], oat: 'Oat milk', milk: 'Milk' };

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const must = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};
const rows = async (name, status) => {
  let query = api.from('items').select('id, name, quantity, status, created_at')
    .eq('household_id', user.householdId).eq('name', name).order('created_at');
  if (status) query = query.eq('status', status);
  return must(await query);
};
const until = async (what, check) => {
  for (let i = 0; i < 40; i++) {
    const value = await check();
    if (value) return value;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`timed out waiting for ${what}`);
};
const ours = [words.item, words.oat, words.plural[1]];
const forget = async () => {
  must(await api.from('items').delete().eq('household_id', user.householdId).in('name', ours));
};
await forget();
// The seeded household has Äpfel (1 kg) in German; the English one gets Apples here.
const pluralSeeded = (await rows(words.plural[0], 'active')).length > 0;
if (!pluralSeeded) ours.push(words.plural[0]);

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
const sheet = addSheet(page, L);
const field = () => addField(page, L);
const buttons = async () => (await sheet.getByRole('button').evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? e.textContent)))
  .filter(Boolean);
const matchButtons = async () => (await buttons()).filter((name) =>
  [L('dedupeMerge'), L('addMatchTickOff'), L('readd')].some((action) => name.startsWith(`${action}, `)));
const type = async (text) => {
  await typeInto(field(), text);
  await page.waitForTimeout(700);
};
const clear = async () => {
  await field().fill('');
  await page.waitForTimeout(300);
};
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}) on ${inst.webUrl}`);
  await field().click();
  await sheet.waitFor();
  for (const name of [words.item, words.oat, ...(pluralSeeded ? [] : [`1 kg ${words.plural[0]}`])]) {
    await type(name);
    await page.keyboard.press('Enter');
    const plain = name.replace(/^1 kg /, '');
    await until(`${plain} added`, async () => (await rows(plain, 'active')).length === 1);
    await page.waitForTimeout(400);
  }
  log(`seeded: ${words.item}, ${words.oat}${pluralSeeded ? '' : `, 1 kg ${words.plural[0]}`}`);

  await type(words.item);
  let shown = await matchButtons();
  await capture(page, dir, '01-exact-match-rows');
  log(`typed "${words.item}": match rows ${JSON.stringify(shown)}`);
  const merge = shown.find((n) => n.startsWith(`${L('dedupeMerge')}, `));
  const tick = shown.find((n) => n.startsWith(`${L('addMatchTickOff')}, `));
  if (!merge?.includes(`2× ${words.item}`) && !merge?.includes(`2 ${words.item}`)) throw new Error(`no merge row showing 2× ${words.item}: ${merge}`);
  if (!tick?.includes(words.item)) throw new Error(`no tick-off row for ${words.item}`);

  await page.keyboard.press('Enter');
  const two = await until(`a second open ${words.item}`, async () => {
    const open = await rows(words.item, 'active');
    return open.length === 2 ? open : null;
  });
  await page.waitForTimeout(500);
  await capture(page, dir, '02-enter-added-separately');
  log(`Enter on the match: ${two.length} open ${words.item} rows ${JSON.stringify(two.map((r) => r.quantity))}`);

  await type(words.item);
  shown = await matchButtons();
  log(`typed "${words.item}" with two open: ${JSON.stringify(shown)}`);
  if (shown.length > 3) throw new Error(`more than three match rows: ${shown.length}`);
  await sheet.getByRole('button', { name: shown.find((n) => n.startsWith(`${L('dedupeMerge')}, `)), exact: true }).first().click();
  const merged = await until('the merge saved', async () => {
    const [oldest] = await rows(words.item);
    return oldest?.quantity ? oldest : null;
  });
  await page.waitForTimeout(400);
  await capture(page, dir, '03-merged-note');
  const mergedNote = await sheet.getByText(new RegExp(L('dedupeMerged', { item: '' }).trim())).count();
  log(`merge tapped: oldest ${words.item} now "${merged.quantity}"; note shown: ${mergedNote}`);
  if (!mergedNote) throw new Error('no "merged" note after the merge');

  for (const n of [1, 2]) {
    await type(words.item);
    shown = await matchButtons();
    const tickRow = shown.find((x) => x.startsWith(`${L('addMatchTickOff')}, `));
    if (!tickRow) throw new Error(`no tick-off row (round ${n}): ${JSON.stringify(shown)}`);
    await sheet.getByRole('button', { name: tickRow, exact: true }).click();
    await until(`${n} ${words.item} ticked`, async () => (await rows(words.item, 'bought')).length === n);
    await page.waitForTimeout(400);
    if (n === 1) await capture(page, dir, '04-ticked-note');
  }
  log(`both ${words.item} ticked off from the sheet`);

  await type(words.item);
  shown = await matchButtons();
  await capture(page, dir, '05-ticked-match-readd');
  log(`typed "${words.item}" with both ticked: ${JSON.stringify(shown)}`);
  if (!shown.some((n) => n.startsWith(`${L('readd')}, `))) throw new Error('no back-on-the-list row for a ticked match');
  await page.keyboard.press('Enter');
  await until(`${words.item} back on the list`, async () => (await rows(words.item, 'active')).length === 1);
  await page.waitForTimeout(400);
  await capture(page, dir, '06-readded-note');
  log(`Enter put one ${words.item} back: ${JSON.stringify(await rows(words.item))}`);

  await type(words.plural[1]);
  shown = await matchButtons();
  await capture(page, dir, '07-plural-match');
  log(`typed "${words.plural[1]}": ${JSON.stringify(shown)}`);
  if (!shown.some((n) => n.includes(words.plural[0]))) throw new Error(`no match row for ${words.plural[0]}`);
  await clear();

  await type(words.milk);
  shown = await matchButtons();
  await capture(page, dir, '08-milk-no-oat-milk');
  log(`typed "${words.milk}": ${JSON.stringify(shown)}`);
  if (shown.some((n) => n.includes(words.oat))) throw new Error(`${words.milk} offers ${words.oat}`);
  await clear();

  // Another member deletes the item while its rows show: the rows go and no outcome is claimed.
  await type(words.oat);
  shown = await matchButtons();
  if (!shown.length) throw new Error(`no match rows for ${words.oat}`);
  const [oatRow] = await rows(words.oat, 'active');
  must(await api.from('items').delete().eq('id', oatRow.id));
  await until(`the rows for ${words.oat} gone`, async () => (await matchButtons()).length === 0);
  await capture(page, dir, '09-deleted-elsewhere-rows-gone');
  log(`${words.oat} deleted by another member while typed: rows now ${JSON.stringify(await matchButtons())}`);
  await clear();
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await forget().catch((error) => log(`cleanup: ${error.message}`));
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS add-match-rows (evidence: ${dir})`);
