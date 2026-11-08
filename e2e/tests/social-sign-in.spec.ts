import { expect, test, type Locator, type Page } from './fixtures';
import {
  addField, addItem, answerConsent, apiAs, itemRow, newEmail, openMore, screenshot, signUpWithHousehold, supabaseUrl, typeInto,
  viaFakeProvider, createHousehold, skipInvite,
  openEmailSignIn,
} from './helpers';

const google = (page: Page) => page.getByRole('button', { name: 'Mit Google anmelden' });
const apple = (page: Page) => page.getByRole('button', { name: 'Mit Apple anmelden' });

/** The authorize URL a button opens, stopped before it reaches Supabase. */
async function authorizeUrl(page: Page, button: Locator): Promise<URL> {
  await page.route((url) => url.href.startsWith(`${supabaseUrl}/auth/v1/authorize?`), (route) =>
    route.fulfill({ status: 200, contentType: 'text/plain', body: 'stopped before the provider' }));
  const request = page.waitForRequest((r) => r.url().startsWith(`${supabaseUrl}/auth/v1/authorize?`));
  await button.click();
  return new URL((await request).url());
}

async function signOut(page: Page): Promise<void> {
  await openMore(page, 'Abmelden');
  await expect(page).toHaveURL(/\/login$/);
}

test('the login screen offers Google and Apple first and email behind one button, nothing focused', async ({ page }) => {
  // Flutter web adds its <input> only for a focused field.
  const fieldFocused = () => page.evaluate(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName ?? ''));
  await page.goto('/');
  await expect(google(page)).toBeVisible();
  await expect(apple(page)).toBeVisible();
  const email = page.getByRole('button', { name: 'Weiter mit E-Mail' });
  await expect(email).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'E-Mail' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Registrieren' })).toHaveCount(0);
  expect(await fieldFocused(), 'nothing focused on open').toBe(false);
  await screenshot(page, '01-login-providers-first');

  await email.click();
  await expect(page.getByText('oder mit E-Mail')).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'E-Mail' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Passwort' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Anmelden', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Registrieren' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Anmeldelink per E-Mail senden' })).toBeVisible();
  expect(await fieldFocused(), 'opening the email form focuses no field').toBe(false);
  await screenshot(page, '01-login-all-methods');
});

for (const [name, button] of [['google', google], ['apple', apple]] as const) {
  test(`${name}: the button starts the PKCE redirect to Supabase's authorize URL`, async ({ page }) => {
    await page.goto('/');
    const origin = new URL(page.url()).origin;
    const url = await authorizeUrl(page, button(page));
    expect(url.origin + url.pathname).toBe(`${supabaseUrl}/auth/v1/authorize`);
    expect(url.searchParams.get('provider')).toBe(name);
    expect(url.searchParams.get('redirect_to')).toBe(`${origin}/`);
    expect(url.searchParams.get('code_challenge')).toMatch(/^[\w-]{43}$/);
    expect(url.searchParams.get('code_challenge_method')).toBe('s256');
  });
}

test('an invite link survives the provider redirect', async ({ page }) => {
  await page.goto('/?invite=ABCD2345');
  await expect(page).toHaveURL(/\/login\?invite=ABCD2345$/);
  const origin = new URL(page.url()).origin;
  const url = await authorizeUrl(page, apple(page));
  expect(url.searchParams.get('redirect_to')).toBe(`${origin}/?invite=ABCD2345`);
});

test('a first provider sign-in goes through household onboarding', async ({ page }) => {
  const email = newEmail('google-new');
  await page.goto('/');
  await viaFakeProvider(page, email);
  await google(page).click();
  // Job 19: the analytics consent comes first, then onboarding.
  await answerConsent(page);

  await expect(page).toHaveURL(/\/welcome$/);
  await createHousehold(page);
  await skipInvite(page);
  await addItem(page, 'Hafermilch');
  await expect(itemRow(page, 'Hafermilch')).toBeVisible();
});

test('the same email via a provider lands in the existing account and household', async ({ page }) => {
  const email = newEmail('linked');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Kaffee');
  await expect(itemRow(page, 'Kaffee')).toBeVisible();
  await signOut(page);

  await viaFakeProvider(page, email);
  await apple(page).click();
  await expect(addField(page)).toBeFocused();
  await expect(itemRow(page, 'Kaffee')).toBeVisible();
  await expect(page).toHaveURL(/\/$/);
  await screenshot(page, '03-provider-sign-in-same-household');

  // One user, two ways in.
  const api = await apiAs(email);
  const { data } = await api.auth.getUserIdentities();
  expect(data?.identities.map((i) => i.provider).sort()).toEqual(['email', 'keycloak']);
});

test('canceling at the provider says so on the login screen', async ({ page }) => {
  await page.goto('/');
  await viaFakeProvider(page, newEmail('cancel'), { cancel: true });
  await google(page).click();
  await expect(page.getByText('Anmeldung abgebrochen').first()).toBeVisible();
  await expect(google(page)).toBeEnabled();
  await screenshot(page, '02-login-canceled');
});

test('password sign-in still works next to the providers', async ({ page }) => {
  const email = newEmail('pw-next-to-social');
  await signUpWithHousehold(page, email);
  await signOut(page);
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), 'test-password-123');
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(addField(page)).toBeFocused();
});
