// Job 22 (Spec #3): onboarding after sign-in and the analytics consent: create a household (with
// with the stores picked, job 58, or without) or join one with an invite, invite the partner, manage invites.
// The acceptance criteria on the web; the mobile parts are unit-tested (app/test/household,
// app/test/app/router_test.dart, deep_links_config_test.dart) and on Peter's device checklist.
import { expect, test, type Browser, type Page } from './fixtures';
import process from 'node:process';
import {
  addField, addItem, adminClient, answerConsent, apiAs, type Collector, confirmJoin, createHousehold, createInviteCode,
  cutOff, eventNames, fakeCollector, firstOf, inviteCodeLabel, invitePreview, itemRow, joinWithCode, latestLinkFor, must, newEmail, openMore, password,
  screenshot, shownInviteCodes, signUp, signUpWithHousehold, skipInvite, typeInto, viaFakeProvider, within,
  invitePath, openEmailSignIn, openJoinLink, signUpHere,
} from './helpers';

/** Waits until [collector] got exactly [names] among the events named there, in order. */
async function received(collector: Collector, names: string[]) {
  await expect
    .poll(() => eventNames(collector).filter((n) => names.includes(n)), { timeout: 15_000 })
    .toEqual(names);
}

const invalid = 'Dieser Code ist ungültig oder abgelaufen.';
const offline = 'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';
const tooMany = 'Zu viele Versuche. Bitte später noch einmal.';
const phone = { width: 390, height: 844 };
const tablet = { width: 1366, height: 1024 };

/** A user made on the server, signed in for API calls. */
async function apiUser(tag: string) {
  const email = newEmail(tag);
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  return { email, api: await apiAs(email) };
}

/** A household of a server-made user with an open invite: its id and code. */
async function householdWithInvite(tag: string, name = 'Familie Trost') {
  const owner = await apiUser(tag);
  const { data: household, error } = await owner.api.rpc('create_household', { p_name: name });
  if (error) throw error;
  const { data: invite, error: inviteError } = await owner.api.rpc('create_invite', { p_household: household.id });
  if (inviteError) throw inviteError;
  return { ...owner, household: household.id as string, code: invite.code as string, invite: invite.id as string };
}

async function membersOf(household: string): Promise<string[]> {
  const { data, error } = await adminClient().from('household_members').select('user_id').eq('household_id', household);
  if (error) throw error;
  return (data as { user_id: string }[]).map((m) => m.user_id);
}

async function userIdOf(email: string): Promise<string> {
  const { data, error } = await adminClient().auth.admin.listUsers({ perPage: 1000 });
  if (error) throw error;
  return must(data.users.find((u) => u.email === email), `user ${email}`).id;
}

async function householdsCreatedBy(email: string) {
  const { data, error } = await adminClient().from('households').select('id, name').eq('created_by', await userIdOf(email));
  if (error) throw error;
  return data as { id: string; name: string }[];
}

/** A plain snackbar's text shows twice (semantics and announcement): the semantics one. */
const snack = (page: Page, text: string) => page.locator('[id^="flt-semantic-node-"]').getByText(text, { exact: true });

/** The join screen's problem line, which a live region may duplicate. */
const problem = (page: Page, text: string) => page.getByText(text, { exact: true }).first();

async function newPage(browser: Browser, options: Parameters<Browser['newContext']>[0] = {}): Promise<Page> {
  return (await browser.newContext(options)).newPage();
}

