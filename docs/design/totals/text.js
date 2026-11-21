// The round page's own words (not the app's; the app's come from strings.js).
export const text = {
  en: {
    overviewTitle: 'Shopping total: prototypes',
    roundTitle: 'Totals with missing prices (TE1–TE5)',
    roundBlurb: 'Five ways to show the shopping total when no item or only some items have a price.',
    note: 'Prototype with mock data (the fictional Brandt family). Nothing here ships and the app is unchanged. Store names are plain text. Phones are drawn with the app’s tokens; the Today phone was calibrated against the release web build.',
    lang: 'Language', light: 'Light', dark: 'Dark', textSize: 'Text', androidMax: 'Android max', iosMax: 'iPhone max',
    overview: 'Overview', pick: 'Pick', runner: 'Runner-up', today: 'Today', real: 'The real app (release web build, 390 × 844)',
    states: { a: '(a) No prices', b: '(b) Some prices', c: '(c) All priced', d: '(d) On a trip' },
    stateSub: {
      a: 'Seven items in dm, Lidl, Edeka, IKEA and no store. None has a price.',
      b: 'Lidl in full (Milk, Bananas per kg), Edeka’s bread. Four without a price.',
      c: 'Every item has a price.',
      d: 'As (b), and a trip runs: Lidl and the bread are bought.',
    },
    extra: { TE2: 'Opened by a tap (b)', TE5: 'The amount tapped (b)', TE3: 'At the top of the list (b)' },
    liveCap: 'Live: tap a + Price chip to price an item, a row to buy it on a trip',
    reset: 'Reset',
    todayFacts: `<ul>
      <li>With <code>list-declutter</code> and prices on, the block sits after the last store section, above “Recently used”, whenever the list has an open item. It shows even when no item has a price (<code>summary_block.dart</code>, shown when <code>summary.stores</code> is not empty).</li>
      <li>One line per group with something open, in store order, then “No store” as a group of its own (ST-Q3). Each line names how many of its open items have no price: “1 without price”.</li>
      <li>Only with two groups or more: the “SHOPPING TOTAL” head, the store lines and “Total”. With one group, a single “Shopping total” line.</li>
      <li>An amount with an unpriced item behind it is a floor: “at least €2.49” (ST-Q1). A per-kg price on the planned weight is an estimate, and so is every sum holding one: “≈ €3.89” (ST-Q4). Both together read “at least ≈ €6.38”.</li>
      <li>The total’s second line counts both sides: “3 with price · 4 without price”. With no price at all it reads “7 without price” and shows no amount.</li>
      <li>Only while a trip runs, ticked items count, split from the open ones: “€2.49 bought · 1 without price”, and a store bought in full stays as “all bought” (ST-Q2). Without a trip, ticked items leave the sums.</li>
      <li>Every row already has its own “+ Price” chip, so the per-store counts repeat what the rows show.</li>
    </ul>`,
    options: {
      TE1: { name: 'Only what has a price', what: 'Today’s receipt without the empty lines. No price anywhere: no block. Otherwise a line only for a store with a price in it; stores without one drop out, and one count on the total says what is missing (“4 without price”). The floor and ≈ marks stay on every amount, “No store” keeps its own line once it has a price.' },
      TE2: { name: 'One line, opens on tap', what: 'One total line, folded. No price anywhere: nothing. Otherwise “Shopping total”, the amount with its marks and one count below; a chevron opens TE1’s store lines above it. The store lines cost a tap; the line stays at its height in every state.' },
      TE3: { name: 'Sums on the store dividers', what: 'Each store’s open sum moves onto its divider at the top of its section (“1 item · ≈ €3.89”), where you are when you shop there. The end of the list keeps one total line, only once something has a price. No price anywhere: dividers as today, no block.' },
      TE4: { name: 'Total and the next price', what: 'The block turns the missing prices into one action: “7 without price ›” jumps to the next item without a price and opens its price editor. No price anywhere: one line, “Shopping total” and the link. Some prices: the total and the link. The store lines come back only once every item has a price.' },
      TE5: { name: 'Total in the top bar', what: 'No block at the end of the list. Once something has a price, its amount sits in the top bar next to Edit (a trailing “+” while some prices are missing), in view while you scroll. A tap opens TE1’s receipt in a sheet. No price anywhere: the top bar as today.' },
    },
    meterLine: (m) => `Block on this phone at this text size: <b>${m.a} / ${m.b} / ${m.c} / ${m.d} px</b> in (a) / (b) / (c) / (d), against Today’s ${m.ta} / ${m.tb} / ${m.tc} / ${m.td} px. Rows saved: <b>${m.sa} / ${m.sb} / ${m.sc} / ${m.sd}</b>.`,
    tableTitle: 'Measured: block height and rows saved',
    tableNote: 'Height is what the option adds to the list against no total at all: the block at the list’s end, a taller divider (TE3) or top bar (TE5); TE2 folded, TE5’s sheet closed. “List name cut”: TE5’s amount squeezes the switcher until the list’s name ends in “…”. Rows saved: Today’s height minus the option’s, in whole list rows (48 px at 100 %; a row’s measured height at large text). Measured by verify.mjs in Chromium, English; German in brackets where it differs.',
    tableHead: ['Option', 'Phone, text', '(a) No prices', '(b) Some', '(c) All', '(d) Trip'],
    saved: (n) => (n > 0 ? `saves ${n}` : n < 0 ? `costs ${-n}` : 'same'),
    german: 'de',
    cut: 'list name cut',
  },
  de: {
    overviewTitle: 'Einkaufssumme: Prototypen',
    roundTitle: 'Summen mit fehlenden Preisen (TE1–TE5)',
    roundBlurb: 'Fünf Wege, die Einkaufssumme zu zeigen, wenn kein Artikel oder nur einige einen Preis haben.',
    note: 'Prototyp mit Beispieldaten (die erfundene Familie Brandt). Nichts davon wird ausgeliefert, die App ist unverändert. Läden stehen als reiner Text da. Die Telefone nutzen die Tokens der App; das Telefon „Heute“ ist am Release-Web-Build ausgemessen.',
    lang: 'Sprache', light: 'Hell', dark: 'Dunkel', textSize: 'Text', androidMax: 'Android max.', iosMax: 'iPhone max.',
    overview: 'Übersicht', pick: 'Wahl', runner: 'Zweite Wahl', today: 'Heute', real: 'Die echte App (Release-Web-Build, 390 × 844)',
    states: { a: '(a) Keine Preise', b: '(b) Einige Preise', c: '(c) Alles mit Preis', d: '(d) Beim Einkauf' },
    stateSub: {
      a: 'Sieben Artikel bei dm, Lidl, Edeka, IKEA und ohne Laden. Keiner hat einen Preis.',
      b: 'Lidl ganz (Milch, Bananen pro kg), Brot bei Edeka. Vier ohne Preis.',
      c: 'Jeder Artikel hat einen Preis.',
      d: 'Wie (b), und ein Einkauf läuft: Lidl und das Brot sind gekauft.',
    },
    extra: { TE2: 'Durch Tippen geöffnet (b)', TE5: 'Betrag angetippt (b)', TE3: 'Oben in der Liste (b)' },
    liveCap: 'Live: „+ Preis“ antippen gibt einen Preis, eine Zeile kauft beim Einkauf',
    reset: 'Zurücksetzen',
    todayFacts: `<ul>
      <li>Mit <code>list-declutter</code> und Preisen steht der Block nach dem letzten Laden-Abschnitt, über „Zuletzt verwendet“, sobald die Liste einen offenen Artikel hat. Er erscheint auch, wenn kein Artikel einen Preis hat (<code>summary_block.dart</code>, gezeigt, wenn <code>summary.stores</code> nicht leer ist).</li>
      <li>Eine Zeile pro Gruppe mit etwas Offenem, in Laden-Reihenfolge, dann „Ohne Laden“ als eigene Gruppe (ST-Q3). Jede Zeile nennt, wie viele ihrer offenen Artikel keinen Preis haben: „1 ohne Preis“.</li>
      <li>Nur ab zwei Gruppen: die Überschrift „EINKAUFSSUMME“, die Laden-Zeilen und „Gesamt“. Bei einer Gruppe eine Zeile „Einkaufssumme“.</li>
      <li>Ein Betrag mit einem Artikel ohne Preis dahinter ist eine Untergrenze: „mind. 2,49 €“ (ST-Q1). Ein kg-Preis auf dem geplanten Gewicht ist geschätzt, ebenso jede Summe mit ihm: „≈ 3,89 €“ (ST-Q4). Beides zusammen: „mind. ≈ 6,38 €“.</li>
      <li>Die zweite Zeile der Summe zählt beide Seiten: „3 mit Preis · 4 ohne Preis“. Ganz ohne Preis steht dort „7 ohne Preis“, ohne Betrag.</li>
      <li>Nur während eines Einkaufs zählen abgehakte Artikel mit, getrennt von den offenen: „2,49 € gekauft · 1 ohne Preis“; ein ganz gekaufter Laden bleibt als „alles gekauft“ stehen (ST-Q2). Ohne Einkauf fallen abgehakte Artikel aus den Summen.</li>
      <li>Jede Zeile der Liste hat schon ihren eigenen Chip „+ Preis“; die Zählung je Laden wiederholt, was die Zeilen zeigen.</li>
    </ul>`,
    options: {
      TE1: { name: 'Nur, was einen Preis hat', what: 'Der Kassenzettel von heute ohne die leeren Zeilen. Nirgends ein Preis: kein Block. Sonst eine Zeile nur für einen Laden mit einem Preis darin; Läden ohne fallen weg, und eine Zählung an der Summe sagt, was fehlt („4 ohne Preis“). „mind.“ und „≈“ bleiben an jedem Betrag, „Ohne Laden“ behält seine Zeile, sobald es einen Preis hat.' },
      TE2: { name: 'Eine Zeile, öffnet sich', what: 'Eine Summenzeile, zugeklappt. Nirgends ein Preis: nichts. Sonst „Einkaufssumme“, der Betrag mit seinen Zeichen und eine Zählung darunter; ein Pfeil öffnet die Laden-Zeilen von TE1 darüber. Die Laden-Zeilen kosten einen Tipp; die Zeile bleibt in jedem Zustand gleich hoch.' },
      TE3: { name: 'Summen an den Laden-Trennern', what: 'Die offene Summe jedes Ladens wandert auf seinen Trenner oben im Abschnitt („1 Artikel · ≈ 3,89 €“), dorthin, wo man beim Einkauf in diesem Laden ist. Am Ende der Liste bleibt eine Summenzeile, erst sobald etwas einen Preis hat. Nirgends ein Preis: Trenner wie heute, kein Block.' },
      TE4: { name: 'Summe und der nächste Preis', what: 'Der Block macht aus den fehlenden Preisen eine Handlung: „7 ohne Preis ›“ springt zum nächsten Artikel ohne Preis und öffnet seine Preiseingabe. Nirgends ein Preis: eine Zeile, „Einkaufssumme“ und der Link. Einige Preise: die Summe und der Link. Die Laden-Zeilen kommen erst zurück, wenn jeder Artikel einen Preis hat.' },
      TE5: { name: 'Summe oben in der Leiste', what: 'Kein Block am Ende der Liste. Sobald etwas einen Preis hat, steht sein Betrag oben neben „Anpassen“ (mit einem „+“ dahinter, solange Preise fehlen), beim Scrollen immer zu sehen. Ein Tipp öffnet den Kassenzettel von TE1 in einem Blatt. Nirgends ein Preis: die Leiste wie heute.' },
    },
    meterLine: (m) => `Block auf diesem Telefon in dieser Textgröße: <b>${m.a} / ${m.b} / ${m.c} / ${m.d} px</b> in (a) / (b) / (c) / (d), gegen ${m.ta} / ${m.tb} / ${m.tc} / ${m.td} px heute. Gesparte Zeilen: <b>${m.sa} / ${m.sb} / ${m.sc} / ${m.sd}</b>.`,
    tableTitle: 'Gemessen: Höhe des Blocks und gesparte Zeilen',
    tableNote: 'Höhe ist, was die Option der Liste gegenüber gar keiner Summe hinzufügt: der Block am Ende, ein höherer Trenner (TE3) oder eine höhere Leiste oben (TE5); TE2 zugeklappt, das Blatt von TE5 zu. „Listenname gekürzt“: der Betrag von TE5 drückt den Umschalter, bis der Name der Liste auf „…“ endet. Gesparte Zeilen: Höhe heute minus Höhe der Option, in ganzen Listenzeilen (48 px bei 100 %; bei großer Schrift die gemessene Zeilenhöhe). Gemessen von verify.mjs in Chromium, Englisch; Deutsch in Klammern, wo es abweicht.',
    tableHead: ['Option', 'Telefon, Text', '(a) Keine Preise', '(b) Einige', '(c) Alle', '(d) Einkauf'],
    saved: (n) => (n > 0 ? `spart ${n}` : n < 0 ? `kostet ${-n}` : 'gleich'),
    german: 'de',
    cut: 'Listenname gekürzt',
  },
};
