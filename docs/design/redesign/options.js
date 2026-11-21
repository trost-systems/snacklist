// Round RD: ten directions away from the hexagons, plus Today for comparison. One row per option; render.js draws
// the frames from these fields and proto.css holds each option's look under `.o-<id>`.
// cost: 'tokens' (the hex widgets take a new shape token, screens unchanged), 'widgets' (controls redrawn, the
// screens' structure kept), 'structure' (navigation or list layout changes).
// nav: which navigation the frames draw (render.js). tick: how a tick looks (row, circle, box, strike, swipe, sticker); tickAt: where its control sits (start unless 'end').
// price: chip (a tappable chip), text (amount as text, „+“ icon when none), leader (dotted leader to the amount);
// priceQuiet: no mark on a row without a price (the price is set in the item's sheet, RD-Q3).
// stores: how a store opens its rows (rule, card, title, tabs, caps).
// r: the corner radii by component size, in px: xs (checkbox, badge), sm (chip), md (button, field), lg (card, bar), xl (sheet).
export const options = [
  {
    id: 'today',
    name: { en: 'Today', de: 'Heute' },
    radius: { en: 'Hexagons', de: 'Sechsecke' },
    navName: { en: 'Floating tab bar, switcher and Edit on top', de: 'Schwebende Tab-Leiste, oben Umschalter und Anpassen' },
    cost: 'none',
    rationale: {
      en: 'The release build with hide-categories and TE1: hex pills for every control, a navy contour with a hard sticker shadow, the add field and a three-tab bar floating over the list.',
      de: 'Der Release-Build mit hide-categories und TE1: Sechseck-Pillen für jedes Bedienelement, navy Kontur mit hartem Sticker-Schatten, Eingabefeld und Leiste mit drei Tabs schweben über der Liste.',
    },
    revisits: { en: [], de: [] },
    nav: 'float', tick: 'row', price: 'chip', stores: 'rule',
    r: { xs: 0, sm: 0, md: 0, lg: 0, xl: 28 },
  },
  {
    id: 'RD1',
    name: { en: 'Soft swap', de: 'Weich getauscht' },
    radius: { en: 'Soft: 8 chip, 12 button and field, 20 bar, 24 sheet', de: 'Weich: 8 Chip, 12 Knopf und Feld, 20 Leiste, 24 Sheet' },
    navName: { en: 'Today’s floating tab bar, as a rounded capsule', de: 'Die schwebende Tab-Leiste von heute, als abgerundete Kapsel' },
    cost: 'tokens',
    rationale: {
      en: 'Every hexagon becomes a soft rounded rectangle; the layout, the navy contour and the sticker shadow stay. The cheapest way out: the hex widgets take one shape token and no screen changes.',
      de: 'Jedes Sechseck wird ein weiches Rechteck; Aufbau, navy Kontur und Sticker-Schatten bleiben. Der günstigste Weg: Die Sechseck-Widgets bekommen ein Form-Token, kein Screen ändert sich.',
    },
    revisits: {
      en: ['Shape token only: HexPill, HexBorder, HexCheckbox and the add field draw rounded rectangles', 'The yogurt’s placeholder icon is a rounded square, not a hex cell'],
      de: ['Nur das Form-Token: HexPill, HexBorder, HexCheckbox und das Eingabefeld zeichnen Rechtecke mit Rundung', 'Der Platzhalter beim Joghurt ist ein abgerundetes Quadrat statt einer Wabe'],
    },
    nav: 'float', tick: 'row', price: 'chip', stores: 'rule',
    r: { xs: 6, sm: 8, md: 12, lg: 20, xl: 24 },
  },
  {
    id: 'RD2',
    name: { en: 'Pill dock', de: 'Pillen-Dock' },
    radius: { en: 'Pill: every control fully round, 28 sheet', de: 'Pille: jedes Bedienelement ganz rund, 28 Sheet' },
    navName: { en: 'One dock: menu button beside the add field; the menu is a sheet', de: 'Ein Dock: Menü-Knopf neben dem Eingabefeld; das Menü ist ein Sheet' },
    cost: 'structure',
    rationale: {
      en: 'The tab bar goes: the list is the app, and History and every row of today’s More tab live in one menu sheet that also switches lists. Edit stays top right. The bottom band shrinks to one 52 px line, so the list gets a row back.',
      de: 'Die Tab-Leiste fällt weg: Die Liste ist die App, Verlauf und jede Zeile des heutigen Mehr-Tabs liegen in einem Menü-Sheet, das auch die Liste wechselt. Anpassen bleibt oben rechts. Unten bleibt eine Zeile von 52 px, die Liste gewinnt eine Zeile.',
    },
    revisits: {
      en: ['Navigation: three tabs become one menu sheet with the lists, History, Start a trip, Account and the rest of More', 'Ticking: a round check at the row’s start, rows without dividers', 'Elevation: contour kept, the hard sticker shadow dropped'],
      de: ['Navigation: Drei Tabs werden ein Menü-Sheet mit den Listen, Verlauf, Einkauf starten, Konto und dem Rest von Mehr', 'Abhaken: ein runder Haken vorn in der Zeile, Zeilen ohne Trennlinien', 'Tiefe: Kontur bleibt, der harte Sticker-Schatten fällt weg'],
    },
    nav: 'dock', tick: 'circle', price: 'text', stores: 'title',
    r: { xs: 999, sm: 999, md: 999, lg: 999, xl: 28 },
  },
  {
    id: 'RD3',
    name: { en: 'Docked tabs', de: 'Feste Tabs' },
    radius: { en: 'Soft: 6 box, 8 button and field, 16 sheet', de: 'Weich: 6 Box, 8 Knopf und Feld, 16 Sheet' },
    navName: { en: 'Full-width tab bar with four tabs (Stores gets one); large title', de: 'Tab-Leiste über die ganze Breite mit vier Tabs (Läden bekommt einen); großer Titel' },
    cost: 'structure',
    rationale: {
      en: 'What iOS and Android users already know: a docked bar with four tabs, Stores promoted now that categories are gone, and a large title that names the list. Calm, flat surfaces with hairlines instead of contours.',
      de: 'Was iOS- und Android-Nutzer kennen: eine feste Leiste mit vier Tabs, Läden bekommt einen, seit die Kategorien weg sind, und ein großer Titel mit dem Listennamen. Ruhige, flache Flächen mit Haarlinien statt Konturen.',
    },
    revisits: {
      en: ['Navigation: Stores becomes a tab; Edit leaves the top bar', 'Ticking: a square check box at the row’s end', 'Elevation: flat, 1 px dividers, no contour or sticker shadow', 'Type: a 32 px Bricolage title for the list'],
      de: ['Navigation: Läden wird ein Tab; Anpassen verlässt die obere Leiste', 'Abhaken: eine eckige Box am Zeilenende', 'Tiefe: flach, 1-px-Trennlinien, keine Kontur, kein Sticker-Schatten', 'Schrift: ein 32-px-Titel in Bricolage für die Liste'],
    },
    nav: 'docked', tick: 'box', tickAt: 'end', price: 'text', priceQuiet: true, stores: 'title',
    r: { xs: 6, sm: 8, md: 8, lg: 12, xl: 16 },
  },
  {
    id: 'RD4',
    name: { en: 'One screen', de: 'Ein Screen' },
    radius: { en: 'Nested by size: 4 small, 12 medium, 20 large', de: 'Nach Größe verschachtelt: 4 klein, 12 mittel, 20 groß' },
    navName: { en: 'No tabs: the title opens a panel with lists and every other place', de: 'Keine Tabs: Der Titel öffnet ein Panel mit Listen und allen anderen Orten' },
    cost: 'structure',
    rationale: {
      en: 'The title is the only menu: a tap drops a panel with households, lists, History and every row of today’s More tab. The add field docks to the bottom edge. Radii follow the size of the thing, so small parts look precise and big ones soft.',
      de: 'Der Titel ist das einzige Menü: Ein Tipp öffnet ein Panel mit Haushalten, Listen, Verlauf und jeder Zeile des heutigen Mehr-Tabs. Das Eingabefeld sitzt fest am unteren Rand. Die Rundung folgt der Größe: Kleines wirkt präzise, Großes weich.',
    },
    revisits: {
      en: ['Navigation: tab bar and Edit replaced by the title’s panel', 'Density: 44 px rows with full-width hairlines (one more row)', 'Add: a docked field with the mic inside', 'Ticking: a 4 px rounded box at the start'],
      de: ['Navigation: Tab-Leiste und Anpassen weichen dem Panel am Titel', 'Dichte: 44-px-Zeilen mit Haarlinien über die ganze Breite (eine Zeile mehr)', 'Hinzufügen: ein festes Feld mit Mikrofon', 'Abhaken: eine Box mit 4 px Rundung vorn'],
    },
    nav: 'panel', tick: 'box', price: 'text', priceQuiet: true, stores: 'caps',
    r: { xs: 4, sm: 8, md: 12, lg: 20, xl: 20 },
  },
  {
    id: 'RD5',
    name: { en: 'Store cards', de: 'Laden-Karten' },
    radius: { en: 'Round: 12 chip, 16 button, 24 card and sheet, circle FAB', de: 'Rund: 12 Chip, 16 Knopf, 24 Karte und Sheet, runder FAB' },
    navName: { en: 'Bottom bar with four tabs around a round add button', de: 'Untere Leiste mit vier Tabs um einen runden Hinzufügen-Knopf' },
    cost: 'structure',
    rationale: {
      en: 'Each store is a card, so the list reads as the stops of a trip. The add field turns into a round yellow button in the middle of the bar, which opens the add sheet; the list keeps the space the field took.',
      de: 'Jeder Laden ist eine Karte, die Liste liest sich wie die Stationen eines Einkaufs. Das Eingabefeld wird ein runder gelber Knopf mitten in der Leiste, der das Sheet öffnet; die Liste behält den Platz des Felds.',
    },
    revisits: {
      en: ['Add: the button opens the sheet in one tap, as tapping today’s field does; the “What do you need?” prompt leaves the list', 'Stores: each one a raised card with its count and sum', 'Elevation: soft shadows instead of the sticker shadow', 'Empty state: one card with a big + to start', 'Ticking: as today, the whole row turns mint and strikes through'],
      de: ['Hinzufügen: Der Knopf öffnet das Sheet mit einem Tipp, wie heute das Feld; die Frage „Was brauchst du?“ verschwindet von der Liste', 'Läden: jeder eine erhabene Karte mit Anzahl und Summe', 'Tiefe: weiche Schatten statt Sticker-Schatten', 'Leerer Zustand: eine Karte mit großem + zum Start', 'Abhaken: wie heute, die ganze Zeile wird mint und durchgestrichen'],
    },
    nav: 'fab', tick: 'row', price: 'chip', stores: 'card',
    r: { xs: 999, sm: 12, md: 16, lg: 24, xl: 24 },
  },
  {
    id: 'RD6',
    name: { en: 'Side drawer', de: 'Seitenmenü' },
    radius: { en: 'Squircle: continuous corners, 10 small, 18 medium, 28 large', de: 'Squircle: fließende Ecken, 10 klein, 18 mittel, 28 groß' },
    navName: { en: 'Menu button opens a drawer: household, lists, places', de: 'Menü-Knopf öffnet ein Seitenmenü: Haushalt, Listen, Orte' },
    cost: 'structure',
    rationale: {
      en: 'A drawer holds everything that is not the list, with the household and its people on top. Continuous (squircle) corners are softer than circles at the same size, and Flutter draws them natively.',
      de: 'Ein Seitenmenü hält alles, was nicht die Liste ist, oben der Haushalt mit seinen Leuten. Fließende Ecken (Squircle) wirken weicher als Kreisbögen gleicher Größe, und Flutter zeichnet sie selbst.',
    },
    revisits: {
      en: ['Navigation: drawer with members, lists, History and every row of today’s More tab', 'Shape: continuous corners (RoundedSuperellipseBorder in Flutter)', 'Prices: plain amounts in a muted column, „+“ only on unpriced rows', 'Motion: the drawer pushes the list 24 px', 'Ticking: swipe right or tap; the row turns mint under a check'],
      de: ['Navigation: Seitenmenü mit Mitgliedern, Listen, Verlauf und jeder Zeile des heutigen Mehr-Tabs', 'Form: fließende Ecken (RoundedSuperellipseBorder in Flutter)', 'Preise: Beträge leise in einer Spalte, „+“ nur ohne Preis', 'Bewegung: Das Menü schiebt die Liste 24 px zur Seite', 'Abhaken: nach rechts wischen oder tippen; die Zeile wird mint unter einem Haken'],
    },
    nav: 'drawer', tick: 'swipe', price: 'text', stores: 'title',
    r: { xs: 10, sm: 10, md: 18, lg: 28, xl: 28 },
  },
  {
    id: 'RD7',
    name: { en: 'People first', de: 'Leute zuerst' },
    radius: { en: 'Mixed: circles for people and ticks, 10 for everything else', de: 'Gemischt: Kreise für Leute und Haken, 10 für alles andere' },
    navName: { en: 'Segmented List | History on top; the household’s faces open a sheet with Edit and all of More', de: 'Segmente Liste | Verlauf oben; die Gesichter des Haushalts öffnen ein Sheet mit Anpassen und allem aus Mehr' },
    cost: 'structure',
    rationale: {
      en: 'Snacklist is shared, so the people are the menu: the household’s avatars top right open a sheet with the household, Edit and every row of today’s More tab. List and History switch with a segmented control; nothing sits at the bottom but the add field.',
      de: 'Snacklist wird geteilt, also sind die Leute das Menü: Die Avatare oben rechts öffnen ein Sheet mit dem Haushalt, Anpassen und jeder Zeile des heutigen Mehr-Tabs. Liste und Verlauf wechseln über Segmente; unten sitzt nur das Eingabefeld.',
    },
    revisits: {
      en: ['Navigation: segmented control and an avatar menu, no tab bar', 'Ticking: a circle at the row’s end, the row turns mint', 'Quantities: a small badge before the name instead of blue text', 'Icons: the emoji stay, the placeholder is a circle'],
      de: ['Navigation: Segmente und ein Avatar-Menü, keine Tab-Leiste', 'Abhaken: ein Kreis am Zeilenende, die Zeile wird mint', 'Mengen: ein kleines Badge vor dem Namen statt blauer Schrift', 'Icons: Emoji bleiben, der Platzhalter ist ein Kreis'],
    },
    nav: 'avatars', tick: 'circle', tickAt: 'end', price: 'text', stores: 'title',
    r: { xs: 999, sm: 10, md: 10, lg: 16, xl: 20 },
  },
  {
    id: 'RD8',
    name: { en: 'Store tabs', de: 'Laden-Tabs' },
    radius: { en: 'Tight: 4 small, 6 everywhere else, 12 sheet', de: 'Knapp: 4 klein, 6 überall sonst, 12 Sheet' },
    navName: { en: 'Store tabs under the title; a ••• menu for the rest', de: 'Laden-Tabs unter dem Titel; ein •••-Menü für den Rest' },
    cost: 'structure',
    rationale: {
      en: 'In the shop you want one store: tabs filter the list to it, with All as the default. History, Edit, Start a trip, Settings and the legal pages move into a compact ••• menu, Account and the rest behind its More row, so the bottom holds only the add field.',
      de: 'Im Laden zählt ein Laden: Tabs filtern die Liste darauf, Alle ist der Standard. Verlauf, Anpassen, Einkauf starten, Einstellungen und die Rechtstexte wandern in ein kompaktes •••-Menü, Konto und der Rest hinter dessen Zeile Mehr; unten bleibt nur das Eingabefeld.',
    },
    revisits: {
      en: ['Store switching: horizontal tabs with counts', 'Navigation: an overflow menu, no tab bar', 'Shape: tight 6 px corners, underline for the active tab', 'Ticking: tap the row, the name strikes through'],
      de: ['Laden wechseln: Tabs mit Anzahl nebeneinander', 'Navigation: ein Überlauf-Menü, keine Tab-Leiste', 'Form: knappe 6-px-Ecken, Unterstrich für den aktiven Tab', 'Abhaken: Zeile antippen, der Name wird durchgestrichen'],
    },
    nav: 'storeTabs', tick: 'strike', price: 'text', priceQuiet: true, stores: 'tabs',
    r: { xs: 4, sm: 6, md: 6, lg: 6, xl: 12 },
  },
  {
    id: 'RD9',
    name: { en: 'Receipt', de: 'Kassenbon' },
    radius: { en: 'Sharp: 2 everywhere; a torn edge is the motif', de: 'Scharf: 2 überall; die Abrisskante ist das Motiv' },
    navName: { en: 'Today’s three tabs as a docked text bar with a yellow underline', de: 'Die drei Tabs von heute als feste Textleiste mit gelbem Unterstrich' },
    cost: 'widgets',
    rationale: {
      en: 'Snacklist adds up what you buy, so the list looks like the receipt it becomes: sharp corners, ink rules, dotted leaders to the prices and a torn edge under the total. Same screens and tabs as today; only the controls are redrawn.',
      de: 'Snacklist rechnet zusammen, was ihr kauft, also sieht die Liste aus wie der Bon, der sie wird: scharfe Ecken, Tintenlinien, Punktlinien zu den Preisen und eine Abrisskante unter der Summe. Gleiche Screens und Tabs wie heute; nur die Bedienelemente sind neu gezeichnet.',
    },
    revisits: {
      en: ['Prices: dotted leaders, tabular numbers, the total as a receipt foot', 'Ticking: an ink line strikes the row', 'Type: store names in Bricolage caps, 46 px rows', 'Shape: the torn edge replaces the honeycomb as the brand motif'],
      de: ['Preise: Punktlinien, Ziffern in Spalten, die Summe als Bon-Fuß', 'Abhaken: ein Tintenstrich durch die Zeile', 'Schrift: Ladennamen in Bricolage-Versalien, 46-px-Zeilen', 'Form: Die Abrisskante ersetzt die Wabe als Marken-Motiv'],
    },
    nav: 'textTabs', tick: 'strike', price: 'leader', stores: 'caps',
    r: { xs: 2, sm: 2, md: 2, lg: 2, xl: 2 },
  },
  {
    id: 'RD10',
    name: { en: 'Bite', de: 'Biss' },
    radius: { en: 'Round 20, with a bite out of one corner on the hero controls', de: 'Rund 20, mit einem Biss aus einer Ecke bei den Hauptelementen' },
    navName: { en: 'Floating tab capsule plus a separate round add button', de: 'Schwebende Tab-Kapsel plus eigener runder Hinzufügen-Knopf' },
    cost: 'structure',
    rationale: {
      en: 'A snack has a bite taken out of it: the add button, the active tab and the total carry a round notch in one corner, the new brand motif. The sticker shadow stays, so it still feels like Snacklist.',
      de: 'Einem Snack fehlt ein Bissen: Hinzufügen-Knopf, aktiver Tab und die Summe haben eine runde Kerbe in einer Ecke, das neue Marken-Motiv. Der Sticker-Schatten bleibt, es fühlt sich weiter nach Snacklist an.',
    },
    revisits: {
      en: ['Shape: the bite replaces the honeycomb (also a candidate for the app icon, RD-Q4)', 'Ticking: a yellow sticker dot with a check pops in', 'Add: a round button beside the tabs opens the sheet', 'Totals: a raised card with the bite'],
      de: ['Form: Der Biss ersetzt die Wabe (auch für das App-Icon denkbar, RD-Q4)', 'Abhaken: ein gelber Sticker-Punkt mit Haken springt auf', 'Hinzufügen: ein runder Knopf neben den Tabs öffnet das Sheet', 'Summe: eine erhabene Karte mit Biss'],
    },
    nav: 'split', tick: 'sticker', price: 'chip', stores: 'rule',
    r: { xs: 999, sm: 12, md: 20, lg: 24, xl: 28 },
  },
];
export const ids = options.map((o) => o.id);
export const byId = Object.fromEntries(options.map((o) => [o.id, o]));
export const frames = ['list', 'tick', 'nav', 'add', 'screen', 'empty'];
export const frameName = {
  list: { en: 'List', de: 'Liste' },
  tick: { en: 'Tick', de: 'Abhaken' },
  nav: { en: 'Menu open', de: 'Menü offen' },
  add: { en: 'Add sheet', de: 'Hinzufügen' },
  screen: { en: 'More', de: 'Mehr' },
  empty: { en: 'Empty list', de: 'Leere Liste' },
};
