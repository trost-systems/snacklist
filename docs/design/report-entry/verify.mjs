// Drives the report-entry page in Chromium: measures the comparison table with real clicks, checks Legal's
// form rules (N-226 to N-229) on the live phones, checks layout at 200 % and writes the screenshots.
// Usage: node verify.mjs [<folder or url>] [<out dir>] [<playwright module dir>] [--write]
//   folder: served on 127.0.0.1 (default: the repo root, page at docs/design/report-entry/); a built preview
//   folder has the page at report-entry/. --write puts the measured tables into both RECOMMENDATION files.
import { createRequire } from 'node:module';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve } from './tools/serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const write = process.argv.includes('--write');
const target = args[0] ?? join(here, '../../..');
const out = args[1] ?? '/tmp/report-entry-shots';
const pwDir = args[2] ?? join(here, '../../../e2e');
const require = createRequire(join(pwDir, 'package.json'));
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = createRequire('/home/agents/family-groceries/e2e/package.json')('playwright')); }

let base;
let server;
let built = false;
if (/^https?:/.test(target)) base = target.replace(/\/$/, '');
else {
  ({ server, url: base } = await serve(target));
  built = await stat(join(target, 'report-entry/index.html')).then(() => true, () => false);
  base += built ? '/report-entry/' : '/docs/design/report-entry/';
}

let passed = 0;
const failures = [];
const check = (ok, what) => { if (ok) passed++; else { failures.push(what); console.log(`FAIL ${what}`); } };

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1800, height: 1000 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

const open = async (q = '') => {
  await page.goto(`${base}${q}`);
  await page.waitForSelector('body[data-ready]');
  await page.evaluate(() => document.fonts.ready);
};

// A fresh phone on top of the page, so every measurement starts from the same state.
const probe = (option, lang, ts, state = {}, fb4 = true) => page.evaluate(async ({ option, lang, ts, state, fb4 }) => {
  document.querySelector('#probe')?.remove();
  const { Phone } = await import(new URL('phone.js', location.href).href);
  const el = document.createElement('div');
  el.id = 'probe';
  el.className = `phone${ts === 200 ? ' ts200' : ''}`;
  Object.assign(el.style, { position: 'fixed', left: '0', top: '0', zIndex: '999' });
  document.body.append(el);
  el.phone = new Phone(el, { option, lang, fb4, state });
}, { option, lang, ts, state, fb4 });

const screenOf = () => page.evaluate(() => {
  const p = document.querySelector('#probe');
  return { screen: p.dataset.screen, sheet: p.dataset.sheet };
});

// How far the control sits outside its scroller's visible part (0 = in view), and the tab bar counted as cover.
const scrollNeeded = (sel) => page.evaluate((sel) => {
  const el = document.querySelector(`#probe ${sel}`);
  const sc = el.closest('.body, .sbody');
  const r = el.getBoundingClientRect();
  const v = sc.getBoundingClientRect();
  return Math.max(0, Math.round(r.bottom - v.bottom), Math.round(v.top - r.top));
}, sel);

const count = (sel) => page.locator(`#probe ${sel}`).count();

// Taps from More to a goal: each step taps the first control on screen that leads there. Scrolling is free.
async function walk(prefs, goal) {
  const steps = [];
  for (let i = 0; i < 6; i++) {
    if (goal(await screenOf())) return { taps: steps.length, steps };
    let tapped = false;
    for (const sel of prefs) {
      const loc = page.locator(`#probe ${sel}`);
      if (await loc.count()) {
        const before = await scrollNeeded(sel);
        await loc.first().scrollIntoViewIfNeeded();
        // A control under an open sheet's scrim cannot be tapped.
        if (!(await loc.first().click({ trial: true, timeout: 500 }).then(() => true, () => false))) continue;
        await loc.first().click();
        steps.push({ sel, scroll: before });
        tapped = true;
        break;
      }
    }
    if (!tapped) return { taps: null, steps };
  }
  return { taps: null, steps };
}

