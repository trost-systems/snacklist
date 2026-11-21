# Runde RD: Snacklist ohne Sechsecke (Job 353)

Peter wollte 10 Entwürfe mit verschiedenen Designs weg von den Sechsecken, mit anderen Eckenradien und einem neuen
Blick auf das Menü. Die heutigen Farben bleiben. Diese Runde ist ein Wegwerf-Prototyp. In der App hat sich nichts
geändert.

- Seite: `docs/design/redesign/rd/` (Englisch; `?lang=de` für Deutsch, `?theme=dark`, `?ts=200` oder `?ts=310`).
- Jede Option ist auf dieselbe Liste gezeichnet: die Liste aus Job 350 mit ausgeblendeten Kategorien und der Summe TE1
  aus Job 348. Der Haushalt ist die erfundene Familie Brandt. Alle Daten sind Beispieldaten.
- Jede Option hat sechs Bilder: die Liste, ein Abhaken, das offene Menü, das Hinzufügen-Sheet mit Tastatur, die
  Einstellungen und die leere Liste.
- Die Farben sind genau die heutigen Tokens. `palette.css` wird aus `app/lib/design/tokens.g.dart` erzeugt, und
  `verify.mjs` schlägt fehl, wenn ein Telefon eine Farbe außerhalb davon malt. Formen, Menüs, Zeilen, Haken und Schrift
  sind frei.
- Wo die Sechsecke heute stecken: `HEX-INVENTORY.md` (135 direkte Aufrufstellen in 46 Dateien, etwa 227 weitere über
  das Theme, dazu das Icon, die Store-Rahmen und die Website).

## Die zehn Optionen

| Option | Ecken | Menü | Aufwand |
| --- | --- | --- | --- |
| RD1 Weich getauscht | weich: 8 Chip, 12 Button und Feld, 20 Leiste, 24 Sheet | die heutige schwebende Tab-Leiste | günstig: nur Tokens |
| RD2 Pillen-Dock | Pille bei jedem Bedienelement, 28 Sheet | keine Tab-Leiste; ein Menü-Button neben dem Eingabefeld öffnet ein Sheet mit Listen, Verlauf, Läden, Anpassen, Einstellungen | strukturell |
| RD3 Feste Tabs | 6 Box, 8 Button und Feld, 16 Sheet | Tab-Leiste über die volle Breite mit vier Tabs (Läden bekommt einen), großer Titel | strukturell |
| RD4 Ein Screen | nach Größe verschachtelt: 4 klein, 12 mittel, 20 groß | keine Tabs; der Titel klappt ein Panel mit Haushalten, Listen, Verlauf, Läden, Einstellungen auf | strukturell |
| RD5 Laden-Karten | 12 Chip, 16 Button, 24 Karte und Sheet, runder Hinzufügen-Button | untere Leiste mit vier Tabs um einen runden Hinzufügen-Button | strukturell |
| RD6 Seitenmenü | Squircle (fließende Ecken) 10 / 18 / 28 | Menü-Button oben links öffnet ein Seitenmenü | strukturell |
| RD7 Leute zuerst | Kreise für Leute und Haken, 10 für den Rest | Liste und Verlauf als Segmente oben; die Avatare des Haushalts öffnen die Einstellungen | strukturell |
| RD8 Laden-Tabs | eng: 4 und 6, 12 Sheet | Tabs pro Laden unter dem Titel; ein •••-Menü für den Rest | strukturell |
| RD9 Kassenbon | überall scharf 2; ein abgerissener Rand ist das Motiv | die heutigen drei Tabs als feste Textleiste | mittel: Widgets neu gezeichnet |
| RD10 Biss | rund 20, mit einem runden Biss aus einer Ecke der Hauptelemente | schwebende Tab-Kapsel plus ein eigener runder Hinzufügen-Button | strukturell |

Was jede Option sonst noch ändert, und warum, steht auf der Seite unter ihrem Namen. Kurz:

- **RD1** behält jeden Screen. Nur die Form ändert sich (Inventar: `HlHex.tip` auf 0 macht aus `HexBorder` ein
  abgerundetes Rechteck; `PointyHex`, Radio, Switch, Segmented Control und Checkbox brauchen trotzdem eigene
  Neufassungen).
- **RD2** macht die Liste zur App. Unten sitzen ein runder Menü-Button und das Eingabefeld. Zeilen verlieren ihre
  Trennlinien und bekommen vorne einen runden Haken. Die Kontur bleibt, der harte Sticker-Schatten geht.
