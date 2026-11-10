// Job 169b, wave 2 (docs/households/W2.md): the invite loop against the real stack. The static
// join page asks preview_invite_public and hands over to the app; owner and admins make a group
// link, see who joined with it, revoke it and make a new one; the owner names admins; owner and
// admins remove members, and the removed user's open app says so and shows another household; the
// group link they still hold doesn't take them back, a new invite does.
// join-page.spec.ts covers the page's states with a faked answer.
import { type Browser, expect, type Locator, type Page, test } from './fixtures';
import {
  addField, adminClient, anonClient, answerConsent, apiAs, confirmJoin, createHousehold, firstOf, householdChip, invitePath, itemRow,
  must, newEmail, openEmailSignIn, openHouseholds, openJoinLink, openMore, openTab, password, screenshot, signUp, signUpHere,
  skipInvite, typeInto,
} from './helpers';

const phone = { width: 390, height: 844 };

async function newPage(browser: Browser, options: Parameters<Browser['newContext']>[0] = {}): Promise<Page> {
  return (await browser.newContext({ viewport: phone, ...options })).newPage();
}

// The join page allows 30 opens an hour per client, and every page here is the same client: a
// rerun within the hour starts from no opens.
test.beforeEach(async () => {
  const { error } = await adminClient().from('invite_preview_rate').delete().gte('hits', 0);
  if (error) throw error;
});

async function userIdOf(email: string): Promise<string> {
  const { data } = await (await apiAs(email)).auth.getUser();
  return must(data.user, `user ${email}`).id;
}

/** Sets the name the household shows for [email]'s user (it starts as the email's local part). */
async function nameUser(email: string, name: string): Promise<void> {
  const { error } = await adminClient().from('profiles').update({ 'display_name': name }).eq('id', await userIdOf(email));
  if (error) throw error;
}

async function householdIdOf(email: string, name: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).rpc('my_households');
  if (error) throw error;
  return must((data as { id: string; name: string }[]).find((h) => h.name === name), `household ${name}`).id;
}

async function membersOf(household: string): Promise<string[]> {
  const { data, error } = await adminClient().from('household_members').select('user_id').eq('household_id', household);
  if (error) throw error;
  return (data as { user_id: string }[]).map((m) => m.user_id);
}

/** The household's open group link's code. */
async function groupCode(household: string): Promise<string> {
  const { data, error } = await adminClient().from('invites').select('code')
    .eq('household_id', household).eq('kind', 'group').is('revoked_at', null);
  if (error) throw error;
  return firstOf(data as { code: string }[], 'open group link').code;
}

/** A user made on the server, named [name], with household [household] and a person invite. */
async function serverHousehold(tag: string, household: string, name: string) {
  const email = newEmail(tag);
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  await nameUser(email, name);
  const api = await apiAs(email);
  const { data: created, error: createError } = await api.rpc('create_household', { p_name: household });
  if (createError) throw createError;
  const { data: invite, error: inviteError } = await api.rpc('create_invite', { p_household: created.id, p_kind: 'person' });
  if (inviteError) throw inviteError;
  return { email, api, household: created.id as string, code: invite.code as string, invite: invite.id as string };
}

/** Wheels the open sheet (or page) until [target] is fully on screen. */
async function wheelTo(page: Page, target: Locator): Promise<void> {
  const { width, height } = must(page.viewportSize(), 'viewport');
  await page.mouse.move(width / 2, height * 0.7);
  for (let i = 0; i < 30; i++) {
    const box = await target.boundingBox({ timeout: 1_000 }).catch(() => null);
    if (box && box.y >= 0 && box.y + box.height <= height) return;
    await page.mouse.wheel(0, box && box.y < 0 ? -200 : 200);
    await page.waitForTimeout(150);
  }
  throw new Error(`could not scroll ${target} into view`);
}

const inviteSheetHeading = (page: Page, title = 'Leute einladen'): Locator => page.getByRole('heading', { name: title });

