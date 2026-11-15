// Screenshots every option (EN/DE, light/dark, 100 % and 200 % text) and checks the flows; exits 1 on any miss.
// Usage: node verify.mjs <url of this folder, ending in feedback-experience/> <out dir> [playwright module dir]
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [base, out, pwDir = `${process.env.HOME}/family-groceries/e2e/node_modules/`] = process.argv.slice(2);
if (!base || !out) {
  console.error('usage: node verify.mjs <folder url> <out dir> [playwright module dir]');
  process.exit(2);
}
const { chromium } = createRequire(pwDir)('playwright');
const here = dirname(fileURLToPath(import.meta.url));
mkdirSync(out, { recursive: true });

const ids = ['today', 'FB1', 'FB2', 'FB3', 'FB4', 'FB5'];
const scens = ['bug', 'error', 'idea'];
const required = ['enter', 'attach', 'send', 'after', 'peter'];
const fails = [];
const check = (ok, msg) => {
  if (!ok) fails.push(msg);
};

// The chrome strings are the app's: each value in model.js `chrome` with a key in `arbOf`, and every category
// name, must equal app/l10n/app_<lang>.arb rendered with the same placeholder values.
const model = await import(join(here, 'model.js'));
const { cats } = await import(join(here, 'flows.js'));
// Just enough ICU for these keys: {name} placeholders and one level of plural, braces matched by depth.
const icu = (msg, args) => {
  const close = (str, from) => {
    for (let d = 0, k = from; k < str.length; k++) {
      if (str[k] === '{') d++;
      if (str[k] === '}' && --d === 0) return k;
    }
    return str.length;
  };
  let out = msg;
  for (let at = out.indexOf(', plural, '); at !== -1; at = out.indexOf(', plural, ')) {
    const open = out.lastIndexOf('{', at);
    const end = close(out, open);
    const v = out.slice(open + 1, at);
    const forms = {};
    for (let k = at + ', plural, '.length; k < end; ) {
      const b = out.indexOf('{', k);
      if (b === -1 || b >= end) break;
      const e = close(out, b);
      forms[out.slice(k, b).trim()] = out.slice(b + 1, e);
      k = e + 1;
    }
    out = out.slice(0, open) + (forms[`=${args[v]}`] ?? forms.other ?? '') + out.slice(end + 1);
  }
  return out.replace(/\{(\w+)\}/g, (_, k) => String(args[k] ?? `{${k}}`));
};
for (const lang of ['en', 'de']) {
  const arbFile = JSON.parse(readFileSync(join(here, `../../../app/l10n/app_${lang}.arb`), 'utf8'));
  for (const [k, [key, args = {}]] of Object.entries(model.arbOf)) {
    const want = Array.isArray(key) ? key.map((x) => arbFile[x]).join(' ') : icu(arbFile[key] ?? `(no ${key})`, args);
    const v = model.chrome[lang][k];
    const got = typeof v === 'function' ? v(args.count) : v;
    check(got === want, `${lang}: chrome.${k} “${got}” is not the app’s ${key} “${want}”`);
  }
  for (const g of model.list) check(g.cat[lang] === arbFile[g.cat.arb], `${lang}: category “${g.cat[lang]}” is not the app’s ${g.cat.arb} “${arbFile[g.cat.arb]}”`);
  for (const [, n, key] of cats) check(n[lang] === arbFile[key], `${lang}: edit-sheet category “${n[lang]}” is not the app’s ${key} “${arbFile[key]}”`);
}
check(model.money('de') === '0,00\u00a0€' && model.money('en') === '€0.00', `the total is not formatted as the app does (${model.money('en')}, ${model.money('de')})`);

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1500, height: 1000 } });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

const open = async (query, hash) => {
  await page.goto(`${base}${query ? `?${query}` : ''}#/${hash}`);
  await page.waitForSelector('main.view');
  await page.evaluate(() => document.fonts.ready);
};

