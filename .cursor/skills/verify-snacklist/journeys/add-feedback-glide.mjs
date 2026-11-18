// Feature quick-add, sub-feature qa-feedback-list (flag add-feedback-list, job 276), on
// demo-familie: the glide frame by frame. Playwright's clock drives the web build's frames, so each
// shot is an exact time after the tap: the list going behind the opening sheet, an add, and the
// list gliding back into its stores and categories when the sheet closes. Writes
// open-<ms>.png and close-<ms>.png and a contact strip per motion (needs ffmpeg).
//
//   on a plain launch (add-feedback-list rolls out in full, so launch.sh turns it on), or with
//   VH_DEFINES="FLAGS_ON=input-stable-rows"
//   node journeys/add-feedback-glide.mjs <evidence dir> [--lang de|en]
import { execFileSync } from 'node:child_process';
import process from 'node:process';
import { addField, addSheet, apiAs, instance, logger, member, openApp, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: add-feedback-glide.mjs <evidence dir> [--lang de|en]');
const frame = 16;
const times = [0, 48, 96, 144, 192, 240, 304, 400];

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const forget = async () => {
  const { error } = await api.from('items').delete().eq('household_id', user.householdId).eq('name', 'Kefir');
  if (error) throw new Error(error.message);
};
await forget();

const { browser, page, L, errors } = await openApp(inst, { lang });
const installed = Date.now();
await page.clock.install({ time: installed });
let failed = null;

/** Pauses the app's clock on its 16 ms frame grid, half a second from now. */
const pause = async () => {
  const now = await page.evaluate(() => Date.now());
  const steps = Math.ceil((now - installed + 500) / frame);
  await page.clock.pauseAt(installed + steps * frame);
};

/** Taps [point], then shoots the frames at [times] after it. */
const film = async (name, point) => {
  await pause();
  await page.mouse.click(point.x, point.y);
  let at = 0;
  const shots = [];
  for (const t of times) {
    if (t > at) await page.clock.runFor(t - at);
    at = t;
    const file = `${dir}/${name}-${String(t).padStart(3, '0')}.png`;
    await page.screenshot({ path: file });
    shots.push(file);
  }
  await page.clock.resume();
  execFileSync('ffmpeg', ['-v', 'error', '-y', ...shots.flatMap((f) => ['-i', f]), '-filter_complex', `${shots.map((_, i) => `[${i}:v]scale=260:-1[s${i}]`).join(';')};${shots.map((_, i) => `[s${i}]`).join('')}hstack=inputs=${shots.length}`, `${dir}/${name}-strip.png`]);
  log(`${name}: frames at ${times.join(', ')} ms after the tap, strip ${name}-strip.png`);
};

const centre = async (locator) => {
  const box = await locator.boundingBox();
  if (!box) throw new Error('nothing to tap');
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
};

try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} on ${inst.webUrl}; clock installed`);
  await film('open', await centre(addField(page, L)));
  await typeInto(addField(page, L), 'Kefir', { perKey: 60 });
  const typed = addSheet(page, L).getByRole('button', { name: new RegExp(`^Kefir, ${L('suggestionTyped')}`) }).first();
  await typed.click();
  await addSheet(page, L).getByRole('textbox', { name: L('itemQuantity') }).waitFor({ timeout: 5000 });
  await page.waitForTimeout(800);
  await film('close', await centre(addSheet(page, L).getByRole('button', { name: L('close'), exact: true })));
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await page.screenshot({ path: `${dir}/99-failure.png` }).catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  await forget();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS add-feedback-glide (evidence: ${dir})`);
