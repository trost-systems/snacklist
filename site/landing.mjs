// The landing pages /de and /en: copy from content/landing/copy.yml, illustrations and demo videos
// from public/media/ (media/README.md names the files). Every string carries its copy id in
// `data-copy-id`, so Hummlist Launch finds it in the page and in COPY_NEEDED.md.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import yaml from 'js-yaml';
import MarkdownIt from 'markdown-it';

export const APP_URL = 'https://app.hummlist.com';
const LOCALES = ['de', 'en'];
const STATUSES = ['draft', 'reused'];
const COMPACT = '(max-width: 37.5rem)';
const DARK = '(prefers-color-scheme: dark)';

export class CopyError extends Error {}

// id -> { de, en, status, source }. Both languages are required, so a page can't miss a string.
export function parseCopy(text, file) {
  const fail = (reason) => {
    throw new CopyError(`${file}: ${reason}`);
  };
  let data;
  try {
    data = yaml.safeLoad(text);
  } catch (error) {
    fail(`not valid YAML: ${error.message}`);
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) fail('must map copy ids to entries');
  const copy = new Map();
  for (const [id, entry] of Object.entries(data)) {
    if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(id)) fail(`copy id "${id}" must look like section.name`);
    if (entry === null || typeof entry !== 'object') fail(`${id}: must have de, en, status and source`);
    const extra = Object.keys(entry).filter((k) => ![...LOCALES, 'status', 'source'].includes(k));
    if (extra.length > 0) fail(`${id}: unknown field ${extra.join(', ')}`);
    for (const field of [...LOCALES, 'source']) {
      if (typeof entry[field] !== 'string' || entry[field].trim() === '') fail(`${id}: "${field}" must be a non-empty string`);
    }
    if (!STATUSES.includes(entry.status)) fail(`${id}: "status" must be ${STATUSES.join(' or ')}, got ${JSON.stringify(entry.status)}`);
    copy.set(id, entry);
  }
  return copy;
}

const inline = new MarkdownIt({ html: false, linkify: false, typographer: false });

const escapeAttr = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// Material Symbols (Apache 2.0), outlined, 24 px grid.
const ICONS = {
  check: 'M9.55 18 3.85 12.3l1.43-1.43 4.27 4.28 9.17-9.18 1.43 1.43Z',
  play: 'M8 19V5l11 7Z',
  pause: 'M14 19V5h4v14Zm-8 0V5h4v14Z',
  open: 'M5 21q-.82 0-1.41-.59T3 19V5q0-.82.59-1.41T5 3h7v2H5v14h14v-7h2v7q0 .82-.59 1.41T19 21Zm4.7-5.3-1.4-1.4L17.6 5H14V3h7v7h-2V6.4Z',
};
const icon = (name, cls = '') => `<svg${cls ? ` class="${cls}"` : ''} viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="${ICONS[name]}"/></svg>`;

// Width and height of a WebP (lossy, lossless or extended), for the img's size attributes.
export function webpSize(buffer) {
  const chunk = buffer.toString('ascii', 12, 16);
  if (buffer.toString('ascii', 0, 4) !== 'RIFF' || buffer.toString('ascii', 8, 12) !== 'WEBP') return null;
  if (chunk === 'VP8X') return [1 + buffer.readUIntLE(24, 3), 1 + buffer.readUIntLE(27, 3)];
  if (chunk === 'VP8 ') return [buffer.readUInt16LE(26) & 0x3fff, buffer.readUInt16LE(28) & 0x3fff];
  if (chunk === 'VP8L') {
    const bits = buffer.readUInt32LE(21);
    return [1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff)];
  }
  return null;
}

// The shape each poster must have: demo slots and feature stills are 16:9 wide and 4:5 compact,
// the same frames as the demo videos (media/README.md); the hero has its own.
const RATIOS = { card: { wide: 16 / 9, compact: 4 / 5 }, hero: { wide: null, compact: null } };

