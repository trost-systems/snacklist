// Feature display-name (job 297, flag `display-name`): the name step after sign-in (DN3) and
// Konto › Dein Name (DE1). Four people walk it: a new e-mail sign-up (empty field, required), a
// sign-up whose provider name is prefilled (one tap), a joiner from an invite link (the step comes
// before the join screen, the owner then sees the name), and a seeded member whose name is still
// the e-mail prefix (asked once with „Jetzt nicht“, then changes it under Konto, also at 200 %).
// A later provider name does not replace a chosen one. Needs a build with
// VH_DEFINES="FLAGS_ON=display-name".
//
//   node journeys/display-name.mjs <evidence dir> [--lang de|en] [--dark]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { createClient } from '../../../../e2e/node_modules/@supabase/supabase-js/dist/index.mjs';
import { apiAs, capture, instance, logger, member, openApp, openTab, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: display-name.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const stamp = Date.now().toString(36);
const password = 'test-password-123';
const dbUrl = `postgresql://postgres:postgres@127.0.0.1:${new URL(inst.apiUrl).port.replace(/21$/, '22')}/postgres`;
const sql = (query) => execFileSync('psql', [dbUrl, '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8' }).trim();
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};
const button = (p, name) => p.getByRole('button', { name, exact: true });
const nameField = (p, L) => p.getByRole('textbox', { name: new RegExp(`^${L('yourNameLabel')}`) });
const nameOf = (email) => sql(`select p.display_name || '|' || (p.display_name_chosen_at is not null) from public.profiles p join auth.users u on u.id = p.id where u.email = '${email}'`);
// Flutter web fills the DOM input only while the field has focus.
const valueOf = async (field, want) => {
  await field.click();
  for (let i = 0; i < 40 && (await field.inputValue()) !== want; i++) await field.page().waitForTimeout(250);
  return field.inputValue();
};
const at = async (p, path) => {
  await p.waitForURL(new RegExp(`${path}(\\?|$)`), { timeout: 30_000 });
  await p.waitForTimeout(500);
};

/** The sign-in screen's e-mail form, then the analytics question declined. */
async function signUpOrIn(p, L, email, { signUp, secret = password }) {
  const withEmail = p.getByRole('button', { name: L('continueWithEmail') });
  await withEmail.or(p.getByRole('textbox', { name: L('email') })).waitFor({ timeout: 30_000 });
  if (await withEmail.isVisible()) await withEmail.click();
  await typeInto(p.getByRole('textbox', { name: L('email') }), email);
  await typeInto(p.getByRole('textbox', { name: L('password') }), secret);
  if (signUp) await button(p, L('signUp')).click();
  else await button(p, L('signIn')).click();
  await p.waitForURL(/analytics-consent/, { timeout: 30_000 });
  await button(p, L('analyticsDecline')).click();
}

