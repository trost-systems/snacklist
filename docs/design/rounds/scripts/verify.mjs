#!/usr/bin/env node
// Screenshots every option and checks the measurements this round is about.
// Exits non-zero on failure. Serves the built dist/ locally for the check only.

import { createServer } from 'node:http';
import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = join(root, 'verify-screenshots');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
};

function startStaticServer() {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    let rel = decodeURIComponent(url.pathname);
    if (rel === '/') rel = '/index.html';
    const filePath = join(dist, rel);
    if (!filePath.startsWith(dist)) {
      res.writeHead(403).end();
      return;
    }
    try {
      const st = statSync(filePath);
      if (st.isFile()) {
        res.writeHead(200, { 'content-type': MIME[extname(filePath)] ?? 'application/octet-stream' });
        res.end(readFileSync(filePath));
        return;
      }
    } catch {
      // SPA fallback
    }
    try {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(readFileSync(join(dist, 'index.html')));
    } catch (err) {
      res.writeHead(500).end(String(err));
    }
  });
  return new Promise((resolvePromise) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolvePromise({ server, base: `http://127.0.0.1:${port}` });
    });
  });
}

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch {
    return await import('/home/box/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs');
  }
}

async function barY(page) {
  return page.evaluate(() => {
    const screen = document.querySelector('.phone-screen');
    const bar = document.querySelector('.ob-progress');
    if (!screen || !bar) return null;
    return Math.round(bar.getBoundingClientRect().top - screen.getBoundingClientRect().top);
  });
}

async function clickOption(page, code) {
  await page.locator(`[data-option="${code}"]`).click();
  await page.waitForTimeout(80);
}

async function goToStep(page, n) {
  for (let i = 0; i < 12; i += 1) {
    const label = await page.locator('.transport-step').innerText();
    const current = Number((label.match(/Step\s+(\d+)/) || [])[1] || 0);
    if (current === n) return;
    if (current < n) {
      await page.locator('.transport').getByRole('button', { name: 'Next', exact: true }).click();
    } else {
      await page.locator('.transport').getByRole('button', { name: 'Back', exact: true }).click();
    }
    await page.waitForTimeout(420);
  }
  throw new Error(`Could not reach step ${n} (at ${await page.locator('.transport-step').innerText()})`);
}

async function overflow(page) {
  return page.evaluate(() => {
    const doc = document.documentElement;
    return {
      scrollWidth: doc.scrollWidth,
      clientWidth: doc.clientWidth,
      overflowPx: Math.max(0, doc.scrollWidth - doc.clientWidth),
    };
  });
}

const failures = [];
const log = [];
const say = (msg) => {
  log.push(msg);
  console.log(msg);
};

const { chromium } = await loadPlaywright();
mkdirSync(outDir, { recursive: true });
const { server, base } = await startStaticServer();

const browser = await chromium.launch({
  executablePath: process.env.VERIFY_CHROME || '/usr/bin/google-chrome-stable',
  headless: true,
  args: ['--font-render-hinting=none', '--no-sandbox', '--disable-dev-shm-usage'],
});

