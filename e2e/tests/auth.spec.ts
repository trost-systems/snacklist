import { expect, test, type Page } from './fixtures';
import {
  addField, holdFrames, latestLinkFor, newEmail, nextFrames, openMore, password, signUpWithHousehold, typeInto,
  openEmailSignIn,
  expectSignedOutStart,
  haveAccount,
} from './helpers';
import { watchBuild, withoutWasmGC } from './web-build';

/**
 * The sign-in screen left no copy of its fields behind (job 226): Flutter's web engine kept the
 * email and password in hidden autofill forms, read by screen readers on every later screen.
 */
async function expectNoCredentials(page: Page, email: string): Promise<void> {
  const holding = (): Promise<number> => page.evaluate(
    (values) => [...document.querySelectorAll('input')].filter((input) => values.includes(input.value)).length,
    [email, password],
  );
  await expect.poll(holding).toBe(0);
  expect(await page.locator('body').ariaSnapshot()).not.toContain(email);
}

test('email and password: sign out and back in', async ({ page }) => {
  const email = newEmail('pw');
  await signUpWithHousehold(page, email);
  await expectNoCredentials(page, email);
  await openMore(page, 'Abmelden');
  await expectSignedOutStart(page);
  await haveAccount(page);

  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), 'wrong-password');
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(page.getByText(/Anmeldung fehlgeschlagen/).first()).toBeVisible();

  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(addField(page)).toBeFocused();
  await expectNoCredentials(page, email);
  await expect(addField(page), 'ending the autofill context left the add field alone').toBeFocused();
});

test('a failed sign-in, then the start screen: no copy of the login stays', async ({ page }) => {
  const email = newEmail('left');
  await page.goto('/login');
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(page.getByText(/Anmeldung fehlgeschlagen/).first()).toBeVisible();

  await page.getByRole('button', { name: "Neu bei Snacklist? Los geht's" }).click();
  await expect(page).toHaveURL(/\/start/);
  await expectNoCredentials(page, email);
});

test('magic link signs in on this device', async ({ page }) => {
  const email = newEmail('magic');
  await signUpWithHousehold(page, email);
  await openMore(page, 'Abmelden');
  await expectSignedOutStart(page);
  await haveAccount(page);

  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await page.getByRole('button', { name: 'Anmeldelink per E-Mail senden' }).click();
  await expect(page.getByText(/Anmeldelink geschickt/).first()).toBeVisible();

  await page.goto(await latestLinkFor(email));
  await expect(addField(page)).toBeFocused();
  await expect(page).toHaveURL(/\/$/);
});

for (const build of ['wasm', 'js'] as const) {
  test(`a key typed right after the tap on a field, before the next frame, is kept (${build})`, async ({ page }) => {
    if (build === 'js') await withoutWasmGC(page);
    const loaded = watchBuild(page);
    await page.goto('/login');
    await openEmailSignIn(page);
    const field = page.getByRole('textbox', { name: 'Passwort' });
    await expect(field).toBeVisible();
    expect(loaded()).toEqual([build]);
    await nextFrames(page);
    const release = await holdFrames(page);
    await field.click();
    await page.keyboard.type('g');
    expect(await release(), 'the tap asked for a frame, and it was held').toBeGreaterThan(0);
    await page.keyboard.type('eheim-123', { delay: 30 });
    await nextFrames(page);
    await expect(field).toHaveValue('geheim-123');
  });
}
