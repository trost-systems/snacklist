// Feature ai-assistants, sub-feature ai-unified-keys (job 397, AU1): one personal key for MCP and
// the API. Plain launch (the flag is full since 2026-11-23). It turns integration_lock off for the
// run (what a member with Premium of their own gets; the seeded members have none). With the
// server switch app_switches.unified_keys off, Zugänge keeps its two sections; on, one list
// „Zugriffsschlüssel“ shows an MCP token made before (read and write) next to a new read-only key.
// Over HTTP: the read-only key reads on MCP and gets a tool error saying it can only read on a
// write; the old MCP token reads and writes on the API. Leaves the switch as it found it.
//
//   node journeys/unified-keys.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, capture, flagOn, instance, logger, member, openApp, openTab, repo, reveal, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: unified-keys.mjs <evidence dir> [--lang de|en]');
if (!flagOn('unified-keys')) throw new Error('launch with VH_DEFINES="FLAGS_ON=unified-keys"');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const project = /^project_id = "(.*)"$/m.exec(readFileSync(join(repo, 'supabase/config.toml'), 'utf8'))[1];
const sql = (query) =>
  execFileSync('docker', ['exec', '-i', `supabase_db_${project}`, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-tA'], {
    input: query,
    encoding: 'utf8',
  }).trim();
const switches = sql(`select string_agg(key || '=' || enabled, ',') from public.app_switches where key in ('unified_keys', 'public_api', 'integration_lock')`);
const setSwitch = (key, on) => sql(`update public.app_switches set enabled = ${on} where key = '${key}'`);

async function mcp(token, name, args) {
  const res = await fetch(`${inst.apiUrl}/functions/v1/mcp`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
      'mcp-protocol-version': '2025-11-25',
      'accept-language': lang,
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }),
  });
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  return { status: res.status, body: JSON.parse(data ? data.slice(6) : text) };
}

// A ListTile merges its title and subtitle into one label on web.
const shown = (page, re) => page.getByLabel(re).or(page.getByText(re)).first();

const apiCall = async (token, method, body) => {
  const res = await fetch(`${inst.apiUrl}/functions/v1/api/v1/items`, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json().catch(() => null) };
};

