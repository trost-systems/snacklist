#!/usr/bin/env node
// Round DM: measures Today and DM1–DM5 in the built sandbox at 390×844, screenshots every option in light and dark,
// German and English, 100/200/310 % text, and exits 1 when a DM option has an action without a visible word, an action
// does the wrong thing, or the table on /add/dm/ (src/dm/meta.ts) differs from what it measured.
// `--print` prints the measured rows as JSON. Screenshots go to $VERIFY_OUT (default verify-screenshots/dm).

import { createServer } from 'node:http';
import { mkdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = resolve(process.env.VERIFY_OUT ?? join(root, 'verify-screenshots', 'dm'));
const PRINT = process.argv.includes('--print');

const OPTIONS = ['today', 'dm1', 'dm2', 'dm3', 'dm4', 'dm5'];
const CODE = { today: 'Today', dm1: 'DM1', dm2: 'DM2', dm3: 'DM3', dm4: 'DM4', dm5: 'DM5' };
const FIXTURES = ['exact', 'count', 'unit', 'unitTyped', 'none', 'long'];
const LANGS = ['de', 'en'];
const THEMES = ['light', 'dark'];
const SCALES = ['100', '200', '310'];

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.txt': 'text/plain; charset=utf-8' };

function startStaticServer() {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    const filePath = join(dist, decodeURIComponent(url.pathname));
    if (!filePath.startsWith(dist)) return void res.writeHead(403).end();
    if (statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
      res.writeHead(200, { 'content-type': MIME[extname(filePath)] ?? 'application/octet-stream' });
      return void res.end(readFileSync(filePath));
    }
    res.writeHead(200, { 'content-type': MIME['.html'] });
    res.end(readFileSync(join(dist, 'index.html')));
  });
  return new Promise((done) => server.listen(0, '127.0.0.1', () => done({ server, base: `http://127.0.0.1:${server.address().port}` })));
}

async function loadPlaywright() {
  for (const c of ['playwright', resolve(root, '../../../e2e/node_modules/playwright/index.mjs')]) {
    const loaded = await import(c).catch((e) => (e?.code === 'ERR_MODULE_NOT_FOUND' ? null : Promise.reject(e)));
    if (loaded) return loaded;
  }
  throw new Error('playwright not found: npm ci in e2e/');
}

const failures = [];
const norm = (t) => t.toLowerCase().replace(/[^\p{L}\p{N}×→]+/gu, ' ').trim();
const check = (ok, msg) => {
  if (!ok) failures.push(msg);
};

/** Runs in the page: the phone of option `o` as the measurements read it. */
function probe(o) {
  const phone = document.querySelector(`[data-testid="phone-${o}"]`);
  const screen = phone.querySelector('[data-testid="dm-screen"]');
  const S = screen.getBoundingClientRect();
  if (S.bottom > window.innerHeight) throw new Error(`phone-${o} ends at ${S.bottom} px, below the ${window.innerHeight} px viewport: hit tests would miss`);
  const owns = (el, x, y) => {
    const hit = document.elementFromPoint(x, y);
    return Boolean(hit && el.contains(hit));
  };
  const rowShown = (row) => {
    const r = row.getBoundingClientRect();
    if (r.height < 1 || r.top < S.top || r.bottom > S.bottom + 0.5) return false;
    const x = r.left + Math.min(60, r.width / 2);
    return owns(row, x, r.top + 4) && owns(row, x, r.bottom - 4);
  };
  const rgb = (c) => (c.match(/[\d.]+/g) ?? []).map(Number);
  const lum = ([r, g, b]) => {
    const f = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const contrast = (el) => {
    const fg = rgb(getComputedStyle(el).color);
    let n = el;
    while (n && (rgb(getComputedStyle(n).backgroundColor)[3] ?? 1) === 0) n = n.parentElement;
    const bg = n ? rgb(getComputedStyle(n).backgroundColor) : [255, 255, 255];
    const [a, b] = [lum(fg), lum(bg)].sort((x, y) => y - x);
    return (a + 0.05) / (b + 0.05);
  };
  const clean = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
  // Production chrome that stays an icon: the grab handle („Schließen“), the clear button and the system keyboard.
  const CHROME = '.dm-grab, .dm-field-btn, .dm-key';
  const unworded = [...screen.querySelectorAll('button, [role="button"], [role="radio"]')]
    .filter((el) => !el.matches(CHROME) && !/[\p{L}\p{N}]/u.test(clean(el.innerText)))
    .map((el) => el.className);
  const actions = [...screen.querySelectorAll('[data-dm-action]')].map((el) => {
    const r = el.getBoundingClientRect();
    const visible = clean(el.innerText);
    const inside = r.top >= S.top - 0.5 && r.bottom <= S.bottom + 0.5 && r.left >= S.left - 0.5 && r.right <= S.right + 0.5;
    return {
      action: el.dataset.dmAction,
      amount: el.dataset.dmAmount ?? null,
      visible,
      worded: /[\p{L}\p{N}]/u.test(visible),
      name: clean(el.getAttribute('aria-label') || el.innerText),
      contrast: Math.min(...[...el.querySelectorAll('[data-text]'), el].filter((t) => t.innerText?.trim()).map(contrast)),
      reachable: inside && owns(el, r.left + r.width / 2, r.top + r.height / 2),
    };
  });
  let clipped = 0;
  for (const el of screen.querySelectorAll('[data-text]')) {
    if (el.closest('.dm-header, .dm-dock')) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 1) continue;
    if (el.scrollWidth > el.clientWidth + 1 || r.right > S.right + 0.5 || r.left < S.left - 0.5) clipped++;
  }
  return {
    unworded,
    rows: [...screen.querySelectorAll('[data-dm-row="list"]')].filter(rowShown).length,
    actions,
    clipped,
    qty: Object.fromEntries([...screen.querySelectorAll('[data-dm-row="list"]')].map((r) => [r.dataset.id, r.dataset.qty])),
    note: screen.querySelector('[data-dm-note]')?.dataset.dmNote ?? null,
  };
}

