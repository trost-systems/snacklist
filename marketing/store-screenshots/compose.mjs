#!/usr/bin/env node
// Frames the raw captures (capture.mjs) into the store files and checks them:
//
//   node compose.mjs --locales de-DE,en-US --stores play,appstore [--assistants neutral|named|named_siri]
//                    [--premium-label]
//
// out/<locale>/<set>/<n>-<shot>.png      FR2 Großschrift: headline, subline, the app as a card on
//                                        the canvas foot, the cobalt Wabenband behind (sets.mjs)
// out/<locale>/play/feature-graphic.png  1024 x 500, tagline only
// out/<locale>/play/icon-512.png         app/web/icons/Icon-512.png on the icon's cobalt, no alpha
// out/<locale>/contact-sheet.png         every file of the locale on one sheet
// out/manifest.json, out/summary.md      size, pixel format, bytes, sha256, text share, caption
//                                        status and variant per file
//
// Each frame is an HTML page rendered by Chromium at its exact size, flattened by ffmpeg to 24-bit
// RGB. A file that breaks a check fails the run (docs/STORE_SCREENSHOTS.md, "Checks").
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import process from 'node:process';
import { chromium, labels, repo } from '../../.claude/skills/verify-snacklist/helpers/lib.mjs';
import { AI_BRANDS, captionProblems, captionsFor } from './captions.mjs';
import { C, avatar, band, crop, cutBelow, esc, hexIcon, page, pixelAt, textLines, url, windowFor } from './kit.mjs';
import { FEATURE_GRAPHIC, ICON, LOCALES, SETS, layout, plan, sizeProblems } from './sets.mjs';

const OUT = process.env.STORE_SHOTS_OUT ?? join(import.meta.dirname, 'out');
const WORK = join(OUT, 'work');
const arg = (name, fallback) => (process.argv.includes(`--${name}`) ? process.argv[process.argv.indexOf(`--${name}`) + 1] : fallback);
const locales = arg('locales', Object.keys(LOCALES).join(',')).split(',');
const stores = arg('stores', 'play,appstore').split(',');
const assistants = arg('assistants', 'neutral');
// „Mit Snacklist Premium“ on the api shot: only once MCP and the API are paid (Apple 2.3.2).
const premiumLabel = process.argv.includes('--premium-label');
// While working on a frame: only these sets or shots (the feature graphic and sheet still come).
const sets = arg('sets', Object.keys(SETS).join(',')).split(',');
const only = arg('shots', '').split(',').filter(Boolean);
const TEXT_MAX = 0.2;
// The app's tint for rows a partner just added (light theme).
const HONEY_ROW = 'fff2a8';
const BYTES_MAX = 8_000_000;

const setup = [...captionProblems(), ...Object.keys(SETS).flatMap(sizeProblems)];
if (setup.length) {
  console.error(`captions.yaml or sets.mjs break a rule:\n${setup.join('\n')}`);
  process.exit(1);
}

// Jonas speaks and asks; his colour is the app's mint, Anna's the honey.
const QUOTES = { de: ['„', '“'], en: ['“', '”'] };

/** The band's centre line for a set, in strip pixels: high behind even shots, low behind odd. */
function bandLine({ W, H, u, cardTop }, text) {
  const peak = cardTop + (text ? 14 : -10) * u;
  const trough = H - 330 * u;
  return (x) => (peak + trough) / 2 - ((trough - peak) / 2) * Math.sin((Math.PI * x) / W);
}

/**
 * A sticker on the card's top edge, `overlap` px over the card (never over the rows the caption
 * points at); inspect() fails a sticker that touches the headline block.
 */
function placeSticker({ html, w, left, tilt, overlap }, { H, cardTop, liftTop, u }) {
  const bottom = Math.min(cardTop + overlap, liftTop - 28 * u);
  return `<div class="abs sticker-box" style="left:${left}px;bottom:${Math.round(H - bottom)}px;width:${w}px;transform:rotate(${tilt}deg)">${html}</div>`;
}

