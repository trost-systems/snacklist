// Feature quick-add, sub-feature qa-device-catalog (flag on-device-catalog, job 274), on demo-familie.
// Two bought items give the household a history (Hafermilch, Kölln Haferflocken). Once the household
// index has loaded, the server's suggestions, parsing and writes are held back 2.5 s. Texts typed a
// key every 150 ms (each key checked) and every 30 ms (the last key checked): with the flag on, every
// key's rows already equal public.suggest_entries' answer for that text (asked out of band through
// the API), and the held answer, once it arrives, changes neither their order nor their text. A tap
// adds the row shown; with the server unreachable the rows still come. With --expect off the rows
// before the answer are not the server's ranking (the old behaviour), after it they are.
//
//   launched with VH_DEFINES="FLAGS_ON=on-device-catalog ADD_SHEET_TIMING=true" (without the flag
//   for --expect off)
//   node journeys/on-device-catalog.mjs <evidence dir> [--expect on|off]
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { accessibleName, addField, addSheet, apiAs, capture, instance, logger, member, nextFrames, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const on = opt('expect', 'on') === 'on';
if (!dir) throw new Error('usage: on-device-catalog.mjs <evidence dir> [--expect on|off]');
const hold = 2500;
const texts = ['Hafer', 'Erdbe', 'Rote Be', 'Pampers Windeln', '2 l Hafermilch'];
const history = [
  { name: 'Hafermilch', quantity: '2', brand: null, days: 3 },
  { name: 'Haferflocken', quantity: null, brand: 'Kölln', days: 10 },
];
const added = ['Erdbeere'];

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const must = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};

const forget = async () => {
  must(await api.from('items').delete().eq('household_id', user.householdId).in('name', [...history.map((h) => h.name), ...added]));
};
await forget();
for (const h of history) {
  const at = new Date(Date.now() - h.days * 86_400_000).toISOString();
  must(await api.from('items').insert({ household_id: user.householdId, name: h.name, quantity: h.quantity, brand: h.brand, status: 'bought', bought_at: at, bought_by: user.id, added_by: user.id }));
}
log(`set up: bought ${history.map((h) => `${h.brand ? `${h.brand} ` : ''}${h.name} (${h.days} days ago)`).join(', ')}`);

