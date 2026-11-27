// The classifier rows a catalog draft would add (probe_drafts.sh, jobs 279 and 470), as JSON:
// [[kind, term, value], ...] with kind "term" (term, category) or "synonym" (variant, canonical).
// A German draft's rows are its own; a language draft's are what its words make on top of the
// TSVs as they are now: own concepts as terms, words and forms as synonyms (languages.ts).
// Usage: deno run --allow-read draft_rows.ts <draft.tsv> <accept|all>

import { isWordDraft, parseDraft, parseWordDraft } from "./accept_drafts.ts";
import { languageTables, parseWords, readTables } from "./languages.ts";

export async function draftRows(
  draft: string,
  name: string,
  which: "accept" | "all",
): Promise<[string, string, string][]> {
  const take = (review: string) => which === "all" || review === "accept";
  if (!isWordDraft(draft)) {
    return parseDraft(draft, name).filter((row) => take(row.review)).map((
      row,
    ) => [row.kind, row.term, row.value]);
  }
  const rows = parseWordDraft(draft, name).filter((row) => take(row.review));
  const lang = rows[0]?.lang;
  if (lang === undefined) return [];
  const now = await readTables();
  const words = parseWords(
    lang,
    rows.map((row) =>
      [row.word, row.category, row.concept, row.forms].join("\t").replace(
        /\t+$/,
        "",
      )
    ).join("\n"),
    now.dictionary,
  );
  const next = languageTables(now.dictionary, now.german, [
    ...now.languages,
    ...words,
  ]);
  const terms = new Set(now.terms.map((t) => t.term));
  const variants = new Set(now.synonyms.map((s) => s.variant));
  return [
    ...next.terms.filter((t) => !terms.has(t.term)).map((t): [
      string,
      string,
      string,
    ] => ["term", t.term, t.category]),
    ...next.synonyms.filter((s) => !variants.has(s.variant)).map((s): [
      string,
      string,
      string,
    ] => ["synonym", s.variant, s.canonical]),
  ];
}

if (import.meta.main) {
  const [path, which = "all"] = Deno.args;
  if (!path || (which !== "accept" && which !== "all")) {
    console.error("usage: draft_rows.ts <draft.tsv> <accept|all>");
    Deno.exit(2);
  }
  const name = path.split("/").at(-1) ?? path;
  console.log(
    JSON.stringify(await draftRows(await Deno.readTextFile(path), name, which)),
  );
}
