// Tester groups (job 337), entry point More. A customer account (a non-test e-mail domain) on the
// release web build: a long press on the version line unlocks nothing. The lead's SQL puts the
// user into `internal` and `beta-de`; after a reload More shows „Testfehler senden“, and after the
// analytics yes the flag request carries `is_internal: true` and `tester_groups: "beta-de,internal"`
// and no other personal property. The user's own RPC lists the groups; inserting one as the user
// is refused. Restores the member's e-mail and drops the rows at the end.
//
//   node journeys/tester-groups.mjs <evidence dir>
import { execFileSync } from 'node:child_process';
import process from 'node:process';
import { apiAs, capture, instance, logger, member, openApp, openTab, reveal, signIn } from '../helpers/lib.mjs';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('usage: tester-groups.mjs <evidence dir>');

const log = logger(dir);
const inst = instance();
const seeded = member(inst);
const sql = (query) =>
  execFileSync('docker', ['exec', `supabase_db_${inst.projectId}`, 'psql', '-U', 'postgres', '-tAc', query], { encoding: 'utf8' }).trim();
const customerEmail = `kunde-${seeded.id.slice(0, 8)}@brandt-mail.de`;
const user = { ...seeded, email: customerEmail };

sql(`update auth.users set email = '${customerEmail}' where id = '${seeded.id}'`);
sql(`delete from public.tester_groups where user_id = '${seeded.id}'`);
const { browser, context, page, L, errors } = await openApp(inst, { videoDir: dir });
const flagBodies = [];
await context.route('https://posthog.invalid/**', async (route) => {
  const request = route.request();
  if (new URL(request.url()).pathname.startsWith('/flags')) {
    flagBodies.push(request.postData() ?? '');
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ flags: {} }) });
    return;
  }
  await route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
});

const testError = page.getByRole('button', { name: L('sendTestError') });
async function moreBottom() {
  await openTab(page, L, 'tabMore');
  await page.getByRole('button', { name: L('analyticsSection'), exact: true }).waitFor();
  await page.waitForTimeout(1_000);
  const version = page.getByText(/^Version /);
  await reveal(page, version);
  return version;
}

let failed = null;
try {
  await signIn(page, L, user);
  const version = await moreBottom();
  const box = await version.boundingBox();
  if (!box) throw new Error('no version line');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(1_200);
  await page.mouse.up();
  await page.waitForTimeout(800);
  await capture(page, dir, '01-customer-long-press');
  if (await testError.count()) throw new Error('a long press unlocked „Testfehler senden“');
  log('customer, long press on the version: no „Testfehler senden“, no „Interne Installation“');

  const api = await apiAs(inst, user);
  const insert = await api.from('tester_groups').insert({ user_id: seeded.id, group_name: 'internal' });
  log(`insert as the user: ${JSON.stringify(insert.error?.code ?? 'accepted')}`);
  if (!insert.error) throw new Error('the user could add themselves to a group');

  sql(`insert into public.tester_groups (user_id, group_name) values ('${seeded.id}', 'internal'), ('${seeded.id}', 'beta-de')`);
  const mine = await api.rpc('my_tester_groups');
  log(`my_tester_groups as the user: ${JSON.stringify(mine.data)}`);
  if (JSON.stringify(mine.data) !== '["beta-de","internal"]') throw new Error('my_tester_groups is not the sorted groups');

  await page.goto('/');
  await page.getByRole('textbox', { name: L('addFieldHint') }).waitFor({ timeout: 30_000 });
  await moreBottom();
  await reveal(page, testError);
  await capture(page, dir, '02-internal-group-more');
  log('in the group internal after a reload: „Testfehler senden“ shows below the version');

  const shared = flagBodies.map((b) => JSON.parse(b)).filter((b) => b.distinct_id === 'no-consent');
  log(`shared requests before the yes (${shared.length}): ${JSON.stringify(shared.map((b) => b.person_properties))}`);
  if (!shared.length || shared.some((b) => Object.keys(b.person_properties).sort().join() !== 'app_version,platform')) {
    throw new Error('a shared request without consent carried more than platform and app_version');
  }
  await page.getByRole('button', { name: L('analyticsSection'), exact: true }).click();
  flagBodies.length = 0;
  await page.getByRole('switch').first().click();
  await page.getByRole('button', { name: L('analyticsAccept'), exact: true }).click();
  const targeted = () => flagBodies.map((b) => JSON.parse(b)).find((b) => b.person_properties?.tester_groups);
  for (const end = Date.now() + 20_000; !targeted() && Date.now() < end; ) await page.waitForTimeout(250);
  const body = targeted();
  log(`flag request after the yes: ${JSON.stringify({ ...body, token: '<project key>' })}`);
  if (body?.person_properties?.tester_groups !== 'beta-de,internal' || body.person_properties.is_internal !== true) {
    throw new Error('the flag request lacks is_internal or tester_groups');
  }
  await capture(page, dir, '03-usage-data-on');
  if (errors.length) throw new Error(`page errors: ${errors.join(' | ')}`);
  log('PASS');
} catch (e) {
  failed = e;
  await capture(page, dir, '99-failure').catch(() => {});
  log(`FAIL: ${e.message}`);
} finally {
  await browser.close();
  sql(`delete from public.tester_groups where user_id = '${seeded.id}'`);
  sql(`update auth.users set email = '${seeded.email}' where id = '${seeded.id}'`);
}
if (failed) process.exit(1);
