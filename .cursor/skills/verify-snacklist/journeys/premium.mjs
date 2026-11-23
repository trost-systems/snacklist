// Feature premium, per-user purchase (job 185): RevenueCat's App User ID is the buyer's user id, so
// Premium follows Mia into every household she is in and nobody else sees it. Mia gets a second
// household, RevenueCat's webhook reports her yearly plan (INITIAL_PURCHASE), then EXPIRATION, then
// RENEWAL; the Mehr row and the page's status follow live. Noah, in Familie Brandt with her, never
// sees it. After the lapse the list still adds and ticks.
//
//   node journeys/premium.mjs <evidence dir>
import process from 'node:process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import {
  addField, addSheet, answerShopAsk, apiAs, capture, householdButton, instance, itemRow, logger, member, openApp, openTab, repo, reveal, signIn, switchHousehold, typeInto,
} from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: premium.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const noah = member(inst, 'noah');
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const row = (query) => JSON.parse(sql(`select coalesce(json_agg(t), '[]') from (${query}) t`));

const webhookAuth = (() => {
  const line = readFileSync(join(repo, 'supabase/functions/.env'), 'utf8').split('\n')
    .find((l) => l.startsWith('REVENUECAT_WEBHOOK_AUTH='));
  if (!line) throw new Error('supabase/functions/.env has no REVENUECAT_WEBHOOK_AUTH: run scripts/iap-local-env.sh');
  return line.slice('REVENUECAT_WEBHOOK_AUTH='.length).replace(/^"|"$/g, '');
})();
const yearly = 'com.snacklist.app.yearly';
const day = 86_400_000;
const tx = `18500${Date.now()}`;

/** RevenueCat's webhook as e2e/tests/iap.ts rcEvent posts it: the yearly plan, App User ID = Mia's user id. */
async function rcEvent(type, expiresInDays) {
  const now = Date.now();
  const res = await fetch(`${inst.apiUrl}/functions/v1/purchases/revenuecat/webhook?forceFunctionRegion=eu-central-1`, {
    method: 'POST',
    headers: { authorization: webhookAuth, 'content-type': 'application/json' },
    body: JSON.stringify({
      api_version: '1.0',
      event: {
        id: crypto.randomUUID(), type, app_user_id: mia.id, original_app_user_id: mia.id, aliases: [mia.id],
        product_id: yearly, entitlement_ids: ['premium'], transaction_id: tx, original_transaction_id: tx,
        environment: 'SANDBOX', store: 'APP_STORE', is_family_share: false, period_type: 'NORMAL',
        purchased_at_ms: now - 1000, expiration_at_ms: now + expiresInDays * day, event_timestamp_ms: now,
        price_in_purchased_currency: 9.99, currency: 'EUR', country_code: 'DE',
      },
    }),
  });
  const body = await res.json().catch(() => null);
  log(`webhook ${type} (expires in ${expiresInDays} d): ${res.status} ${JSON.stringify(body)}`);
  if (res.status !== 200) throw new Error(`webhook ${type} answered ${res.status}`);
  return body?.status;
}

const dbState = () => ({
  purchase: row(`select bound_user, bound_household, plan, expires_at, revoked_at from public.purchases where transaction_id = '${tx}'`),
  userEntitlements: row(`select user_id, source, premium_source, expires_at from public.user_entitlements
    where purchase_id in (select id from public.purchases where transaction_id = '${tx}')`),
  householdEntitlements: row(`select household_id from public.entitlements
    where household_id in (select household_id from public.household_members where user_id = '${mia.id}')`),
});

const secondName = 'Mias WG';
sql(`delete from public.households where created_by = '${mia.id}' and name = '${secondName}'`);
const miaApi = await apiAs(inst, mia);
const { data: second, error: createError } = await miaApi.rpc('create_household', {
  p_request_id: crypto.randomUUID(), p_name: secondName,
});
if (createError) throw createError;
const firstName = sql(`select name from public.households where id = '${mia.householdId}'`);
log(`setup: Mia is in ${sql(`select string_agg(h.name, ', ' order by h.name) from public.household_members m join public.households h on h.id = m.household_id where m.user_id = '${mia.id}'`)}`);