const { browser, page, L, errors } = await openApp(inst, { lang: 'de', videoDir: dir });
const sourceLabel = Object.fromEntries(['typed', 'history', 'pack', 'variant', 'size', 'brand', 'catalog'].map((s) => [s, L(`suggestion${s[0].toUpperCase()}${s.slice(1)}`)]));
const sources = Object.values(sourceLabel);
const sheetRows = async () => {
  if (!(await addSheet(page, L).count())) return [];
  return (await addSheet(page, L).ariaSnapshot()).split('\n').filter((l) => l.includes('button "')).map(accessibleName)
    .filter((name) => sources.includes(name.split(', ')[1]));
};
const quantityLabel = (q) => (!q || q === '1' ? '' : /^\d+([.,]\d+)?$/.test(q) ? `${q}× ` : `${q} `);
const rowName = (r) => [`${quantityLabel(r.quantity)}${r.name}`, sourceLabel[r.source], r.brand, r.properties].filter(Boolean).join(', ');
const rowKey = (r) => [r.name, r.brand, r.properties].map((v) => (v ?? '').toLowerCase()).join('|');
// The sheet leaves out rows for items open on the list (all but the typed row), as the app does.
const serverRows = async (text) => {
  const open = new Set(must(await api.from('items').select('name, brand, properties').eq('household_id', user.householdId).eq('status', 'active')).map(rowKey));
  const rows = must(await api.rpc('suggest_entries', { p_household: user.householdId, p_text: text.trim(), p_limit: 8 }));
  return rows.filter((r) => r.source === 'typed' || !open.has(rowKey(r))).map(rowName);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const timing = [];
page.on('console', (m) => m.text().startsWith('[add-sheet timing]') && timing.push(m.text()));
let mode = 'pass';
const answered = new Set();
const textOf = (request) => JSON.parse(request.postData() ?? '{}').p_text;

let failed = null;
const verdicts = [];
const shots = [];
const shot = async (name) => shots.push(await capture(page, dir, name));
try {
  const indexed = on ? page.waitForResponse(/\/rest\/v1\/rpc\/suggest_index/, { timeout: 30_000 }) : null;
  await signIn(page, L, user);
  if (indexed) log(`signed in as ${user.handle} on ${inst.webUrl}; the household index loaded (${(await indexed).status()})`);
  else log(`signed in as ${user.handle} on ${inst.webUrl}, expecting the flag off`);
  await page.route(/\/rest\/v1\/rpc\/(suggest_entries|parse_item|put_item)/, async (route) => {
    if (mode === 'abort') return route.abort('internetdisconnected');
    await new Promise((r) => setTimeout(r, hold));
    await route.continue();
  });
  page.on('response', (r) => /\/rpc\/suggest_entries/.test(r.url()) && answered.add(textOf(r.request())));
  mode = 'hold';

  const typeKeys = async (text, perKey, check) => {
    const field = addField(page, L);
    await field.click();
    await nextFrames(page);
    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.press('Backspace');
    const seen = [];
    for (let i = 1; i <= text.length; i++) {
      const started = Date.now();
      await page.keyboard.insertText(text[i - 1]);
      if (check(i)) {
        await nextFrames(page);
        seen.push({ text: text.slice(0, i), rows: await sheetRows(), answered: answered.has(text.slice(0, i).trim()) });
      }
      const left = perKey - (Date.now() - started);
      if (left > 0) await page.waitForTimeout(left);
    }
    if (!check(text.length)) {
      await nextFrames(page);
      seen.push({ text, rows: await sheetRows(), answered: answered.has(text.trim()) });
    }
    return seen;
  };
  const closeSheet = async () => {
    await page.keyboard.press('Escape');
    await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  };

  for (const text of texts) {
    for (const perKey of on ? [150, 30] : [150]) {
      answered.clear();
      const expected = new Map();
      for (let i = 1; i <= text.length; i++) if (text[i - 1] !== ' ') expected.set(text.slice(0, i), await serverRows(text.slice(0, i)));
      const answer = page.waitForResponse((r) => /\/rpc\/suggest_entries/.test(r.url()) && textOf(r.request()) === text.trim(), { timeout: 15_000 });
      answer.catch(() => {});
      const seen = await typeKeys(text, perKey, (i) => perKey >= 150 || i === text.length);
      for (const s of seen) {
        const want = expected.get(s.text) ?? expected.get(s.text.trimEnd());
        const match = same(s.rows, want);
        log(`"${text}" ${perKey} ms/key, after "${s.text}" (its answer ${s.answered ? 'arrived' : 'held'}): [${s.rows.join(' | ')}]${match ? ' = the server\'s ranking' : ` != the server's [${want.join(' | ')}]`}`);
        if (s.answered) throw new Error(`the server's answer for "${s.text}" arrived before its check: the hold proved nothing`);
        if (on && !match) throw new Error(`after "${s.text}" the rows are not the server's ranking`);
        verdicts.push({ text, perKey, prefix: s.text, match });
      }
      const slug = text.toLowerCase().replace(/[^a-z0-9]+/g, '-');
      const before = seen.at(-1).rows;
      if (perKey >= 150) await shot(`${slug}-held`);
      await (await answer).finished();
      await page.waitForTimeout(300);
      await nextFrames(page);
      const after = await sheetRows();
      const kept = same(after, before);
      log(`"${text}" ${perKey} ms/key: the server answered; rows [${after.join(' | ')}]${kept ? ', unchanged' : ` (were [${before.join(' | ')}])`}`);
      if (perKey >= 150) await shot(`${slug}-answered`);
      if (on && !kept) throw new Error(`the server's answer changed the rows for "${text}"`);
      if (!on && !same(after, expected.get(text.trim()))) throw new Error(`flag off: after the answer the rows for "${text}" are not the server's`);
      await closeSheet();
    }
  }
  if (!on) {
    const stale = verdicts.filter((v) => !v.match && v.prefix === v.text);
    log(`flag off: ${stale.length} of ${texts.length} texts showed other rows than the server's ranking at their last key before the answer`);
    if (!stale.length) throw new Error('flag off, yet every text showed the server\'s ranking before its answer: is the flag really off?');
  } else {
    const typed = await typeKeys('Erdbe', 150, () => false);
    const row = addSheet(page, L).getByRole('button', { name: `Erdbeere, ${sourceLabel.catalog}`, exact: true });
    log(`"Erdbe" held again: tapping "Erdbeere, ${sourceLabel.catalog}" of [${typed.at(-1).rows.join(' | ')}]`);
    await row.click();
    const note = addSheet(page, L).getByText(new RegExp(`^✓ ${L('addedItem', { name: '' }).trim()} Erdbeere`));
    await note.waitFor({ timeout: 10_000 });
    log(`the note: "${await note.textContent()}"`);
    await shot('tap-catalog-row');
    let stored = null;
    for (let i = 0; i < 40 && !stored; i++) {
      await page.waitForTimeout(250);
      stored = must(await api.from('items').select('name, quantity, brand, categories(name)').eq('household_id', user.householdId).eq('name', 'Erdbeere').eq('status', 'active'))[0] ?? null;
    }
    log(`database: ${JSON.stringify(stored)}`);
    if (!stored) throw new Error('the tapped Erdbeere never reached the server');
    await closeSheet();

    mode = 'abort';
    const offline = await typeKeys('Rote Be', 150, (i) => i === 3 || i === 7);
    await page.waitForTimeout(600);
    await nextFrames(page);
    const later = await sheetRows();
    for (const s of offline) {
      const want = await serverRows(s.text);
      log(`offline (suggest_entries, parse_item and put_item aborted), after "${s.text}": [${s.rows.join(' | ')}]${same(s.rows, want) ? ' = the server\'s ranking' : ` != [${want.join(' | ')}]`}`);
      if (!same(s.rows, want)) throw new Error(`offline the rows for "${s.text}" are not the ranking`);
    }
    log(`offline, after the aborted request failed: [${later.join(' | ')}]`);
    await shot('offline-rows');
    if (!same(later, offline.at(-1).rows)) throw new Error('the failed request changed the rows');
    await closeSheet();
    mode = 'hold';
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  writeFileSync(join(dir, 'timing.log'), timing.map((l) => `${l}\n`).join(''));
  await page.context().close();
  await browser.close();
  await forget();
}
log(`${timing.length} [add-sheet timing] lines in ${join(dir, 'timing.log')}`);
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS on-device-catalog, flag ${on ? 'on' : 'off'}: ${verdicts.length} checks (evidence: ${dir})`);
