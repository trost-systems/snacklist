// Usage: node history-shots.mjs <distDir> [outDir prefix]    (without outDir: only the overflow check)
// After `node ../scripts/history-fixture.mjs ../dist-history` (job 444): fails when a page scrolls sideways.
// Screenshots and horizontal-overflow check of pages at 390 and 1440 px, light and dark.
import process from 'node:process';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { RUNS, VIEWPORTS, serve } from './lib.mjs';

const [dist, out, prefix = ''] = process.argv.slice(2);
if (!dist) {
  console.error('usage: node history-shots.mjs <distDir> [outDir prefix]');
  process.exit(2);
}
const pages = ['/history', '/en/history'];
if (out) mkdirSync(out, { recursive: true });
const { origin, close } = await serve(dist, 0);
const browser = await chromium.launch();
let bad = 0;
for (const path of pages) {
  for (const { width, scheme } of RUNS) {
    const ctx = await browser.newContext({ viewport: VIEWPORTS[width], colorScheme: scheme });
    const page = await ctx.newPage();
    await page.goto(origin + path);
    const over = await page.evaluate(() => {
      const w = document.documentElement.clientWidth;
      return [...document.querySelectorAll('main *')].filter((e) => e.getBoundingClientRect().right > w + 0.5).map((e) => e.tagName + '.' + e.className).slice(0, 5)
        .concat(document.documentElement.scrollWidth > w ? [`scrollWidth ${document.documentElement.scrollWidth} > ${w}`] : []);
    });
    if (over.length) { bad++; console.log('OVERFLOW', path, width, scheme, over); }
    if (out) await page.screenshot({ path: join(out, `${prefix}${path.slice(1).replaceAll('/', '-')}-${width}-${scheme}.png`), fullPage: true });
    await ctx.close();
  }
}
await browser.close();
await close();
console.log(bad ? `${bad} overflowing runs` : 'no overflow');
process.exit(bad ? 1 : 0);
