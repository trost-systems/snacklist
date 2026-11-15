// Drives both round pages in Chromium and checks them; exits 1 on any miss, else prints "all checks passed".
// Usage: node verify.mjs [<folder or url>] [<out dir>] [<playwright module dir>]
//   folder: the repo root (default) or a build.sh output; the pages are <base>/household-onboarding/{join,create}/
//   in a build, docs/design/household-onboarding/ in the repo.
import { createRequire } from 'node:module';
import { mkdir, stat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { serve } from './tools/serve.mjs';
import { measure, combos, stepsOf, scenKey } from './metrics.js';
import { itemNames, mock } from './model.js';

const here = dirname(fileURLToPath(import.meta.url));
const [target = join(here, '../../..'), out = '/tmp/263-verify', pwDir = `${process.env.HOME}/family-groceries/e2e/node_modules/`] = process.argv.slice(2);
const require = createRequire(pwDir);
const { chromium } = require('playwright');

let base, server, built = false;
if (/^https?:/.test(target)) base = target.replace(/\/$/, '');
else {
  ({ server, url: base } = await serve(target));
  const inRepo = await stat(join(target, 'docs/design/household-onboarding')).then(() => true, () => false);
  base += inRepo ? '/docs/design/household-onboarding' : '/household-onboarding';
  built = !inRepo && (await stat(join(target, 'overview.js')).then(() => true, () => false));
}
await mkdir(out, { recursive: true });

const fails = [];
let checks = 0;
const ok = (cond, msg) => {
  checks++;
  if (!cond) fails.push(msg);
};

const browser = await chromium.launch();
const page = async (w = 1700, h = 1000) => {
  const p = await browser.newPage({ viewport: { width: w, height: h } });
  p.on('pageerror', (e) => fails.push(`page error: ${e}`));
  return p;
};

const tablesOk = (() => {
  try {
    execFileSync('node', [join(here, 'tools/tables.mjs'), '--check'], { stdio: 'pipe' });
    return true;
  } catch (e) {
    console.log(String(e.stdout));
    return false;
  }
})();
ok(tablesOk, 'RECOMMENDATION tables differ from the flows (node tools/tables.mjs)');

const required = {
  join: (sc) => ['entry', 'landing', 'account', 'consent', 'list', ...(sc.approval === 'on' ? ['wait'] : [])],
  create: () => ['start', 'account', 'consent', 'list'],
};

for (const roundId of ['join', 'create']) {
  const { round } = await import(join(here, roundId, 'flows.js'));
  const url = `${base}/${roundId}/`;
  const p = await page();
  const lastGoal = round.goals.at(-1).key;

  // 1. Every option, scenario and goal: walk the Try-it phone with real clicks; the count must match the table's numbers.
  for (const o of round.options)
    for (const sc of combos(round.scenarios)) {
      const q = new URLSearchParams(sc);
      await p.goto(`${url}?${q}#/${o.id}`);
      await p.waitForSelector('[data-live]');
      for (const { key } of round.goals) {
        const path = o.paths(sc)[key];
        const where = `${roundId} ${o.id} ${scenKey(sc)} ${key}`;
        if (round.goals.length > 1) await p.click(`.try-side button[data-goal="${key}"]`);
        for (let i = 1; i < path.length; i++) {
          const next = path[i];
          if (next.via === 'tap' && next.by !== 'outside') {
            const el = p.locator(`[data-live] [data-go="${next.s}"]`);
            const n = await el.count();
            ok(n === 1, `${where}: step ${i} (${next.s}) has ${n} controls that lead on`);
            if (n !== 1) break;
            const box = await el.boundingBox();
            const inline = await el.evaluate((e) => e.classList.contains('chat-link'));
            ok(inline || (box && box.height >= 32 && box.width >= 32), `${where}: control for ${next.s} is ${box?.width}×${box?.height}, too small`);
            await el.click();
          } else {
            const adv = p.locator('[data-testid="advance"]');
            ok((await adv.count()) === 1, `${where}: step ${i} (${next.s}, ${next.via}) has no side control`);
            if (!(await adv.count())) break;
            await adv.click();
          }
        }
        const trail = p.locator('[data-testid="trail"]');
        const m = measure(o, path);
        ok((await trail.getAttribute('data-taps')) === String(m.taps), `${where}: walked ${await trail.getAttribute('data-taps')} taps, table says ${m.taps}`);
        ok((await trail.getAttribute('data-done')) === 'true', `${where}: walk did not reach the end`);
        ok((await p.locator('[data-live]').getAttribute('data-state')) === path.at(-1).s, `${where}: ended on the wrong state`);
        // The flow's steps: every required one on the end-to-end path, the goal reached.
        const steps = new Set(path.flatMap((st) => stepsOf(o, st.s)));
        const all = new Set(round.goals.flatMap((g) => o.paths(sc)[g.key]).flatMap((st) => stepsOf(o, st.s)));
        if (key === lastGoal) for (const r of required[roundId](sc)) ok(all.has(r), `${where}: no ${r} step on the way to ${round.goals.map((g) => g.key).join(' or ')}`);
        if (roundId === 'join') {
          ok(stepsOf(o, path.at(-1).s).includes('list'), `${where}: does not end in the shared list`);
          if (sc.approval === 'off') ok(!steps.has('wait'), `${where}: waits with approval off`);
          // Before the first list frame nothing may show an item name, and every landing names Mia and the household.
        } else ok(stepsOf(o, path.at(-1).s).includes(key === 'list' ? 'list' : 'shared'), `${where}: does not end at ${key}`);
        await p.click('[data-reset]');
        if (round.goals.length > 1) await p.click(`.try-side button[data-goal="${lastGoal}"]`);
      }

      // 2. The storyboard for this scenario: privacy of the landings, captions, the table row.
      const frames = await p.$$eval(`.story[data-goal="${lastGoal}"] figure`, (fs) => fs.map((f) => ({ s: f.dataset.frameState, text: f.querySelector('.phone').innerText })));
      const path = o.paths(sc)[lastGoal];
      ok(frames.length === path.length, `${roundId} ${o.id} ${scenKey(sc)}: storyboard has ${frames.length} frames, path ${path.length}`);
      if (roundId === 'join') {
        const firstList = path.findIndex((st) => stepsOf(o, st.s).includes('list'));
        frames.slice(0, firstList).forEach((f, i) => {
          const hit = itemNames.find((n) => new RegExp(`(^|\\s)${n}(\\s|$)`).test(f.text));
          ok(!hit || stepsOf(o, path[i].s).includes('entry'), `${roundId} ${o.id} ${scenKey(sc)}: “${hit}” shown on ${f.s} before the join`);
          if (stepsOf(o, path[i].s).includes('landing') && !/join$/.test(f.s))
            ok(f.text.includes(mock.en.household) && (o.id === 'today' && f.s === 'join' ? true : f.text.includes('Mia')), `${roundId} ${o.id}: landing ${f.s} does not name Mia and the household`);
        });
      }
      const badges = await p.$$eval('.goal-badge', (bs) => bs.map((b) => ({ goals: b.dataset.goalEnd.split(' '), s: b.closest('figure').dataset.frameState })));
      for (const { key } of round.goals) {
        const end = o.paths(sc)[key].at(-1).s;
        const on = badges.filter((b) => b.goals.includes(key));
        ok(on.length >= 1 && on.every((b) => b.s === end), `${roundId} ${o.id} ${scenKey(sc)}: “${key}” badge on ${on.map((b) => b.s)}, path ends on ${end}`);
      }
      for (const { key } of round.goals) {
        const m = measure(o, o.paths(sc)[key]);
        const nums = await p.locator(`[data-testid="nums"] [data-goal="${key}"]`).innerText();
        ok(nums.includes(`${m.taps} `) && nums.includes(`${m.screens} `), `${roundId} ${o.id} ${scenKey(sc)} ${key}: header says “${nums}”, measured ${m.taps}/${m.screens}`);
      }
    }

  // 3. The overview: one card per option, table numbers for each scenario, the pick and runner-up, the questions.
  for (const sc of combos(round.scenarios)) {
    await p.goto(`${url}?${new URLSearchParams(sc)}#/`);
    await p.waitForSelector('[data-testid="comparison"]');
    for (const o of round.options)
      for (const { key } of round.goals) {
        const m = measure(o, o.paths(sc)[key]);
        const td = p.locator(`[data-row="${o.id}"] td[data-goal="${key}"]`);
        ok((await td.getAttribute('data-taps')) === String(m.taps) && (await td.getAttribute('data-screens')) === String(m.screens), `${roundId} table ${o.id} ${scenKey(sc)} ${key} differs from the walk`);
      }
  }
  ok((await p.locator('[data-card]').count()) === 6, `${roundId}: overview should have Today + 5 cards`);
  ok((await p.locator('[data-strip]').count()) === 6, `${roundId}: side-by-side should have 6 strips`);
  for (const lang of ['en', 'de']) {
    await p.goto(`${url}?lang=${lang}#/rec`);
    await p.waitForSelector('[data-testid="rec"] h2');
    const rec = await p.locator('[data-testid="rec"]').innerText();
    const prefix = roundId === 'join' ? 'JH' : 'CH';
    const qItems = (await p.locator('[data-testid="rec"] ol > li').allInnerTexts()).filter((t) => t.startsWith(`${prefix}-Q`));
    const qs = qItems.map((t) => Number(t.match(new RegExp(`^${prefix}-Q(\\d+)`))[1]));
    ok(qs.length >= 3 && qs.every((n, i) => n === i + 1), `${roundId} ${lang}: questions not numbered ${prefix}-Q1… in order (${qs})`);
    const items = await p.locator('[data-testid="rec"] ol > li').allInnerTexts();
    const dflt = lang === 'de' ? 'Standard:' : 'Default:';
    ok(items.filter((t) => t.includes(`${prefix}-Q`)).every((t) => t.includes(dflt)), `${roundId} ${lang}: a question without “${dflt}”`);
    ok(rec.includes(round.rec.pick) && rec.includes(round.rec.runnerUp), `${roundId} ${lang}: pick or runner-up missing`);
    const back = await p.locator('[data-testid="back"]').getAttribute('href');
    ok(back && back.includes('../../'), `${roundId}: back link ${back}`);
  }
  await p.close();

  // 4. Screenshots: every option in EN and DE, light and dark, 100 and 200 % text; nothing sticks out of a phone.
  const shot = await page();
  for (const o of round.options)
    for (const lang of ['en', 'de'])
      for (const theme of ['light', 'dark'])
        for (const ts of ['100', '200']) {
          await shot.goto(`${url}?lang=${lang}&theme=${theme}&ts=${ts}#/${o.id}`);
          await shot.waitForSelector('.story');
          await shot.evaluate(() => document.fonts.ready);
          const sticks = await shot.$$eval('.story .phone', (phones) =>
            phones.flatMap((ph) => {
              const r = ph.getBoundingClientRect();
              return [...ph.querySelectorAll('*')]
                .filter((el) => {
                  const b = el.getBoundingClientRect();
                  if (!b.width || b.right <= r.right + 1) return false;
                  for (let a = el.parentElement; a && a !== ph; a = a.parentElement) if (getComputedStyle(a).overflowX !== 'visible') return false;
                  return true;
                })
                .map((el) => `${ph.dataset.state}: ${el.className || el.tagName}`);
            }),
          );
          ok(!sticks.length, `${roundId} ${o.id} ${lang} ${theme} ${ts}%: sticks out of the phone: ${sticks.slice(0, 3).join('; ')}`);
          const spills = await shot.$$eval('.story .phone', (phones) =>
            phones.flatMap((ph) =>
              [...ph.querySelectorAll('.tact, .tbtn, p, .mrow, .fs-row, .sticker, .lfield, .item, .card, h1')]
                .filter((el) => getComputedStyle(el).overflowY === 'visible' && el.scrollHeight > el.clientHeight + 2)
                .map((el) => `${ph.dataset.state}: ${el.className || el.tagName} “${el.innerText.slice(0, 30)}”`),
            ),
          );
          const underBar = await shot.$$eval('.story .phone', (phones) =>
            phones.flatMap((ph) => {
              const bar = ph.querySelector('.homeind i')?.getBoundingClientRect();
              if (!bar || !bar.width) return [];
              return [...ph.querySelectorAll('*')]
                .filter((el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()) && !el.closest('.homeind'))
                .filter((el) => {
                  let r = el.getBoundingClientRect();
                  let top = r.top, bottom = r.bottom;
                  for (let a = el.parentElement; a && a !== ph; a = a.parentElement)
                    if (getComputedStyle(a).overflowY !== 'visible') {
                      const ar = a.getBoundingClientRect();
                      top = Math.max(top, ar.top);
                      bottom = Math.min(bottom, ar.bottom);
                    }
                  if (getComputedStyle(el).visibility === 'hidden' || bottom <= top) return false;
                  return top < bar.bottom && bottom > bar.top && r.left < bar.right && r.right > bar.left;
                })
                .map((el) => `${ph.dataset.state}: “${el.textContent.trim().slice(0, 30)}”`);
            }),
          );
          ok(!underBar.length, `${roundId} ${o.id} ${lang} ${theme} ${ts}%: text under the home indicator: ${underBar.slice(0, 3).join('; ')}`);
          ok(!spills.length, `${roundId} ${o.id} ${lang} ${theme} ${ts}%: text spills out of its box: ${spills.slice(0, 3).join('; ')}`);
          await shot.screenshot({ path: `${out}/${roundId}-${o.id}-${lang}-${theme}-${ts}.png`, fullPage: true });
        }
  await shot.goto(`${url}#/`);
  await shot.screenshot({ path: `${out}/${roundId}-overview.png`, fullPage: true });
  await shot.close();

  // 5. A phone-sized screen: one phone per screen width, controls reachable.
  const phone = await page(390, 664);
  await phone.goto(`${url}#/${round.options[1].id}`);
  await phone.waitForSelector('.story');
  const w = await phone.$eval('.story figure .phone', (el) => el.getBoundingClientRect().width);
  ok(Math.abs(w - 390) < 2, `${roundId}: on a phone the phones are ${w} px wide`);
  ok((await phone.evaluate(() => document.documentElement.scrollWidth)) <= 391, `${roundId}: the page scrolls sideways on a phone`);
  await phone.screenshot({ path: `${out}/${roundId}-phone-390x664.png` });
  await phone.close();
}

// 6. In a preview build with the overview: overview → each round page → back to the overview, in both languages.
if (built) {
  const p = await page();
  for (const lang of ['en', 'de'])
    for (const [roundId, title] of [['join', { en: 'Joining a household', de: 'Einem Haushalt beitreten' }], ['create', { en: 'Creating a household', de: 'Einen Haushalt anlegen' }]]) {
      await p.goto(`${base.replace(/\/household-onboarding$/, '')}/${lang === 'de' ? '?lang=de' : ''}`);
      const link = p.locator(`a[href^="../household-onboarding/${roundId}/"]`);
      ok((await link.count()) === 1, `overview ${lang}: no link to ${roundId}`);
      await link.click();
      await p.waitForSelector('[data-testid="back"]');
      ok((await p.locator('.page-head h1').innerText()).startsWith(title[lang]), `overview ${lang} → ${roundId}: wrong page`);
      await p.click('[data-testid="back"]');
      await p.waitForSelector('ul.rounds');
      ok((await p.locator(`a[href^="../household-onboarding/${roundId}/"]`).count()) === 1, `${roundId} ${lang}: back link does not reach the overview`);
    }
  await p.close();
}

await browser.close();
server?.close();
for (const f of fails) console.log(`FAIL ${f}`);
console.log(`${checks} checks, ${fails.length} failed`);
if (fails.length) process.exit(1);
console.log('all checks passed');
