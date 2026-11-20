# Runde AM: Empfehlung

**Empfehlung: AM2 Ergebnis-Zeilen. Zweite Wahl: AM1 Markierte Zeilen.**

Peters Klarstellung (t1077u) gilt für alle fünf Optionen. Ein Treffer steht nur im Sheet, als Vorschlag, der sich deutlich von einem unterscheidet, der einen neuen Artikel hinzufügt, und dasselbe gilt für das Abhaken. Die Zeile auf der Liste hinter dem Sheet wird nie ins Bild geholt oder markiert. Nach einem Ergebnis sagt das Sheet an der Stelle der Chips, was passiert ist, mit den Sätzen der App („Zusammengeführt: 2× Nudeln“, „Nudeln abgehakt“, „Nudeln steht schon auf der Liste“), bis zum nächsten Buchstaben. Die Liste hinter dem Sheet zeigt nur Artikel, die das Sheet hinzugefügt hat. `am/verify.mjs` prüft das in jedem Bild.

## Gemessen

`am/verify.mjs` hat diese Werte in Chromium gemessen. Tipps sind Klicks und Enter auf dem Live-Telefon, nachdem das Wort getippt ist. Das Skript spielt jeden Weg nach und vergleicht die Liste danach mit dem Reducer. Die Höhen reichen von der Oberkante des Sheets bis zur Tastatur, auf Englisch bei 100 %, iPhone / Android. AS1 beim Tippen mit einem normalen Vorschlag (Zimt) hat auf beiden Telefonen 135 px.

| Option | Enter, offener Treffer | Enter, abgehakter Treffer | Abhaken | Zusammenführen | Getrennt | Wieder auf die Liste | Sheet, 1 Treffer | Sheet, 3 Treffer |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AM1 Markierte Zeilen | führt zusammen (+1) | wieder auf die Liste | 1 | 1 | 1 | 1 | 191 / 191 px | 303 / 303 px |
| AM2 Ergebnis-Zeilen | lässt die Liste, sagt, dass er da ist | wieder auf die Liste | 1 | 1 | 1 | 1 | 247 / 247 px | 303 / 303 px |
| AM3 Entscheidungs-Tasten | führt zusammen (+1) | wieder auf die Liste | 1 | 1 | 1 | 1 | 187 / 187 px | 247 / 247 px |
| AM4 Erst hinzufügen, dann anbieten | fügt getrennt hinzu | fügt getrennt hinzu | – | 2 | 1 | 2 | 135 / 135 px | 135 / 135 px |
| AM5 Kacheln (Bring!) | hakt ab | wieder auf die Liste | 1 | 1 | 1 | 1 | 171 / 171 px | 271 / 271 px |

AM4 zeigt beim Tippen nichts, sein Sheet ist also das von AS1. Sein Treffer erscheint nach Enter, in einem Sheet von 187 / 237 px. AM2 braucht für einen offenen Treffer auf denselben Artikel zwei Zeilen (zusammenführen und abhaken). Bei Milch halten seine drei Zeilen also Milch und Hafermilch, und die abgehakte Buttermilch passt nicht hinein. Die anderen Optionen zeigen alle drei.

**Sichtbar.** Jeder Treffer, jede Taste, die entscheidet, und das Feld müssen über der Tastatur und auf dem Bildschirm liegen, ohne seitliches Wischen und ohne Scrollen im Sheet. Geprüft in beiden Sprachen und beiden Designs.

| Option | Ein Treffer, iPhone | Ein Treffer, Android | Drei Treffer, iPhone | Drei Treffer, Android | Neue UI-Wörter |
| --- | --- | --- | --- | --- | --- |
| AM1 | bis 200 % | bis 200 % | bis 200 % | 100 % | keine |
| AM2 | bis 200 % | bis 200 % | bis 200 % | 100 % | keine |
| AM3 | bis 200 % | 100 % | 100 % | nein: auf Deutsch braucht der dritte Name ein Wischen | Zusammenführen, Neu, Wieder auf die Liste (alle schon in der App) |
| AM4 | 100 % | 100 % | 100 % | 100 % | Zusammenführen, Wieder auf die Liste (schon in der App) |
| AM5 | bis 310 % | bis 200 % | bis 200 % | 100 % | keine |

Jede Option markiert die Szenarien gleich, bei jeder Größe, in beiden Sprachen und beiden Designs:
- genau (Nudeln), Plural (Apfel → Äpfel 1 kg) und der Fall mit Laden und Marke zeigen je einen Treffer, und Hafermilch zeigt „dm · Hafergold“;
- mehrere Treffer (Milch) zeigen drei Artikel, bei AM2 zwei;
- ein gestern abgehakter Treffer (Eier) erscheint als abgehakt;
- kein Treffer (Zimt) zeigt AS1, wie es ist.

