// Feature list-declutter, `ld-voice` (job 248): the switcher sheet's one row for Siri, Alexa & KI,
// its household step and its list step, on a 320 × 568 phone. Back from the list step saves
// nothing; a list pick saves the household and the list on the server, and the row names both.
// Needs a build with VH_DEFINES="FLAGS_ON=list-declutter,default-list-voice-target". Adds a second
// household with a long name and two lists, and leaves it at the end.
//
//   node journeys/voice-default.mjs <evidence dir> [--lang de|en] [--dark] [--scale 2]
import process from 'node:process';
import { apiAs, capture, instance, logger, member, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'de');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
if (!dir) throw new Error('usage: voice-default.mjs <evidence dir> [--lang de|en] [--dark] [--scale 2]');

const de = lang === 'de';
const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const assert = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

const otherName = de ? 'Ferienwohnung Ostsee Familie Brandt' : 'Holiday flat by the sea, Brandt family';
const longList = de ? 'Wocheneinkauf für das ganze Wochenende' : 'Weekly shop for the whole long weekend';
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

for (const h of (await api.rpc('my_households')).data ?? []) {
  if (h.name === otherName) await api.rpc('leave_household', { p_household: h.id, p_archive: false });
}
const { data: made, error: madeError } = await api.rpc('create_household', {
  p_name: otherName,
  p_default_stores: false,
  p_stores: [],
  p_request_id: crypto.randomUUID(),
  p_kind: null,
});
if (madeError) throw madeError;
const other = typeof made === 'string' ? made : (made?.id ?? made?.household_id);
const longId = crypto.randomUUID();
{
  const { error } = await api.rpc('create_list', { p_household: other, p_name: longList, p_id: longId });
  if (error) throw error;
}
await api.rpc('set_default_household', { p_household: user.householdId });

const serverDefault = async () => {
  const { data, error } = await api.rpc('my_households');
  if (error) throw error;
  return data.find((h) => h.is_default)?.id;
};
const serverList = async (household) => (await api.rpc('default_list', { p_household: household })).data;
const listBefore = await serverList(other);
log(`${otherName}: lists ${JSON.stringify((await api.from('lists').select('name').eq('household_id', other)).data)}, pick ${listBefore}`);

const { browser, page, L, errors } = await openApp(inst, { lang, dark, viewport: { width: 320, height: 568 } });
const tag = `${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}`;
const shot = (name) => capture(page, dir, `${tag}-${name}`);
const voiceRow = () => page.getByRole('button', { name: new RegExp(`^${escape(L('voiceDefaultLabel'))}`) });
const backTo = (label) => page.getByRole('button', { name: L('switcherBack', { page: label }), exact: true });
const scrollTo = async (target) => {
  for (let i = 0; i < 12 && !(await target.isVisible().catch(() => false)); i++) {
    await page.mouse.move(160, 420);
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(250);
  }
  for (let i = 0; i < 4; i++) {
    await page.mouse.move(160, 420);
    await page.mouse.wheel(0, 1000);
    await page.waitForTimeout(400);
  }
};

let failed = null;
try {
  await signIn(page, L, user);
  // Larger text only after signing in: the analytics question's buttons would sit below the fold.
  if (scale !== 1) await page.evaluate((s) => { document.documentElement.style.fontSize = `${s * 100}%`; }, scale);
  await page.waitForTimeout(800);
  await page.getByRole('button', { name: /·/ }).first().click();
  await backTo(L('switcherHouseholds')).click();
  await page.getByRole('button', { name: L('newHousehold'), exact: true }).waitFor({ timeout: 10_000 });
  await scrollTo(voiceRow());
  const rowName = await voiceRow().getAttribute('aria-label').catch(() => null) ?? (await voiceRow().ariaSnapshot());
  log(`row: ${rowName}`);
  await shot('01-row');

  await voiceRow().click();
  await page.getByText(L('voiceDefaultTitle'), { exact: true }).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);
  await shot('02-households');

  const otherRow = page.getByRole('button', { name: new RegExp(`^${escape(otherName)}`) });
  await scrollTo(otherRow);
  await otherRow.click();
  await page.getByText(L('defaultListTitle'), { exact: true }).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);
  await shot('03-lists');

  await backTo(L('voiceDefaultBack')).click();
  await page.getByText(L('voiceDefaultTitle'), { exact: true }).waitFor({ timeout: 10_000 });
  assert(await serverDefault() === user.householdId, 'back from the list step: the default household is unchanged on the server');
  assert(await serverList(other) === listBefore, 'back from the list step: the list pick is unchanged on the server');

  await scrollTo(otherRow);
  await otherRow.click();
  await page.getByText(L('defaultListTitle'), { exact: true }).waitFor({ timeout: 10_000 });
  const listRow = page.getByRole('button', { name: new RegExp(`^${escape(longList)}`) });
  await scrollTo(listRow);
  await listRow.click();
  await page.getByRole('button', { name: L('newHousehold'), exact: true }).waitFor({ timeout: 10_000 });
  assert(await serverDefault() === other, `the default household is ${otherName} on the server`);
  assert(await serverList(other) === longId, `its list for Siri, Alexa & AI is ${longList} on the server`);
  await scrollTo(voiceRow());
  await page.waitForTimeout(800);
  const after = (await voiceRow().ariaSnapshot());
  log(`row after: ${after}`);
  const heard = [L('voiceDefaultHouseholdName', { household: otherName }), L('defaultListRow', { list: longList })];
  assert(heard.every((part) => after.includes(part)), `the row names the new household and list as ${JSON.stringify(heard)}`);
  await shot('04-saved');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, `${tag}-99-failure`).catch(() => {});
} finally {
  await browser.close();
  await api.rpc('set_default_household', { p_household: user.householdId });
  await api.rpc('leave_household', { p_household: other, p_archive: false });
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
