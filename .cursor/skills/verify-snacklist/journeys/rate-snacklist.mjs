// Feature rate-snacklist (job 155), entry points More and a completed trip on the List tab. The web
// build has no store listing: proves More has no „Snacklist bewerten“ between „Feedback senden“ and
// „Hilfe & Kontakt“, and that ticking every item counts one completed trip in this device's
// counters (`review.state`: counts and dates only) without a page error or a prompt, and that
// putting an item back from „Zuletzt verwendet“ and ticking it again is still that one trip. A
// tick 10 s offline is no sync failure; an add 70 s offline is one (`last_error_at`). The first
// return from the background after the launch starts a new session.
//
//   node journeys/rate-snacklist.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { addField, answerShopAsk, capture, instance, logger, member, openApp, openTab, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: rate-snacklist.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  const counters = () =>
    page.evaluate(() => {
      const entry = Object.entries(localStorage).find(([k]) => k.endsWith('review.state'));
      return entry ? JSON.parse(JSON.parse(entry[1])) : null;
    });
  const before = await counters();
  log(`review.state after sign-in: ${JSON.stringify(before)}`);
  if (!before?.first_launch || before.active_days !== 1) throw new Error('the first start was not counted');

  // The first return from the background after a launch in the foreground starts a session.
  const visibility = (v) =>
    page.evaluate((v) => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => v });
      document.dispatchEvent(new Event('visibilitychange'));
    }, v);
  await visibility('hidden');
  await page.waitForTimeout(1_500);
  await visibility('visible');
  await page.waitForTimeout(1_500);
  const returned = await counters();
  log(`back from the background once; review.state: ${JSON.stringify(returned)}`);
  if (returned?.session_start === before.session_start) throw new Error('the first return from the background started no session');
  if (returned?.previous_session_start !== before.session_start) throw new Error('the launch session is not the previous one');

  const open = page.getByRole('checkbox', { checked: false });
  // A tick in a dead spot that goes out once the signal is back is no sync failure.
  await page.context().setOffline(true);
  const first = open.first();
  await reveal(page, first);
  await first.click();
  await answerShopAsk(page, L, 'shopAskNo');
  // The sync indicator's card or pill: a button named „Offline: …“ (e2e's offlineIndicator).
  const offlineShown = async () => (await page.getByRole('button', { name: new RegExp(`^${L('syncOffline')}:`) }).count()) > 0;
  for (const end = Date.now() + 8_000; !(await offlineShown()) && Date.now() < end; ) await page.waitForTimeout(250);
  if (!(await offlineShown())) throw new Error('the list never showed it was offline');
  await page.waitForTimeout(10_000);
  await page.context().setOffline(false);
  await page.waitForTimeout(8_000);
  const blip = await counters();
  log(`ticked one item 10 s offline, back online; review.state: ${JSON.stringify(blip)}`);
  if (blip?.last_error_at) throw new Error('a short offline spell counted as a sync failure');
  // The list builds rows lazily: tick until no open row is left, not a count taken up front.
  let total = 0;
  for (; total < 60 && (await open.count()) > 0; total++) {
    const row = open.first();
    await reveal(page, row);
    await row.click();
    await answerShopAsk(page, L, 'shopAskNo', 1_500);
    await page.waitForTimeout(400);
  }
  if ((await open.count()) > 0) throw new Error('items left open after ticking all');
  await page.waitForTimeout(4_000);
  await capture(page, dir, '01-list-done');
  const after = await counters();
  log(`ticked ${total} items; review.state now: ${JSON.stringify(after)}`);
  if (after?.completed_trips !== (before.completed_trips ?? 0) + 1) throw new Error('the completed trip was not counted');
  if (JSON.stringify(after).match(/Bananen|Butter|[0-9a-f]{8}-[0-9a-f]{4}-/)) throw new Error('review.state holds an item name or id');
  if ((after.requests ?? []).length) throw new Error('a web build asked for a rating');

  // The tick's undo: put one item back from „Zuletzt verwendet“ and tick it again. Same trip.
  const section = page.getByRole('button', { name: L('recentlyUsed') });
  await reveal(page, section);
  await section.click();
  const used = page.getByRole('button', { name: new RegExp(` ${L('readd')}$`) }).first();
  await reveal(page, used);
  await used.click();
  const back = page.getByRole('checkbox', { checked: false }).first();
  await back.waitFor({ timeout: 10_000 });
  await reveal(page, back);
  await back.click();
  await answerShopAsk(page, L, 'shopAskNo');
  for (const end = Date.now() + 10_000; (await open.count()) > 0 && Date.now() < end; ) await page.waitForTimeout(250);
  await page.waitForTimeout(1_000);
  const undone = await counters();
  log(`put one back and ticked it again; review.state now: ${JSON.stringify(undone)}`);
  if (undone?.completed_trips !== after.completed_trips) throw new Error('the undo and re-tick counted another trip');

  // Offline past the 60 s grace is a sync failure the user saw.
  await page.context().setOffline(true);
  const field = addField(page, L);
  await typeInto(field, 'Kaffee');
  await field.press('Enter');
  // The add sheet stays open and hides the list from the accessibility tree.
  await page.keyboard.press('Escape');
  for (const end = Date.now() + 8_000; !(await offlineShown()) && Date.now() < end; ) await page.waitForTimeout(250);
  if (!(await offlineShown())) throw new Error('the list never showed it was offline');
  await page.waitForTimeout(70_000);
  await page.context().setOffline(false);
  const long = await counters();
  log(`70 s offline; review.state: ${JSON.stringify(long)}`);
  if (!long?.last_error_at) throw new Error('a minute offline was not counted as a sync failure');

  await openTab(page, L, 'tabMore');
  // feedback-fb4 (users' build) names the row „Feedback & Ideen“; a flag-off build „Feedback senden“.
  const hub = page.getByRole('button', { name: new RegExp(`^${L('feedbackHubRow')}( |,|$)`) });
  await hub.or(page.getByRole('button', { name: new RegExp(`^${L('feedbackRow')}( |$)`) })).first().waitFor({ timeout: 10_000 });
  const feedbackLabel = L((await hub.count()) ? 'feedbackHubRow' : 'feedbackRow');
  const feedback = page.getByRole('button', { name: new RegExp(`^${feedbackLabel}( |,|$)`) });
  await reveal(page, feedback);
  await capture(page, dir, '02-more-feedback-group');
  const rate = await page.getByRole('button', { name: new RegExp(`^${L('rateApp')}( |$)`) }).count();
  const aria = await page.locator('body').ariaSnapshot();
  const order = aria.indexOf(feedbackLabel) < aria.indexOf(L('helpRow'));
  log(`More: „${L('rateApp')}“ rows: ${rate}; „${feedbackLabel}“ before „${L('helpRow')}“: ${order}`);
  if (rate !== 0) throw new Error('the web build shows the rate row');
  if (!order) throw new Error('feedback and help rows are not in order');
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
log(`PASS rate-snacklist (evidence: ${dir})`);
