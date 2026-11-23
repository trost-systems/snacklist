// Job 50 (Spec #4): MCP is part of Snacklist Premium once the server's integration_lock switch is
// on. A user without premium (per user: another member's plan does not count, job 328) is refused
// in context and nothing is added; the integration settings say so, with connections paused, not
// removed; the user's own Premium opens it within one sync with the same credentials, for that
// user only (a household's grant or another member's plan opens nothing, job 419); its end locks
// it again and deletes nothing. A tester's per-user grant works throughout. Siri (job 184) and Alexa (job 72, Legal Review N-27) stay free:
// they add throughout and Alexa's connection never shows as paused.
//
// The switch is global, so this spec runs alone after the suite (scripts/gates/e2e.sh,
// FG_E2E_INTEGRATION_LOCK): it turns the switch on and off again.
import type { Client } from '@modelcontextprotocol/client';
import { type Browser, expect, type Page, test } from './fixtures';
import {
  adminClient,
  apiAs,
  firstOf,
  functionsUrl,
  itemRow,
  joinWithCode,
  must,
  newEmail,
  openMore,
  screenshot,
  signUp,
  signUpWithHousehold,
} from './helpers';
import { linkAccount, registerAlexaClient, say as alexaSay } from './alexa-helpers';
import { householdOf } from './iap';
import { connectWithToken } from './mcp-helpers';

test.describe.configure({ mode: 'serial' });

const mcpPremium =
  'Dafür brauchst du einen anderen Snacklist-Tarif. Infos: https://snacklist.app/de/anleitungen/ki-assistenten-tarif Es wurde nichts gelesen oder geändert.';

async function lockSwitch(enabled: boolean) {
  const { error } = await adminClient().from('app_switches').update({ enabled }).eq('key', 'integration_lock');
  if (error) throw error;
}

test.beforeAll(() => lockSwitch(true));
test.afterAll(() => lockSwitch(false));

/** The Siri Shortcut's request: one sentence, the PAT, the spoken answer as text. */
/**
 * Stores or ends a RevenueCat promotional grant without end for the user [user] (job 419: the
 * integrations count only the user's own Premium), as the purchases function does for a user's
 * customer.
 */
async function promote(user: string, active = true): Promise<string> {
  const { data, error } = await adminClient().rpc('promotional_premium_sync_user',
    { p_user: user, p_active: active, p_expires_at: null });
  expect(error).toBeNull();
  return data as string;
}

async function userOf(email: string): Promise<string> {
  const { data } = await (await apiAs(email)).auth.getUser();
  return must(data.user?.id, 'user id');
}

