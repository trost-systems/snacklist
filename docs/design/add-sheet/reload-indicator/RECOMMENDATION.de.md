# Ladeanzeige: Empfehlung (Job 273, Runde RI)

Frage: Wie soll das Hinzufügen-Blatt zeigen, dass die Vorschläge des Servers noch unterwegs sind, ohne dass Zeilen unter dem Finger springen? Heute zeigt es nichts (`AddSheetState.fresh` wird in der Oberfläche nicht genutzt, EVIDENCE Lücke 3). Das Entprellen bleibt bei 120 ms wie heute.

## Gemessen

<!-- table -->
| Variante | Anzeige während des ganzen Ladens (ms bis sichtbar) | Weg im ersten Frame mit den Zeilen der Antwort | Blatthöhe beim Laden / bei der Antwort | Zeile bewegt beim Laden | Zeile unter dem Finger wechselt bei der Antwort | Getippte Zeile zeigt den Text | Tipp beim Laden nimmt die gezeigte Zeile | Deutlichkeit, die geringste: Pixel, die die Anzeige um ≥ 3:1 ändert (Median), + schwächer geänderte | Text abgeschnitten, übergelaufen oder überlappt bei 200 % (Chrome wie main eingeschlossen) | Reduzierte Bewegung: steht still |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Heute** | nein | — | 0 px / +307 px (DE 200 %) | 0 px | ja (EN 100 %, EN 200 %) | nein | ja bei EN 100 %, EN 200 %; keine zweite Zeile bei DE 100 %, DE 200 % | keine Anzeige | 2 | — |
| **Basis 272, ohne Anzeige** | nein | — | 0 px / +34 px (DE 200 %) | 0 px | nein | ja | ja bei EN 100 %, EN 200 %; keine zweite Zeile bei DE 100 %, DE 200 % | keine Anzeige | 2 | — |
| **RI1 Alte Zeilen abblenden** | nein bei DE 100 %, DE 200 %, sonst ja (≤ 1 Frame) | ja | 0 px / +34 px (DE 200 %) | 0 px | nein | ja | ja bei EN 100 %, EN 200 %; keine zweite Zeile bei DE 100 %, DE 200 % | 0 px² + 0 px² (DE 100 %, DE 200 %) | 2 | ja |
| **RI2 Ladelinie** | ja (≤ 1 Frame) | ja | 0 px / +34 px (DE 200 %) | 0 px | nein | ja | ja bei EN 100 %, EN 200 %; keine zweite Zeile bei DE 100 %, DE 200 % | 312 px² (8,9:1) + 468 px² | 2 | ja |
| **RI3 Ladesymbol im Feld** | ja (≤ 1 Frame) | ja | 0 px / +34 px (DE 200 %) | 0 px | nein | ja | ja bei EN 100 %, EN 200 %; keine zweite Zeile bei DE 100 %, DE 200 % | 68 px² (5,8:1) + 76 px² (EN 200 %, DE 100 %) | 2 | ja |
<!-- /table -->

Gemessen von `verify.mjs` in Chromium, auf Englisch und Deutsch bei 100 % und 200 % Text: Die schnelle Tipperin tippt „Milk“ („Milch“) mit 70 ms je Taste bei 450 ms Antwortzeit, abgetastet in jedem Animations-Frame; der Tipp-Test tippt mit 220 ms je Taste bei 1800 ms Antwortzeit und tippt während des Ladens die zweite Zeile an. Jede Zelle außer der 200-%-Spalte ist das Schlechteste der vier Einstellungen; wo es sich zwischen ihnen unterscheidet, nennt die Zelle die Einstellungen, für die es gilt.

- Das deutsche „Milch“ beginnt ohne Zeile, die bleiben könnte: Das Gerät kennt nichts zu „M“, also zeigt beim Laden jedes Telefon nur die getippte Zeile. RI1 blendet dann nichts ab (0 px²), und der Tipp-Test hat keine zweite Zeile zum Antippen.
- Auf Deutsch bei 200 % bricht „Buttermilch · Schon mal gekauft · Rewe“ aus der Antwort auf zwei Zeilen um; deshalb wächst das Blatt bei der Antwort um 34 px, in der Kontrolle und in jeder Variante: Die vier freigehaltenen Plätze sind eine Zeile hoch. In den anderen drei Einstellungen bleibt es bei 0 px.
- „Basis 272, ohne Anzeige“ ist die Kontrolle: die mitlaufende getippte Zeile und vier freigehaltene Zeilenplätze aus Job 272, sonst nichts. RI1–RI3 sind dieses Telefon plus ihre Anzeige. Die Spalten zu Höhe, wandernden Zeilen, Wechsel und getippter Zeile kommen von der Basis: RI1–RI3 dort mit der Kontrollzeile vergleichen, nicht mit heute.
- „Weg im ersten Frame mit den Zeilen der Antwort“ prüft den Frame, in dem die Zeilen der Antwort gemalt werden.
- „Deutlichkeit“ vergleicht das ladende Telefon mit und ohne seine Anzeige, Pixel für Pixel, für jede Variante gleich, und nennt das Geringste der vier Einstellungen. Die erste Zahl zählt die Pixel, die die Anzeige um mindestens 3:1 ändert (die sichtbare Marke: das wandernde Stück von RI2, der Ring von RI3, die abgeblendeten Buchstaben von RI1), mit ihrem mittleren Kontrast. Die zweite zählt die schwächer geänderten Pixel (die blasse Spur von RI2, die weichen Ränder der Buchstaben von RI1). Die Linie von RI2 und der Ring von RI3 behalten bei 200 % ihre Größe (312 px² und 68 px² in allen vier Einstellungen); RI1 ändert auf Englisch 599 px² bei 100 % und 3005 px² bei 200 %, auf Deutsch nichts.
- „Text abgeschnitten, übergelaufen oder überlappt bei 200 %“ schließt das Chrome von main ein: Die 2 in jedem Telefon sind der Haushaltsname „Zuhause“, der mit … endet.

