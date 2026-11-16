// Feature quick-add, sub-feature qa-stable-rows (flag input-stable-rows, job 272), on demo-familie.
// The server's suggestions are held back 2.5 s, as on a slow phone network, and the adds' writes
// too. Typing „Kefir“ a key every 30 ms, the typed row must read the field (flag on) or still the
// first letter (flag off, the bug); a tap adds what it reads. With the flag on the add sorts into
// Kühlregal before the server has it and lands in the store the household remembers for its other
// chilled items (Vollmilch and Butter at „Wochenmarkt“, set up through the API). Then a finger held
// on a row while the server's answer arrives: the rows stay as they were until it lifts.
//
//   launched with VH_DEFINES="FLAGS_ON=input-stable-rows" (or without, for --expect off)
//   node journeys/input-stable-rows.mjs <evidence dir> [--expect on|off]
import process from 'node:process';
import { accessibleName, addField, addSheet, apiAs, capture, headingAbove, instance, itemRow, logger, member, nextFrames, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const on = opt('expect', 'on') === 'on';
if (!dir) throw new Error('usage: input-stable-rows.mjs <evidence dir> [--expect on|off]');
const hold = 2500;

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const must = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};

const forget = async () => {
  must(await api.from('items').delete().eq('household_id', user.householdId).in('name', ['Kefir', 'K', 'Joghu', 'J']));
};
await forget();
const stores = must(await api.from('stores').select('id, name').eq('household_id', user.householdId).eq('name', 'Wochenmarkt'));
const market = stores[0]?.id ?? must(await api.rpc('add_store', { p_household: user.householdId, p_name: 'Wochenmarkt' }));
must(await api.from('items').update({ store_id: market }).eq('household_id', user.householdId).in('name', ['Vollmilch', 'Butter']));
log(`set up: Vollmilch and Butter at Wochenmarkt (${market}), so the household's chilled items are bought there`);

const { browser, page, L, errors } = await openApp(inst, { lang: 'de', videoDir: dir });
const sources = ['Typed', 'History', 'Pack', 'Variant', 'Size', 'Brand', 'Catalog'].map((s) => L(`suggestion${s}`));
const sheetRows = async () =>
  (await addSheet(page, L).ariaSnapshot()).split('\n').filter((l) => l.includes('button "')).map(accessibleName)
    .filter((name) => sources.includes(name.split(', ')[1]));
const typedRow = () => addSheet(page, L).getByRole('button', { name: new RegExp(`, ${L('suggestionTyped')}(,|$)`) }).first();
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} on ${inst.webUrl}, expecting the flag ${on ? 'on' : 'off'}`);
  await page.route(/\/rest\/v1\/rpc\/(suggest_entries|parse_item|put_item)/, async (route) => {
    await new Promise((r) => setTimeout(r, hold));
    await route.continue();
  });

  await typeInto(addField(page, L), 'Kefir', { perKey: 30 });
  await nextFrames(page);
  const shown = accessibleName(await typedRow().ariaSnapshot());
  log(`typed "Kefir" a key every 30 ms, server held back ${hold} ms: the typed row reads "${shown}" (rows: ${(await sheetRows()).join(' | ')})`);
  await capture(page, dir, '01-typed-fast');
  const expected = on ? 'Kefir' : 'K';
  if (!shown.startsWith(`${expected}, `)) throw new Error(`the typed row reads "${shown}", expected "${expected}, …"`);

  await typedRow().click();
  await addSheet(page, L).getByRole('button', { name: L('close'), exact: true }).click();
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  await reveal(page, itemRow(page, expected).first());
  const heading = await headingAbove(page, itemRow(page, expected).first());
  const before = must(await api.from('items').select('id').eq('household_id', user.householdId).eq('name', expected));
  log(`tapped it: the list shows "${expected}" under "${heading}" while the server has ${before.length} such row(s)`);
  await capture(page, dir, '02-added-before-server');
  if (before.length !== 0) throw new Error('the server had the add already: the optimistic placement was not observed');

  let row = null;
  for (let i = 0; i < 40 && !row; i++) {
    await page.waitForTimeout(250);
    row = must(await api.from('items').select('name, store_id, stores(name), categories(name)').eq('household_id', user.householdId).eq('name', expected).eq('status', 'active'))[0] ?? null;
  }
  log(`database: ${JSON.stringify(row)}`);
  if (!row) throw new Error(`"${expected}" never reached the server`);
  if (on) {
    if (heading !== row.categories?.name) throw new Error(`shown under "${heading}" before the server, filed under "${row.categories?.name}"`);
    if (row.stores?.name !== 'Wochenmarkt') throw new Error(`a first-time chilled grocery went to "${row.stores?.name}", not Wochenmarkt`);
  } else if (row.store_id !== null) {
    throw new Error(`flag off, yet "${expected}" got a store`);
  }
  await reveal(page, itemRow(page, expected).first());
  await capture(page, dir, '03-after-server');

  if (on) {
    await typeInto(addField(page, L), 'Joghu', { perKey: 30 });
    await nextFrames(page);
    const box = await typedRow().boundingBox();
    const held = await sheetRows();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    const answer = await page.waitForResponse(/\/rest\/v1\/rpc\/suggest_entries/, { timeout: 10_000 });
    await answer.finished();
    await page.waitForTimeout(300);
    await nextFrames(page);
    const during = await sheetRows();
    log(`finger down on "${held[0]}" with rows [${held.join(' | ')}]; the server answered (${answer.status()}); rows now [${during.join(' | ')}]`);
    await capture(page, dir, '04-held-after-answer');
    if (JSON.stringify(during) !== JSON.stringify(held)) throw new Error('the rows changed under the finger');
    await page.mouse.up();
    const note = addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} Joghu`));
    await note.waitFor({ timeout: 10_000 });
    log(`finger up: "${await note.textContent()}"`);
    await capture(page, dir, '05-released');

    await typeInto(addField(page, L), 'Joghu', { perKey: 30 });
    const control = page.waitForResponse(/\/rest\/v1\/rpc\/suggest_entries/, { timeout: 10_000 });
    await nextFrames(page);
    const untouched = await sheetRows();
    await (await control).finished();
    await page.waitForTimeout(300);
    await nextFrames(page);
    const answered = await sheetRows();
    log(`control, no finger: rows [${untouched.join(' | ')}] became [${answered.join(' | ')}] with the answer`);
    await capture(page, dir, '06-control-answered');
    if (JSON.stringify(answered) === JSON.stringify(untouched)) throw new Error('the answer changed nothing, so the hold above proved nothing');
    if (JSON.stringify(answered.slice(0, untouched.length)) !== JSON.stringify(untouched)) throw new Error('the answer moved the rows shown before it');
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await forget();
  must(await api.from('items').update({ store_id: null }).eq('household_id', user.householdId).in('name', ['Vollmilch', 'Butter']));
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS input-stable-rows, flag ${on ? 'on' : 'off'} (evidence: ${dir})`);