- **RD3** ist das, was iOS- und Android-Nutzer schon kennen: flache Flächen, Haarlinien und eine Checkbox am Ende der
  Zeile.
- **RD4** ist am dichtesten: 44 px hohe Zeilen und ein festes Eingabefeld. Die Radien folgen der Größe des Teils.
- **RD5** setzt jeden Laden in eine Karte mit seiner Summe, und das Eingabefeld wird ein runder Button. Ein Tipp öffnet
  das Sheet, wie heute ein Tipp ins Feld. Aber die Frage „Was brauchst du?“ verschwindet aus der Liste.
- **RD6** nutzt fließende Ecken (Flutter: `RoundedSuperellipseBorder`; die Seite zeigt sie in Chrome, Safari zeichnet
  normale runde Ecken). Ein Wisch nach rechts hakt ab.
- **RD7** setzt die Leute des Haushalts in die Ecke und zeigt Mengen als kleine Badges.
- **RD8** filtert die Liste auf einen Laden, für den Einsatz im Geschäft.
- **RD9** zeichnet die Liste als den Kassenbon, der aus ihr wird: gepunktete Linien zu den Preisen und ein abgerissener
  Rand unter der Summe.
- **RD10** ersetzt die Waben durch einen Biss als Markenmotiv. Das passt auch für das App-Icon (RD-Q4).

## Messungen

<!-- table -->
| Option | Aufwand | Ganze Zeilen, 100 % | Ganze Zeilen, 310 % | Kleinstes Tippziel | Niedrigster Textkontrast, hell / dunkel | Niedrigster Randkontrast, hell / dunkel | Überläufe bei 310 % | Getrennte Wörter bei 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Heute | heute | 7 | 1 | 44 px | 7,1 / 8,43 | – / – | 0 | 7 |
| RD1 Weich getauscht | günstig (nur Tokens) | 7 | 2 | 44 px | 7,1 / 8,43 | 7,1 / 5,12 | 0 | 2 |
| **RD2 Pillen-Dock** | strukturell | 8 | 2 | 44 px | 7,1 / 8,43 | 7,1 / 5,12 | 0 | 2 |
| RD3 Feste Tabs | strukturell | 7 | 2 | 44 px | 7,1 / 8,43 | 7,1 / 8,43 | 0 | 2 |
| RD4 Ein Screen (zweite Wahl) | strukturell | 10 | 2 | 44 px | 7,1 / 8,43 | 7,1 / 5,12 | 0 | 2 |
| RD5 Laden-Karten | strukturell | 8 | 2 | 44 px | 7,1 / 8,43 | 8,87 / 8,43 | 0 | 2 |
| RD6 Seitenmenü | strukturell | 9 | 2 | 44 px | 7,1 / 8,56 | 7,1 / 9,68 | 0 | 2 |
| RD7 Leute zuerst | strukturell | 7 | 2 | 44 px | 6,63 / 8,43 | 7,1 / 5,12 | 0 | 1 |
| RD8 Laden-Tabs | strukturell | 8 | 2 | 44 px | 7,1 / 8,43 | 8,87 / 5,12 | 0 | 2 |
| RD9 Kassenbon | mittel (Widgets) | 7 | 2 | 44 px | 7,1 / 8,43 | 8,87 / 8,43 | 0 | 2 |
| RD10 Biss | strukturell | 8 | 2 | 44 px | 7,1 / 8,43 | 7,1 / 5,12 | 0 | 2 |
<!-- /table -->

So wurde gemessen. `verify.mjs` rendert jede Option × Bild × hell und dunkel × 100, 200 und 310 % Text × Englisch und
Deutsch (792 Telefone) in Chromium und misst jedes mit `measure.js`:

- **Ganze Zeilen.** Artikelzeilen, die ganz zwischen oberer und unterer Leiste liegen, im Listen-Bild (Englisch, hell).
  Das Telefon ist ein iPhone-Screen mit 390 × 844, mit 47 px Statusleiste und 34 px Home-Indikator. Die Zahlen aus
  Job 347 (heute 9) stammen aus dem Fenster des Web-Builds, das keine Statusleiste und keinen Home-Indikator hat. Es ist
  also etwa 80 px höher.
- **Kleinste Tippfläche.** Die kürzere Seite von allem, was tippbar und nicht verdeckt ist: Zeilen, Chips, Tabs,
  Menüzeilen, Buttons. Die Prüfung schlägt unter 44 px fehl.
