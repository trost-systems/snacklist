// The Snacklist skill for Alexa on the site (Legal N-366): the trademark line on every page that
// names Alexa, only utterances the certified skill understands, the skill URLs from one place and
// config.json's alexaPublished toggle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, htmlRoutes, stageBuild, REPO_DIR, SITE_DIR } from './helpers.mjs';
import { ALEXA_SKILL_URLS } from '../config/stores.mjs';
import { MARKS } from '../build.mjs';

const ALEXA_MARK = MARKS.find(({ mark }) => mark.test('Alexa'));
const ALEXA_DOC = readFileSync(join(REPO_DIR, 'docs/ALEXA.md'), 'utf8').replace(/\s+/g, ' ').toLowerCase();
const words = (s) => s.toLowerCase().replace(/[,.!?]/g, '').replace(/\s+/g, ' ').trim();

// The certified build's sample utterances, per model, as patterns over words.
const samplesOf = (model) =>
  JSON.parse(readFileSync(join(REPO_DIR, `alexa/skill-package/interactionModels/custom/${model}.json`), 'utf8'))
    .interactionModel.languageModel.intents.flatMap((i) => i.samples)
    .map((sample) => new RegExp(`^${words(sample).split(' ').map((w) => (w.startsWith('{') ? '.+' : w.replace(/'/g, "['’]"))).join(' ')}$`));
const SAMPLES = { de: samplesOf('de-DE'), en: samplesOf('en-US') };

// How a sentence reaches the skill, as docs/ALEXA.md names it: an invocation with a request the
// model knows, or the launch phrase alone. The own-list sentences are the guides' "don't say" examples.
const INVOCATIONS = [
  { doc: 'alexa, sag snacklist', pattern: /^sag snacklist (.+)$/, model: 'de' },
  { doc: 'alexa, frag snacklist', pattern: /^frag snacklist (.+)$/, model: 'de' },
  { doc: 'alexa, ask snacklist', pattern: /^ask snacklist (?:to )?(.+)$/, model: 'en' },
  { doc: 'alexa, tell snacklist', pattern: /^tell snacklist (?:to )?(.+)$/, model: 'en' },
  { doc: 'alexa, öffne snacklist', pattern: /^öffne snacklist$/ },
  { doc: 'alexa, open snacklist', pattern: /^open snacklist$/ },
];
const OWN_LIST = ['alexa, setz milch auf die snacklist', 'alexa, add milk to snacklist'];

function understood(utterance) {
  const said = words(utterance.replace(/^Alexa,/, ''));
  if (OWN_LIST.some((u) => words(u) === `alexa ${said}`)) return true;
  // „Alexa, sag Snacklist, …“: the form itself, what follows left open.
  if (said.endsWith('…')) return INVOCATIONS.some(({ doc }) => words(doc) === `alexa ${said.slice(0, -1).trim()}`);
  return INVOCATIONS.some(({ pattern, model }) => {
    const m = pattern.exec(said);
    return m && (!model || SAMPLES[model].some((s) => s.test(m[1])));
  });
}

const sites = { waitlist: buildSite(), launch: stageBuild('launch') };