const toReport = ['[data-act="row:report"]', '[data-act="choose:report"]', '[data-act="report"]', '[data-act="row:hub"]'];
const toWrite = ['[data-act="write"]', '[data-act="choose:hub"]', '[data-act="row:hub"]'];
const toHub = ['[data-act="choose:hub"]', '[data-act="row:hub"]'];
const reportActs = new Set(toReport.slice(0, 3));

const opts = ['today', 'RC1', 'RC2', 'RC3'];
const langs = ['en', 'de'];
const sizes = [100, 200];
const M = {};

const modes = { on: true, off: false };
await open();
for (const o of opts) {
  M[o] = {};
  for (const [mode, fb4] of Object.entries(modes)) {
    for (const lang of langs) {
      for (const ts of sizes) {
        const m = {};
        await probe(o, lang, ts, {}, fb4);
        m.moreText = await page.evaluate(() => document.querySelector('#probe [data-group="feedback"]').innerText);
        m.groupH = await page.evaluate(() => Math.round(document.querySelector('#probe [data-group="feedback"]').getBoundingClientRect().height));
        const r = await walk(toReport, (s) => s.screen === 'form');
        m.reportTaps = r.taps;
        const entry = r.steps.find((s) => reportActs.has(s.sel));
        m.choiceScroll = entry && entry.sel !== '[data-act="row:report"]' ? entry.scroll : null;
        await probe(o, lang, ts, {}, fb4);
        m.writeTaps = (await walk(toWrite, (s) => s.sheet === 'compose')).taps;
        m.reportBesideFeedback = await count('[data-act="report"]') === 1;
        await probe(o, lang, ts, {}, fb4);
        m.hubTaps = (await walk(toHub, (s) => s.screen === 'hub')).taps;
        if (m.hubTaps != null) m.reportBesideFeedback ||= await count('[data-act="report"]') === 1;
        M[o][`${mode}-${lang}${ts}`] = m;
      }
    }
  }
}

// N-226: the More screen names reporting in every option; the report form is reachable and is never a feedback category.
for (const o of ['RC1', 'RC2', 'RC3']) {
  for (const k of Object.keys(M[o])) {
    check(/report|meld/i.test(M[o][k].moreText), `${o} ${k}: More names reporting`);
    check(M[o][k].reportTaps != null && M[o][k].reportTaps <= 2, `${o} ${k}: report form within 2 taps of More`);
    check(M[o][k].choiceScroll == null || M[o][k].choiceScroll === 0, `${o} ${k}: the report choice is in view without scrolling where it is offered`);
  }
}
for (const k of Object.keys(M.today)) check(M.today[k].reportTaps == null, `today ${k}: no report entry (baseline)`);
for (const o of opts) for (const k of Object.keys(M[o]).filter((x) => x.startsWith('off'))) check(M[o][k].hubTaps == null, `${o} ${k}: no hub without FB4`);

// Legal batch 17 Nov, N-260: the "Somewhere else" hint, verbatim.
const N260 = {
  de: 'Beschreibe, wo er ist: Name des Haushalts und der Liste und der genaue Text des Eintrags. Je genauer, desto schneller finden wir ihn.',
  en: 'Describe where it is: the household and list name and the exact text of the item. The more exact, the faster we can find it.',
};

