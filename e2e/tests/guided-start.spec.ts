// Job 168b: the guided start. Signed out, `/` asks who you shop with, the household's name, the
// stores and what is missing, all kept on the device, and only then for the account; the app sets
// the household up from the answers and offers invites that show who joined, live. The widget tests
// (app/test/onboarding/guided_start_test.dart) cover every branch; this proves the path on the web
// build against the real stack.
import { expect, type Locator, type Page, test } from './fixtures';
import {
  addField, addNeed, adminClient, apiAs, confirmJoin, createHousehold, firstOf, invitePath, itemRow, must, newEmail,
  onboardingChip, openEmailSignIn, password, screenshot, shownInviteCodes, signUp, typeInto,
} from './helpers';

const phone = { width: 390, height: 844 };

async function userIdOf(email: string): Promise<string | undefined> {
  const { data, error } = await adminClient().auth.admin.listUsers({ perPage: 1000 });
  if (error) throw error;
  return data.users.find((u) => u.email === email)?.id;
}

async function householdsCreatedBy(userId: string) {
  const { data, error } = await adminClient().from('households').select('id, name, kind, join_approval')
    .eq('created_by', userId);
  if (error) throw error;
  return data as { id: string; name: string; kind: string | null; join_approval: boolean }[];
}

async function listOf(household: string) {
  const { data, error } = await adminClient().from('items').select('name, quantity, category_id')
    .eq('household_id', household).eq('status', 'active').order('name');
  if (error) throw error;
  return data as { name: string; quantity: string | null; category_id: string | null }[];
}

/** „Schritt N von 7“: one labelled node on the web. */
const progress = (page: Page, step: number): Locator => {
  const label = `Schritt ${step} von 7`;
  return page.getByLabel(label, { exact: true }).or(page.getByText(label, { exact: true })).first();
};

/** The first screen's „Los geht's“, then the usage question declined (a fresh browser has not answered). */
async function letsGo(page: Page): Promise<void> {
  await page.goto('/');
  await expect(page).toHaveURL(/\/start$/);
  await page.getByRole('button', { name: "Los geht's", exact: true }).click();
  await expect(page).toHaveURL(/\/start\/usage$/);
  await expect(progress(page, 1)).toBeAttached();
  const decline = page.getByRole('button', { name: 'Nicht erlauben', exact: true });
  const size = must(page.viewportSize(), 'viewport');
  await page.mouse.move(size.width / 2, size.height / 2);
  await expect(async () => {
    if (!(await decline.isVisible())) await page.mouse.wheel(0, 400);
    await expect(decline).toBeVisible({ timeout: 500 });
  }).toPass();
  await decline.click();
  await expect(page).toHaveURL(/\/start\/who$/);
}

const next = (page: Page): Locator => page.getByRole('button', { name: 'Weiter', exact: true });
const skip = (page: Page): Locator => page.getByRole('button', { name: 'Überspringen', exact: true });

/** The X on a step, then one of its dialog's answers. */
async function leave(page: Page, choice: 'Stattdessen anmelden' | 'Fortschritt verwerfen'): Promise<void> {
  await page.getByRole('button', { name: 'Einrichtung verlassen' }).click();
  await page.getByRole('button', { name: choice, exact: true }).click();
}

