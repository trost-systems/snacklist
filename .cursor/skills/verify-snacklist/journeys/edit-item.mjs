// Feature edit-item, sub-feature ed-rename-open: renaming an item to the name of another open item
// (any case, spacing or umlaut spelling) folds it into that item. Proves one open row is left, the
// merged snackbar shows, and Rückgängig brings the renamed item back. With --onto, --to is a synonym
// of the open item --onto: proves nothing merges and the duplicate hint shows (Addendum 3).
//
//   node journeys/edit-item.mjs <evidence dir> [--lang de|en] [--from Apfelsaft] [--to Mineralwasser]
//     [--onto Brötchen]
import process from 'node:process';
import { addField, apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const from = opt('from', 'Apfelsaft');
const to = opt('to', 'Mineralwasser');
const onto = opt('onto', to);
if (!dir) throw new Error('usage: edit-item.mjs <evidence dir> [--lang de|en] [--from name] [--to name] [--onto name]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const open = async () => {
  const { data, error } = await api.from('items').select('id, name, quantity, status')
    .eq('household_id', user.householdId).eq('status', 'active').order('name');
  if (error) throw error;
  return data;
};
// As the app's foldName: case, spacing and umlauts.
const folded = (s) => s.trim().toLowerCase().replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue')
  .replaceAll('ß', 'ss').replace(/\s+/g, ' ');
const synonym = folded(onto) !== folded(to);
const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  const before = await open();
  const targets = before.filter((i) => folded(i.name) === folded(onto));
  const target = targets[0];
  if (!before.some((i) => i.name === from) || !target) {
    throw new Error(`needs "${from}" and "${onto}" open; open: ${before.map((i) => i.name).join(', ')}`);
  }
  if (targets.length > 1) throw new Error(`"${onto}" is open ${targets.length} times; seed a fresh run`);
  await signIn(page, L, user);
  await addField(page, L).waitFor();
  log(`signed in as ${user.handle} (${lang}); open before: ${before.length} items, "${target.name}" ${target.quantity ?? '-'}`);
  await capture(page, dir, '01-list-before');

  const sheet = page.getByRole('group', { name: L('editSheet'), exact: true });
  await reveal(page, itemRow(page, from).first());
  await itemRow(page, from).first().click({ button: 'right' });
  await sheet.waitFor({ timeout: 10_000 });
  await typeInto(sheet.getByRole('textbox', { name: L('fieldName') }), to);
  await capture(page, dir, '02-renaming');
  await sheet.getByRole('button', { name: L('done'), exact: true }).click();
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });

  if (synonym) {
    const hint = page.getByRole('group', { name: new RegExp(`^${L('alreadyOnList', { name: target.name })}`) });
    const shown = await hint.first().waitFor({ timeout: 10_000 }).then(() => true, () => false);
    await capture(page, dir, '03-after-rename');
    await page.waitForTimeout(1_500);
    const after = await open();
    const kept = after.find((i) => i.id === target.id);
    log(`hint: ${shown ? 'shown' : 'none'}; database: "${onto}" ${kept?.quantity ?? 'gone'}, "${to}" open: ${after.some((i) => i.name === to)}`);
    if (!kept || kept.quantity !== target.quantity) throw new Error(`"${onto}" changed: a synonym was merged`);
    if (!after.some((i) => i.name === to)) throw new Error(`"${to}" is not open: a synonym was merged`);
    if (!shown) throw new Error('no duplicate hint');
    if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  } else {
    const merged = page.getByRole('group', { name: new RegExp(`^${L('dedupeMerged', { item: '' }).trim()} `) });
    const note = await merged.first().waitFor({ timeout: 10_000 }).then(
      async () => (await merged.first().getAttribute('aria-label')) ?? '',
      () => null,
    );
    log(`snackbar: ${note === null ? 'none' : `"${note}"`}`);
    await capture(page, dir, '03-after-rename');

    await page.waitForTimeout(1_500);
    const after = await open();
    const same = after.filter((i) => [folded(to), folded(onto)].includes(folded(i.name)));
    log(`database: open "${onto}"/"${to}": ${JSON.stringify(same)}; "${from}" open: ${after.some((i) => i.name === from)}`);
    if (same.length !== 1) throw new Error(`expected one open "${onto}", found ${same.length}`);
    if (same[0].id !== target.id) throw new Error(`"${onto}" is not the item that was open before`);
    if (note === null) throw new Error('no merged snackbar');

    const back = from;
    await merged.first().getByRole('button', { name: L('undo'), exact: true }).click();
    await itemRow(page, back).first().waitFor({ timeout: 10_000 });
    await page.waitForTimeout(1_500);
    const undone = await open();
    log(`after Rückgängig: "${back}" open: ${undone.some((i) => i.name === back)}, open "${onto}": ${undone.filter((i) => folded(i.name) === folded(onto)).length}`);
    await capture(page, dir, '04-after-undo');
    if (!undone.some((i) => i.name === back)) throw new Error(`Rückgängig did not bring "${back}" back`);
    if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  }
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
log(`PASS edit-item ${synonym ? 'a synonym rename is only offered' : 'rename onto an open item merges'} (evidence: ${dir})`);