// The form's rules, on a live phone reached from More, for every option, FB4 on and off, both languages and sizes.
const fill = (sel, text) => page.locator(`#probe ${sel}`).fill(text);
const tap = async (sel) => { const l = page.locator(`#probe ${sel}`).first(); await l.scrollIntoViewIfNeeded(); await l.click(); };
const text = (sel) => page.locator(`#probe ${sel}`).innerText();
const { copy } = await import('./copy.js');
for (const o of ['RC1', 'RC2', 'RC3']) {
  for (const [mode, fb4] of Object.entries(modes)) {
    for (const lang of langs) {
      for (const ts of sizes) {
        const k = `${o} fb4 ${mode} ${lang}${ts}`;
        const t = copy[lang];
        await probe(o, lang, ts, {}, fb4);
        const path = await walk(toReport, (x) => x.screen === 'form');
        const last = path.steps.at(-1).sel;
        const start = last === '[data-act="report"]' && fb4 ? 'hub' : 'more';
        check((await screenOf()).screen === 'form', `${k}: More → report form`);
        check(await count('[data-act^="kind:"]') === 6, `${k}: six kinds (N-228.1)`);
        check((await page.locator('#probe [data-act^="kind:"]').allInnerTexts()).join('|') === t.kinds.map(([, x]) => x).join('|'), `${k}: the kinds are B.4's, in its order`);
        check(await page.locator('#probe input[data-in="name"]').inputValue() === t.meName, `${k}: name prefilled from the account (N-228.4)`);
        check(await page.locator('#probe input[data-in="email"]').inputValue() === t.meEmail, `${k}: e-mail prefilled`);
        await tap('[data-act="send"]');
        check((await screenOf()).screen === 'form' && await count('.ferr') === 4, `${k}: Send with nothing filled stays and names 4 missing fields`);
        await tap('[data-act="kind:csam"]');
        check(await count('input:is([data-in="name"], [data-in="email"])') === 0, `${k}: child abuse material hides name and e-mail by default`);
        check((await text('[data-field="contact"]')).includes(t.csamNote), `${k}: B.4's anonymous line shows`);
        await tap('[data-act="kind:insult"]');
        check(await count('input:is([data-in="name"], [data-in="email"])') === 2, `${k}: another kind shows name and e-mail again`);
        await tap('[data-act="kind:csam"]');
        await tap('[data-act="csam-add"]');
        check(await count('input:is([data-in="name"], [data-in="email"])') === 2, `${k}: with child abuse material, name and e-mail can still be added`);
        await tap('[data-act="kind:insult"]');
        await tap('[data-act="where-open"]');
        await tap('[data-act="pick-else"]');
        check(await text('[data-field="where"] .help') === N260[lang], `${k}: "Somewhere else" shows N-260's hint word for word`);
        await tap('[data-act="send"]');
        check(await count('[data-field="where"] .ferr') === 1, `${k}: "Somewhere else" needs a description`);
        await fill('textarea[data-in="whereText"]', 'Brandt, Weekly shop');
        check(await count('[data-field="where"] .ferr') === 0, `${k}: a description is enough`);
        await tap('[data-act="where-open"]');
        check((await screenOf()).sheet === 'where', `${k}: Where opens the picker`);
        await fill('input[data-in="pick"]', lang === 'de' ? 'hafer' : 'oat');
        check(await count('.pickrow[data-act^="pick:item"]') === 1, `${k}: picker search filters items`);
        await tap('[data-act="pick:item:0"]');
        check((await text('.picked')).includes(t.items[0][1]) && (await text('[data-field="where"]')).includes(t.whereHelp), `${k}: picked item shown with B.4's "please check it" (N-228.2)`);
        await fill('textarea[data-in="reason"]', 'x'.repeat(19));
        await tap('[data-act="good"]');
        await tap('[data-act="send"]');
        check((await screenOf()).screen === 'form' && await count('[data-field="reason"] .ferr') === 1, `${k}: 19 characters are too few`);
        await fill('textarea[data-in="reason"]', 'x'.repeat(5001));
        await tap('[data-act="send"]');
        check((await screenOf()).screen === 'form' && await count('[data-field="reason"] .ferr') === 1 && await count('.counter.over') === 1, `${k}: 5,001 characters are refused`);
        await fill('textarea[data-in="reason"]', 'x'.repeat(5000));
        check(await count('[data-field="reason"] .ferr') === 0, `${k}: 5,000 characters are fine (N-228.3)`);
        await tap('[data-act="good"]');
        await tap('[data-act="send"]');
        check((await screenOf()).screen === 'form' && await count('[data-field="good"] .ferr') === 1, `${k}: good faith is required (N-228.5)`);
        await tap('[data-act="good"]');
        await fill('input[data-in="name"]', '');
        await fill('input[data-in="email"]', '');
        await tap('[data-act="send"]');
        check((await screenOf()).screen === 'done', `${k}: sends without name and e-mail (recommended, not required)`);
        const ref = await text('.ref');
        check(/^R-[2-9A-HJKMNP-Z]{6}$/.test(ref), `${k}: reference number on screen (N-229): ${ref}`);
        check(await text('.thanks') === t.thanks(ref), `${k}: B.4's on-screen confirmation, word for word, with the number`);
        check((await text('.done')).includes(t.notMailed), `${k}: no e-mail given, no reply promised`);
        await tap('[data-act="done"]');
        const back = await screenOf();
        check(back.screen === start && back.sheet === '', `${k}: Done returns to where the report started (${start})`);
        if (fb4) {
          if (back.screen !== 'hub') await walk(toHub, (x) => x.screen === 'hub');
          check(await count('.card:not(.idea)') === 3, `${k}: the report is not under Your notes (N-227)`);
        }
        await probe(o, lang, ts, {}, fb4);
        await walk(toWrite, (x) => x.sheet === 'compose');
        check((await page.locator('#probe .sheet .chips .tact').allInnerTexts()).join('|') === [t.catBug, t.catIdea, t.catOther].join('|'), `${k}: the feedback form's kinds are Bug, Idea, Other only (N-226)`);
      }
    }
  }
}

