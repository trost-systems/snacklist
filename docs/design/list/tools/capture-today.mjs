// Today's "Recently used" in the real app (release web build, verify-snacklist instance): the round's mock list
// (EDEKA, dm, three items bought a few minutes ago) put into the seeded household, then the list's end with the
// section collapsed and expanded. It records the semantics boxes of the last open row, what sits between it and the
// tile, the tile and the recent rows, with the list's scroll offset, and a screenshot of each state. The round's
// replica is calibrated against these numbers. Built on job 347's docs/design/order/tools/capture-today.mjs.
//
//   node docs/design/list/tools/capture-today.mjs <out dir> [--lang en|de] [--scale 3.1]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, instance, itemRow, member, openApp, signIn } from '../../../../.claude/skills/verify-snacklist/helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'en');
const scale = Number(arg('--scale', '1'));
if (!dir) throw new Error('usage: capture-today.mjs <out dir> [--lang en|de] [--scale 3.1]');
mkdirSync(dir, { recursive: true });

const open = [
  { en: 'Bananas', de: 'Bananen', qty: '6', store: 'EDEKA' },
  { en: 'Apples', de: 'Äpfel', qty: '1 kg', store: 'EDEKA' },
  { en: 'Tomatoes', de: 'Tomaten', store: 'EDEKA' },
  { en: 'Bread', de: 'Brot', store: 'EDEKA' },
  { en: 'Milk', de: 'Milch', qty: '2', store: 'EDEKA' },
  { en: 'Butter', de: 'Butter', store: 'EDEKA' },
  { en: 'Eggs', de: 'Eier', qty: '10', store: 'EDEKA' },
  { en: 'Pasta', de: 'Nudeln', store: 'EDEKA' },
  { en: 'Toothpaste', de: 'Zahnpasta', store: 'dm' },
  { en: 'Shampoo', de: 'Shampoo', store: 'dm' },
  { en: 'Toilet paper', de: 'Toilettenpapier', store: 'dm' },
];
const bought = [
  { en: 'Coffee', de: 'Kaffee', store: 'EDEKA' },
  { en: 'Cheese', de: 'Käse', store: 'EDEKA' },
  { en: 'Yogurt', de: 'Joghurt', store: 'EDEKA' },
];

const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();

const storeIds = {};
for (const name of ['EDEKA', 'dm']) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  storeIds[name] = data.find((s) => s.name === name)?.id;
  if (!storeIds[name]) {
    const { data: id, error: e } = await api.rpc('add_store', { p_household: household, p_name: name });
    if (e) throw e;
    storeIds[name] = id;
  }
}
sql(`update public.stores set sort_order = 100 where household_id = '${household}'`);
sql(`update public.stores set sort_order = 0 where id = '${storeIds.EDEKA}'`);
sql(`update public.stores set sort_order = 1 where id = '${storeIds.dm}'`);

// Only the round's items: the seed's own, open or bought, would add rows to the list and to Recently used.
sql(`delete from public.items where household_id = '${household}'`);
const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
for (const i of [...open, ...bought]) {
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name: i[lang], store_id: storeIds[i.store], quantity: i.qty ?? null });
  if (error) throw error;
  await new Promise((r) => setTimeout(r, 30));
}
// Ticked in the order Coffee, Cheese, Yogurt, a minute apart: Recently used shows the newest first.
for (const [k, i] of bought.entries()) {
  sql(`update public.items set status = 'bought', bought_at = now() - interval '${10 - k} minutes', bought_by = '${mia.id}' where household_id = '${household}' and name = '${i[lang].replace(/'/g, "''")}'`);
}

const viewport = { width: 390, height: 844 };
const tag = `${lang}-${Math.round(scale * 100)}`;
const { browser, page, L } = await openApp(inst, { lang, viewport, dpr: 1 });
const nodes = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => {
  const r = n.getBoundingClientRect();
  const leaf = !n.querySelector('flt-semantics');
  const own = (leaf ? n.textContent : [...n.childNodes].filter((c) => c.nodeType === 3).map((c) => c.textContent).join('')).trim();
  return { role: n.getAttribute('role') ?? (n.querySelector(':scope > h1, :scope > h2, :scope > h3') ? 'heading' : null), label: n.getAttribute('aria-label') || own || n.querySelector(':scope > h1, :scope > h2, :scope > h3')?.textContent || '', expanded: n.getAttribute('aria-expanded'), top: r.top, bottom: r.bottom, left: r.left, right: r.right, height: r.height };
}).filter((n) => n.bottom > n.top && n.label));