/**
 * The stickers of the shots that have one, on sets with text: what each draws, its height in u,
 * and how much card height it takes from the top (`reserve`, in u) so that it fits between the
 * subline and the card, over the card's top edge only, and the card's header and strip stay readable. Each returns its html, width, place and tilt; placeSticker() stands it on the card's top edge.
 */
const STICKERS = {
  // Jonas's confirmation, cut out of his own phone.
  sync: { reserve: 60, draw: ({ g, meta, rawDir }) => {
    const s = meta.sender;
    const { viewport, dpr } = SETS[g.set];
    const sender = crop({ src: url(join(rawDir, s.file)), width: viewport[0] * dpr, top: s.y[0], bottom: s.y[1], x: s.x, scale: g.scale * 0.96, cls: 'sat' });
    return { html: sender.html, w: sender.w, left: Math.round(g.gutter * 0.45), tilt: -2, overlap: Math.round(6 * g.u) };
  } },
  // Jonas's sentence: his avatar and a speech bubble with the app's mic.
  voice: { reserve: 0, draw: ({ g, c, lang }) => {
    const { u, W } = g;
    const [open, close] = QUOTES[lang];
    const html = `<div class="say" style="gap:${Math.round(18 * u)}px">${avatar('J', C.mint, Math.round(92 * u))}<p class="bubble">${hexIcon('mic', { fill: C.honey, size: Math.round(62 * u) })}<span>${esc(open + c.sticker.said + close)}</span></p></div>`;
    return { html, w: W - 2 * Math.round(g.gutter * 0.5), left: Math.round(g.gutter * 0.5), tilt: -1.5, overlap: Math.round(6 * u) };
  } },
  // The MCP-Server heading and address, cut out of the same screen above the app's hint.
  api: { reserve: 150, draw: ({ g, meta, rawDir }) => {
    const s = mcpSticker(join(rawDir, meta.raw), meta);
    const { viewport, dpr } = SETS[g.set];
    const cut = crop({ src: url(join(rawDir, meta.raw)), width: viewport[0] * dpr, top: s.y[0], bottom: s.y[1], x: s.x, scale: g.scale * 1.12 });
    // The cut ends close under the address (the hint follows): the sticker's own padding, in the
    // screen's surface colour, gives the words their margin.
    const pad = Math.round(22 * g.u);
    const html = `<div class="sat" style="background:${C.surface};padding:${pad}px ${Math.round(pad * 1.3)}px">${cut.html}</div>`;
    return { html, w: cut.w + 2 * Math.round(pad * 1.3), left: Math.round(g.gutter * 0.45), tilt: -2, overlap: Math.round(6 * g.u) };
  } },
  // A generic chat in Snacklist's own style: the request, the reply with the items it added.
  assist: { reserve: 120, draw: ({ g, c }) => {
    const { u, W } = g;
    const chips = c.sticker.items.map((i) => `<li>${hexIcon('check', { fill: C.mint, size: Math.round(42 * u) })}<span>${esc(i)}</span></li>`).join('');
    const html = `<div class="chat"><p class="me">${esc(c.sticker.ask)}</p><div class="reply"><p>${esc(c.sticker.reply)}</p><ul>${chips}</ul></div></div>`;
    return { html, w: Math.round(W - g.gutter), left: Math.round(g.gutter * 0.5), tilt: 0, overlap: Math.round(6 * u) };
  } },
};

/**
 * The api sticker's rows: from the MCP-Server heading to the end of the address, the second line
 * of text in the tile, cut halfway into the gap before the hint below it.
 */
function mcpSticker(file, meta) {
  const { y, x } = meta.sticker;
  const [heading, address] = textLines(file, x, y[0], y[1]);
  if (!address) throw new Error(`${file}: no address line under the MCP-Server heading`);
  // Across to the address's end; the heading's rule to its right is cut there.
  return { x: [Math.min(heading.ink[0], address.ink[0]), address.ink[1]], y: [heading.top, address.bottom + Math.floor(address.gap / 2)] };
}

