// Drives both round pages in Chromium, measures the comparison tables and checks the required behaviours.
// Exits 1 on any miss, else prints "all checks passed (N)". With --write it stores the measured tables in
// <round>/measured.json and in the RECOMMENDATION files instead of comparing against them.
// Usage: node verify.mjs [<folder or url>] [<out dir>] [<playwright module dir>] [--write]
//   folder: the repo root (default) or a build.sh output (pages at <base>/add-sheet/<round>/).
import { createRequire } from 'node:module';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve } from './tools/serve.mjs';
import { probes } from './tools/probes.js';
import * as M from './model.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const write = process.argv.includes('--write');
const [target = join(here, '../../..'), out = '/tmp/273-verify', pwDir = `${process.env.HOME}/family-groceries/e2e/node_modules/`] = args;
const require = createRequire(pwDir);
const { chromium } = require('playwright');

let base, server, built = false;
if (/^https?:/.test(target)) base = target.replace(/\/$/, '');
else {
  ({ server, url: base } = await serve(target));
  const inRepo = await stat(join(target, 'docs/design/add-sheet')).then(() => true, () => false);
  base += inRepo ? '/docs/design/add-sheet' : '/add-sheet';
  built = !inRepo && (await stat(join(target, 'overview.js')).then(() => true, () => false));
}
await mkdir(out, { recursive: true });

const fails = [];
let checks = 0;
const ok = (cond, msg) => {
  checks++;
  if (!cond) fails.push(msg);
  return !!cond;
};
const browser = await chromium.launch();
const newPage = async ({ w = 1700, h = 1000, reduced = false } = {}) => {
  const p = await browser.newPage({ viewport: { width: w, height: h }, reducedMotion: reduced ? 'reduce' : 'no-preference' });
  p.on('pageerror', (e) => fails.push(`page error: ${e}`));
  return p;
};
const open = async (p, round, q = {}) => {
  await p.goto(`${base}/${round}/?${new URLSearchParams(q)}`);
  await p.waitForFunction(() => window.__page && document.querySelectorAll('[data-host] .phone').length);
  await p.evaluate(() => document.fonts.ready);
  await p.evaluate(`window.__probe = (${probes.toString()})()`);
};
const phoneSel = (opt, frame) => `[data-host][data-opt="${opt}"][data-frame="${frame}"]`;


// ---- round AF ----
const AF = 'add-feedback';
const { round: af } = await import('./add-feedback/options.js');
const lastRec = (opt, frame) => `(() => { const ph = window.__page.phones['${opt}:${frame}']; const r = ph.adds.at(-1); return { id: r.itemId, name: r.name, store: ph.storeName(r.storeId), cat: ph.catName(r.categoryId), storeId: r.storeId, why: r.why }; })()`;
const recsOf = (opt, frame) => `window.__page.phones['${opt}:${frame}'].session.map((r) => ({ id: r.itemId, name: r.name, store: window.__page.phones['${opt}:${frame}'].storeName(r.storeId), cat: window.__page.phones['${opt}:${frame}'].catName(r.categoryId) }))`;
const idOf = async (p, opt, frame, rec) => p.evaluate(([sel, r]) => window.__probe.identify(document.querySelector(sel).querySelector('.phone'), r), [phoneSel(opt, frame), rec]);

// The window shows the phone, the list shows the row a third of the way down (above the dock).
const bringIntoView = (e) => {
  e.closest('.phone').scrollIntoView({ block: 'center' });
  const list = e.closest('.list');
  if (list) list.scrollTop += e.getBoundingClientRect().top - list.getBoundingClientRect().top - list.clientHeight / 3;
};

// Walks a fix path with real clicks; returns the taps it took, or null when the option has no such path.
const walk = async (p, opt, frame, kind, when) => {
  const o = af.options.find((x) => x.id === opt);
  const rec = await p.evaluate(lastRec(opt, frame));
  const to = kind === 'store' ? (rec.storeId === 'lidl' ? 'rewe' : 'lidl') : 'pantry';
  const path = o.fix[when][kind]?.(rec.id, to, kind);
  if (!path) return { taps: null };
  const host = p.locator(phoneSel(opt, frame));
  for (const step of path) {
    const hold = step.startsWith('hold:');
    const el = host.locator(hold ? step.slice(5) : step);
    const n = await el.count();
    if (!ok(n === 1, `AF ${opt} ${when} fix ${kind}: ${n} controls for ${step}`)) return { taps: null, broken: true };
    await el.evaluate(bringIntoView);
    await p.waitForTimeout(50);
    await el.evaluate(bringIntoView);
    const box = await el.boundingBox();
    if (!ok(box && box.height >= 44 && box.width >= 44, `AF ${opt} ${when} fix ${kind}: ${step} is ${box?.width}×${box?.height}`)) return { taps: null, broken: true };
    if (hold) {
      await p.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await p.mouse.down();
      await p.waitForTimeout(550);
      await p.mouse.up();
    } else await el.click();
    await p.waitForTimeout(40);
  }
  const now = await p.evaluate(([o, f, id]) => window.__page.phones[`${o}:${f}`].byId(id), [opt, frame, rec.id]);
  const done = kind === 'store' ? now.storeId === to : now.categoryId === to;
  ok(done, `AF ${opt} ${when} fix ${kind}: the walk did not change it`);
  return { taps: done ? path.length : null, rec, to, own: !path[0].startsWith('hold:') };
};

// The list behind the add band: with the list hidden, does any pixel of the band (from the field's bar down) change?
// The phone's corners are squared for both shots and the bar's first, fractional pixel row is left out: both blend
// the list into their anti-aliased edge.
const bandShowsList = async (p, sel) => {
  const phone = p.locator(`${sel} .phone`);
  const top = await p.evaluate((s) => {
    const ph = document.querySelector(s).querySelector('.phone');
    ph.style.borderRadius = '0';
    return Math.ceil(ph.querySelector('.addbar').getBoundingClientRect().top - ph.getBoundingClientRect().top) + 1;
  }, sel);
  const a = await phone.screenshot();
  await p.evaluate((s) => (document.querySelector(s).querySelector('.list').style.visibility = 'hidden'), sel);
  const b = await phone.screenshot();
  await p.evaluate((s) => {
    const ph = document.querySelector(s).querySelector('.phone');
    ph.querySelector('.list').style.visibility = '';
    ph.style.borderRadius = '';
  }, sel);
  const url = (buf) => `data:image/png;base64,${buf.toString('base64')}`;
  const d = await p.evaluate(([x, y, t]) => window.__probe.diff(x, y, t), [url(a), url(b), top]);
  return d.strong + d.weak;
};