## Wahl: RI2 Ladelinie

In allen vier Einstellungen steht RI2 während des ganzen Ladens, innerhalb eines Frames nach dem Tastendruck, ist in dem Frame weg, der die Antwort malt, braucht beim Laden keine Höhe und steht bei reduzierter Bewegung still. Bei der Antwort fügt sie der Kontrolle nichts hinzu: 0 px, und die 34 px der Kontrolle auf Deutsch bei 200 %. Ihr wanderndes Stück ist in jeder Einstellung eine Marke von 312 px² bei 8,9:1, 4,6-mal der Ring von RI3, und sie lässt die Zeilen, wie sie sind; eine Zeile, die einen Tipp nimmt, wirkt also nicht deaktiviert. Sie zeigt sich auch, wenn keine Zeile veraltet ist, wie beim deutschen „Milch“.

## Zweite Wahl: RI1 Alte Zeilen abblenden

Auf Englisch ist RI1 die deutlichste Änderung (599 px² ändern sich um mindestens 3:1 bei 100 %, 3005 px² bei 200 %, Median 4,4:1) und die einzige Variante, die sagt, welche Zeilen sich noch ändern können, auch für Screenreader. Sie kann nur Zeilen abblenden, die es gibt: Auf Deutsch lädt „Milch“ mit nichts als der getippten Zeile, und RI1 zeigt das ganze Laden über nichts (RI-Q6). Dasselbe Abblenden lässt Zeilen deaktiviert aussehen, obwohl sie einen Tipp nehmen. Beides macht sie zur zweiten Wahl.

## Was die Tabelle sonst zeigt

- Der Ladekreis von RI3 ist die kleinste Marke, die immer erscheint (68 px² bei 5,8:1 in jeder Einstellung), und sitzt im Feld, wo die Augen beim Tippen sind; neben dem Leeren-✕ übersieht man ihn leicht.
- Den Sprung bei der Antwort behebt die Basis aus Job 272, nicht die Anzeige. Heute wächst das Blatt auf Englisch bei 100 % um 60 px und auf Deutsch bei 200 % um bis zu 307 px (ein deutsches Blatt beginnt mit einer Zeile), und auf Englisch wechselt die Zeile unter dem Finger. Die Kontrolle ohne Anzeige zeigt keinen Wechsel und 0 px, bis auf die 34 px einer umgebrochenen Zeile auf Deutsch bei 200 %. Dieser Teil gehört zu Job 272.

## Offene Fragen

1. RI-Q1: Wie viele Zeilenplätze hält das Blatt beim Tippen frei? Standard: 4 (die getippte Zeile und drei weitere); damit blieb die Höhe bei der Antwort für „Milk“ und „Milch“ bei 100 % und für „Milk“ bei 200 % bei 0 px. Die Plätze sind eine Zeile hoch: Auf Deutsch bei 200 % bricht eine Zeile der Antwort auf zwei Zeilen um, und das Blatt wächst trotzdem um 34 px; eine Antwort mit mehr Zeilen als Plätzen lässt es ebenfalls wachsen.
2. RI-Q2: Wo läuft die Linie: an der Unterkante des Blatts über dem Feld oder an der Oberkante unter den Chips? Standard: an der Unterkante, direkt über dem Feld, in das getippt wird.
3. RI-Q3: Zeigt sich die Linie auch beim ersten Buchstaben, wenn die Zeilen auf dem Gerät entstanden? Standard: Ja, immer wenn `fresh` falsch ist, wie gebaut.
4. RI-Q4: Eine schnelle Antwort (150 ms) lässt die Linie aufblitzen. Standard: Trotzdem sofort zeigen; eine Verzögerung würde langsame erste Antworten verstecken, und das Aufblitzen ist 2 px hoch.
5. RI-Q5: Bekommen Screenreader auch die Ansage „älterer Vorschlag, lädt noch“ von RI1 auf vorläufigen Zeilen? Standard: Ja, die Ansage ohne das Abblenden, dazu die Rolle progressbar der Linie.
6. RI-Q6: RI1 zeigt nichts, solange keine Zeile veraltet ist, etwa wenn das Gerät zum ersten Buchstaben nichts kennt (deutsches „M“). Was zeigt sich dann, wenn RI1 gewählt wird? Standard: die Linie von RI2, sobald keine Zeile veraltet ist; wie gebaut zeigt RI1 dann nichts.
