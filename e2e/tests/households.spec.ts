// Job 169b, wave 1: a user can be in several households (docs/households/W1.md). The chip top
// left of the list opens the switcher; each household keeps its own list; joining adds a
// household; the default is the one Siri, Alexa and AI assistants use; More's household page
// leaves one. Old store builds read their own membership with .maybeSingle() and see the default.
import { type Browser, expect, type Page, test } from './fixtures';
import process from 'node:process';
import {
  addItem, adminClient, apiAs, confirmJoin, createHousehold, createInviteCode, firstOf, householdChip, householdRow,
  invitePreview, itemRow, must, newEmail, openEmailSignIn, openHouseholds, openMore, password, screenshot,
  signUp, signUpWithHousehold, skipInvite, switchHousehold, typeInto,
} from './helpers';

const phone = { width: 390, height: 844 };

type MyHousehold = { id: string; name: string; 'is_default': boolean; 'member_count': number };

async function myHouseholds(email: string): Promise<MyHousehold[]> {
  const { data, error } = await (await apiAs(email)).rpc('my_households');
  if (error) throw error;
  return data as MyHousehold[];
}

/** What an old store build reads: its own membership row, at most one, or it fails. */
async function oldAppMembership(email: string) {
  const api = await apiAs(email);
  const { data: user } = await api.auth.getUser();
  return api.from('household_members').select('household_id, user_id').eq('user_id', must(user.user, 'user').id).maybeSingle();
}

/** A user made on the server with a household [name] and an open invite to it. */
async function householdWithInvite(tag: string, name: string) {
  const email = newEmail(tag);
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const api = await apiAs(email);
  const { data: household, error: createError } = await api.rpc('create_household', { p_name: name });
  if (createError) throw createError;
  const { data: invite, error: inviteError } = await api.rpc('create_invite', { p_household: household.id });
  if (inviteError) throw inviteError;
  return { email, household: household.id as string, code: invite.code as string };
}

/** Signs up and creates the first household, [name], from onboarding; ends on its list. */
async function signUpWithNamed(page: Page, email: string, name: string): Promise<void> {
  await signUp(page, email);
  await createHousehold(page, { name });
  await skipInvite(page);
}

async function newPage(browser: Browser, options: Parameters<Browser['newContext']>[0] = {}): Promise<Page> {
  return (await browser.newContext(options)).newPage();
}

test('a second household from the switcher: its own list, kept apart, still shown after a reload', async ({ page }) => {
  const email = newEmail('hh-create');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Milch');
  await expect(householdChip(page, 'Unser Haushalt'), 'the chip names the shown household').toBeVisible();

  await openHouseholds(page, 'Unser Haushalt');
  await expect(householdRow(page, 'Unser Haushalt')).toHaveAccessibleName(/1 Mitglied · 1 offen/);
  await page.getByRole('button', { name: 'Neuer Haushalt', exact: true }).click();
  await expect(page).toHaveURL(/\/households\/new$/);
  await typeInto(page.getByRole('textbox', { name: 'Name des Haushalts' }), 'Ferienhaus');
  await page.getByRole('button', { name: 'Überspringen', exact: true }).click();
  await skipInvite(page);
  await expect(householdChip(page, 'Ferienhaus'), 'the new household shows').toBeVisible();
  await expect(itemRow(page, 'Milch'), 'with its own, empty list').toHaveCount(0);

  await addItem(page, 'Brennholz');
  await switchHousehold(page, 'Ferienhaus', 'Unser Haushalt');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(itemRow(page, 'Brennholz'), 'an item stays in its household').toHaveCount(0);
  await switchHousehold(page, 'Unser Haushalt', 'Ferienhaus');
  await expect(itemRow(page, 'Brennholz')).toBeVisible();
  await expect(itemRow(page, 'Milch')).toHaveCount(0);

  await page.reload();
  await expect(householdChip(page, 'Ferienhaus'), 'this device opens the household it showed last').toBeVisible();
  await expect(itemRow(page, 'Brennholz')).toBeVisible();
  await expect(itemRow(page, 'Milch')).toHaveCount(0);

  const households = await myHouseholds(email);
  expect(households.map((h) => [h.name, h.is_default]), 'the first household stays the default')
    .toEqual([['Unser Haushalt', true], ['Ferienhaus', false]]);
});