// Elements sticking out of the phone sideways, and tap targets under 44 px, in every phone on the page.
const layoutMisses = () =>
  page.evaluate(() => {
    const misses = [];
    for (const ph of document.querySelectorAll('.phone')) {
      const box = ph.getBoundingClientRect();
      for (const el of ph.querySelectorAll('*')) {
        const r = el.getBoundingClientRect();
        if (!r.width || getComputedStyle(el).visibility === 'hidden') continue;
        if (r.right > box.right + 1 || r.left < box.left - 1) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: ${el.className || el.tagName} sticks out by ${Math.round(Math.max(r.right - box.right, box.left - r.left))} px`);
      }
      for (const el of ph.querySelectorAll('.att, .sheet-top, .field, .att-row, .check, .mrow, .note-card, .banner, .chipx, .snack, .dialog')) {
        if (el.scrollHeight > el.clientHeight + 2) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: ${el.className} squashed (${el.clientHeight} of ${el.scrollHeight} px)`);
      }
      // Stacked parts of a sheet or page must not run into each other.
      for (const col of ph.querySelectorAll('.sheet-body, .scroll')) {
        const kids = [...col.children].filter((k) => getComputedStyle(k).position !== 'absolute' && k.getBoundingClientRect().height);
        for (let i = 1; i < kids.length; i++) {
          const a = kids[i - 1].getBoundingClientRect();
          const b = kids[i].getBoundingClientRect();
          if (a.bottom > b.top + 1 && a.left < b.right && b.left < a.right) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: ${kids[i - 1].className} overlaps ${kids[i].className}`);
        }
      }
      // Snackbars follow the app's SnackBarThemeData: surface-raised card, 2 px edge contour, brand action.
      const probe = (v) => { const d = document.createElement('i'); d.style.color = `var(${v})`; ph.append(d); const c = getComputedStyle(d).color; d.remove(); return c; };
      for (const sn of ph.querySelectorAll('.snack')) {
        const cs = getComputedStyle(sn);
        if (cs.backgroundColor !== probe('--hl-color-surface-raised') || cs.borderTopWidth !== '2px' || cs.borderTopColor !== probe('--hl-color-edge') || cs.color !== probe('--hl-color-text'))
          misses.push(`${ph.dataset.flow}/${ph.dataset.state}: snackbar is not the app's (bg ${cs.backgroundColor}, border ${cs.borderTopWidth} ${cs.borderTopColor})`);
        for (const b of sn.querySelectorAll('button')) if (getComputedStyle(b).color !== probe('--hl-color-brand')) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: snackbar action is not the brand colour`);
      }
      // A snackbar floats right above what is fixed below it: the add band or tab bar, else the bottom inset.
      const safe = parseFloat(getComputedStyle(ph).getPropertyValue('--safe')) || 0;
      for (const sn of ph.querySelectorAll('.snack')) {
        const r = sn.getBoundingClientRect();
        const below = sn.nextElementSibling?.getBoundingClientRect().top ?? ph.getBoundingClientRect().bottom - safe;
        const gap = below - r.bottom;
        if (gap < 0 || gap > 16) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: snackbar floats ${Math.round(gap)} px above what is below it`);
      }
      for (const el of ph.querySelectorAll('[data-go],[data-tog]')) {
        const r = el.getBoundingClientRect();
        if (r.height < 44 || r.width < 44) misses.push(`${ph.dataset.flow}/${ph.dataset.state}: target ${el.dataset.go ?? el.dataset.tog} is ${Math.round(r.width)}×${Math.round(r.height)}`);
      }
    }
    return [...new Set(misses)];
  });

