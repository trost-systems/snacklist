// Sub-feature ld-total of list-declutter (job 237, ST3): the summary block above „Zuletzt
// verwendet“. Launch with VH_DEFINES="FLAGS_ON=list-declutter,prices-and-trip-total,trip-mode".
// On demo-familie it ticks off every open item a day ago, then puts on Mia's list: at Lidl Milch
// 1,19 €, Brot 2,49 €, Käse without a price and 846 g Bananen at 1,79 €/kg typed per kg (≈ 1,51 €);
// at dm Seife 0,95 €; at „Wochenmarkt am Kollwitzplatz (Samstag)“ 2 kg Kartoffeln from the label's
// 3,60 €; without a store Pinsel 3,00 €. It checks every line's label (floor, estimate, „Ohne
// Laden“), jumps to Lidl from its line, ticks Seife and starts a trip („Ja“): dm stays „alles
// gekauft“, Gesamt splits bought and open. Beenden ends the trip; ticked items drop out
// again. It deletes the trip and its items at the end.
//
//   node journeys/list-summary.mjs <evidence dir> [--lang de|en] [--dark] [--scale 1.6] [--compact]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'de');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
const compact = rest.includes('--compact');
if (!dir) throw new Error('usage: list-summary.mjs <evidence dir> [--lang de|en] [--dark] [--scale 1.6] [--compact]');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const flat = (s) => s.replace(/[\s  ]+/g, ' ');
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const money = (cents) => (lang === 'en' ? `€${(cents / 100).toFixed(2)}` : `${(cents / 100).toFixed(2).replace('.', ',')} €`);

async function storeId(name) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  const found = data.find((s) => s.name === name)?.id;
  if (found) return found;
  const { data: id, error: e } = await api.rpc('add_store', { p_household: household, p_name: name });
  if (e) throw e;
  return id;
}

const market = 'Wochenmarkt am Kollwitzplatz (Samstag)';
const lidl = await storeId('Lidl');
const dm = await storeId('dm');
const marketId = await storeId(market);
const now = new Date().toISOString();
const price = (cents, per = 'piece', basis = 'unit') => ({
  price_unit_micros: cents * 10_000, price_basis: basis, price_per: per, price_currency: 'EUR', priced_at: now,
});
const mine = [
  ['Milch', lidl, null, price(119)],
  ['Brot', lidl, null, price(249)],
  ['Käse', lidl, null, {}],
  ['Bananen', lidl, '846 g', price(179, 'kg')],
  ['Seife', dm, null, price(95)],
  ['Kartoffeln', marketId, '2 kg', price(180, 'kg', 'line')],
  ['Pinsel', null, null, price(300)],
];
const names = mine.map(([name]) => `'${name}'`).join(',');
const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
for (const id of sql(`select id from public.trip_sessions where household_id = '${household}'`).split('\n').filter(Boolean)) {
  await api.rpc('delete_trip_session', { p_id: id });
}
sql(`delete from public.items where household_id = '${household}' and name in (${names})`);
sql(`update public.items set status = 'bought', bought_at = now() - interval '1 day', bought_by = '${mia.id}' where household_id = '${household}' and status = 'active'`);
for (const [name, store, quantity, p] of mine) {
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name, store_id: store, quantity, ...p });
  if (error) throw error;
}
log(`setup: ${mine.map(([n, , q, p]) => `${q ? `${q} ` : ''}${n}${p.price_unit_micros ? ` ${p.price_unit_micros / 10_000}/${p.price_per}/${p.price_basis}` : ''}`).join(', ')}`);

