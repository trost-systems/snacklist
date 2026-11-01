// Shared pieces of the demo-video compositions: formats, the page shell, the phone, touch dots
// and captions. Sizes are written in `u`, one CSS pixel of the size the site shows the video at
// (media/README.md: 576 x 324 wide, 358 x 448 compact), so a scene reads like the posters of
// site/scenes/ and every number can be checked against the page.

import { readFileSync } from 'node:fs';

export const FPS = 30;

export const FORMATS = {
  wide: { width: 1920, height: 1080, shown: { width: 576, height: 324 } },
  compact: { width: 1080, height: 1350, shown: { width: 358, height: 448 } },
};

/** The app's logical window (app/linux/runner/my_application.cc). */
export const APP = { width: 412, height: 892 };

export const copy = JSON.parse(readFileSync(new URL('./copy.json', import.meta.url), 'utf8'));

export function t(id, lang) {
  const entry = copy[id];
  if (!entry?.[lang]) throw new Error(`copy.json has no ${lang} text for ${id}`);
  return entry[lang].replace(/\n/g, ' ');
}

/** The text with its hand-set line break ("\n" in copy.json) for a wide caption column. */
export const tBreak = (id, lang) => {
  t(id, lang);
  return copy[id][lang];
};

export const frames = (s) => Math.round(s * FPS) / FPS;

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
export { esc };

/** Unit size in video pixels for a format. */
export const unit = (fmt) => FORMATS[fmt].width / FORMATS[fmt].shown.width;

/**
 * A phone: navy body, 2 px contour, sticker shadow (site/scenes/scenes.css .phone), and the
 * real app footage inside its screen. `fadeTop` ([from, to] in u from the phone's top) dissolves a cropped phone's head into the
 * ground, so no screen edge sits above content that is really mid-list. `box` is the phone in u; `appTop` is the logical app y at
 * the screen's top edge. Returns the html and a mapper from logical app points to stage u.
 */