test('AC1-3: sign-in, consent, Step 1, create with picked stores, invite with a visible code', async ({ browser }) => {
  const page = await newPage(browser, { viewport: phone, permissions: ['clipboard-read', 'clipboard-write'] });
  const email = newEmail('create');
  await signUp(page, email);
  // AC1: consent (answered in signUp) came first, then Step 1.
  await expect(page).toHaveURL(/\/welcome$/);
  await expect(page.getByRole('button', { name: /^Haushalt erstellen/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Einladung annehmen/ })).toBeVisible();

  await createHousehold(page, { stores: ['dm', 'Lidl', 'Wochenmarkt'] });
  const household = firstOf(await householdsCreatedBy(email), 'household');
  expect(household.name).toBe('Unser Haushalt');
  expect(await membersOf(household.id), 'the user is its only member').toEqual([await userIdOf(email)]);
  const { data: role } = await adminClient().from('household_members').select('role').eq('household_id', household.id).single();
  expect(must(role, 'membership').role).toBe('owner');
  const { data: stores } = await adminClient().from('stores').select('name').eq('household_id', household.id).order('sort_order');
  expect((stores as { name: string }[]).map((s) => s.name), 'two from the offer and an own one, in the order picked')
    .toEqual(['dm', 'Lidl', 'Wochenmarkt']);

  // AC3 on the web: Chromium here has no Web Share, so the invite shows with its code and link.
  await page.getByRole('button', { name: 'Partner einladen', exact: true }).click();
  await expect(inviteCodeLabel(page).first()).toBeVisible();
  const [code] = await shownInviteCodes(page);
  expect(code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  const link = `${new URL(page.url()).origin}/join/${code}`;
  // "Link <url>" is one node.
  await expect(page.getByText(link)).toBeVisible();
  await expect(page.getByText(/^gültig bis /)).toBeVisible();
  await page.getByRole('button', { name: 'Link kopieren' }).click();
  await expect(snack(page, 'Link kopiert')).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(link);
  await page.getByRole('button', { name: 'Code kopieren' }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(code);
  await skipInvite(page);

  // The shared link works: a second person joins with it (AC4 in live-sync.spec.ts).
  const lea = await newPage(browser);
  await openJoinLink(lea, link);
  await expect(lea).toHaveURL(new RegExp(`/login\\?invite=${code}$`));
  await signUpHere(lea, newEmail('lea'));
  await confirmJoin(lea, 'Unser Haushalt');
  expect(await membersOf(household.id)).toHaveLength(2);
});

test('AC2: Skip creates a household without stores; categories and the fallback are there', async ({ page }) => {
  const email = newEmail('skip');
  await signUp(page, email);
  await createHousehold(page, { name: 'WG Sonnenallee', stores: [] });
  const household = firstOf(await householdsCreatedBy(email), 'household');
  expect(household.name).toBe('WG Sonnenallee');
  const admin = adminClient();
  const { count: stores } = await admin.from('stores').select('*', { count: 'exact', head: true }).eq('household_id', household.id);
  expect(stores).toBe(0);
  const { data: categories } = await admin.from('categories').select('seed_key').eq('household_id', household.id);
  expect(categories).toHaveLength(11);
  expect((categories as { seed_key: string }[]).map((c) => c.seed_key)).toContain('other');
  await skipInvite(page);
  await addItem(page, 'Milch');
  await expect(itemRow(page, 'Milch'), 'the list works without stores').toBeVisible();
});

test('AC2: a double tap, and a retry after a lost answer, make one household', async ({ page }) => {
  const email = newEmail('double');
  await signUp(page, email);
  await page.getByRole('button', { name: /^Haushalt erstellen/ }).click();
  await expect(page).toHaveURL(/\/welcome\/create$/);
  // The first answer is lost on the way back: the server created the household, the app saw none.
  let dropped = false;
  await page.route('**/rest/v1/rpc/create_household', async (route) => {
    if (dropped) return route.continue();
    dropped = true;
    await route.fetch();
    await route.abort('connectionreset');
  });
  const create = page.getByRole('button', { name: 'Haushalt erstellen', exact: true });
  await create.dblclick();
  await expect(problem(page, offline)).toBeVisible();
  expect(dropped).toBe(true);
  expect(await householdsCreatedBy(email), 'the server made it').toHaveLength(1);
  // The retry finds it (already_in_household) and goes on.
  await create.click();
  await expect(page).toHaveURL(/\/welcome\/invite$/);
  expect(await householdsCreatedBy(email), 'still one').toHaveLength(1);
});

test('AC5 and AC12: a typed code joins; events once, without names, emails, codes or links', async ({ browser }) => {
  const ownerContext = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
  const ownerEvents = await fakeCollector(ownerContext);
  const owner = await ownerContext.newPage();
  const ownerEmail = newEmail('ac12-owner');
  await signUp(owner, ownerEmail, '/', { consent: 'accept' });
  await createHousehold(owner, { name: 'Familie Geheim', stores: ['Supermarkt', 'Drogerie', 'Wochenmarkt'] });
  await owner.getByRole('button', { name: 'Partner einladen', exact: true }).click();
  await expect(inviteCodeLabel(owner).first()).toBeVisible();
  const code = firstOf(await shownInviteCodes(owner), 'invite code');
  await owner.getByRole('button', { name: 'Code kopieren' }).click();
  await owner.getByRole('button', { name: 'Link kopieren' }).click();
  await skipInvite(owner);
  await received(ownerEvents, ['first_open', 'household_created', 'invite_sent', 'invite_sent']);
  const created = must(ownerEvents.events.find((e) => e.event === 'household_created'), 'household_created event');
  expect(created.properties.store_count).toBe(3);
  expect(ownerEvents.events.filter((e) => e.event === 'invite_sent').map((e) => [e.properties.channel, e.properties.context]))
    .toEqual([['copy_code', 'onboarding'], ['copy_link', 'onboarding']]);

  const memberContext = await browser.newContext();
  const memberEvents = await fakeCollector(memberContext);
  const member = await memberContext.newPage();
  const memberEmail = newEmail('ac12-member');
  await signUp(member, memberEmail, '/', { consent: 'accept' });
  await joinWithCode(member, code.toLowerCase(), 'Familie Geheim');
  await received(memberEvents, ['first_open', 'invite_accepted']);
  expect(must(memberEvents.events.find((e) => e.event === 'invite_accepted'), 'invite_accepted event').properties.method).toBe('code');
  // A realtime echo or a reload sends nothing more.
  await addItem(owner, 'Kaffee');
  await expect(itemRow(member, 'Kaffee')).toBeVisible();
  await member.reload();
  await expect(addField(member)).toBeVisible();
  await received(memberEvents, ['first_open', 'invite_accepted']);

  const sent = JSON.stringify([...ownerEvents.events, ...memberEvents.events]);
  for (const secret of [code, code.toLowerCase(), '/join/', 'Familie Geheim', 'Unser Haushalt', ownerEmail, memberEmail,
    ownerEmail.split('@')[0], memberEmail.split('@')[0]]) {
    expect(sent, `no "${secret}" in any event`).not.toContain(secret);
  }
  expect([...ownerEvents.leaks, ...memberEvents.leaks]).toEqual([]);
});

test('AC12: declined, onboarding works the same and sends nothing', async ({ browser }) => {
  const context = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
  const collector = await fakeCollector(context);
  const page = await context.newPage();
  await signUp(page, newEmail('declined'));
  await createHousehold(page);
  await page.getByRole('button', { name: 'Partner einladen', exact: true }).click();
  await page.getByRole('button', { name: 'Link kopieren' }).click();
  await skipInvite(page);
  const { code } = await householdWithInvite('declined-other');
  await page.goto(invitePath(code));
  await confirmJoin(page, 'Familie Trost');
  await page.waitForTimeout(6_000);
  expect(collector.requests).toEqual([]);
});

test('AC6: an invite link survives sign-in when the location loses it (password)', async ({ page }) => {
  const { code, household } = await householdWithInvite('ac6-pw');
  await page.goto(invitePath(code));
  await expect(page).toHaveURL(new RegExp(`/login\\?invite=${code}$`));
  // The location drops the invite (as the apps' sign-in callback does): the device kept it.
  await page.goto('/');
  await expect(page).toHaveURL(new RegExp(`/login\\?invite=${code}$`));
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), newEmail('ac6-pw'));
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();
  await answerConsent(page);
  await expect(page).toHaveURL(new RegExp(`/join/${code}$`));
  await confirmJoin(page, 'Familie Trost');
  expect(await membersOf(household)).toHaveLength(2);
});

