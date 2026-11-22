#!/usr/bin/env node
// Round AI: renders every option (Today, AI1-AI5) the ways an icon is judged and measures it.
//   node docs/design/app-icon/ai/tools/render.mjs <out dir>
// writes <out>/img/<id>/*.png and <out>/measured.json. Same art modules and rasterizer as
// design/app-icon/build.mjs, so the previews are the shipped pixels.
import process from 'node:process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { roundedPolygon } from '../../../../../design/app-icon/geom.mjs';
import { Canvas, coverage, png } from '../../../../../design/app-icon/raster.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../../../../..');
const out = process.argv[2] ?? join(here, '../dist');
const tokens = JSON.parse(readFileSync(join(root, 'design/tokens/snacklist.tokens.json'), 'utf8'));
const resolve = (v) => (typeof v === 'string' && /^\{.+\}$/.test(v) ? resolve(v.slice(1, -1).split('.').reduce((n, k) => n[k], tokens).$value) : v);
const color = (mode, name) => resolve(tokens.color[mode][name].$value).hex.toLowerCase();

export const IDS = ['Today', 'AI1', 'AI2', 'AI3', 'AI4', 'AI5'];
const ART = 1024;
const C = 512;
// Sample tints: iOS 26 tinted (a warm tint on its dark base) and Android 13+ themed icons
// (a green Material You palette), as in job 52's previews.
const TINT = { ios: ['#1d160b', '#ffb84a'], androidLight: ['#d7e8cd', '#102000'], androidDark: ['#253420', '#bcecaa'] };
const WALL = { light: '#e9edf4', dark: '#0d0f16' };

function superellipse(n) {
  return [Array.from({ length: 512 }, (_, i) => {
    const t = (i / 512) * 2 * Math.PI;
    const c = Math.cos(t);
    const s = Math.sin(t);
    return [C + C * Math.sign(c) * Math.abs(c) ** (2 / n), C + C * Math.sign(s) * Math.abs(s) ** (2 / n)];
  })];
}
const MASKS = {
  apple: superellipse(5),
  squircle: superellipse(4),
  circle: [Array.from({ length: 256 }, (_, i) => [C + C * Math.cos((i * Math.PI) / 128), C + C * Math.sin((i * Math.PI) / 128)])],
  play: roundedPolygon([[0, 0], [ART, 0], [ART, ART], [0, ART]], 0.2 * ART).rings,
};
const FULL = [[[-1e4, -1e4], [1e4, -1e4], [1e4, 1e4], [-1e4, 1e4]]];
const rule = (e) => (e.evenOdd ? 'evenodd' : 'nonzero');

function draw(size, layers, { mask, place = [size / ART, 0, 0] } = {}) {
  const canvas = new Canvas(size, size);
  for (const [rings, col, r = 'nonzero', opacity = 1] of layers) canvas.paint(coverage(size, size, rings, place, r), col, opacity);
  if (mask) canvas.clip(coverage(size, size, MASKS[mask], place));
  return canvas;
}
const iconLayers = (art, mode) => [[FULL, art.colors[mode].bg], ...art.groups.flatMap((g) => g.els).map((e) => [e.shape.rings, art.colors[mode][e.role], rule(e)])];
const monoLayers = (art, bg, glyph, glyphOpacity = 1) => [...(bg ? [[FULL, bg]] : []), [art.mono.rings, glyph, art.monoEvenOdd ? 'evenodd' : 'nonzero', glyphOpacity]];
const save = (file, canvas) => { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, png(canvas.width, canvas.height, canvas.bytes())); };

// Per pixel, the share each fill has after painting (bg first, then the elements in order).
function fractions(art, size) {
  const els = art.groups.flatMap((g) => g.els);
  const roles = ['bg', ...els.map((e) => e.role)];
  const f = roles.map(() => new Float32Array(size * size));
  f[0].fill(1);
  els.forEach((e, k) => {
    const cov = coverage(size, size, e.shape.rings, [size / ART, 0, 0], rule(e));
    for (let i = 0; i < cov.length; i++) {
      const a = Math.min(1, cov[i]);
      if (!a) continue;
      for (let j = 0; j <= k; j++) f[j][i] *= 1 - a;
      f[k + 1][i] += a;
    }
  });
  return { roles, f };
}

