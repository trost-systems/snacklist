// The page's own words (not app UI), English and German.
const en = {
  lang: 'Lang', light: 'Light', dark: 'Dark', textSize: 'Text', androidMax: 'Android’s largest', iosMax: 'iOS’s largest',
  overview: 'All rounds',
  roundTitle: 'Round AM: typing something that is already there',
  roundBlurb: 'Five ways to show, inside AS1’s sheet, that a typed item matches one on the list or ticked recently, so you can tick it off, merge into it or add a separate one. Inspired by Bring!.',
  note: 'A throwaway prototype with mock data (the fictional Familie Brandt). Nothing here ships. The sheet is AS1 (job 319’s pick, job 322’s build). On the list: Pasta, Apples 1 kg (farmers’ market), 2× Oat milk (dm, Hafergold), Milk (Edeka, 1.5 %), Bananas; ticked yesterday: 10× Eggs (Edeka, free range) and Buttermilk. The live phone works: type Pasta, Apple, Oat milk, Milk, Eggs or Cinnamon, then tap or press Enter. Store names are plain text (N-292). Per Peter (t1077u), every match shows only inside the sheet, as a marked suggestion; the row on the list behind the sheet is never moved into view or highlighted, and what became of a match is said in the sheet.',
  pick: 'Pick', runner: 'Runner-up', reset: 'Start again',
  liveCap: 'Live', liveHint: 'Click like a thumb, press Enter for the keyboard’s return key.',
  today: 'Today (main)',
  todayFacts: `<ul>
    <li><b>Same name, brand and details as an open item</b> (case, spaces and umlauts folded): nothing is added. The sheet says “Pasta is already on the list”, with no key (<code>addParsed</code> → <code>AlreadyOnList</code>, list_cubit.dart; the server’s <code>items_skip_duplicate</code> trigger would skip it too).</li>
    <li><b>Another spelling, a plural or a synonym</b> (the same <code>canonical_key</code>: Apfel and Äpfel), or the same name where only one of the two has a brand or details: the item is added first. Then the note “Apples is already on the list” with <b>Merge</b> takes the added note’s place, until the next letter (<code>similarItems</code>, <code>DedupeHint</code>). With the sheet closed it is a 6 s snackbar.</li>
    <li><b>Merge</b> keeps the older item: its name, category, store and price. Amounts add up (<code>merge_quantities</code>: none + none = 2, 2 + none = 3, 500 g + 1 kg = 1,5 kg, but 1 kg + none stays 1 kg). Brand and details: the older item’s, else the new one’s. The new item is deleted. “Merged: 2× Pasta” with Undo follows, and Undo puts both back.</li>
    <li><b>Ticked items never match.</b> Typing Eggs while yesterday’s Eggs are ticked adds a new row; the ticked one stays in the ticked section. The suggestions list ticked items as history (“Bought before”) and hide open ones, and a tap there also adds a new row.</li>
    <li>Store, category and price are never compared. Only open items on the list that is shown count.</li></ul>`,
  outcomesTitle: 'The outcomes',
  outcomes: `<ul>
    <li><b>Tick off</b> an <b>open</b> match: it leaves the list into the ticked section, as a tap on its row does; nothing is added. It fits “we have it after all” or Bring!’s toggle, and it is the rarest wish while adding. A <b>ticked</b> match can’t be ticked off again. Its counterpart is <b>Back on the list</b> (the app’s “readd”): the ticked item opens again with its amount, store, brand and details. That is what fits a ticked match almost always, and it is what Bring! does with a recent item.</li>
    <li><b>Merge</b> into an open match: today’s merge. The amount adds up (none + none = 2) and the older item keeps its store, brand and details. It fits the exact and the spelling match when the list should hold one more. Merging into a ticked match is Back on the list.</li>
    <li><b>Add a separate item</b>: a new row under the typed name. It fits when the match is another brand or store (Oat milk from Lidl while the list has Hafergold from dm), and for a part match (Milk while Oat milk is on the list). AS1’s chips then set its store.</li>
    <li><b>Keep</b> (Enter in AM2 only): nothing changes, as today’s refusal. The sheet says “Pasta is already on the list”.</li></ul>
    <p>After any of them the sheet says what happened in the chips’ place, with the app’s own sentences (“Merged: 2× Pasta”, “Pasta ticked off”, “Back on the list: 10× Eggs”), until the next letter. The list behind the sheet shows only items this sheet added.</p>`,
  scen: {
    exact: 'Exact (open)', spelling: 'Plural / other spelling', brand: 'Other store or brand set', several: 'Several matches',
    ticked: 'Ticked yesterday', none: 'No match',
  },
  frameOrder: [
    ['exact', '1 · Exact match', 'Pasta is on the list.'],
    ['exactEnter', '2 · Enter on it', (o) => `Enter: ${o}.`],
    ['spelling', '3 · Plural', 'Apple → Apples (1 kg).'],
    ['brand', '4 · Store and brand set', 'Oat milk: dm, Hafergold.'],
    ['brandNew', '5 · A separate one from Lidl', 'New row, then AS1’s store chip.'],
    ['several', '6 · Several matches', 'Milk, Oat milk, ticked Buttermilk.'],
    ['ticked', '7 · Ticked yesterday', 'Eggs, ticked yesterday.'],
    ['tickedEnter', '8 · Enter on it', (o) => `Enter: ${o}.`],
    ['none', '9 · No match', 'Cinnamon: AS1 as is.'],
    ['merged', '10 · Merged', (o, p) => (p ? `${p} tap${p > 1 ? 's' : ''}.` : '')],
    ['tickedOff', '11 · Ticked off', (o, p) => (p ? `${p} tap${p > 1 ? 's' : ''}.` : 'Not offered in the sheet.')],
  ],
  outcomeName: { tick: 'ticks it off', merge: 'merges (+1)', new: 'adds a separate one', back: 'back on the list', keep: 'keeps the list, says it is there' },
  meterLine: (d) => `Enter on an open match: <b>${d.enter}</b>; on a ticked one: <b>${d.enterTicked}</b>. Taps after typing: tick off <b>${d.tick}</b>, merge <b>${d.merge}</b>, separate <b>${d.new}</b>, back on the list <b>${d.back}</b>. Sheet with three matches: <b>${d.h3} px</b> on the iPhone.`,
  tableTitle: 'Measured',
  tableNote: (m) => `Taps are clicks and Enter presses on the live phone after typing the word (verify.mjs replays every path and checks the list after it). Heights run from the sheet’s top to the keyboard at 100 % in English; AS1 typing with one plain suggestion (Cinnamon) is ${m.ios.plain} / ${m.android.plain} px. “In view” means every match and every key that decides sits above the keyboard and inside the screen, without the sheet scrolling, at each text size up to the phone’s largest, in both languages.`,
  tableHead: ['Option', 'Enter, open match', 'Enter, ticked match', 'Tick off', 'Merge', 'Separate', 'Back on the list', 'Sheet, 1 match, iPhone / Android', 'Sheet, 3 matches, iPhone / Android', 'In view, iPhone: 1 match; 3', 'In view, Android: 1 match; 3', 'New UI words'],
  notOffered: 'not in the sheet',
  options: {
    AM1: { name: 'Marked rows', what: 'Matches lead the suggestion rows, drawn like list rows: honey when open, struck through when ticked, with store, brand and details under the name. A tap on an open one, or Enter on the first, merges into it. Its round key ticks it off. A ticked one comes back with a tap. The last row, + and the typed text, adds a separate item.' },
    AM2: { name: 'Outcome rows', what: 'One suggestion row per outcome, each marked by its icon, its colour and its result. Merge shows the item as it would be (2× Pasta, honey), tick off shows it struck through (mint), a ticked match shows Back on the list’s icon (grey), and the + row adds a separate item. Each takes one tap. No row is on Enter: Enter keeps the list as it is, as today, and the sheet says “Pasta is already on the list”.' },
    AM3: { name: 'Decision keys', what: 'The match shows as one row with three equal keys under it: ✓ (tick off), Merge, New. Enter takes the honey one, Merge (for a ticked match: Back on the list). With several matches, their names sit above as a line to switch between.' },
    AM4: { name: 'Add, then offer', what: 'Today’s order inside AS1. While typing nothing is marked. Enter adds a new item, and the item it matched then sits over the chips with one key: Merge, or Back on the list for a ticked one. Typing on keeps both. Tick-off has no key.' },
    AM5: { name: 'Tiles (Bring!)', what: 'Bring!’s tiles: matches as tiles over the field, honey when on the list. A tap on a honey tile ticks it off, as Bring! does, and so does Enter. A tap on a ticked tile puts it back. The + in a tile’s corner merges. The last tile adds the typed text as a separate item.' },
  },
  recFile: 'RECOMMENDATION.md',
};

