// Job 169b, wave 2 (docs/households/W2.md "Join page"): /join/<code> serves the static page in
// app/web/join, which asks preview_invite_public and offers the browser join. The RPC is faked
// per test, so this spec runs against the served build alone; the CSP is the one serve.mjs takes
// from vercel.json, as the deployed page gets it.
import { readFileSync } from 'node:fs';
import { type Browser, expect, type Page, test } from './fixtures';
import { screenshot } from './helpers';

const code = 'ABCD2345';
const rpc = '**/rest/v1/rpc/preview_invite_public';

const okAnswer = {
  status: 'ok',
  household: 'Familie Brandt',
  inviter: 'Peter',
  members: 3,
  'open_items': 12,
  premium: true,
  'invite_kind': 'person',
};

interface Watched {
  readonly page: Page;
  readonly cspErrors: string[];
  readonly calls: unknown[];
}

/** A page whose RPC answers `answer` (or fails the request), recording calls and CSP errors. */
async function joinPage(
  page: Page,
  answer: Record<string, unknown> | 'network-error',
  path = `/join/${code}`,
): Promise<Watched> {
  const cspErrors: string[] = [];
  const calls: unknown[] = [];
  page.on('console', (message) => {
    if (/Content Security Policy|Content-Security-Policy/i.test(message.text())) cspErrors.push(message.text());
  });
  await page.route(rpc, async (route) => {
    calls.push({ headers: route.request().headers(), body: route.request().postDataJSON() });
    if (answer === 'network-error') await route.abort('internetdisconnected');
    else await route.fulfill({ json: answer });
  });
  await page.goto(path);
  return { page, cspErrors, calls };
}

async function englishPage(browser: Browser, baseURL: string | undefined): Promise<Page> {
  const context = await browser.newContext({ locale: 'en-US', baseURL: baseURL ?? '' });
  return context.newPage();
}

