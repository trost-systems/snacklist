// Feature onboarding, the store step with the flag open-store-app (job 321, OB1): signed out at `/`
// on a browser whose language names a region, the guided start to the store step, which shows that
// region's chains as chips, without the two hint lines. The picked chips and an own store go
// through sign-up, and the stores the server made are linked to their chains (the own one is not),
// so the first list asks nothing. Needs a build with FLAGS_ON=open-store-app; signs up a fresh user.
//
//   node journeys/onboarding-store-chains.mjs <evidence dir> --scenario de|unlisted|at|us [--lang de|en] [--dark]
import process from 'node:process';
import { createClient } from '../../../../e2e/node_modules/@supabase/supabase-js/dist/index.mjs';
import { capture, instance, logger, openApp, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const opt = (name, def) => (rest.includes(`--${name}`) ? rest[rest.indexOf(`--${name}`) + 1] : def);
const scenario = opt('scenario', 'de');
const lang = opt('lang', scenario === 'us' ? 'en' : 'de');
const dark = rest.includes('--dark');
if (!dir || !['de', 'unlisted', 'at', 'us'].includes(scenario)) {
  throw new Error('usage: onboarding-store-chains.mjs <evidence dir> --scenario de|unlisted|at|us [--lang de|en] [--dark]');
}

// What each region offers and what the user picks. `chips` is the step's whole offer in order;
// `taps` the chips tapped; `typed` an own store typed and, with `pick`, the suggestion taken for it.
const scenarios = {
  de: {
    locale: `${lang}-DE`,
    chips: ['EDEKA', 'REWE', 'Lidl', 'ALDI SÜD', 'ALDI Nord', 'Kaufland', 'Netto', 'PENNY', 'dm', 'Rossmann', 'hardware'],
    taps: ['Lidl', 'dm', 'REWE'],
    typed: [],
    stores: ['Lidl:lidl/DE', 'dm:dm/DE', 'REWE:rewe/DE'],
  },
  unlisted: {
    locale: `${lang}-DE`,
    chips: ['EDEKA', 'REWE', 'Lidl', 'ALDI SÜD', 'ALDI Nord', 'Kaufland', 'Netto', 'PENNY', 'dm', 'Rossmann', 'hardware'],
    taps: [],
    // Typed exactly as a chip, a name ticks that chip (OB-Q6); another stays the user's own.
    typed: [{ text: 'lidl' }, { text: 'Hofladen Sonnenwiese' }],
    stores: ['Lidl:lidl/DE', 'Hofladen Sonnenwiese:'],
  },
  at: {
    locale: `${lang}-AT`,
    chips: ['BILLA', 'SPAR', 'Hofer', 'Lidl', 'PENNY', 'MPREIS', 'dm', 'hardware'],
    taps: ['Hofer', 'SPAR', 'Lidl'],
    typed: [],
    stores: ['Hofer:aldi-sued/AT', 'SPAR:spar-at/AT', 'Lidl:lidl/AT'],
  },
  us: {
    locale: `${lang}-US`,
    chips: [],
    taps: [],
    typed: [{ text: 'Hofer', pick: 'Hofer' }, { text: 'Corner shop' }],
    stores: ['Hofer:aldi-sued/AT', 'Corner shop:'],
  },
}[scenario];

const log = logger(dir);
const inst = instance();
const stamp = Date.now().toString(36);
const password = 'test-password-123';
const owner = `ob1-${scenario}-${stamp}@fg-test.invalid`;
const check = (ok, what) => {
  if (!ok) throw new Error(what);
  log(`ok: ${what}`);
};

const { browser, page, L, errors } = await openApp(inst, { lang, locale: scenarios.locale, dark, videoDir: dir });
const button = (name) => page.getByRole('button', { name, exact: true });
const at = async (path) => {
  await page.waitForURL(new RegExp(`${path}(\\?|$)`), { timeout: 20_000 });
  await page.waitForTimeout(400);
};
const label = (chip) => (chip === 'hardware' ? L('storeHardware') : chip);
let failed = null;
let taps = 0;
try {
  await page.goto('/');
  await at('/start');
  await button(L('startGo')).click();
  await at('/start/usage');
  await button(L('analyticsDecline')).click();
  await at('/start/who');
  await page.getByRole('checkbox', { name: L('kindPartner') }).click();
  await button(L('onboardingNext')).click();
  await at('/start/name');
  await button(L('onboardingNext')).click();
  await at('/start/stores');
  await capture(page, dir, '01-stores');

  const snapshot = await page.locator('body').ariaSnapshot();
  const offered = [...snapshot.matchAll(/- checkbox "([^"]+)"/g)].map((m) => m[1]);
  log(`chips offered: ${JSON.stringify(offered)}`);
  check(
    JSON.stringify(offered) === JSON.stringify(scenarios.chips.map(label)),
    `the chips are ${scenarios.chips.length ? scenarios.chips.map(label).join(', ') : 'none'} (${scenarios.locale})`,
  );
  const hints = [L('onboardingStoresHint'), L('skipStoresHint')];
  check(hints.every((h) => !snapshot.includes(h)), 'neither hint line shows');
  check(snapshot.includes(L('storeAddOwn')), '„Add your own store“ shows');

  for (const chip of scenarios.taps) {
    await page.getByRole('checkbox', { name: chip, exact: true }).click();
    taps++;
  }
  for (const { text, pick } of scenarios.typed) {
    await button(L('storeAddOwn')).click();
    taps++;
    await typeInto(page.getByRole('textbox').last(), text);
    if (pick) {
      const suggestion = page.getByRole('button', { name: new RegExp(`\\b${pick} \\(`) });
      await suggestion.first().waitFor({ timeout: 10_000 });
      await page.waitForTimeout(400);
      await capture(page, dir, `02-suggestions-${pick}`);
      log(`suggestions: ${JSON.stringify(await suggestion.allInnerTexts())}`);
      await suggestion.first().click();
    } else {
      await page.keyboard.press('Enter');
    }
    taps++;
    await page.waitForTimeout(400);
  }
  await capture(page, dir, '03-picked');
  await button(L('onboardingNext')).click();
  taps++;
  log(`taps on the store step: ${taps}`);
  if (scenario === 'de' || scenario === 'at') check(taps === 4, 'four taps from the step to every store linked');
  await at('/start/need');
  await page.getByRole('button', { name: new RegExp(`^${L('onboardingNext')}`) }).click();
  await at('/start/account');
  const withEmail = page.getByRole('button', { name: L('continueWithEmail') });
  if (await withEmail.isVisible()) await withEmail.click();
  await typeInto(page.getByRole('textbox', { name: L('email') }), owner);
  await typeInto(page.getByRole('textbox', { name: L('password') }), password);
  await button(L('signUp')).click();
  await page.waitForURL(/\/(your-name|start\/invite)(\?|$)/, { timeout: 30_000 });
  if (page.url().includes('/your-name')) {
    await typeInto(page.getByRole('textbox', { name: new RegExp(`^${L('yourNameLabel')}`) }), 'Mia');
    await button(L('onboardingNext')).click();
  }
  await at('/start/invite');

  const api = createClient(inst.apiUrl, inst.publishableKey, { auth: { persistSession: false } });
  await api.auth.signInWithPassword({ email: owner, password });
  const { data: households } = await api.from('households').select('id');
  check(households?.length === 1, 'one household');
  const { data: stores } = await api
    .from('stores')
    .select('name, retailer_chain, retailer_country, retailer_app, retailer_answered')
    .eq('household_id', households[0].id)
    .order('sort_order');
  log(`stores ${JSON.stringify(stores)}`);
  const made = stores.map((s) => `${s.name}:${s.retailer_chain ? `${s.retailer_chain}/${s.retailer_country}` : ''}`);
  check(
    JSON.stringify(made) === JSON.stringify(scenarios.stores),
    `the stores, in the order picked, with their chains: ${scenarios.stores.join(', ')}`,
  );
  check(
    stores.every((s) => s.retailer_app === null && s.retailer_answered === !!s.retailer_chain),
    'linked stores have the default app and count as answered; own ones stay unanswered',
  );
  const { data: questions } = await api.rpc('retailer_questions', {
    p_household: households[0].id,
    p_country: scenarios.locale.slice(-2),
  });
  check((questions ?? []).length === 0, 'the first list has no chain question to ask');

  // „Partner einladen“ offers „Später“ until an invite exists.
  await button(L('later')).click();
  await at('/');
  await page.waitForTimeout(2000);
  await capture(page, dir, '04-first-list');
  check(errors.length === 0, `no page errors (${errors.join(' | ')})`);
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
}
await browser.close();
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
