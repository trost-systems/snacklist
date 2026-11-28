// Feature more-help (vmaint-20261125): More's rows top to bottom on the users' build, every button
// from Konto to Abmelden so an unknown row fails („Benachrichtigungen & Erinnerungen“ on every build
// since #759: on the web its page holds only the name switch, since push needs a phone), the legal rows' pages (Nutzungsbedingungen opens Snacklist's own terms since #695; the Apple EULA row is
// iPhone-only, so the web has none) and the version line from app/pubspec.yaml. snacklist.app is
// stubbed, so only the popup's URL is checked, never the live site.
//
//   node journeys/more-help.mjs <evidence dir> [--lang de|en]
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { accessibleName, capture, instance, logger, member, openApp, openTab, repo, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: more-help.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, context, page, L, errors } = await openApp(inst, { lang, videoDir: dir, viewport: { width: 390, height: 1400 } });
await context.route('https://snacklist.app/**', (route) => route.fulfill({ status: 200, contentType: 'text/html', body: '<p>stub</p>' }));
const site = 'https://snacklist.app';
const expected = [
  L('account'), L('accessTitle'), L('settingsTitle'), L('settingsPush'),
  L('analyticsSection'), L('hintsTitle'),
  L('feedbackHubRow'), L('helpRow'), L('imprint'), L('privacyPolicy'), L('premiumTermsLink'),
  L('licenses'), L('signOut'),
];
const pages = [
  [L('helpRow'), lang === 'de' ? `${site}/support` : `${site}/en/support`],
  [L('imprint'), lang === 'de' ? `${site}/impressum` : `${site}/en/imprint`],
  [L('privacyPolicy'), lang === 'de' ? `${site}/datenschutz` : `${site}/en/privacy`],
  [L('premiumTermsLink'), lang === 'de' ? `${site}/nutzungsbedingungen` : `${site}/en/terms`],
];
const pubspec = /^version: (\d+\.\d+\.\d+)\+(\d+)$/m.exec(readFileSync(join(repo, 'app/pubspec.yaml'), 'utf8'));
let failed = null;
try {
  await signIn(page, L, user);
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: L('signOut'), exact: true }).waitFor({ timeout: 15_000 });
  await capture(page, dir, '01-more');
  const snapshot = await page.locator('body').ariaSnapshot();
  const buttons = snapshot.split('\n').filter((line) => /^\s*- button "/.test(line)).map(accessibleName);
  const rows = buttons.slice(buttons.indexOf(L('account')), buttons.indexOf(L('signOut')) + 1);
  log(`More's rows: ${rows.join(' | ')}`);
  const withoutPremium = rows.filter((name) => name !== L('premiumTitle'));
  if (withoutPremium.join('|') !== expected.join('|')) throw new Error(`rows differ from ${expected.join(' | ')}`);
  if (rows.includes(L('premiumAppleEulaLink'))) throw new Error('the Apple EULA row shows on the web');
  for (const [label, url] of pages) {
    const popup = page.waitForEvent('popup');
    await page.getByRole('button', { name: label, exact: true }).click();
    const opened = await popup;
    log(`„${label}“ opened ${opened.url()}`);
    if (opened.url().replace(/\/$/, '') !== url) throw new Error(`„${label}“ opened ${opened.url()}, expected ${url}`);
    await opened.close();
    if (!page.url().endsWith('/more')) throw new Error(`the app left /more: ${page.url()}`);
  }
  const version = `${pubspec?.[1]} (${pubspec?.[2]})`;
  await page.getByText(L('appVersion', { version }), { exact: true }).waitFor({ timeout: 5_000 });
  log(`version line „${L('appVersion', { version })}“`);
  await capture(page, dir, '02-more-after-links');
  await page.getByRole('button', { name: L('settingsPush'), exact: true }).click();
  await page.getByRole('switch', { name: new RegExp(`^${L('pushNameHidden')}`) }).waitFor({ timeout: 10_000 });
  if (!page.url().endsWith('/more/notifications')) throw new Error(`the row opened ${page.url()}`);
  for (const key of ['pushHouseholdAdd', 'shoppingDayTitle', 'remindersTitle']) {
    if (await page.getByText(L(key), { exact: true }).count()) throw new Error(`„${L(key)}“ shows on the web, which has no push`);
  }
  log(`„${L('settingsPush')}“ opened /more/notifications with only „${L('pushNameHidden')}“`);
  await capture(page, dir, '03-notifications');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await context.close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS more-help (evidence: ${dir})`);
