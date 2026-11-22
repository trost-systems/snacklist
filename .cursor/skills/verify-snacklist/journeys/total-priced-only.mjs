// Sub-feature ld-total-priced of list-declutter (job 348, TE1 behind `total-priced-only`): the
// summary block shows only what has a price.
// On demo-familie it ticks off every open item a day ago, then puts on Mia's list Käse and Milch at
// Lidl, Seife at dm and Pinsel without a store, none priced. With --expect on (launched with
// VH_DEFINES="FLAGS_ON=total-priced-only") there is no block; with --expect off (a plain launch)
// the block lists every store with „1 ohne Preis“. Then Milch gets 1,19 €, 846 g Bananen at
// 1,79 €/kg (≈ 1,51 €) join Lidl and Pinsel gets 3,00 €: on, only Lidl and „Ohne Laden“ get a line
// and Gesamt says „2 ohne Preis“ once. Last it ticks Milch and starts a trip („Ja“): Lidl splits
// bought and open, Gesamt adds the count. It deletes the trip and its items at the end.
//
//   node journeys/total-priced-only.mjs <evidence dir> [--expect on|off] [--lang de|en] [--dark] [--scale 3.1]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const on = arg('--expect', 'on') === 'on';
const lang = arg('--lang', 'de');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
if (!dir) throw new Error('usage: total-priced-only.mjs <evidence dir> [--expect on|off] [--lang de|en] [--dark] [--scale 3.1]');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const flat = (s) => s.replace(/[\s  ]+/g, ' ');
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

const lidl = await storeId('Lidl');
const dm = await storeId('dm');
const now = new Date().toISOString();
const price = (cents, per = 'piece') => ({
  price_unit_micros: cents * 10_000, price_basis: 'unit', price_per: per, price_currency: 'EUR', priced_at: now,
});
const names = ['Käse', 'Milch', 'Seife', 'Pinsel', 'Bananen'];
const quoted = names.map((n) => `'${n}'`).join(',');
const listId = sql(`select id from public.lists where household_id = '${household}' order by position limit 1`);
const clearTrips = async () => {
  for (const id of sql(`select id from public.trip_sessions where household_id = '${household}'`).split('\n').filter(Boolean)) {
    await api.rpc('delete_trip_session', { p_id: id });
  }
};
await clearTrips();
sql(`delete from public.items where household_id = '${household}' and name in (${quoted})`);
sql(`update public.items set status = 'bought', bought_at = now() - interval '1 day', bought_by = '${mia.id}' where household_id = '${household}' and status = 'active'`);
const insert = async (name, store, extra = {}) => {
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name, store_id: store, ...extra });
  if (error) throw error;
};
await insert('Käse', lidl);
await insert('Milch', lidl);
await insert('Seife', dm);
await insert('Pinsel', null);
log('setup: Käse, Milch at Lidl, Seife at dm, Pinsel without a store, none priced');

const { browser, page, L, errors } = await openApp(inst, { lang, dark });
const tag = `${on ? 'on' : 'off'}-${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}`;
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
const toEnd = async () => {
  await page.mouse.move(195, 400);
  for (let i = 0; i < 20; i++) {
    await page.mouse.wheel(0, 1000);
    await page.waitForTimeout(100);
  }
  await page.waitForTimeout(800);
};
const has = (snapshot, text) => snapshot.includes(flat(text));

let failed = null;
try {
  await signIn(page, L, mia);
  log(`signed in as mia (${tag}) on ${inst.webUrl}`);
  // After the sign-in: at large text the analytics question's buttons sit below the fold.
  if (scale !== 1) await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await until(async () => (await itemRow(page, 'Pinsel').count()) === 1, 'Pinsel on the list');
  await toEnd();
  const none = await aria();
  const total = L('subtotalsTotal');
  if (on) {
    check(!has(none, `${total},`) && !has(none, unpriced(4)), 'no price at all: no block, no count');
  } else {
    for (const text of [`dm, ${unpriced(1)}`, `Lidl, ${unpriced(2)}`, `${L('noStore')}, ${unpriced(1)}`, `${total}, ${unpriced(4)}`]) {
      check(has(none, text), `no price at all: the block reads „${flat(text)}“`);
    }
  }
  await shot('01-no-price');

  await api.from('items').update(price(119)).eq('household_id', household).eq('name', 'Milch');
  await api.from('items').update(price(300)).eq('household_id', household).eq('name', 'Pinsel');
  await insert('Bananen', lidl, { quantity: '846 g', ...price(179, 'kg') });
  await until(async () => (await itemRow(page, 'Bananen').count()) === 1, 'Bananen on the list');
  await toEnd();
  const some = await aria();
  const lidlLine = `Lidl, ${atLeast(about(money(270)))}`;
  check(has(some, on ? `"${lidlLine}"` : `${lidlLine}, ${unpriced(1)}`), `Lidl reads „${lidlLine}“${on ? ' and nothing more' : ''}`);
  check(has(some, `${L('noStore')}, ${money(300)}`), `„${L('noStore')}“ has its own line`);
  const gesamt = `${total}, ${atLeast(about(money(570)))}, ${on ? '' : `${L('subtotalsPriced', { count: '3' })}, `}${unpriced(2)}`;
  check(has(some, gesamt), `Gesamt reads „${flat(gesamt)}“`);
  check(has(some, `dm, ${unpriced(1)}`) === !on, on ? 'no line for dm, which has no price' : 'dm keeps its line');
  await shot('02-some-priced');

  await reveal(page, itemRow(page, 'Milch'));
  await itemRow(page, 'Milch').click();
  await until(async () => (await button(L('shopAskYes')).count()) === 1, 'the trip question after ticking Milch');
  await button(L('shopAskYes')).click();
  await until(async () => (await button(L('shopEnd')).count()) === 1, 'the trip strip');
  await toEnd();
  const trip = await aria();
  const bought = L('subtotalsBought', { amount: money(119) });
  const lidlOpen = L('subtotalsOpen', { amount: about(money(151)) });
  check(has(trip, `${lidlLine}, ${bought}, ${lidlOpen}${on ? '' : `, ${unpriced(1)}`}`), 'Lidl splits bought and open');
  const tripTotal = `${total}, ${atLeast(about(money(570)))}, ${bought}, ${L('subtotalsOpen', { amount: about(money(451)) })}, ${unpriced(2)}`;
  check(has(trip, tripTotal), `during the trip Gesamt reads „${flat(tripTotal)}“`);
  await shot('03-trip');
  check(errors.length === 0, `no page errors (${errors.join('; ')})`);
} catch (e) {
  failed = e;
  await shot('fail').catch(() => {});
} finally {
  await browser.close();
  await clearTrips();
  sql(`delete from public.items where household_id = '${household}' and name in (${quoted})`);
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