test('AC6: magic link sign-in lands on the join screen', async ({ page }) => {
  const { code, household } = await householdWithInvite('ac6-magic');
  const email = newEmail('ac6-magic');
  await page.goto(invitePath(code));
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await page.getByRole('button', { name: 'Anmeldelink per E-Mail senden' }).click();
  await expect(page.getByText(/Anmeldelink geschickt/).first()).toBeVisible();
  await page.goto(await latestLinkFor(email));
  await answerConsent(page);
  await expect(page).toHaveURL(new RegExp(`/join/${code}$`));
  await confirmJoin(page, 'Familie Trost');
  expect(await membersOf(household)).toHaveLength(2);
});

for (const provider of ['Google', 'Apple'] as const) {
  test(`AC6: ${provider} sign-in (fake provider) lands on the join screen`, async ({ page }) => {
    const { code, household } = await householdWithInvite(`ac6-${provider.toLowerCase()}`);
    await page.goto(invitePath(code));
    await expect(page).toHaveURL(new RegExp(`/login\\?invite=${code}$`));
    await viaFakeProvider(page, newEmail(`ac6-${provider.toLowerCase()}`));
    await page.getByRole('button', { name: `Mit ${provider} anmelden` }).click();
    await answerConsent(page);
    await expect(page).toHaveURL(new RegExp(`/join/${code}$`));
    await confirmJoin(page, 'Familie Trost');
    expect(await membersOf(household)).toHaveLength(2);
  });
}

