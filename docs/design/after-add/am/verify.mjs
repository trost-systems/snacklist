// Drives round AM in Chromium and checks what the page claims.
// Usage: node am/verify.mjs [<root>] [--path /docs/design/after-add/] [--write]
// --write stores the measurements in am/measured.json; without it they must match the file.
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from '../tools/serve.mjs';
import { act, catalog, categories, copy, initial, run, stores, summary } from './model.js';
import { ids, options } from './phone.js';
import { text } from './text.js';
import { classify, outcomes, paths, verdict, words } from './walk.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const write = args.includes('--write');
const pathArg = args.includes('--path') ? args[args.indexOf('--path') + 1] : '/docs/design/after-add/';
const root = resolve(args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--path') ?? join(here, '../../../..'));
const pwDir = [join(root, 'e2e'), join(here, '../../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');

let checks = 0;
const failures = [];
const check = (ok, what) => {
  checks += 1;
  if (!ok) failures.push(what);
};

const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 1200 } });
page.setDefaultTimeout(5000);
page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
const devices = ['ios', 'android'];
const sizesFor = (device) => (device === 'ios' ? [100, 200, 310] : [100, 200]);
const open = async (q) => {
  await page.goto(`${url}${pathArg}am/?${q}`);
  await page.waitForSelector('body[data-ready]');
};

// Per frame: the matches shown, the keys that decide, whether all of them sit in view above the keyboard.
const inspect = () =>
  page.evaluate(() => {
    const out = {};
    for (const sec of document.querySelectorAll('section.option')) {
      out[sec.id] = Object.fromEntries(
        [...sec.querySelectorAll('figure.cell[data-frame]')].map((fig) => {
          const ph = fig.querySelector('.phone');
          if (!ph) return [fig.dataset.frame, null];
          const box = ph.getBoundingClientRect();
          const kb = ph.querySelector('.kbd').getBoundingClientRect();
          const status = ph.querySelector('.status').getBoundingClientRect();
          const sheet = ph.querySelector('[data-sheet]');
          const sr = sheet.getBoundingClientRect();
          const outside = (el) => {
            const r = el.getBoundingClientRect();
            return r.left < box.left - 0.5 || r.right > box.right + 0.5 || r.top < status.bottom - 0.5 || r.bottom > kb.top + 0.5;
          };
          const ms = [...sheet.querySelectorAll('[data-match]')];
          const keys = [...ph.querySelectorAll('[data-outcome]')].filter((k) => k.dataset.outcome);
          const content = [...sheet.children].reduce((h, c) => Math.max(h, c.getBoundingClientRect().bottom), 0) - sr.top;
          const small = keys.filter((b) => {
            const r = b.getBoundingClientRect();
            return r.height < 43.5 || r.width < 43.5;
          });
          return [
            fig.dataset.frame,
            {
              // One entry per matched item (AM2 gives an item a row per outcome).
              matches: [...new Map(ms.reverse().map((m) => [m.dataset.match, { id: m.dataset.match, status: m.dataset.status, text: m.innerText }])).values()].reverse(),
              // What marks each match row: its own background, else its first child's (AM3's chips paint a span).
              bgs: ms.map((m) => {
                const own = getComputedStyle(m).backgroundColor;
                return own === 'rgba(0, 0, 0, 0)' && m.firstElementChild ? getComputedStyle(m.firstElementChild).backgroundColor : own;
              }),
              // AS1's plain suggestion that Enter adds.
              plainBg: sheet.querySelector('.sugg.first:not([data-match])') ? getComputedStyle(sheet.querySelector('.sugg.first:not([data-match])')).backgroundColor : null,
              behind: [...ph.querySelectorAll('.list.behind [data-row]')].map((r) => r.dataset.row),
              note: sheet.querySelector('[data-note]') ? { kind: sheet.querySelector('[data-note]').dataset.note, text: sheet.querySelector('[data-note]').innerText.trim() } : null,
              outcomes: [...new Set(keys.map((k) => k.dataset.outcome))],
              // The field counts too: three rows must not push it under the keyboard.
              hidden: [...ms, ...keys, ...sheet.querySelectorAll('[data-field="input"]')].filter(outside).map((e) => e.dataset.match ?? e.dataset.outcome ?? 'field'),
              overflow: Math.round(content - sr.height),
              small: small.map((b) => b.dataset.act),
              sheetH: Math.round(kb.top - sr.top),
              keyText: keys.map((k) => k.innerText.trim()).filter(Boolean),
            },
          ];
        }),
      );
    }
    return out;
  });

