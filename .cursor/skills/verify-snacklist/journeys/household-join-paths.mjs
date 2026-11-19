// Feature household-invites, sub-feature join (job 206): joining is the list's household sheet's,
// More offers no join. Mia makes three households with an invite each. Ida opens „Mit Code
// beitreten“ from the sheet (`/join`, Abbrechen back to the list), finds no join row anywhere on
// More, sees the old `/more/join` land on `/join`, joins one household by typed code from the
// sheet and one by a `/join/<code>` link (on the web through the invite landing page). Noah, signed out, opens the third link, signs in and
// lands on its join screen.
//
//   node journeys/household-join-paths.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { addField, apiAs, capture, householdButton, instance, logger, member, openApp, openHouseholds, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: household-join-paths.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const ida = member(inst, 'ida');
const noah = member(inst, 'noah');
const mia = member(inst, 'mia');
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const names = ['Nachbarn', 'Verein', 'Oma'];
const memberOf = (user, name) => sql(`select count(*) from public.household_members m join public.households h on h.id = m.household_id
  where m.user_id = '${user.id}' and h.name = '${name}' and h.created_by = '${mia.id}'`);

sql(`delete from public.households where created_by = '${mia.id}' and name in (${names.map((n) => `'${n}'`).join(', ')})`);
const miaApi = await apiAs(inst, mia);
const codes = {};
for (const name of names) {
  const { data: household, error } = await miaApi.rpc('create_household', { p_request_id: crypto.randomUUID(), p_name: name });
  if (error) throw error;
  const { data: invite, error: inviteError } = await miaApi.rpc('create_invite', { p_household: household.id });
  if (inviteError) throw inviteError;
  codes[name] = invite.code;
}
log(`setup: Mia made ${names.join(', ')} with an invite each`);

const joinRow = (page, L) => page.getByRole('button', { name: L('joinWithCode'), exact: true });
const codeField = (page, L) => page.getByRole('textbox', { name: L('inviteCode') });
const openSheet = openHouseholds;
// On the web `/join/<code>` is the invite landing page; its „Im Browser beitreten“ opens the app
// with `?invite=` (the phones open the app's `/join/<code>` route directly).
async function openLink(page, code) {
  await page.goto(`/join/${code}`);
  const landing = new URL(page.url()).pathname;
  await page.getByRole('link', { name: /beitreten|join/i }).click();
  await page.waitForURL(/invite=|\/join|\/login/, { timeout: 30_000 });
  log(`link /join/<code>: landing page ${landing}, then the app at ${new URL(page.url()).pathname}`);
}
// A typed code waits for „Haushalt beitreten“; with join-household-jh2 (users' build) a link joins
// without it.
async function confirmJoin(page, L, name) {
  const join = page.getByRole('button', { name: L('joinHousehold'), exact: true });
  const shown = householdButton(page, name).first();
  await join.or(shown).first().waitFor({ timeout: 30_000 });
  if (await join.count()) await join.click();
  await shown.waitFor({ timeout: 30_000 });
}

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, ida);
  const home = sql(`select name from public.households where id = '${ida.householdId}'`);
  log(`signed in as ida (${lang}), shown household ${home}`);

  await openSheet(page, L, home);
  await joinRow(page, L).waitFor({ timeout: 10_000 });
  await capture(page, dir, '01-sheet');
  await joinRow(page, L).click();
  await page.waitForURL(/\/join$/, { timeout: 10_000 });
  await codeField(page, L).waitFor({ timeout: 10_000 });
  log(`sheet → ${L('joinWithCode')}: ${new URL(page.url()).pathname}`);
  await capture(page, dir, '02-join-from-sheet');
  await page.getByRole('button', { name: L('cancel'), exact: true }).click();
  await addField(page, L).waitFor({ timeout: 10_000 });
  log(`${L('cancel')}: back on the list at ${new URL(page.url()).pathname}`);

  await page.getByRole('tab', { name: L('tabMore'), exact: true }).click();
  await page.getByRole('heading', { name: L('tabMore'), exact: true }).waitFor({ timeout: 10_000 });
  await capture(page, dir, '03-more-top');
  const seen = new Set();
  await page.mouse.move(195, 400);
  for (let i = 0; i < 12; i++) {
    for (const line of (await page.locator('body').ariaSnapshot()).split('\n')) seen.add(line.trim());
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(150);
  }
  await capture(page, dir, '04-more-end');
  const joinish = [...seen].filter((line) => /beitreten|join/i.test(line));
  log(`More, scrolled top to end: ${seen.size} ARIA lines, join entries: ${JSON.stringify(joinish)}`);
  if (joinish.length) throw new Error(`More still offers a join: ${joinish.join(' | ')}`);

  await page.goto('/more/join');
  await codeField(page, L).waitFor({ timeout: 30_000 });
  log(`old link /more/join → ${new URL(page.url()).pathname}`);
  if (new URL(page.url()).pathname !== '/join') throw new Error('/more/join did not land on /join');
  await capture(page, dir, '05-old-more-join-link');
  await page.getByRole('button', { name: L('cancel'), exact: true }).click();
  await addField(page, L).waitFor({ timeout: 10_000 });

  await openSheet(page, L, home);
  await joinRow(page, L).click();
  await typeInto(codeField(page, L), codes.Nachbarn.toLowerCase());
  await page.getByRole('button', { name: L('inviteCheck'), exact: true }).click();
  await capture(page, dir, '06-code-preview');
  await confirmJoin(page, L, 'Nachbarn');
  await capture(page, dir, '07-joined-by-code');
  log(`typed code from the sheet: Ida in Nachbarn ${memberOf(ida, 'Nachbarn')}, still in ${home}: ${sql(`select count(*) from public.household_members where user_id = '${ida.id}' and household_id = '${ida.householdId}'`)}`);
  if (memberOf(ida, 'Nachbarn') !== '1') throw new Error('the typed code did not join');

  await openLink(page, codes.Verein);
  await page.getByRole('button', { name: L('joinHousehold'), exact: true }).or(householdButton(page, 'Verein')).first().waitFor({ timeout: 30_000 });
  await capture(page, dir, '08-link-preview');
  await confirmJoin(page, L, 'Verein');
  log(`/join/<code> signed in: Ida in Verein ${memberOf(ida, 'Verein')}`);
  if (memberOf(ida, 'Verein') !== '1') throw new Error('the link did not join');
} catch (e) {
  failed = e;
  await capture(page, dir, 'failure').catch(() => {});
} finally {
  await browser.close();
}

