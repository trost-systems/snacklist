// Feature trip-mode (job 234), behind the PostHog flag trip-mode: launch with
// VH_DEFINES="FLAGS_ON=trip-mode,grocery-log,prices-and-trip-total". Entry points: a tick on the
// list (the question), Mehr › „Einkauf starten“, Verlauf's trip tiles, the list's ended card.
// On demo-familie it puts the 15 seeded items back on the list split over Lidl and Rewe, prices
// Bananen (yesterday), Vollmilch (today) and Nudeln (yesterday), deletes the household's earlier
// trips and sessions, and takes Mia's promotional Premium away. Then as Mia: tm-ask (Nein, ask again,
// Zurücknehmen), tm-strip (Ja, Pause, Weiter), a paid price and Noah's Kaffee during the trip,
// tm-free (Beenden, the locked card), tm-history (two Verlauf trips with the session id, a tile
// opens the summary), tm-summary as Premium (Mia's promotional grant, the local stack's
// RevenueCat sync, removed afterwards), tm-manual-start, and in a second browser on Playwright's
// clock tm-long-running (45 min: paused at the last tick; 4 h: ended there, the card).
//
//   node journeys/trip-mode.mjs <evidence dir> [--lang de|en] [--dark] [--compact]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import {
  apiAs, capture, instance, itemRow, logger, member, openApp, openTab, reveal, signIn,
} from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
const compact = rest.includes('--compact');
if (!dir) throw new Error('usage: trip-mode.mjs <evidence dir> [--lang de|en] [--dark] [--compact]');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const noah = member(inst, 'noah');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const noahApi = await apiAs(inst, noah);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const plural = (template, count) => template
  .replace(/\{count, plural, =1\{([^}]*)\} other\{([^{}]*(?:\{count\}[^{}]*)*)\}\}/, (_, one, other) => (count === 1 ? one : other))
  .replaceAll('{count}', String(count));