test('AC7: expired, revoked, used and made-up codes give one message and no membership; 6 days old works', async ({ browser }) => {
  const admin = adminClient();
  const owner = await householdWithInvite('ac7');
  const make = async () => {
    const { data, error } = await owner.api.rpc('create_invite', { p_household: owner.household });
    if (error) throw error;
    return data as { id: string; code: string };
  };
  const expired = await make();
  await admin.from('invites').update({ created_at: new Date(Date.now() - 8 * 864e5).toISOString(), expires_at: new Date(Date.now() - 864e5).toISOString() }).eq('id', expired.id);
  const sixDays = await make();
  await admin.from('invites').update({ created_at: new Date(Date.now() - 6 * 864e5).toISOString(), expires_at: new Date(Date.now() + 864e5).toISOString() }).eq('id', sixDays.id);
  const revoked = await make();
  expect((await owner.api.rpc('revoke_invite', { p_invite: revoked.id })).error).toBeNull();
  const used = await make();
  const taker = await apiUser('ac7-taker');
  expect((await taker.api.rpc('accept_invite', { p_code: used.code })).data.status).toBe('joined');

  const page = await newPage(browser);
  await signUp(page, newEmail('ac7'));
  await page.getByRole('button', { name: /^Einladung annehmen/ }).click();
  const field = page.getByRole('textbox', { name: 'Einladungscode' });
  for (const code of [expired.code, revoked.code, used.code, 'ZZZZ2345']) {
    await typeInto(field, code);
    await page.getByRole('button', { name: 'Weiter', exact: true }).click();
    await expect(problem(page, invalid), code).toBeVisible();
    await expect(page.getByText('Familie Trost'), 'no hint which household').toHaveCount(0);
  }
  expect(await membersOf(owner.household), 'nobody new').toHaveLength(2);
  await typeInto(field, sixDays.code);
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await confirmJoin(page, 'Familie Trost');
  expect(await membersOf(owner.household)).toHaveLength(3);
});

