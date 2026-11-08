import { type Browser, expect, type Page, test } from './fixtures';
import {
  addItem,
  apiAs,
  createHousehold,
  householdChip,
  itemRow,
  joinWithCode,
  newEmail,
  openMore,
  openPremium,
  password,
  screenshot,
  signUp,
  signUpWithHousehold,
  skipInvite,
  switchHousehold,
  typeInto,
  openEmailSignIn,
} from './helpers';
import { buy, householdOf, rcEvent, subscribe, yearlyId } from './iap';

// Job 49: Hummlist Premium as a yearly plan and Lifetime, on the web (docs/PURCHASES.md). The web
// sells nothing; it shows the household's Premium, live for every member, from RevenueCat's
// lifecycle events posted to the real webhook (iap.ts). Ending a plan deletes nothing. A plan that
// keeps being billed is said before deleting the account or leaving the household (H-85).

const newPage = async (browser: Browser) => await (await browser.newContext()).newPage();

const status = (page: Page) => page.getByText(/^Hummlist Premium (Lifetime|aktiv|über)/);
const renews = (page: Page) => page.getByText(/^Hummlist Premium aktiv \(jährlich, verlängert sich am /);
const ends = (page: Page) => page.getByText(/^Hummlist Premium aktiv \(jährlich, läuft am /);
/** The web's manage note: a group named by its text, with the two store links in it. */
const manageOnWeb = (page: Page) =>
  page.getByRole('group', { name: 'Dein Jahresabo verwaltest du im App Store oder bei Google Play.' });
/** The note after Lifetime: its sentence as text, the store page as a link of its own. */
const lifetimeWhileYearly = (page: Page, rest: RegExp) =>
  page.getByText(new RegExp(`^Euer Haushalt hat schon ein Jahresabo\\..*${rest.source}`));
const billingContinues = (page: Page) =>
  page.getByText(/^Dein Jahresabo für Hummlist Premium läuft weiter und wird über dein Apple- bzw\. Google-Konto/);
const billingOther = (page: Page) =>
  page.getByText('Ein Jahresabo für diesen Haushalt läuft weiter, bis es gekündigt wird.');

/** A fresh invite code for [email]'s household, through their own API client. */
async function inviteCode(email: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).rpc('create_invite', { p_household: await householdOf(email) });
  if (error) throw error;
  return (Array.isArray(data) ? data[0] : data).code;
}

/** Peter's household with Lea in it; both pages signed in. */
async function couple(browser: Browser, tag: string) {
  const peterEmail = newEmail(`${tag}-peter`);
  const leaEmail = newEmail(`${tag}-lea`);
  const peter = await newPage(browser);
  await peter.setViewportSize({ width: 390, height: 844 });
  await signUpWithHousehold(peter, peterEmail);
  const code = await inviteCode(peterEmail);
  const lea = await newPage(browser);
  await lea.setViewportSize({ width: 390, height: 844 });
  await signUp(lea, leaEmail);
  await joinWithCode(lea, code);
  return { peter, lea, peterEmail, leaEmail, household: await householdOf(peterEmail) };
}

test('a yearly plan: live for both partners, cancelled it runs to its end, expired the list and '
  + 'integrations stay', async ({ browser }) => {
  const { peter, lea, peterEmail, household } = await couple(browser, 'yearly');
  const revenueCat: string[] = [];
  peter.on('request', (r) => {
    if (/revenuecat/i.test(new URL(r.url()).hostname)) revenueCat.push(r.url());
  });
  await addItem(peter, 'Milch');
  const pat = await (await apiAs(peterEmail)).rpc('create_personal_access_token', { p_name: 'Kurzbefehl' });
  expect(pat.error).toBeNull();

  await openPremium(peter);
  await openPremium(lea);
  await expect(status(lea)).toHaveCount(0);

  // Peter subscribes on his iPhone; both pages show it live. The web never offers Buy.
  const tx = `4900${Date.now()}`;
  expect(await subscribe(peterEmail, tx)).toBe('granted');
  await expect(renews(peter), 'the subscriber sees it live').toBeVisible({ timeout: 10_000 });
  await expect(renews(lea), 'the partner sees it live, without buying').toBeVisible({ timeout: 10_000 });
  await expect(lea.getByRole('button', { name: /abschließen|kaufen/ }), 'Lea never sees Buy').toHaveCount(0);
  await expect(manageOnWeb(lea)).toBeVisible();
  await screenshot(lea, 'job49-web-yearly-renews-de-390');

  // Peter turns auto-renew off: premium stays until the end, the line says so (H-81).
  expect((await rcEvent('CANCELLATION', household, tx, {
    productId: yearlyId,
    extra: { cancel_reason: 'UNSUBSCRIBE' },
  })).body).toEqual({ status: 'updated' });
  await expect(ends(lea), 'cancelled, it runs to its end').toBeVisible({ timeout: 10_000 });
  await screenshot(lea, 'job49-web-yearly-ends-de-390');

  // The plan expires: Premium is off for both, live; the list and the token stay.
  expect((await rcEvent('EXPIRATION', household, tx, { productId: yearlyId, expiresInDays: -1 })).body)
    .toEqual({ status: 'updated' });
  await expect(status(peter)).toHaveCount(0, { timeout: 10_000 });
  await expect(status(lea)).toHaveCount(0, { timeout: 10_000 });
  await expect(manageOnWeb(lea)).toHaveCount(0);
  const { data: tokens } = await (await apiAs(peterEmail)).from('personal_access_tokens')
    .select('name, revoked_at');
  expect(tokens, 'expiry revokes no integration').toEqual([{ name: 'Kurzbefehl', revoked_at: null }]);
  await peter.getByRole('tab', { name: 'Liste' }).click();
  await expect(itemRow(peter, 'Milch'), 'the list stays').toBeVisible();

  // A late renewal brings it back.
  expect((await rcEvent('RENEWAL', household, tx, { productId: `${yearlyId}:yearly`, extra: { store: 'APP_STORE' } }))
    .body).toEqual({ status: 'restored' });
  await expect(renews(lea)).toBeVisible({ timeout: 10_000 });
  expect(revenueCat, 'the web never talks to RevenueCat').toEqual([]);
});

test('Lifetime while a yearly plan runs: Lifetime wins, the plan keeps billing and the page says '
  + 'so; a TRANSFER moves nothing', async ({ browser }) => {
  const { peter, lea, peterEmail, leaEmail } = await couple(browser, 'upgrade');
  await openPremium(peter);
  await openPremium(lea);
  const tx = `4901${Date.now()}`;
  expect(await subscribe(peterEmail, tx)).toBe('granted');
  await expect(renews(lea)).toBeVisible({ timeout: 10_000 });
  expect(await buy(leaEmail, `4902${Date.now()}`)).toBe('granted');
  await expect(lea.getByText(/^Hummlist Premium Lifetime/)).toBeVisible({ timeout: 10_000 });
  await expect(lifetimeWhileYearly(lea, /Kündigen kann nur, wer das Abo abgeschlossen hat, unter Abos verwalten/))
    .toBeVisible();
  // The note itself is text, not one big link (the inline link is a tap on the span; widget tests tap it).
  await expect(lea.getByRole('link', { name: /^Euer Haushalt/ })).toHaveCount(0);
  // Peter took the plan out: his variant.
  await expect(lifetimeWhileYearly(peter, /Du kannst es unter Abo verwalten kündigen/))
    .toBeVisible({ timeout: 10_000 });
  await screenshot(lea, 'job49-web-lifetime-while-yearly-de-390');

  // RevenueCat transfers Peter's plan to Max's household: nothing moves.
  const max = await newPage(browser);
  const maxEmail = newEmail('upgrade-max');
  await signUpWithHousehold(max, maxEmail);
  const maxHousehold = await householdOf(maxEmail);
  expect((await rcEvent('TRANSFER', maxHousehold, tx, {
    productId: yearlyId,
    extra: { transferred_from: [await householdOf(peterEmail)], transferred_to: [maxHousehold] },
  })).body).toEqual({ status: 'ignored' });
  expect((await rcEvent('RENEWAL', maxHousehold, tx, { productId: yearlyId })).body)
    .toEqual({ status: 'used_elsewhere' });
  await openPremium(max);
  await expect(max.getByText('Hummlist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.')).toBeVisible();
  await expect(status(max), 'Max has no Premium').toHaveCount(0);
});

test('deleting the account: the subscriber hears the plan keeps billing, the partner the short line',
  async ({ browser }) => {
    const { peter, lea, peterEmail } = await couple(browser, 'billing');
    expect(await subscribe(peterEmail, `4903${Date.now()}`)).toBe('granted');

    await openMore(lea, 'Konto');
    await lea.getByRole('button', { name: 'Konto löschen', exact: true }).click();
    await expect(billingOther(lea)).toBeVisible();
    await lea.getByRole('button', { name: 'Abbrechen' }).click();
    await expect(billingOther(lea)).toHaveCount(0);

    await openMore(peter, 'Konto');
    await peter.getByRole('button', { name: 'Konto löschen', exact: true }).click();
    await expect(billingContinues(peter)).toBeVisible();
    await expect(peter.getByRole('button', { name: 'Abo verwalten' })).toBeVisible();
    await screenshot(peter, 'job49-web-billing-continues-de-390');
    await peter.getByRole('button', { name: 'Trotzdem fortfahren' }).click();
    await expect(peter.getByRole('textbox', { name: 'Zum Bestätigen LÖSCHEN eingeben' })).toBeVisible();
    await typeInto(peter.getByRole('textbox', { name: 'Zum Bestätigen LÖSCHEN eingeben' }), 'LÖSCHEN');
    await peter.getByRole('button', { name: 'Endgültig löschen' }).click();
    await expect(peter.getByText('Dein Konto wurde gelöscht.')).toBeVisible();
    // The household and its plan stay with Lea: deleting cancels nothing.
    await openPremium(lea);
    await expect(renews(lea)).toBeVisible({ timeout: 10_000 });
  });

test('leaving a household with a yearly plan: the subscriber hears it first, then leaves', async ({ browser }) => {
  const { peter, peterEmail, household } = await couple(browser, 'leave');
  expect(await subscribe(peterEmail, `4904${Date.now()}`)).toBe('granted');
  const otherEmail = newEmail('leave-other');
  const other = await newPage(browser);
  await signUp(other, otherEmail);
  await createHousehold(other, { name: 'Familie Trost' });
  await skipInvite(other);
  const code = await inviteCode(otherEmail);
  // Job 169b: joining adds a household and leaves nothing, so nothing about billing comes up.
  await peter.goto(`/join/${code}`);
  await peter.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(householdChip(peter, 'Familie Trost')).toBeVisible();
  await expect(billingContinues(peter)).toHaveCount(0);

  // Leaving the household with the plan, from its page, is where the subscriber hears it.
  await switchHousehold(peter, 'Familie Trost', 'Unser Haushalt');
  await openMore(peter, 'Unser Haushalt');
  await peter.getByRole('button', { name: 'Haushalt verlassen', exact: true }).click();
  await expect(peter.getByText('„Unser Haushalt“ verlassen?')).toBeVisible();
  await peter.getByRole('button', { name: 'Haushalt verlassen', exact: true }).last().click();
  await expect(billingContinues(peter)).toBeVisible();
  await peter.getByRole('button', { name: 'Trotzdem fortfahren' }).click();
  await expect(peter).toHaveURL(/\/$/, { timeout: 10_000 });
  await expect(householdChip(peter, 'Familie Trost'), 'on to his other household').toBeVisible();
  expect(await householdOf(peterEmail)).toBe(await householdOf(otherEmail));
  expect(await householdOf(peterEmail)).not.toBe(household);
});

test.describe('in English', () => {
  test.use({ locale: 'en-US' });

  test('the yearly status and the manage note', async ({ page }) => {
    const email = newEmail('yearly-en');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
    await typeInto(page.getByRole('textbox', { name: 'Email' }), email);
    await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
    await page.getByRole('button', { name: 'Sign up' }).click();
    await page.getByRole('button', { name: "Don't allow", exact: true }).click();
    await page.getByRole('button', { name: /^Create a household/ }).click();
    await page.getByRole('button', { name: 'Create a household', exact: true }).click();
    await expect(page).toHaveURL(/\/welcome\/invite$/);
    expect(await subscribe(email, `4905${Date.now()}`)).toBe('granted');
    await page.goto('/more/lifetime');
    await expect(page.getByText(/^Hummlist Premium active \(yearly, renews on /)).toBeVisible({ timeout: 10_000 });
    await expect(page.getByRole('group', { name: 'You manage your yearly plan in the App Store or on Google Play.' }))
      .toBeVisible();
    await screenshot(page, 'job49-web-yearly-renews-en-390');
  });
});
