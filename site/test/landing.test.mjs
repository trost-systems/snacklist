import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, publicWith, alternates, meta, serve, SITE_DIR, CONTENT_DIR } from './helpers.mjs';
import { parseCopy } from '../landing.mjs';
import { checkHtml } from '../build.mjs';
import { copyNeeded } from '../scripts/copy-needed.mjs';

const SITE = 'https://hummlist.com';
const COPY_TEXT = readFileSync(join(CONTENT_DIR, 'landing/copy.yml'), 'utf8');
const COPY = parseCopy(COPY_TEXT, 'copy.yml');
const PROD = { VERCEL_ENV: 'production' };
const SLOTS = ['add-tick', 'household-sync', 'mcp-chat'];

// The smallest WebP header the build reads sizes from (VP8X: canvas width and height).
function webp(width, height) {
  const b = Buffer.alloc(30);
  b.write('RIFF', 0);
  b.writeUInt32LE(22, 4);
  b.write('WEBPVP8X', 8);
  b.writeUInt32LE(10, 16);
  b.writeUIntLE(width - 1, 24, 3);
  b.writeUIntLE(height - 1, 27, 3);
  return b;
}

const CUES = 'WEBVTT\n\n00:00.000 --> 00:04.000\nHafermilch\n';
const videoFiles = (slot, locale) => ({
  ...Object.fromEntries(['wide.webm', 'wide.mp4', 'compact.webm', 'compact.mp4'].map((f) => [`media/${slot}-${locale}-${f}`, 'video'])),
  [`media/${slot}-${locale}.vtt`]: CUES,
});

test('/de and /en are the landing pages, paired with each other', () => {
  const { page } = buildSite();
  const expected = { de: `${SITE}/de`, en: `${SITE}/en`, 'x-default': `${SITE}/de` };
  for (const [route, locale, other] of [['/de', 'de', '/en'], ['/en', 'en', '/de']]) {
    const doc = page(route);
    assert.equal(doc.querySelector('html').getAttribute('lang'), locale);
    assert.equal(doc.querySelector('title').text, COPY.get('meta.title')[locale]);
    assert.equal(meta(doc, 'description'), COPY.get('meta.description')[locale]);
    assert.equal(doc.querySelector('h1').text, COPY.get('hero.title')[locale]);
    assert.deepEqual(alternates(doc), expected, route);
    assert.equal(doc.querySelector('link[rel="canonical"]').getAttribute('href'), `${SITE}${route}`);
    assert.equal(doc.querySelector('header nav.lang a').getAttribute('href'), other);
    assert.equal(doc.querySelector('meta[name="robots"]'), null, 'the landing page is not a draft');
  }
});

test('every copy id is on both landing pages with its text, and every string on them has an id', () => {
  const { page } = buildSite();
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    const seen = new Set(doc.querySelectorAll('[data-copy-id]').map((el) => el.getAttribute('data-copy-id')));
    // The play and pause labels sit on the button of a slot with a video (tested below).
    const meta = ['meta.title', 'meta.description', 'demo.play', 'demo.pause'];
    assert.deepEqual([...COPY.keys()].filter((id) => !seen.has(id) && !meta.includes(id)), [], locale);
    for (const el of doc.querySelectorAll('main [data-copy-id]')) {
      const entry = COPY.get(el.getAttribute('data-copy-id'));
      const plain = entry[locale].replace(/\*\*|\[|\]\([^)]*\)/g, '');
      const shown = el.querySelector('img')?.getAttribute('alt') ?? el.text;
      assert.equal(shown.trim(), plain, el.getAttribute('data-copy-id'));
    }
    const text = (el) => el.childNodes.filter((n) => n.nodeType === 3).map((n) => n.text).join('').trim();
    const loose = doc.querySelectorAll('main *').filter((el) => text(el) !== '' && !el.closest('[data-copy-id]'));
    assert.deepEqual(loose.map((el) => `${el.tagName} ${text(el)}`), [], `${locale}: text without a copy id`);
  }
});

