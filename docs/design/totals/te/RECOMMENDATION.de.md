# Summen mit fehlenden Preisen: TE1, nur was einen Preis hat

**Die Wahl: TE1 „Nur, was einen Preis hat“.** Sie behält den ST3-Block, den Peter gewählt hat, und nimmt weg, was nichts sagt. Hat nichts einen Preis, ist der Block weg. Haben einige Artikel einen Preis, bekommen nur die Läden mit Preis eine Zeile, und eine Zählung an der Summe sagt, was fehlt („4 ohne Preis“). Hat alles einen Preis, ist es der heutige Block ohne „7 mit Preis“. Die ST3-Regeln bleiben: „mind.“ an jedem Betrag mit einem Artikel ohne Preis dahinter, „≈“ an jeder Summe mit einem geplanten Gewicht, „Ohne Laden“ als eigene Zeile, gekauft/offen nur während eines Einkaufs.

**Warum TE1.**

- **Sie löst das Problem dort, wo es auftritt.** Peters Bild (fünf Läden, nichts mit Preis) verliert auf dem iPhone 390 × 844 353 px, 7 Listenzeilen. Mit einigen Preisen spart sie 3 Zeilen. Jede Zeile hat schon ihren Chip „+ Preis“; die Zeilen „1 ohne Preis“ je Laden wiederholten die Liste.
- **Nichts, was Peter gewählt hat, fällt weg.** Kassenzettel, Teilsummen, „mind.“, „≈“ und „Ohne Laden“ bleiben, wie Job 237 sie gebaut hat. Nur leere Zeilen und eine Zählung gehen. Hat alles einen Preis, bleibt der Block gleich (0 Zeilen gespart, 4 px weniger).
- **Keine neuen Wörter.** Jeder Text steht schon in der App („Einkaufssumme“, „Gesamt“, „4 ohne Preis“, „mind.“, „alles gekauft“).
- **Der kleinste Bau.** Ein Filter beim Aufruf von `summaryOf` und zwei Bedingungen in `SummaryBlock`. Kein neues Bedienelement, kein neuer Zustand.

**Der Preis dafür.** Hat alles einen Preis, bleibt es ein Block mit fünf Zeilen (353 px, wie heute). Ist auch das zu lang, ist TE2 der nächste Schritt.

**Zweite Wahl: TE2 „Eine Zeile, öffnet sich“.** In jedem Zustand mit Preis eine Summenzeile (70 bis 75 px, 5 Zeilen gespart), ohne Preis nichts. Die Laden-Zeilen sind einen Tipp entfernt und klappen wieder zu. Mit allen Preisen ist sie kürzer als TE1. Aber Peter wollte die Teilsummen je Laden sehen (Runde ST), und TE2 legt sie hinter einen Tipp. ST4 (`expandable-total`) war in Runde ST derselbe Tausch und wurde nicht gewählt.

**Die anderen.**

- **TE3 „Summen an den Laden-Trennern“** ist am Ende so kurz wie TE2, und die Summe eines Ladens steht dort, wo man in ihm einkauft. Aber die Trenner zeigen nach ST-Q5 nur die Anzahl, und ST1 (die Teilsumme am Trenner) hat Runde ST verloren. Bei 310 % brechen die Trenner um, und sie spart weniger Zeilen als TE2 (2 bis 7).
- **TE4 „Summe und der nächste Preis“** macht als einzige etwas aus einer Liste ohne Preise: „7 ohne Preis ›“ springt zum nächsten Artikel ohne Preis und öffnet seine Eingabe. Ohne jeden Preis kostet sie aber 70 px, und sie versteckt die Laden-Zeilen, bis alles einen Preis hat; mit einigen Preisen fehlen also die Teilsummen. Ihr Link könnte an die Summenzeile von TE1 (TE-Q4).
- **TE5 „Summe oben in der Leiste“** fügt der Liste nichts hinzu und hält den Betrag im Blick. Sie braucht aber ein neues Zeichen für die Untergrenze („≈ 6,38 €+“, TE-Q8), und auf Deutsch und auf dem Android mit 360 px drückt der Betrag den Umschalter, bis der Listenname abgeschnitten ist („Einkaufsliste …“). Die Teilsummen stehen in einem Blatt. Die Summe wandert weg von dort, wo Job 229 sie hingesetzt hat.

## Gemessen: was der Block der Liste hinzufügt, iPhone 390 × 844

Pixel, die die Option gegenüber gar keiner Summe hinzufügt (Block, höhere Trenner oder Leiste). In Klammern die gegenüber heute gesparten Listenzeilen: 48 px bei 100 %, bei 310 % eine Zeile von 151 px. 310 % ist die größte Stufe des iPhones. Android 360 × 640 bei 100 % und 200 % steht in der Tabelle der Seite. Das Telefon „Heute“ trifft den Release-Web-Build auf 3 px bei 100 % (353/357 gegen 354/359 px) und auf 12 % bei 310 % (`te/real/heights.json`). Das sind bei 310 % bis zu 104 px; die gesparten Zeilen dort gelten ±1 Zeile. Gemessen auf Englisch.

