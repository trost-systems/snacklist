// Feature list-declutter (job 229, flag `list-declutter`): the switcher in the see-through header,
// the total as a row, and the switcher sheet's three levels with the members page. Long-press then
// drag reorders a list and a household by touch, checked on the server. Needs a build with
// VH_DEFINES="FLAGS_ON=list-declutter,prices-and-trip-total". Adds two lists, a second household
// and an open person invite for the first member, and removes them at the end.
//
//   node journeys/list-declutter.mjs <evidence dir> [--lang de|en] [--dark] [--scale 1.3]
import process from 'node:process';
import { apiAs, capture, instance, logger, member, openApp, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'de');
const dark = rest.includes('--dark');
const scale = Number(arg('--scale', '1'));
if (!dir) throw new Error('usage: list-declutter.mjs <evidence dir> [--lang de|en] [--dark] [--scale 1.3]');

const de = lang === 'de';
const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const assert = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

const listNames = de ? ['Drogerie', 'Grillabend am Samstag bei Oma Hildegard'] : ['Drugstore', 'Barbecue on Saturday at Grandma Hildegard’s'];
const otherName = de ? 'Ferienhaus Ostsee' : 'Holiday cottage';
const made = { lists: [], household: null, invite: null };
// What an earlier run that stopped half-way left behind.
for (const { id } of (await api.from('lists').select('id').eq('household_id', user.householdId).in('name', listNames)).data ?? []) {
  await api.rpc('delete_list', { p_list: id });
}
for (const name of listNames) {
  const id = crypto.randomUUID();
  const { error } = await api.rpc('create_list', { p_household: user.householdId, p_name: name, p_id: id });
  if (error) throw error;
  made.lists.push(id);
}
{
  const { data, error } = await api.rpc('create_household', {
    p_name: otherName,
    p_default_stores: false,
    p_stores: [],
    p_request_id: crypto.randomUUID(),
    p_kind: null,
  });
  if (error) throw error;
  made.household = typeof data === 'string' ? data : (data?.id ?? data?.household_id ?? null);
}
{
  const { data, error } = await api.rpc('create_invite', { p_household: user.householdId, p_kind: 'person' });
  if (error) throw error;
  made.invite = (Array.isArray(data) ? data[0] : data)?.id ?? null;
}
// create_household shows the new household on next start; the drive starts in the seeded one.
await api.rpc('set_default_household', { p_household: user.householdId });

const { data: home } = await api.from('households').select('name').eq('id', user.householdId).single();
const homeName = home.name;

const order = async () => {
  const { data, error } = await api.from('lists').select('name, position').eq('household_id', user.householdId).order('position');
  if (error) throw error;
  return data.map((l) => l.name);
};
const households = async () => {
  const { data, error } = await api.rpc('my_households');
  if (error) throw error;
  return data.map((h) => h.name);
};

const { browser, context, page, L, errors } = await openApp(inst, { lang, dark });
// The switcher's name is "<list> · <household>".
const switcher = () => page.getByRole('button', { name: new RegExp(` · ${homeName}$`) }).first();
if (scale !== 1) await context.addInitScript((s) => {
  document.addEventListener('DOMContentLoaded', () => { document.documentElement.style.fontSize = `${s * 100}%`; });
}, scale);
const tag = `${lang}-${dark ? 'dark' : 'light'}-${Math.round(scale * 100)}`;
const shot = (name) => capture(page, dir, `${tag}-${name}`);
const cdp = await context.newCDPSession(page);
const touch = (type, x, y) =>
  cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
/** Holds the centre of `locator` 700 ms, drags it by `dy` px in steps, lets go. */
const holdAndDrag = async (locator, dy) => {
  const box = await locator.boundingBox();
  const x = box.x + box.width / 3;
  const y = box.y + box.height / 2;
  await touch('touchStart', x, y);
  await page.waitForTimeout(700);
  for (let i = 1; i <= 12; i++) {
    await touch('touchMove', x, y + (dy * i) / 12);
    await page.waitForTimeout(30);
  }
  await page.waitForTimeout(150);
  await touch('touchEnd', x, y + dy);
  await page.waitForTimeout(800);
};

