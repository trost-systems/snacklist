// Drives the display-name rounds in Chromium: walks every option with real clicks, measures taps and screens per
// scenario, checks text at 100 % and 200 % for spills, overlaps and small targets, checks what Peter and the join page
// show after each walk or save, checks both languages, and compares the measurements with measured.json and the tables
// in RECOMMENDATION.md / .de.md (--write updates them). Writes screenshots into <out>.
// Usage: node verify.mjs [<repo root or build dir>] [<screenshot dir>] [<playwright dir>] [--write]
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { tmpdir } from 'node:os';
import { serve } from './tools/serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const write = process.argv.includes('--write');
const root = resolve(args[0] || join(here, '../../..'));
const shots = resolve(args[1] || join(tmpdir(), 'display-name-shots'));
const pwDir = args[2] || [join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
const base = existsSync(join(root, 'display-name/index.html')) ? '/display-name/' : '/docs/design/display-name/';
const src = existsSync(join(root, 'display-name/index.html')) ? join(root, 'display-name') : here;

let checks = 0;
const fails = [];
const ok = (cond, msg) => { checks++; if (!cond) fails.push(msg); };

const { server, url } = await serve(root);
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1700, height: 1000 } });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

const open = async (path, q = {}) => {
  const qs = new URLSearchParams(q).toString();
  await page.goto(`${url}${base}${path}${qs ? `?${qs}` : ''}`);
  await page.waitForSelector('body[data-ready="1"]', { timeout: 15000 });
};

const PERSONAS = ['email', 'google', 'appleHidden', 'long', 'emoji'];
const MEASURE = ['email', 'google', 'appleHidden'];
const DN_OPTIONS = ['today', 'DN1', 'DN2', 'DN3', 'DN4', 'DN5'];
const DE_OPTIONS = ['today', 'DE1', 'DE2', 'DE3', 'DE4', 'DE5'];
const TYPED = { email: 'Lea', google: 'Lea', appleHidden: 'Lea', long: 'Maximiliane Theodora von Hohenzollern-Sigmaringen', emoji: 'Lea 🌻' };

