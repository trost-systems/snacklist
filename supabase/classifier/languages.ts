// The catalog's languages besides German (job 470): one dictionary.<lang>.tsv per language, read
// by generate.ts and generate_synonyms.ts. German is the classifier's base: its words are
// dictionary.tsv's terms. Every other language lists the words its catalog offers, each one either
// a German concept (milk -> milch: the concept's category and canonical key) or a concept of its
// own (a classifier_terms row with that language). The classifier reads every language's forms;
// the app offers the words of its language.

import {
  categories,
  type Category,
  dictionaryUrl,
  parseDictionary,
  type Term,
  termPattern,
} from "./generate.ts";
import {
  parseSynonyms,
  type Synonym,
  synonymsUrl,
} from "./generate_synonyms.ts";

/** A line of dictionary.<lang>.tsv: word<TAB>category[<TAB>concept[<TAB>forms]]. */
export type Word = {
  lang: string;
  word: string;
  category: Category;
  /** The dictionary.tsv term this word is, or null for a concept of its own. */
  concept: string | null;
  /** Other spellings of the word: misspellings, irregular plurals. */
  forms: string[];
};

export type LanguageTerm = Term & { lang: string };
export type CatalogWord = { lang: string; word: string; category: Category };

const langPattern = /^[a-z]{2}$/;

/** The forms a language derives from a word: the plural of a singular, the singular of a plural. */
export const inflections: Record<string, (word: string) => string[]> = {
  en: englishInflections,
};

/**
 * The singular of [word]'s last word when it is a plural (apples -> apple, berries -> berry,
 * tomatoes -> tomato, loaves -> loaf, loafe), so the German stemmer's keys meet both (apple ->
 * appl, apples -> apple). No plurals: a mass noun's (wines, milks) would be new short forms that
 * other words match; a word that has a plural lists it in its forms.
 */
export function englishInflections(word: string): string[] {
  const space = word.lastIndexOf(" ");
  const head = word.slice(0, space + 1);
  const last = word.slice(space + 1);
  if (last.length < 4 || !last.endsWith("s") || /(ss|us|is)$/.test(last)) {
    return [];
  }
  const singular = last.endsWith("ies")
    ? [`${last.slice(0, -3)}y`]
    : last.endsWith("ves")
    ? [`${last.slice(0, -3)}f`, `${last.slice(0, -3)}fe`]
    : /(oes|ches|shes|xes|zes)$/.test(last)
    ? [last.slice(0, -2)]
    : [last.slice(0, -1)];
  return singular.filter((form) => form.length >= 3).map((form) =>
    `${head}${form}`
  );
}

/** The languages that have a dictionary.<lang>.tsv next to this file, sorted. */
export async function languageFiles(): Promise<Map<string, URL>> {
  const files = new Map<string, URL>();
  for await (const entry of Deno.readDir(new URL("./", import.meta.url))) {
    const lang = /^dictionary\.([a-z]{2})\.tsv$/.exec(entry.name)?.[1];
    if (entry.isFile && lang !== undefined) {
      files.set(lang, new URL(entry.name, import.meta.url));
    }
  }
  return new Map([...files].sort(([a], [b]) => a < b ? -1 : 1));
}

export function languageUrl(lang: string): URL {
  return new URL(`./dictionary.${lang}.tsv`, import.meta.url);
}

/** Every language's words, as their files are now. */
export async function readWords(dictionary: Term[]): Promise<Word[]> {
  const words: Word[] = [];
  for (const [lang, url] of await languageFiles()) {
    words.push(
      ...parseWords(lang, await Deno.readTextFile(url), dictionary),
    );
  }
  return words;
}

/**
 * dictionary.<lang>.tsv's rows. A concept must be a dictionary.tsv term of the same category; a
 * word without one must not be a German term, since both would be one classifier_terms row.
 */
export function parseWords(
  lang: string,
  tsv: string,
  dictionary: Term[],
): Word[] {
  if (!langPattern.test(lang) || lang === "de") {
    throw new Error(`dictionary.${lang}.tsv: not a language besides de`);
  }
  const german = new Map(dictionary.map((t) => [t.term, t.category]));
  const seen = new Map<string, number>();
  const words: Word[] = [];
  tsv.split("\n").forEach((raw, index) => {
    const line = raw.trimEnd();
    const at = `dictionary.${lang}.tsv:${index + 1}`;
    if (line === "" || line.startsWith("#")) return;
    const [word, category, concept = "", forms = "", ...extra] = line.split(
      "\t",
    );
    if (word === undefined || category === undefined || extra.length > 0) {
      throw new Error(
        `${at}: expected "word<TAB>category[<TAB>concept[<TAB>forms]]"`,
      );
    }
    const listed = forms === "" ? [] : forms.split(",").map((f) => f.trim());
    for (const text of [word, ...listed, ...(concept ? [concept] : [])]) {
      if (!termPattern.test(text)) {
        throw new Error(`${at}: invalid word "${text}"`);
      }
    }
    if (!(categories as readonly string[]).includes(category)) {
      throw new Error(`${at}: unknown category "${category}"`);
    }
    if (concept !== "") {
      const target = german.get(concept);
      if (target === undefined) {
        throw new Error(`${at}: concept "${concept}" is not in dictionary.tsv`);
      }
      if (target !== category) {
        throw new Error(
          `${at}: "${word}" is ${category}, its concept "${concept}" is ${target}`,
        );
      }
    } else if (german.has(word)) {
      throw new Error(
        `${at}: "${word}" is a dictionary.tsv term: give it as its own concept ("${word}<TAB>${category}<TAB>${word}")`,
      );
    }
    const first = seen.get(word);
    if (first !== undefined) {
      throw new Error(`${at}: "${word}" repeats line ${first}`);
    }
    seen.set(word, index + 1);
    words.push({
      lang,
      word,
      category: category as Category,
      concept: concept === "" ? null : concept,
      forms: listed,
    });
  });
  return words;
}

