// Measures every option in every scenario on the round page: measured.json[lang][device][ts][scenario][option] =
// { active, recent, toFirstRecent, sectionPx } (phone.js `measure`). --write stores it in ru/measured.json (keeping
// pick and runner) and fills the measured tables of ru/RECOMMENDATION.md and .de.md.
// Usage: node tools/measure.mjs [--write] [--dir <root>] [--path /docs/design/list/]
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { chromium } from './pw.mjs';
import { fill } from './rec-table.mjs';
import { serve } from './serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const combos = [['ios', 100], ['ios', 310], ['android', 100], ['android', 200]];

export const measureAll = async (browser, base) => {
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
  const out = {};
  for (const lang of ['en', 'de']) {
    out[lang] = {};
    for (const [dev, ts] of combos) {
      const q = new URLSearchParams({ lang, device: dev, ts: String(ts) });
      await page.goto(`${base}ru/?${q}`);
      await page.waitForSelector('body[data-ready]');
      out[lang][dev] ??= {};
      out[lang][dev][ts] = await page.evaluate(() => window.ru.measureAll());
    }
  }
  await page.close();
  return out;
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (k, d) => (args.includes(k) ? args[args.indexOf(k) + 1] : d);
  const dir = resolve(opt('--dir', join(here, '../../../..')));
  const path = opt('--path', '/docs/design/list/');
  const { server, url } = await serve(dir);
  const browser = await chromium.launch();
  const m = await measureAll(browser, `${url}${path}`);
  await browser.close();
  server.close();
  if (args.includes('--write')) {
    const file = join(here, '../ru/measured.json');
    let old = {};
    try { old = JSON.parse(readFileSync(file, 'utf8')); } catch { /* first run */ }
    writeFileSync(file, `${JSON.stringify({ pick: old.pick ?? '', runner: old.runner ?? '', ...m }, null, 1)}\n`);
    for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
      const p = join(here, '../ru', f);
      writeFileSync(p, fill(readFileSync(p, 'utf8'), m));
    }
    console.log(`wrote ${file} and the RECOMMENDATION tables`);
  } else {
    console.log(JSON.stringify(m.en.ios[100], null, 1));
  }
}