export function phone({ id, box, appTop, src, start, duration, mediaStart, z = 2, quiet = false, fadeTop = null }) {
  const pad = 12; // 10 px body + 2 px contour, as in scenes.css
  const screen = { x: box.x + pad, y: box.y + pad, w: box.w - 2 * pad, h: box.h - 2 * pad };
  const k = screen.w / APP.width;
  const html = `
  <div class="phone${quiet ? ' phone--quiet' : ''}" id="${id}" data-layout-allow-overflow style="left:calc(${box.x} * var(--u));top:calc(${box.y} * var(--u));width:calc(${box.w} * var(--u));height:calc(${box.h} * var(--u));z-index:${z}${fadeTop ? `;--fade:linear-gradient(to bottom, transparent calc(${fadeTop[0]} * var(--u)), #000 calc(${fadeTop[1]} * var(--u)));-webkit-mask-image:var(--fade);mask-image:var(--fade)` : ''}">
    <div class="screen">
      <video id="${id}-v" class="clip" src="${src}" muted playsinline data-start="${start}" data-duration="${duration}" data-media-start="${mediaStart}" data-track-index="${z}"
        style="left:0;top:calc(${-appTop * k} * var(--u));width:calc(${APP.width * k} * var(--u));height:calc(${APP.height * k} * var(--u))"></video>
    </div>
  </div>`;
  const at = (x, y) => ({ x: screen.x + x * k, y: screen.y + (y - appTop) * k });
  return { html, at, k, screen };
}

/** A touch dot for each press/release pair of one client, timed on the composition clock. */
export function touches({ id, events, client, toStage, toTime, from, to }) {
  const presses = events.filter((e) => e.client === client && e.kind === 'press');
  const out = [];
  const tweens = [];
  presses.forEach((p, i) => {
    const r = events.find((e) => e.client === client && e.kind === 'release' && e.t >= p.t);
    const t0 = toTime(p.t);
    const t1 = toTime(r?.t ?? p.t + 100);
    if (t0 < from || t1 > to) return;
    const { x, y } = toStage(p.x, p.y);
    const did = `${id}-${i}`;
    const start = frames(Math.max(0, t0 - 0.12));
    const end = frames(t1 + 0.32);
    out.push(`<div id="${did}" class="clip touch-host" data-start="${start}" data-duration="${frames(end - start)}" data-track-index="9" style="left:calc(${x} * var(--u));top:calc(${y} * var(--u))"><div class="touch" id="${did}-dot"></div></div>`);
    tweens.push(`tl.fromTo('#${did}-dot', { scale: 0.55, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.1, ease: 'power2.out' }, ${(frames(t0) - 0.1).toFixed(4)});`);
    const hold = Math.max(1 / 30, Math.min(0.07, frames(t1) - frames(t0) - 1 / 30));
    tweens.push(`tl.to('#${did}-dot', { scale: 0.86, duration: ${hold.toFixed(3)}, ease: 'power1.out' }, ${frames(t0)});`);
    tweens.push(`tl.to('#${did}-dot', { scale: 1.25, opacity: 0, duration: 0.24, ease: 'power2.in' }, ${frames(t1)});`);
  });
  return { html: out.join('\n'), tweens };
}

/** Outlined Material glyphs (the app's icon font, codepoints from the Flutter SDK). */
export const ICONS = { add: 'ee47', chat: 'ef42', check: 'ef49', group: 'f0d9', mic: 'f1cb', send: 'f355', up: 'ee91' };

/**
 * Captions that swap in one slot. `cues` are [{ text, from, to }] on the composition clock; each
 * gets an entrance (rise and fade in, 240 ms) and an exit (fade up, 180 ms) inside its window.
 */
export function captions({ id, cues, slot, align = 'left' }) {
  const html = [];
  const tweens = [];
  cues.forEach((c, i) => {
    const cid = `${id}-${i}`;
    const icon = c.iconHtml ? `<span class="avs">${c.iconHtml}</span>`
      : c.icon ? `<span class="hxp hxp--${c.tone ?? 'honey'}"><b><i class="mi">&#x${ICONS[c.icon]};</i></b></span>` : '';
    html.push(`<p id="${cid}" class="clip caption caption--${align}" data-start="${frames(c.from)}" data-duration="${frames(c.to - c.from)}" data-track-index="8" style="${slot}"><span class="cap" id="${cid}-t">${icon}<span>${(c.html ?? esc(c.text))}</span></span></p>`);
    if (c.enter !== false) {
      tweens.push(`tl.fromTo('#${cid}-t', { opacity: 0, y: 18 }, { opacity: 1, y: 0, duration: 0.24, ease: 'power2.out' }, ${frames(c.from)});`);
    }
    if (c.exit !== false) {
      tweens.push(`tl.to('#${cid}-t', { opacity: 0, y: -14, duration: 0.18, ease: 'power1.in' }, ${frames(c.to - 0.2)});`);
    }
  });
  return { html: html.join('\n'), tweens };
}

/** WebVTT for the same cues; the page shows them as captions of the muted loop. */
export function vtt(cues) {
  const ts = (s) => {
    const ms = Math.round(s * 1000);
    const h = String(Math.floor(ms / 3600000)).padStart(2, '0');
    const m = String(Math.floor((ms % 3600000) / 60000)).padStart(2, '0');
    const sec = String(Math.floor((ms % 60000) / 1000)).padStart(2, '0');
    return `${h}:${m}:${sec}.${String(ms % 1000).padStart(3, '0')}`;
  };
  return `WEBVTT\n\n${cues.map((c, i) => `${i + 1}\n${ts(c.from)} --> ${ts(c.to)}\n${c.text}\n`).join('\n')}`;
}

/** The whole composition page. */
export function page({ fmt, duration, title, body, tweens, extraCss = '' }) {
  const f = FORMATS[fmt];
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<link rel="stylesheet" href="assets/tokens.css">
<link rel="stylesheet" href="assets/video.css">
<style>
  #root { --u: ${unit(fmt)}px; }
${extraCss}
</style>
<script src="assets/gsap.min.js"></script>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="${duration}" data-width="${f.width}" data-height="${f.height}" data-fps="${FPS}">
  <div class="ground"></div>
${body}
</div>
<script>
  window.__timelines = window.__timelines || {};
  const tl = gsap.timeline({ paused: true });
  ${tweens.join('\n  ')}
  tl.set({}, {}, ${duration});
  window.__timelines["main"] = tl;
</script>
</body>
</html>
`;
}