test('joining by link adds the household: both in the switcher, the inviter\'s list shown', async ({ browser }) => {
  const peter = await newPage(browser);
  const lea = await newPage(browser);
  const peterEmail = newEmail('hh-peter');
  const leaEmail = newEmail('hh-lea');
  await signUpWithNamed(peter, peterEmail, 'Familie Trost');
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);
  await signUpWithNamed(lea, leaEmail, 'WG Lea');
  await addItem(lea, 'Tee');

  await lea.goto(`/join/${code}`);
  await expect(invitePreview(lea, 'Familie Trost')).toBeVisible();
  await confirmJoin(lea, 'Familie Trost');
  await expect(householdChip(lea, 'Familie Trost')).toBeVisible();
  await expect(itemRow(lea, 'Kaffee'), 'the inviter\'s list').toBeVisible();
  await expect(itemRow(lea, 'Tee')).toHaveCount(0);

  await openHouseholds(lea, 'Familie Trost');
  await expect(householdRow(lea, 'WG Lea'), 'her own household stays').toHaveAccessibleName(/^WG Lea\s+1 Mitglied · 1 offen/);
  await expect(householdRow(lea, 'Familie Trost')).toHaveAccessibleName(/^Familie Trost\s+2 Mitglieder · 1 offen/);
  await householdRow(lea, 'WG Lea').click();
  await expect(householdChip(lea, 'WG Lea')).toBeVisible();
  await expect(itemRow(lea, 'Tee')).toBeVisible();

  await openHouseholds(peter, 'Familie Trost');
  await expect(householdRow(peter, 'Familie Trost')).toHaveAccessibleName(/^Familie Trost\s+2 Mitglieder/);
  await expect(householdRow(peter, 'WG Lea'), 'the inviter sees only shared households').toHaveCount(0);

  expect((await myHouseholds(leaEmail)).map((h) => [h.name, h.member_count, h.is_default]))
    .toEqual([['WG Lea', 1, true], ['Familie Trost', 2, false]]);
});

test('the default for Siri, Alexa and AI changes from the switcher; old apps read that one row', async ({ page }) => {
  const email = newEmail('hh-default');
  await signUpWithHousehold(page, email);
  const api = await apiAs(email);
  const { data: second, error } = await api.rpc('create_household', {
    p_name: 'Büro', p_default_stores: false, p_stores: [], p_request_id: crypto.randomUUID(), p_kind: null,
  });
  expect(error).toBeNull();
  const first = firstOf((await myHouseholds(email)).filter((h) => h.name === 'Unser Haushalt'), 'first household');
  expect((await oldAppMembership(email)).data?.household_id, 'old apps see the first').toBe(first.id);

  // Opening the sheet reads the households again: Büro was made elsewhere.
  await openHouseholds(page, 'Unser Haushalt');
  await expect(householdRow(page, 'Büro')).toBeVisible();
  await page.getByRole('button', { name: 'Siri, Alexa & KI nutzen: Unser Haushalt' }).click();
  await page.getByRole('radio', { name: 'Büro' }).click();
  await expect(page.getByRole('button', { name: 'Siri, Alexa & KI nutzen: Büro' })).toBeVisible();
  await expect.poll(async () => (await myHouseholds(email)).map((h) => [h.name, h.is_default]))
    .toEqual([['Unser Haushalt', false], ['Büro', true]]);

  await page.keyboard.press('Escape');
  await expect(householdChip(page, 'Unser Haushalt'), 'the default is not the shown one').toBeVisible();

  const old = await oldAppMembership(email);
  expect(old.error, 'one row, so .maybeSingle() holds').toBeNull();
  expect(old.data?.household_id, 'the new default').toBe(second.id);
});