const de = {
  ...en,
  lang: 'Sprache', light: 'Hell', dark: 'Dunkel', androidMax: 'größte bei Android', iosMax: 'größte bei iOS',
  overview: 'Alle Runden',
  roundTitle: 'Runde AM: etwas tippen, das schon da ist',
  roundBlurb: 'Fünf Wege, im Sheet von AS1 zu zeigen, dass ein getippter Artikel schon auf der Liste steht oder kürzlich abgehakt wurde, damit man ihn abhaken, zusammenführen oder getrennt hinzufügen kann. Nach dem Vorbild von Bring!.',
  note: 'Ein Wegwerf-Prototyp mit Beispieldaten (die erfundene Familie Brandt). Nichts davon wird ausgeliefert. Das Sheet ist AS1 (Empfehlung aus Job 319, gebaut in Job 322). Auf der Liste: Nudeln, Äpfel 1 kg (Wochenmarkt), 2× Hafermilch (dm, Hafergold), Milch (Edeka, 1,5 %), Bananen; gestern abgehakt: 10× Eier (Edeka, Freiland) und Buttermilch. Das Live-Telefon funktioniert: tippe Nudeln, Apfel, Hafermilch, Milch, Eier oder Zimt, dann tippen oder Enter. Ladennamen sind reiner Text (N-292). Laut Peter (t1077u) steht jeder Treffer nur im Sheet, als markierter Vorschlag; die Zeile auf der Liste hinter dem Sheet wird nie ins Bild geholt oder markiert, und was aus einem Treffer wurde, sagt das Sheet.',
  pick: 'Empfehlung', runner: 'Zweite Wahl', reset: 'Neu starten',
  liveHint: 'Klicke wie mit dem Daumen, Enter ist die Eingabetaste der Tastatur.',
  today: 'Heute (main)',
  todayFacts: `<ul>
    <li><b>Gleicher Name, gleiche Marke und Eigenschaften wie ein offener Artikel</b> (Groß/klein, Leerzeichen, Umlaute gefaltet): nichts wird hinzugefügt. Das Sheet sagt „Nudeln steht schon auf der Liste“, ohne Taste (<code>addParsed</code> → <code>AlreadyOnList</code>; der Trigger <code>items_skip_duplicate</code> würde es auch überspringen).</li>
    <li><b>Andere Schreibweise, Plural oder Synonym</b> (gleicher <code>canonical_key</code>: Apfel und Äpfel), oder gleicher Name, wo nur einer der beiden Marke oder Eigenschaften hat: der Artikel wird erst hinzugefügt. Dann nimmt „Äpfel steht schon auf der Liste“ mit <b>Zusammenführen</b> den Platz der Hinzugefügt-Zeile ein, bis zum nächsten Buchstaben (<code>similarItems</code>, <code>DedupeHint</code>). Bei geschlossenem Sheet eine Snackbar, 6 s.</li>
    <li><b>Zusammenführen</b> behält den älteren Artikel: Name, Kategorie, Laden und Preis. Mengen addieren sich (<code>merge_quantities</code>: keine + keine = 2, 2 + keine = 3, 500 g + 1 kg = 1,5 kg, aber 1 kg + keine bleibt 1 kg). Marke und Eigenschaften: die des älteren, sonst die des neuen. Der neue Artikel wird gelöscht. Danach „Zusammengeführt: 2× Nudeln“ mit Rückgängig, das beide wiederherstellt.</li>
    <li><b>Abgehakte Artikel zählen nie.</b> Wer Eier tippt, während die Eier von gestern abgehakt sind, bekommt eine neue Zeile; die abgehakte bleibt bei den abgehakten. Die Vorschläge zeigen Abgehaktes als Verlauf („Schon mal gekauft“) und blenden Offenes aus; ein Tipp darauf fügt auch eine neue Zeile hinzu.</li>
    <li>Laden, Kategorie und Preis werden nie verglichen. Es zählen nur offene Artikel der gezeigten Liste.</li></ul>`,
  outcomesTitle: 'Die Ergebnisse',
  outcomes: `<ul>
    <li><b>Abhaken</b>, wenn der Treffer <b>offen</b> ist: er verlässt die Liste zu den abgehakten, wie ein Tipp auf seine Zeile; nichts kommt dazu. Passt zu „haben wir doch“ oder zum Umschalten wie in Bring!, und ist beim Hinzufügen der seltenste Wunsch. Ein <b>abgehakter</b> Treffer lässt sich nicht noch einmal abhaken. Sein Gegenstück ist <b>Wieder auf die Liste</b> (das „readd“ der App): der abgehakte Artikel ist wieder offen, mit Menge, Laden, Marke und Eigenschaften. Das passt zu einem abgehakten Treffer fast immer, und so macht es Bring! mit einem zuletzt gekauften Artikel.</li>
    <li><b>Zusammenführen</b> mit einem offenen Treffer: das heutige Zusammenführen. Die Menge addiert sich (keine + keine = 2), der ältere behält Laden, Marke und Eigenschaften. Passt zum genauen und zum Schreibweisen-Treffer, wenn einer mehr auf die Liste soll. Mit einem abgehakten zusammenführen heißt: wieder auf die Liste.</li>
    <li><b>Getrennt hinzufügen</b>: eine neue Zeile unter dem getippten Namen. Passt, wenn der Treffer eine andere Marke oder ein anderer Laden ist (Hafermilch von Lidl, während Hafergold von dm auf der Liste steht), und für einen Teil-Treffer (Milch, während Hafermilch draufsteht). Die Chips von AS1 setzen dann den Laden.</li>
    <li><b>Lassen</b> (nur Enter in AM2): nichts ändert sich, wie bei der heutigen Ablehnung. Das Sheet sagt „Nudeln steht schon auf der Liste“.</li></ul>
    <p>Nach jedem davon sagt das Sheet an der Stelle der Chips, was passiert ist, mit den Sätzen der App („Zusammengeführt: 2× Nudeln“, „Nudeln abgehakt“, „Wieder auf die Liste: 10× Eier“), bis zum nächsten Buchstaben. Die Liste hinter dem Sheet zeigt nur, was dieses Sheet hinzugefügt hat.</p>`,
  scen: {
    exact: 'Genau (offen)', spelling: 'Plural / andere Schreibweise', brand: 'Anderer Laden oder Marke gesetzt', several: 'Mehrere Treffer',
    ticked: 'Gestern abgehakt', none: 'Kein Treffer',
  },
  frameOrder: [
    ['exact', '1 · Genauer Treffer', 'Nudeln stehen auf der Liste.'],
    ['exactEnter', '2 · Enter darauf', (o) => `Enter: ${o}.`],
    ['spelling', '3 · Plural', 'Apfel → Äpfel (1 kg).'],
    ['brand', '4 · Laden und Marke gesetzt', 'Hafermilch: dm, Hafergold.'],
    ['brandNew', '5 · Eine getrennte von Lidl', 'Neue Zeile, dann der Laden-Chip von AS1.'],
    ['several', '6 · Mehrere Treffer', 'Milch, Hafermilch, abgehakte Buttermilch.'],
    ['ticked', '7 · Gestern abgehakt', 'Eier, gestern abgehakt.'],
    ['tickedEnter', '8 · Enter darauf', (o) => `Enter: ${o}.`],
    ['none', '9 · Kein Treffer', 'Zimt: AS1 wie es ist.'],
    ['merged', '10 · Zusammengeführt', (o, p) => (p ? `${p} ${p > 1 ? 'Tipps' : 'Tipp'}.` : '')],
    ['tickedOff', '11 · Abgehakt', (o, p) => (p ? `${p} ${p > 1 ? 'Tipps' : 'Tipp'}.` : 'Im Sheet nicht angeboten.')],
  ],
  outcomeName: { tick: 'hakt ab', merge: 'führt zusammen (+1)', new: 'fügt getrennt hinzu', back: 'wieder auf die Liste', keep: 'lässt die Liste, sagt, dass er da ist' },
  meterLine: (d) => `Enter auf einem offenen Treffer: <b>${d.enter}</b>; auf einem abgehakten: <b>${d.enterTicked}</b>. Tipps nach dem Tippen: abhaken <b>${d.tick}</b>, zusammenführen <b>${d.merge}</b>, getrennt <b>${d.new}</b>, wieder auf die Liste <b>${d.back}</b>. Sheet mit drei Treffern: <b>${d.h3} px</b> auf dem iPhone.`,
  tableTitle: 'Gemessen',
  tableNote: (m) => `Tipps sind Klicks und Enter auf dem Live-Telefon nach dem Tippen des Worts (verify.mjs spielt jeden Weg nach und prüft danach die Liste). Höhen von der Oberkante des Sheets bis zur Tastatur bei 100 % auf Englisch; AS1 beim Tippen mit einem normalen Vorschlag (Zimt) hat ${m.ios.plain} / ${m.android.plain} px. „Sichtbar“ heißt: jeder Treffer und jede Taste, die entscheidet, liegt über der Tastatur und auf dem Bildschirm, ohne dass das Sheet scrollt, bei jeder Textgröße bis zur größten des Telefons, in beiden Sprachen.`,
  tableHead: ['Option', 'Enter, offener Treffer', 'Enter, abgehakter Treffer', 'Abhaken', 'Zusammenführen', 'Getrennt', 'Wieder auf die Liste', 'Sheet, 1 Treffer, iPhone / Android', 'Sheet, 3 Treffer, iPhone / Android', 'Sichtbar, iPhone: 1 Treffer; 3', 'Sichtbar, Android: 1 Treffer; 3', 'Neue UI-Wörter'],
  notOffered: 'nicht im Sheet',
  options: {
    AM1: { name: 'Markierte Zeilen', what: 'Treffer stehen zuerst in den Vorschlägen, gezeichnet wie Listenzeilen: honiggelb, wenn offen, durchgestrichen, wenn abgehakt, mit Laden, Marke und Eigenschaften unter dem Namen. Ein Tipp auf einen offenen, oder Enter auf den ersten, führt zusammen. Seine runde Taste hakt ihn ab. Ein abgehakter kommt mit einem Tipp zurück. Die letzte Zeile, + und der getippte Text, fügt getrennt hinzu.' },
    AM2: { name: 'Ergebnis-Zeilen', what: 'Eine Vorschlagszeile je Ergebnis, markiert durch Symbol, Farbe und Ergebnis. Zusammenführen zeigt den Artikel, wie er danach wäre (2× Nudeln, honiggelb), Abhaken zeigt ihn durchgestrichen (minzgrün), ein abgehakter Treffer trägt das Symbol von Wieder auf die Liste (grau), die +-Zeile fügt getrennt hinzu. Jedes braucht einen Tipp. Keine Zeile liegt auf Enter: Enter lässt die Liste, wie sie ist, wie heute, und das Sheet sagt „Nudeln steht schon auf der Liste“.' },
    AM3: { name: 'Entscheidungs-Tasten', what: 'Der Treffer steht als eine Zeile da, darunter drei gleiche Tasten: ✓ (abhaken), Zusammenführen, Neu. Enter nimmt die honiggelbe, Zusammenführen (bei einem abgehakten: Wieder auf die Liste). Bei mehreren Treffern stehen ihre Namen darüber als Zeile zum Umschalten.' },
    AM4: { name: 'Erst hinzufügen, dann anbieten', what: 'Die heutige Reihenfolge im Sheet von AS1. Beim Tippen ist nichts markiert. Enter fügt einen neuen Artikel hinzu, danach steht der Treffer über den Chips mit einer Taste: Zusammenführen, oder Wieder auf die Liste bei einem abgehakten. Weitertippen behält beide. Abhaken hat keine Taste.' },
    AM5: { name: 'Kacheln (Bring!)', what: 'Die Kacheln von Bring!: Treffer als Kacheln über dem Feld, honiggelb, wenn auf der Liste. Ein Tipp auf eine honiggelbe hakt ab, wie bei Bring!, und Enter auch. Ein Tipp auf eine abgehakte holt sie zurück. Das + in der Ecke einer Kachel führt zusammen. Die letzte Kachel fügt den getippten Text getrennt hinzu.' },
  },
  recFile: 'RECOMMENDATION.de.md',
};

export const text = { en, de };
