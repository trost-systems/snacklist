// Legal's rule BN-1 (docs/store/LISTING.md, "Brand rule BN-1") over the store listing texts in
// app/fastlane/metadata. Siri, Alexa, Claude and ChatGPT (and their makers) never appear in the
// name, subtitle, keywords, promotional text, Play title, Play short description or in-app purchase
// texts (points 3 and 8); that always fails. A long description may name a brand only while
// docs/store/BRAND_LIVE.md marks it live, in BN-1's wording (point 4), once per text, with its
// Premium and plan lines (point 6) and its trademark notice at the end (point 5).
//
// CI runs it without arguments: a brand needs Live "yes" in BRAND_LIVE.md, and findings that
// scripts/store-brands.baseline.json lists (copy approved before BN-1, each with its reason) pass;
// the baseline only shrinks. On the day a listing text goes public, run it with --publish: the
// baseline no longer counts and every named brand needs Live "yes" verified today (Europe/Berlin).
// Usage: deno run --allow-read scripts/store-brands.ts [--publish] [repo-dir]

export type Brand = 'Siri' | 'Alexa' | 'Claude' | 'ChatGPT';
type Locale = 'de-DE' | 'en-US';

interface BrandRule {
  /**
   * Every word that names the brand in a description: the product and, for AI, its maker. No
   * boundary after it, so a possessive, plural or compound („Claudes“, „OpenAIs“) still names it.
   */
  names: RegExp;
  notice: Record<Locale, string>;
}

export const BRANDS: Record<Brand, BrandRule> = {
  Siri: {
    names: /\bSiri/gi,
    notice: {
      'de-DE': 'Siri ist eine Marke von Apple Inc.',
      'en-US': 'Siri is a trademark of Apple Inc.',
    },
  },
  Alexa: {
    names: /\bAlexa/gi,
    notice: {
      'de-DE':
        'Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.',
      'en-US': 'Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates.',
    },
  },
  Claude: {
    names: /\b(?:Claude|Anthropic)/gi,
    notice: {
      'de-DE': 'Claude ist eine Marke von Anthropic.',
      'en-US': 'Claude is a trademark of Anthropic.',
    },
  },
  ChatGPT: {
    names: /\b(?:Chat[\s-]?GPT|Open[\s-]?AI)/gi,
    notice: {
      'de-DE': 'ChatGPT ist eine Marke von OpenAI.',
      'en-US': 'ChatGPT is a trademark of OpenAI.',
    },
  },
};
const BRAND_ORDER: Brand[] = ['Siri', 'Alexa', 'Claude', 'ChatGPT'];

/** Points 3 and 8: no brand, nor Apple or Amazon, on these surfaces, ever. */
const NEVER_SURFACE = /(?:^|\/)(?:name|subtitle|keywords|promotional_text|title|short_description)\.txt$|\/iap\//;
// Substrings, not words: German glues a brand into compounds („Alexaliste“, „claudeapp“). Apple only at a word start.
const NEVER_BRAND =
  /siri|alexa|amazon|claude|anthropic|chat[\s-]?gpt|gpt|openai|open[\s-]?ai|gemini|copilot|google[\s-]?assistant|\bapple/i;
/** Point 9: brands without a BN-1 row stay generic-only. */
const UNKNOWN_BRAND =
  /\b(?:gemini|copilot|google[\s-]?assistant|cortana|bixby|perplexity|grok|meta ai|le chat|echo|car[\s-]?play|(?<!chat[\s-]?)gpt)\b/i;
const DESCRIPTION = /(?:^|\/)(?:description|full_description)\.txt$/;

/** Point 4's "Never" list, in a sentence that names a brand. */
const NEVER_PHRASE =
  /\b(?:works? with|compatible with|kompatibel mit|funktioniert mit|partner\w*|official\w*|offiziell\w*|certified|zertifiziert\w*|recommended by|empfohlen von|powered by|built with|entwickelt mit)\b|™|®/i;
const AI_PREMIUM = /\b(?:mit|with) Snacklist Premium\b/;
const CHATGPT_QUALIFIER = /je nach ChatGPT-Tarif und Land|depending on (?:your )?ChatGPT plan and country/i;

export type Rule =
  | 'surface'
  | 'live'
  | 'texts'
  | 'once'
  | 'phrasing'
  | 'form'
  | 'premium'
  | 'qualifier'
  | 'notice'
  | 'unknown';

