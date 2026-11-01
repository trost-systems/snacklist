// Usage: node lighthouse.mjs [distDir] [--port 57622] [--out /tmp/s53/lighthouse] [--pages /de,/en]
// Lighthouse (performance, accessibility, best practices, SEO) for the landing pages at mobile
// (390 px) and desktop (1440 px), light and dark, against scripts/preview.mjs (vercel.json's
// headers, so the intended X-Robots-Tag: noindex fails is-crawlable). Chrome runs with
// --blink-settings=preferredColorScheme=<0 dark | 1 light> for the colour scheme; every run proves
// it took effect by sampling the page background in Lighthouse's own final screenshot.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { launch } from 'chrome-launcher';
import lighthouse from 'lighthouse';
import desktopConfig from 'lighthouse/core/config/desktop-config.js';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { contrast, parseArgs, serve, table } from './lib.mjs';

const { dist, port, out, pages: only } = parseArgs({ port: 57622, out: '/tmp/s53/lighthouse' });
const PAGES = only ?? ['/de', '/en'];
const CATEGORIES = ['performance', 'accessibility', 'best-practices', 'seo'];
// The site sends X-Robots-Tag: noindex until launch (vercel.json), so this audit fails on purpose.
const EXPECTED_FAILS = new Set(['is-crawlable']);
// tokens.css --hl-color-surface: the page ground in each scheme.
const SURFACE = { light: [0xf7, 0xf7, 0xf2], dark: [0x0b, 0x10, 0x24] };
const FORMS = {
  mobile: { width: 390, config: undefined, screenEmulation: { mobile: true, width: 390, height: 844, deviceScaleFactor: 3, disabled: false } },
  desktop: { width: 1440, config: desktopConfig, screenEmulation: { mobile: false, width: 1440, height: 900, deviceScaleFactor: 1, disabled: false } },
};
const SCHEME_FLAG = { dark: 0, light: 1 };

mkdirSync(out, { recursive: true });
const { origin, close } = await serve(dist, port);
const rows = [];
const problems = [];
let version = '';

for (const path of PAGES) {
  for (const [form, f] of Object.entries(FORMS)) {
    for (const scheme of ['light', 'dark']) {
      const chrome = await launch({
        chromePath: chromium.executablePath(),
        port: port + 10,
        // --no-sandbox as Playwright launches it: this host has no unprivileged user namespaces.
        chromeFlags: ['--headless=new', '--no-sandbox', '--no-first-run', `--blink-settings=preferredColorScheme=${SCHEME_FLAG[scheme]}`],
      });
      let lhr;
      try {
        const result = await lighthouse(origin + path, {
          port: chrome.port, output: 'json', logLevel: 'error', onlyCategories: CATEGORIES,
          formFactor: f.config ? 'desktop' : 'mobile', screenEmulation: f.screenEmulation,
        }, f.config);
        lhr = result.lhr;
        version = lhr.lighthouseVersion;
      } finally {
        await chrome.kill();
      }
      const name = `${path.replace(/\//g, '_').replace(/^_/, '')}-${form}-${scheme}`;
      writeFileSync(join(out, `${name}.json`), JSON.stringify(lhr, null, 1));

      // Proof of the scheme: the final screenshot's top-left corner is the page ground.
      const shot = lhr.audits['final-screenshot']?.details?.data;
      let ground = null;
      if (shot) {
        const buf = Buffer.from(shot.split(',')[1], 'base64');
        writeFileSync(join(out, `${name}.jpg`), buf);
        const { data, width } = await jpegToRgba(buf);
        const px = (x, y) => [...data.subarray((y * width + x) * 4, (y * width + x) * 4 + 3)];
        ground = px(4, 4);
      }
      const schemeOk = ground && contrast(ground, SURFACE[scheme]) < 1.15;
      if (!schemeOk) problems.push(`${name}: final screenshot ground ${ground ? `rgb(${ground})` : 'missing'} is not the ${scheme} surface rgb(${SURFACE[scheme]})`);

      const score = (c) => Math.round((lhr.categories[c]?.score ?? 0) * 100);
      const failing = (c) => lhr.categories[c].auditRefs
        .map((r) => lhr.audits[r.id])
        .filter((a) => a.score !== null && a.score < 1 && a.scoreDisplayMode !== 'informative' && a.scoreDisplayMode !== 'manual' && a.scoreDisplayMode !== 'notApplicable')
        .map((a) => a.id);
      const seoUnexpected = failing('seo').filter((id) => !EXPECTED_FAILS.has(id));
      if (score('accessibility') !== 100) problems.push(`${name}: accessibility ${score('accessibility')} (${failing('accessibility').join(', ')})`);
      if (seoUnexpected.length) problems.push(`${name}: SEO audits fail beyond the expected noindex: ${seoUnexpected.join(', ')}`);
      const bp = failing('best-practices');
      const metric = (id) => lhr.audits[id]?.displayValue ?? '-';
      rows.push({
        page: path, form, width: f.width, scheme, ground: ground ? `rgb(${ground.join(',')})` : '-', schemeOk,
        perf: score('performance'), a11y: score('accessibility'), bp: score('best-practices'), seo: score('seo'),
        lcp: metric('largest-contentful-paint'), cls: metric('cumulative-layout-shift'), tbt: metric('total-blocking-time'),
        perfFails: failing('performance'), a11yFails: failing('accessibility'), bpFails: bp, seoFails: failing('seo'),
      });
      console.error(`lighthouse ${name}: perf ${score('performance')} a11y ${score('accessibility')} bp ${score('best-practices')} seo ${score('seo')}`);
    }
  }
}
await close();