const rank = { no: 0, name: 1, partly: 2, yes: 3 };
const af1 = {};
const ts2 = {};
{
  const p = await newPage();
  // 1. While open: item, store and section identifiable in the text a reader sees, the worst of four scenarios in
  // English and German, at 100 % and 200 %.
  for (const ts of ['100', '200'])
    for (const lang of ['en', 'de'])
      for (const scen of ['one', 'long', 'first', 'empty']) {
        await open(p, AF, { scen, ts, lang });
        for (const o of af.options) {
          const r = (af1[o.id] ??= {});
          const v = await idOf(p, o.id, 'open', await p.evaluate(lastRec(o.id, 'open')));
          if (!r[`id${ts}`] || rank[v] < rank[r[`id${ts}`].v]) r[`id${ts}`] = { v, at: `${lang} ${scen}` };
        }
      }
  for (const ts of ['100', '200']) {
    await open(p, AF, { scen: 'one', ts });
    for (const o of af.options) {
      const r = af1[o.id];
      // The sheet's height above the field.
      if (ts === '100')
        r.height = await p.evaluate((sel) => {
          const ph = document.querySelector(sel).querySelector('.phone');
          const field = ph.querySelector('.addbar').getBoundingClientRect().top;
          const tops = [...ph.querySelectorAll('.sheet, .toast')].map((e) => e.getBoundingClientRect().top);
          return Math.round(field - Math.min(...tops));
        }, phoneSel(o.id, 'open'));
      // 2. After the close: whole rows visible, the added item among them, list text half under a toast or bar.
      const after = await p.evaluate(lastRec(o.id, 'after'));
      r[`rows${ts}`] = await p.evaluate(([sel, id]) => {
        const ph = document.querySelector(sel).querySelector('.phone');
        const rows = window.__probe.rowsVisible(ph);
        return { n: rows.length, has: rows.some((x) => x.dataset.item === id), half: window.__probe.halfUnder(ph) };
      }, [phoneSel(o.id, 'after'), after.id]);
      // 3. Room for suggestions while typing: whole rows in view for the letter with the most rows.
      r[`sugg${ts}`] = await p.evaluate((k) => {
        const ph = window.__page.phones[k];
        const best = [...'abcdefghijklmnopqrstuvwxyz'].map((c) => (ph.type(c), [c, ph.sheet.rows.length])).sort((a, b) => b[1] - a[1])[0];
        ph.type(best[0]);
        ph.render();
        const body = ph.host.querySelector('.sheet-body').getBoundingClientRect();
        const n = [...ph.host.querySelectorAll('.srow')].filter((x) => {
          const r = x.getBoundingClientRect();
          return r.top >= body.top - 1 && r.bottom <= body.bottom + 1;
        }).length;
        ph.type('');
        ph.render();
        return { n, of: best[1] };
      }, `${o.id}:open`);
      ok(r[`sugg${ts}`].of >= 6, `AF ${o.id} ${ts}%: the best letter brings only ${r[`sugg${ts}`].of} suggestion rows`);
    }
  }
  // Find after the close: 0 if the row shows, 1 if one control brings it, else the scroll it takes. An option whose
  // control goes away after a while (`lasts`) is measured again once it has.
  const findIn = async (sel, id) => {
    const shows = () => p.evaluate(([s, i]) => window.__probe.rowsVisible(document.querySelector(s).querySelector('.phone')).some((x) => x.dataset.item === i), [sel, id]);
    if (await shows()) return { taps: 0 };
    const show = p.locator(`${sel} [data-act="show"]`);
    if ((await show.count()) === 1) {
      await show.click();
      await p.waitForTimeout(100);
      if (await shows()) return { taps: 1 };
    }
    return {
      scroll: await p.evaluate(([s, i]) => {
        const ph = document.querySelector(s).querySelector('.phone');
        const row = ph.querySelector(`[data-item="${i}"]`).getBoundingClientRect();
        return Math.round(row.bottom - window.__probe.coverTop(ph));
      }, [sel, id]),
    };
  };
  const outlast = async (o, sel) => {
    await p.evaluate((k) => window.__page.phones[k].wake(), `${o.id}:after`);
    await p.waitForTimeout(o.lasts + 300);
    ok((await p.locator(`${sel} [data-act="show"], ${sel} [data-toast], ${sel} [data-bar]`).count()) === 0, `AF ${o.id}: its control is still there ${o.lasts} ms after the close`);
  };
  for (const o of af.options) {
    await open(p, AF, { scen: 'one' });
    const sel = phoneSel(o.id, 'after');
    const rec = await p.evaluate(lastRec(o.id, 'after'));
    af1[o.id].find = await findIn(sel, rec.id);
    if (o.lasts) {
      await open(p, AF, { scen: 'one' });
      await outlast(o, sel);
      af1[o.id].findLate = await findIn(sel, rec.id);
    }
  }
  // Fix walks: each on a fresh page, from the open frame, from the after-close frame, and once the option's control
  // has gone (`late`).
  for (const o of af.options)
    for (const when of ['open', 'after', 'late'])
      for (const kind of ['store', 'cat']) {
        if (when === 'late' && !o.lasts) continue;
        await open(p, AF, { scen: 'one' });
        const frame = when === 'late' ? 'after' : when;
        if (when === 'late') await outlast(o, phoneSel(o.id, frame));
        const w = await walk(p, o.id, frame, kind, when);
        af1[o.id][`fix_${when}_${kind}`] = w.taps;
        // The correction moves the row into the other store's section.
        if (w.taps && kind === 'store')
          ok(
            await p.evaluate(([sel, id, to]) => !!document.querySelector(`${sel} section[data-store="${to}"] [data-item="${id}"]`), [phoneSel(o.id, frame), w.rec.id, w.to]),
            `AF ${o.id} ${when}: the fixed row is not in ${w.to}’s section`,
          );
        // What the option's feedback shows after the fix: no store (or section) but the new one, and the new one
        // wherever the fix went through the option's own control.
        if (w.taps) {
          const fb = await p.evaluate((sel) => window.__probe.feedbackText(document.querySelector(sel).querySelector('.phone')), phoneSel(o.id, frame));
          const names = kind === 'store' ? M.stores.map((s) => s.name) : M.categories.map((c) => c.en);
          const want = kind === 'store' ? M.storeName(w.to, 'en') : M.catName(w.to, 'en');
          const named = names.filter((n) => new RegExp(`(^|[^\\p{L}])${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^\\p{L}])`, 'u').test(fb));
          ok(named.every((n) => n === want), `AF ${o.id} ${when} fix ${kind}: after the fix to ${want} its feedback shows ${named.filter((n) => n !== want)}: “${fb}”`);
          if (w.own) ok(named.includes(want), `AF ${o.id} ${when} fix ${kind}: after the fix its feedback does not show ${want}: “${fb}”`);
        }
      }
  // The correction sticks: fix the first-time grocery to Rewe, buy it, add it again by typing and tapping.
  for (const o of af.options) {
    await open(p, AF, { scen: 'first' });
    const when = o.fix.open.store ? 'open' : 'after';
    const sel = phoneSel(o.id, when);
    const rec = await p.evaluate(lastRec(o.id, when));
    const path = o.fix[when].store(rec.id, 'rewe', 'store');
    const host = p.locator(sel);
    for (const step of path) {
      const hold = step.startsWith('hold:');
      const el = host.locator(hold ? step.slice(5) : step);
      await el.evaluate(bringIntoView);
      const box = await el.boundingBox();
      if (hold) {
        await p.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await p.mouse.down();
        await p.waitForTimeout(550);
        await p.mouse.up();
      } else await el.click();
    }
    const learned = await host.locator('.learned').count();
    if (o.id !== 'today') ok(learned === 1, `AF ${o.id}: no “Learned” line after the fix`);
    await p.evaluate(([k, id]) => {
      const ph = window.__page.phones[k];
      ph.buy(id);
      ph.close();
      ph.render();
    }, [`${o.id}:${when}`, rec.id]);
    await host.locator('input.field').click();
    await p.keyboard.type('Hallo', { delay: 40 });
    await host.locator('.srow[data-name="Halloumi"]').first().click();
    const again = await p.evaluate(lastRec(o.id, when));
    const shown = await idOf(p, o.id, when, again);
    const why = await host.locator('.sheet, .toast, .list').first().evaluate((e, w) => e.closest('.phone').textContent.includes(w), o.id === 'today' ? 'Rewe' : 'remembered');
    const sticks = again.storeId === 'rewe' && ['yes', 'partly'].includes(shown);
    af1[o.id].sticks = sticks;
    ok(sticks && why, `AF ${o.id}: the correction did not stick or show (${again.storeId}, ${shown}, why ${why})`);
  }
  // Today's note names the store whenever main's does: suggest_entries' typed row carries parse_item's store (the
  // remembered one, else the category's: dm for drugstore items), so Enter on a typed item shows it.
  for (const [lang, word, want] of [
    ['en', 'Eggs', '✓ Added: Eggs → Lidl'],
    ['en', 'Soap', '✓ Added: Soap → dm'],
    ['en', 'Halloumi', '✓ Added: Halloumi'],
    ['de', 'Eier', '✓ Hinzugefügt: Eier → Lidl'],
    ['de', 'Seife', '✓ Hinzugefügt: Seife → dm'],
  ]) {
    await open(p, AF, { scen: 'one', lang });
    const host = p.locator(phoneSel('today', 'after'));
    await host.locator('input.field').click();
    await p.keyboard.type(word, { delay: 30 });
    await p.keyboard.press('Enter');
    const note = (await host.locator('[data-note] p').innerText()).trim();
    ok(note === want, `AF today: “${word}” + Enter shows “${note}”, main shows “${want}”`);
  }
  // Several adds: how many of the three are identifiable while the sheet is open, at 100 % and 200 %.
  for (const ts of ['100', '200']) {
    await open(p, AF, { scen: 'several', ts });
    for (const o of af.options) {
      const recs = await p.evaluate(recsOf(o.id, 'open'));
      ok(recs.length === 3, `AF ${o.id} several: ${recs.length} adds`);
      let n = 0;
      for (const r of recs) if ((await idOf(p, o.id, 'open', r)) === 'yes') n++;
      af1[o.id][`several${ts}`] = `${n}/${recs.length}`;
    }
  }
  // ST1 in “first”: the options default Halloumi to Lidl, usual for Chilled; Today leaves it without a store.
  await open(p, AF, { scen: 'first' });
  for (const o of af.options) {
    const r = await p.evaluate(lastRec(o.id, 'open'));
    if (o.id === 'today') ok(r.storeId === null, `AF today first: Halloumi got ${r.storeId}, main gives no store`);
    else {
      ok(r.storeId === 'lidl' && r.why === 'usual', `AF ${o.id} first: ST1 gave ${r.storeId}/${r.why}`);
      const text = await p.locator(phoneSel(o.id, 'open')).innerText();
      const textAfter = await p.locator(phoneSel(o.id, 'after')).innerText();
      ok(/usual for Chilled/i.test(text + textAfter), `AF ${o.id} first: “usual for Chilled” not shown`);
    }
  }
  // Empty section: the peas open Lidl’s Frozen section, which was not there before.
  await open(p, AF, { scen: 'empty' });
  for (const o of af.options) {
    const has = await p.evaluate((sel) => !!document.querySelector(`${sel} section[data-store="lidl"] [data-cat="frozen"]`), phoneSel(o.id, 'after'));
    const before = await p.evaluate(() => {
      const ph = Object.values(window.__page.phones)[0];
      return ph.items.filter((it) => it.categoryId === 'frozen' && it.key !== 'peas').length;
    });
    ok(has && before === 0, `AF ${o.id} empty: the Frozen section did not appear`);
  }
  // Faults at 200 % (EN and DE), every scenario and frame, split into the option's own and main's chrome; targets
  // at 100 % too; nothing of the list shows through the add band (EN).
  for (const lang of ['en', 'de'])
    for (const ts of ['100', '200'])
      for (const scen of Object.keys(af.scenarios)) {
        await open(p, AF, { scen, ts, lang });
        for (const o of af.options) {
          for (const f of af.frames) {
            const sel = phoneSel(o.id, f.id);
            const res = await p.evaluate((s) => {
              const ph = document.querySelector(s).querySelector('.phone');
              return { faults: window.__probe.faults(ph), small: window.__probe.targets(ph), off: window.__probe.offCentre(ph), order: window.__probe.readingOrder(ph) };
            }, sel);
            if (ts === '200') (ts2[o.id] ??= []).push(...res.faults.map((x) => ({ ...x, what: `${lang} ${scen} ${f.id}: ${x.what}` })));
            ok(!res.small.length, `AF ${o.id} ${lang} ${ts}% ${scen} ${f.id}: targets under 44 px: ${res.small.slice(0, 3).join('; ')}`);
            ok(!res.off.length, `AF ${o.id} ${lang} ${ts}% ${scen} ${f.id}: hex content off centre: ${res.off.slice(0, 3).join('; ')}`);
            ok(!res.order.length, `AF ${o.id} ${lang} ${ts}% ${scen} ${f.id}: a hex label does not read as one run of text: ${res.order.slice(0, 3).join('; ')}`);
            if (lang === 'en') {
              const px = await bandShowsList(p, sel);
              ok(px === 0, `AF ${o.id} ${ts}% ${scen} ${f.id}: ${px} px of the list show through the add band`);
            }
          }
        }
      }
  for (const o of af.options) {
    af1[o.id].overflow = ts2[o.id].filter((x) => !x.chrome).length;
    af1[o.id].chrome = ts2[o.id].filter((x) => x.chrome).length;
    ok(!af1[o.id].overflow, `AF ${o.id}: its own text is cut, spills or overlaps at 200 %: ${ts2[o.id].filter((x) => !x.chrome).slice(0, 3).map((x) => x.what).join(' | ')}`);
  }
  // Suggestion rows left in view right after an add, with the note, card or toast up (the fewest over the scenarios);
  // a note's
  // reason (“usual for Chilled”) starts a line of its own; a list that scrolled to an add shows the row whole, with its
  // category header or store divider above it, below the list's top edge.
  for (const ts of ['100', '200'])
    for (const scen of Object.keys(af.scenarios)) {
      await open(p, AF, { scen, ts });
      for (const o of af.options) {
        const open1 = await p.evaluate((sel) => {
          const ph = document.querySelector(sel).querySelector('.phone');
          const body = ph.querySelector('.sheet-body').getBoundingClientRect();
          const rows = [...ph.querySelectorAll('.srow')].filter((x) => x.getBoundingClientRect().top >= body.top - 1 && x.getBoundingClientRect().bottom <= body.bottom + 1).length;
          const whys = [...ph.querySelectorAll('small.why')].map((w) => {
            const r = w.getBoundingClientRect(), pr = w.parentElement.getBoundingClientRect();
            return r.left - parseFloat(getComputedStyle(w.parentElement).paddingLeft) - pr.left;
          });
          return { rows, whys };
        }, phoneSel(o.id, 'open'));
        const least = (af1[o.id][`afterAdd${ts}`] ??= { n: Infinity });
        if (open1.rows < least.n) Object.assign(least, { n: open1.rows, at: scen });
        ok(open1.whys.every((d) => Math.abs(d) <= 1), `AF ${o.id} ${ts}% ${scen}: the reason does not start its own line (${open1.whys})`);
        for (const f of af.frames) {
          const res = await p.evaluate(([sel, k]) => {
            const ph = document.querySelector(sel).querySelector('.phone');
            const model = window.__page.phones[k];
            const rec = model.session.at(-1);
            const list = ph.querySelector('.list');
            if (!rec || !list.scrollTop || ph.querySelector('.scrim')) return null;
            const wrap = list.querySelector(`[data-item="${rec.itemId}"]`)?.closest('.item-wrap');
            if (!wrap) return null;
            let head = wrap.previousElementSibling;
            while (head && !head.matches('.cat')) head = head.previousElementSibling;
            const top = list.getBoundingClientRect().top, cover = window.__probe.coverTop(ph);
            const r = wrap.getBoundingClientRect(), h = head.getBoundingClientRect();
            return { row: r.top >= top - 1 && r.bottom <= cover + 1, head: h.top >= top - 1 };
          }, [phoneSel(o.id, f.id), `${o.id}:${f.id}`]);
          if (res) ok(res.row && res.head, `AF ${o.id} ${ts}% ${scen} ${f.id}: the scrolled-to row (${res.row}) or its header (${res.head}) is not whole below the list's top`);
        }
      }
    }
  await p.close();
}

