// Feature learned-order (flag `learned-order`, off for users; job 352), on demo-familie, launched
// with VH_DEFINES="FLAGS_ON=learned-order,trip-mode,grocery-log". Puts the 15 seeded items and
// Joghurt, Käse and Tomaten (18) at Lidl in a learned household, then as Mia: the list in walk order
// without category dividers, the edit sheet's „Neben …“ chip and its options (17 others: the filter
// field). Then two walks of five ticks, their events spread one tick every 30 s and `detect_trips`
// run as the database owner after each (spread forward from now: ticks before the switch to the
// learned order or before the app first asked about detection never count). The first walk's
// first tick asks, with „Nach „Nein“ fragen wir eine Stunde lang nicht mehr, und dieser Einkauf wird
// nicht erkannt.“; „Nein“ sends `decline_shop` and snoozes the rest: no trip, the order unchanged
// (TD-Q5). The second walk, ticked while the snooze still holds (no question) and spread to start
// 45 minutes after the first one's last tick (a new run: more than 30 minutes apart), is detected:
// one trip, the order moved towards the walk. Then the first-trip card, Verlauf's „Aus deinen
// Häkchen erkannt“, Einstellungen' switch; as Noah: Mia's detected trip without clock times and the
// „Kein Einkauf“ dialog (cancelled); and Mia's list in English dark. Rerunnable: it first deletes
// the household's detected trips, declines, app tick events and Mia's and Noah's detection
// settings, and puts every item back.
//
//   node journeys/learned-order.mjs <evidence dir>
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { answerShopAsk, apiAs, capture, instance, itemRow, logger, member, openApp, openTab, reveal, signIn } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: learned-order.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const noah = member(inst, 'noah');
const household = mia.householdId;
const api = await apiAs(inst, mia);
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const walked = ['Mineralwasser', 'Brötchen', 'Bananen', 'Duschgel', 'Vollmilch'];

async function setUp() {
  sql(`delete from public.trips where household_id = '${household}' and session_id in (
         select id from public.trip_sessions where household_id = '${household}' and source = 'detected');
       delete from public.trip_sessions where household_id = '${household}' and source = 'detected';
       delete from public.shop_declines where household_id = '${household}';
       delete from public.item_events where household_id = '${household}' and source = 'app';
       delete from public.trip_detection_settings where user_id in ('${mia.id}', '${noah.id}');
       update public.trip_detection_state set detected_through = null where household_id = '${household}';
       update public.items set status = 'active' where household_id = '${household}' and status = 'bought';`);
  const { data: stores } = await api.from('stores').select('id, name').eq('household_id', household);
  let lidl = stores.find((s) => s.name === 'Lidl')?.id;
  if (!lidl) {
    const { data, error } = await api.rpc('add_store', { p_household: household, p_name: 'Lidl' });
    if (error) throw error;
    lidl = data;
  }
  const { data: mode, error: modeError } = await api.rpc('set_order_mode', { p_household: household, p_mode: 'learned' });
  if (modeError) throw modeError;
  check(mode === 'learned', 'the household orders by what it learns');
  // The deleted trips' walks still hold the items' places until the store is replayed.
  sql(`select public.replay_store_order('${household}', '${lidl}')`);
  const { data: open } = await api.from('items').select('name').eq('household_id', household).eq('status', 'active');
  const extra = ['Joghurt', 'Käse', 'Tomaten'].filter((n) => !open.some((i) => i.name === n));
  if (extra.length) {
    const { error } = await api.from('items').insert(extra.map((name) => ({ household_id: household, name, store_id: lidl })));
    if (error) throw error;
  }
  const { error } = await api.from('items').update({ store_id: lidl }).eq('household_id', household).eq('status', 'active');
  if (error) throw error;
  return lidl;
}

async function order(lidl) {
  const { data, error } = await api.from('items').select('name').eq('store_id', lidl).eq('status', 'active')
    .order('sort_key').order('created_at').order('id');
  if (error) throw error;
  return data.map((r) => r.name);
}

