// Job 271 (JH2, flag join-household-jh2): an invite link joins in the browser. The sign-in asks
// first whether to create an account or sign in; a new account answers today's full-screen
// consent and lands on the invited household's list, an existing one lands there without the
// guided start; neither is asked "join?" again. Without a link, the household-name step's „Join
// existing household“ looks the code up as soon as the eighth character is in. With the flag off
// the screens stay as before (guided-start.spec.ts, invite-loop.spec.ts).
import { type Browser, expect, type Locator, type Page, test } from './fixtures';
import {
  addField, adminClient, answerConsent, apiAs, fakeCollector, itemRow, must, newEmail, openEmailSignIn, openJoinLink,
  password, screenshot, typeInto,
} from './helpers';

const phone = { width: 390, height: 844 };
const flag = 'join-household-jh2';

async function newPage(browser: Browser, { on = true } = {}): Promise<Page> {
  const context = await browser.newContext({ viewport: phone });
  await fakeCollector(context, { flags: { [flag]: on } });
  return context.newPage();
}

// Every page here is the same client for preview_invite_public's 30 opens an hour.
test.beforeEach(async () => {
  const { error } = await adminClient().from('invite_preview_rate').delete().gte('hits', 0);
  if (error) throw error;
});

async function userIdOf(email: string): Promise<string> {
  const { data } = await (await apiAs(email)).auth.getUser();
  return must(data.user, `user ${email}`).id;
}

async function householdsOf(email: string): Promise<string[]> {
  const { data, error } = await (await apiAs(email)).rpc('my_households');
  if (error) throw error;
  return (data as { name: string }[]).map((h) => h.name).sort();
}

/** A user made on the server, named [name], with [household], one open item and a person invite. */
async function serverHousehold(tag: string, household: string, name: string) {
  const email = newEmail(tag);
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const admin = adminClient();
  const { error: nameError } = await admin.from('profiles').update({ 'display_name': name }).eq('id', await userIdOf(email));
  if (nameError) throw nameError;
  const api = await apiAs(email);
  const { data: created, error: createError } = await api.rpc('create_household', { p_name: household });
  if (createError) throw createError;
  const { error: itemError } = await api.from('items').insert({ 'household_id': created.id, name: 'Hafermilch' });
  if (itemError) throw itemError;
  const { data: invite, error: inviteError } = await api.rpc('create_invite', { p_household: created.id, p_kind: 'person' });
  if (inviteError) throw inviteError;
  return { email, household: created.id as string, code: invite.code as string };
}

/** The invite sheet over the sign-in, and one of its two answers. */
async function answerInviteSheet(page: Page, answer: 'Konto erstellen' | 'Anmelden'): Promise<void> {
  await expect(page).toHaveURL(/\/login\?invite=/);
  const create = page.getByRole('button', { name: 'Konto erstellen', exact: true });
  await expect(create, 'the sheet asks before any sign-in method').toBeVisible({ timeout: 15_000 });
  await expect(page.getByText('Du bist in einen Haushalt eingeladen')).toBeVisible();
  await screenshot(page, '271-de-light-invite-sheet');
  await (answer === 'Konto erstellen' ? create : page.getByRole('button', { name: 'Anmelden', exact: true }).first()).click();
  await expect(create, 'the sheet closes').toBeHidden();
}

/** The email form after the sheet: email, password, then [button]. */
async function emailForm(page: Page, email: string, button: RegExp): Promise<void> {
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: button }).first().click();
}

/** The list of [household], reached without a join confirmation. */
async function onListOf(page: Page, household: string): Promise<void> {
  await expect(page).toHaveURL(/\/$/, { timeout: 30_000 });
  await expect(addField(page)).toBeVisible();
  await expect(itemRow(page, 'Hafermilch'), `the list of ${household}`).toBeVisible();
  await expect(page.getByRole('button', { name: 'Haushalt beitreten', exact: true }), 'never asked again').toBeHidden();
}

