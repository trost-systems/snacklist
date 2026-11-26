// Feature ai-assistants, sub-features ai-apps and ai-app-details (job 80), entry point Mehr →
// Zugänge. Gives the member a connected app the way an approval leaves it (a client registered over
// DCR, the grant, a session and the consent page's device label, written as postgres since a real approval
// needs an MCP client: e2e/tests/mcp.spec.ts drives that), then proves the row names the device
// and the last activity, the keys' hint (the one list of „Zugriffsschlüssel“ users have with
// unified-keys and its server switch on; else the token hint, pointing at the API section when
// public-api is on), and the details sheet in plain words. With the server switch integration_lock on
// (production since 2026-11-24, so a plain launch) and no Premium of the member's own, the card „Teil
// von Snacklist Premium“ and the row's „Pausiert: braucht Snacklist Premium“; with it off, neither.
//
//   node journeys/ai-assistants.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, capture, flagOn, instance, logger, member, openApp, openTab, repo, reveal, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: ai-assistants.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const project = /^project_id = "(.*)"$/m.exec(readFileSync(join(repo, 'supabase/config.toml'), 'utf8'))[1];
const sql = (query) =>
  execFileSync('docker', ['exec', '-i', `supabase_db_${project}`, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-tA'], {
    input: query,
    encoding: 'utf8',
  });
// The client registers itself as an MCP host does (dynamic client registration), so Auth knows it.
const registered = await (await fetch(`${inst.apiUrl}/auth/v1/oauth/clients/register`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ client_name: 'Claude', redirect_uris: ['https://claude.ai/api/mcp/auth_callback'] }),
})).json();
const client = registered.client_id;
if (!client) throw new Error(`client registration failed: ${JSON.stringify(registered)}`);
sql(`
  insert into auth.oauth_consents (id, user_id, client_id, scopes, granted_at)
  values (gen_random_uuid(), '${user.id}', '${client}', 'openid email offline_access', now() - interval '3 days');
  insert into auth.sessions (id, user_id, oauth_client_id, created_at, updated_at)
  values (gen_random_uuid(), '${user.id}', '${client}', now() - interval '3 days', now() - interval '2 hours');
  insert into public.oauth_app_devices (user_id, client_id, device) values ('${user.id}', '${client}', 'Chrome · macOS');
`);
const api = await apiAs(inst, user);
const details = (await api.rpc('connected_app_details')).data;
log(`connected_app_details as ${user.handle}: ${JSON.stringify(details)}`);

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${L('accessTitle')}`) }).first().click();
  // The screen shows the token sections until the switch's answer arrives, so wait for the hint
  // the switch picks, and make sure the other one is gone.
  const unified = flagOn('unified-keys') && (await api.rpc('unified_keys')).data === true;
  const hint = unified ? 'accessKeysUnifiedHint' : flagOn('public-api') ? 'accessTokensHintWithApi' : 'accessTokensHint';
  await page.getByText(L(hint)).waitFor({ timeout: 15_000 });
  const other = unified ? (flagOn('public-api') ? 'accessTokensHintWithApi' : 'accessTokensHint') : 'accessKeysUnifiedHint';
  if ((await page.getByText(L(other)).count()) > 0) throw new Error(`„${L(other)}“ still shows next to „${L(hint)}“`);
  log(`token hint shown (${hint}): „${L(hint)}“`);
  const row = page.getByRole('button', { name: /^Claude Chrome · macOS · / });
  await row.waitFor({ timeout: 15_000 });
  log(`row: „${await row.getAttribute('aria-label') ?? await row.textContent()}“`);
  if ((await page.getByText(L('scopeOpenid')).count()) > 0) throw new Error('the scopes are still listed on the row');
  const locked = sql(`select enabled from public.app_switches where key = 'integration_lock'`).trim() === 't';
  const card = page.getByRole('heading', { name: L('integrationPremiumTitle') });
  const paused = (await row.getAttribute('aria-label') ?? '').endsWith(L('integrationPaused'));
  if (locked) {
    await card.waitFor({ timeout: 10_000 });
    if (!paused) throw new Error(`lock on: the row does not end with „${L('integrationPaused')}“`);
    // The card is one semantics node: its text is in the group's aria-label.
    const footer = page.locator(`[aria-label*="${L('premiumWeb').slice(0, 40)}"]`);
    log(`lock on, no Premium of her own: „${L('integrationPremiumTitle')}“ card, row „${L('integrationPaused')}“; web footer „${L('premiumWeb')}“ shown: ${(await footer.count()) > 0}`);
  } else {
    if ((await card.count()) > 0 || paused) throw new Error('lock off: the Premium card or the paused line shows');
    log('lock off: no Premium card, the row not paused');
  }
  // The row's last line („Pausiert …“ when locked) clear of the tab bar for the capture.
  await reveal(page, row);
  await capture(page, dir, '01-access-connected-app');

  await row.click();
  await page.getByText(L('appDevice', { device: 'Chrome · macOS' })).waitFor({ timeout: 10_000 });
  await page.getByText(L('appCanEmail')).waitFor();
  await page.getByText(L('appCanStay')).waitFor();
  log('details sheet: device, what it may do, disconnect button');
  await capture(page, dir, '02-app-details');
  await page.keyboard.press('Escape');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  sql(`delete from auth.oauth_consents where client_id = '${client}'; delete from auth.sessions where oauth_client_id = '${client}'; delete from auth.oauth_clients where id = '${client}';`);
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log(`PASS ai-assistants (evidence: ${dir})`);
