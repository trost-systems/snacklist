# Empfehlung: FB3, zweite Wahl FB2

**Wahl: FB3, „Hier melden, wo es passiert“.** Es fragt in dem Moment, in dem etwas schiefging, und schickt genau das: wohin man einen Eintrag verschoben hat oder welche Änderung der Server abgelehnt hat. Das gibt Peter in diesen Fällen 5 und 8 von 14 Debug-Punkten, gegenüber 3 bei FB1, bei mittlerer Exposition (6, und als einzige Variante mit dem Eintragsnamen standardmäßig, hinter einem Chip, den man entfernen kann), ohne neuen Auftragsverarbeiter und ohne Bilder, in etwa 5 Tagen auf unserem Stack. Schütteln wirkt nur nahe an einem Fehler, nie nur weil das Telefon offline ist.

**Zweite Wahl: FB2, „Schütteln, dann im Bildschirmfoto markieren“.** Es gibt Peter bei einer falschen Kategorie am meisten (7 Punkte) und ist die einzige Variante, die Layout-Fehler zeigt. Dafür kostet es etwa 7 Tage und bringt Bilder und Schritt-Protokolle vom Gerät in den Speicher und in die Datenschutzerklärung (Exposition 8).

<!-- table -->
| Variante | Tipps (falsche Kategorie · Änderung abgelehnt · Idee) | Debug-Punkte von 14 | Datenschutz-Exposition | Bau (Schätzung) | Fertiger Dienst | Rückmeldung an Nutzer |
| --- | --- | --- | --- | --- | --- | --- |
| Heute | 3 · 3 · 3 | 2 · 2 · 2 | niedrig (4) | live | keiner | per Mail, wenn angehakt |
| FB1 | 2 · 2 · 2 | 3 · 3 · 3 | mittel (7) | 3 Tage | keiner | per Mail, wenn angehakt |
| FB2 | 4 · 4 · 3 | 7 · 7 · 2 | mittel (8) | 7 Tage | keiner | per Mail, wenn angehakt |
| FB3 | 6 · 2 · 3 | 5 · 8 · 1 | mittel (6), nennt den Eintrag | 5 Tage | keiner | per Mail, wenn angehakt |
| FB4 | 4 · 4 · 4 | 2 · 2 · 2 | niedrig (4) | 9 Tage | keiner | in der App |
| FB5 | 3 · 3 · 3 | 2 · 7 · 2 | mittel (7) | 6 Tage | PostHog EU + Sentry EU | per Mail, wenn angehakt |
<!-- /table -->

Jede Variante ist in denselben drei Situationen gemessen. Bei FB3 sind 4 der 6 Tipps für eine falsche Kategorie die heutige Korrektur (lange drücken, Kategorie, Kühlregal, Fertig); Peter Bescheid sagen kostet 2 mehr. Die 7 Punkte von FB5 bei einer abgelehnten Änderung brauchen das Ja zu Nutzungsdaten (nur dann hat Sentry den Fehler); ohne sind es 2. Einstiege, die zu keiner Situation passen, sind Bilder auf der Seite der Variante, keine Zellen: der Absturz-Hinweis und die Umfrage bei FB5 (je 2 Tipps), das +1 auf eine gelistete Idee bei FB4 (3 Tipps) und die Preisfrage auf der Bezahlseite bei FB3.

## Warum FB3 die günstigeren Zeilen schlägt

- **FB1** ist günstiger (2 Tipps, 3 Tage), aber jede Notiz bleibt allgemein: Peter erfährt Bildschirm und Telefon, nicht was schiefging, und muss nachfragen. Schütteln ist standardmäßig an, also kostet versehentliches Schütteln im Laden.
- **Der Eintrags-Chip von FB3 widerspricht der Recherche („nichts geht mit, außer man schaltet es ein“).** Hier ist er trotzdem richtig: Man hat genau diesen Eintrag gerade verschoben und „Peter sagen“ angetippt, der Chip zeigt, was mitgeht, und ein Tipp entfernt ihn. Legal muss diese Lesart im §10-Redline bestätigen (FB-Q2), bevor etwas erscheint.
- **FB2** ist das stärkste Werkzeug fürs Debuggen und der nächste Schritt auf FB3, sobald Legal den Text zu Bildern und Schritt-Protokollen hat.
- **FB4** gibt Antworten in der App, ist aber am aufwendigsten und lohnt sich erst, wenn Außenstehende regelmäßig schreiben. Bis dahin antwortet Peter per Mail, wenn das Kontakt-Häkchen gesetzt ist.
- **FB5** bringt Sentry dazu, einen neuen Auftragsverarbeiter, der Kontodaten in den USA hält und für seine KI-Funktionen LLM-Unterauftragnehmer nennt. Die lassen sich für die ganze Organisation abschalten, der Verarbeiter bleibt aber neu. Die Absturz-Verknüpfung kann später mit eigener Legal-Prüfung kommen.

## Was der echte Bau von den anderen übernimmt