AM4 ist die Ausnahme: Es markiert nichts, bis Enter den Artikel hinzugefügt hat. Jede Taste, die entscheidet, ist mindestens 44 px groß.

## Warum AM2

- **Es ist Peters Klarstellung, wörtlich genommen.** Jedes Ergebnis ist ein eigener Vorschlag, deutlich unterschieden von der +-Zeile, die hinzufügt:
  - Zusammenführen zeigt den Artikel, wie er danach wäre, 2× Nudeln, honiggelb, mit dem Symbol für Zusammenführen;
  - Abhaken zeigt den Namen durchgestrichen, minzgrün, mit dem Häkchen-Symbol;
  - ein abgehakter Treffer zeigt das Symbol von Wieder auf die Liste, grau.

  Man muss nichts lesen außer dem Artikel selbst, und es braucht keine neuen UI-Wörter.
- **Jedes Ergebnis ist ein Tipp, und jedes ist vor dem Tipp sichtbar.** Man sieht, wie die Liste danach aussieht (2× Nudeln), bevor man wählt. AM1 versteckt das Zusammenführen hinter einem Tipp auf die Zeile, und sein ✓ ist eine nackte runde Taste.
- **Enter ändert die Liste nie überraschend.** Meist tippt man etwas, das schon da ist, weil der andere es hinzugefügt hat oder weil man vergessen hat, dass man es selbst getan hat. Heute weist die App es ab mit „Nudeln steht schon auf der Liste“. Enter tut in AM2 dasselbe, im Sheet. AM1 und AM3 führen bei Enter zusammen, und das ergibt 2× Nudeln, obwohl man eine wollte. AM5 hakt den Artikel ab, also verlässt er die Liste: Das ist das Umschalten von Bring!, und es überrascht jeden, der tippt.
- **Ein abgehakter Treffer kommt mit einem Tipp oder Enter zurück,** mit Menge, Laden, Marke und Eigenschaften (10× Eier, Edeka, Freiland). Heute fügt die App eine neue Zeile hinzu, und Menge, Marke und Eigenschaften des abgehakten kommen nicht zurück.
- **Bei großer Schrift hält es so gut wie AM1.** Ein Treffer ist auf beiden Telefonen bis 200 % sichtbar. Bei 310 % auf dem iPhone schiebt ein Treffer mit Laden und Marke (zwei Zeilen) das Feld unter die Tastatur, in AM1 auch (AM-Q8). Nur die Kacheln von AM5 halten einen Treffer bei 310 % sichtbar.
- **Der Preis ist die Höhe.** Mit einem offenen Treffer braucht es drei Zeilen, 247 px, gegen 191 px bei AM1. Das ist immer noch weniger als das heutige Sheet nach dem Hinzufügen (312 px), und es bleibt nur beim Tippen.

## Warum nicht die anderen

- **AM1** (zweite Wahl): Jedes Ergebnis braucht einen Tipp, in zwei Zeilen statt drei. Aber Enter führt zusammen, ein Tipp auf die Zeile auch, und nichts auf der Zeile sagt das. Sein Abhaken ist eine nackte runde Taste.
- **AM3**: Drei gleiche Tasten unter einem Treffer sind die klarste einzelne Wahl. Aber es ist die einzige Option, die Wörter braucht (Zusammenführen, Neu, Wieder auf die Liste). Auf Deutsch auf dem Telefon mit 360 px braucht der Name des dritten Treffers ein Wischen. Jede Taste bleibt nur bis 200 % (iPhone) und 100 % (Android) sichtbar. Enter führt zusammen.
- **AM4**: die heutige Reihenfolge. Beim Tippen ist nichts markiert, also sieht man den Treffer erst nach dem Hinzufügen. Zusammenführen braucht 2 Tipps, und Abhaken hat keine Taste. Seine Angebotszeile bleibt nur bei 100 % sichtbar.
- **AM5**: Die Kacheln sehen Bring! am ähnlichsten, aber ein Tipp und Enter haken ab. Wer „Milch“ und Enter tippt, das natürlichste Hinzufügen, nimmt Milch von der Liste. Zusammenführen versteckt sich in einem + in der Ecke.

## Offene Fragen (jede mit der Vorgabe, die der Bau nimmt, wenn Peter nichts anderes sagt)

