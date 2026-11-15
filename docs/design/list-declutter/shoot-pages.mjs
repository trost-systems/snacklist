// The overview and the round pages (job 238): one page per round with only its own buttons, and old links redirected.
// Usage: node shoot-pages.mjs <sandbox-url> <out-dir> [playwright-module-dir], the sandbox URL ending in `list-declutter/`.
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import process from 'node:process';
import { rounds, viewsOf } from './rounds.js';

const [base, out, pwDir = `${process.env.HOME}/family-groceries/e2e/node_modules/`] = process.argv.slice(2);
const { chromium } = createRequire(pwDir)('playwright');
mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
const errors = [];
const failures = [];
const check = (ok, label) => {
  if (!ok) failures.push(label);
};
const newPage = async (viewport) => {
  const page = await browser.newPage({ viewport, deviceScaleFactor: 2 });
  page.on('pageerror', (e) => errors.push(String(e)));
  return page;
};
const page = await newPage({ width: 1400, height: 1000 });
const go = async (path, ready) => {
  await page.goto(new URL(path, base).href);
  await page.waitForSelector(ready);
  await page.evaluate(() => document.fonts.ready);
};
const where = () => page.evaluate((root) => ({ path: location.pathname.slice(root.length), search: location.search, hash: location.hash }), new URL(base).pathname);

const overview = async (q) => {
  await go(`./${q}`, '.rounds a');
  return page.evaluate(() => ({
    lang: document.documentElement.lang,
    h1: document.querySelector('h1').textContent,
    links: [...document.querySelectorAll('.rounds a')].map((a) => ({ text: a.innerText.replace(/\s+/g, ' '), href: a.getAttribute('href') })),
    dateBelow: [...document.querySelectorAll('.rounds a')].map((a) => a.querySelector('.date').getBoundingClientRect().top >= a.querySelector('b').getBoundingClientRect().bottom - 1),
    lines: [...document.querySelectorAll('.rounds p')].map((p) => Math.round(p.getBoundingClientRect().height / parseFloat(getComputedStyle(p).lineHeight))),
  }));
};
const en = await overview('');
check(en.lang === 'en' && en.h1 === 'List screen prototypes', `overview opens in English (${en.lang}, ${en.h1})`);
check(
  JSON.stringify(en.links.map((l) => l.text)) ===
    JSON.stringify(['Add feedback (AF1–AF5) Nov 15', 'Reload indicator (RI1–RI3) Nov 15', 'Joining a household (JH1–JH5) Nov 15', 'Creating a household (CH1–CH5) Nov 15', 'Feedback experience (FB1–FB5) Nov 15', 'Per-store subtotals (ST1–ST5) Nov 14', 'Switcher sheet + bottom area (SS/BB) Nov 13', 'List declutter round 1 (LD1–LD5) Nov 13']),
  `overview lists the eight rounds, newest first (${en.links.map((l) => l.text).join(' | ')})`,
);
check(en.lines.length === 8 && en.lines.every((n) => n === 1), `overview: each round's description is one line (${en.lines})`);
check(en.dateBelow.every(Boolean), `overview: each date sits under its title (${en.dateBelow})`);
check(JSON.stringify(en.links.map((l) => l.href)) === JSON.stringify(['../add-sheet/add-feedback/', '../add-sheet/reload-indicator/', '../household-onboarding/join/', '../household-onboarding/create/', '../feedback-experience/', 'st/', 'ss-bb/', 'round1/']), `overview links (${en.links.map((l) => l.href)})`);
await page.screenshot({ path: `${out}/overview-en.png`, fullPage: true });
const de = await overview('?lang=de');
check(de.lang === 'de' && de.links[0].text.startsWith('Rückmeldung beim Hinzufügen') && de.links[2].text.startsWith('Einem Haushalt beitreten') && de.links[4].text.startsWith('Feedback-Erlebnis') && de.links[5].text.startsWith('Summen je Laden') && de.links.every((l) => l.href.endsWith('/?lang=de')), `overview ?lang=de: German, links keep lang (${de.links.map((l) => l.href)})`);
await page.screenshot({ path: `${out}/overview-de.png`, fullPage: true });

// Every hash of the old shared page lands on the round that holds it, keeping the query.
const homes = {
  st: ['st', 'recst', 'ST1', 'ST2', 'ST3', 'ST4', 'ST5', 'today'],
  'ss-bb': ['ss', 'bb', 'ld4', 'rec', 'R2', 'SS1', 'SS4', 'BB4', 'BB5', 'LD4-3T'],
  round1: ['r1', 'rec1', 'all', 'LD1', 'LD2', 'LD5'],
};
for (const [path, views] of Object.entries(homes))
  for (const v of views) {
    await go(`./?lang=de#/${v}`, '.page-head h1');
    const w = await where();
    const want = v === 'all' ? 'r1' : v;
    check(w.path === `${path}/` && w.search === '?lang=de' && w.hash === `#/${want}`, `old link #/${v}: lands on ${path}/?lang=de#/${want} (got ${w.path}${w.search}${w.hash})`);
  }
// A typed hash of another round on a round page goes on too.
await go('st/#/SS4', '.page-head h1');
check((await where()).path === 'ss-bb/', `st/#/SS4 goes on to ss-bb/ (${(await where()).path})`);