- Die Vorschau aus FB1: jedes mitgeschickte Feld mit Wert und Schalter (FB3 zeigt sie schon).
- Den Detektor und die Ruheregeln aus #281 für das kurze Schüttel-Fenster von FB3. #281 wird danach geschlossen oder in diesen Bau überführt (SH2).
- Die tägliche Sammelmail (Job 225) als Weg, auf dem Peter Notizen liest, nach Kontext gruppiert (FB-Q5).

## Offene Fragen

1. **FB-Q1 Schütteln im echten Bau.** Vorgabe: nur im Zusammenhang, wie in FB3 (iOS und Android; 2 Minuten nach „Änderung abgelehnt“ oder solange „Sync gestört“ zu sehen ist; nie nur wegen offline; Web nichts). Der Detektor aus #281 wandert in diesen Bau, und #281 wird geschlossen.
2. **FB-Q2 Der Eintrags-Chip.** Steht der Name standardmäßig in der Meldung, wenn man von einem verschobenen oder abgelehnten Eintrag aus meldet? Vorgabe: ja, als Chip, den man sieht und entfernen kann, weil man von genau diesem Eintrag aus gestartet ist. Legal bestätigt das im §10-Redline, bevor der Bau erscheint. Ein Tipp auf „Peter sagen“ gilt als Einwilligung, das zu senden, was das Blatt dann zeigt: den Eintragsnamen mit alter und neuer Kategorie, sonst nichts aus der Liste, und erst nach Senden. Sagt Legal nein, startet der Chip aus, und die Meldung schickt trotzdem die Kategorien („Vorrat & Konserven → Kühlregal“), ohne den Namen. FB3 behält dann seine 5 Punkte für eine falsche Kategorie, weil die Kategorien der Fall sind; ohne auch sie sind es 2. Die Sammelmail zählt eine Verschiebung über Haushalte nur aus Meldungen, deren Chip blieb, nennt also nie einen Eintrag aus einem Haushalt, der ihn entfernt hat.
3. **FB-Q3 Welche Kontextfelder aus #281 kommen.** Vorgabe: für FB3 nur die Felder von heute (Bildschirm, App-Version, Plattform und System, Sprache) und kein Gerätemodell. Design, Textgröße, Ausrichtung, online und Premium-Status kommen nur, wenn eine spätere Meldungsart sie braucht.
4. **FB-Q4 Das Shake-SDK später für Bildschirmfotos.** Vorgabe: nein. Erst wieder prüfen, wenn Shake schriftlich bestätigt, dass sein KI-Assistent für unsere Organisation aus bleibt, und wenn die einmonatige Aufbewahrung und das Limit im Gratis-Plan passen.
5. **FB-Q5 Die tägliche Sammelmail.** Vorgabe: die Sammelmail aus Job 225 nach dem GO von Legal einschalten, unter zwei Bedingungen. Erstens bleiben die Gemini- und Smart-Funktionen von Workspace für das Postfach hello@snacklist.app aus. Zweitens sagt die Datenschutzerklärung, dass die Sammelmail über Resend läuft, das Mails 30 Tage in den USA hält (DPF und SCC, wie bei Anmelde-Mails). Mit FB3 steht ein behaltener Eintrags-Chip in dieser Mail.
6. **FB-Q6 Antworten und Status (FB4).** Vorgabe: nicht im ersten Bau. Peter antwortet per Mail, wenn das Kontakt-Häkchen gesetzt ist. Wieder prüfen, wenn etwa 10 Notizen pro Woche von außen kommen.
7. **FB-Q7 Der Einstieg „Frage zum Preis?“ auf der Bezahlseite.** Vorgabe: ja, hinter demselben Flag wie die Bezahlseite, mit Store und Plan, ohne Zahlungsdaten.
8. **FB-Q8 Was eine Kontextmeldung ohne Text schickt und was eine Ablehnung trägt.** Vorgabe: Eine leere Nachricht ist nur bei Kontextmeldungen erlaubt (`context_kind` gesetzt). Die Datenbankprüfung (1 bis 2000 Zeichen) wird nur für diesen Fall gelockert, und eine allgemeine Notiz braucht weiter Text. Eine Ablehnungsmeldung trägt Op-Art und Server-Code (`add`, `42501`). Heute behält `ItemRejected` nur den Eintragsnamen, also ergänzt der Bau sie.
9. **FB-Q9 Job 259 (Feedback aus dem Menü ohne aktuellen Bildschirm).** Vorgabe: ja. Das Formular unter Mehr schickt keinen Bildschirm, kontextuelle Meldungen ihren eigenen. Kommt 259 zuerst auf main, wird „Heute“ in dieser Sandbox angepasst.
10. **FB-Q10 Wann die neue Snackbar „Peter sagen“ von FB3 kommt.** Heute zeigt Fertig im Bearbeiten-Blatt keine Snackbar. Vorgabe: nur wenn man eine Kategorie ändert, die die App selbst gewählt hat, einmal pro Eintrag, und für dieselbe Art Eintrag (`canonical_key`) im Haushalt 30 Tage nicht wieder. Eine Kategorie, die man selbst gesetzt hatte, fragt nie.
