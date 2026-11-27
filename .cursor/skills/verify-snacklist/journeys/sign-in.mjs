// Feature sign-in, sign-out and the one sign-in page (job 486): „Abmelden“ in More opens the start
// screen („Los geht's“, „Ich habe schon ein Konto“, Impressum and Datenschutz) and stays there;
// „Ich habe schon ein Konto“ opens the sign-in with „Neu bei Snacklist? Los geht's“ and the legal
// links; that button leads back to the start screen. A link opened signed out shows the same
// sign-in, and „Neu bei Snacklist?“ carries the link into the guided start.
//
//   node journeys/sign-in.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { capture, instance, logger, member, nextFrames, openApp, openTab, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: sign-in.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
const button = (key) => page.getByRole('button', { name: L(key), exact: true });
const legal = ['imprint', 'privacy'];
const path = () => { const u = new URL(page.url()); return u.pathname + u.search; };
const park = () => page.mouse.move(1, 1);
const storageKeys = () => page.evaluate(() => Object.keys(localStorage).sort());

async function expectButtons(where, keys) {
  for (const key of keys) {
    if (!(await button(key).isVisible())) throw new Error(`${where}: no "${L(key)}"`);
  }
  for (const key of legal) {
    if (!(await page.getByRole('link', { name: L(key), exact: true }).isVisible())) throw new Error(`${where}: no link "${L(key)}"`);
  }
  log(`${where}: ${keys.map((k) => `"${L(k)}"`).join(', ')} and the links ${legal.map((k) => `"${L(k)}"`).join(', ')} visible`);
}

let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}) on ${inst.webUrl}`);
  const before = await storageKeys();

  await openTab(page, L, 'tabMore');
  const signOut = page.getByRole('button', { name: new RegExp(`^${L('signOut')}`) });
  await page.mouse.move(195, 400);
  for (let i = 0; i < 20 && !(await signOut.isVisible()); i++) await page.mouse.wheel(0, 400);
  await signOut.click();
  await page.waitForURL(/\/start$/, { timeout: 15_000 });
  await button('startGo').waitFor();
  await page.waitForTimeout(2_000);
  await nextFrames(page);
  if (path() !== '/start') throw new Error(`2 s after the sign-out the app is at ${path()}, not /start`);
  log(`signed out from More: ${path()} and still there 2 s later`);
  await expectButtons('start screen', ['startGo', 'startLogIn']);
  await park();
  await capture(page, dir, '01-signed-out-start');
  const after = await storageKeys();
  log(`localStorage keys signed in: ${before.length}, signed out: ${after.length}; gone: ${before.filter((k) => !after.includes(k)).join(', ') || 'none'}`);

  await button('startLogIn').click();
  await page.waitForURL(/\/login$/, { timeout: 15_000 });
  await button('loginNew').waitFor();
  await expectButtons('sign-in', ['loginNew']);
  await park();
  await capture(page, dir, '02-sign-in-new-user');

  await button('loginNew').click();
  await page.waitForURL(/\/start$/, { timeout: 15_000 });
  log(`"${L('loginNew')}" leads to ${path()}`);
  await park();
  await capture(page, dir, '03-back-to-start');

  await page.goto('/more/invites');
  await page.waitForURL(/\/login\?next=/, { timeout: 15_000 });
  await button('loginNew').waitFor();
  await expectButtons(`a link signed out (${path()})`, ['loginNew']);
  await park();
  await capture(page, dir, '04-link-sign-in-new-user');
  await button('loginNew').click();
  await page.waitForURL(/\/start\?next=/, { timeout: 15_000 });
  await button('startGo').waitFor();
  log(`"${L('loginNew')}" with a link leads to ${path()}`);
  await park();
  await capture(page, dir, '05-link-start');

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
log(`PASS sign-in (evidence: ${dir})`);
