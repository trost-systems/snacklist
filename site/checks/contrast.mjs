// Usage: node contrast.mjs [distDir] [--port 57621] [--pages /de,/en,...]
// Text and non-text contrast of the landing pages, a guide, a changelog and a legal page, light
// and dark at 390 and 1440 px. Text: axe's color-contrast rule with background images removed
// (the blocks' hex clusters, paper textures), and the pixels for nodes axe cannot decide. Non-text:
// each hex control's contour and edge against the block around it, and every focus indicator's
// ring colour against what surrounds it, both read from computed styles. README.md has the rules.
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { AXE_PATH, RUNS, VIEWPORTS, contrast, pageKit, parseArgs, parseRgb, runName, serve, table } from './lib.mjs';

const { dist, port, pages: only } = parseArgs({ port: 57621 });
const PAGES = only ?? ['/de', '/en', '/de/anleitungen/siri-kurzbefehl', '/en/changelog', '/datenschutz'];
const { origin, close } = await serve(dist, port);
const browser = await chromium.launch();
const axeSource = readFileSync(AXE_PATH, 'utf8');
const fmt = (n) => n.toFixed(2);
const hex = (rgb) => `#${rgb.slice(0, 3).map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`;

const summary = [];
const textPairs = new Map();
const nonText = new Map();
const fails = [];

function addPair(map, key, row) {
  const prev = map.get(key);
  if (!prev) map.set(key, { ...row, runs: new Set([row.run]), n: 1 });
  else {
    prev.n++;
    prev.runs.add(row.run);
    if (row.ratio < prev.ratio) Object.assign(prev, { ratio: row.ratio, sample: row.sample, page: row.page });
  }
}