// What a frame must show, per option: [scenario frame, matches, statuses that must be among them].
// AM4 marks nothing while typing; its match shows after Enter.
const expected = (id) => {
  const hides = id === 'AM4';
  return {
    exact: hides ? [0] : [1, ['open']],
    spelling: hides ? [0] : [1, ['open']],
    brand: hides ? [0] : [1, ['open']],
    // AM2 spends two rows on the same item (merge, tick off), so its three rows hold two items, both open.
    several: hides ? [0] : id === 'AM2' ? [2, ['open']] : [3, ['open', 'ticked']],
    ticked: hides ? [0] : [1, ['ticked']],
    none: [0],
    // After Enter only AM4 shows a match: its offer.
    exactEnter: hides ? [1, ['open']] : [0],
    tickedEnter: hides ? [1, ['ticked']] : [0],
  };
};
// The keys a match frame must offer: every outcome the option has a key for on that screen.
const keysOn = (id, key) => {
  const ks = new Set();
  for (const o of outcomes) {
    const p = paths[id][o];
    if (!p) continue;
    const [scenario, steps] = p;
    const first = steps[0];
    const frame = first === 'enter' && steps.length > 1 ? `${scenario}Enter` : scenario;
    const step = first === 'enter' && steps.length > 1 ? steps[1] : first;
    if (frame === key && step !== 'enter' && !step.startsWith('qty')) ks.add(o === 'add' ? 'new' : o);
  }
  return ks;
};

const measured = { ios: { fits: {}, fitsOne: {} }, android: { fits: {}, fitsOne: {} }, words: {}, pick: verdict.pick, runner: verdict.runner };
// Every word the mock data can put on a key (names, stores, categories, brands, details, amounts); the rest is UI text.
const tokens = (x) => x.toLowerCase().split(/[\s·]+/).filter(Boolean);
const dataWords = (lang) =>
  new Set(
    [
      ...Object.values(words).map((w) => w[lang]),
      ...initial(lang).items.flatMap((i) => [i[lang], i.brand, i.details, i.qty, `${i.qty}×`]),
      ...catalog.map((c) => c[lang]),
      ...stores.map((x) => (typeof x.name === 'string' ? x.name : x.name[lang])),
      ...categories.map((c) => c[lang]),
    ].flatMap((w) => tokens(w ?? '')),
  );
