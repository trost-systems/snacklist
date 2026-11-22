#!/usr/bin/env node
// Writes the Snacklist app icon and the splash screens for iOS, Android and the web, the
// Alexa skill's icons, the site's and the MCP page's copies and the store listing icons, from an
// art module (art/ai1.mjs, "Soft tile", unless --art names another) and the colours in
// design/tokens/snacklist.tokens.json. Node only, no packages and no network.
//   node design/app-icon/build.mjs             writes every platform file
//   node design/app-icon/build.mjs --check     writes nothing, exits 1 when a file differs
//   node design/app-icon/build.mjs --previews  writes docs/screenshots/385/icon/ and prints the
//                                              contrast and safe-zone numbers
//   --art <module>  draws another art module (job 372's options: branch job/372-app-icon-prototypes)
//   --out <dir>     writes under <dir> instead of the repo
import { Buffer } from 'node:buffer';
import process from 'node:process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve as absolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { roundedPolygon } from './geom.mjs';
import { Canvas, coverage, png } from './raster.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const tokens = JSON.parse(readFileSync(join(root, 'design/tokens/snacklist.tokens.json'), 'utf8'));
const resolve = (v) => (typeof v === 'string' && /^\{.+\}$/.test(v) ? resolve(v.slice(1, -1).split('.').reduce((n, k) => n[k], tokens).$value) : v);
const color = (mode, name) => resolve(tokens.color[mode][name].$value).hex.toLowerCase();
const MODES = ['light', 'dark'];
const args = process.argv.slice(2);
const arg = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const artPath = arg('--art') ?? join(here, 'art/ai1.mjs');
const outRoot = arg('--out');
const art = (await import(pathToFileURL(absolute(artPath)).href)).default({ color });

// ---- The art ----
// A 1024 canvas, which is Android's 72 dp visible area. Foreground groups over a background
// fill; Icon Composer and Android's foreground take the groups as they are. MONO is the one-colour
// glyph (Android monochrome, iOS tinted).
const C = 512;
const ART = 1024;
const GROUPS = art.groups;
const MONO = art.mono;
const MONO_RULE = art.monoEvenOdd ? 'evenodd' : 'nonzero';
const ICON = art.colors;
const ELS = GROUPS.flatMap((g) => g.els);

const SPLASH = { light: color('light', 'surface'), dark: color('dark', 'surface') };
// The mark's box on every splash, in pt, dp and CSS px.
const SPLASH_MARK = 128;

// ---- Rendering ----
// `place` maps art units to output pixels: [scale, tx, ty].
const fit = (size) => [size / ART, 0, 0];
// Android's 108 dp canvas: the 1024 art is its middle 72 dp.
const fitAdaptive = (size) => [size / (ART * 1.5), size / 6, size / 6];

const MASKS = {
  apple: superellipse(5),
  squircle: superellipse(4),
  circle: [Array.from({ length: 256 }, (_, i) => [C + C * Math.cos((i * Math.PI) / 128), C + C * Math.sin((i * Math.PI) / 128)])],
  rounded: roundedPolygon([[0, 0], [ART, 0], [ART, ART], [0, ART]], 184).rings,
};
function superellipse(n) {
  return [Array.from({ length: 512 }, (_, i) => {
    const t = (i / 512) * 2 * Math.PI;
    const c = Math.cos(t);
    const s = Math.sin(t);
    return [C + C * Math.sign(c) * Math.abs(c) ** (2 / n), C + C * Math.sign(s) * Math.abs(s) ** (2 / n)];
  })];
}
const FULL = [[[-1e4, -1e4], [1e4, -1e4], [1e4, 1e4], [-1e4, 1e4]]];

function rgba(size, paint, { place = fit(size), mask } = {}) {
  const canvas = new Canvas(size, size);
  const fill = (rings, col, rule) => canvas.paint(coverage(size, size, rings, place, rule), col);
  paint(fill, place);
  if (mask) canvas.clip(coverage(size, size, MASKS[mask], place));
  return canvas.bytes();
}
const render = (size, paint, opts) => png(size, size, rgba(size, paint, opts));