/** Opens "Leute einladen" for the shown [household] from its row in the switcher. */
async function openInviteSheet(page: Page, household: string): Promise<void> {
  await openHouseholds(page, household);
  await page.getByRole('button', { name: `Leute in ${household} einladen` }).click();
  await expect(inviteSheetHeading(page)).toBeVisible();
}

const joinHeading = (page: Page): Locator => page.getByRole('heading', { level: 1 });
const escape = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * [text] as the app shows it: its own node, or a part of a group's name, where Flutter web puts
 * the plain texts of a container (the sheet's counts and who joined).
 */
const shown = (page: Page, text: string): Locator =>
  page.getByText(text, { exact: true }).or(page.getByRole('group', { name: new RegExp(escape(text)) })).first();

/** A member's row on the household page: the name, then the role label if any („Hauptadmin“, „Admin“). */
const memberRow = (page: Page, name: string, role?: string): Locator => {
  const label = new RegExp(`^${escape(name)}${role === undefined ? '' : `\\s+${role}`}$`);
  return page.getByText(label).or(page.getByRole('group', { name: label }));
};
const memberMenu = (page: Page, name?: string): Locator =>
  page.getByRole('button', { name: name === undefined ? /^Optionen für / : `Optionen für ${name}` });
const menuItem = (page: Page, name: string): Locator =>
  page.getByRole('menuitem', { name, exact: true }).or(page.getByRole('button', { name, exact: true }));
/** A plain snackbar's text, the semantics copy (the announcement duplicates it). */
const snack = (page: Page, text: string): Locator => page.locator('[id^="flt-semantic-node-"]').getByText(text, { exact: true });

/** The tab goes to the background and comes back, as the app sees a switch to another app. */
async function backAndFront(page: Page): Promise<void> {
  await page.evaluate(() => globalThis.dispatchEvent(new Event('blur')));
  await page.waitForTimeout(300);
  await page.evaluate(() => globalThis.dispatchEvent(new Event('focus')));
}

test('the join page shows the real invite without item names; its button joins through sign-up', async ({ browser }) => {
  const owner = await serverHousehold('loop-page', 'Familie Brandt', 'Peter Trost');
  const { error } = await owner.api.from('items').insert([
    { 'household_id': owner.household, name: 'Hafermilch' },
    { 'household_id': owner.household, name: 'Zahnpasta' },
  ]);
  if (error) throw error;

  const page = await newPage(browser);
  await page.goto(`/join/${owner.code}`);
  await expect(joinHeading(page)).toHaveText('Peter lädt dich zu „Familie Brandt“ ein');
  await expect(page.getByText('1 Mitglied · 2 offene Einträge')).toBeVisible();
  await expect(page.getByText(/Premium/)).toBeHidden();
  await expect(page.getByText(`${owner.code.slice(0, 4)}-${owner.code.slice(4)}`)).toBeVisible();
  const html = await page.content();
  for (const secret of ['Hafermilch', 'Zahnpasta', owner.email, 'Trost', owner.household]) {
    expect(html, `no "${secret}" in the page`).not.toContain(secret);
  }
  const { data: answer } = await anonClient().rpc('preview_invite_public', { p_code: owner.code });
  expect(answer, 'what a signed-out caller gets').toMatchObject({
    status: 'ok', household: 'Familie Brandt', inviter: 'Peter', members: 1, 'open_items': 2, premium: false, 'invite_kind': 'person',
  });
  expect(Object.keys(answer as object).sort(), 'nothing else: no ids, emails or item names')
    .toEqual(['household', 'invite_kind', 'inviter', 'kind', 'members', 'open_items', 'premium', 'status']);
  const { data: counted } = await adminClient().from('invites').select('preview_count').eq('id', owner.invite).single();
  expect(must(counted, 'invite').preview_count, 'the page open and the call above').toBeGreaterThanOrEqual(2);
  await screenshot(page, 'w2-de-light-join-page');

  await page.getByRole('link', { name: 'Im Browser beitreten' }).click();
  await expect(page).toHaveURL(new RegExp(`/login\\?invite=${owner.code}$`));
  await signUpHere(page, newEmail('loop-page-lea'));
  await expect(page).toHaveURL(new RegExp(`/join/${owner.code}$`));
  await confirmJoin(page, 'Familie Brandt');
  await expect(itemRow(page, 'Hafermilch')).toBeVisible();
  expect(await membersOf(owner.household)).toHaveLength(2);

  // The used person invite and a made-up code: the page says the invite no longer works.
  for (const code of [owner.code, 'ZZZZ2345']) {
    const other = await newPage(browser);
    await other.goto(`/join/${code}`);
    await expect(joinHeading(other), code).toHaveText('Diese Einladung gilt nicht mehr');
    await expect(other.getByRole('link', { name: 'Code im Browser eingeben' })).toHaveAttribute('href', invitePath(code));
  }
});

test('group link: two join with it, the owner sees them live; members get no group link; revoke and renew', async ({ browser }) => {
  test.setTimeout(240_000);
  const peterEmail = newEmail('loop-peter');
  const peter = await newPage(browser);
  await signUp(peter, peterEmail);
  await createHousehold(peter, { name: 'Verein Grün' });
  await skipInvite(peter);
  await nameUser(peterEmail, 'Peter Trost');
  const household = await householdIdOf(peterEmail, 'Verein Grün');

  await openInviteSheet(peter, 'Verein Grün');
  await expect(peter.getByRole('button', { name: 'Neue Einladung' }), 'the person invite').toBeVisible();
  await wheelTo(peter, peter.getByRole('button', { name: 'Gruppenlink erstellen' }));
  await peter.getByRole('button', { name: 'Gruppenlink erstellen' }).click();
  await expect(shown(peter, '0 von 50 beigetreten')).toBeVisible();
  const code = await groupCode(household);
  await expect(peter.getByRole('group', { name: `Code ${code}` }).or(peter.getByText(`Code ${code}`, { exact: true }))).toBeVisible();
  await expect(peter.getByRole('img', { name: 'QR-Code des Gruppenlinks' })).toBeVisible();
  await wheelTo(peter, peter.getByRole('heading', { name: 'Wer ist beigetreten' }));
  await expect(shown(peter, 'Noch niemand.')).toBeVisible();

  // Anna opens the shared link: the page, then the browser join through sign-up.
  const annaEmail = newEmail('loop-anna');
  const anna = await newPage(browser);
  await anna.goto(`/join/${code}`);
  await expect(joinHeading(anna)).toHaveText('Peter lädt dich zu „Verein Grün“ ein');
  await openJoinLink(anna, `/join/${code}`);
  await signUpHere(anna, annaEmail);
  await nameUser(annaEmail, 'Anna Berg');
  await confirmJoin(anna, 'Verein Grün');

  // Ben has a household of his own and joins with the same link.
  const benEmail = newEmail('loop-ben');
  const ben = await newPage(browser);
  await signUp(ben, benEmail);
  await createHousehold(ben, { name: 'Bens WG' });
  await skipInvite(ben);
  await nameUser(benEmail, 'Ben Kurz');
  await ben.goto(invitePath(code));
  await confirmJoin(ben, 'Verein Grün');
  await expect(householdChip(ben, 'Verein Grün')).toBeVisible();
  expect(await membersOf(household)).toHaveLength(3);

  // The owner's open sheet follows live.
  await expect(shown(peter, '2 von 50 beigetreten')).toBeVisible({ timeout: 15_000 });
  await expect(shown(peter, 'Anna Berg')).toBeVisible();
  await expect(shown(peter, 'Ben Kurz')).toBeVisible();
  await expect(shown(peter, 'Noch niemand.')).toHaveCount(0);
  await wheelTo(peter, peter.getByRole('heading', { name: 'Wer ist beigetreten' }));
  await screenshot(peter, 'w2-de-light-invite-sheet-admin');

  // A member gets the person invite only.
  await openInviteSheet(anna, 'Verein Grün');
  await expect(anna.getByRole('button', { name: 'Neue Einladung' })).toBeVisible();
  for (const owners of ['Gruppenlink erstellen', 'Link widerrufen', 'Neuen Link erstellen']) {
    await expect(anna.getByRole('button', { name: owners }), owners).toHaveCount(0);
  }
  for (const heading of ['Gruppenlink', 'Wer ist beigetreten']) {
    await expect(anna.getByRole('heading', { name: heading, exact: true }), heading).toHaveCount(0);
  }
  await expect(shown(anna, 'von 50 beigetreten')).toHaveCount(0);
  const annaApi = await apiAs(annaEmail);
  const { error: notAdmin } = await annaApi.rpc('create_invite', { p_household: household, p_kind: 'group' });
  expect(notAdmin?.message, 'nor from the server').toContain('not_admin');
  const { data: link } = await adminClient().from('invites').select('id').eq('code', code).single();
  const { error: noRevoke } = await annaApi.rpc('revoke_invite', { p_invite: must(link, 'group link').id });
  expect(noRevoke?.message, 'a member cannot revoke the group link').toContain('not_admin');
  // Old store builds list `invites` with used_at null as their Einladungen page.
  const { data: oldAppList, error: oldAppError } = await annaApi.from('invites').select('code')
    .eq('household_id', household).is('used_at', null).is('revoked_at', null);
  if (oldAppError) throw oldAppError;
  expect(oldAppList, 'old builds see no group link to revoke').toEqual([]);

  // Revoke, then a new link: a new code, and the old link's page says it no longer works.
  await wheelTo(peter, peter.getByRole('button', { name: 'Link widerrufen' }));
  await peter.getByRole('button', { name: 'Link widerrufen' }).click();
  await expect(peter.getByText('Gruppenlink widerrufen?')).toBeVisible();
  await peter.getByRole('button', { name: 'Widerrufen', exact: true }).click();
  await expect(shown(peter, 'Link widerrufen: Niemand kann mehr damit beitreten.')).toBeVisible();
  await peter.getByRole('button', { name: 'Neuen Link erstellen' }).click();
  await expect(shown(peter, '0 von 50 beigetreten')).toBeVisible();
  const renewed = await groupCode(household);
  expect(renewed).not.toBe(code);
  await expect(peter.getByRole('group', { name: `Code ${renewed}` }).or(peter.getByText(`Code ${renewed}`, { exact: true })))
    .toBeVisible();

  const stranger = await newPage(browser);
  await stranger.goto(`/join/${code}`);
  await expect(joinHeading(stranger), 'the old link').toHaveText('Diese Einladung gilt nicht mehr');
  await stranger.goto(`/join/${renewed}`);
  await expect(joinHeading(stranger), 'the new link').toHaveText('Peter lädt dich zu „Verein Grün“ ein');
  await expect(stranger.getByText('3 Mitglieder · 0 offene Einträge')).toBeVisible();
});

test('roles: the owner makes an admin, the admin removes a member, whose open app says so; members remove nobody', async ({ browser }) => {
  test.setTimeout(240_000);
  const peterEmail = newEmail('roles-peter');
  const peter = await newPage(browser);
  await signUp(peter, peterEmail);
  await createHousehold(peter, { name: 'Verein Grün' });
  await skipInvite(peter);
  await nameUser(peterEmail, 'Peter Trost');
  const household = await householdIdOf(peterEmail, 'Verein Grün');
  const { data: invite, error } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household, p_kind: 'group' });
  if (error) throw error;
  const code = (invite as { code: string }).code;

  const annaEmail = newEmail('roles-anna');
  const anna = await newPage(browser);
  await signUp(anna, annaEmail, invitePath(code));
  await nameUser(annaEmail, 'Anna Berg');
  await confirmJoin(anna, 'Verein Grün');
  const benEmail = newEmail('roles-ben');
  const ben = await newPage(browser);
  await signUp(ben, benEmail);
  await createHousehold(ben, { name: 'Bens WG' });
  await skipInvite(ben);
  await nameUser(benEmail, 'Ben Kurz');
  await ben.goto(invitePath(code));
  await confirmJoin(ben, 'Verein Grün');

  // The owner's page: roles, and a menu for each other member.
  await openMore(peter, 'Verein Grün');
  await expect(peter).toHaveURL(/\/more\/household$/);
  await expect(memberRow(peter, 'Peter Trost (du)', 'Hauptadmin')).toBeVisible();
  await expect(memberRow(peter, 'Anna Berg')).toBeVisible();
  await expect(memberMenu(peter, 'Peter Trost (du)'), 'none for oneself').toHaveCount(0);
  await memberMenu(peter, 'Anna Berg').click();
  await expect(menuItem(peter, 'Aus dem Haushalt entfernen')).toBeVisible();
  await menuItem(peter, 'Zum Admin machen').click();
  await expect(memberRow(peter, 'Anna Berg', 'Admin')).toBeVisible();
  await expect.poll(async () => {
    const { data } = await adminClient().from('household_members').select('role')
      .eq('household_id', household).eq('user_id', await userIdOf(annaEmail)).single();
    return data?.role;
  }).toBe('admin');
  await screenshot(peter, 'w2-de-light-members-roles');

  // Ben, a member, has no menu for anyone; the server refuses him too.
  await openMore(ben, 'Verein Grün');
  await expect(memberRow(ben, 'Ben Kurz (du)')).toBeVisible();
  await expect(memberRow(ben, 'Anna Berg', 'Admin')).toBeVisible();
  await expect(memberMenu(ben)).toHaveCount(0);
  const { error: notAdmin } = await (await apiAs(benEmail)).rpc('remove_member', {
    p_household: household, p_user: await userIdOf(annaEmail),
  });
  expect(notAdmin?.message).toContain('not_admin');
  await openTab(ben, 'Liste');
  await expect(householdChip(ben, 'Verein Grün')).toBeVisible();

  // Anna, now admin: a menu for Ben (remove only), none for the owner. Her open app learns its
  // new role only from a fresh read of her households (reported: the household page's own row
  // says Admin before that, without the admin's menu), so she reloads.
  await anna.reload();
  await expect(addField(anna)).toBeVisible();
  await openMore(anna, 'Verein Grün');
  await expect(memberRow(anna, 'Anna Berg (du)', 'Admin')).toBeVisible();
  await expect(memberRow(anna, 'Peter Trost', 'Hauptadmin')).toBeVisible();
  await expect(memberMenu(anna, 'Peter Trost'), 'not for the owner').toHaveCount(0);
  await memberMenu(anna, 'Ben Kurz').click();
  await expect(menuItem(anna, 'Zum Admin machen'), 'only the owner names admins').toHaveCount(0);
  await menuItem(anna, 'Aus dem Haushalt entfernen').click();
  await expect(anna.getByText('Ben Kurz entfernen?')).toBeVisible();
  await anna.getByRole('button', { name: 'Entfernen', exact: true }).click();
  // The open dialog hides the page from the accessibility tree, so the row's absence alone proves
  // nothing: wait for the dialog to go and the server to answer.
  await expect(anna.getByText('Ben Kurz entfernen?')).toHaveCount(0);
  await expect.poll(() => membersOf(household), 'removed on the server')
    .not.toContain(await userIdOf(benEmail));
  await expect(memberRow(anna, 'Ben Kurz')).toHaveCount(0);

  // Ben's open app finds out when it comes back to the front: the notice, and his own household.
  const removedNotice = 'Du wurdest aus dem Haushalt „Verein Grün“ entfernt. 30 Tage lang kommst du über alte Einladungen nicht zurück. Beitreten kannst du in dieser Zeit nur über eine neue Einladung vom Hauptadmin oder einem Admin.';
  await backAndFront(ben);
  await expect(snack(ben, removedNotice)).toBeVisible({ timeout: 15_000 });
  await expect(householdChip(ben, 'Bens WG')).toBeVisible();
  await expect(addField(ben)).toBeVisible();

  // A device that never knew the club tells him too, at sign-in (my_household_removals), but only
  // once he has answered the analytics consent asked first: there it would cover the answers and
  // run out (15 s) while he reads (review 1 of job 178).
  const benPhone = await newPage(browser);
  await benPhone.goto('/login');
  await openEmailSignIn(benPhone);
  await typeInto(benPhone.getByRole('textbox', { name: 'E-Mail' }), benEmail);
  await typeInto(benPhone.getByRole('textbox', { name: 'Passwort' }), password);
  await benPhone.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(benPhone).toHaveURL(/\/analytics-consent(\?|$)/);
  await expect(benPhone.getByRole('heading', { name: 'Nutzungsdaten', exact: true })).toBeVisible();
  await benPhone.waitForTimeout(16_000);
  await expect(snack(benPhone, removedNotice), 'held behind the consent').toHaveCount(0);
  await answerConsent(benPhone);
  await expect(snack(benPhone, removedNotice)).toBeVisible({ timeout: 15_000 });
  await expect(householdChip(benPhone, 'Bens WG')).toBeVisible();

  // The group link still in the club's chat doesn't take him back; a new invite from the owner
  // or an admin does (a plain member's would not, pgTAP).
  await ben.goto(invitePath(code));
  await expect(ben.getByText('Dieser Code ist ungültig oder abgelaufen.', { exact: true }).first()).toBeVisible();
  await expect(ben.getByRole('button', { name: 'Haushalt beitreten', exact: true })).toHaveCount(0);
  expect(await membersOf(household), 'the old link').not.toContain(await userIdOf(benEmail));
  const { data: fresh, error: freshError } = await (await apiAs(peterEmail)).rpc('create_invite', {
    p_household: household, p_kind: 'person',
  });
  if (freshError) throw freshError;
  await ben.goto(invitePath((fresh as { code: string }).code));
  await confirmJoin(ben, 'Verein Grün');
  expect(await membersOf(household), 'a new invite').toContain(await userIdOf(benEmail));
});

