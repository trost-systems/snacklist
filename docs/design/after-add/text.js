// The page's own words (not app UI), English and German.
const en = {
  lang: 'Lang', light: 'Light', dark: 'Dark', textSize: 'Text', androidMax: 'Android’s largest', iosMax: 'iOS’s largest',
  overview: 'All rounds', overviewTitle: 'After-add sheet: prototypes (job 319)',
  roundTitle: 'Round AS: the sheet after an add',
  roundBlurb: 'Five ways to edit the item you just added without the close key, the “Just added” header, the “Added / Undo” row or the gap above the field. Every field in view with the keyboard up.',
  note: 'A throwaway prototype with mock data (the fictional Familie Brandt). Nothing here ships. The live phone on the left of each option works: type in the field (try “Oat”, “Br”, “E”), Enter or a row adds, the chips edit, a swipe down on the grabber or a tap on the list above closes. Store names are plain text (N-292).',
  pick: 'Pick', runner: 'Runner-up', yes: 'yes', no: 'no', reset: 'Start again',
  liveCap: 'Live', liveHint: 'Click like a thumb. Any word adds an item; Oat, Br and E suggest from the catalog. Swipe down on the grabber (or click it, or the list) to close.',
  today: 'Today (main, flag add-feedback-list)',
  todayCap: 'Today, after adding',
  todayFacts: `<p>What the sheet shows today after an add (<code>app/lib/list/add_sheet/add_sheet.dart</code>, <code>_AddedDetails</code> and <code>ItemDetailFields._line</code>; the list's <code>justAdded</code> section in <code>shopping_list_view.dart</code>), top to bottom:</p>
    <ul><li>Behind the sheet: the items already on the list, then a “JUST ADDED” header and the new row.</li>
    <li>The grabber, and a header line that holds only the close key (X) at its end.</li>
    <li>“✓ Added: Oat milk → Edeka” with Undo (<code>_AddedNote</code>).</li>
    <li>The label “Qty”, then one line that scrolls sideways: the quantity field, −, +, the store chip, the category chip, Brand (“no brand”) and Details (“e.g. organic, 1 l”). Brand and Details start past the right edge.</li>
    <li>Room for three suggestion rows that the line doesn’t fill (the gap above the field, kept so the sheet doesn’t jump), then the field with the microphone.</li></ul>
    <p>Not in the sheet: the price (the row’s Price pill), the note about a duplicate (“already on the list”, Merge), which takes the added note’s place when it comes.</p>`,
  frameOrder: [
    ['open', '1 · Opened', 'The list behind is empty.'],
    ['added', '2 · First add', 'Only the new row behind the sheet.'],
    ['picking', '3 · Store options', (id) => (id === 'AS5' ? 'Already out: nothing to open.' : 'One tap opens them, in one line that swipes sideways.')],
    ['pickingCat', '3b · Category options', (id) => (id === 'AS5' ? 'Already out.' : id === 'AS2' ? 'The same panel.' : 'The item’s own is scrolled into view.')],
    ['edited', '4 · Qty 2, Lidl, Chilled', ''],
    ['details', '5 · Details', (id) => (['AS2', 'AS3'].includes(id) ? 'Brand and details, two fields.' : 'Brand goes into details.')],
    ['typing', '6 · Typing the next one', 'Suggestions take the fields’ room.'],
    ['second', '7 · Second add', 'Two rows behind; the fields follow the new item.'],
    ['third', '8 · Third add', 'Still only the last two.'],
    ['dismiss', '9 · Closing', 'Swipe the sheet down, or tap the list.'],
    ['closed', '10 · Closed', 'The whole list is back.'],
  ],
  meterLine: ({ h, saved, taps, brand, fits }) => `Editing above the keyboard after an add: <b>${h} px</b>, <b>${saved} px</b> less than today. Store and category: <b>${taps} taps</b>. Brand field: <b>${brand ? 'kept' : 'into details'}</b>. Every field in view: <b>${fitsText(fits, 'en')}</b>.`,
  fitsCell: (f) => fitsText(f, 'en'),
  tableTitle: 'Measured',
  tableNote: 'Measured by verify.mjs in Chromium on the frames above, after the first add (frame 2). “Editing takes” is from the top of the sheet (AS4: of the card on the list) to the keyboard. “In view” means every field of the item, and each open picker with the item’s own option, sits inside the screen above the keyboard and the sheet doesn’t scroll, checked at 100 %, 200 % and 310 % text.',
  tableHead: ['Option', 'Editing takes, iPhone 390 × 844', 'Editing takes, Android 360 × 640', 'Taps: store + category', 'Brand field', 'In view, iPhone', 'In view, Android', 'List above, Android, after 2 adds'],
  plusSwipe: '(+1 swipe on Android)',
  german: 'German',
  listLeft: (d) => `${d.freeList} px${d.rowsCut ? `, ${d.rowsCut} row under the status bar` : ''}`,
  options: {
    AS1: { name: 'Chip row', what: 'One line of chips under the grabber: the quantity with − and +, the store, the category and Details. Brand goes into Details. A chip folds its options out above the field, as today.' },
    AS2: { name: 'Field on top', what: 'The field is the sheet’s top line and the new item’s fields sit under it, nearest the thumb. Store and category share one chip that opens both lists, so both take three taps. Brand stays. Sending an empty field also closes the sheet.' },
    AS3: { name: 'Field grid', what: 'A fixed grid of two columns: quantity, store, category, brand and details, all in view, each one tap away. Options fold out under the grid. Brand stays. The tallest option.' },
    AS4: { name: 'Edit on the row', what: 'The sheet keeps only the field. The row just added opens into a card on the list right above the sheet, with the quantity, store, category and Details. The next add folds it back into a row. Brand goes into Details.' },
    AS5: { name: 'One-tap rows', what: 'The store and category options are always out, as two rows that swipe sideways; the item’s own are honey. Quantity and Details share the top line. Store and category take two taps. Brand goes into Details. Both rows run past the screen edge (REWE is cut on the iPhone too), so a store or category further along needs a swipe.' },
  },
  recFile: 'RECOMMENDATION.md',
};

