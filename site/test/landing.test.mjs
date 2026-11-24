import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, publicWith, alternates, meta, serve, stageBuild, SITE_DIR, CONTENT_DIR } from './helpers.mjs';
import { parseCopy } from '../landing.mjs';
import { checkHtml } from '../build.mjs';
import { copyNeeded, readVideoCopy } from '../scripts/copy-needed.mjs';

const SITE = 'https://snacklist.app';
const COPY_TEXT = readFileSync(join(CONTENT_DIR, 'landing/copy.yml'), 'utf8');
const COPY = parseCopy(COPY_TEXT, 'copy.yml');
const PROD = { VERCEL_ENV: 'production' };
const SLOTS = ['add-tick', 'household-sync', 'mcp-chat', 'voice-add'];

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
// The same file names removed: the slot falls back to its poster.
const withoutVideos = (slots) => Object.fromEntries(
  slots.flatMap((slot) => ['de', 'en'].flatMap((locale) => Object.keys(videoFiles(slot, locale)).map((f) => [f, null]))),
);

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

test('every copy id is on a landing page of some stage or a mail-link page with its text, and every string on them has an id', () => {
  const builds = ['waitlist', 'beta', 'launch'].map((stage) => stageBuild(stage).page);
  const routes = { de: ['/de/warteliste/bestaetigen', '/de/warteliste/abmelden'], en: ['/en/waitlist/confirm', '/en/waitlist/unsubscribe'] };
  for (const locale of ['de', 'en']) {
    const docs = [...builds.map((page) => page(`/${locale}`)), ...routes[locale].map(builds[0])];
    const seen = new Set(docs.flatMap((doc) => doc.querySelectorAll('[data-copy-id]').map((el) => el.getAttribute('data-copy-id'))));
    // The play and pause labels sit on the button of a slot with a video (tested below); the
    // email placeholder is an attribute; titles and descriptions are in the head.
    const elsewhere = ['meta.title', 'meta.description', 'demo.play', 'demo.pause', 'waitlist.form.email-placeholder', /\.(meta-title|description)$/];
    const unseen = [...COPY.keys()].filter((id) => !seen.has(id) && !elsewhere.some((e) => (typeof e === 'string' ? e === id : e.test(id))));
    assert.deepEqual(unseen, [], locale);
    for (const doc of docs) {
      for (const el of doc.querySelectorAll('main [data-copy-id]')) {
        const entry = COPY.get(el.getAttribute('data-copy-id'));
        const plain = entry[locale].replace(/\*\*|\[|\]\([^)]*\)/g, '');
        const shown = el.querySelector('img')?.getAttribute('alt') ?? el.text;
        assert.equal(shown.trim(), plain, el.getAttribute('data-copy-id'));
      }
      const text = (el) => el.childNodes.filter((n) => n.nodeType === 3).map((n) => n.text).join('').trim();
      // Legal's consent texts come from content/legal/consent/ (data-legal names the version).
      const loose = doc.querySelectorAll('main *').filter((el) => text(el) !== '' && !el.closest('[data-copy-id], [data-legal]'));
      assert.deepEqual(loose.map((el) => `${el.tagName} ${text(el)}`), [], `${locale}: text without a copy id`);
    }
  }
});

test('copy.yml must give both languages, a status and a source, and every id must be used', () => {
  const broken = (text, pattern) => assert.throws(() => buildSite({ files: { 'landing/copy.yml': text } }), pattern);
  broken(COPY_TEXT.replace('  en: "Quick to add, quick to tick off"\n', ''), /feature\.list\.title: "en" must be a non-empty string/);
  broken(COPY_TEXT.replace(/(hero\.title:\n(?: {2}.*\n)*?) {2}status: draft/, '$1  status: final'), /hero\.title: "status" must be draft or reused/);
  broken(`${COPY_TEXT}\nhero.extra:\n  de: "x"\n  en: "x"\n  status: draft\n  source: "x"\n`, /copy ids not used on the landing page: hero\.extra/);
  broken(COPY_TEXT.replace(/hero\.lead:\n(?: {2}.*\n)*/, ''), /copy id "hero\.lead" is used by the landing page but missing/);
});

test('COPY_NEEDED.md is generated from copy.yml and lists every draft', () => {
  const file = readFileSync(join(SITE_DIR, 'COPY_NEEDED.md'), 'utf8');
  assert.equal(file, copyNeeded(COPY, readVideoCopy()), 'stale: run node site/scripts/copy-needed.mjs');
  for (const [id, entry] of COPY) {
    if (entry.status === 'draft') assert.match(file, new RegExp(`\\| \`${id.replaceAll('.', '\\.')}\` \\|.*\\| draft \\|`), id);
  }
  assert.equal(COPY.get('voice.siri.now').status, 'draft');
});