/**
 * The classifier rows [words] add to German's: their own concepts as terms, every word and form
 * of a concept as a synonym of it, and the catalog's words. A form the German data has already,
 * for the same concept, adds nothing; for another one it is refused.
 */
export function languageTables(
  dictionary: Term[],
  germanSynonyms: Synonym[],
  words: Word[],
): {
  terms: LanguageTerm[];
  synonyms: Synonym[];
  forms: (Synonym & { lang: string })[];
  words: CatalogWord[];
} {
  const germanTerm = new Map(dictionary.map((t) => [t.term, t.category]));
  const germanVariant = new Map(
    germanSynonyms.map((s) => [s.variant, s.canonical]),
  );
  const ownTerms = new Map(
    words.filter((w) => w.concept === null).map((w) => [w.word, w.category]),
  );
  const synonyms = new Map<
    string,
    { canonical: string; lang: string; from: string }
  >();
  // Words and listed forms first: a form derived from one word never takes another word.
  const passes = [
    (w: Word) => [w.word, ...w.forms],
    (w: Word) =>
      (inflections[w.lang]?.(w.word) ?? []).filter((f) =>
        f !== w.word && !w.forms.includes(f)
      ),
  ];
  for (const w of words) {
    const canonical = w.concept === null
      ? undefined
      : germanVariant.get(w.concept);
    if (canonical !== undefined) {
      throw new Error(
        `${w.lang} "${w.word}": concept "${w.concept}" is a synonym of "${canonical}": name "${canonical}"`,
      );
    }
  }
  for (const [pass, textsOf] of passes.entries()) {
    const listed = pass === 0;
    for (const w of words) {
      const canonical = w.concept ?? w.word;
      const from = `${w.lang} "${w.word}"`;
      for (const text of textsOf(w)) {
        if (text === canonical) continue;
        const termCategory = germanTerm.get(text) ?? ownTerms.get(text);
        if (termCategory !== undefined) {
          // A derived form that is a term already (chip -> chips) is that term.
          if (!listed) continue;
          if (termCategory !== w.category) {
            throw new Error(
              `${from}: "${text}" is a term of ${termCategory}, the word is ${w.category}`,
            );
          }
          // A listed word that is a term of the same aisle joins the concept (bacon -> speck).
        }
        const variantOf = germanVariant.get(text);
        if (variantOf !== undefined) {
          if (variantOf === canonical || !listed) continue;
          throw new Error(
            `${from}: "${text}" is a synonym of "${variantOf}" in synonyms.tsv`,
          );
        }
        const other = synonyms.get(text);
        if (other === undefined) {
          synonyms.set(text, { canonical, lang: w.lang, from });
        } else if (other.canonical !== canonical && listed) {
          throw new Error(
            `${from}: "${text}" is a form of "${other.canonical}" too (${other.from})`,
          );
        }
      }
    }
  }
  return {
    terms: [
      ...dictionary.map((t) => ({ ...t, lang: "de" })),
      ...words.filter((w) => w.concept === null).map((w) => ({
        term: w.word,
        category: w.category,
        lang: w.lang,
      })),
    ],
    synonyms: [
      ...germanSynonyms,
      ...[...synonyms].map(([variant, { canonical }]) => ({
        variant,
        canonical,
      })),
    ],
    forms: [...synonyms].map(([variant, { canonical, lang }]) => ({
      variant,
      canonical,
      lang,
    })),
    words: words.map(({ lang, word, category }) => ({ lang, word, category })),
  };
}

export type Tables = ReturnType<typeof languageTables> & {
  dictionary: Term[];
  german: Synonym[];
  languages: Word[];
};

/** Every classifier table the TSVs make, as they are now. */
export async function readTables(): Promise<Tables> {
  const dictionary = parseDictionary(await Deno.readTextFile(dictionaryUrl));
  const german = parseSynonyms(
    await Deno.readTextFile(synonymsUrl),
    dictionary,
  );
  const languages = await readWords(dictionary);
  return {
    ...languageTables(dictionary, german, languages),
    dictionary,
    german,
    languages,
  };
}

/** What each language covers: words, shared and own concepts, forms, words per category. */
export function coverage(tables: Tables): string {
  const { dictionary, german, languages, forms } = tables;
  const lines = [
    `de: ${dictionary.length} terms, ${german.length} synonyms, ${
      new Set(dictionary.map((t) => t.category)).size
    }/${categories.length} categories`,
  ];
  for (const [lang, list] of Map.groupBy(languages, (w) => w.lang)) {
    const perCategory = Map.groupBy(list, (w) => w.category);
    const concepts = new Set(list.map((w) => w.concept ?? w.word));
    const own = list.filter((w) => w.concept === null).length;
    lines.push(
      `${lang}: ${list.length} words, ${concepts.size} concepts (${
        list.length - own
      } words on a German concept, ${own} own), ${
        forms.filter((f) => f.lang === lang).length
      } forms, ${perCategory.size}/${categories.length} categories`,
      `  ${
        categories.map((c) => `${c} ${perCategory.get(c)?.length ?? 0}`).join(
          ", ",
        )
      }`,
    );
  }
  return lines.join("\n");
}