for (const path of PAGES) {
  for (const run of RUNS) {
    // bypassCSP: this pass injects a stylesheet; crawl.mjs checks the CSP.
    const ctx = await browser.newContext({ viewport: VIEWPORTS[run.width], colorScheme: run.scheme, reducedMotion: 'reduce', bypassCSP: true });
    await ctx.addInitScript(pageKit);
    const p = await ctx.newPage();
    await p.goto(origin + path, { waitUntil: 'networkidle' });
    await p.evaluate(() => document.fonts.ready);
    await p.addScriptTag({ content: axeSource });
    // No transitions: a colour restored after measuring one node must not still be fading back
    // when the next node, its child, is read.
    await p.addStyleTag({ content: '*, *::before, *::after { background-image: none !important; transition: none !important; }' });
    const name = `${path} ${runName(run)}`;

    const axe = await p.evaluate(async () => {
      const res = await window.axe.run(document, { runOnly: { type: 'rule', values: ['color-contrast'] } });
      const msg = (n) => `${n.target.join(' ')}: ${(n.any[0]?.message ?? '').slice(0, 140)}`;
      const textual = (n) => !/non-text|too short|pseudo|no text/i.test(n.any[0]?.message ?? '');
      return {
        passes: res.passes.flatMap((v) => v.nodes.map((n) => ({ sel: n.target.join(' '), ...n.any[0]?.data }))),
        violations: res.violations.flatMap((v) => v.nodes.map(msg)),
        incomplete: res.incomplete.flatMap((v) => v.nodes.filter(textual).map((n) => n.target[0])),
      };
    });
    for (const n of axe.passes) {
      if (!n.contrastRatio) continue;
      const min = Number(n.expectedContrastRatio?.replace(':1', '') ?? 4.5);
      addPair(textPairs, `${n.fgColor} on ${n.bgColor} >=${min}`, { fg: n.fgColor, bg: n.bgColor, min, ratio: n.contrastRatio, sample: n.sel, page: path, run: run.scheme });
    }
    for (const v of axe.violations) fails.push(`${name} text (axe): ${v}`);

    const measured = [];
    for (const sel of axe.incomplete) {
      const info = await p.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (!el || !el.getClientRects().length) return null;
        el.scrollIntoView({ block: 'center', behavior: 'instant' });
        for (const x of document.querySelectorAll('body *')) {
          const pos = getComputedStyle(x).position;
          if ((pos === 'fixed' || pos === 'sticky') && !x.contains(el)) x.setAttribute('data-cr-hidden', '');
        }
        for (const x of document.querySelectorAll('[data-cr-hidden]')) x.style.visibility = 'hidden';
        const cs = getComputedStyle(el);
        const svg = el instanceof SVGElement;
        const color = svg ? cs.fill : cs.color;
        const size = parseFloat(cs.fontSize); const weight = Number(cs.fontWeight);
        for (const k of ['color', '-webkit-text-fill-color', 'text-decoration-color', ...(svg ? ['fill'] : [])]) el.style.setProperty(k, 'transparent', 'important');
        el.style.setProperty('text-shadow', 'none', 'important');
        const r = el.getBoundingClientRect();
        return { color, large: size >= 24 || (size >= 18.66 && weight >= 700), rect: { x: Math.max(0, r.x), y: Math.max(0, r.y), width: Math.max(1, Math.min(r.width, innerWidth - Math.max(0, r.x))), height: Math.max(1, Math.min(r.height, innerHeight - Math.max(0, r.y))) } };
      }, sel);
      if (!info) continue;
      const png = PNG.sync.read(await p.screenshot({ clip: info.rect }));
      await p.evaluate((sel) => {
        const el = document.querySelector(sel);
        for (const k of ['color', '-webkit-text-fill-color', 'text-shadow', 'text-decoration-color', 'fill']) el.style.removeProperty(k);
        for (const x of document.querySelectorAll('[data-cr-hidden]')) { x.style.visibility = ''; x.removeAttribute('data-cr-hidden'); }
      }, sel);
      const [tr, tg, tb, ta = 1] = parseRgb(info.color) ?? [0, 0, 0, 1];
      const ratios = [];
      for (let i = 0; i < png.data.length; i += 4) {
        const bg = [png.data[i], png.data[i + 1], png.data[i + 2]];
        ratios.push(contrast([tr, tg, tb].map((c, k) => c * ta + bg[k] * (1 - ta)), bg));
      }
      ratios.sort((a, b) => a - b);
      const median = ratios[Math.floor(ratios.length / 2)]; const p10 = ratios[Math.floor(ratios.length / 10)];
      const min = info.large ? 3 : 4.5;
      measured.push({ sel, median, p10, min });
      if (median < min) fails.push(`${name} text (pixels): ${sel} median ${fmt(median)} < ${min}`);
    }

    // Non-text, from computed colours. A hex control's contour (.face::before) and its face
    // (.face::after) against the block it sits on: the control's boundary needs 3:1 from one of
    // them (WCAG 1.4.11), the contour on light grounds, the honey face on dark ones. Then every
    // focusable element's ring, focused with focus-visible, against the ground outside the ring.
    const ui = await p.evaluate(() => {
      const out = [];
      const bgOf = (e) => window.__kit.bgBehind(e);
      for (const el of document.querySelectorAll('.hex:has(> .face)')) {
        if (!el.getClientRects().length) continue;
        const ground = bgOf(el.parentElement);
        const face = el.querySelector(':scope > .face');
        out.push({ kind: 'hex contour', sel: window.__kit.sel(el), fg: getComputedStyle(face, '::before').backgroundColor, bg: ground.color, ground: ground.sel });
        out.push({ kind: 'hex face', sel: window.__kit.sel(el), fg: getComputedStyle(face, '::after').backgroundColor, bg: ground.color, ground: ground.sel });
      }
      for (const el of document.querySelectorAll('a[href], button, summary, input, select, textarea, [tabindex]:not([tabindex="-1"])')) {
        if (!el.getClientRects().length || el.closest('[hidden]')) continue;
        el.focus({ focusVisible: true, preventScroll: true });
        if (document.activeElement !== el) continue;
        const s = getComputedStyle(el);
        const ground = bgOf(el.parentElement);
        const shadows = [...s.filter.matchAll(/drop-shadow\((rgba?\([^)]+\))/g)].map((m) => m[1]);
        const visible = (c) => c && !/^rgba\([^)]*,\s*0\)$/.test(c) && c !== 'transparent';
        if (shadows.length) {
          // .hex: four drop shadows in the gap colour, then four in the ring colour.
          out.push({ kind: 'focus ring (hex)', sel: window.__kit.sel(el), fg: shadows.at(-1), bg: ground.color, ground: ground.sel, gap: shadows[0] });
        } else if (s.outlineStyle !== 'none' && visible(s.outlineColor) && parseFloat(s.outlineWidth) > 0) {
          const box = [...s.boxShadow.matchAll(/rgba?\([^)]+\)/g)].map((m) => m[0]).filter(visible);
          // A box-shadow outside the outline (the demo toggle) is the ground the ring sits on.
          out.push({ kind: 'focus outline', sel: window.__kit.sel(el), fg: s.outlineColor, bg: box[0] ?? ground.color, ground: box[0] ? 'its box-shadow' : ground.sel });
        } else {
          out.push({ kind: 'focus (none found)', sel: window.__kit.sel(el), fg: null, bg: ground.color, ground: ground.sel });
        }
        el.blur();
      }
      return out;
    });
    const ratioOf = (u) => (u.fg ? contrast(parseRgb(u.fg), parseRgb(u.bg)) : 0);
    const uiFails = [];
    for (const u of ui) {
      const fg = u.fg && parseRgb(u.fg); const bg = parseRgb(u.bg);
      if (!fg) { uiFails.push(`${u.kind}: ${u.sel} has no ring colour in outline or filter`); continue; }
      const ratio = contrast(fg, bg);
      const gap = u.gap ? contrast(fg, parseRgb(u.gap)) : null;
      addPair(nonText, `${u.kind} ${hex(fg)} on ${hex(bg)}`, { kind: u.kind, fg: hex(fg), bg: hex(bg), ratio, gap, ground: u.ground, sample: u.sel, page: path, run: run.scheme });
      if (u.kind === 'hex contour') {
        const face = ui.find((f) => f.kind === 'hex face' && f.sel === u.sel);
        if (Math.max(ratio, ratioOf(face)) < 3) uiFails.push(`hex boundary: ${u.sel} contour ${fmt(ratio)} and face ${fmt(ratioOf(face))} on ${u.ground} ${hex(bg)}, neither reaches 3`);
      } else if (u.kind !== 'hex face' && ratio < 3) uiFails.push(`${u.kind}: ${u.sel} ${hex(fg)} on ${u.ground} ${hex(bg)} = ${fmt(ratio)} < 3`);
    }
    fails.push(...uiFails.map((f) => `${name} ${f}`));

    const lowest = measured.reduce((a, m) => (!a || m.median < a.median ? m : a), null);
    const minPass = axe.passes.reduce((a, n) => (n.contrastRatio && n.contrastRatio < a ? n.contrastRatio : a), Infinity);
    summary.push([path, runName(run), axe.passes.length, axe.violations.length, Number.isFinite(minPass) ? fmt(minPass) : '-', measured.length, measured.filter((m) => m.median < m.min).length, lowest ? fmt(lowest.median) : '-', measured.filter((m) => m.median >= m.min && m.p10 < m.min).length, uiFails.length]);
    await ctx.close();
  }
  console.error(`measured ${path}`);
}
await browser.close();
await close();

