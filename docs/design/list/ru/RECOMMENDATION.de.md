# Empfehlung

**Wahl: RU2, das getönte Fach mit Vorschau. Zweite Wahl: RU4, abgehakt mit Häkchen.**

## Was die Messung geändert hat

Den Abschnitt standardmäßig aufzuklappen zeigt allein noch nicht, wie der abgehakte Artikel ankommt. Ganz oben in der Liste zeigt keine Option eine ganze Zeile aus „Zuletzt verwendet“. Das gilt auf dem iPhone (390 × 844) und auf Android (360 × 640), bei 100 % und bei der größten Schrift, auf Deutsch und Englisch, mit einer kurzen Liste (5 offen) und einer langen (11 offen). Der Abschnitt steht nach dem letzten Laden und nach der Einkaufssumme (TE1), und bei 5 offenen Artikeln füllt die Summe allein den Rest des Bildschirms. Mit jedem offenen Abschnitt verschwindet ein abgehakter Artikel bei einer normalen Liste also trotzdem aus dem Blick. Auf dem iPhone muss man bei 5 offenen Artikeln 55 bis 109 px scrollen, bis der erste Artikel ganz zu sehen ist, bei 11 offenen 343 bis 397 px.

Nur RU2 zeigt die Ankunft auf dem ersten Bildschirm. Solange das Fach unter dem Bildschirm liegt, sitzt eine Vorschau auf dem Eingabefeld: „Abgehakt · 3“ und der neueste abgehakte Artikel als Pille. Ein Haken lässt die Zeile in die Vorschau fliegen, und ein Tipp auf die Pille holt den Artikel zurück. Hinuntergescrollt ist das Fach klar nicht die Liste: eigene Tönung, runder Haken, kompakte blasse Zeilen und ein Rückgängig-Pfeil an jeder Zeile.

Die Vorschau kostet Platz, solange sie zu sehen ist. Bei der langen Liste kostet sie auf dem iPhone 1 offene Zeile (9 statt 10) und auf Android 2 (6 statt 8). Bei 310 % und der kurzen Liste kostet sie auf Deutsch keine Zeile (RU1 und RU2 zeigen je 2), auf Englisch eine. Ohne zuletzt verwendete Artikel gibt es weder Abschnitt noch Vorschau, und jede Option zeigt dieselben Zeilen wie heute.

RU4 ist die zweite Wahl. Hinuntergescrollt zeigt es am klarsten, dass der Artikel abgehakt und nicht weg ist: ein gefüllter runder Haken und der Name durchgestrichen, wie in einer Aufgabenliste. Mit 15 Artikeln ist es auch der kürzeste Abschnitt (380 px statt 814 px bei RU1), weil es die neuesten 5 zeigt und dann „Alle zeigen (15)“. Die Ankunft außerhalb des Bildschirms löst es aber nicht. RU-F3 schlägt vor, RU4s Zeilen mit Haken und Durchstreichung in RU2s Fach zu setzen, falls Peter beides mag.

RU1 ändert am wenigsten gegenüber heute, ist aber der höchste Abschnitt (814 px mit 15), und seine blassen Zeilen sehen der Liste selbst am ähnlichsten. RU3s Chips sind bei der kurzen Liste am kompaktesten (112 px mit 3), aber Pillen lesen sich wie Vorschläge, nicht wie „was ich gerade abgehakt habe“. Die Reihenfolge der Liste geht auf einen Blick verloren.

## Gemessen (iPhone 390 × 844, 100 %, Deutsch)

Ganze Zeilen ganz oben zwischen Kopfleiste und Eingabefeld (oder RU2s Vorschau). „Bis erster“ ist, wie weit die Liste scrollen muss, bis der neueste zuletzt verwendete Artikel ganz über dem Eingabefeld steht. „—“ heißt: Die zugeklappte Kachel von heute zeigt den Artikel nie ohne Tipp. Mit 0 zuletzt verwendeten Artikeln zeigen alle Optionen 5 (kurz) und 10 (lang) offene Zeilen, wie heute.

