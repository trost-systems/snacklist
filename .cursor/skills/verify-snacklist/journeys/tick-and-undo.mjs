// Feature tick-and-undo, entry point: a tap on a list row, then a tap on it under „Zuletzt
// verwendet“ (sub-features tu-tick, tu-tick-a11y, tu-used-section, tu-put-back). Proves the row is
// a checkbox, strikes and leaves without a snackbar, is stored as bought, and comes back. On the
// users' build (trip-mode full) the tick asks „Kaufst du gerade ein?“: it answers „Nein, nur
// abgehakt“, then ticks a second item and takes it back with „Zurücknehmen“.
//
//   node journeys/tick-and-undo.mjs <evidence dir> [--lang de|en] [--item Butter] [--second Reis]
import process from 'node:process';
import { answerShopAsk, apiAs, capture, instance, itemRow, logger, member, openApp, reveal, signIn } from '../helpers/lib.mjs';

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

  await row.click();
  await page.waitForTimeout(60);
  await page.screenshot({ path: `${dir}/02-striking.png`, animations: 'allow' });
  log(`tapped "${name}": mid-tick screenshot 02-striking.png`);
  await itemRow(page, name).waitFor({ state: 'detached', timeout: 10_000 });
  const askTitle = page.getByText(L('shopAskTitle'), { exact: true });
  const asked = await askTitle.waitFor({ timeout: 3_000 }).then(() => true, () => false);
  if (asked) {
    await capture(page, dir, '02b-trip-question');
    await answerShopAsk(page, L, 'shopAskNo');
    log(`„${L('shopAskTitle')}“ came; answered „${L('shopAskNo')}“`);
  } else {
    log(`no „${L('shopAskTitle')}“ (a build without trip-mode)`);
  }
  const undo = await page.getByRole('button', { name: L('undo'), exact: true }).count();
  if (undo) throw new Error('a tick showed an undo button');
  for (let i = 0; i < 20 && (await status())?.[0] !== 'bought'; i++) await page.waitForTimeout(250);
  log(`row gone, no „${L('undo')}“; database: ${JSON.stringify(await status())}`);
  if ((await status())?.[0] !== 'bought') throw new Error('the tick did not reach the server');
  await capture(page, dir, '03-after-tick');

  const section = page.getByRole('button', { name: L('recentlyUsed') });
  await reveal(page, section);
  await section.click();
  const used = page.getByRole('button', { name: new RegExp(`^${name}( .*)? ${L('readd')}$`) });
  await reveal(page, used);
  await capture(page, dir, '04-recently-used');
  await used.click();
  await itemRow(page, name).first().waitFor({ timeout: 10_000 });
  for (let i = 0; i < 20 && (await status())?.[0] !== 'active'; i++) await page.waitForTimeout(250);
  log(`put back from „${L('recentlyUsed')}“; database: ${JSON.stringify(await status())}`);
  if ((await status())?.[0] !== 'active') throw new Error('putting it back did not reach the server');
  await capture(page, dir, '05-put-back');

  if (asked) {
    const other = itemRow(page, second).first();
    await reveal(page, other);
    await other.click();
    await itemRow(page, second).waitFor({ state: 'detached', timeout: 10_000 });
    if (!(await answerShopAsk(page, L, 'shopAskTakeBack'))) throw new Error(`no „${L('shopAskTitle')}“ after ticking "${second}"`);
    await itemRow(page, second).first().waitFor({ timeout: 10_000 });
    for (let i = 0; i < 20 && (await statusOf(second))?.[0] !== 'active'; i++) await page.waitForTimeout(250);
    log(`ticked "${second}", „${L('shopAskTakeBack')}“ put it back; database: ${JSON.stringify(await statusOf(second))}`);
    if ((await statusOf(second))?.[0] !== 'active') throw new Error(`„${L('shopAskTakeBack')}“ did not put "${second}" back on the server`);
    await capture(page, dir, '06-taken-back');
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
