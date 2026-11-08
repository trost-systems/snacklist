// Job 169b, wave 3 (docs/households/W3.md): club features against the real stack. Several lists
// per household (tabs, a move between lists, the per-list duplicate rule, a delete from the
// household page, old writes landing in the first list), "Ich bringe" claims seen live by
// another member, join approval (request, live approval, decline) and the MCP list tools.
import { type Browser, expect, type Locator, type Page, test } from './fixtures';
import {
  addField, addItem, adminClient, apiAs, confirmJoin, createHousehold, editSheet, firstOf, householdChip, invitePath, itemRow,
  must, newEmail, openEdit, openEmailSignIn, openMore, openTab, password, saveEdit, screenshot, signUp, signUpWithHousehold, skipInvite, tick,
  typeInto, wheelTo,
} from './helpers';
import { call, connectWithToken } from './mcp-helpers';

type ListRow = { id: string; name: string; position: number };

const phone = { width: 390, height: 844 };
const escape = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

async function newPage(browser: Browser, options: Parameters<Browser['newContext']>[0] = {}): Promise<Page> {
  return (await browser.newContext({ viewport: phone, ...options })).newPage();
}

const listTab = (page: Page, name: string): Locator => page.getByRole('tab', { name, exact: true });
const newListButton = (page: Page): Locator => page.getByRole('button', { name: 'Neue Liste', exact: true });
/** A plain snackbar's text, the semantics copy (the announcement duplicates it). */
const snack = (page: Page, text: string): Locator => page.locator('[id^="flt-semantic-node-"]').getByText(text, { exact: true });
/** [text] as its own node, or inside a group's accessible name (Flutter web merges a card's texts). */
const shown = (page: Page, text: string): Locator =>
  page.getByText(text, { exact: true }).or(page.getByRole('group', { name: new RegExp(escape(text)) })).first();

async function userIdOf(email: string): Promise<string> {
  const { data } = await (await apiAs(email)).auth.getUser();
  return must(data.user, `user ${email}`).id;
}

async function nameUser(email: string, name: string): Promise<void> {
  const { error } = await adminClient().from('profiles').update({ 'display_name': name }).eq('id', await userIdOf(email));
  if (error) throw error;
}