const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const lum = (h) => {
  const [r, g, b] = rgb(h).map((x) => x / 255).map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
export const contrast = (a, b) => {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

// The lowest contrast between two fills that touch, at 256 px.
function touchingContrast(art, mode) {
  const size = 256;
  const { roles, f } = fractions(art, size);
  const label = new Int8Array(size * size).fill(-1);
  for (let i = 0; i < size * size; i++) for (let j = 0; j < f.length; j++) if (f[j][i] >= 0.5) label[i] = j;
  const pairs = new Set();
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const a = label[y * size + x];
    for (const [dx, dy] of [[1, 0], [0, 1], [2, 0], [0, 2]]) {
      if (x + dx >= size || y + dy >= size) continue;
      const b = label[(y + dy) * size + x + dx];
      if (a >= 0 && b >= 0 && roles[a] !== roles[b]) pairs.add([roles[a], roles[b]].sort().join('|'));
    }
  }
  let worst = { ratio: Infinity, pair: '' };
  for (const p of pairs) {
    const [a, b] = p.split('|');
    // Two parts in one colour read as one shape: no edge between them.
    if (art.colors[mode][a] === art.colors[mode][b]) continue;
    const ratio = contrast(art.colors[mode][a], art.colors[mode][b]);
    if (ratio < worst.ratio) worst = { ratio, pair: `${a}/${b}` };
  }
  return worst;
}

// Squared distance to the nearest pixel outside, Felzenszwalb and Huttenlocher's two passes.
function edt(inside, n) {
  const INF = 1e12;
  const g = new Float64Array(n * n);
  const line = (f, get, set) => {
    const v = new Int32Array(n);
    const z = new Float64Array(n + 1);
    let k = 0;
    v[0] = 0; z[0] = -INF; z[1] = INF;
    for (let q = 1; q < n; q++) {
      let s;
      for (;;) {
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        if (s <= z[k]) k--; else break;
      }
      k++; v[k] = q; z[k] = s; z[k + 1] = INF;
    }
    k = 0;
    for (let q = 0; q < n; q++) {
      while (z[k + 1] < q) k++;
      set(q, (q - v[k]) ** 2 + f[v[k]]);
    }
    void get;
  };
  const f = new Float64Array(n);
  for (let x = 0; x < n; x++) {
    for (let y = 0; y < n; y++) f[y] = inside[y * n + x] ? INF : 0;
    line(f, null, (q, val) => { g[q * n + x] = val; });
  }
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) f[x] = g[y * n + x];
    line(f, null, (q, val) => { g[y * n + q] = val; });
  }
  return g;
}

// The thinnest part of any one fill (a stroke, a ring, or the gap a fill leaves between two
// others), in art units. Local thickness: each pixel gets the diameter of the largest disc that
// fits in its fill and covers it. The value reported is the thickness that at least SLIVER pixels
// of a fill reach, so a single anti-aliased corner pixel does not count as a feature.
const N = 384;
const SLIVER = 120;
function thinnest(art) {
  const { roles, f } = fractions(art, N);
  let worst = { w: Infinity, role: '' };
  for (const role of new Set(roles)) {
    const inside = new Uint8Array(N * N);
    roles.forEach((r, j) => { if (r === role) for (let i = 0; i < N * N; i++) if (f[j][i] >= 0.5) inside[i] = 1; });
    const d2 = edt(inside, N);
    const thick = new Float32Array(N * N);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const i = y * N + x;
      if (!inside[i]) continue;
      const d = Math.sqrt(d2[i]);
      let ridge = true;
      for (let dy = -1; dy <= 1 && ridge; dy++) for (let dx = -1; dx <= 1; dx++) {
        const xx = x + dx; const yy = y + dy;
        if (xx >= 0 && yy >= 0 && xx < N && yy < N && d2[yy * N + xx] > d2[i]) { ridge = false; break; }
      }
      if (!ridge) continue;
      const r = Math.floor(d);
      for (let oy = -r; oy <= r; oy++) for (let ox = -r; ox <= r; ox++) {
        if (ox * ox + oy * oy > d * d) continue;
        const xx = x + ox; const yy = y + oy;
        if (xx < 0 || yy < 0 || xx >= N || yy >= N) continue;
        const j = yy * N + xx;
        if (thick[j] < 2 * d) thick[j] = 2 * d;
      }
    }
    const vals = [];
    for (let i = 0; i < N * N; i++) if (inside[i] && thick[i] > 0) vals.push(thick[i]);
    if (vals.length < SLIVER) continue;
    vals.sort((a, b) => a - b);
    const w = (vals[SLIVER - 1] * ART) / N;
    if (w < worst.w) worst = { w, role };
  }
  return worst;
}

const DP = ART / 72;
function safeZone(art) {
  const far = Math.max(...art.groups.flatMap((g) => g.els).flatMap((e) => e.shape.rings.flat()).map(([x, y]) => Math.hypot(x - C, y - C)));
  return { reachDp: far / DP, inside: far / DP <= 33 };
}