const paintIcon = (mode, { background = true } = {}) => (fill) => {
  const c = ICON[mode];
  if (background) fill(FULL, c.bg);
  for (const e of ELS) fill(e.shape.rings, c[e.role], e.evenOdd ? 'evenodd' : 'nonzero');
};
const paintMono = (bg, glyph) => (fill) => {
  if (bg) fill(FULL, bg);
  fill(MONO.rings, glyph, MONO_RULE);
};
const icon = (mode, size, opts = {}) => render(size, paintIcon(mode, opts), opts);

// The splash mark: the icon itself on a rounded tile.
const TILE = roundedPolygon([[0, 0], [ART, 0], [ART, ART], [0, ART]], 184);

// The mark, its box scaled to `box` px and centred on a `size` px canvas.
function renderMark(mode, size, box, bg) {
  const o = (size - box) / 2;
  return render(size, (fill) => {
    if (bg) fill(FULL, bg);
    fill(TILE.rings, ICON[mode].bg);
    for (const e of ELS) fill(e.shape.rings, ICON[mode][e.role], e.evenOdd ? 'evenodd' : 'nonzero');
  }, { place: [box / ART, o, o] });
}

// ---- Text formats ----
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const json = (v) => `${JSON.stringify(v, null, 2)}\n`;
const svgDoc = (body, viewBox = `0 0 ${ART} ${ART}`) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">${body}</svg>\n`;

const fillRule = (e) => (e.evenOdd ? ' fill-rule="evenodd"' : '');
function markSvg(mode) {
  const c = ICON[mode];
  return svgDoc(`<title>Snacklist</title><path fill="${c.bg}" d="${TILE.d}"/>${ELS.map((e) => `<path fill="${c[e.role]}"${fillRule(e)} d="${e.shape.d}"/>`).join('')}`);
}

// The favicon follows the browser's colour scheme on its own.
function faviconSvg() {
  const cls = Object.keys(ICON.light);
  const rules = (mode) => cls.map((k) => `.${k}{fill:${ICON[mode][k]}}`).join('');
  const r = 184;
  return svgDoc(`<style>${rules('light')}@media (prefers-color-scheme:dark){${rules('dark')}}</style><rect class="bg" width="${ART}" height="${ART}" rx="${r}"/>${ELS.map((e) => `<path class="${e.role}"${fillRule(e)} d="${e.shape.d}"/>`).join('')}`);
}

