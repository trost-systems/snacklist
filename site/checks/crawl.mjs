// Usage: node crawl.mjs [distDir] [--port 57620] [--pages /de,/en (check only these, no crawl)]
// Serves dist with scripts/preview.mjs (vercel.json's CSP, redirects, cleanUrls) and crawls every
// page reachable from /de and /en, plus / and a missing path, in Chromium at 390 and 1440 px,
// light and dark, under prefers-reduced-motion: reduce. One more run per page at 1440 light with
// motion allowed checks what demo.js loads once videos play. README.md lists what each run proves.
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { AXE_PATH, RUNS, VIEWPORTS, contrast, groupProblems, pageKit, parseArgs, runName, serve, table } from './lib.mjs';

const { dist, port, pages: only } = parseArgs({ port: 57620 });
const { origin, close } = await serve(dist, port);
const MISSING = '/gibt-es-nicht';
const FONTS = ['Bricolage Grotesque', 'Inter'];
const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];
const MOTION_RUN = { width: 1440, scheme: 'light', motion: true };

const browser = await chromium.launch();
const problems = [];
const report = (page, run, check, selector, message) => problems.push({ page, run: run.motion ? '1440 light motion' : runName(run), check, selector, message });
const files = new Set();
// What the runs measured, so a pass is not a check that found nothing to look at.
const stats = { 'tab stops': 0, 'targets': 0, 'hex presses': 0, 'videos': 0 };

async function newPage(run) {
  const ctx = await browser.newContext({
    viewport: VIEWPORTS[run.width],
    colorScheme: run.scheme,
    reducedMotion: run.motion ? 'no-preference' : 'reduce',
  });
  await ctx.addInitScript(pageKit);
  await ctx.addInitScript(() => {
    window.__csp = [];
    document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(`${e.violatedDirective} blocked ${e.blockedURI || 'inline'} (${e.sourceFile || ''}:${e.lineNumber || ''})`));
  });
  await ctx.addInitScript({ path: AXE_PATH });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => {
    // Chromium logs the missing path's own 404 document as a console error.
    if (m.location().url === origin + MISSING && /status of 404/.test(m.text())) return;
    if (m.type() === 'error' || /Content.Security.Policy/i.test(m.text())) errors.push(['console', m.text()]);
  });
  page.on('pageerror', (e) => errors.push(['page error', String(e)]));
  page.on('requestfailed', (r) => {
    // A paused or replaced <video> aborts its own range request; that is not a failure.
    if (r.resourceType() === 'media' && /ERR_ABORTED/.test(r.failure()?.errorText ?? '')) return;
    errors.push(['request', `failed ${r.url()} ${r.failure()?.errorText ?? ''}`]);
  });
  page.on('request', (r) => { if (!r.url().startsWith(origin) && !r.url().startsWith('data:')) errors.push(['request', `off-origin ${r.url()}`]); });
  page.on('response', (r) => {
    if (r.status() >= 400 && !(new URL(r.url()).pathname === MISSING && r.request().isNavigationRequest())) errors.push(['request', `HTTP ${r.status()} ${r.url()}`]);
  });
  return { ctx, page, errors };
}

async function settle(page) {
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.race([
    Promise.all(document.getAnimations().map((a) => a.finished.catch(() => {}))),
    new Promise((r) => setTimeout(r, 1500)),
  ]));
}

