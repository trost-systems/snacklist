# Empfehlung: Runde IO

**Pick: IO4 Lernt, plus „Neben“. Runner-up: IO2 Lernt euren Weg.**

## Gemessen

Zeilen sind Artikelzeilen, die am Anfang der Liste ganz zwischen oberer Leiste und Eingabefeld sichtbar sind. Das Fenster ist das des Release-Web-Builds: 390 × 844 oder 360 × 640 App, ohne Statusleiste oder Home-Balken darin. Ein echtes iPhone gibt der App etwa 80 px weniger (geschätzt aus der 47 px hohen Statusleiste und dem 34 px hohen Home-Balken von iOS, nicht auf einem Gerät gemessen), also zeigt dort jede Option etwa eine Zeile weniger, alle gleich. `verify.mjs` misst die Zeilen auf dieser Seite. Es prüft, dass der Nachbau von „Heute“ in allen zehn Aufnahmen die Zeilenpositionen, das Eingabefeld, die obere Leiste und die Zahl ganzer Zeilen des Release-Builds hat (`io/real`). Tippen zählt die Korrektur der Eier, die bei der Milch stehen, in diesem EDEKA aber neben dem Mehl liegen. „Ganze IKEA-Liste“ heißt: die IKEA-Liste von der heutigen Reihenfolge in die Laufweg-Reihenfolge der Familie bringen.

| Option | iPhone 100 % | iPhone 310 % | Android 100 % | Eier korrigieren (Tippen) | Ganze IKEA-Liste (Tippen) |
| --- | --- | --- | --- | --- | --- |
| Heute | 9 | 2 (de 3) | 6 | 4 | – |
| IO1 Leise Kategorien | 12 | 3 | 8 | 4 | – |
| IO2 Lernt euren Weg | 12 | 3 | 8 | 0 | 0, ein Einkauf |
| IO3 Ziehen zum Ordnen | 12 | 3 | 8 | 3 | 5 (de 6) |
| **IO4 Lernt, plus „Neben“** | 12 | 3 | 8 | 4 | 0, ein Einkauf |
| IO5 Kategorien an oder aus | 11 | 3 | 7 | 6 | 31 (de 27) |

- Ohne Kategorie-Überschriften zeigt der erste Bildschirm des iPhones 3 Zeilen mehr (9 → 12, in beiden Sprachen) und der kleine Android 2 mehr (6 → 8). Bei größter Schrift ist es auf Englisch eine Zeile, auf Deutsch keine, weil dort ein Artikel ein Drittel des Bildschirms füllt. Die Abstände von IO5 kosten eine Zeile, und mit eingeschaltetem Schalter ist IO5 genau „Heute“.
- In „Heute“ und IO1 bringt eine Kategorie-Auswahl die Eier nur ans Ende von Vorrat (hinter Passierte Tomaten, nicht hinter Mehl). Außerdem landen die Eier damit in jedem Laden in Vorrat, weil die Korrektur für den ganzen Haushalt gilt.
- IO2 und IO4 haben IKEA nach einem Einkauf in Ordnung, ohne Tippen. IO3 braucht einen Zug pro falsch stehendem Artikel und die zwei Tipps für den Sortiermodus. Mit Nach oben / Nach unten braucht IO5 für dieselbe Liste 27 bis 31 Tipps (gezählt Artikel für Artikel). „Heute“ und IO1 schaffen es nicht Artikel für Artikel: Haushalt und Sonstiges sind ganze Blöcke, in einer Reihenfolge für jeden Laden.
- Ein neuer Artikel findet seinen Platz in jeder Option ohne Tippen. Ketchup landet beim Vorrat: hinter Passierte Tomaten in der heutigen Reihenfolge, hinter Mehl in der gelernten.

## Warum IO4