/**
 * What the api frame's screen says inside the card's window and on the sticker, from the
 * screen reader's texts (the sticker keeps only each text's first line, the address): no AI
 * brand, no local host, nothing like a key; the production API URL and MCP address, and no key
 * made („Kein aktiver API-Schlüssel.“).
 */
function screenProblems(m, win, lang, file) {
  const inside = ([a, b]) => m.texts.filter((t) => Math.min(t.y[1], b) - Math.max(t.y[0], a) > 4).map((t) => t.text);
  const sticker = mcpSticker(file, m);
  const card = inside([win.top, win.bottom]);
  const cut = inside(sticker.y).map((t) => t.split('\n')[0]);
  const problems = [];
  for (const [where, texts] of [['card', card], ['sticker', cut]]) {
    for (const t of texts) {
      if (AI_BRANDS.test(t)) problems.push(`the ${where} shows an AI brand: "${t}"`);
      if (/127\.0\.0\.1|localhost/i.test(t)) problems.push(`the ${where} shows a local host: "${t}"`);
      if (/[A-Za-z0-9_-]{28,}/.test(t.replace(/\S+:\/\/\S+/g, ''))) problems.push(`the ${where} shows something like a key: "${t}"`);
    }
  }
  if (!card.some((t) => t.includes(m.shown.api))) problems.push(`the card does not show the API URL ${m.shown.api}`);
  if (!card.includes(labels(lang)('noApiKeys'))) problems.push('the card does not show that no API key exists');
  if (!cut.includes(m.shown.mcp)) problems.push(`the sticker does not show the MCP address ${m.shown.mcp}`);
  return problems;
}