const emoji = /^\p{Extended_Pictographic}+$/u;
for (const device of devices) {
  const sizes = sizesFor(device);
  const largest = sizes.at(-1);
  for (const id of ids) {
    measured[device].fits[id] = { max: largest, largest };
    measured[device].fitsOne[id] = { max: largest, largest };
  }
  for (const ts of sizes) {
    for (const lang of ['en', 'de']) {
      for (const theme of ['light', 'dark']) {
        await open(`device=${device}&ts=${ts}&lang=${lang}&theme=${theme}`);
        const r = await inspect();
        const tag = `${device} ${ts}% ${lang} ${theme}`;
        for (const id of ids) {
          const F = r[id];
          for (const [key, [n, statuses = []]] of Object.entries(expected(id))) {
            const f = F[key];
            check(f.matches.length === n, `${tag} ${id} ${key}: ${n} matches shown (${f.matches.length})`);
            for (const st of statuses) check(f.matches.some((m) => m.status === st), `${tag} ${id} ${key}: a ${st} match is marked`);
            for (const o of keysOn(id, key)) check(f.outcomes.includes(o), `${tag} ${id} ${key}: a key for ${o}`);
          }
          // Review 0: no match may look like the plain suggestion Enter adds (Peter t1077u: marked apart from an add).
          const plain = F.none.plainBg;
          check(plain !== null, `${tag} ${id}: the no-match frame shows AS1's plain Enter suggestion`);
          for (const [k, f] of Object.entries(F)) {
            if (!f) continue;
            for (const bg of f.bgs) check(bg !== plain && bg !== 'rgba(0, 0, 0, 0)', `${tag} ${id} ${k}: a match is marked apart from a plain add (${bg} vs ${plain})`);
          }
          // Review 0: a product that only contains the word (Oat milk for Milk) is no match.
          check(!F.several.matches.some((m) => m.id === 'o2'), `${tag} ${id}: Milk offers no Oat milk`);
          // Two Oat milks apart: the match shows its store and brand.
          const brandFrame = id === 'AM4' ? null : F.brand;
          if (brandFrame) check(/dm/.test(brandFrame.matches[0]?.text ?? '') && /Hafergold/.test(brandFrame.matches[0]?.text ?? ''), `${tag} ${id}: the Oat milk match shows dm and Hafergold`);
          // Peter t1077u: the list behind the sheet holds only what this sheet added, never a match.
          for (const [k, f] of Object.entries(F)) if (f) check(f.behind.every((r) => r.startsWith('n')), `${tag} ${id} ${k}: no item from before the sheet behind it (${f.behind.join(', ')})`);
          // What became of the match, in the app's sentences.
          const w = copy[lang];
          const says = {
            merge: (t) => t.startsWith(w.merged('')),
            tick: (t) => t.endsWith(w.ticked('')),
            back: (t) => t.startsWith(`${w.readd}: `),
            already: (t) => t.endsWith(w.already('')),
          };
          const notes = { merged: 'merge', tickedOff: 'tick', tickedEnter: id === 'AM4' ? null : 'back', exactEnter: { AM1: 'merge', AM2: 'already', AM3: 'merge', AM4: null, AM5: 'tick' }[id] };
          for (const [k, kind] of Object.entries(notes)) {
            if (!F[k]) continue;
            check(kind ? F[k].note?.kind === kind && says[kind](F[k].note.text) : F[k].note === null, `${tag} ${id} ${k}: the sheet says ${kind ?? 'nothing'} (${F[k].note?.text ?? 'no note'})`);
          }
          const shown = Object.keys(expected(id)).map((k) => [k, F[k]]);
          // fits: every frame; fitsOne: every frame with at most one match (all but "several").
          const bad = ([, f]) => f.hidden.length || f.overflow > 1;
          const fits = !shown.some(bad);
          for (const [what, list] of [['fits', shown], ['fitsOne', shown.filter(([k]) => k !== 'several')]]) {
            const miss = list.filter(bad).map(([k, f]) => `${k}: ${f.hidden.join(', ') || `overflows ${f.overflow} px`}`);
            if (miss.length && measured[device][what][id].max >= ts) measured[device][what][id] = { max: sizes[sizes.indexOf(ts) - 1] ?? 0, largest, firstMiss: `${ts}% ${lang}: ${miss.join('; ')}` };
          }
          if (ts === 100) {
            for (const [k, f] of shown) check(f.small.length === 0, `${tag} ${id} ${k}: keys under 44 px: ${f.small.join(', ')}`);
            if (id === verdict.pick) check(fits, `${tag} ${id} (the pick): every match and key in view at 100 %`);
            if (lang === 'en' && theme === 'light') {
              measured[device][id] = { one: F.exact.sheetH, several: F.several.sheetH, afterEnter: F.exactEnter.sheetH };
              measured[device].plain = F.none.sheetH;
            }
            if (theme === 'light') {
              const known = dataWords(lang);
              const ui = [...new Set(shown.flatMap(([, f]) => f.keyText))]
                .flatMap((t) => t.split('\n'))
                .map((t) => t.trim())
                .filter((t) => t && !emoji.test(t) && !tokens(t).every((w) => known.has(w) || /^\d+×?$/.test(w)));
              const arb = [copy[lang].merge, copy[lang].readd, copy[lang].newItem];
              for (const w of ui) check(arb.includes(w), `${tag} ${id}: "${w}" is an app string (ARB)`);
              if (lang === 'en') measured.words[id] = [...new Set(ui)].sort();
            }
          }
        }
      }
    }
  }
}

// The pick's claim (RECOMMENDATION.md): one match, its keys and the field in view to 200 % on both phones.
for (const device of devices) {
  const f = measured[device].fitsOne[verdict.pick];
  check(f.max >= 200, `${device}: the pick ${verdict.pick} keeps one match, its keys and the field in view to 200 % (${f.firstMiss ?? ''})`);
}

