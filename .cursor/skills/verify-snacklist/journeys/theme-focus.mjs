// Theme `theme-focus`: the keyboard focus indicator (FH1, job 487). Tab walks the guided start's
// stores step (chips, a picked chip, the own-store field, „Eigenen Laden hinzufügen“), the list,
// the add sheet with „Joghu“ typed, Läden and Einstellungen; each stop is a PNG. The pixels that
// changed from the stop before are split into areas and compared with the control under them:
// FH1 paints only inside the control, so no area may reach past it (the outer ring before reached
// 5 px), and each stop needs the focus colour (cobalt, navy on honey) come in a band at least
// about 2 px wide (WCAG 2.4.13); `knownFill` lists the controls that still show a grey fill, with why.
// A step that scrolled is shown, not measured.
//
//   cd .cursor/skills/verify-snacklist && node journeys/theme-focus.mjs <evidence dir> [--lang de|en] [--dark] [--stops N]
import process from 'node:process';
import { readFileSync } from 'node:fs';
import { addField, addSheet, apiAs, capture, instance, logger, member, openApp, openTab, repo, signIn, typeInto } from '../helpers/lib.mjs';

const [dir, ...rest] = process.argv.slice(2);
const arg = (name, fallback) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : fallback);
const lang = arg('--lang', 'de');
const dark = rest.includes('--dark');
const stops = Number(arg('--stops', '8'));
if (!dir) throw new Error('usage: theme-focus.mjs <evidence dir> [--lang de|en] [--dark] [--stops N]');

// The focus colours of the theme: cobalt, and navy on a honey face (design/tokens).
const tokens = JSON.parse(readFileSync(`${repo}/design/tokens/snacklist.tokens.json`, 'utf8'));
const inks = ['accent', 'on-honey'].map((k) => tokens.color[dark ? 'dark' : 'light'][k].$value.components.map((c) => Math.round(c * 255)));
// Controls that still show Material's grey focus fill, with the reason; a stop on one is logged, not failed.
const knownFill = [
  { name: /^(Sprache|Language)\b/, why: 'a ListTile row: the follow-up job in NEEDS_LEAD „Job 487“' },
];

const log = logger(dir);
const inst = instance();
const user = member(inst);
const api = await apiAs(inst, user);
for (const name of ['Supermarkt', 'Drogerie']) {
  const { error } = await api.rpc('add_store', { p_household: user.householdId, p_name: name });
  if (error && !/exists|duplicate/i.test(error.message)) throw error;
}
const opened = await openApp(inst, { lang, dark, videoDir: dir });
const { browser, L, errors } = opened;
let { page } = opened;
// The pixel compare runs in a page of its own context, so the journey's video has only the app.
let probeContext;

/** The boxes of the semantics nodes and inputs on the page, in CSS px. */
const nodes = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics, input, textarea')].map((el) => {
  const r = el.getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height, name: (el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').split('\n')[0].slice(0, 40) };
}).filter((b) => b.w > 0 && b.h > 0));

/**
 * The blobs of pixels that differ between two PNGs (8-connected after a 2 px dilation), each as a
 * box in CSS px. A focus move gives one blob for the indicator that went and one for the one that came.
 */
async function blobs(a, b, ink) {
  const probe = await (probeContext ??= await browser.newContext()).newPage();
  try {
    return await probe.evaluate(async ([a64, b64, dpr, inks, dark]) => {
      const load = async (s) => createImageBitmap(await (await fetch(`data:image/png;base64,${s}`)).blob());
      const [ia, ib] = await Promise.all([load(a64), load(b64)]);
      const pixels = (img) => {
        const c = new OffscreenCanvas(img.width, img.height);
        const g = c.getContext('2d');
        g.drawImage(img, 0, 0);
        return g.getImageData(0, 0, img.width, img.height).data;
      };
      const [pa, pb] = [pixels(ia), pixels(ib)];
      // Which focus colour a pixel is, or -1. Dark's page is the navy of on-honey, so a pixel
      // counts when it turns into a focus colour it was not.
      const inkOf = (p, j) => inks.findIndex(([r, g, b]) => Math.abs(p[j] - r) + Math.abs(p[j + 1] - g) + Math.abs(p[j + 2] - b) < 40);
      const { width: w, height: h } = ia;
      const diff = new Uint8Array(w * h);
      for (let i = 0; i < w * h; i++) {
        const j = i * 4;
        diff[i] = Math.abs(pa[j] - pb[j]) + Math.abs(pa[j + 1] - pb[j + 1]) + Math.abs(pa[j + 2] - pb[j + 2]) > 24 ? 1 : 0;
      }
      const seen = new Uint8Array(w * h);
      const out = [];
      const r = 2 * dpr;
      for (let start = 0; start < w * h; start++) {
        if (!diff[start] || seen[start]) continue;
        let x0 = w;
        let y0 = h;
        let x1 = -1;
        let y1 = -1;
        let count = 0;
        let inked = 0;
        let lost = 0;
        const stack = [start];
        seen[start] = 1;
        while (stack.length) {
          const i = stack.pop();
          const x = i % w;
          const y = (i - x) / w;
          count++;
          const ink = inkOf(pb, i * 4);
          const was = inkOf(pa, i * 4);
          if (ink >= 0 && ink !== was) inked++;
          // Dark's page is on-honey's navy, so only cobalt counts as lost there.
          if (was >= 0 && ink !== was && (was === 0 || !dark)) lost++;
          x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
          for (let dy = -r; dy <= r; dy++) {
            for (let dx = -r; dx <= r; dx++) {
              const nx = x + dx;
              const ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              const k = ny * w + nx;
              if (diff[k] && !seen[k]) { seen[k] = 1; stack.push(k); }
            }
          }
        }
        if (count >= 4 * dpr * dpr) out.push({ x: x0 / dpr, y: y0 / dpr, w: (x1 - x0 + 1) / dpr, h: (y1 - y0 + 1) / dpr, ink: inked / (dpr * dpr), lost: lost / (dpr * dpr) });
      }
      return out;
    }, [a.toString('base64'), b.toString('base64'), 2, ink, dark]);
  } finally {
    await probe.close();
  }
}