| Option | Text | (a) Keine Preise | (b) Einige | (c) Alle | (d) Einkauf |
| --- | --- | --- | --- | --- | --- |
| Heute | 100 % | 353 | 357 | 357 | 357 |
| Heute | 310 % | 954 | 1423 | 993 | 1543 |
| **TE1 Nur, was einen Preis hat** | 100 % | 0 (+7) | 213 (+3) | 353 (0) | 213 (+3) |
| **TE1 Nur, was einen Preis hat** | 310 % | 0 (+6) | 872 (+3) | 936 (0) | 975 (+3) |
| TE2 Eine Zeile, öffnet sich | 100 % | 0 (+7) | 75 (+5) | 70 (+5) | 75 (+5) |
| TE2 Eine Zeile, öffnet sich | 310 % | 0 (+6) | 504 (+6) | 340 (+4) | 456 (+7) |
| TE3 Summen an den Laden-Trennern | 100 % | 0 (+7) | 75 (+5) | 70 (+5) | 75 (+5) |
| TE3 Summen an den Laden-Trennern | 310 % | 0 (+6) | 685 (+4) | 586 (+2) | 456 (+7) |
| TE4 Summe und der nächste Preis | 100 % | 70 (+5) | 110 (+5) | 357 (0) | 115 (+5) |
| TE4 Summe und der nächste Preis | 310 % | 155 (+5) | 509 (+6) | 993 (0) | 461 (+7) |
| TE5 Summe oben in der Leiste | 100 % | 0 (+7) | 0 (+7) | 0 (+7) | 0 (+7) |
| TE5 Summe oben in der Leiste | 310 % | 0 (+6) | 0 (+9) | 0 (+6) | 0 (+10) |

## Offene Fragen

1. **TE-Q1 Das Flag.** `list-declutter` und `prices-and-trip-total` sind voll ausgerollt; den Block direkt zu ändern, ändert ihn für alle. Vorgabe: ein neues PostHog-Flag `total-priced-only` auf beiden, zuerst an für Peter und die Tester.
2. **TE-Q2 Eine Liste ganz ohne Preis.** Vorgabe: nichts, auch keine Zeile (TE1). Andere Wege: eine Zeile „Einkaufssumme · 7 ohne Preis ›“ mit dem Link aus TE4 (70 px), oder nur die Linie mit „Einkaufssumme“.
3. **TE-Q3 Wie die fehlenden Preise heißen.** Vorgabe: die zweite Zeile der Summe sagt „4 ohne Preis“ / "4 without price" (der vorhandene Text), die Laden-Zeilen sagen nichts; ihr „mind.“ zeigt, dass einem Laden etwas fehlt. Andere Wege: gar keine Zählung (das „mind.“ sagt es), oder „+ 4 ohne Preis“ hinter dem Betrag.
4. **TE-Q4 Der Link aus TE4 in TE1.** Soll „4 ohne Preis“ an der Summe zum nächsten Artikel ohne Preis und seiner Eingabe springen? Vorgabe: nein; jede Zeile hat schon ihren Chip „+ Preis“. Es wäre eine neue Handlung ohne neuen Text.
5. **TE-Q5 Die Zählung „mit Preis“.** TE1 lässt „3 mit Preis“ / "3 with price" an der Summe in jedem Zustand weg; der Betrag sagt es. Vorgabe: weglassen.
6. **TE-Q6 Nur ein Laden mit Preis.** Haben nur Artikel eines Ladens einen Preis, zeigt TE1 eine Zeile „Einkaufssumme“ und keine Laden-Zeile, wie ST3 bei einem Laden (eine Zeile würde die Summe wiederholen). Vorgabe: so lassen; gezählt werden Läden mit Preis, nicht Läden auf der Liste.
7. **TE-Q7 Ein Laden ohne Preise beim Einkauf gekauft.** Ein ganz gekaufter Laden ohne Preis bekommt keine Zeile; seine Artikel zählen bei „ohne Preis“. Vorgabe: wie gezeigt. Anderer Weg: eine Zeile „alles gekauft“ ohne Betrag behalten.
8. **TE-Q8 Das Zeichen für die Untergrenze in TE5.** Falls TE5 gewählt wird: in der Pille ist kein Platz für „mind.“, der Prototyp schreibt „6,38 €+“, ein neues Zeichen. Vorgabe: mit TE1 nicht nötig.
9. **TE-Q9 Beträge bei größter Schrift.** Bei 310 % bricht die echte App einen Betrag mitten in der Zahl um („€6.3 / 8“, gesehen im Release-Web-Build), heute und in jeder Option. Vorgabe: im Bau beheben; ein Betrag, der nicht passt, steht in einer eigenen Zeile unter dem Namen. Das ist eine Zeile mehr, aber die Zahl bleibt ganz.

10. **TE-Q10 Preise in einer anderen Währung.** Die App lässt einen Artikel, der heute in einer anderen Währung bepreist wurde, aus den Summen und macht sie zur Untergrenze (`Sum.foreign`); der Prototyp bildet das nicht nach. Ein Laden, dessen einzige Preise fremd sind, hat keinen Betrag, aber eine Untergrenze. Vorgabe: TE1 behandelt ihn wie einen Laden ohne Preis (keine Zeile), und die Zählung an der Summe nennt ihn mit den anderen („4 ohne Preis“).

## Was hier nicht entschieden wird

Das ist ein Prototyp. In der App hat sich nichts geändert. Der Bau folgt Peters Wahl, hinter dem Flag aus TE-Q1.