/** Runs in the page: painted things in the sheet that reach past its rounded top corners (Peter, 28 Nov 14:08). */
function cornerProbe(o) {
  const sheet = document.querySelector(`[data-testid="phone-${o}"] [data-dm-sheet]`);
  if (!sheet) return [];
  const cs = getComputedStyle(sheet);
  const R = parseFloat(cs.borderTopLeftRadius);
  const S = sheet.getBoundingClientRect();
  const alpha = (c) => {
    const m = c.match(/[\d.]+/g) ?? [];
    return m.length > 3 ? Number(m[3]) : m.length ? 1 : 0;
  };
  const painted = (st) =>
    (alpha(st.backgroundColor) > 0 && st.backgroundColor !== cs.backgroundColor) ||
    st.boxShadow !== 'none' ||
    (st.outlineStyle !== 'none' && parseFloat(st.outlineWidth) > 0) ||
    ['Top', 'Left', 'Right'].some((side) => parseFloat(st[`border${side}Width`]) > 0 && alpha(st[`border${side}Color`]) > 0);
  const out = [];
  for (const el of sheet.querySelectorAll('*')) {
    const st = getComputedStyle(el);
    if (!painted(st)) continue;
    const pad = st.outlineStyle !== 'none' ? parseFloat(st.outlineWidth) + parseFloat(st.outlineOffset || '0') : 0;
    const r = el.getBoundingClientRect();
    const box = { l: r.left - pad, t: r.top - pad, w: r.width + 2 * pad };
    if (r.width < 1 || box.t > S.top + R) continue;
    for (const side of ['Left', 'Right']) {
      const re = parseFloat(st[`borderTop${side}Radius`]) + pad;
      const cx = side === 'Left' ? S.left + R : S.right - R;
      const cy = S.top + R;
      const ex = side === 'Left' ? box.l : box.l + box.w;
      const dir = side === 'Left' ? 1 : -1;
      const pts = [];
      for (let a = 0; a <= 90; a += 5) {
        const rad = (a * Math.PI) / 180;
        pts.push([ex + dir * (re - re * Math.cos(rad)), box.t + re - re * Math.sin(rad)]);
      }
      for (let d = re; d <= R + 1; d += 1) pts.push([ex + dir * d, box.t], [ex, box.t + d]);
      const bad = pts.some(([x, y]) => {
        const inZone = side === 'Left' ? x < cx && y < cy : x > cx && y < cy;
        return inZone && Math.hypot(x - cx, y - cy) > R + 0.75;
      });
      if (bad) out.push(`${el.className || el.tagName} (${side.toLowerCase()})`);
    }
  }
  return out;
}