// 1. Drive each shortest path on the Try-it phone with real clicks and count the actions.
const measured = {};
for (const id of ids) {
  measured[id] = [];
  for (const scen of scens) {
    await open(`scen=${scen}`, id);
    const path = await page.evaluate(([i, s]) => import('./flows.js').then((m) => m.flows.find((f) => f.id === i).path[s]), [id, scen]);
    let actions = 0;
    for (const next of path.slice(1)) {
      const shake = page.locator(`[data-testid="shake"][data-shake="${next}"]`);
      const hint = page.locator(`[data-live] .next[data-go="${next}"]`);
      if (await shake.count()) await shake.click();
      else if (await hint.count()) await hint.first().click();
      else {
        check(false, `${id}/${scen}: no way from ${await page.locator('[data-live]').getAttribute('data-state')} to ${next}`);
        break;
      }
      actions++;
      check((await page.locator('[data-live]').getAttribute('data-state')) === next, `${id}/${scen}: click did not reach ${next}`);
    }
    measured[id].push(actions);
    const trail = await page.locator('[data-testid="trail"]').getAttribute('data-count');
    check(Number(trail) === actions, `${id}/${scen}: trail says ${trail}, drove ${actions}`);
    check((await page.locator('[data-live]').getAttribute('data-state')) === path.at(-1), `${id}/${scen}: did not end at ${path.at(-1)}`);

    // 2. The five required steps, each with content.
    for (const step of required) {
      const fig = page.locator(`[data-testid="story"] figure[data-step="${step}"]`);
      check((await fig.count()) >= 1, `${id}/${scen}: step ${step} missing`);
      if (await fig.count()) check((await fig.first().innerText()).trim().length > 40, `${id}/${scen}: step ${step} is empty`);
    }
    check((await page.locator('[data-testid="shake-decision"]').innerText()).length > 40, `${id}: shake decision missing`);
    const dupes = await page.$$eval('[data-testid="story"] .desk table', (ts) => ts.flatMap((t) => { const ks = [...t.querySelectorAll('tr td:first-child')].map((td) => td.textContent); return ks.filter((k, i) => ks.indexOf(k) !== i); }));
    check(!dupes.length, `${id}/${scen}: a column shows twice in Peter's table (${dupes})`);

    // 3. What goes with the note is visible, and every switch really drops its field.
    const attach = page.locator('[data-testid="story"] figure[data-step="attach"]').first();
    const panel = attach.locator('[data-testid="attachments"]');
    const fixedLine = attach.locator('.included');
    check((await panel.count()) + (await fixedLine.count()) > 0, `${id}/${scen}: the attach step shows nothing about what is sent`);
    const sw = panel.locator('.sw').first();
    // A preview panel offers a switch for every field that isn't fixed; a field marked "always" is shown, not hidden.
    if (await panel.count()) {
      const loose = await panel.locator('.att-row:not(:has(.fixed))').count();
      check(loose === (await panel.locator('.att-row .sw').count()), `${id}/${scen}: a field in the preview has no switch`);
    } else check(id === 'today' || (await attach.locator('[data-tog],[data-go]').count()) > 0, `${id}/${scen}: the attach step shows no preview`);
    if (await sw.count()) {
      const key = await sw.getAttribute('data-tog');
      const before = await page.locator(`[data-testid="story"] [data-att="${key}"]`).first().getAttribute('data-on');
      await sw.click();
      const after = await page.locator(`[data-testid="story"] [data-att="${key}"]`).first().getAttribute('data-on');
      check(before !== after, `${id}/${scen}: switching ${key} changed nothing`);
    }
  }
}

// 4. List content: never sent without a choice. Today and FB1 attach none; FB2's screenshot hides every name
// until one row is tapped; FB3's item chip can be removed.
await open('', 'FB2');
await page.locator('[data-testid="shake"]').click();
await page.locator('[data-live] [data-testid="report"]').click();
const shotText = () => page.locator('[data-live] [data-testid="screenshot"]').innerText();
const listText = /Oat milk|Bananas|Apples|Milk|Butter|Pasta|Rice|Fruit|Chilled|Pantry|Brandt|No store|\p{Extended_Pictographic}/u;
check(!listText.test(await shotText()), `FB2: the screenshot shows list text or emoji before the user reveals a row (${(await shotText()).match(listText)})`);
await page.locator('[data-live] [data-testid="screenshot"] [data-tog="reveal"]').click();
const revealed = (await shotText()).replace(/Oat milk|🥣/g, '');
check(/Oat milk/.test(await shotText()) && !listText.test(revealed), 'FB2: tapping a row does not reveal exactly that row');
check((await page.locator('[data-live] [data-testid="screenshot"] .marked').innerText()).includes('Oat milk'), 'FB2: the highlight is not on the revealed row');
for (const id of ['today', 'FB1']) {
  await open('', id);
  check((await page.locator('[data-testid="story"] .att-row.list').count()) === 0, `${id}: attaches list content`);
}
await open('', 'FB3');
await page.locator('[data-testid="story"] [data-testid="item-chip"] button').first().click();
check((await page.locator('[data-testid="story"] [data-testid="item-chip"]').count()) === 0, 'FB3: the item chip cannot be removed');