const de = {
  ...en,
  lang: 'Sprache', light: 'Hell', dark: 'Dunkel', textSize: 'Text', androidMax: 'größte bei Android', iosMax: 'größte bei iOS',
  overview: 'Alle Runden', overviewTitle: 'Sheet nach dem Hinzufügen: Prototypen (Job 319)',
  roundTitle: 'Runde AS: das Sheet nach dem Hinzufügen',
  roundBlurb: 'Fünf Wege, den gerade hinzugefügten Artikel zu bearbeiten, ohne Schließen-Taste, ohne „Gerade hinzugefügt“, ohne die Zeile „Hinzugefügt / Rückgängig“ und ohne die Lücke über dem Feld. Alle Felder sichtbar, während die Tastatur offen ist.',
  note: 'Ein Wegwerf-Prototyp mit Beispieldaten (die erfundene Familie Brandt). Nichts davon wird ausgeliefert. Das Live-Telefon links in jeder Option funktioniert: tippe ins Feld („Hafer“, „Br“, „E“), Enter oder eine Zeile fügt hinzu, die Chips bearbeiten, Wischen am Griff nach unten oder Tippen auf die Liste darüber schließt. Ladennamen sind reiner Text (N-292).',
  pick: 'Empfehlung', runner: 'Zweite Wahl', yes: 'ja', no: 'nein', reset: 'Neu starten',
  liveCap: 'Live', liveHint: 'Klicke wie mit dem Daumen. Jedes Wort fügt einen Artikel hinzu; Hafer, Br und E schlagen aus dem Katalog vor. Am Griff nach unten wischen (oder ihn oder die Liste anklicken) schließt.',
  today: 'Heute (main, Flag add-feedback-list)',
  todayCap: 'Heute, nach dem Hinzufügen',
  todayFacts: `<p>Was das Sheet heute nach dem Hinzufügen zeigt (<code>app/lib/list/add_sheet/add_sheet.dart</code>, <code>_AddedDetails</code> und <code>ItemDetailFields._line</code>; der Abschnitt <code>justAdded</code> der Liste in <code>shopping_list_view.dart</code>), von oben nach unten:</p>
    <ul><li>Hinter dem Sheet: die Artikel, die schon auf der Liste stehen, dann „GERADE HINZUGEFÜGT“ und die neue Zeile.</li>
    <li>Der Griff und eine Kopfzeile, die nur die Schließen-Taste (X) am Ende trägt.</li>
    <li>„✓ Hinzugefügt: Hafermilch → Edeka“ mit Rückgängig (<code>_AddedNote</code>).</li>
    <li>Das Label „Menge“, dann eine Zeile, die seitlich scrollt: Mengenfeld, −, +, Laden-Chip, Kategorie-Chip, Marke („ohne Marke“) und Eigenschaften („z. B. Bio, 1 l“). Marke und Eigenschaften beginnen rechts außerhalb des Bildschirms.</li>
    <li>Platz für drei Vorschlagszeilen, den die Zeile nicht füllt (die Lücke über dem Feld, damit das Sheet nicht springt), dann das Feld mit dem Mikrofon.</li></ul>
    <p>Nicht im Sheet: der Preis (die Preis-Pille der Zeile) und der Hinweis auf ein Duplikat („steht schon auf der Liste“, Zusammenführen), der den Platz der Hinzugefügt-Zeile nimmt, wenn er kommt.</p>`,
  frameOrder: [
    ['open', '1 · Geöffnet', 'Die Liste dahinter ist leer.'],
    ['added', '2 · Erster Artikel', 'Nur die neue Zeile hinter dem Sheet.'],
    ['picking', '3 · Läden zur Wahl', (id) => (id === 'AS5' ? 'Schon offen: nichts zu öffnen.' : 'Ein Tipp öffnet sie, in einer Zeile, die seitlich wischt.')],
    ['pickingCat', '3b · Kategorien zur Wahl', (id) => (id === 'AS5' ? 'Schon offen.' : id === 'AS2' ? 'Dasselbe Feld.' : 'Die des Artikels ist ins Bild gescrollt.')],
    ['edited', '4 · Menge 2, Lidl, Kühlregal', ''],
    ['details', '5 · Eigenschaften', (id) => (['AS2', 'AS3'].includes(id) ? 'Marke und Eigenschaften, zwei Felder.' : 'Die Marke kommt in die Eigenschaften.')],
    ['typing', '6 · Der nächste wird getippt', 'Vorschläge nehmen den Platz der Felder.'],
    ['second', '7 · Zweiter Artikel', 'Zwei Zeilen dahinter; die Felder folgen dem neuen.'],
    ['third', '8 · Dritter Artikel', 'Weiter nur die letzten zwei.'],
    ['dismiss', '9 · Schließen', 'Sheet nach unten wischen oder auf die Liste tippen.'],
    ['closed', '10 · Geschlossen', 'Die ganze Liste ist wieder da.'],
  ],
  meterLine: ({ h, saved, taps, brand, fits }) => `Bearbeiten über der Tastatur nach dem Hinzufügen: <b>${h} px</b>, <b>${saved} px</b> weniger als heute. Laden und Kategorie: <b>${taps} Tipps</b>. Feld Marke: <b>${brand ? 'bleibt' : 'in Eigenschaften'}</b>. Alle Felder sichtbar: <b>${fitsText(fits, 'de')}</b>.`,
  fitsCell: (f) => fitsText(f, 'de'),
  tableTitle: 'Gemessen',
  tableNote: 'Gemessen von verify.mjs in Chromium an den Bildern oben, nach dem ersten Hinzufügen (Bild 2). „Bearbeiten braucht“ reicht von der Oberkante des Sheets (AS4: der Karte auf der Liste) bis zur Tastatur. „Sichtbar“ heißt: jedes Feld des Artikels und jede offene Auswahl mit der Wahl des Artikels liegt auf dem Bildschirm über der Tastatur, und das Sheet scrollt nicht; geprüft bei 100 %, 200 % und 310 % Text.',
  tableHead: ['Option', 'Bearbeiten braucht, iPhone 390 × 844', 'Bearbeiten braucht, Android 360 × 640', 'Tipps: Laden + Kategorie', 'Feld Marke', 'Sichtbar, iPhone', 'Sichtbar, Android', 'Liste darüber, Android, nach 2 Artikeln'],
  plusSwipe: '(+1 Wischen bei Android)',
  german: 'Deutsch',
  listLeft: (d) => `${d.freeList} px${d.rowsCut ? `, ${d.rowsCut} Zeile unter der Statusleiste` : ''}`,
  options: {
    AS1: { name: 'Chip-Zeile', what: 'Eine Zeile Chips unter dem Griff: die Menge mit − und +, der Laden, die Kategorie und Eigenschaften. Die Marke kommt in die Eigenschaften. Ein Chip klappt seine Auswahl über dem Feld aus, wie heute.' },
    AS2: { name: 'Feld oben', what: 'Das Feld ist die oberste Zeile des Sheets, die Felder des neuen Artikels liegen darunter, nah am Daumen. Laden und Kategorie teilen sich einen Chip, der beide Listen öffnet: drei Tipps für beides. Die Marke bleibt. Ein leeres Feld abschicken schließt das Sheet auch.' },
    AS3: { name: 'Feldraster', what: 'Ein festes Raster mit zwei Spalten: Menge, Laden, Kategorie, Marke und Eigenschaften, alle sichtbar, jedes einen Tipp entfernt. Die Auswahl klappt unter dem Raster aus. Die Marke bleibt. Die höchste Option.' },
    AS4: { name: 'Auf der Zeile bearbeiten', what: 'Das Sheet behält nur das Feld. Die gerade hinzugefügte Zeile öffnet sich auf der Liste direkt über dem Sheet zu einer Karte, mit Menge, Laden, Kategorie und Eigenschaften. Der nächste Artikel klappt sie wieder zur Zeile. Die Marke kommt in die Eigenschaften.' },
    AS5: { name: 'Ein-Tipp-Reihen', what: 'Läden und Kategorien liegen immer offen, als zwei Reihen, die seitlich wischen; die des Artikels sind honiggelb. Menge und Eigenschaften teilen sich die obere Zeile. Laden und Kategorie: zwei Tipps. Die Marke kommt in die Eigenschaften. Beide Reihen laufen über den Rand (REWE ist auch auf dem iPhone abgeschnitten), ein Laden oder eine Kategorie weiter hinten braucht ein Wischen.' },
  },
  recFile: 'RECOMMENDATION.de.md',
};

function fitsText(f, lang) {
  const yes = lang === 'de' ? 'ja' : 'yes';
  const at = lang === 'de' ? 'bis' : 'up to';
  const no = lang === 'de' ? 'nein' : 'no';
  if (!f) return '';
  if (f.max === 0) return no;
  return f.max === f.largest ? `${yes} (100–${f.largest} %)` : `${at} ${f.max} %`;
}

export const text = { en, de };