// NumberFormat.simpleCurrency as the app formats EUR: „1,80 €“ in German, „€1.80“ in English.
const money = (cents) => (lang === 'en' ? `€${(cents / 100).toFixed(2)}` : `${(cents / 100).toFixed(2).replace('.', ',')} €`);
const hm = (iso) => new Intl.DateTimeFormat('de-DE', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Berlin' }).format(new Date(iso));
const flat = (s) => s.replace(/[\s\u00a0\u202f]+/g, ' ');

async function rpc(client, name, params) {
  const { data, error } = await client.rpc(name, params);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function storeId(name) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  return data.find((s) => s.name === name)?.id ?? rpc(api, 'add_store', { p_household: household, p_name: name });
}

const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(new Date());
const yesterday = new Date(Date.now() - 86_400_000).toISOString();
const history = () => rpc(api, 'trip_history', { p_household: household, p_today: today });
const premium = (on) => sql(`select public.promotional_premium_sync_user('${mia.id}', ${on}, null)`);

const lidl = await storeId('Lidl');
const rewe = await storeId('Rewe');
const atLidl = ['Bananen', 'Äpfel', 'Brötchen', 'Vollmilch', 'Schokolade', 'Mineralwasser', 'Apfelsaft'];
const atRewe = ['Butter', 'Nudeln', 'Reis', 'Erbsen', 'Spülmittel', 'Müllbeutel', 'Zahnpasta', 'Duschgel'];
const extra = 'Kaffee';
const noPrice = { 'price_unit_micros': null, 'price_basis': null, 'price_per': null, 'price_currency': null, 'priced_at': null };
const price = (euros, at) => ({ 'price_unit_micros': Math.round(euros * 1e6), 'price_basis': 'unit', 'price_per': 'piece', 'price_currency': 'EUR', 'priced_at': at });

premium(false);
for (const id of sql(`select id from public.trip_sessions where household_id = '${household}'`).split('\n').filter(Boolean)) {
  await rpc(api, 'delete_trip_session', { p_id: id });
}
for (const trip of (await history()).trips) await rpc(api, 'delete_trip', { p_id: trip.id });
sql(`delete from public.items where household_id = '${household}' and name = '${extra}'`);
for (const [store, names] of [[lidl, atLidl], [rewe, atRewe]]) {
  const { error } = await api.from('items').update({ status: 'active', bought_by: null, bought_at: null, store_id: store, ...noPrice })
    .eq('household_id', household).in('name', names);
  if (error) throw error;
}
for (const [name, p] of [['Bananen', price(0.25, yesterday)], ['Vollmilch', price(1.09, new Date().toISOString())], ['Nudeln', price(1.29, yesterday)]]) {
  const { error } = await api.from('items').update(p).eq('household_id', household).eq('name', name);
  if (error) throw error;
}
const listId = sql(`select list_id from public.items where household_id = '${household}' and name = 'Bananen'`);
// Legal GL-2: a pharmacy's item asks nothing and offers no log card.
const pharmacy = await storeId('APOTHEKE am Markt');
sql(`delete from public.items where household_id = '${household}' and name = 'Aspirin'`);
{
  const { error } = await api.from('items').insert({ household_id: household, list_id: listId, name: 'Aspirin', store_id: pharmacy });
  if (error) throw error;
}
const active = () => Number(sql(`select count(*) from public.items where household_id = '${household}' and status = 'active'`));
const status = (name) => sql(`select status from public.items where household_id = '${household}' and name = '${name}'`);
log(`setup: ${active()} open items (Lidl: ${atLidl.join(', ')}; Rewe: ${atRewe.join(', ')}), Bananen 0,25 €/St. yesterday, Vollmilch 1,09 €/St. today, Nudeln 1,29 € yesterday; no sessions, no trips, Mia Free`);

const viewport = compact ? { width: 358, height: 760 } : undefined;
const shots = [];
let failed = null;
const open = [];

/** One browser on the build signed in as Mia; with [clock] Playwright's clock runs from now. */
async function browserFor(name, { clock = false } = {}) {
  const app = await openApp(inst, { lang, dark, videoDir: `${dir}/${name}`, ...(viewport && { viewport }) });
  open.push(app);
  if (clock) await app.page.clock.install({ time: new Date() });
  return app;
}

function handles({ page, L }) {
  const aria = async () => flat(await page.locator('body').ariaSnapshot());
  const until = async (test, what, timeout = 15_000) => {
    for (const end = Date.now() + timeout; Date.now() < end; await page.waitForTimeout(200)) {
      if (await test()) return;
    }
    throw new Error(`${what} not seen after ${timeout} ms`);
  };
  const button = (name) => page.getByRole('button', { name, exact: true });
  const shot = async (name) => {
    await page.mouse.move(1, 1);
    await page.waitForTimeout(500);
    shots.push(name);
    return capture(page, dir, name);
  };
  // The summary builds its rows lazily: its text is the union of the snapshots on the way down.
  const scan = async () => {
    const { width, height } = page.viewportSize();
    await page.mouse.move(width / 2, height / 2);
    await page.mouse.wheel(0, -20_000);
    await page.waitForTimeout(400);
    const seen = [];
    for (let i = 0; i < 20; i++) {
      const now = await aria();
      if (seen.at(-1) === now) break;
      seen.push(now);
      await page.mouse.wheel(0, height / 2);
      await page.waitForTimeout(400);
    }
    return seen.join(' ');
  };
  const sheetUp = async () => (await button(L('shopAskYes')).count()) === 1;
  const stripUp = async () => (await button(L('shopEnd')).count()) + (await page.getByRole('button', { name: new RegExp(`^${escape(L('shopEndAt', { time: 'X' })).replace('X', '\\d\\d:\\d\\d')}$`) }).count()) === 1;
  const tick = async (name) => {
    await reveal(page, itemRow(page, name));
    await itemRow(page, name).click();
    await until(() => status(name) === 'bought', `${name} bought in the database`);
  };
  return { aria, scan, until, button, shot, sheetUp, stripUp, tick };
}

try {
  const app = await browserFor('mia');
  const { page, L } = app;
  const { aria, scan, until, button, shot, sheetUp, stripUp, tick } = handles(app);
  await signIn(page, L, mia);
  log(`signed in as mia (${lang}${dark ? ', dark' : ''}${compact ? ', 358 px' : ''}) on ${inst.webUrl}`);

  // tm-ask
  await tick('Äpfel');
  await until(sheetUp, `„${L('shopAskTitle')}“ after ticking Äpfel`);
  const sheet = await aria();
  for (const text of [L('itemTicked', { name: 'Äpfel' }), L('shopAskTitle'), L('shopAskBody'), L('shopAskNo'), L('shopAskMistake'), L('shopAskTakeBack')]) {
    check(sheet.includes(flat(text)), `the sheet says „${text}“`);
  }
  await shot('01-ask-sheet');
  await button(L('shopAskNo')).click();
  await until(async () => !(await sheetUp()), 'the sheet gone after Nein');
  await page.waitForTimeout(800);
  check(!(await stripUp()), `no strip after „${L('shopAskNo')}“`);
  check(status('Äpfel') === 'bought', 'Äpfel stays ticked off');

  await tick('Brötchen');
  await until(sheetUp, 'the sheet again on the next tick (Brötchen)');
  await button(L('shopAskTakeBack')).click();
  await until(() => status('Brötchen') === 'active', 'Brötchen back on the list in the database');
  await until(async () => (await itemRow(page, 'Brötchen').count()) === 1, 'Brötchen back on the screen');
  await page.waitForTimeout(800);
  check(!(await stripUp()) && !(await sheetUp()), `no strip and no sheet after „${L('shopAskTakeBack')}“`);

  // Legal GL-2
  await tick('Aspirin');
  await page.waitForTimeout(1500);
  check(!(await sheetUp()), 'no question on ticking Aspirin at „APOTHEKE am Markt“ (GL-2)');
  check(!(await aria()).includes(L('tripPromptAt', { store: 'APOTHEKE am Markt' })), 'no log card for the pharmacy (GL-2)');

  // tm-strip
  const planned = active();
  await tick('Bananen');
  await until(sheetUp, 'the sheet after ticking Bananen');
  await button(L('shopAskYes')).click();
  await until(stripUp, 'the strip after „Ja, Einkauf starten“');
  check((await aria()).includes(L('shopRunning')), `the strip says „${L('shopRunning')}“`);
  const underAMinute = /=0\{([^}]*)\}/.exec(L('shopClockLabel'))[1];
  check((await aria()).includes(`${L('shopRunning')}, ${underAMinute}`), `the strip's label „${L('shopRunning')}, ${underAMinute}“`);
  // The stopwatch's face is drawn only (the label rounds to minutes): two pictures of it differ.
  const face = async () => {
    const end = await button(L('shopEnd')).boundingBox();
    return page.screenshot({ clip: { x: 0, y: end.y - 4, width: page.viewportSize().width / 2.5, height: end.height + 8 } });
  };
  const first = await face();
  await page.waitForTimeout(2200);
  check(!first.equals(await face()), 'the stopwatch runs (its face changes in 2 s)');
  if (compact) {
    const vw = page.viewportSize().width;
    const boxes = [];
    for (const [name, locator] of [['pause', button(L('shopPause'))], ['end', button(L('shopEnd'))]]) boxes.push([name, await locator.boundingBox()]);
    for (const [name, b] of boxes) check(b.x >= 0 && b.x + b.width <= vw + 0.5, `strip at ${vw} px: ${name} inside (${Math.round(b.x)}..${Math.round(b.x + b.width)})`);
    for (let i = 1; i < boxes.length; i++) check(boxes[i - 1][1].x + boxes[i - 1][1].width <= boxes[i][1].x + 0.5, `strip at ${vw} px: ${boxes[i - 1][0]} left of ${boxes[i][0]}`);
  }
  await shot('02-strip-running');
  await button(L('shopPause')).click();
  await until(async () => (await button(L('shopResume')).count()) === 1, `„${L('shopResume')}“ after Pause`);
  check((await aria()).includes(L('shopPaused')), `the strip says „${L('shopPaused')}“`);
  const frozen = await face();
  await page.waitForTimeout(2200);
  check(frozen.equals(await face()), 'the stopwatch stands while paused');
  await shot('03-strip-paused');
  await button(L('shopResume')).click();
  await until(async () => (await button(L('shopPause')).count()) === 1 && (await aria()).includes(L('shopRunning')), 'running again after Weiter');

  // A paid price on Bananen, more ticks without a question, Noah's Kaffee at Rewe.
  {
    const { error } = await api.from('items').update(price(0.30, new Date().toISOString())).eq('household_id', household).eq('name', 'Bananen');
    if (error) throw error;
  }
  for (const name of ['Vollmilch', 'Butter', 'Nudeln']) {
    await tick(name);
    await page.waitForTimeout(700);
    check(!(await sheetUp()), `no question on ticking ${name} while the trip runs`);
  }
  {
    const { error } = await noahApi.from('items').insert({ household_id: household, list_id: listId, name: extra, store_id: rewe, ...price(5.99, new Date().toISOString()) });
    if (error) throw error;
  }
  await until(async () => (await itemRow(page, extra).count()) === 1, `Noah's ${extra} on Mia's list`);
  await tick(extra);
  check(!(await sheetUp()), `no question on ticking ${extra}`);

  // tm-free: Beenden, the fresh page without Premium.
  await button(L('shopEnd')).click();
  await page.waitForURL(/\/trip\/[0-9a-f-]{36}$/, { timeout: 15_000 });
  const sessionId = /\/trip\/([0-9a-f-]{36})$/.exec(page.url())[1];
  await until(async () => (await aria()).includes(L('shopLockedTitle')), `„${L('shopLockedTitle')}“ on the Free page`);
  const free = await aria();
  for (const text of [L('shopSummaryTitle'), plural(L('shopTicked'), 5), L('shopLockedBody'), 'Lidl', 'Rewe', L('shopKeepShopping'), L('done')]) {
    check(free.includes(flat(text)), `the Free summary shows „${text}“`);
  }
  for (const text of [L('shopPlannedSection'), L('shopPaidTotal'), 'Kaffee']) check(!free.includes(text), `the Free summary hides „${text}“`);
  await shot('04-summary-free');
  await until(() => sql(`select count(*) from public.trip_sessions where id = '${sessionId}'`) === '1', 'the session saved');
  const asFree = await rpc(api, 'trip_session', { p_household: household, p_id: sessionId });
  log(`trip_session (Free): ${JSON.stringify({ ...asFree, lines: asFree.lines && asFree.lines.length })}`);
  check(asFree.premium === false && asFree.lines === null && asFree.bought === 5, 'trip_session for Free: premium false, no lines, 5 bought');
  check(JSON.stringify(asFree.stores) === JSON.stringify(['Lidl', 'Rewe']), `trip_session stores Lidl, Rewe (${JSON.stringify(asFree.stores)})`);
  const saved = JSON.parse(sql(`select json_build_object('lines', lines, 'source', source, 'end_reason', end_reason) from public.trip_sessions where id = '${sessionId}'`));
  log(`stored lines: ${JSON.stringify(saved.lines.map((l) => [l.name, l.bought, l.planned, l.planned_cents, l.paid_cents, l.by_other ?? null]))}`);
  check(saved.source === 'ask' && saved.end_reason === 'user', 'source ask, end reason user');

  // tm-history
  const logged = (await history()).trips.filter((t) => t.session_id === sessionId);
  log(`trip_history for the session: ${JSON.stringify(logged.map((t) => [t.store_name, t.items.map((i) => i.name)]))}`);
  check(logged.length === 2 && logged.map((t) => t.store_name).sort().join() === 'Lidl,Rewe', 'two Verlauf trips (Lidl, Rewe) carry the session id');
  check(logged.find((t) => t.store_name === 'Rewe').items.map((i) => i.name).sort().join() === ['Butter', extra, 'Nudeln'].sort().join(), 'the Rewe trip holds Butter, Kaffee, Nudeln');
  await button(L('done')).click();
  await page.waitForURL((url) => !/\/trip\//.test(url.pathname), { timeout: 10_000 });
  await page.waitForTimeout(800);
  check(!(await stripUp()), 'no strip after Fertig');

  premium(true);
  log('Mia gets promotional Premium (promotional_premium_sync_user), page reloaded');
  await page.reload();
  await openTab(page, L, 'tabHistory').catch(() => {});
  await page.getByRole('tab', { name: L('tabHistory'), exact: true }).waitFor({ timeout: 30_000 });
  await openTab(page, L, 'tabHistory');
  const tile = page.getByRole('button', { name: new RegExp(`${escape(extra)}`) });
  await until(async () => (await tile.count()) === 1, `the Rewe trip with ${extra} in Verlauf`);
  await shot('05-history');
  await tile.click();
  await page.waitForURL(new RegExp(`/history/trip/${sessionId}$`), { timeout: 10_000 });

  // tm-summary (Premium, from the server)
  await until(async () => (await aria()).includes(L('shopPlannedSection')), `„${L('shopPlannedSection')}“ on the Premium page`);
  const asPremium = await rpc(api, 'trip_session', { p_household: household, p_id: sessionId });
  check(asPremium.premium === true && Array.isArray(asPremium.lines), 'trip_session for Premium has the lines');
  const bananen = asPremium.lines.find((l) => l.name === 'Bananen');
  const kaffee = asPremium.lines.find((l) => l.name === extra);
  check(bananen.planned_cents === 150 && bananen.paid_cents === 180, `Bananen: planned 150 (6 × 0,25 € yesterday), paid 180 (6 × 0,30 € today): ${bananen.planned_cents}/${bananen.paid_cents}`);
  check(kaffee.planned === false && kaffee.by_other === true && kaffee.added_by === noah.id && kaffee.paid_cents === 599, `Kaffee is Noah's extra at 5,99 €`);
  const summary = await scan();
  log(`summary text: ${summary.length} chars`);
  const lede = `${L('shopLede', { bought: 4, planned })} · ${plural(L('shopLedeExtra'), 1)}`;
  const compared = (planned, more, count) => `${L('shopCompared', { amount: money(planned), difference: L('shopMore', { amount: money(more) }) })} · ${plural(L('shopComparedCount'), count)}`;
  for (const text of [
    lede, 'Lidl', 'Rewe', L('shopPlannedSection'), L('shopExtraSection'), L('shopNotBought'), L('shopMarkPlannedHint'),
    `${extra} ${L('shopBy', { name: 'Noah' })}`,
    `6 Bananen ${money(180)} · ${L('shopPlannedPrice', { amount: money(150) })} · ${L('shopMore', { amount: money(30) })}`,
    `2 Vollmilch ${money(218)} · ${L('shopPlannedPrice', { amount: money(218) })} · ${L('shopAsPlanned')}`,
    `${L('shopPaid')} ${money(398)} ${compared(368, 30, 2)}`,
    `${L('shopPaid')} ${money(599)} ${plural(L('shopWithoutPrice'), 2)} ${plural(L('shopWithoutPlan'), 1)}`,
    `${L('shopPaidTotal')} ${money(997)} ${compared(368, 30, 2)} ${plural(L('shopWithoutPrice'), 2)} ${plural(L('shopWithoutPlan'), 1)}`,
    L('shopTotalsNote'),
  ]) check(summary.includes(flat(text)), `the Premium summary shows „${text}“`);
  // Web semantics: each store a heading of its own, „War geplant“ a toggle of its own.
  const middle = () => page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
  for (const store of ['Lidl', 'Rewe']) {
    const heading = page.getByRole('heading', { name: store, exact: true });
    await middle();
    await page.mouse.wheel(0, -20_000);
    for (let i = 0; i < 20 && !(await heading.count()); i++) {
      await page.mouse.wheel(0, page.viewportSize().height / 2);
      await page.waitForTimeout(300);
    }
    check((await heading.count()) === 1, `„${store}“ is a heading of its own on the web`);
  }
  await middle();
  await page.mouse.wheel(0, -20_000);
  await shot('06-summary-premium');
  await middle();
  await page.mouse.wheel(0, 20_000);
  await page.waitForTimeout(500);
  const mark = page.getByRole('switch', { name: L('shopMarkPlanned'), exact: true });
  await until(async () => (await mark.count()) === 1, `„${L('shopMarkPlanned')}“ on ${extra}: a toggle of its own`);
  log(`summary bottom: ${await aria()}`);
  check(!(await mark.isChecked()), `„${L('shopMarkPlanned')}“ starts off`);
  await shot('07-summary-premium-totals');
  await mark.click();
  const markedOnServer = async () => (await rpc(api, 'trip_session', { p_household: household, p_id: sessionId })).lines.find((l) => l.name === extra).marked_planned;
  await until(async () => (await markedOnServer()) === true, `${extra} marked_planned in trip_session after „${L('shopMarkPlanned')}“`);
  await until(() => mark.isChecked(), `„${L('shopMarkPlanned')}“ checked on the page`);
  log(`after „${L('shopMarkPlanned')}“: ${await aria()}`);

  // „Einkauf löschen“ from the Verlauf summary
  await button(L('tripDelete')).click();
  await button(L('delete')).click();
  await page.waitForURL((url) => !/\/trip\//.test(url.pathname), { timeout: 10_000 });
  await until(async () => !(await history()).trips.some((t) => t.session_id === sessionId), 'trip_history without the session\'s trips');
  {
    const { error } = await api.rpc('trip_session', { p_household: household, p_id: sessionId });
    check(error?.message === 'trip_not_found', `trip_session after the delete: trip_not_found (${error?.message})`);
  }
  check(sql(`select count(*) from public.trip_sessions where id = '${sessionId}'`) === '0', 'the session row is gone');

  // tm-manual-start
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${escape(L('shopStartByHand'))}`) }).click();
  await until(stripUp, `the strip after Mehr › „${L('shopStartByHand')}“`);
  check(!(await sheetUp()), 'no question on a manual start');
  await button(L('shopEnd')).click();
  await page.waitForURL(/\/trip\/[0-9a-f-]{36}$/, { timeout: 15_000 });
  const manualId = /\/trip\/([0-9a-f-]{36})$/.exec(page.url())[1];
  await until(async () => (await aria()).includes(flat(L('shopLede', { bought: 0, planned: planned - 4 }))), `„${L('shopLede', { bought: 0, planned: planned - 4 })}“ on the manual trip`);
  await until(() => sql(`select source from public.trip_sessions where id = '${manualId}'`) === 'manual', 'the manual session saved with source manual');
  log('manual start: saved with source manual');
  await page.mouse.wheel(0, 20_000);
  await page.waitForTimeout(500);
  await button(L('done')).click();
  if (app.errors.length) throw new Error(`page errors: ${app.errors.join('; ')}`);

  // tm-long-running, on Playwright's clock
  premium(false);
  const later2 = await browserFor('clock', { clock: true });
  const h = handles(later2);
  await signIn(later2.page, later2.L, mia);
  await h.tick('Erbsen');
  await h.until(h.sheetUp, 'the sheet after ticking Erbsen');
  await h.button(L('shopAskYes')).click();
  await h.until(h.stripUp, 'the strip on the clock browser');
  const tickAt = sql(`select to_json(bought_at) from public.items where household_id = '${household}' and name = 'Erbsen'`).replace(/"/g, '');
  const tickHm = hm(tickAt);
  await later2.page.clock.fastForward('46:00');
  await h.until(async () => (await h.aria()).includes(flat(L('shopAutoPaused', { time: tickHm }))), `„${L('shopAutoPaused', { time: tickHm })}“ after 46 min`);
  check((await h.button(L('shopEndAt', { time: tickHm })).count()) === 1, `the button „${L('shopEndAt', { time: tickHm })}“`);
  await h.shot('08-strip-auto-paused');
  await later2.page.clock.fastForward('04:00:00');
  await h.until(async () => (await h.aria()).includes(L('shopAutoEndedTitle')), `„${L('shopAutoEndedTitle')}“ after 4 h more`);
  check((await h.aria()).includes(flat(L('shopAutoEndedBody', { time: tickHm }))), `the card says „${L('shopAutoEndedBody', { time: tickHm })}“`);
  check(!(await h.stripUp()), 'no strip after the automatic end');
  await h.shot('09-auto-ended-card');
  await h.until(() => sql(`select count(*) from public.trip_sessions where household_id = '${household}' and end_reason = 'auto'`) === '1', 'the auto-ended session saved');
  const auto = JSON.parse(sql(`select json_build_object('ended_at', ended_at, 'started_at', started_at) from public.trip_sessions where household_id = '${household}' and end_reason = 'auto'`));
  const gap = Math.abs(new Date(auto.ended_at) - new Date(tickAt));
  log(`auto end: ended_at ${auto.ended_at}, Erbsen bought_at ${tickAt}`);
  check(gap <= 1000, `ended_at is the last tick's bought_at (${gap} ms apart)`);
  await h.button(L('shopKeepGoing')).click();
  await h.until(h.stripUp, `the strip again after „${L('shopKeepGoing')}“`);
  check(!(await h.aria()).includes(L('shopAutoEndedTitle')), `no card after „${L('shopKeepGoing')}“`);
  await later2.page.clock.fastForward('04:01:00');
  await h.until(async () => (await h.aria()).includes(L('shopAutoEndedTitle')), `„${L('shopAutoEndedTitle')}“ again 4 h after „${L('shopKeepGoing')}“`);
  check(sql(`select count(*) from public.trip_sessions where household_id = '${household}' and end_reason = 'auto'`) === '1', 'still one auto-ended session');
  await h.button(L('shopShowSummary')).click();
  await later2.page.waitForURL(/\/trip\/[0-9a-f-]{36}$/, { timeout: 15_000 });
  await h.until(async () => (await h.aria()).includes(flat(L('shopAutoEndHint', { time: tickHm }))), `„${L('shopAutoEndHint', { time: tickHm })}“ on its summary`);
  if (later2.errors.length) throw new Error(`page errors (clock): ${later2.errors.join('; ')}`);
} catch (error) {
  failed = error;
  const last = open.at(-1);
  if (last) await capture(last.page, dir, '99-failure').catch(() => {});
} finally {
  premium(false);
  for (const { context, browser } of open) {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS trip-mode (${lang}${dark ? ', dark' : ''}${compact ? ', 358 px' : ''}; shots: ${shots.join(', ')}; evidence: ${dir})`);
