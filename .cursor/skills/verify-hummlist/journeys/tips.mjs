// Feature tips (job 168b: trigger hints), entry point the List tab after sign-in. Proves More → Tipps
// lists the hints, a hint shows 10 s after a start once the checklist is gone, the X hides it with
// the „Alle Tipps unter Mehr → Tipps.“ note and stores it on this device, and the next start shows
// no new hint (one new hint per 24 h). Needs a demo household with 5 or more open items.
//
//   node journeys/tips.mjs <evidence dir> [--lang de|en] [--dark]
import process from 'node:process';
import { capture, instance, logger, member, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: tips.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const { browser, page, L, errors } = await openApp(inst, { lang, dark, videoDir: dir });
let failed = null;
try {
  // signIn hides the checklist, which takes this session's slot: hints wait for the next start.
  await signIn(page, L, user);
  const stored = () => page.evaluate(() => Object.entries(localStorage).filter(([k]) => k.includes('hints.')));
  // A hint's title and text are one merged semantics node, and a snackbar's text is announced
  // and cleared, so both are read from the ARIA snapshot.
  const aria = () => page.locator('body').ariaSnapshot();
  const until = async (test, what, timeout) => {
    for (const end = Date.now() + timeout; Date.now() < end; await page.waitForTimeout(250)) {
      if (await test()) return;
    }
    throw new Error(`${what} not seen after ${timeout} ms`);
  };
  const dismiss = page.getByRole('button', { name: L('tipDismiss') });

  await page.goto('/more/tips');
  await until(async () => (await aria()).includes(`${L('tipEditTitle')} `), 'the Tipps page', 15_000);
  log(`More → ${L('hintsTitle')} lists „${L('tipEditTitle')}“ (${lang}${dark ? ', dark' : ''})`);
  await capture(page, dir, '01-tips-page');

  await page.goto('/');
  await until(async () => (await dismiss.count()) > 0, 'a hint 10 s after the start', 25_000);
  log(`a hint shows: ${JSON.stringify(await stored())}`);
  await capture(page, dir, '02-hint');

  await dismiss.first().click();
  await until(async () => (await aria()).includes(L('hintDismissedNotice')), 'the note', 3_000);
  log(`X: „${L('hintDismissedNotice')}“`);
  await capture(page, dir, '03-dismissed');
  await until(async () => (await dismiss.count()) === 0, 'the hint gone', 5_000);

  await page.reload();
  await page.waitForTimeout(15_000);
  if ((await dismiss.count()) > 0) throw new Error('a new hint showed within 24 h');
  log(`after a reload and 15 s no new hint: ${JSON.stringify(await stored())}`);
  await capture(page, dir, '04-next-start');
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
log(`PASS tips (evidence: ${dir})`);
