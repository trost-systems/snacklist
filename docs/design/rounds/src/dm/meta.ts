import type { L10n } from './data';

/** The rows come from `node scripts/verify-dm.mjs --print`; the verify fails when they differ from what it measures. */
export const MEASURED = {
  method:
    'Measured by scripts/verify-dm.mjs in the built sandbox at 390×844, starting from the add sheet open with „Omega 3“ typed (on the list once, at dm), keyboard hidden, German, light, 100 % unless a column says otherwise. Taps are clicks the script makes and then checks in the list (2×, gone, 3×).',
  columns: [
    'Option',
    'Taps to merge',
    'Taps to tick off',
    'Taps for 2 more, nothing typed',
    'Enter on „Omega 3 2“ · „Mehl“ (500 g) · „Mehl 1kg“',
    'Every action has a visible word',
    'Labels: merge / tick off / new entry',
    'List rows in view (kbd hidden · shown · shown at 200 %)',
    'Large text, kbd hidden (DE+EN, light+dark): merge, tick off, new in view without scrolling',
    'Screen-reader names in words',
  ],
  rows: [
      [
          "Today",
          "1",
          "1",
          "– (type „Omega 3 x2“)",
          "2× · 500 g · 1,5 kg",
          "no",
          "DE „2× Omega 3 dm“ / (icon only) / „Omega 3 Wie getippt“ · EN „2× Omega 3 dm“ / (icon only) / „Omega 3 As typed“",
          "8 · 3 · 2",
          "200 %: 3/3 in view, 0 clipped · 310 %: 3/3 in view, 0 clipped",
          "yes"
      ],
      [
          "DM1",
          "1",
          "1",
          "1",
          "3× · 1 kg · 1,5 kg",
          "yes",
          "DE „+1 → 2×“ / „Abhaken“ / „Omega 3 Als neuen Eintrag“ · EN „+1 → 2×“ / „Tick off“ / „Omega 3 As a new entry“",
          "7 · 3 · 1",
          "200 %: 3/3 in view, 0 clipped · 310 %: 2/3 in view, 0 clipped",
          "yes"
      ],
      [
          "DM2",
          "1",
          "1",
          "– (type „Omega 3 x2“)",
          "3× · 1 kg · 1,5 kg",
          "yes",
          "DE „+1 dazu 2× Omega 3 dm“ / „Abhaken“ / „Omega 3 Als zweiter Eintrag“ · EN „Add 1 2× Omega 3 dm“ / „Tick off“ / „Omega 3 As a second entry“",
          "8 · 3 · 2",
          "200 %: 2/3 in view, 0 clipped · 310 %: 2/3 in view, 0 clipped",
          "yes"
      ],
      [
          "DM3",
          "1",
          "1",
          "– (type „Omega 3 x2“)",
          "3× · 1 kg · 1,5 kg",
          "yes",
          "DE „Auf 2× erhöhen“ / „Abhaken: hab ich schon“ / „Omega 3 zusätzlich als eigenen Eintrag“ · EN „Raise it to 2×“ / „Tick off: I have it already“ / „Add Omega 3 as a separate entry“",
          "6 · 2 · 0",
          "200 %: 3/3 in view, 0 clipped · 310 %: 2/3 in view, 0 clipped",
          "yes"
      ],
      [
          "DM4",
          "1",
          "1",
          "– (type „Omega 3 x2“)",
          "3× · 1 kg · 1,5 kg",
          "yes",
          "DE „+1 → 2×“ / „Abhaken“ / „Omega 3 Wie getippt“ · EN „+1 → 2×“ / „Tick off“ / „Omega 3 As typed“",
          "6 · 2 · 0",
          "200 %: 3/3 in view, 0 clipped · 310 %: 2/3 in view, 0 clipped",
          "yes"
      ],
      [
          "DM5",
          "1",
          "2",
          "2",
          "3× · 1 kg · 1,5 kg",
          "yes",
          "DE „Auf 2× erhöhen“ / „Omega 3 abhaken“ / „Omega 3 neu hinzufügen“ · EN „Raise to 2×“ / „Tick off Omega 3“ / „Add Omega 3 as new“",
          "6 · 2 · 0",
          "200 %: 3/3 in view, 0 clipped · 310 %: 2/3 in view, 0 clipped",
          "yes"
      ]
  ],
  notes: [
    'Today is the AE2 split row as main (b41a60e1, #789) draws it; the real web build is in docs/screenshots/490/ae2-*-duplicate-split-row.png. Its Menge column is production\'s own rule, measured on main with parseEntry and mergeQuantities: „Omega 3 2“ keys to „omega“ and matches Omega 3, but the 2 is not read as an amount (a number after a word with a digit is a size, like „Windeln Größe 4“), so Enter gives 2× and „As typed“ would add an item named „Omega 3 2“. „Mehl“ on „500 g Mehl“ merges to 500 g: nothing changes.',
    'DM1–DM5 read a bare number after a name on the list as its amount, and an untyped merge on a weight or volume as one more pack (DM-Q3, DM-Q4). DM5 tick off is 2 taps (choose, then confirm). Only DM1 (preset chip) and DM5 (stepper) add 2 without typing; elsewhere one types „Omega 3 x2“.',
    'List rows counts complete rows of the list not covered by the sheet, the keyboard or the top bar. DM1 counts its matched row once; its chips under it are extra height. Today\'s tick tile has only a check mark: its screen-reader name is „Abhaken, Omega 3“, but nothing on screen says so.',
    'Clipped counts text cut or pushed past the phone edge; none in any option. The add field itself is a fixed 52 px in production and cuts its own text at 310 % in every option (AE-Q8); it is not counted. The page controls stay English; the phones follow the language.',
  ],
};

