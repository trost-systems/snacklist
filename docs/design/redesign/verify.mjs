// Round RD's checks: renders every option × frame × light/dark × 100/200/310 % × English/German in Chromium, measures
// each phone (measure.js), and fails on a tap target under 44 px, text under its WCAG contrast, a control border under
// 3:1, text cut, off the screen or over other text, a colour that is not today's palette, or a list with too few rows.
// It also checks strings.js and palette.css against the app, the RECOMMENDATION tables against the measurements, and
// writes screenshots with --shots.
// Usage: node verify.mjs [--write] [--shots <dir>] [<root> --path <dir under root>]
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './tools/serve.mjs';
import { generate as genStrings } from './tools/strings.mjs';
import { generate as genPalette, readTokens } from './tools/palette.mjs';
import { frames, ids, options } from './options.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : null);
const pathArg = opt('--path') ?? '/docs/design/redesign/';
const rootArg = args.find((a, i) => !a.startsWith('--') && !['--path', '--shots'].includes(args[i - 1]));
const root = resolve(rootArg ?? join(here, '../../..'));
const dir = join(root, pathArg);
const write = args.includes('--write');
const shots = opt('--shots');
const pwDir = [join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');

let n = 0;
const fails = [];
const check = (ok, what) => {
  n += 1;
  if (!ok) {
    fails.push(what);
    if (fails.length <= 60) console.log(`FAIL ${what}`);
  }
};

const repo = [root, join(here, '../../..'), process.cwd()].find((d) => existsSync(join(d, 'app/l10n')));
check(readFileSync(join(dir, 'strings.js'), 'utf8') === genStrings(join(repo, 'app/l10n')), 'strings.js equals the ARB files (node tools/strings.mjs)');
const dart = readFileSync(join(repo, 'app/lib/design/tokens.g.dart'), 'utf8');
check(readFileSync(join(dir, 'palette.css'), 'utf8') === genPalette(dart), 'palette.css equals tokens.g.dart (node tools/palette.mjs)');
const tokens = readTokens(dart);
const palette = { light: Object.values(tokens.light), dark: Object.values(tokens.dark) };

const themes = ['light', 'dark'];
const sizes = [1, 2, 3.1];
const langs = ['en', 'de'];
const jobs = [];
for (const o of options) for (const f of frames) for (const th of themes) for (const ts of sizes) for (const lang of langs) jobs.push({ id: o.id, f, th, ts, lang });

const { server, url } = await serve(root);
const browser = await chromium.launch();
const results = {};
const errors = [];
const worker = async (slice) => {
  const page = await browser.newPage({ viewport: { width: 400, height: 860 } });
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${url}${pathArg}rd/?solo=1`);
  await page.waitForSelector('body[data-ready="1"]', { state: 'attached' });
  for (const j of slice) {
    const m = await page.evaluate(([a, b, c, d, e, p]) => globalThis.show(a, b, c, d, e, p), [j.id, j.f, j.th, j.ts, j.lang, palette[j.th]]);
    results[`${j.id}/${j.f}/${j.th}/${j.ts}/${j.lang}`] = m;
    if (shots && j.lang === (j.ts === 1 && j.th === 'light' ? j.lang : 'en') && (j.ts !== 2)) {
      const name = `${j.id}-${j.f}-${j.th}-${Math.round(j.ts * 100)}-${j.lang}.png`;
      if (j.lang === 'en' || (j.f === 'list' && j.th === 'light' && j.ts === 1)) await page.locator('.phone').screenshot({ path: join(shots, name) });
    }
  }
  await page.close();
};
if (shots) mkdirSync(shots, { recursive: true });
const lanes = 6;
await Promise.all(Array.from({ length: lanes }, (_, k) => worker(jobs.filter((_, i) => i % lanes === k))));
await browser.close();
server.close();
check(errors.length === 0, `no page errors (${errors.slice(0, 3).join('; ')})`);

for (const [key, m] of Object.entries(results)) {
  const [id, f, th, ts] = key.split('/');
  check(m.smallTaps.length === 0, `${key}: tap targets ≥ 44 px (${m.smallTaps.slice(0, 3).join('; ')})`);
  check(m.lowText.length === 0, `${key}: text contrast (${m.lowText.slice(0, 3).join('; ')})`);
  check(m.lowUi.length === 0, `${key}: border contrast ≥ 3 (${m.lowUi.slice(0, 3).join('; ')})`);
  check(m.overflow.length === 0, `${key}: no text cut, off screen or overlapping (${m.overflow.slice(0, 3).join('; ')})`);
  check(m.offPalette.length === 0, `${key}: only palette colours (${m.offPalette.slice(0, 3).join('; ')})`);
  if (f === 'list') check(m.rows >= (Number(ts) === 1 ? 5 : 1), `${key}: ${m.rows} whole rows (need ${Number(ts) === 1 ? 5 : 1})`);
  check(m.minTap !== null, `${key}: something tappable is measured`);
  if (id && th) check(true, 'counted');
}

const min = (xs) => Math.min(...xs.filter((x) => x !== null));
const summary = {};
for (const id of ids) {
  const of = (pred) => Object.entries(results).filter(([k]) => k.startsWith(`${id}/`) && pred(k.split('/'))).map(([, m]) => m);
  const uiOf = (th) => { const v = of(([, , t]) => t === th).map((m) => m.ui).filter((x) => x !== null); return v.length ? Math.min(...v) : null; };
  summary[id] = {
    rows100: results[`${id}/list/light/1/en`].rows,
    rows310: results[`${id}/list/light/3.1/en`].rows,
    rows100de: results[`${id}/list/light/1/de`].rows,
    minTap: min(of(() => true).map((m) => m.minTap)),
    contrastLight: min(of(([, , t]) => t === 'light').map((m) => m.contrast)),
    contrastDark: min(of(([, , t]) => t === 'dark').map((m) => m.contrast)),
    uiLight: uiOf('light'),
    uiDark: uiOf('dark'),
    overflow310: of(([, , , ts]) => ts === '3.1').reduce((a, m) => a + m.overflow.length, 0),
    broken310: of(([, , th, ts]) => ts === '3.1' && th === 'light').reduce((a, m) => a + m.broken.length, 0),
    brokenList310: results[`${id}/list/light/3.1/de`].broken.length + results[`${id}/list/light/3.1/en`].broken.length,
    offPalette: of(() => true).reduce((a, m) => a + m.offPalette.length, 0),
  };
}

// The recommendation's tables quote these numbers: each option's row, cell by cell.
const cells = (md, id) => {
  const line = md.split('\n').find((l) => l.startsWith(`| ${id} `) || l.startsWith(`| **${id}`));
  return line ? line.split('|').slice(1, -1).map((c) => c.trim().replace(/\*\*/g, '')) : null;
};
for (const [file, todayName] of [['RECOMMENDATION.md', 'Today'], ['RECOMMENDATION.de.md', 'Heute']]) {
  const p = join(dir, 'rd', file);
  if (!existsSync(p)) { check(false, `${file} exists`); continue; }
  const md = readFileSync(p, 'utf8').split('<!-- table -->')[1]?.split('<!-- /table -->')[0] ?? '';
  for (const id of ids) {
    const c = cells(md, id === 'today' ? todayName : id);
    const sm = summary[id];
    if (!c) { check(false, `${file}: a table row for ${id}`); continue; }
    const num = (x) => x.replaceAll(',', '.');
    check(c[2] === String(sm.rows100), `${file} ${id}: rows at 100 % ${c[2]} = ${sm.rows100}`);
    check(c[3] === String(sm.rows310), `${file} ${id}: rows at 310 % ${c[3]} = ${sm.rows310}`);
    check(num(c[4]) === `${sm.minTap} px`, `${file} ${id}: smallest target ${c[4]} = ${sm.minTap} px`);
    check(num(c[5]) === `${sm.contrastLight} / ${sm.contrastDark}`, `${file} ${id}: text contrast ${c[5]} = ${sm.contrastLight} / ${sm.contrastDark}`);
    check(num(c[6]) === `${sm.uiLight ?? '–'} / ${sm.uiDark ?? '–'}`, `${file} ${id}: border contrast ${c[6]} = ${sm.uiLight} / ${sm.uiDark}`);
    check(c[7] === String(sm.overflow310), `${file} ${id}: overflows at 310 % ${c[7]} = ${sm.overflow310}`);
    check(c[8] === String(sm.broken310), `${file} ${id}: broken words at 310 % ${c[8]} = ${sm.broken310}`);
  }
}

const measuredPath = join(dir, 'rd', 'measured.json');
const out = { phone: '390 × 844 iPhone screen (status bar 47, home indicator 34)', checks: n, summary, frames: results };
if (write) {
  writeFileSync(measuredPath, `${JSON.stringify(out, null, 1)}\n`);
  console.log(`wrote ${measuredPath}`);
} else {
  const old = existsSync(measuredPath) ? JSON.parse(readFileSync(measuredPath, 'utf8')) : null;
  check(old && JSON.stringify(old.summary) === JSON.stringify(summary), 'rd/measured.json summary equals this run (node verify.mjs --write)');
}
console.log(JSON.stringify(summary));
if (fails.length) {
  console.log(`${fails.length} of ${n} checks failed`);
  process.exit(1);
}
console.log(`all checks passed (${n})`);
