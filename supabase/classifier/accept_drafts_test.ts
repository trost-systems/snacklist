import { assertEquals, assertThrows } from "@std/assert";
import {
  accept,
  acceptWords,
  draftsUrl,
  isWordDraft,
  migrationVersion,
  parseDraft,
  parseWordDraft,
  waitingDrafts,
} from "./accept_drafts.ts";

const header = "kind\tterm\tvalue\tsource\tconfidence\treview\tnote";
const dictionary = "# Seed dictionary\nbrötchen\tbakery\nmöhre\tproduce\n";
const synonyms = "# Synonyms\nsemmel\tbrötchen\n";
const draft = [
  "# Drafted 2026-11-16",
  header,
  "term\tpastinake\tproduce\tclaude-draft\thigh\taccept\t",
  "synonym\tschrippe\tbrötchen\tclaude-draft\thigh\taccept\tBerlin",
  "synonym\tpastinaken\tpastinake\tclaude-draft\tmedium\taccept\t",
  "term\tkohlrabi\tproduce\tclaude-draft\tmedium\t\t",
  "term\tsnus\tsweets\tclaude-draft\tlow\treject\tnot a grocery",
  "",
].join("\n");

Deno.test("accepted rows move into the catalog under the draft's heading", () => {
  const result = accept(draft, "2026-11-16-claude.tsv", dictionary, synonyms);
  assertEquals(
    result.dictionary,
    "# Seed dictionary\nbrötchen\tbakery\nmöhre\tproduce\n\n" +
      "# Reviewed drafts from catalog/drafts/2026-11-16-claude.tsv\npastinake\tproduce\n",
  );
  assertEquals(
    result.synonyms,
    "# Synonyms\nsemmel\tbrötchen\n\n" +
      "# Reviewed drafts from catalog/drafts/2026-11-16-claude.tsv\n" +
      "schrippe\tbrötchen\npastinaken\tpastinake\n",
  );
  assertEquals([result.terms, result.variants], [1, 2]);
});

Deno.test("unreviewed and rejected rows stay in the draft", () => {
  const result = accept(draft, "d.tsv", dictionary, synonyms);
  assertEquals(
    result.draft,
    [
      "# Drafted 2026-11-16",
      header,
      "term\tkohlrabi\tproduce\tclaude-draft\tmedium\t\t",
      "term\tsnus\tsweets\tclaude-draft\tlow\treject\tnot a grocery",
      "",
    ].join("\n"),
  );
});

Deno.test("a second run moves nothing and a later batch joins the same heading", () => {
  const first = accept(draft, "d.tsv", dictionary, synonyms);
  const again = accept(first.draft, "d.tsv", first.dictionary, first.synonyms);
  assertEquals([again.dictionary, again.synonyms, again.terms], [
    first.dictionary,
    first.synonyms,
    0,
  ]);
  const later = accept(
    first.draft.replace("medium\t\t", "medium\taccept\t"),
    "d.tsv",
    first.dictionary,
    first.synonyms,
  );
  assertEquals(
    later.dictionary,
    first.dictionary + "kohlrabi\tproduce\n",
  );
});

Deno.test("a row the catalog would refuse stops the whole move", () => {
  const orphan =
    `${header}\nsynonym\tsellerie\tknollensellerie\tclaude-draft\thigh\taccept\t\n`;
  assertThrows(
    () => accept(orphan, "d.tsv", dictionary, synonyms),
    Error,
    'canonical "knollensellerie" is not in dictionary.tsv',
  );
  const listed =
    `${header}\nterm\tmöhre\tproduce\tclaude-draft\thigh\taccept\t\n`;
  assertThrows(
    () => accept(listed, "d.tsv", dictionary, synonyms),
    Error,
    '"möhre" repeats',
  );
});

Deno.test("a malformed draft names its line", () => {
  assertThrows(
    () =>
      accept(
        `${header}\nterm\tkiwi\tproduce\tclaude-draft\thigh\tyes\t\n`,
        "d.tsv",
        "",
        "",
      ),
    Error,
    'd.tsv:2: review is "accept", "reject" or empty, not "yes"',
  );
  assertThrows(
    () => accept("term\tkiwi\n", "d.tsv", "", ""),
    Error,
    "d.tsv:1: expected the header",
  );
});

