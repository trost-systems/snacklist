import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import { categories, parseDictionary } from "./generate.ts";
import { parseSynonyms } from "./generate_synonyms.ts";
import {
  coverage,
  englishInflections,
  languageTables,
  parseWords,
  readTables,
} from "./languages.ts";

const dictionary = parseDictionary(
  "apfel\tproduce\nbrötchen\tbakery\nbacon\tmeat\nspeck\tmeat\nchips\tsweets\nmilch\tchilled\nwiener\tmeat\nfrankfurter\tmeat\n",
);
const german = parseSynonyms("frankfurter\twiener\n", dictionary);
const words = (tsv: string) => parseWords("en", tsv, dictionary);

Deno.test("English derives the singular of a plural, never a plural", () => {
  const cases: [string, string[]][] = [
    ["apples", ["apple"]],
    ["berries", ["berry"]],
    ["tomatoes", ["tomato"]],
    ["peaches", ["peach"]],
    ["boxes", ["box"]],
    ["loaves", ["loaf", "loafe"]],
    ["bell peppers", ["bell pepper"]],
    ["milk", []],
    ["avocado", []],
    ["hummus", []],
    ["glass", []],
    ["oats", ["oat"]],
    ["peas", ["pea"]],
  ];
  for (const [word, forms] of cases) {
    assertEquals(englishInflections(word), forms, word);
  }
});

Deno.test("a word joins its German concept, with its forms and derived singular", () => {
  const tables = languageTables(
    dictionary,
    german,
    words(
      "apples\tproduce\tapfel\tappels\nbacon\tmeat\tspeck\ncrisps\tsweets\tchips\nhaddock\tmeat\n",
    ),
  );
  const canonical = new Map(
    tables.synonyms.map((s) => [s.variant, s.canonical]),
  );
  assertEquals(canonical.get("apples"), "apfel");
  assertEquals(canonical.get("apple"), "apfel");
  assertEquals(canonical.get("appels"), "apfel");
  assertEquals(
    canonical.get("bacon"),
    "speck",
    "a German term of the aisle joins the concept",
  );
  assertEquals(canonical.get("crisp"), "chips");
  assertEquals(canonical.get("frankfurter"), "wiener");
  assertEquals(
    tables.terms.filter((t) => t.lang === "en"),
    [{ term: "haddock", category: "meat", lang: "en" }],
  );
  assertEquals(
    tables.terms.filter((t) => t.lang === "de").map((t) => t.term),
    dictionary.map((t) => t.term),
    "German's terms are dictionary.tsv's",
  );
  assertEquals(tables.words.length, 4);
});

Deno.test("words that would split a key or a concept are refused", () => {
  assertThrows(
    () => words("milk\tdrinks\tmilch"),
    Error,
    'its concept "milch" is chilled',
  );
  assertThrows(
    () => words("milk\tchilled\tmilk"),
    Error,
    "not in dictionary.tsv",
  );
  assertThrows(() => words("chips\tsweets"), Error, "is a dictionary.tsv term");
  assertThrows(
    () => words("milk\tchilled\tmilch\nmilk\tchilled\tmilch"),
    Error,
    "repeats line 1",
  );
  assertThrows(
    () => parseWords("de", "", dictionary),
    Error,
    "not a language besides de",
  );
  assertThrows(
    () =>
      languageTables(
        dictionary,
        german,
        words("frankfurters\tmeat\tfrankfurter"),
      ),
    Error,
    'is a synonym of "wiener"',
  );
  assertThrows(
    () =>
      languageTables(
        dictionary,
        german,
        words(
          "rolls\tbakery\tbrötchen\tbuns\nbuns\tbakery\tbrötchen\nbaps\tmeat\tspeck\tbuns",
        ),
      ),
    Error,
    'is a form of "brötchen" too',
  );
  assertThrows(
    () =>
      languageTables(dictionary, german, words("crisps\tsweets\tchips\tmilch")),
    Error,
    '"milch" is a term of chilled',
  );
});

Deno.test("the English catalog covers every aisle, mostly on German concepts", async () => {
  const tables = await readTables();
  const report = coverage(tables);
  assertStringIncludes(report, `en: `);
  assertStringIncludes(
    report,
    `${categories.length}/${categories.length} categories`,
  );
  const english = tables.languages.filter((w) => w.lang === "en");
  if (english.length < 900) {
    throw new Error(`only ${english.length} English words`);
  }
  const onGerman = english.filter((w) => w.concept !== null).length;
  if (onGerman < english.length * 0.8) {
    throw new Error(
      `only ${onGerman} of ${english.length} English words on a German concept`,
    );
  }
});

Deno.test("a language's words may hold the letters of other Latin alphabets", () => {
  const hu = parseWords(
    "hu",
    "őszibarack\tproduce\ntejföl\tchilled\ntúró\tchilled\n",
    dictionary,
  );
  assertEquals(hu.map((w) => w.word), ["őszibarack", "tejföl", "túró"]);
  assertThrows(
    () => parseWords("hu", "Barack\tproduce\n", dictionary),
    Error,
    "invalid word",
  );
});
