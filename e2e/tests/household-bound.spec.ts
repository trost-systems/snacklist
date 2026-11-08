import { type Browser, expect, type Page, test } from './fixtures';
import {
  adminClient, apiAs, createHousehold, householdChip, newEmail, nextFrames, openEmailSignIn, openMore, openPremium, openTab, password,
  screenshot, signUp, signUpWithHousehold, skipInvite, switchHousehold, typeInto,
} from './helpers';
import { archiveSwitchOn, buy, householdOf, report } from './iap';

// Job 43: Hummlist Lifetime is household-bound (docs/PURCHASES.md, model A). Purchases are signed
// by the local stack's App Store stand-in and verified by the real function, as in
// purchases.spec.ts; the web shows what every member sees.

// The archive cases need the server's switch on as well as the e2e build's HOUSEHOLD_ARCHIVE.
test.beforeAll(archiveSwitchOn);

const newPage = async (browser: Browser) => {
  const page = await (await browser.newContext()).newPage();
  await page.setViewportSize({ width: 390, height: 844 });
  return page;
};

/** The status tile: its title says which Premium the household has (job 49). */
const unlocked = (page: Page) => page.getByText(/^Hummlist Premium (Lifetime|aktiv|über)/);
const buyButton = (page: Page) => page.getByRole('button', { name: /Weiter zum Kauf|kaufen/ });
const BOUGHT_TWICE = /^Euer Haushalt hat Hummlist Lifetime mehr als einmal gekauft\./;

async function inviteCode(email: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).rpc('create_invite', {
    p_household: await householdOf(email),
  });
  if (error) throw error;
  return (Array.isArray(data) ? data[0] : data).code;
}

/**
 * Leaves the [shown] household from More's household page (job 169b), as its last member with
 * Hummlist Lifetime: the dialog offers the archive (the e2e build's HOUSEHOLD_ARCHIVE), and
 * [choice] answers it. Ends on the list of another household.
 */