function frameHtml({ locale, set, index, shot, meta, words, rawDir, room = 0 }) {
  const s = SETS[set];
  const { lang } = LOCALES[locale];
  const g = { ...layout(set), set };
  const { W, H, u, gutter } = g;
  const m = meta[shot];
  const file = join(rawDir, m.raw);
  const sticker = s.text ? STICKERS[shot] : undefined;
  const win = windowFor(file, s.text ? m.chrome : Infinity, g.span - Math.round((((sticker?.reserve ?? 0) + room) * u) / g.scale), m.lift.y, m.floor);
  const card = crop({ src: url(file), width: s.viewport[0] * s.dpr, top: win.top, bottom: win.bottom, scale: g.scale, cls: 'card' });
  const cardTop = H - card.h;
  const liftTop = cardTop + (m.lift.y[0] - win.top) * g.scale;
  const c = words[shot];
  const label = premiumLabel && c.premium ? `<p class="premium">${esc(c.premium)}</p>` : '';
  const head = s.text
    ? `<div class="abs head"><div class="display">${c.h.map((l) => `<div>${esc(l)}</div>`).join('')}</div><p class="sub">${esc(c.s)}</p>${label}</div>`
    : '';
  const extra = sticker ? placeSticker(sticker.draw({ g, c: words[shot], lang, meta: m, rawDir }), { H, cardTop, liftTop, u }) : '';
  const css = `
.head{left:${gutter}px;right:${gutter}px;top:${Math.round(96 * u)}px;display:flex;flex-direction:column;gap:${Math.round(26 * u)}px}
.head .display{font-size:${Math.round(132 * u)}px}
.head .sub{font-size:${Math.round(40 * u)}px;max-width:${Math.round(900 * u)}px}
.head .premium{align-self:flex-start;font-size:${Math.round(32 * u)}px;font-weight:700;line-height:1.2;background:${C.white};border:${Math.round(4 * u)}px solid ${C.ink};border-radius:${Math.round(999 * u)}px;padding:${Math.round(10 * u)}px ${Math.round(26 * u)}px;box-shadow:0 ${Math.round(8 * u)}px 0 0 ${C.ink}}
.card{border:${Math.round(5 * u)}px solid ${C.ink};border-bottom:0;border-radius:${Math.round(44 * u)}px ${Math.round(44 * u)}px 0 0;box-shadow:${Math.round(16 * u)}px ${Math.round(16 * u)}px 0 0 ${C.ink}}
.sat{border:${Math.round(4 * u)}px solid ${C.ink};border-radius:${Math.round(26 * u)}px;box-shadow:0 ${Math.round(12 * u)}px 0 0 ${C.ink}}
.say{display:flex;align-items:center}
.bubble{display:flex;align-items:center;gap:${Math.round(18 * u)}px;background:${C.white};border:${Math.round(4 * u)}px solid ${C.ink};border-radius:${Math.round(34 * u)}px;box-shadow:0 ${Math.round(12 * u)}px 0 0 ${C.ink};padding:${Math.round(16 * u)}px ${Math.round(30 * u)}px ${Math.round(16 * u)}px ${Math.round(18 * u)}px;font-size:${Math.round(40 * u)}px;font-weight:650;line-height:1.2}
.hexicon{position:relative;display:inline-grid;place-items:center;flex:none}
.hexicon svg{position:absolute;inset:0}
.hexicon b{position:relative;display:grid;place-items:center}
.chat{display:flex;flex-direction:column;align-items:flex-end;gap:${Math.round(18 * u)}px;font-size:${Math.round(34 * u)}px;line-height:1.25}
.chat .me{max-width:82%;background:${C.cobalt};color:${C.white};font-weight:600;border:${Math.round(4 * u)}px solid ${C.ink};border-radius:${Math.round(30 * u)}px ${Math.round(30 * u)}px ${Math.round(8 * u)}px ${Math.round(30 * u)}px;padding:${Math.round(18 * u)}px ${Math.round(26 * u)}px;box-shadow:0 ${Math.round(10 * u)}px 0 0 ${C.ink}}
.chat .reply{align-self:flex-start;background:${C.white};border:${Math.round(4 * u)}px solid ${C.ink};border-radius:${Math.round(8 * u)}px ${Math.round(30 * u)}px ${Math.round(30 * u)}px ${Math.round(30 * u)}px;padding:${Math.round(18 * u)}px ${Math.round(26 * u)}px;box-shadow:0 ${Math.round(10 * u)}px 0 0 ${C.ink}}
.chat .reply p{font-weight:700;margin-bottom:${Math.round(10 * u)}px}
.chat ul{list-style:none;padding:0;display:flex;gap:${Math.round(26 * u)}px}
.chat li{display:flex;align-items:center;gap:${Math.round(16 * u)}px;font-weight:600}`;
  const body = band({ x0: index * W, w: W, h: H, y: bandLine(g, s.text), width: Math.round(170 * u), contour: Math.round(7 * u), cell: Math.round(46 * u) })
    + head
    + `<div class="abs" style="left:${gutter}px;top:${cardTop}px">${card.html}</div>`
    + extra;
  return { html: page({ w: W, h: H, lang, css, body }), win };
}

function featureHtml(locale, words) {
  const [W, H] = FEATURE_GRAPHIC.size;
  const { lang } = LOCALES[locale];
  const rawDir = join(OUT, 'raw', locale, 'play-phone');
  const m = JSON.parse(readFileSync(join(rawDir, 'meta.json'), 'utf8')).list;
  const file = join(rawDir, m.raw);
  const width = SETS['play-phone'].viewport[0] * SETS['play-phone'].dpr;
  const bottom = cutBelow(file, m.chrome, m.lift.y[1]);
  // The whole width: a narrower crop would cut the first store's count (English puts the
  // strip beside the household's name). The card stays right of the centre zone (x 592).
  const scale = Math.min(0.5, (H - 44) / bottom, (W - 594) / width);
  const card = crop({ src: url(file), width, top: 0, bottom, scale, cls: 'card' });
  const css = `
.t{left:72px;width:350px;top:0;bottom:70px;display:flex;align-items:center}
.t .display{font-size:54px;white-space:normal;text-wrap:balance}
.t em{font-style:normal;color:${C.cobalt}}
.card{border:3px solid ${C.ink};border-right:0;border-bottom:0;border-radius:24px 0 0 0;box-shadow:-9px 9px 0 0 ${C.ink}}`;
  const tagline = esc(words.feature.tagline);
  const body = band({ x0: 0, w: W, h: H, y: (x) => 505 - 300 * Math.sin((Math.PI * x) / 2048), width: 62, contour: 4, cell: 17 })
    + `<div class="abs t"><div class="display tagline">${tagline}</div></div>`
    + `<div class="abs" style="left:${W - card.w}px;top:${H - card.h}px">${card.html}</div>`;
  return page({ w: W, h: H, lang, css, body });
}

