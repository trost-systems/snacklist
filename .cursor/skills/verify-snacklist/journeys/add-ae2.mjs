// Feature quick-add, sub-feature qa-ae2-peeks (flag add-ae2-list-peeks, job 490, AE2): the list
// stays in view above the open add sheet. Proves, at 390x844: the rows and the top bar show above
// the sheet with no scrim; adds are marked „Neu“ in their place until the sheet closes; a seeded
// open item typed again is one row with the merge part and its own tick button, then the + row;
// Enter raises its Menge (one active row in the database), the tick button ticks it off; a tap on
// the list closes the sheet without ticking the row, a wheel scrolls the list with the sheet open;
// an add sorted below the sheet is scrolled between the top bar and the sheet; at 200 % text both
// actions of the split row stay on screen. Resets its items first and last, so it reruns on the
// same seed.
//
//   node journeys/add-ae2.mjs <evidence dir> [--lang de|en] [--dark]
// on demo-familie (de) or demo-family-en (en), launched with VH_DEFINES="FLAGS_ON=add-ae2-list-peeks".
import process from 'node:process';
import { accessibleName, addField, addSheet, apiAs, capture, flagOn, householdButton, instance, itemRow, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: add-ae2.mjs <evidence dir> [--lang de|en] [--dark]');
for (const flag of ['add-ae2-list-peeks', 'add-match-rows', 'add-sheet-compact']) {
  if (!flagOn(flag)) throw new Error(`the build has ${flag} off: launch with VH_DEFINES="FLAGS_ON=add-ae2-list-peeks" and export it here too`);
}
const words = lang === 'de'
  ? { household: 'Familie Brandt', added: ['Kefir', 'Ingwer'], low: 'Shampoo', dup: 'Bananen', dupQty: '6', big: 'Vollmilch', tap: 'Butter' }
  : { household: 'Brandt family', added: ['Kefir', 'Ginger'], low: 'Shampoo', dup: 'Bananas', dupQty: '6', big: 'Milk', tap: 'Butter' };

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const rows = (name) => api.from('items').select('id, name, quantity, status').eq('household_id', user.householdId).eq('name', name);
async function reset() {
  const ours = [...words.added, words.low];
  const { error: del } = await api.from('items').delete().eq('household_id', user.householdId).in('name', ours);
  if (del) throw del;
  const { data: dups } = await rows(words.dup);
  const [keep, ...extra] = dups ?? [];
  if (extra.length) await api.from('items').delete().in('id', extra.map((r) => r.id));
  if (keep) {
    const { error } = await api.from('items').update({ status: 'active', quantity: words.dupQty }).eq('id', keep.id);
    if (error) throw error;
  }
}
await reset();

const { browser, page, L, errors } = await openApp(inst, { lang, dark, videoDir: dir });
const marked = (label) => label.endsWith(` ${L('newItem')}`);
const nameOf = async (locator) => ((await locator.getAttribute('aria-label')) || accessibleName(await locator.ariaSnapshot())).replace(/\s+/g, ' ').trim();
const box = (locator) => locator.boundingBox({ timeout: 5_000 });
const sheetTop = async () => (await box(addSheet(page, L))).y;
const barBottom = async () => { const b = await box(householdButton(page, words.household)); return b.y + b.height; };
const fmt = (b) => b && `y ${b.y.toFixed(1)}..${(b.y + b.height).toFixed(1)}`;
const listNames = async () => Promise.all((await page.getByRole('checkbox').all()).map(nameOf));
const settle = async (locator) => {
  let last;
  for (let i = 0; i < 30; i++) {
    const b = await box(locator);
    if (last && b && Math.abs(b.y - last.y) < 0.5) return b;
    last = b;
    await page.waitForTimeout(150);
  }
  return last;
};
const until = async (what, check, timeout = 10_000) => {
  const end = Date.now() + timeout;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > end) throw new Error(`timed out: ${what}`);
    await page.waitForTimeout(200);
  }
};
// Mean RGB of a screen patch, read back through the page: a scrim would darken it.
const patchColor = async (clip) => {
  const png = await page.screenshot({ clip });
  return page.evaluate(async (b64) => {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const bmp = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
    const ctx = new OffscreenCanvas(bmp.width, bmp.height).getContext('2d');
    ctx.drawImage(bmp, 0, 0);
    const d = ctx.getImageData(0, 0, bmp.width, bmp.height).data;
    const sum = [0, 0, 0];
    for (let i = 0; i < d.length; i += 4) for (let c = 0; c < 3; c++) sum[c] += d[i + c];
    return sum.map((v) => Math.round(v / (d.length / 4)));
  }, png.toString('base64'));
};
const openSheet = async () => {
  await addField(page, L).click();
  await addSheet(page, L).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(600);
};
const closeSheet = async () => {
  await addField(page, L).press('Escape');
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  await page.waitForTimeout(400);
};
const sheetButtons = async () => (await addSheet(page, L).getByRole('button').all());
const mergeButton = () => addSheet(page, L).getByRole('button', { name: new RegExp(`^${L('dedupeMerge')}, `) });
const tickButton = (name) => addSheet(page, L).getByRole('button', { name: `${L('addMatchTickOff')}, ${name}`, exact: true });

