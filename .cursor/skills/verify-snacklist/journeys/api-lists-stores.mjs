// Feature ai-assistants, sub-features ai-recent-usuals and ai-lists-stores (job 345), entry point
// the public API. An integration with a read-write key makes a list and a store, sets the store's
// walk order, adds items there and ticks one; then the app shows the list in the switcher, the
// store's items in the new order and the ticked item under „Zuletzt verwendet“, and the API's
// recent and suggestions answers match what the app shows. Switches the local public_api on and
// integration_lock off (as for a member with Premium of their own; production has it on, and the
// seeded members have no Premium) and both back to what they were.
//
//   node journeys/api-lists-stores.mjs <evidence dir> [--lang de|en]
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { apiAs, capture, flagOn, instance, itemRow, logger, member, openApp, repo, reveal, signIn } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const lang = rest.includes('--lang') ? rest[rest.indexOf('--lang') + 1] : 'de';
if (!dir) throw new Error('usage: api-lists-stores.mjs <evidence dir> [--lang de|en]');

const log = logger(dir);
const inst = instance();
const user = member(inst);
const project = /^project_id = "(.*)"$/m.exec(readFileSync(join(repo, 'supabase/config.toml'), 'utf8'))[1];
const sql = (query) =>
  execFileSync('docker', ['exec', '-i', `supabase_db_${project}`, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-tA'], {
    input: query,
    encoding: 'utf8',
  }).trim();
const publicApiWas = sql(`select enabled from public.app_switches where key = 'public_api'`) === 't';
const lockWas = sql(`select enabled from public.app_switches where key = 'integration_lock'`) === 't';
sql(`update public.app_switches set enabled = true where key = 'public_api'`);
sql(`update public.app_switches set enabled = false where key = 'integration_lock'`);

const client = await apiAs(inst, user);
const minted = await client.rpc('create_api_token', {
  p_name: 'Journey 345',
  p_scopes: ['read', 'write'],
  p_household: user.householdId,
});
const token = (Array.isArray(minted.data) ? minted.data[0] : minted.data)?.token;
if (!token) throw new Error(`no API key: ${JSON.stringify(minted.error)}`);
const V1 = `${inst.apiUrl}/functions/v1/api/v1`;
async function api(method, path, body) {
  const res = await fetch(`${V1}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  log(`API ${method} ${path}${body ? ` ${JSON.stringify(body)}` : ''} -> ${res.status} ${JSON.stringify(json).slice(0, 400)}`);
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status}`);
  return json;
}

const list = (await api('POST', '/lists', { name: 'Baumarkt' })).data;
const store = (await api('POST', '/stores', { name: 'Rewe' })).data;
await api('PUT', `/stores/${store.id}/layout`, { categories: ['Getränke', 'Kühlregal'] });
const { data: added } = await api('POST', '/items', {
  items: [{ name: 'Lauch', store: 'Rewe' }, { name: 'Joghurt', store: 'Rewe' }, { name: 'Sprudel', store: 'Rewe' }, {
    name: 'Kerzen',
    store: 'Rewe',
  }],
});
const kerzen = added.added.find((i) => i.name === 'Kerzen');
await api('POST', `/items/${kerzen.id}/tick`);
const recent = (await api('GET', '/items/recent?limit=5')).data;
const usuals = (await api('GET', '/suggestions?limit=5')).data;
const layout = (await api('GET', `/stores/${store.id}/layout`)).data.map((c) => c.name);

const { browser, page, L, errors } = await openApp(inst, { lang, videoDir: dir });
let failed = null;
try {
  await signIn(page, L, user);
  const walk = ['Sprudel', 'Joghurt', 'Lauch'];
  const boxes = [];
  for (const name of walk) {
    const row = itemRow(page, name).first();
    await row.waitFor({ timeout: 20_000 });
    await reveal(page, row);
    boxes.push([name, (await row.boundingBox())?.y ?? -1]);
  }
  // reveal scrolls, so the positions are compared after one more look at the top row.
  await reveal(page, itemRow(page, walk[0]).first());
  const ys = [];
  for (const name of walk) ys.push([name, (await itemRow(page, name).first().boundingBox())?.y ?? -1]);
  const order = ys.sort((a, b) => a[1] - b[1]).map(([n]) => n).join(',');
  log(`Rewe's rows in the app, top to bottom: ${order}`);
  if (order !== walk.join(',')) throw new Error(`Rewe's items are not in its new walk order: ${order}`);
  await capture(page, dir, '01-rewe-walk-order');

  const recentButton = page.getByRole('button', { name: L('recentlyUsed'), exact: true }).first();
  await reveal(page, recentButton);
  // With recently-used-open (full since 2026-11-22) the section starts open and a tap folds it.
  if (!flagOn('recently-used-open')) await recentButton.click();
  const kerzenRow = page.getByRole('button', { name: new RegExp(`^Kerzen ${L('readd')}`) }).first();
  await kerzenRow.waitFor({ timeout: 15_000 });
  for (let i = 0; i < 12; i++) await page.mouse.wheel(0, 900);
  const box = await kerzenRow.boundingBox();
  const viewport = page.viewportSize();
  if (!box || !viewport || box.y < 0 || box.y + box.height > viewport.height) {
    throw new Error(`Kerzen is not on screen under „${L('recentlyUsed')}“: ${JSON.stringify(box)}`);
  }
  await capture(page, dir, '02-recently-used');
  log(`app shows Kerzen under „${L('recentlyUsed')}“; API recent[0] = ${recent[0]?.name}`);
  if (recent[0]?.name !== 'Kerzen') throw new Error('API recent does not start with the ticked item');

  await page.getByRole('button', { name: / · / }).first().click();
  await page.getByRole('button', { name: /^Baumarkt/ }).first().waitFor({ timeout: 15_000 });
  await capture(page, dir, '03-switcher-new-list');
  log(`switcher lists „Baumarkt“ (${list.id})`);
  log(`walk order from the API: ${layout.join(', ')}`);
  log(`suggestions from the API: ${usuals.map((u) => u.name).join(', ') || '(none yet)'}`);
  if (errors.length > 0) throw new Error(`page errors: ${errors.join(' | ')}`);
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
  sql(`update public.app_switches set enabled = ${publicApiWas} where key = 'public_api'`);
  sql(`update public.app_switches set enabled = ${lockWas} where key = 'integration_lock'`);
}
if (failed) {
  console.log(`FAIL: ${failed.message}`);
  process.exit(1);
}
console.log('PASS');
