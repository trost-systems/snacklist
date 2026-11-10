import { expect, type Locator, type Page, test } from './fixtures';
import {
  addField,
  addItem,
  answerConsent,
  boxOf,
  type Collector,
  createInviteCode,
  eventNames,
  fakeCollector,
  firstOf,
  itemRow,
  must,
  newEmail,
  openMore,
  openTab,
  password,
  putBack,
  screenshot,
  signUp,
  signUpWithHousehold,
  tick,
  typeInto, createHousehold, skipInvite, confirmJoin,
  openEmailSignIn,
  invitePath,
} from './helpers';

// Job 19: analytics to PostHog EU, asked for right after the first sign-in (Peter, 2026-10-27).
// Job 44: through posthog_flutter, posthog-js under it on the web, loaded only after the yes.
// The e2e build points at https://posthog.invalid (app/config/e2e.json), which fakeCollector
// answers: nothing ever leaves the machine. posthog-js sends every 3 s.

/** Long enough for posthog-js' 3 s flush to have happened, had it anything to send. */
const flushWindow = 7_000;

async function quietFor(page: Page, collector: Collector, before: number) {
  // The app sends on a timer; the only way to see that it sent nothing is to wait it out.
  await page.waitForTimeout(flushWindow);
  expect(collector.requests.length, `requests: ${collector.requests.join(', ')}`).toBe(before);
}

/** Wheels the page until [target] is on screen above the tab bar. */
async function wheelIntoView(page: Page, target: Locator): Promise<void> {
  const size = page.viewportSize() ?? { width: 480, height: 900 };
  const tabs = await page.getByRole('tab').first().boundingBox({ timeout: 2000 }).catch(() => null);
  const bottom = tabs ? tabs.y : size.height;
  await page.mouse.move(size.width / 2, size.height / 3);
  await expect(async () => {
    const box = await target.boundingBox();
    if (!box || box.y + box.height > bottom) {
      await page.mouse.wheel(0, 300);
      throw new Error(`${target} is not above the tab bar yet`);
    }
  }).toPass();
}

/** The usage-data switch under More → Nutzungsdaten (job 85; a switch, or a checkbox for some engines). */
async function analyticsSwitch(page: Page) {
  await openMore(page, 'Nutzungsdaten');
  await expect(page).toHaveURL(/\/more\/usage-data$/);
  await expect(page.getByRole('heading', { name: 'Nutzungsdaten', exact: true })).toBeVisible();
  const toggle = page.getByRole('switch', { name: /^Nutzungsdaten und Fehlerberichte senden/ })
    .or(page.getByRole('checkbox', { name: /^Nutzungsdaten und Fehlerberichte senden/ }));
  await wheelIntoView(page, toggle);
  return toggle;
}

/**
 * The install id in localStorage (shared_preferences on the web), or null. Job 33b (legal review
 * H-08): it exists only after a yes, and turning analytics off deletes it.
 */
async function storedInstallId(page: Page): Promise<string | null> {
  // The key is `analytics.install_id` (shared_preferences' async web store has no `flutter.` prefix).
  // A yes must find it, so the "absent" checks cannot pass on a wrong key.
  const raw = await page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /(^|\.)analytics\.install_id$/.test(k));
    return key === undefined ? null : localStorage.getItem(key);
  });
  if (raw === null) return null;
  const value: unknown = JSON.parse(raw);
  return (typeof value === 'string' && value.startsWith('"') ? JSON.parse(value) : value) as string;
}

/**
 * Every property key a web event may leave the browser with (`webEventKeys` in
 * app/lib/analytics/events.dart): the context, the event's own, the error report's, and what
 * posthog-js adds about the browser. Never its URL, referrer, user agent, session or device id.
 */
const allowedKeys = new Set([
  'install_id', 'household_id', 'platform', 'app_version', 'is_internal', '$geoip_disable',
  '$process_person_profile', '$groups', '$exception_list', '$exception_level',
  'token', 'distinct_id', '$lib', '$lib_version', '$os', '$os_version', '$browser', '$browser_version',
  '$browser_language', '$device_type', '$screen_height', '$screen_width', '$viewport_height',
  '$viewport_width', '$timezone',
  'source', 'actor_role', 'household_size', 'default_stores', 'store_count', 'method', 'channel', 'context', 'scope',
  'via', 'category', 'entry_point', 'screen', 'contact_ok',
  // The guided start's onboarding_completed and the hints' events (job 168b).
  'kind', 'kind_count', 'item_count', 'invited', 'hint_id', 'step', 'open_steps',
]);

