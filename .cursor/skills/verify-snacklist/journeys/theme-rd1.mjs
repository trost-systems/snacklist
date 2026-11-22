// Theme `theme-rd1`: RD1's soft look (flag redesign-rd1, job 368) on the screens RD1 drew: the list,
// a tick's trip question, the switcher sheet, the add sheet, More, Einstellungen, Läden, and the list at
// 200 % text. Screens only: the look is in pixels, so the proof is the PNGs (and the same journey on
// a build without the flag for today's look).
//
//   cd .cursor/skills/verify-snacklist && node journeys/theme-rd1.mjs <evidence dir> [--lang de|en] [--dark]
import process from 'node:process';
import { addField, addSheet, answerShopAsk, capture, flagOn, instance, logger, member, nextFrames, openApp, openTab, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: theme-rd1.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, page, L, errors } = await openApp(inst, { lang, dark, videoDir: dir });
let failed = null;
try {
  log(`build: redesign-rd1 ${flagOn('redesign-rd1') ? 'on (soft look)' : 'off (hex look)'}; ${lang}, ${dark ? 'dark' : 'light'}`);
  await signIn(page, L, user);
  await capture(page, dir, '01-list');

  const row = page.getByRole('checkbox').first();
  await reveal(page, row);
  await row.click();
  const takeBack = page.getByRole('button', { name: L('shopAskTakeBack'), exact: true });
  if (await takeBack.waitFor({ timeout: 4_000 }).then(() => true, () => false)) {
    await page.waitForTimeout(600);
    await capture(page, dir, '02-tick-question');
    await answerShopAsk(page, L, 'shopAskTakeBack');
    log('tick: the trip question came; taken back');
  } else {
    await capture(page, dir, '02-ticked');
    await row.click();
    log('tick: no trip question (snoozed or off); unticked');
  }

  await page.getByRole('button', { name: / · / }).first().click();
  await page.waitForTimeout(700);
  await capture(page, dir, '03-switcher');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(500);

  await typeInto(addField(page, L), lang === 'de' ? 'Mi' : 'Mi');
  await addSheet(page, L).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  await capture(page, dir, '04-add-sheet');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);

  await openTab(page, L, 'tabMore');
  await page.waitForTimeout(700);
  await capture(page, dir, '05-more');

  await page.getByRole('button', { name: L('settingsTitle'), exact: true }).first().click();
  await page.waitForTimeout(700);
  await capture(page, dir, '06-settings');
  await page.goBack();
  await openTab(page, L, 'tabList');

  await page.getByRole('button', { name: L('listEdit'), exact: true }).click();
  await page.waitForTimeout(700);
  await capture(page, dir, '07-stores');
  await page.goBack();
  await page.waitForTimeout(500);

  await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
  await page.waitForTimeout(800);
  await nextFrames(page);
  await capture(page, dir, '08-list-200');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
}
if (failed) {
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
console.log('PASS');