- **Textkontrast.** WCAG-Verhältnis jedes Textes zur Farbe darunter. Die Prüfung schlägt unter 4,5 fehl, bei großem Text
  unter 3.
- **Randkontrast.** Für jedes Bedienelement der größere Wert von Rand oder Füllung gegen den Grund. Die Prüfung schlägt
  unter 3 fehl (WCAG 1.4.11). Heute sind die Umrisse als Sechseck-Schatten gezeichnet, die diese Prüfung nicht lesen
  kann, daher „–“.
- **Überläufe.** Text, der abgeschnitten ist, den Screen verlässt oder anderen Text überlappt, bei 310 %, über alle
  Bilder, beide Themes und beide Sprachen. Die Prüfung schlägt bei jedem Fall fehl.
- **Getrennte Wörter.** Wörter, die bei 310 % auf zwei Zeilen umbrechen (hell, beide Sprachen). Das wird nur berichtet,
  nicht als Fehler gewertet: Lange deutsche Wörter wie „Einkaufsliste“ müssen bei der größten Stufe umbrechen.
- Die Zahlen der Tabelle kommen aus `rd/measured.json` (`tools/table.mjs`), und `verify.mjs` prüft jede Zelle gegen
  einen frischen Lauf.

Tipps, gezählt nach dem Design des jeweiligen Menüs (nicht gemessen):

| Option | zum Verlauf | zu den Läden | zu den Einstellungen | zu einer anderen Liste | Menü öffnet von |
| --- | --- | --- | --- | --- | --- |
| Heute, RD1, RD9, RD10 | 1 | 2 | 2 | 2 | unten (Tabs) |
| RD2 | 2 | 2 | 2 | 2 | unten (Menü-Button) |
| RD3, RD5 | 1 | 1 | 2 | 2 | unten (Tabs) |
| RD4, RD6, RD8 | 2 | 2 | 2 | 2 | oben |
| RD7 | 1 | 2 | 2 | 2 | oben |

Was die Zahlen sagen:

- Keine Option fällt durch eine Prüfung. Jede behält 44 px große Tippflächen, WCAG-Kontrast in beiden Themes und keinen
  Überlauf. Die Palette übersteht also jede Form.
- Die Zeilen unterscheiden sie. RD4 zeigt 3 Zeilen mehr als Heute, RD6 2 mehr, und RD2, RD5, RD8 und RD10 eine mehr.
  RD1, RD3, RD7 und RD9 zeigen so viele wie Heute.
- Bei 310 % zeigt jede RD-Option 2 ganze Zeilen, Heute nur 1. Sie nutzen dieselbe Regel für große Schrift: Der Preis
  rutscht unter den Namen, und Überschriften wachsen ab 200 % nicht weiter (RD-Q6).

## Empfehlung

**Empfehlung: RD2 Pillen-Dock.** Sie erfüllt beide Wünsche von Peter mit der kleinsten Änderung daran, wie man die
Liste benutzt:

- Die Sechsecke werden Pillen, eine freundliche Form, die zu einer Snack-App passt.
- Die Tab-Leiste fällt weg. Verlauf, Läden, Anpassen und Einstellungen liegen in einem Menü-Sheet, das auch die Listen
  wechselt.
- Der Menü-Button sitzt neben dem Eingabefeld in Daumenreichweite. Der untere Rand des Screens ist damit eine Zeile.
- Die Liste gewinnt eine Zeile (8 statt 7).
- Hinzufügen bleibt gleich: Das Feld ist immer da.
- Der Nachteil ist ein Tipp mehr zum Verlauf (2 statt 1). Der Verlauf ist heute der am wenigsten genutzte Tab. Das ist
  eine Annahme. RD-Q2 enthält die Prüfung in den Analytics.

**Zweite Wahl: RD4 Ein Screen.** Sie hat die dichteste Liste: 10 Zeilen statt 7. Ihre Radien folgen der Größe jedes
Teils. Das ist das am klarsten begründete Radius-System der zehn. Ihr Menü sitzt oben unter dem Titel, auf einem großen
Telefon außer Daumenreichweite. Deshalb kommt sie auf Platz zwei.

**In zwei Schritten ausliefern (RD-Q1).**

1. **Zuerst RD1.** Das sind nur Tokens. Die Sechsecke verschwinden so innerhalb von Tagen von jedem Screen:
   `HlHex.tip` → 0 (zuerst mit Goldens absichern), dazu Neufassungen von `PointyHex`, `HexRadio`, `HexSwitch`,
   `HexSegmented` und `HexCheckbox`.