// Crawl: collect same-origin pages and linked files from /de, /en, / and a missing path.
const pages = [];
{
  const queue = only ? [...only] : ['/de', '/en', '/', MISSING];
  const seen = new Set();
  const { ctx, page } = await newPage({ width: 1440, scheme: 'light' });
  while (queue.length) {
    const path = queue.shift();
    if (seen.has(path)) continue;
    seen.add(path);
    if (/\.[a-z0-9]+$/i.test(path)) { files.add(path); continue; }
    const resp = await page.goto(origin + path, { waitUntil: 'networkidle' });
    const final = new URL(page.url()).pathname;
    if (path === MISSING) {
      if (resp.status() !== 404) report(path, { width: 1440, scheme: 'light' }, 'crawl', 'document', `missing path answered HTTP ${resp.status()}, expected 404`);
    } else if (resp.status() !== 200) report(path, { width: 1440, scheme: 'light' }, 'crawl', 'document', `HTTP ${resp.status()}`);
    if (path === '/' && !['/de', '/en'].includes(final)) report(path, { width: 1440, scheme: 'light' }, 'crawl', 'document', `/ ended on ${final}, expected /de or /en`);
    if (final !== path) { if (!only) queue.push(final); continue; }
    pages.push(path);
    if (only) continue;
    for (const href of await page.$$eval('a[href], link[href], img[src], source[srcset], video[poster], track[src]', (els) => els.map((e) => e.href || e.src || e.srcset || e.poster))) {
      const u = new URL(href, origin);
      if (u.origin === origin) queue.push(u.pathname);
    }
  }
  await ctx.close();
}
for (const path of files) {
  const r = await fetch(origin + path);
  if (r.status !== 200) report(path, { width: 1440, scheme: 'light' }, 'crawl', 'file', `linked file answered HTTP ${r.status}`);
}

