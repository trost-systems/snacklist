// The drawing parts of the frames (job 214's kit, FR2 Großschrift plus FR1's Wabenband in cobalt):
// the page shell with the site's self-hosted fonts and tokens, crops of a capture cut only between
// rows, the band, hexagons and the stickers. Pure functions of their inputs: compose.mjs renders
// what they return.
import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { repo } from '../../.claude/skills/verify-snacklist/helpers/lib.mjs';

export const url = (path) => pathToFileURL(path).href;
const site = (path) => url(join(repo, 'site/public', path));

export const C = {
  cobalt: '#1b3fae',
  cobaltField: '#2448c0',
  honey: '#ffe24a',
  mint: '#7fe3b8',
  ink: '#0f1530',
  surface: '#f7f7f2',
  white: '#ffffff',
};

// The app's own icon font (Material Icons, as Flutter ships it): mic and check, never redrawn.
const flutterBin = dirname(realpathSync(execFileSync('bash', ['-c', 'command -v flutter'], { encoding: 'utf8' }).trim()));
const ICON_FONT = join(flutterBin, 'cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
// Flutter's own codepoints (Icons.mic, Icons.check), the glyphs the app shows.
const ICONS = { mic: 'e3e1', check: 'e156' };
export const icon = (name) => `<i class="mi">&#x${ICONS[name]};</i>`;

export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function page({ w, h, lang, css, body }) {
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<link rel="stylesheet" href="${site('tokens.css')}">
<style>
@font-face{font-family:"Bricolage Grotesque";src:url("${site('fonts/bricolage-grotesque-latin-standard-normal.woff2')}") format("woff2");font-weight:200 800}
@font-face{font-family:Inter;src:url("${site('fonts/inter-latin-wght-normal.woff2')}") format("woff2");font-weight:100 900}
@font-face{font-family:"Material Icons";src:url("${url(ICON_FONT)}") format("opentype")}
*{box-sizing:border-box;margin:0}
html,body{width:${w}px;height:${h}px;overflow:hidden;color-scheme:light}
body{position:relative;font-family:Inter,sans-serif;color:${C.ink};-webkit-font-smoothing:antialiased;background:${C.honey}}
.abs{position:absolute}
.display{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;letter-spacing:-0.035em;line-height:0.98}
.display>div{white-space:nowrap;width:max-content}
.sub{font-weight:600;line-height:1.28;text-wrap:balance}
.crop{position:relative;overflow:hidden;background:${C.surface}}
.crop>img{position:absolute;left:0;display:block}
.mi{font-family:"Material Icons";font-style:normal;font-weight:400;line-height:1;display:inline-block}
${css}
</style></head><body>${body}</body></html>`;
}

/** A window onto a capture: rows top..bottom and columns x, in capture pixels, drawn `scale` times. */
export function crop({ src, width, top, bottom, x = [0, width], scale, cls = '' }) {
  const w = Math.round((x[1] - x[0]) * scale);
  const h = Math.round((bottom - top) * scale);
  const html = `<div class="crop ${cls}" style="width:${w}px;height:${h}px"><img src="${src}" style="top:${-Math.round(top * scale)}px;left:${-Math.round(x[0] * scale)}px;width:${Math.round(width * scale)}px"></div>`;
  return { html, w, h };
}

// Where a capture can be cut without slicing anything: inside every run of at least `min` pixel
// rows of one background colour (surface, sheet, scrim) across the full width, so between rows
// and sections and never inside a honey or mint row. A window's top cut keeps up to `pad` rows of
// that background above the content below it, its bottom cut up to `pad` below the content above,
// so no row's words touch the card's border. Lines from `chrome` down (the floating add bar and
// tab bar, or the end of what the shot is about) don't count.
const BACKGROUNDS = new Set(['f7f7f2', 'ffffff', '949491']);

/** A capture's size and a function giving a row's one colour in columns x0..x1, or null. */
function rows(file) {
  const [w, h] = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim().split(',').map(Number);
  const px = execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], { maxBuffer: w * h * 3 + 1024 });
  const colourOf = (y, x0 = 0, x1 = w) => {
    const row = px.subarray((y * w + x0) * 3, (y * w + x1) * 3);
    for (let i = 3; i < row.length; i += 3) if (row[i] !== row[0] || row[i + 1] !== row[1] || row[i + 2] !== row[2]) return null;
    return [...row.subarray(0, 3)].map((n) => n.toString(16).padStart(2, '0')).join('');
  };
  const inkColumns = (y0, y1, x0, x1) => {
    let [left, right] = [x1, x0];
    for (let y = y0; y < y1; y++) {
      const bg = px.subarray((y0 - 1) * w * 3 + x0 * 3, (y0 - 1) * w * 3 + x0 * 3 + 3);
      for (let x = x0; x < x1; x++) {
        const i = (y * w + x) * 3;
        if (px[i] !== bg[0] || px[i + 1] !== bg[1] || px[i + 2] !== bg[2]) [left, right] = [Math.min(left, x), Math.max(right, x + 1)];
      }
    }
    return [left, right];
  };
  return { w, h, colourOf, inkColumns };
}

/**
 * The lines of text in columns x from row `from` on: each [top, bottom) of rows with ink, `ink`
 * the columns [left, right) they cover, and `gap`, the plain rows after it (up to `to`).
 */
export function textLines(file, [x0, x1], from, to) {
  const { colourOf, inkColumns } = rows(file);
  const lines = [];
  for (let y = from; y < to; ) {
    if (colourOf(y, x0, x1)) {
      y++;
      continue;
    }
    const top = y;
    while (y < to && !colourOf(y, x0, x1)) y++;
    const bottom = y;
    while (y < to && colourOf(y, x0, x1)) y++;
    lines.push({ top, bottom, gap: y - bottom, ink: inkColumns(top, bottom, x0, x1) });
  }
  return lines;
}

export function cuts(file, chrome, min = 16, pad = 64) {
  const { w, h, colourOf } = rows(file);
  const tops = [0];
  const bottoms = [];
  for (let y = 0; y < h; ) {
    const colour = colourOf(y);
    let end = y;
    while (colour && end + 1 < h && colourOf(end + 1) === colour) end++;
    if (end - y + 1 >= min && BACKGROUNDS.has(colour) && y < chrome) {
      tops.push(Math.min(Math.max(y, end + 1 - pad), chrome));
      bottoms.push(Math.min(end + 1, y + pad, chrome));
    }
    y = end + 1;
  }
  if (chrome >= h) bottoms.push(h);
  return { width: w, height: h, tops, bottoms };
}

/**
 * The window of whole rows, at most `span` capture pixels, that holds the band `keep`, starts no
 * higher than `floor`, and starts at the first cut it may (the capture's top: the household's
 * name and the strip stay in frame) when it can; else, of the windows within 10 % of the
 * tallest, the one that centres the band best.
 */
export function windowFor(file, chrome, span, keep, floor = 0) {
  const { bottoms, ...all } = cuts(file, chrome);
  const tops = all.tops.filter((t) => t >= floor);
  // A semantics box may overhang its painted row by a few pixels; cuts lie in plain background.
  const [from, to] = [keep[0] + 12, keep[1] - 12];
  const fits = tops.flatMap((top) => bottoms.filter((bottom) => top <= from && bottom >= to && bottom - top <= span).map((bottom) => ({ top, bottom })));
  if (!fits.length) throw new Error(`${file}: no clean window of ${span} px around ${keep}`);
  const tallest = Math.max(...fits.map((w) => w.bottom - w.top));
  const fromTop = fits.filter((w) => w.top === tops[0] && w.bottom - w.top >= 0.9 * tallest);
  if (fromTop.length) return fromTop.sort((a, b) => b.bottom - a.bottom)[0];
  const off = (w) => Math.abs((w.top + w.bottom) / 2 - (keep[0] + keep[1]) / 2);
  return fits.filter((w) => w.bottom - w.top >= 0.9 * tallest).sort((a, b) => off(a) - off(b))[0];
}

/** The colour of one capture pixel as hex. */
export function pixelAt(file, x, y) {
  const px = execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-vf', `crop=1:1:${x}:${y}`, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']);
  return [...px.subarray(0, 3)].map((n) => n.toString(16).padStart(2, '0')).join('');
}

/** The first clean cut below `y` (the end of a crop that must show everything above it). */
export const cutBelow = (file, chrome, y) => cuts(file, chrome).bottoms.find((c) => c > y);

// Pointy-top hexagon around (cx, cy) with circumradius r, corners rounded by `round`.
export function hexPath(cx, cy, r, round = 0) {
  const pts = [...Array(6)].map((_, i) => {
    const a = (Math.PI / 180) * (60 * i - 90);
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  });
  const k = round / r;
  let d = '';
  pts.forEach((p, i) => {
    const prev = pts[(i + 5) % 6];
    const next = pts[(i + 1) % 6];
    const a = [p[0] + (prev[0] - p[0]) * k, p[1] + (prev[1] - p[1]) * k];
    const b = [p[0] + (next[0] - p[0]) * k, p[1] + (next[1] - p[1]) * k];
    d += `${i ? 'L' : 'M'}${a[0].toFixed(1)} ${a[1].toFixed(1)} Q${p[0].toFixed(1)} ${p[1].toFixed(1)} ${b[0].toFixed(1)} ${b[1].toFixed(1)} `;
  });
  return `${d}Z`;
}

/**
 * The Wabenband: a cobalt ribbon with an ink contour and a honeycomb inside, drawn in the
 * coordinates of the whole strip of a set (all its shots side by side) and shown through the
 * window [x0, x0 + w]. Neighbouring shots therefore meet in one continuous band. `y(x)` is the
 * centre line in strip coordinates, `width` the ribbon's width.
 */
export function band({ x0, w, h, y, width, contour, cell }) {
  const pts = [];
  for (let x = x0 - 2 * width; x <= x0 + w + 2 * width; x += 8) pts.push(`${(x - x0).toFixed(1)} ${y(x).toFixed(1)}`);
  const d = `M${pts.join(' L')}`;
  // The comb's grid is fixed to the strip, not to the shot, so it runs on across the seam too.
  const dx = Math.sqrt(3) * cell;
  let comb = '';
  const first = Math.floor((x0 - 2 * dx) / dx);
  for (let row = -1; row * cell * 1.5 < h + cell; row++) {
    for (let col = first; col * dx < x0 + w + 2 * dx; col++) {
      const cx = col * dx + (row % 2 ? dx / 2 : 0);
      const cy = row * cell * 1.5;
      if (Math.abs(cy - y(cx)) < width) comb += hexPath(cx - x0, cy, cell - contour, cell * 0.14);
    }
  }
  return `<svg class="abs" style="left:0;top:0" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
<defs><mask id="ribbon" maskUnits="userSpaceOnUse" x="0" y="0" width="${w}" height="${h}"><path d="${d}" fill="none" stroke="#fff" stroke-width="${width}" stroke-linejoin="round"/></mask></defs>
<path d="${d}" fill="none" stroke="${C.ink}" stroke-width="${width + 2 * contour}" stroke-linejoin="round"/>
<path d="${d}" fill="none" stroke="${C.cobalt}" stroke-width="${width}" stroke-linejoin="round"/>
<path d="${comb}" fill="none" stroke="${C.cobaltField}" stroke-width="${contour * 0.9}" mask="url(#ribbon)"/></svg>`;
}

/** A member's hexagon avatar with the initial. */
export function avatar(initial, fill, size) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100" style="display:block;overflow:visible;flex:none"><path d="${hexPath(50, 50, 48, 10)}" fill="${fill}" stroke="${C.ink}" stroke-width="6"/><text x="50" y="53" text-anchor="middle" dominant-baseline="central" font-family="Bricolage Grotesque" font-weight="800" font-size="50" fill="${C.ink}">${esc(initial)}</text></svg>`;
}

/** A hexagon chip around an icon, in the app's style (honey, mint or cobalt). */
export function hexIcon(name, { fill, color = C.ink, size }) {
  return `<span class="hexicon" style="width:${size}px;height:${size}px"><svg width="${size}" height="${size}" viewBox="0 0 100 100"><path d="${hexPath(50, 50, 47, 9)}" fill="${fill}" stroke="${C.ink}" stroke-width="6"/></svg><b style="color:${color};font-size:${Math.round(size * 0.56)}px">${icon(name)}</b></span>`;
}
