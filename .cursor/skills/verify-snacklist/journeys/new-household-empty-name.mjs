// Feature household-invites, sub-feature switcher: „Neuer Haushalt“ submitted with an empty name
// from the button below the store chips. Proves the list scrolls back to the name field, the error
// shows once (under the field, not again above the button), typing lands in the field and clears
// it, and no household is made.
//
//   node journeys/new-household-empty-name.mjs <evidence dir> [--lang de|en] [--height 560] [--reduced-motion]
//
// A short --height puts the field out of view at the button; --reduced-motion jumps instead of
// scrolling (an animation of zero length threw before job 231's review fix).
import process from 'node:process';
import { apiAs, capture, instance, logger, member, openApp, openHouseholds, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const height = Number(opt('height', 844));
const still = rest.includes('--reduced-motion');
if (!dir) throw new Error('usage: new-household-empty-name.mjs <evidence dir> [--lang de|en] [--height px] [--reduced-motion]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const households = async () => {
  const { count, error } = await api.from('household_members').select('household_id', { count: 'exact', head: true }).eq('user_id', user.id);
  if (error) throw error;
  return count;
};
const { browser, page, L, errors } = await openApp(inst, { lang, viewport: { width: 390, height }, videoDir: dir });
let failed = null;
try {
  if (still) await page.emulateMedia({ reducedMotion: 'reduce' });
  await signIn(page, L, user);
  const before = await households();
  const { data: shown, error } = await api.from('households').select('name').eq('id', user.householdId).single();
  if (error) throw error;
  log(`signed in as ${user.handle} (${lang}${still ? ', reduced motion' : ''}), in ${before} households`);

  await openHouseholds(page, L, shown.name);
  const newHousehold = page.getByRole('button', { name: L('newHousehold'), exact: true });
  await page.mouse.move(195, height / 2);
  for (let i = 0; i < 20 && !(await newHousehold.count() && (await newHousehold.boundingBox())?.y < height - 84); i++) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(200);
  }
  await newHousehold.click();
  const field = page.getByRole('textbox', { name: L('householdName') });
  await field.waitFor({ timeout: 10_000 });

  const create = page.getByRole('button', { name: L('createHousehold'), exact: true });
  await page.mouse.move(195, height / 2);
  for (let i = 0; i < 20 && !(await create.count() && (await create.boundingBox())?.y < height - 84); i++) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(200);
  }
  const away = await field.count() ? await field.boundingBox() : null;
  log(`scrolled to „${L('createHousehold')}“; name field ${away ? `at y=${Math.round(away.y)}` : 'not in the page'} (viewport ${height})`);
  await capture(page, dir, '01-at-the-button');
  await create.click();
  await page.waitForTimeout(1_000);
  await capture(page, dir, '02-after-empty-submit');

  const message = L('householdNameInvalid');
  const texts = await page.getByText(message, { exact: true }).count();
  const fieldBox = await field.count() ? await field.boundingBox() : null;
  const tree = await page.locator('body').ariaSnapshot();
  const mentions = tree.split('\n').filter((l) => l.includes(message));
  log(`„${message}“: ${texts} visible text(s); in the ARIA tree: ${mentions.map((l) => l.trim()).join(' | ')}`);
  log(`name field ${fieldBox ? `on screen at y=${Math.round(fieldBox.y)}` : 'not in the page'}`);
  await page.keyboard.type('Abc');
  await page.waitForTimeout(500);
  const typed = await field.inputValue();
  const left = await page.getByText(message, { exact: true }).count();
  log(`typed "Abc" without a click: the field holds "${typed}", the error shows ${left} times`);
  await capture(page, dir, '03-typed');
  const after = await households();
  log(`database: in ${after} households`);
  if (texts !== 1) throw new Error(`the error shows ${texts} times, not once`);
  if (!fieldBox || fieldBox.y < 0 || fieldBox.y + fieldBox.height > height) throw new Error('the name field is not on screen after the submit');
  if (typed !== 'Abc') throw new Error(`typing after the submit did not reach the field (it holds "${typed}")`);
  if (left !== 0) throw new Error('the error stays after typing a name');
  if (after !== before) throw new Error('an empty name made a household');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
console.log('PASS');