test('AC8: a member revokes an invite under More; its link and code stop at once', async ({ browser }) => {
  const page = await newPage(browser);
  const email = newEmail('ac8');
  await signUpWithHousehold(page, email);
  const code = await createInviteCode(page);
  const kept = await createInviteCode(page);
  await openMore(page, 'Partner einladen');
  await expect(inviteCodeLabel(page, code)).toBeVisible();
  await page.getByRole('button', { name: `Einladung ${code} widerrufen` }).click();
  await expect(inviteCodeLabel(page, code), 'gone from the list').toHaveCount(0);
  await expect(inviteCodeLabel(page, kept)).toBeVisible();

  const lea = await newPage(browser);
  await signUp(lea, newEmail('ac8-lea'), invitePath(code));
  await expect(problem(lea, invalid), 'the link').toBeVisible();
  const other = await apiUser('ac8-other');
  expect((await other.api.rpc('accept_invite', { p_code: code })).data.status, 'the code').toBe('invalid_invite');
  // Members cannot un-revoke it through the table (job 22 revoked the column grant).
  const api = await apiAs(email);
  const { error } = await api.from('invites').update({ revoked_at: null }).eq('code', code);
  expect(error, 'no update right on invites').not.toBeNull();
  expect((await other.api.rpc('accept_invite', { p_code: code })).data.status).toBe('invalid_invite');
});

test('AC9: someone in a household who opens an invite sees whose it is, and nothing changes without a Join', async ({ browser }) => {
  const page = await newPage(browser);
  const email = newEmail('ac9');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Tee');
  const mine = firstOf(await householdsCreatedBy(email), 'household');
  const { code, household } = await householdWithInvite('ac9-other');
  await page.goto(invitePath(code));
  await expect(invitePreview(page, 'Familie Trost')).toBeVisible();
  // Job 169b: joining adds a household beside this one, so there is no move to warn about.
  await expect(page.getByText('Du bist schon in einem Haushalt'), 'no move warning').toHaveCount(0);
  await page.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(itemRow(page, 'Tee')).toBeVisible();
  expect(await membersOf(mine.id), 'still in their household').toEqual([await userIdOf(email)]);
  expect(await membersOf(household), 'not in the other').toHaveLength(1);
  // Opening the link again shows the invite again; nothing happened in between.
  await page.goto(invitePath(code));
  await expect(invitePreview(page, 'Familie Trost')).toBeVisible();
});

test('a link opened twice, or by a member, lands on the list without a second membership', async ({ browser }) => {
  const page = await newPage(browser);
  const email = newEmail('twice');
  await signUpWithHousehold(page, email);
  const code = await createInviteCode(page);
  // The inviter opens their own link.
  await page.goto(invitePath(code));
  await expect(addField(page)).toBeVisible();
  await expect(page).toHaveURL(/\/$/);
  const household = firstOf(await householdsCreatedBy(email), 'household');

  const lea = await newPage(browser);
  await signUp(lea, newEmail('twice-lea'), invitePath(code));
  await confirmJoin(lea);
  await lea.goto(invitePath(code));
  await expect(addField(lea)).toBeVisible();
  await expect(lea).toHaveURL(/\/$/);
  expect(await membersOf(household.id)).toHaveLength(2);
});

