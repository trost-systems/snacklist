// Feature premium, a beta account's lifetime grant (job 371): RevenueCat's promotional grant on Mia's
// own customer (App User ID = her user id) until 2100-01-01, stored through the server's real sync
// (promotional_premium_sync_user, what the webhook and scripts/iap/beta-lifetime.ts's reconcile
// call). With the integration lock on, the API refuses Mia before the grant and serves her after
// it; Noah in Familie Brandt stays refused and sees nothing of it. Mia's
// Premium page shows the beta-lifetime line; a tester grant on the household then shows Noah the
// tester line and leaves Mia's. Everything is undone at the end.
//
//   node journeys/premium-beta-lifetime.mjs <evidence dir>
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { apiAs, capture, instance, logger, member, openApp, openTab, signIn } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: premium-beta-lifetime.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const mia = member(inst, 'mia');
const noah = member(inst, 'noah');
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const forGood = '2100-01-01T00:00:00Z';

const premiumRow = (page, L) => page.getByRole('button', { name: new RegExp(`^${L('premiumTitle')}`) });

async function until(locator, n, timeout = 15_000) {
  const start = Date.now();
  while ((await locator.count()) !== n) {
    if (Date.now() - start > timeout) throw new Error(`${locator} has ${await locator.count()} matches, not ${n}`);
    await locator.page().waitForTimeout(100);
  }
  return Date.now() - start;
}

async function apiKey(user) {
  const { data, error } = await (await apiAs(inst, user)).rpc('create_api_token', { p_name: 'beta-lifetime', p_scopes: ['read'] });
  if (error) throw new Error(error.message);
  return data[0].token;
}

const items = async (key) => {
  const res = await fetch(`${inst.apiUrl}/functions/v1/api/v1/items`, { headers: { authorization: `Bearer ${key}` } });
  const body = await res.json().catch(() => null);
  return `${res.status}${body?.error?.code ? ` ${body.error.code}` : ''}`;
};

const switches = sql(`select string_agg(key || '=' || enabled, ',' order by key) from public.app_switches where key in ('integration_lock', 'premium_offer', 'public_api')`);
log(`switches before: ${switches}`);
const restore = () => {
  for (const pair of switches.split(',')) {
    const [key, on] = pair.split('=');
    sql(`update public.app_switches set enabled = ${on} where key = '${key}'`);
  }
  sql(`delete from public.purchases where transaction_id = 'beta-lifetime-journey'`);
  sql(`select public.promotional_premium_sync_user('${mia.id}', false, null)`);
  sql(`select public.promotional_premium_sync('${mia.householdId}', false, null)`);
  sql(`delete from public.personal_access_tokens where name = 'beta-lifetime'`);
};

