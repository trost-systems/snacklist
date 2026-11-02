// Usage: node waitlist.mjs [distDir] [--port 57640] [--shots dir]
// The waitlist in Chromium against scripts/preview.mjs and a stub of the edge function: the form's
// labelled errors, the client-side email check, sign-up, the honeypot, the server's answers, the
// confirm and unsubscribe pages (nothing sent before the button), the form above the fold at
// 390 px, and on every page no cookie, no request off this origin and no console error.
// The dist must be a waitlist-mode build (`npm run build` outside production). --shots writes
// the PR screenshots. README.md lists what each step proves.
import { createServer } from 'node:http';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { parseArgs, serve } from './lib.mjs';

const args = process.argv.slice(2);
const shotsAt = args.indexOf('--shots');
const shots = shotsAt < 0 ? null : args.splice(shotsAt, 2)[1];
process.argv = [process.argv[0], process.argv[1], ...args];
const { dist, port } = parseArgs({ port: 57640 });
if (shots) mkdirSync(shots, { recursive: true });

// The edge function, by what the test sends: an address with +busy is rate limited, +down makes
// the upstream fail (the proxy answers 503); token "good" confirms, id "good" deletes.
const calls = [];
const upstream = createServer(async (req, res) => {
  let text = '';
  for await (const chunk of req) text += chunk;
  const body = JSON.parse(text);
  calls.push({ path: req.url, body, secret: req.headers['x-waitlist-proxy-secret'], region: req.headers['x-region'] });
  const send = (status, data) => res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(data));
  if (req.url === '/signup') {
    if (body.email.includes('+busy')) return send(429, { error: 'rate_limited' });
    if (body.email.includes('+down')) return res.writeHead(502).end('bad gateway');
    return send(202, { status: 'ok' });
  }
  if (req.url === '/confirm') return send(200, { status: body.token === 'good' ? 'confirmed' : 'invalid' });
  if (req.url === '/unsubscribe') return send(200, { status: body.id === 'good' && body.sig === 'sig' ? 'deleted' : 'invalid' });
  send(404, { error: 'not_found' });
});
await new Promise((r) => upstream.listen(0, '127.0.0.1', r));
process.env.WAITLIST_UPSTREAM_URL = `http://127.0.0.1:${upstream.address().port}`;
process.env.WAITLIST_PROXY_SECRET = 'check-secret';

const { origin, close } = await serve(dist, port);
const browser = await chromium.launch();
const problems = [];
let steps = 0;
const expect = (ok, what) => {
  steps++;
  if (!ok) problems.push(what);
};

async function open(path, { width = 390, scheme = 'light' } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height: width === 390 ? 844 : 900 }, colorScheme: scheme, reducedMotion: 'reduce' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => {
    // Chromium logs every 4xx/5xx response; the rate-limit and outage steps ask for those on purpose.
    const answered = /^Failed to load resource: the server responded with a status of (429|503)/.test(m.text()) && m.location().url.endsWith('/api/waitlist');
    if (m.type() === 'error' && !answered) errors.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => errors.push(`page error: ${e}`));
  page.on('request', (r) => { if (!r.url().startsWith(origin)) errors.push(`off-origin request ${r.url()}`); });
  await page.goto(origin + path, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  const done = async () => {
    for (const e of errors) problems.push(`${path}: ${e}`);
    const cookies = await ctx.cookies();
    expect(cookies.length === 0, `${path}: cookies set: ${cookies.map((c) => c.name).join(', ')}`);
    await ctx.close();
  };
  return { page, done };
}

const shot = async (target, name) => {
  if (shots) await target.screenshot({ path: join(shots, `${name}.png`), animations: 'disabled' });
};
const visible = (page, selector) => page.locator(selector).isVisible();
const describedBy = (page, selector) => page.locator(selector).evaluate((el) =>
  (el.getAttribute('aria-describedby') ?? '').split(' ').filter(Boolean).map((id) => document.getElementById(id)?.textContent.trim()));

