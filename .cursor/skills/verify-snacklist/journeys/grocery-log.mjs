// Feature grocery-log (job 199), launched with VH_DEFINES="FLAGS_ON=grocery-log,prices-and-trip-total,trip-mode"
// (off for users since 2026-11-22, Peter HP2, job 401; a plain launch has no Verlauf tab, so it
// fails there). Entry points the Verlauf tab and the list after a tick.
// Seeds Lidl and Rewe and a known set of trips through save_trip (fixed ids, so a rerun upserts
// them), then proves gl-calendar (a 3-trip and a 5-trip day), gl-day-filter, gl-journal,
// gl-view-toggle with its persistence over a reload, gl-store-timeline, gl-free-window (a 40-day-old
// trip locked for a Free member), gl-sheet (add by hand, edit, delete, checked through
// trip_history) and gl-no-card (no inline card after a store's last open item is ticked). With --compact only the 358 px checks run.
//
//   node journeys/grocery-log.mjs <evidence dir> [--lang de|en] [--dark] [--compact]
import { createHash } from 'node:crypto';
import process from 'node:process';
import { accessibleName, apiAs, capture, instance, itemRow, logger, member, openApp, openTab, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
const dark = rest.includes('--dark');
const compact = rest.includes('--compact');
if (!dir) throw new Error('usage: grocery-log.mjs <evidence dir> [--lang de|en] [--dark] [--compact]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
const household = user.householdId;
const locale = lang === 'en' ? 'en-US' : 'de-DE';
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

// Days as the app sees them: the browser runs in Europe/Berlin.
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(new Date());
const daysAgo = (n) => {
  const [y, m, d] = today.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d - n)).toISOString().slice(0, 10);
};
const asDate = (wire) => new Date(`${wire}T12:00:00Z`);
// DateFormat.MMMMEEEEd and MMMMd, as the calendar's labels and the filter heading use them.
const longDay = (wire) => new Intl.DateTimeFormat(locale, { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(asDate(wire));
const monthDay = (wire) => new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', timeZone: 'UTC' }).format(asDate(wire));
// The journal's section for a day, as the app groups it: weeks start on Monday, older ones by month.
const mondayOf = (wire) => asDate(wire).getTime() - ((asDate(wire).getUTCDay() + 6) % 7) * 864e5;
const journalSection = (wire) => {
  const weeks = Math.round((mondayOf(today) - mondayOf(wire)) / (7 * 864e5));
  return weeks <= 0 ? L('historyThisWeek') : weeks === 1 ? L('historyLastWeek') : monthTitle(wire);
};
const plural = (template, count) => template
  .replace(/\{count, plural, =1\{([^}]*)\} other\{([^{}]*(?:\{count\}[^{}]*)*)\}\}/, (_, one, other) => (count === 1 ? one : other))
  .replaceAll('{count}', String(count));

// A fixed id per household and slot: a rerun saves the same trips again instead of adding more.
const tripId = (slot) => {
  const h = createHash('sha1').update(`grocery-log-journey:${household}:${slot}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};

async function rpc(name, params) {
  const { data, error } = await api.rpc(name, params);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function storeId(name) {
  const { data, error } = await api.from('stores').select('id, name').eq('household_id', household);
  if (error) throw error;
  return data.find((s) => s.name === name)?.id ?? rpc('add_store', { p_household: household, p_name: name });
}

const lidl = await storeId('Lidl');
const rewe = await storeId('Rewe');
const threeDay = daysAgo(2);
const fiveDay = daysAgo(8);
const lastMonthDay = daysAgo(20);
const oldDay = daysAgo(40);
const seeds = [
  ['yesterday', lidl, daysAgo(1), ['Haferflocken', 'Bananen']],
  ['three-1', lidl, threeDay, ['Kaffee', 'Zucker']],
  ['three-2', lidl, threeDay, ['Spinat']],
  ['three-3', rewe, threeDay, ['Rotwein', 'Oliven', 'Feta', 'Ciabatta']],
  ['five-1', lidl, fiveDay, ['Quark']],
  ['five-2', rewe, fiveDay, ['Lachs']],
  ['five-3', lidl, fiveDay, ['Gurken']],
  ['five-4', rewe, fiveDay, ['Basilikum']],
  ['five-5', lidl, fiveDay, ['Mehl']],
  ['last-month', rewe, lastMonthDay, ['Kürbis', 'Ingwer']],
  ['old', lidl, oldDay, ['Sauerkraut']],
];
const seedIds = new Set(seeds.map(([slot]) => tripId(slot)));
const history = () => rpc('trip_history', { p_household: household, p_today: today });

for (const trip of (await history()).trips) {
  if (!seedIds.has(trip.id)) await rpc('delete_trip', { p_id: trip.id });
}
for (const [slot, store, day, names] of seeds) {
  await rpc('save_trip', { p_household: household, p_id: tripId(slot), p_store: store, p_day: day, p_items: names.map((name) => ({ name, quantity: null })) });
}
const prompted = ['Butter', 'Nudeln', 'Reis'];
{
  const { error } = await api.from('items').update({ status: 'active', bought_by: null, bought_at: null, store_id: lidl })
    .eq('household_id', household).in('name', prompted);
  if (error) throw error;
  // Only these three may be open at Lidl, or ticking them never empties it (trip-mode.mjs puts the seeded items over Lidl and Rewe).
  const { error: off } = await api.from('items').update({ store_id: null })
    .eq('household_id', household).eq('store_id', lidl).eq('status', 'active').not('name', 'in', `(${prompted.join(',')})`);
  if (off) throw off;
}
const seeded = await history();
log(`seeded ${seeds.length} trips (today ${today}; 3 on ${threeDay}, 5 on ${fiveDay}, 1 on ${oldDay}); trip_history: premium=${seeded.premium} since=${seeded.since} locked=${seeded.locked} trips=${seeded.trips.length}`);
check(seeded.premium === false && seeded.locked === 1 && seeded.since === daysAgo(27), `${user.handle} is Free: since ${daysAgo(27)}, the 40-day-old trip is the 1 locked one`);
check(!seeded.trips.some((t) => t.id === tripId('old')), 'trip_history leaves the 40-day-old trip out');

const viewport = compact ? { width: 358, height: 760 } : undefined;
const { browser, page, L, errors } = await openApp(inst, { lang, dark, videoDir: dir, ...(viewport && { viewport }) });
const aria = () => page.locator('body').ariaSnapshot();
const until = async (test, what, timeout = 10_000) => {
  for (const end = Date.now() + timeout; Date.now() < end; await page.waitForTimeout(200)) {
    if (await test()) return;
  }
  throw new Error(`${what} not seen after ${timeout} ms`);
};
// Off every control first: a hovered button's tooltip or highlight is not part of the state.
const shot = async (name) => {
  await page.mouse.move(1, 1);
  await page.waitForTimeout(500);
  return capture(page, dir, name);
};
const button = (name) => page.getByRole('button', { name, exact: true });
const tile = (item) => page.getByRole('button', { name: new RegExp(escape(item)) });
const dayButton = (wire) => page.getByRole('button', { name: new RegExp(`^${escape(longDay(wire))}(,|$)`) });
const sheet = (title) => page.getByRole('group', { name: title, exact: true });
// A hovered tooltip adds its text to the name once more, so the toggle is matched by its start.
const toStores = () => page.getByRole('button', { name: new RegExp(`^${escape(L('historyShowByStore'))}`) });
const toDates = () => page.getByRole('button', { name: new RegExp(`^${escape(L('historyShowByDate'))}`) });
const monthTitle = (wire) => new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(asDate(wire));
const monthButton = (key) => page.getByRole('button', { name: new RegExp(`^${escape(L(key))}`) });
// The month the calendar shows: the heading level with its month buttons. The journal also titles its
// sections older than last week by month, so a month's name alone can be either. null: no calendar built.
async function calendarMonth() {
  const prev = await monthButton('previousMonth').boundingBox().catch(() => null);
  if (!prev) return null;
  for (const heading of await page.getByRole('heading').all()) {
    const b = await heading.boundingBox();
    if (b && b.y < prev.y + prev.height && b.y + b.height > prev.y) return accessibleName(await heading.ariaSnapshot());
  }
  return null;
}
// A journal section shows: its heading once more than the calendar's own, when the calendar shows that month.
const sectionShown = async (title) => {
  const headings = (await aria()).split('\n').filter((line) => line.trim().startsWith(`- heading "${title}"`)).length;
  return headings > ((await calendarMonth()) === title ? 1 : 0);
};

// The calendar reaches back at most a few months here: the seeds span 40 days.
const monthsBack = [0, 1, 2, 3].map((k) => {
  const [y, m] = today.split('-').map(Number);
  return new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1 - k, 15)));
});
async function showMonthOf(wire) {
  const want = monthTitle(wire);
  for (let i = 0; i < 4; i++) {
    const shown = await calendarMonth();
    if (shown === want) return;
    await monthButton(monthsBack.indexOf(shown) > monthsBack.indexOf(want) ? 'nextMonth' : 'previousMonth').click();
    await page.waitForTimeout(300);
  }
  await until(async () => (await calendarMonth()) === want, `the calendar on ${want}`, 5_000);
}

async function boxesApart(locators, what) {
  const boxes = [];
  for (const [name, locator] of locators) boxes.push([name, await locator.boundingBox()]);
  const vw = page.viewportSize().width;
  for (const [name, b] of boxes) check(b && b.x >= 0 && b.x + b.width <= vw + 0.5, `${what}: ${name} inside the ${vw} px width (${b && Math.round(b.x)}..${b && Math.round(b.x + b.width)})`);
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const [na, a] = boxes[i];
      const [nb, b] = boxes[j];
      const overlap = a.x < b.x + b.width - 0.5 && b.x < a.x + a.width - 0.5 && a.y < b.y + b.height - 0.5 && b.y < a.y + a.height - 0.5;
      check(!overlap, `${what}: ${na} and ${nb} do not overlap`);
    }
  }
}

let failed = null;
try {
  await signIn(page, L, user);
  log(`signed in as ${user.handle} (${lang}${dark ? ', dark' : ''}${compact ? ', 358 px' : ''}) on ${inst.webUrl}`);
  const tabs = page.getByRole('tab');
  check((await tabs.count()) === 3, `the flag shows three tabs: ${(await page.getByRole('tablist').ariaSnapshot()).replace(/\s*\n\s*/g, ' ')}`);

  await openTab(page, L, 'tabHistory');
  await until(async () => (await calendarMonth()) === monthTitle(today), 'the calendar on this month', 15_000);
  if (await toDates().count()) await toDates().click();
  await toStores().waitFor({ timeout: 5_000 });
  await shot('01-journal-calendar');
  const three = await dayButton(threeDay).ariaSnapshot();
  check(three.includes(plural(L('historyDayLabel', { date: longDay(threeDay) }), 3)), `the 3-trip day reads „${plural(L('historyDayLabel', { date: longDay(threeDay) }), 3)}“`);

  if (compact) {
    await boxesApart([
      ['tab List', page.getByRole('tab', { name: L('tabList'), exact: true })],
      [`tab ${L('tabHistory')}`, page.getByRole('tab', { name: L('tabHistory'), exact: true })],
      ['tab More', page.getByRole('tab', { name: L('tabMore'), exact: true })],
    ], 'tab bar');
    await boxesApart([
      ['title', page.getByRole('heading', { name: L('tabHistory'), exact: true }).first()],
      ['view toggle', toStores()],
      ['add', button(L('tripAdd'))],
    ], 'app bar');
    const cells = await page.getByRole('button', { name: new RegExp(`^${escape(longDay(today))}`) }).boundingBox();
    check(cells.width >= 40, `a calendar day cell is ${Math.round(cells.width)} px wide at 358 px`);
    await reveal(page, tile('Rotwein'));
    await shot('02-compact-journal');
    await toStores().click();
    await toDates().waitFor();
    await shot('03-compact-stores');
    await toDates().click();
    await button(L('tripAdd')).click();
    await sheet(L('tripAdd')).waitFor();
    await shot('04-compact-sheet');
    if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  } else {
    // gl-calendar: 5 trips still read as 5, drawn as 3 dots (the cell's picture).
    const five = await dayButton(fiveDay).ariaSnapshot();
    check(five.includes(plural(L('historyDayLabel', { date: longDay(fiveDay) }), 5)), `the 5-trip day reads 5 trips (${five.trim()})`);
    if (fiveDay.slice(0, 7) === today.slice(0, 7)) await dayButton(fiveDay).screenshot({ path: `${dir}/01b-five-trip-day-cell.png` });
    if (threeDay.slice(0, 7) === today.slice(0, 7)) await dayButton(threeDay).screenshot({ path: `${dir}/01c-three-trip-day-cell.png` });
    const future = daysAgo(-1);
    if (future.slice(0, 7) === today.slice(0, 7)) {
      check((await dayButton(future).count()) === 0, `tomorrow (${future}) is no button`);
    }

    // gl-journal: a section per week or month the seeded trips fall in (on a Monday none is this week).
    for (const heading of new Set([daysAgo(1), threeDay, fiveDay].map(journalSection))) check(await sectionShown(heading), `journal section „${heading}“`);
    await reveal(page, tile('Kürbis'));
    check(await sectionShown(journalSection(lastMonthDay)), `journal section „${journalSection(lastMonthDay)}“ above Kürbis`);
    await shot('02-journal-scrolled');
    const locked = plural(L('historyLockedCount'), 1);
    await until(async () => (await aria()).includes(L('historyLockedTitle')), 'the locked row at the end of the journal');
    check((await aria()).includes(locked), `the journal ends in „${L('historyLockedTitle')}“ / „${locked}“`);
    check((await tile('Sauerkraut').count()) === 0, 'the 40-day-old trip is not listed');
    const salesTalk = ['kaufst du', 'bald verfügbar', L('integrationPremiumSoon'), L('premiumWeb')];
    const quietLockRow = async (where) => {
      const text = (await aria()).toLowerCase();
      const said = salesTalk.filter((line) => text.includes(line.toLowerCase().replace(/\s+/g, ' ')));
      check(said.length === 0, `${where}: the locked row says nothing about buying before sales start${said.length ? ` (found ${said.join(' | ')})` : ''}`);
      check((await page.getByRole('button', { name: new RegExp(escape(L('historyLockedTitle'))) }).count()) === 0, `${where}: the locked row is no button while premium_offer is off`);
    };
    await quietLockRow('journal');
    await shot('03-journal-locked-row');

    // gl-day-filter
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    await page.mouse.wheel(0, -5000);
    await showMonthOf(threeDay);
    await dayButton(threeDay).click();
    await button(L('historyDayClear')).waitFor({ timeout: 5_000 });
    check((await aria()).includes(L('historyDayFilter', { day: monthDay(threeDay) })), `„${L('historyDayFilter', { day: monthDay(threeDay) })}“ heads the journal`);
    for (const item of ['Kaffee', 'Spinat', 'Rotwein']) check((await tile(item).count()) === 1, `the filtered journal lists the ${item} trip`);
    for (const item of ['Haferflocken', 'Quark', 'Kürbis']) check((await tile(item).count()) === 0, `the filtered journal leaves the ${item} trip out`);
    await shot('04-day-filter');
    await button(L('historyDayClear')).click();
    await until(async () => (await tile('Quark').count()) === 1, 'all trips after clearing the day');
    log('cleared: every trip again');

    // gl-view-toggle, gl-store-timeline
    await toStores().click();
    await toDates().waitFor({ timeout: 5_000 });
    for (const store of ['Lidl', 'Rewe']) check((await page.getByRole('heading', { name: store, exact: true }).count()) === 1, `store timeline block „${store}“`);
    check((await monthButton('previousMonth').count()) === 0, 'no calendar in the store timeline');
    await shot('05-store-timeline');
    await page.reload();
    await openTab(page, L, 'tabHistory').catch(() => {});
    await toDates().waitFor({ timeout: 30_000 });
    check((await page.getByRole('heading', { name: 'Lidl', exact: true }).count()) === 1, 'after a reload the history opens by store again');
    await shot('06-store-timeline-after-reload');
    await reveal(page, page.getByText(L('historyLockedTitle')).or(page.getByLabel(new RegExp(escape(L('historyLockedTitle'))))).first());
    check((await aria()).includes(L('historyLockedTitle')), 'the store timeline ends in the locked row');
    await quietLockRow('store timeline');
    await shot('07-store-timeline-locked-row');
    await toDates().click();
    await toStores().waitFor({ timeout: 5_000 });
    log('toggled back to the journal');

    // gl-free-window: the calendar's locked days. It goes back only to the window's first month (the
    // 40-day-old trip is locked, so it does not count), which is the 40-day-old trip's month only late
    // in a month: check the locked days that month has before the window's first day.
    const firstOpen = daysAgo(27);
    await showMonthOf(firstOpen);
    check(await monthButton('previousMonth').isDisabled(), `the calendar goes back no further than ${monthTitle(firstOpen)}`);
    check((await dayButton(firstOpen).count()) === 1, `${firstOpen}, the window's first day, is a button`);
    for (const day of [daysAgo(28), oldDay].filter((d) => d.slice(0, 7) === firstOpen.slice(0, 7))) {
      const locked = L('historyDayLocked', { date: longDay(day) });
      check((await page.getByText(locked, { exact: true }).count()) === 1, `${day} reads „${locked}“`);
      check((await dayButton(day).count()) === 0, `${day} is no button`);
    }
    await shot('08-calendar-locked-month');
    await showMonthOf(today);

    // gl-sheet: add by hand.
    await button(L('tripAdd')).click();
    const add = sheet(L('tripAdd'));
    await add.waitFor({ timeout: 5_000 });
    const storeChips = ['Lidl', 'Rewe', L('noStore')];
    const pickedChips = [];
    for (const name of storeChips) if ((await add.getByRole('button', { name, exact: true }).getAttribute('aria-current')) === 'true') pickedChips.push(name);
    check(pickedChips.length === 0, `a new trip starts with no store picked${pickedChips.length ? ` (picked: ${pickedChips.join(', ')})` : ''}`);
    const fields = add.getByRole('textbox');
    await typeInto(fields.nth(0), 'Joghurt');
    // The note joins the store group's name on the web („Laden Wähle einen Laden.“).
    const storeMissing = () => add.getByRole('group', { name: new RegExp(`${escape(L('tripStoreMissing'))}$`) });
    const tripsBefore = (await history()).trips.length;
    await add.getByRole('button', { name: L('save'), exact: true }).click();
    await until(async () => (await storeMissing().count()) === 1, `„${L('tripStoreMissing')}“ under the store chips`, 5_000);
    check((await history()).trips.length === tripsBefore, 'a save without a store choice saves nothing');
    await shot('09a-sheet-store-missing');
    await add.getByRole('button', { name: 'Rewe', exact: true }).click();
    await until(async () => (await storeMissing().count()) === 0, 'the note goes once Rewe is picked', 5_000);
    await add.getByRole('button', { name: L('dayYesterday'), exact: true }).click();
    await typeInto(fields.nth(1), '2');
    await add.getByRole('button', { name: L('tripAddItem'), exact: true }).click();
    await until(async () => (await fields.count()) === 4, 'a second item row');
    await typeInto(fields.nth(2), 'Honig');
    await shot('09-sheet-filled');
    await add.getByRole('button', { name: L('save'), exact: true }).click();
    await add.waitFor({ state: 'detached', timeout: 10_000 });
    await until(async () => (await tile('Joghurt').count()) === 1, 'the new trip in the journal');
    await shot('10-journal-with-new-trip');
    const added = (await history()).trips.find((t) => t.items.some((i) => i.name === 'Joghurt'));
    log(`trip_history: ${JSON.stringify(added)}`);
    check(added?.store_id === rewe && added.store_name === 'Rewe' && added.shopped_on === daysAgo(1), 'saved at Rewe, yesterday, with the store name snapshot');
    check(JSON.stringify(added.items.map(({ name, quantity }) => [name, quantity])) === JSON.stringify([['Joghurt', '2'], ['Honig', null]]), 'items saved as snapshots: Joghurt 2, Honig');
    check(added.items.every((i) => Object.keys(i).sort().join() === 'canonical_key,name,quantity'), 'each item is name, quantity and canonical key, no item id');

    // edit
    await tile('Joghurt').click();
    const edit = sheet(L('tripEdit'));
    await edit.waitFor({ timeout: 5_000 });
    check((await edit.getByRole('button', { name: L('tripRemoveItem', { name: 'Honig' }) }).count()) === 1, 'the edit sheet holds Honig');
    await edit.getByRole('button', { name: L('tripAddItem'), exact: true }).click();
    const editFields = edit.getByRole('textbox');
    await until(async () => (await editFields.count()) === 6, 'a third item row');
    await typeInto(editFields.nth(4), 'Brot');
    await shot('11-edit-sheet');
    await edit.getByRole('button', { name: L('save'), exact: true }).click();
    await edit.waitFor({ state: 'detached', timeout: 10_000 });
    const edited = (await history()).trips.find((t) => t.id === added.id);
    check(edited?.items.map((i) => i.name).join() === 'Joghurt,Honig,Brot', `edited in place: ${edited?.items.map((i) => i.name).join(', ')}`);

    // delete
    await tile('Joghurt').click();
    await edit.waitFor({ timeout: 5_000 });
    await edit.getByRole('button', { name: L('tripDelete'), exact: true }).click();
    await button(L('delete')).waitFor({ timeout: 5_000 });
    await shot('12-delete-dialog');
    await button(L('delete')).click();
    await until(async () => !(await history()).trips.some((t) => t.id === added.id), 'the trip gone from trip_history');
    log('trip_history no longer has the deleted trip');
    // The dialog and then the sheet hide the journal from the semantics tree until both are gone.
    await until(async () => (await edit.count()) === 0 && (await page.getByRole('heading', { name: journalSection(daysAgo(1)) }).count()) === 1, 'the journal back');
    check((await tile('Joghurt').count()) === 0, 'the deleted trip is gone from the journal');

    // gl-no-card: ticking a store's last open item shows no inline card (job 264)
    await openTab(page, L, 'tabList');
    const logCard = /eintragen\?|Log your trip/;
    for (const item of prompted) {
      await reveal(page, itemRow(page, item));
      await itemRow(page, item).click();
      // A build with trip-mode on too (as internal testers have it) asks „Kaufst du gerade ein?“ after a tick.
      const justTicked = page.getByRole('button', { name: L('shopAskNo'), exact: true });
      if (await justTicked.waitFor({ timeout: 2_000 }).then(() => true, () => false)) {
        await justTicked.click();
      }
      await until(async () => (await itemRow(page, item).count()) === 0, `${item} ticked off`);
    }
    await page.waitForTimeout(800);
    // The card stood at the top of the list, which a lazily built list drops once scrolled away.
    await page.mouse.wheel(0, -5000);
    await page.waitForTimeout(400);
    check(!logCard.test(await aria()), 'no inline log card after ticking the last open Lidl item');
    await shot('13-no-card-after-last-tick');
    if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
  }
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
log(`PASS grocery-log${compact ? ' (358 px)' : ''} (evidence: ${dir})`);