test('DE: the invite names inviter, household, members, open items and Premium; the button joins in the browser', async ({ page }) => {
  const { calls, cspErrors } = await joinPage(page, okAnswer);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Peter lädt dich zu „Familie Brandt“ ein');
  await expect(page.locator('html')).toHaveAttribute('lang', 'de');
  await expect(page.getByText('3 Mitglieder · 12 offene Einträge')).toBeVisible();
  await expect(page.getByText('Premium gilt für alle im Haushalt')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Im Browser beitreten' })).toHaveAttribute('href', `/?invite=${code}`);
  await expect(page.getByText('ABCD-2345')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Code kopieren' })).toBeVisible();
  expect(calls).toHaveLength(1);
  expect(calls[0]).toMatchObject({ body: { p_code: code }, headers: { apikey: expect.stringMatching(/^sb_publishable_/) } });
  expect(cspErrors).toEqual([]);
  await page.setViewportSize({ width: 390, height: 844 });
  await screenshot(page, 'join-page-de-light');
});

test('DE: one member, one open item, no Premium', async ({ page }) => {
  await joinPage(page, { ...okAnswer, members: 1, 'open_items': 1, premium: false });
  await expect(page.getByText('1 Mitglied · 1 offener Eintrag')).toBeVisible();
  await expect(page.getByText(/Premium/)).toBeHidden();
});

test('an invite without an inviter name still names the household', async ({ page }) => {
  await joinPage(page, { ...okAnswer, inviter: null });
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Du bist zu „Familie Brandt“ eingeladen');
});

test('EN, dark: the invite in English', async ({ browser, baseURL }) => {
  const page = await englishPage(browser, baseURL);
  await page.emulateMedia({ colorScheme: 'dark' });
  await joinPage(page, okAnswer);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Peter invites you to “Familie Brandt”');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.getByText('3 members · 12 open items')).toBeVisible();
  await expect(page.getByText('Premium covers everyone in the household')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Join in the browser' })).toHaveAttribute('href', `/?invite=${code}`);
  await expect(page.getByRole('button', { name: 'Copy code' })).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await screenshot(page, 'join-page-en-dark');
});

test('a browser in neither language reads English; German further down its list reads German', async ({ browser, baseURL }) => {
  for (const [languages, lang, heading] of [
    [['fr-FR', 'fr'], 'en', 'Peter invites you to “Familie Brandt”'],
    [['fr-FR', 'de-CH'], 'de', 'Peter lädt dich zu „Familie Brandt“ ein'],
  ] as const) {
    const context = await browser.newContext({ locale: languages[0], baseURL: baseURL ?? '' });
    await context.addInitScript((list) => Object.defineProperty(navigator, 'languages', { get: () => list }), [...languages]);
    const page = await context.newPage();
    await joinPage(page, okAnswer);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(heading);
    await expect(page.locator('html')).toHaveAttribute('lang', lang);
    await context.close();
  }
});

test('copy puts the bare code on the clipboard and says so', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await joinPage(page, okAnswer);
  await page.getByRole('button', { name: 'Code kopieren' }).click();
  await expect(page.getByRole('button', { name: 'Kopiert' })).toBeVisible();
  await expect(page.getByRole('status')).toHaveText('Code kopiert');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(code);
});

const failures = [
  {
    answer: { status: 'invalid' },
    de: 'Diese Einladung gilt nicht mehr',
    en: 'This invite no longer works',
    action: 'Code im Browser eingeben',
    showsCode: false,
  },
  {
    answer: { status: 'full' },
    de: 'Diese Einladung ist voll',
    en: 'This invite is full',
    action: 'Code im Browser eingeben',
    showsCode: false,
  },
  {
    answer: { status: 'rate_limited' },
    de: 'Gerade zu viele Aufrufe',
    en: 'Too many requests right now',
    action: 'Im Browser beitreten',
    showsCode: true,
  },
  {
    answer: 'network-error' as const,
    de: 'Einladung nicht geladen',
    en: 'Couldn’t load the invite',
    action: 'Im Browser beitreten',
    showsCode: true,
  },
];

for (const failure of failures) {
  const name = failure.answer === 'network-error' ? 'network error' : failure.answer.status;
  test(`${name}: own text, and the browser still takes the code`, async ({ page, browser, baseURL }) => {
    await joinPage(page, failure.answer);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(failure.de);
    await expect(page.getByRole('link', { name: failure.action })).toHaveAttribute('href', `/?invite=${code}`);
    await expect(page.getByText('ABCD-2345')).toBeVisible({ visible: failure.showsCode });
    await expect(page.getByText(/Mitglied/)).toBeHidden();
    if (name === 'invalid') {
      await page.setViewportSize({ width: 390, height: 844 });
      await screenshot(page, 'join-page-invalid-390');
    }

    const english = await englishPage(browser, baseURL);
    await joinPage(english, failure.answer);
    await expect(english.getByRole('heading', { level: 1 })).toHaveText(failure.en);
  });
}

test('a link whose code cannot be one shows invalid without asking the server', async ({ page }) => {
  const { calls } = await joinPage(page, okAnswer, '/join/not-a-code');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Diese Einladung gilt nicht mehr');
  await expect(page.getByRole('link', { name: 'Code im Browser eingeben' })).toHaveAttribute('href', '/');
  expect(calls).toEqual([]);
});

test('a link that is not valid percent-encoding shows invalid, and the server stays up', async ({ page }) => {
  const { calls } = await joinPage(page, okAnswer, '/join/%E0%A4%A');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Diese Einladung gilt nicht mehr');
  await expect(page.getByRole('link', { name: 'Code im Browser eingeben' })).toHaveAttribute('href', '/');
  expect(calls).toEqual([]);
  expect((await page.request.get('/assets/%E0%A4%A.png')).status(), 'no rewrite takes a malformed file path').toBe(400);
  expect((await page.request.get(`/join/${code}`)).status()).toBe(200);
});

test('a long household name wraps at 390 px instead of scrolling the page sideways', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await joinPage(page, { ...okAnswer, household: 'Kleingartenvereinsgemeinschaft' });
  const heading = page.getByRole('heading', { level: 1 });
  await expect(heading).toHaveText('Peter lädt dich zu „Kleingartenvereinsgemeinschaft“ ein');
  await page.evaluate(async () => { await document.fonts.ready; });
  const root = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  const h1 = await heading.evaluate((element) => ({ scrollWidth: element.scrollWidth, clientWidth: element.clientWidth }));
  expect(root.scrollWidth, 'the document does not scroll sideways').toBeLessThanOrEqual(root.clientWidth);
  expect(h1.scrollWidth, 'the heading does not overflow its box').toBeLessThanOrEqual(h1.clientWidth);
});

test('a lower-case code and a trailing slash land on the same invite', async ({ page }) => {
  const { calls } = await joinPage(page, okAnswer, `/join/${code.toLowerCase()}/`);
  await expect(page).toHaveURL(new RegExp(`/join/${code.toLowerCase()}$`));
  await expect(page.getByRole('link', { name: 'Im Browser beitreten' })).toHaveAttribute('href', `/?invite=${code}`);
  expect(calls).toHaveLength(1);
});

test('no store button and no Smart App Banner while the listings are not public', async ({ page }) => {
  await joinPage(page, okAnswer);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(/Peter/);
  await expect(page.getByRole('link', { name: /App Store|Google Play/ })).toHaveCount(0);
  await expect(page.locator('meta[name="apple-itunes-app"]')).toHaveCount(0);
});

test('a sign-in that comes back to /join/<code> goes on to the app with its parameters', async ({ page }) => {
  await page.route((url) => url.pathname === '/', (route) => route.fulfill({ contentType: 'text/html', body: '<p>app</p>' }));
  await page.goto(`/join/${code}?code=pkce123#later`);
  await expect(page).toHaveURL(new RegExp(`/\\?code=pkce123&invite=${code}#later$`));
});

test('the page is served under the deployed CSP and runs without CSP errors', async ({ page }) => {
  const response = await page.request.get(`/join/${code}`);
  const csp = response.headers()['content-security-policy'];
  expect(csp, 'serve.mjs --csp sends vercel.json\'s policy').toContain("script-src 'self'");
  expect(response.headers()['content-type']).toContain('text/html');
  const { cspErrors, calls } = await joinPage(page, okAnswer);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(/Familie Brandt/);
  expect(calls).toHaveLength(1);
  expect(cspErrors).toEqual([]);
});

test("vercel.json's CSP lets the production join page reach its Supabase project", () => {
  const vercel = JSON.parse(readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8')) as {
    headers: { headers: { key: string; value: string }[] }[];
  };
  const csp = vercel.headers.flatMap((h) => h.headers).find((h) => h.key === 'Content-Security-Policy')?.value ?? '';
  const config = readFileSync(new URL('../../app/web/join/config.js', import.meta.url), 'utf8');
  const url = /supabaseUrl = '([^']+)'/.exec(config)?.[1] ?? '';
  expect(url).toMatch(/^https:\/\/[a-z0-9]+\.supabase\.co$/);
  expect(csp.split(';').find((d) => d.trim().startsWith('connect-src'))).toContain(url);
});
