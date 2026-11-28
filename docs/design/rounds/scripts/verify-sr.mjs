#!/usr/bin/env node
// Round SR: drives every add path with real clicks and counts them, measures the Mitteilungen
// content height at 390×844, checks the edge-case fixtures, and screenshots Today and SR1–SR5 in
// light/dark × EN/DE × 100/140 %. Fails (exit 1) when a count or a height differs from the page's
// table. Serves dist/ locally for the check only. Screenshots go to $VERIFY_OUT (default
// verify-screenshots/sr).

import { createServer } from 'node:http';
import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = resolve(process.env.VERIFY_OUT ?? join(root, 'verify-screenshots', 'sr'));
const HEIGHT_TOLERANCE = 2;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
};

function startStaticServer() {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    const filePath = join(dist, decodeURIComponent(url.pathname));
    if (!filePath.startsWith(dist)) {
      res.writeHead(403).end();
      return;
    }
    try {
      if (statSync(filePath).isFile()) {
        res.writeHead(200, { 'content-type': MIME[extname(filePath)] ?? 'application/octet-stream' });
        res.end(readFileSync(filePath));
        return;
      }
    } catch {
      // not a file: the SPA answers
    }
    res.writeHead(200, { 'content-type': MIME['.html'] });
    res.end(readFileSync(join(dist, 'index.html')));
  });
  return new Promise((done) => {
    server.listen(0, '127.0.0.1', () => done({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch {
    return await import('/home/box/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs');
  }
}

const failures = [];
const log = [];
const say = (msg) => {
  log.push(msg);
  console.log(msg);
};
const check = (ok, msg) => {
  if (ok) say(`  ok    ${msg}`);
  else {
    failures.push(msg);
    say(`  FAIL  ${msg}`);
  }
};

const { chromium } = await loadPlaywright();
mkdirSync(outDir, { recursive: true });
const { server, base } = await startStaticServer();
const browser = await chromium.launch({
  executablePath: process.env.VERIFY_CHROME || '/usr/bin/google-chrome-stable',
  headless: true,
});
const context = await browser.newContext({ viewport: { width: 1280, height: 1100 }, deviceScaleFactor: 1 });
const page = await context.newPage();
page.on('pageerror', (err) => failures.push(`page error: ${err.message}`));

const url = (q) => `${base}/reminders/sr/?${new URLSearchParams({ lang: 'en', theme: 'light', text: '100', ...q })}`;
async function open(q) {
  await page.goto(url(q));
  await page.locator('.sr-phone').waitFor();
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(60);
}

const phone = () => page.locator('.sr-phone');
const reminders = async () => JSON.parse((await phone().getAttribute('data-reminders')) ?? '[]');

let taps = 0;
async function tap(locator) {
  await locator.click();
  taps += 1;
}

const SAT_BEFORE_20 = { day: 6, offset: 'before', time: 20 * 60 };
const SAT_SAME_915 = { day: 6, offset: 'same', time: 9 * 60 + 15 };
const sameSet = (a, b) => JSON.stringify([...a].map((x) => JSON.stringify(x)).sort()) === JSON.stringify([...b].map((x) => JSON.stringify(x)).sort());

const radio = (name) => phone().getByRole('radio', { name, exact: true });
const PATHS = {
  sr1: {
    first: async () => {
      await tap(phone().getByRole('button', { name: 'Add reminder' }));
      await tap(radio('Saturday'));
      await tap(radio('Hour 20'));
      await tap(phone().getByTestId('sheet-save'));
    },
    second: async () => {
      await tap(phone().getByRole('button', { name: 'Add reminder' }));
      await tap(radio('Saturday'));
      await tap(radio('On the day'));
      await tap(radio('Hour 09'));
      await tap(radio('Minute 15'));
      await tap(phone().getByTestId('sheet-save'));
    },
  },
  sr2: {
    first: async () => {
      await tap(phone().locator('.sr-strip-day').nth(5));
      await tap(radio('Hour 20'));
      await tap(phone().getByTestId('composer-save'));
    },
    second: async () => {
      await tap(phone().locator('.sr-strip-day').nth(5));
      await tap(radio('On the day'));
      await tap(radio('Hour 09'));
      await tap(radio('Minute 15'));
      await tap(phone().getByTestId('composer-save'));
    },
  },
  sr3: {
    first: async () => {
      await tap(phone().getByRole('checkbox', { name: 'Saturday' }));
      await tap(phone().getByRole('button', { name: 'Evening before · 20:00' }));
    },
    second: async () => {
      await tap(phone().getByRole('button', { name: 'Morning of · 9:15' }));
    },
  },
  sr4: {
    first: async () => {
      await tap(phone().getByRole('checkbox', { name: 'Saturday' }));
      await tap(radio('Hour 20'));
      await tap(phone().getByTestId('rule-save'));
    },
    second: async () => {
      await tap(phone().getByRole('button', { name: 'New rule' }));
      await tap(radio('On the day'));
      await tap(radio('Hour 09'));
      await tap(radio('Minute 15'));
      await tap(phone().getByRole('checkbox', { name: 'Saturday' }));
      await tap(phone().getByTestId('rule-save'));
    },
  },
  sr5: {
    first: async () => {
      await tap(phone().getByRole('button', { name: 'Add reminder' }));
      await tap(radio('Saturday'));
      await tap(radio('Hour 20'));
      await tap(phone().getByTestId('sheet-save'));
    },
    second: async () => {
      await tap(phone().getByRole('button', { name: 'Add reminder' }));
      await tap(radio('Saturday'));
      await tap(radio('On the day'));
      await tap(radio('Hour 09'));
      await tap(radio('Minute 15'));
      await tap(phone().getByTestId('sheet-save'));
    },
  },
};

async function tableNumber(option, attr) {
  const v = await page.locator(`tr[data-row="${option}"] [${attr}]`).getAttribute(attr);
  return v === '' || v === null ? null : Number(v);
}

const measured = {};

say('Taps (fixture 1, EN, 100 %)');
for (const [option, path] of Object.entries(PATHS)) {
  await open({ o: option, f: 'none' });
  check((await reminders()).length === 0, `${option}: starts with no reminders`);
  taps = 0;
  await path.first();
  const first = taps;
  check(sameSet(await reminders(), [SAT_BEFORE_20]), `${option}: first path saved Saturday, day before, 20:00`);
  taps = 0;
  await path.second();
  const second = taps;
  check(sameSet(await reminders(), [SAT_BEFORE_20, SAT_SAME_915]), `${option}: second path added Saturday, on the day, 9:15 next to it`);
  const want1 = await tableNumber(option, 'data-taps-first');
  const want2 = await tableNumber(option, 'data-taps-second');
  check(first === want1, `${option}: ${first} taps for the first (table says ${want1})`);
  check(second === want2, `${option}: ${second} taps for the second (table says ${want2})`);
  measured[option] = { first, second };
  await phone().screenshot({ path: join(outDir, `taps-${option}-after-two.png`) });
}

await open({ o: 'today', f: 'none' });
await phone().getByRole('checkbox', { name: 'Saturday' }).click();
check(sameSet(await reminders(), [6]), 'today: one tap on Saturday picks the day (still 19:00 the evening before)');
check((await phone().getByRole('radio', { name: 'Hour 20' }).count()) === 0, 'today: no time picker');

say('Edit and delete');
for (const option of ['sr1', 'sr2', 'sr3', 'sr4', 'sr5']) {
  await open({ o: option, f: 'one' });
  const opener = {
    sr1: () => phone().locator('.sr-row-main').first(),
    sr2: () => phone().locator('.sr-timechip').first(),
    sr3: () => phone().locator('.sr-row-main').first(),
    sr4: () => phone().locator('.sr-row-main').first(),
    sr5: () => phone().locator('.sr-hero-main'),
  }[option];
  await opener().click();
  await radio('Hour 18').click();
  const saveId = { sr1: 'sheet-save', sr2: 'composer-save', sr3: 'sheet-save', sr4: 'rule-save', sr5: 'sheet-save' }[option];
  await phone().getByTestId(saveId).click();
  check(sameSet(await reminders(), [{ ...SAT_BEFORE_20, time: 18 * 60 }]), `${option}: editing moves 20:00 to 18:00`);
  await opener().click();
  await phone().getByRole('button', { name: 'Delete', exact: true }).click();
  check((await reminders()).length === 0, `${option}: delete removes it`);
}

say('Fixture 5 (now Sat 28 Nov 10:30): the passed 9:15 goes to next week');
for (const option of ['sr1', 'sr2', 'sr3', 'sr4', 'sr5']) {
  await open({ o: option, f: 'passed' });
  const text = await phone().innerText();
  check(/has passed|next week/.test(text), `${option}: says the 9:15 has passed / next week`);
  check(!/overdue/i.test(text), `${option}: never says overdue`);
  await phone().screenshot({ path: join(outDir, `passed-${option}.png`) });
}
await open({ o: 'sr5', f: 'passed' });
check((await phone().locator('.sr-hero-when').innerText()).startsWith('Today, 20:00') === false, 'sr5: the hero is not the passed 9:15');
check(/Tomorrow|Today|Tue|Mon|Sat|Fri/.test(await phone().locator('.sr-hero-when').innerText()), 'sr5: the hero shows the next real firing');

say('Saving a time already passed today (SR-Q7)');
await open({ o: 'sr1', f: 'none' });
await page.locator('select[aria-label="Mock day"]').selectOption('6');
await PATHS.sr1.second();
const snack = await phone().locator('.sr-snack').innerText();
check(/Sat 5 Dec, 9:15/.test(snack) && /has passed/.test(snack), `sr1: saving Sat 9:15 at Sat 10:30 says the first is Sat 5 Dec ("${snack}")`);

say('Heights (fixture 3, 390×844)');
const heights = {};
const TABLE_KEYS = { en100: 'data-h100', de100: 'data-h100de', en140: 'data-h140' };
for (const option of ['today', 'sr1', 'sr2', 'sr3', 'sr4', 'sr5']) {
  heights[option] = {};
  for (const text of ['100', '140']) {
    for (const lang of ['en', 'de']) {
      await open({ o: option, f: 'three', text, lang });
      const key = `${lang}${text}`;
      const r = page.getByTestId('fit-readout');
      const content = Number(await r.getAttribute('data-content'));
      const viewport = Number(await r.getAttribute('data-viewport'));
      heights[option][key] = content;
      if (key === 'en100') heights[option].section = Number(await r.getAttribute('data-section'));
      const box = await page.locator('.sr-screen').boundingBox();
      check(Math.round(box?.width ?? 0) === 390 && Math.round(box?.height ?? 0) === 844, `${option} ${key}: phone screen is 390×844`);
      check(viewport === 643, `${option} ${key}: viewport 643 px (got ${viewport})`);
      const attr = TABLE_KEYS[key];
      if (attr) {
        const want = await tableNumber(option, attr);
        check(Math.abs(content - want) <= HEIGHT_TOLERANCE, `${option} ${key}: content ${content} px (table says ${want})`);
      }
      const xOverflow = await page.getByTestId('phone-scroll').evaluate((el) => el.scrollWidth - el.clientWidth);
      check(xOverflow <= 0, `${option} ${key}: no sideways overflow in the phone`);
    }
  }
  const wantSection = await tableNumber(option, 'data-section100');
  check(Math.abs(heights[option].section - wantSection) <= HEIGHT_TOLERANCE, `${option}: reminder section ${heights[option].section} px (table says ${wantSection})`);
  say(`  ${option}: ${JSON.stringify(heights[option])}`);
}

say('Soft look: no shadow on section cards');
await open({ o: 'sr1', f: 'three' });
const shadows = await page.locator('.sr-group').evaluateAll((els) => els.map((e) => getComputedStyle(e).boxShadow));
check(shadows.every((s) => s === 'none'), `every .sr-group has box-shadow none (${shadows.length} cards)`);

say('Screenshots');
let shots = 0;
for (const option of ['today', 'sr1', 'sr2', 'sr3', 'sr4', 'sr5']) {
  for (const theme of ['light', 'dark']) {
    for (const lang of ['en', 'de']) {
      for (const text of ['100', '140']) {
        await open({ o: option, f: 'three', theme, lang, text });
        await phone().screenshot({ path: join(outDir, `${option}-${theme}-${lang}-${text}.png`) });
        shots += 1;
      }
    }
  }
  await open({ o: option, f: 'none' });
  await phone().screenshot({ path: join(outDir, `empty-${option}.png`) });
  shots += 1;
}
for (const [option, opener] of [
  ['sr1', () => phone().getByRole('button', { name: 'Add reminder' })],
  ['sr2', () => phone().locator('.sr-strip-day').nth(5)],
  ['sr5', () => phone().getByRole('button', { name: 'Add reminder' })],
  ['sr4', () => phone().getByRole('button', { name: 'New rule' })],
]) {
  await open({ o: option, f: 'three' });
  await opener().click();
  await page.waitForTimeout(120);
  await phone().screenshot({ path: join(outDir, `open-${option}.png`) });
  shots += 1;
}
await page.setViewportSize({ width: 390, height: 844 });
await open({ o: 'sr2', f: 'three' });
await page.screenshot({ path: join(outDir, 'page-mobile-top.png') });
await page.setViewportSize({ width: 1280, height: 1100 });
await open({ o: 'sr2', f: 'three' });
await page.screenshot({ path: join(outDir, 'page-desktop-full.png'), fullPage: true });
await page.goto(`${base}/`);
await page.screenshot({ path: join(outDir, 'overview.png'), fullPage: true });
check((await page.locator('.overview-card').first().getAttribute('href')) === '/reminders/sr/', 'overview lists SR first and links to it');
await page.goto(`${base}/round`);
check((await page.locator('.topbar-title').innerText()).includes('Onboarding'), 'the old /round link still opens T1–T5');
say(`  ${shots + 3} screenshots in ${outDir}`);

writeFileSync(join(outDir, 'measurements.json'), JSON.stringify({ taps: measured, heights }, null, 2));
writeFileSync(join(outDir, 'verify.log'), log.join('\n') + '\n');
await browser.close();
server.close();

if (failures.length) {
  console.error(`\nverify-sr FAILED (${failures.length}):\n- ${failures.join('\n- ')}`);
  process.exit(1);
}
console.log('\nverify-sr passed');
