# Rückmeldung beim Hinzufügen: Empfehlung (Job 273, Runde AF)

Frage: Wie sieht man nach einem Tipp im Hinzufügen-Blatt, welcher Artikel in welchen Laden und welche Kategorie kam, und wie findet oder korrigiert man ihn, wenn das Blatt zu ist? Peter: „Das Erste, was man nach dem Schließen tun muss, ist den Artikel in der Liste zu suchen.“

## Gemessen

<!-- table -->
| Variante | Artikel + Laden + Kategorie offen erkennbar 100 % / 200 % (schlechtestes von 4 Szenarien) | Drei hinzu: erkennbar (offen) 100 % / 200 % | Finden nach dem Schließen | Laden ändern: offen / danach (Tipps) | Kategorie ändern: offen / danach (Tipps) | Korrektur gilt beim nächsten Mal | Mehr Höhe als heute (offen, 100 %) | Text abgeschnitten, übergelaufen oder überlappt bei 200 %: Variante / Chrome wie main | Ganze Zeilen nach dem Schließen 100 % / 200 % (Artikel dabei) | Vorschlagszeilen beim Tippen 100 % / 200 % (von) | Vorschlagszeilen direkt nach dem Hinzufügen 100 % / 200 % (wenigste, Szenario) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Heute** | nur Name (en first) / nur Name (en first) | 0/3 / 0/3 | scrollen, 137 px | — / 4 | — / 4 | ja | 309 px | 0 / 28 | 7 (nein) / 7 (nein) | 7 / 5 (7) | 3 (Ein bekannter Artikel) / 1 (Lange Namen) |
| **AF1 Beim Schließen zeigen** | ja / ja | 1/3 / 1/3 | 0 Tipps (schon sichtbar) | 2 / 4 | 2 / 4 | ja | +44 px | 0 / 28 | 6 (ja) / 6 (ja) | 7 / 5 (7) | 3 (Ein bekannter Artikel) / 1 (Lange Namen) |
| **AF2 Ablage „Hinzugefügt“** | ja / nur Name (en long) | 3/3 / 1/3 | 1 Tipp (Zeigen) für 5 s, dann scrollen, 137 px | 2 / 4 | 2 / 4 | ja | +20 px | 0 / 28 | 7 (nein, „Rewe 6 items“ halb darunter) / 6 (nein, „🥣Natural yoghurt“ halb darunter) | 7 / 3 (7) | 3 (Ein bekannter Artikel) / 2 (Drei hinzu, zwei Läden) |
| **AF3 Bestätigung an Ort und Stelle** | ja / ja | 1/3 / 1/3 | 0 Tipps (schon sichtbar) | 2 / 2 | 2 / 2 | ja | +37 px | 0 / 28 | 6 (ja) / 6 (ja) | 7 / 3 (7) | 3 (Ein bekannter Artikel) / 1 (Lange Namen) |
| **AF4 Hinweis mit Zeigen und Ändern** | ja / ja | 0/3 / 0/3 | 1 Tipp (Zeigen) für 6 s, dann scrollen, 137 px | 2 / 2 für 6 s, dann 4 | 2 / 2 für 6 s, dann 4 | ja | +13 px | 0 / 28 | 6 (nein, „🥣Natural yoghurt“ halb darunter) / 4 (nein, „🥛2× Whole milk“ halb darunter) | 7 / 3 (7) | 3 (Ein bekannter Artikel) / 1 (Lange Namen) |
| **AF5 Geteilte Ansicht** | ja / ja | 1/3 / 1/3 | 0 Tipps (schon sichtbar) | 2 / 2 | 2 / 2 | ja | +0 px | 0 / 28 | 6 (ja) / 6 (ja) | 4 / 3 (7) | 2 (Lange Namen) / 1 (Lange Namen) |
<!-- /table -->

Gemessen von `verify.mjs` in Chromium auf dem 390 × 844 Telefon, Szenario „Ein bekannter Artikel“, wenn die Spalte nichts anderes sagt.

- „Erkennbar“ heißt: Name, Laden und Kategorie des Artikels stehen zusammen in Text, den man sieht: in jedem Zuschnitt, nicht hinter einer Auslassung (…), nicht unter dem Schleier oder dem Blatt, innerhalb von etwa drei Vorschlagszeilen um den Namen. Jede Zelle ist das schlechteste von vier Szenarien (ein bekannter Artikel, lange Namen, zum ersten Mal, leere Kategorie) auf Englisch und Deutsch, mit dem Szenario, in dem es am schlechtesten war.
- Gezählt wird jeder Tipp, auch der, der eine Auswahl öffnet. „Halten“ auf einer Zeile zählt als einer. Eine Korrektur ohne eigenes Bedienelement geht über das Bearbeiten-Blatt: Halten, Chip, Auswahl, Fertig (4).
- „Finden nach dem Schließen“ ist 0, wenn der Artikel schon zu sehen ist, 1, wenn ein Knopf ihn zeigt, sonst wie weit man scrollen muss. Die Leiste von AF2 und der Hinweis von AF4 verschwinden nach 5 s und 6 s; die Zellen sagen, was danach bleibt.
- „Text abgeschnitten, übergelaufen oder überlappt bei 200 %“ zählt Text, der hinaussteht, überläuft, von einem Rahmen oder einer Auslassung abgeschnitten wird, sich überlappt oder unter dem Home-Balken liegt, über alle Szenarien und beide Bilder, Englisch und Deutsch. Die erste Zahl ist die eigene Rückmeldung der Variante (Notiz, Karte, Ablage, Hinweis, Chips). Die zweite ist das Chrome von main, in jedem Telefon dieselben 28: Haushaltsname, „Ohne Laden“ und der lange Name des Wochenmarkts in den Laden-Trennern enden mit …, wie in der App.
- „Halb darunter“ nennt Listentext, den ein schwebender Hinweis oder eine Leiste nach dem Schließen halb verdeckt.
- „Vorschlagszeilen“ zählen ganze Zeilen im Blick. Beim Tippen: für den Buchstaben mit den meisten Zeilen (7, `suggest_entries` bringt bis zu 8). Direkt nach dem Hinzufügen: die wenigsten über die sechs Szenarien, mit offener Notiz, Karte oder Hinweis.
- AF5 läuft bis 130 % Text als halbes Blatt. Ab 130 % ist es das volle Blatt von AF3 mit Schleier (AF-Q3); seine Zellen bei 200 % messen das.