// The list's scroll offset, followed through every wheel step by the boxes both frames share.
let offset = 0;
let last = null;
const key = (n) => `${n.role}|${n.label}|${n.left}`;
async function track() {
  const now = await nodes();
  if (last) {
    const before = new Map(last.map((n) => [key(n), n]));
    const moves = now.map((n) => before.get(key(n)) && before.get(key(n)).top - n.top).filter((d) => d !== undefined && d !== 0 && Number.isFinite(d)).sort((a, b) => a - b);
    if (moves.length) offset += moves[Math.floor(moves.length / 2)];
  }
  last = now;
  return now;
}
async function toEnd() {
  await page.mouse.move(viewport.width / 2, viewport.height / 3);
  let still = 0;
  let prev = offset;
  for (let k = 0; k < 120 && still < 3; k += 1) {
    await page.mouse.wheel(0, 150);
    await page.waitForTimeout(150);
    await track();
    still = offset === prev ? still + 1 : 0;
    prev = offset;
  }
  await page.waitForTimeout(600);
  return track();
}

const readd = L('readd');
const tileName = L('recentlyUsed');
const park = () => page.mouse.move(1, viewport.height - 1);
function measure(all) {
  const rows = all.filter((n) => n.role === 'checkbox');
  const lastRow = rows.at(-1) ?? null;
  const tile = all.find((n) => n.label.startsWith(tileName) && n.role === 'button') ?? all.find((n) => n.label.startsWith(tileName)) ?? null;
  const used = all.filter((n) => n.label.endsWith(readd));
  // What the list draws between the last open row and the tile (the summary block, a store's total).
  const between = lastRow && tile ? all.filter((n) => n.top >= lastRow.bottom - 0.5 && n.bottom <= tile.top + 0.5 && n !== tile) : [];
  return {
    scrollOffset: offset,
    lastOpenRow: lastRow,
    openRowHeight: lastRow?.height ?? null,
    between,
    tile,
    tileHeight: tile?.height ?? null,
    gapLastRowToTile: lastRow && tile ? tile.top - lastRow.bottom : null,
    gapAboveTile: tile ? tile.top - Math.max(lastRow?.bottom ?? -Infinity, ...between.map((n) => n.bottom)) : null,
    usedRows: used,
    usedRowHeight: used[0]?.height ?? null,
    tileBottomToFirstUsed: tile && used[0] ? used[0].top - tile.bottom : null,
    nodes: all,
  };
}

const out = { lang, scale, viewport };
try {
  await signIn(page, L, mia);
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await page.reload();
  await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await itemRow(page, open[0][lang]).waitFor({ timeout: 20_000 });
  await page.waitForTimeout(1200);
  out.top = await track();
  out.collapsed = measure(await toEnd());
  out.addField = await page.getByRole('textbox', { name: L('addFieldHint') }).boundingBox();
  await park();
  await page.waitForTimeout(400);
  await page.screenshot({ path: join(dir, `${tag}-collapsed.png`) });
  await page.getByRole('button', { name: new RegExp(`^${tileName}`) }).click();
  await page.waitForTimeout(800);
  out.expandedInPlace = measure(await track());
  out.expanded = measure(await toEnd());
  await park();
  await page.waitForTimeout(1500);
  await page.screenshot({ path: join(dir, `${tag}-expanded.png`) });
  const c = out.collapsed;
  const e = out.expanded;
  console.log(`${tag}: open row ${c.openRowHeight}, tile ${c.tileHeight} (gap above ${c.gapAboveTile}, from last row ${c.gapLastRowToTile}), between ${JSON.stringify(c.between.map((n) => n.label))}, used rows ${e.usedRows.length} x ${e.usedRowHeight}, offset ${c.scrollOffset} -> ${e.scrollOffset}`);
} finally {
  await browser.close();
}
writeFileSync(join(dir, `${tag}.json`), JSON.stringify(out, null, 1));
