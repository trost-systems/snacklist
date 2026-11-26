// The native Siri phrases (app/ios/Runner/AppIntents/SnacklistIntents.swift) against the catalog
// Siri matches them with (Runner/AppShortcuts.xcstrings, job 97): every App Shortcut phrase has a
// set of en and de phrases that each name the app once and keep the Swift phrase's parameter, no
// German phrase is left in English or said twice, and each language names the app the way its
// Siri writes it (INAlternativeAppNames, job 71). German phrases stay out of Reminders' grammar,
// the add phrase without an item comes first, every spoken name carries a pronunciation hint
// (job 92), and the negative phrases never name the app. RunnerTests checks the same on macOS;
// this runs everywhere.
// Usage: deno run --allow-read scripts/siri-phrases.ts [ios-dir]
const ios = Deno.args[0] ?? new URL("../app/ios", import.meta.url).pathname;
const problems: string[] = [];
function read(path: string): string {
  try {
    return Deno.readTextFileSync(`${ios}/${path}`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    problems.push(`${path} is missing`);
    return "";
  }
}

/** `"key" = "value";` lines of a .strings file, comments skipped. */
function strings(path: string): Map<string, string> {
  const table = new Map<string, string>();
  const text = read(path).replace(/\/\*[\s\S]*?\*\//g, "").replace(
    /^\s*\/\/.*$/gm,
    "",
  );
  for (const line of text.split("\n").filter((l) => l.trim())) {
    const match = line.match(
      /^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$/,
    );
    if (!match) {
      problems.push(`${path}: unreadable line ${JSON.stringify(line)}`);
    } else if (table.has(match[1])) {
      problems.push(`${path}: "${match[1]}" twice`);
    } else table.set(match[1], match[2]);
  }
  return table;
}

const placeholders = (phrase: string) =>
  [...phrase.matchAll(/\$\{[A-Za-z]+\}/g)].map((m) => m[0]).sort();
const parameters = (phrase: string) =>
  placeholders(phrase).filter((p) => p !== "${applicationName}");

const source = read("Runner/AppIntents/SnacklistIntents.swift");
const literals = (code: string) =>
  [...code.matchAll(
    /"((?:[^"\\\n]|\\\(\.applicationName\)|\\\(\\\.\$\w+\))*)"/g,
  )].map((m) =>
    m[1].replaceAll("\\(.applicationName)", "${applicationName}").replace(
      /\\\(\\\.\$(\w+)\)/g,
      "${$1}",
    )
  );
const providerCode =
  source.match(/static var appShortcuts[\s\S]*?\n {2}\}\n/)?.[0] ?? "";
const negativeCode =
  source.match(/static var negativePhrases[\s\S]*?\n {2}\}\n/)?.[0] ?? "";
const phraseLists = [...providerCode.matchAll(/phrases: \[([\s\S]*?)\]/g)].map((
  m,
) => literals(m[1]));
const phrases = phraseLists.flat();
const negatives = literals(negativeCode);
const shortcuts = providerCode.split("AppShortcut(\n").length - 1;
if (phrases.length < 3) {
  problems.push(`SnacklistIntents.swift: only ${phrases.length} phrases found`);
}
if (shortcuts === 0 || shortcuts > 10) {
  problems.push(
    `SnacklistIntents.swift: ${shortcuts} App Shortcuts; Apple allows 1 to 10`,
  );
}
for (const phrase of phrases) {
  if (/snacklist/i.test(phrase)) {
    problems.push(
      `"${phrase}": spells the app's name; \\(.applicationName) says it`,
    );
  }
  if (!phrase.includes("${applicationName}")) {
    problems.push(`"${phrase}": every App Shortcut phrase names the app`);
  }
}
if (phraseLists.length !== shortcuts) {
  problems.push("SnacklistIntents.swift: an App Shortcut without phrases");
}
if (negatives.length === 0) {
  problems.push("SnacklistIntents.swift: no negativePhrases");
}
// Siri asks for the items after a phrase without one, so that works for any item; an item phrase
// matches only the names the app suggested.
const add = literals(
  source.match(/intent: AddItemsIntent\(\)([\s\S]*?)shortTitle:/)?.[1] ?? "",
);
const firstWithItem = add.findIndex((p) => p.includes("${item}"));
if (add.length === 0) {
  problems.push("SnacklistIntents.swift: no AddItemsIntent phrases found");
} else if (
  firstWithItem === 0 ||
  add.slice(firstWithItem).some((p) => !p.includes("${item}"))
) {
  problems.push(
    "SnacklistIntents.swift: the add phrases without an item must come first",
  );
}
for (const phrase of phrases) {
  if (parameters(phrase).length > 1) {
    problems.push(`"${phrase}": more than one parameter`);
  }
}

