// Feature tips, sub-feature checklist (job 204): „Einmal einkaufen“ on the „Erste Schritte“ card is
// done by one tick or one saved edit while other items stay on the list. The first member ticks one
// item; a second member, on a fresh device, saves a change in an item's edit sheet. Needs a fresh
// demo household (three members, five or more open items): launch.sh --fresh.
//
//   node journeys/tips-first-shop.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { answerShopAsk, apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: tips-first-shop.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const [first, second] = ['mia', 'noah'].map((handle) => member(inst, handle));
const api = await apiAs(inst, first);
const openItems = async () => {
  const { data, error } = await api.from('items').select('name').eq('household_id', first.householdId)
    .eq('status', 'active').order('name');
  if (error) throw error;
  return data.map((i) => i.name);
};

/** Signs in and keeps the card: signIn hides it unless its X has no name to find. */
async function session(user, step) {
  const app = await openApp(inst, { lang, videoDir: dir });
  const { page, L } = app;
  await signIn(page, (key, params) => (key === 'checklistDismiss' ? '\u0000' : L(key, params)), user);
  const card = page.getByRole('button', { name: L('checklistDismiss'), exact: true });
  await card.waitFor({ timeout: 15_000 });
  const heading = async () => {
    const aria = await page.locator('body').ariaSnapshot();
    return aria.split('\n').find((line) => line.includes(`heading "${L('checklistTitle')}`))?.trim() ?? 'no card';
  };
  const done = () => page.getByText(L('checklistDone', { step: L('checklistShop') })).count();
  return { ...app, card, heading, done, shot: (name) => capture(page, dir, `${step}-${name}`) };
}

let failed = null;
const browsers = [];
try {
  const before = await openItems();
  if (before.length < 3) throw new Error(`needs 3 or more open items, has ${before.length}`);

  const a = await session(first, 'a');
  browsers.push(a.browser);
  log(`${first.handle} signed in: ${await a.heading()}; open: ${before.join(', ')}`);
  await a.shot('01-before-tick');
  const ticked = before[0];
  await reveal(a.page, itemRow(a.page, ticked).first());
  await itemRow(a.page, ticked).first().click();
  await itemRow(a.page, ticked).waitFor({ state: 'detached', timeout: 10_000 });
  await answerShopAsk(a.page, a.L, 'shopAskNo');
  await a.page.waitForTimeout(1_000);
  const afterTick = await openItems();
  const cardLeft = (await a.card.count()) === 0;
  log(`ticked "${ticked}"; still open: ${afterTick.length} (${afterTick.join(', ')}); card: ${cardLeft ? 'gone (every step done)' : await a.heading()}`);
  await a.shot('02-after-tick');
  if (afterTick.length === 0) throw new Error('the tick emptied the list: not the case under test');
  if (!cardLeft && (await a.done()) === 0) throw new Error(`„${a.L('checklistShop')}“ still open after a tick`);

  const b = await session(second, 'b');
  browsers.push(b.browser);
  log(`${second.handle} signed in on a fresh device: ${await b.heading()}`);
  if ((await b.done()) > 0) throw new Error(`„${b.L('checklistShop')}“ done before anything happened on this device`);
  await b.shot('01-before-edit');
  const edited = afterTick[0];
  const sheet = b.page.getByRole('group', { name: b.L('editSheet'), exact: true });
  await reveal(b.page, itemRow(b.page, edited).first());
  await itemRow(b.page, edited).first().click({ button: 'right' });
  await sheet.waitFor({ timeout: 10_000 });
  await typeInto(sheet.getByRole('textbox', { name: b.L('fieldName') }), `${edited} Bio`);
  await sheet.getByRole('button', { name: b.L('done'), exact: true }).click();
  await sheet.waitFor({ state: 'detached', timeout: 10_000 });
  await b.page.waitForTimeout(1_000);
  const editLeft = (await b.card.count()) === 0;
  log(`renamed "${edited}" to "${edited} Bio" in the edit sheet; card: ${editLeft ? 'gone (every step done)' : await b.heading()}`);
  await b.shot('02-after-edit');
  if (!editLeft && (await b.done()) === 0) throw new Error(`„${b.L('checklistShop')}“ still open after a saved edit`);
  for (const { errors } of [a, b]) if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
} finally {
  for (const browser of browsers) await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS tips-first-shop (evidence: ${dir})`);