function expectAllowedKeys(collector: Collector) {
  for (const e of collector.events) {
    expect(Object.keys(e.properties).filter((k) => !allowedKeys.has(k)), `${e.event}: keys off the list`).toEqual([]);
    expect(Object.keys(e).sort(), `${e.event}: no $set`).toEqual(['event', 'properties', 'timestamp', 'uuid']);
  }
}

/** Whether posthog-js was fetched or runs in [page]: never before the yes. */
function posthogJsLoaded(page: Page): Promise<boolean> {
  return page.evaluate(() => 'posthog' in window ||
    performance.getEntriesByType('resource').some((r) => r.name.includes('posthog/array.js')));
}

/** No PostHog cookie or storage key in [page]: posthog-js keeps its state in memory. */
async function expectNoPostHogStorage(page: Page) {
  const keys = await page.evaluate(() => [...Object.keys(localStorage), ...Object.keys(sessionStorage), document.cookie]);
  expect(keys.filter((k) => /ph_|posthog/i.test(k))).toEqual([]);
}

async function received(collector: Collector, names: string[]) {
  await expect
    .poll(() => eventNames(collector).filter((n) => names.includes(n)), { timeout: 15_000 })
    .toEqual(names);
}

/** The collector's log as a page, for the PR's screenshot. */
async function showLog(page: Page, title: string, collector: Collector) {
  const rows = collector.events.map((e) => {
    const p = e.properties;
    const extra = ['source', 'method', 'scope', 'actor_role', 'household_size']
      .filter((k) => k in p).map((k) => `${k}=${p[k]}`).join(' ');
    return `${e.event.padEnd(18)} household_id=${String(p.household_id).slice(0, 8)}… ` +
      `is_internal=${p.is_internal} $geoip_disable=${p.$geoip_disable} ${extra}`;
  });
  const html = `<pre style="font: 14px/1.5 monospace; padding: 16px">${title}\n` +
    `requests to the PostHog stand-in: ${collector.requests.length}\n` +
    `requests to a real PostHog host: ${collector.leaks.length}\n\n${rows.join('\n')}</pre>`;
  await page.setViewportSize({ width: 1100, height: 520 });
  await page.setContent(html.replace(/&/g, '&amp;'));
}