test('copy.yml must give both languages, a status and a source, and every id must be used', () => {
  const broken = (text, pattern) => assert.throws(() => buildSite({ files: { 'landing/copy.yml': text } }), pattern);
  broken(COPY_TEXT.replace('  en: "One list for everyone"\n', ''), /feature\.list\.title: "en" must be a non-empty string/);
  broken(COPY_TEXT.replace(/(hero\.title:\n(?:  .*\n)*?)  status: draft/, '$1  status: final'), /hero\.title: "status" must be draft or reused/);
  broken(`${COPY_TEXT}\nhero.extra:\n  de: "x"\n  en: "x"\n  status: draft\n  source: "x"\n`, /copy ids not used on the landing page: hero\.extra/);
  broken(COPY_TEXT.replace(/hero\.lead:\n(?:  .*\n)*/, ''), /copy id "hero\.lead" is used by the landing page but missing/);
});

test('COPY_NEEDED.md is generated from copy.yml and lists every draft', () => {
  const file = readFileSync(join(SITE_DIR, 'COPY_NEEDED.md'), 'utf8');
  assert.equal(file, copyNeeded(COPY), 'stale: run node site/scripts/copy-needed.mjs');
  for (const [id, entry] of COPY) {
    if (entry.status === 'draft') assert.match(file, new RegExp(`\\| \`${id.replaceAll('.', '\\.')}\` \\|.*\\| draft \\|`), id);
  }
  assert.equal(COPY.get('voice.siri.badge').status, 'draft');
  assert.equal(COPY.get('voice.siri.body').status, 'draft');
});

test('the landing pages promise nothing that is not there: no prices, no Alexa, no Watch, no ChatGPT', () => {
  const { page } = buildSite({ env: PROD });
  for (const locale of ['de', 'en']) {
    const text = page(`/${locale}`).querySelector('body').text;
    assert.doesNotMatch(text, /€|\$|\bpreis|\bprice|premium|lifetime|abo\b|subscription|kostenlos|\bfree\b/i, locale);
    assert.doesNotMatch(text, /alexa|apple watch|chatgpt|openai|gemini/i, locale);
    assert.doesNotMatch(text, /\bhumm\b(?!list)|biene|\bbee\b/i, locale);
    assert.doesNotMatch(text, /\[PETER/, locale);
  }
});

test('Siri is marked as coming soon and links the shortcut guide that works today', () => {
  const { page } = buildSite();
  for (const [locale, badge, guide] of [['de', 'Bald', '/de/anleitungen/siri-kurzbefehl'], ['en', 'Coming soon', '/en/guides/siri-shortcut']]) {
    const card = page(`/${locale}`).querySelector('.assistant--siri');
    assert.equal(card.querySelector('[data-copy-id="voice.siri.badge"]').text, badge);
    assert.ok(card.querySelectorAll('a').some((a) => a.getAttribute('href') === guide), locale);
  }
});

test('the web app is linked and the privacy and help links follow their flags', () => {
  const on = buildSite().page('/de');
  assert.ok(on.querySelectorAll('main a').filter((a) => a.getAttribute('href') === 'https://app.hummlist.com').length >= 2);
  assert.ok(on.querySelector('main a[href="/datenschutz"]'));
  assert.ok(on.querySelector('main a[href="/support"]'));
  assert.ok(on.querySelector('main a[href="#test"]') && on.querySelector('#test'));
  const off = buildSite({ config: { privacyPublished: false, supportPublished: false } }).page('/de');
  assert.equal(off.querySelector('main a[href="/datenschutz"]'), null);
  assert.equal(off.querySelector('main a[href="/support"]'), null);
});

test('the illustrations are responsive pictures with their size, light and dark, wide and compact', () => {
  const { page } = buildSite();
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    const hero = doc.querySelector('.hero-visual picture');
    const img = hero.querySelector('img');
    assert.equal(img.getAttribute('src'), `/media/hero-${locale}-wide.webp`);
    assert.deepEqual([img.getAttribute('width'), img.getAttribute('height')], ['1000', '1080']);
    assert.equal(img.getAttribute('fetchpriority'), 'high');
    assert.equal(img.getAttribute('alt'), COPY.get('hero.image')[locale]);
    assert.deepEqual(hero.querySelectorAll('source').map((s) => [s.getAttribute('media'), s.getAttribute('srcset')]), [
      ['(max-width: 37.5rem) and (prefers-color-scheme: dark)', `/media/hero-${locale}-compact-dark.webp`],
      ['(max-width: 37.5rem)', `/media/hero-${locale}-compact.webp`],
      ['(prefers-color-scheme: dark)', `/media/hero-${locale}-wide-dark.webp`],
    ]);
    for (const name of [...SLOTS, 'stores']) {
      const card = doc.querySelector(`img[src="/media/${name}-${locale}-wide.webp"]`);
      assert.ok(card, name);
      assert.deepEqual([card.getAttribute('width'), card.getAttribute('height'), card.getAttribute('loading')], ['1152', '648', 'lazy'], name);
    }
  }
});