console.log('\nPer page and run (text: axe after removing background images, then pixels for what axe leaves open)\n');
console.log(table(['page', 'run', 'axe pass', 'axe FAIL', 'lowest axe', 'pixel nodes', 'pixel FAIL', 'lowest median', 'mixed bg', 'non-text FAIL'], summary));
const rows = (map, cols) => [...map.values()].sort((a, b) => a.ratio - b.ratio).map(cols);
console.log('\nText colour pairs axe measured (lowest ratio per pair, every page and run)\n');
console.log(table(['fg', 'bg', 'ratio', 'needs', 'nodes', 'schemes', 'lowest at'], rows(textPairs, (r) => [r.fg, r.bg, fmt(r.ratio), r.min, r.n, [...r.runs].join('+'), `${r.page} ${r.sample}`.slice(0, 90)])));
console.log('\nNon-text: hex contour and face vs the block (one of them needs 3:1), focus ring vs the ground outside it (needs 3:1)\n');
console.log(table(['kind', 'fg', 'bg', 'ratio', 'ring vs gap', 'ground', 'n', 'schemes', 'sample'], rows(nonText, (r) => [r.kind, r.fg, r.bg, fmt(r.ratio), r.gap == null ? '-' : fmt(r.gap), r.ground.slice(0, 40), r.n, [...r.runs].join('+'), `${r.page} ${r.sample}`.slice(0, 80)])));
if (fails.length) {
  console.log(`\n${fails.length} failure(s):\n- ${fails.join('\n- ')}`);
  process.exit(1);
}
console.log('\nall text and non-text contrast passes');
