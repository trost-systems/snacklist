// Usage: node selftest.mjs [distDir] [--port 57623]
// Proves crawl.mjs catches what it claims to: copies the dist to a temp dir, breaks /de in one
// known way per check, runs crawl.mjs on /de alone and fails unless every breakage is reported.
import { execFileSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { parseArgs } from './lib.mjs';

const { dist, port } = parseArgs({ port: 57623 });
const dir = mkdtempSync(join(tmpdir(), 'site-checks-selftest-'));
cpSync(dist, dir, { recursive: true });

// A short webm to autoplay, recorded by Playwright itself.
{
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ recordVideo: { dir, size: { width: 320, height: 180 } }, viewport: { width: 320, height: 180 } });
  const page = await ctx.newPage();
  await page.setContent('<body style="background:#e33"></body>');
  await page.waitForTimeout(1500);
  await ctx.close();
  execFileSync('mv', [await page.video().path(), join(dir, 'selftest.webm')]);
  await browser.close();
}

appendFileSync(join(dir, 'styles.css'), `
.hex:active { --y: 0px !important; }
a:not(.hex):focus-visible { outline: none !important; }
.brand .mark { animation: selftest-spin 2s linear infinite !important; }
@keyframes selftest-spin { to { rotate: 1turn; } }
.selftest-small { width: 20px; height: 20px; }
.selftest-wide { width: 2400px; }
.selftest-faint { color: #ddd; background: #fff; }
`);
const html = readFileSync(join(dir, 'de.html'), 'utf8').replace('<main id="inhalt">', `<main id="inhalt">
<button class="selftest-small" type="button">x</button>
<video class="selftest-video" autoplay muted loop playsinline src="/selftest.webm"></video>
<img src="https://example.com/selftest.png" alt="selftest">
<p class="selftest-wide">This paragraph is far wider than any phone.</p>
<p class="selftest-faint">Faint text</p>`);
writeFileSync(join(dir, 'de.html'), html);

let out = '';
try {
  execFileSync(process.execPath, ['crawl.mjs', dir, '--pages', '/de', '--port', String(port)], { cwd: import.meta.dirname, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
} catch (e) {
  out = e.stdout;
}
rmSync(dir, { recursive: true, force: true });

const expected = {
  press: /\[press\] .*face moved 0\.0px on press/,
  focus: /\[focus\] .*focus indicator changes/,
  'motion (animation)': /\[motion\] .*running under reduced motion/,
  'motion (video)': /\[motion\] .*video\.selftest-video.*video plays under reduced motion/,
  target: /\[target\] .*selftest-small.*< 48px/,
  csp: /\[(csp|console)\] .*(img-src|Content Security Policy).*example\.com/,
  overflow: /\[overflow\] .*selftest-wide/,
  axe: /\[axe\] .*selftest-faint.*color-contrast/,
};
const missed = Object.entries(expected).filter(([, re]) => !re.test(out)).map(([k]) => k);
console.log(out);
if (missed.length) {
  console.error(`selftest: crawl.mjs missed ${missed.join(', ')}`);
  process.exit(1);
}
console.error(`selftest: crawl.mjs reported all ${Object.keys(expected).length} breakages`);