const miaApp = await openApp(inst, { videoDir: `${dir}/mia` });
let noahApp = null;
let failed = null;
try {
  sql(`update public.app_switches set enabled = true where key in ('integration_lock', 'public_api')`);
  const miaKey = await apiKey(mia);
  const noahKey = await apiKey(noah);
  const before = { mia: await items(miaKey), noah: await items(noahKey) };
  log(`integration lock on, no grant: GET /items mia ${before.mia}, noah ${before.noah}`);
  if (!before.mia.startsWith('402') || !before.noah.startsWith('402')) throw new Error('the lock does not refuse before the grant');

  const { page, L } = miaApp;
  await signIn(page, L, mia);
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: L('account'), exact: true }).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(2000);
  if (await premiumRow(page, L).count()) throw new Error('Mia has a Premium row before the grant');
  await capture(page, dir, '01-mia-more-before');

  const outcome = sql(`select public.promotional_premium_sync_user('${mia.id}', true, '${forGood}')`);
  const again = sql(`select public.promotional_premium_sync_user('${mia.id}', true, '${forGood}')`);
  log(`grant stored: ${outcome}; again: ${again}; rows: ${sql(`select string_agg(source || '/' || premium_source || '/' || expires_at, ' ') from public.user_entitlements where user_id = '${mia.id}'`)}`);
  if (outcome !== 'granted' || again !== 'unchanged') throw new Error('the sync is not granted then unchanged');

  log(`the Mehr row appeared live after ${await until(premiumRow(page, L), 1)} ms`);
  await capture(page, dir, '02-mia-more-row-live');
  await premiumRow(page, L).click();
  const status = page.getByText(L('premiumStatusBetaLifetime'), { exact: true });
  await status.waitFor({ timeout: 10_000 });
  const body = await page.getByText(L('premiumBetaLifetimeBody'), { exact: true }).count();
  const oldBody = await page.getByText(L('premiumBetaBody'), { exact: true }).count();
  const testerLine = await page.getByText(L('premiumStatusFree'), { exact: true }).count();
  const privacy = await page.getByRole('link', { name: L('premiumBetaPrivacyLink') }).count();
  const buy = await page.getByRole('button', { name: new RegExp(`^(${L('premiumBuyYearly')}|${L('premiumBuyLifetime')})`) }).count();
  const heroOff = await page.getByText(L('premiumHeroBody'), { exact: true }).count();
  const refundOff = await page.getByRole('button', { name: L('lifetimeRefundLink') }).count();
  log(`mia's page: status 1, lifetime body ${body}, 4-weeks body ${oldBody}, tester line ${testerLine}, privacy link ${privacy}, buy buttons ${buy}, hero ${heroOff}, refund link ${refundOff}`);
  if (body !== 1 || oldBody || testerLine || privacy !== 1 || buy || heroOff !== 1 || refundOff) throw new Error('mia\'s page is wrong');
  await capture(page, dir, '03-mia-page-beta-lifetime');

  // Legal Review N-345, N-346: with sales on, the per-account hero, and no refund link for a grant alone.
  sql(`update public.app_switches set enabled = true where key = 'premium_offer'`);
  await page.reload();
  await status.waitFor({ timeout: 15_000 });
  await page.waitForTimeout(2000);
  const hero = await page.getByText(L('premiumHeroBody'), { exact: true }).count();
  const refund = await page.getByRole('button', { name: L('lifetimeRefundLink') }).count();
  log(`mia's page with sales on: hero ${hero}, refund link ${refund}`);
  if (hero !== 1 || refund) throw new Error('mia\'s page with sales on is wrong');
  await capture(page, dir, '03b-mia-page-sales-on');
  sql(`with p as (insert into public.purchases (store, transaction_id, product_id, environment, user_id, bound_user, purchased_at) values ('apple', 'beta-lifetime-journey', 'snacklist_premium_lifetime', 'Sandbox', '${mia.id}', '${mia.id}', now()) returning id, store, product_id, environment)
    insert into public.user_entitlements (purchase_id, user_id, source, premium_source, product_id, store, environment) select id, '${mia.id}', 'purchase', 'lifetime', product_id, store, environment from p`);
  await page.reload();
  const paidRefund = await until(page.getByRole('button', { name: L('lifetimeRefundLink') }), 1);
  log(`a store purchase next to the grant: refund link after ${paidRefund} ms`);
  await capture(page, dir, '03c-mia-page-sales-on-paid');
  sql(`delete from public.purchases where transaction_id = 'beta-lifetime-journey'`);
  sql(`update public.app_switches set enabled = false where key = 'premium_offer'`);

  const after = { mia: await items(miaKey), noah: await items(noahKey) };
  log(`after the grant: GET /items mia ${after.mia}, noah ${after.noah}`);
  if (!after.mia.startsWith('200') || !after.noah.startsWith('402')) throw new Error('the grant does not open the API for Mia alone');

  const household = sql(`select public.promotional_premium_sync('${mia.householdId}', true, '${forGood}')`);
  log(`a tester grant on Familie Brandt: ${household}`);
  await page.reload();
  await status.waitFor({ timeout: 15_000 });
  log('mia still reads the beta-lifetime line next to the household tester grant');
  await capture(page, dir, '04-mia-page-with-household-tester-grant');

  noahApp = await openApp(inst, { videoDir: `${dir}/noah` });
  await signIn(noahApp.page, noahApp.L, noah);
  await noahApp.page.goto('/more/lifetime');
  await noahApp.page.getByText(noahApp.L('premiumStatusFree'), { exact: true }).waitFor({ timeout: 15_000 });
  const noahLifetime = await noahApp.page.getByText(noahApp.L('premiumStatusBetaLifetime'), { exact: true }).count();
  log(`noah's page: tester line, beta-lifetime line ${noahLifetime}`);
  if (noahLifetime) throw new Error('Noah sees Mia\'s own grant');
  await capture(noahApp.page, dir, '05-noah-page-tester');
} catch (e) {
  failed = e;
} finally {
  restore();
  log(`restored: switches ${sql(`select string_agg(key || '=' || enabled, ',' order by key) from public.app_switches where key in ('integration_lock', 'premium_offer', 'public_api')`)}, mia rows ${sql(`select count(*) from public.user_entitlements where user_id = '${mia.id}'`)}`);
  await miaApp.context.close();
  await miaApp.browser.close();
  await noahApp?.context.close();
  await noahApp?.browser.close();
}
if (failed) {
  log(`FAILED: ${failed.message}`);
  process.exit(1);
}
log('PASSED');