test('EN, dark: the owner\'s invite sheet with a group link and who joined', async ({ browser }) => {
  const peter = await newPage(browser, { locale: 'en-US', colorScheme: 'dark' });
  const peterEmail = newEmail('loop-en');
  // Signed out, `/` is the guided start (job 168b): the sign-in first, then its steps from Welcome.
  await peter.goto('/login');
  await openEmailSignIn(peter, { button: 'Continue with email', field: 'Email' });
  await typeInto(peter.getByRole('textbox', { name: 'Email' }), peterEmail);
  await typeInto(peter.getByRole('textbox', { name: 'Password' }), password);
  await peter.getByRole('button', { name: 'Sign up' }).click();
  await peter.getByRole('button', { name: "Don't allow", exact: true }).click();
  await createHousehold(peter, { name: 'Green Club', lang: 'en' });
  await peter.getByRole('button', { name: 'Later', exact: true }).click();
  await expect(peter).toHaveURL(/\/$/);
  await nameUser(peterEmail, 'Peter Trost');
  const household = await householdIdOf(peterEmail, 'Green Club');
  const { data: invite, error } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household, p_kind: 'group' });
  if (error) throw error;
  for (const name of ['Anna Berg', 'Ben Kurz']) {
    const email = newEmail('loop-en-joiner');
    const { error: userError } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
    if (userError) throw userError;
    await nameUser(email, name);
    const { data: joined } = await (await apiAs(email)).rpc('accept_invite', { p_code: (invite as { code: string }).code });
    expect(joined.status).toBe('joined');
  }

  await householdChip(peter, 'Green Club').click();
  await expect(peter.getByRole('heading', { name: 'Your households' })).toBeVisible();
  await peter.getByRole('button', { name: 'Invite people to Green Club' }).click();
  await expect(inviteSheetHeading(peter, 'Invite people')).toBeVisible();
  await expect(shown(peter, '2 of 50 joined')).toBeVisible();
  await expect(peter.getByRole('img', { name: 'QR code of the group link' })).toBeVisible();
  await expect(peter.getByRole('button', { name: 'Revoke link' })).toBeVisible();
  await expect(shown(peter, 'Anna Berg')).toBeVisible();
  await expect(shown(peter, 'Ben Kurz')).toBeVisible();
  await wheelTo(peter, peter.getByRole('heading', { name: 'Who joined' }));
  await screenshot(peter, 'w2-en-dark-invite-sheet-admin');
});