// What a phone shows that should not: text cut or spilling past the phone, a horizontal scroll, consecutive blocks
// overlapping, a control under 44 px.
const layoutIssues = (sel) => page.$eval(sel, (ph) => {
  const out = [];
  const pr = ph.getBoundingClientRect();
  const z = Number(ph.style.zoom || 1);
  for (const el of ph.querySelectorAll('.body, .web, .sbody')) if (el.scrollWidth > el.clientWidth + 1) out.push(`horizontal scroll in .${el.className.split(' ')[0]} (${el.scrollWidth} > ${el.clientWidth})`);
  for (const el of ph.querySelectorAll('*')) {
    if (el.closest('svg') || el.tagName === 'INPUT') continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    if (!r.width || !r.height) continue;
    if (el.closest('.body, .web, .sbody') && el.scrollWidth > el.clientWidth + 1 && cs.overflowX !== 'auto' && !el.matches('.body,.web,.sbody')) out.push(`text wider than its box: “${el.textContent.trim().slice(0, 40)}”`);
    if (r.right > pr.right + 1 || r.left < pr.left - 1) out.push(`past the phone's edge: “${el.textContent.trim().slice(0, 40)}”`);
  }
  for (const col of ph.querySelectorAll('.col, .sbody, .groups, .web')) {
    const kids = [...col.children].filter((k) => getComputedStyle(k).position !== 'absolute' && k.getBoundingClientRect().height);
    for (let i = 1; i < kids.length; i++) {
      const a = kids[i - 1].getBoundingClientRect();
      const b = kids[i].getBoundingClientRect();
      if (a.bottom > b.top + 1) out.push(`overlap: “${kids[i - 1].textContent.trim().slice(0, 30)}” over “${kids[i].textContent.trim().slice(0, 30)}”`);
    }
  }
  for (const el of ph.querySelectorAll('[data-act]:not(.scrim)')) {
    const r = el.getBoundingClientRect();
    if (r.height && (r.height / z < 43.5 || r.width / z < 43.5)) out.push(`target ${Math.round(r.width / z)}×${Math.round(r.height / z)}: ${el.dataset.act}`);
  }
  if (/undefined|NaN|\[object/.test(ph.textContent)) out.push('undefined in the text');
  return [...new Set(out)];
});

const st = (sel) => page.$eval(sel, (el) => ({ screen: el.phone.s.screen, sheet: el.phone.s.sheet, invited: el.phone.s.invited, taps: el.phone.taps, typed: el.phone.typed,
  screens: el.phone.trail.filter((x, i, a) => x !== a[i - 1]).length, seen: el.phone.seen() }));
const has = (sel, act) => page.locator(`${sel} [data-act="${act}"]`).count().then((n) => n > 0);
const click = async (sel, act) => { await page.locator(`${sel} [data-act="${act}"]`).first().click(); };
const value = (sel, f) => page.locator(`${sel} input[data-field="${f}"]`).inputValue();
const fill = async (sel, f, v) => { const i = page.locator(`${sel} input[data-field="${f}"]`); await i.click(); await i.fill(v); };

// One walk from the first screen to the list. `skip`: never type a name where it can be left out.
async function walkDN(sel, persona, { skip = false, check = null } = {}) {
  for (let n = 0; n < 40; n++) {
    const s = await st(sel);
    if (check) await check(s);
    const name = TYPED[persona];
    if (s.screen === 'list') return s;
    if (s.sheet === 'google' || s.sheet === 'apple') { await click(sel, 'sys'); continue; }
    if (s.sheet === 'ask') { if (skip) await click(sel, 'askLater'); else { await fill(sel, 'ask', name); await click(sel, 'askSave'); } continue; }
    switch (s.screen) {
      case 'hello': if (skip) await click(sel, 'skip'); else { if (!(await value(sel, 'you'))) await fill(sel, 'you', name); await click(sel, 'next'); } break;
      case 'who': await click(sel, 'chip:partner'); await click(sel, 'next'); break;
      case 'you': if (!(await value(sel, 'you'))) await fill(sel, 'you', name); await click(sel, 'next'); break;
      case 'hhname': if (!skip && (await page.locator(`${sel} input[data-field="you"]`).count()) && !(await value(sel, 'you'))) await fill(sel, 'you', name); await click(sel, 'next'); break;
      case 'stores': await click(sel, 'skip'); break;
      case 'need': await click(sel, 'chip:0'); await click(sel, 'chip:1'); await click(sel, 'next'); break;
      case 'account': await click(sel, { email: 'email', google: 'google', apple: 'apple' }[{ email: 'email', google: 'google', appleHidden: 'apple', long: 'google', emoji: 'email' }[persona]]); break;
      case 'emailSignup': await click(sel, 'register'); break;
      case 'confirm': if (await has(sel, 'yes')) await click(sel, 'yes'); else { await fill(sel, 'you', name); await click(sel, 'next'); } break;
      case 'invite': await click(sel, s.invited ? 'toList' : 'invite'); break;
      case 'joinpage': await click(sel, 'join'); break;
      case 'joinconfirm': if (!skip && (await page.locator(`${sel} input[data-field="you"]`).count()) && !(await value(sel, 'you'))) await fill(sel, 'you', name); await click(sel, 'joinHousehold'); break;
      default: throw new Error(`no step for ${s.screen}`);
    }
  }
  throw new Error(`walk did not reach the list: ${sel}`);
}

const DE_PATH = { DE1: ['tab:more', 'row:accountPage', 'edit'], DE2: ['tab:more', 'row:household', 'edit'], DE3: ['tab:more', 'editInline'], DE4: ['tab:more', 'row:invites', 'edit'], DE5: ['tab:more', 'row:household', 'edit'] };
const ENTRY_SCREEN = { DE1: 'accountPage', DE2: 'household', DE3: 'more', DE4: 'invites', DE5: 'household' };

const measured = { DN: { create: {}, join: {}, skip: { create: {}, join: {} } }, DE: {} };
const overflow = {};
const flag = (opt, items, where) => { const k = / 310 % /.test(where) ? `${opt}@310` : opt; for (const i of items) (overflow[k] ??= new Set()).add(`${where}: ${i}`); };

// ---- Round DN ----
for (const role of ['create', 'join']) {
  for (const persona of PERSONAS) {
    for (const ts of ['100', '200', '310']) {
      for (const lang of ['en', 'de']) {
        const measure = ts === '100' && lang === 'en' && MEASURE.includes(persona);
        await open('dn/', { role, persona, ts, lang });
        for (const opt of DN_OPTIONS) {
          const sel = `.phone[data-frame="${opt}:walk"]`;
          const end = await walkDN(sel, persona, { check: async (s) => flag(opt, await layoutIssues(sel), `DN ${role} ${persona} ${lang} ${ts} % ${s.screen}${s.sheet ? `+${s.sheet}` : ''}`) });
          if (measure) (measured.DN[role][persona] ??= {})[opt] = { taps: end.taps, screens: end.screens, typed: end.typed, member: end.seen.member, join: end.seen.join };
          if (persona === 'emoji') {
            ok(end.seen.member === (opt === 'today' ? 'lea.brandt87' : 'Lea 🌻'), `DN ${role} emoji ${opt}: member list shows ${end.seen.member}`);
          }
        }
        // The other frames, as they open.
        for (const el of await page.locator('.phone[data-frame]:not([data-frame$=":walk"]), .phone[data-peer]').all()) {
          const id = (await el.getAttribute('data-frame')) ?? (await el.getAttribute('data-peer'));
          flag(id.split(':')[0], await layoutIssues(`.phone[data-frame="${id}"], .phone[data-peer="${id}"]`), `DN ${role} ${persona} ${lang} ${ts} % frame ${id}`);
        }
      }
    }
    if (MEASURE.includes(persona)) {
      await open('dn/', { role, persona });
      for (const opt of DN_OPTIONS) {
        const end = await walkDN(`.phone[data-frame="${opt}:walk"]`, persona, { skip: true });
        (measured.DN.skip[role][persona] ??= {})[opt] = { taps: end.taps, screens: end.screens, typed: end.typed, member: end.seen.member, join: end.seen.join };
      }
      // The strip follows the last walk that reached the list.
      const strip = await page.$eval('.phone[data-peer="peerHousehold"]', (el) => el.textContent);
      ok(strip.includes(measured.DN.skip[role][persona].today.member), `DN ${role} ${persona}: the strip shows the last walk's name`);
    }
  }
}

// Behaviour pins: a chosen name wins over Google's; the join page never shows the e-mail prefix.
for (const role of ['create', 'join']) {
  const g = measured.DN[role].google;
  const e = measured.DN[role].email;
  ok(e.today.member === 'lea.brandt87' && e.today.join === null, `DN ${role} today e-mail: member “lea.brandt87”, no name on the join page (got ${e.today.member} / ${e.today.join})`);
  ok(g.today.member === 'Lea Brandt' && g.today.join === 'Lea', `DN ${role} today Google: “Lea Brandt”, join page “Lea”`);
  for (const opt of ['DN1', 'DN2', 'DN3', 'DN4', 'DN5']) ok(e[opt].member === 'Lea' && e[opt].join === 'Lea', `DN ${role} ${opt} e-mail, complete walk: the typed name reaches Peter and the join page (${e[opt].member} / ${e[opt].join})`);
  for (const opt of ['DN1', 'DN3']) ok(measured.DN.skip[role].email[opt].member === 'Lea', `DN ${role} ${opt} is required: no way past it without a name`);
}
ok(measured.DN.create.google.DN1.member === 'Lea', 'DN1 create with Google: the name typed before the account wins over “Lea Brandt”');
ok(measured.DN.create.google.DN3.typed === false && measured.DN.create.google.DN4.typed === false, 'DN3 and DN4 with Google: no typing');

// ---- Round DE ----
for (const persona of PERSONAS) {
  for (const ts of ['100', '200', '310']) {
    for (const lang of ['en', 'de']) {
      await open('de/', { persona, ts, lang });
      for (const el of await page.locator('.phone[data-frame]:not([data-frame$=":walk"]), .phone[data-peer]').all()) {
        const id = (await el.getAttribute('data-frame')) ?? (await el.getAttribute('data-peer'));
        flag(id.split(':')[0], await layoutIssues(`.phone[data-frame="${id}"], .phone[data-peer="${id}"]`), `DE ${persona} ${lang} ${ts} % frame ${id}`);
      }
      for (const opt of DE_OPTIONS.slice(1)) {
        const sel = `.phone[data-frame="${opt}:walk"]`;
        const visible = {};
        for (const act of DE_PATH[opt]) {
          const s = await st(sel);
          if (s.screen === ENTRY_SCREEN[opt] && !s.sheet) {
            // The entry is whole above the floating tabs, without scrolling.
            visible.v = await page.$eval(sel, (ph) => {
              const e = ph.querySelector('[data-name-entry]');
              const tabs = ph.querySelector('.tabs').getBoundingClientRect();
              return !!e && e.getBoundingClientRect().bottom <= tabs.top;
            });
          }
          await click(sel, act);
          flag(opt, await layoutIssues(sel), `DE ${persona} ${lang} ${ts} % ${act}`);
        }
        const newName = persona === 'long' ? 'Lea' : 'Lea Maria Brandt-Sommerfeld';
        await page.locator(`${sel} input[data-field="edit"]`).fill(newName);
        flag(opt, await layoutIssues(sel), `DE ${persona} ${lang} ${ts} % typed`);
        await click(sel, opt === 'DE3' ? 'inlineDone' : 'save');
        const s = await st(sel);
        ok(s.seen.member === newName && !s.sheet, `DE ${opt} ${persona}: saved (${s.seen.member})`);
        const strip = await page.$eval('#spread', (el) => el.textContent);
        ok(strip.includes(newName) && strip.includes(newName.split(' ')[0]), `DE ${opt} ${persona} ${lang}: Peter's member list, his list and the join page show the new name`);
        if (lang === 'en' && persona === 'email') {
          const r = (measured.DE[opt] ??= { taps: s.taps, screens: s.screens });
          r[`visible${ts}`] = visible.v;
        }
      }
      if (lang === 'en' && persona === 'email') {
        // How far More's first row moves down.
        const rowY = (f) => page.$eval(`.phone[data-frame="${f}"]`, (ph) => ph.querySelector('[data-act="row:accountPage"]').getBoundingClientRect().top - ph.getBoundingClientRect().top);
        measured.DE[`pushed${ts}`] = Math.round((await rowY('DE3:more')) - (await rowY('today:more')));
      }
    }
  }
}

// ---- Overview, languages, back links ----
await open('', {});
ok((await page.locator('[data-round-link]').count()) === 2, 'overview links both rounds');
await page.locator('[data-round-link="DN"]').click();
await page.waitForSelector('body[data-ready="1"]');
ok(page.url().includes('/dn/'), 'overview → DN');
await page.locator('.back-link').click();
await page.waitForSelector('body[data-ready="1"]');
ok(!page.url().includes('/dn/'), 'DN → back to the overview');
for (const r of ['dn/', 'de/', '']) {
  await open(r, { lang: 'de' });
  const t = await page.textContent('#app');
  ok(await page.$eval('html', (h) => h.lang === 'de'), `${r || 'overview'}: German with ?lang=de`);
  ok(!/Walk it|Pick:|Runner-up|Step \d of/.test(t), `${r || 'overview'} DE: no English page words`);
  await open(r, {});
  ok(!/Schritt \d von|Wahl:/.test(await page.textContent('#app')), `${r || 'overview'} EN: no German page words`);
}

// ---- On a phone: no page scrolls sideways (Peter opens the preview on his phone) ----
const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
const mp = await mobile.newPage();
mp.on('pageerror', (e) => errors.push(String(e)));
for (const r of ['', 'dn/', 'de/']) {
  for (const q of [{}, { lang: 'de' }, { ts: '200' }, { ts: '310', lang: 'de' }, { role: 'join', persona: 'long' }]) {
    await mp.goto(`${url}${base}${r}?${new URLSearchParams(q)}`);
    await mp.waitForSelector('body[data-ready="1"]', { timeout: 15000 });
    const w = await mp.evaluate(() => ({ doc: document.documentElement.scrollWidth, vw: innerWidth, wide: [...document.querySelectorAll('body *')].filter((e) => !e.closest('.phone, .table-wrap') && e.getBoundingClientRect().right > innerWidth + 1).slice(0, 3).map((e) => e.className || e.tagName) }));
    ok(w.vw === 390 && w.doc <= 391 && w.wide.length === 0, `390 px ${r || 'overview'} ${JSON.stringify(q)}: no sideways scroll (layout ${w.vw}, page ${w.doc}, wide: ${w.wide.join(', ')})`);
  }
}
await mobile.close();

// ---- Recommendations ----
const L = {
  en: { yes: 'yes', no: 'no', required: 'required', none: 'none', see: 'see verify output',
    DN: ['Option', 'Screens added, create (e-mail / Google)', 'Taps added, create (e-mail / Google / Apple hidden)', 'Taps added, join (e-mail / Google)', 'Typing, create (e-mail / Google / Apple hidden)', 'Peter sees (e-mail)', 'If skipped (create / join)', 'Overflow at 100 % and 200 %', 'Overflow at 310 %'],
    DE: ['Option', 'Taps from the list to saved', 'Screens and sheets', 'Entry visible without scrolling (100 % / 200 % / 310 %)', 'More’s rows pushed down (100 % / 200 % / 310 %)', 'Overflow at 100 % and 200 %', 'Overflow at 310 %'] },
  de: { yes: 'ja', no: 'nein', required: 'Pflicht', none: 'keiner', see: 'siehe Ausgabe des Prüfskripts',
    DN: ['Option', 'Bildschirme mehr, anlegen (E-Mail / Google)', 'Tipps mehr, anlegen (E-Mail / Google / Apple verborgen)', 'Tipps mehr, beitreten (E-Mail / Google)', 'Getippt, anlegen (E-Mail / Google / Apple verborgen)', 'Peter sieht (E-Mail)', 'Übersprungen (anlegen / beitreten)', 'Überlauf bei 100 % und 200 %', 'Überlauf bei 310 %'],
    DE: ['Option', 'Tipps ab der Liste bis gespeichert', 'Bildschirme und Blätter', 'Einstieg ohne Scrollen sichtbar (100 % / 200 % / 310 %)', 'Zeilen von Mehr nach unten (100 % / 200 % / 310 %)', 'Überlauf bei 100 % und 200 %', 'Überlauf bei 310 %'] },
};
const tableOf = (round, lang) => {
  const m = measured;
  const w = L[lang];
  const cell = (b) => (b ? w.yes : w.no);
  const iss = (o) => (overflow[o]?.size ? `${overflow[o].size} (${w.see})` : w.none);
  const head = (h) => [`| ${h.join(' | ')} |`, `| ${h.map(() => '---').join(' | ')} |`];
  if (round === 'DN') {
    const d = (role, p, o, k) => m.DN[role][p][o][k] - m.DN[role][p].today[k];
    const fmt = (n) => (n > 0 ? `+${n}` : String(n));
    const rows = DN_OPTIONS.map((o) => `| ${o} | ${fmt(d('create', 'email', o, 'screens'))} / ${fmt(d('create', 'google', o, 'screens'))} | ${MEASURE.map((p) => fmt(d('create', p, o, 'taps'))).join(' / ')} | ${MEASURE.slice(0, 2).map((p) => fmt(d('join', p, o, 'taps'))).join(' / ')} | ${MEASURE.map((p) => cell(m.DN.create[p][o].typed)).join(' / ')} | ${m.DN.create.email[o].member} | ${['create', 'join'].map((r) => (m.DN.skip[r].email[o].typed && o !== 'today' ? w.required : m.DN.skip[r].email[o].member)).join(' / ')} | ${iss(o)} | ${iss(`${o}@310`)} |`);
    return [...head(w.DN), ...rows].join('\n');
  }
  const rows = DE_OPTIONS.slice(1).map((o) => `| ${o} | ${m.DE[o].taps} | ${m.DE[o].screens} | ${cell(m.DE[o].visible100)} / ${cell(m.DE[o].visible200)} / ${cell(m.DE[o].visible310)} | ${o === 'DE3' ? `${m.DE.pushed100} px / ${m.DE.pushed200} px / ${m.DE.pushed310} px` : '0'} | ${iss(o)} | ${iss(`${o}@310`)} |`);
  return [...head(w.DE), ...rows].join('\n');
};
const markers = /<!-- table:start -->[\s\S]*?<!-- table:end -->/;
for (const [round, dir] of [['DN', 'dn'], ['DE', 'de']]) {
  const mjson = join(src, dir, 'measured.json');
  const now = JSON.stringify(round === 'DN' ? measured.DN : measured.DE, null, 1);
  for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
    const table = tableOf(round, f.includes('.de.') ? 'de' : 'en');
    const p = join(src, dir, f);
    const md = readFileSync(p, 'utf8');
    if (write) writeFileSync(p, md.replace(markers, `<!-- table:start -->\n${table}\n<!-- table:end -->`));
    else ok(md.match(markers)?.[0] === `<!-- table:start -->\n${table}\n<!-- table:end -->`, `${dir}/${f}: the table matches the measurement (rerun with --write)`);
    const pick = md.match(/<!-- pick: (\w+) -->/)?.[1];
    const runner = md.match(/<!-- runner-up: (\w+) -->/)?.[1];
    ok(pick && runner && pick !== runner && pick.startsWith(round) && runner.startsWith(round), `${dir}/${f}: a pick and a runner-up`);
    ok(new RegExp(`${round}-Q1\\b`).test(md), `${dir}/${f}: open questions numbered ${round}-Q1..`);
  }
  const [a, b] = ['RECOMMENDATION.md', 'RECOMMENDATION.de.md'].map((f) => readFileSync(join(src, dir, f), 'utf8').match(/<!-- (pick|runner-up): \w+ -->/g)?.join());
  ok(a === b, `${dir}: English and German name the same pick and runner-up`);
  if (write) writeFileSync(mjson, `${now}\n`);
  else ok(existsSync(mjson) && readFileSync(mjson, 'utf8').trim() === now.trim(), `${dir}/measured.json matches (rerun with --write)`);
}