type Catalog = {
  sourceLanguage?: string;
  strings?: Record<
    string,
    {
      localizations?: Record<
        string,
        { stringSet?: { values?: string[] }; stringUnit?: { value?: string } }
      >;
    }
  >;
};
const catalogPath = "Runner/AppShortcuts.xcstrings";
let catalog: Catalog = {};
try {
  catalog = JSON.parse(read(catalogPath) || "{}");
} catch (error) {
  problems.push(`${catalogPath}: ${error}`);
}
for (const lang of ["en", "de"]) {
  try {
    Deno.statSync(`${ios}/Runner/${lang}.lproj/AppShortcuts.strings`);
    problems.push(
      `Runner/${lang}.lproj/AppShortcuts.strings: the catalog replaced it; delete it`,
    );
  } catch {
    // gone, as it should be
  }
}
const catalogEntries = catalog.strings ?? {};
const values = (key: string, lang: string) =>
  catalogEntries[key]?.localizations?.[lang]?.stringSet?.values ?? [];
/** A negative phrase's one plain translation (job 170): no string set, whose use for negatives is unproven. */
const negativeValues = (key: string, lang: string) => {
  const value = catalogEntries[key]?.localizations?.[lang]?.stringUnit?.value;
  return value ? [value] : [];
};
for (const key of Object.keys(catalogEntries)) {
  if (!phrases.includes(key) && !negatives.includes(key)) {
    problems.push(
      `${catalogPath}: "${key}" is no phrase in SnacklistIntents.swift`,
    );
  }
}

// Apple expands every parameter value into each phrase that has it, up to 1,000 phrases per app;
// the app sends at most 100 item names and synonyms (ItemSuggestionStore).
const spokenItems = 100;
const prepositions = new Set([
  "auf",
  "zu",
  "zur",
  "zum",
  "in",
  "im",
  "an",
  "mit",
  "für",
]);
const known: Record<string, Set<string>> = { en: new Set(), de: new Set() };
for (const lang of ["en", "de"]) {
  const said = new Map<string, string>();
  let expanded = 0;
  for (const phrase of phrases) {
    const set = values(phrase, lang);
    if (set.length === 0) {
      problems.push(`${catalogPath}: no ${lang} phrases for "${phrase}"`);
    }
    for (const value of set) {
      const where = `${catalogPath} ${lang} "${value}"`;
      known[lang].add(value.toLowerCase());
      expanded += parameters(value).length ? spokenItems : 1;
      if (/snacklist/i.test(value)) {
        problems.push(
          `${where}: spells the app's name; \${applicationName} says it`,
        );
      }
      if (value.split("${applicationName}").length !== 2) {
        problems.push(
          `${where}: names the app ${
            value.split("${applicationName}").length - 1
          } times, not once`,
        );
      }
      if (parameters(value).join() !== parameters(phrase).join()) {
        problems.push(
          `${where}: must keep ${
            parameters(phrase).join(", ") || "no parameter"
          }`,
        );
      }
      const spoken = value.toLowerCase().replace(/[,?.!]/g, "");
      if (said.has(spoken)) {
        problems.push(`${where}: also a phrase of "${said.get(spoken)}"`);
      }
      said.set(spoken, phrase);
      if (lang !== "de") continue;
      // German Siri hands "Einkaufsliste" and "Füge X zur <…>liste hinzu" to Reminders; a bare
      // "Auf meine Snacklist" is a fragment of that grammar.
      const first = value.split(" ")[0].toLowerCase();
      if (/liste/i.test(value)) {
        problems.push(`${where}: says Liste, which Reminders takes`);
      } else if (
        prepositions.has(first) && value.endsWith("${applicationName}")
      ) {
        problems.push(`${where}: is a fragment without a verb`);
      } else if (
        values(phrase, "en").some((en) =>
          en.toLowerCase() === value.toLowerCase()
        )
      ) {
        problems.push(`${where}: is not translated`);
      }
    }
  }
  if (expanded > 1000) {
    problems.push(
      `${catalogPath}: ${lang} expands to ${expanded} phrases with ${spokenItems} items; Apple allows 1,000`,
    );
  }
  for (const negative of negatives) {
    const set = negativeValues(negative, lang);
    if (set.length === 0) {
      problems.push(
        `${catalogPath}: no ${lang} stringUnit for the negative "${negative}" (one translation, not a set)`,
      );
    }
    if (lang === "de" && set.some((value) => value === negative)) {
      problems.push(
        `${catalogPath}: the de negative "${negative}" is not translated`,
      );
    }
    for (const value of set) {
      if (value.includes("${applicationName}") || /snacklist/i.test(value)) {
        problems.push(
          `${catalogPath} ${lang} negative "${value}" names the app and would block it`,
        );
      }
      if (said.has(value.toLowerCase().replace(/[,?.!]/g, ""))) {
        problems.push(
          `${catalogPath} ${lang} negative "${value}" is also an App Shortcut phrase`,
        );
      }
    }
  }
}

