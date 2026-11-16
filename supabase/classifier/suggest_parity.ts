// Job 274: the household and the texts of supabase/tests/suggest_parity.json, the table the
// server's public.suggest_entries and the app's port (app/lib/list/catalog/suggest_entries.dart)
// both pass. supabase/functions/_shared/suggest_parity_integration_test.ts seeds the household,
// asks the server for every text and checks (or, with SUGGEST_PARITY_WRITE=1, writes) the file;
// app/test/list/suggest_parity_test.dart reads it. Deterministic: the same repo files give the
// same texts.

/** An item the household had: name, brand, details, Menge, and how many days ago. */
export type HistoryItem = readonly [
  string,
  string | null,
  string | null,
  string | null,
  number,
];

/** Every age is different, so no two rows tie on their time. */
export const history: readonly HistoryItem[] = [
  ["Milch", "Weihenstephan", "1,5 %", "2", 3],
  ["Milch", "Weihenstephan", "3,5 %", null, 20],
  ["Milch", null, "laktosefrei", null, 45],
  ["Milch", "Berchtesgadener Land", null, null, 90],
  ["Hafermilch", "Oatly", "Barista", null, 10],
  ["Windeln", "Pampers", "Größe 4", null, 7],
  ["Windeln", "Pampers", "Größe 3", null, 120],
  ["Windeln", null, "Größe 4, Big Pack", null, 30],
  ["Feuchttücher", "Pampers", "Sensitive", "4", 14],
  ["Spaghetti", "Barilla", null, "2", 5],
  ["Spaghetti", null, "Vollkorn", null, 60],
  ["Joghurt", null, "Erdbeere", "4", 2],
  ["Joghurt", "Ehrmann", "Natur, 4er Pack", null, 33],
  ["Äpfel", null, "Bio", "1 kg", 8],
  ["Apfelsaft", null, "naturtrüb", null, 12],
  ["Bananen", null, null, "6", 1],
  ["Brot", null, null, null, 4],
  ["Brötchen", null, null, "6", 2.5],
  ["Butter", "Kerrygold", null, null, 6],
  ["Kaffee", "Tchibo", "ganze Bohne", null, 25],
  ["Toilettenpapier", "Hakle", "3-lagig, 16 Rollen", null, 40],
  ["Spülmittel", "Pril", null, null, 70],
  ["Mineralwasser", "Gerolsteiner", "still, 6x1,5 l", null, 9],
  ["Cola", "Coca-Cola", "Zero", null, 15],
  ["Rote Bete", null, null, null, 50],
  ["Möhren", null, null, "1 kg", 11],
  ["Gurke", null, null, null, 3.5],
  ["Tomaten", null, "passiert", null, 18],
  ["Eier", "Hofgut Sonnenschein", "Bio, 10er Pack", null, 6.5],
  ["Käse", "Bergbauer", "gerieben", null, 22],
  ["Schokolade", "Ritter Sport", "Vollmilch", null, 13],
  ["Schokolade", "Milka", null, null, 80],
  ["Zahnpasta", "elmex", null, null, 100],
  ["Shampoo", null, null, null, 200],
  ["Duschgel", "Duschdas", null, null, 300],
  ["Plimbel", null, null, null, 31],
  ["Hackfleisch", null, "gemischt", "500 g", 16],
  ["Paprika", null, "rot", "3", 5.5],
  ["Paprika", null, "gelb", null, 17],
  ["Klopapier", null, "4-lagig", null, 1.5],
  // Older than a year: no history row, but a name public.is_known_name knows.
  ["Grillkohle", null, null, null, 380],
  ["Glühwein", "Zimtzauber", null, null, 400],
];

/** Spaces around a line, which suggest_parity_lines.txt would not keep. */
const spaced = ["Milch, ", " Milch "];

/** Up to [count] of [rows], evenly spread: the same sample every run. */
function spread<T>(rows: readonly T[], count: number): T[] {
  if (rows.length <= count) return [...rows];
  const step = rows.length / count;
  const picked: T[] = [];
  for (let i = 0; i < count; i++) {
    const row = rows[Math.floor(i * step)];
    if (row !== undefined) picked.push(row);
  }
  return picked;
}

/** The first [n] letters of [word], from 2 on. */
function prefixes(word: string): string[] {
  const chars = [...word];
  const out: string[] = [];
  for (let n = 2; n <= chars.length; n++) out.push(chars.slice(0, n).join(""));
  return out;
}

/** One-letter typos of [word] in its middle: a letter dropped, doubled, swapped and replaced. */
function typos(word: string): string[] {
  const c = [...word];
  if (c.length < 4) return [];
  const m = Math.floor(c.length / 2);
  const swapped = [...c];
  const a = swapped[m - 1];
  const b = swapped[m];
  if (a !== undefined && b !== undefined) {
    swapped[m - 1] = b;
    swapped[m] = a;
  }
  const replaced = [...c];
  replaced[m] = replaced[m] === "e" ? "a" : "e";
  return [
    [...c.slice(0, m), ...c.slice(m + 1)].join(""),
    [...c.slice(0, m + 1), ...c.slice(m)].join(""),
    swapped.join(""),
    replaced.join(""),
  ];
}

function capitalized(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1);
}

/** The data rows of a TSV file in this repo: no comments, no empty lines, split at tabs. */
async function tsv(path: string): Promise<string[][]> {
  const text = await Deno.readTextFile(new URL(path, import.meta.url));
  return text.split("\n").filter((l) => l.trim() !== "" && !l.startsWith("#"))
    .map((l) => l.split("\t"));
}

/** Every text of the table, without repeats, in a fixed order. */
export async function texts(): Promise<string[]> {
  const sweep = (await tsv("./sweep.tsv")).map((r) => r[0] ?? "");
  const quantities = (await tsv("../tests/quantity_parse.tsv")).map((r) =>
    r[0] ?? ""
  );
  const terms = (await tsv("./dictionary.tsv")).map((r) => r[0] ?? "").sort();
  const brands = await tsv("./brands.tsv");
  const lines = (await tsv("./suggest_parity_lines.txt")).map((r) =>
    r[0] ?? ""
  );

  const out = [...lines, ...spaced, ...sweep, ...quantities];
  for (const term of spread(terms, 45)) {
    out.push(...prefixes(capitalized(term)));
  }
  for (const term of spread(terms.filter((t) => [...t].length >= 4), 90)) {
    out.push(...typos(capitalized(term)));
  }
  for (const [brand, product] of spread(brands, 70)) {
    if (brand === undefined) continue;
    out.push(brand);
    if (product) out.push(`${brand} ${product}`, `${product} ${brand}`);
  }
  for (const [name, brand, properties] of history) {
    out.push(
      ...prefixes(name),
      ...typos(name),
      `2 ${name}`,
      `${name} 2`,
      `${name} Big Pack`,
    );
    out.push(`${name} Größe 2`, `${name} laktosefrei`, `${name} 4er Pack`);
    if (brand) {
      out.push(`${brand} ${name}`, `${name} ${brand}`, `${brand} ${name} 1 l`);
    }
    if (properties) {
      out.push(`${name} ${properties}`, `${name} ${properties.split(", ")[0]}`);
    }
  }
  return [
    ...new Set(
      out.map((t) => t.replaceAll("\r", "")).filter((t) => t.trim() !== ""),
    ),
  ];
}
