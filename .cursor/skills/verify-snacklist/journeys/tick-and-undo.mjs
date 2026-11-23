// Feature tick-and-undo, entry point: a tap on a list row, then a tap on it under „Zuletzt
// verwendet“ (sub-features tu-tick, tu-tick-a11y, tu-used-section, tu-put-back). Proves the row is
// a checkbox, strikes and leaves without a snackbar, is stored as bought, and comes back. With
// recently-used-open (full since 2026-11-22) „Zuletzt verwendet“ starts open: it proves that, folds
// the section with a tap and opens it again before the put-back. With
// trip-mode on (off for users since 2026-11-22, Peter HP2, job 401; VH_DEFINES="FLAGS_ON=trip-mode")
// the tick asks „Kaufst du gerade ein?“: it first ticks the second item and takes it back with
// „Zurücknehmen“ (no snooze), then answers „Nein, nur abgehakt“ for the item, and proves the next
// tick asks nothing for the hour after that no (#618). Without the question (a plain launch) it
// skips those steps and logs a build without trip-mode. The second item goes back on the list
// through the API at the end.
//
//   node journeys/tick-and-undo.mjs <evidence dir> [--lang de|en] [--item Butter] [--second Reis]
import process from 'node:process';
import { answerShopAsk, apiAs, capture, flagOn, instance, itemRow, logger, member, openApp, reveal, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const name = opt('item', 'Butter');
const second = opt('second', lang === 'en' ? 'Rice' : 'Reis');
if (!dir) throw new Error('usage: tick-and-undo.mjs <evidence dir> [--lang de|en] [--item name] [--second name]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const statusOf = async (item) => (await api.from('items').select('status').eq('household_id', user.householdId).eq('name', item)).data?.map((r) => r.status);
const status = () => statusOf(name);
const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}); "${name}" in the database: ${JSON.stringify(await status())}`);
  const row = itemRow(page, name).first();
  await reveal(page, row);
  if (await row.isChecked()) throw new Error(`"${name}" starts checked`);
  await capture(page, dir, '01-before');

  const tickAway = async (item) => {
    const r = itemRow(page, item).first();
    await reveal(page, r);
    await r.click();
    await itemRow(page, item).waitFor({ state: 'detached', timeout: 10_000 });
  };
  const waitStatus = async (item, want) => {
    for (let i = 0; i < 20 && (await statusOf(item))?.[0] !== want; i++) await page.waitForTimeout(250);
    return (await statusOf(item))?.[0] === want;
  };

  await tickAway(second);
  const asked = await answerShopAsk(page, L, 'shopAskTakeBack');
  if (asked) {
    await itemRow(page, second).first().waitFor({ timeout: 10_000 });
    const back = await waitStatus(second, 'active');
    log(`ticked "${second}", „${L('shopAskTitle')}“ came, „${L('shopAskTakeBack')}“ put it back; database: ${JSON.stringify(await statusOf(second))}`);
    if (!back) throw new Error(`„${L('shopAskTakeBack')}“ did not put "${second}" back on the server`);
    await capture(page, dir, '01b-taken-back');
  } else {
    log(`no „${L('shopAskTitle')}“ (a build without trip-mode)`);
    if (!(await waitStatus(second, 'bought'))) throw new Error(`the tick of "${second}" did not reach the server`);
    await api.from('items').update({ status: 'active', bought_by: null, bought_at: null }).eq('household_id', user.householdId).eq('name', second);
  }

  await row.click();
  await page.waitForTimeout(60);
  await page.screenshot({ path: `${dir}/02-striking.png`, animations: 'allow' });
  log(`tapped "${name}": mid-tick screenshot 02-striking.png`);
  await itemRow(page, name).waitFor({ state: 'detached', timeout: 10_000 });
  if (asked) {
    await page.getByText(L('shopAskTitle'), { exact: true }).waitFor({ timeout: 3_000 });
    await capture(page, dir, '02b-trip-question');
    await answerShopAsk(page, L, 'shopAskNo');
    log(`„${L('shopAskTitle')}“ came; answered „${L('shopAskNo')}“`);
  }
  const undo = await page.getByRole('button', { name: L('undo'), exact: true }).count();
  if (undo) throw new Error('a tick showed an undo button');
  const bought = await waitStatus(name, 'bought');
  log(`row gone, no „${L('undo')}“; database: ${JSON.stringify(await status())}`);
  if (!bought) throw new Error('the tick did not reach the server');
  await capture(page, dir, '03-after-tick');

  const section = page.getByRole('button', { name: L('recentlyUsed') });
  await reveal(page, section);
  const used = page.getByRole('button', { name: new RegExp(`^${name}( .*)? ${L('readd')}$`) });
  if (flagOn('recently-used-open')) {
    if (!(await used.count())) throw new Error(`„${L('recentlyUsed')}“ did not start open`);
    await section.click();
    await used.waitFor({ state: 'detached', timeout: 5_000 });
    log(`„${L('recentlyUsed')}“ started open (recently-used-open); a tap on it folds it`);
    await capture(page, dir, '03b-used-folded');
  }
  await section.click();
  await reveal(page, used);
  await capture(page, dir, '04-recently-used');
  await used.click();
  await itemRow(page, name).first().waitFor({ timeout: 10_000 });
  const active = await waitStatus(name, 'active');
  log(`put back from „${L('recentlyUsed')}“; database: ${JSON.stringify(await status())}`);
  if (!active) throw new Error('putting it back did not reach the server');
  await capture(page, dir, '05-put-back');

  if (asked) {
    await tickAway(second);
    if (await answerShopAsk(page, L, 'shopAskNo')) throw new Error(`„${L('shopAskTitle')}“ came again within the hour after „${L('shopAskNo')}“`);
    const ticked = await waitStatus(second, 'bought');
    log(`ticked "${second}" again: no „${L('shopAskTitle')}“ (snoozed after the no); database: ${JSON.stringify(await statusOf(second))}`);
    if (!ticked) throw new Error(`the tick of "${second}" did not reach the server`);
    await capture(page, dir, '06-snoozed');
    await api.from('items').update({ status: 'active', bought_by: null, bought_at: null }).eq('household_id', user.householdId).eq('name', second);
  }
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS tick-and-undo (evidence: ${dir})`);