// Ticks [walked] in the app; the first one's question is answered „Nein“ when [declining].
// Spreads the walk's events (those after event [afterId]) to one every 30 s from [offset] past now
// and puts the items back. Returns the walk's last event id.
async function walk(page, L, declining, afterId, offset) {
  for (const [i, name] of walked.entries()) {
    await reveal(page, itemRow(page, name));
    const saved = page.waitForResponse((r) => new URL(r.url()).pathname === '/rest/v1/rpc/set_item_status' && r.ok());
    await itemRow(page, name).click();
    await saved;
    if (declining && i === 0) {
      await page.getByText(L('shopAskQuiet'), { exact: true }).waitFor({ timeout: 5_000 });
      await capture(page, dir, '352-09-trip-question-quiet');
      const declined = page.waitForResponse((r) => new URL(r.url()).pathname === '/rest/v1/rpc/decline_shop' && r.ok());
      check(await answerShopAsk(page, L, 'shopAskNo'), 'the first tick asks, „Nein“ answers');
      await declined;
      log('„Nein“ sent decline_shop');
    } else {
      check(!(await answerShopAsk(page, L, 'shopAskNo', 1_500)), `within the snooze the tick of ${name} asks nothing`);
    }
  }
  const ticks = sql(`select count(*) from public.item_events where household_id = '${household}' and source = 'app'
                       and action = 'bought' and client_at is not null and id > ${afterId}`);
  check(ticks === String(walked.length), `${walked.length} app ticks with their tap times`);
  sql(`with t as (
         select e.id, row_number() over (order by e.id) - 1 as n from public.item_events e
         where e.household_id = '${household}' and e.source = 'app' and e.action = 'bought' and e.id > ${afterId})
       update public.item_events e
       set client_at = now() + interval '${offset}' + t.n * interval '30 seconds',
           created_at = now() + interval '${offset}' + t.n * interval '30 seconds' + interval '400 milliseconds'
       from t where t.id = e.id;
       update public.items set status = 'active' where household_id = '${household}' and status = 'bought';`);
  return Number(sql(`select coalesce(max(id), 0) from public.item_events where household_id = '${household}'`));
}