test('an old app\'s own-membership read stays one row for a user in three households', async () => {
  const owner = await householdWithInvite('hh-old-owner', 'Familie Trost');
  const email = newEmail('hh-old');
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const api = await apiAs(email);
  // As an old build creates: no request id.
  const { data: first, error: createError } = await api.rpc('create_household', { p_name: 'Zuhause' });
  expect(createError).toBeNull();
  const { error: secondError } = await api.rpc('create_household', {
    p_name: 'Büro', p_default_stores: false, p_stores: [], p_request_id: crypto.randomUUID(), p_kind: null,
  });
  expect(secondError).toBeNull();
  const { data: joined } = await api.rpc('accept_invite', { p_code: owner.code, p_mode: 'add' });
  expect(joined).toEqual({ status: 'joined', household_id: owner.household });
  expect(await myHouseholds(email)).toHaveLength(3);

  const old = await oldAppMembership(email);
  expect(old.error).toBeNull();
  expect(old.data?.household_id, 'the default, the first household').toBe(first.id);
  const { data: rows } = await api.from('household_members').select('household_id').eq('user_id', must(old.data, 'row').user_id);
  expect(rows, 'exactly one own row').toHaveLength(1);
});

test('leaving a household from its page: it goes, the list shows another, the others keep theirs', async ({ browser }) => {
  const peter = await newPage(browser);
  const lea = await newPage(browser);
  const peterEmail = newEmail('hh-leave-peter');
  const leaEmail = newEmail('hh-leave-lea');
  await signUpWithNamed(peter, peterEmail, 'Familie Trost');
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);
  await signUpWithHousehold(lea, leaEmail);
  await addItem(lea, 'Tee');
  await lea.goto(`/join/${code}`);
  await confirmJoin(lea, 'Familie Trost');
  await expect(householdChip(lea, 'Familie Trost')).toBeVisible();

  await openMore(lea, 'Familie Trost');
  await expect(lea).toHaveURL(/\/more\/household$/);
  await expect(lea.getByRole('group', { name: 'Siri, Alexa und KI-Assistenten nutzen gerade „Unser Haushalt“.' }), 'not the default')
    .toBeVisible();
  // Display names default to the email's local part.
  const nameOf = (email: string) => must(email.split('@')[0], 'local part');
  await expect(lea.getByText(nameOf(peterEmail), { exact: true }), 'the other member').toBeVisible();
  await expect(lea.getByText(`${nameOf(leaEmail)} (du)`, { exact: true }), 'herself, marked').toBeVisible();
  await lea.getByRole('button', { name: 'Haushalt verlassen', exact: true }).click();
  await expect(lea.getByText('„Familie Trost“ verlassen?')).toBeVisible();
  await expect(lea.getByText(/^Die anderen Mitglieder behalten die Liste\./)).toBeVisible();
  await lea.getByRole('button', { name: 'Haushalt verlassen', exact: true }).last().click();

  await expect(lea).toHaveURL(/\/$/);
  await expect(householdChip(lea, 'Unser Haushalt'), 'the list switches to her other household').toBeVisible();
  await expect(itemRow(lea, 'Tee')).toBeVisible();
  await expect(itemRow(lea, 'Kaffee')).toHaveCount(0);
  await openHouseholds(lea, 'Unser Haushalt');
  await expect(householdRow(lea, 'Familie Trost'), 'gone from the switcher').toHaveCount(0);
  await expect(householdRow(lea, 'Unser Haushalt')).toBeVisible();
  expect((await myHouseholds(leaEmail)).map((h) => h.name)).toEqual(['Unser Haushalt']);

  await expect(itemRow(peter, 'Kaffee'), 'Peter keeps the list').toBeVisible();
  await openHouseholds(peter, 'Familie Trost');
  await expect(householdRow(peter, 'Familie Trost')).toHaveAccessibleName(/^Familie Trost\s+1 Mitglied/);
});

