import { assertEquals, assertThrows } from "@std/assert";
import {
  accept,
  draftsUrl,
  migrationVersion,
  parseDraft,
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
    parseDraft(await Deno.readTextFile(new URL(name, draftsUrl)), name);
  }
});

Deno.test("no drafts directory means no drafts", async () => {
  assertEquals(
    await waitingDrafts(new URL("./no-such-drafts/", import.meta.url)),
    [],
  );
});