/** Names a new list in the open "Neue Liste" dialog and creates it. */
async function nameNewList(page: Page, name: string): Promise<void> {
  await typeInto(page.getByRole('textbox', { name: 'Name der Liste' }), name);
  await page.getByRole('button', { name: 'Erstellen', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Name der Liste' })).toHaveCount(0);
}

async function itemsOn(household: string): Promise<{ name: string; list: string }[]> {
  const { data, error } = await adminClient().from('items').select('name, lists(name)')
    .eq('household_id', household).eq('status', 'active').order('name');
  if (error) throw error;
  return (data as unknown as { name: string; lists: { name: string } }[]).map((i) => ({ name: i.name, list: i.lists.name }));
}

async function householdOf(email: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).rpc('my_households');
  if (error) throw error;
  return firstOf(data as { id: string }[], 'household').id;
}

async function listsOf(household: string): Promise<ListRow[]> {
  const { data, error } = await adminClient().from('lists').select('id, name, position')
    .eq('household_id', household).order('position');
  if (error) throw error;
  return data as ListRow[];
}

/** A user made on the server, with a household of [kind]. */
async function serverUser(tag: string, household = 'Verein Grün', kind: string | null = null) {
  const email = newEmail(tag);
  const { error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const api = await apiAs(email);
  const { data, error: createError } = await api.rpc('create_household', {
    p_request_id: crypto.randomUUID(), p_name: household, p_kind: kind,
  });
  if (createError) throw createError;
  return { email, api, household: (data as { id: string }).id };
}

async function createTokenInSettings(page: Page, name: string): Promise<string> {
  await openMore(page, 'Zugänge');
  await page.getByRole('button', { name: 'Token erstellen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), name);
  await page.getByRole('button', { name: 'Erstellen' }).click();
  const shown = page.getByText(/^fgp_[A-Za-z0-9_-]{43}$/);
  await expect(shown).toBeVisible();
  return must(await shown.textContent(), 'token text');
}

test('an old app\'s insert without a list lands in the first list; a club household asks to approve joins', async () => {
  const owner = await serverUser('club-old');
  const { data: second, error } = await owner.api.rpc('create_list', {
    p_household: owner.household, p_name: 'Sommerfest', p_id: crypto.randomUUID(),
  });
  expect(error).toBeNull();
  await owner.api.rpc('move_list', { p_list: (second as ListRow).id, p_position: 0 });
  const lists = await listsOf(owner.household);
  expect(lists.map((l) => l.name), 'moved to the front').toEqual(['Sommerfest', 'Einkaufsliste']);

  const { data: inserted, error: insertError } = await owner.api.from('items')
    .insert({ 'household_id': owner.household, name: 'Grillkohle' }).select('list_id').single();
  expect(insertError).toBeNull();
  expect(must(inserted, 'item').list_id, 'the first list by position').toBe(firstOf(lists, 'list').id);

  const club = await serverUser('club-kind', 'Turnverein', 'club');
  const { data: mine } = await club.api.rpc('my_households');
  expect((mine as { kind: string; join_approval: boolean }[]).map((h) => [h.kind, h.join_approval]))
    .toEqual([['club', true]]);
  expect((await owner.api.rpc('my_households')).data?.[0]?.join_approval, 'off for other kinds').toBe(false);
});

test('MCP: list_lists names the lists, add_items with "list" writes to that one', async ({ page }) => {
  const email = newEmail('club-mcp');
  await signUpWithHousehold(page, email);
  const household = await householdOf(email);
  const { error } = await (await apiAs(email)).rpc('create_list', {
    p_household: household, p_name: 'Baumarkt', p_id: crypto.randomUUID(),
  });
  expect(error).toBeNull();
  const client = await connectWithToken(await createTokenInSettings(page, 'Listen'));

  const lists = await call<{ id: string; name: string; default: boolean }[]>(client, 'list_lists');
  expect(lists.map((l) => [l.name, l.default])).toEqual([['Einkaufsliste', true], ['Baumarkt', false]]);
  await call(client, 'add_items', { items: [{ name: 'Schrauben' }], list: 'baumarkt' });
  await call(client, 'add_items', { items: [{ name: 'Milch' }] });
  const inBaumarkt = await call<{ list: string; items: { name: string }[] }>(client, 'list_items', { list: 'Baumarkt' });
  expect([inBaumarkt.list, inBaumarkt.items.map((i) => i.name)]).toEqual(['Baumarkt', ['Schrauben']]);
  const inFirst = await call<{ list: string; items: { name: string }[] }>(client, 'list_items', {});
  expect([inFirst.list, inFirst.items.map((i) => i.name)]).toEqual(['Einkaufsliste', ['Milch']]);
});

test('lists: a second list, adds stay on their list, tabs switch, a move between lists, the same name on two, a delete', async ({ browser }) => {
  test.setTimeout(240_000);
  const page = await newPage(browser);
  const email = newEmail('club-lists');
  await signUpWithHousehold(page, email);
  const household = await householdOf(email);
  await addItem(page, 'Milch');
  await expect(page.getByRole('tablist', { name: 'Listen' }), 'one list: no tabs').toHaveCount(0);

  // The first further list from the household page, the next one from the tabs' "+".
  await openMore(page, 'Unser Haushalt');
  await expect(page).toHaveURL(/\/more\/household$/);
  await wheelTo(page, newListButton(page));
  await newListButton(page).click();
  await nameNewList(page, 'Sommerfest');
  await openTab(page, 'Liste');
  await expect(listTab(page, 'Einkaufsliste')).toBeVisible();
  await expect(listTab(page, 'Sommerfest')).toBeVisible();
  await listTab(page, 'Sommerfest').click();
  await expect(listTab(page, 'Sommerfest')).toHaveAttribute('aria-selected', 'true');
  await expect(itemRow(page, 'Milch'), 'Milch is on the first list').toHaveCount(0);
  await addItem(page, 'Kuchen');
  await addItem(page, 'Grillkohle');

  await newListButton(page).click();
  await nameNewList(page, 'Vereinsheim');
  await expect(listTab(page, 'Vereinsheim')).toHaveAttribute('aria-selected', 'true');
  await expect(itemRow(page, 'Kuchen')).toHaveCount(0);
  await addItem(page, 'Kuchen');
  await addItem(page, 'Kaffee');
  await expect(itemRow(page, 'Kuchen'), 'the same name may be open on two lists').toBeVisible();

  await listTab(page, 'Einkaufsliste').click();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(itemRow(page, 'Kuchen')).toHaveCount(0);
  await expect.poll(() => itemsOn(household)).toEqual([
    { name: 'Grillkohle', list: 'Sommerfest' },
    { name: 'Kaffee', list: 'Vereinsheim' },
    { name: 'Kuchen', list: 'Sommerfest' },
    { name: 'Kuchen', list: 'Vereinsheim' },
    { name: 'Milch', list: 'Einkaufsliste' },
  ].sort((a, b) => a.name.localeCompare(b.name) || a.list.localeCompare(b.list)));

  // Milch moves to Sommerfest through the edit sheet's "Liste".
  await openEdit(page, 'Milch');
  const picker = editSheet(page).getByRole('group', { name: 'Liste', exact: true });
  await expect(picker.getByRole('button')).toHaveText(['Einkaufsliste', 'Sommerfest', 'Vereinsheim']);
  await picker.getByRole('button', { name: 'Sommerfest', exact: true }).click();
  await saveEdit(page);
  await expect(itemRow(page, 'Milch'), 'gone from the shown list').toHaveCount(0);
  await listTab(page, 'Sommerfest').click();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect.poll(async () => (await itemsOn(household)).find((i) => i.name === 'Milch')?.list).toBe('Sommerfest');
  await screenshot(page, 'w3-de-light-list-tabs');

  await page.reload();
  await expect(listTab(page, 'Sommerfest'), 'the device shows the list it showed last').toHaveAttribute('aria-selected', 'true');
  await expect(itemRow(page, 'Milch')).toBeVisible();

  // Delete Vereinsheim from the household page: the confirm names its open items.
  await openMore(page, 'Unser Haushalt');
  const actions = page.getByRole('button', { name: 'Aktionen für „Vereinsheim“' });
  await wheelTo(page, actions);
  await actions.click();
  await page.getByRole('menuitem', { name: 'Löschen', exact: true }).or(page.getByRole('button', { name: 'Löschen', exact: true })).click();
  await expect(shown(page, '„Vereinsheim“ löschen?')).toBeVisible();
  await expect(shown(page, 'Die 2 offenen Artikel darauf werden mit gelöscht.')).toBeVisible();
  await page.getByRole('button', { name: 'Löschen', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Aktionen für „Vereinsheim“' })).toHaveCount(0);
  expect((await listsOf(household)).map((l) => l.name)).toEqual(['Einkaufsliste', 'Sommerfest']);
  expect((await itemsOn(household)).map((i) => i.name).sort()).toEqual(['Grillkohle', 'Kuchen', 'Milch']);
  await openTab(page, 'Liste');
  await expect(listTab(page, 'Vereinsheim')).toHaveCount(0);
});

test('claims: Lea says she brings 2, Peter\'s open app shows it live; taking it back; a tick ends a claim', async ({ browser }) => {
  test.setTimeout(240_000);
  const peterEmail = newEmail('club-claim-peter');
  const peter = await newPage(browser);
  await signUp(peter, peterEmail);
  await createHousehold(peter, { name: 'Verein Grün' });
  await skipInvite(peter);
  await nameUser(peterEmail, 'Peter Trost');
  const household = await householdOf(peterEmail);
  const { data: invite, error } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household, p_kind: 'person' });
  if (error) throw error;
  await addItem(peter, 'Kuchen');
  await addItem(peter, 'Salat');
  const { error: listError } = await (await apiAs(peterEmail)).rpc('create_list', {
    p_household: household, p_name: 'Vereinsheim', p_id: crypto.randomUUID(),
  });
  if (listError) throw listError;
  await expect(listTab(peter, 'Vereinsheim'), 'a list made elsewhere shows live').toBeVisible({ timeout: 15_000 });

  const leaEmail = newEmail('club-claim-lea');
  const lea = await newPage(browser);
  await signUp(lea, leaEmail, invitePath((invite as { code: string }).code));
  await nameUser(leaEmail, 'Lea Berg');
  await confirmJoin(lea, 'Verein Grün');
  await lea.reload();
  await expect(itemRow(lea, 'Kuchen')).toBeVisible();

  await openEdit(lea, 'Kuchen');
  await editSheet(lea).getByRole('checkbox', { name: 'Ich bringe das' }).click();
  await typeInto(editSheet(lea).getByRole('textbox', { name: 'Wie viel?' }), '2');
  await screenshot(lea, 'w3-de-light-edit-sheet-list-claim');
  await saveEdit(lea);
  await expect(itemRow(lea, 'Kuchen'), 'her own claim').toHaveAccessibleName(/Du bringst 2/);
  await expect(itemRow(peter, 'Kuchen'), 'live on Peter\'s open app').toHaveAccessibleName(/Lea Berg bringt 2/, { timeout: 15_000 });

  await openEdit(peter, 'Salat');
  await editSheet(peter).getByRole('checkbox', { name: 'Ich bringe das' }).click();
  await saveEdit(peter);
  await expect(itemRow(lea, 'Salat')).toHaveAccessibleName(/Peter Trost bringt/, { timeout: 15_000 });
  await screenshot(peter, 'w3-de-light-claims');

  await openEdit(lea, 'Kuchen');
  await editSheet(lea).getByRole('checkbox', { name: 'Ich bringe das' }).click();
  await saveEdit(lea);
  await expect(itemRow(peter, 'Kuchen'), 'taken back').not.toHaveAccessibleName(/bringt/, { timeout: 15_000 });

  const salat = firstOf((await adminClient().from('items').select('id').eq('household_id', household).eq('name', 'Salat')).data, 'Salat');
  await tick(lea, 'Salat');
  await expect.poll(async () => (await adminClient().from('item_claims').select('user_id').eq('item_id', salat.id)).data)
    .toEqual([]);
});

test('join approval: the owner turns it on; a request waits, is approved live and the app switches; a decline', async ({ browser }) => {
  test.setTimeout(300_000);
  const peterEmail = newEmail('club-approve-peter');
  const peter = await newPage(browser);
  await signUp(peter, peterEmail);
  await createHousehold(peter, { name: 'Verein Grün' });
  await skipInvite(peter);
  await nameUser(peterEmail, 'Peter Trost');
  const household = await householdOf(peterEmail);
  await addItem(peter, 'Bier');

  await openMore(peter, 'Verein Grün');
  const toggle = peter.getByRole('switch', { name: /Beitritte bestätigen/ }).or(peter.getByRole('checkbox', { name: /Beitritte bestätigen/ }));
  await wheelTo(peter, toggle);
  await toggle.click();
  await expect.poll(async () => (await adminClient().from('households').select('join_approval').eq('id', household).single()).data?.join_approval)
    .toBe(true);
  const { data: invite, error } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household, p_kind: 'group' });
  if (error) throw error;
  const code = (invite as { code: string }).code;

  // Anna, new, opens the group link: a request, no membership.
  const annaEmail = newEmail('club-approve-anna');
  const anna = await newPage(browser);
  await signUp(anna, annaEmail, invitePath(code));
  await nameUser(annaEmail, 'Anna Berg');
  await anna.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(shown(anna, 'Anfrage gesendet: Ein Admin von „Verein Grün“ bestätigt deinen Beitritt.')).toBeVisible();
  await screenshot(anna, 'w3-de-light-approval-waiting');
  const { data: members } = await adminClient().from('household_members').select('user_id').eq('household_id', household);
  expect(members, 'not a member yet').toHaveLength(1);

  // Peter's open household page shows the request live.
  const approve = peter.getByRole('button', { name: /^Aufnehmen/ });
  await expect(shown(peter, 'Anna Berg')).toBeVisible({ timeout: 15_000 });
  await wheelTo(peter, approve);
  await screenshot(peter, 'w3-de-light-approval-admin');
  await approve.click();

  await expect(snack(anna, 'Du bist jetzt in „Verein Grün“.')).toBeVisible({ timeout: 15_000 });
  await expect(householdChip(anna, 'Verein Grün')).toBeVisible();
  await expect(itemRow(anna, 'Bier')).toBeVisible();

  // Ben has a household of his own and asks with a person link; Peter declines.
  const benEmail = newEmail('club-approve-ben');
  const ben = await newPage(browser);
  await signUpWithHousehold(ben, benEmail);
  await nameUser(benEmail, 'Ben Kurz');
  const { data: person } = await (await apiAs(peterEmail)).rpc('create_invite', { p_household: household, p_kind: 'person' });
  await ben.goto(invitePath((person as { code: string }).code));
  await ben.getByRole('button', { name: 'Haushalt beitreten', exact: true }).click();
  await expect(shown(ben, 'Anfrage gesendet: Ein Admin von „Verein Grün“ bestätigt deinen Beitritt.')).toBeVisible();
  await ben.getByRole('button', { name: 'Zur Liste', exact: true }).click();
  await expect(addField(ben)).toBeVisible();

  const decline = peter.getByRole('button', { name: /^Ablehnen/ });
  await expect(shown(peter, 'Ben Kurz')).toBeVisible({ timeout: 15_000 });
  await wheelTo(peter, decline);
  await decline.click();
  await expect(snack(ben, 'Deine Anfrage für „Verein Grün“ wurde nicht angenommen.')).toBeVisible({ timeout: 15_000 });
  await expect(householdChip(ben, 'Unser Haushalt')).toBeVisible();
  const { data: after } = await adminClient().from('household_members').select('user_id').eq('household_id', household);
  expect(after, 'Peter and Anna').toHaveLength(2);
});

test('EN, dark: the list tabs', async ({ browser }) => {
  const page = await newPage(browser, { locale: 'en-US', colorScheme: 'dark' });
  const email = newEmail('club-en');
  await page.goto('/');
  await openEmailSignIn(page, { button: 'Continue with email', field: 'Email' });
  await typeInto(page.getByRole('textbox', { name: 'Email' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Password' }), password);
  await page.getByRole('button', { name: 'Sign up' }).click();
  await page.getByRole('button', { name: "Don't allow", exact: true }).click();
  await page.getByRole('button', { name: /^Create a household/ }).click();
  await typeInto(page.getByRole('textbox', { name: 'Household name' }), 'Green Club');
  await page.getByRole('button', { name: 'Create a household', exact: true }).click();
  await page.getByRole('button', { name: 'Later', exact: true }).click();
  await expect(page).toHaveURL(/\/$/);

  const household = await householdOf(email);
  const api = await apiAs(email);
  for (const name of ['Summer party', 'Clubhouse']) {
    const { error } = await api.rpc('create_list', { p_household: household, p_name: name, p_id: crypto.randomUUID() });
    if (error) throw error;
  }
  const party = must((await listsOf(household)).find((l) => l.name === 'Summer party'), 'Summer party');
  const { error } = await api.from('items').insert(['Cake', 'Charcoal', 'Lemonade', 'Paper plates'].map((name) => ({
    'household_id': household, 'list_id': party.id, name,
  })));
  if (error) throw error;
  await expect(page.getByRole('tab', { name: 'Summer party', exact: true })).toBeVisible({ timeout: 15_000 });
  await page.getByRole('tab', { name: 'Summer party', exact: true }).click();
  await expect(page.getByRole('checkbox', { name: /^Paper plates/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'New list', exact: true })).toBeVisible();
  await screenshot(page, 'w3-en-dark-list-tabs');
});
