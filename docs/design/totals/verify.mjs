// Drives round TE in Chromium and checks what the page claims.
// Usage: node verify.mjs [<root>] [--path /docs/design/totals/] [--write]
// --write stores the measurements in te/measured.json; without it they must match the file.
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './tools/serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const write = args.includes('--write');
const pathArg = args.includes('--path') ? args[args.indexOf('--path') + 1] : '/docs/design/totals/';
const root = resolve(args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--path') ?? join(here, '../../..'));
const pwDir = [join(root, 'e2e'), join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');

let checks = 0;
const failures = [];
const check = (ok, what) => {
  checks += 1;
  if (!ok) failures.push(what);
};

// The UI words are the app's: strings.js equals the ARB files (only where the repo's app/ is there).
const arbDir = join(here, '../../../app/l10n');
if (existsSync(arbDir)) {
  const { generate } = await import('./tools/strings.mjs');
  check(readFileSync(join(here, 'strings.js'), 'utf8') === generate(arbDir), 'strings.js equals the ARB files (node tools/strings.mjs)');
}

const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
page.setDefaultTimeout(8000);
page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
const open = async (q) => {
  await page.goto(`${url}${pathArg}te/?${q}`);
  await page.waitForSelector('body[data-ready]');
};

const ids = ['TE1', 'TE2', 'TE3', 'TE4', 'TE5'];
const states = ['a', 'b', 'c', 'd'];
const sizes = [['ios', 100], ['ios', 310], ['android', 100], ['android', 200]];

// One phone per option and state, drawn off screen: what it adds to the list against no total at all, plus what
// the block, dividers and top bar say.
const inspect = () =>
  page.evaluate(async ({ ids, states }) => {
    const base = new URL('../', location.href).href;
    const { options } = await import(`${base}blocks.js`);
    const { phone, settle } = await import(`${base}phone.js`);
    const { initial, summary, items } = await import(`${base}model.js`);
    const { env } = await import(`${base}page.js`);
    const host = document.createElement('div');
    host.style.cssText = 'position:absolute;left:-5000px;top:0';
    document.body.append(host);
    const draw = (id, st, extra = {}) => {
      host.innerHTML = phone({ ...initial(st), ...extra }, options[id], env);
      settle(host);
      return host.querySelector('.phone');
    };
    const height = (ph) => ph.querySelector('[data-content]').scrollHeight;
    const out = {};
    for (const st of states) {
      const none = height(draw('none', st));
      const rowHs = [...draw('today', st).querySelectorAll('.item')].map((r) => r.getBoundingClientRect().height).sort((a, b) => a - b);
      out[st] = { none, row: rowHs[Math.floor(rowHs.length / 2)], summary: summary(initial(st)), opts: {} };
      for (const id of ['today', ...ids]) {
        const ph = draw(id, st);
        const blk = ph.querySelector('[data-block]');
        const box = ph.getBoundingClientRect();
        // Every element of the phone, by what stays visible of it: an ancestor that clips (the add field clips its hint,
        // as the app does) cuts it first.
        const visible = (el) => {
          let { left, right } = el.getBoundingClientRect();
          for (let a = el.parentElement; a && a !== ph; a = a.parentElement) {
            if (getComputedStyle(a).overflowX === 'visible') continue;
            const r = a.getBoundingClientRect();
            left = Math.max(left, r.left);
            right = Math.min(right, r.right);
          }
          return { left, right };
        };
        const outside = [...ph.querySelectorAll('*')].filter((el) => {
          if (el.getBoundingClientRect().width === 0) return false;
          const r = visible(el);
          return r.right > r.left && (r.left < box.left - 0.5 || r.right > box.right + 0.5);
        }).length;
        const acts = [...ph.querySelectorAll('[data-block] [data-act], [data-bar-amount]')].map((el) => el.getBoundingClientRect().height);
        out[st].opts[id] = {
          h: height(ph) - none,
          blockText: blk?.innerText.replace(/\s+/g, ' ').trim() ?? '',
          lines: [...ph.querySelectorAll('[data-block] .sline')].map((l) => ({ store: l.dataset.line, text: l.innerText.replace(/\s+/g, ' ').trim(), amount: l.querySelector('[data-amount]')?.innerText.replace(/\s+/g, ' ') ?? '' })),
          total: ph.querySelector('[data-block] [data-total] .tamt')?.innerText.replace(/\s+/g, ' ') ?? '',
          counts: ph.querySelector('[data-block] [data-counts]')?.innerText ?? '',
          dividers: Object.fromEntries([...ph.querySelectorAll('[data-dsum]')].map((d) => [d.closest('[data-divider]').dataset.divider, d.innerText])),
          bar: ph.querySelector('[data-bar-amount]')?.innerText.replace(/\s+/g, ' ') ?? '',
          nudge: ph.querySelector('[data-nudge]')?.innerText ?? '',
          cut: [...ph.querySelectorAll('.switcher .two > *')].some((el) => el.scrollWidth > el.clientWidth + 0.5),
          outside,
          acts,
        };
      }
    }
    host.remove();
    return { out, items: items.map((i) => i.id) };
  }, { ids, states });

const measured = {};
const words = { en: { atLeast: 'at least', without: 'without price', bought: 'bought' }, de: { atLeast: 'mind.', without: 'ohne Preis', bought: 'gekauft' } };
for (const [device, ts] of sizes) {
  for (const lang of ['en', 'de']) {
    for (const theme of ts === 100 ? ['light', 'dark'] : ['light']) {
      await open(`lang=${lang}&theme=${theme}&ts=${ts}&device=${device}`);
      const { out } = await inspect();
      // On every phone of the page (each option's frames, the extra ones and the live phones): in a total or store row,
      // no two parts draw over each other. Glyph boxes by Range, so a word that runs past its own box counts.
      const overlaps = await page.evaluate(() => {
        const boxes = (el) => {
          const r = document.createRange();
          r.selectNodeContents(el);
          return [...r.getClientRects()].filter((b) => b.width > 0.5 && b.height > 0.5);
        };
        const hit = (a, b) => a.some((x) => b.some((y) => Math.min(x.right, y.right) - Math.max(x.left, y.left) > 0.5 && Math.min(x.bottom, y.bottom) - Math.max(x.top, y.top) > 0.5));
        const found = [];
        for (const row of document.querySelectorAll('.phone .trow, .phone .sline')) {
          const parts = [...row.children].map(boxes);
          for (let i = 0; i < parts.length; i += 1) for (let j = i + 1; j < parts.length; j += 1) {
            if (hit(parts[i], parts[j])) {
              const where = row.closest('section')?.id ?? '?';
              const frame = row.closest('figure[data-frame]')?.dataset.frame ?? 'live';
              found.push(`${where} ${frame}: “${row.innerText.replace(/\s+/g, ' ').trim()}”`);
            }
          }
        }
        return found;
      });
      check(overlaps.length === 0, `${device} ${ts} % ${lang} ${theme}: no row draws its name over its amount or link (${overlaps.length}: ${overlaps.slice(0, 4).join('; ')})`);
      const where = `${device} ${ts} % ${lang} ${theme}`;
      const W = words[lang];
      for (const st of states) {
        const { opts, summary: sm } = out[st];
        const anyPrice = sm.total.priced > 0;
        for (const id of ['today', ...ids]) {
          const o = opts[id];
          check(o.outside === 0, `${id} (${st}) ${where}: nothing sticks out of the phone (${o.outside})`);
          check(o.acts.every((h) => h >= 44), `${id} (${st}) ${where}: every control in the block is at least 44 px tall (${o.acts.join(', ')})`);
          if (id === 'today') continue;
          // The point of the round: no option lists a store only to say it has no price.
          check(o.lines.every((l) => !l.text.includes(W.without)), `${id} (${st}) ${where}: no store line says “${W.without}”`);
          check(o.lines.every((l) => l.amount !== ''), `${id} (${st}) ${where}: every store line has an amount`);
          // ST3 rules kept: the floor where something is unpriced, ≈ where an estimate is inside, „No store“ its own line.
          for (const l of o.lines) {
            const g = sm.groups.find((x) => (x.store ?? 'none') === l.store);
            check(l.amount.includes(W.atLeast) === g.sum.unpriced > 0, `${id} (${st}) ${where}: ${l.store}'s amount has the floor exactly when it lacks a price (${l.amount})`);
            check(l.amount.includes('≈') === g.sum.estimate, `${id} (${st}) ${where}: ${l.store}'s amount has ≈ exactly with an estimate (${l.amount})`);
          }
          if (o.total) {
            check(o.total.includes(W.atLeast) === sm.total.unpriced > 0, `${id} (${st}) ${where}: the total has the floor exactly when something lacks a price (${o.total})`);
            check(o.total.includes('≈') === sm.total.estimate, `${id} (${st}) ${where}: the total has ≈ exactly with an estimate (${o.total})`);
          }
          if (o.lines.length) {
            const cents = (t) => Number(t.replace(/[^\d]/g, ''));
            check(o.lines.reduce((a, l) => a + cents(l.amount), 0) === cents(o.total), `${id} (${st}) ${where}: the store lines add up to the total`);
            if (sm.groups.some((g) => g.store === null && g.sum.priced > 0)) check(o.lines.some((l) => l.store === 'none'), `${id} (${st}) ${where}: “No store” has its own line`);
          }
          if (st === 'd' && anyPrice && id !== 'TE5') check(o.counts.includes(W.bought), `${id} (d) ${where}: on a trip the total says what was bought (${o.counts})`);
        }
        // Each option's own promise, state by state.
        const T = opts;
        check(!anyPrice ? T.TE1.h === 0 && T.TE2.h === 0 && T.TE3.h === 0 && T.TE5.h === 0 : true, `(a) ${where}: TE1, TE2, TE3 and TE5 show nothing without a price`);
        check(anyPrice === (T.TE1.total !== '' || T.TE1.lines.length > 0), `(${st}) ${where}: TE1 shows a total exactly when something has a price`);
        check(T.TE1.lines.length === sm.groups.filter((g) => g.sum.priced > 0).length || T.TE1.lines.length === 0, `(${st}) ${where}: TE1 lists every store with a price`);
        check(T.TE2.lines.length === 0, `(${st}) ${where}: TE2 is folded by default`);
        check(T.TE3.lines.length === 0 && Object.keys(T.TE3.dividers).length === sm.groups.filter((g) => g.open.priced > 0).length, `(${st}) ${where}: TE3 puts each open sum on its divider and none in the block`);
        const unpriced = sm.total.unpriced;
        check(unpriced > 0 ? T.TE4.nudge.includes(String(unpriced)) : T.TE4.nudge === '', `(${st}) ${where}: TE4 links the ${unpriced} items without a price`);
        check(unpriced > 0 ? T.TE4.lines.length === 0 : T.TE4.lines.length > 1, `(${st}) ${where}: TE4 lists stores only once all is priced`);
        if (device === 'ios' && ts === 100 && lang === 'en') check(T.TE5.h === 0, `(${st}) ${where}: TE5 adds nothing to the list in English (${T.TE5.h})`);
        check(anyPrice === (T.TE5.bar !== ''), `(${st}) ${where}: TE5's amount shows in the top bar exactly when something has a price`);
        check(!T.TE5.blockText, `(${st}) ${where}: TE5 has no block`);
        if (theme !== 'light') continue;
        const rec = (measured[device] ??= {})[ts] ??= {};
        const into = lang === 'en' ? rec : (rec.de ??= {});
        // One row height per phone and text size: the median list row of state (a).
        const unit = out.a.row;
        for (const id of ['today', ...ids]) {
          const saved = Math.floor((opts.today.h - opts[id].h) / unit);
          ((into[id] ??= {})[st] = { h: opts[id].h, saved, ...(opts[id].cut && !opts.today.cut ? { cut: true } : {}) });
        }
        if (lang === 'en') rec.row = unit;
      }
    }
  }
}

// TE-Q6's frame: with prices in one store only, TE1 shows one total line and no store line.
await open('');
const b1 = await page.locator('#TE1 figure[data-frame="b1"] [data-block]').evaluate((el) => ({ lines: el.querySelectorAll('.sline').length, total: el.querySelector('.tamt')?.innerText ?? '' }));
check(b1.lines === 0 && /3\.89/.test(b1.total), `TE1 with one store priced: a total line only (${b1.lines} store lines, ${b1.total})`);
// The page on a phone: nothing scrolls sideways at 390 px.
await page.setViewportSize({ width: 390, height: 844 });
for (const q of ['', 'lang=de']) {
  await open(q);
  const w = await page.evaluate(() => document.documentElement.scrollWidth);
  check(w <= 390, `the round page fits a 390 px phone without sideways scrolling (${q || 'en'}: ${w} px)`);
}
await page.setViewportSize({ width: 1600, height: 1000 });

// RECOMMENDATION.md's claim about TE5: in German and on the 360 px Android the amount cuts the list name; in English on
// the iPhone it does not.
check(measured.ios[100].de.TE5.b.cut === true && measured.android[100].TE5.b.cut === true && !measured.ios[100].TE5.b.cut, 'TE5 cuts the list name in German and on Android, not in English on the iPhone');

// The Today replica against the real app: block heights the release web build measured (tools/capture-today.mjs).
const real = JSON.parse(readFileSync(join(here, 'te/real/heights.json'), 'utf8'));
for (const [key, hs] of Object.entries(real)) {
  const [device, ts, lang] = key.split('-');
  const mine = lang === 'en' ? measured[device][ts].today : measured[device][ts].de.today;
  for (const st of states) {
    if (hs[st] == null) continue;
    // ±3 px on the brief's 390 × 844 at 100 %. Elsewhere 12 %: at the wrap edge the two engines break a line apart, and
    // Flutter breaks an amount too wide for its column on the line it sits on (“≈ €1 / 9.10”) where CSS first moves it
    // down (“≈ / €19. / 10”), one display line, about 105 px at 310 %.
    const tol = device === 'ios' && Number(ts) === 100 ? 3 : hs[st] * 0.12;
    check(Math.abs(mine[st].h - hs[st]) <= tol, `Today replica ${key} (${st}): ${mine[st].h} px against the real ${hs[st]} px (±${Math.round(tol)})`);
  }
}

// The live phones: a price, a fold, the next price, the sheet, a tick on the trip.
await open('');
const live = (id) => page.locator(`[data-live-phone="${id}"]`);
const text = async (id) => (await live(id).innerText()).replace(/\s+/g, ' ');
await live('TE1').locator('[data-row="toothpaste"] [data-chip]').click();
check((await live('TE1').locator('[data-block]').count()) === 1 && (await text('TE1')).includes('€1.45'), 'live TE1: pricing Toothpaste brings the block with €1.45');
await live('TE2').locator('..').locator('[data-state="b"]').click();
await live('TE2').locator('[data-act="fold"]').click();
check((await live('TE2').locator('.sline').count()) === 2, 'live TE2: a tap on the total opens Lidl and Edeka');
await live('TE4').locator('..').locator('[data-state="b"]').click();
await live('TE4').locator('[data-nudge]').click();
const target = await live('TE4').locator('.item.target').getAttribute('data-row');
check(target === 'toothpaste', `live TE4: the link points at the first item without a price (${target})`);
const inView = await live('TE4').evaluate((el) => {
  const t = el.querySelector('.item.target').getBoundingClientRect();
  const s = el.querySelector('[data-scroll]').getBoundingClientRect();
  return t.top >= s.top && t.bottom <= s.bottom;
});
check(inView, 'live TE4: the item without a price is scrolled into view');
await live('TE5').locator('..').locator('[data-state="b"]').click();
await live('TE5').locator('[data-bar-amount]').click();
check((await live('TE5').locator('[data-sheet] .sline').count()) === 2, 'live TE5: the amount opens the receipt with Lidl and Edeka');
await live('TE3').locator('..').locator('[data-state="b"]').click();
await live('TE3').locator('[data-row="bread"] .nm').click();
check((await text('TE3')).includes('€2.49 bought'), 'live TE3: buying the bread on the trip shows “€2.49 bought”');

// The numbers on the page and in the recommendation.
const file = join(here, 'te/measured.json');
const old = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
const next = { pick: old.pick, runner: old.runner, ...measured };
if (write) writeFileSync(file, `${JSON.stringify(next, null, 1)}\n`);
else check(JSON.stringify({ ...old }) === JSON.stringify(next), 'te/measured.json holds these measurements (run with --write after a change)');
for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
  const md = readFileSync(join(here, 'te', f), 'utf8');
  const rows = md.split('\n').filter((l) => /^\| \*{0,2}(Today|Heute|TE\d)/.test(l));
  check(rows.length === 12, `${f}: a height row for Today and each option, at 100 % and at max text (${rows.length})`);
  for (const r of rows) {
    const cells = r.split('|').slice(1, -1).map((c) => c.trim().replace(/\*/g, ''));
    const id = /TE\d/.exec(cells[0])?.[0] ?? 'today';
    const ts = /310|max/.test(cells[1]) ? 310 : 100;
    states.forEach((st, k) => {
      const m = measured.ios[ts][id][st];
      const want = id === 'today' ? `${m.h}` : `${m.h} (${m.saved > 0 ? '+' : ''}${m.saved})`;
      check(cells[2 + k] === want, `${f}: ${id} ${ts} % (${st}) reads “${cells[2 + k]}”, measured “${want}”`);
    });
  }
}

await browser.close();
server.close();
for (const f of failures.slice(0, 40)) console.log(`FAIL ${f}`);
if (failures.length > 40) console.log(`… and ${failures.length - 40} more`);
console.log(failures.length ? `${failures.length} of ${checks} checks failed` : `all checks passed (${checks})`);
process.exit(failures.length ? 1 : 0);