try {
  const phone = { width: 390, height: 844, deviceScaleFactor: 2 };
  const page = await browser.newPage({ viewport: phone });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.goto(`${base}/round`, { waitUntil: 'networkidle' });
  await page.waitForSelector('.phone-screen');

  // Overview exists and links to the round.
  const overview = await browser.newPage({ viewport: phone });
  await overview.goto(`${base}/`, { waitUntil: 'networkidle' });
  const overviewLink = overview.locator('a.overview-card[href="/round"]');
  if ((await overviewLink.count()) !== 1) failures.push('Overview is missing the T1–T5 round link.');
  await overview.screenshot({ path: join(outDir, 'overview-390.png'), fullPage: true });
  await overview.close();

  const options = ['T1', 'T2', 'T3', 'T4', 'T5', 'Today'];
  const measurements = {};

  for (const code of options) {
    await clickOption(page, code === 'Today' ? 'Today' : code);
    // Today button's data-option is "Today" from m.code
    const ys = [];
    for (let step = 1; step <= 7; step += 1) {
      await goToStep(page, step);
      const y = await barY(page);
      if (y == null) failures.push(`${code}: progress bar was not found on step ${step}.`);
      ys.push(y);
    }
    const present = ys.filter((y) => y != null);
    const min = Math.min(...present);
    const max = Math.max(...present);
    const jump = max - min;
    measurements[code] = { ys, jump };
    say(`${code}: bar Y by step = [${ys.join(', ')}] px · jump ${jump} px`);
    await goToStep(page, 1);
    await page.screenshot({ path: join(outDir, `round-${code.toLowerCase()}-step1-390.png`), fullPage: true });
    if (code === 'Today') {
      if (jump < 8) {
        failures.push(`Today should jump the progress bar (got ${jump} px; expected at least 8 px in this frame).`);
      }
    } else if (jump > 1) {
      failures.push(`${code} should keep the progress bar still (got ${jump} px jump; allowed 0–1 px).`);
    }
  }

  // Overflow matrix: 390 and 1440, 100% and 140% text, light and dark, English and German.
  const cases = [
    { width: 390, height: 844, text: '100%', theme: 'Light', lang: 'English' },
    { width: 390, height: 844, text: '140%', theme: 'Light', lang: 'English' },
    { width: 390, height: 844, text: '140%', theme: 'Dark', lang: 'Deutsch' },
    { width: 1440, height: 900, text: '100%', theme: 'Light', lang: 'English' },
    { width: 1440, height: 900, text: '140%', theme: 'Dark', lang: 'English' },
  ];

  for (const c of cases) {
    await page.setViewportSize({ width: c.width, height: c.height });
    const themeBtn = page.getByRole('button', { name: /Theme:/ });
    const textBtn = page.getByRole('button', { name: /Text size/ });
    const langBtn = page.getByRole('button', { name: /Language / });
    const themeNow = (await themeBtn.innerText()).includes('Dark') ? 'Dark' : 'Light';
    if (themeNow !== c.theme) await themeBtn.click();
    const textNow = (await textBtn.getAttribute('aria-label'))?.includes('140%') ? '140%' : '100%';
    // aria-label is "Text size 100%. Switch to 140%" — so current is the first number
    const textLabel = await textBtn.getAttribute('aria-label');
    const currentText = textLabel?.includes('Text size 140%') ? '140%' : '100%';
    if (currentText !== c.text) await textBtn.click();
    const langLabel = await langBtn.getAttribute('aria-label');
    const currentLang = langLabel?.includes('Deutsch') ? 'Deutsch' : 'English';
    if (currentLang !== c.lang) await langBtn.click();
    await clickOption(page, 'T1');
    await goToStep(page, 2);
    const ov = await overflow(page);
    const tag = `${c.width}x${c.height} ${c.text} ${c.theme} ${c.lang}`;
    say(`overflow ${tag}: ${ov.overflowPx} px (scroll ${ov.scrollWidth} / client ${ov.clientWidth})`);
    const slug = tag.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
    await page.screenshot({ path: join(outDir, `overflow-${slug}.png`), fullPage: true });
    if (ov.overflowPx > 0) failures.push(`Horizontal overflow of ${ov.overflowPx} px at ${tag}.`);
  }

  writeFileSync(join(outDir, 'measurements.json'), `${JSON.stringify({ measurements, failures }, null, 2)}\n`);
} finally {
  await browser.close();
  await new Promise((r) => server.close(r));
}

if (failures.length) {
  console.error(`\\nVERIFY FAILED (${failures.length}):`);
  for (const f of failures) console.error(`- ${f}`);
  process.exit(1);
}

console.log("\nVERIFY PASSED");