// B.4's strings in copy.js, word for word in Legal's addendum (outside the repo; skipped where it isn't).
const addendum = process.env.LEGAL_ADDENDUM ?? '/home/agents/groceries-ops/jobs/278-proto-report-entry/in/legal-addendum-B.md';
const legalText = await readFile(addendum, 'utf8').catch(() => null);
if (legalText) {
  for (const lang of langs) {
    const t = copy[lang];
    const legal = { intro: t.intro, about: t.about, where: t.where, whereHelp: t.whereHelp, why: t.why, whyHelp: t.whyHelp, name: t.name, email: t.email, recommended: t.recommended, contactHelp: t.contactHelp, csamNote: t.csamNote, goodFaith: t.goodFaith, shotHelp: t.shotHelp, footerLink: t.footerLink, sendReport: t.sendReport, thanks: t.thanks('{ref}'), hubReports: t.hubReports, alsoReport: t.alsoReport, report: t.report };
    t.kinds.forEach(([k, v]) => { legal[`kind ${k}`] = v; });
    for (const [key, v] of Object.entries(legal)) check(legalText.includes(v), `${lang}: ${key} is Legal's text`);
  }
} else console.log(`skipped: Legal's addendum not at ${addendum}`);

// Layout on every storyboard phone: nothing outside the phone, cut or overlapping, 44 px targets.
const layout = () => page.evaluate(() => {
  const bad = [];
  for (const p of document.querySelectorAll('.phone[data-frame]')) {
    const pr = p.getBoundingClientRect();
    for (const el of p.querySelectorAll('*')) {
      if (!el.childNodes.length || el.closest('.homeind, .status')) continue;
      const hasText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
      const r = el.getBoundingClientRect();
      if (hasText && r.width && (r.right > pr.right + 1 || r.left < pr.left - 1)) bad.push(`${p.dataset.frame}: outside "${el.textContent.trim().slice(0, 30)}"`);
      if (hasText && el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible') bad.push(`${p.dataset.frame}: cut "${el.textContent.trim().slice(0, 30)}"`);
      if (hasText && el.scrollHeight > el.clientHeight + 1 && getComputedStyle(el).overflowY === 'hidden') bad.push(`${p.dataset.frame}: cut below "${el.textContent.trim().slice(0, 30)}"`);
    }
    for (const sc of p.querySelectorAll('.body, .sbody')) {
      const kids = [...sc.children].filter((c) => c.getBoundingClientRect().height);
      for (let i = 1; i < kids.length; i++) {
        if (kids[i].getBoundingClientRect().top < kids[i - 1].getBoundingClientRect().bottom - 1) bad.push(`${p.dataset.frame}: overlap after "${kids[i - 1].textContent.trim().slice(0, 30)}"`);
      }
    }
    for (const t of p.querySelectorAll('[data-act]:not(.scrim)')) {
      const r = t.getBoundingClientRect();
      if (r.height && r.height < 44) bad.push(`${p.dataset.frame}: target ${Math.round(r.height)} px "${t.dataset.act}"`);
    }
  }
  return bad;
});

await mkdir(out, { recursive: true });
const cut = {};
const looks = [];
for (const lang of langs) for (const theme of ['light', 'dark']) for (const ts of sizes) looks.push({ lang, theme, ts, fb4: 'on' });
for (const lang of langs) for (const theme of ['light', 'dark']) for (const ts of sizes) looks.push({ lang, theme, ts, fb4: 'off' });
for (const { lang, theme, ts, fb4 } of looks) {
  {
    {
      const q = new URLSearchParams();
      if (fb4 === 'off') q.set('fb4', 'off');
      if (lang === 'de') q.set('lang', 'de');
      if (theme === 'dark') q.set('theme', 'dark');
      if (ts === 200) q.set('ts', '200');
      await open(q.toString() ? `?${q}` : '');
      const bad = await layout();
      bad.forEach((b) => console.log(`  layout ${lang} ${theme} ${ts} fb4 ${fb4}: ${b}`));
      check(bad.length === 0, `layout ${lang} ${theme} ${ts} fb4 ${fb4}: ${bad.length} problems`);
      cut[`${lang}${ts}`] = (cut[`${lang}${ts}`] ?? 0) + bad.length;
      const tags = await page.locator('.option > h2 .tag').allInnerTexts();
      check(tags.length === 2, `${lang}: pick and runner-up tagged`);
      check(lang === 'en' ? await page.locator('.page-head h1').innerText() === 'Report content entry (RC1–RC3)' : /Inhalt melden/.test(await page.locator('.page-head h1').innerText()), `${lang}: page language`);
      for (const el of await page.locator('.phone[data-frame]').all()) {
        const f = (await el.getAttribute('data-frame')).replace(':', '-');
        await el.screenshot({ path: join(out, `${f}-${lang}-${theme}-${ts}${fb4 === 'off' ? '-nofb4' : ''}.png`) });
      }
    }
  }
}
await page.setViewportSize({ width: 390, height: 844 });
await open();
check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'page fits a 390 px phone');
await page.screenshot({ path: join(out, 'page-390.png') });
await page.setViewportSize({ width: 1800, height: 1000 });
await open();
await page.screenshot({ path: join(out, 'page-overview.png') });
if (await page.locator('.back-link').count()) {
  const href = await page.locator('.back-link').getAttribute('href');
  const res = await page.request.get(new URL(href, page.url()).href);
  if (built || !server) check(res.ok(), `back link ${href} answers (${res.status()})`);
}
if (built) {
  await page.goto(new URL('../', base).href);
  const link = page.locator('a[href*="report-entry"]').first();
  await link.waitFor({ timeout: 10000 }).catch(() => {});
  check(await link.count() === 1, 'overview links this round');
  if (await link.count()) {
    await link.click();
    await page.waitForSelector('body[data-ready]');
    check(/RC1–RC3/.test(await page.locator('.page-head h1').innerText()), 'overview → round opens this page');
  }
}
check(errors.length === 0, `no page errors: ${errors.join(' | ')}`);