export interface Finding {
  file: string;
  brand: Brand | null;
  rule: Rule;
  message: string;
}

export interface LiveRow {
  brand: Brand;
  live: boolean;
  /** YYYY-MM-DD, or null when never verified. */
  verified: string | null;
  texts: string[];
}

export interface Input {
  /** Repo-relative path to text, every file under app/fastlane/metadata. */
  texts: Map<string, string>;
  rows: Map<Brand, LiveRow>;
  /** YYYY-MM-DD in Europe/Berlin. */
  today: string;
  publish: boolean;
  /** The native-siri hold is released: Peter's device test passed, so "mit Siri" may replace the Kurzbefehl wording. */
  nativeSiri: boolean;
}

function localeOf(file: string): Locale {
  return file.includes('en-US') ? 'en-US' : 'de-DE';
}

/** The text without the notice sentences and the ChatGPT plan qualifier, which name a brand by design. */
function withoutNotices(text: string, locale: Locale): string {
  return BRAND_ORDER.reduce(
    (t, b) => t.split(BRANDS[b].notice[locale]).join(''),
    text,
  )
    .replace(new RegExp(CHATGPT_QUALIFIER.source, 'gi'), '…');
}

function sentences(text: string): string[] {
  return text.split('\n').flatMap((line) => line.split(/(?<=[.!?])\s+/)).filter(
    (s) => s.trim() !== '',
  );
}

function mentions(text: string, brand: Brand): RegExpMatchArray[] {
  return [...text.matchAll(BRANDS[brand].names)];
}

function formProblem(
  brand: Brand,
  sentence: string,
  nativeSiri: boolean,
): string | null {
  const all = mentions(sentence, brand);
  switch (brand) {
    case 'Alexa': {
      const ok = sentence.match(
        /Snacklist-Skill für Amazon Alexa|Snacklist skill for Amazon Alexa/g,
      )?.length ?? 0;
      return ok === all.length
        ? null
        : 'names Alexa only as „Snacklist-Skill für Amazon Alexa“ / "Snacklist skill for Amazon Alexa"';
    }
    case 'Siri': {
      const shortcut = sentence.match(/\bper Siri-Kurzbefehl(?![-\p{L}])|\bSiri Shortcut(?![-\p{L}])/giu)?.length ?? 0;
      const native = nativeSiri ? (sentence.match(/\b(?:mit|with) Siri\b/g)?.length ?? 0) : 0;
      if (shortcut + native === all.length) return null;
      return nativeSiri
        ? 'names Siri only as „per Siri-Kurzbefehl“ or „mit Siri“ / "with a Siri Shortcut" or "with Siri"'
        : 'names Siri only as „per Siri-Kurzbefehl“ / "with a Siri Shortcut" until the native-siri hold is released (device test)';
    }
    case 'Claude':
    case 'ChatGPT': {
      const bad = all.filter((m) => {
        const at = m.index ?? 0;
        const compound = /[-\p{L}]/u.test(sentence.charAt(at + m[0].length));
        return compound || !/\b(?:in|für|for|mit|with)\s+$/i.test(sentence.slice(0, at));
      });
      return bad.length === 0
        ? null
        : `names ${brand} only as „in/für/mit ${brand}“ / "in/for/with ${brand}", never inside a product or feature name`;
    }
  }
}

function brandPhrasing(brand: Brand, sentence: string): string | null {
  const name = `(?:${BRANDS[brand].names.source})`;
  const by = new RegExp(
    `\\b(?:by|von) ${name}\\b|${name}[- ]app\\b|${name}(?:['’]?s['’]?)(?![\\p{L}\\p{N}])`,
    'iu',
  );
  const m = sentence.match(NEVER_PHRASE) ?? sentence.match(by) ??
    (brand === 'Alexa' ? sentence.match(/Alexa-Snacklist|\bhey,? Alexa/i) : null);
  return m ? `"${m[0]}" (BN-1 point 4: never)` : null;
}