test('sign-in, then consent, then onboarding; declining sends nothing, ever', async ({ browser }) => {
  const context = await browser.newContext();
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await page.goto('/login');
  await expect(page.getByRole('button', { name: 'Weiter mit E-Mail' })).toBeVisible();
  expect(await storedInstallId(page), 'no install id at the login').toBeNull();
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), newEmail('consent-no'));
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();

  await expect(page).toHaveURL(/\/analytics-consent$/);
  // Job 33b (legal review H-03): who asks, what for, pseudonymous, and a link to the policy.
  await expect(page.getByRole('heading', { name: 'Darf Snacklist Nutzungsdaten erfassen?' })
    .or(page.getByText('Darf Snacklist Nutzungsdaten erfassen?'))).toBeVisible();
  await expect.poll(() => page.locator('body').ariaSnapshot(), { message: 'the consent text as the review wrote it' })
    .toMatch(/Snacklist \(Anbieter: Peter Trost\)[\s\S]*Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet\./);
  const policy = page.getByRole('link', { name: 'Datenschutzerklärung', exact: true });
  await expect(policy).toHaveAttribute('href', 'https://snacklist.app/datenschutz');
  await expect.poll(() => page.locator('body').ariaSnapshot(), { message: 'approved wording: no draft mark' })
    .not.toMatch(/ENTWURF/);
  await screenshot(page, 'analytics-01-consent-after-sign-in');
  await context.route('https://snacklist.app/**', (route) =>
    route.fulfill({ contentType: 'text/html', body: '<title>snacklist.app</title>' }));
  const popup = page.waitForEvent('popup');
  await policy.scrollIntoViewIfNeeded();
  await policy.click();
  expect((await popup).url(), 'the policy opens in a new tab').toBe('https://snacklist.app/datenschutz');
  await (await popup).close();
  await expect(page, 'still asking').toHaveURL(/\/analytics-consent$/);
  expect(collector.requests, 'the login screen sent nothing').toEqual([]);
  expect(await storedInstallId(page), 'no install id before the answer').toBeNull();
  expect(await posthogJsLoaded(page), 'posthog-js is not even fetched before the answer').toBe(false);

  await answerConsent(page, 'decline');
  await expect(page).toHaveURL(/\/welcome$/);
  expect(await storedInstallId(page), 'no install id after a no').toBeNull();
  await screenshot(page, 'analytics-02-declined-then-welcome');
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Hafermilch');
  await tick(page, 'Hafermilch');
  await quietFor(page, collector, 0);
  expect(await posthogJsLoaded(page), 'nor after a no').toBe(false);

  // The switch under More → Nutzungsdaten shows the decision.
  await expect(await analyticsSwitch(page)).not.toBeChecked();
  expect(collector.leaks).toEqual([]);
  const log = await context.newPage();
  const after = await storedInstallId(page);
  await showLog(log, 'Declined at the consent screen, then: household, add, tick.\n' +
    `localStorage analytics.install_id at the login, on the consent screen, after the no, now: null, null, null, ${after}`, collector);
  await screenshot(log, 'analytics-03-collector-declined');
});

test('accepting sends first_open once, then one event per action, no list text; off stops at once', async ({ browser }) => {
  const context = await browser.newContext();
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  const email = newEmail('consent-yes');
  await signUp(page, email, '/', { consent: 'accept' });
  await expect(page).toHaveURL(/\/welcome$/);
  // The router moves on at the answer; the id is written right after.
  await expect.poll(() => storedInstallId(page), { message: 'a yes stores an install id' }).toMatch(/^[0-9a-f-]{36}$/);
  const installId = await storedInstallId(page);
  await createHousehold(page, { name: 'Familie Geheim' });
  await skipInvite(page);
  await received(collector, ['first_open', 'household_created']);

  await addItem(page, 'Hafermilch');
  await addItem(page, 'Brot');
  await tick(page, 'Hafermilch');
  await received(collector, ['first_open', 'household_created', 'item_added', 'item_added', 'item_ticked']);

  // Putting it back right away under "Zuletzt verwendet" is the undo and sends nothing; ticking
  // again is a new action.
  await tick(page, 'Brot');
  await putBack(page, 'Brot');
  await tick(page, 'Brot');
  await received(collector, [
    'first_open', 'household_created', 'item_added', 'item_added', 'item_ticked', 'item_ticked', 'item_ticked',
  ]);

  const byName = (name: string) => collector.events.filter((e) => e.event === name);
  const ticked = firstOf(byName('item_ticked'), 'item_ticked event');
  const household = ticked.properties.household_id as string;
  expect(household).toMatch(/^[0-9a-f-]{36}$/);
  expect(byName('first_open')).toHaveLength(1);
  expect(firstOf(byName('first_open'), 'first_open event').properties.household_id).toBeUndefined();
  expect(firstOf(byName('household_created'), 'household_created event').properties.household_id).toBe(household);
  expect(byName('item_added').map((e) => e.properties.source)).toEqual(['typed', 'typed']);
  expect(ticked.properties.actor_role).toBe('owner');
  expect(ticked.properties.household_size).toBe(1);
  for (const e of collector.events) {
    expect(e.properties.install_id, 'every event carries the stored install id').toBe(installId);
    expect(e.uuid).toMatch(/^[0-9a-f-]{36}$/);
    expect(e.properties.distinct_id).toBe(e.properties.install_id);
    expect(e.properties.$process_person_profile).toBe(false);
    expect(e.properties.$geoip_disable).toBe(true);
    expect(e.properties.platform).toBe('web');
    // A test account: e2e mail domains are reserved test domains.
    expect(e.properties.is_internal).toBe(true);
    expect('$ip' in e.properties).toBe(false);
  }
  expectAllowedKeys(collector);
  await expectNoPostHogStorage(page);
  const sent = JSON.stringify(collector.events) + collector.bodies.join('');
  for (const secret of ['Hafermilch', 'Brot', 'Familie Geheim', email, email.split('@')[0], '127.0.0.1']) {
    expect(sent, `no "${secret}" in what was sent`).not.toContain(secret);
  }

  // A reload is the same install: no second first_open.
  await page.reload();
  await expect(addField(page)).toBeVisible();
  await addItem(page, 'Käse');
  await received(collector, [
    'first_open', 'household_created', 'item_added', 'item_added', 'item_ticked', 'item_ticked', 'item_ticked', 'item_added',
  ]);

  // Off under More → Nutzungsdaten: nothing more, at once.
  const toggle = await analyticsSwitch(page);
  await expect(toggle).toBeChecked();
  await screenshot(page, 'analytics-04-more-switch-on');
  await toggle.click();
  await expect(toggle).not.toBeChecked();
  await expect.poll(() => storedInstallId(page), { message: 'off deletes the install id' }).toBeNull();
  await screenshot(page, 'analytics-05-more-switch-off');
  const before = collector.requests.length;
  await openTab(page, 'Liste');
  await tick(page, 'Käse');
  await quietFor(page, collector, before);
  expect(collector.leaks).toEqual([]);
  const log = await context.newPage();
  await showLog(log, 'Accepted; household, 3 adds, 3 ticks (one undone), reload; then switched off and ticked.\n' +
    `localStorage analytics.install_id after the yes: ${installId}; after switching off: ${await storedInstallId(page)}`, collector);
  await screenshot(log, 'analytics-06-collector-accepted');
});

