# Runde AS: Empfehlung

**Empfehlung: AS1 Chip-Zeile. Zweite Wahl: AS2 Feld oben.**

## Gemessen

Die Zahlen und Gründe stehen in `RECOMMENDATION.md`, die Tabelle auch auf der Seite der Runde. Kurz:
- Heute braucht das Bearbeiten nach dem Hinzufügen 312 px über der Tastatur, so viel wie auf Peters Screenshot.
- AS1 braucht 131 px, AS2 187 px, AS3 243 px, AS5 255 px. Bei AS4 sind es 247 px: das Sheet ist nur 79 px hoch, aber die Karte liegt auf der Liste. Auf dem Android-Telefon mit 360 px bricht „Getränke“ die Chip-Zeile um, dann braucht AS1 181 px und AS2 239 px.
- Tipps für Laden und Kategorie: heute 4, AS1 4, AS2 3, AS3 4, AS4 4, AS5 2. Auf dem Android-Telefon brauchen AS2 und AS5 ein Wischen mehr, bis „Kühlregal“ sichtbar ist.
- Bei AS1, AS2, AS4 und AS5 sind alle Felder sichtbar, auf dem iPhone bis 310 % Text und bei Android bis 200 %. AS3 verliert auf dem iPhone bei 310 % das Eingabefeld.
- Auf dem Android-Telefon mit 360 × 640 schieben AS2, AS3 und AS5 nach zwei Artikeln die frühere Zeile unter die Statusleiste.

## Warum AS1

- AS1 spart von allen fünf am meisten Platz: 181 px weniger als heute (auf Englisch; auf Deutsch auf dem kleinen Android-Telefon 131 px weniger).
- Alle Felder sind bei jeder Textgröße sichtbar, die die beiden Telefone anbieten.
- Die Chips, ihre Auswahl und das Feld bleiben, wo sie heute sind. Es fällt nur weg, was Peter markiert hat.
- Der kleinste Umbau. AS1 nutzt `FoldoutChips` und die Eigenschaften-Zeile weiter. Es entfallen `_AddedNote` mit der Schließen-Taste, der Abschnitt „Gerade hinzugefügt“ und der feste Platz für drei Zeilen.

Aus AS2 übernommen: Ein leeres Feld abzuschicken schließt das Sheet auch.

## Offene Fragen

Rückgängig fällt ganz weg (Peter, t1071u). Einen versehentlich hinzugefügten Artikel entfernt man so: Sheet schließen, Zeile antippen, Löschen. Gelernter Laden und gelernte Kategorie werden nicht zurückgenommen; das nächste Hinzufügen korrigiert sie im Sheet.

Die Fragen AS-Q1 bis AS-Q10 stehen mit ihren Vorgaben in `RECOMMENDATION.md`:
- AS-Q1: Marke
- AS-Q2: Schließen ohne X
- AS-Q3: Das kleine Android-Telefon
- AS-Q4: Der Duplikat-Hinweis
- AS-Q5: Das Tippen des nächsten Artikels
- AS-Q6: Ein Tipp auf eine Zeile hinter dem Sheet
- AS-Q7: Das Sheet erneut öffnen
- AS-Q8: Die Ladenauswahl aus Job 313
- AS-Q9: Der leere Eigenschaften-Chip zeigt nur sein Symbol
- AS-Q10: Das Flag `add-sheet-compact`