const people = [];
const open = async () => {
  const app = await openApp(inst, { lang, dark, videoDir: dir });
  people.push(app);
  return app;
};
let failed = null;
let shot = null;
try {
  // 1. A new e-mail sign-up: the step is required and starts empty.
  {
    const { page, L } = await open();
    shot = page;
    const email = `name-mail-${stamp}@fg-test.invalid`;
    await page.goto('/login');
    await signUpOrIn(page, L, email, { signUp: true });
    await at(page, '/your-name');
    const field = nameField(page, L);
    await field.waitFor();
    check((await valueOf(field, '')) === '', 'an e-mail sign-up sees an empty name field');
    const go = button(page, L('onboardingNext'));
    check(await go.isDisabled(), `„${L('onboardingNext')}“ is off while the field is empty`);
    check(!(await button(page, L('yourNameNotNow')).count()), 'no „Jetzt nicht“ before a household exists');
    check(await button(page, L('signOut')).isVisible(), `the step offers „${L('signOut')}“, so a wrong account is not stuck`);
    await capture(page, dir, '01-mail-empty');
    await typeInto(field, '  Lea   🌻 ');
    await capture(page, dir, '02-mail-typed');
    await go.click();
    await at(page, '/welcome');
    check(nameOf(email) === 'Lea 🌻|true', `the name is stored trimmed and collapsed, chosen (${nameOf(email)})`);
    await capture(page, dir, '03-mail-welcome');
  }

  // 1b. A wrong account leaves the step by signing out, and nothing is stamped.
  {
    const { page, L } = await open();
    shot = page;
    const email = `name-wrong-${stamp}@fg-test.invalid`;
    await page.goto('/login');
    await signUpOrIn(page, L, email, { signUp: true });
    await at(page, '/your-name');
    await button(page, L('signOut')).click();
    await page.waitForURL(/\/login$/, { timeout: 30_000 });
    check(nameOf(email) === `name-wrong-${stamp}|false`, 'signing out from the step saves no name');
    await capture(page, dir, '03b-signed-out-from-step');
  }

  // 2. A provider name (as Google or Apple fill it): prefilled, one tap.
  {
    const { page, L } = await open();
    shot = page;
    const email = `name-google-${stamp}@fg-test.invalid`;
    const api = createClient(inst.apiUrl, inst.publishableKey, { auth: { persistSession: false } });
    const { error } = await api.auth.signUp({ email, password, options: { data: { full_name: 'Ida Sommer' } } });
    if (error) throw error;
    await page.goto('/login');
    await signUpOrIn(page, L, email, { signUp: false });
    await at(page, '/your-name');
    await nameField(page, L).waitFor();
    check((await valueOf(nameField(page, L), 'Ida Sommer')) === 'Ida Sommer', 'the provider name is prefilled');
    const yes = button(page, L('yourNameConfirm'));
    check(await yes.isEnabled(), `„${L('yourNameConfirm')}“ is ready without typing`);
    await capture(page, dir, '04-provider-prefilled');
    await yes.click();
    await at(page, '/welcome');
    check(nameOf(email) === 'Ida Sommer|true', 'one tap stores the provider name as chosen');
    sql(`update auth.users set raw_user_meta_data = raw_user_meta_data || '{"full_name": "Someone Else"}' where email = '${email}'`);
    check(nameOf(email) === 'Ida Sommer|true', 'a later provider name does not replace the confirmed one');
  }

  // 3. A joiner from an invite link: the step comes before the join screen.
  const mia = member(inst, 'mia');
  const miaApi = await apiAs(inst, mia);
  {
    const { data: invite, error } = await miaApi.rpc('create_invite', { p_household: mia.householdId, p_kind: 'person' });
    if (error) throw error;
    const code = (Array.isArray(invite) ? invite[0] : invite).code;
    const { page, L } = await open();
    shot = page;
    const email = `name-join-${stamp}@fg-test.invalid`;
    await page.goto(`/join/${code}`);
    await page.getByRole('link', { name: lang === 'en' ? 'Join in the browser' : 'Im Browser beitreten' }).click();
    await signUpOrIn(page, L, email, { signUp: true });
    await page.waitForURL(new RegExp(`/your-name\\?invite=${code}`), { timeout: 30_000 });
    log(`ok: the joiner lands on /your-name with the invite (${page.url()})`);
    await nameField(page, L).waitFor();
    await capture(page, dir, '05-joiner-name');
    await typeInto(nameField(page, L), 'Jo Brandt');
    await button(page, L('onboardingNext')).click();
    await button(page, L('joinHousehold')).waitFor({ timeout: 30_000 });
    await capture(page, dir, '06-joiner-join-screen');
    await button(page, L('joinHousehold')).click();
    await page.waitForURL(/\/$/, { timeout: 30_000 });
    const { data: members } = await miaApi.rpc('household_members_of', { p_household: mia.householdId });
    check(members.some((m) => m.display_name === 'Jo Brandt'), 'the owner sees the joiner by the chosen name');
  }

  // 4. A member whose name is still the e-mail prefix: asked once, then Konto › Dein Name.
  {
    const noah = member(inst, 'noah');
    const prefix = noah.email.split('@')[0];
    sql(`update public.profiles set display_name = '${prefix}', display_name_chosen_at = null where id = (select id from auth.users where email = '${noah.email}')`);
    const { page, L } = await open();
    shot = page;
    await page.goto('/login');
    await signUpOrIn(page, L, noah.email, { signUp: false, secret: noah.password });
    await at(page, '/your-name');
    await nameField(page, L).waitFor();
    check((await valueOf(nameField(page, L), '')) === '', 'the e-mail prefix is not prefilled');
    await capture(page, dir, '07-member-asked');
    await button(page, L('yourNameNotNow')).click();
    await page.getByRole('textbox', { name: L('addFieldHint') }).waitFor({ timeout: 30_000 });
    await page.reload();
    await page.getByRole('textbox', { name: L('addFieldHint') }).waitFor({ timeout: 30_000 });
    check(!page.url().includes('/your-name'), '„Jetzt nicht“ holds after a reload');
    const card = button(page, L('checklistDismiss'));
    if (await card.waitFor({ timeout: 3_000 }).then(() => true, () => false)) await card.click();

    await openTab(page, L, 'tabMore');
    await page.getByRole('button', { name: new RegExp(`^${L('account')}`) }).first().click();
    const row = page.getByRole('button', { name: new RegExp(`^${L('yourNameLabel')}`) }).first();
    await row.waitFor();
    check((await page.locator('body').ariaSnapshot()).includes(L('yourNameAdd')), `the row reads „${L('yourNameAdd')}“`);
    await capture(page, dir, '08-account-row-add');
    await row.click();
    const save = button(page, L('save'));
    await save.waitFor();
    check(await save.isDisabled(), 'Save is off for an empty name');
    await typeInto(nameField(page, L), 'Noah');
    check(await save.isEnabled(), 'Save is on for „Noah“');
    await capture(page, dir, '09-account-sheet');
    await save.click();
    await page.getByText(L('yourNameSaved')).first().waitFor({ timeout: 10_000 }).catch(() => {});
    await page.waitForTimeout(800);
    check((await page.locator('body').ariaSnapshot()).includes('Noah'), 'the row shows the new name');
    check(nameOf(noah.email) === 'Noah|true', 'Konto saved „Noah“ as chosen');
    await capture(page, dir, '10-account-row-saved');

    await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
    await page.waitForTimeout(800);
    await capture(page, dir, '11-account-200');
    await row.click();
    await button(page, L('save')).waitFor();
    await page.waitForTimeout(600);
    check(await button(page, L('save')).isVisible(), 'at 200 % the sheet still shows Save');
    await capture(page, dir, '12-account-sheet-200');
  }

  const errors = people.flatMap((p) => p.errors);
  check(errors.length === 0, `no page errors (${errors.join(' | ')})`);
} catch (e) {
  failed = e;
  if (shot) await capture(shot, dir, '99-failure').catch(() => {});
}
for (const p of people) await p.browser.close();
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
