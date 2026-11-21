// The PR's screenshots of the round: each section of te/ in the asked variants.
// Usage: node tools/shots.mjs <out dir> [<root>] [--path /docs/design/totals/]
import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const pathArg = args.includes('--path') ? args[args.indexOf('--path') + 1] : '/docs/design/totals/';
const [out, rootArg] = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--path');
const root = resolve(rootArg ?? join(here, '../../../..'));
const pwDir = [join(root, 'e2e'), join(here, '../../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
mkdirSync(out, { recursive: true });

const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2200, height: 1200 } });
const variants = ['', 'theme=dark&lang=de', 'ts=310', 'device=android&ts=200'];
const sections = (q) => (q ? ['today', 'TE1', 'TE2', 'TE3', 'TE4', 'TE5'] : ['today', 'TE1', 'TE2', 'TE3', 'TE4', 'TE5', 'table', 'rec']);
for (const q of variants) {
  await page.goto(`${url}${pathArg}te/?${q}`);
  await page.waitForSelector('body[data-ready]');
  for (const id of sections(q)) {
    const name = `TE-${id}${q ? `-${q.replace(/[=&]/g, '-')}` : ''}.png`;
    if (!(await page.locator(`#${id}`).innerText()).trim()) continue;
    await page.locator(`#${id}`).screenshot({ path: join(out, name) });
    console.log(name);
  }
}
await page.goto(`${url}${pathArg}`);
await page.waitForSelector('body[data-ready]');
await page.screenshot({ path: join(out, 'overview.png') });
await browser.close();
server.close();