// One run of one page: everything the README lists for crawl.mjs.
async function check(path, run) {
  const { ctx, page, errors } = await newPage(run);
  await page.goto(origin + path, { waitUntil: 'networkidle' });
  await settle(page);
  const r = (check, selector, message) => report(path, run, check, selector, message);

  // Scroll every demo into view so demo.js gets to start (or not start) its video, and read the
  // video's state there: in view it plays only with motion allowed, out of view it pauses.
  for (const demo of await page.locator('[data-demo], video').all()) {
    await demo.scrollIntoViewIfNeeded();
    await page.waitForTimeout(600);
    const inView = await demo.evaluate((el) => {
      const v = el.matches('video') ? el : el.querySelector('video');
      return v ? { selector: window.__kit.sel(v), playing: !v.paused } : null;
    });
    if (!inView) continue;
    stats.videos++;
    if (run.motion && !inView.playing) r('motion', inView.selector, 'demo video does not play in view with motion allowed');
    if (!run.motion && inView.playing) r('motion', inView.selector, 'video plays in view under reduced motion');
    if (run.motion) {
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(600);
      if (await demo.evaluate((el) => !(el.matches('video') ? el : el.querySelector('video')).paused)) {
        r('motion', inView.selector, 'demo video keeps playing out of view');
      }
    }
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForLoadState('networkidle');
  for (const v of await page.evaluate(() => window.__csp)) r('csp', 'document', v);
  for (const [kind, msg] of errors) r(kind === 'request' ? 'request' : 'console', 'document', msg);

  if (!run.motion) {
    const fonts = await page.evaluate((families) => families.map((f) => ({
      f,
      check: document.fonts.check(`16px "${f}"`),
      faces: [...document.fonts].filter((x) => x.family.replace(/"/g, '') === f).map((x) => x.status),
    })), FONTS);
    for (const { f, check, faces } of fonts) {
      if (!faces.length) r('fonts', 'document', `no @font-face for ${f}`);
      else if (!check || !faces.includes('loaded')) r('fonts', 'document', `${f} not loaded (${faces.join(', ')})`);
    }

    const over = await page.evaluate(() => {
      const out = [];
      const sw = document.documentElement.scrollWidth - innerWidth;
      if (sw > 0) out.push({ selector: 'html', message: `page scrolls sideways by ${sw}px` });
      // body has overflow-x: clip, which hides a sideways scroll; text past the edge is still cut.
      for (const e of document.body.querySelectorAll('*')) {
        if (![...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) continue;
        const b = e.getBoundingClientRect();
        if (b.width === 0 || getComputedStyle(e).visibility === 'hidden') continue;
        if (b.right > innerWidth + 1 || b.left < -1) {
          const clipped = (() => {
            for (let a = e.parentElement; a && a !== document.body; a = a.parentElement) if (getComputedStyle(a).overflowX !== 'visible') return true;
            return false;
          })();
          if (!clipped && !e.closest('.skip')) out.push({ selector: window.__kit.sel(e), message: `text box spans ${Math.round(b.left)}..${Math.round(b.right)}px, viewport ${innerWidth}px` });
        }
      }
      return out;
    });
    for (const o of over) r('overflow', o.selector, o.message);

    const axe = await page.evaluate(async (tags) => {
      const res = await window.axe.run(document, { runOnly: { type: 'tag', values: tags }, resultTypes: ['violations'] });
      return res.violations.flatMap((v) => v.nodes.map((n) => ({ id: v.id, selector: n.target.join(' '), message: `${v.id}: ${(n.failureSummary ?? v.help).replace(/\s+/g, ' ').slice(0, 220)}` })));
    }, AXE_TAGS);
    for (const v of axe) r('axe', v.selector, v.message);

    const targets = await page.evaluate(() => {
      const out = [];
      let n = 0;
      const inText = (e) => getComputedStyle(e).display === 'inline'
        && [...e.parentElement.childNodes].some((n) => n !== e && n.textContent.trim());
      for (const e of document.querySelectorAll('a[href], button, input, select, textarea, summary, [role="button"], [tabindex]:not([tabindex="-1"])')) {
        const b = e.getBoundingClientRect();
        if (b.width <= 1 || b.height <= 1 || e.closest('[hidden]') || inText(e)) continue;
        n++;
        const control = e.matches('button, input, select, textarea, summary, [role="button"], .hex, .link-strong') || e.closest('nav, header, footer');
        const min = control ? 48 : 24;
        if (b.width < min - 0.5 || b.height < min - 0.5) {
          out.push({ selector: window.__kit.sel(e), message: `target ${b.width.toFixed(0)}x${b.height.toFixed(0)} < ${min}px (${control ? 'button or nav, 48 px rule' : 'standalone link, WCAG 2.5.8'}) "${window.__kit.label(e)}"` });
        }
      }
      return { out, n };
    });
    stats.targets += targets.n;
    for (const t of targets.out) r('target', t.selector, t.message);

    const motion = await page.evaluate(() => [
      ...document.getAnimations().filter((a) => a.playState === 'running' && Number(a.effect?.getComputedTiming().duration) > 1)
        .map((a) => ({ selector: a.effect.target ? window.__kit.sel(a.effect.target) : '?', message: `${a.constructor.name} ${a.animationName ?? a.transitionProperty ?? ''} running under reduced motion` })),
      ...[...document.querySelectorAll('video')].filter((v) => !v.paused).map((v) => ({ selector: window.__kit.sel(v), message: 'video plays under reduced motion' })),
    ]);
    for (const m of motion) r('motion', m.selector, m.message);

    for (const f of await focusProblems(page)) r('focus', f.selector, f.message);
    for (const p of await pressProblems(page)) r('press', p.selector, p.message);
  }
  await ctx.close();
}

const shot = async (page, box) => PNG.sync.read(await page.screenshot({ clip: box, animations: 'disabled', caret: 'hide' }));

// Tab through the page. At each stop compare the element's surroundings focused and blurred: the
// indicator must change at least one perimeter's worth of pixels by 3:1 or more (WCAG 2.4.13's
// area, the 2.4.11 / 1.4.11 contrast), and the element must match :focus-visible.
async function focusProblems(page) {
  const out = [];
  await page.mouse.move(0, 0);
  await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0); });
  const seen = new Set();
  for (let i = 0; i < 150; i++) {
    await page.keyboard.press('Tab');
    const info = await page.evaluate(() => {
      const e = document.activeElement;
      if (!e || e === document.body) return null;
      e.scrollIntoView({ block: 'center', behavior: 'instant' });
      return { selector: window.__kit.sel(e), label: window.__kit.label(e), visible: e.matches(':focus-visible') };
    });
    if (!info || seen.has(info.selector)) break;
    seen.add(info.selector);
    stats['tab stops']++;
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const el = page.locator(info.selector).first();
    const b = await el.boundingBox();
    if (!b) { out.push({ selector: info.selector, message: `focused but has no box "${info.label}"` }); continue; }
    if (!info.visible) out.push({ selector: info.selector, message: `not :focus-visible after Tab "${info.label}"` });
    const vp = page.viewportSize();
    const pad = 8;
    const x = Math.max(0, Math.floor(b.x - pad)); const y = Math.max(0, Math.floor(b.y - pad));
    const box = { x, y, width: Math.min(vp.width - x, Math.ceil(b.width + 2 * pad)), height: Math.min(vp.height - y, Math.ceil(b.height + 2 * pad)) };
    if (box.width < 2 || box.height < 2) { out.push({ selector: info.selector, message: `focused element is off screen "${info.label}"` }); continue; }
    const focused = await shot(page, box);
    await page.evaluate(() => document.activeElement.blur());
    const blurred = await shot(page, box);
    await el.evaluate((e) => e.focus({ focusVisible: true, preventScroll: true }));
    let changed = 0;
    for (let p = 0; p < focused.data.length; p += 4) {
      const a = [focused.data[p], focused.data[p + 1], focused.data[p + 2]];
      const c = [blurred.data[p], blurred.data[p + 1], blurred.data[p + 2]];
      if (contrast(a, c) >= 3) changed++;
    }
    const perimeter = 2 * (Math.min(b.width, box.width) + Math.min(b.height, box.height));
    if (changed < perimeter) out.push({ selector: info.selector, message: `focus indicator changes ${changed} px by >= 3:1, needs ${Math.round(perimeter)} (its perimeter) "${info.label}"` });
  }
  if (!seen.size) out.push({ selector: 'document', message: 'Tab reached no control' });
  await page.evaluate(() => document.activeElement?.blur());
  return out;
}

// .hex:active sinks the face by the control's edge (--d, --hl-depth-edge): measure .face's box
// with the mouse up and down, the mouse leaving before release so no link is followed.
async function pressProblems(page) {
  const out = [];
  const hexes = await page.locator('.hex:has(> .face)').all();
  for (const el of hexes) {
    if (!(await el.isVisible())) continue;
    const selector = await el.evaluate((e) => window.__kit.sel(e));
    await el.scrollIntoViewIfNeeded();
    await page.mouse.move(0, 0);
    const face = el.locator('> .face');
    stats['hex presses']++;
    const before = (await face.boundingBox()).y;
    const d = await el.evaluate((e) => parseFloat(getComputedStyle(e).getPropertyValue('--d')));
    const box = await el.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    let down = before;
    for (let t = 0; t < 20 && Math.abs(down - before - d) > 0.5; t++) {
      await page.waitForTimeout(25);
      down = (await face.boundingBox()).y;
    }
    await page.mouse.move(0, 0);
    await page.mouse.up();
    await page.waitForTimeout(50);
    const up = (await face.boundingBox()).y;
    if (!(d > 0)) out.push({ selector, message: `--d is ${d}, expected the 4px edge` });
    else if (Math.abs(down - before - d) > 0.5) out.push({ selector, message: `face moved ${(down - before).toFixed(1)}px on press, expected its edge ${d}px` });
    if (Math.abs(up - before) > 0.5) out.push({ selector, message: `face did not return after release (${(up - before).toFixed(1)}px)` });
  }
  return out;
}

for (const path of pages) {
  for (const run of [...RUNS, MOTION_RUN]) await check(path, run);
  console.error(`checked ${path}`);
}
await browser.close();
await close();

const runs = [...RUNS.map(runName), '1440 light motion'];
const count = (page, run) => problems.filter((p) => p.page === page && p.run === run).length;
console.log(`\n${pages.length} pages, ${files.size} linked files, ${runs.length} runs per page\n`);
console.log(table(['page', ...runs], [...pages, ...new Set(problems.map((p) => p.page).filter((p) => !pages.includes(p)))].map((page) => [page, ...runs.map((run) => count(page, run))])));
const grouped = groupProblems(problems);
const checks = [...new Set(grouped.map((g) => g.check))];
console.log(`\nmeasured over all reduced-motion runs: ${Object.entries(stats).map(([k, v]) => `${v} ${k}`).join(', ')}`);
console.log(`\nby check: ${checks.map((c) => `${c} ${grouped.filter((g) => g.check === c).length}`).join(', ') || 'none'}`);
if (grouped.length) {
  console.log(`\n${grouped.length} distinct problem(s):`);
  for (const g of grouped) console.log(`- ${g.page} [${g.check}] ${g.selector}: ${g.message} (${g.runs.length === runs.length ? 'all runs' : g.runs.join(', ')})`);
  process.exit(1);
}
console.log('\nall pages pass');
