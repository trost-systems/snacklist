export const MEASURED = {
  method:
    'scripts/verify-ae.mjs, Chromium, 390×844 phone, device scale 1, list “Many items” (15 open items: REWE 10, dm 3, no store 2), English, light, 100 % unless a column says otherwise. A row counts as visible when its top and bottom are on the screen and nothing (scrim, sheet, keyboard, header button) is drawn over them; AE5’s rows sit under the scrim, so they count as dimmed. Taps: one on the add bar, then send on the keyboard for Milk, Eggs and Cheese (typing is not counted). Add surface: the height of everything the add state draws over the list (sheet, add bar, hint band or keyboard, AE1’s and AE4’s cards, AE3’s field row with its suggestions), with the keyboard hidden; open = before typing, typing = “Milk”. Largest text: every option at 200 % (Android’s largest) and 310 % (iOS AX5), EN and DE, light and dark, opened, typing and after 2 adds, keyboard shown and hidden; clipped = text cut sideways or by a box, or the add bar or keyboard pushed off the screen.',
  columns: [
    'Option',
    'Existing list rows visible while adding (keyboard hidden · shown · shown at 200 %)',
    'Taps to add 3 items from the closed list; the 3 in their list place while still adding',
    'Taps until all 3 are seen on the list',
    'Add surface over the list, px (opened · typing), vs Today',
    'Enter on “Bananas” (on the list as 6×)',
    'Largest text (200 and 310 %, EN and DE, light and dark); the add field’s text width at 310 %',
  ],
  rows: [
    ["Today", "0 · 0 · 0", "4; 0 of 3 in their list place while adding", "5", "195 · 328 (±0 · ±0)", "2 rows (6× + 1)", "0 clipped; field text cut at 310 %; field 241 px wide at 310 % (narrowest, about 7 letters)"],
    ["AE1", "0 · 0 · 0", "4; 0 of 3 in their list place while adding", "5", "297 · 411 (+102 · +83)", "2 rows (6× + 1)", "0 clipped; field text cut at 310 %; field 241 px wide at 310 % (narrowest, about 7 letters)"],
    ["AE2", "10 · 5 · 3", "4; 3 of 3 in their list place while adding", "4", "195 · 268 (±0 · −60)", "one row, 7×; its row in view while typing", "0 clipped; field text cut at 310 %; field 241 px wide at 310 % (narrowest, about 7 letters)"],
    ["AE3", "10 · 7 · 7", "4; 3 of 3 in their list place while adding", "4", "140 · 321 (−55 · −7)", "one row, 7×; its row in view while typing", "0 clipped; field text cut at 310 %; field 52 px wide at 310 % (narrowest, about 1 letter)"],
    ["AE4", "0 · 0 · 0", "4; 0 of 3 in their list place while adding (2 in the card)", "5", "298 · 532 (+103 · +204)", "one row, 7×; its row in view while typing", "0 clipped; field text cut at 310 %; field 241 px wide at 310 % (narrowest, about 7 letters)"],
    ["AE5", "10 dimmed · 5 dimmed · 3 dimmed", "4; 3 of 3 in their list place while adding, each flies there", "4", "195 · 328 (±0 · ±0)", "one row, 7×; its row in view while typing", "0 clipped; field text cut at 310 %; field 241 px wide at 310 % (narrowest, about 7 letters)"],
  ] as string[][],
  notes: [
    'Today, measured on the real web build (origin/main 151458422, verify-snacklist on a local stack, 27 Nov 2026): while the sheet is open the list is replaced, not covered (BehindSheet, lastTwo); before the first add the area above the sheet is the empty page under the 40 % black scrim, after it only the last two adds, without heading or store. The sheet top sits at 647 px opened, 516 px typing (three 60 px rows), 648 px after an add (the chip row); the replica uses the same sizes. Typing an item already on the list shows Merge (7×), Tick off and “As typed”, with the honey default on “As typed”: Enter made a second “Bananas” row next to the 6× one (database: two active rows).',
    'Where a new item lands: production sorts a store by category, then by when it was added, and hides only the category headings (hide-categories), so a new item lands at the end of its category’s group, not at the end of the store: Milk, Eggs and Cheese land after Butter, before Pasta. Nothing on screen says so today; AE2, AE3 and AE5 show it, AE4 previews it.',
    'The keyboard is iOS’s 291 pt on a 390 pt phone; with it up the sheet sits on it and the hint band goes, as in the app. In the sandbox it is drawn (its keys type), so a phone visiting the page does not open its own.',
    'The add field is 52 px high in production (_composeHeight), whatever the text size: at 310 % its 56 px text is cut in every option. The suggestion rows grow with the text and the sheet scrolls, as production’s does.',
    'AE3 at 310 %: the inline field shares its row with „Done“ / „Fertig“, so its text area is 52 px wide, about one letter of 56 px text („M“ of „Milch“); the other options keep 241 px (about 7 letters). AE3 would need the button under the field at large text (or an icon only).',
    'Taps to add 3 is 4 in every option: the bar, then send three times. What differs is whether the adds are seen without one more tap to close: “Taps until all 3 are seen”.',
    'The duplicate column follows each option’s Enter default, not its layout: Today and AE1 would also give 7× if Merge became the default (AE-Q2).',
    'The page’s own controls and headings stay English; the EN/DE switch translates the phones and the option texts.',
    'AE1 changes no layout, so it keeps Today’s 0 rows; its card at the top of the scrim is the +102 px. AE4’s card shows no list row until something is typed; while typing it shows the rows around the landing spot (2 of them, plus the ghost).',
    'At 310 % with the keyboard up, three suggestion rows fill the room above the keyboard: while typing, AE4’s card scrolls out of view above the sheet (screenshots ae4-typing-*-310). AE3, without a sheet, keeps 7 rows at 200 %. The list switcher ellipsizes its two lines at large text, as production does (list_switcher_button.dart).',
    'AE5’s flight is 520 ms on the standard easing; with reduced motion there is no flight and the row only lifts (checked by the verify).',
  ],
};