// The AF table, from the measurements.
const yn = { en: { yes: 'yes', partly: 'partly', no: 'no', name: 'name only' }, de: { yes: 'ja', partly: 'teils', no: 'nein', name: 'nur Name' } };
// Today and the RI control have no code: their name is their label.
const rowName = (o, lang) => (/^[A-Z]{2}\d$/.test(o.id) ? `${o.id} ${o.name[lang]}` : o.name[lang]);
const afTable = (lang) => {
  const L = lang === 'de';
  const taps = (n) => (n == null ? '—' : String(n));
  const today = af1.today.height;
  const cols = L
    ? ['Variante', 'Artikel + Laden + Kategorie offen erkennbar 100 % / 200 % (schlechtestes von 4 Szenarien)', 'Drei hinzu: erkennbar (offen) 100 % / 200 %', 'Finden nach dem Schließen', 'Laden ändern: offen / danach (Tipps)', 'Kategorie ändern: offen / danach (Tipps)', 'Korrektur gilt beim nächsten Mal', 'Mehr Höhe als heute (offen, 100 %)', 'Text abgeschnitten, übergelaufen oder überlappt bei 200 %: Variante / Chrome wie main', 'Ganze Zeilen nach dem Schließen 100 % / 200 % (Artikel dabei)', 'Vorschlagszeilen beim Tippen 100 % / 200 % (von)', 'Vorschlagszeilen direkt nach dem Hinzufügen 100 % / 200 % (wenigste, Szenario)']
    : ['Option', 'Item + store + section identifiable while open 100 % / 200 % (worst of 4 scenarios)', 'Three adds: identifiable while open 100 % / 200 %', 'Find after the close', 'Fix store: open / after (taps)', 'Fix section: open / after (taps)', 'Correction sticks next time', 'Extra height vs Today (open, 100 %)', 'Text cut, spilling or overlapping at 200 %: option / main’s chrome', 'Whole rows after the close 100 % / 200 % (item among them)', 'Suggestion rows in view while typing 100 % / 200 % (of)', 'Suggestion rows in view right after an add 100 % / 200 % (fewest, scenario)'];
  const rows = af.options.map((o) => {
    const r = af1[o.id];
    const secs = o.lasts ? `${o.lasts / 1000} s` : '';
    const find1 = (f) => (f.taps === 0 ? (L ? '0 Tipps (schon sichtbar)' : '0 taps (already shows)') : f.taps === 1 ? (L ? '1 Tipp (Zeigen)' : '1 tap (Show)') : L ? `scrollen, ${f.scroll} px` : `scroll ${f.scroll} px`);
    const find = r.findLate ? (L ? `${find1(r.find)} für ${secs}, dann ${find1(r.findLate)}` : `${find1(r.find)} for ${secs}, then ${find1(r.findLate)}`) : find1(r.find);
    const after = (kind) => (o.lasts && r[`fix_late_${kind}`] !== r[`fix_after_${kind}`] ? (L ? `${taps(r[`fix_after_${kind}`])} für ${secs}, dann ${taps(r[`fix_late_${kind}`])}` : `${taps(r[`fix_after_${kind}`])} for ${secs}, then ${taps(r[`fix_late_${kind}`])}`) : taps(r[`fix_after_${kind}`]));
    const half = (v) => (v.half.length ? (L ? `, „${v.half[0]}“ halb darunter` : `, “${v.half[0]}” half under it`) : '');
    const vis = (v) => `${v.n} (${v.has ? (L ? 'ja' : 'yes') : L ? 'nein' : 'no'}${half(v)})`;
    const idv = (v) => (v.v === 'yes' ? yn[lang].yes : `${yn[lang][v.v]} (${v.at})`);
    const h = r.height - today;
    return [
      rowName(o, lang),
      `${idv(r.id100)} / ${idv(r.id200)}`,
      `${r.several100} / ${r.several200}`,
      find,
      `${taps(r.fix_open_store)} / ${after('store')}`,
      `${taps(r.fix_open_cat)} / ${after('cat')}`,
      r.sticks ? (L ? 'ja' : 'yes') : L ? 'nein' : 'no',
      o.id === 'today' ? `${r.height} px` : `${h >= 0 ? '+' : ''}${h} px`,
      `${r.overflow} / ${r.chrome}`,
      `${vis(r.rows100)} / ${vis(r.rows200)}`,
      `${r.sugg100.n} / ${r.sugg200.n} (${r.sugg100.of})`,
      `${r.afterAdd100.n} (${af.scenarios[r.afterAdd100.at].name[lang]}) / ${r.afterAdd200.n} (${af.scenarios[r.afterAdd200.at].name[lang]})`,
    ];
  });
  return { cols, rows };
};

