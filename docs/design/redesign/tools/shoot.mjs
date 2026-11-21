// Screenshots the round page for review: node tools/shoot.mjs <query> <out.png> [--full | --sel <css>]
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../../../..');
const pwDir = [join(root, 'e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
const [query, out] = process.argv.slice(2);
const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2560, height: 1100 } });
page.on('pageerror', (e) => console.error('pageerror', e.message));
page.on('console', (m) => { if (m.type() === 'error') console.error('console', m.text()); });
await page.goto(`${url}/docs/design/redesign/rd/?${query}`);
await page.waitForSelector('body[data-ready="1"]', { timeout: 20000 });
const sel = process.argv.includes('--sel') ? process.argv[process.argv.indexOf('--sel') + 1] : null;
if (sel) await page.locator(sel).first().screenshot({ path: out });
else await page.screenshot({ path: out, fullPage: process.argv.includes('--full') });
await browser.close();
server.close();
console.log(`wrote ${out}`);
