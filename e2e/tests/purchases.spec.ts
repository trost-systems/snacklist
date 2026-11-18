import { type Browser, expect, type Page, test } from './fixtures';
import {
  adminClient,
  apiAs,
  functionsUrl,
  joinWithCode,
  newEmail,
  openPremium,
  password,
  screenshot,
  signUp,
  signUpWithHousehold,
  typeInto,
  openEmailSignIn,
  createHousehold,
} from './helpers';
import { buy, claim, householdOf, rcEvent, report } from './iap';

// Job 25, as of job 43: Snacklist Lifetime on the web (docs/PURCHASES.md). The web never sells: More
// shows the household's unlock, and (job 87, Legal Review's final texts) says where to buy only once
// sales start (premium_offer on; off on the e2e stack). RevenueCat's
// part is played by events posted to the real webhook with the local secret (iap.ts), so the
// purchase runs through the function, Postgres, RLS and Realtime (with the H-55 column grants).

const newPage = async (browser: Browser) => await (await browser.newContext()).newPage();

const lifetimeRow = (page: Page) => page.getByRole('button', { name: /^Snacklist Premium/ });
const webNote = (page: Page) => page.getByText(/^Snacklist Premium kaufst du in der iPhone- oder Android-App\./);
/** The status tile: its title says which Premium the household has (job 49). */
const unlocked = (page: Page) => page.getByText(/^Snacklist Premium (Lifetime|aktiv|über)/);
/** Job 87: PW-P4's hero body, on every state of the page, the web's included. */
const hero = (page: Page) => page.getByText('Snacklist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.');
/** Its buying slogan, only while sales are on (Legal Review N-68): never on the e2e stack. */
const slogan = (page: Page) => page.getByText('Einer kauft. Alle haben es.');

