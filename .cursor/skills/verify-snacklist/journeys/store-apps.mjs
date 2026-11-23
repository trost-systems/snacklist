// Feature store-apps (flag open-store-app, off for users; job 313), on demo-familie. With
// `--expect on` (a build with FLAGS_ON=open-store-app): Liste → Anpassen → „Laden hinzufügen“
// offers REWE after „Re“ and a tap makes it without a question; „Lidl am Markt“ and Enter asks
// „Ist das Lidl (Deutschland)?“, „Ja“ matches it (`stores.retailer_chain`), its details read
// „Zugeordnet: Lidl · …“ and „Lidl Plus öffnen“ opens the Play page in a new tab; with Butter moved
// to it, the list's store header has the key and the one-time tip, and the key opens the same page.
// With `--expect off` (the users' build): no chain offered, no question, no chain line, no key.
// Deletes the stores it made.
//
//   node journeys/store-apps.mjs <evidence dir> [--expect on|off]
import process from 'node:process';
import { apiAs, capture, instance, itemRow, logger, member, openApp, openTab, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const expect = opt('expect', 'off');
if (!dir || !['on', 'off'].includes(expect)) throw new Error('usage: store-apps.mjs <evidence dir> [--expect on|off]');

const playLidl = 'https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus';
const made = ['REWE', 'Lidl am Markt'];
const item = 'Butter';
const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const { browser, context, page, L, errors } = await openApp(inst, { videoDir: dir });
await context.route(/^https:\/\/(play\.google\.com|apps\.apple\.com)\//, (route) =>
  route.fulfill({ status: 200, contentType: 'text/html', body: '<title>store page</title>' }));

const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const count = (locator) => locator.count();
const back = () => page.getByRole('button', { name: 'Zurück', exact: true }).first().click();
const storeRow = (name) => page.getByRole('button', { name, exact: true });
async function openStores() {
  await openTab(page, L, 'tabList');
  await page.getByRole('button', { name: L('listEdit'), exact: true }).click();
  await page.getByRole('button', { name: L('storeAdd') }).waitFor({ timeout: 10_000 });
}
async function typeNewStore(name) {
  await page.getByRole('button', { name: L('storeAdd') }).click();
  await typeInto(page.getByRole('textbox', { name: L('storeNameHint') }), name);
}
async function opened(tap) {
  const popup = context.waitForEvent('page', { timeout: 10_000 });
  await tap();
  const tab = await popup;
  await tab.waitForLoadState('domcontentloaded');
  const url = tab.url();
  await tab.close();
  return url;
}
async function cleanup() {
  const { data } = await api.from('stores').select('id, name').eq('household_id', user.householdId).in('name', made);
  for (const { id } of data ?? []) await api.rpc('delete_store', { p_store: id });
  log(`cleanup: deleted ${(data ?? []).map((s) => s.name).join(', ') || 'nothing'}`);
}

let failed = null;
try {
  await cleanup();
  await signIn(page, L, user);
  log(`signed in as ${user.handle}, expect ${expect}, on ${inst.webUrl}`);
  await openStores();
  await capture(page, dir, '01-stores');

  const rewe = page.getByRole('button', { name: L('chainSuggestionPick', { chain: 'REWE', country: 'Deutschland' }) });
  await typeNewStore('Re');
  if (expect === 'on') {
    await rewe.waitFor({ timeout: 10_000 });
    await capture(page, dir, '02-suggestion');
    await rewe.click();
    await storeRow('REWE').waitFor({ timeout: 10_000 });
    check(await count(page.getByRole('dialog')) === 0, 'a suggestion makes REWE and asks nothing');
  } else {
    await page.waitForTimeout(2_000);
    check(await count(page.getByRole('button', { name: /wählen$/ })) === 0, 'no chain offered while typing „Re“');
    await capture(page, dir, '02-no-suggestion');
    await page.keyboard.press('Escape');
  }

  await typeNewStore('Lidl am Markt');
  await page.keyboard.press('Enter');
  const question = page.getByRole('heading', { name: L('chainQuestionOne', { chain: 'Lidl', country: 'Deutschland' }) });
  if (expect === 'on') {
    await question.waitFor({ timeout: 10_000 });
    await capture(page, dir, '03-question');
    await page.getByRole('button', { name: L('chainQuestionYes'), exact: true }).click();
  } else {
    await storeRow('Lidl am Markt').waitFor({ timeout: 10_000 });
    await page.waitForTimeout(1_500);
    check(await count(question) === 0, 'a chain\'s name asks nothing');
  }
  await storeRow('Lidl am Markt').waitFor({ timeout: 10_000 });
  const { data: stored } = await api.from('stores').select('name, retailer_chain, retailer_country, retailer_app').eq('household_id', user.householdId).eq('name', 'Lidl am Markt');
  log(`database: ${JSON.stringify(stored)}`);
  check(stored?.length === 1 && (expect === 'on' ? stored[0].retailer_chain !== null : stored[0].retailer_chain === null),
    expect === 'on' ? '„Ja“ matched Lidl am Markt on the server' : 'Lidl am Markt stays unmatched');

  await storeRow('Lidl am Markt').click();
  // The chain line is read out in the App card's group, „App Lidl Plus Zugeordnet: Lidl · Deutschland“.
  const linked = page.getByText(new RegExp(`^${L('storeChainLinked', { chain: 'Lidl', country: 'XX' }).replace('XX', '.+')}$`))
    .or(page.getByRole('group', { name: new RegExp(`${L('storeChainLinked', { chain: 'Lidl', country: 'XX' }).replace('XX', '.+')}$`) }));
  const openKey = page.getByRole('button', { name: L('storeAppOpen', { app: 'Lidl Plus' }) });
  if (expect === 'on') {
    await linked.waitFor({ timeout: 10_000 });
    await capture(page, dir, '04-details');
    const url = await opened(() => openKey.first().click());
    check(url === playLidl, `the details' App card opens ${url}`);
  } else {
    await page.getByRole('heading', { name: 'Lidl am Markt', exact: true }).waitFor({ timeout: 10_000 });
    check(await count(linked) + await count(page.getByRole('button', { name: L('storeChainConnect') })) + await count(openKey) === 0,
      'the details have no chain line, no „Kette zuordnen“ and no App card');
    await capture(page, dir, '04-details');
  }
  await back();

  const { data: lidl } = await api.from('stores').select('id').eq('household_id', user.householdId).eq('name', 'Lidl am Markt').single();
  const { error } = await api.from('items').update({ store_id: lidl.id }).eq('household_id', user.householdId).eq('name', item).eq('status', 'active');
  if (error) throw error;
  await openTab(page, L, 'tabList');
  await reveal(page, itemRow(page, item).first());
  const tip = page.getByRole('group', { name: L('storeAppTip') });
  if (expect === 'on') {
    await openKey.first().waitFor({ timeout: 10_000 });
    check(await count(tip) === 1, 'the one-time tip shows under the header');
    await capture(page, dir, '05-header-key');
    const url = await opened(() => openKey.first().click());
    check(url === playLidl, `the header key opens ${url}`);
    await tip.waitFor({ state: 'detached', timeout: 5_000 });
    log('ok: the first key tap ends the tip');
  } else {
    await page.waitForTimeout(1_500);
    check(await count(openKey) + await count(tip) === 0, 'the header of a store named Lidl has no key and no tip');
    await capture(page, dir, '05-header-plain');
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await cleanup().catch((e) => log(`cleanup failed: ${e.message}`));
  await browser.close();
}
log(failed ? `FAIL store-apps (${expect}): ${failed.message}` : `PASS store-apps (${expect})`);
process.exit(failed ? 1 : 0);
