#!/usr/bin/env node
// Round AE: measures Today and AE1–AE5 in the built sandbox, screenshots every option in both themes, both languages
// and 100/200/310 % text, and exits 1 when an option breaks or when the table on /add/ae/ differs from what it measured.
// `--print` prints the measured rows for src/ae/meta.ts. Screenshots go to $VERIFY_OUT (default verify-screenshots/ae).

import { createServer } from 'node:http';
import { mkdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = resolve(process.env.VERIFY_OUT ?? join(root, 'verify-screenshots', 'ae'));
const PRINT = process.argv.includes('--print');
const QUICK = process.argv.includes('--quick');

const OPTIONS = ['today', 'ae1', 'ae2', 'ae3', 'ae4', 'ae5'];
const CODE = { today: 'Today', ae1: 'AE1', ae2: 'AE2', ae3: 'AE3', ae4: 'AE4', ae5: 'AE5' };
const ADDS = { en: ['Milk', 'Eggs', 'Cheese'], de: ['Milch', 'Eier', 'Käse'] };
const DUP = { en: 'Bananas', de: 'Bananen' };

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
const check = (ok, msg) => {
  if (!ok) failures.push(msg);
};

/** Runs in the page: what the phone of option `o` shows right now. */
function probe(o) {
  const phone = document.querySelector(`[data-testid="phone-${o}"]`);
  const screen = phone.querySelector('[data-testid="ae-screen"]');
  const S = screen.getBoundingClientRect();
  const ownedBy = (row, x, y) => {
    const hit = document.elementFromPoint(x, y);
    return hit && hit.closest('[data-ae-row]') === row;
  };
  const shown = (row) => {
    const r = row.getBoundingClientRect();
    if (r.height < 1 || r.top < S.top || r.bottom > S.bottom + 0.5) return false;
    const x = r.left + Math.min(60, r.width / 2);
    return ownedBy(row, x, r.top + 4) && ownedBy(row, x, r.bottom - 4);
  };
  const rows = [...screen.querySelectorAll('[data-ae-row]')].map((row) => ({
    existing: row.dataset.aeRow === 'existing',
    place: row.dataset.aePlace,
    dim: row.dataset.dim === '1',
    name: row.dataset.name,
    qty: row.dataset.qty,
    id: row.dataset.id,
    visible: shown(row),
  }));
  let cover = 0;
  for (const el of screen.querySelectorAll('[data-ae-cover]')) {
    const r = el.getBoundingClientRect();
    cover += Math.max(0, Math.min(r.bottom, S.bottom) - Math.max(r.top, S.top));
  }
  const clipped = [];
  for (const el of screen.querySelectorAll('[data-text]')) {
    const r = el.getBoundingClientRect();
    if (r.width < 1) continue;
    let clip = el.scrollWidth > el.clientWidth + 1 || r.right > S.right + 0.5 || r.left < S.left - 0.5;
    // Cut by a box that does not scroll: sideways always, up or down unless a scroll area in between can bring it into view.
    let scrollsY = false;
    for (let a = el.parentElement; a && !clip; a = a === screen ? null : a.parentElement) {
      const cs = getComputedStyle(a);
      const ar = a.getBoundingClientRect();
      if (cs.overflowY === 'auto' || cs.overflowY === 'scroll') scrollsY = true;
      if (cs.overflowX !== 'visible' && (r.right > ar.right + 0.5 || r.left < ar.left - 0.5)) clip = true;
      if (!scrollsY && cs.overflowY !== 'visible' && (r.bottom > ar.bottom + 0.5 || r.top < ar.top - 0.5)) clip = true;
    }
    if (clip) clipped.push(el.textContent.slice(0, 40));
  }
  const input = screen.querySelector('[data-ae-field] input');
  const fs = input ? parseFloat(getComputedStyle(input).fontSize) : 0;
  const fieldCut = input ? fs * 1.15 > input.clientHeight : false;
  const pad = input ? parseFloat(getComputedStyle(input).paddingLeft) + parseFloat(getComputedStyle(input).paddingRight) : 0;
  const fieldWidth = input ? Math.round(input.clientWidth - pad) : 0;
  const bar = screen.querySelector('[data-ae-field]');
  const br = bar?.getBoundingClientRect();
  const barOff = br ? br.bottom > S.bottom + 0.5 || br.top < S.top : false;
  const send = screen.querySelector('[data-ae-send]');
  const sendOff = send ? send.getBoundingClientRect().bottom > S.bottom + 0.5 : false;
  const horizontal = screen.scrollWidth > screen.clientWidth + 1;
  return { rows, cover: Math.round(cover), clipped, fieldCut, fieldWidth, barOff, sendOff, horizontal, flight: Boolean(screen.querySelector('[data-ae-flight]')), lift: [...screen.querySelectorAll('.ae-row--lift')].map((r) => r.dataset.name) };
}

async function main() {
  const { chromium } = await loadPlaywright();
  const { server, base } = await startStaticServer();
  mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch(process.env.VERIFY_CHROME ? { executablePath: process.env.VERIFY_CHROME } : {});
  const page = await browser.newPage({ viewport: { width: 1000, height: 1000 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${base}/add/ae/?o=today`);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => 'ae' in window);
  await page.addStyleTag({ content: '.ae-hero, .ae-controls, .ae-option, .ae-phone-label { display: none !important; } .ae-stage { margin: 0 !important; }' });

  const pageTable = await page.$$eval('[data-testid="ae-table"] tr', (trs) => trs.map((tr) => [...tr.children].map((c) => c.textContent.trim())));
  const set = async (s) => {
    await page.evaluate((st) => window.ae.set(st), s);
    await page.waitForTimeout(60);
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  };
  const look = (o) => page.evaluate(probe, o);
  const phone = (o) => page.locator(`[data-testid="phone-${o}"]`);
  const tap = async (o, sel) => {
    await phone(o).locator(sel).first().click();
    await page.waitForTimeout(40);
  };
  const settle = () => page.waitForTimeout(650);

  const measured = [];
  for (const o of OPTIONS) {
    const out = { code: CODE[o] };
    const visible = async (kb, text = '100') => {
      await set({ o, f: 'many', m: 'open', kb, theme: 'light', text, lang: 'en' });
      const p = await look(o);
      const shown = p.rows.filter((r) => r.existing && r.visible);
      return { clear: shown.filter((r) => !r.dim).length, dim: shown.filter((r) => r.dim).length };
    };
    const fmt = (v) => (v.dim ? `${v.dim} dimmed` : `${v.clear}`);
    out.rowsKbOff = fmt(await visible('off'));
    out.rowsKbOn = fmt(await visible('on'));
    out.rows200 = fmt(await visible('on', '200'));

    await set({ o, f: 'many', m: 'open', kb: 'off', theme: 'light', text: '100', lang: 'en' });
    const coverOpen = (await look(o)).cover;
    await set({ o, f: 'many', m: 'typing', kb: 'off', theme: 'light', text: '100', lang: 'en' });
    const coverTyping = (await look(o)).cover;
    out.cover = [coverOpen, coverTyping];

    // Three adds from the closed list, by taps on the phone (send on its keyboard); typing itself is not counted.
    await set({ o, f: 'many', m: 'closed', kb: 'on', theme: 'light', text: '100', lang: 'en' });
    let taps = 0;
    await tap(o, '[data-ae-field] input');
    taps++;
    for (const name of ADDS.en) {
      await page.keyboard.type(name);
      await tap(o, '[data-ae-send]');
      taps++;
      await settle();
    }
    let p = await look(o);
    const placed = (pr) => ADDS.en.filter((n) => pr.rows.some((r) => r.name === n && r.visible && r.place === 'list')).length;
    const inCard = ADDS.en.filter((n) => p.rows.some((r) => r.name === n && r.visible && r.place === 'card')).length;
    out.taps = taps;
    out.placedWhileAdding = placed(p);
    out.inCard = inCard;
    out.flightSeen = p.flight || p.lift.length > 0;
    let toSee = taps;
    if (placed(p) < 3) {
      await tap(o, '[data-ae-send]');
      toSee++;
      await settle();
      p = await look(o);
    }
    out.toSee = toSee;
    out.seenAfter = placed(p);
    check(ADDS.en.every((n) => p.rows.some((r) => r.name === n)), `${CODE[o]}: the three adds are not all on the list`);

    // Enter on an item already on the list.
    await set({ o, f: 'duplicate', m: 'closed', kb: 'off', theme: 'light', text: '100', lang: 'en' });
    await tap(o, '[data-ae-field] input');
    await page.keyboard.type(DUP.en);
    const dupShown = (await look(o)).rows.filter((r) => r.existing && r.name === DUP.en && r.visible).length;
    await page.keyboard.press('Enter');
    await settle();
    await page.keyboard.press('Enter');
    await settle();
    const after = (await look(o)).rows.filter((r) => r.place === 'list' && r.name === DUP.en);
    out.dup = after.length === 1 ? `one row, ${after[0].qty}×` : `${after.length} rows (${after.map((r) => (r.qty ? `${r.qty}×` : '1')).join(' + ')})`;
    out.dupShown = dupShown > 0 ? 'yes' : 'no';
    measured.push(out);
  }

  // Largest text, both languages and themes, every moment; plus the fixtures at 100 %.
  const overflow = Object.fromEntries(OPTIONS.map((o) => [o, { clipped: new Set(), fieldCut: new Set(), off: new Set(), narrowest: Infinity }]));
  const scales = QUICK ? ['310'] : ['100', '200', '310'];
  let shots = 0;
  for (const o of OPTIONS) {
    for (const theme of ['light', 'dark']) {
      for (const lang of ['en', 'de']) {
        for (const text of scales) {
          for (const m of ['closed', 'open', 'typing', 'added']) {
            for (const kb of m === 'closed' ? ['off'] : ['on', 'off']) {
              await set({ o, f: 'many', m, kb, theme, text, lang });
              await settle();
              const pr = await look(o);
              if (text !== '100') {
                for (const t of pr.clipped) overflow[o].clipped.add(`${text} % ${lang}: ${t}`);
                if (pr.fieldCut) overflow[o].fieldCut.add(text);
                if (text === '310' && pr.fieldWidth > 0) overflow[o].narrowest = Math.min(overflow[o].narrowest, pr.fieldWidth);
                if (pr.barOff || pr.sendOff || pr.horizontal) overflow[o].off.add(`${text} % ${lang} ${m} kb ${kb}`);
              } else {
                check(!pr.clipped.length && !pr.fieldCut && !pr.barOff && !pr.sendOff && !pr.horizontal, `${CODE[o]} at 100 % ${lang} ${theme} ${m} kb ${kb}: ${JSON.stringify({ clipped: pr.clipped, fieldCut: pr.fieldCut, barOff: pr.barOff })}`);
              }
              if (kb === 'on' || m === 'closed') {
                await phone(o).screenshot({ path: join(outDir, `${o}-${m}-${lang}-${theme}-${text}.png`) });
                shots++;
              }
            }
          }
        }
      }
    }
    for (const f of ['empty', 'one', 'long', 'duplicate']) {
      for (const m of ['open', 'typing', 'added']) {
        await set({ o, f, m, kb: 'on', theme: 'light', text: '100', lang: 'en' });
        await settle();
        const pr = await look(o);
        check(!pr.clipped.length && !pr.barOff && !pr.horizontal, `${CODE[o]} fixture ${f} ${m}: clipped ${JSON.stringify(pr.clipped)}`);
        await phone(o).screenshot({ path: join(outDir, `${o}-fixture-${f}-${m}.png`) });
        shots++;
      }
    }
  }

  // AE5 without motion: no flight, the row still lifts.
  const rm = await browser.newPage({ viewport: { width: 1000, height: 1000 }, reducedMotion: 'reduce' });
  await rm.goto(`${base}/add/ae/?o=ae5&f=many&m=closed&kb=on`);
  await rm.waitForFunction(() => 'ae' in window);
  await rm.locator('[data-testid="phone-ae5"] [data-ae-field] input').click();
  await rm.keyboard.type('Milk');
  await rm.locator('[data-testid="phone-ae5"] [data-ae-send]').click();
  await rm.waitForTimeout(80);
  const reduced = await rm.evaluate(probe, 'ae5');
  check(!reduced.flight && reduced.lift.includes('Milk'), `AE5 reduced motion: flight ${reduced.flight}, lifted ${JSON.stringify(reduced.lift)}`);
  await rm.close();

  const today = measured[0];
  const rows = measured.map((m, i) => {
    const o = OPTIONS[i];
    const ov = overflow[o];
    const delta = (n, t) => (n === t ? '±0' : `${n > t ? '+' : '−'}${Math.abs(n - t)}`);
    return [
      m.code,
      `${m.rowsKbOff} · ${m.rowsKbOn} · ${m.rows200}`,
      `${m.taps}; ${m.placedWhileAdding} of 3 in their list place while adding${m.inCard ? ` (${m.inCard} in the card)` : ''}${m.flightSeen && o === 'ae5' ? ', each flies there' : ''}`,
      `${m.toSee}`,
      `${m.cover[0]} · ${m.cover[1]} (${delta(m.cover[0], today.cover[0])} · ${delta(m.cover[1], today.cover[1])})`,
      `${m.dup}${m.dupShown === 'yes' ? '; its row in view while typing' : ''}`,
      `${ov.clipped.size ? `${ov.clipped.size} clipped` : '0 clipped'}; field text cut at ${[...ov.fieldCut].sort().map((s) => `${s} %`).join(', ') || 'none'}; field ${ov.narrowest} px wide at 310 % (narrowest, about ${Math.floor(ov.narrowest / 31)} letter${Math.floor(ov.narrowest / 31) === 1 ? '' : 's'})${ov.off.size ? `; FAIL bar or keyboard off screen ${ov.off.size}×` : ''}`,
    ];
  });

  for (const o of OPTIONS) {
    check(overflow[o].off.size === 0, `${CODE[o]}: add bar or keyboard pushed off screen: ${[...overflow[o].off].slice(0, 4).join('; ')}`);
    check(overflow[o].clipped.size === 0, `${CODE[o]}: clipped text at large sizes: ${[...overflow[o].clipped].slice(0, 6).join('; ')}`);
  }
  for (const [i, m] of measured.entries()) {
    if (OPTIONS[i] === 'today' || OPTIONS[i] === 'ae1') continue;
    check(m.dup.startsWith('one row'), `${m.code}: Enter on an item already on the list made ${m.dup}`);
  }
  check(measured[1].rowsKbOff === today.rowsKbOff && measured[1].cover[0] >= today.cover[0], 'AE1 must not change how much of the list is visible');
  check(Number.parseInt(measured[2].rowsKbOn, 10) > 0, 'AE2 must keep list rows in view with the keyboard up');
  check(measured[5].flightSeen, 'AE5: no flight or lift after an add');
  check(errors.length === 0, `page errors: ${errors.join('; ')}`);

  if (PRINT) console.log(JSON.stringify(rows, null, 2));
  const body = pageTable.slice(1);
  for (const [i, row] of rows.entries()) {
    const want = body[i];
    check(JSON.stringify(want) === JSON.stringify(row), `table row ${row[0]}: page says ${JSON.stringify(want)}, measured ${JSON.stringify(row)}`);
  }
  check(body.length === rows.length, `the page table has ${body.length} rows, measured ${rows.length}`);

  await browser.close();
  server.close();
  console.log(`[verify-ae] ${shots} screenshots in ${outDir}`);
  if (failures.length) {
    for (const f of failures) console.log(`FAIL ${f}`);
    console.log(`[verify-ae] FAILED: ${failures.length} check(s)`);
    process.exit(1);
  }
  console.log('[verify-ae] passed: the table on /add/ae/ matches the measurements');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
