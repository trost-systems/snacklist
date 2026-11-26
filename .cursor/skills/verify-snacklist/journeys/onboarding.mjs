// Feature onboarding, entry point: signed out at `/`, the guided start („Los geht's“) to the list
// (job 168b). Proves the account comes last: the answers survive a reload, nobody exists on the
// server before the sign-up, then the household is made from them (name, kind, stores in order,
// the items sorted into categories), two invites show, a second browser joins through one link and
// the first page marks it „beigetreten“ without a reload, and the list opens with the items.
// Needs no seeded household: it signs up two fresh users.
//
//   node journeys/onboarding.mjs <evidence dir> [--lang de|en] [--dark]
import process from 'node:process';
import { createClient } from '../../../../e2e/node_modules/@supabase/supabase-js/dist/index.mjs';
import { capture, instance, logger, openApp, reveal, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const lang = opt('lang', 'de');
const dark = rest.includes('--dark');
if (!dir) throw new Error('usage: onboarding.mjs <evidence dir> [--lang de|en] [--dark]');

const log = logger(dir);
const inst = instance();
const stamp = Date.now().toString(36);
const password = 'test-password-123';
const owner = `start-${stamp}@fg-test.invalid`;
const joiner = `join-${stamp}@fg-test.invalid`;
const client = () => createClient(inst.apiUrl, inst.publishableKey, { auth: { persistSession: false } });
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

// The store step offers the browser region's chains (open-store-app, full since 2026-11-25); en-US has
// none, so the English run is an English browser in Germany.
const locale = lang === 'en' ? 'en-DE' : 'de-DE';
const { browser, page, L, errors } = await openApp(inst, { lang, locale, dark, videoDir: dir });
const second = await openApp(inst, { lang, locale, dark });
const button = (p, name) => p.getByRole('button', { name, exact: true });
// display-name (users' build) asks the new account's own name after the usage question.
const nameStep = async (p, name) => {
  const field = p.getByRole('textbox', { name: new RegExp(`^${L('yourNameLabel')}`) });
  if (!(await field.waitFor({ timeout: 10_000 }).then(() => true, () => false))) return false;
  await typeInto(field, name);
  await button(p, L('onboardingNext')).click();
  return true;
};
const at = async (path) => {
  await page.waitForURL(new RegExp(`${path}(\\?|$)`), { timeout: 20_000 });
  await page.waitForTimeout(400);
};
let failed = null;
try {
  await page.goto('/');
  await at('/start');
  await capture(page, dir, '01-start');
  await button(page, L('startGo')).click();
  await at('/start/usage');
  await capture(page, dir, '02-usage');
  await button(page, L('analyticsDecline')).click();
  await at('/start/who');
  await page.getByRole('checkbox', { name: L('kindPartner') }).click();
  await page.getByRole('checkbox', { name: L('kindClub') }).click();
  await page.waitForTimeout(300);
  await capture(page, dir, '03-who');
  await button(page, L('onboardingNext')).click();
  await at('/start/name');
  await capture(page, dir, '04-name');
  await button(page, L('onboardingNext')).click();
  await at('/start/stores');
  for (const store of ['REWE', 'dm']) await page.getByRole('checkbox', { name: store, exact: true }).click();
  await page.reload();
  await at('/start/stores');
  const rewe = page.getByRole('checkbox', { name: 'REWE', exact: true });
  await rewe.waitFor();
  check(await rewe.isChecked(), 'a reload resumes at the stores with REWE still ticked');
  await capture(page, dir, '05-stores-after-reload');
  await button(page, L('onboardingNext')).click();
  await at('/start/need');
  const staples = L('needStaples').split(',');
  for (const staple of [staples[0], staples[2]]) await page.getByRole('checkbox', { name: staple, exact: true }).click();
  await typeInto(page.getByRole('textbox', { name: L('needFieldLabel') }), lang === 'de' ? '2 Gurken' : '2 cucumbers');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(400);
  await capture(page, dir, '06-need');
  await page.getByRole('button', { name: new RegExp(`^${L('onboardingNext')}`) }).click();
  await at('/start/account');
  await capture(page, dir, '07-account');
  const early = await client().auth.signInWithPassword({ email: owner, password });
  check(early.error !== null, 'no account on the server before the account step');

  const withEmail = page.getByRole('button', { name: L('continueWithEmail') });
  if (await withEmail.isVisible()) await withEmail.click();
  await typeInto(page.getByRole('textbox', { name: L('email') }), owner);
  await typeInto(page.getByRole('textbox', { name: L('password') }), password);
  await button(page, L('signUp')).click();
  await page.waitForURL(/\/(your-name|start\/invite)(\?|$)/, { timeout: 20_000 });
  if (page.url().includes('/your-name')) {
    await capture(page, dir, '07b-your-name');
    await nameStep(page, 'Mia');
    log('ok: the name step came after the account and took „Mia“');
  }
  await at('/start/invite');
  await capture(page, dir, '08-invite');

  const api = client();
  await api.auth.signInWithPassword({ email: owner, password });
  const { data: households } = await api.from('households').select('id, name, kind');
  check(households?.length === 1, `one household (${JSON.stringify(households)})`);
  const [household] = households;
  check(household.kind === 'partner', 'its kind is the first pick, partner');
  const { data: stores } = await api.from('stores').select('name').eq('household_id', household.id).order('sort_order');
  check(stores.map((s) => s.name).join(',') === 'REWE,dm', 'its stores are REWE, dm, in the order picked');
  const { data: items } = await api.from('items').select('name, quantity, categories(name)').eq('household_id', household.id);
  log(`items ${JSON.stringify(items)}`);
  check(items.length === 3 && items.every((i) => i.categories?.name), 'the three items are on its list, each in a category');

  await page.getByRole('button', { name: L('inviteStepPartner') }).click();
  await page.getByRole('button', { name: L('inviteAnother') }).click();
  await page.waitForTimeout(1500);
  const codes = [...(await page.locator('body').ariaSnapshot()).matchAll(/Code ([A-HJ-NP-Z2-9]{8})/g)].map((m) => m[1]);
  check(new Set(codes).size === 2, `two invites, two codes (${codes.join(', ')})`);
  await capture(page, dir, '09-two-invites');

  const sp = second.page;
  await sp.goto(`/join/${codes[1]}`);
  // `/join/<code>` is the static invite page (app/web/join), not the app: its link opens the app with the invite.
  await sp.getByRole('link', { name: lang === 'en' ? 'Join in the browser' : 'Im Browser beitreten' }).click();
  // join-household-jh2 (users' build) asks „Konto erstellen“ or „Anmelden“ first.
  const create = button(sp, L('jh2InviteSheetCreate'));
  // The sheet opens a frame after the login screen, so wait for it alone before falling back.
  if (await create.waitFor({ timeout: 10_000 }).then(() => true, () => false)) await create.click();
  const secondEmail = sp.getByRole('button', { name: L('continueWithEmail') });
  await secondEmail.or(sp.getByRole('textbox', { name: L('email') })).waitFor({ timeout: 30_000 });
  if (await secondEmail.isVisible()) await secondEmail.click();
  await typeInto(sp.getByRole('textbox', { name: L('email') }), joiner);
  await typeInto(sp.getByRole('textbox', { name: L('password') }), password);
  await button(sp, L('signUp')).click();
  await sp.waitForURL(/analytics-consent/, { timeout: 30_000 });
  await button(sp, L('analyticsDecline')).click();
  await nameStep(sp, 'Jo');
  // With join-household-jh2 a link joins without the „Haushalt beitreten“ tap.
  const join = button(sp, L('joinHousehold'));
  await join.or(sp.getByRole('textbox', { name: L('addFieldHint') })).first().waitFor({ timeout: 30_000 });
  if (await join.count()) await join.click();
  await sp.waitForURL(/\/$/, { timeout: 30_000 });
  log('the second user joined through the second link');
  await page.getByText(new RegExp(`(^${L('inviteJoined')}|^join-${stamp}|${L('inviteJoinedName', { name: 'Jo' })})`)).first().waitFor({ timeout: 15_000 });
  await page.waitForTimeout(500);
  await capture(page, dir, '10-joined-live');
  log('ok: the first page marks the invite joined without a reload');

  // The German invite note is long: the button sits below the screen, built only once scrolled near.
  const toList = page.getByRole('button', { name: L('toTheList') });
  await reveal(page, toList);
  await toList.click();
  await at('/');
  await page.waitForTimeout(1500);
  await capture(page, dir, '11-list');
  check(errors.length === 0, `no page errors (${errors.join(' | ')})`);
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
}
await second.browser.close();
await browser.close();
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