test('in English: the consent text links the English policy; the switch under More → Usage data', async ({ browser }) => {
  const context = await browser.newContext({ locale: 'en-US' });
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await page.goto('/login');
  await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
  await typeInto(page.getByRole('textbox', { name: 'Email' }), newEmail('consent-en'));
  await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
  await page.getByRole('button', { name: 'Sign up' }).click();
  await expect(page).toHaveURL(/\/analytics-consent$/);
  await expect.poll(() => page.locator('body').ariaSnapshot(), { message: 'the English consent text as the review wrote it' })
    .toMatch(/May Snacklist collect usage data\?[\s\S]*Snacklist \(run by Peter Trost\)[\s\S]*List contents, names and e-mail addresses are never sent\./);
  await screenshot(page, 'analytics-07-consent-en');
  await context.route('https://snacklist.app/**', (route) =>
    route.fulfill({ contentType: 'text/html', body: '<title>snacklist.app</title>' }));
  const english = page.getByRole('link', { name: 'privacy policy', exact: true });
  await expect(english).toHaveAttribute('href', 'https://snacklist.app/en/privacy');
  const popup = page.waitForEvent('popup');
  await english.click();
  expect((await popup).url(), 'the English policy, in a new tab').toBe('https://snacklist.app/en/privacy');
  await (await popup).close();

  const allow = page.getByRole('button', { name: 'Allow', exact: true });
  const size = page.viewportSize() ?? { width: 400, height: 800 };
  await page.mouse.move(size.width / 2, size.height / 2);
  await expect(async () => {
    if (!(await allow.isVisible())) await page.mouse.wheel(0, 400);
    await expect(allow).toBeVisible({ timeout: 500 });
  }).toPass();
  await allow.click();
  await createHousehold(page, { lang: 'en' });
  await page.getByRole('button', { name: /^(Later|Go to the list)$/ }).click();
  await expect(page.getByRole('textbox', { name: 'What do you need?' })).toBeVisible();
  await expect.poll(() => storedInstallId(page), { message: 'a yes stores an install id' }).toMatch(/^[0-9a-f-]{36}$/);

  await page.getByRole('tab', { name: 'More', exact: true }).or(page.getByRole('button', { name: /^More Tab / })).click();
  await expect(page).toHaveURL(/\/more$/);
  await page.getByRole('button', { name: 'Usage data', exact: true }).click();
  await expect(page).toHaveURL(/\/more\/usage-data$/);
  await expect(page.getByRole('heading', { name: 'Usage data', exact: true })).toBeVisible();
  const toggle = page.getByRole('switch', { name: /^Send usage data and error reports/ })
    .or(page.getByRole('checkbox', { name: /^Send usage data and error reports/ }));
  await wheelIntoView(page, toggle);
  await expect(toggle).toBeChecked();
  await expect(toggle).toHaveAccessibleName(/Turning it off deletes the ID on this device/);
  await expect(toggle, 'approved wording: no draft mark').not.toHaveAccessibleName(/DRAFT/);
  await screenshot(page, 'analytics-08-more-switch-en');
  await toggle.click();
  await expect.poll(() => storedInstallId(page), { message: 'off deletes the install id' }).toBeNull();
  expect(collector.leaks).toEqual([]);
});

