#!/usr/bin/env node
// `--print` prints the rows to paste into meta.ts. Screenshots go to $VERIFY_OUT.

import { createServer } from 'node:http';
import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = resolve(process.env.VERIFY_OUT ?? join(root, 'verify-screenshots', 'fh'));
const PRINT = process.argv.includes('--print');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
};

function startStaticServer() {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    const filePath = join(dist, decodeURIComponent(url.pathname));
    if (!filePath.startsWith(dist)) {
      res.writeHead(403).end();
      return;
    }
    if (statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
      res.writeHead(200, { 'content-type': MIME[extname(filePath)] ?? 'application/octet-stream' });
      res.end(readFileSync(filePath));
      return;
    }
    res.writeHead(200, { 'content-type': MIME['.html'] });
    res.end(readFileSync(join(dist, 'index.html')));
  });
  return new Promise((done) => {
    server.listen(0, '127.0.0.1', () => done({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

async function loadPlaywright() {
  const candidates = ['playwright', resolve(root, '../../../e2e/node_modules/playwright/index.mjs')];
  for (const c of candidates) {
    const loaded = await import(c).catch((e) => (e?.code === 'ERR_MODULE_NOT_FOUND' ? null : Promise.reject(e)));
    if (loaded) return loaded;
  }
  throw new Error('playwright not found: npm ci in e2e/');
}

const failures = [];
const check = (ok, msg) => {
  if (!ok) failures.push(msg);
};

/** store_name_field.dart pins the field at 48 px: at large text it cuts its own text, whatever the option. */
const FIXED_HEIGHT_IN_PRODUCTION = new Set(['field']);
/** Antialiasing moves a control's 3:1 pixel count by a few px between runs; the verdict must match exactly. */
const AREA_TOLERANCE = 0.02;
const CONTRAST_TOLERANCE = 0.2;
const AREA_CELL = /^(pass|FAIL) ([\d.]+)×, ([\d.]+):1$/;

function cellMatches(want, got) {
  const w = AREA_CELL.exec(want ?? '');
  const g = AREA_CELL.exec(got);
  if (!w || !g) return want === got;
  return w[1] === g[1] && Math.abs(Number(w[2]) - Number(g[2])) <= AREA_TOLERANCE && Math.abs(Number(w[3]) - Number(g[3])) <= CONTRAST_TOLERANCE;
}

const OPTIONS = ['today', 'fh1', 'fh2', 'fh3', 'fh4', 'fh5'];
const CODE = { today: 'Today', fh1: 'FH1', fh2: 'FH2', fh3: 'FH3', fh4: 'FH4', fh5: 'FH5' };
const THEMES = ['light', 'dark'];
const LOOKS = ['soft', 'hex'];
const TARGETS = {
  chip: { id: 'chip-REWE', phone: 'phone-stores' },
  chipPicked: { id: 'chip-EDEKA', phone: 'phone-stores' },
  addOwn: { id: 'add-own', phone: 'phone-stores' },
  field: { id: 'field', phone: 'phone-stores' },
  next: { id: 'next', phone: 'phone-stores' },
  skip: { id: 'skip', phone: 'phone-stores' },
  row: { id: 'row-1', phone: 'phone-list' },
};

const LAB = `
  const lum = (r, g, b) => {
    const f = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (a, b) => { const hi = Math.max(a, b), lo = Math.min(a, b); return (hi + 0.05) / (lo + 0.05); };
  async function pixels(b64) {
    const img = new Image();
    img.src = 'data:image/png;base64,' + b64;
    await img.decode();
    const c = new OffscreenCanvas(img.width, img.height);
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    return { w: img.width, h: img.height, d: g.getImageData(0, 0, img.width, img.height).data };
  }
  window.compare = async (a64, b64, box, neighbours, textRects, glyphs64) => {
    const A = await pixels(a64), B = await pixels(b64);
    const reach = { left: 0, right: 0, top: 0, bottom: 0 };
    let area3 = 0, visible = 0, overText = 0;
    const strong = [];
    const into = neighbours.map(() => 0);
    const inside = (x, y, r) => x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
    for (let y = 0; y < A.h; y++) {
      for (let x = 0; x < A.w; x++) {
        const i = (y * A.w + x) * 4;
        const la = lum(A.d[i], A.d[i + 1], A.d[i + 2]);
        const lb = lum(B.d[i], B.d[i + 1], B.d[i + 2]);
        const cr = ratio(la, lb);
        if (cr < 1.1) continue;
        visible++;
        const near = x >= box.x - 16 && x < box.x + box.w + 16 && y >= box.y - 16 && y < box.y + box.h + 16;
        if (near && cr >= 3) { area3++; strong.push(cr); }
        if (y >= box.y && y < box.y + box.h) {
          if (x < box.x) reach.left = Math.max(reach.left, box.x - x);
          if (x >= box.x + box.w) reach.right = Math.max(reach.right, x - (box.x + box.w) + 1);
        }
        if (x >= box.x && x < box.x + box.w) {
          if (y < box.y) reach.top = Math.max(reach.top, box.y - y);
          if (y >= box.y + box.h) reach.bottom = Math.max(reach.bottom, y - (box.y + box.h) + 1);
        }
        neighbours.forEach((n, k) => { if (inside(x, y, n)) into[k]++; });
      }
    }
    strong.sort((p, q) => p - q);
    if (glyphs64) {
      const G = await pixels(glyphs64);
      overText = 0;
      for (let y = box.y; y < box.y + box.h; y++) {
        for (let x = box.x; x < box.x + box.w; x++) {
          const i = (y * A.w + x) * 4;
          const la = lum(A.d[i], A.d[i + 1], A.d[i + 2]);
          const glyph = ratio(la, lum(G.d[i], G.d[i + 1], G.d[i + 2])) >= 1.5;
          const mark = ratio(la, lum(B.d[i], B.d[i + 1], B.d[i + 2])) >= 1.5;
          if (glyph && mark) overText++;
        }
      }
    }
    return { reach, area3, visible, into, overText, median3: strong.length ? strong[strong.length >> 1] : 0 };
  };
`;

async function main() {
  const { chromium } = await loadPlaywright();
  const { server, base } = await startStaticServer();
  mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch(process.env.VERIFY_CHROME ? { executablePath: process.env.VERIFY_CHROME } : {});
  const page = await browser.newPage({ viewport: { width: 1320, height: 1000 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const lab = await browser.newPage();
  await lab.setContent('<body></body>');
  await lab.addScriptTag({ content: LAB });

  await page.goto(`${base}/focus/fh/?o=today&f=none`);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => 'fh' in window);
  // The page copy above the phones has fractional line heights: a reworded sentence put the phones on a half pixel and
  // every edge antialiased 1 px into its neighbour (390 px "on the next row"). Measure with the phones on whole pixels.
  // The step body is centred, which can put it on a half pixel: top-align it while measuring.
  await page.addStyleTag({ content: '.fh-hero, .fh-controls, .fh-option { display: none !important; } .fh-body { margin: 0 !important; }' });
  const offGrid = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('.fh-phone, .fh-sheet, .fh-phone .fh-ctl')]
        .filter((n) => {
          const r = n.getBoundingClientRect();
          return !Number.isInteger(r.top) || !Number.isInteger(r.left) || !Number.isInteger(r.height);
        })
        .map((n) => n.dataset.testid ?? n.className),
    );

  const settle = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  const set = async (s) => {
    await page.evaluate((s) => window.fh.set(s), s);
    await settle();
    await page.evaluate(() => document.fonts.ready);
    if (s.f) {
      const want = s.f === 'none' ? [] : [TARGETS[s.f].id];
      await page.waitForFunction(
        (want) => {
          const on = [...document.querySelectorAll('.fh-phone [data-focused="true"]')].map((n) => n.dataset.testid);
          return JSON.stringify(on) === JSON.stringify(want);
        },
        want,
      );
    }
    await settle();
  };
  const shot = async (phone) => (await page.getByTestId(phone).screenshot()).toString('base64');

  const geometry = (phone, id) =>
    page.evaluate(
      ({ phone, id }) => {
        const p = document.querySelector(`[data-testid="${phone}"]`).getBoundingClientRect();
        const rel = (r) => ({ x: Math.round(r.left - p.left), y: Math.round(r.top - p.top), w: Math.round(r.width), h: Math.round(r.height) });
        const el = document.querySelector(`[data-testid="${phone}"] [data-testid="${id}"]`);
        const box = rel(el.getBoundingClientRect());
        const all = [...document.querySelectorAll(`[data-testid="${phone}"] .fh-ctl, [data-testid="${phone}"] .fh-icon`)].filter((n) => n !== el);
        const neighbours = all.map((n) => ({ id: n.dataset.testid ?? n.getAttribute('aria-label'), ...rel(n.getBoundingClientRect()) }));
        const outline = el.querySelector('[data-layer="outline"]');
        const perimeter = outline ? outline.getTotalLength() : 0;
        const textRects = [];
        for (const t of el.querySelectorAll('.fh-ctl-body span, .fh-ctl-body input')) {
          if (t.tagName === 'INPUT') {
            textRects.push(rel(t.getBoundingClientRect()));
            continue;
          }
          const range = document.createRange();
          range.selectNodeContents(t);
          for (const r of range.getClientRects()) if (r.width > 0) textRects.push(rel(r));
        }
        const body = el.querySelector('.fh-ctl-body');
        const clipped = [...el.querySelectorAll('.fh-ctl-body *')].some((n) => n.scrollWidth > n.clientWidth + 1 && getComputedStyle(n).overflow !== 'visible')
          || body.scrollWidth > el.clientWidth + 1;
        const scroll = el.closest('.fh-scroll, .fh-footer, .fh-screen');
        const room = rel(scroll.getBoundingClientRect());
        const rects = [...document.querySelectorAll(`[data-testid="${phone}"] .fh-ctl, [data-testid="${phone}"] .fh-heading`)].map((n) => rel(n.getBoundingClientRect()));
        return { box, neighbours, perimeter, textRects, clipped, room, rects };
      },
      { phone, id },
    );

  const sideGaps = (box, neighbours) => {
    const gaps = {};
    const overlapsY = (n) => n.y < box.y + box.h && n.y + n.h > box.y;
    const overlapsX = (n) => n.x < box.x + box.w && n.x + n.w > box.x;
    const pick = (side, list, dist) => {
      const ds = list.map(dist).filter((d) => d >= 0);
      if (ds.length) gaps[side] = Math.min(...ds);
    };
    pick('left', neighbours.filter(overlapsY), (n) => box.x - (n.x + n.w));
    pick('right', neighbours.filter(overlapsY), (n) => n.x - (box.x + box.w));
    pick('top', neighbours.filter(overlapsX), (n) => box.y - (n.y + n.h));
    pick('bottom', neighbours.filter(overlapsX), (n) => n.y - (box.y + box.h));
    return gaps;
  };

  const results = [];
  for (const look of LOOKS) {
    for (const theme of THEMES) {
      for (const o of OPTIONS) {
        for (const [target, t] of Object.entries(TARGETS)) {
          await set({ o, look, theme, text: '100', lang: 'en', f: 'none', open: target === 'field' });
          const before = await geometry(t.phone, t.id).catch(() => null);
          const a = before ? await shot(t.phone) : null;
          await set({ f: target });
          const g = await geometry(t.phone, t.id);
          const b = await shot(t.phone);
          const off = await offGrid();
          check(off.length === 0, `${o} ${look} ${theme} ${target}: off the pixel grid, so edges antialias into neighbours: ${off.join(', ')}`);
          if (look === 'soft' && target !== 'skip') {
            writeFileSync(join(outDir, `${o}-${look}-${theme}-${target}.png`), Buffer.from(b, 'base64'));
          }
          if (!a) {
            failures.push(`${o} ${look} ${theme} ${target}: no unfocused state to compare`);
            continue;
          }
          const shift = Math.max(...g.rects.map((r, i) => {
            const q = before.rects[i];
            return q ? Math.max(Math.abs(r.x - q.x), Math.abs(r.y - q.y), Math.abs(r.w - q.w), Math.abs(r.h - q.h)) : 0;
          }));
          const neighbours = g.neighbours;
          const cmp = await lab.evaluate(([a, b, box, n, tr]) => window.compare(a, b, box, n, tr), [a, b, g.box, neighbours, []]);
          const gaps = sideGaps(g.box, neighbours);
          const focusedGaps = Object.fromEntries(Object.entries(gaps).map(([side, gap]) => [side, gap - cmp.reach[side]]));
          const spill = cmp.into.reduce((s, n) => s + n, 0);
          const need = 2 * g.perimeter;
          const roomCut = cmp.reach.left > g.box.x - g.room.x || cmp.reach.right > g.room.x + g.room.w - (g.box.x + g.box.w);
          results.push({ look, theme, o, target, gaps, focusedGaps, reach: cmp.reach, spill, area3: cmp.area3, need, median3: cmp.median3, shift, roomCut });
        }
      }
    }
  }

  const large = [];
  for (const look of LOOKS) {
    for (const scale of ['200', '310']) {
      for (const lang of ['en', 'de']) {
        for (const o of OPTIONS) {
          for (const [target, t] of Object.entries(TARGETS)) {
            await set({ o, look, theme: 'light', text: scale, lang, f: 'none', open: target === 'field' });
            await page.evaluate(() => document.querySelectorAll('.fh-scroll').forEach((s) => (s.scrollTop = 0)));
            await page.evaluate(({ phone, id }) => document.querySelector(`[data-testid="${phone}"] [data-testid="${id}"]`).scrollIntoView({ block: 'center' }), t);
            const glyphs = await shot(t.phone);
            const style = await page.addStyleTag({ content: '.fh-ctl-body { visibility: hidden !important; } .fh-ctl-body [data-deco] { visibility: visible !important; }' });
            const g0 = await geometry(t.phone, t.id);
            const a = await shot(t.phone);
            await set({ f: target });
            const g = await geometry(t.phone, t.id);
            const b = await shot(t.phone);
            await style.evaluate((n) => n.remove());
            await settle();
            const withText = await geometry(t.phone, t.id);
            const cmp = await lab.evaluate(([a, b, box, n, tr, gl]) => window.compare(a, b, box, n, tr, gl), [a, b, g.box, [], [], glyphs]);
            const fills = o === 'fh3';
            large.push({ look, scale, lang, o, target, clipped: withText.clipped, overText: fills ? null : cmp.overText, moved: JSON.stringify(g0.box) !== JSON.stringify(g.box) });
            if (scale === '310' && look === 'soft' && lang === 'de' && (target === 'field' || target === 'chip' || target === 'row')) {
              writeFileSync(join(outDir, `${o}-${look}-light-${target}-310-de.png`), await page.getByTestId(t.phone).screenshot());
            }
          }
        }
      }
    }
  }

  const sheetShots = [];
  for (const look of LOOKS) {
    for (const theme of THEMES) {
      for (const o of OPTIONS) {
        await set({ o, look, theme, text: '100', lang: 'en', f: 'none' });
        const file = `sheet-${o}-${look}-${theme}.png`;
        writeFileSync(join(outDir, file), await page.locator('.fh-sheet').screenshot());
        sheetShots.push(file);
      }
    }
  }
  for (const lang of ['en', 'de']) {
    await set({ o: 'fh1', look: 'soft', theme: 'light', text: '100', lang, f: 'field' });
    writeFileSync(join(outDir, `page-fh1-${lang}.png`), await page.screenshot({ fullPage: true }));
  }

  for (const r of results) {
    if (r.o === 'today') continue;
    const where = `${r.o} ${r.look} ${r.theme} ${r.target}`;
    check(r.area3 >= r.need, `${where}: ${r.area3} px at 3:1, needs ${Math.round(r.need)} (2 px perimeter)`);
    check(r.shift === 0, `${where}: layout shifts ${r.shift} px on focus`);
    check(!r.roomCut, `${where}: the indicator reaches past its scroll area and is cut`);
    if (r.target === 'row') check(r.spill === 0, `${where}: ${r.spill} px painted onto the neighbouring rows`);
  }
  for (const r of large) {
    if (r.o === 'today') continue;
    const where = `${r.o} ${r.look} ${r.scale}% ${r.lang} ${r.target}`;
    check(!r.moved, `${where}: focus moved the control`);
    if (FIXED_HEIGHT_IN_PRODUCTION.has(r.target)) continue;
    check(!r.clipped, `${where}: a label is clipped`);
    check(r.overText === null || r.overText === 0, `${where}: ${r.overText} indicator px over text`);
  }
  check(errors.length === 0, `page errors: ${errors.join('; ')}`);

  const pick = (o, target, theme = 'light', look = 'soft') => results.find((r) => r.o === o && r.target === target && r.theme === theme && r.look === look);
  const gapCell = (o, target, side) => {
    const r = pick(o, target);
    const u = r.gaps[side];
    const f = r.focusedGaps[side];
    if (u === undefined) return 'n/a';
    return f < 0 ? `${u} → overlaps ${-f}` : `${u} → ${f}`;
  };
  // The smallest area ratio and the smallest median contrast over the six controls, each on its own: naming
  // "the worst control" flipped between two controls whose counts differ by 2 antialiased pixels (review 0).
  const areaCell = (o, theme, look) => {
    const rs = results.filter((r) => r.o === o && r.theme === theme && r.look === look);
    const x = Math.min(...rs.map((r) => r.area3 / r.need));
    const contrast = Math.min(...rs.map((r) => r.median3));
    return `${x >= 1 ? 'pass' : 'FAIL'} ${x.toFixed(2)}×, ${contrast.toFixed(1)}:1`;
  };
  const rowSpill = (o) => {
    const r = pick(o, 'row');
    return r.spill === 0 ? 'none' : `${r.spill} px`;
  };
  const shiftCell = (o) => `${Math.max(...results.filter((r) => r.o === o).map((r) => r.shift))} px`;
  const largeCell = (o) => {
    const rs = large.filter((r) => r.o === o && !FIXED_HEIGHT_IN_PRODUCTION.has(r.target));
    const clipped = rs.filter((r) => r.clipped).length;
    const over = rs.filter((r) => r.overText).reduce((s, r) => s + r.overText, 0);
    return `${clipped} clipped; ${o === 'fh3' ? 'fill under text' : `${over} px over text`}`;
  };
  const rows = OPTIONS.map((o) => [
    CODE[o],
    gapCell(o, 'chip', 'right'),
    gapCell(o, 'field', 'right'),
    gapCell(o, 'field', 'top'),
    gapCell(o, 'next', 'bottom'),
    rowSpill(o),
    areaCell(o, 'light', 'soft'),
    areaCell(o, 'dark', 'soft'),
    areaCell(o, 'light', 'hex'),
    areaCell(o, 'dark', 'hex'),
    shiftCell(o),
    largeCell(o),
  ]);

  writeFileSync(join(outDir, 'measurements.json'), JSON.stringify({ results, large, rows }, null, 2));
  if (PRINT) console.log(JSON.stringify(rows, null, 2));

  const metaSrc = readFileSync(join(root, 'src', 'fh', 'meta.ts'), 'utf8');
  const tableJson = metaSrc.match(/rows: (\[[\s\S]*?\]) as string\[\]\[\]/);
  const table = tableJson ? JSON.parse(tableJson[1].replace(/'/g, '"').replace(/,(\s*[\]}])/g, '$1')) : [];
  rows.forEach((row, i) => {
    const want = table[i];
    const same = want && want.length === row.length && row.every((cell, k) => cellMatches(want[k], cell));
    check(same, `table row ${CODE[OPTIONS[i]]}: page says ${JSON.stringify(want)}, measured ${JSON.stringify(row)}`);
  });

  await browser.close();
  server.close();
  console.log(`[verify-fh] ${results.length} focus states at 100 %, ${large.length} at 200/310 %, ${sheetShots.length} sheets; screenshots in ${outDir}`);
  if (failures.length) {
    console.log(`[verify-fh] FAILED (${failures.length}):\n- ${failures.slice(0, 60).join('\n- ')}`);
    process.exit(1);
  }
  console.log('[verify-fh] passed');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
