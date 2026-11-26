// Feature store-apps, the „… ist erledigt“ card (job 399, SC1; flag open-store-app, full since
// 2026-11-25, so a plain launch). On demo-familie: Noah adds Haferkekse and Leinsamen to a store „Lidl am Markt“
// linked to Lidl, and Senf to an unlinked „Hofladen“. Mia ticks Haferkekse and Leinsamen in the list: the
// card „Lidl am Markt ist erledigt“ shows with „App öffnen“ below the title, which opens Lidl Plus'
// Play page; the card stays there, since a headless page is never hidden by the new tab. Noah, who only added, sees no card. Mia ticks Senf: the unlinked
// store gets none. At 310 % text the button is still below the title and inside the card. X hides
// it, also after a reload; Noah adds Milch there, Mia ticks it and the card is back, then the page
// goes hidden and visible again (visibilitychange, as a real tab switch does) and the card is gone.
// Offline, Mia
// ticks Essig, closes the card and goes online: it stays closed. Deletes the stores and items it made.
//
//   node journeys/store-done.mjs <evidence dir>
import process from 'node:process';
import { answerShopAsk, apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: store-done.mjs <evidence dir>');

const playLidl = 'https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus';
const stores = ['Lidl am Markt', 'Hofladen'];
const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const noah = member(inst, 'noah');
const asMia = await apiAs(inst, mia);
const asNoah = await apiAs(inst, noah);

const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

async function cleanup() {
  const { data } = await asMia.from('stores').select('id, name').eq('household_id', mia.householdId).in('name', stores);
  for (const { id } of data ?? []) {
    await asMia.from('items').delete().eq('household_id', mia.householdId).eq('store_id', id);
    await asMia.rpc('delete_store', { p_store: id });
  }
  log(`cleanup: deleted ${(data ?? []).map((s) => s.name).join(', ') || 'nothing'}`);
}

async function add(storeId, name) {
  const { error } = await asNoah.from('items').insert({ household_id: noah.householdId, name, store_id: storeId });
  if (error) throw error;
}

async function store(name, chain) {
  const { data: id, error } = await asMia.rpc('add_store', { p_household: mia.householdId, p_name: name });
  if (error) throw error;
  if (chain) {
    const { error: linkError } = await asMia.rpc('answer_store_retailer', { p_store: id, p_chain: chain, p_country: 'DE', p_app: null });
    if (linkError) throw linkError;
  }
  return id;
}

async function tick(page, L, name) {
  const row = itemRow(page, name).first();
  await reveal(page, row);
  await row.click();
  await answerShopAsk(page, L, 'shopAskNo');
  await row.waitFor({ state: 'detached', timeout: 10_000 }).catch(() => {});
}

let failed = null;
let shot = null;
const browsers = [];
try {
  await cleanup();
  const lidl = await store('Lidl am Markt', 'lidl');
  const farm = await store('Hofladen', null);
  await add(lidl, 'Haferkekse');
  await add(lidl, 'Leinsamen');
  await add(farm, 'Senf');
  log('Noah added Haferkekse and Leinsamen at Lidl am Markt (linked to Lidl), Senf at Hofladen (unlinked)');

  const m = await openApp(inst, { videoDir: dir });
  browsers.push(m.browser);
  const { context, page, L, errors } = m;
  shot = page;
  await context.route(/^https:\/\/(play\.google\.com|apps\.apple\.com)\//, (route) =>
    route.fulfill({ status: 200, contentType: 'text/html', body: '<title>store page</title>' }));
  await signIn(page, L, mia);
  const title = page.getByRole('group', { name: L('storeDoneTitle', { store: 'Lidl am Markt' }), exact: true });
  const open = page.getByRole('button', { name: L('storeAppOpen', { app: 'Lidl Plus' }) });
  const close = page.getByRole('button', { name: L('close'), exact: true });
  await itemRow(page, 'Haferkekse').first().waitFor({ timeout: 15_000 });
  await reveal(page, itemRow(page, 'Haferkekse').first());
  await capture(page, dir, '01-before');
  check(await open.count() === 1, 'Lidl am Markt has its app key in the header');
  check(await title.count() === 0, 'no card while Lidl am Markt has open items');

  await tick(page, L, 'Haferkekse');
  check(await title.count() === 0, 'no card after the first of two ticks');
  await tick(page, L, 'Leinsamen');
  await title.waitFor({ timeout: 10_000 });
  await page.evaluate(() => globalThis.scrollTo(0, 0));
  await capture(page, dir, '02-card');
  const t = await title.boundingBox();
  const b = await open.first().boundingBox();
  log(`title ${JSON.stringify(t)} button ${JSON.stringify(b)}`);
  check(b.y >= t.y + 20 && b.y + b.height <= t.y + t.height && b.x - t.x < 40, 'the button sits below the title, left-aligned, inside the card');
  const { data: rows } = await asMia.from('items').select('name, status, bought_by').eq('store_id', lidl);
  log(`database: ${JSON.stringify(rows)}`);
  check(rows.length === 2 && rows.every((r) => r.status === 'bought' && r.bought_by === mia.id), 'both Lidl items bought by Mia on the server');

  const popup = context.waitForEvent('page', { timeout: 10_000 });
  await open.first().click();
  const tab = await popup;
  await tab.waitForLoadState('domcontentloaded');
  const url = tab.url();
  await tab.close();
  check(url === playLidl, `„App öffnen“ opens ${url}`);
  await page.waitForTimeout(1_000);
  check(await title.count() === 1, 'the card stays after „App öffnen“ (headless: the opener tab is not hidden)');

  await page.evaluate(() => { document.documentElement.style.fontSize = '310%'; });
  await page.waitForTimeout(1_500);
  await capture(page, dir, '03-card-310');
  const t3 = await title.boundingBox();
  const b3 = await open.first().boundingBox();
  log(`310 %: title ${JSON.stringify(t3)} button ${JSON.stringify(b3)}`);
  check(b3.y >= t3.y + 60 && b3.y + b3.height <= t3.y + t3.height && b3.x + b3.width <= 390, 'at 310 % the button is below the title, inside the card and on screen');
  await page.evaluate(() => { document.documentElement.style.fontSize = ''; });
  await page.waitForTimeout(1_000);

  const n = await openApp(inst, {});
  browsers.push(n.browser);
  await signIn(n.page, n.L, noah);
  await itemRow(n.page, 'Senf').first().waitFor({ timeout: 15_000 });
  await n.page.waitForTimeout(2_000);
  await capture(n.page, dir, '04-noah-no-card');
  check(await n.page.getByRole('group', { name: n.L('storeDoneTitle', { store: 'Lidl am Markt' }), exact: true }).count() === 0,
    'Noah, who only added the items, sees no card');

  await tick(page, L, 'Senf');
  await page.waitForTimeout(1_500);
  check(await page.getByRole('group', { name: L('storeDoneTitle', { store: 'Hofladen' }), exact: true }).count() === 0,
    'the unlinked Hofladen gets no card');
  check(await title.count() === 1, 'the Lidl card is still the one shown');

  await close.first().click();
  await title.waitFor({ state: 'detached', timeout: 5_000 });
  await capture(page, dir, '05-dismissed');
  await page.reload();
  await signIn(page, L, mia).catch(() => {});
  await page.getByRole('textbox', { name: L('addFieldHint') }).waitFor({ timeout: 15_000 }).catch(() => {});
  await page.waitForTimeout(2_000);
  check(await title.count() === 0, 'the dismissal holds after a reload');

  await add(lidl, 'Milch');
  await itemRow(page, 'Milch').first().waitFor({ timeout: 15_000 });
  await tick(page, L, 'Milch');
  await title.waitFor({ timeout: 10_000 });
  await capture(page, dir, '06-back-after-new-item');
  log('ok: a new item at Lidl am Markt, ticked off, brings the card back');

  const visibility = (v) =>
    page.evaluate((v) => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => v });
      document.dispatchEvent(new Event('visibilitychange'));
    }, v);
  await visibility('hidden');
  await page.waitForTimeout(1_000);
  await visibility('visible');
  await title.waitFor({ state: 'detached', timeout: 5_000 });
  await capture(page, dir, '06b-gone-after-hidden');
  log('ok: the card is gone after the page was hidden and shown again');

  await add(lidl, 'Essig');
  await itemRow(page, 'Essig').first().waitFor({ timeout: 15_000 });
  await context.setOffline(true);
  await tick(page, L, 'Essig');
  await title.waitFor({ timeout: 10_000 });
  await close.first().click();
  await title.waitFor({ state: 'detached', timeout: 5_000 });
  log('offline: ticked Essig, the card showed and was closed');
  await context.setOffline(false);
  let essig = null;
  for (let i = 0; i < 30 && essig?.status !== 'bought'; i++) {
    await page.waitForTimeout(1_000);
    ({ data: essig } = await asMia.from('items').select('status, bought_at').eq('store_id', lidl).eq('name', 'Essig').single());
  }
  log(`database after going online: ${JSON.stringify(essig)}`);
  check(essig?.status === 'bought', 'the offline tick reached the server');
  await page.waitForTimeout(3_000);
  await capture(page, dir, '07-closed-offline-stays-closed');
  check(await title.count() === 0, "a card closed offline stays closed after the server stamps its own time");
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  if (shot) await capture(shot, dir, '99-failure').catch(() => {});
} finally {
  await cleanup().catch((e) => log(`cleanup failed: ${e.message}`));
  for (const b of browsers) await b.close();
}
log(failed ? `FAIL store-done: ${failed.stack}` : 'PASS store-done');
process.exit(failed ? 1 : 0);
