// Feature onboarding, the answers no step may drop (job 461): signed out, the name suggestion
// follows a kind changed on the way back, the name field stops at the server's 80 code points (an
// emoji past them is cut whole), an own store typed without its check and an item typed without +
// are kept by „Weiter“. Then signs up a fresh user and reads the household the setup made.
//
//   node journeys/onboarding-dead-ends.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { createClient } from '../../../../e2e/node_modules/@supabase/supabase-js/dist/index.mjs';
import { capture, instance, logger, openApp, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: onboarding-dead-ends.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const email = `dead-ends-${Date.now().toString(36)}@fg-test.invalid`;
const password = 'test-password-123';
const longName = `${'A'.repeat(74)}👨‍👩‍👧‍👦`;
const store = lang === 'de' ? 'Hofladen' : 'Farm shop';
const item = lang === 'de' ? 'Hafermilch' : 'Oat milk';
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

const { browser, page, L, errors } = await openApp(inst, { lang, locale: lang === 'en' ? 'en-DE' : 'de-DE', videoDir: dir });
const button = (name) => page.getByRole('button', { name, exact: true });
const at = async (path) => {
  await page.waitForURL(new RegExp(`${path}(\\?|$)`), { timeout: 20_000 });
  await page.waitForTimeout(600);
};
// A hovered „Zurück“ shows its tooltip, which moves the button out of the semantics tree for a while.
const back = async () => {
  await button(lang === 'en' ? 'Back' : 'Zurück').first().click();
  await page.mouse.move(200, 600);
};
const kind = (key) => page.getByRole('checkbox', { name: L(key) });
const nameField = () => page.getByRole('textbox', { name: new RegExp(`^${L('householdName')}`) });
const nameShown = async () => {
  await nameField().click();
  await page.waitForTimeout(300);
  return nameField().inputValue();
};
let failed = null;
try {
  await page.goto('/');
  await at('/start');
  await button(L('startGo')).click();
  await at('/start/usage');
  await button(L('analyticsDecline')).click();
  await at('/start/who');
  await kind('kindFamily').click();
  await button(L('onboardingNext')).click();
  await at('/start/name');
  check((await nameShown()) === L('householdNameFamily'), `the name step suggests „${L('householdNameFamily')}“`);
  await button(L('onboardingNext')).click();
  await at('/start/stores');
  await back();
  await at('/start/name');
  await back();
  await at('/start/who');
  await kind('kindFamily').click();
  await kind('kindFlat').click();
  await page.waitForTimeout(300);
  await button(L('onboardingNext')).click();
  await at('/start/name');
  const suggested = await nameShown();
  await capture(page, dir, '01-name-follows-kind');
  check(suggested === L('householdNameFlat'), `after Zurück and „${L('kindFlat')}“ the suggestion is „${L('householdNameFlat')}“ (${suggested})`);

  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.insertText(longName);
  await page.waitForTimeout(300);
  const kept = await nameField().inputValue();
  await capture(page, dir, '02-name-80-code-points');
  check(kept === 'A'.repeat(74), `74 letters and a family emoji (81 code points): the field keeps the letters (${kept.length} chars)`);
  await button(L('onboardingNext')).click();
  await at('/start/stores');
  log('ok: Weiter takes that name');

  await button(L('storeAddOwn')).click();
  await typeInto(page.getByRole('textbox', { name: new RegExp(`^${L('storeNameHint')}`) }), store);
  await capture(page, dir, '03-store-typed');
  await button(L('onboardingNext')).click();
  await at('/start/need');
  log(`ok: Weiter with „${store}“ typed but not checked goes on`);

  await typeInto(page.getByRole('textbox', { name: L('needFieldLabel') }), item);
  await capture(page, dir, '04-need-typed');
  await button(L('onboardingNext')).click();
  await at('/start/account');

  const withEmail = page.getByRole('button', { name: L('continueWithEmail') });
  if (await withEmail.isVisible()) await withEmail.click();
  await typeInto(page.getByRole('textbox', { name: L('email') }), email);
  await typeInto(page.getByRole('textbox', { name: L('password') }), password);
  await button(L('signUp')).click();
  await page.waitForURL(/\/(your-name|start\/invite)(\?|$)/, { timeout: 20_000 });
  if (page.url().includes('/your-name')) {
    await typeInto(page.getByRole('textbox', { name: new RegExp(`^${L('yourNameLabel')}`) }), 'Mia');
    await button(L('onboardingNext')).click();
  }
  await at('/start/invite');
  await capture(page, dir, '05-invite');

  const api = createClient(inst.apiUrl, inst.publishableKey, { auth: { persistSession: false } });
  await api.auth.signInWithPassword({ email, password });
  const { data: households } = await api.from('households').select('id, name, kind');
  check(households?.length === 1, `one household (${households?.length})`);
  const [household] = households;
  check(household.name === 'A'.repeat(74) && household.kind === 'flat', `its name is the 74 letters, its kind flat (${household.kind})`);
  const { data: stores } = await api.from('stores').select('name').eq('household_id', household.id);
  check(stores.map((s) => s.name).join(',') === store, `its store is „${store}“ (${stores.map((s) => s.name)})`);
  const { data: items } = await api.from('items').select('name').eq('household_id', household.id);
  check(items.map((i) => i.name).join(',') === item, `its list has „${item}“ (${items.map((i) => i.name)})`);
  check(errors.length === 0, `no page errors (${errors.join(' | ')})`);
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
}
await page.context().close();
await browser.close();
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS onboarding-dead-ends (evidence: ${dir})`);