test('the web shows the unlock live for both partners, sells nothing, and a refund locks again', async ({ browser }) => {
  const peterEmail = newEmail('iap-peter');
  const leaEmail = newEmail('iap-lea');
  const peter = await newPage(browser);
  // H-67: nothing on the page (or before it) talks to RevenueCat.
  const revenueCat: string[] = [];
  peter.on('request', (r) => {
    if (/revenuecat/i.test(new URL(r.url()).hostname)) revenueCat.push(r.url());
  });
  await peter.setViewportSize({ width: 390, height: 844 });
  await signUpWithHousehold(peter, peterEmail);
  const household = await householdOf(peterEmail);
  const { data: invite, error } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household });
  if (error) throw error;
  const lea = await newPage(browser);
  await signUp(lea, leaEmail);
  await joinWithCode(lea, (Array.isArray(invite) ? invite[0] : invite).code);

  await openPremium(peter);
  await expect(peter).toHaveURL(/\/more\/lifetime$/);
  await expect(hero(peter)).toBeVisible();
  await expect(slogan(peter), 'no buying slogan while nothing is sold (N-68)').toHaveCount(0);
  await expect(peter.getByText(/^Doppelt gekauft\?/), 'no refund link before sales start (N-69)').toHaveCount(0);
  await expect(peter.getByText(/ChatGPT|Claude/), 'no assistant brand (N-67)').toHaveCount(0);
  await expect(webNote(peter), 'nothing about buying before sales start').toHaveCount(0);
  await expect(peter.getByText(/€|\d,\d\d/), 'no price on the web').toHaveCount(0);
  await expect(peter.getByRole('button', { name: /Weiter zum Kauf|kaufen|abschließen/ }), 'no buy button on the web').toHaveCount(0);
  await expect(peter.getByRole('button', { name: 'Kauf wiederherstellen' }), 'no restore on the web').toHaveCount(0);
  await expect(unlocked(peter)).toHaveCount(0);
  expect(revenueCat, 'no request to RevenueCat from app start or the Lifetime page').toEqual([]);
  await screenshot(peter, 'job25-web-de-390');
  await peter.setViewportSize({ width: 1366, height: 1024 });
  await expect(hero(peter)).toBeVisible();
  await expect(webNote(peter), 'nothing about buying before sales start').toHaveCount(0);
  await screenshot(peter, 'job25-web-de-1366');
  await peter.setViewportSize({ width: 390, height: 844 });
  await openPremium(lea);
  await expect(hero(lea)).toBeVisible();
  await expect(webNote(lea), 'nothing about buying before sales start').toHaveCount(0);

  // Peter buys on his iPhone; both web pages show it without a reload.
  const transactionId = `2000${Date.now()}`;
  const peterHousehold = await householdOf(peterEmail);
  expect(await buy(peterEmail, transactionId)).toBe('granted');
  await expect(unlocked(peter), 'the buyer sees it live').toBeVisible({ timeout: 10_000 });
  await expect(unlocked(lea), 'the partner sees it live, without buying').toBeVisible({ timeout: 10_000 });
  await screenshot(peter, 'job25-unlocked-web-de-390');
  await peter.setViewportSize({ width: 1366, height: 1024 });
  await screenshot(peter, 'job25-unlocked-web-de-1366');
  await peter.setViewportSize({ width: 390, height: 844 });

  // The same transaction again (a restore on Lea's phone) only restores; a retried event does nothing.
  expect(await report(leaEmail, transactionId), 'Lea restores the purchase on her phone').toBe('restored');
  const id = crypto.randomUUID();
  await rcEvent('NON_RENEWING_PURCHASE', peterHousehold, transactionId, { id });
  expect((await rcEvent('NON_RENEWING_PURCHASE', peterHousehold, transactionId, { id })).body).toEqual({ status: 'duplicate' });
  expect((await claim(leaEmail, transactionId)).body, 'Peter claimed it first').toEqual({ status: 'taken' });

  // Peter's transaction reported for Max's household (a transfer, a replay): refused.
  const maxEmail = newEmail('iap-max');
  const max = await newPage(browser);
  await signUpWithHousehold(max, maxEmail);
  expect(await report(maxEmail, transactionId)).toBe('used_elsewhere');
  expect((await rcEvent('TRANSFER', await householdOf(maxEmail), transactionId)).body).toEqual({ status: 'ignored' });
  await openPremium(max);
  await expect(hero(max)).toBeVisible();
  await expect(webNote(max), 'nothing about buying before sales start').toHaveCount(0);
  await expect(unlocked(max), 'Max stays locked').toHaveCount(0);

  // Without RevenueCat's secret nothing is recorded.
  expect(await rcEvent('NON_RENEWING_PURCHASE', await householdOf(maxEmail), `${transactionId}9`, { authorization: 'Bearer forged' }))
    .toEqual({ status: 401, body: { error: 'invalid_token' } });
  await expect(unlocked(max)).toHaveCount(0);

  // Apple refunds it (RevenueCat's CANCELLATION): the unlock goes for both, live.
  expect((await rcEvent('CANCELLATION', peterHousehold, transactionId)).body).toEqual({ status: 'revoked' });
  expect((await rcEvent('CANCELLATION', peterHousehold, transactionId)).body, 'a repeated refund changes nothing')
    .toEqual({ status: 'unchanged' });
  await expect(unlocked(peter)).toHaveCount(0, { timeout: 10_000 });
  await expect(unlocked(lea)).toHaveCount(0, { timeout: 10_000 });
  await expect(hero(lea)).toBeVisible();
  await expect(webNote(lea), 'nothing about buying before sales start').toHaveCount(0);
  expect(await report(peterEmail, transactionId), 'a refunded purchase does not unlock again').toBe('revoked');
});

