// Moves reviewed rows of a catalog draft (catalog/drafts/*.tsv, catalog/REVIEW.md) into
// dictionary.tsv and synonyms.tsv, and writes the migrations that load them (job 279).
// Usage: deno run --allow-read --allow-write accept_drafts.ts <draft.tsv>
// Rows whose review cell is "accept" leave the draft; "reject" and empty rows stay in it.
// Nothing is written unless both TSVs still parse with the accepted rows in them.

import {
  dictionaryUrl,
  migrationsUrl,
  parseDictionary,
  toMigration as dictionaryMigration,
} from "./generate.ts";
import {
  parseSynonyms,
  synonymsUrl,
  toMigration as synonymsMigration,
} from "./generate_synonyms.ts";

export const draftColumns = [
  "kind",
  "term",
  "value",
  "source",
  "confidence",
  "review",
  "note",
] as const;

type Column = typeof draftColumns[number];
export type DraftRow = Record<Column, string>;
export type Accepted = {
  draft: string;
  dictionary: string;
  synonyms: string;
  terms: number;
  variants: number;
};

const kinds = ["term", "synonym"];
const confidences = ["high", "medium", "low"];
const reviews = ["", "accept", "reject"];

/** The header line, then one row per line; comment and blank lines are kept as they are. */
export function parseDraft(tsv: string, name: string): DraftRow[] {
  const rows: DraftRow[] = [];
  let header = false;
  tsv.split("\n").forEach((line, index) => {
    const at = `${name}:${index + 1}`;
    if (line === "" || line.startsWith("#")) return;
    const cells = line.split("\t");
    if (!header) {
      if (cells.join("\t") !== draftColumns.join("\t")) {
        throw new Error(
          `${at}: expected the header "${draftColumns.join("<TAB>")}"`,
        );
      }
      header = true;
      return;
    }
    if (cells.length !== draftColumns.length) {
      throw new Error(
        `${at}: expected ${draftColumns.length} columns, got ${cells.length}`,
      );
    }
    const [
      kind = "",
      term = "",
      value = "",
      source = "",
      confidence = "",
      review = "",
      note = "",
    ] = cells;
    const row: DraftRow = {
      kind,
      term,
      value,
      source,
      confidence,
      review,
      note,
    };
    if (!kinds.includes(row.kind)) {
      throw new Error(`${at}: unknown kind "${row.kind}"`);
    }
    if (!confidences.includes(row.confidence)) {
      throw new Error(`${at}: unknown confidence "${row.confidence}"`);
    }
    if (!reviews.includes(row.review)) {
      throw new Error(
        `${at}: review is "accept", "reject" or empty, not "${row.review}"`,
      );
    }
    if (row.source === "") throw new Error(`${at}: empty source`);
    rows.push(row);
  });
  if (!header) throw new Error(`${name}: no header line`);
  return rows;
}

function append(tsv: string, heading: string, lines: string[]): string {
  if (lines.length === 0) return tsv;
  const body = tsv.endsWith("\n") ? tsv : `${tsv}\n`;
  const head = body.split("\n").includes(heading) ? "" : `\n${heading}\n`;
  return `${body}${head}${lines.join("\n")}\n`;
}

/** The three files after moving the draft's accepted rows; throws if the catalog would not parse. */
export function accept(
  draft: string,
  name: string,
  dictionary: string,
  synonyms: string,
): Accepted {
  const rows = parseDraft(draft, name);
  const accepted = rows.filter((row) => row.review === "accept");
  const heading = `# Reviewed drafts from catalog/drafts/${name}`;
  const lines = (kind: string) =>
    accepted.filter((row) => row.kind === kind).map((row) =>
      `${row.term}\t${row.value}`
    );
  const nextDictionary = append(dictionary, heading, lines("term"));
  const nextSynonyms = append(synonyms, heading, lines("synonym"));
  parseSynonyms(nextSynonyms, parseDictionary(nextDictionary));
  const nextDraft = draft
    .split("\n")
    .filter((line) => line.startsWith("#") || line.split("\t")[5] !== "accept")
    .join("\n");
  return {
    draft: nextDraft,
    dictionary: nextDictionary,
    synonyms: nextSynonyms,
    terms: lines("term").length,
    variants: lines("synonym").length,
  };
}

/** The drafts in `dir` waiting for review, by name; none once the last one is accepted and deleted. */
export async function waitingDrafts(dir: URL): Promise<string[]> {
  const names: string[] = [];
  try {
    for await (const entry of Deno.readDir(dir)) {
      if (entry.isFile && entry.name.endsWith(".tsv")) names.push(entry.name);
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
  return names.sort();
}

export const draftsUrl = new URL("../../catalog/drafts/", import.meta.url);

/** A migration version (UTC yyyymmddhhmmss) `offset` seconds after `now`. */
export function migrationVersion(now: Date, offset: number): string {
  return new Date(now.getTime() + offset * 1000).toISOString().replace(
    /\D/g,
    "",
  ).slice(0, 14);
}

if (import.meta.main) {
  const [path] = Deno.args;
  if (!path) {
    console.error(
      "usage: accept_drafts.ts <catalog/drafts/<date>-<source>.tsv>",
    );
    Deno.exit(2);
  }
  const name = path.split("/").at(-1) ?? path;
  const result = accept(
    await Deno.readTextFile(path),
    name,
    await Deno.readTextFile(dictionaryUrl),
    await Deno.readTextFile(synonymsUrl),
  );
  if (result.terms + result.variants === 0) {
    console.log(`${path}: no row has review "accept"; nothing moved`);
    Deno.exit(0);
  }
  const slug = name.replace(/\.tsv$/, "").replace(/\W/g, "_");
  const now = new Date();
  const terms = parseDictionary(result.dictionary);
  const written: string[] = [];
  if (result.terms > 0) {
    const file = new URL(
      `${migrationVersion(now, 0)}_classifier_dictionary_draft_${slug}.sql`,
      migrationsUrl,
    );
    await Deno.writeTextFile(file, dictionaryMigration(terms));
    written.push(file.pathname);
  }
  if (result.variants > 0) {
    const file = new URL(
      `${migrationVersion(now, 1)}_classifier_synonyms_draft_${slug}.sql`,
      migrationsUrl,
    );
    await Deno.writeTextFile(
      file,
      synonymsMigration(parseSynonyms(result.synonyms, terms)),
    );
    written.push(file.pathname);
  }
  await Deno.writeTextFile(dictionaryUrl, result.dictionary);
  await Deno.writeTextFile(synonymsUrl, result.synonyms);
  await Deno.writeTextFile(path, result.draft);
  console.log(
    `${result.terms} terms and ${result.variants} synonyms moved from ${path}\n` +
      written.map((file) => `  wrote ${file}`).join("\n"),
  );
}
