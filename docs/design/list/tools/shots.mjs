// The PR's screenshots: per option a strip of its short-3, long-15 and scrolled frames in four variants, and the tick
// strip (EN light 100 %).
// Usage: node tools/shots.mjs <out dir> [--dir <root>] [--path /docs/design/list/]
import { mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { chromium } from './pw.mjs';
import { serve } from './serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (k, d) => (args.includes(k) ? args[args.indexOf(k) + 1] : d);
const out = args[0];
const root = resolve(opt('--dir', join(here, '../../../..')));
const path = opt('--path', '/docs/design/list/');
mkdirSync(out, { recursive: true });

const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2400, height: 1200 } });
const variants = [['en-light-100', 'lang=en'], ['de-dark-100', 'lang=de&theme=dark'], ['en-light-310', 'ts=310'], ['en-android-200', 'device=android&ts=200']];
const strip = async (id, frames, file) => {
  await page.evaluate(async ([oid, fs]) => {
    document.getElementById('strip')?.remove();
    const s = document.createElement('div');
    s.id = 'strip';
    s.className = document.body.className;
    s.style.cssText = 'display:flex;gap:16px;padding:12px;position:absolute;top:0;left:0;z-index:99;background:var(--hl-color-surface-sunken)';
    for (const f of fs) s.append(document.querySelector(`#${oid} [data-frame="${f}"]`).cloneNode(true));
    document.body.append(s);
    (await import(new URL('../phone.js', location.href).href)).settle(s);
  }, [id, frames]);
  await page.locator('#strip').screenshot({ path: join(out, file) });
  console.log(file);
};
for (const [tag, q] of variants) {
  await page.goto(`${url}${path}ru/?${q}`);
  await page.waitForSelector('body[data-ready]');
  for (const id of ['today', 'RU1', 'RU2', 'RU3', 'RU4']) {
    await strip(id, ['short-3', 'long-15', 'scrolled'], `${id}-${tag}.png`);
    if (tag === 'en-light-100') await strip(id, ['tick-start', 'tick-mid', 'tick-landed', 'back'], `${id}-tick-${tag}.png`);
  }
}
await browser.close();
server.close();