/** Every BN-1 finding in the listing texts, before the baseline. */
export function findings(input: Input): Finding[] {
  const out: Finding[] = [];
  const add = (
    file: string,
    brand: Brand | null,
    rule: Rule,
    message: string,
  ) => out.push({ file, brand, rule, message });

  for (
    const [file, text] of [...input.texts].sort(([a], [b]) => a.localeCompare(b))
  ) {
    if (NEVER_SURFACE.test(file)) {
      const m = text.match(NEVER_BRAND);
      if (m) {
        add(
          file,
          null,
          'surface',
          `names "${m[0]}": no brand on this surface, ever (BN-1 points 3 and 8)`,
        );
      }
      continue;
    }
    if (!DESCRIPTION.test(file)) continue;
    const locale = localeOf(file);
    const body = withoutNotices(text, locale);
    const original = new Map(
      sentences(text).map((s) => [withoutNotices(s, locale), s]),
    );
    // From the raw text: a notice sentence or the ChatGPT qualifier alone still puts the brand on the page.
    const named = BRAND_ORDER.filter((b) => mentions(text, b).length > 0);
    const unknown = text.match(UNKNOWN_BRAND);
    if (unknown) {
      add(file, null, 'unknown', `names "${unknown[0]}", a brand BN-1 has no row for: generic only (BN-1 point 9)`);
    }

    for (const brand of named) {
      const row = input.rows.get(brand);
      if (!row?.live) {
        add(
          file,
          brand,
          'live',
          `names ${brand}, which docs/store/BRAND_LIVE.md does not mark live (BN-1 point 1)`,
        );
      } else if (input.publish && row.verified !== input.today) {
        add(
          file,
          brand,
          'live',
          `names ${brand}, last verified ${row.verified ?? 'never'}, not today ${input.today} (BN-1 point 2)`,
        );
      }
      if (!row?.texts.includes(file)) {
        add(
          file,
          brand,
          'texts',
          `names ${brand}: list this file under "Texts that depend on it" in docs/store/BRAND_LIVE.md (BN-1 points 2 and 7)`,
        );
      }
      const count = mentions(body, brand).length;
      if (count > 1) {
        add(
          file,
          brand,
          'once',
          `names ${brand} ${count} times: one plain mention per text (BN-1 point 3)`,
        );
      }

      for (
        const sentence of sentences(body).filter((s) => mentions(s, brand).length > 0)
      ) {
        const phrase = brandPhrasing(brand, sentence);
        if (phrase) add(file, brand, 'phrasing', `${phrase}: ${sentence}`);
        const form = formProblem(brand, sentence, input.nativeSiri);
        if (form) {
          add(file, brand, 'form', `${form} (BN-1 point 4): ${sentence}`);
        }
        if (
          (brand === 'Siri' || brand === 'Alexa') && /Premium/.test(sentence)
        ) {
          add(
            file,
            brand,
            'premium',
            `${brand} lines never mention Premium (BN-1 point 6): ${sentence}`,
          );
        }
        if (
          (brand === 'Claude' || brand === 'ChatGPT') &&
          !AI_PREMIUM.test(sentence)
        ) {
          add(
            file,
            brand,
            'premium',
            `${brand} lines carry „mit Snacklist Premium“ / "with Snacklist Premium" (BN-1 point 6): ${sentence}`,
          );
        }
        if (
          brand === 'ChatGPT' &&
          !CHATGPT_QUALIFIER.test(original.get(sentence) ?? sentence)
        ) {
          add(
            file,
            brand,
            'qualifier',
            `ChatGPT lines name the plan and country limit („je nach ChatGPT-Tarif und Land“, BN-1 point 6): ${sentence}`,
          );
        }
      }
    }
    if (named.length > 0) {
      const end = named.map((b) => BRANDS[b].notice[locale]).join(' ');
      if (!text.endsWith(end)) {
        add(
          file,
          null,
          'notice',
          `does not end with the trademark notice "${end}" (BN-1 point 5)`,
        );
      }
    }
  }
  return out;
}