test('without its video files a demo slot shows its poster and no video', () => {
  const doc = buildSite().page('/de');
  assert.equal(doc.querySelectorAll('video').length, 0);
  for (const slot of SLOTS) {
    const figure = doc.querySelector(`figure[data-copy-id="demo.${slot}"]`);
    assert.equal(figure.querySelector('img').getAttribute('alt'), COPY.get(`demo.${slot}`).de);
    assert.equal(figure.querySelector('button'), null);
  }
});

test('with its video files a demo slot is a muted, looped, captioned video that loads nothing up front', () => {
  const publicDir = publicWith({ ...videoFiles('add-tick', 'de'), ...videoFiles('add-tick', 'en') });
  const { page } = buildSite({ publicDir });
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    const figure = doc.querySelector('figure[data-demo]');
    const video = figure.querySelector('video');
    for (const attr of ['muted', 'loop', 'playsinline', 'controls']) assert.ok(video.hasAttribute(attr), attr);
    assert.equal(video.getAttribute('preload'), 'none');
    assert.equal(video.hasAttribute('autoplay'), false, 'demo.js starts it only without reduced motion');
    assert.equal(video.getAttribute('poster'), `/media/add-tick-${locale}-wide.webp`);
    assert.equal(video.getAttribute('aria-label'), COPY.get('demo.add-tick')[locale]);
    assert.deepEqual(video.querySelectorAll('source').map((s) => [s.getAttribute('media'), s.getAttribute('src'), s.getAttribute('type')]), [
      ['(max-width: 37.5rem)', `/media/add-tick-${locale}-compact.webm`, 'video/webm'],
      ['(max-width: 37.5rem)', `/media/add-tick-${locale}-compact.mp4`, 'video/mp4'],
      [undefined, `/media/add-tick-${locale}-wide.webm`, 'video/webm'],
      [undefined, `/media/add-tick-${locale}-wide.mp4`, 'video/mp4'],
    ]);
    const track = video.querySelector('track');
    assert.deepEqual([track.getAttribute('kind'), track.getAttribute('srclang'), track.getAttribute('src')], ['captions', locale, `/media/add-tick-${locale}.vtt`]);
    assert.equal(figure.querySelector('picture').getAttribute('aria-hidden'), 'true', 'the video carries the description');
    const button = figure.querySelector('button.demo-toggle');
    assert.ok(button.hasAttribute('hidden'), 'demo.js shows the button');
    assert.equal(button.getAttribute('aria-label'), COPY.get('demo.play')[locale]);
    assert.equal(button.getAttribute('data-pause'), COPY.get('demo.pause')[locale]);
    assert.equal(doc.querySelectorAll('video').length, 1, 'the other slots still show posters');
  }
});