/**
 * The controls a blob belongs to: every node the blob covers at least half of. Rows touch, so one
 * blob can hold the row that lost focus and the one that got it; a ring's thin band over a
 * neighbour's tap target covers little of it. A blob that covers no node (one side of a tab's ring)
 * belongs to the smallest node holding its centre.
 */
function owners(blob, all) {
  const overlap = (n) => Math.max(0, Math.min(blob.x + blob.w, n.x + n.w) - Math.max(blob.x, n.x)) * Math.max(0, Math.min(blob.y + blob.h, n.y + n.h) - Math.max(blob.y, n.y));
  const cx = blob.x + blob.w / 2;
  const cy = blob.y + blob.h / 2;
  const holding = all.filter((n) => n.x <= cx && cx <= n.x + n.w && n.y <= cy && cy <= n.y + n.h).sort((p, q) => p.w * p.h - q.w * q.h);
  const covered = all.filter((n) => overlap(n) >= (n.w * n.h) / 2).sort((p, q) => p.w * p.h - q.w * q.h);
  if (!covered.length) return holding[0] ?? null;
  return covered.reduce((u, n) => ({
    x: Math.min(u.x, n.x), y: Math.min(u.y, n.y), w: Math.max(u.x + u.w, n.x + n.w) - Math.min(u.x, n.x), h: Math.max(u.y + u.h, n.y + n.h) - Math.min(u.y, n.y),
    name: u.name || n.name,
  }));
}

/** How far [blob] reaches past [box], in CSS px (0 when inside). */
const reach = (blob, box) => Math.max(0, box.x - blob.x, box.y - blob.y, blob.x + blob.w - (box.x + box.w), blob.y + blob.h - (box.y + box.h));