let failed = null;
const browsers = [];
try {
  const lidl = await setUp();
  const before = await order(lidl);
  check(before.length === 18, `18 items at Lidl: ${before.join(', ')}`);

  const app = await openApp(inst, { videoDir: dir });
  browsers.push(app.browser);
  const { page, L } = app;
  await signIn(page, L, mia);
  await itemRow(page, before[0]).waitFor({ timeout: 15_000 });
  check(await page.getByRole('heading', { name: 'Obst & Gemüse', exact: true }).count() === 0, 'no category dividers');
  await page.mouse.move(0, 843);
  await capture(page, dir, '352-01-learned-list');

  const item = before[5];
  await reveal(page, itemRow(page, item));
  await itemRow(page, item).click({ button: 'right' });
  const sheet = page.getByRole('group', { name: L('editSheet'), exact: true });
  await sheet.waitFor({ timeout: 10_000 });
  const chip = sheet.getByRole('button', { name: L('chipPlace', { place: L('placeNextTo', { name: before[4] }) }) });
  await chip.waitFor({ timeout: 5_000 });
  log(`the chip of ${item} says „Neben ${before[4]}“`);
  await page.mouse.move(0, 0);
  await capture(page, dir, '352-02-edit-sheet-place-chip');
  await chip.click();
  await sheet.getByRole('button', { name: L('placeFirst'), exact: true }).waitFor({ timeout: 5_000 });
  check(await sheet.getByRole('textbox', { name: L('placeFilter') }).count() === 1, 'over 15 others: the filter field');
  await page.mouse.move(0, 0);
  await capture(page, dir, '352-03-place-options');
  await sheet.getByRole('button', { name: L('cancel'), exact: true }).click();
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });

  const agreeing = (list) => walked.flatMap((a, i) => walked.slice(i + 1).map((b) => list.indexOf(a) < list.indexOf(b))).filter(Boolean).length;
  const detected = () => sql(`select count(*) from public.trip_sessions where household_id = '${household}' and source = 'detected'`);

  const firstId = Number(sql(`select coalesce(max(id), 0) from public.item_events where household_id = '${household}'`));
  const declinedId = await walk(page, L, true, firstId, '0 minutes');
  check(sql(`select count(*) from public.shop_declines where household_id = '${household}' and user_id = '${mia.id}'`) === '1',
    'the „Nein“ is on the server');
  check(sql(`select public.detect_trips('${household}')`) === '0', 'TD-Q5: the walk answered „Nein“ gives no trip');
  check(detected() === '0', 'TD-Q5: no detected trip session');
  const declinedOrder = await order(lidl);
  check(JSON.stringify(declinedOrder) === JSON.stringify(before), 'TD-Q5: the walk answered „Nein“ changes no order');

  await page.reload();
  await itemRow(page, walked[0]).waitFor({ timeout: 15_000 });
  await walk(page, L, false, declinedId, '45 minutes');
  check(sql(`select public.detect_trips('${household}')`) === '1', 'the walk 45 minutes later, inside the snooze, is detected');
  check(detected() === '1', 'one detected trip session');
  const after = await order(lidl);
  log(`order after the walk: ${after.join(', ')}`);
  check(agreeing(after) > agreeing(before), `the order moved towards the walk: ${agreeing(before)} -> ${agreeing(after)} of 10 pairs`);

  await page.reload();
  const cardTitle = page.getByRole('heading', { name: L('detectedCardTitle', { store: 'Lidl' }), exact: true });
  await cardTitle.waitFor({ timeout: 20_000 });
  await page.mouse.move(0, 843);
  await capture(page, dir, '352-04-first-trip-card');
  await page.getByRole('button', { name: L('detectedCardGotIt'), exact: true }).click();
  await cardTitle.waitFor({ state: 'detached', timeout: 10_000 });

  await openTab(page, L, 'tabHistory');
  await page.getByRole('button', { name: new RegExp(L('detectedOwn')) }).waitFor({ timeout: 15_000 });
  await page.mouse.move(0, 843);
  await capture(page, dir, '352-05-verlauf-detected');

  const second = await openApp(inst);
  browsers.push(second.browser);
  await signIn(second.page, second.L, noah);
  await openTab(second.page, second.L, 'tabHistory');
  const theirs = second.page.getByRole('button', { name: new RegExp(second.L('detectedOther', { name: mia.name })) });
  await theirs.waitFor({ timeout: 15_000 });
  await theirs.click();
  await second.page.waitForURL(/\/history\/trip\//, { timeout: 10_000 });
  await second.page.getByRole('button', { name: second.L('tripNotShopping'), exact: true }).waitFor({ timeout: 15_000 });
  const text = await second.page.locator('body').ariaSnapshot();
  check(!/\d{1,2}:\d{2}/.test(text), 'Noah sees Mia\'s detected trip without clock times');
  await capture(second.page, dir, '352-06-other-members-trip');
  await second.page.getByRole('button', { name: second.L('tripNotShopping'), exact: true }).click();
  await second.page.getByText(second.L('tripNotShoppingBody'), { exact: true }).waitFor({ timeout: 5_000 });
  await capture(second.page, dir, '352-07-kein-einkauf-dialog');
  await second.page.getByRole('button', { name: second.L('cancel'), exact: true }).click();

  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${L('settingsTitle')}`) }).click();
  const toggle = page.getByRole('switch', { name: new RegExp(`^${L('detectTrips')}`) });
  await toggle.waitFor({ timeout: 10_000 });
  check(await toggle.isChecked(), 'the switch is on');
  await page.mouse.move(0, 843);
  await capture(page, dir, '352-08-settings-switch');

  const english = await openApp(inst, { lang: 'en', dark: true });
  browsers.push(english.browser);
  await signIn(english.page, english.L, mia);
  await itemRow(english.page, after[0]).waitFor({ timeout: 15_000 });
  await english.page.mouse.move(0, 843);
  await capture(english.page, dir, '352-10-list-en-dark');
  check(app.errors.length === 0 && second.errors.length === 0 && english.errors.length === 0, 'no page errors');
} catch (e) {
  failed = e;
} finally {
  for (const browser of browsers) await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS on ${inst.commit}`);