// The live phones: every outcome's path as clicks and Enter presses; the list after it equals the reducer's.
for (const device of devices) {
  for (const lang of ['en', 'de']) {
    await open(`device=${device}&lang=${lang}`);
    for (const id of ids) {
      for (const o of outcomes) {
        const p = paths[id][o];
        if (!p) continue;
        const [scenario, steps] = p;
        const tag = `${device} ${lang} ${id} live ${o}`;
        try {
          await page.locator(`[data-reset="${id}"]`).click();
          const live = page.locator(`[data-live-phone="${id}"]`);
          await live.locator('[data-input="text"]').fill(words[scenario][lang]);
          for (const step of steps) {
            if (step === 'enter') {
              await live.locator('[data-input="text"]').press('Enter');
              continue;
            }
            const target = live.locator(`[data-act="${step}"]`).first();
            const inView = await target.evaluate((el) => {
              const ph = el.closest('.phone').getBoundingClientRect();
              const kb = el.closest('.phone').querySelector('.kbd').getBoundingClientRect();
              const rr = el.getBoundingClientRect();
              return rr.left >= ph.left - 0.5 && rr.right <= ph.right + 0.5 && rr.bottom <= kb.top + 0.5;
            });
            check(inView, `${tag}: ${step} in view without a swipe`);
            await target.click();
          }
          check(Number(await live.getAttribute('data-taps')) === steps.length, `${tag}: ${steps.length} taps`);
          const before = run([`type:${words[scenario][lang]}`], lang, options[id]);
          const after = steps.reduce((s, a) => act(s, a, lang, options[id]), before);
          const got = JSON.parse(await live.getAttribute('data-items'));
          check(JSON.stringify(got) === JSON.stringify(summary(after, lang)), `${tag}: the live list equals the reducer's`);
          const did = classify(before, after, scenario === 'ticked' ? 't0' : 'o0');
          check(did === (o === 'add' ? 'new' : o), `${tag}: the path does ${o} (did ${did})`);
        } catch (e) {
          check(false, `${tag}: the walk broke: ${String(e.message).split('\n')[0]}`);
        }
      }
    }
  }
}

// The overview links the round.
const small = await browser.newPage({ viewport: { width: 390, height: 844 } });
await small.goto(`${url}${pathArg}`);
await small.waitForSelector('body[data-ready]');
check((await small.locator('a.ocard[href^="am/"]').count()) === 1, 'overview: links round AM');
check(await small.evaluate(() => document.documentElement.scrollWidth <= 391), 'overview: no sideways scroll at 390 px');

const file = join(here, 'measured.json');
if (write) writeFileSync(file, `${JSON.stringify(measured, null, 1)}\n`);
else check(existsSync(file) && JSON.stringify(JSON.parse(readFileSync(file, 'utf8'))) === JSON.stringify(measured), 'am/measured.json matches this run (rerun with --write)');

// RECOMMENDATION.md quotes the same taps and heights: | AMn ... | tick | merge | new | back | 1 match | 3 matches |
const recFile = join(here, 'RECOMMENDATION.md');
if (existsSync(recFile)) {
  const rec = readFileSync(recFile, 'utf8');
  for (const id of ids) {
    const cells = rec.split('\n').find((l) => l.startsWith(`| ${id} `))?.split('|').map((c) => c.trim()) ?? [];
    const enterDoes = (scenario) => {
      const before = run([`type:${words[scenario].en}`], 'en', options[id]);
      return text.en.outcomeName[classify(before, act(before, 'enter', 'en', options[id]), scenario === 'ticked' ? 't0' : 'o0')];
    };
    check(cells[2] === enterDoes('exact') && cells[3] === enterDoes('ticked'), `RECOMMENDATION.md: what Enter does in ${id} (${cells[2]}; ${cells[3]})`);
    const tp = (o) => (paths[id][o] ? String(paths[id][o][1].length) : '–');
    check(cells[4] === tp('tick') && cells[5] === tp('merge') && cells[6] === tp('new') && cells[7] === tp('back'), `RECOMMENDATION.md: ${id}'s taps (${cells.slice(4, 8).join(', ')})`);
    check(cells[8] === `${measured.ios[id].one} / ${measured.android[id].one} px` && cells[9] === `${measured.ios[id].several} / ${measured.android[id].several} px`, `RECOMMENDATION.md: ${id}'s heights (${cells[8]}; ${cells[9]})`);
  }
} else check(false, 'am/RECOMMENDATION.md exists');

await browser.close();
server.close();
console.log(JSON.stringify(measured, null, 1));
for (const f of failures) console.log(`FAIL ${f}`);
console.log(failures.length ? `${failures.length} of ${checks} checks failed` : `all checks passed (${checks})`);
process.exit(failures.length ? 1 : 0);
