// Usage: node get-app.mjs [distDir] [--port 57660] [--shots dir]   (a launch-stage build)
// The launch stage's store cards in Chromium with each device's user agent: a desktop sees both
// badges and both QR codes, an iPhone only the App Store badge, an Android phone only Google
// Play's, no phone a QR code, and every badge links straight to its listing. Also the web app link
// in the nav and no waitlist form, in German and English.
import process from 'node:process';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { parseArgs, serve } from './lib.mjs';

const args = process.argv.slice(2);
const shotsAt = args.indexOf('--shots');
const shots = shotsAt < 0 ? null : args.splice(shotsAt, 2)[1];
process.argv = [process.argv[0], process.argv[1], ...args];
const { dist, port } = parseArgs({ port: 57660 });
if (shots) mkdirSync(shots, { recursive: true });

const APP_STORE = 'https://apps.apple.com/app/id6832756448';
const PLAY = 'https://play.google.com/store/apps/details?id=com.snacklist.app';
const DEVICES = {
  desktop: { ua: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36', viewport: { width: 1440, height: 900 }, badges: [APP_STORE, PLAY], qr: 2 },
  iphone: { ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1', viewport: { width: 390, height: 844 }, mobile: true, badges: [APP_STORE], qr: 0 },
  android: { ua: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36', viewport: { width: 390, height: 844 }, mobile: true, badges: [PLAY], qr: 0 },
};

const { origin, close } = await serve(dist, port);
const browser = await chromium.launch();
const problems = [];
let steps = 0;
const expect = (ok, what) => {
  steps++;
  if (!ok) problems.push(what);
};

for (const locale of ['de', 'en']) {
  for (const [name, device] of Object.entries(DEVICES)) {
    const context = await browser.newContext({ userAgent: device.ua, viewport: device.viewport, isMobile: device.mobile ?? false, hasTouch: device.mobile ?? false });
    const page = await context.newPage();
    const errors = [];
    page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
    page.on('pageerror', (e) => errors.push(String(e)));
    await page.goto(`${origin}/${locale}`);
    const at = `${locale} ${name}`;
    for (const [where, selector] of [['hero', '.hero-actions'], ['closing block', '#app']]) {
      const links = await page.$$eval(`${selector} .store-badge`, (as) => as.filter((a) => a.getBoundingClientRect().width > 0).map((a) => a.href));
      expect(JSON.stringify(links) === JSON.stringify(device.badges), `${at} ${where}: visible badges ${links}`);
    }
    const qr = await page.$$eval('#app .store-qr svg', (svgs) => svgs.filter((s) => s.getBoundingClientRect().width > 0).length);
    expect(qr === device.qr, `${at}: ${qr} visible QR codes, want ${device.qr}`);
    expect(await page.locator('form').count() === 0, `${at}: a form is on the page`);
    const nav = await page.$$eval('header .nav a', (as) => as.map((a) => [a.textContent, a.href]));
    expect(nav.some(([text, href]) => text === (locale === 'de' ? 'Web-App' : 'Web app') && href === 'https://app.snacklist.app/'), `${at}: nav has no web app link: ${JSON.stringify(nav)}`);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${at}: horizontal scroll`);
    expect(errors.length === 0, `${at}: console errors ${errors}`);
    if (shots) {
      await page.locator('#app').scrollIntoViewIfNeeded();
      await page.screenshot({ path: join(shots, `${locale}-${name}.png`) });
      await page.screenshot({ path: join(shots, `${locale}-${name}-top.png`), clip: { x: 0, y: 0, ...device.viewport } }).catch(() => {});
    }
    await context.close();
  }
}

await browser.close();
await close();
console.log(`get-app: ${steps} checks, ${problems.length} problems`);
for (const p of problems) console.log(`  ${p}`);
process.exit(problems.length > 0 ? 1 : 0);