async function jpegToRgba(buf) {
  // Decode through Chromium: pngjs reads PNG only and the screenshot is a JPEG.
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const rgba = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = `data:image/jpeg;base64,${b64}`;
    await img.decode();
    const c = new OffscreenCanvas(img.width, img.height);
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    return { width: img.width, data: [...g.getImageData(0, 0, 16, 16).data] };
  }, buf.toString('base64'));
  await browser.close();
  // Only the top-left 16x16 is read back; index it as a 16-wide image.
  return { width: Math.min(16, rgba.width), data: Uint8Array.from(rgba.data) };
}

const header = ['page', 'form', 'scheme', 'ground (proof)', 'perf', 'a11y', 'best pr.', 'seo', 'LCP', 'CLS', 'TBT', 'below 1 (besides informative)'];
const body = rows.map((r) => [r.page, `${r.form} ${r.width}`, r.scheme, `${r.ground}${r.schemeOk ? '' : ' WRONG'}`, r.perf, r.a11y, r.bp, r.seo, r.lcp, r.cls, r.tbt,
  [...r.perfFails.map((a) => `perf:${a}`), ...r.a11yFails.map((a) => `a11y:${a}`), ...r.bpFails.map((a) => `bp:${a}`), ...r.seoFails.map((a) => `seo:${a}${EXPECTED_FAILS.has(a) ? ' (expected, noindex)' : ''}`)].join(', ') || '-']);
const md = `# Lighthouse, hummlist.com landing pages

Lighthouse ${version}, Chromium ${chromium.executablePath().match(/chromium-(\d+)/)?.[1] ?? ''} build, against \`${dist}\` served by \`scripts/preview.mjs\` (vercel.json headers).
Colour scheme: Chrome flag \`--blink-settings=preferredColorScheme=0\` (dark) or \`=1\` (light). The
"ground" column is the top-left pixel of Lighthouse's final screenshot (\`<name>.jpg\` beside this
file), expected light rgb(${SURFACE.light}) and dark rgb(${SURFACE.dark}).
SEO: \`is-crawlable\` fails on purpose (X-Robots-Tag: noindex until launch).

${table(header, body)}
${problems.length ? `\n## Problems\n\n${problems.map((p) => `- ${p}`).join('\n')}\n` : '\nNo problems: accessibility 100 everywhere, SEO fails only the expected is-crawlable, every run in the intended scheme.\n'}`;
writeFileSync(join(out, 'summary.md'), md);
writeFileSync(join(out, 'summary.json'), JSON.stringify({ rows, problems }, null, 1));
console.log(md);
console.log(`wrote ${out}/summary.md, summary.json and one <page>-<form>-<scheme>.json/.jpg per run`);
process.exit(problems.length ? 1 : 0);