async function main() {
  const { chromium } = await loadPlaywright();
  const { server, base } = await startStaticServer();
  const browser = await chromium.launch(process.env.VERIFY_CHROME ? { executablePath: process.env.VERIFY_CHROME } : {});
  const page = await browser.newPage({ viewport: { width: 1000, height: 2400 } });
  mkdirSync(outDir, { recursive: true });
  let shots = 0;

  const go = async (o, q) => {
    const p = new URLSearchParams({ o, f: 'exact', m: 'typing', kb: 'off', theme: 'light', text: '100', lang: 'de', ...q });
    await page.goto(`${base}/add/dm/?${p}`);
    await page.locator(`[data-testid="phone-${o}"] [data-testid="dm-screen"]`).waitFor();
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(60);
  };
  const read = (o) => page.evaluate(probe, o);
  const shoot = async (o, name) => {
    await page.locator(`[data-testid="phone-${o}"]`).screenshot({ path: join(outDir, `${name}.png`) });
    shots++;
  };
  const click = (o, sel) => page.locator(`[data-testid="phone-${o}"] ${sel}`).first().click();
  const has = async (o, sel) => (await page.locator(`[data-testid="phone-${o}"] ${sel}`).count()) > 0;

  const rows = [];
  for (const o of OPTIONS) {
    const code = CODE[o];
    const isDm = o !== 'today';

    // Taps to merge and to tick off, from the sheet open with "Omega 3" typed (on the list once, at dm).
    await go(o, {});
    await click(o, '[data-dm-action="merge"]');
    let s = await read(o);
    check(s.qty.omega3 === '2', `${code}: one tap on merge gives Omega 3 2× (got ${s.qty.omega3})`);
    const mergeTaps = 1;

    await go(o, {});
    let tickTaps = 0;
    if (!(await has(o, '[data-dm-action="tick"]'))) {
      await click(o, '[data-dm-action="choose-tick"]');
      tickTaps++;
    }
    await click(o, '[data-dm-action="tick"]');
    tickTaps++;
    s = await read(o);
    check(!('omega3' in s.qty) && s.note === 'ticked', `${code}: tick off removes Omega 3 from the list and says so`);

    // Two more without typing an amount.
    await go(o, {});
    let twoTaps = '–';
    if (await has(o, '[data-dm-action="merge"][data-dm-amount="2"]')) {
      await click(o, '[data-dm-action="merge"][data-dm-amount="2"]');
      twoTaps = '1';
    } else if (await has(o, '[data-dm-action="more"]')) {
      await click(o, '[data-dm-action="more"]');
      await click(o, '[data-dm-action="merge"]');
      twoTaps = '2';
    }
    if (twoTaps !== '–') {
      s = await read(o);
      check(s.qty.omega3 === '3', `${code}: two more without typing gives 3× (got ${s.qty.omega3})`);
    }

    // What Enter does with a typed amount and on a unit item.
    const after = {};
    for (const [f, id] of [['count', 'omega3'], ['unit', 'flour'], ['unitTyped', 'flour']]) {
      await go(o, { f, m: 'after' });
      after[f] = (await read(o)).qty[id];
    }
    const label = (q) => (/^\d+$/.test(q) ? `${q}×` : q);
    if (isDm) {
      check(after.count === '3', `${code}: „Omega 3 2“ adds 2 (got ${after.count})`);
      check(after.unit === '1 kg', `${code}: „Mehl“ on 500 g adds one pack (got ${after.unit})`);
    }
    check(after.unitTyped === '1,5 kg', `${code}: „Mehl 1kg“ on 500 g gives 1,5 kg (got ${after.unitTyped})`);

    // Words on every action, their contrast, and the names a screen reader gets; DE and EN, light and dark.
    const labels = {};
    let allWorded = true;
    let named = true;
    for (const lang of LANGS) {
      const states = o === 'dm5' ? [null, 'choose-tick', 'choose-new'] : [null];
      const seen = [];
      for (const theme of THEMES)
        for (const st of states) {
          await go(o, { lang, theme });
          if (st) await click(o, `[data-dm-action="${st}"]`);
          const r = await read(o);
          seen.push(...r.actions);
          if (isDm) check(r.unworded.length === 0, `${code} ${lang} ${theme}: buttons without a visible word: ${r.unworded.join(', ')}`);
        }
      for (const a of seen) {
        if (!a.worded) allWorded = false;
        if (!/\p{L}/u.test(a.name)) named = false;
        if (isDm) check(a.contrast >= 4.5, `${code} ${lang}: action „${a.action}“ text contrast ${a.contrast.toFixed(2)} < 4.5`);
        if (isDm) check(a.worded, `${code} ${lang}: action „${a.action}“ has no visible word (${JSON.stringify(a.visible)})`);
        check(/\p{L}/u.test(a.name), `${code} ${lang}: action „${a.action}“ has no accessible name in words`);
        if (isDm) check(norm(a.name).includes(norm(a.visible)), `${code} ${lang}: action „${a.action}“: its name „${a.name}“ does not contain its visible label „${a.visible}“ (WCAG 2.5.3)`);
        if (isDm && ['merge', 'tick', 'new'].includes(a.action)) check(/\p{L}{3,}/u.test(a.name.replace(/Omega|dm|REWE/g, '')), `${code} ${lang}: action „${a.action}“: its name „${a.name}“ has no word besides the item`);
      }
      const first = (k) => seen.find((a) => a.action === k);
      labels[lang] = ['merge', 'tick', 'new'].map((k) => {
        const a = first(k);
        return a ? (a.worded ? `„${a.visible}“` : '(icon only)') : '–';
      });
    }

    // List rows in view while the match shows: keyboard hidden, shown, shown at 200 %.
    const visible = [];
    for (const q of [{}, { kb: 'on' }, { kb: 'on', text: '200' }]) {
      await go(o, q);
      visible.push((await read(o)).rows);
    }

    // Large text, keyboard hidden: clipped text, and how many of the three choices (merge, tick off, new entry) are on
    // screen without scrolling, the fewest over both languages and themes.
    const CORE = o === 'dm5' ? [['merge'], ['tick', 'choose-tick'], ['new', 'choose-new']] : [['merge'], ['tick'], ['new']];
    const large = {};
    for (const scale of ['200', '310']) {
      let clipped = 0;
      let fewest = 3;
      for (const lang of LANGS)
        for (const theme of THEMES) {
          await go(o, { lang, theme, text: scale });
          const r = await read(o);
          clipped += r.clipped;
          const inView = CORE.filter((names) => r.actions.some((a) => names.includes(a.action) && a.reachable)).length;
          fewest = Math.min(fewest, inView);
        }
      large[scale] = `${fewest}/3 in view, ${clipped} clipped`;
      if (isDm && scale === '200') check(clipped === 0, `${code}: 200 % clips ${clipped} texts`);
    }

    rows.push([
      code,
      String(mergeTaps),
      String(tickTaps),
      twoTaps === '–' ? '– (type „Omega 3 x2“)' : twoTaps,
      `${label(after.count)} · ${label(after.unit)} · ${label(after.unitTyped)}`,
      allWorded ? 'yes' : 'no',
      `DE ${labels.de.join(' / ')} · EN ${labels.en.join(' / ')}`,
      visible.join(' · '),
      `200 %: ${large['200']} · 310 %: ${large['310']}`,
      named ? 'yes' : 'no',
    ]);
  }

  // The sheet's top row follows its rounded corners in every option, Today included, every scenario and text size.
  for (const o of OPTIONS)
    for (const f of FIXTURES)
      for (const text of SCALES)
        for (const [theme, lang] of [['light', 'de'], ['dark', 'en']]) {
          await go(o, { f, text, theme, lang });
          const bad = await page.evaluate(cornerProbe, o);
          check(bad.length === 0, `${CODE[o]} ${f} ${text} % ${theme}: painted past the sheet's top corner: ${bad.join(', ')}`);
          if (o === 'dm5' && f === 'exact') {
            for (const st of ['choose-tick', 'choose-new']) {
              await click(o, `[data-dm-action="${st}"]`);
              const b2 = await page.evaluate(cornerProbe, o);
              check(b2.length === 0, `DM5 ${st} ${text} %: painted past the sheet's top corner: ${b2.join(', ')}`);
            }
          }
        }

  // Screenshots: every option, light and dark, DE and EN, 100/200/310 %, keyboard hidden and shown; and each scenario.
  for (const o of OPTIONS)
    for (const lang of LANGS)
      for (const theme of THEMES)
        for (const text of SCALES) {
          await go(o, { lang, theme, text });
          await shoot(o, `${o}-${lang}-${theme}-${text}`);
        }
  for (const o of OPTIONS) {
    for (const f of FIXTURES)
      for (const m of ['typing', 'after']) {
        await go(o, { f, m });
        await shoot(o, `${o}-scenario-${f}-${m}`);
      }
    await go(o, { kb: 'on' });
    await shoot(o, `${o}-keyboard`);
    await go(o, { m: 'closed' });
    await shoot(o, `${o}-closed`);
  }

  // The table on the page must equal what was measured.
  await go('dm1', {});
  const table = await page.evaluate(() => [...document.querySelectorAll('[data-testid="dm-table"] tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map((td) => td.textContent.trim())));
  if (PRINT) console.log(JSON.stringify(rows, null, 1));
  check(JSON.stringify(table) === JSON.stringify(rows), `the table on /add/dm/ differs from the measurement:\npage     ${JSON.stringify(table)}\nmeasured ${JSON.stringify(rows)}`);

  await browser.close();
  server.close();
  console.log(`[verify-dm] ${shots} screenshots in ${outDir}`);
  if (failures.length) {
    console.error(`[verify-dm] FAILED (${failures.length}):\n- ${failures.join('\n- ')}`);
    process.exit(1);
  }
  console.log('[verify-dm] passed: Today and DM1–DM5 measured, every DM action has a visible word, the table matches');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