const premiumRow = (page, L) => page.getByRole('button', { name: new RegExp(`^${L('premiumTitle')}`) });
const renews = (page, L) => page.getByText(new RegExp(`^${L('premiumStatusRenews').split(' (')[0]} \\(`));
const anyStatus = (page) => page.getByText(/^Snacklist Premium (Lifetime|aktiv|über)/);
// Material's own back button: its name comes from the framework's localizations, not the ARB.
const back = (page) => page.getByRole('button', { name: /^(Zurück|Back)$/ }).click();
const chip = householdButton;

/** Waits until [locator] has [n] matches; returns the ms it took. */
async function until(locator, n, timeout = 15_000) {
  const start = Date.now();
  while ((await locator.count()) !== n) {
    if (Date.now() - start > timeout) throw new Error(`${locator} still has ${await locator.count()} matches, not ${n}, after ${timeout} ms`);
    await locator.page().waitForTimeout(100);
  }
  return Date.now() - start;
}

async function showHousehold(page, L, from, to) {
  await openTab(page, L, 'tabList');
  await switchHousehold(page, L, from, to);
}

const miaApp = await openApp(inst, { videoDir: join(dir, 'mia') });
const { page, L } = miaApp;
let noahApp = null;
let failed = null;
try {
  await signIn(page, L, mia);
  const shown = (await chip(page, firstName).count()) ? firstName : secondName;
  const other = shown === firstName ? secondName : firstName;
  log(`signed in as mia; the list shows „${shown}“`);

  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: L('account'), exact: true }).waitFor({ timeout: 10_000 });
  // Entitlements arrive a moment after More draws; a count right away would pass vacuously.
  await page.waitForTimeout(2000);
  const before = await premiumRow(page, L).count();
  log(`before: Mehr shows ${before} „${L('premiumTitle')}“ rows`);
  await capture(page, dir, '01-mia-more-before');
  if (before !== 0) throw new Error('Mia already has a Premium row before buying');

  const granted = await rcEvent('INITIAL_PURCHASE', 365);
  if (granted !== 'granted') throw new Error(`INITIAL_PURCHASE answered ${granted}, not granted`);
  const bought = dbState();
  log(`database after INITIAL_PURCHASE: ${JSON.stringify(bought)}`);
  if (bought.purchase[0]?.bound_user !== mia.id) throw new Error('the purchase is not bound to Mia');
  if (bought.purchase[0]?.bound_household !== null) throw new Error('the purchase is bound to a household');
  if (bought.userEntitlements.length !== 1 || bought.userEntitlements[0].user_id !== mia.id) throw new Error('no user_entitlements row for Mia');
  if (bought.householdEntitlements.length) throw new Error('a household entitlement appeared');

  const appeared = await until(premiumRow(page, L), 1);
  log(`the row appeared live after ${appeared} ms (no reload)`);
  await capture(page, dir, '02-mia-more-row-live');
  await premiumRow(page, L).click();
  await renews(page, L).waitFor({ timeout: 10_000 });
  log(`page in „${shown}“: "${await renews(page, L).textContent()}"`);
  await capture(page, dir, '03-mia-page-yearly');
  await back(page);

  await showHousehold(page, L, shown, other);
  log(`switched to „${other}“`);
  await capture(page, dir, '04-mia-switched');
  await openTab(page, L, 'tabMore');
  await until(premiumRow(page, L), 1);
  await capture(page, dir, '05-mia-more-other-household');
  await premiumRow(page, L).click();
  await renews(page, L).waitFor({ timeout: 10_000 });
  log(`page in „${other}“: "${await renews(page, L).textContent()}"`);
  await capture(page, dir, '06-mia-page-other-household');
  await back(page);
  await premiumRow(page, L).click();

  noahApp = await openApp(inst, { videoDir: join(dir, 'noah') });
  await signIn(noahApp.page, noahApp.L, noah);
  await openTab(noahApp.page, noahApp.L, 'tabMore');
  await noahApp.page.getByRole('button', { name: noahApp.L('account'), exact: true }).waitFor({ timeout: 10_000 });
  await noahApp.page.waitForTimeout(3000);
  const noahRows = await premiumRow(noahApp.page, noahApp.L).count();
  await capture(noahApp.page, dir, '07-noah-more');
  await noahApp.page.goto('/more/lifetime');
  await noahApp.page.getByText(noahApp.L('premiumHeroBody')).waitFor({ timeout: 15_000 });
  await noahApp.page.waitForTimeout(2000);
  const noahStatus = await anyStatus(noahApp.page).count();
  await capture(noahApp.page, dir, '08-noah-page');
  const { data: noahReads, error: noahError } = await (await apiAs(inst, noah)).from('user_entitlements').select('id');
  if (noahError) throw noahError;
  log(`noah: ${noahRows} Premium rows in Mehr, ${noahStatus} status lines on /more/lifetime, reads ${noahReads.length} user_entitlements rows`);
  if (noahRows || noahStatus || noahReads.length) throw new Error('Noah sees Mia\'s Premium');
  const { data: miaReads } = await miaApi.from('user_entitlements').select('premium_source, expires_at');
  log(`mia reads her user_entitlements: ${JSON.stringify(miaReads)}`);

  const updated = await rcEvent('EXPIRATION', -1);
  log(`database after EXPIRATION: ${JSON.stringify(dbState())}`);
  const gone = await until(renews(page, L), 0, 30_000);
  log(`the status left Mia's page live after ${gone} ms (answer ${updated})`);
  await capture(page, dir, '09-mia-page-lapsed');
  await back(page);
  const rowGone = await until(premiumRow(page, L), 0, 30_000);
  log(`the Mehr row is gone (${rowGone} ms after reopening Mehr)`);
  await capture(page, dir, '10-mia-more-lapsed');

  await openTab(page, L, 'tabList');
  await addField(page, L).click();
  await addSheet(page, L).waitFor({ timeout: 10_000 });
  await typeInto(addField(page, L), 'Kaffee');
  await addSheet(page, L).getByRole('button', { name: new RegExp(`, ${L('suggestionTyped')}(,|$)`) }).waitFor({ timeout: 10_000 });
  await page.keyboard.press('Enter');
  // The added note, or on the compact sheet (add-sheet-compact, full) the chip row.
  await addSheet(page, L).getByText(/^✓ /).first().or(addSheet(page, L).getByRole('button', { name: L('quantityPlus'), exact: true })).waitFor({ timeout: 10_000 });
  await page.keyboard.press('Escape');
  await addSheet(page, L).waitFor({ state: 'detached', timeout: 10_000 });
  const coffee = itemRow(page, 'Kaffee').first();
  await reveal(page, coffee);
  await capture(page, dir, '11-mia-added-after-lapse');
  await coffee.click();
  await itemRow(page, 'Kaffee').waitFor({ state: 'detached', timeout: 10_000 });
  await answerShopAsk(page, L, 'shopAskNo');
  const listId = sql(`select id from public.households where name = '${other}' and id in (select household_id from public.household_members where user_id = '${mia.id}')`);
  let status;
  for (let i = 0; i < 40 && status !== 'bought'; i++) {
    status = (await miaApi.from('items').select('status').eq('household_id', listId).eq('name', 'Kaffee')).data?.[0]?.status;
    if (status !== 'bought') await page.waitForTimeout(250);
  }
  log(`after lapse: added and ticked „Kaffee“ in „${other}“; database status ${status}`);
  if (status !== 'bought') throw new Error('the tick after the lapse did not reach the server');
  await capture(page, dir, '12-mia-ticked-after-lapse');

  await openTab(page, L, 'tabMore');
  const restored = await rcEvent('RENEWAL', 365);
  log(`database after RENEWAL: ${JSON.stringify(dbState())}`);
  const returned = await until(premiumRow(page, L), 1, 30_000);
  log(`RENEWAL (${restored}): the row came back live after ${returned} ms`);
  await premiumRow(page, L).click();
  await renews(page, L).waitFor({ timeout: 10_000 });
  log(`page after RENEWAL: "${await renews(page, L).textContent()}"`);
  await capture(page, dir, '13-mia-page-renewed');
  const errors = [...miaApp.errors, ...noahApp.errors];
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await miaApp.browser.close();
  await noahApp?.browser.close();
  sql(`delete from public.purchases where transaction_id = '${tx}'`);
  sql(`delete from public.households where id = '${second.id}'`);
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
console.log('PASS');