// Screenshots for the PR (docs/screenshots/169b): the chip, the switcher with three households,
// the household page and the create screen; German light and English dark, phone size.
for (const [lang, scheme] of [['de', 'light'], ['en', 'dark']] as const) {
  test(`screenshots ${lang} ${scheme}`, async ({ browser }) => {
    test.skip(!process.env.SCREENSHOT_DIR, 'only when screenshots are asked for');
    const de = lang === 'de';
    const t = de
      ? { withEmail: 'Weiter mit E-Mail', email: 'E-Mail', password: 'Passwort', signUp: 'Registrieren', decline: 'Nicht erlauben',
        create: 'Haushalt erstellen', first: 'Unser Haushalt', holiday: 'Ferienhaus', family: 'Familie Trost', title: 'Deine Haushalte',
        newHousehold: 'Neuer Haushalt', more: 'Mehr', items: ['Milch', 'Brot', 'Äpfel'], holidayItems: ['Brennholz'] }
      : { withEmail: 'Continue with email', email: 'Email', password: 'Password', signUp: 'Sign up', decline: "Don't allow",
        create: 'Create a household', first: 'Our household', holiday: 'Holiday home', family: 'The Trosts', title: 'Your households',
        newHousehold: 'New household', more: 'More', items: ['Milk', 'Bread', 'Apples'], holidayItems: ['Firewood'] };
    const shot = (page: Page, name: string) => screenshot(page, `169b-${lang}-${scheme}-${name}`);
    const page = await newPage(browser, { locale: de ? 'de-DE' : 'en-US', colorScheme: scheme, viewport: phone });
    const email = newEmail(`hh-shots-${lang}`);
    await page.goto('/');
    await openEmailSignIn(page, { button: t.withEmail, field: t.email });
    await typeInto(page.getByRole('textbox', { name: t.email }), email);
    await typeInto(page.getByRole('textbox', { name: t.password }), password);
    await page.getByRole('button', { name: t.signUp }).click();
    await page.getByRole('button', { name: t.decline, exact: true }).click();
    await page.getByRole('button', { name: new RegExp(`^${t.create}`) }).click();
    await page.getByRole('button', { name: t.create, exact: true }).click();
    await expect(page).toHaveURL(/\/welcome\/invite$/);

    const api = await apiAs(email);
    const owner = await householdWithInvite(`hh-shots-owner-${lang}`, t.family);
    const { data: holiday } = await api.rpc('create_household', {
      p_name: t.holiday, p_default_stores: false, p_stores: [], p_request_id: crypto.randomUUID(), p_kind: null,
    });
    expect((await api.rpc('accept_invite', { p_code: owner.code, p_mode: 'add' })).data?.status).toBe('joined');
    const first = firstOf((await myHouseholds(email)).filter((h) => h.name === t.first), 'first household');
    const items = [
      ...t.items.map((name) => ({ household_id: first.id, name })),
      ...t.holidayItems.map((name) => ({ household_id: holiday.id, name })),
    ];
    expect((await api.from('items').insert(items)).error).toBeNull();
    expect((await (await apiAs(owner.email)).from('items').insert({ household_id: owner.household, name: t.items[0] })).error)
      .toBeNull();

    await page.goto('/');
    const chip = householdChip(page, t.first);
    await expect(chip).toBeVisible();
    await expect(itemRow(page, t.items[2] ?? '')).toBeVisible();
    await shot(page, '01-chip');
    await chip.click();
    await expect(page.getByRole('heading', { name: t.title })).toBeVisible();
    await expect(page.getByRole('button', { name: new RegExp(`^${t.family}`) })).toBeVisible();
    await shot(page, '02-switcher');
    await page.getByRole('button', { name: t.newHousehold, exact: true }).click();
    await expect(page).toHaveURL(/\/households\/new$/);
    await shot(page, '03-create');
    // The household page of a shared household that is not the default.
    await page.goto('/');
    await householdChip(page, t.first).click();
    await page.getByRole('button', { name: new RegExp(`^${t.family}`) }).click();
    await expect(householdChip(page, t.family)).toBeVisible();
    await page.goto('/more/household');
    await expect(page.getByRole('button', { name: de ? 'Haushalt verlassen' : 'Leave household', exact: true })).toBeVisible();
    await shot(page, '04-household-page');
  });
}