test('signed out: the questions first, kept across a reload, then the account; the household is set up from the answers', async ({ browser }) => {
  const page = await (await browser.newContext({ viewport: phone })).newPage();
  const email = newEmail('guided');
  await page.goto('/');
  await expect(page).toHaveURL(/\/start$/);
  await expect(page.getByRole('button', { name: 'Schon ein Konto? Anmelden', exact: true })).toBeVisible();
  await screenshot(page, '168b-01-start');

  await letsGo(page);
  await expect(progress(page, 2)).toBeAttached();
  await onboardingChip(page, 'Partner·in').click();
  await onboardingChip(page, 'Verein oder Team').click();
  await expect(page.getByText('Wir starten mit „Partner·in“. Die anderen merken wir uns für später.')).toBeVisible();
  await screenshot(page, '168b-02-who');
  await next(page).click();

  await expect(page).toHaveURL(/\/start\/name$/);
  await expect(page.getByRole('textbox', { name: 'Name des Haushalts' })).toBeVisible();
  await next(page).click();

  await expect(page).toHaveURL(/\/start\/stores$/);
  await onboardingChip(page, 'Lidl').click();
  await page.getByRole('button', { name: 'Eigenen Laden hinzufügen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Ladens' }), 'Wochenmarkt');
  await page.keyboard.press('Enter');
  await expect(onboardingChip(page, 'Wochenmarkt')).toBeChecked();
  await expect(onboardingChip(page, 'Lidl')).toBeChecked();

  // The draft is on the device: a reload resumes here with the picks.
  await page.reload();
  await expect(page).toHaveURL(/\/start\/stores$/);
  await expect(onboardingChip(page, 'Lidl')).toBeChecked();
  await expect(onboardingChip(page, 'Wochenmarkt')).toBeChecked();
  await expect(onboardingChip(page, 'EDEKA')).not.toBeChecked();
  await next(page).click();

  await expect(page).toHaveURL(/\/start\/need$/);
  await onboardingChip(page, 'Milch').click();
  await addNeed(page, '2 Gurken');
  await screenshot(page, '168b-03-need');
  await page.getByRole('button', { name: 'Weiter mit 2 Artikeln', exact: true }).click();

  await expect(page).toHaveURL(/\/start\/account$/);
  await expect(progress(page, 6)).toBeAttached();
  expect(await userIdOf(email), 'no account, so no household, before the sign-up').toBeUndefined();
  await openEmailSignIn(page);
  await screenshot(page, '168b-04-account');
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();

  // Usage was answered at the start: no consent screen after the sign-up.
  await expect(page).toHaveURL(/\/start\/invite$/, { timeout: 20_000 });
  await expect(page.getByRole('button', { name: 'Partner·in einladen', exact: true })).toBeVisible();
  await expect(page.getByText('2 Artikel warten schon auf der Liste.')).toBeVisible();

  const userId = must(await userIdOf(email), 'the new user');
  const household = firstOf(await householdsCreatedBy(userId), 'household');
  expect(household.name, 'the suggestion kept').toBe('Unser Haushalt');
  expect(household.kind, 'the first kind picked').toBe('partner');
  const admin = adminClient();
  const { data: stores } = await admin.from('stores').select('name').eq('household_id', household.id).order('sort_order');
  expect((stores as { name: string }[]).map((s) => s.name), 'in the order picked').toEqual(['Lidl', 'Wochenmarkt']);
  const items = await listOf(household.id);
  expect(items.map((i) => [i.name, i.quantity])).toEqual([['Gurken', '2'], ['Milch', null]]);
  for (const item of items) expect(item.category_id, `${item.name} has a category`).not.toBeNull();
  const { data: members } = await admin.from('household_members').select('user_id').eq('household_id', household.id);
  expect((members as { user_id: string }[]).map((m) => m.user_id), 'the user is its only member').toEqual([userId]);
});