/**
 * In the page: the share of the canvas covered by the frame's own text (the app's captures are
 * images and don't count; Play advises at most 20 %), and what is cut: a headline line wider than
 * its column, a subline over two lines, a sticker or text outside the canvas.
 */
function inspect() {
  const W = document.documentElement.clientWidth;
  const H = document.documentElement.clientHeight;
  const rects = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent.trim() || n.parentElement.closest('svg')) continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    rects.push(...range.getClientRects());
  }
  const area = rects.reduce((sum, r) => sum + Math.max(0, Math.min(r.right, W) - Math.max(r.left, 0)) * Math.max(0, Math.min(r.bottom, H) - Math.max(r.top, 0)), 0);
  const cut = [];
  const head = document.querySelector('.head');
  if (head) {
    const column = head.getBoundingClientRect();
    for (const line of head.querySelectorAll('.display>div')) if (line.getBoundingClientRect().right > column.right + 0.5) cut.push(`headline "${line.textContent}" is wider than its column`);
    const sub = head.querySelector('.sub');
    if (sub.getBoundingClientRect().height > 2.7 * parseFloat(getComputedStyle(sub).fontSize)) cut.push('subline runs over two lines');
  }
  const block = head?.getBoundingClientRect();
  for (const el of document.querySelectorAll('.sticker-box, .tagline')) {
    const r = el.getBoundingClientRect();
    if (block && el.classList.contains('sticker-box') && r.top < block.bottom + 8) cut.push('the sticker touches the headline block');
    if (r.left < 0 || r.top < 0 || r.right > W || r.bottom > H) cut.push(`${el.className} leaves the canvas`);
  }
  for (const r of rects) if (r.left < 0 || r.right > W || r.top < 0 || r.bottom > H) cut.push('text leaves the canvas');
  return { text: area / (W * H), cut: [...new Set(cut)], words: document.body.innerText };
}

const browser = await chromium.launch();
const tab = await (await browser.newContext({ deviceScaleFactor: 1, colorScheme: 'light' })).newPage();

/** Renders html at w x h into `file` as 24-bit RGB; returns what inspect() found. */
async function render(html, [w, h], file) {
  mkdirSync(WORK, { recursive: true });
  const src = join(WORK, 'page.html');
  writeFileSync(src, html);
  await tab.setViewportSize({ width: w, height: h });
  await tab.goto(url(src));
  await tab.evaluate(() => document.fonts.ready);
  await tab.evaluate(() => Promise.all([...document.images].map((i) => i.decode())));
  const found = await tab.evaluate(inspect);
  const shot = join(WORK, 'shot.png');
  await tab.screenshot({ path: shot });
  mkdirSync(join(file, '..'), { recursive: true });
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', shot, '-pix_fmt', 'rgb24', file]);
  return found;
}

const sha = (f) => createHash('sha256').update(readFileSync(f)).digest('hex');
const probe = (f) => JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height,pix_fmt', '-of', 'json', f], { encoding: 'utf8' })).streams[0];

const manifest = { assistants, premiumLabel, files: [] };
const failures = [];