// 5. The table: measured taps, six rows, a pick and a runner-up that RECOMMENDATION.md names, and the
// Markdown table equal to the page's.
await open('', '');
const rows = await page.$$eval('[data-testid="comparison"] tr[data-row]', (trs) =>
  trs.map((tr) => ({
    id: tr.dataset.row,
    taps: tr.querySelector('[data-taps]').dataset.taps,
    debug: tr.querySelector('[data-debug]').dataset.debug,
    exposure: tr.querySelector('[data-exposure]').dataset.exposure,
    build: tr.querySelector('[data-build]').dataset.build,
    service: tr.querySelector('[data-service]').dataset.service,
  })),
);
check(rows.length === 6, `table has ${rows.length} rows, not 6`);
for (const r of rows) check(r.taps === measured[r.id].join(','), `${r.id}: table says ${r.taps} taps, driving took ${measured[r.id].join(',')}`);
check(rows.some((r) => r.service === '1') && rows.some((r) => r.service === '0' && r.id !== 'today'), 'need one option on an existing service and one on today’s stack');
const tsv = ['option\ttaps (bug,error,idea)\tdebug signals\texposure points\tbuild days\texisting service', ...rows.map((r) => `${r.id}\t${r.taps}\t${r.debug}\t${r.exposure}\t${r.build}\t${r.service}`)].join('\n');
writeFileSync(join(out, 'comparison.tsv'), `${tsv}\n`);
for (const file of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
  const md = readFileSync(join(here, file), 'utf8');
  const table = md.match(/<!-- table -->([\s\S]*?)<!-- \/table -->/)?.[1] ?? '';
  for (const r of rows) {
    const line = table.split('\n').find((l) => l.startsWith(`| ${r.id === 'today' ? (file.includes('.de') ? 'Heute' : 'Today') : r.id} `));
    check(!!line, `${file}: no table row for ${r.id}`);
    if (line) {
      const cells = line.split('|').map((c) => c.trim());
      check(cells[2] === r.taps.split(',').join(' · '), `${file}: ${r.id} taps ${cells[2]} ≠ ${r.taps}`);
      check(cells[3] === r.debug.split(',').join(' · '), `${file}: ${r.id} debug ${cells[3]} ≠ ${r.debug}`);
      check(cells[4].includes(`(${r.exposure})`), `${file}: ${r.id} exposure ${cells[4]} ≠ ${r.exposure}`);
    }
  }
  const qs = [...md.matchAll(/\*\*FB-Q(\d+)\b/g)].map((m) => Number(m[1]));
  check(qs.length >= 3 && qs.every((n, i) => n === i + 1), `${file}: open questions not numbered FB-Q1… in order (${qs})`);
  const qBlocks = md.split(/\n(?=\d+\. \*\*FB-Q)/).slice(1);
  check(qBlocks.every((b) => /Default|Vorgabe/.test(b)), `${file}: an open question has no default`);
  check(/FB3/.test(md.split('\n').slice(0, 8).join('\n')) && /FB2/.test(md.split('\n').slice(0, 8).join('\n')), `${file}: pick (FB3) and runner-up (FB2) not named at the top`);
}
const pick = await page.locator('tr.pick').getAttribute('data-row');
check(pick === 'FB3', `the table stars ${pick}, the recommendation picks FB3`);