// ---- round RI ----
const RI = 'reload-indicator';
const { round: ri } = await import('./reload-indicator/options.js');
const ri1 = {};
const ri200 = {};
// Samples every phone on every animation frame while a play runs: loading, indicator shown, sheet height, rows.
const sample = async (p, playId, ms) =>
  p.evaluate(
    ([id, ms]) =>
      new Promise((done) => {
        const { phones, round, play } = window.__page;
        const frames = [];
        const t0 = performance.now();
        const tick = () => {
          const t = performance.now() - t0;
          for (const [k, ph] of Object.entries(phones)) {
            if (!k.endsWith(':loading')) continue;
            const el = ph.host.querySelector('.phone');
            const sheet = el.querySelector('.sheet');
            const sel = round.options.find((o) => o.id === ph.opt.id).indicator;
            const ind = sel ? el.querySelector(sel) : null;
            const P = sheet && el.querySelector('.srow:nth-child(2)');
            frames.push({
              k: ph.opt.id,
              t,
              loading: ph.loading,
              key: ph.key,
              typed: ph.sheet.rows[0]?.name ?? '',
              ind: !!ind && ind.getBoundingClientRect().height > 0,
              h: sheet ? Math.round(sheet.getBoundingClientRect().height) : 0,
              rows: [...el.querySelectorAll('.srow')].map((r) => ({ n: r.dataset.name, y: Math.round(r.getBoundingClientRect().top) })),
              at: P ? Math.round(P.getBoundingClientRect().top + 20) : null,
            });
          }
          if (t < ms) requestAnimationFrame(tick);
          else done(frames);
        };
        play(round.plays.find((x) => x.id === id));
        requestAnimationFrame(tick);
      }),
    [playId, ms],
  );