/** Checks a written file and records it in the manifest. */
function record(file, { size, store, rule, text, cut = [], ...extra }) {
  const p = probe(file);
  const bytes = readFileSync(file).length;
  const name = relative(OUT, file);
  const problems = [...cut];
  if (p.width !== size[0] || p.height !== size[1]) problems.push(`${p.width}x${p.height}, want ${size.join('x')}`);
  if (p.pix_fmt !== 'rgb24') problems.push(`pixel format ${p.pix_fmt}, want rgb24 (no alpha)`);
  if (bytes > BYTES_MAX) problems.push(`${bytes} bytes, the stores take at most 8 MB`);
  if (rule) problems.push(...rule);
  if (store === 'play' && text > TEXT_MAX) problems.push(`text covers ${(text * 100).toFixed(1)} %, Play advises at most 20 %`);
  failures.push(...problems.map((x) => `${name}: ${x}`));
  manifest.files.push({ file: name, width: p.width, height: p.height, pixFmt: p.pix_fmt, bytes, sha256: sha(file), text: text === undefined ? undefined : Number((text * 100).toFixed(1)), ...extra });
}

try {
  for (const locale of locales) {
    const made = [];
    const byStore = Object.fromEntries(stores.map((store) => [store, captionsFor(locale, { assistants, store })]));
    for (const { set, shot, n } of plan({ locales: [locale], stores }).filter((p) => sets.includes(p.set) && (!only.length || only.includes(p.shot)))) {
      const s = SETS[set];
      const rawDir = join(OUT, 'raw', locale, set);
      if (!existsSync(join(rawDir, 'meta.json'))) throw new Error(`no captures in ${relative(OUT, rawDir)}: run capture.mjs first`);
      const meta = JSON.parse(readFileSync(join(rawDir, 'meta.json'), 'utf8'));
      if (!meta[shot]) throw new Error(`no capture of ${shot} in ${relative(OUT, rawDir)}`);
      const words = byStore[s.store];
      const file = join(OUT, locale, set, `${n}-${shot}.png`);
      // A subline on two lines pushes the sticker into the headline block: give the sticker
      // more room above the card, 50 u at a time.
      let found;
      let win;
      for (let room = 0; room <= 200; room += 50) {
        const frame = frameHtml({ locale, set, index: n - 1, shot, meta, words, rawDir, room });
        win = frame.win;
        found = await render(frame.html, s.size, file);
        if (!found.cut.includes('the sticker touches the headline block')) break;
      }
      if (meta[shot].texts) found.cut.push(...screenProblems(meta[shot], win, LOCALES[locale].lang, join(rawDir, meta[shot].raw)));
      // The frame's own words name Premium only as the api shot's label, and only when asked for.
      if (/premium/i.test(found.words) && !(premiumLabel && words[shot].premium)) found.cut.push('the frame names Premium');
      if (premiumLabel && words[shot].premium && s.text && !found.words.includes(words[shot].premium)) found.cut.push('the Premium label is missing');
      // The rows the caption is about must still be in honey when the frame was taken.
      const faded = (meta[shot].honey ?? []).filter((y) => pixelAt(join(rawDir, meta[shot].raw), meta[shot].lift.x[0] + 6, y) !== HONEY_ROW);
      if (faded.length) found.cut.push(`${faded.length} of the new rows are not in honey in the capture`);
      const c = words[shot];
      record(file, {
        size: s.size, store: s.store, text: found.text, cut: found.cut, locale, set, shot,
        status: c.status, variant: c.variant ?? undefined, alt: c.alt,
        caption: s.text ? [...c.h, c.s, ...(premiumLabel && c.premium ? [c.premium] : [])].join(' / ') : '(no text, spec D4-B)',
      });
      made.push(file);
    }
    if (stores.includes('play')) {
      const words = byStore.play;
      const fg = join(OUT, locale, 'play', 'feature-graphic.png');
      const found = await render(featureHtml(locale, words), FEATURE_GRAPHIC.size, fg);
      const centre = await tab.evaluate(() => ['.tagline', '.card'].some((sel) => {
        const t = document.querySelector(sel).getBoundingClientRect();
        return t.right > 432 && t.left < 592 && t.bottom > 170 && t.top < 330;
      }));
      record(fg, { size: FEATURE_GRAPHIC.size, store: 'play', text: found.text, cut: [...found.cut, ...(centre ? ['the tagline or the app enters the centre zone x 432-592, y 170-330'] : [])], locale, set: 'play-feature-graphic', status: words.feature.status, alt: words.feature.alt, caption: words.feature.tagline });
      const icon = join(OUT, locale, 'play', 'icon-512.png');
      execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', `color=c=${C.cobalt}:s=512x512`, '-i', join(repo, ICON.source),
        '-filter_complex', '[0][1]overlay=format=auto,format=rgb24', '-frames:v', '1', icon]);
      record(icon, { size: ICON.size, store: 'play', locale, set: 'play-icon' });
      made.push(fg, icon);
    }
    const sheet = join(OUT, locale, 'contact-sheet.png');
    await render(contactSheet(locale, made), [3200, 400], join(WORK, 'sheet-probe.png'));
    const height = await tab.evaluate(() => document.body.scrollHeight);
    await render(contactSheet(locale, made), [3200, height], sheet);
    console.log(`${locale}: ${made.length} files, contact sheet ${relative(repo, sheet)}`);
  }
} finally {
  await browser.close();
  rmSync(WORK, { recursive: true, force: true });
}