test('the landing pages promise nothing that is not there: no prices, no Watch, no ChatGPT, Alexa only in its card and trademark line', () => {
  const { page } = buildSite({ env: PROD });
  for (const locale of ['de', 'en']) {
    const body = page(`/${locale}`).querySelector('body');
    const text = body.text;
    assert.doesNotMatch(text, /€|\$|\bpreis|\bprice|premium|lifetime|abo\b|subscription|kostenlos|\bfree\b/i, locale);
    assert.doesNotMatch(text, /apple watch|chatgpt|openai|gemini/i, locale);
    for (const el of body.querySelectorAll('.assistant--alexa, footer .marks')) el.remove();
    assert.doesNotMatch(body.text, /alexa/i, locale);
    assert.doesNotMatch(text, /\bhumm\b(?!list)|biene|\bbee\b/i, locale);
    assert.doesNotMatch(text, /\[PETER/, locale);
  }
});

test('Siri promises no date and links the shortcut guide that works today', () => {
  const { page } = buildSite();
  for (const [locale, guide] of [['de', '/de/anleitungen/siri-kurzbefehl'], ['en', '/en/guides/siri-shortcut']]) {
    const card = page(`/${locale}`).querySelector('.assistant--siri');
    assert.doesNotMatch(card.text, /\bbald\b|\bsoon\b/i, locale);
    assert.ok(card.querySelectorAll('a').some((a) => a.getAttribute('href') === guide), locale);
  }
});

test('the landing pages hold no date but the badge\'s beta month, no app instructions and no invite validity (Peter, 2026-11-03 and 2026-11-05)', () => {
  for (const stage of ['waitlist', 'beta', 'launch']) {
    const { page } = stageBuild(stage);
    for (const locale of ['de', 'en']) {
      const doc = page(`/${locale}`);
      const badge = doc.querySelector('[data-copy-id="hero.badge"]');
      if (stage === 'launch') assert.equal(badge, null);
      else assert.equal(badge.text, { de: 'Jetzt in der Beta', en: 'Now in beta' }[locale]);
      const text = `${doc.querySelector('head').toString()} ${doc.querySelector('body').text.replace(badge?.text ?? '', '')}`;
      assert.doesNotMatch(text, /januar|februar|märz|april|\bmai\b|juni|juli|august|september|oktober|november|dezember|january|february|march|\bmay\b|june|july|october|december/i, `${stage} ${locale}: a month`);
      // "as soon as you are back online" describes the offline sync, it promises nothing.
      assert.doesNotMatch(text, /\bbald\b|(?<!as )\bsoon\b/i, `${stage} ${locale}: a "soon"`);
      // Legal's consent text names the 7-day deletion of unconfirmed sign-ups; that one stays.
      assert.doesNotMatch(text, /Einladung gilt[^.]*(sieben|7) Tage|invit\w* (is )?valid for (seven|7) days/i, `${stage} ${locale}: the invite validity`);
      assert.doesNotMatch(text, /in der App unter|in the app under|›/, `${stage} ${locale}: an app instruction`);
    }
  }
});

test('the founder note sits between the privacy block and the sign-up form, brand-free, and leaves with the beta at launch', () => {
  for (const stage of ['waitlist', 'beta', 'launch']) {
    const { page } = stageBuild(stage);
    for (const locale of ['de', 'en']) {
      const doc = page(`/${locale}`);
      const sections = doc.querySelectorAll('main > section').map((s) => s.getAttribute('class'));
      const note = doc.querySelector('.founder-section');
      if (stage === 'launch') {
        assert.equal(note, null, `${stage} ${locale}`);
        continue;
      }
      assert.deepEqual(sections.slice(-3), ['section privacy-section', 'section founder-section', 'section test-section'], `${stage} ${locale}`);
      assert.equal(note.querySelector('h2').text, { de: 'Von Peter', en: 'From Peter' }[locale]);
      assert.match(note.querySelector('p').text, /MCP.*Beta|MCP.*beta/s);
      assert.match(note.querySelector('p').text, /— Peter$/);
      assert.doesNotMatch(note.text, /Claude|Anthropic|ChatGPT|OpenAI/);
    }
  }
});

test('no call to action links the web app, the hero leads to the form, and the privacy and help links follow their flags', () => {
  const on = buildSite().page('/de');
  assert.deepEqual(on.querySelectorAll('a').filter((a) => /app\.snacklist\.app/.test(a.getAttribute('href'))).length, 0);
  assert.ok(on.querySelector('main a[href="/datenschutz"]'));
  assert.ok(on.querySelector('main a[href="/support"]'));
  assert.ok(on.querySelector('.hero-actions a[href="#warteliste"]') && on.querySelector('#test #warteliste form'));
  const off = buildSite({ config: { privacyPublished: false, supportPublished: false } }).page('/de');
  // The consent text under the button always links the policy; the privacy block follows the flag.
  assert.equal(off.querySelector('.privacy a[href="/datenschutz"]'), null);
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
    for (const name of SLOTS) {
      const card = doc.querySelector(`img[src="/media/${name}-${locale}-wide.webp"]`);
      assert.ok(card, name);
      assert.deepEqual([card.getAttribute('width'), card.getAttribute('height'), card.getAttribute('loading')], ['1152', '648', 'lazy'], name);
    }
  }
});