## Wahl: AF3 Bestätigung an Ort und Stelle

AF3 beantwortet „was kam wohin“ dort, wo der Finger ist: Die getippte Zeile wird zum Artikel mit Laden- und Kategorie-Chip (erkennbar ja bei 100 % und 200 %), beides offen mit 2 Tipps änderbar und nach dem Schließen über den Chip „Lidl · Kühlregal“ der neuen Zeile ebenfalls mit 2 Tipps, wo die Liste den Artikel schon zeigt (Finden 0). Das volle Blatt von heute bleibt, also bleiben beim Tippen bei 100 % 7 Vorschlagszeilen im Blick (bei 200 % 3, weil die Karte stehen bleibt, während das Nächste getippt wird; heute 7 und 5); die Karte kostet 37 px Höhe, solange sie steht.

## Zweite Wahl: AF5 Geteilte Ansicht

AF5 ist beim Finden (0) und Ändern (2 / 2) gleich gut und zeigt die neue Zeile ohne zusätzliche Höhe dort, wo sie in ihrem Laden landet, aber das halbe Blatt lässt beim Tippen 4 statt 7 Vorschlagszeilen im Blick, und ab 130 % Text muss es ohnehin zu AF3 werden. AF5 statt AF3, wenn es wichtiger ist, die Zeile in der Liste landen zu sehen, als Platz für Vorschläge (AF-Q3).

## Was die anderen zeigten

- AF1 (Beim Schließen zeigen) findet den Artikel mit 0 Tipps und lässt ihn aufleuchten, aber jede Änderung nach dem Schließen braucht das Bearbeiten-Blatt (4 Tipps), und die größere Notiz kostet 44 px.
- AF2 (Ablage) hält als einzige Variante alle drei Hinzugefügten offen erkennbar (3/3 bei 100 %). Bei 200 % passt nur eines in die Ablage (1/3), und ein langer Name schiebt den Laden aus ihrem Blick („nur Name“). Nach dem Schließen findet ein Tipp (Zeigen) den Artikel 5 s lang, danach heißt es 137 px scrollen; ändern kostet 4 Tipps.
- AF4 (Hinweis) ändert 6 s lang mit 2 Tipps, danach mit 4. Mehrere werden zur Zahl (0/3 erkennbar), und nach dem Schließen verdeckt der Hinweis Listenzeilen halb („Naturjoghurt“ bei 100 %, „2× Vollmilch“ bei 200 %).
- Heute nennt den Laden nur, wenn die getippte Zeile ihn kannte, und nie die Kategorie („nur Name“ beim ersten Mal), und der Artikel liegt nach dem Schließen 137 px unter dem sichtbaren Teil der Liste.

## Offene Fragen

1. AF-Q1: Mehrere auf einmal: Die Karte von AF3 zeigt nur das neueste (1/3 offen erkennbar). Standard: Die Karte folgt jedem Hinzufügen, wie gebaut; die früheren behalten nach dem Schließen ihren Chip „Laden · Kategorie“ in der Liste.
2. AF-Q2: Wie lange tragen neue Zeilen ihren Chip „Lidl · Kühlregal“? Standard: Bis das Hinzufügen-Blatt wieder aufgeht, wie gebaut.
3. AF-Q3: Ist es 3 Vorschlagszeilen weniger beim Tippen wert (4 statt 7 bei 100 %), die Zeile bei offenem Blatt in der Liste landen zu sehen (AF5)? Standard: Nein, das volle Blatt von AF3; will Peter AF5, läuft es unter 130 % Text als halbes Blatt und ab 130 % als AF3, wie gebaut.
4. AF-Q4: Ein langer Name lässt bei 200 % eine ganze Vorschlagszeile unter der Karte (Tabelle). Standard: So lassen; die Karte lässt ab 130 % „Hinzugefügt zu“ weg, wie gebaut, und der Name wird nie abgeschnitten.
5. AF-Q5: Zeigt jede Korrektur „Gemerkt: Halloumi kommt nächstes Mal zu Rewe“? Standard: Ja, unter der verschobenen Zeile oder in der Karte, bis zum nächsten Tipp; der Server lernt jede Korrektur schon heute (`items_learn`).
6. AF-Q6: Soll die Karte sagen, warum ein Laden gewählt wurde („gemerkt“, „üblich für Kühlregal“)? Standard: Ja, klein und gedämpft nach den Chips, damit eine ST1-Vermutung als Vermutung zu lesen ist.