<!-- measured: de ios 100 -->
| Option | Kurz 3: offen | Kurz 3: zuletzt | Kurz 15: zuletzt | Lang 15: offen | Lang 15: zuletzt | Lang 15: bis erster (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 5 | 0 | 0 | 10 | 0 | — |
| RU1 | 5 | 0 | 0 | 10 | 0 | 397 |
| RU2 | 5 | 0 | 0 | 9 | 0 | 347 |
| RU3 | 5 | 0 | 0 | 10 | 0 | 359 |
| RU4 | 5 | 0 | 0 | 10 | 0 | 343 |

### Größte Schrift (iPhone, 310 %)

<!-- measured: de ios 310 -->
| Option | Kurz 3: offen | Kurz 3: zuletzt | Kurz 15: zuletzt | Lang 15: offen | Lang 15: zuletzt | Lang 15: bis erster (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 2 | 0 | 0 | 2 | 0 | — |
| RU1 | 2 | 0 | 0 | 2 | 0 | 3115 |
| RU2 | 2 | 0 | 0 | 2 | 0 | 2726 |
| RU3 | 2 | 0 | 0 | 2 | 0 | 2975 |
| RU4 | 2 | 0 | 0 | 2 | 0 | 2719 |

### Android (360 × 640, 100 %)

<!-- measured: de android 100 -->
| Option | Kurz 3: offen | Kurz 3: zuletzt | Kurz 15: zuletzt | Lang 15: offen | Lang 15: zuletzt | Lang 15: bis erster (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 5 | 0 | 0 | 8 | 0 | — |
| RU1 | 5 | 0 | 0 | 8 | 0 | 601 |
| RU2 | 5 | 0 | 0 | 6 | 0 | 551 |
| RU3 | 5 | 0 | 0 | 8 | 0 | 563 |
| RU4 | 5 | 0 | 0 | 8 | 0 | 547 |

## Offene Fragen (jede mit dem Standard, den der Bau nimmt)

1. **RU-F1 Flag.** Hinter einem neuen PostHog-Flag `recently-used-open`, zuerst an für Peter und die internen Tester. *Standard: ja.*
2. **RU-F2 Lässt es sich noch zuklappen?** Die Kopfzeile des Fachs behält ihren Pfeil. Das Gerät merkt sich das Zuklappen, und das Fach startet offen. Ein zugeklapptes Fach zeigt weiter die Vorschau. *Standard: ja, offen als Standard, Zuklappen pro Gerät gemerkt.*
3. **RU-F3 Zeilen im Fach.** RU2s kompakte blasse Zeilen mit Rückgängig-Pfeil, oder RU4s volle Zeilen mit gefülltem Haken und durchgestrichenem Namen im selben Fach. *Standard: RU2s Zeilen wie gebaut. RU4s Zeilen lassen sich mit einer Zeile tauschen, wenn Peter sie lieber mag.*
4. **RU-F4 Ist die Pille der Vorschau ein Rückgängig-Knopf?** Sie holt den neuesten Artikel mit einem Tipp zurück, wie ein Rückgängig. Anders als eine Snackbar läuft sie nie ab und gehört zum Abschnitt: Sie ist die Kopfzeile des Fachs, angeheftet, solange das Fach nicht zu sehen ist. *Standard: behalten. Ein Tipp auf den Rest der Vorschau scrollt zum Fach.*
5. **RU-F5 Wessen Haken zeigt die Vorschau?** „Zuletzt verwendet“ listet die Einkäufe des ganzen Haushalts, also landeten Leas Haken in Peters Vorschau, während sie einkauft. *Standard: Die Pille zeigt nur den neuesten auf diesem Gerät abgehakten Artikel. Anzahl und Fach zeigen alle, wie heute.*
6. **RU-F6 Überschrift.** „Abgehakt“ / „Ticked off“ ersetzt „Zuletzt verwendet“ / „Recently used“ auf der Liste. Die Vorschläge im Hinzufügen-Blatt behalten „Zuletzt verwendet“. *Standard: nur auf der Liste umbenennen, Feature-Map und FEATURES-FOR-WRITERS im Bau-PR anpassen.*
7. **RU-F7 Vor oder nach der Summe?** Über der Einkaufssumme käme das Fach bei einer kurzen Liste um die Höhe der Summe näher (etwa 200 px in der kurzen Liste des Nachbaus, am Screenshot abgelesen), aber die Summe schlösse dann nicht mehr die offenen Artikel ab. *Standard: nach der Summe, wie heute.*
8. **RU-F8 Wie viele.** Die heutige Grenze von 20 bleibt, neueste zuerst, eine Zeile pro Artikel. *Standard: 20, alle im offenen Fach.*
9. **RU-F9 Nach dem Zurückholen.** Der Artikel kehrt mit einer kurzen Markierung an seinen Platz zurück, und die Liste scrollt nicht. Liegt sein Platz über dem Bildschirm, sagt der Screenreader „Milch: Wieder auf die Liste“. *Standard: kein Scrollen, dazu die Ansage.*
10. **RU-F10 Einkaufsmodus und Hinzufügen-Blatt.** Während eines Einkaufs sitzt die Vorschau über der Einkaufsleiste. Bei offenem Hinzufügen-Blatt ist sie weg. *Standard: wie beschrieben. Der Bau misst, wie viele Zeilen die Vorschau mit der Einkaufsleiste kostet.*
11. **RU-F11 Weniger Bewegung.** Kein Fliegen, kein Zuklappen. Die Zeile verschwindet, und der Artikel erscheint sofort mit Markierung in Vorschau oder Fach. *Standard: ja (im Prototyp gebaut).*
12. **RU-F12 Preise im Fach.** Kein Preis-Chip an zuletzt verwendeten Zeilen. Ein Preis kommt wieder, wenn der Artikel auf der Liste ist. *Standard: keine Preise im Fach.*

## So prüfst du

`node docs/design/list/verify.mjs` endet mit `all checks passed (N)`. `node docs/design/list/tools/mutate.mjs` führt die Mutationen aus `MUTATIONS.md` aus, und jede lässt benannte Prüfungen scheitern.