test('invite link, new account: create account, the full-screen consent, then the list; no second ask', async ({ browser }) => {
  const owner = await serverHousehold('jh2-new', 'Familie Brandt', 'Peter Trost');
  const page = await newPage(browser);
  const email = newEmail('jh2-new-lea');

  await openJoinLink(page, `/join/${owner.code}`);
  await answerInviteSheet(page, 'Konto erstellen');
  await emailForm(page, email, /^(Konto erstellen|Registrieren)$/);
  // Today's consent, full screen, right after the sign-up and before the join.
  await expect(page).toHaveURL(/\/analytics-consent(\?|$)/, { timeout: 20_000 });
  await expect(page.getByRole('heading', { name: 'Nutzungsdaten', exact: true })).toBeVisible();
  expect(await householdsOf(email), 'not joined before the consent is answered').toEqual([]);
  await screenshot(page, '271-de-light-consent');
  await answerConsent(page, 'decline');
  await onListOf(page, 'Familie Brandt');
  await expect(page.getByRole('button', { name: 'Nicht erlauben', exact: true }), 'no consent card on the list').toBeHidden();
  await screenshot(page, '271-de-light-list-after-join');

  expect(await householdsOf(email), 'the invited household only, none of her own').toEqual(['Familie Brandt']);
});

test('invite link, existing account: sign in, then the invited household’s list, never the guided start', async ({ browser }) => {
  const owner = await serverHousehold('jh2-old', 'WG Sonnenallee', 'Mia Berg');
  const ben = await serverHousehold('jh2-old-ben', 'Bens Haushalt', 'Ben Kurz');
  const page = await newPage(browser);
  const visited: string[] = [];
  page.on('framenavigated', (frame) => {
    if (frame === page.mainFrame()) visited.push(new URL(frame.url()).pathname);
  });

  await openJoinLink(page, `/join/${owner.code}`);
  await answerInviteSheet(page, 'Anmelden');
  await emailForm(page, ben.email, /^Anmelden$/);
  // A new browser is a new install: it asks once, as today.
  await answerConsent(page, 'decline');
  await onListOf(page, 'WG Sonnenallee');

  expect(await householdsOf(ben.email), 'both households, the invited one added').toEqual(['Bens Haushalt', 'WG Sonnenallee']);
  expect(visited.filter((p) => p.startsWith('/start')), 'no guided start').toEqual([]);
});