async function leaveLastWithLifetime(page: Page, shown: string, choice: 'Löschen und verlassen' | 'Archivieren und verlassen', shot: string) {
  await openMore(page, shown);
  await expect(page).toHaveURL(/\/more\/household$/);
  await page.getByRole('button', { name: 'Haushalt verlassen', exact: true }).click();
  await expect(page.getByText(/Archiviere den Haushalt, statt ihn zu löschen/)).toBeVisible();
  await screenshot(page, shot);
  await page.getByRole('button', { name: choice, exact: true }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(householdChip(page, shown)).toHaveCount(0);
}

test('joining an unlocked household: nothing to buy, the refund help; the purchase stays behind', async ({ browser }) => {
  const annaEmail = newEmail('iap43-anna');
  const benEmail = newEmail('iap43-ben');
  const anna = await newPage(browser);
  const ben = await newPage(browser);
  await signUp(anna, annaEmail);
  await createHousehold(anna, { name: 'Familie Anna' });
  await skipInvite(anna);
  await signUpWithHousehold(ben, benEmail);
  const annaHousehold = await householdOf(annaEmail);
  const benHousehold = await householdOf(benEmail);

  // Both bought, each in their own household (Ben recently, so the refund help applies).
  const annaTx = `4300${Date.now()}`;
  const benTx = `4301${Date.now()}`;
  expect(await buy(annaEmail, annaTx)).toBe('granted');
  expect(await buy(benEmail, benTx)).toBe('granted');

  // Ben opens Anna's invite link as the last member of his unlocked household. Joining adds a
  // household (job 169b), so the join screen no longer offers to archive or delete his own.
  await ben.goto(`/join/${await inviteCode(annaEmail)}`);
  await expect(ben.getByText('Dieser Haushalt hat Hummlist Lifetime. Du musst nichts kaufen.')).toBeVisible();
  await expect(ben.getByText(/Archiviere den Haushalt/), 'nothing about his own household').toHaveCount(0);
  const refundLink = ben.getByRole('button', { name: /vor Kurzem gekauft\? So forderst du den Kauf zurück/ });
  await expect(refundLink).toBeVisible();
  await screenshot(ben, 'job43-join-unlocked-de-390');
  await refundLink.click();
  await expect(ben.getByText('Kauf zurückfordern', { exact: true })).toBeVisible();
  await expect(ben.getByText(/^Hummlist Lifetime gehört immer zu dem Haushalt, in dem es gekauft wurde\. Käufe im App Store erstattet nur Apple\./)).toBeVisible();
  await expect(ben.getByRole('link', { name: 'Mehr in den häufigen Fragen' })).toHaveAttribute('href', 'https://hummlist.com/support');
  await expect(ben.getByRole('link', { name: 'Bei Apple anfragen' })).toHaveAttribute('href', 'https://reportaproblem.apple.com/');
  await expect(ben.getByRole('link', { name: 'Bei Google anfragen' })).toHaveAttribute(
    'href',
    'https://support.google.com/googleplay/answer/15574897?hl=de',
  );
  await screenshot(ben, 'job43-refund-help-de-390');
  await ben.keyboard.press('Escape');
  await expect(ben.getByText('Kauf zurückfordern', { exact: true })).toHaveCount(0);
  await ben.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(ben).toHaveURL(/\/$/);
  await expect(householdChip(ben, 'Familie Anna')).toBeVisible();

  // In Anna's household, a member who did not buy sees it unlocked, with no Buy.
  await openPremium(ben);
  await expect(unlocked(ben)).toBeVisible();
  await expect(buyButton(ben)).toHaveCount(0);
  // Ben's purchase stays with his household: it unlocks nothing in Anna's.
  expect(await report(benEmail, benTx, annaHousehold), 'his purchase reported for Anna\'s household').toBe('used_elsewhere');

  // Ben leaves his own household from its page and deletes it rather than archive it.
  await openTab(ben, 'Liste');
  await switchHousehold(ben, 'Familie Anna', 'Unser Haushalt');
  await leaveLastWithLifetime(ben, 'Unser Haushalt', 'Löschen und verlassen', 'job43-leave-delete-de-390');
  await expect(householdChip(ben, 'Familie Anna'), 'on to his other household').toBeVisible();
  const { count } = await adminClient().from('households').select('*', { count: 'exact', head: true }).eq('id', benHousehold);
  expect(count, 'his household is deleted').toBe(0);
  // His purchase went with it: it unlocks nothing anywhere else, ever.
  expect(await report(benEmail, benTx), 'restore after the household is gone').toBe('used_elsewhere');
});

test('a joiner into a locked household is told nothing; a household bought twice says so', async ({ browser }) => {
  const caraEmail = newEmail('iap43-cara');
  const dirkEmail = newEmail('iap43-dirk');
  const cara = await newPage(browser);
  const dirk = await newPage(browser);
  await signUpWithHousehold(cara, caraEmail);
  await signUpWithHousehold(dirk, dirkEmail);
  const caraHousehold = await householdOf(caraEmail);

  await dirk.goto(`/join/${await inviteCode(caraEmail)}`);
  await expect(dirk.getByRole('button', { name: 'Haushalt beitreten', exact: true })).toBeVisible();
  await expect(dirk.getByText(/Du musst nichts kaufen/)).toHaveCount(0);
  await expect(dirk.getByText(/Hummlist Lifetime endet/)).toHaveCount(0);
  await dirk.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(dirk).toHaveURL(/\/$/);

  await openPremium(cara);
  expect(await buy(caraEmail, `4302${Date.now()}`)).toBe('granted');
  await expect(unlocked(cara)).toBeVisible({ timeout: 10_000 });
  // Dirk bought too on his phone, in Cara's household, before he saw it (two phones, Ask to Buy):
  // flagged for the refund help.
  expect(await buy(dirkEmail, `4303${Date.now()}`, caraHousehold)).toBe('granted');
  await expect(cara.getByText(BOUGHT_TWICE)).toBeVisible({ timeout: 10_000 });
  await screenshot(cara, 'job43-bought-twice-de-390');
});

test('the last member archives an unlocked household, its purchase stays its own, and brings it back', async ({ browser }) => {
  const frankEmail = newEmail('iap43-frank');
  const caraEmail = newEmail('iap43-cara2');
  const frank = await newPage(browser);
  await signUpWithHousehold(frank, frankEmail);
  const cara = await newPage(browser);
  await signUp(cara, caraEmail);
  await createHousehold(cara, { name: 'Familie Cara' });
  await skipInvite(cara);
  const frankHousehold = await householdOf(frankEmail);
  const caraHousehold = await householdOf(caraEmail);
  const frankTx = `4304${Date.now()}`;
  expect(await buy(frankEmail, frankTx)).toBe('granted');

  // Job 169b: Frank joins Cara's household beside his own, then leaves his own from its page.
  await frank.goto(`/join/${await inviteCode(caraEmail)}`);
  await frank.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(householdChip(frank, 'Familie Cara')).toBeVisible();
  await switchHousehold(frank, 'Familie Cara', 'Unser Haushalt');
  await leaveLastWithLifetime(frank, 'Unser Haushalt', 'Archivieren und verlassen', 'job43-leave-archive-offer-de-390');
  await expect(householdChip(frank, 'Familie Cara')).toBeVisible();

  // In Cara's household the purchase restores nothing: it belongs to the archived one.
  expect(await report(frankEmail, frankTx, caraHousehold)).toBe('used_elsewhere');
  await openPremium(frank);
  await expect(unlocked(frank), 'Cara\'s household has no Lifetime').toHaveCount(0);

  await openTab(frank, 'Mehr');
  await frank.getByRole('button', { name: /^Archivierte Haushalte/ }).click();
  // Job 47 (H-50): each archived household says when it is deleted, 24 months after archiving.
  const deletes = new Date();
  deletes.setMonth(deletes.getMonth() + 24);
  // In the browser's zone (playwright.config.ts): on a UTC runner just before midnight the day differs.
  const date = deletes.toLocaleDateString('de-DE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Berlin' });
  await expect(frank.getByRole('group', { name: new RegExp(`Mit Hummlist Lifetime\\s+Wird am ${date} gelöscht$`) }))
    .toBeVisible();
  await screenshot(frank, 'job43-archived-de-390');
  await screenshot(frank, 'job47-archived-deletes-de-390');
  await frank.getByRole('button', { name: 'Wieder aktivieren', exact: true }).click();
  await frank.getByRole('button', { name: 'Wieder aktivieren', exact: true }).last().click();
  // Job 169b: it comes back beside Cara's household, which Frank keeps, and shows.
  await expect.poll(async () => ((await (await apiAs(frankEmail)).rpc('my_households')).data ?? []).map((h: { id: string }) => h.id).sort())
    .toEqual([frankHousehold, caraHousehold].sort());
  // The app shows it before the Premium page reloads (the server answering is not enough).
  await expect(householdChip(frank, 'Unser Haushalt')).toBeVisible();
  await openPremium(frank);
  await expect(unlocked(frank), 'back in his household, the unlock is back').toBeVisible({ timeout: 10_000 });
  expect(await report(frankEmail, frankTx, frankHousehold)).toBe('restored');
});