export const RECOMMENDATION = {
  en: [
    'AE2, the list stays in view. It answers the user’s confusion where it starts: the list never disappears, so there is nothing to explain. With the keyboard up 5 rows stay visible (Today 0), each add appears in its real place with “New”, all 3 adds are in view while still adding, and all 3 are seen without closing (4 taps until seen, Today 5). Typing an item already on the list scrolls its row into view and Enter adds 1 to it (7×) instead of a second row (that part comes from the Merge default, AE-Q2, which Today could take too). It keeps today’s sheet, rows, chips and gestures, and is no taller: the sheet shows two suggestions instead of three, 60 px less while typing.',
    'Runner-up: AE3, adding inside the list. It shows the relation most literally (the field sits where the item lands, under the row it matches) and keeps the most list at 200 % (7 rows, AE2 3), though at 310 % its field next to „Done“ shows about one letter. It came second because it is the largest rebuild (no sheet, the add bar and its gestures go), its field moves between spots as you add, and its suggestions take list room (321 px while typing).',
    'Not recommended: AE1 explains, but the list is still gone and a duplicate still becomes a second row by default; its words are worth keeping for the duplicate rows in any option. AE4 makes the landing spot explicit, but its card is 204 px more while typing and still hides the list. AE5 is the most delightful, but the list stays dimmed and motion is the only link; its flight could be added to AE2 later.',
  ],
  de: [
    'AE2, die Liste bleibt sichtbar. Sie löst die Verwirrung dort, wo sie entsteht: die Liste verschwindet nie, also muss nichts erklärt werden. Mit Tastatur bleiben 5 Zeilen sichtbar (heute 0), jeder neue Artikel erscheint an seinem echten Platz mit „Neu“, alle 3 sind schon beim Hinzufügen zu sehen, und alle 3 sind ohne Schließen zu sehen (4 Tipps bis dahin, heute 5). Wer einen Artikel tippt, der schon auf der Liste steht, sieht seine Zeile, und Enter zählt 1 dazu (7×) statt ihn ein zweites Mal anzulegen (das kommt vom Zusammenführen als Standard, AE-Q2, das auch heute ginge). Fenster, Zeilen, Chips und Gesten bleiben wie heute, und es wird nicht höher: zwei Vorschläge statt drei, beim Tippen 60 px weniger.',
    'Zweite Wahl: AE3, direkt in der Liste hinzufügen. Es zeigt den Zusammenhang am wörtlichsten (das Feld steht dort, wo der Artikel landet, unter der passenden Zeile) und lässt bei 200 % am meisten Liste sichtbar (7 Zeilen, AE2 3), auch wenn sein Feld neben „Fertig“ bei 310 % nur etwa einen Buchstaben zeigt. Es ist Zweiter, weil es der größte Umbau ist (kein Fenster, das Eingabefeld unten und seine Gesten fallen weg), sein Feld beim Hinzufügen den Platz wechselt und seine Vorschläge Platz in der Liste brauchen (321 px beim Tippen).',
    'Nicht empfohlen: AE1 erklärt, aber die Liste ist weiterhin weg, und ein Doppelter wird standardmäßig weiterhin ein zweiter Eintrag; seine Worte für die Zeilen bei Doppelten lohnen sich in jeder Option. AE4 macht den Zielplatz deutlich, aber seine Karte ist beim Tippen 204 px höher und verdeckt die Liste weiter. AE5 ist am schönsten, aber die Liste bleibt abgedunkelt und nur die Bewegung verbindet; sein Flug könnte später zu AE2 dazukommen.',
  ],
};

