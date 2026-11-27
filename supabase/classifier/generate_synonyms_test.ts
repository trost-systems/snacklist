import { assertEquals, assertThrows } from "@std/assert";
import { readTables } from "./languages.ts";
import { migrationsUrl, parseDictionary } from "./generate.ts";
import { parseSynonyms, toMigration } from "./generate_synonyms.ts";

Deno.test("the newest synonyms migration is generated from synonyms.tsv", async () => {
  const names: string[] = [];
  for await (const entry of Deno.readDir(migrationsUrl)) {
    if (entry.name.includes("_classifier_synonyms")) names.push(entry.name);
  }
  const newest = names.sort().at(-1);
  if (newest === undefined) {
    throw new Error("no _classifier_synonyms migration");
  }
  const migration = await Deno.readTextFile(new URL(newest, migrationsUrl));
  const expected = toMigration((await readTables()).synonyms);
  assertEquals(
    migration,
    expected,
    `regenerate ${newest} with generate_synonyms.ts`,
  );
});

Deno.test("the spec's regional pairs and English words are in", async () => {
  const { synonyms } = await readTables();
  const canonical = new Map(synonyms.map((s) => [s.variant, s.canonical]));
  for (
    const [variant, target] of [
      ["karotte", "möhre"],
      ["mohrrübe", "möhre"],
      ["gelbe rübe", "möhre"],
      ["semmel", "brötchen"],
      ["weck", "brötchen"],
      ["erdapfel", "kartoffel"],
      ["rahm", "sahne"],
      ["topfen", "quark"],
      ["zwetschge", "pflaume"],
      ["paradeiser", "tomate"],
      ["karfiol", "blumenkohl"],
      ["carrots", "möhre"],
      ["milk", "milch"],
    ] as const
  ) {
    assertEquals(canonical.get(variant), target, variant);
  }
  if (synonyms.length < 100) {
    throw new Error(`only ${synonyms.length} synonyms`);
  }
});

Deno.test("malformed or inconsistent lines are refused with their line number", () => {
  const dictionary = parseDictionary(
    "möhre\tproduce\nkarotte\tproduce\nmilch\tchilled\nmehl\tpantry",
  );
  assertThrows(
    () => parseSynonyms("rüebli\tmöhre\nrüebli\tmöhre", dictionary),
    Error,
    "repeats line 1",
  );
  assertThrows(
    () => parseSynonyms("# x\nrüebli\tkarotten", dictionary),
    Error,
    'synonyms.tsv:2: canonical "karotten" is not in dictionary.tsv',
  );
  assertThrows(
    () => parseSynonyms("mehl\tmilch", dictionary),
    Error,
    '"mehl" is pantry in dictionary.tsv, "milch" is chilled',
  );
  assertThrows(
    () => parseSynonyms("rüebli\tkarotte\nkarotte\tmöhre", dictionary),
    Error,
    "itself a variant",
  );
  assertThrows(
    () => parseSynonyms("möhre\tmöhre", dictionary),
    Error,
    "its own canonical",
  );
  assertThrows(
    () => parseSynonyms("Rüebli\tmöhre", dictionary),
    Error,
    "invalid term",
  );
  assertThrows(
    () => parseSynonyms("rüebli möhre", dictionary),
    Error,
    "expected",
  );
});
