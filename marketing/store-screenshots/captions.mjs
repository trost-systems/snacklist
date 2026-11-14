// captions.yaml read and checked once: the words of a locale for one store and one assistants
// variant, and the rules no caption may break (docs/STORE_SCREENSHOTS.md, "Checks").
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { LOCALES, SHOTS } from './sets.mjs';

const FILE = join(import.meta.dirname, 'captions.yaml');
/** Each variant and, in order, what a shot without it shows instead. */
const FALLBACK = { neutral: ['neutral'], named: ['named', 'neutral'], 'named_siri': ['named_siri', 'neutral'] };
export const VARIANTS = Object.keys(FALLBACK);
const ALT_MAX = 140;

/** AI assistants and their makers (Legal N-80..N-86): never in a caption or on a shown screen. */
export const AI_BRANDS = /\b(chatgpt|openai|claude|anthropic|gemini|copilot|perplexity|mistral|llama|grok)\b/i;

// What no caption, alt text or sticker may say. Brand and chain names match whole words.
const FORBIDDEN = [
  [/premium/i, 'Premium'],
  [/[€$£]|\bpreis|\bprice|\bkostenlos|\bgratis|\bfree\b/i, 'a price or "free"'],
  [/\b(beste[nrs]?|best|nr\.? ?1|no\.? ?1|#1|top|neu|new)\b/i, '„beste“, „Nr. 1“, „Top“ or „Neu“'],
  [/\b(lidl|aldi|edeka|rewe|kaufland|penny|netto|rossmann|dm|norma|globus|tegut|walmart|target|kroger|costco|safeway|publix|whole foods|trader joe'?s|amazon fresh|instacart)\b/i, 'a retailer'],
  [AI_BRANDS, 'an AI brand'],
  [/humm/i, 'the old product name'],
  [/works with (amazon )?alexa|funktioniert mit (amazon )?alexa/i, 'Amazon\'s device programme "Works with Alexa"'],
  [/snack[\s­-]+list|snackl\b/i, 'a split or shortened "Snacklist"'],
];
// Allowed only in these variants, or on a shot whose `may_name` lists the word.
const NAMED = [[/\bsiri\b/i, ['named', 'named_siri']], [/\balexa\b/i, ['named', 'named_siri']], [/\bmcp\b/i, ['named']], [/\bapi\b/i, []]];

const all = parse(readFileSync(FILE, 'utf8'));

/**
 * Every rule a text breaks, in a variant (or none for words outside the variants), on a store,
 * for a shot that may name `mayName`; `premium` lets the Premium label through.
 */
export function textProblems(text, variant, { store, mayName = [], premium = false } = {}) {
  const problems = FORBIDDEN.filter(([re, what]) => re.test(text) && !(premium && what === 'Premium')).map(([, what]) => `names ${what}`);
  for (const [re, allowed] of NAMED) {
    const word = re.source.replace(/\\b/g, '');
    if (re.test(text) && !allowed.includes(variant) && !mayName.some((w) => w.toLowerCase() === word)) problems.push(`names ${word} outside ${allowed.join('/') || 'a shot that may name it'}`);
  }
  if (store === 'play' && /\bsiri\b/i.test(text)) problems.push('names Siri on Play (Android has no Siri)');
  return problems;
}

const strings = (value) => (typeof value === 'string' ? [value] : Object.values(value ?? {}).flatMap(strings));

/** Every problem in captions.yaml, for every locale, store and variant. */
export function captionProblems() {
  const problems = [];
  for (const locale of Object.keys(LOCALES)) {
    const doc = all[locale];
    if (!doc) {
      problems.push(`${locale}: missing`);
      continue;
    }
    const ids = Object.keys(doc.shots ?? {});
    if (ids.join() !== SHOTS.join()) problems.push(`${locale}: shots are ${ids.join(', ')}, sets.mjs has ${SHOTS.join(', ')} (store order)`);
    for (const variant of VARIANTS) {
      for (const store of ['play', 'appstore']) {
        const words = captionsFor(locale, { assistants: variant, store });
        for (const [id, c] of Object.entries(words)) {
          const where = `${locale} ${id} (${variant}, ${store})`;
          if (id !== 'feature' && (!Array.isArray(c.h) || c.h.length !== 2 || !c.s)) problems.push(`${where}: needs h as two lines and s`);
          if (!c.alt || c.alt.length > ALT_MAX) problems.push(`${where}: alt text missing or over ${ALT_MAX} characters`);
          if (!['draft', 'approved'].includes(c.status)) problems.push(`${where}: status must be draft or approved`);
          // Sticker words do not change with the variant: they must pass as neutral.
          const rules = { store, mayName: c.may_name ?? [] };
          for (const t of strings({ h: c.h, s: c.s, alt: c.alt, tagline: c.tagline })) problems.push(...textProblems(t, c.variant, rules).map((p) => `${where}: "${t}" ${p}`));
          if (c.premium) problems.push(...textProblems(c.premium, c.variant, { ...rules, premium: true }).map((p) => `${where} premium label: "${c.premium}" ${p}`));
          if (c.sticker && Object.values(c.sticker).some((v) => v === null || v === undefined)) problems.push(`${where}: a sticker key without a value (quote text with commas)`);
          for (const t of strings(c.sticker)) problems.push(...textProblems(t, 'neutral', { store }).map((p) => `${where} sticker: "${t}" ${p}`));
        }
      }
    }
  }
  return [...new Set(problems)];
}

/**
 * The words of a locale's shots for one store, with the assistants variant applied: a shot with
 * variants gets the chosen one or the first of its FALLBACK it has, and on Play a variant's
 * `play:` replaces its own fields, or names the variant Play shows instead. `feature` holds the
 * feature graphic's words.
 */
export function captionsFor(locale, { assistants = 'neutral', store }) {
  if (!VARIANTS.includes(assistants)) throw new Error(`unknown assistants variant ${assistants} (${VARIANTS.join(', ')})`);
  const doc = all[locale];
  const out = {};
  for (const [id, { variants, ...base }] of Object.entries(doc.shots)) {
    if (!variants) {
      out[id] = { ...base, variant: null };
      continue;
    }
    let name = FALLBACK[assistants].find((v) => variants[v]);
    let { play, ...chosen } = variants[name];
    if (store === 'play' && typeof play === 'string') {
      name = play;
      ({ play, ...chosen } = variants[name]);
    }
    out[id] = { ...base, ...chosen, ...(store === 'play' && play ? play : {}), variant: name };
  }
  out.feature = { ...doc.feature, variant: null };
  return out;
}