// Android vector drawables on the 108 dp canvas; the art sits in the middle 72 dp.
const PAD = ART / 4;
function vector(paths, { size = 108, viewport = ART + 2 * PAD, group = `android:translateX="${PAD}" android:translateY="${PAD}"` } = {}) {
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by design/app-icon/build.mjs. Do not edit. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${size}dp"
    android:height="${size}dp"
    android:viewportWidth="${viewport}"
    android:viewportHeight="${viewport}">
    <group ${group}>
${paths.map((p) => `        <path ${p}/>`).join('\n')}
    </group>
</vector>
`;
}
const vdFill = (col, d, evenOdd) => `android:fillColor="${col}"${evenOdd ? ' android:fillType="evenOdd"' : ''} android:pathData="${d}"`;
const adaptive = `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by design/app-icon/build.mjs. Do not edit. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
`;
// Android 12's splash icon is 288 dp with the visible part inside a 192 dp circle; the mark
// sits in the middle at SPLASH_MARK dp, and pre-12 launch_background draws the same drawable.
function splashVector(mode) {
  const c = ICON[mode];
  const s = SPLASH_MARK / ART;
  const o = (288 - SPLASH_MARK) / 2;
  return vector([vdFill(c.bg, TILE.d), ...ELS.map((e) => vdFill(c[e.role], e.shape.d, e.evenOdd))], { size: 288, viewport: 288, group: `android:translateX="${o}" android:translateY="${o}" android:scaleX="${s}" android:scaleY="${s}"` });
}
const colorsXml = (mode) => `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by design/app-icon/build.mjs. Do not edit. -->
<resources>
    <!-- Splash screen and the window behind the app: the ${mode} surface token. -->
    <color name="splash_background">${SPLASH[mode]}</color>
</resources>
`;

// iOS asset catalog.
const XCODE_INFO = { author: 'xcode', version: 1 };
const dark = { appearances: [{ appearance: 'luminosity', value: 'dark' }] };
const srgb = (hexColor) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hexColor.slice(i, i + 2), 16));
  return { 'color-space': 'srgb', components: { red: `0x${r.toString(16).toUpperCase().padStart(2, '0')}`, green: `0x${g.toString(16).toUpperCase().padStart(2, '0')}`, blue: `0x${b.toString(16).toUpperCase().padStart(2, '0')}`, alpha: '1.000' } };
};

// ---- Outputs ----
const IOS = 'app/ios/Runner';
const XCASSETS = `${IOS}/Assets.xcassets`;
const RES = 'app/android/app/src/main/res';
const WEB = 'app/web';
const BRAND = 'app/assets/brand';
const ALEXA = 'alexa/skill-package/assets/images';
const STORE = 'marketing/store-icons';
const BRAND_SIZE = 56;
const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

function outputs() {
  const out = [];
  const add = (path, content) => out.push([path, content]);

  add(`${XCASSETS}/AppIcon.appiconset/Contents.json`, json({
    images: [
      { filename: 'AppIcon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
      { ...dark, filename: 'AppIcon-1024-dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
      { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'AppIcon-1024-tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    ],
    info: XCODE_INFO,
  }));
  add(`${XCASSETS}/AppIcon.appiconset/AppIcon-1024.png`, icon('light', 1024));
  add(`${XCASSETS}/AppIcon.appiconset/AppIcon-1024-dark.png`, icon('dark', 1024));
  // Tinted: grayscale on black; iOS tints the light parts.
  add(`${XCASSETS}/AppIcon.appiconset/AppIcon-1024-tinted.png`, render(1024, paintMono('#000000', '#ffffff')));

  add(`${XCASSETS}/LaunchBackground.colorset/Contents.json`, json({
    colors: [{ color: srgb(SPLASH.light), idiom: 'universal' }, { ...dark, color: srgb(SPLASH.dark), idiom: 'universal' }],
    info: XCODE_INFO,
  }));
  const scales = [1, 2, 3];
  const launchName = (mode, k) => `LaunchImage${mode === 'dark' ? '-dark' : ''}${k > 1 ? `@${k}x` : ''}.png`;
  add(`${XCASSETS}/LaunchImage.imageset/Contents.json`, json({
    images: MODES.flatMap((mode) => scales.map((k) => ({ ...(mode === 'dark' ? dark : {}), filename: launchName(mode, k), idiom: 'universal', scale: `${k}x` }))),
    info: XCODE_INFO,
  }));
  for (const mode of MODES) for (const k of scales) add(`${XCASSETS}/LaunchImage.imageset/${launchName(mode, k)}`, renderMark(mode, SPLASH_MARK * k, SPLASH_MARK * k));

  for (const [path, content] of iconComposer()) add(`${IOS}/AppIcon.icon/${path}`, content);

  add(`${RES}/drawable/ic_launcher_background.xml`, vector([vdFill(ICON.light.bg, `M${-PAD} ${-PAD} L${ART + PAD} ${-PAD} L${ART + PAD} ${ART + PAD} L${-PAD} ${ART + PAD} Z`)]));
  add(`${RES}/drawable/ic_launcher_foreground.xml`, vector(ELS.map((e) => vdFill(ICON.light[e.role], e.shape.d, e.evenOdd))));
  add(`${RES}/drawable/ic_launcher_monochrome.xml`, vector([vdFill('#FF000000', MONO.d, art.monoEvenOdd)]));
  add(`${RES}/mipmap-anydpi-v26/ic_launcher.xml`, adaptive);
  add(`${RES}/mipmap-anydpi-v26/ic_launcher_round.xml`, adaptive);
  // Android 7 (API 24, 25) has no adaptive icons and takes these as they are.
  for (const [density, k] of Object.entries(DENSITIES)) {
    add(`${RES}/mipmap-${density}/ic_launcher.png`, icon('light', 48 * k, { mask: 'rounded' }));
    add(`${RES}/mipmap-${density}/ic_launcher_round.png`, icon('light', 48 * k, { mask: 'circle' }));
  }
  add(`${RES}/drawable/splash_mark.xml`, splashVector('light'));
  add(`${RES}/drawable-night/splash_mark.xml`, splashVector('dark'));
  add(`${RES}/values/colors.xml`, colorsXml('light'));
  add(`${RES}/values-night/colors.xml`, colorsXml('dark'));

  // The in-app brand block on login and welcome: the same icon, rounded, 56 dp at 1x/2x/3x.
  // Flutter picks `2.0x/` and `3.0x/` next to the 1x file by pixel ratio.
  for (const mode of MODES) {
    for (const k of scales) add(`${BRAND}/${k > 1 ? `${k}.0x/` : ''}mark-${mode}.png`, icon(mode, BRAND_SIZE * k, { mask: 'rounded' }));
  }

  add(`${WEB}/favicon.svg`, faviconSvg());
  add(`${WEB}/favicon.png`, icon('light', 48, { mask: 'rounded' }));
  // The site's and the MCP page's copies of the web icons.
  add('site/public/favicon.svg', faviconSvg());
  add('site/public/favicon.png', icon('light', 48, { mask: 'rounded' }));
  add('site/public/apple-touch-icon.png', icon('light', 180));
  add('mcp-proxy/public/static/logo.svg', faviconSvg());
  add(`${WEB}/icons/Icon-192.png`, icon('light', 192, { mask: 'rounded' }));
  add(`${WEB}/icons/Icon-512.png`, icon('light', 512, { mask: 'rounded' }));
  // Maskable: the whole image is the 108 dp canvas, like Android's adaptive icon, so the art
  // stays inside the 80 % safe circle with room to spare.
  add(`${WEB}/icons/Icon-maskable-192.png`, icon('light', 192, { place: fitAdaptive(192) }));
  add(`${WEB}/icons/Icon-maskable-512.png`, icon('light', 512, { place: fitAdaptive(512) }));
  add(`${WEB}/icons/apple-touch-icon.png`, icon('light', 180));
  // Job 55: the email header's logo, 48 px shown at 2x, square so it never has transparent
  // corners for a client's dark mode to invert behind; the mail rounds it with CSS.
  add('site/public/email/snacklist-icon-96.png', icon('light', 96));
  for (const mode of MODES) add(`${WEB}/splash/mark-${mode}.svg`, markSvg(mode));
  // Amazon's skill store sizes; full bleed like the App Store icon, which Amazon may round.
  add(`${ALEXA}/de-DE_smallIconUri.png`, icon('light', 108));
  add(`${ALEXA}/de-DE_largeIconUri.png`, icon('light', 512));
  add(`${WEB}/splash.css`, `/* Generated by design/app-icon/build.mjs. Do not edit. The page before Flutter's first
   frame: the mark on the surface colour; flutter_bootstrap.js removes #splash on that frame. */
html { background: ${SPLASH.light}; }
#splash { position: fixed; inset: 0; z-index: 1; pointer-events: none; background: ${SPLASH.light} url("splash/mark-light.svg") center / ${SPLASH_MARK}px ${SPLASH_MARK}px no-repeat; }
@media (prefers-color-scheme: dark) {
  html { background: ${SPLASH.dark}; }
  #splash { background-color: ${SPLASH.dark}; background-image: url("splash/mark-dark.svg"); }
}
`);
  // The manifest keeps its own text; only the two colours come from here.
  const manifest = JSON.parse(readFileSync(join(root, WEB, 'manifest.json'), 'utf8'));
  manifest.background_color = SPLASH.light;
  manifest.theme_color = ICON.light.bg;
  add(`${WEB}/manifest.json`, `${JSON.stringify(manifest, null, 4)}\n`);
  // The store listings: App Store Connect takes the 1024 icon without alpha, Play the 512 one
  // full bleed (Play rounds it).
  add(`${STORE}/app-store-1024.png`, icon('light', 1024));
  add(`${STORE}/play-512.png`, icon('light', 512));
  return out;
}

// Icon Composer (iOS 26): one SVG per layer, the fills per appearance in icon.json. Groups and
// layers list front to back. Tinted (Icon Composer's "Mono"): every layer white unless the art's
// `tinted` hides a role or gives it another grey (AI1: the inner tile hidden).
const icSrgb = (h) => `srgb:${rgb(h).map((v) => (v / 255).toFixed(5)).join(',')},1.00000`;
const icFill = (light, darkColor) => [{ value: { solid: icSrgb(light) } }, { appearance: 'dark', value: { solid: icSrgb(darkColor) } }];
const icJson = (v) => `${JSON.stringify(v, null, 2).replace(/"([^"]+)": /g, '"$1" : ')}\n`;
function iconComposer() {
  const files = [];
  const layer = (e) => {
    files.push([`Assets/${e.role}.svg`, svgDoc(`<path fill="${ICON.light[e.role]}"${fillRule(e)} d="${e.shape.d}"/>`)]);
    const tint = art.tinted[e.role];
    const tinted = tint === 'hide'
      ? { 'opacity-specializations': [{ value: 1 }, { appearance: 'tinted', value: 0 }] }
      : {};
    const gray = typeof tint === 'number' ? tint : 1;
    return {
      'fill-specializations': [...icFill(ICON.light[e.role], ICON.dark[e.role]), { appearance: 'tinted', value: { solid: `extended-gray:${gray.toFixed(5)},1.00000` } }],
      'image-name': `${e.role}.svg`,
      name: e.role,
      ...tinted,
    };
  };
  const groups = [...GROUPS].reverse().map((g) => ({ layers: [...g.els].reverse().map(layer), name: g.name }));
  files.push(['icon.json', icJson({
    'fill-specializations': icFill(ICON.light.bg, ICON.dark.bg),
    groups,
    'supported-platforms': { squares: 'shared' },
  })]);
  return files;
}

// ---- Previews and numbers (docs only, not checked) ----
const luminance = (h) => {
  const [r, g, b] = rgb(h).map((x) => x / 255).map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

function previews() {
  const dir = 'docs/screenshots/385/icon';
  const out = [];
  const add = (name, content) => out.push([`${dir}/${name}`, content]);
  for (const mode of MODES) add(`apple-${mode}.png`, icon(mode, 1024, { mask: 'apple' }));
  add('apple-tinted.png', render(1024, paintMono('#1d160b', '#ffb84a'), { mask: 'apple' }));
  for (const mask of ['circle', 'squircle', 'rounded']) add(`android-${mask}.png`, icon('light', 1024, { mask }));
  add('android-themed-light.png', render(1024, paintMono('#d7e8cd', '#102000'), { mask: 'circle' }));
  add('android-themed-dark.png', render(1024, paintMono('#253420', '#bcecaa'), { mask: 'circle' }));
  add('web-maskable-512.png', icon('light', 512, { place: fitAdaptive(512) }));
  for (const mode of MODES) add(`splash-${mode}.png`, renderMark(mode, 512, SPLASH_MARK * 2, SPLASH[mode]));
  const SMALL = [['apple-16', 16, 'apple'], ['apple-29', 29, 'apple'], ['apple-87', 87, 'apple'], ['android-48', 48, 'circle'], ['android-144', 144, 'circle']];
  for (const [name, size, mask] of SMALL) for (const mode of MODES) add(`small/${name}-${mode}.png`, icon(mode, size, { mask }));
  // The small sizes side by side, every pixel drawn as a ZOOM x ZOOM block on grey.
  const ZOOM = 6;
  const GAP = 24;
  const W = SMALL.reduce((w, [, size]) => w + size * ZOOM + GAP, GAP);
  const H = GAP + MODES.length * (Math.max(...SMALL.map(([, size]) => size)) * ZOOM + GAP);
  const sheet = Buffer.alloc(W * H * 4);
  for (let i = 0; i < W * H; i++) sheet.set([136, 136, 136, 255], i * 4);
  MODES.forEach((mode, row) => {
    let x0 = GAP;
    const y0 = GAP + row * (Math.max(...SMALL.map(([, size]) => size)) * ZOOM + GAP);
    for (const [, size, mask] of SMALL) {
      const px = rgba(size, paintIcon(mode), { mask });
      for (let y = 0; y < size * ZOOM; y++) for (let x = 0; x < size * ZOOM; x++) {
        const s4 = (Math.floor(y / ZOOM) * size + Math.floor(x / ZOOM)) * 4;
        const d4 = ((y0 + y) * W + x0 + x) * 4;
        const a = px[s4 + 3] / 255;
        for (let c = 0; c < 3; c++) sheet[d4 + c] = Math.round(px[s4 + c] * a + 136 * (1 - a));
      }
      x0 += size * ZOOM + GAP;
    }
  });
  add('small-sheet.png', png(W, H, sheet));
  return out;
}

function report() {
  const pairs = [['bg', 'outer'], ['outer', 'inner'], ['bg', 'inner'], ['inner', 'mark']];
  for (const mode of MODES) {
    const c = ICON[mode];
    console.log(`${mode}: ${pairs.map(([a, b]) => `${a} ${c[a]} / ${b} ${c[b]} ${contrast(c[a], c[b]).toFixed(2)}:1`).join(', ')}`);
    console.log(`${mode} splash tile ${c.bg} on ${SPLASH[mode]}: ${contrast(c.bg, SPLASH[mode]).toFixed(2)}:1`);
  }
  const far = Math.max(...ELS.flatMap((e) => e.shape.rings.flat()).map(([x, y]) => Math.hypot(x - C, y - C)));
  console.log(`foreground reaches ${(far / (ART / 72)).toFixed(2)} dp from the centre (safe circle 33 dp)`);
  const tileFar = Math.max(...TILE.rings.flat().map(([x, y]) => Math.hypot(x - C, y - C)));
  console.log(`splash tile reaches ${(tileFar * (SPLASH_MARK / ART)).toFixed(1)} dp from the centre (Android 12 circle 96 dp)`);
}

// Android crops the adaptive icon to as little as the 66 dp circle; nothing may reach past it.
const SAFE = 33 * (ART / 72);
for (const g of GROUPS) for (const e of g.els) for (const [x, y] of e.shape.rings.flat()) {
  if (Math.hypot(x - C, y - C) > SAFE) throw new Error(`${g.name} leaves the 66 dp safe circle`);
}

const checkOnly = args.includes('--check');
const files = args.includes('--previews') ? previews() : outputs();
let stale = 0;
for (const [path, content] of files) {
  const file = join(outRoot ?? root, path);
  const want = Buffer.from(content);
  if (existsSync(file) && readFileSync(file).equals(want)) continue;
  if (checkOnly) {
    console.error(`${path} is stale: run node design/app-icon/build.mjs`);
    stale++;
  } else {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, want);
    console.log(`wrote ${path}`);
  }
}
if (args.includes('--previews')) report();
process.exit(stale ? 1 : 0);
