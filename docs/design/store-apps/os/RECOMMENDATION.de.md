# Runde OS: Empfehlung

<!-- pick: OS1 -->
<!-- runner-up: OS4 -->

## Empfehlung

**Wahl: OS1, eine Taste im Kopf des Ladens, mit der App-Karte aus OS3 auf der Seite des Ladens als beschriftetem Zwilling.** Die Taste ist einen Tipp von der Liste entfernt. Sie kostet keine Höhe und keine Zeilen und ist da vor dem Einkauf, währenddessen und an der Kasse. Sie erscheint nur bei Läden, deren Kette eine App hat, also sehen der Markt und der Hofladen aus wie heute. Die Seite des Ladens sagt es in Worten („App: Lidl Plus, Öffnen“), neben der Verbindung zur Kette, die Runde SS dort hinzufügt.

**Zweite Wahl: OS4, ein Laden-Menü aus einer sichtbaren Taste.** Es braucht zwei Tipps, aber die Aktion hat Worte („Lidl Plus öffnen“). Jeder Kopf sieht gleich aus, und das Menü hat Platz für die nächsten Aktionen je Laden, etwa Prospekt-Links (OF1). Nimm es, wenn die Taste ohne Text im Test schlecht abschneidet.

Nicht empfohlen:
- **OS2, der Einkaufsstreifen.** Er braucht den Einkaufsmodus, der heute nur intern läuft. Er kostet 47 px, solange ein Einkauf läuft, und die Zeile springt, wenn du bei einem Laden ohne App abhakst.
- **OS5, die Erledigt-Zeile.** Sie trifft den richtigen Moment für die Kasse, erscheint aber nie vor dem letzten Haken. Bei 310 % wächst sie auf +155 px.
- **OS3 allein.** Drei Tipps, in einer Seite, die beim Einkaufen niemand öffnet.

## Gemessen

Alle Zahlen stammen aus `verify.mjs` auf dem Handy (390 × 844), jede Option gegen heute im selben Zustand. OS2 und OS5 sind während eines Einkaufs mit Haken gemessen, die anderen auf der Liste.

| Option | Tipps bis zur App | Mehr Höhe, 100 % | Zeilen im Blick, 100 % (heute) | Mehr, 200 % | Mehr, 310 % | Schild des langen Namens 100 % / 310 % (heute 220 / 130 px) | Gekürzte Namen bei 310 %, von 5 (heute 3) | Erscheint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **OS1** Taste im Kopf | 1 | +0 px | 6 (6) | +0 px | +0 px | 170 / 72 px | 5 | immer, bei Läden mit App |
| **OS2** Einkaufsstreifen | 1 | +47 px | 5 (5) | +47 px | +47 px | 220 / 130 px | 3 | nur beim Einkauf, beim Laden des letzten Hakens |
| **OS3** Seite des Ladens | 3 | +0 px | 6 (6) | +0 px | +0 px | 220 / 130 px | 3 | Liste › Anpassen › Laden |
| **OS4** Laden-Menü | 2 | +0 px | 6 (6) | +0 px | +0 px | 170 / 72 px | 5 | immer, bei jedem Laden |
| **OS5** Erledigt-Zeile | 1 | +12 px | 4 (4) | +68 px | +155 px | 220 / 130 px | 3 | erst nach dem letzten Haken eines Ladens |

- „Zeilen im Blick“ zählt ganze Artikelzeilen zwischen dem Anfang der Liste und dem Eingabefeld. Bei 100 % ändern nur OS2 und OS5 die Höhe; keine kostet dort eine ganze Zeile. Bei 200 % kosten beide eine Zeile: 3 statt heute 4 bei OS2, 2 statt 3 bei OS5.
- Die Taste kostet den langen Ladennamen bei 100 % 50 px („ALDI SÜD am Ha…“ statt „ALDI SÜD am Hauptbah…“) und bei 310 % 58 px („A…“). Heute kürzt er sich bei 310 % schon auf „AL…“. Screenreader bekommen immer den ganzen Namen.
- Bei 310 % kürzt die Taste (und OS4s Menü-Taste) alle fünf Namen, „dm“ und „Lidl“ bis auf den ersten Buchstaben; heute sind es drei. Zeigt der Kopf bei dieser Größe nur die Zahl („4“ statt „4 Artikel“), bleibt Platz: dann kürzt OS1 zwei von fünf, weniger als heute (im Prototyp gemessen, Englisch und Deutsch).
- Keine Option läuft bei 200 % oder 310 % über, auf Englisch oder Deutsch, hell oder dunkel. Jede neue Taste ist mindestens 44 × 44 px groß (`verify.mjs`).