let failed = null;
try {
  await signIn(page, L, user);
  await page.waitForTimeout(800);
  await shot('01-list');
  assert((await page.getByRole('tab', { name: listNames[0] }).count()) === 0, 'no list tabs under the header');

  await page.mouse.move(195, 500);
  await page.mouse.wheel(0, 260);
  await page.waitForTimeout(600);
  await shot('02-list-scrolled');
  await page.mouse.wheel(0, 4000);
  await page.waitForTimeout(600);
  await shot('03-list-end-total');

  const shownBefore = await switcher().ariaSnapshot();
  await switcher().click();
  const invite = page.getByRole('button', { name: L('switcherInvite'), exact: true });
  await invite.waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);
  await shot('04-sheet-household');

  const before = await order();
  const row = page.getByRole('button', { name: new RegExp(`^${listNames[0]}`) }).first();
  const rowBox = await row.boundingBox();
  await holdAndDrag(row, -rowBox.height * 1.1);
  const after = await order();
  log(`lists before ${JSON.stringify(before)} after ${JSON.stringify(after)}`);
  assert(after.indexOf(listNames[0]) === before.indexOf(listNames[0]) - 1, 'long-press drag moved the list up one place on the server');
  await page.keyboard.press('Escape');
  await invite.waitFor({ state: 'detached', timeout: 10_000 });
  assert((await switcher().ariaSnapshot()) === shownBefore, `the list on screen is still "${shownBefore}"`);
  await switcher().click();
  await invite.waitFor({ timeout: 10_000 });

  await page.getByRole('button', { name: new RegExp(de ? 'Mitglied' : 'member') }).first().click();
  await page.getByRole('heading', { name: L('householdMembersTitle') }).or(page.getByText(L('householdMembersTitle'), { exact: true })).first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  await shot('05-sheet-members');

  // Job 242: „Leute einladen“ is a page of the same sheet, back leads to the members.
  // In German the barrier and the drag handle are „Schließen“ too: the ✕ is
  // the small one at the right.
  const closeButton = async () => {
    const all = page.getByRole('button', { name: L('close'), exact: true });
    let found = null;
    for (let i = 0; i < await all.count(); i++) {
      const box = await all.nth(i).boundingBox();
      if (box && box.width < 100 && box.x > (found?.box.x ?? 195)) found = { box, at: all.nth(i) };
    }
    return found?.at ?? null;
  };
  await page.getByRole('button', { name: L('inviteSheetTitle'), exact: true }).click();
  await page.getByRole('button', { name: L('newInvite'), exact: true }).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  const backToMembers = page.getByRole('button', { name: L('switcherBack', { page: L('householdMembersTitle') }), exact: true });
  assert((await backToMembers.count()) === 1, 'the invite page goes back to the members');
  assert((await closeButton()) !== null, 'the sheet has Schließen');
  await shot('05b-sheet-invite');
  await page.mouse.move(195, 600);
  await page.mouse.wheel(0, 4000);
  await page.waitForTimeout(800);
  const closeBox = await (await closeButton())?.boundingBox();
  assert(closeBox && closeBox.y >= 0, `Schließen stays in view after scrolling the invite page (${JSON.stringify(closeBox)})`);
  await shot('05c-sheet-invite-end');
  await backToMembers.click();
  await page.getByRole('heading', { name: L('householdMembersTitle') }).or(page.getByText(L('householdMembersTitle'), { exact: true })).first().waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);

  await page.getByRole('button', { name: new RegExp(`^${L('switcherBack', { page: '' }).trim()}`) }).first().click();
  await invite.waitFor({ timeout: 10_000 });
  await page.getByRole('button', { name: new RegExp(`^${L('switcherBack', { page: '' }).trim()}`) }).first().click();
  await page.getByRole('button', { name: L('newHousehold'), exact: true }).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(500);
  await shot('06-sheet-households');

  const hhBefore = await households();
  const hhRow = page.getByRole('button', { name: new RegExp(`^${otherName}`) }).first();
  const hhBox = await hhRow.boundingBox();
  await holdAndDrag(hhRow, -hhBox.height * 1.1);
  const hhAfter = await households();
  log(`households before ${JSON.stringify(hhBefore)} after ${JSON.stringify(hhAfter)}`);
  assert(hhAfter[0] === otherName, 'long-press drag put the other household first on the server');
  await shot('07-sheet-households-reordered');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, `${tag}-99-failure`).catch(() => {});
} finally {
  await browser.close();
  for (const id of made.lists) await api.rpc('delete_list', { p_list: id });
  if (made.invite) await api.rpc('revoke_invite', { p_invite: made.invite });
  if (made.household) await api.rpc('leave_household', { p_household: made.household, p_archive: false });
  await api.rpc('reorder_households', { p_households: [user.householdId] });
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