export const RECOMMENDATION: Record<'en' | 'de', string[]> = {
  en: [
    'DM1, actions under the row. The actions sit on the item they change, so how they relate to the list is shown, not explained. Every action has a word („+1 → 2×“, „+2 → 3×“, „Tick off“), merge, tick off and 2 more each take one tap, a typed amount comes first („Omega 3 2“ gives „+2 → 3×“), and a weight steps by its pack („+500 g → 1 kg“). It keeps 7 list rows in view (Today 8), and at 200 % with the keyboard up the matched row and its chips stay in view (DM3–DM5: no list row).',
    'Runner-up: DM3, one sentence. Its words are the plainest („Omega 3 is already on the list (1×, dm).“, „Tick off: I have it already“) and all three choices stay in view at 200 %, but it covers more of the list (6 · 2 · 0) and links to the row only by the outline. Its tick-off wording could go onto DM1\'s chip if „Abhaken“ alone stays unclear (DM-Q5).',
  ],
  de: [
    'DM1, Aktionen unter der Zeile. Die Aktionen stehen an dem Artikel, den sie ändern: wie sie mit der Liste zusammenhängen, sieht man, statt es zu lesen. Jede Aktion hat ein Wort („+1 → 2×“, „+2 → 3×“, „Abhaken“), Zusammenführen, Abhaken und 2 mehr kosten je einen Tipp, eine getippte Menge kommt zuerst („Omega 3 2“ ergibt „+2 → 3×“), und Gewichte zählen in Packungen („+500 g → 1 kg“). 7 Listenzeilen bleiben sichtbar (heute 8), und bei 200 % mit Tastatur bleiben die Zeile und ihre Knöpfe im Bild (DM3–DM5: keine Listenzeile).',
    'Zweite Wahl: DM3, ein Satz. Die klarsten Worte („Omega 3 steht schon auf der Liste (1×, dm).“, „Abhaken: hab ich schon“), und alle drei Wahlen bleiben bei 200 % im Bild, aber es verdeckt mehr Liste (6 · 2 · 0) und zeigt den Bezug zur Zeile nur über die Umrandung. Seine Abhaken-Worte könnten auf DM1s Knopf, falls „Abhaken“ allein unklar bleibt (DM-Q5).',
  ],
};

const q = (id: string, en: string, de: string, dEn: string, dDe: string) => ({ id, en, de, default: { en: dEn, de: dDe } });

export const QUESTIONS: ({ id: string; default: L10n } & L10n)[] = [
  q('DM-Q1', 'Which option should the app build?', 'Welche Option soll die App bekommen?', 'DM1', 'DM1'),
  q('DM-Q2', 'How is the amount chosen: from the input, from chips or a stepper at the row, or both?', 'Woher kommt die Menge: aus der Eingabe, aus Knöpfen oder einem Zähler an der Zeile, oder beides?', 'both: a typed amount first, else „+1“ and „+2“ chips (a weight in packs); no stepper', 'beides: eine getippte Menge zuerst, sonst Knöpfe „+1“ und „+2“ (Gewichte in Packungen); kein Zähler'),
  q('DM-Q3', 'Should „Omega 3 2“ mean Omega 3, 2 more, when Omega 3 is on the list? Today the 2 is dropped.', 'Soll „Omega 3 2“ Omega 3, 2 mehr heißen, wenn Omega 3 auf der Liste steht? Heute fällt die 2 weg.', 'yes, in parse_item and parseEntry together (a bare number after a name on the list)', 'ja, in parse_item und parseEntry zugleich (eine Zahl nach einem Namen von der Liste)'),
  q('DM-Q4', 'What does merging „Mehl“ add to „500 g Mehl“? Today nothing changes.', 'Was fügt „Mehl“ zu „500 g Mehl“ hinzu? Heute ändert sich nichts.', 'one more pack: +500 g → 1 kg', 'eine Packung mehr: +500 g → 1 kg'),
  q('DM-Q5', 'Is „Abhaken“ / „Tick off“ alone clear enough, or does it need its meaning („hab ich schon“)?', 'Reicht „Abhaken“ allein, oder braucht es seine Bedeutung („hab ich schon“)?', '„Abhaken“ alone, as everywhere on the list; the screen-reader name and the note „Omega 3 abgehakt“ say the rest', '„Abhaken“ allein, wie überall in der Liste; Screenreader-Name und der Hinweis „Omega 3 abgehakt“ sagen den Rest'),
  q('DM-Q6', 'What does Enter do on a match?', 'Was tut Enter bei einem Treffer?', 'the first amount chip (merge), as today', 'den ersten Mengen-Knopf (zusammenführen), wie heute'),
  q('DM-Q7', 'With two matches (the same thing open twice, or one in „Recently used“), where do the chips go?', 'Bei zwei Treffern (zweimal offen, oder einer unter „Zuletzt verwendet“): wo stehen die Knöpfe?', 'under the oldest open one; the others keep their rows in the sheet', 'unter dem ältesten offenen; die anderen behalten ihre Zeilen im Blatt'),
  q('DM-Q8', 'Should the merged row keep a tag after the tap?', 'Soll die Zeile nach dem Tipp eine Marke behalten?', 'yes, its new Menge („2×“) until the sheet closes, like „Neu“', 'ja, ihre neue Menge („2×“), bis das Blatt schließt, wie „Neu“'),
  q('DM-Q9', 'Flag, or straight to everyone?', 'Flag oder gleich für alle?', 'a new flag on top of add-ae2-list-peeks, Peter and internal testers first', 'ein neues Flag auf add-ae2-list-peeks, zuerst Peter und interne Tester'),
];