// Every RI column but the 200 % one is measured in English and German at 100 % and 200 % text; the table reports the
// worst of the four with where it occurs.
const riSettings = [['en', '100'], ['en', '200'], ['de', '100'], ['de', '200']];
{
  const p = await newPage();
  for (const [lang, ts] of riSettings) {
    const at = `${lang} ${ts}`;
    await open(p, RI, { scen: 'typical', lang, ts });
    const frames = await sample(p, 'fast', 70 * 6 + 120 + 450 + 400);
    for (const o of ri.options) {
      const fs = frames.filter((f) => f.k === o.id);
      const loadingF = fs.filter((f) => f.loading);
      const firstLoad = loadingF[0];
      const firstInd = fs.find((f) => f.ind);
      const replyI = fs.findIndex((f, i) => i > 0 && fs[i - 1].loading && !f.loading);
      const r = ((ri1[o.id] ??= { per: {} }).per[at] = {});
      r.whole = o.indicator ? loadingF.slice(1).every((f) => f.ind) : false;
      r.toVisible = o.indicator && firstInd ? Math.round(firstInd.t - firstLoad.t) : null;
      // The first frame painted after the reply's rows: the indicator must be gone in it.
      r.goneInReply = o.indicator ? replyI > 0 && !fs[replyI].ind : null;
      const hs = loadingF.map((f) => f.h);
      r.hLoading = Math.max(...hs) - Math.min(...hs);
      r.hReply = replyI > 0 ? fs[replyI].h - fs[replyI - 1].h : 0;
      // Rows that move while loading: the same row (by its text) at a different height in two loading frames.
      let moved = 0;
      for (const f of loadingF) for (const row of f.rows) {
        const first = loadingF[0].rows.find((x) => x.n === row.n);
        if (first) moved = Math.max(moved, Math.abs(first.y - row.y));
      }
      r.moved = moved;
      // Under a pointer resting on the second row: is it the same row once the reply lands?
      const before = fs[replyI - 1], after = fs[replyI];
      const under = (f, y) => {
        const rs = f.rows.slice().sort((a, b) => a.y - b.y);
        return rs.filter((x) => x.y <= y).at(-1)?.n;
      };
      r.swapAtReply = before && after ? under(before, before.at) !== under(after, before.at) : null;
      r.typedLive = loadingF.slice(1).every((f) => f.typed.toLowerCase() === f.key.toLowerCase());
      ok(loadingF.length > 3, `RI ${o.id} ${at}: only ${loadingF.length} loading frames sampled`);
      ok(replyI > 0, `RI ${o.id} ${at}: the reply never landed in the sample`);
      if (o.indicator) {
        ok(r.goneInReply, `RI ${o.id} ${at}: indicator still there in the reply's frame`);
        ok(r.hLoading === 0, `RI ${o.id} ${at}: sheet height changed by ${r.hLoading} px while loading`);
      }
    }
    // Obviousness, the same way for every option: the loading phone with and without its indicator, pixel by pixel;
    // the pixels it changes by at least 3:1 (the visible mark: RI2's moving segment, RI3's ring, RI1's dimmed glyphs),
    // their median contrast, and the pixels it changes less (RI2's track). RI1 changes nothing when no row is stale.
    await open(p, RI, { scen: 'typical', lang, ts });
    await p.addStyleTag({ content: '.ri-off .loadline, .ri-off .spinner { visibility: hidden; } .ri-off .srow.stale { opacity: 1; transition: none; } .srow { transition: none !important; }' });
    for (const o of ri.options) {
      if (!o.indicator) {
        ri1[o.id].per[at].mark = null;
        continue;
      }
      const sel = phoneSel(o.id, 'loading');
      const phone = p.locator(`${sel} .phone`);
      const on = await phone.screenshot();
      await p.evaluate((s) => document.querySelector(s).querySelector('.phone').classList.add('ri-off'), sel);
      const off = await phone.screenshot();
      await p.evaluate((s) => document.querySelector(s).querySelector('.phone').classList.remove('ri-off'), sel);
      const url = (buf) => `data:image/png;base64,${buf.toString('base64')}`;
      ri1[o.id].per[at].mark = await p.evaluate(([a, b]) => window.__probe.diff(a, b), [url(on), url(off)]);
      ok(ri1[o.id].per[at].whole === ri1[o.id].per[at].mark.strong > 0, `RI ${o.id} ${at}: the play shows the indicator in every loading frame: ${ri1[o.id].per[at].whole}, the loading phone changes ${ri1[o.id].per[at].mark.strong} px by 3:1`);
    }
    // Taps during a slow reply: a tap on the second row adds the row it shows. German “Milch” has no second row
    // until the reply (the device knows nothing for “M”), so there is nothing to tap.
    await open(p, RI, { scen: 'typical', lang, ts });
    await p.evaluate(() => window.__page.play(window.__page.round.plays.find((x) => x.id === 'slowreply')));
    await p.waitForTimeout(220 * 5 + 300);
    for (const o of ri.options) {
      const host = p.locator(phoneSel(o.id, 'loading'));
      if ((await host.locator('.srow').count()) < 2) {
        ri1[o.id].per[at].tapOk = null;
        continue;
      }
      const row = host.locator('.srow').nth(1);
      const shown = await row.getAttribute('data-name');
      const loading = await p.evaluate((k) => window.__page.phones[k].loading, `${o.id}:loading`);
      await row.click();
      const added = await p.evaluate((k) => window.__page.phones[k].adds.at(-1)?.name, `${o.id}:loading`);
      ri1[o.id].per[at].tapOk = loading && added === shown;
      ok(loading, `RI ${o.id} ${at}: the slow reply had already landed before the tap`);
      ok(added === shown, `RI ${o.id} ${at}: a tap on “${shown}” during loading added “${added}”`);
    }
  }
  // Large text: the loading and settled frames at 200 % in EN and DE.
  for (const lang of ['en', 'de'])
    for (const ts of ['100', '200']) {
      await open(p, RI, { scen: 'typical', ts, lang });
      for (const o of ri.options)
        for (const f of ri.frames) {
          const res = await p.evaluate((sel) => {
            const ph = document.querySelector(sel).querySelector('.phone');
            return { faults: window.__probe.faults(ph), small: window.__probe.targets(ph), off: window.__probe.offCentre(ph), order: window.__probe.readingOrder(ph) };
          }, phoneSel(o.id, f.id));
          if (ts === '200') (ri200[o.id] ??= []).push(...res.faults.map((x) => ({ ...x, what: `${lang} ${f.id}: ${x.what}` })));
          ok(!res.small.length, `RI ${o.id} ${lang} ${ts}% ${f.id}: targets under 44 px: ${res.small.slice(0, 3).join('; ')}`);
          ok(!res.off.length, `RI ${o.id} ${lang} ${ts}% ${f.id}: hex content off centre: ${res.off.slice(0, 3).join('; ')}`);
          ok(!res.order.length, `RI ${o.id} ${lang} ${ts}% ${f.id}: a hex label does not read as one run of text: ${res.order.slice(0, 3).join('; ')}`);
        }
    }
  for (const o of ri.options) ri1[o.id].overflow = ri200[o.id].length;
  await p.close();
  // Reduced motion: the indicator stands still wherever it shows.
  const rm = await newPage({ reduced: true });
  for (const [lang, ts] of riSettings) {
    await open(rm, RI, { scen: 'typical', lang, ts });
    for (const o of ri.options) {
      if (!o.indicator) continue;
      const r = await rm.evaluate(([sel, ind]) => {
        const els = [...document.querySelector(sel).querySelectorAll(ind)].flatMap((e) => [e, ...e.querySelectorAll('*')]);
        return { moving: els.some((e) => getComputedStyle(e).animationName !== 'none'), rm: document.querySelector(sel).querySelector('.phone').classList.contains('rm') };
      }, [phoneSel(o.id, 'loading'), o.indicator]);
      ri1[o.id].per[`${lang} ${ts}`].still = !r.moving;
      ok(!r.moving && r.rm, `RI ${o.id} ${lang} ${ts}: with reduced motion the indicator still moves`);
    }
  }
  await rm.close();
}