let failed = null;
const results = [];
const pass = (n, line) => { results.push(`${n} PASS`); log(`check ${n} PASS: ${line}`); };
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}${dark ? ', dark' : ''}) on ${inst.webUrl}`);
  await itemRow(page, words.tap).waitFor();
  await page.waitForTimeout(800);
  const tapBox = await box(itemRow(page, words.tap));
  const patch = { x: 300, y: tapBox.y + 8, width: 80, height: tapBox.height - 16 };
  const before = await patchColor(patch);
  await capture(page, dir, '01-list');

  // 1. The list above the open sheet.
  await openSheet();
  const top1 = await sheetTop();
  const bar1 = await barBottom();
  const shown = [];
  for (const row of await page.getByRole('checkbox').all()) {
    const b = await box(row);
    if (b && b.y >= bar1 && b.y + b.height <= top1) shown.push(await nameOf(row));
  }
  const after = await patchColor(patch);
  const shift = Math.max(...after.map((v, i) => Math.abs(v - before[i])));
  log(`sheet top ${top1.toFixed(1)}, top bar bottom ${bar1.toFixed(1)}; ${shown.length} rows fully between them: ${shown.join(' | ')}`);
  log(`list patch ${JSON.stringify(patch)} rgb before ${before} after ${after} (max channel shift ${shift})`);
  await capture(page, dir, '02-sheet-open');
  if (shown.length < 5) throw new Error(`only ${shown.length} list rows show above the sheet`);
  if (bar1 < 0 || bar1 > top1) throw new Error('the top bar is not on screen above the sheet');
  if (shift > 6) throw new Error(`the list behind the sheet changed colour by ${shift}: a scrim?`);
  pass(1, `${shown.length} rows and the top bar above the sheet, no scrim (shift ${shift})`);

  // 2. Adds marked in their place until the sheet closes.
  const [first, second] = words.added;
  await typeInto(addField(page, L), first);
  await addField(page, L).press('Enter');
  const firstRow = itemRow(page, first).first();
  await until(`${first} marked`, async () => (await firstRow.count()) && marked(await nameOf(firstRow)));
  const order1 = await listNames();
  const at = order1.findIndex((n) => n.startsWith(`${first} `));
  log(`added ${first}: row "${await nameOf(firstRow)}" at ${at + 1} of ${order1.length}, between "${order1[at - 1] ?? '-'}" and "${order1[at + 1] ?? '-'}"; ${fmt(await settle(firstRow))}`);
  await capture(page, dir, '03-added-first');
  await typeInto(addField(page, L), second);
  await addField(page, L).press('Enter');
  const secondRow = itemRow(page, second).first();
  await until(`${second} marked`, async () => (await secondRow.count()) && marked(await nameOf(secondRow)));
  const both = [await nameOf(firstRow), await nameOf(secondRow)];
  log(`second add: rows "${both.join('", "')}"`);
  await capture(page, dir, '04-added-second');
  if (!both.every(marked)) throw new Error(`both adds should stay marked: ${both.join(', ')}`);
  if (at === order1.length - 1) log(`note: ${first} sorted last on the list`);
  await closeSheet();
  const closed = [await nameOf(firstRow), await nameOf(secondRow)];
  const stillMarked = (await listNames()).filter(marked);
  log(`after close: "${closed.join('", "')}"; marked rows: ${stillMarked.length}`);
  await capture(page, dir, '05-closed-no-tags');
  if (stillMarked.length) throw new Error(`rows still marked after close: ${stillMarked.join(', ')}`);
  pass(2, `"${first}" placed at ${at + 1}/${order1.length} and marked, both marked after "${second}", none after close`);

  // 3. A seeded open item typed again: the split row, then the + row; Enter merges.
  await openSheet();
  await typeInto(addField(page, L), words.dup);
  await mergeButton().first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(300);
  const names = [];
  for (const b of await sheetButtons()) names.push(await nameOf(b));
  const offered = names.filter((n) => n !== L('close'));
  const mergeBox = await box(mergeButton().first());
  const tickBox = await box(tickButton(words.dup));
  log(`typed "${words.dup}": sheet buttons ${JSON.stringify(offered)}; merge ${fmt(mergeBox)} x ${mergeBox.x}..${mergeBox.x + mergeBox.width}, tick ${fmt(tickBox)} x ${tickBox.x}..${tickBox.x + tickBox.width}`);
  const dupRow = itemRow(page, words.dup).first();
  const dupBox = await settle(dupRow);
  log(`list row "${await nameOf(dupRow)}" ${fmt(dupBox)} (sheet top ${(await sheetTop()).toFixed(1)}, bar ${(await barBottom()).toFixed(1)})`);
  await capture(page, dir, '06-duplicate-split-row');
  if (!offered[0]?.startsWith(`${L('dedupeMerge')}, `)) throw new Error(`first sheet button is "${offered[0]}", not the merge`);
  if (offered[1] !== `${L('addMatchTickOff')}, ${words.dup}`) throw new Error(`second sheet button is "${offered[1]}", not the tick`);
  if (!offered[2]?.includes(words.dup)) throw new Error(`third sheet button is "${offered[2]}", not the + row`);
  if (Math.abs(mergeBox.y - tickBox.y) > 1 || tickBox.x < mergeBox.x + mergeBox.width - 1) throw new Error('merge and tick are not one row');
  if (tickBox.width < 48 || tickBox.height < 48) throw new Error(`tick button is ${tickBox.width}x${tickBox.height}`);
  await addField(page, L).press('Enter');
  const merged = await until('one active row with a raised Menge', async () => {
    const { data } = await rows(words.dup);
    const active = (data ?? []).filter((r) => r.status === 'active');
    return active.length === 1 && active[0].quantity !== words.dupQty ? data : null;
  });
  await page.waitForTimeout(500);
  log(`database after Enter: ${JSON.stringify(merged)}; list rows named ${words.dup}: ${await itemRow(page, words.dup).count()}`);
  await capture(page, dir, '07-merged');
  if (merged.length !== 1) throw new Error(`expected one ${words.dup} row, found ${merged.length}`);
  pass(3, `buttons ${JSON.stringify(offered.slice(0, 3))}; Enter: ${JSON.stringify(merged)}`);

  // 4. The tick button ticks it off.
  await typeInto(addField(page, L), words.dup);
  await tickButton(words.dup).waitFor({ timeout: 10_000 });
  await tickButton(words.dup).click();
  const ticked = await until('status bought', async () => {
    const { data } = await rows(words.dup);
    return data?.length === 1 && data[0].status === 'bought' ? data : null;
  });
  log(`database after the tick button: ${JSON.stringify(ticked)}`);
  await capture(page, dir, '08-ticked');
  pass(4, `tick button: ${JSON.stringify(ticked)}`);

  // 5. A tap on the list closes the sheet and ticks nothing; a wheel scrolls it, the sheet stays.
  if (await addField(page, L).inputValue()) await addField(page, L).fill('');
  const tapRow = itemRow(page, words.tap).first();
  const tapAt = await settle(tapRow);
  const top5 = await sheetTop();
  if (!(tapAt.y + tapAt.height <= top5)) throw new Error(`${words.tap} is not above the sheet (${fmt(tapAt)}, sheet ${top5})`);
  await page.mouse.click(tapAt.x + tapAt.width / 2, tapAt.y + tapAt.height / 2);
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  await page.waitForTimeout(800);
  const { data: tapData } = await rows(words.tap);
  const checked = await tapRow.getAttribute('aria-checked');
  log(`tapped "${words.tap}" at ${fmt(tapAt)}: sheet closed; row aria-checked=${checked}; database ${JSON.stringify(tapData)}`);
  await capture(page, dir, '09-tap-closed');
  if (tapData?.[0]?.status !== 'active' || checked === 'true') throw new Error(`the tap ticked ${words.tap}`);
  await openSheet();
  const probe = itemRow(page, words.tap).first();
  const yBefore = (await settle(probe)).y;
  const sheetBefore = await box(addSheet(page, L));
  await page.mouse.move(195, (await barBottom()) + 120);
  await page.mouse.wheel(0, 200);
  await page.waitForTimeout(800);
  const yAfter = (await settle(probe)).y;
  const sheetAfter = await box(addSheet(page, L));
  log(`wheel 200 over the list: "${words.tap}" y ${yBefore.toFixed(1)} -> ${yAfter.toFixed(1)}; sheet ${fmt(sheetBefore)} -> ${fmt(sheetAfter)}`);
  await capture(page, dir, '10-wheel-scrolled');
  if (!(yAfter < yBefore - 20)) throw new Error('the wheel did not scroll the list');
  if (Math.abs(sheetAfter.y - sheetBefore.y) > 1) throw new Error('the sheet moved or closed on the wheel');
  pass(5, `tap closed the sheet, ${words.tap} still active; wheel moved the list ${(yBefore - yAfter).toFixed(1)} px, sheet stayed`);

  // 6. An add sorted below the sheet ends up between the top bar and the sheet.
  await page.mouse.wheel(0, -2000);
  await page.waitForTimeout(800);
  const lastSeeded = page.getByRole('checkbox').last();
  const lastBox = await box(lastSeeded);
  log(`list top again; last built row "${await nameOf(lastSeeded)}" ${fmt(lastBox)}, sheet top ${(await sheetTop()).toFixed(1)}`);
  const anchor = itemRow(page, words.tap).first();
  const anchorBefore = (await settle(anchor)).y;
  await typeInto(addField(page, L), words.low);
  await addField(page, L).press('Enter');
  const lowRow = itemRow(page, words.low).first();
  await until(`${words.low} on the list`, async () => (await lowRow.count()) > 0);
  await page.waitForTimeout(1200);
  const lowBox = await settle(lowRow);
  const top6 = await sheetTop();
  const bar6 = await barBottom();
  const order6 = await listNames();
  const anchorAfter = (await anchor.count()) ? (await box(anchor))?.y : null;
  log(`added ${words.low}: row ${fmt(lowBox)} at ${order6.findIndex((n) => n.startsWith(`${words.low} `)) + 1} of ${order6.length}; top bar bottom ${bar6.toFixed(1)}, sheet top ${top6.toFixed(1)}; first row y ${anchorBefore.toFixed(1)} -> ${anchorAfter?.toFixed(1) ?? 'off screen'}`);
  await capture(page, dir, '11-low-add-in-view');
  if (!(lowBox.y >= bar6 - 0.5 && lowBox.y + lowBox.height <= top6 + 0.5)) throw new Error(`${words.low} at ${fmt(lowBox)} is not between ${bar6} and ${top6}`);
  if (anchorAfter !== null && anchorAfter !== undefined && Math.abs(anchorAfter - anchorBefore) < 1) log('note: the list did not scroll for this add');
  pass(6, `${words.low} ${fmt(lowBox)} between bar ${bar6.toFixed(1)} and sheet ${top6.toFixed(1)}`);

  // 7. 200 % text with a duplicate typed.
  await closeSheet();
  await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
  await page.waitForTimeout(1000);
  await openSheet();
  await typeInto(addField(page, L), words.big);
  await mergeButton().first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  const m7 = await box(mergeButton().first());
  const t7 = await box(tickButton(words.big));
  const vp = page.viewportSize();
  log(`200 %: merge "${await nameOf(mergeButton().first())}" ${fmt(m7)} x ${m7.x}..${m7.x + m7.width}; tick ${fmt(t7)} x ${t7.x}..${t7.x + t7.width} (${t7.width}x${t7.height})`);
  await capture(page, dir, '12-large-text-duplicate');
  for (const [what, b] of [['merge', m7], ['tick', t7]]) {
    if (b.x < 0 || b.y < 0 || b.x + b.width > vp.width + 0.5 || b.y + b.height > vp.height) throw new Error(`${what} is off screen at 200 %`);
  }
  pass(7, `merge ${fmt(m7)} and tick ${fmt(t7)} (${t7.width.toFixed(0)}x${t7.height.toFixed(0)}) on screen at 200 %`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await reset().catch((e) => log(`reset failed: ${e.message}`));
}
log(`results: ${results.join(', ') || 'none'}`);
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS add-ae2 (evidence: ${dir})`);
