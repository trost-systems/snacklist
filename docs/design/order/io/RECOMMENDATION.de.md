# Empfehlung: Runde IO

**Pick: IO4 Lernt, plus „Neben“. Runner-up: IO2 Lernt euren Weg.**

## Gemessen

Zeilen sind Artikelzeilen, die am Anfang der Liste ganz sichtbar sind. `verify.mjs` misst sie auf dieser Seite. Der Nachbau von „Heute“ setzt seine Zeilen dorthin, wo der Release-Web-Build sie hat (`io/real`). Tippen zählt die Korrektur der Eier, die bei der Milch stehen, in diesem EDEKA aber neben dem Mehl liegen. „Ganze IKEA-Liste“ heißt: die IKEA-Liste von der heutigen Reihenfolge in die Laufweg-Reihenfolge der Familie bringen.

| Option | iPhone 100 % | iPhone 310 % | Android 100 % | Eier korrigieren (Tippen) | Ganze IKEA-Liste (Tippen) |
| --- | --- | --- | --- | --- | --- |
| Heute | 9 (de 8) | 2 | 5 (de 6) | 4 | – |
| IO1 Leise Kategorien | 11 | 2 (de 3) | 7 | 4 | – |
| IO2 Lernt euren Weg | 11 | 2 (de 3) | 7 | 0 | 0, ein Einkauf |
| IO3 Ziehen zum Ordnen | 11 | 2 (de 3) | 7 | 3 | 5 (de 6) |
| **IO4 Lernt, plus „Neben“** | 11 | 2 (de 3) | 7 | 4 | 0, ein Einkauf |
| IO5 Kategorien an oder aus | 10 | 2 (de 3) | 7 | 6 | 31 (de 27) |

- Ohne Kategorie-Überschriften zeigt der erste Bildschirm 2 bis 3 Zeilen mehr auf dem iPhone (Englisch 9 → 11, Deutsch 8 → 11) und 1 bis 2 mehr auf dem kleinen Android. Bei größter Schrift ist es höchstens eine Zeile, weil dort ein Artikel ein Drittel des Bildschirms füllt. IO5 mit eingeschaltetem Schalter ist genau „Heute“.
- In „Heute“ und IO1 bringt eine Kategorie-Auswahl die Eier nur ans Ende von Vorrat (hinter Passierte Tomaten, nicht hinter Mehl). Außerdem landen die Eier damit in jedem Laden in Vorrat, weil die Korrektur für den ganzen Haushalt gilt.
- IO2 und IO4 haben IKEA nach einem Einkauf in Ordnung, ohne Tippen. IO3 braucht einen Zug pro falsch stehendem Artikel und die zwei Tipps für den Sortiermodus. Mit Nach oben / Nach unten braucht IO5 für dieselbe Liste 27 bis 31 Tipps (gezählt Artikel für Artikel). „Heute“ und IO1 schaffen es nicht Artikel für Artikel: Haushalt und Sonstiges sind ganze Blöcke, in einer Reihenfolge für jeden Laden.
- Ein neuer Artikel findet seinen Platz in jeder Option ohne Tippen. Ketchup landet beim Vorrat: hinter Passierte Tomaten in der heutigen Reihenfolge, hinter Mehl in der gelernten.

## Warum IO4

- **Peters Wunsch, Punkt für Punkt.** Die Kategorien sind vom Bildschirm weg. Die Reihenfolge kommt von dort, wo die Familie wirklich langgeht, und niemand muss sie pflegen. IKEA, Märkte und jeder Laden ohne recherchierten Laufweg bekommen ihre Reihenfolge nach einem Einkauf.
- **Wenn das Lernen danebenliegt, wird es sofort richtig.** „Neben Mehl“ braucht 4 Tipps, egal wie weit. Es geht ohne Ziehen (Job 78 hat das Ziehen von der Liste genommen, und Flutter Web kennt keine eigenen Screenreader-Aktionen), mit Screenreader und im Web. Der Chip sagt mit Artikel-Wörtern, wohin der Artikel kommt, nicht mit Kategorie-Wörtern.
- **Die Daten gibt es schon.** Jedes Abhaken wird mit Uhrzeit gespeichert (`item_events`), Einkäufe sind markiert (der Einkaufsmodus ist für alle an), und `place_item` gibt es auf dem Server. Neu sind eine Tabelle (`item_order_memory`), ein Lerner am Ende eines Einkaufs und der Chip.
- **Agenten bekommen dasselbe Verb.** MCP `place_item(item, after: "Mehl")` macht dasselbe wie der Chip. `list_items` liefert den Laufweg.

## Warum IO2 die zweite Wahl ist

IO2 ist IO4 ohne den Chip: billiger, und nichts Neues auf dem Bildschirm. Es ist der richtige erste Schritt, falls IO4 für einen Bau zu viel ist. Es scheitert genau dort, wo IO4 den Chip ergänzt. Die Liste bleibt bis zum nächsten Einkauf falsch, und ein Haushalt, der „Nein, nur abgehakt“ antwortet, bringt ihm nie etwas bei.