// Each cell is the worst of the four settings (riSettings), with where it occurs when the settings differ.
const riTable = (lang) => {
  const L = lang === 'de';
  const y = (v) => (v == null ? '—' : v ? (L ? 'ja' : 'yes') : L ? 'nein' : 'no');
  const n = (x) => (L ? String(x).replace('.', ',') : String(x));
  const label = (at) => at.replace(/^(\w+) (\d+)$/, (_, l, t) => `${l.toUpperCase()} ${t} %`);
  const cols = L
    ? ['Variante', 'Anzeige während des ganzen Ladens (ms bis sichtbar)', 'Weg im ersten Frame mit den Zeilen der Antwort', 'Blatthöhe beim Laden / bei der Antwort', 'Zeile bewegt beim Laden', 'Zeile unter dem Finger wechselt bei der Antwort', 'Getippte Zeile zeigt den Text', 'Tipp beim Laden nimmt die gezeigte Zeile', 'Deutlichkeit, die geringste: Pixel, die die Anzeige um ≥ 3:1 ändert (Median), + schwächer geänderte', 'Text abgeschnitten, übergelaufen oder überlappt bei 200 % (Chrome wie main eingeschlossen)', 'Reduzierte Bewegung: steht still']
    : ['Option', 'Indicator during the whole load (ms to visible)', 'Gone in the first frame with the reply’s rows', 'Sheet height while loading / at the reply', 'Row moved while loading', 'Row under the finger swaps at the reply', 'Typed row shows the text', 'Tap while loading takes the row shown', 'Obviousness, the least: pixels the indicator changes by ≥ 3:1 (median), + pixels changed less', 'Text cut, spilling or overlapping at 200 % (main’s chrome included)', 'Reduced motion: stands still'];
  const rows = ri.options.map((o) => {
    const r = ri1[o.id];
    const per = Object.entries(r.per);
    // The worst value of `f` over the settings (`worse(a, b)`: a is worse than b), and where, unless everywhere.
    const worst = (f, worse) => {
      const vals = per.map(([at, m]) => [at, f(m)]);
      const v = vals.reduce((w, [, x]) => (worse(x, w) ? x : w), vals[0][1]);
      const ats = vals.filter(([, x]) => x === v).map(([at]) => label(at));
      return { v, where: ats.length === vals.length ? '' : ` (${ats.join(', ')})` };
    };
    const yes = (f) => {
      const w = worst(f, (a, b) => a === false && b !== false);
      return `${y(w.v)}${w.where}`;
    };
    const most = (f) => worst(f, (a, b) => Math.abs(a) > Math.abs(b));
    const fr = (ms) => (ms == null ? '' : ms <= 20 ? (L ? ' (≤ 1 Frame)' : ' (≤ 1 frame)') : ` (${Math.round(ms / 50) * 50} ms)`);
    const shownIn = per.filter(([, m]) => m.whole);
    const toVisible = shownIn.length ? Math.max(...shownIn.map(([, m]) => m.toVisible)) : null;
    const missing = per.filter(([, m]) => !m.whole).map(([at]) => label(at)).join(', ');
    const whole = !o.indicator || !shownIn.length ? y(false) : shownIn.length === per.length ? `${y(true)}${fr(toVisible)}` : L ? `nein bei ${missing}, sonst ja${fr(toVisible)}` : `no in ${missing}, else yes${fr(toVisible)}`;
    const hl = most((m) => m.hLoading), hr = most((m) => m.hReply);
    const mark = (x) => (x ? `${x.strong} px²${x.median ? ` (${n(x.median)}:1)` : ''} + ${x.weak} px²` : '');
    const fewest = per.map(([, x]) => x.mark).sort((a, b) => a?.strong - b?.strong || a?.weak - b?.weak)[0];
    const least = worst((x) => mark(x.mark), (a) => a === mark(fewest));
    const obvious = !o.indicator ? (L ? 'keine Anzeige' : 'no indicator') : `${least.v}${least.where}`;
    return [
      rowName(o, lang),
      whole,
      o.indicator ? yes((x) => x.goneInReply) : '—',
      `${hl.v} px${hl.where} / ${hr.v >= 0 ? '+' : ''}${hr.v} px${hr.where}`,
      `${most((x) => x.moved).v} px${most((x) => x.moved).where}`,
      (() => {
        const w = worst((x) => x.swapAtReply, (a, b) => a === true && b !== true);
        return `${y(w.v)}${w.where}`;
      })(),
      yes((x) => x.typedLive),
      (() => {
        const none = per.filter(([, x]) => x.tapOk == null).map(([at]) => label(at));
        if (!none.length) return yes((x) => x.tapOk);
        const tapped = per.filter(([, x]) => x.tapOk != null);
        const w = tapped.every(([, x]) => x.tapOk) ? y(true) : y(false);
        const at = tapped.filter(([, x]) => x.tapOk === (w === y(true))).map(([k]) => label(k)).join(', ');
        return L ? `${w} bei ${at}; keine zweite Zeile bei ${none.join(', ')}` : `${w} in ${at}; no second row in ${none.join(', ')}`;
      })(),
      obvious,
      String(r.overflow),
      o.indicator ? yes((x) => x.still) : '—',
    ];
  });
  return { cols, rows };
};