async function load(id) {
  const file = join(root, 'design/app-icon/art', `${id === 'Today' ? 'today' : id.toLowerCase()}.mjs`);
  return (await import(pathToFileURL(file).href)).default({ color });
}

const measured = {};
for (const id of IDS) {
  const art = await load(id);
  const dir = join(out, 'img', id);
  for (const mode of ['light', 'dark']) save(join(dir, `ios-${mode}.png`), draw(240, iconLayers(art, mode), { mask: 'apple' }));
  save(join(dir, 'ios-tinted.png'), draw(240, monoLayers(art, TINT.ios[0], TINT.ios[1]), { mask: 'apple' }));
  // iOS 26 clear: a frosted pane with the glyph in white; the page blurs the wallpaper behind it.
  save(join(dir, 'ios-clear.png'), draw(240, [[FULL, '#ffffff', 'nonzero', 0.22], ...monoLayers(art, null, '#ffffff', 0.9)], { mask: 'apple' }));
  for (const mask of ['circle', 'squircle']) save(join(dir, `android-${mask}.png`), draw(240, iconLayers(art, 'light'), { mask }));
  save(join(dir, 'android-themed-light.png'), draw(240, monoLayers(art, ...TINT.androidLight), { mask: 'circle' }));
  save(join(dir, 'android-themed-dark.png'), draw(240, monoLayers(art, ...TINT.androidDark), { mask: 'circle' }));
  // Android's adaptive canvas (108 dp) with the 66 dp safe circle and the 72 dp visible square.
  save(join(dir, 'android-canvas.png'), draw(324, iconLayers(art, 'light'), { place: [324 / (ART * 1.5), 54, 54] }));
  // Small sizes at their real pixels; the page scales them up with pixelated rendering.
  for (const mode of ['light', 'dark']) {
    save(join(dir, `settings-29-${mode}.png`), draw(29, iconLayers(art, mode), { mask: 'apple' }));
    save(join(dir, `settings-87-${mode}.png`), draw(87, iconLayers(art, mode), { mask: 'apple' }));
    save(join(dir, `launcher-48-${mode}.png`), draw(48, iconLayers(art, mode), { mask: 'circle' }));
  }
  for (const size of [24, 48]) save(join(dir, `notification-${size}.png`), draw(size, monoLayers(art, null, '#ffffff')));
  save(join(dir, 'store-app.png'), draw(256, iconLayers(art, 'light'), { mask: 'apple' }));
  save(join(dir, 'store-play.png'), draw(256, iconLayers(art, 'light'), { mask: 'play' }));
  const thin = thinnest(art);
  // Tinted and themed icons draw only the one-colour glyph: its thinnest part, glyph or gap.
  const monoThin = thinnest({ groups: [{ els: [{ shape: art.mono, role: 'glyph', evenOdd: art.monoEvenOdd }] }] });
  measured[id] = {
    thinnest: thin.role,
    thinnestArt: thin.w,
    thinnest29: (thin.w * 29) / ART,
    thinnest48: (thin.w * 48) / ART,
    contrastLight: touchingContrast(art, 'light'),
    contrastDark: touchingContrast(art, 'dark'),
    tileOnWall: { light: contrast(art.colors.light.bg, WALL.light), dark: contrast(art.colors.dark.bg, WALL.dark) },
    keyLight: contrast(art.colors.light[art.key[0]], art.colors.light[art.key[1]]),
    keyDark: contrast(art.colors.dark[art.key[0]], art.colors.dark[art.key[1]]),
    monoThinnest29: (monoThin.w * 29) / ART,
    tinted: { ios: contrast(...TINT.ios), androidLight: contrast(...TINT.androidLight), androidDark: contrast(...TINT.androidDark) },
    ...safeZone(art),
    bg: art.colors.light.bg,
  };
}
writeFileSync(join(out, 'measured.json'), `${JSON.stringify(measured, null, 2)}\n`);
console.log(Object.entries(measured).map(([id, m]) => `${id}: thinnest ${m.thinnest} ${m.thinnestArt.toFixed(0)} = ${m.thinnest29.toFixed(1)} px @29 (mono ${m.monoThinnest29.toFixed(1)}), key ${m.keyLight.toFixed(2)}/${m.keyDark.toFixed(2)}, weakest edge ${m.contrastLight.ratio.toFixed(2)} (${m.contrastLight.pair}) / ${m.contrastDark.ratio.toFixed(2)} (${m.contrastDark.pair}), tile/wall ${m.tileOnWall.light.toFixed(2)}/${m.tileOnWall.dark.toFixed(2)}, reach ${m.reachDp.toFixed(1)} dp`).join('\n'));