## Nicht gewählt

- **IO1** ist die billigste Änderung (keine Überschriften). Es versteckt aber den einzigen Griff, den man an der Reihenfolge hat. Korrigiert wird weiter über eine unsichtbare Kategorie, das verschiebt den Artikel in jedem Laden, und IKEA bleibt in Supermarkt-Reihenfolge.
- **IO3** ist genau und vorhersehbar. Jemand muss aber jeden Laden und jeden neuen Artikel sortieren, und genau diese Pflege will Peter loswerden. Außerdem kommt das Ziehen zurück, wenn auch in einem eigenen Modus.
- **IO5** beantwortet „andere sehen es vielleicht anders“ gut. Sein Schalter ist unten IO-Q3 und lohnt sich zusätzlich zu IO4 für alle, die Kategorien mögen. Allein sortiert es nicht besser als heute, und Nach oben / Nach unten sind über größere Abstände langsam (6 Tipps für die Eier).

## Offene Fragen (jede mit Vorgabe)

1. **IO-Q1 Flag.** Ein PostHog-Flag, `learned-order` (in `releases/flags.json` als `off`), für die gelernte Reihenfolge, die versteckten Überschriften und den „Neben“-Chip. Zuerst ist es nur für Peter und Lea an. *Vorgabe: ja.*
2. **IO-Q2 Kategorien standardmäßig versteckt?** Mit dem Flag sind die Überschriften für alle versteckt, auch für bestehende Haushalte, und der Schalter holt sie zurück. *Vorgabe: für alle versteckt.* Die Alternative ist: nur für Haushalte, die nach der Änderung angelegt werden.
3. **IO-Q3 Pro Person oder pro Haushalt?** Der Schalter „Kategorien zeigen“ gilt pro Person und wird auf dem Gerät gespeichert, wie das Zuklappen. Er steht unter Liste → Anpassen, über den Läden. *Vorgabe: pro Person, auf dem Gerät, aus.* Die Alternative ist: pro Konto synchronisiert.
4. **IO-Q4 Welches Abhaken lehrt?** Nur Abhaken während eines Einkaufs („Ja, Einkauf starten“), getrennt nach den Läden der Artikel. Ein Abhaken mehr als 10 Minuten nach dem vorigen zählt nicht. *Vorgabe: ja.* Die Alternative ist: jedes Abhaken, also auch das zu Hause.
5. **IO-Q5 Von Hand gegen gelernt.** Ein „Neben“-Platz hält, bis drei Einkäufe hintereinander den Artikel woanders abhaken. *Vorgabe: drei Einkäufe.*
6. **IO-Q6 Mitglieder, die anders gehen.** Eine Reihenfolge pro Laden und Haushalt, ein Mittel aller Einkäufe, neuere zählen mehr. *Vorgabe: eine gemeinsame Reihenfolge.* Die Alternative ist eine Reihenfolge pro Mitglied, die aber die gemeinsame Liste aufteilt.
7. **IO-Q7 Der Chip bei sichtbaren Kategorien.** Mit eingeschaltetem Schalter zeigt das Bearbeiten-Blatt den Kategorie-Chip und „Neben“, ausgeschaltet nur „Neben“. *Vorgabe: ja.*
8. **IO-Q8 Ladentrenner.** Der Ladentrenner bleibt, auch wenn die Liste nur einen Laden hat. Er trägt die Zahl und das Zuklappen und zeigt, wo eine Reihenfolge beginnt. *Vorgabe: bleibt.*
9. **IO-Q9 API und MCP.** `GET /v1/items` und MCP `list_items` liefern die Artikel nach Laden in Laufweg-Reihenfolge, dazu `position`, den 1-basierten Rang im Abschnitt des Ladens. Neu sind MCP `place_item(item, before|after)` mit `POST /v1/items/{id}/place` und MCP `set_store_order(store, items[])` mit `PUT /v1/stores/{id}/order`. `move_item`, A1 `update_item` und A9 `set_store_layout` bleiben; A9 wird zur „Standard-Reihenfolge für neue Artikel“. *Vorgabe: wie in APPROACHES.md. Die Lese-Reihenfolge ändert sich mit dem vollen Rollout des Flags, `position` kommt sofort.*
10. **IO-Q10 Kategorien darunter.** Kategorien, der Klassifizierer und die besseren Sätze aus Job 346 bleiben als Vorgabe für Artikel und Läden ohne Einkäufe. *Vorgabe: ja.* Nichts wird gelöscht.
11. **IO-Q11 Erster Einkauf in einem neuen Laden.** Ein neuer Laden startet mit dem Mittel der anderen Läden des Haushalts statt mit der Grund-Reihenfolge. *Vorgabe: ja.*

Neu sind die Wörter „Neben {name}“, „Ganz vorne“, „Kategorien zeigen“ und „Reihenfolge“. Sie sind auf den Telefonen markiert. Für den Bau brauchen sie ARB-Einträge und eine Prüfung des Wortlauts, die kein Legal braucht.