// The measured tables, in both languages.
const W = {
  en: {
    head: ['Option', 'More names reporting (FB4 on / off)', 'Taps from More to the report form, FB4 on / off', 'Report choice in view where it is offered (100 % and 200 %, both FB4 states)', 'Taps to write feedback, FB4 on / off (today 2 / 1)', 'Taps to notes and ideas, FB4 on (today 1)', 'Report offered on the feedback screen (hub or sheet), FB4 on / off', 'Feedback group on More vs today, 100 % / 200 % (more of FB4 on and off)', 'Text cut, outside or overlapping at 200 %'],
    names: { today: 'Today', RC1: 'RC1 Chooser sheet', RC2: 'RC2 Two buttons in the hub', RC3: 'RC3 Its own More row' },
    no: 'no', none: 'none (e-mail only)', isRow: '— (the More row itself)', yes: 'yes', scroll: (n) => `scroll ${n} px`,
  },
  de: {
    head: ['Option', 'Mehr nennt Melden (FB4 an / aus)', 'Tipps von Mehr zum Meldeformular, FB4 an / aus', 'Meldewahl ohne Scrollen sichtbar, wo sie angeboten wird (100 % und 200 %, beide FB4-Zustände)', 'Tipps bis Feedback schreiben, FB4 an / aus (heute 2 / 1)', 'Tipps bis Notizen und Ideen, FB4 an (heute 1)', 'Melden auf dem Feedback-Bildschirm angeboten (Übersicht oder Blatt), FB4 an / aus', 'Feedback-Gruppe in Mehr gegenüber heute, 100 % / 200 % (mehr von FB4 an und aus)', 'Text abgeschnitten, außerhalb oder überlappend bei 200 %'],
    names: { today: 'Heute', RC1: 'RC1 Auswahlblatt', RC2: 'RC2 Zwei Knöpfe in der Übersicht', RC3: 'RC3 Eigene Zeile in Mehr' },
    no: 'nein', none: 'keine (nur E-Mail)', isRow: '— (die Zeile in Mehr selbst)', yes: 'ja', scroll: (n) => `${n} px scrollen`,
  },
};
// One value when the languages and sizes agree, else every value (a difference the table must show).
const same = (o, mode, f) => { const v = langs.flatMap((l) => sizes.map((s) => f(M[o][`${mode}-${l}${s}`]))); return v.every((x) => x === v[0]) ? v[0] : v.join('/'); };
const both = (o, f, show = String) => ['on', 'off'].map((mode) => show(same(o, mode, f))).join(' / ');
function table(L) {
  const w = W[L];
  const rows = opts.map((o) => {
    const named = ['on', 'off'].map((mode) => M[o][`${mode}-${L}100`].moreText.split('\n').map((x) => x.trim()).filter((x) => /report|meld/i.test(x))).map((v) => (v.length ? v.map((x) => (L === "de" ? `„${x}“` : `“${x}”`)).join(', ') : w.no)).join(' / ');
    const rt = both(o, (x) => x.reportTaps, (v) => (v == null ? w.none : String(v)));
    const worstScroll = Math.max(...Object.values(M[o]).map((x) => x.choiceScroll ?? 0));
    const choice = o === 'today' ? '—' : o === 'RC3' ? w.isRow : worstScroll ? w.scroll(worstScroll) : w.yes;
    const dh = sizes.map((s) => { const d = Math.max(...['on', 'off'].flatMap((mode) => langs.map((l) => M[o][`${mode}-${l}${s}`].groupH - M.today[`${mode}-${l}${s}`].groupH))); return d ? `+${d} px` : '0 px'; }).join(' / ');
    return [o === 'today' ? w.names[o] : `**${w.names[o]}**`, named, rt, choice, both(o, (x) => x.writeTaps), String(same(o, 'on', (x) => x.hubTaps)), both(o, (x) => x.reportBesideFeedback, (v) => (v === true ? w.yes : w.no)), dh, String(cut[`${L}200`])];
  });
  return [`| ${w.head.join(' | ')} |`, `|${w.head.map(() => ' --- ').join('|')}|`, ...rows.map((r) => `| ${r.join(' | ')} |`)].join('\n');
}

for (const [L, file] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) {
  const t = table(L);
  console.log(`\n${t}\n`);
  const path = join(here, file);
  const src = await readFile(path, 'utf8');
  const re = /<!-- table -->\n[^]*?\n<!-- \/table -->/;
  const next = `<!-- table -->\n${t}\n<!-- /table -->`;
  if (write) await writeFile(path, src.replace(re, next));
  else check(re.test(src) && src.match(re)[0] === next, `${file}: table matches the measurement (run with --write)`);
}

await browser.close();
server?.close();
if (failures.length) { console.log(`${failures.length} checks failed, ${passed} passed`); process.exit(1); }
console.log(`all checks passed (${passed})`);
