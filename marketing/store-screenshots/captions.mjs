// captions.yaml read and checked once: the words of a locale for one store, and the rules no
// caption may break (docs/STORE_SCREENSHOTS.md, "Checks").
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { LOCALES, SHOTS } from './sets.mjs';

const FILE = join(import.meta.dirname, 'captions.yaml');
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
  [/alexa/i, 'Alexa (N-187: the skill is not live)'],
  [/\bapi\b|automation|\bmcp\b/i, 'the API, automations or MCP (N-194)'],
  [/\bhey siri\b|\beinfach\b|\bohne einrichtung\b|\bjust (say|ask)\b|\bno setup\b/i, '"Hey Siri" or a no-setup claim (N-189)'],
  [/[™®©]/, 'a trademark sign (N-189)'],
  [/\b\d+ (listen|lists)\b|\b(maximal|max\.?|bis zu|up to|limit)\b/i, 'a list cap'],
  [/\b(bier|wein|sekt|prosecco|vodka|whisk(e)?y|likör|schnaps|alkohol|tabak|zigarette[n]?|beer|wine|liquor|alcohol|tobacco|cigarette[s]?)\b/i, 'alcohol or tobacco (age 4+)'],
  [/snack[\s­-]+list|snackl\b/i, 'a split or shortened "Snacklist"'],
];

const all = parse(readFileSync(FILE, 'utf8'));

/** Every rule a text breaks on a store; `premium` lets the Premium label through. */
export function textProblems(text, { store, premium = false } = {}) {
  const problems = FORBIDDEN.filter(([re, what]) => re.test(text) && !(premium && what === 'Premium')).map(([, what]) => `names ${what}`);
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
    for (const store of ['play', 'appstore']) {
      const words = captionsFor(locale, { store });
      for (const [id, c] of Object.entries(words)) {
        const where = `${locale} ${id} (${store})`;
        if (id !== 'feature' && (!Array.isArray(c.h) || c.h.length !== 2 || !c.s)) problems.push(`${where}: needs h as two lines and s`);
        if (!c.alt || c.alt.length > ALT_MAX) problems.push(`${where}: alt text missing or over ${ALT_MAX} characters`);
        if (!['draft', 'approved', 'blocked'].includes(c.status)) problems.push(`${where}: status must be draft, approved or blocked`);
        for (const t of strings({ h: c.h, s: c.s, alt: c.alt, tagline: c.tagline })) problems.push(...textProblems(t, { store }).map((p) => `${where}: "${t}" ${p}`));
        if (c.premium) problems.push(...textProblems(c.premium, { store, premium: true }).map((p) => `${where} premium label: "${c.premium}" ${p}`));
        if (c.sticker && Object.values(c.sticker).some((v) => v === null || v === undefined)) problems.push(`${where}: a sticker key without a value (quote text with commas)`);
        for (const t of strings(c.sticker)) problems.push(...textProblems(t, { store }).map((p) => `${where} sticker: "${t}" ${p}`));
      }
    }
  }
  return [...new Set(problems)];
}

/**
 * The words of a locale's shots for one store: a shot's `appstore:` (Siri, N-195) or `play:` fields replace its own
 * on that store's set only. `feature` holds the feature graphic's words.
 */
export function captionsFor(locale, { store }) {
  const out = {};
  for (const [id, { appstore, play, ...base }] of Object.entries(all[locale].shots)) out[id] = { ...base, ...(store === 'appstore' ? appstore : play) };
  out.feature = { ...all[locale].feature };
  return out;
}