async function siri(token: string, text: string) {
  const res = await fetch(`${functionsUrl}/voice?format=text`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  return { status: res.status, speech: await res.text() };
}

async function toolText(client: Client, name: string, args: Record<string, unknown> = {}) {
  const result = await client.callTool({ name, arguments: args });
  return { isError: result.isError === true, text: firstOf(result.content as { text: string }[], 'tool result text').text };
}

async function openNames(email: string): Promise<string[]> {
  const { data, error } = await (await apiAs(email)).from('items').select('name').eq('status', 'active')
    .order('created_at');
  expect(error).toBeNull();
  return (data as { name: string }[]).map((r) => r.name);
}

async function pat(email: string, name: string): Promise<string> {
  const { data, error } = await (await apiAs(email)).rpc('create_personal_access_token', { p_name: name });
  expect(error).toBeNull();
  return (Array.isArray(data) ? data[0] : data).token as string;
}

const newPage = async (browser: Browser) => {
  const page = await (await browser.newContext()).newPage();
  await page.setViewportSize({ width: 390, height: 844 });
  return page;
};

const card = (page: Page) => page.getByRole('heading', { name: 'Teil von Snacklist Premium' });
/** A connection's tile: one group named by its texts, "Pausiert: …" last while locked. */
// A token row is a group. A connected app's row opens its details (job 80), so it is a button,
// told from its „<name> trennen“ button by the details after the name.
const tile = (page: Page, name: string) =>
  page.getByRole('group', { name: new RegExp(`^${name} `) })
    .or(page.getByRole('button', { name: new RegExp(`^${name} .* · `) }));
const paused = (page: Page) => page.getByRole('group', { name: /Pausiert: braucht Snacklist Premium$/ });

test('locked household: MCP refuses in context and adds nothing, Siri and Alexa add; the own Premium opens '
  + "MCP for Peter only, with the same credentials; its end locks again and keeps everything", async ({ browser, baseURL }) => {
  test.setTimeout(240_000);
  const peterEmail = newEmail('lock-peter');
  const leaEmail = newEmail('lock-lea');
  const peter = await newPage(browser);
  await signUpWithHousehold(peter, peterEmail);
  const { data: invite } = await (await apiAs(peterEmail)).rpc('create_invite', {
    p_household: await householdOf(peterEmail),
  });
  const lea = await newPage(browser);
  await signUp(lea, leaEmail);
  await joinWithCode(lea, (Array.isArray(invite) ? invite[0] : invite).code);

  // Peter connects all three while locked: linking is allowed, so unlocking needs no relinking.
  const shortcut = await pat(peterEmail, 'Kurzbefehl');
  const alexa = await linkAccount(peter, await registerAlexaClient(), must(baseURL, 'baseURL'));
  await peter.goto('/');
  const mcp = await connectWithToken(shortcut);

  expect(await siri(shortcut, 'Brot'), 'Siri is never locked (job 184)')
    .toEqual({ status: 200, speech: 'Hinzugefügt: Brot.' });
  expect(await alexaSay(alexa.access_token, 'Eier'), 'Alexa is never locked').toBe('Ich habe Eier auf die Snacklist gesetzt.');
  const sideDoor = await siri(alexa.access_token, 'Senf');
  expect(sideDoor.status, 'an OAuth client token is no way into the voice function (job 213)').toBe(401);
  expect(sideDoor.speech).toContain('Zugriffstoken fehlt oder ist ungültig');
  expect(await openNames(peterEmail), 'nothing added through it').not.toContain('Senf');
  const tools = (await mcp.listTools()).tools.map((t) => t.name);
  expect(tools, 'tools/list stays reachable').toContain('add_items');
  expect(await toolText(mcp, 'add_items', { items: [{ name: 'Kaffee' }] })).toEqual({ isError: true, text: mcpPremium });
  expect(await toolText(mcp, 'list_items')).toEqual({ isError: true, text: mcpPremium });
  expect(await openNames(peterEmail), 'the Siri and Alexa adds went through').toEqual(['Brot', 'Eier']);

  // Both members see it in the integration settings; the web sells nothing.
  await openMore(peter, 'Zugänge');
  await openMore(lea, 'Zugänge');
  await expect(card(peter)).toBeVisible();
  await expect(card(lea)).toBeVisible();
  await expect(peter.getByRole('group', { name: /Snacklist Premium kaufst du in der iPhone- oder Android-App\./ }))
    .toBeVisible();
  await expect(peter.getByRole('button', { name: 'Snacklist Premium freischalten' }), 'no Buy on the web')
    .toHaveCount(0);
  await expect(paused(peter).first(), 'the connections stay, paused').toBeVisible();
  await expect(tile(peter, 'Kurzbefehl')).toHaveAccessibleName(/Pausiert: braucht Snacklist Premium$/);
  await expect(tile(peter, 'Amazon Alexa'), 'Alexa is free, never paused')
    .not.toHaveAccessibleName(/Pausiert: braucht Snacklist Premium$/);
  await screenshot(peter, 'job50-web-access-locked-de-390');

  // Peter has Premium of his own: within one sync everything opens for him, same credentials.
  // Premium belongs to the account (Terms §6): Lea, in the same household, stays locked.
  const peterId = await userOf(peterEmail);
  expect(await promote(peterId)).toBe('granted');
  await expect(card(peter), 'Peter loses the card live').toHaveCount(0, { timeout: 10_000 });
  await expect(card(lea), 'the partner keeps it').toBeVisible();
  await expect(paused(peter), 'no connection paused any more').toHaveCount(0);
  await screenshot(peter, 'job50-web-access-unlocked-de-390');
  expect(await siri(shortcut, 'Milch')).toEqual({ status: 200, speech: 'Hinzugefügt: Milch.' });
  expect(await alexaSay(alexa.access_token, 'Butter')).toBe('Ich habe Butter auf die Snacklist gesetzt.');
  expect((await toolText(mcp, 'add_items', { items: [{ name: 'Kaffee' }] })).isError).toBe(false);
  expect(await openNames(peterEmail)).toEqual(['Brot', 'Eier', 'Milch', 'Butter', 'Kaffee']);

  // The grant ends: locked again, nothing deleted or disconnected.
  expect(await promote(peterId, false)).toBe('removed');
  await expect(card(peter), 'locked again, live').toBeVisible({ timeout: 10_000 });
  expect(await siri(shortcut, 'Quark'), 'lapsed: Siri stays open')
    .toEqual({ status: 200, speech: 'Hinzugefügt: Quark.' });
  expect(await alexaSay(alexa.access_token, 'Käse'), 'lapsed: Alexa stays open').toBe('Ich habe Käse auf die Snacklist gesetzt.');
  expect((await toolText(mcp, 'list_items')).isError).toBe(true);
  expect(await openNames(peterEmail), 'the list stays')
    .toEqual(['Brot', 'Eier', 'Milch', 'Butter', 'Kaffee', 'Quark', 'Käse']);
  const { data: tokens } = await (await apiAs(peterEmail)).from('personal_access_tokens').select('name, revoked_at');
  expect(tokens, 'no token revoked').toEqual([{ name: 'Kurzbefehl', revoked_at: null }]);
  await expect(tile(peter, 'Kurzbefehl'), 'the Shortcut token stays, paused')
    .toHaveAccessibleName(/Pausiert: braucht Snacklist Premium$/, { timeout: 10_000 });
  await expect(tile(peter, 'Amazon Alexa'), 'the Alexa link stays, never paused')
    .not.toHaveAccessibleName(/Pausiert: braucht Snacklist Premium$/);
  await screenshot(peter, 'job50-web-access-paused-de-390');

  // Granted again: open again, still the same credentials.
  expect(await promote(peterId)).toBe('granted');
  await expect(card(peter)).toHaveCount(0, { timeout: 10_000 });
  expect((await toolText(mcp, 'add_items', { items: [{ name: 'Senf' }] })).isError).toBe(false);
  await peter.getByRole('tab', { name: 'Liste' }).click();
  await expect(itemRow(peter, 'Senf')).toBeVisible();
  await mcp.close();
});

test("a tester's own grant works with the lock on, a household grant alone does not; a beta account without "
  + 'a grant is locked until the Lead grants it', async ({ browser }) => {
  const tessEmail = newEmail('lock-tess');
  const betaEmail = newEmail('lock-beta');
  const tess = await newPage(browser);
  await signUp(tess, tessEmail);
  await signUpWithHousehold(await newPage(browser), betaEmail);
  const { error: created } = await (await apiAs(tessEmail)).rpc('create_household', { p_name: 'Tess' });
  expect(created).toBeNull();
  // A tester's grant is a RevenueCat promotional grant for the user's own customer; the purchases
  // function stores it like this (promotional_premium_sync_user, docs/PURCHASES.md "Testers"). A
  // household's grant opens nothing (job 419).
  expect(await adminClient().rpc('promotional_premium_sync',
    { p_household: await householdOf(tessEmail), p_active: true, p_expires_at: null }).then((r) => r.error)).toBeNull();
  const tessMcp0 = await connectWithToken(await pat(tessEmail, 'Zweiter'));
  expect((await toolText(tessMcp0, 'list_items')).isError, 'a household grant alone opens nothing').toBe(true);
  await tessMcp0.close();
  expect(await promote(await userOf(tessEmail))).toBe('granted');

  const tessMcp = await connectWithToken(await pat(tessEmail, 'Kurzbefehl'));
  expect((await toolText(tessMcp, 'list_items')).isError).toBe(false);
  await tessMcp.close();
  const beta = await connectWithToken(await pat(betaEmail, 'Kurzbefehl'));
  expect(await toolText(beta, 'list_items')).toEqual({ isError: true, text: mcpPremium });

  // The cut-over: the Lead grants the beta tester's account at RevenueCat
  // (scripts/iap/promotional.ts grant --user); it unlocks at once and the same token works.
  expect(await promote(await userOf(betaEmail))).toBe('granted');
  expect((await toolText(beta, 'list_items')).isError).toBe(false);
  await beta.close();
  await tess.goto('/');
  await openMore(tess, 'Zugänge');
  await expect(tile(tess, 'Kurzbefehl')).toBeVisible();
  await expect(card(tess)).toHaveCount(0);
  await expect(paused(tess)).toHaveCount(0);
});

test('English settings, locked', async ({ browser }) => {
  const email = newEmail('lock-en');
  const page = await newPage(browser);
  await signUpWithHousehold(page, email);
  await pat(email, 'Shortcut');
  await page.goto('/more/settings/language');
  await page.getByRole('radio', { name: 'English', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Language' })).toBeVisible();
  await page.goto('/more/access');
  await expect(page.getByRole('heading', { name: 'Part of Snacklist Premium' })).toBeVisible();
  await expect(tile(page, 'Shortcut')).toHaveAccessibleName(/Paused: needs Snacklist Premium$/);
  await screenshot(page, 'job50-web-access-locked-en-390');
});