function contactSheet(locale, files) {
  const groups = Map.groupBy(files, (f) => relative(join(OUT, locale), join(f, '..')));
  const rows = [...groups].map(([set, list]) => `<section><h2>${esc(set)}</h2><div class="row">${list.map((f) => `<figure><img src="${url(f)}"><figcaption>${esc(relative(join(OUT, locale), f))}</figcaption></figure>`).join('')}</div></section>`).join('');
  const css = `body{background:#dfe3ec;padding:32px;height:auto;min-height:100%}html{height:auto}
h1{font:800 44px "Bricolage Grotesque";margin-bottom:24px}h2{font:700 28px Inter;margin:28px 0 12px}
.row{display:flex;flex-wrap:wrap;gap:20px;align-items:flex-end}figure{display:flex;flex-direction:column;gap:8px}
figure img{height:560px;display:block;box-shadow:0 0 0 2px ${C.ink}}figcaption{font:500 18px Inter}`;
  return page({ w: 3200, h: 400, lang: 'en', css: `${css}\nhtml,body{overflow:visible}`, body: `<h1>Snacklist store screenshots, ${esc(locale)} (assistants: ${esc(assistants)}${premiumLabel ? ', Premium label' : ''})</h1>${rows}` });
}

writeFileSync(join(OUT, 'manifest.json'), `${JSON.stringify(manifest, null, 1)}\n`);
const drafts = [...new Set(manifest.files.filter((f) => f.status === 'draft').map((f) => `${f.locale} ${f.shot ?? 'feature'}`))];
writeFileSync(join(OUT, 'summary.md'), `${[
  `Assistants variant: ${assistants}; Premium label: ${premiumLabel ? 'on' : 'off'}`, '',
  '| File | Size | Pixels | Text | Caption | Status |', '| --- | --- | --- | --- | --- | --- |',
  ...manifest.files.map((f) => `| \`${f.file}\` | ${f.width} x ${f.height} | ${f.pixFmt} | ${f.text ?? ''}${f.text === undefined ? '' : ' %'} | ${f.caption ?? ''}${f.variant ? ` (${f.variant})` : ''} | ${f.status ?? ''} |`),
  '', drafts.length ? `Draft captions: ${drafts.join(', ')}` : 'Every caption is approved.',
  '', failures.length ? `Checks FAILED:\n${failures.map((f) => `- ${f}`).join('\n')}` : 'All checks pass.',
].join('\n')}\n`);
if (failures.length) {
  console.error(`checks failed:\n${failures.join('\n')}`);
  process.exit(1);
}
console.log(`all checks pass (${manifest.files.length} files)`);
