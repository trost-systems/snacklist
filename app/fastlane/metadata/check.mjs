// Fails when a store listing text breaks a limit or a Legal rule.
// Run: node app/fastlane/metadata/check.mjs   (prints a markdown table of counts)
import { readFileSync } from "node:fs";
import process from "node:process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(join(root, p), "utf8").replace(/\n$/, "");
const len = (s) => [...s].length;
const errors = [];
const rows = [];

function limit(file, what, n, max) {
  rows.push([file, what, n, max]);
  if (n > max) errors.push(`${file}: ${what} ${n} > ${max}`);
}

const locales = ["de-DE", "en-US"];
const files = [];
for (const l of locales) {
  files.push([`${l}/name.txt`, 30], [`${l}/subtitle.txt`, 30], [`${l}/keywords.txt`, 100],
    [`${l}/promotional_text.txt`, 170], [`${l}/description.txt`, 4000],
    [`android/${l}/title.txt`, 30], [`android/${l}/short_description.txt`, 80],
    [`android/${l}/full_description.txt`, 4000]);
}
for (const [f, max] of files) {
  const t = read(f);
  limit(f, "chars", len(t), max);
  if (t.includes("\n") && !f.includes("description")) errors.push(`${f}: must be one line`);
}
// IAP: line 1 name, line 2 description. App Store limits 30/45; Play 55/45/80 are looser or equal.
for (const l of locales) for (const p of ["yearly", "lifetime"]) {
  const f = `iap/${l}/${p}.txt`;
  const lines = read(f).split("\n");
  if (lines.length !== 2) errors.push(`${f}: needs exactly 2 lines`);
  limit(f, "name", len(lines[0] ?? ""), 30);
  limit(f, "description", len(lines[1] ?? ""), 45);
}

const banned = /\b(kostenlos\w*|gratis|free|hexagon\w*|chatgpt|openai|claude|anthropic|kategorie\w*|categor\w*|widget|apple watch|google assistant|push|rezept\w*|recipe\w*|rewe|lidl|edeka|aldi|kaufland|rossmann|penny|netto|migros|coop)\b/i;
// HP2 (Peter, 22 Nov 2026): prices, totals, trip mode and History are off for everyone at launch.
const HP2 = /\b(preis\w*|price\w*|einkaufssumme|summe|total\w*|verlauf|history|einkaufsmodus|trip mode|trips?\b|stoppuhr|stopwatch|bezahlten beträge\w*|amounts? paid|log (a|one) by hand|von hand eintragbar)/i;
const SIRI_TM = { "de-DE": "Siri ist eine Marke von Apple Inc.", "en-US": "Siri is a trademark of Apple Inc." };
const AMAZON_TM = {
  "de-DE": "Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.",
  "en-US": "Amazon, Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates.",
};
const priceRe = /[€$£]|\b\d+[.,]\d{2}\b|\bEUR\b|\bUSD\b/;
const all = files.map(([f]) => f).concat(locales.flatMap((l) => ["yearly", "lifetime"].map((p) => `iap/${l}/${p}.txt`)));
for (const f of all) {
  const t = read(f);
  const m = t.match(banned);
  if (m) errors.push(`${f}: banned word "${m[0]}"`);
  if (priceRe.test(t)) errors.push(`${f}: looks like a price`);
  if (/\bsie\b.*\balexa|\balexa\b.*\bsie\b/i.test(t)) errors.push(`${f}: Alexa as "sie"`);
  if (/hey,? alexa/i.test(t)) errors.push(`${f}: "Hey Alexa" (Legal N-366: utterances start with "Alexa,")`);
  if (/\bAlexa\b/.test(t) && !/Snacklist-Skill für Alexa|Snacklist skill for Alexa/.test(t)) errors.push(`${f}: Alexa without "Snacklist-Skill für Alexa" / "Snacklist skill for Alexa" (N-366)`);
  if (/Amazon Alexa/.test(t)) errors.push(`${f}: "Amazon Alexa" (N-366 names it "Snacklist-Skill für Alexa")`);
  const hp2 = t.match(HP2);
  if (hp2) errors.push(`${f}: "${hp2[0]}" names a feature that is off at launch (HP2: prices, totals, trip mode, History)`);
}
// N-366: a description naming Alexa ends with the trademark notice; the App Store's names Siri first, Play's only Amazon.
for (const l of locales) for (const [f, store] of [[`${l}/description.txt`, "appstore"], [`android/${l}/full_description.txt`, "play"]]) {
  const t = read(f);
  if (!/\bAlexa\b/.test(t)) continue;
  const end = (store === "appstore" ? `${SIRI_TM[l]} ` : "") + AMAZON_TM[l];
  if (!t.endsWith(end)) errors.push(`${f}: does not end with the trademark notice "${end}"`);
}
// Premium may list AI assistants and the API only while the integration lock is released (releases/flags.json,
// hold integration-lock); until then they work without Premium (Legal N-354). docs/store/LISTING.md has both blocks.
const lockReleased = JSON.parse(readFileSync(join(root, "../../../releases/flags.json"), "utf8")).holds["integration-lock"].released;
for (const l of locales) for (const f of [`${l}/description.txt`, `android/${l}/full_description.txt`]) {
  const premium = read(f).split(/\n\n/).find((p) => /^SNACKLIST PREMIUM/.test(p)) ?? "";
  const named = /\bMCP\b|\bAPI\b/.test(premium);
  if (named && !lockReleased) errors.push(`${f}: Premium names AI assistants or the API, but integration-lock is unreleased`);
  if (!named && lockReleased) errors.push(`${f}: integration-lock is released: put the Premium block from docs/store/LISTING.md in`);
}
// Keywords: 100 chars, no spaces, no repeats of name/subtitle words, no trademarks or retailers.
const tm = new Set(["siri", "alexa", "amazon", "apple", "google", "chatgpt", "openai", "claude", "anthropic", "iphone", "android", "ios", "rewe", "lidl", "edeka", "aldi", "kaufland", "rossmann", "penny", "netto", "dm", "migros", "coop", "bring", "listonic", "anylist", "todoist", "trello"]);
for (const l of locales) {
  const kw = read(`${l}/keywords.txt`);
  if (/\s/.test(kw)) errors.push(`${l}/keywords.txt: contains whitespace`);
  const words = kw.split(",");
  if (new Set(words).size !== words.length) errors.push(`${l}/keywords.txt: duplicate keyword`);
  const used = new Set(`${read(`${l}/name.txt`)} ${read(`${l}/subtitle.txt`)}`.toLowerCase().split(/[^\p{L}]+/u).filter(Boolean));
  for (const w of words) {
    if (used.has(w)) errors.push(`${l}/keywords.txt: "${w}" is in the name or subtitle`);
    if (tm.has(w)) errors.push(`${l}/keywords.txt: "${w}" is a trademark or retailer`);
  }
}
// Android must not name Siri (iPhone only), App Store must not name Google Play.
for (const l of locales) {
  if (/\bSiri\b/.test(read(`android/${l}/full_description.txt`))) errors.push(`android/${l}/full_description.txt: names Siri`);
  if (/Google Play|Google-Konto|Google account/.test(read(`${l}/description.txt`))) errors.push(`${l}/description.txt: names Google`);
}

console.log("| file | what | count | limit |\n| --- | --- | ---: | ---: |");
for (const [f, w, n, m] of rows) console.log(`| \`${f}\` | ${w} | ${n} | ${m} |`);
if (errors.length) { console.error("\n" + errors.join("\n")); process.exit(1); }
console.log("\nok");
