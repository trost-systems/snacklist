// Job 19, AC11 proof, run by hand (never in CI): a release web build with the real PostHog key
// raises the internal-only test error and sends it to PostHog EU. Supabase is faked by routes, so
// no account is needed. features/analytics.md has the steps:
//
//   flutter build web --release --source-maps -o /tmp/proof \
//     --dart-define=SUPABASE_URL=https://fake-supabase.invalid \
//     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_fakeproof \
//     --dart-define=POSTHOG_PROJECT_API_KEY="$POSTHOG_PROJECT_API_KEY" --dart-define=POSTHOG_HOST="$POSTHOG_HOST"
//   node serve.mjs /tmp/proof 56180 &
//   flock /tmp/fg-e2e.lock node analytics-proof.mjs http://127.0.0.1:56180 <out-dir>
//
// Writes the consent and More screenshots and what went to PostHog (key redacted) to <out-dir>.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import { Buffer } from 'node:buffer';
import process from 'node:process';

const [app, out] = process.argv.slice(2);
const SB = 'https://fake-supabase.invalid';
const user = { id: '5f0c2a9e-0000-4000-8000-00000000a011', email: 'proof-ac11@fg.test', aud: 'authenticated', role: 'authenticated', 'app_metadata': { provider: 'email' }, 'user_metadata': {}, 'created_at': '2026-10-29T19:00:00Z' };
const household = { id: '5f0c2a9e-0000-4000-8000-00000000b011', name: 'Proof' };
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const jwt = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: user.id, exp: now + 3600, iat: now, role: 'authenticated', aud: 'authenticated', email: user.email, session_id: 's1' })}.c2ln`;
const session = { 'access_token': jwt, 'token_type': 'bearer', 'expires_in': 3600, 'expires_at': now + 3600, 'refresh_token': 'refresh', user };
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 480, height: 900 }, locale: 'de-DE', timezoneId: 'Europe/Berlin' });
const sent = [];
await context.route(`${SB}/**`, (route) => {
  const req = route.request();
  const url = new URL(req.url());
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'content-type': 'application/json' };
  if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors });
  let body = '[]';
  if (url.pathname === '/auth/v1/token') body = JSON.stringify(session);
  else if (url.pathname === '/auth/v1/user') body = JSON.stringify(user);
  else if (url.pathname === '/rest/v1/household_members' && (url.searchParams.get('select') || '').includes('households')) body = (req.headers()['accept'] || '').includes('object') ? JSON.stringify({ households: household }) : JSON.stringify([{ households: household }]);
  else if (url.pathname === '/rest/v1/household_members') body = JSON.stringify([{ user_id: user.id, role: 'owner' }]);
  else if (url.pathname === '/rest/v1/profiles') body = JSON.stringify([{ id: user.id, display_name: 'Proof' }]);
  // The proof's user is in the tester group internal, which shows „Testfehler senden“ (job 337).
  else if (url.pathname === '/rest/v1/rpc/my_tester_groups') body = '["internal"]';
  else if (url.pathname.startsWith('/rest/v1/rpc/')) body = '[]';
  return route.fulfill({ status: 200, headers: cors, body });
});
await context.routeWebSocket(/fake-supabase\.invalid/, (ws) => ws.close());
const page = await context.newPage();
page.on('request', (r) => { if (r.url().includes('posthog.com')) sent.push({ method: r.method(), url: r.url(), body: r.postData() }); });
const answers = [];
page.on('response', async (r) => { if (r.url().includes('posthog.com')) answers.push({ url: r.url(), status: r.status(), body: await r.text().catch(() => '') }); });
page.on('requestfailed', (r) => { if (r.url().includes('posthog.com')) answers.push({ url: r.url(), failed: r.failure()?.errorText }); });
// The sign-in itself: signed out, `/` is the guided start's first screen (job 168b).
await page.goto(`${app}/login`);
// Builds with Google or Apple keep the email form behind „Weiter mit E-Mail“.
const withEmail = page.getByRole('button', { name: 'Weiter mit E-Mail' });
await withEmail.or(page.getByRole('textbox', { name: 'E-Mail' })).waitFor();
if (await withEmail.isVisible()) await withEmail.click();
for (const [name, text] of [['E-Mail', user.email], ['Passwort', 'irrelevant-password']]) {
  const field = page.getByRole('textbox', { name });
  for (let i = 0; i < 10; i++) {
    await field.click(); await page.waitForTimeout(300);
    await page.keyboard.press('ControlOrMeta+a'); await page.keyboard.insertText(text); await page.waitForTimeout(300);
    if ((await field.inputValue()) === text) break;
  }
}
await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
await page.getByRole('button', { name: 'Erlauben', exact: true }).waitFor();
await page.screenshot({ path: `${out}/ac11-01-consent.png` });
const beforeConsent = sent.length;
await page.getByRole('button', { name: 'Erlauben', exact: true }).click();
await page.getByRole('tab', { name: 'Mehr', exact: true }).or(page.getByRole('button', { name: 'Mehr Tab ' })).click();
await page.waitForURL(/\/more$/);
await page.mouse.move(240, 400);
for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 600); await page.waitForTimeout(200); }
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/ac11-02a-more-consent-on.png` });
// The faked my_tester_groups says internal: the button shows without a long press (job 337).
await page.getByRole('button', { name: 'Testfehler senden' }).waitFor();
await page.screenshot({ path: `${out}/ac11-02-internal-install.png` });
await page.getByRole('button', { name: 'Testfehler senden' }).click();
for (let i = 0; i < 40 && !sent.some((s) => (s.body || '').includes('$exception')); i++) await page.waitForTimeout(500);
await page.waitForTimeout(2000);
const redact = (s) => (s || '').replace(/phc_[A-Za-z0-9_-]+/g, '<redacted>');
fs.writeFileSync(`${out}/ac11-sent.json`, JSON.stringify({ requestsBeforeConsent: beforeConsent, sent: sent.map((s) => ({ ...s, body: s.body ? JSON.parse(redact(s.body)) : null })), answers }, null, 2));
console.log('before consent:', beforeConsent, 'requests:', sent.map((s) => `${s.method} ${s.url}`).join(' | '));
console.log('answers:', JSON.stringify(answers));
await browser.close();