/** docs/store/BRAND_LIVE.md's table: | Brand | Live | URL | Last verified | Proof | Texts that depend on it | ... */
export function parseBrandLive(
  markdown: string,
): { rows: Map<Brand, LiveRow>; problems: string[] } {
  const rows = new Map<Brand, LiveRow>();
  const problems: string[] = [];
  for (const line of markdown.split('\n')) {
    const cells = line.split('|').map((c) => c.trim());
    const brand = BRAND_ORDER.find((b) => b === cells[1]);
    if (brand === undefined) continue;
    const [, , live = '', url = '', verified = '', proof = '', texts = ''] = cells;
    if (live !== 'yes' && live !== 'no') {
      problems.push(
        `BRAND_LIVE.md: ${brand}: Live is "${live}", write yes or no`,
      );
    }
    const date = /^\d{4}-\d{2}-\d{2}$/.test(verified) ? verified : null;
    if (
      live === 'yes' &&
      (date === null || url === '' || url === '-' || proof === '' ||
        proof === '-')
    ) {
      problems.push(
        `BRAND_LIVE.md: ${brand}: Live yes needs the URL, a YYYY-MM-DD verification date and the proof path (BN-1 point 2)`,
      );
    }
    rows.set(brand, {
      brand,
      live: live === 'yes',
      verified: date,
      texts: [...texts.matchAll(/`([^`]+)`/g)].flatMap((
        [, t],
      ) => (t === undefined ? [] : [t])),
    });
  }
  for (const b of BRAND_ORDER) {
    if (!rows.has(b)) problems.push(`BRAND_LIVE.md: no row for ${b}`);
  }
  return { rows, problems };
}

/** One finding of today's copy, matched by its whole message: a new sentence with the same rule still fails. */
interface BaselineEntry {
  file: string;
  brand: Brand | null;
  rule: Rule;
  message: string;
  reason: string;
}

const key = (f: { file: string; brand: Brand | null; rule: Rule; message: string }): string =>
  `${f.file}|${f.brand ?? ''}|${f.rule}|${f.message}`;

export const BASELINE = 'scripts/store-brands.baseline.json';
export const BRAND_LIVE = 'docs/store/BRAND_LIVE.md';
const METADATA = 'app/fastlane/metadata';

function* walk(dir: string): Generator<string> {
  for (
    const entry of [...Deno.readDirSync(dir)].sort((a, b) => a.name.localeCompare(b.name))
  ) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory) yield* walk(path);
    else if (entry.isFile && path.endsWith('.txt')) yield path;
  }
}

export function berlinToday(now: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(
    now,
  );
}

/** Every problem, empty when the listing follows BN-1. */
export function check(
  repoDir: string,
  opts: { publish: boolean; today: string },
): string[] {
  const texts = new Map<string, string>();
  for (const path of walk(`${repoDir}/${METADATA}`)) {
    texts.set(
      path.slice(repoDir.length + 1),
      Deno.readTextFileSync(path).replace(/\n$/, ''),
    );
  }
  const { rows, problems } = parseBrandLive(
    Deno.readTextFileSync(`${repoDir}/${BRAND_LIVE}`),
  );
  const flags = JSON.parse(
    Deno.readTextFileSync(`${repoDir}/releases/flags.json`),
  );
  const nativeSiri = flags?.holds?.['native-siri']?.released === true;
  const found = findings({
    texts,
    rows,
    today: opts.today,
    publish: opts.publish,
    nativeSiri,
  });

  const entries: BaselineEntry[] = JSON.parse(Deno.readTextFileSync(`${repoDir}/${BASELINE}`)).entries ?? [];
  const baselined = new Set(opts.publish ? [] : entries.map(key));
  entries.forEach((e, i) => {
    if (!e.reason?.trim()) {
      problems.push(`${BASELINE}: entry ${i + 1} has no reason`);
    }
    if (e.rule === 'surface') {
      problems.push(
        `${BASELINE}: entry ${i + 1}: a surface finding is never baselined (BN-1 point 8)`,
      );
    }
  });
  for (const f of found) {
    if (f.rule !== 'surface' && baselined.has(key(f))) continue;
    problems.push(`${f.file}: ${f.message}`);
  }
  if (!opts.publish) {
    const live = new Set(found.map(key));
    entries.forEach((e, i) => {
      if (!live.has(key(e))) {
        problems.push(
          `${BASELINE}: entry ${i + 1} (${key(e)}) is stale, the text no longer has it. Remove it.`,
        );
      }
    });
  }
  return problems;
}

if (import.meta.main) {
  const publish = Deno.args.includes('--publish');
  const repo = Deno.args.find((a) => !a.startsWith('--')) ??
    new URL('..', import.meta.url).pathname.replace(/\/$/, '');
  const problems = check(repo, { publish, today: berlinToday(new Date()) });
  for (const problem of problems) console.error(problem);
  if (problems.length > 0) {
    console.error(
      `\nBN-1: docs/store/LISTING.md "Brand rule BN-1"; brand status: ${BRAND_LIVE}`,
    );
    Deno.exit(1);
  }
}