test('AC10: offline, create and join say so, keep what was typed and work on retry, once', async ({ browser }) => {
  const page = await newPage(browser);
  const email = newEmail('ac10');
  await signUp(page, email);
  await page.getByRole('button', { name: /^Haushalt erstellen/ }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name des Haushalts' }), 'Offline-WG');
  const cut = await cutOff(page);
  await page.getByRole('button', { name: 'Haushalt erstellen', exact: true }).click();
  await expect(problem(page, offline)).toBeVisible();
  expect(await householdsCreatedBy(email)).toHaveLength(0);
  await cut.restore();
  // The retry without typing again: the name was kept.
  await page.getByRole('button', { name: 'Haushalt erstellen', exact: true }).click();
  await expect(page).toHaveURL(/\/welcome\/invite$/);
  expect((await householdsCreatedBy(email)).map((h) => h.name)).toEqual(['Offline-WG']);

  // Inviting offline too.
  const cutAgain = await cutOff(page);
  await page.getByRole('button', { name: 'Partner einladen', exact: true }).click();
  await expect(problem(page, offline)).toBeVisible();
  await cutAgain.restore();
  await page.getByRole('button', { name: 'Partner einladen', exact: true }).click();
  await expect(inviteCodeLabel(page).first()).toBeVisible();

  const { code, household } = await householdWithInvite('ac10-other');
  const lea = await newPage(browser);
  await signUp(lea, newEmail('ac10-lea'));
  await lea.getByRole('button', { name: /^Einladung annehmen/ }).click();
  await typeInto(lea.getByRole('textbox', { name: 'Einladungscode' }), code);
  const leaCut = await cutOff(lea);
  await lea.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(problem(lea, offline)).toBeVisible();
  await leaCut.restore();
  // The retry without typing again: the code was kept.
  await lea.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(lea.getByText('Familie Trost')).toBeVisible();
  // Offline again at the join itself, and a lost answer on the retry.
  const joinCut = await cutOff(lea);
  await lea.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(problem(lea, offline)).toBeVisible();
  await joinCut.restore();
  let dropped = false;
  await lea.route('**/rest/v1/rpc/accept_invite', async (route) => {
    if (dropped) return route.continue();
    dropped = true;
    await route.fetch();
    await route.abort('connectionreset');
  });
  await lea.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(problem(lea, offline)).toBeVisible();
  expect(await membersOf(household), 'the server took the first').toHaveLength(2);
  await confirmJoin(lea, 'Familie Trost');
  expect(await membersOf(household), 'one membership').toHaveLength(2);
});

test('AC13: after 10 wrong codes in an hour the next is refused, the field keeps the code', async ({ page }) => {
  const email = newEmail('ac13');
  await signUp(page, email);
  const api = await apiAs(email);
  for (let i = 0; i < 9; i++) {
    expect((await api.rpc('preview_invite', { p_code: `WRONG${i}` })).data.status).toBe('invalid_invite');
  }
  const { code } = await householdWithInvite('ac13-other');
  await page.getByRole('button', { name: /^Einladung annehmen/ }).click();
  const field = page.getByRole('textbox', { name: 'Einladungscode' });
  await typeInto(field, 'ZZZZ2345');
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(problem(page, invalid), 'the 10th failure still says invalid').toBeVisible();
  await typeInto(field, code);
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await expect(problem(page, tooMany), 'the 11th is refused, a good code too').toBeVisible();
  expect((await api.rpc('accept_invite', { p_code: code })).data.status).toBe('too_many_attempts');
  // An hour later (the window moved back here), the kept code goes through without typing again.
  await adminClient().from('invite_attempts').update({ at: new Date(Date.now() - 61 * 60e3).toISOString() })
    .eq('user_id', await userIdOf(email));
  await page.getByRole('button', { name: 'Weiter', exact: true }).click();
  await confirmJoin(page, 'Familie Trost');
});

test('two people racing for one code: exactly one joins', async () => {
  const { code, household } = await householdWithInvite('race');
  const [a, b] = await Promise.all([apiUser('race-a'), apiUser('race-b')]);
  const results = await Promise.all([a, b].map(async (u) => (await u.api.rpc('accept_invite', { p_code: code })).data.status));
  expect(results.sort()).toEqual(['invalid_invite', 'joined']);
  expect(await membersOf(household)).toHaveLength(2);
});

test('AC11: onboarding, the share text and errors in English', async ({ browser }) => {
  const page = await newPage(browser, { locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  await page.goto('/');
  await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
  await typeInto(page.getByRole('textbox', { name: 'Email' }), newEmail('english'));
  await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
  await page.getByRole('button', { name: 'Sign up' }).click();
  await page.getByRole('button', { name: "Don't allow", exact: true }).click();
  await expect(page.getByRole('button', { name: /^Create a household/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Join with an invite/ })).toBeVisible();
  await page.getByRole('button', { name: /^Join with an invite/ }).click();
  await typeInto(page.getByRole('textbox', { name: 'Invite code' }), 'ZZZZ2345');
  await page.getByRole('button', { name: 'Continue', exact: true }).click();
  await expect(problem(page, 'This code is invalid or has expired.')).toBeVisible();
  await page.getByRole('button', { name: 'Cancel' }).click();
  await page.getByRole('button', { name: /^Create a household/ }).click();
  await expect(page.getByRole('textbox', { name: 'Household name' })).toBeVisible();
  await expect(page.getByRole('checkbox', { name: 'EDEKA', exact: true }), 'nothing picked').not.toBeChecked();
  await expect(page.getByRole('button', { name: 'Add your own store' })).toBeVisible();
  await expect(page.getByText(/^We use shop names such as dm, Lidl or EDEKA only/)).toBeVisible();
  await page.getByRole('button', { name: 'Create a household', exact: true }).click();
  await page.getByRole('button', { name: 'Invite your partner', exact: true }).click();
  await expect(page.getByText(/^valid until /)).toBeVisible();
  await page.getByRole('button', { name: 'Copy link' }).click();
  await expect(snack(page, 'Link copied')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Go to the list' })).toBeVisible();
});

// Screenshots for the PR: every onboarding state, German and English, phone and tablet.
for (const [lang, locale] of [['de', 'de-DE'], ['en', 'en-US']] as const) {
  for (const [size, viewport] of [['390', phone], ['1366', tablet]] as const) {
    test(`screenshots ${lang} ${size}`, async ({ browser }) => {
      test.skip(!process.env.SCREENSHOT_DIR, 'only when screenshots are asked for');
      const t = lang === 'de'
        ? { withEmail: 'Weiter mit E-Mail', email: 'E-Mail', password: 'Passwort', signUp: 'Registrieren', decline: 'Nicht erlauben', create: 'Haushalt erstellen',
          join: 'Einladung annehmen', skip: /^Überspringen/, invite: 'Partner einladen', code: 'Einladungscode', next: 'Weiter',
          later: 'Weiter zur Liste', more: 'Partner einladen', newInvite: 'Neue Einladung' }
        : { withEmail: 'Continue with email', email: 'Email', password: 'Password', signUp: 'Sign up', decline: "Don't allow", create: 'Create a household',
          join: 'Join with an invite', skip: /^Skip/, invite: 'Invite your partner', code: 'Invite code', next: 'Continue',
          later: 'Go to the list', more: 'Invite your partner', newInvite: 'New invite' };
      const shot = (page: Page, n: string, name: string) => screenshot(page, `job22-${lang}-${size}-${n}-${name}`);
      const page = await newPage(browser, { locale, viewport });
      await page.goto('/');
      await openEmailSignIn(page, { button: t.withEmail, field: t.email });
      await typeInto(page.getByRole('textbox', { name: t.email }), newEmail(`shots-${lang}`));
      await typeInto(page.getByRole('textbox', { name: t.password }), password);
      await page.getByRole('button', { name: t.signUp }).click();
      await expect(page).toHaveURL(/\/analytics-consent$/);
      await shot(page, '01', 'consent');
      await page.getByRole('button', { name: t.decline }).click();
      await expect(page.getByRole('button', { name: new RegExp(`^${t.create}`) })).toBeVisible();
      await shot(page, '02', 'step1');
      await page.getByRole('button', { name: new RegExp(`^${t.create}`) }).click();
      await expect(page.getByRole('button', { name: t.create, exact: true })).toBeVisible();
      await shot(page, '03', 'create-stores');
      await page.getByRole('checkbox', { name: 'REWE', exact: true }).or(page.getByRole('button', { name: 'REWE', exact: true }))
        .click();
      await shot(page, '04', 'create-stores-picked');
      const cut = await cutOff(page);
      await page.getByRole('button', { name: t.create, exact: true }).click();
      await expect(page.getByRole('textbox').first()).toBeVisible();
      await page.waitForTimeout(500);
      await shot(page, '05', 'create-offline');
      await cut.restore();
      await page.getByRole('button', { name: t.create, exact: true }).click();
      await page.getByRole('button', { name: t.invite, exact: true }).click();
      await expect(inviteCodeLabel(page).first().or(page.getByText(/^Code [A-HJ-NP-Z2-9]{8}$/)).first()).toBeVisible();
      await shot(page, '06', 'invite-web-fallback');
      await page.getByRole('button', { name: t.later }).click();
      await expect(addField(page).or(page.getByRole('textbox', { name: 'What do you need?' }))).toBeVisible();
      await page.getByRole('tab', { name: lang === 'de' ? 'Mehr' : 'More', exact: true })
        .or(page.getByRole('button', { name: `${lang === 'de' ? 'Mehr' : 'More'} Tab ` })).click();
      await page.getByRole('button', { name: new RegExp(`^${t.more}`) }).click();
      await page.getByRole('button', { name: t.newInvite }).click();
      await expect.poll(async () => (await shownInviteCodes(page)).length).toBe(2);
      await shot(page, '07', 'invites-revoke');

      // The join side: another person, a good code, then an invalid one, the rate limit, offline.
      const { code } = await householdWithInvite(`shots-${lang}-${size}`);
      const joiner = await newPage(browser, { locale, viewport });
      const joinerEmail = newEmail(`shots-join-${lang}`);
      await joiner.goto(invitePath(code));
      await openEmailSignIn(joiner, { button: t.withEmail, field: t.email });
      await typeInto(joiner.getByRole('textbox', { name: t.email }), joinerEmail);
      await typeInto(joiner.getByRole('textbox', { name: t.password }), password);
      await joiner.getByRole('button', { name: t.signUp }).click();
      await joiner.getByRole('button', { name: t.decline }).click();
      await expect(joiner.getByText('Familie Trost').first()).toBeVisible();
      await shot(joiner, '08', 'join-household-name');
      const field = joiner.getByRole('textbox', { name: t.code });
      await typeInto(field, 'ZZZZ2345');
      await joiner.getByRole('button', { name: t.next, exact: true }).click();
      await expect(joiner.getByText(lang === 'de' ? invalid : 'This code is invalid or has expired.').first()).toBeVisible();
      await shot(joiner, '09', 'join-invalid');
      const joinerCut = await cutOff(joiner);
      await typeInto(field, code);
      await joiner.getByRole('button', { name: t.next, exact: true }).click();
      await expect(joiner.getByText(lang === 'de' ? offline : "No internet connection. Try again once you're online.").first()).toBeVisible();
      await shot(joiner, '10', 'join-offline');
      await joinerCut.restore();
      const api = await apiAs(joinerEmail);
      for (let i = 0; i < 10; i++) await api.rpc('preview_invite', { p_code: `WRONG${i}` });
      await joiner.getByRole('button', { name: t.next, exact: true }).click();
      await expect(joiner.getByText(lang === 'de' ? tooMany : 'Too many attempts. Please try again later.').first()).toBeVisible();
      await shot(joiner, '11', 'join-rate-limit');

      // Already in a household: the first user opens the link, which adds a household (job 169b).
      await page.goto(invitePath(code));
      await expect(page.getByText('Familie Trost').first()).toBeVisible();
      await shot(page, '12', 'join-while-in-household');
    });
  }
}

test("a used invite disappears from More's invite list", async ({ browser }) => {
  const page = await newPage(browser);
  await signUpWithHousehold(page, newEmail('used'));
  const code = await createInviteCode(page);
  const kept = await createInviteCode(page);
  const lea = await newPage(browser);
  await signUp(lea, newEmail('used-lea'), invitePath(code));
  await confirmJoin(lea);
  await openMore(page, 'Partner einladen');
  // Since job 169b W2 an empty list shows nothing: the open invite shows, the used one not.
  await expect(inviteCodeLabel(page, kept)).toBeVisible();
  await within(10_000, (timeout) => expect(inviteCodeLabel(page, code)).toHaveCount(0, { timeout }));
});