// ---- tables: write or compare ----
const mdTable = ({ cols, rows }) => `<!-- table -->\n| ${cols.join(' | ')} |\n| ${cols.map(() => '---').join(' | ')} |\n${rows.map((r) => `| ${r.map((c, i) => (i ? c : `**${c}**`)).join(' | ')} |`).join('\n')}\n<!-- /table -->`;
for (const [dir, tableOf, raw] of [[AF, afTable, af1], [RI, riTable, ri1]]) {
  const want = { table: { en: tableOf('en'), de: tableOf('de') }, raw };
  const file = join(here, dir, 'measured.json');
  if (write) await writeFile(file, `${JSON.stringify(want, null, 1)}\n`);
  const have = JSON.parse(await readFile(file, 'utf8').catch(() => 'null'));
  ok(JSON.stringify(have?.table) === JSON.stringify(want.table), `${dir}: measured table differs from ${dir}/measured.json (rerun with --write):\n${JSON.stringify(want.table.en.rows)}\n${JSON.stringify(have?.table?.en?.rows)}`);
  for (const [lang, f] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) {
    const path = join(here, dir, f);
    const md = await readFile(path, 'utf8').catch(() => '');
    const next = md.replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, mdTable(want.table[lang]));
    if (write && md.includes('<!-- table -->')) await writeFile(path, next);
    ok(md.includes('<!-- table -->') && (write || next === md), `${dir}/${f}: table differs from the measurements`);
  }
}