export const QUESTIONS: { id: string; en: string; de: string; default: { en: string; de: string } }[] = [
  { id: 'AE-Q1', en: 'Which option should the app build?', de: 'Welche Option soll die App bekommen?', default: { en: 'AE2', de: 'AE2' } },
  {
    id: 'AE-Q2',
    en: 'Enter on an item already on the list: add 1 to it (Merge first, honey) instead of today’s second row, in whichever option is built?',
    de: 'Enter auf einem Artikel, der schon auf der Liste steht: 1 dazuzählen (Zusammenführen zuerst, gelb) statt heute einen zweiten Eintrag, in jeder gebauten Option?',
    default: { en: 'yes; “As typed” stays one tap away', de: 'ja; „Wie getippt“ bleibt einen Tipp entfernt' },
  },
  {
    id: 'AE-Q3',
    en: 'With the list visible above the sheet (AE2), what does a tap on the list do: close the sheet, or tick the row?',
    de: 'Wenn die Liste über dem Fenster sichtbar ist (AE2), was macht ein Tipp auf die Liste: das Fenster schließen oder die Zeile abhaken?',
    default: { en: 'close the sheet; scrolling works while adding', de: 'Fenster schließen; Scrollen geht beim Hinzufügen' },
  },
  {
    id: 'AE-Q4',
    en: 'AE2 shows two suggestion rows before the sheet scrolls, Today three. Two always, or two only while the keyboard is up?',
    de: 'AE2 zeigt zwei Vorschläge, bevor das Fenster scrollt, heute drei. Immer zwei oder nur zwei, solange die Tastatur offen ist?',
    default: { en: 'two always', de: 'immer zwei' },
  },
  {
    id: 'AE-Q5',
    en: 'How long does an added row keep its honey wash and “New”: until the sheet closes, or a few seconds?',
    de: 'Wie lange behält eine hinzugefügte Zeile ihre gelbe Fläche und „Neu“: bis das Fenster schließt oder ein paar Sekunden?',
    default: { en: 'until the sheet closes', de: 'bis das Fenster schließt' },
  },
  {
    id: 'AE-Q6',
    en: 'When an add lands outside the visible part of the list (another store, or the person scrolled away), should the list scroll to it?',
    de: 'Wenn ein Artikel außerhalb des sichtbaren Teils landet (anderer Laden, oder weggescrollt), soll die Liste dorthin scrollen?',
    default: { en: 'yes, just far enough to show it', de: 'ja, gerade so weit, dass er zu sehen ist' },
  },
  {
    id: 'AE-Q7',
    en: 'At 200 % the top bar grows and leaves 3 list rows with the keyboard up. Cap the top bar’s text size (as the sync pill is) to keep more of the list?',
    de: 'Bei 200 % wächst die obere Leiste, mit Tastatur bleiben 3 Zeilen. Die Schriftgröße der Leiste begrenzen (wie beim Sync-Hinweis), damit mehr Liste bleibt?',
    default: { en: 'no; take it up in a large-text pass', de: 'nein; in einem eigenen Durchgang für große Schrift' },
  },
  {
    id: 'AE-Q8',
    en: 'The add field is fixed at 52 px and cuts its text at 310 % in every option. Fix it with this change or separately?',
    de: 'Das Eingabefeld ist fest 52 px hoch und schneidet bei 310 % den Text ab, in jeder Option. Mit dieser Änderung beheben oder getrennt?',
    default: { en: 'separately', de: 'getrennt' },
  },
  {
    id: 'AE-Q9',
    en: 'Roll out behind a flag (on for Peter and internal testers first), or straight to everyone?',
    de: 'Hinter einem Flag ausrollen (zuerst für Peter und interne Tester) oder direkt für alle?',
    default: { en: 'behind a flag', de: 'hinter einem Flag' },
  },
];