/** From the first screen to the household-name step, the usage question declined. */
async function toNameStep(page: Page): Promise<void> {
  await page.goto('/');
  await expect(page).toHaveURL(/\/start$/);
  await page.getByRole('button', { name: "Los geht's", exact: true }).click();
  const decline = page.getByRole('button', { name: 'Nicht erlauben', exact: true });
  const size = must(page.viewportSize(), 'viewport');
  await page.mouse.move(size.width / 2, size.height / 2);
  await expect(async () => {
    if (!(await decline.isVisible())) await page.mouse.wheel(0, 400);
    await expect(decline).toBeVisible({ timeout: 500 });
  }).toPass();
  await decline.click();
  await expect(page).toHaveURL(/\/start\/who$/);
  await page.getByRole('button', { name: 'Überspringen', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/name$/);
}

const codeField = (page: Page): Locator => page.getByRole('textbox', { name: 'Einladungscode' });
const joinButton = (page: Page): Locator => page.getByRole('button', { name: 'Beitreten', exact: true });
/** The preview card: one live region, so its text is also in the screen reader's announcement. */
const preview = (page: Page, text: RegExp): Locator => page.locator('[id^="flt-semantic-node-"]').getByText(text);

test('name step: a typed code shows who invites at the eighth character; a dead code shows nothing; Join leads through sign-up to the list', async ({ browser }) => {
  const owner = await serverHousehold('jh2-code', 'Familie Brandt', 'Peter Trost');
  const page = await newPage(browser);
  const email = newEmail('jh2-code-lea');

  await page.goto('/start');
  await expect(page.getByRole('button', { name: 'Ich habe schon ein Konto', exact: true })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('button', { name: 'Einladung einfügen' }), 'no Paste invite').toBeHidden();
  await screenshot(page, '271-de-light-start');

  await toNameStep(page);
  await expect(page.getByRole('button', { name: 'Weiter', exact: true })).toBeVisible();
  await screenshot(page, '271-de-light-name-step');
  await page.getByRole('button', { name: 'Bestehendem Haushalt beitreten', exact: true }).click();
  await expect(page).toHaveURL(/\/start\/join$/);
  await screenshot(page, '271-de-light-code-empty');

  // A made-up code: the generic line, no names, Join stays off.
  await typeInto(codeField(page), 'ZZZZ2345');
  await expect(preview(page, /^Diese Einladung gilt nicht mehr/)).toBeVisible();
  await expect(joinButton(page)).toBeDisabled();

  // The real one, no tap after the eighth character.
  await typeInto(codeField(page), owner.code);
  await expect(preview(page, /^Peter lädt dich zu „Familie Brandt“ ein\s+1 Mitglied · 1 offener Eintrag$/)).toBeVisible();
  await expect(page.getByText(/Hafermilch/), 'no item names before the join').toBeHidden();
  await screenshot(page, '271-de-light-code-preview');
  await joinButton(page).click();

  await answerInviteSheet(page, 'Konto erstellen');
  await emailForm(page, email, /^(Konto erstellen|Registrieren)$/);
  // Usage was answered at the start: no consent screen, straight to the list.
  await onListOf(page, 'Familie Brandt');
  expect(await householdsOf(email), 'no household of her own from the draft').toEqual(['Familie Brandt']);
});

test('name step: a pasted invite (lower case, with its dash) is looked up without a tap', async ({ browser }) => {
  const owner = await serverHousehold('jh2-paste', 'Familie Brandt', 'Peter Trost');
  const page = await newPage(browser);
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await toNameStep(page);
  await page.getByRole('button', { name: 'Bestehendem Haushalt beitreten', exact: true }).click();

  const written = `${owner.code.slice(0, 4).toLowerCase()}-${owner.code.slice(4).toLowerCase()}`;
  await page.evaluate((text) => navigator.clipboard.writeText(text), written);
  await codeField(page).click();
  await expect(codeField(page)).toBeFocused();
  await page.keyboard.press('ControlOrMeta+v');
  await expect(codeField(page)).toHaveValue(owner.code);
  await expect(preview(page, /^Peter lädt dich zu „Familie Brandt“ ein/)).toBeVisible();
  await expect(joinButton(page)).toBeEnabled();
});

test('flag off: the start screen, Paste invite and the sign-in for an invite stay as they were', async ({ browser }) => {
  const owner = await serverHousehold('jh2-off', 'Familie Brandt', 'Peter Trost');
  const page = await newPage(browser, { on: false });
  await page.goto('/start');
  await expect(page.getByRole('button', { name: 'Ich habe schon ein Konto', exact: true })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('button', { name: 'Einladung einfügen' })).toBeVisible();

  await openJoinLink(page, `/join/${owner.code}`);
  await expect(page).toHaveURL(/\/login\?invite=/);
  await expect(page.getByText('Einladung gemerkt. Melde dich an, dann trittst du bei.')).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('button', { name: 'Konto erstellen', exact: true }), 'no invite sheet').toBeHidden();
});

const iPhone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';

test('a phone browser: the Open card on every load, closed until the next one; not on a desktop browser', async ({ browser }) => {
  const owner = await serverHousehold('jh2-open', 'Familie Brandt', 'Peter Trost');
  const context = await browser.newContext({ viewport: phone, userAgent: iPhone });
  await fakeCollector(context, { flags: { [flag]: true } });
  const page = await context.newPage();
  await page.goto('/login');
  await emailForm(page, owner.email, /^Anmelden$/);
  await answerConsent(page, 'decline');
  await onListOf(page, 'Familie Brandt');

  const open = page.getByRole('button', { name: 'Öffnen', exact: true });
  // The card is one container: on the web its text is the name of a group.
  const text = 'Snacklist funktioniert in der App besser.';
  await expect(page.getByText(text, { exact: true }).or(page.getByRole('group', { name: new RegExp(text.replace('.', '\\.')) })).first())
    .toBeVisible();
  await expect(open).toBeVisible();
  await screenshot(page, '271-de-light-open-card');
  await page.getByRole('button', { name: 'Schließen', exact: true }).click();
  await expect(open, 'closed').toBeHidden();
  await page.reload();
  await expect(itemRow(page, 'Hafermilch')).toBeVisible();
  await expect(open, 'back on the next load').toBeVisible();

  const desktop = await newPage(browser);
  await desktop.goto('/login');
  await emailForm(desktop, owner.email, /^Anmelden$/);
  await answerConsent(desktop, 'decline');
  await onListOf(desktop, 'Familie Brandt');
  await expect(desktop.getByRole('button', { name: 'Öffnen', exact: true }), 'no card on a desktop browser').toBeHidden();
});