2. **Dann das Dock und das Menü-Sheet von RD2**, hinter einem Flag.

RD1 allein antwortet schon den Nutzern, die die Sechsecke nicht mögen. RD2 ist danach eine kleinere, eigene Änderung.

Nicht gewählt, und warum:

- **RD3:** Standard, aber sie fügt einen Tab hinzu, wo Peter das Menü neu denken wollte.
- **RD5 und RD10:** Das Eingabefeld wird ein Button, und die Frage „Was brauchst du?“ verschwindet aus der Liste.
- **RD6 und RD8:** Das Menü sitzt oben rechts oder oben links.
- **RD7:** Sie gewinnt keine Zeilen.
- **RD9:** Ein starker Look für die Summen, aber die gepunkteten Linien ziehen jede Zeile zum Geld hin, und eine Zeile
  ohne Preis endet bei „+ Preis“.

## Offene Fragen (es gelten die Vorgaben, wenn Peter nichts anderes sagt)

- **RD-Q1: zwei Schritte?** Vorgabe: ja. Zuerst der Token-Tausch von RD1, dann das Dock von RD2 hinter einem neuen Flag
  (`pill-dock`).
- **RD-Q2: Verlauf ohne Tab.** Vorgabe: Der Verlauf ist die erste Zeile im Menü-Sheet. Vor dem Bauen die
  PostHog-Screen-Views von Verlauf gegen Liste prüfen. Wenn der Verlauf oft geöffnet wird,
  hält die Tab-Leiste von RD3 oder RD9 ihn bei 1 Tipp.
- **RD-Q3: eine Zeile ohne Preis.** RD2 behält ein kleines „+“ am Zeilenende, das den Preis setzt wie heute der Chip
  „+ Preis“. RD3, RD4 und RD8 zeigen nichts, und der Preis wird im Sheet des Artikels gesetzt. Vorgabe: das kleine „+“
  von RD2.
- **RD-Q4: App-Icon, Store-Rahmen und Website.** Das Icon (#5 Wabenstapel), das „Wabenband“ der Store-Rahmen, die
  Sechseck-Masken der Website und das E-Mail-Logo sind ebenfalls Sechsecke (Inventar). Vorgabe: eine eigene Folgerunde
  für Icon und Markenzeichen, mit dem Biss aus RD10 als einem Kandidaten. Store-Rahmen und Website folgen der App im
  selben Release.
- **RD-Q5: der Sticker-Schatten.** RD2 lässt den harten Navy-Schatten weg und behält die 2 px Kontur. RD1 und RD10
  behalten beides. Vorgabe: mit RD2 weglassen.
- **RD-Q6: große Schrift.** In jeder RD-Option rutscht der Preis ab 200 % unter den Namen, und Überschriften wachsen ab
  200 % nicht weiter. Vorgabe: ja, für alle Listenzeilen und Überschriften.
- **RD-Q7: Abhaken.** RD2 zeichnet vorne in der Zeile einen runden Haken. Die ganze Zeile hakt weiterhin ab, wie heute,
  und der Kreis zeigt den Zustand. Vorgabe: wie gezeichnet.
- **RD-Q8: Anpassen.** RD2 behält es oben rechts als ruhige Pille und führt es auch im Menü. Vorgabe: beides.
- **RD-Q9: Felder und Beschriftungen.** Heute stehen die Beschriftungen über den Feldern, weil ein Sechseck-Umriss keine
  schwebende Beschriftung tragen kann (`LabeledField`, Lint `no-label-in-hex-field`). Vorgabe: Beschriftungen über dem
  Feld lassen und die Lint-Regel umbenennen, wenn die Sechsecke gehen.
- **RD-Q10: der leere Zustand.** Die leere Liste jeder Option zeichnet ihr eigenes Motiv statt des Sechsecks. Vorgabe:
  der gelbe Kreis von RD2, bis RD-Q4 das Markenzeichen klärt.

## So prüfst du es

- `node docs/design/redesign/verify.mjs` prüft:
  - `strings.js` und `palette.css` gegen die App;
  - die Messwerte jedes Telefons;
  - beide Tabellen in `RECOMMENDATION.md` und `.de.md`, Zelle für Zelle, gegen einen frischen Lauf.
- `--write` schreibt `rd/measured.json` neu, und `--shots <dir>` schreibt Screenshots.
- `node docs/design/redesign/tools/table.mjs` schreibt die Tabellen aus `measured.json` neu.