for (const [locale, anchor, email, platform, sent] of [
  ['de', 'warteliste', 'E-Mail-Adresse', 'iPhone', 'Fast geschafft'],
  ['en', 'waitlist', 'Email address', 'Android', 'Almost there'],
]) {
  const path = `/${locale}`;
  for (const width of [390, 1440]) {
    const { page, done } = await open(path, { width });
    await shot(page, `landing-${locale}-${width}`);
    const field = await page.getByLabel(email).boundingBox();
    expect(field && field.y + field.height <= (width === 390 ? 844 : 900), `${path} at ${width}: the email field is below the fold (${field && Math.round(field.y + field.height)}px)`);
    await done();
  }

  const { page, done } = await open(path);
  const before = calls.length;
  const card = page.locator(`#${anchor}`);
  await page.locator('.header-cta').click();
  await page.waitForTimeout(300);
  expect(await card.evaluate((el) => el.getBoundingClientRect().top < innerHeight), `${path}: the header button does not bring the form into view`);

  await page.locator('.wl-submit').click();
  expect(await visible(page, '#wl-email-error') && await visible(page, '#wl-platform-error'), `${path}: empty submit shows no field errors`);
  expect((await page.locator('#wl-email').getAttribute('aria-invalid')) === 'true', `${path}: email not aria-invalid`);
  expect((await describedBy(page, '#wl-email')).length === 2, `${path}: the email error is not tied to the field`);
  expect((await describedBy(page, 'input[value="ios"]')).length === 1, `${path}: the platform error is not tied to the radios`);
  expect(await page.evaluate(() => document.activeElement?.id) === 'wl-email', `${path}: focus did not move to the first error`);
  await shot(card, `form-errors-${locale}`);

  await page.getByLabel(email).fill('hello+waitlisttest@');
  await page.getByLabel(platform, { exact: true }).check();
  await page.locator('.wl-submit').click();
  const invalid = (await page.locator('#wl-email-error').textContent()).trim();
  expect(/richtig|right/.test(invalid), `${path}: invalid email not named (${invalid})`);
  expect(!(await visible(page, '#wl-platform-error')), `${path}: platform error stays after choosing`);
  expect(calls.length === before, `${path}: an invalid form reached the server`);

  await page.getByLabel(email).fill('hello+waitlisttest+busy@hummlist.com');
  await page.locator('.wl-submit').click();
  await page.locator('.wl-status').filter({ hasText: /Versuche|tries/ }).waitFor();
  await page.getByLabel(email).fill('hello+waitlisttest+down@hummlist.com');
  await page.locator('.wl-submit').click();
  await page.locator('.wl-status').filter({ hasText: /gerade nicht|just now/ }).waitFor();

  await page.getByLabel(email).fill(`hello+waitlisttest-${locale}@hummlist.com`);
  await page.locator('.wl-submit').click();
  await page.locator('.wl-done').waitFor();
  expect((await page.locator('.wl-done h2').textContent()).includes(sent), `${path}: success state`);
  expect(await page.evaluate(() => document.activeElement?.classList.contains('wl-done')), `${path}: focus not on the success message`);
  const signup = calls.at(-1);
  expect(signup.path === '/signup' && signup.secret === 'check-secret' && signup.region === 'eu-central-1', `${path}: upstream call ${JSON.stringify(signup)}`);
  const { body } = signup;
  expect(body.email === `hello+waitlisttest-${locale}@hummlist.com` && body.platform === (platform === 'iPhone' ? 'ios' : 'android') && body.locale === locale
    && body.launch_news === false && body.consent_version === `waitlist-${locale}-v1` && body.website === '' && Number.isInteger(body.elapsed_ms) && body.elapsed_ms > 0,
  `${path}: sign-up body ${JSON.stringify(body)}`);
  await shot(card, `form-success-${locale}`);
  await done();

  const bot = await open(path);
  await bot.page.getByLabel(email).fill('hello+waitlisttest-bot@hummlist.com');
  await bot.page.getByLabel(platform, { exact: true }).check();
  await bot.page.locator('input[name="launch_news"]').check();
  await bot.page.locator('#wl-website').evaluate((el) => { el.value = 'https://spam.example'; });
  await bot.page.locator('.wl-submit').click();
  await bot.page.locator('.wl-done').waitFor();
  expect(calls.at(-1).body.website === 'https://spam.example' && calls.at(-1).body.launch_news === true, `${path}: honeypot and launch news not sent`);
  await bot.done();
}

for (const [path, kind, good, bad, done, name] of [
  ['/de/warteliste/bestaetigen', 'confirm', '#t=good', '#t=old', 'Du stehst auf der Warteliste', 'confirm-de'],
  ['/en/waitlist/confirm', 'confirm', '#t=good', '#t=old', "You're on the waitlist", 'confirm-en'],
  ['/de/warteliste/abmelden', 'unsubscribe', '#id=good&s=sig', '#id=good&s=forged', 'Dein Eintrag ist gelöscht', 'unsubscribe-de'],
  ['/en/waitlist/unsubscribe', 'unsubscribe', '#id=good&s=sig', '#id=good&s=forged', 'Your sign-up is deleted', 'unsubscribe-en'],
]) {
  for (const [fragment, heading] of [[good, done], [bad, null], ['', null]]) {
    const before = calls.length;
    const { page, done: close } = await open(path + fragment);
    await page.waitForTimeout(300);
    expect(calls.length === before, `${path}${fragment}: opening the page sent a request`);
    const state = await page.locator(`[data-waitlist="${kind}"]`).getAttribute('data-state');
    if (fragment === '') {
      expect(state === 'invalid', `${path} without values: state ${state}, expected the neutral page`);
    } else {
      expect(state === 'ready', `${path}${fragment}: state ${state}`);
      if (fragment === good) await shot(page, `${name}-before`);
      await page.locator('.wl-action').click();
      await page.locator(`[data-waitlist="${kind}"]:not([data-state="ready"]):not([data-state="sending"])`).waitFor();
      const sent = calls.at(-1);
      expect(sent.path === `/${kind}` && calls.length === before + 1, `${path}${fragment}: button sent ${JSON.stringify(sent)}`);
      const shown = (await page.locator('#wl-heading').innerText()).trim();
      if (heading) {
        expect(shown === heading, `${path}${fragment}: heading "${shown}"`);
        await shot(page, `${name}-after`);
      } else {
        expect(await page.locator(`[data-waitlist="${kind}"]`).getAttribute('data-state') === 'invalid', `${path}${fragment}: not the neutral page`);
        if (kind === 'confirm' && path.startsWith('/de')) await shot(page, `${name}-invalid`);
      }
      expect(!page.url().includes('#'), `${path}: the values stay in the address bar`);
      expect(await page.evaluate(() => document.activeElement?.id) === 'wl-heading', `${path}: focus not on the new heading`);
    }
    await close();
  }
}

await browser.close();
await close();
upstream.close();
console.log(`waitlist: ${steps} checks, ${calls.length} upstream calls`);
if (problems.length) {
  console.error(problems.map((p) => `- ${p}`).join('\n'));
  process.exit(1);
}
console.log('waitlist: no problems');
