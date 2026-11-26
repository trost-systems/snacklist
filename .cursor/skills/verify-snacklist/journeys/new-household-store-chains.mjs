// Feature households, „Neuer Haushalt“ from the switcher with the flag open-store-app (job 321, OB-Q8):
// the same store chips as the guided start, from the browser's region, without the hint lines; the
// household is created with the tapped chains linked. Plain launch (open-store-app is full since 2026-11-25).
//
//   node journeys/new-household-store-chains.mjs <evidence dir> [--locale de-AT]
import process from 'node:process';
import { apiAs, capture, instance, logger, member, openApp, openHouseholds, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const locale = rest.includes('--locale') ? rest[rest.indexOf('--locale') + 1] : 'de-AT';
if (!dir) throw new Error('usage: new-household-store-chains.mjs <evidence dir> [--locale de-AT]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const name = `Ferienhaus ${Date.now().toString(36)}`;
const { browser, page, L, errors } = await openApp(inst, { lang: 'de', locale, videoDir: dir });
const scrollTo = async (locator) => {
  await page.mouse.move(195, 422);
  for (let i = 0; i < 20 && !(await locator.count() && (await locator.boundingBox())?.y < 760); i++) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(200);
  }
};
let failed = null;
let created = null;
try {
  await signIn(page, L, user);
  const { data: shown } = await api.from('households').select('name').eq('id', user.householdId).single();
  await openHouseholds(page, L, shown.name);
  const newHousehold = page.getByRole('button', { name: L('newHousehold'), exact: true });
  await scrollTo(newHousehold);
  await newHousehold.click();
  await typeInto(page.getByRole('textbox', { name: L('householdName') }), name);
  await page.getByRole('checkbox', { name: 'BILLA', exact: true }).click();
  await page.getByRole('checkbox', { name: 'MPREIS', exact: true }).click();
  await page.waitForTimeout(300);
  await capture(page, dir, '01-new-household');
  const snapshot = await page.locator('body').ariaSnapshot();
  const offered = [...snapshot.matchAll(/- checkbox "([^"]+)"/g)].map((m) => m[1]);
  log(`chips offered: ${JSON.stringify(offered)}`);
  check(offered.join(',') === `BILLA,SPAR,Hofer,Lidl,PENNY,MPREIS,dm,${L('storeHardware')}`, `the ${locale} chips, as in the guided start`);
  check(![L('onboardingStoresHint'), L('skipStoresHint')].some((h) => snapshot.includes(h)), 'neither hint line shows');
  const create = page.getByRole('button', { name: L('createHousehold'), exact: true });
  await scrollTo(create);
  await create.click();
  await page.waitForURL(/invite/, { timeout: 20_000 });
  const { data: households } = await api.from('households').select('id').eq('name', name);
  created = households?.[0]?.id;
  const { data: stores } = await api
    .from('stores')
    .select('name, retailer_chain, retailer_country, retailer_answered')
    .eq('household_id', created)
    .order('sort_order');
  log(`stores ${JSON.stringify(stores)}`);
  check(
    stores.map((s) => `${s.name}:${s.retailer_chain}/${s.retailer_country}`).join(',') === 'BILLA:billa/AT,MPREIS:mpreis/AT',
    'the new household has BILLA and MPREIS, linked',
  );
  check(errors.length === 0, `no page errors (${errors.join(' | ')})`);
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
}
// The seeded member leaves the household again, so the run's teardown finds what it seeded.
if (created) await api.rpc('leave_household', { p_household: created }).then(({ error }) => log(`left it: ${error?.message ?? 'ok'}`));
await browser.close();
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
