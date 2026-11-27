// Moves reviewed rows of a catalog draft (catalog/drafts/*.tsv, catalog/REVIEW.md) into
// dictionary.tsv and synonyms.tsv (job 279), or a language draft's into dictionary.<lang>.tsv
// (job 470), and writes the migrations that load them.
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
import {
  languageTables,
  languageUrl,
  parseWords,
  readTables,
} from "./languages.ts";

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
  const body = tsv === "" || tsv.endsWith("\n") ? tsv : `${tsv}\n`;
  const head = body.split("\n").includes(heading)
    ? ""
    : body === ""
    ? `${heading}\n`
    : `\n${heading}\n`;
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

/** A language draft's columns: rows for dictionary.<lang>.tsv (languages.ts). */
export const wordDraftColumns = [
  "lang",
  "word",
  "category",
  "concept",
  "forms",
  "source",
  "confidence",
  "review",
  "note",
] as const;

type WordColumn = typeof wordDraftColumns[number];
export type WordDraftRow = Record<WordColumn, string>;

/** Whether [tsv]'s header is a language draft's. */
export function isWordDraft(tsv: string): boolean {
  const header = tsv.split("\n").find((l) => l !== "" && !l.startsWith("#"));
  return header === wordDraftColumns.join("\t");
}

/** A language draft's rows; one language per draft. */
export function parseWordDraft(tsv: string, name: string): WordDraftRow[] {
  const rows: WordDraftRow[] = [];
  let header = false;
  tsv.split("\n").forEach((line, index) => {
    const at = `${name}:${index + 1}`;
    if (line === "" || line.startsWith("#")) return;
    const cells = line.split("\t");
    if (!header) {
      if (cells.join("\t") !== wordDraftColumns.join("\t")) {
        throw new Error(
          `${at}: expected the header "${wordDraftColumns.join("<TAB>")}"`,
        );
      }
      header = true;
      return;
    }
    if (cells.length !== wordDraftColumns.length) {
      throw new Error(
        `${at}: expected ${wordDraftColumns.length} columns, got ${cells.length}`,
      );
    }
    const row = Object.fromEntries(
      wordDraftColumns.map((column, i) => [column, cells[i] ?? ""]),
    ) as WordDraftRow;
    if (rows[0] !== undefined && rows[0].lang !== row.lang) {
      throw new Error(`${at}: one language per draft, not ${row.lang}`);
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

export type AcceptedWords = {
  draft: string;
  lang: string;
  words: string;
  moved: number;
};

/**
 * The draft and dictionary.<lang>.tsv after moving the accepted rows; throws if the language's
 * words or the classifier rows they make would not parse.
 */
export function acceptWords(
  draft: string,
  name: string,
  words: string,
  dictionary: string,
  synonyms: string,
): AcceptedWords {
  const rows = parseWordDraft(draft, name);
  const lang = rows[0]?.lang ?? "";
  const lines = rows.filter((row) => row.review === "accept").map((row) =>
    [row.word, row.category, row.concept, row.forms].join("\t").replace(
      /\t+$/,
      "",
    )
  );
  const heading = `# Reviewed drafts from catalog/drafts/${name}`;
  const nextWords = append(words, heading, lines);
  const terms = parseDictionary(dictionary);
  languageTables(
    terms,
    parseSynonyms(synonyms, terms),
    parseWords(lang, nextWords, terms),
  );
  const reviewAt = wordDraftColumns.indexOf("review");
  const nextDraft = draft
    .split("\n")
    .filter((line) =>
      line.startsWith("#") || line.split("\t")[reviewAt] !== "accept"
    )
    .join("\n");
  return { draft: nextDraft, lang, words: nextWords, moved: lines.length };
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

/** The dictionary and synonyms migrations of the TSVs as they are now; the files written. */
async function writeMigrations(
  slug: string,
  now: Date,
  dictionary: boolean,
  synonyms: boolean,
): Promise<string[]> {
  const tables = await readTables();
  const written: string[] = [];
  if (dictionary) {
    const file = new URL(
      `${migrationVersion(now, 0)}_classifier_dictionary_draft_${slug}.sql`,
      migrationsUrl,
    );
    await Deno.writeTextFile(
      file,
      dictionaryMigration(tables.terms, tables.words),
    );
    written.push(file.pathname);
  }
  if (synonyms) {
    const file = new URL(
      `${migrationVersion(now, 1)}_classifier_synonyms_draft_${slug}.sql`,
      migrationsUrl,
    );
    await Deno.writeTextFile(file, synonymsMigration(tables.synonyms));
    written.push(file.pathname);
  }
  return written;
}

async function acceptWordDraft(path: string, name: string, draft: string) {
  const lang = parseWordDraft(draft, name)[0]?.lang ?? "";
  const url = languageUrl(lang);
  let words = "";
  try {
    words = await Deno.readTextFile(url);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const result = acceptWords(
    draft,
    name,
    words,
    await Deno.readTextFile(dictionaryUrl),
    await Deno.readTextFile(synonymsUrl),
  );
  if (result.moved === 0) {
    console.log(`${path}: no row has review "accept"; nothing moved`);
    return;
  }
  await Deno.writeTextFile(url, result.words);
  await Deno.writeTextFile(path, result.draft);
  const slug = name.replace(/\.tsv$/, "").replace(/\W/g, "_");
  const written = await writeMigrations(slug, new Date(), true, true);
  console.log(
    `${result.moved} ${lang} words moved from ${path}\n` +
      written.map((file) => `  wrote ${file}`).join("\n"),
  );
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
  const draft = await Deno.readTextFile(path);
  if (isWordDraft(draft)) {
    await acceptWordDraft(path, name, draft);
    Deno.exit(0);
  }
  const result = accept(
    draft,
    name,
    await Deno.readTextFile(dictionaryUrl),
    await Deno.readTextFile(synonymsUrl),
  );
  if (result.terms + result.variants === 0) {
    console.log(`${path}: no row has review "accept"; nothing moved`);
    Deno.exit(0);
  }
  const slug = name.replace(/\.tsv$/, "").replace(/\W/g, "_");
  await Deno.writeTextFile(dictionaryUrl, result.dictionary);
  await Deno.writeTextFile(synonymsUrl, result.synonyms);
  await Deno.writeTextFile(path, result.draft);
  const written = await writeMigrations(
    slug,
    new Date(),
    result.terms > 0,
    result.variants > 0,
  );
  console.log(
    `${result.terms} terms and ${result.variants} synonyms moved from ${path}\n` +
      written.map((file) => `  wrote ${file}`).join("\n"),
  );
}