// The files of one visual or demo slot in public/media/: posters per width and scheme, and, for a
// demo slot, the video in both widths and formats plus its captions. Posters are required; a video
// is all four files and its captions, or none of them (the slot then shows its poster).
export function mediaFor(publicDir, name, locale, { shape, video = false }) {
  const rel = (file) => `/media/${file}`;
  const path = (file) => join(publicDir, 'media', file);
  const has = (file) => existsSync(path(file));
  const base = `${name}-${locale}`;
  const size = (file, width) => {
    const dims = webpSize(readFileSync(path(file)));
    if (!dims) throw new CopyError(`public/media/${file} is not a WebP image`);
    const ratio = RATIOS[shape][width];
    if (ratio !== null && Math.abs(dims[0] / dims[1] - ratio) > 0.01) {
      throw new CopyError(`public/media/${file} is ${dims[0]}x${dims[1]}; a ${width} poster must be ${width === 'wide' ? '16:9' : '4:5'}`);
    }
    return dims;
  };
  const poster = (width) => {
    const light = `${base}-${width}.webp`;
    const dark = `${base}-${width}-dark.webp`;
    if (!has(light)) throw new CopyError(`public/media/${light} is missing (media/README.md lists the files)`);
    const dims = size(light, width);
    if (has(dark) && size(dark, width).join() !== dims.join()) throw new CopyError(`public/media/${dark} must be the size of ${light}`);
    return { light: rel(light), dark: has(dark) ? rel(dark) : null, size: dims };
  };
  const media = { posters: { wide: poster('wide'), compact: poster('compact') }, video: null };
  if (!video) return media;
  const files = ['wide.webm', 'wide.mp4', 'compact.webm', 'compact.mp4'].map((f) => `${base}-${f}`);
  const present = files.filter(has);
  if (present.length === 0) return media;
  const missing = [...files, `${base}.vtt`].filter((f) => !has(f));
  if (missing.length > 0) throw new CopyError(`public/media/: ${base} has ${present.join(', ')} but not ${missing.join(', ')}; a demo video needs all of them`);
  if (!readFileSync(path(`${base}.vtt`), 'utf8').includes('-->')) {
    throw new CopyError(`public/media/${base}.vtt has no cues; a demo video ships with its captions`);
  }
  media.video = { files: files.map(rel), captions: rel(`${base}.vtt`) };
  return media;
}

function picture({ posters }, alt, { className = '', eager = false, hidden = false } = {}) {
  const { wide, compact } = posters;
  const sources = [
    compact.dark && [`${COMPACT} and ${DARK}`, compact.dark, compact.size],
    [COMPACT, compact.light, compact.size],
    wide.dark && [DARK, wide.dark, wide.size],
  ]
    .filter(Boolean)
    .map(([media, src, [w, h]]) => `<source media="${media}" srcset="${src}" width="${w}" height="${h}">`);
  const [w, h] = wide.size;
  const loading = eager ? ' fetchpriority="high"' : ' loading="lazy"';
  return `<picture${className ? ` class="${className}"` : ''}${hidden ? ' aria-hidden="true"' : ''}>${sources.join('')}<img src="${wide.light}" alt="${escapeAttr(alt)}" width="${w}" height="${h}" decoding="async"${loading}></picture>`;
}