if (!failed) {
  const second = await openApp(inst, { lang });
  try {
    const { page: p2, L: L2 } = second;
    await openLink(p2, codes.Oma);
    // join-household-jh2 (users' build) asks „Konto erstellen“ or „Anmelden“ first.
    const signInFirst = p2.getByRole('button', { name: L2('signIn'), exact: true });
    // The sheet opens a frame after the login screen, so wait for it alone before falling back.
    if (await signInFirst.waitFor({ timeout: 10_000 }).then(() => true, () => false)) await signInFirst.click();
    const withEmail = p2.getByRole('button', { name: L2('continueWithEmail') });
    await withEmail.or(p2.getByRole('textbox', { name: L2('email') })).waitFor({ timeout: 30_000 });
    log(`signed out, /join/<code> → ${new URL(p2.url()).pathname}${new URL(p2.url()).search.replace(/invite=[^&]+/, 'invite=<code>')}`);
    if (await withEmail.isVisible()) await withEmail.click();
    await typeInto(p2.getByRole('textbox', { name: L2('email') }), noah.email);
    await typeInto(p2.getByRole('textbox', { name: L2('password') }), noah.password);
    await p2.keyboard.press('Enter');
    const join = p2.getByRole('button', { name: L2('joinHousehold'), exact: true });
    const decline = p2.getByRole('button', { name: L2('analyticsDecline'), exact: true });
    const oma = householdButton(p2, 'Oma').first();
    await join.or(decline).or(oma).first().waitFor({ timeout: 30_000 });
    if (await decline.isVisible()) {
      await p2.mouse.move(195, 400);
      await decline.click();
    }
    await join.or(oma).first().waitFor({ timeout: 30_000 });
    await capture(p2, dir, '09-signed-out-link-after-sign-in');
    await confirmJoin(p2, L2, 'Oma');
    log(`signed out → sign-in → join: Noah in Oma ${memberOf(noah, 'Oma')}`);
    if (memberOf(noah, 'Oma') !== '1') throw new Error('the signed-out link did not join');
  } catch (e) {
    failed = e;
  } finally {
    await second.browser.close();
  }
}

if (errors.length) log(`page errors: ${errors.join(' | ')}`);
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
