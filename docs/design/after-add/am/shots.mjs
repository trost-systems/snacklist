// The PR's screenshots of round AM: each section, the overview.
// Usage: node am/shots.mjs <out> [<root>] [--query <query>] [--only <section id>[,<id>]]
import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from '../tools/serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (n) => (args.includes(n) ? args.splice(args.indexOf(n), 2)[1] : null);
const only = flag('--only')?.split(',');
const query = flag('--query') ?? '';
const out = resolve(args[0] ?? 'shots');
const root = resolve(args[1] ?? join(here, '../../../..'));
const pwDir = [join(root, 'e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
mkdirSync(out, { recursive: true });
const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 1200 } });
page.on('pageerror', (e) => console.error('pageerror', e.message));
const base = `${url}/docs/design/after-add/`;
const tag = query.replace(/[?&=]/g, '-').replace(/^-/, '');
await page.goto(`${base}am/${query ? `?${query}` : ''}`);
await page.waitForSelector('body[data-ready]');
for (const id of only ?? ['today', 'outcomes', 'AM1', 'AM2', 'AM3', 'AM4', 'AM5', 'table', 'rec']) {
  const loc = page.locator(`section#${id}`);
  if (await loc.count()) await loc.screenshot({ path: join(out, `AM-${id}${tag ? `-${tag}` : ''}.png`) });
}
if (!only) {
  await page.setViewportSize({ width: 1200, height: 700 });
  await page.goto(base);
  await page.waitForSelector('body[data-ready]');
  await page.screenshot({ path: join(out, 'overview.png') });
}
await browser.close();
server.close();
