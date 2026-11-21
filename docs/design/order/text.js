// The round page's own words (not the app's; the app's come from strings.js, new UI words from its `proposed`).
export const text = {
  en: {
    overviewTitle: 'Item order: prototypes',
    roundTitle: 'Items in the right order (IO1–IO5)',
    roundBlurb: 'Five list views that put items in walking order with little or no category noise, and how people and agents reorder.',
    note: 'Prototype with mock data (the fictional Brandt family: an EDEKA trip, an IKEA trip, two items without a store). Nothing here ships and the app is unchanged. Store names are plain text. The phones use the app’s tokens, fonts and icons; Today was checked against the release web build. Words marked with a dotted underline are new; every other word is the app’s own.',
    lang: 'Language', light: 'Light', dark: 'Dark', textSize: 'Text', androidMax: 'Android max', iosMax: 'iPhone max',
    overview: 'Overview', pick: 'Pick', runner: 'Runner-up', today: 'Today', approaches: 'The thinking behind the round: APPROACHES.md',
    real: 'The real app (release web build)',
    frames: {
      top: ['Supermarket', 'The first screen of the list.'],
      ikea: ['IKEA', 'The IKEA section. The household walks it: kitchen, textiles, frames, storage, candles, plants, warehouse, food shop.'],
      add: ['A new item', 'Ketchup, never bought at this EDEKA, just added (tinted here to point it out).'],
      fixing: ['Fixing a place', 'Eggs sit with the milk; at this EDEKA they stand next to the flour.'],
      fixed: ['Fixed', 'Where Eggs are after the fix.'],
      cats: ['Categories shown', 'The same list with the switch on.'],
      settings: ['The switch', 'List → Edit.'],
      trip: ['On a trip', 'Ticks in the order the shelves come.'],
      first: ['IKEA, first trip', 'A store with no trips yet: the order of its categories, as Today.'],
    },
    liveCap: 'Live: tap a row to tick it, hold (or right click) a row to edit it.',
    scenes: { top: 'Supermarket', ikea: 'IKEA', add: '+ Ketchup', addIkea: '+ Hangers', trip: 'One trip', reset: 'Reset' },
    todayFacts: `<ul>
      <li>The list is sorted by three keys: the store (List → Edit), then the category in that store’s walk order, then the order the items were added. Everything is set by hand; nothing learns order, and since job 78 nothing on the list drags (<code>sections.dart:27</code>, <code>model.dart:561</code>, <code>model.dart:711</code>).</li>
      <li>Each category with an item gets a small heading in capitals (<code>dividers.dart:277</code>). On the 18-item EDEKA list they cost the iPhone’s first screen 2 to 3 rows (the table below).</li>
      <li>A store the household adds itself, like IKEA, gets the supermarket route order. The classifier gives IKEA items Household or Other, and in English “Tea lights” land in Pantry.</li>
      <li>A wrong place is fixed with the category chip in the edit sheet (hold the row). The item goes to the end of its new category, and the household’s correction moves it in every store.</li>
      <li>The server can already place an item before or after another (<code>place_item</code>, job 15), and every tick is stored with its time (<code>item_events</code>), but neither is used for order today.</li>
    </ul>`,
    options: {
      IO1: { name: 'Quiet categories', what: 'Today’s order with the category headings left out. Store dividers stay. A wrong place is fixed as today, with the category chip in the edit sheet, so the user picks a category they no longer see. Nothing new to learn or build.' },
      IO2: { name: 'Learns your walk', what: 'No categories anywhere. Each store keeps the order its trips are ticked in: after a trip, the list comes back in that order. A new item takes the place its kind of item has in the store. There is nothing to fix by hand; the next trip does it.' },
      IO3: { name: 'Drag to order', what: 'No categories. The order is the household’s own: a sort key in the top bar shows drag handles (the list stops ticking), the row is dragged, Done ends it. The list itself still never drags (job 78). Nothing is learned.' },
      IO4: { name: 'Learns, plus “Next to”', what: 'IO2’s learned order, and a fix for the moment it is wrong: the edit sheet’s category chip becomes “Next to Flour”, a list of the store’s items in order. One pick puts the item right after another, at any distance, without dragging. A manual place wins until trips disagree.' },
      IO5: { name: 'Categories on or off', what: 'A switch on the stores screen (List → Edit) shows or hides the category headings, per person. Hidden, a quiet gap marks where the category changes. The order is Today’s, and Move up / Move down in the edit sheet move an item one place; crossing a gap takes it into that category.' },
    },
    meterLine: (m) => `First screen: <b>${m.rows}</b> item rows (Today ${m.today}). Fix Eggs: <b>${m.taps}</b>. Whole IKEA list: <b>${m.ikea}</b>.`,
    taps: (n) => (n === 0 ? 'no taps' : `${n} taps`),
    ikeaText: (c) => (c.taps === null ? 'not possible item by item' : c.trips ? 'one trip, no taps' : `${c.taps} taps`),
    eggsWhere: { flour: 'right after Flour', passata: 'end of Pantry, after Passata (and Pantry for eggs in every store)', yogurt: 'unchanged until a trip' },
    tableTitle: 'Measured',
    tableNote: 'Rows: item rows wholly visible between the top bar and the add field at the top of the list, measured in this page. Today’s replica matches the release web build in every column (io/real). Taps: the clicks verify.mjs makes on the live phone; a drag is one. IKEA: the list in Today’s order brought into the walking order.',
    tableHead: ['Option', 'Rows, iPhone 100 %', 'iPhone 310 %', 'Android 100 %', 'Android 200 %', 'Fix Eggs', 'Eggs end up', 'Whole IKEA list'],
    german: 'German',
    newWord: 'New word',
  },
  de: {
    overviewTitle: 'Reihenfolge: Prototypen',
    roundTitle: 'Artikel in der richtigen Reihenfolge (IO1–IO5)',
    roundBlurb: 'Fünf Listenansichten, die Artikel in Laufweg-Reihenfolge zeigen, mit wenig oder ohne Kategorien, und wie Menschen und Agenten umsortieren.',
    note: 'Prototyp mit Beispieldaten (die erfundene Familie Brandt: ein EDEKA-Einkauf, ein IKEA-Einkauf, zwei Artikel ohne Laden). Nichts davon wird ausgeliefert, die App ist unverändert. Ladennamen sind reiner Text. Die Telefone nutzen die Tokens, Schriften und Icons der App; „Heute“ wurde mit dem Release-Web-Build abgeglichen. Gepunktet unterstrichene Wörter sind neu, alle anderen stammen aus der App.',
    lang: 'Sprache', light: 'Hell', dark: 'Dunkel', textSize: 'Text', androidMax: 'Android max.', iosMax: 'iPhone max.',
    overview: 'Übersicht', pick: 'Empfehlung', runner: 'Zweite Wahl', today: 'Heute', approaches: 'Die Überlegungen hinter der Runde: APPROACHES.md (Englisch)',
    real: 'Die echte App (Release-Web-Build)',
    frames: {
      top: ['Supermarkt', 'Der erste Bildschirm der Liste.'],
      ikea: ['IKEA', 'Der IKEA-Abschnitt. Die Familie geht: Küche, Textilien, Rahmen, Aufbewahrung, Kerzen, Pflanzen, Lager, Schwedenshop.'],
      add: ['Ein neuer Artikel', 'Ketchup, bei diesem EDEKA noch nie gekauft, gerade hinzugefügt (hier eingefärbt, damit man ihn sieht).'],
      fixing: ['Platz korrigieren', 'Eier stehen bei der Milch; in diesem EDEKA stehen sie neben dem Mehl.'],
      fixed: ['Korrigiert', 'Wo die Eier nach der Korrektur stehen.'],
      cats: ['Kategorien an', 'Dieselbe Liste mit eingeschaltetem Schalter.'],
      settings: ['Der Schalter', 'Liste → Anpassen.'],
      trip: ['Beim Einkauf', 'Abgehakt in der Reihenfolge der Regale.'],
      first: ['IKEA, erster Einkauf', 'Ein Laden ohne bisherige Einkäufe: die Reihenfolge seiner Kategorien, wie heute.'],
    },
    liveCap: 'Live: Tippen hakt ab, Halten (oder Rechtsklick) bearbeitet.',
    scenes: { top: 'Supermarkt', ikea: 'IKEA', add: '+ Ketchup', addIkea: '+ Kleiderbügel', trip: 'Ein Einkauf', reset: 'Zurücksetzen' },
    todayFacts: `<ul>
      <li>Die Liste sortiert nach drei Schlüsseln: Laden (Liste → Anpassen), dann die Kategorie im Laufweg dieses Ladens, dann die Reihenfolge des Hinzufügens. Alles wird von Hand gesetzt; nichts lernt, und seit Job 78 lässt sich auf der Liste nichts ziehen (<code>sections.dart:27</code>, <code>model.dart:561</code>, <code>model.dart:711</code>).</li>
      <li>Jede Kategorie mit einem Artikel bekommt eine kleine Überschrift in Großbuchstaben (<code>dividers.dart:277</code>). Bei der EDEKA-Liste mit 18 Artikeln kosten sie den ersten Bildschirm des iPhones 2 bis 3 Zeilen (Tabelle unten).</li>
      <li>Ein selbst angelegter Laden wie IKEA bekommt die Supermarkt-Reihenfolge. Der Klassifizierer steckt IKEA-Artikel in Haushalt oder Sonstiges, auf Englisch landen „Tea lights“ in Vorrat.</li>
      <li>Ein falscher Platz wird mit dem Kategorie-Chip im Bearbeiten-Blatt korrigiert (Zeile halten). Der Artikel kommt ans Ende der neuen Kategorie, und die Korrektur des Haushalts verschiebt ihn in jedem Laden.</li>
      <li>Der Server kann einen Artikel schon vor oder hinter einen anderen setzen (<code>place_item</code>, Job 15), und jedes Abhaken wird mit Uhrzeit gespeichert (<code>item_events</code>); beides nutzt die Reihenfolge heute nicht.</li>
    </ul>`,
    options: {
      IO1: { name: 'Leise Kategorien', what: 'Die heutige Reihenfolge ohne Kategorie-Überschriften. Die Ladentrenner bleiben. Ein falscher Platz wird wie heute über den Kategorie-Chip korrigiert, also über eine Kategorie, die man nicht mehr sieht. Nichts Neues zu lernen oder zu bauen.' },
      IO2: { name: 'Lernt euren Weg', what: 'Nirgends Kategorien. Jeder Laden merkt sich die Reihenfolge, in der seine Einkäufe abgehakt werden: Nach einem Einkauf kommt die Liste in dieser Reihenfolge zurück. Ein neuer Artikel bekommt den Platz, den seine Art Artikel im Laden hat. Von Hand gibt es nichts zu korrigieren; das macht der nächste Einkauf.' },
      IO3: { name: 'Ziehen zum Ordnen', what: 'Keine Kategorien. Die Reihenfolge gehört dem Haushalt: Ein Sortier-Knopf oben zeigt Griffe (die Liste hakt dann nicht ab), die Zeile wird gezogen, Fertig beendet es. Die Liste selbst zieht weiterhin nie (Job 78). Nichts wird gelernt.' },
      IO4: { name: 'Lernt, plus „Neben“', what: 'Die gelernte Reihenfolge von IO2 und eine Korrektur für den Moment, in dem sie falsch ist: Der Kategorie-Chip im Bearbeiten-Blatt wird zu „Neben Mehl“, einer Liste der Artikel des Ladens in Reihenfolge. Eine Auswahl setzt den Artikel direkt hinter einen anderen, egal wie weit, ohne Ziehen. Ein von Hand gesetzter Platz gilt, bis Einkäufe widersprechen.' },
      IO5: { name: 'Kategorien an oder aus', what: 'Ein Schalter auf dem Läden-Bildschirm (Liste → Anpassen) zeigt oder versteckt die Kategorie-Überschriften, für jede Person. Versteckt markiert ein ruhiger Abstand den Wechsel der Kategorie. Die Reihenfolge ist die heutige; Nach oben / Nach unten im Bearbeiten-Blatt verschieben um einen Platz, über einen Abstand hinweg wechselt der Artikel die Kategorie.' },
    },
    meterLine: (m) => `Erster Bildschirm: <b>${m.rows}</b> Artikelzeilen (heute ${m.today}). Eier korrigieren: <b>${m.taps}</b>. Ganze IKEA-Liste: <b>${m.ikea}</b>.`,
    taps: (n) => (n === 0 ? 'kein Tippen' : `${n}× tippen`),
    ikeaText: (c) => (c.taps === null ? 'Artikel für Artikel nicht möglich' : c.trips ? 'ein Einkauf, kein Tippen' : `${c.taps}× tippen`),
    eggsWhere: { flour: 'direkt hinter Mehl', passata: 'Ende von Vorrat, hinter Passierte Tomaten (und Vorrat für Eier in jedem Laden)', yogurt: 'unverändert bis zum Einkauf' },
    tableTitle: 'Gemessen',
    tableNote: 'Zeilen: Artikelzeilen, die am Anfang der Liste ganz zwischen oberer Leiste und Eingabefeld sichtbar sind, auf dieser Seite gemessen. Der Nachbau von „Heute“ stimmt in jeder Spalte mit dem Release-Web-Build überein (io/real). Tippen: die Klicks, die verify.mjs am Live-Telefon macht; Ziehen zählt als eins. IKEA: die Liste in heutiger Reihenfolge in die Laufweg-Reihenfolge bringen.',
    tableHead: ['Option', 'Zeilen, iPhone 100 %', 'iPhone 310 %', 'Android 100 %', 'Android 200 %', 'Eier korrigieren', 'Eier landen', 'Ganze IKEA-Liste'],
    german: 'Deutsch',
    newWord: 'Neues Wort',
  },
};