test('without its video files a demo slot shows its poster and no video', () => {
  const doc = buildSite({ publicDir: publicWith(withoutVideos(SLOTS)) }).page('/de');
  assert.equal(doc.querySelectorAll('video').length, 0);
  for (const slot of SLOTS) {
    const figure = doc.querySelector(`figure[data-copy-id="demo.${slot}"]`);
    assert.equal(figure.querySelector('img').getAttribute('alt'), COPY.get(`demo.${slot}`).de);
    assert.equal(figure.querySelector('button'), null);
  }
});

test('with its video files a demo slot is a muted, looped, captioned video that loads nothing up front', () => {
  const publicDir = publicWith({ ...withoutVideos(SLOTS.filter((s) => s !== 'add-tick')), ...videoFiles('add-tick', 'de'), ...videoFiles('add-tick', 'en') });
  const { page } = buildSite({ publicDir });
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    const figure = doc.querySelector('figure[data-demo]');
    const video = figure.querySelector('video');
    for (const attr of ['muted', 'loop', 'playsinline', 'controls']) assert.ok(video.hasAttribute(attr), attr);
    assert.equal(video.getAttribute('preload'), 'none');
    assert.equal(video.hasAttribute('autoplay'), false, 'demo.js starts it only without reduced motion');
    // The lazy, responsive <picture> is the poster; a poster attribute would fetch the wide image
    // on phones before anything else (Lighthouse mobile LCP 3.1 s -> 4.0 s, job 54).
    assert.equal(video.hasAttribute('poster'), false);
    assert.equal(video.getAttribute('aria-label'), COPY.get('demo.add-tick')[locale]);
    assert.deepEqual(video.querySelectorAll('source').map((s) => [s.getAttribute('media'), s.getAttribute('src'), s.getAttribute('type')]), [
      ['(max-width: 37.5rem)', `/media/add-tick-${locale}-compact.webm`, 'video/webm'],
      ['(max-width: 37.5rem)', `/media/add-tick-${locale}-compact.mp4`, 'video/mp4'],
      [undefined, `/media/add-tick-${locale}-wide.webm`, 'video/webm'],
      [undefined, `/media/add-tick-${locale}-wide.mp4`, 'video/mp4'],
    ]);
    const track = video.querySelector('track');
    assert.deepEqual([track.getAttribute('kind'), track.getAttribute('srclang'), track.getAttribute('src')], ['captions', locale, `/media/add-tick-${locale}.vtt`]);
    // The words are in the picture; a default track would draw them a second time over it (job 54).
    assert.equal(track.hasAttribute('default'), false);
    assert.equal(figure.querySelector('picture').getAttribute('aria-hidden'), 'true', 'the video carries the description');
    const button = figure.querySelector('button.demo-toggle');
    assert.ok(button.hasAttribute('hidden'), 'demo.js shows the button');
    assert.equal(button.getAttribute('aria-label'), COPY.get('demo.play')[locale]);
    assert.equal(button.getAttribute('data-pause'), COPY.get('demo.pause')[locale]);
    assert.equal(doc.querySelectorAll('video').length, 1, 'the other slots still show posters');
  }
});

test('every demo slot names where its play button sits, wide and compact, off the add field (job 150)', () => {
  const doc = buildSite().page('/de');
  for (const slot of SLOTS) {
    const figure = doc.querySelector(`figure[data-copy-id="demo.${slot}"]`);
    assert.match(figure.getAttribute('data-toggle-wide') ?? '', /^(br|bl|tr)$/, `${slot} wide`);
    assert.match(figure.getAttribute('data-toggle-compact') ?? '', /^(br|bl|ur|mr)$/, `${slot} compact`);
  }
});