export function renderLanding({ locale, copy, config, publicDir }) {
  const used = new Set();
  const text = (id) => {
    const entry = copy.get(id);
    if (!entry) throw new CopyError(`content/landing/copy.yml: copy id "${id}" is used by the landing page but missing`);
    used.add(id);
    return entry[locale];
  };
  const md = (id) => inline.renderInline(text(id));
  const el = (tag, id, attrs = '') => `<${tag} data-copy-id="${id}"${attrs ? ` ${attrs}` : ''}>${md(id)}</${tag}>`;

  const demo = (slot) => {
    const media = mediaFor(publicDir, slot, locale, { shape: 'card', video: true });
    const alt = text(`demo.${slot}`);
    const play = escapeAttr(text('demo.play'));
    const pause = escapeAttr(text('demo.pause'));
    if (!media.video) {
      return `<figure class="media-frame demo" data-copy-id="demo.${slot}">${picture(media, alt)}</figure>`;
    }
    const [wideWebm, wideMp4, compactWebm, compactMp4] = media.video.files;
    const sources = [
      `<source media="${COMPACT}" src="${compactWebm}" type="video/webm">`,
      `<source media="${COMPACT}" src="${compactMp4}" type="video/mp4">`,
      `<source src="${wideWebm}" type="video/webm">`,
      `<source src="${wideMp4}" type="video/mp4">`,
    ].join('');
    const label = locale === 'de' ? 'Deutsch' : 'English';
    return `<figure class="media-frame demo" data-demo data-copy-id="demo.${slot}">${picture(media, alt, { hidden: true })}<video muted loop playsinline preload="none" controls aria-label="${escapeAttr(alt)}">${sources}<track kind="captions" srclang="${locale}" label="${label}" src="${media.video.captions}"></video><button type="button" class="demo-toggle" hidden data-play="${play}" data-pause="${pause}" aria-label="${play}"><span class="demo-toggle-face">${icon('play', 'icon-play')}${icon('pause', 'icon-pause')}</span></button></figure>`;
  };

  const still = (name, altId) => `<figure class="media-frame" data-copy-id="${altId}">${picture(mediaFor(publicDir, name, locale, { shape: 'card' }), text(altId))}</figure>`;

  // Shown only while their pages are published, but always part of the page's copy.
  const privacyMore = config.privacyPublished ? el('p', 'privacy.more', 'class="privacy-more"') : (text('privacy.more'), '');
  const helpLink = config.supportPublished
    ? `<a class="link-strong" href="${locale === 'de' ? '/support' : '/en/support'}" data-copy-id="test.help">${md('test.help')}</a>`
    : (text('test.help'), '');
  const tick = `<span class="tick hxp" aria-hidden="true">${icon('check')}</span>`;
  const privacyItems = ['privacy.frankfurt', 'privacy.consent', 'privacy.export', 'privacy.delete', 'privacy.website'];

  const html = `<section class="hero" aria-labelledby="hero-title">
<div class="wrap block block--cobalt hero-block">
<div class="hero-copy">
<p class="chip hx"><span class="dot hxp" aria-hidden="true">${icon('check')}</span><span data-copy-id="hero.badge">${md('hero.badge')}</span></p>
${el('h1', 'hero.title', 'class="display" id="hero-title"')}
${el('p', 'hero.lead', 'class="lead"')}
<div class="hero-actions">
<a class="hex" href="${APP_URL}"><span class="face" data-copy-id="header.open-app">${md('header.open-app')}${icon('open')}</span></a>
<a class="link-strong" href="#test" data-copy-id="hero.test-link">${md('hero.test-link')}</a>
</div>
</div>
<div class="hero-visual" data-copy-id="hero.image">${picture(mediaFor(publicDir, 'hero', locale, { shape: 'hero' }), text('hero.image'), { eager: true })}</div>
</div>
</section>
<section class="section features" id="features" aria-labelledby="features-title">
<div class="wrap">
<div class="section-head">
${el('h2', 'features.title', 'class="headline" id="features-title"')}
${el('p', 'features.lead', 'class="lead"')}
</div>
<article class="feature block block--honey" aria-labelledby="feature-list">
<div class="feature-copy">
${el('h3', 'feature.list.title', 'class="title-l" id="feature-list"')}
${el('p', 'feature.list.body')}
</div>
${demo('add-tick')}
</article>
<article class="feature feature--flip block block--mist" aria-labelledby="feature-household">
<div class="feature-copy">
${el('h3', 'feature.household.title', 'class="title-l" id="feature-household"')}
${el('p', 'feature.household.body')}
${el('p', 'feature.household.invite')}
</div>
${demo('household-sync')}
</article>
<article class="feature block block--mint" aria-labelledby="feature-stores">
<div class="feature-copy">
${el('h3', 'feature.stores.title', 'class="title-l" id="feature-stores"')}
${el('p', 'feature.stores.body')}
${el('p', 'feature.stores.more')}
</div>
${still('stores', 'feature.stores.image')}
</article>
</div>
</section>
<section class="section voice" id="voice" aria-labelledby="voice-title">
<div class="wrap block block--tomato">
<div class="section-head">
${el('h2', 'voice.title', 'class="headline" id="voice-title"')}
${el('p', 'voice.lead', 'class="lead"')}
</div>
<div class="voice-grid">
<article class="assistant assistant--ai" aria-labelledby="voice-ai">
<div class="assistant-copy">
${el('h3', 'voice.ai.title', 'class="title" id="voice-ai"')}
${el('p', 'voice.ai.body')}
${el('p', 'voice.ai.how', 'class="muted"')}
</div>
${demo('mcp-chat')}
</article>
<article class="assistant assistant--siri" aria-labelledby="voice-siri">
<div class="assistant-head">
${el('h3', 'voice.siri.title', 'class="title" id="voice-siri"')}
<p class="soon hx hx--honey" data-copy-id="voice.siri.badge">${md('voice.siri.badge')}</p>
</div>
${el('p', 'voice.siri.body')}
${el('p', 'voice.siri.now', 'class="muted"')}
</article>
</div>
</div>
</section>
<section class="section privacy-section" id="privacy" aria-labelledby="privacy-title">
<div class="wrap block block--cobalt privacy">
<div class="section-head">
${el('h2', 'privacy.title', 'class="headline" id="privacy-title"')}
${el('p', 'privacy.lead', 'class="lead"')}
${privacyMore}
</div>
<ul class="checklist">
${privacyItems.map((id) => `<li>${tick}<span data-copy-id="${id}">${md(id)}</span></li>`).join('\n')}
</ul>
</div>
</section>
<section class="section test-section" id="test" aria-labelledby="test-title">
<div class="wrap block block--honey cta">
${el('h2', 'test.title', 'class="headline" id="test-title"')}
${el('p', 'test.body')}
<div class="cta-actions">
<a class="hex hex--tomato" href="${APP_URL}"><span class="face" data-copy-id="header.open-app">${md('header.open-app')}${icon('open')}</span></a>
${helpLink}
</div>
</div>
</section>
`;
  return { html, used };
}

export function readCopy(contentDir) {
  const file = join(contentDir, 'landing/copy.yml');
  return parseCopy(readFileSync(file, 'utf8'), 'content/landing/copy.yml');
}