setSwitch('public_api', true);
setSwitch('integration_lock', false);
setSwitch('unified_keys', false);
const api = await apiAs(inst, user);
const made = await api.rpc('create_personal_access_token', { p_name: 'Claude', p_household: user.householdId });
if (made.error) throw new Error(`create_personal_access_token: ${made.error.message}`);
const oldToken = made.data[0].token;
const oldId = made.data[0].id;
log('an MCP token „Claude“ made as an older app build does (create_personal_access_token)');

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
let newId = null;
const openAccess = async () => {
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: new RegExp(`^${L('accessTitle')}`) }).first().click();
};
try {
  await signIn(page, L, user);
  await openAccess();
  await page.getByRole('button', { name: L('createToken'), exact: true }).waitFor({ timeout: 15_000 });
  if ((await page.getByRole('button', { name: L('createAccessKey'), exact: true }).count()) > 0) {
    throw new Error('switch off: the unified section shows');
  }
  if ((await shown(page, new RegExp(`· ${L('apiScopeReadWrite')} ·`)).count()) > 0) {
    throw new Error('switch off: the MCP token shows a scope label');
  }
  log(`switch off, flag on: the two sections as before („${L('createToken')}“, no „${L('createAccessKey')}“)`);
  await capture(page, dir, '01-switch-off-two-sections');

  setSwitch('unified_keys', true);
  await page.reload();
  await openAccess();
  const create = page.getByRole('button', { name: L('createAccessKey'), exact: true });
  await create.waitFor({ timeout: 15_000 });
  if ((await page.getByRole('button', { name: L('createToken'), exact: true }).count()) > 0) {
    throw new Error('switch on: the old token button still shows');
  }
  await page.getByText(L('accessKeysUnifiedHint')).waitFor();
  await shown(page, new RegExp(`· ${L('apiScopeReadWrite')} ·`)).waitFor();
  log(`switch on: one section, hint „${L('accessKeysUnifiedHint')}“, the old token listed as „${L('apiScopeReadWrite')}“`);
  await capture(page, dir, '02-switch-on-one-list');

  await reveal(page, create);
  await create.click();
  await typeInto(page.getByRole('textbox', { name: L('tokenName') }), 'Home Assistant');
  await page.getByRole('radio', { name: new RegExp(`^${L('apiScopeRead')}`) }).waitFor();
  await capture(page, dir, '03-create-dialog');
  await page.getByRole('button', { name: L('create'), exact: true }).click();
  await page.getByText(L('accessKeyCreated')).waitFor({ timeout: 15_000 });
  const secret = (await page.getByText(/^fgp_[A-Za-z0-9_-]{43}$/).textContent()).trim();
  log(`„${L('accessKeyCreated')}“ shows the key once`);
  await page.getByRole('button', { name: L('done') }).click();
  await page.getByText(/^fgp_/).waitFor({ state: 'detached' });
  await shown(page, new RegExp(`· ${L('apiScopeRead')} ·`)).waitFor();
  await capture(page, dir, '04-two-keys');
  const rows = await api.from('personal_access_tokens').select('id, name, kind, scopes').is('revoked_at', null);
  log(`rows: ${JSON.stringify(rows.data.map(({ name, kind, scopes }) => ({ name, kind, scopes })))}`);
  newId = rows.data.find((r) => r.name === 'Home Assistant')?.id ?? null;

  const read = await mcp(secret, 'list_items', {});
  if (read.body.result?.isError) throw new Error(`read-only key on MCP list_items: ${JSON.stringify(read.body)}`);
  log(`MCP list_items with the read-only key: HTTP ${read.status}, a result`);
  const write = await mcp(secret, 'add_items', { items: [{ name: 'Kefir' }] });
  const refusal = write.body.result;
  if (!refusal?.isError || refusal.structuredContent?.error !== 'insufficient_scope') {
    throw new Error(`read-only key on MCP add_items: ${JSON.stringify(write.body)}`);
  }
  log(`MCP add_items with the read-only key: HTTP ${write.status}, tool error „${refusal.content[0].text}“, ${JSON.stringify(refusal.structuredContent)}`);
  const oldRead = await apiCall(oldToken, 'GET');
  const oldWrite = await apiCall(oldToken, 'POST', { items: [{ name: 'Kefir' }] });
  const newWrite = await apiCall(secret, 'POST', { items: [{ name: 'Kefir' }] });
  log(`API with the old MCP token: GET ${oldRead.status}, POST ${oldWrite.status}; with the read-only key: POST ${newWrite.status} ${newWrite.body?.error?.code}`);
  if (oldRead.status !== 200 || oldWrite.status !== 201 || newWrite.status !== 403) throw new Error('API answers differ');

  const revoke = page.getByRole('button', { name: L('revokeToken', { name: 'Home Assistant' }) });
  await reveal(page, revoke);
  await revoke.click();
  await page.getByText(L('revokeAccessKeyTitle')).waitFor();
  await capture(page, dir, '05-revoke');
  await page.getByRole('button', { name: L('revoke'), exact: true }).click();
  await page.getByRole('button', { name: L('revokeToken', { name: 'Home Assistant' }) }).waitFor({ state: 'detached' });
  const after = await mcp(secret, 'list_items', {});
  log(`after the revoke the key gets HTTP ${after.status} on MCP`);
  if (after.status !== 401) throw new Error('a revoked key still works');
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await page.context().close();
  await browser.close();
  sql(`delete from public.items where name = 'Kefir' and household_id = '${user.householdId}'`);
  sql(`update public.personal_access_tokens set revoked_at = now() where id in ('${oldId}'${newId ? `, '${newId}'` : ''}) and revoked_at is null`);
  for (const pair of switches.split(',')) {
    const [key, on] = pair.split('=');
    setSwitch(key, on === 'true');
  }
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
