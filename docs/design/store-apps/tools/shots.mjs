// The PR's screenshots: each option's section, the overview, a 390 px phone. Usage: node shots.mjs <out> [<root>]
import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] ?? 'shots');
const root = resolve(process.argv[3] ?? join(here, '../../../..'));
const pwDir = [join(root, 'e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
mkdirSync(out, { recursive: true });
const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2520, height: 1200 } });
const base = `${url}/docs/design/store-apps/`;
const section = async (path, id, file) => {
  await page.goto(`${base}${path}`);
  await page.waitForSelector('body[data-ready]');
  await page.locator(`section#${id}`).screenshot({ path: join(out, file) });
};
for (const id of ['today', 'OS1', 'OS2', 'OS3', 'OS4', 'OS5']) await section('os/', id, `OS-${id}.png`);
await section('os/?platform=android&installed=no', 'OS1', 'OS-OS1-android-not-installed.png');
await section('os/?lang=de&theme=dark&ts=310', 'OS1', 'OS-OS1-de-dark-310.png');
for (const sc of ['migrate', 'new', 'unlisted', 'twocountries', 'country']) {
  for (const id of ['SS1', 'SS2', 'SS3', 'SS4', 'SS5']) await section(`ss/?scenario=${sc}`, id, `SS-${sc}-${id}.png`);
}
await section('ss/', 'registry', 'SS-registry.png');
await page.setViewportSize({ width: 1200, height: 700 });
await page.goto(base);
await page.waitForSelector('body[data-ready]');
await page.screenshot({ path: join(out, 'overview.png') });
const phone = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true });
await phone.goto(`${base}os/#OS1`);
await phone.waitForSelector('body[data-ready]');
await phone.screenshot({ path: join(out, 'OS-phone-390x844.png') });
await browser.close();
server.close();
console.log(`shots in ${out}`);
