// Feature onboarding, the step transition (job 454, T1): signed out, through the usage question to
// „Mit wem“, then frames of who → name, name → stores (the field focused first) and Back to name,
// on Playwright's paused clock, joined into strips. Checks on the web build: Weiter leaves the
// name field unfocused, the new step's heading has the DOM focus once it settles, and one „Weiter“
// is in the accessibility tree mid-slide. With --reduced the browser asks for reduced motion
// (prefers-reduced-motion, which the web engine reports as both disableAnimations and reduceMotion).
// Needs no seeded household and signs nobody up.
//
//   node journeys/onboarding-t1.mjs <evidence dir> [--lang de|en] [--reduced]
import { execFileSync } from 'node:child_process';
import process from 'node:process';
import { instance, logger, openApp } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const reduced = rest.includes('--reduced');
if (!dir) throw new Error('usage: onboarding-t1.mjs <evidence dir> [--lang de|en] [--reduced]');
const frame = 16;
const times = reduced ? [0, 32, 64, 96, 128, 160] : [0, 48, 96, 144, 192, 240, 304, 400];

const log = logger(dir);
const inst = instance();
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

const { browser, page, L, errors } = await openApp(inst, { lang, locale: lang === 'en' ? 'en-DE' : 'de-DE' });
if (reduced) await page.emulateMedia({ reducedMotion: 'reduce' });
const installed = Date.now();
await page.clock.install({ time: installed });
const button = (name) => page.getByRole('button', { name, exact: true });
let failed = null;

const pause = async () => {
  const now = await page.evaluate(() => Date.now());
  await page.clock.pauseAt(installed + Math.ceil((now - installed + 500) / frame) * frame);
};
const centre = async (locator) => {
  const box = await locator.boundingBox();
  if (!box) throw new Error('nothing to tap');
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
};
const active = () => page.evaluate(() => {
  const el = document.activeElement;
  return { tag: el?.tagName ?? '', text: (el?.textContent ?? '').trim(), label: el?.getAttribute('aria-label') ?? '' };
});

/** Taps [locator] on the paused clock and shoots [times]; returns what was checked mid-way. */
const film = async (name, locator) => {
  const point = await centre(locator);
  await pause();
  await page.mouse.click(point.x, point.y);
  let at = 0;
  const shots = [];
  let mid = null;
  for (const t of times) {
    if (t > at) await page.clock.runFor(t - at);
    at = t;
    const file = `${dir}/${name}-${String(t).padStart(3, '0')}.png`;
    await page.screenshot({ path: file });
    shots.push(file);
    if (t === times[2]) {
      mid = { nexts: await button(L('onboardingNext')).count(), focus: await active() };
    }
  }
  await page.clock.resume();
  execFileSync('ffmpeg', ['-v', 'error', '-y', ...shots.flatMap((f) => ['-i', f]), '-filter_complex', `${shots.map((_, i) => `[${i}:v]scale=260:-1[s${i}]`).join(';')};${shots.map((_, i) => `[s${i}]`).join('')}hstack=inputs=${shots.length}`, `${dir}/${name}-strip.png`]);
  log(`${name}: frames at ${times.join(', ')} ms after the tap, strip ${name}-strip.png`);
  await page.waitForTimeout(600);
  return mid;
};
const headingFocused = async (key) => {
  const focus = await active();
  check(focus.text.includes(L(key)) || focus.label.includes(L(key)), `focus on the heading „${L(key)}“ (${focus.tag} ${focus.label} ${focus.text.slice(0, 40)})`);
};

try {
  await page.goto('/');
  await page.waitForURL(/\/start(\?|$)/, { timeout: 30_000 });
  await button(L('startGo')).click();
  await page.waitForURL(/\/start\/usage/);
  await button(L('analyticsDecline')).click();
  await page.waitForURL(/\/start\/who/);
  await page.getByRole('checkbox', { name: L('kindPartner') }).click();
  await page.waitForTimeout(400);

  const whoMid = await film('who-to-name', button(L('onboardingNext')));
  await page.waitForURL(/\/start\/name/);
  check(whoMid.nexts === 1, `one „${L('onboardingNext')}“ in the accessibility tree mid-change (${whoMid.nexts})`);
  await headingFocused('nameTitle');

  const field = page.getByRole('textbox', { name: new RegExp(`^${L('householdName')}`) });
  await field.click();
  await page.waitForTimeout(400);
  check((await active()).tag === 'INPUT', 'the name field has the focus before Weiter');
  const nameMid = await film('name-to-stores', button(L('onboardingNext')));
  await page.waitForURL(/\/start\/stores/);
  check(nameMid.focus.tag !== 'INPUT', `the field lost the focus mid-change (${nameMid.focus.tag})`);
  await headingFocused('storesStepTitle');

  await film('stores-back-to-name', page.getByRole('button', { name: lang === 'en' ? 'Back' : 'Zurück', exact: true }).first());
  await page.waitForURL(/\/start\/name/);
  await headingFocused('nameTitle');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await page.screenshot({ path: `${dir}/99-failure.png` }).catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS onboarding-t1${reduced ? ' (reduced motion)' : ''} (evidence: ${dir})`);