test('the invite step: two invites, one joined shows live, then the list with the items', async ({ browser }) => {
  const page = await (await browser.newContext({ viewport: phone })).newPage();
  await signUp(page, newEmail('guided-invite'));
  await createHousehold(page, { kinds: ['Partner·in'], name: 'Familie Brandt', items: ['Brot', '2 Gurken'] });

  await page.getByRole('button', { name: 'Partner·in einladen', exact: true }).click();
  await expect.poll(async () => (await shownInviteCodes(page)).length).toBe(1);
  await page.getByRole('button', { name: 'Weitere Einladung', exact: true }).click();
  await expect.poll(async () => (await shownInviteCodes(page)).length).toBe(2);
  const [first, second] = await shownInviteCodes(page);
  expect(first).not.toBe(second);
  await expect(page.getByText(`/join/${must(second, 'second code')}`, { exact: false })).toBeVisible();

  const joined = page.getByText(/^(.+ ist beigetreten|Beigetreten)$/);
  await expect(joined).toHaveCount(0);
  const lea = await (await browser.newContext()).newPage();
  await signUp(lea, newEmail('guided-lea'), invitePath(must(first, 'first code')));
  await confirmJoin(lea, 'Familie Brandt');

  // Without a reload: realtime on invites marks that card.
  await expect(joined).toHaveCount(1, { timeout: 15_000 });
  await expect(page.getByRole('button', { name: 'Link kopieren' }), 'the other invite is still open').toHaveCount(1);
  await screenshot(page, '168b-05-invite-joined');

  await page.getByRole('button', { name: 'Weiter zur Liste', exact: true }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(addField(page)).toBeVisible();
  await expect(itemRow(page, 'Brot')).toBeVisible();
  await expect(itemRow(page, 'Gurken')).toBeVisible();
  await expect(itemRow(lea, 'Brot'), 'Lea sees the same list').toBeVisible();
});

test('the X: sign in instead keeps the draft for later; discard starts over with nothing kept', async ({ browser }) => {
  const page = await (await browser.newContext({ viewport: phone })).newPage();
  await letsGo(page);
  await onboardingChip(page, 'Familie').click();
  await next(page).click();
  await expect(page).toHaveURL(/\/start\/name$/);
  await next(page).click();
  await expect(page).toHaveURL(/\/start\/stores$/);

  await leave(page, 'Stattdessen anmelden');
  await expect(page).toHaveURL(/\/login$/);
  await page.getByRole('button', { name: "Neu bei Snacklist? Los geht's", exact: true }).click();
  await expect(page, 'the draft resumes').toHaveURL(/\/start\/stores$/);

  await leave(page, 'Fortschritt verwerfen');
  await expect(page).toHaveURL(/\/start$/);
  await page.reload();
  await expect(page, 'nothing kept on the device').toHaveURL(/\/start$/);
  await page.getByRole('button', { name: "Los geht's", exact: true }).click();
  // Usage stays answered (that is the install's choice, not the draft's).
  await expect(page).toHaveURL(/\/start\/who$/);
  await expect(onboardingChip(page, 'Familie')).not.toBeChecked();
});

// Job 168c: the kind goes with the create, so a club starts with join approval on (169b W3), as the
// server does it only from create_household's p_kind.
test('a club from the guided start starts with join approval on', async ({ browser }) => {
  const email = newEmail('guided-club');
  const page = await (await browser.newContext({ viewport: phone })).newPage();
  await signUp(page, email);
  await createHousehold(page, { kinds: ['Verein oder Team'] });
  await expect(page.getByRole('button', { name: 'Mitglieder einladen', exact: true })).toBeVisible();
  const household = firstOf(await householdsCreatedBy(must(await userIdOf(email), 'user')), 'household');
  expect(household.kind).toBe('club');
  expect(household.join_approval, 'join approval on for a new club').toBe(true);
});

test('signing in to an account with a household puts the draft items on its list', async ({ browser }) => {
  const email = newEmail('guided-existing');
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const { data: created, error: createError } = await (await apiAs(email)).rpc('create_household', { p_name: 'Familie Trost' });
  if (createError) throw createError;
  const household = (created as { id: string }).id;

  const page = await (await browser.newContext({ viewport: phone })).newPage();
  await letsGo(page);
  await skip(page).click();
  await next(page).click();
  await skip(page).click();
  await expect(page).toHaveURL(/\/start\/need$/);
  await onboardingChip(page, 'Brot').click();
  await addNeed(page, 'Kaffee');
  await page.getByRole('button', { name: 'Weiter mit 2 Artikeln', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/account$/);
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();

  await expect(page).toHaveURL(/\/$/, { timeout: 20_000 });
  await expect(itemRow(page, 'Brot')).toBeVisible();
  await expect(itemRow(page, 'Kaffee')).toBeVisible();
  expect((await listOf(household)).map((i) => i.name)).toEqual(['Brot', 'Kaffee']);
  expect(await householdsCreatedBy(must(await userIdOf(email), 'user')), 'no second household').toHaveLength(1);
});
