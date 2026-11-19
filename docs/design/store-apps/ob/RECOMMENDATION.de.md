# Runde OB: Empfehlung

<!-- pick: OB1 -->
<!-- runner-up: OB4 -->

## Empfehlung

**Wahl: OB1, die Chips von heute aus der Region des Handys, beim Tippen verbunden, ohne die zwei Hinweiszeilen (OB-Q1).** Der Schritt behält seinen Platz, sein Aussehen und seine Tipps. Die Chips kommen jetzt aus dem Verzeichnis für die Region des Handys, und ein angetippter Chip ist ein verbundener Laden. Damit fallen die Nachfragen aus Job 313 auf der ersten Liste weg: 3 Tipps für neue Nutzer in Deutschland, 5 Tipps und zwei getippte Namen für neue Nutzer in Österreich. Die Chips von heute sind auf jedem Handy deutsch, wer in Österreich einkauft, muss also Hofer und SPAR tippen. „Eigenen Laden hinzufügen“ bleibt und bietet passende Ketten in jedem Land an, „Hofer“ auf einem deutschen Handy findet also trotzdem die österreichische Kette. Ein Name ohne Treffer bleibt ein eigener Laden, ohne Frage. Eine Kette mit zwei Apps bekommt ihre Standard-App. Die Seite des Ladens ändert sie später, so wie Job 313 sie baut. Wer beitritt, tut nichts, denn Verbindungen sind Haushaltsdaten. Ohne die Hinweiszeilen zeigt der Schritt 9 Wörter statt 35.

**Zweite Wahl: OB4, kein Laden-Schritt, dafür eine Karte auf der ersten Liste.** Der Einstieg hat 6 statt 7 Schritte, die Tipps wandern auf die Liste (4 für neue Nutzer in Deutschland). Nur diese Option macht den Einstieg selbst kürzer. Drei Kosten halten sie auf Platz zwei:
- Die Karte füllt die erste Liste. Darunter ist bei 100 % 1 Artikel zu sehen, bei 200 % keiner (OB1: 4 und 3).
- Bis jemand die Karte beantwortet, steht jeder Artikel unter „Kein Laden“.
- Wer mit einem Handy aus einem anderen Land beitritt, sieht die Chips dieses Landes für einen Haushalt in Deutschland (Szenario Beitreten).

Nicht empfohlen:
- **OB2, nur Vorschläge beim Tippen.** Es hat die wenigsten Wörter (6), und Weiter bleibt auch bei 310 % im Bild. Aber jeder Laden kostet einen getippten Namen: 3 für neue Nutzer in Deutschland, gegen 0 mit Chips. Der Einstieg soll aus Tipps bestehen, nicht aus Tippen.
- **OB3, die fünf größten plus „Anderer Laden“.** Die Zeilen lesen sich bei großer Schrift gut. Aber ein häufiger Laden außerhalb der fünf (dm in Deutschland) kostet einen Tipp und einen getippten Namen mehr, und welche fünf die größten sind, müsste das Verzeichnis je Land festlegen.
- **OB5, OB1 mit einer Vorschau der Taste „App öffnen“.** Bei einer Kette mit zwei Apps ist es am schnellsten (3 Tipps gegen 6), und es zeigt, was die Verbindung bringt. Aber es bringt 38 Wörter und einen Block je Laden in den Schritt, der am schnellsten sein soll, für eine Wahl, die wenige Haushalte brauchen. Die App-Karte aus Job 313 deckt die Wahl später ab.

## Messwerte

Tipps ab Ankunft im Laden-Schritt, bis jeder Laden mit App verbunden ist, mit den Fragen aus Job 313 auf der ersten Liste und, bei zwei Apps, der Wahl von jö Bonus Club. Die Zahl in Klammern ist der Unterschied zu heute nach Job 313. Das erste Handy jeder Bildfolge ist live, und `verify.mjs` tippt es auf demselben Weg durch und prüft die Zahl.

| Option | Neu in DE | Neu in AT | Nicht im Verzeichnis | Überspringen | Zwei Apps | Beitreten | Getippte Namen (DE / AT) | Laden-Bildschirme im Einstieg |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Heute (main, plus Karte aus Job 313) | 7 | 9 | 5 | 1 | 8 | 0 | 0 / 2 | 1 |
| **OB1** Chips der Region, verbunden | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 0 / 0 | 1 |
| OB2 Vorschläge beim Tippen im Schritt | 4 (−3) | 4 (−5) | 3 (−2) | 1 (0) | 6 (−2) | 0 (0) | 3 / 3 | 1 |
| OB3 Die fünf größten plus „Anderer Laden“ | 5 (−2) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 1 / 0 | 1 |
| OB4 Kein Schritt, eine Karte auf der Liste | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 0 / 0 | 0 |
| OB5 OB1 plus Vorschau der Taste | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 3 (−5) | 0 (0) | 0 / 0 | 1 |

