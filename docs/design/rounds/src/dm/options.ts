import type { L10n } from './data';

export const OPTION_ORDER = ['today', 'dm1', 'dm2', 'dm3', 'dm4', 'dm5'] as const;
export type OptionId = (typeof OPTION_ORDER)[number];

export interface OptionSpec {
  code: string;
  slug: string;
  name: L10n;
  line: L10n;
  /** The DM reading of the typed line: "Omega 3 2" adds 2, an untyped amount adds one more (one pack for g/kg/ml/l). */
  smart: boolean;
}

export const OPTIONS: Record<OptionId, OptionSpec> = {
  today: {
    code: 'Today',
    slug: 'today',
    name: { en: 'AE2 split row (main, b41a60e1)', de: 'AE2-Zeile heute (main, b41a60e1)' },
    line: {
      en: 'The matching row is outlined with „→ 2×“. The sheet shows a blue merge row („2× Omega 3 / dm“, merge icon), a mint tile with only a check mark (tick off), then „+ Omega 3 / As typed“. Enter merges. The typed Menge is merged as production does: „Omega 3 2“ gives 2×, and „Mehl“ on 500 g stays 500 g. One change from production: the top row\'s corners follow the sheet\'s (Peter, 28 Nov; production clips them, job 497 fixes it).',
      de: 'Die passende Zeile ist umrandet, mit „→ 2×“. Im Blatt: eine blaue Zusammenführen-Zeile („2× Omega 3 / dm“, Symbol), ein mintgrünes Feld nur mit Haken (abhaken), dann „+ Omega 3 / Wie getippt“. Enter führt zusammen. Die Menge rechnet wie in der App: „Omega 3 2“ ergibt 2×, „Mehl“ auf 500 g bleibt 500 g. Eine Abweichung von der App: die Ecken der obersten Zeile folgen denen des Blatts (Peter, 28. Nov; die App schneidet sie ab, Job 497 behebt das).',
    },
    smart: false,
  },
  dm1: {
    code: 'DM1',
    slug: 'dm1-row-actions',
    name: { en: 'Actions under the row (required)', de: 'Aktionen unter der Zeile (Pflicht)' },
    line: {
      en: 'The match gets its actions right under its own row in the list: „+1 → 2×“, „+2 → 3×“ (or „+500 g → 1 kg“) and „Tick off“. The amount comes from what you typed („Omega 3 2“ puts „+2“ first), else from two preset chips. The sheet keeps only „As a new entry“.',
      de: 'Der Treffer bekommt seine Aktionen direkt unter seiner Zeile in der Liste: „+1 → 2×“, „+2 → 3×“ (oder „+500 g → 1 kg“) und „Abhaken“. Die Menge kommt aus dem Getippten („Omega 3 2“ stellt „+2“ vorn hin), sonst aus zwei Vorschlägen. Im Blatt bleibt nur „Als neuen Eintrag“.',
    },
    smart: true,
  },
  dm2: {
    code: 'DM2',
    slug: 'dm2-worded-buttons',
    name: { en: 'Today, with words on every button', de: 'Heute, mit Worten auf jedem Knopf' },
    line: {
      en: 'The smallest change. Same split row, but the merge part says „Add 1“ above „2× Omega 3 · dm“, the mint tile becomes a „✓ Tick off“ button with its word, and „As typed“ reads „As a second entry“.',
      de: 'Die kleinste Änderung. Dieselbe geteilte Zeile, aber der blaue Teil sagt „+1 dazu“ über „2× Omega 3 · dm“, das Mintfeld wird ein Knopf „✓ Abhaken“ mit Wort, und „Wie getippt“ heißt „Als zweiter Eintrag“.',
    },
    smart: true,
  },
  dm3: {
    code: 'DM3',
    slug: 'dm3-sentence',
    name: { en: 'One sentence, then what each tap does', de: 'Ein Satz, dann was jeder Tipp tut' },
    line: {
      en: 'A line says „Omega 3 is already on the list (1×, dm).“ Under it three full-width rows each say their result: „Raise it to 2×“, „Tick off: I have it already“, „Add Omega 3 as a separate entry“. The hint names what Enter does.',
      de: 'Eine Zeile sagt „Omega 3 steht schon auf der Liste (1×, dm).“ Darunter sagen drei breite Zeilen ihr Ergebnis: „Auf 2× erhöhen“, „Abhaken: hab ich schon“, „Omega 3 zusätzlich als eigenen Eintrag“. Der Hinweis nennt, was Enter tut.',
    },
    smart: true,
  },
  dm4: {
    code: 'DM4',
    slug: 'dm4-on-list-card',
    name: { en: '„Already on the list“ card', de: 'Karte „Schon auf der Liste“' },
    line: {
      en: 'A card titled „Already on the list“ shows the item as its list row (emoji, Menge, store) with two buttons inside: „+1 → 2×“ and „Tick off“. Below a divider „Or add new“ come „As typed“ and the catalog rows.',
      de: 'Eine Karte „Schon auf der Liste“ zeigt den Artikel wie seine Listenzeile (Emoji, Menge, Laden), mit zwei Knöpfen darin: „+1 → 2×“ und „Abhaken“. Unter „Oder neu hinzufügen“ folgen „Wie getippt“ und die Katalogzeilen.',
    },
    smart: true,
  },
  dm5: {
    code: 'DM5',
    slug: 'dm5-choose-confirm',
    name: { en: 'Choose, then one worded button', de: 'Wählen, dann ein Knopf mit Wort' },
    line: {
      en: 'A question „Omega 3 is already on it. What would you like?“ with three choices („More of it“ preselected, „Tick off“, „New entry“). „More of it“ shows an amount with „less“ and „more“. One big button below says exactly what will happen: „Raise to 2×“, „Tick off Omega 3“, „Add Omega 3 as new“. Enter presses it.',
      de: 'Eine Frage „Omega 3 steht schon drauf. Was möchtest du?“ mit drei Wahlen („Mehr davon“ vorgewählt, „Abhaken“, „Neuer Eintrag“). „Mehr davon“ zeigt eine Menge mit „weniger“ und „mehr“. Ein großer Knopf darunter sagt genau, was passiert: „Auf 2× erhöhen“, „Omega 3 abhaken“, „Omega 3 neu hinzufügen“. Enter drückt ihn.',
    },
    smart: true,
  },
};