// Every page's text, tags as line breaks, with its footer's trademark lines.
function pages(site) {
  return htmlRoutes(site.outDir).map((route) => {
    const doc = site.page(route);
    for (const el of doc.querySelectorAll('script, style')) el.remove();
    const body = doc.querySelector('body');
    return { route, lang: doc.querySelector('html').getAttribute('lang'), doc, text: body ? body.innerHTML.replace(/<[^>]*>/g, '\n').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&') : '' };
  });
}

test('the invocation forms and own-list sentences are the ones docs/ALEXA.md names', () => {
  for (const { doc } of INVOCATIONS) assert.ok(ALEXA_DOC.includes(doc), `docs/ALEXA.md names „${doc}“`);
  for (const sentence of OWN_LIST) assert.ok(ALEXA_DOC.includes(sentence), `docs/ALEXA.md names „${sentence}“`);
  assert.ok(understood('Alexa, sag Snacklist, füg Milch und Eier hinzu'));
  assert.ok(understood("Alexa, ask Snacklist what's on the list"));
  assert.ok(!understood('Alexa, sag Snacklist, bestell Milch'), 'a request the model lacks');
  assert.ok(!understood('Alexa, deaktiviere Snacklist'), 'not in docs/ALEXA.md');
  assert.ok(understood('Alexa, sag Snacklist, …'), 'the form');
  assert.ok(!understood('Alexa, setz …'), 'no form');
});

test('every page naming Alexa carries Amazon\'s trademark line in its language, in the page and its Markdown twin', () => {
  for (const [stage, site] of Object.entries(sites)) {
    let named = 0;
    for (const { route, lang, doc, text } of pages(site)) {
      const marks = doc.querySelectorAll('footer .marks').map((p) => p.text);
      const main = text.replace(marks.join('\n'), '');
      if (!/alexa/i.test(main) || !doc.querySelector('footer')) continue;
      named++;
      assert.deepEqual(marks, [ALEXA_MARK[lang]], `${stage} ${route}`);
      const twin = readFileSync(join(site.outDir, `${route.slice(1)}.md`), 'utf8');
      assert.ok(twin.includes(ALEXA_MARK[lang]), `${stage} ${route}.md`);
    }
    assert.ok(named >= 10, `${stage}: ${named} pages name Alexa`);
  }
  assert.equal(ALEXA_MARK.de, 'Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.');
  assert.equal(ALEXA_MARK.en, 'Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates.');
  assert.equal(sites.waitlist.page('/en/changelog').querySelector('footer .marks'), null, 'a page without Alexa has no line');
});

test('no page says "Hey Alexa", and every "Alexa, …" works as written in the certified skill', () => {
  for (const [stage, site] of Object.entries(sites)) {
    let checked = 0;
    for (const { route, text } of pages(site)) {
      assert.doesNotMatch(text, /hey,? alexa/i, `${stage} ${route}`);
      for (const [, utterance] of text.matchAll(/(?:^[ \t]*|[„“"]|:\s+)(Alexa,[^“”"\n]*)/gm)) {
        checked++;
        assert.ok(understood(utterance.replace(/[.?!]\s*$/, '')), `${stage} ${route}: „${utterance}“ is not a sentence the skill understands (docs/ALEXA.md, the interaction models)`);
      }
    }
    assert.ok(checked >= 30, `${stage}: ${checked} utterances checked`);
  }
});

test('the skill URLs come from config/stores.mjs: the landing card and the help pages link them', () => {
  assert.deepEqual(ALEXA_SKILL_URLS, { de: 'https://www.amazon.de/dp/B0HRTTRGZ2', en: 'https://www.amazon.com/dp/B0HRTTRGZ2' });
  assert.equal(JSON.parse(readFileSync(join(SITE_DIR, 'config.json'), 'utf8')).alexaPublished, true, 'the skill is live: the Alexa wording is on');
  for (const [locale, support] of [['de', '/support'], ['en', '/en/support']]) {
    const card = sites.waitlist.page(`/${locale}`).querySelector('.assistant--alexa');
    assert.ok(card, `${locale}: the Alexa card`);
    assert.equal(card.querySelector('[data-copy-id="voice.alexa.store"]').getAttribute('href'), ALEXA_SKILL_URLS[locale]);
    assert.equal(card.querySelectorAll('img, svg, picture, video').length, 0, 'text only: no logo, badge or device');
    assert.match(card.text, locale === 'de' ? /Mit dem Snacklist-Skill für Alexa kannst du/ : /With the Snacklist skill for Alexa you can/);
    const links = sites.waitlist.page(support).querySelectorAll('main a').filter((a) => a.text === 'Alexa Skill Store');
    assert.deepEqual(links.map((a) => a.getAttribute('href')), [ALEXA_SKILL_URLS[locale]], `${support}`);
    assert.match(sites.waitlist.page(support).querySelector('main').text, locale === 'de' ? /mit dem Snacklist-Skill für Alexa\./ : /with the Snacklist skill for Alexa\./);
  }
  assert.throws(() => buildSite({ files: { 'guides/de/alexa.md': readFileSync(join(SITE_DIR, 'content/guides/de/alexa.md'), 'utf8').replace('alexa-skill:de', 'alexa-skill:fr') } }), /link alexa-skill:fr: config\/stores\.mjs has skill URLs for de, en/);
});

test('alexaPublished off renders the landing page without the Alexa card and the help pages without the skill link', () => {
  const off = buildSite({ config: { alexaPublished: false } });
  for (const [locale, support] of [['de', '/support'], ['en', '/en/support']]) {
    const landing = off.page(`/${locale}`);
    assert.equal(landing.querySelector('.assistant--alexa'), null);
    assert.doesNotMatch(landing.querySelector('main').text, /alexa/i);
    assert.equal(landing.querySelector('footer .marks'), null);
    const main = off.page(support).querySelector('main');
    assert.equal(main.querySelectorAll('a').filter((a) => (a.getAttribute('href') ?? '').includes('amazon.')).length, 0);
    assert.match(main.text, locale === 'de' ? /Den Skill findest du im Alexa Skill Store\./ : /You find the skill in the Alexa Skill Store\./);
  }
});