// Each round page: its title, the way back, and only its own buttons.
// The title is in the HTML too, for tabs and link previews before the script runs.
for (const r of rounds) {
  const html = await (await page.request.get(new URL(`${r.path}/`, base).href)).text();
  check(html.includes(`<title>${r.title.en}</title>`), `${r.path}/index.html: static <title> is the round's (${html.match(/<title>(.*?)<\/title>/)?.[1]})`);
}
const own = {
  st: { title: 'Per-store subtotals (ST1–ST5)', views: ['st', 'recst', 'today', 'R2', 'ST1', 'ST2', 'ST3', 'ST4', 'ST5'], data: ['three', 'one', 'mixed'], scen: [] },
  'ss-bb': { title: 'Switcher sheet + bottom area (SS/BB)', views: ['ss', 'bb', 'ld4', 'rec', 'today', 'SS1', 'SS2', 'SS3', 'SS4', 'SS5'], data: ['shot', 'big'], scen: ['one', 'two', 'many'] },
  round1: { title: 'List declutter round 1 (LD1–LD5)', views: ['r1', 'rec1', 'today', 'LD1', 'LD2', 'LD3', 'LD4', 'LD5'], data: ['shot', 'big'], scen: ['one', 'two', 'many'] },
};
const buttons = () =>
  page.evaluate(() => {
    const vals = (set) => [...document.querySelectorAll(`.controls [data-set="${set}"]`)].map((b) => b.dataset.val);
    return {
      h1: document.querySelector('.page-head h1').textContent,
      note: document.querySelector('.page-head .note').textContent,
      back: document.querySelector('.back-link')?.getAttribute('href'),
      views: vals('view'),
      data: vals('data'),
      scen: vals('scen'),
      text: document.querySelector('.controls').innerText,
      phones: [...new Set([...document.querySelectorAll('.phone')].map((p) => p.dataset.v))],
    };
  });
const otherIds = /\b(LD4-3T|ST\d|SS\d|BB\d|LD\d)\b/g;
for (const [path, want] of Object.entries(own)) {
  await go(`${path}/`, '.phone');
  const b = await buttons();
  check(b.h1 === want.title && b.note.length > 40, `${path}/: title "${b.h1}" and a comparing line`);
  check(b.back === '../?lang=en', `${path}/: links back to the overview (${b.back})`);
  check(JSON.stringify(b.views) === JSON.stringify(want.views), `${path}/: view buttons ${b.views}`);
  check(JSON.stringify(b.data) === JSON.stringify(want.data) && JSON.stringify(b.scen) === JSON.stringify(want.scen), `${path}/: data ${b.data}, people ${b.scen}`);
  const allowed = viewsOf(rounds.find((r) => r.path === path));
  const strays = [...b.text.matchAll(otherIds)].map((m) => m[1]).filter((id) => !allowed.has(id));
  check(!strays.length, `${path}/: no other round's buttons (${strays})`);
  if (path === 'st') check(JSON.stringify(b.phones) === JSON.stringify(want.views.slice(2)), `st/: shows Today, R2 and ST1–ST5 (${b.phones})`);
  await page.screenshot({ path: `${out}/page-${path}.png` });
  await page.click('.back-link');
  await page.waitForSelector('.rounds a');
  check((await where()).path === '', `${path}/: the back link opens the overview`);
}
// Within a page the set buttons still switch views.
await go('st/', '.phone');
await page.click('.controls [data-set="theme"][data-val="dark"]');
check(!(await where()).search.includes('scen='), `st/: a control click keeps the people switch out of the URL (${(await where()).search})`);
await go('ss-bb/', '.phone');
await page.click('.controls [data-set="view"][data-val="bb"]');
check((await buttons()).phones.includes('BB3') && (await where()).hash === '#/bb', 'ss-bb/: the BB button shows the BB set');
await page.click('.controls [data-set="view"][data-val="rec"]');
await page.waitForSelector('.rec h2');
check((await page.textContent('.rec h2')).startsWith('Round 2: SS4'), 'ss-bb/: the recommendation button shows round 2’s recommendation');
await go('st/?lang=de#/recst', '.rec h2');
check(/ST3/.test(await page.textContent('.rec h2')) && (await page.evaluate(() => document.documentElement.lang)) === 'de', 'st/?lang=de#/recst: the ST recommendation in German');

// On a phone the round's title and the way back stay on screen above the phone.
const mp = await newPage({ width: 390, height: 664 });
await mp.goto(new URL('st/#/ST3', base).href);
await mp.waitForSelector('.phone');
await mp.waitForTimeout(400);
const fit = await mp.evaluate(() => {
  const r = (s) => document.querySelector(s).getBoundingClientRect();
  return { h1: r('.page-head h1'), back: r('.back-link'), phone: r('.phone'), w: document.documentElement.scrollWidth, h: innerHeight };
});
check(fit.h1.height > 0 && fit.back.height > 0 && fit.h1.right <= 390 && fit.phone.bottom <= fit.h + 0.5 && fit.w <= 390, `st/ at 390 × 664: title and back link show, the phone fits (${JSON.stringify(fit)})`);
await mp.screenshot({ path: `${out}/phone-390x664-st.png` });
check(!(await mp.locator('.page-head .note').isVisible()), 'st/ at 390 × 664: the comparing line waits in the options');
await mp.click('.controls [data-act="opts"]');
const note = await mp.evaluate(() => {
  const n = document.querySelector('.page-head .note');
  return { text: n.textContent, shown: n.checkVisibility(), right: n.getBoundingClientRect().right, phone: document.querySelector('.phone').getBoundingClientRect().bottom, h: innerHeight };
});
check(note.shown && note.text.startsWith('Five ways') && note.right <= 390 && note.phone <= note.h + 0.5, `st/ at 390 × 664: Options shows the comparing line, and the phone still fits (${JSON.stringify(note)})`);
await mp.screenshot({ path: `${out}/phone-390x664-st-options.png` });

await browser.close();
if (errors.length) console.log('page errors:', errors);
check(!errors.length, `no page errors (${errors.length})`);
if (failures.length) {
  console.log(`FAILED (${failures.length}):\n- ${failures.join('\n- ')}`);
  process.exit(1);
}
console.log('all checks passed');