1. **AM-Q1. Flag.** *Vorgabe:* ein neues Flag `add-match-rows` in releases/flags.json, Rollout aus, an für Peter und die Tester. Es baut auf `add-sheet-compact` (Job 322) auf und braucht es. Ist das Flag aus, bleiben die heutige Abweisung und der Hinweis „steht schon auf der Liste“.
2. **AM-Q2. Was Enter bei einem genauen oder Plural-Treffer auf einen offenen Artikel tut.** *Vorgabe:* Nichts ändert sich, und das Sheet sagt „Nudeln steht schon auf der Liste“ (AM2, wie heute). Die Alternativen sind zusammenführen (+1, AM1 und AM3), getrennt hinzufügen (AM4) oder abhaken (AM5, das Umschalten von Bring!).
3. **AM-Q3. Abgehakte Artikel als Treffer.** *Vorgabe:* ja, die Artikel im abgehakten Bereich der gezeigten Liste, auf einer grauen Zeile mit dem Symbol von Wieder auf die Liste. Enter oder ein Tipp bringt den Artikel zurück, mit Menge, Laden, Marke und Eigenschaften. Ein offener Treffer auf denselben Artikel kommt immer zuerst. Soll die alte Menge zurückkommen (10× Eier) oder geleert werden? *Vorgabe:* Sie kommt zurück.
4. **AM-Q4. Was als derselbe Artikel zählt.** *Vorgabe:* der `canonical_key` des Servers (Plural, Umlaute, Synonyme, Tippfehler), egal welche Marke und Eigenschaften die beiden Artikel haben. „Hafermilch“ trifft die Hafermilch Hafergold von dm, und die +-Zeile fügt eine getrennte hinzu. Ein Teil-Treffer (Milch, während Hafermilch auf der Liste steht) bekommt nur eine Zeile zum Zusammenführen, und Enter wirkt nie auf ihn.
5. **AM-Q5. Mehrere Treffer.** *Vorgabe:*
   - höchstens drei Zeilen, wie im Prototyp (die drei aus AS-Q5);
   - ein offener Treffer auf den getippten Artikel braucht zwei Zeilen, zusammenführen und abhaken, andere Treffer je eine, in dieser Reihenfolge: derselbe Artikel, andere offene, abgehakte;
   - die +-Zeile kommt danach, als vierte Zeile.

   Bei Milch passt die abgehakte Buttermilch nicht hinein.
6. **AM-Q6. Mengen beim Zusammenführen.** *Vorgabe:* das heutige `merge_quantities`. Eine getippte Menge addiert sich („2 Nudeln“ auf Nudeln ergibt 3×), und keine Menge zählt als ein Stück. Ein Gewicht plus keine Menge bleibt, wie es ist (Äpfel 1 kg), und die Zeile zum Zusammenführen zeigt das vor dem Tipp. Soll diese Zeile dann stattdessen den Schritt des Zählers anbieten (2 kg)?
7. **AM-Q7. Was das Sheet nach einem Ergebnis sagt.** *Vorgabe:* eine Zeile an der Stelle der Chips bis zum nächsten Buchstaben, ohne Rückgängig (Peter hat Rückgängig in AS gestrichen). Sie nutzt die Sätze der App: „Zusammengeführt: 2× Nudeln“, „Nudeln abgehakt“, „Nudeln steht schon auf der Liste“. Wieder auf die Liste ist „Wieder auf die Liste: 10× Eier“, gebaut aus dem vorhandenen Label `readd`. Ein falsches Abhaken macht man mit einem Tipp auf die Zeile im abgehakten Bereich rückgängig, ein falsches Zusammenführen, indem man die Menge ändert.
8. **AM-Q8. Große Schrift.** In AM2 schieben die Zeilen das Feld in zwei Fällen unter die Tastatur: ein Treffer mit zweiter Zeile (Laden und Marke) bei 310 % auf dem iPhone, und drei Treffer bei 310 % auf dem iPhone oder 200 % bei Android. Der Prototyp löst das nicht. *Vorgabe für den Bau:* Die Zeilen scrollen über dem Feld, das fest bleibt, und die +-Zeile rückt über die Treffer, damit ein getrenntes Hinzufügen nie weggescrollt ist.
9. **AM-Q9. Der heutige Duplikat-Hinweis im Sheet** („… steht schon auf der Liste“ mit Zusammenführen nach dem Hinzufügen; AS-Q4). *Vorgabe:* Er fällt im Sheet weg, weil der Treffer vor dem Hinzufügen gezeigt wird. Die Snackbar für Hinzufügen von außerhalb des Sheets bleibt: Sprache, Siri, die API und MCP. Diese Wege laufen weiter über das Überspringen von Duplikaten auf dem Server.
10. **AM-Q10. Welche Liste.** *Vorgabe:* nur die gezeigte Liste, wie heute. Ein offener Artikel auf einer anderen Liste des Haushalts ist kein Treffer.
11. **AM-Q11. Analytics.** *Vorgabe:* Die Events `add_match_shown` und `add_match_outcome` (Eigenschaft `outcome`: keep, merge, tick, readd, separate) bekommen Regeln in `eventCatalog` und Zeilen in docs/ANALYTICS.md. Sie ersetzen `dedupe_hint_*` für das Sheet. Es werden keine Namen und kein Text gesendet.