- **Peters Wunsch, Punkt für Punkt.** Die Kategorien sind vom Bildschirm weg. Die Reihenfolge kommt von dort, wo die Familie wirklich langgeht, und niemand muss sie pflegen. IKEA, Märkte und jeder Laden ohne recherchierten Laufweg bekommen ihre Reihenfolge nach einem Einkauf.
- **Wenn das Lernen danebenliegt, wird es sofort richtig.** „Neben Mehl“ braucht 4 Tipps, egal wie weit. Das Menü öffnet beim jetzigen Nachbarn, also muss man für ein weiter entferntes Ziel erst im Menü scrollen. Bei den 18 EDEKA-Artikeln steht Mehl am unteren Rand des Menüs. Ab 40 Artikeln in einem Laden braucht das Menü oben ein Suchfeld (IO-Q12). Das Ziehen in IO3 und Nach oben / Nach unten in IO5 haben dieselben Wegkosten, dort in Tipps gezählt. Es geht ohne Ziehen (Job 78 hat das Ziehen von der Liste genommen, und Flutter Web kennt keine eigenen Screenreader-Aktionen), mit Screenreader und im Web. Der Chip sagt mit Artikel-Wörtern, wohin der Artikel kommt, nicht mit Kategorie-Wörtern.
- **Die Daten gibt es schon.** Jedes Abhaken wird mit Uhrzeit gespeichert (`item_events`), Einkäufe sind markiert (der Einkaufsmodus ist für alle an), und `place_item` gibt es auf dem Server. Neu sind eine Tabelle (`item_order_memory`), ein Lerner am Ende eines Einkaufs und der Chip.
- **Agenten bekommen dasselbe Verb.** MCP `place_item(item, after: "Mehl")` macht dasselbe wie der Chip. `list_items` liefert den Laufweg.

## Warum IO2 die zweite Wahl ist

IO2 ist IO4 ohne den Chip: billiger, und nichts Neues auf dem Bildschirm. Es ist der richtige erste Schritt, falls IO4 für einen Bau zu viel ist. Es scheitert genau dort, wo IO4 den Chip ergänzt. Die Liste bleibt bis zum nächsten Einkauf falsch, und ein Haushalt, der „Nein, nur abgehakt“ antwortet, bringt ihm nie etwas bei.

## Nicht gewählt

- **IO1** ist die billigste Änderung (keine Überschriften). Es versteckt aber den einzigen Griff, den man an der Reihenfolge hat. Korrigiert wird weiter über eine unsichtbare Kategorie, das verschiebt den Artikel in jedem Laden, und IKEA bleibt in Supermarkt-Reihenfolge.
- **IO3** ist genau und vorhersehbar. Jemand muss aber jeden Laden und jeden neuen Artikel sortieren, und genau diese Pflege will Peter loswerden. Außerdem kommt das Ziehen zurück, wenn auch in einem eigenen Modus.
- **IO5** beantwortet „andere sehen es vielleicht anders“ gut. Sein Schalter ist unten IO-Q3 und lohnt sich zusätzlich zu IO4 für alle, die Kategorien mögen. Allein sortiert es nicht besser als heute, und Nach oben / Nach unten sind über größere Abstände langsam (6 Tipps für die Eier).

## Offene Fragen (jede mit Vorgabe)