// ---- both pages: the page table, language, controls, recommendation, back link, screenshots ----
for (const [dir, round, prefix] of [[AF, af, 'AF'], [RI, ri, 'RI']]) {
  const p = await newPage();
  await open(p, dir);
  ok((await p.evaluate(() => document.documentElement.lang)) === 'en', `${dir}: not English without ?lang`);
  ok((await p.locator('input.field').first().getAttribute('placeholder')) === 'What do you need?', `${dir}: field not English`);
  const shown = await p.$$eval('[data-testid="comparison"] tr', (trs) => trs.map((tr) => [...tr.children].map((c) => c.textContent.trim())));
  const want = (dir === AF ? afTable : riTable)('en');
  ok(JSON.stringify(shown) === JSON.stringify([want.cols, ...want.rows]), `${dir}: the page table differs from the measurements`);
  ok((await p.locator('[data-play]').count()) === (dir === RI ? 2 : 0), `${dir}: play controls on the wrong page`);
  const scenNames = await p.$$eval('[data-set="scen"]', (bs) => bs.map((b) => b.dataset.v));
  ok(JSON.stringify(scenNames) === JSON.stringify(Object.keys(round.scenarios)), `${dir}: scenario controls are not this round’s`);
  const other = dir === AF ? ri : af;
  const body = await p.locator('.page-head').innerText();
  ok(!Object.values(other.scenarios).some((s) => body.includes(s.name.en)), `${dir}: shows the other round’s controls`);
  ok(!(await p.locator('.page-head').innerText()).includes(other.label + '1'), `${dir}: names the other round’s options`);
  ok((await p.locator('section.option').count()) === round.options.length && (await p.locator('[data-host]').count()) === round.options.length * 2, `${dir}: not every option shows both frames`);
  // Pick and runner-up come from one place, round.rec: the page's tags, the starred table row, the page's
  // recommendation headings and both RECOMMENDATION files name exactly those options.
  const { pick, runnerUp } = round.rec;
  const tagged = await p.$$eval('section.option', (ss) => ss.flatMap((x) => [...x.querySelectorAll('.tag')].map((t) => `${t.classList.contains('pick') ? 'pick' : 'runner'}:${x.dataset.option}`)));
  ok(JSON.stringify(tagged.sort()) === JSON.stringify([`pick:${pick}`, `runner:${runnerUp}`].sort()), `${dir}: page tags ${tagged}, want pick ${pick}, runner-up ${runnerUp}`);
  ok(JSON.stringify(await p.$$eval('table.cmp tr.pick', (trs) => trs.map((t) => t.dataset.row))) === JSON.stringify([pick]), `${dir}: the starred table row is not ${pick}`);
  const heads = { en: ['Pick', 'Runner-up'], de: ['Wahl', 'Zweite Wahl'] };
  const named = (text, lang) => heads[lang].map((h) => [...text.matchAll(new RegExp(`^#* *${h}: (\\S+)`, 'gm'))].map((m) => m[1]));
  for (const [lang, f] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) {
    const md = await readFile(join(here, dir, f), 'utf8');
    ok(JSON.stringify(named(md, lang)) === JSON.stringify([[pick], [runnerUp]]), `${dir}/${f}: names ${JSON.stringify(named(md, lang))}, want pick ${pick}, runner-up ${runnerUp}`);
  }
  const back = await p.locator('[data-testid="back"]').getAttribute('href');
  ok(back && (built ? back.startsWith('../../') : back.includes('list-declutter')), `${dir}: back link ${back}`);
  for (const lang of ['en', 'de']) {
    await open(p, dir, { lang });
    const qs = (await p.locator('[data-testid="rec"] ol > li').allInnerTexts()).filter((t) => t.startsWith(`${prefix}-Q`));
    const nums = qs.map((t) => Number(t.match(new RegExp(`^${prefix}-Q(\\d+)`))[1]));
    ok(nums.length >= 3 && nums.every((n, i) => n === i + 1), `${dir} ${lang}: questions not numbered ${prefix}-Q1… (${nums})`);
    const dflt = lang === 'de' ? 'Standard:' : 'Default:';
    ok(qs.every((t) => t.includes(dflt)), `${dir} ${lang}: a question without “${dflt}”`);
    const h3 = (await p.locator('[data-testid="rec"] h3').allInnerTexts()).join('\n');
    ok(JSON.stringify(named(h3, lang)) === JSON.stringify([[pick], [runnerUp]]), `${dir} ${lang}: the page's recommendation names ${JSON.stringify(named(h3, lang))}, want pick ${pick}, runner-up ${runnerUp}`);
    if (lang === 'de') {
      ok(!/Bereich/.test(await p.locator('body').innerText()), `${dir}: the German page says “Bereich”; the app says “Kategorie”`);
      ok(!/Bereich/.test(await readFile(join(here, dir, 'RECOMMENDATION.de.md'), 'utf8')), `${dir}/RECOMMENDATION.de.md says “Bereich”; the app says “Kategorie”`);
      ok((await p.evaluate(() => document.documentElement.lang)) === 'de', `${dir}: ?lang=de is not German`);
      ok((await p.locator('input.field').first().getAttribute('placeholder')) === 'Was brauchst du?', `${dir}: field not German`);
    }
  }
  // Screenshots: the whole page and every phone, EN/DE × light/dark × 100/200 %.
  const scens = dir === AF ? Object.keys(round.scenarios) : ['typical'];
  for (const lang of ['en', 'de'])
    for (const theme of ['light', 'dark'])
      for (const ts of ['100', '200'])
        for (const scen of scens) {
          await open(p, dir, { lang, theme, ts, scen });
          if (scen === scens[0] || scen === 'several') await p.screenshot({ path: `${out}/${dir}-${scen}-${lang}-${theme}-${ts}.png`, fullPage: true });
          for (const o of round.options) await p.locator(`section.option[data-option="${o.id}"]`).screenshot({ path: `${out}/${dir}-${scen}-${o.id}-${lang}-${theme}-${ts}.png` });
        }
  await p.close();
  // A phone-sized screen: one phone fills the width, the strip switches between Today and the options.
  const ph = await newPage({ w: 390, h: 844 });
  await open(ph, dir);
  const w = await ph.$eval('.cell.on .phone', (el) => el.getBoundingClientRect().width);
  ok(Math.abs(w - 390) < 2, `${dir}: on a phone the phone is ${w} px wide`);
  ok((await ph.locator('.cell:visible').count()) === 1, `${dir}: more than one phone shows on a phone`);
  ok((await ph.evaluate(() => document.documentElement.scrollWidth)) <= 391, `${dir}: the page scrolls sideways on a phone`);
  await ph.locator('[data-cell]').nth(2).click();
  ok((await ph.locator('.cell:visible [data-host]').getAttribute('data-opt')) === round.options[1].id, `${dir}: the strip does not switch phones`);
  await ph.screenshot({ path: `${out}/${dir}-phone-390x844.png` });
  await ph.close();
}

// In a preview build with the overview: overview → each round page → back.
if (built) {
  const p = await newPage();
  for (const lang of ['en', 'de'])
    for (const dir of [AF, RI]) {
      await p.goto(`${base.replace(/\/add-sheet$/, '')}/${lang === 'de' ? '?lang=de' : ''}`);
      const link = p.locator(`a[href^="../add-sheet/${dir}/"]`);
      if (!ok((await link.count()) === 1, `overview ${lang}: no link to ${dir}`)) continue;
      await link.click();
      await p.waitForSelector('[data-testid="back"]');
      await p.click('[data-testid="back"]');
      await p.waitForSelector('ul.rounds');
      ok((await p.locator(`a[href^="../add-sheet/${dir}/"]`).count()) === 1, `${dir} ${lang}: back link does not reach the overview`);
    }
  await p.close();
}

await browser.close();
server?.close();
console.log('AF', JSON.stringify(afTable('en').rows));
console.log('RI', JSON.stringify(riTable('en').rows));
for (const [k, v] of Object.entries(ts2)) if (v.length) console.log(`AF faults ${k}: ${v.map((x) => `${x.chrome ? '[chrome] ' : ''}${x.what}`).slice(0, 8).join(' | ')}`);
for (const [k, v] of Object.entries(ri200)) if (v.length) console.log(`RI faults ${k}: ${v.map((x) => x.what).slice(0, 6).join(' | ')}`);
for (const f of fails) console.log(`FAIL ${f}`);
if (fails.length) {
  console.log(`${checks} checks, ${fails.length} failed`);
  process.exit(1);
}
console.log(`all checks passed (${checks})`);