Deno.test("migration versions are UTC and sort in offset order", () => {
  const now = new Date("2026-11-16T23:59:59Z");
  assertEquals([migrationVersion(now, 0), migrationVersion(now, 1)], [
    "20261116235959",
    "20261117000000",
  ]);
});

Deno.test("every draft waiting for review parses", async () => {
  for (const name of await waitingDrafts(draftsUrl)) {
    const draft = await Deno.readTextFile(new URL(name, draftsUrl));
    if (isWordDraft(draft)) parseWordDraft(draft, name);
    else parseDraft(draft, name);
  }
});

Deno.test("no drafts directory means no drafts", async () => {
  assertEquals(
    await waitingDrafts(new URL("./no-such-drafts/", import.meta.url)),
    [],
  );
});

const wordHeader =
  "lang\tword\tcategory\tconcept\tforms\tsource\tconfidence\treview\tnote";

Deno.test("a language draft's accepted rows move to its words, rejected ones stay", () => {
  const draft = [
    "# a language draft",
    wordHeader,
    "en\tcarrots\tproduce\tmöhre\t\tclaude-draft\thigh\taccept\t",
    "en\tbuns\tbakery\tbrötchen\tbunz\tclaude-draft\thigh\taccept\tUK",
    "en\tgrapes\tproduce\t\t\tclaude-draft\thigh\treject\twrong",
  ].join("\n");
  const result = acceptWords(draft, "e.tsv", "", dictionary, "");
  assertEquals(result.lang, "en");
  assertEquals(result.moved, 2);
  assertEquals(
    result.words,
    "# Reviewed drafts from catalog/drafts/e.tsv\ncarrots\tproduce\tmöhre\nbuns\tbakery\tbrötchen\tbunz\n",
  );
  assertEquals(result.draft.includes("grapes"), true);
  assertEquals(result.draft.includes("carrots"), false);
  assertEquals(isWordDraft(draft), true);
});

Deno.test("a language draft that would not parse moves nothing", () => {
  const row = (concept: string) =>
    [wordHeader, `en\tcarrots\tbakery\t${concept}\t\tc\thigh\taccept\t`]
      .join("\n");
  assertThrows(
    () => acceptWords(row("möhre"), "e.tsv", "", dictionary, ""),
    Error,
    'its concept "möhre" is produce',
  );
  assertThrows(
    () => acceptWords(row("karotte"), "e.tsv", "", dictionary, ""),
    Error,
    'concept "karotte" is not in dictionary.tsv',
  );
  assertThrows(
    () =>
      parseWordDraft(
        [
          wordHeader,
          "en\ta\tproduce\t\t\tc\thigh\t\t",
          "de\tb\tproduce\t\t\tc\thigh\t\t",
        ]
          .join("\n"),
        "e.tsv",
      ),
    Error,
    "one language per draft",
  );
});

Deno.test("every German draft, accepted whole, still fits every language's words (EN6)", async () => {
  const { dictionaryUrl, parseDictionary } = await import("./generate.ts");
  const { parseSynonyms, synonymsUrl } = await import("./generate_synonyms.ts");
  const { languageFiles, languageTables, parseWords } = await import(
    "./languages.ts"
  );
  for (const name of await waitingDrafts(draftsUrl)) {
    const draft = await Deno.readTextFile(new URL(name, draftsUrl));
    if (isWordDraft(draft)) continue;
    const all = draft.split("\n").map((line) => {
      const cells = line.split("\t");
      return line.startsWith("#") || cells.length !== 7 || cells[0] === "kind"
        ? line
        : [...cells.slice(0, 5), "accept", cells[6]].join("\t");
    }).join("\n");
    const result = accept(
      all,
      name,
      await Deno.readTextFile(dictionaryUrl),
      await Deno.readTextFile(synonymsUrl),
    );
    const terms = parseDictionary(result.dictionary);
    const synonyms = parseSynonyms(result.synonyms, terms);
    for (const [lang, url] of await languageFiles()) {
      languageTables(
        terms,
        synonyms,
        parseWords(lang, await Deno.readTextFile(url), terms),
      );
    }
  }
});