test('the web says nothing about buying before sales start, also in English', async ({ browser }) => {
  const email = newEmail('iap43-web');
  const page = await newPage(browser);
  await signUpWithHousehold(page, email);
  await openTab(page, 'Mehr');
  await expect(page.getByRole('button', { name: 'Konto', exact: false }).first()).toBeVisible();
  await expect(page.getByRole('button', { name: /^Hummlist Premium/ }), 'not listed before the launch (job 64)')
    .toHaveCount(0);
  await openPremium(page);
  // Job 87, Legal Review's final texts: nothing about buying before sales start (premium_offer off).
  await expect(page.getByText('Hummlist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.')).toBeVisible();
  await expect(page.getByText(/^Hummlist Premium kaufst du in der iPhone- oder Android-App\./)).toHaveCount(0);
  await expect(buyButton(page)).toHaveCount(0);
  await expect(page.getByRole('button', { name: /^Doppelt gekauft\?/ }), 'no refund link before sales start (N-69)')
    .toHaveCount(0);
  await screenshot(page, 'job43-web-de-390');
});

test.describe('in English', () => {
  test.use({ locale: 'en-US' });

  test('the web copy, and the refund help once bought twice', async ({ page }) => {
    const email = newEmail('iap43-en');
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
    await page.goto('/more/lifetime');
    await expect(page.getByText('Hummlist Premium covers your whole household, including everyone who joins later.')).toBeVisible();
    await expect(page.getByText(/^You can buy Hummlist Premium in the iPhone or Android app\./)).toHaveCount(0);
    await screenshot(page, 'job43-web-en-390');
    // Before sales start the refund help shows only to a household that bought twice (N-69).
    await expect(page.getByRole('button', { name: /^Bought it twice\?/ })).toHaveCount(0);
    expect(await buy(email, `4310${Date.now()}`)).toBe('granted');
    expect(await buy(email, `4311${Date.now()}`)).toBe('granted');
    await page.getByRole('button', { name: /^Bought it twice\?/ }).click({ timeout: 10_000 });
    await expect(page.getByText('Request a refund', { exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Ask Google' })).toHaveAttribute(
      'href',
      'https://support.google.com/googleplay/answer/15574897?hl=en',
    );
    await screenshot(page, 'job43-refund-help-en-390');
  });
});

// Job 68: deleting the account as the last member of an unlocked household, or with an unlocked
// archived household, says that Hummlist Premium ends and is not refunded; Delete waits for the
// tick. Neither household is archived: an archive would go with the account (DECISIONS 68).
test('account deletion: the last member of an unlocked household confirms that Premium is not refunded', async ({ browser }) => {
  const email = newEmail('acct68');
  const page = await newPage(browser);
  await signUpWithHousehold(page, email);
  // The household from onboarding gets Lifetime and is archived; it goes with the account too.
  expect(await buy(email, `6800${Date.now()}`)).toBe('granted');
  const archivedId = await householdOf(email);
  const api = await apiAs(email);
  expect((await api.rpc('leave_current_household', { p_archive: true })).data).toBe('archived');
  // A new household, also with Lifetime, whose last member the user is.
  const { error } = await api.rpc('create_household', { p_name: 'Zuhause' });
  expect(error).toBeNull();
  const homeId = await householdOf(email);
  expect(await buy(email, `6801${Date.now()}`)).toBe('granted');

  await page.reload();
  await openMore(page, 'Konto');
  await page.getByRole('button', { name: 'Konto löschen', exact: true }).click();
  await expect(page.getByRole('group', { name: /^„Zuhause“ hat Hummlist Premium\. Es gehört zum Haushalt und endet mit ihm\. Archivieren geht hier nicht/ })).toBeVisible();
  // The dialog's paragraphs reach the screen reader as one text.
  await expect(page.getByText(/Dein archivierter Haushalt „Unser Haushalt“ wird mit deinem Konto gelöscht, und mit ihm sein Hummlist Premium\./)).toBeVisible();
  const ack = page.getByRole('checkbox', { name: 'Ich weiß: Premium endet. Ich bekomme mein Geld nicht von selbst zurück.' });
  await expect(ack).toBeVisible();
  // Scroll the dialog in Flutter first: a click on the field below the fold would land on the
  // canvas where the box is now.
  await page.mouse.move(195, 400);
  await page.mouse.wheel(0, 1000);
  await nextFrames(page);
  await expect(ack, 'the box starts unticked').not.toBeChecked();
  await typeInto(page.getByRole('textbox', { name: 'Zum Bestätigen LÖSCHEN eingeben' }), 'LÖSCHEN');
  await expect(ack).not.toBeChecked();
  const deleteButton = page.getByRole('button', { name: 'Endgültig löschen' });
  await expect(deleteButton, 'Delete waits for the tick').toBeDisabled();
  await screenshot(page, 'job68-delete-premium-de-390');

  await page.getByRole('button', { name: 'Erstattung bei Apple oder Google anfragen' }).click();
  await expect(page.getByRole('link', { name: 'Bei Apple anfragen' })).toHaveAttribute('href', 'https://reportaproblem.apple.com/');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('link', { name: 'Bei Apple anfragen' })).toHaveCount(0);

  await ack.click();
  await expect(ack).toBeChecked();
  await screenshot(page, 'job68-delete-premium-ticked-de-390');
  await deleteButton.click();
  await expect(page.getByText('Dein Konto wurde gelöscht.')).toBeVisible();

  const { count } = await adminClient().from('households').select('*', { count: 'exact', head: true })
    .in('id', [homeId, archivedId]);
  expect(count, 'both households are deleted, neither archived').toBe(0);
});