test('an invite link survives sign-in and consent, ends on joining, and counts as invite_accepted by link', async ({ browser }) => {
  const owner = await (await browser.newContext()).newPage();
  await signUpWithHousehold(owner, newEmail('consent-owner'));
  const code = await createInviteCode(owner);

  const context = await browser.newContext();
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await page.goto(invitePath(code));
  await expect(page).toHaveURL(new RegExp(`/login\\?invite=${code}$`));
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), newEmail('consent-member'));
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();
  await expect(page).toHaveURL(new RegExp(`/analytics-consent\\?invite=${code}$`));
  await answerConsent(page, 'accept');
  // Job 22: the invite skips Step 1 and opens the join screen with the household's name.
  await expect(page).toHaveURL(new RegExp(`/join/${code}$`));
  await confirmJoin(page, 'Unser Haushalt');
  await expect(addField(page)).toBeFocused();
  await received(collector, ['first_open', 'invite_accepted']);
  const joined = must(collector.events.find((e) => e.event === 'invite_accepted'), 'invite_accepted event');
  expect(joined.properties.method).toBe('link');
  expect(joined.properties.household_id).toMatch(/^[0-9a-f-]{36}$/);
  expect(JSON.stringify(collector.events) + collector.bodies.join(''), 'no invite code, not even in a URL').not.toContain(code);
  expectAllowedKeys(collector);
});

test('a member with a household is asked once on a new install, then goes to the list', async ({ browser }) => {
  const email = newEmail('consent-existing');
  const first = await (await browser.newContext()).newPage();
  await signUpWithHousehold(first, email);
  await addItem(first, 'Kaffee');

  const context = await browser.newContext();
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await page.goto('/login');
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(page).toHaveURL(/\/analytics-consent$/);
  await screenshot(page, 'analytics-07-consent-before-list');
  await answerConsent(page, 'decline');
  await expect(addField(page)).toBeFocused();
  await expect(itemRow(page, 'Kaffee')).toBeVisible();
  await screenshot(page, 'analytics-08-declined-then-list');

  // Signing out and in again on this install does not ask again.
  await openMore(page, 'Abmelden');
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(addField(page)).toBeFocused();
  expect(collector.requests).toEqual([]);
});

test('an internal device sends a test error, scrubbed, to error tracking', async ({ browser }) => {
  const context = await browser.newContext();
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await signUp(page, newEmail('errors'), '/', { consent: 'accept' });
  await createHousehold(page);
  await skipInvite(page);
  await openTab(page, 'Mehr');
  await expect(page).toHaveURL(/\/more$/);
  // More is a lazy list: wheel down to the version line at its end.
  await page.mouse.move(240, 400);
  const version = page.getByText(/^Version /);
  await expect(async () => {
    await page.mouse.wheel(0, 800);
    await expect(version).toBeVisible({ timeout: 500 });
  }).toPass();
  // Let the scroll settle before measuring where to press.
  await page.waitForTimeout(500);
  const box = await boxOf(version);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(1_000);
  await page.mouse.up();
  // "Interne Installation" and "Testfehler senden" show below the version: wheel down to them.
  const testError = page.getByRole('button', { name: 'Testfehler senden' });
  await expect(async () => {
    await page.mouse.wheel(0, 400);
    await expect(testError).toBeVisible({ timeout: 500 });
  }).toPass();
  await page.waitForTimeout(500);
  await testError.click();

  await expect.poll(() => eventNames(collector).includes('$exception'), { timeout: 15_000 }).toBe(true);
  const error = must(collector.events.find((e) => e.event === '$exception'), '$exception event');
  const exception = firstOf(error.properties.$exception_list as {
    type: string; value: string; mechanism: { handled: boolean }; stacktrace?: { frames: unknown[] };
  }[], 'exception in $exception_list');
  expect(exception.type).toBe('StateError');
  expect(exception.value).toBe('Bad state: <w> error (<w>, <w>)');
  expect(exception.mechanism.handled).toBe(false);
  expect(exception.stacktrace?.frames.length ?? 0).toBeGreaterThan(0);
  expect(error.properties.is_internal).toBe(true);
  expect(error.properties.household_id).toMatch(/^[0-9a-f-]{36}$/);
  expectAllowedKeys(collector);
  expect(collector.leaks).toEqual([]);
});

