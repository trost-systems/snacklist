// Feature household-invites, sub-feature household-cap (job 200): a user is in at most 20
// households. Ida is put in 20 (her seeded household and 19 of her own); Mia makes „Nachbarn“ and
// an invite. Ida opening the invite and joining is refused with the cap message, a 21st household
// from the switcher too, and she stays in 20. Once she is out of one, the same invite joins.
//
//   node journeys/household-cap.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { addField, apiAs, capture, householdButton, instance, logger, member, openApp, openHouseholds, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: household-cap.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const ida = member(inst, 'ida');
const mia = member(inst, 'mia');
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const count = () => Number(sql(`select count(*) from public.household_members where user_id = '${ida.id}'`));
const fillerName = (i) => `Cap ${String(i).padStart(2, '0')}`;

sql(`delete from public.households where created_by = '${ida.id}' and name like 'Cap %'`);
sql(`delete from public.households where created_by = '${mia.id}' and name = 'Nachbarn'`);
const room = 20 - count();
sql(`with h as (
  insert into public.households (name, created_by)
  select 'Cap ' || lpad(i::text, 2, '0'), '${ida.id}' from generate_series(1, ${room}) i returning id)
  insert into public.household_members (household_id, user_id, role) select id, '${ida.id}', 'owner' from h`);
log(`setup: Ida is in ${count()} households`);
if (count() !== 20) throw new Error(`setup left Ida in ${count()} households, not 20`);

const miaApi = await apiAs(inst, mia);
const { data: household, error: createError } = await miaApi.rpc('create_household', {
  p_request_id: crypto.randomUUID(), p_name: 'Nachbarn',
});
if (createError) throw createError;
const { data: invite, error: inviteError } = await miaApi.rpc('create_invite', { p_household: household.id });
if (inviteError) throw inviteError;
log(`setup: Mia made „Nachbarn“ and an invite`);

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, ida);
  log(`signed in as ida (${lang}) on ${inst.webUrl}`);

  await page.goto(`/?invite=${invite.code}`);
  // With join-household-jh2 (users' build) a link joins without the „Haushalt beitreten“ tap.
  const join = page.getByRole('button', { name: L('joinHousehold'), exact: true });
  const refusal = page.locator('span', { hasText: L('tooManyHouseholds') });
  await join.or(refusal).first().waitFor({ timeout: 30_000 });
  await capture(page, dir, '01-join-form');
  if (await join.count()) await join.click();
  await refusal.waitFor({ timeout: 15_000 });
  log(`join refused: "${await refusal.textContent()}"`);
  await capture(page, dir, '02-join-refused');
  const inNachbarn = sql(`select count(*) from public.household_members where user_id = '${ida.id}' and household_id = '${household.id}'`);
  log(`database after the refused join: Ida in ${count()} households, in Nachbarn: ${inNachbarn}`);
  if (count() !== 20 || inNachbarn !== '0') throw new Error('the refused join changed Ida\'s memberships');

  await page.getByRole('button', { name: L('cancel'), exact: true }).click();
  await addField(page, L).waitFor({ timeout: 30_000 });
  const shown = sql(`select name from public.households where id = '${ida.householdId}'`);
  await openHouseholds(page, L, shown);
  const newHousehold = page.getByRole('button', { name: L('newHousehold'), exact: true });
  await page.mouse.move(195, 500);
  for (let i = 0; i < 20 && !(await newHousehold.count() && (await newHousehold.boundingBox())?.y < 760); i++) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(200);
  }
  await capture(page, dir, '03-switcher-at-20');
  await newHousehold.click();
  await typeInto(page.getByRole('textbox', { name: L('householdName') }), 'Einundzwanzig');
  await capture(page, dir, '04-create-form');
  await page.getByRole('button', { name: L('skipStores'), exact: true }).click();
  const createRefusal = page.locator('span', { hasText: L('tooManyHouseholds') });
  await createRefusal.waitFor({ timeout: 15_000 });
  log(`21st create refused: "${await createRefusal.textContent()}"`);
  await capture(page, dir, '05-create-refused');
  const made = sql(`select count(*) from public.households where name = 'Einundzwanzig'`);
  log(`database after the refused create: Ida in ${count()} households, „Einundzwanzig“ rows: ${made}`);
  if (count() !== 20 || made !== '0') throw new Error('the refused create made a household');

  sql(`delete from public.households where created_by = '${ida.id}' and name = '${fillerName(room)}'`);
  log(`setup: Ida is out of ${fillerName(room)}, now in ${count()}`);
  await page.goto(`/?invite=${invite.code}`);
  await join.or(addField(page, L)).first().waitFor({ timeout: 30_000 });
  if (await join.count()) await join.click();
  await addField(page, L).waitFor({ timeout: 30_000 });
  await householdButton(page, 'Nachbarn').first().waitFor({ timeout: 15_000 });
  await capture(page, dir, '06-joined-at-19');
  log(`database after the join: Ida in ${count()} households`);
  if (count() !== 20) throw new Error(`Ida is in ${count()} households after joining at 19, not 20`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
  sql(`delete from public.households where created_by = '${ida.id}' and name like 'Cap %'`);
  sql(`delete from public.household_members where user_id = '${ida.id}' and household_id = '${household.id}'`);
  sql(`delete from public.households where id = '${household.id}'`);
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
console.log('PASS');