test('the shipped demo videos fill all four slots in both languages', () => {
  const { page } = buildSite();
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    for (const slot of SLOTS) {
      const video = doc.querySelector(`figure[data-copy-id="demo.${slot}"] video`);
      assert.ok(video, `${slot} ${locale} is a video`);
      assert.equal(video.querySelector('track').getAttribute('src'), `/media/${slot}-${locale}.vtt`);
    }
  }
});

test('half a video set, a missing poster or a poster of the wrong shape fails the build', () => {
  const fails = (files, pattern) => assert.throws(() => buildSite({ publicDir: publicWith(files) }), pattern);
  fails({ 'media/mcp-chat-en-wide.webm': null }, /mcp-chat-en has .*mcp-chat-en-wide\.mp4.* but not mcp-chat-en-wide\.webm/);
  fails({ 'media/mcp-chat-en.vtt': null }, /but not mcp-chat-en\.vtt/);
  fails({ 'media/mcp-chat-en.vtt': 'WEBVTT\n' }, /mcp-chat-en\.vtt has no cues; a demo video ships with its captions/);
  fails({ 'media/hero-en-compact.webp': null }, /public\/media\/hero-en-compact\.webp is missing/);
  fails({ 'media/add-tick-de-wide.webp': webp(1000, 1000) }, /add-tick-de-wide\.webp is 1000x1000; a wide poster must be 16:9/);
  fails({ 'media/add-tick-de-compact-dark.webp': webp(716, 800) }, /compact-dark\.webp is 716x800; a compact poster must be 4:5/);
  fails({ 'media/add-tick-de-wide.webp': 'not an image' }, /add-tick-de-wide\.webp is not a WebP image/);
});

test('a poster without a dark variant shows the light one in dark mode', () => {
  const { page } = buildSite({ publicDir: publicWith({ 'media/hero-de-wide-dark.webp': null }) });
  const sources = page('/de').querySelectorAll('.hero-visual source').map((s) => s.getAttribute('srcset'));
  assert.ok(!sources.includes('/media/hero-de-wide-dark.webp'));
  assert.ok(sources.includes('/media/hero-de-compact-dark.webp'));
});

test('the stores card renders the stores with the supermarket first and a pressed button, ready for stores.js', () => {
  const { page } = buildSite();
  const home = ['market', 'bakery', 'supermarket', 'drugstore'];
  const routes = Object.fromEntries(home.map((store) => [store, [store, ...home.filter((s) => s !== store)]]));
  for (const locale of ['de', 'en']) {
    const doc = page(`/${locale}`);
    const card = doc.querySelector('.feature [data-stores]');
    assert.equal(card.querySelector('[role="group"]').getAttribute('aria-labelledby'), 'store-pick');
    const buttons = card.querySelectorAll('button');
    assert.deepEqual(buttons.map((b) => b.querySelector('[data-copy-id]').getAttribute('data-copy-id').split('.').at(-1)), home, locale);
    assert.deepEqual(buttons.map((b) => [b.getAttribute('type'), b.getAttribute('aria-pressed')]), [['button', 'false'], ['button', 'false'], ['button', 'true'], ['button', 'false']], locale);
    for (const b of buttons) {
      const store = b.querySelector('[data-copy-id]').getAttribute('data-copy-id').split('.').at(-1);
      assert.equal(b.getAttribute('data-route'), routes[store].join(' '), store);
    }
    const list = card.querySelector('ol.store-route');
    assert.equal(list.getAttribute('aria-labelledby'), 'store-supermarket');
    assert.equal(card.querySelector('#store-supermarket').text, COPY.get('feature.stores.store.supermarket')[locale]);
    assert.deepEqual(list.querySelectorAll('li').map((li) => li.getAttribute('data-store')), routes.supermarket, 'without JS the supermarket comes first, the others in their order');
    for (const li of list.querySelectorAll('li')) {
      assert.equal(li.querySelector('[data-copy-id]').getAttribute('data-copy-id'), `feature.stores.store.${li.getAttribute('data-store')}`);
    }
    assert.ok(doc.querySelector('script[type="module"][src="/stores.js"]'), 'stores.js ships with the landing page');
  }
});

test('the stores card shows no category: the app hides categories', () => {
  assert.deepEqual([...COPY.keys()].filter((id) => id.startsWith('feature.stores.category.')), []);
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