test('More lists Premium only once the household has it (premium_offer off), live', async ({ page }) => {
  const email = newEmail('iap-row');
  await page.setViewportSize({ width: 390, height: 844 });
  await signUpWithHousehold(page, email);
  await page.getByRole('tab', { name: 'Mehr' }).click();
  await expect(page.getByRole('button', { name: /^Leute einladen/ })).toBeVisible();
  await expect(lifetimeRow(page), 'not listed before the launch (job 64)').toHaveCount(0);
  await screenshot(page, 'job25-more-de-390');
  expect(await buy(email, `2001${Date.now()}`)).toBe('granted');
  await expect(lifetimeRow(page), 'listed once the household has it, live').toBeVisible({ timeout: 10_000 });
  await screenshot(page, 'job25-more-unlocked-de-390');
  await page.setViewportSize({ width: 1366, height: 1024 });
  await expect(lifetimeRow(page)).toBeVisible();
  await screenshot(page, 'job25-more-unlocked-de-1366');
});

test('a household given Premium in the beta sees the approved beta texts, nothing to buy (N-53)', async ({ page }) => {
  const email = newEmail('iap-beta');
  await page.setViewportSize({ width: 390, height: 844 });
  await signUpWithHousehold(page, email);
  const { data, error } = await adminClient().rpc('promotional_premium_sync',
    { p_household: await householdOf(email), p_active: true, p_expires_at: new Date(Date.now() + 60 * 86_400_000).toISOString() });
  expect(error).toBeNull();
  expect(data).toBe('granted');
  await openPremium(page);
  await expect(page.getByText('In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet'))
    .toBeVisible({ timeout: 10_000 });
  await expect(hero(page)).toBeVisible();
  await expect(slogan(page), 'no buying slogan above „Du zahlst nichts“ (N-68)').toHaveCount(0);
  await expect(page.getByText('Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose '
    + 'Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Mehr dazu in der Datenschutzerklärung' }))
    .toHaveAttribute('href', 'https://snacklist.app/datenschutz#premium-beta');
  await expect(page.getByText(/Test und App-Prüfung/), 'premium_offer is off: the beta line').toHaveCount(0);
  await expect(page.getByText(/Danke!|bald verfügbar|kaufst du in der/), 'hidden before sales start').toHaveCount(0);
  await expect(page.getByText(/€/)).toHaveCount(0);
  await expect(page.getByRole('button', { name: /kaufen|abschließen|wiederherstellen/ })).toHaveCount(0);
  await screenshot(page, 'job87-beta-web-de-390');
});

test.describe('in English', () => {
  test.use({ locale: 'en-US' });

  test('the page shows the hero, nothing to buy, and Unlocked', async ({ page }) => {
    const email = newEmail('iap-en');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/login');
    await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
    await typeInto(page.getByRole('textbox', { name: 'Email' }), email);
    await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
    await page.getByRole('button', { name: 'Sign up' }).click();
    await page.getByRole('button', { name: "Don't allow", exact: true }).click();
    await createHousehold(page, { lang: 'en' });
    // The invite step stays until it is left.
    await page.getByRole('button', { name: 'Later', exact: true }).click();
    await expect(page.getByRole('textbox', { name: 'What do you need?' })).toBeVisible();
    await page.goto('/more/lifetime');
    await expect(page.getByText('Snacklist Premium covers your whole household, including everyone who joins later.')).toBeVisible();
    await expect(page.getByText('One buys. Everyone has it.')).toHaveCount(0);
    await expect(page.getByText(/^You can buy Snacklist Premium in the iPhone or Android app\./),
      'nothing about buying before sales start').toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Restore purchase' })).toHaveCount(0);
    await screenshot(page, 'job25-web-en-390');
    await page.setViewportSize({ width: 1366, height: 1024 });
    await screenshot(page, 'job25-web-en-1366');
    expect(await buy(email, `2002${Date.now()}`)).toBe('granted');
    await expect(page.getByText(/^Snacklist Premium Lifetime/)).toBeVisible({ timeout: 10_000 });
    await screenshot(page, 'job25-unlocked-web-en-1366');
    await page.setViewportSize({ width: 390, height: 844 });
    await screenshot(page, 'job25-unlocked-web-en-390');
  });
});