/**
 * The raw localStorage key of `analytics.consent_text_version`, and its value, or null. The app
 * stores it with every decision (Legal Review 2026-11-01, addendum 12:35).
 */
function storedTextVersion(page: Page): Promise<{ key: string; raw: string } | null> {
  return page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /(^|\.)analytics\.consent_text_version$/.test(k));
    const raw = key === undefined ? null : localStorage.getItem(key);
    return key === undefined || raw === null ? null : { key, raw };
  });
}

// Legal Review 2026-11-01, addendum 12:35: a yes counts only for the consent text it was given
// under. A yes an older build stored (no version) or one under an older text is no decision: the
// app asks again and sends nothing to PostHog before the new yes, no event and no /flags lookup.
for (const [label, outdate] of [
  ['without a version (an older build)', (_raw: string) => null],
  ['under the 2026-10-30 text', (raw: string) => raw.replace('2026-11-11', '2026-10-30')],
] as const) {
  test(`a yes ${label} is asked again; nothing goes to PostHog before the new yes`, async ({ browser }) => {
    const context = await browser.newContext();
    const collector = await fakeCollector(context);
    const page = await context.newPage();
    await signUp(page, newEmail('consent-version'), '/', { consent: 'accept' });
    await expect(page).toHaveURL(/\/welcome$/);
    await expect.poll(() => storedInstallId(page)).toMatch(/^[0-9a-f-]{36}$/);
    const stored = await storedTextVersion(page);
    expect(stored?.raw, 'the yes is stored with the current version').toContain('2026-11-11');
    if (stored === null) throw new Error('no stored consent text version');
    await received(collector, ['first_open']);
    expect(collector.requests.some((r) => r.startsWith('POST /flags')), 'a current yes asks for flags')
      .toBe(true);

    // What an older build (or the older text) left: the yes stays, the version goes or ages.
    const outdated = outdate(stored.raw);
    await page.evaluate(({ key, raw }) => {
      if (raw === null) localStorage.removeItem(key);
      else localStorage.setItem(key, raw);
    }, { key: stored.key, raw: outdated });
    collector.requests.length = 0;
    collector.events.length = 0;
    await page.reload();

    await expect(page, 'asked again').toHaveURL(/\/analytics-consent$/);
    await expect(page.getByRole('button', { name: 'Erlauben', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Nicht erlauben', exact: true })).toBeVisible();
    await quietFor(page, collector, 0);
    expect(collector.requests, 'no event, no /flags').toEqual([]);
    expect(await posthogJsLoaded(page), 'posthog-js is not even fetched').toBe(false);
    expect(await storedInstallId(page), 'the old install id is gone, as on a no').toBeNull();
    expect(collector.leaks).toEqual([]);

    await answerConsent(page, 'accept');
    await expect.poll(() => storedTextVersion(page).then((v) => v?.raw)).toContain('2026-11-11');
    await received(collector, ['first_open']);
    await expect.poll(() => collector.requests.some((r) => r.startsWith('POST /flags')),
      { message: 'flags work again after the new yes' }).toBe(true);
    expect(collector.leaks).toEqual([]);
    await context.close();
  });
}