Verglichen mit dem Einstieg auf main kostet der Laden-Schritt selbst mit OB1, OB2 und OB5 in Deutschland dieselben 4 Tipps und in Österreich 2 weniger. OB3 kostet in Deutschland 1 mehr. OB4 streicht den Schritt, seine 4 Tipps fallen auf der Liste an. Überspringen kostet überall 1 Tipp, wie heute. Die Szenarien:
- Neu in DE: Lidl, dm, REWE.
- Neu in AT: Hofer, SPAR, Lidl. Hofer ist ALDI SÜD in Österreich, mit eigener App.
- Nicht im Verzeichnis: Lidl und „Hofladen Sonnenwiese“.
- Überspringen: keine Läden.
- Zwei Apps: BILLA, wobei der Haushalt jö Bonus Club statt der Standard-App BILLA nutzt.
- Beitreten: Beitritt zu Familie Brandt, deren Läden schon verbunden sind, von einem Handy auf Österreich.

Der Bildschirm, auf dem neue Nutzer in Deutschland wählen, bei 390 × 844. Wörter sind die Wörter der Oberfläche, ohne Namen von Ketten und Apps. „Scrollen“ heißt, dass Weiter (OB4: Fertig) unter dem sichtbaren Bereich liegt. Die letzte Spalte zählt ganze Artikelzeilen zwischen dem Anfang der ersten Liste und dem Eingabefeld: heute beginnt diese Liste mit der ersten Frage aus Job 313, bei OB4 mit seiner Karte.

| Option | Wörter auf dem Bildschirm | Scrollen bis Weiter bei 100 / 200 / 310 % | Artikel im Bild auf der ersten Liste bei 100 / 200 % |
| --- | --- | --- | --- |
| Heute | 35 | nein / ja / ja | 3 / 2 |
| **OB1** | 35 | nein / ja / ja | 4 / 3 |
| OB1-lean (OB1 ohne die zwei Hinweiszeilen, OB-Q1) | 9 | nein / ja / ja | 4 / 3 |
| OB2 | 6 | nein / nein / nein | 4 / 3 |
| OB3 | 8 | nein / nein / ja | 4 / 3 |
| OB4 (die Karte) | 8 | nein / ja / ja | 1 / 0 |
| OB5 | 38 | nein / ja / ja | 4 / 3 |

Bei 200 % muss man bei OB1 noch scrollen, weil elf Chips auf viele Zeilen umbrechen. OB2 und OB3 passen, weil sie weniger Auswahl zeigen. Bei 100 % zeigt jede Option Weiter ohne Scrollen.

## Was sich in der App ändert (für den Bau-Job, nach Job 313)

- `popularStores` liest das zwischengespeicherte Verzeichnis für die Region des Handys statt einer festen deutschen Liste, „Baumarkt“ bleibt als Ladentyp. `OnboardingDraft.stores` hält Ketten-Schlüssel neben den Namen, und `setup` legt die Läden verbunden an, über den `add_store`-Weg aus Job 313.
- `CreateHouseholdScreen` nutzt dieselben Chips (ein zweiter Haushalt aus dem Wechsler).
- „Eigenen Laden hinzufügen“ bekommt die Vorschläge aus Job 313 (`chain_suggestions.dart`).
- Nichts Neues für Beitretende. Nichts geht an Händler. Kein Standort: das Land ist die Region des Handys.

## Offene Fragen

1. **OB-Q1 Die zwei Hinweiszeilen im Laden-Schritt streichen?** Standard: ja. Die Überschrift stellt die Frage, und Überspringen sagt, was es tut. Der Schritt geht von 35 auf 9 Wörter. Der Hinweis zur Reihenfolge steht auch auf der Seite Läden (Liste › Anpassen).
2. **OB-Q2 Was zeigt ein Handy, dessen Region das Verzeichnis nicht kennt (UK, USA)?** Standard: keine Chips, nur „Eigenen Laden hinzufügen“ mit Vorschlägen aus allen Ländern. Kein Raten aus der Sprache der App.
3. **OB-Q3 Beschriftung der Chips: der Name im Verzeichnis („Netto Marken-Discount“) oder ein kurzer („Netto“, wie heute)?** Standard: ein optionaler `short`-Name im Verzeichnis für Chips und den gespeicherten Namen des Ladens, sonst der Name.
4. **OB-Q4 „Baumarkt“ behalten?** Standard: ja, unverbunden, wie heute. Er ist ein Ladentyp, keine Kette.
5. **OB-Q5 Eine Kette mit zwei Apps im Einstieg?** Standard: ihre Standard-App (die mit Kundenkarte, Peters Wahl 4), ohne Frage. Die Seite des Ladens ändert sie (Job 313).
6. **OB-Q6 Ein getippter Name, der genau die Kette eines Chips ist („lidl“)?** Standard: er hakt diesen Chip an, wie es der Code heute schon tut, und ist damit ohne Frage verbunden. Andere Treffer erscheinen als Vorschläge.
7. **OB-Q7 Woher kommt die Region im Web?** Standard: aus der Sprach-Region des Browsers (`de-AT` ergibt Österreich). Ohne sie gilt OB-Q2. Nie aus dem Standort.
8. **OB-Q8 Dieselben Chips auf `CreateHouseholdScreen`?** Standard: ja.
9. **OB-Q9 Hinter welchem Flag?** Standard: `open-store-app`, wie Job 313. Mit Flag aus bleiben die Chips wie heute.
10. **OB-Q10 Haushalte, die den Einstieg von heute schon durchlaufen haben?** Standard: die Karte aus Job 313 fragt einmal nach ihnen, unverändert.
11. **OB-Q11 Reihenfolge der Chips?** Standard: die Reihenfolge des Verzeichnisses je Land (die meisten Filialen zuerst), wie die Liste heute geordnet ist.