const viewport = compact ? { width: 358, height: 760 } : undefined;
const { browser, context, page, L, errors } = await openApp(inst, { lang, dark, ...(viewport && { viewport }) });
if (scale !== 1) await context.addInitScript((s) => {
  document.addEventListener('DOMContentLoaded', () => { document.documentElement.style.fontSize = `${s * 100}%`; });
}, scale);
const tag = `${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}${compact ? '-358' : ''}`;
const shot = async (name) => {
  await page.mouse.move(1, 1);
  await page.waitForTimeout(500);
  return capture(page, dir, `${tag}-${name}`);
};
const aria = async () => flat(await page.locator('body').ariaSnapshot());
const until = async (test, what, timeout = 15_000) => {
  for (const end = Date.now() + timeout; Date.now() < end; await page.waitForTimeout(200)) {
    if (await test()) return;
  }
  throw new Error(`${what} not seen after ${timeout} ms`);
};
const button = (name) => page.getByRole('button', { name, exact: true });
const atLeast = (m) => L('moneyAtLeastSpoken', { amount: m });
const about = (m) => L('moneyEstimateSpoken', { amount: m });
const unpriced = (n) => L('subtotalsUnpriced', { count: String(n) });
const line = (name) => page.getByRole('button', { name: new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}, `) });
const toEnd = async () => {
  await page.mouse.move(195, 400);
  await page.mouse.wheel(0, 20_000);
  await page.waitForTimeout(800);
};

let failed = null;
try {
  await signIn(page, L, mia);
  log(`signed in as mia (${tag}) on ${inst.webUrl}`);
  await until(async () => (await itemRow(page, 'Pinsel').count()) === 1, 'Pinsel on the list');
  const chip = page.getByRole('button', { name: flat(L('priceChipSet', { name: 'Bananen', amount: about(money(151)) })) });
  check(await chip.count() === 1, `Bananen's price reads „${L('moneyEstimate', { amount: money(151) })}“`);
  await toEnd();
  const block = await aria();
  const expected = [
    `Lidl, ${atLeast(about(money(519)))}, ${unpriced(1)}`,
    `dm, ${money(95)}`,
    `${market}, ${money(360)}`,
    `${L('noStore')}, ${money(300)}`,
    `${L('subtotalsTotal')}, ${atLeast(about(money(1274)))}, ${L('tripCounts', { priced: '6', open: '1' })}`,
  ];
  for (const text of expected) check(block.includes(flat(text)), `the block reads „${flat(text)}“`);
  check(!block.includes(flat(L('storeSubtotal', { store: 'Lidl', amount: money(519) }))), 'no „Summe Lidl“ at the section end');
  await shot('01-block');

  await line('Lidl').click();
  await page.waitForTimeout(1000);
  // The divider's name is „Lidl, 4 Artikel“; the block's line „Lidl, mindestens …“.
  const divider = page.getByRole('button', { name: /^Lidl, \d+ \S+$/ });
  const top = (await divider.boundingBox())?.y ?? -1;
  log(`Lidl's divider at y=${Math.round(top)} after the jump`);
  check(top >= 40 && top < 200, 'the jump puts Lidl\'s divider just under the header');
  await shot('02-jumped-to-lidl');

  await reveal(page, itemRow(page, 'Seife'));
  await itemRow(page, 'Seife').click();
  await until(async () => (await button(L('shopAskYes')).count()) === 1, 'the trip question after ticking Seife');
  await button(L('shopAskYes')).click();
  await until(async () => (await button(L('shopEnd')).count()) === 1, 'the trip strip');
  await toEnd();
  const split = await aria();
  for (const text of [
    `dm, ${money(95)}, ${L('subtotalsAllBought')}`,
    // Nothing bought at Lidl yet: no split on its line.
    `Lidl, ${atLeast(about(money(519)))}, ${unpriced(1)}`,
    `${L('subtotalsTotal')}, ${atLeast(about(money(1274)))}, ${L('subtotalsBought', { amount: money(95) })}, ${L('subtotalsOpen', { amount: about(money(1179)) })}, ${unpriced(1)}`,
  ]) check(split.includes(flat(text)), `during the trip „${flat(text)}“`);
  await shot('03-trip-split');

  await button(L('shopEnd')).click();
  await page.waitForURL(/\/trip\/[0-9a-f-]{36}$/, { timeout: 15_000 });
  await page.goBack();
  await until(async () => (await itemRow(page, 'Pinsel').count()) === 1, 'back on the list');
  await toEnd();
  const after = await aria();
  check(after.includes(flat(`${L('subtotalsTotal')}, ${atLeast(about(money(1179)))}`)), `after the trip Gesamt drops Seife: ${atLeast(about(money(1179)))}`);
  check(!after.includes(flat(`dm, ${money(95)}`)), 'dm leaves the block with its section');
  await shot('04-after-trip');
  check(errors.length === 0, `no page errors (${errors.join('; ')})`);
} catch (e) {
  failed = e;
  await shot('fail').catch(() => {});
} finally {
  await browser.close();
  for (const id of sql(`select id from public.trip_sessions where household_id = '${household}'`).split('\n').filter(Boolean)) {
    await api.rpc('delete_trip_session', { p_id: id });
  }
  sql(`delete from public.items where household_id = '${household}' and name in (${names})`);
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