// ---- Screenshots ----
mkdirSync(shots, { recursive: true });
for (const [r, q, name] of [
  ['dn/', {}, 'DN-en-light-100'], ['dn/', { lang: 'de', theme: 'dark', ts: '200' }, 'DN-de-dark-200'], ['dn/', { role: 'join', persona: 'google' }, 'DN-join-google-en-light-100'],
  ['dn/', { persona: 'long', ts: '200' }, 'DN-long-en-light-200'],
  ['de/', {}, 'DE-en-light-100'], ['de/', { lang: 'de', theme: 'dark', ts: '200' }, 'DE-de-dark-200'], ['de/', { persona: 'emoji', ts: '200' }, 'DE-emoji-en-light-200'],
]) {
  await open(r, q);
  for (const id of r === 'dn/' ? ['DN1', 'DN2', 'DN3', 'DN4', 'DN5', 'today', 'spread'] : ['DE1', 'DE2', 'DE3', 'DE4', 'DE5', 'today', 'spread']) {
    await page.locator(`#${id}`).screenshot({ path: join(shots, `${name}-${id}.png`) });
  }
}
await open('', {});
await page.screenshot({ path: join(shots, 'overview.png'), fullPage: true });
await page.setViewportSize({ width: 390, height: 844 });
await open('dn/', {});
await page.locator('#DN4').scrollIntoViewIfNeeded();
await page.screenshot({ path: join(shots, 'DN-phone-390x844.png') });
await open('', {});
await page.screenshot({ path: join(shots, 'overview-390x844.png'), fullPage: true });

ok(errors.length === 0, `page errors: ${errors.join(' | ')}`);
for (const [o, s] of Object.entries(overflow)) for (const i of [...s].slice(0, 12)) console.log(`overflow ${o}: ${i}`);
await browser.close();
server.close();
console.log(JSON.stringify({ DN_create_email: measured.DN.create.email, DE: measured.DE }, null, 0).slice(0, 3000));
if (fails.length) { for (const f of fails) console.log(`FAIL ${f}`); console.log(`${fails.length} of ${checks} checks failed`); process.exit(1); }
console.log(`all checks passed (${checks})`);
