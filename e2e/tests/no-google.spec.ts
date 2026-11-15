import { expect, test } from './fixtures';
import {
  addField,
  addSheet,
  answerConsent,
  expectOnlyNoConsentFlags,
  fakeCollector,
  itemRow,
  must,
  newEmail,
  password,
  screenshot,
  supabaseUrl,
  typeInto,
  openEmailSignIn,
} from './helpers';
import { householdWithItems } from './web-build';

// Job 33c (legal review H-02): the web app sends nothing to Google. The engine (CanvasKit or
// skwasm) and every font, the fallback fonts for emoji and non-Latin scripts included, come
// from our own origin. Runs in Chromium, Firefox and WebKit (wasm and skwasm in each since job 201), under
// the production Content-Security-Policy (e2e/serve.mjs --csp).

const items = ['🍎 Äpfel', 'Brötchen für Grüße', '牛奶', 'خبز', 'Молоко', '🧀 Käse'];
const posthog = 'posthog.invalid';
const google = /(^|\.)(gstatic\.com|googleapis\.com|google\.com|google\.[a-z.]+)$/;

test('no request leaves for Google: login, sign-in, a list in many scripts, the add sheet', async ({ page, context, browserName, baseURL }) => {
  // A CI runner's WebKit draws in software, a frame every 200 ms or so: each step takes a second.
  test.slow(browserName === 'webkit');
  const email = newEmail('no-google');
  await householdWithItems(email, items);
  const collector = await fakeCollector(context);

  const requests: URL[] = [];
  // WebKit also reports data: and blob: URLs, which never reach the network.
  page.on('request', (request) => {
    const url = new URL(request.url());
    if (/^(https?|wss?):$/.test(url.protocol)) requests.push(url);
  });
  await page.addInitScript(() => {
    const seen: string[] = [];
    (window as unknown as { cspViolations: string[] }).cspViolations = seen;
    document.addEventListener('securitypolicyviolation', (e) => seen.push(`${e.violatedDirective} ${e.blockedURI}`));
  });

  await page.goto('/login');
  await openEmailSignIn(page);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await screenshot(page, `33c-${browserName}-login`);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Nutzungsdaten', exact: true })).toBeVisible();
  expect(requests.filter((url) => url.host === posthog && url.pathname !== '/flags/').map(String), 'PostHog before consent')
    .toEqual([]);
  expectOnlyNoConsentFlags(collector, 'PostHog before consent');
  await answerConsent(page, 'accept');

  for (const name of items) await expect(itemRow(page, name)).toBeVisible({ timeout: 30_000 });
  const fonts = () => requests.filter((url) => url.pathname.startsWith('/fonts/')).map((url) => url.pathname);
  // The engine fetched a fallback font for each script Roboto lacks, from us.
  for (const font of [/^\/fonts\/notocoloremoji\//, /^\/fonts\/notosans(sc|tc|hk|jp|kr)\//, /^\/fonts\/notosansarabic\//]) {
    await expect.poll(() => fonts().some((path) => font.test(path)), { message: `fetched ${font}` }).toBe(true);
  }
  await screenshot(page, `33c-${browserName}-list`);

  await addField(page).click();
  await expect(addSheet(page)).toBeVisible();
  await typeInto(addField(page), '🍐 Birne 梨');
  await expect(addSheet(page).getByRole('button', { name: /, Wie getippt(,|$)/ })).toBeVisible();
  await screenshot(page, `33c-${browserName}-add-sheet`);

  const own = new URL(must(baseURL, 'baseURL')).host;
  const allowed = new Set([own, new URL(supabaseUrl).host, posthog]);
  const hosts = [...new Set(requests.map((url) => url.host))].sort();
  console.log(`HOSTS ${browserName} ${hosts.map((h) => `${h}=${requests.filter((url) => url.host === h).length}`).join(' ')}`);
  expect(requests.filter((url) => google.test(url.hostname)).map(String), 'requests to Google').toEqual([]);
  expect(hosts.filter((h) => !allowed.has(h)), 'hosts besides ours, Supabase and PostHog').toEqual([]);
  expect(await page.evaluate(() => (window as unknown as { cspViolations: string[] }).cspViolations), 'CSP violations').toEqual([]);
});