test('half a video set, a missing poster or a poster of the wrong shape fails the build', () => {
  const fails = (files, pattern) => assert.throws(() => buildSite({ publicDir: publicWith(files) }), pattern);
  fails({ 'media/mcp-chat-en-wide.mp4': 'video' }, /mcp-chat-en has mcp-chat-en-wide\.mp4 but not .*mcp-chat-en-wide\.webm/);
  fails({ ...videoFiles('mcp-chat', 'en'), 'media/mcp-chat-en.vtt': null }, /but not mcp-chat-en\.vtt/);
  fails({ ...videoFiles('mcp-chat', 'en'), 'media/mcp-chat-en.vtt': 'WEBVTT\n' }, /mcp-chat-en\.vtt has no cues; a demo video ships with its captions/);
  fails({ 'media/stores-en-compact.webp': null }, /public\/media\/stores-en-compact\.webp is missing/);
  fails({ 'media/add-tick-de-wide.webp': webp(1000, 1000) }, /add-tick-de-wide\.webp is 1000x1000; a wide poster must be 16:9/);
  fails({ 'media/add-tick-de-compact-dark.webp': webp(716, 800) }, /compact-dark\.webp is 716x800; a compact poster must be 4:5/);
  fails({ 'media/stores-de-wide.webp': 'not an image' }, /stores-de-wide\.webp is not a WebP image/);
});

test('a demo poster without a dark variant shows the light one in dark mode', () => {
  const { page } = buildSite({ publicDir: publicWith({ 'media/stores-de-wide-dark.webp': null }) });
  const sources = page('/de').querySelectorAll('figure[data-copy-id="feature.stores.image"] source').map((s) => s.getAttribute('srcset'));
  assert.ok(!sources.includes('/media/stores-de-wide-dark.webp'));
  assert.ok(sources.includes('/media/stores-de-compact-dark.webp'));
});

test('the HTML check allows only script files of this site and resources that exist', () => {
  const { outDir } = buildSite();
  const check = (body) => checkHtml(join(outDir, 'x.html'), `<html><body><h1>T</h1>${body}</body></html>`, outDir, SITE);
  assert.doesNotThrow(() => check('<script src="/demo.js" defer></script><img src="/media/hero-de-wide.webp" alt="A"><a href="#t" id="t">t</a>'));
  assert.throws(() => check('<script>alert(1)</script>'), /<script> is allowed only as a file from this site/);
  assert.throws(() => check('<script src="https://cdn.example/x.js"></script>'), /external resource https:\/\/cdn\.example\/x\.js/);
  assert.throws(() => check('<video poster="/media/nope.webp"></video>'), /missing resource \/media\/nope\.webp/);
  assert.throws(() => check('<video><track src="/media/nope.vtt"></video>'), /missing resource \/media\/nope\.vtt/);
  assert.throws(() => check('<a href="#nowhere">x</a>'), /link #nowhere has no target on the page/);
});

test('served like Vercel: the landing pages answer 200 with noindex, slashes and .html redirect', async () => {
  const { outDir } = buildSite();
  const res = await serve(outDir, ['/de', '/en', '/de/', '/en.html', '/demo.js', '/landing.css', '/media/hero-en-compact.webp', '/media/README.md']);
  for (const path of ['/de', '/en']) {
    assert.equal(res[path].status, 200, path);
    assert.equal(res[path].headers['x-robots-tag'], 'noindex', path);
    assert.match(res[path].body, /<h1 /, path);
  }
  assert.deepEqual([res['/de/'].status, res['/de/'].headers.location], [308, '/de']);
  assert.deepEqual([res['/en.html'].status, res['/en.html'].headers.location], [308, '/en']);
  assert.match(res['/demo.js'].headers['content-type'], /javascript/);
  assert.equal(res['/media/hero-en-compact.webp'].headers['content-type'], 'image/webp');
  for (const path of Object.keys(res)) assert.equal(res[path].headers['x-robots-tag'], 'noindex', path);
});

test('production builds the landing pages too, without drafts or placeholders', () => {
  const { routes, page } = buildSite({ env: PROD });
  assert.ok(routes.includes('/de') && routes.includes('/en'));
  assert.doesNotMatch(page('/de').toString(), /ENTWURF|noindex/);
});