const measured = [];
/** Stops where no focus colour came in a band 2 px wide. */
const unseen = [];
/** Stops where focus went to a control that is not on screen. */
const offscreen = [];
async function walk(screen) {
  let shot = readFileSync(await capture(page, dir, `${screen}-00`));
  let before = await nodes();
  for (let i = 1; i <= stops; i++) {
    await page.keyboard.press('Tab');
    await page.waitForTimeout(400);
    const step = `${screen} ${i}`;
    const nextShot = readFileSync(await capture(page, dir, `${screen}-${String(i).padStart(2, '0')}`));
    const after = await nodes();
    const found = await blobs(shot, nextShot, inks);
    const { height } = page.viewportSize();
    if (found.length > 6 || found.some((b) => b.h > height / 2)) {
      log(`${step}: the screen scrolled or the list moved (${found.length} areas), not measured`);
    } else {
      let band = 0;
      let named = '';
      for (const blob of found) {
        const box = owners(blob, [...before, ...after]);
        const past = box ? reach(blob, box) : Infinity;
        measured.push({ step, name: box?.name, past });
        // The focus colour that came, as a band along the changed area's box. WCAG 2.4.13 asks
        // for the area of a 2 px perimeter; a round or hex outline is shorter than its box's, so
        // a 3 px ring in a 40 px circle reads 1.9 here and the bar is 1.5.
        const width = blob.ink / (2 * (blob.w + blob.h));
        if (width > band) [band, named] = [width, box?.name ?? ''];
        log(`${step}: changed ${JSON.stringify({ x: blob.x, y: blob.y, w: blob.w, h: blob.h, lost: Math.round(blob.lost) })} on ${box ? `${JSON.stringify(box.name)} ${JSON.stringify({ x: box.x, y: box.y, w: box.w, h: box.h })}` : 'no control'}; ${past.toFixed(1)} px past it; focus colour ${width.toFixed(1)} px wide`);
      }
      if (!found.length) log(`${step}: no pixel changed`);
      const focused = await page.evaluate(() => {
        const el = document.activeElement;
        return (el?.getAttribute('aria-label') || el?.textContent || '').trim().split('\n')[0] ?? '';
      });
      const known = knownFill.find((k) => k.name.test(focused) || found.some((b) => k.name.test(owners(b, [...before, ...after])?.name ?? '')));
      // Only a caret blinked: focus is in the add field, which has no ring (the open question in
      // NEEDS_LEAD „Job 487“); a field with the ring changes more than its caret.
      const caret = found.length > 0 && found.every((b) => b.w <= 3);
      // Every larger area only lost the focus colour: focus went to a control that is not on
      // screen. Logged, not failed: no indicator design can show it.
      const away = found.some((b) => b.lost > 0) && found.every((b) => b.ink < 4 && (b.lost > 0 || b.w * b.h < 400));
      if (band < 1.5 && away) {
        log(`${step}: focus left the screen (a control not drawn took it)`);
        offscreen.push(step);
      } else if (band < 1.5 && caret) {
        log(`${step}: only a caret changed: the add field, no ring (NEEDS_LEAD „Job 487“)`);
      } else if (band < 1.5 && known) {
        log(`${step}: no focus colour on ${JSON.stringify(focused)}, known: ${known.why}`);
      } else if (band < 1.5) {
        unseen.push(`${step} ${JSON.stringify(named || focused)} (${band.toFixed(1)} px)`);
      }
    }
    shot = nextShot;
    before = after;
  }
}

let failed = null;
try {
  log(`${lang}, ${dark ? 'dark' : 'light'}`);
  const start = await openApp(inst, { lang, locale: lang === 'en' ? 'en-DE' : 'de-DE', dark });
  try {
    const p = start.page;
    const next = () => p.getByRole('button', { name: L('onboardingNext'), exact: true }).click();
    await p.goto('/');
    await p.getByRole('button', { name: L('startGo'), exact: true }).click();
    await p.getByRole('button', { name: L('analyticsDecline'), exact: true }).click();
    await p.waitForURL(/\/start\/who/);
    await p.getByRole('checkbox', { name: L('kindPartner') }).click();
    await next();
    await p.waitForURL(/\/start\/name/);
    await next();
    await p.waitForURL(/\/start\/stores/);
    await p.getByRole('checkbox', { name: 'REWE', exact: true }).click();
    await p.getByRole('button', { name: L('storeAddOwn'), exact: true }).click();
    await p.waitForTimeout(600);
    const pageBefore = page;
    page = p;
    try {
      await walk('stores-step');
    } finally {
      page = pageBefore;
    }
  } catch (error) {
    await capture(start.page, dir, '99-failure-stores-step').catch(() => {});
    throw error;
  } finally {
    await start.browser.close();
  }
  await signIn(page, L, user);
  await addField(page, L).waitFor();
  await walk('list');

  await typeInto(addField(page, L), 'Joghu');
  await addSheet(page, L).waitFor({ timeout: 10_000 });
  await page.waitForTimeout(800);
  await walk('add-sheet');
  await page.reload();
  await addField(page, L).waitFor({ timeout: 30_000 });

  await page.getByRole('button', { name: L('listEdit'), exact: true }).click();
  await page.waitForTimeout(800);
  await walk('stores');
  await page.goBack();
  await page.waitForTimeout(500);

  await openTab(page, L, 'tabMore');
  await page.waitForTimeout(600);
  await page.getByRole('button', { name: L('settingsTitle'), exact: true }).first().click();
  await page.waitForTimeout(800);
  await walk('settings');

  const over = measured.filter((m) => m.past > 1);
  log(`measured ${measured.length} changed areas; the largest reaches ${Math.max(0, ...measured.map((m) => m.past)).toFixed(1)} px past its control`);
  if (offscreen.length) log(`focus left the screen at: ${offscreen.join('; ')}`);
  if (unseen.length) throw new Error(`no focus indicator at: ${unseen.join('; ')}`);
  if (over.length) throw new Error(`focus paint past the control: ${over.map((m) => `${m.step} ${JSON.stringify(m.name)} ${m.past.toFixed(1)} px`).join('; ')}`);
  if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
} catch (error) {
  failed = error;
  await capture(page, dir, '99-failure').catch(() => {});
} finally {
  await browser.close();
}
if (failed) {
  log(`FAIL: ${failed.message}`);
  process.exit(1);
}
log('PASS');