// 6. The way back to the overview of all rounds.
const back = (await page.locator('[data-testid="back"]').getAttribute('href')) ?? '';
check(back.startsWith('../'), 'no link back to the overview');
const backRes = await page.request.get(new URL(back, page.url()).href);
if (backRes.ok()) {
  await page.locator('[data-testid="back"]').click();
  await page.waitForSelector('.rounds a');
  const links = await page.$$eval('.rounds a', (as) => as.map((a) => a.getAttribute('href')));
  check(links.some((l) => l.startsWith('../feedback-experience/')), `the overview does not list this round (${links})`);
  await page.locator('.rounds a[href^="../feedback-experience/"]').click();
  await page.waitForSelector('main.view');
  check(new URL(page.url()).pathname.endsWith('/feedback-experience/'), `the overview's link does not come back here (${page.url()})`);
} else console.log(`note: ${back} is not in this build (${backRes.status()}); run against build.sh's output with the overview to check the round trip`);

// 7. Screenshots: every option, EN/DE × light/dark × 100/200 %, plus each scenario once; layout checks on each.
const shots = [];
for (const id of ids)
  for (const lang of ['en', 'de'])
    for (const theme of ['light', 'dark'])
      for (const ts of ['100', '200']) shots.push({ id, lang, theme, ts, scen: 'bug' });
for (const id of ids) for (const scen of ['error', 'idea']) shots.push({ id, lang: 'en', theme: 'light', ts: '100', scen });
for (const s of shots) {
  await open(new URLSearchParams({ lang: s.lang, theme: s.theme, ts: s.ts, scen: s.scen }).toString(), s.id);
  const name = `${s.id}-${s.scen}-${s.lang}-${s.theme}-${s.ts}`;
  await page.addStyleTag({ content: '.story { flex-wrap: wrap; overflow: visible; }' });
  await page.locator('[data-testid="story"]').screenshot({ path: join(out, `${name}.png`) });
  check((await page.locator('[data-testid="story"] figure[data-step="peter"]').count()) === 1, `${name}: no step 5 in the screenshot`);
  for (const m of await layoutMisses()) check(false, `${name}: ${m}`);
  if (s.lang === 'de') {
    const txt = await page.locator('[data-testid="story"] .phone').allInnerTexts();
    for (const en of ['Send feedback', 'Sent along', 'Your message', 'What do you need?', 'Not now']) check(!txt.join('\n').includes(en), `${name}: English “${en}” in the German phone`);
  }
}
for (const lang of ['en', 'de']) {
  await open(lang === 'de' ? 'lang=de' : '', '');
  await page.screenshot({ path: join(out, `overview-${lang}.png`), fullPage: true });
}

// 8. Peter's phone: one frame per screen width, the page itself never scrolls sideways.
const phonePage = await ctx.newPage();
await phonePage.setViewportSize({ width: 390, height: 844 });
for (const id of ['FB3', 'FB1']) {
  await phonePage.goto(`${base}#/${id}`);
  await phonePage.waitForSelector('main.view');
  const wide = await phonePage.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  check(wide <= 0, `390 px: ${id} page scrolls sideways by ${wide} px`);
  const hidden = await phonePage.$$eval('.controls .group, .controls button, .controls a', (els) => els.filter((e) => e.scrollWidth > e.clientWidth + 1 || e.getBoundingClientRect().right > innerWidth).map((e) => e.textContent.trim().slice(0, 20)));
  check(!hidden.length, `390 px: ${id} controls cut off or off screen (${hidden})`);
  await phonePage.screenshot({ path: join(out, `narrow-${id}.png`) });
}

check(errors.length === 0, `page errors: ${[...new Set(errors)].join(' | ')}`);
await browser.close();

console.log(`measured taps: ${ids.map((i) => `${i} ${measured[i].join('/')}`).join(', ')}`);
console.log(`screenshots: ${shots.length + 4} in ${out}`);
if (fails.length) {
  console.log(`${fails.length} check(s) failed:\n- ${[...new Set(fails)].join('\n- ')}`);
  process.exit(1);
}
console.log('all checks passed');