1. **IO-Q1 Flag.** Ein neues PostHog-Flag, `learned-order`, das in `releases/flags.json` als `off` hinzukommt. Es schaltet in der App die versteckten Überschriften und den „Neben“-Chip. Ist es für ein Mitglied an, stellt die App dessen Haushalt auf die Reihenfolge `learned` (`households.order_mode`, APPROACHES.md). Diesen Modus liest der Server für den Lerner, die API und MCP. Er stellt sich nie von selbst zurück, und der Lead kann ihn zurücksetzen. Zuerst ist das Flag nur für Peter und Lea an. *Vorgabe: ja.*
2. **IO-Q2 Kategorien standardmäßig versteckt?** Mit dem Flag sind die Überschriften für alle versteckt, auch für bestehende Haushalte, und der Schalter holt sie zurück. *Vorgabe: für alle versteckt.* Die Alternative ist: nur für Haushalte, die nach der Änderung angelegt werden.
3. **IO-Q3 Pro Person oder pro Haushalt?** Der Schalter „Kategorien zeigen“ gilt pro Person und wird auf dem Gerät gespeichert, wie das Zuklappen. Er steht unter Liste → Anpassen, über den Läden. *Vorgabe: pro Person, auf dem Gerät, aus.* Die Alternative ist: pro Konto synchronisiert.
4. **IO-Q4 Welches Abhaken lehrt?** Nur Abhaken während eines Einkaufs („Ja, Einkauf starten“), getrennt nach den Läden der Artikel. Ein Abhaken mehr als 10 Minuten nach dem vorigen zählt nicht. *Vorgabe: ja.* Die Alternative ist: jedes Abhaken, also auch das zu Hause.
5. **IO-Q5 Von Hand gegen gelernt.** Ein „Neben“-Platz hält, bis drei Einkäufe hintereinander den Artikel woanders abhaken. *Vorgabe: drei Einkäufe.*
6. **IO-Q6 Mitglieder, die anders gehen.** Eine Reihenfolge pro Laden und Haushalt, ein Mittel aller Einkäufe, neuere zählen mehr. *Vorgabe: eine gemeinsame Reihenfolge.* Die Alternative ist eine Reihenfolge pro Mitglied, die aber die gemeinsame Liste aufteilt.
7. **IO-Q7 Der Chip bei sichtbaren Kategorien.** Mit eingeschaltetem Schalter zeigt das Bearbeiten-Blatt den Kategorie-Chip und „Neben“, ausgeschaltet nur „Neben“. *Vorgabe: ja.*
8. **IO-Q8 Ladentrenner.** Der Ladentrenner bleibt, auch wenn die Liste nur einen Laden hat. Er trägt die Zahl und das Zuklappen und zeigt, wo eine Reihenfolge beginnt. *Vorgabe: bleibt.*
9. **IO-Q9 API und MCP.** Jeder Artikel bekommt sofort `position`: den 1-basierten Rang im Abschnitt seines Ladens, in der aktuellen Reihenfolge des Haushalts. MCP `list_items` liefert die Artikel nach Laden, jeden Laden in der Reihenfolge des Haushalts (in einem `learned`-Haushalt der Laufweg). Es hat keinen Cursor, also bricht nichts. `GET /v1/items` behält seine v1-Reihenfolge und seine Cursor, und `order=walk` wählt die Laufweg-Reihenfolge nach Laden, die in v2 Standard wird. Neu sind MCP `place_item(item, before|after)` mit `POST /v1/items/{id}/place` und MCP `set_store_order(store, items[])` mit `PUT /v1/stores/{id}/order` (nur `learned`-Haushalte). Ein Ladenwechsel über `update_item`, den PATCH oder `move_item` setzt den Artikel an seinen Platz im neuen Laden. Ein reiner Kategoriewechsel lässt ihn stehen. A1 `update_item` und A9 `set_store_layout`, so wie in Job 344 und 345 entworfen, bleiben; A9 wird zur „Standard-Reihenfolge für neue Artikel“. *Vorgabe: wie in APPROACHES.md.*
10. **IO-Q10 Kategorien darunter.** Kategorien, der Klassifizierer und die besseren Sätze aus Job 346 bleiben als Vorgabe für Artikel und Läden ohne Einkäufe. *Vorgabe: ja.* Nichts wird gelöscht.
11. **IO-Q11 Erster Einkauf in einem neuen Laden.** Ein neuer Laden startet mit dem Mittel der anderen Läden des Haushalts statt mit der Grund-Reihenfolge. *Vorgabe: ja.*
12. **IO-Q12 Lange Ladenlisten.** Das „Neben“-Menü bekommt ein Suchfeld, sobald ein Laden mehr als 15 Artikel hat. *Vorgabe: ja.*

Neu sind die Wörter „Neben {name}“, „Ganz vorne“, „Kategorien zeigen“ und „Reihenfolge“. Sie sind auf den Telefonen markiert. Für den Bau brauchen sie ARB-Einträge und eine Prüfung des Wortlauts, die kein Legal braucht.