// The phrases the Zugänge page shows (app/lib/siri/siri_phrases.dart) must be ones Siri knows.
const dart = read("../lib/siri/siri_phrases.dart");
for (const lang of ["en", "de"]) {
  const block = dart.match(new RegExp(`\\b${lang}: \\[([\\s\\S]*?)\\]`))?.[1] ??
    "";
  const list = [...block.matchAll(/'((?:[^'\\]|\\.)*)'|"([^"]*)"/g)].map((m) =>
    m[1] ?? m[2]
  );
  if (list.length === 0) problems.push(`siri_phrases.dart: no ${lang} phrases`);
  for (const phrase of list) {
    const asTable = phrase.replace(/[?.!]$/, "").replace(/<[^>]+>/g, "${item}")
      .replaceAll("Snacklist", "${applicationName}").toLowerCase();
    if (!known[lang].has(asTable)) {
      problems.push(
        `siri_phrases.dart shows "${phrase}", which is no ${lang} phrase Siri knows`,
      );
    }
  }
}

const plist = read("Runner/Info.plist");
const alternatives = plist.match(
  /<key>INAlternativeAppNames<\/key>\s*<array>([\s\S]*?)<\/array>/,
)
  ?.[1];
const entries = [...(alternatives ?? "").matchAll(/<dict>([\s\S]*?)<\/dict>/g)]
  .map((m) => m[1]);
const entryValue = (entry: string, key: string) =>
  entry.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`))?.[1];
const variables = entries.map((e) => entryValue(e, "INAlternativeAppName"))
  .filter((v) => v !== undefined);
const hints = entries.map((e) =>
  entryValue(e, "INAlternativeAppNamePronunciationHint")
);
if (hints.some((h) => h === undefined)) {
  problems.push(
    "Info.plist: every INAlternativeAppNames entry needs INAlternativeAppNamePronunciationHint",
  );
}
const intents =
  plist.match(/<key>INIntentsSupported<\/key>\s*<array>([\s\S]*?)<\/array>/)
    ?.[1] ??
    "";
for (const intent of ["INAddTasksIntent", "INSearchForNotebookItemsIntent"]) {
  if (!intents.includes(`<string>${intent}</string>`)) {
    problems.push(
      `Info.plist: INIntentsSupported lacks ${intent} (AppDelegate handles it)`,
    );
  }
}
if (variables.length === 0) {
  problems.push("Info.plist: no INAlternativeAppNames");
}
if (
  !/<key>CFBundleSpokenName<\/key>\s*<string>Snacklist<\/string>/.test(plist)
) {
  problems.push('Info.plist: CFBundleSpokenName must be "Snacklist"');
}
if (variables.length > 3) {
  problems.push("Info.plist: Apple reads at most three INAlternativeAppNames");
}
for (const lang of ["en", "de", "Base"]) {
  const path = `Runner/${lang}.lproj/InfoPlist.strings`;
  const table = strings(path);
  for (const variable of variables) {
    const name = table.get(variable)?.trim();
    if (!name) problems.push(`${path}: no ${variable}`);
    else if (name.toLowerCase() === "snacklist") {
      problems.push(`${path}: ${variable} repeats the app name`);
    } else if (name.toLowerCase() === "snack") {
      problems.push(
        `${path}: ${variable} is "Snack"; the brand is never Snack alone`,
      );
    } else if (lang === "de" && /liste$/i.test(name)) {
      // German Siri hands "Füge X zur … Liste hinzu" to Reminders (job 97).
      problems.push(
        `${path}: ${variable} "${name}" ends in Liste, Reminders' grammar`,
      );
    }
  }
  for (const hint of hints) {
    if (hint && !table.get(hint)?.trim()) problems.push(`${path}: no ${hint}`);
  }
  for (const key of ["CFBundleSpokenName", "NSSiriUsageDescription"]) {
    if (!table.get(key)?.trim()) problems.push(`${path}: no ${key}`);
  }
  if (table.get("CFBundleSpokenName") !== "Snacklist") {
    problems.push(`${path}: CFBundleSpokenName must be "Snacklist"`);
  }
}

if (problems.length) {
  console.error(problems.map((p) => `siri-phrases: ${p}`).join("\n"));
  Deno.exit(1);
}
console.log(
  `siri-phrases: ${phrases.length} App Shortcut phrases with ${known.en.size} en and ${known.de.size} de variants, ${negatives.length} negative phrases, ${variables.length} spoken app names per language`,
);