## Was ein Tipp tut

- **Android:** Der Knopf startet die App des Händlers (ihre Start-Activity über den Paketnamen). Fehlt sie, öffnet er ihre Seite bei Google Play.
- **iPhone, mit verifiziertem App-Link** (21 der 58 Einträge im Verzeichnis, etwa ALDI SÜD `/homescreen`, ALDI Nord und REWE `/shop`): Der Link öffnet die App. Fehlt sie, öffnet der Knopf die Seite im App Store.
- **iPhone, ohne einen solchen Link:** Das betrifft Lidl Plus, Mein dm, EDEKA, Kaufland, PENNY, Netto und Rossmann, 37 der 58 Einträge. iOS kann nur die Seite im App Store öffnen, wo „Öffnen“ die installierte App startet. Das ist ein Tipp mehr; es ist der Preis dafür, dass wir keine eigenen URL-Schemes nutzen (DL1-Auftrag).
- Die Beschriftung bleibt in beiden Fällen „Lidl Plus öffnen“, weil iOS vor dem Tipp nicht weiß, ob die App installiert ist.

## Offene Fragen

1. **OS-Q1 Nur ein Symbol auf der Taste, oder Worte?** Standard: die Symbol-Taste (in neuem Fenster öffnen), für Screenreader „Lidl Plus öffnen“ genannt, mit einem einmaligen Hinweis unter dem ersten Kopf mit App. Der Hinweis steht außerhalb der Taste, nach Peters Regel für Hinweise.
2. **OS-Q2 Auch die App-Karte auf der Seite des Ladens zeigen (OS3)?** Standard: ja. Sie ist der beschriftete Zwilling, und dort sitzt auch die Verbindung zur Kette aus Runde SS.
3. **OS-Q3 Was passiert auf dem iPhone bei Apps ohne Link zu ihrem Startbildschirm (Lidl Plus, Mein dm, EDEKA und andere)?** Standard: die Seite im App Store öffnen, wo „Öffnen“ die App startet. Lidls `/prm/`-Pfade und andere tiefe Pfade bleiben ungetestet; dafür bräuchte es DL3, das gestrichen ist.
4. **OS-Q4 Was passiert bei großer Schrift, wo die Taste selbst kurze Namen kürzt?** Standard: die Taste bleibt, und über 200 % zeigt der Kopf nur die Zahl (das Wort bleibt im Screenreader-Text). Bei 310 % gemessen kürzt OS1 dann zwei von fünf Namen statt alle fünf; heute sind es drei.
5. **OS-Q5 Soll die Beschriftung anders lauten, wenn die App fehlt?** Standard: nein. „Lidl Plus öffnen“ auf beiden Plattformen; die Store-Seite erklärt sich selbst.
6. **OS-Q6 Soll der Einkaufsstreifen (OS2) den Knopf tragen, sobald der Einkaufsmodus kommt?** Standard: nicht in der ersten Version. Wieder ansehen, wenn der Einkaufsmodus ausgerollt wird.
7. **OS-Q7 Analytics.** Standard: ein Event, `store_app_opened`, mit dem Ketten-Schlüssel aus dem Verzeichnis, dem Land, der Plattform und dem Ergebnis (App oder Store-Seite). Es trägt nie den eigenen Namen des Ladens. Es bekommt eine Regel in `eventCatalog`, einen Test und eine Zeile in ANALYTICS.md, alles in DL1.
8. **OS-Q8 Kann ein Tipp, der der Taste gilt, den Abschnitt zuklappen?** Standard: Die Taste ist 48 px breit, mit 10 px Abstand zum Pfeil, und die Klapp-Fläche des Kopfs lässt sie aus. Fehltipps in der internen Beta beobachten.
