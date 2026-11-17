# Runde DE: den Namen später ändern
<!-- pick: DE1 -->
<!-- runner-up: DE2 -->

## Empfehlung

**Wahl: DE1 Konto › Dein Name.** Der Name gehört zur Person, nicht zu einem Haushalt, und im Konto sucht man „meine Angaben“. Es ist schon die erste Zeile in Mehr. Die Zeile zeigt den aktuellen Namen oder „Namen eintragen“ statt eines E-Mail-Teils. Ein Tipp öffnet ein Blatt mit dem Feld, vorausgefüllt, und Speichern bleibt aus, solange es leer oder unverändert ist. Das kostet 4 Tipps ab der Liste. Die Zeile ist bei 100 %, 200 % und 310 % ohne Scrollen zu sehen, sie verschiebt nichts in Mehr, und sie ist in jedem Haushalt gleich. Das Haushaltsmitglied, das gefragt hat, fände sie unter Mehr › Konto.

**Zweite Wahl: DE2 Die eigene Mitgliederzeile.** Gleich viele Tipps, und man ändert den Namen dort, wo man ihn neben den anderen sieht. Aber es ist ein Stift auf einer Zeile in einer Liste, auf die Haushaltsseite geht man, um zu sehen, wer dabei ist, nicht um sich selbst zu bearbeiten, und mit dem Flag list-declutter wandert die Seite ins Wechselblatt der Liste. Gut als zweiter Weg ins selbe Blatt (DE-Q1), nicht als einziger.

Nicht gewählt:
- **DE3 Ein Profilkopf in Mehr** ist am schnellsten (3 Tipps, Bearbeiten an Ort und Stelle), setzt aber eine Karte über jede Zeile von Mehr und schiebt alle nach unten, für eine seltene Handlung.
- **DE4 Wo deine Einladung ihn zeigt** korrigiert den Namen dann, wenn ihn jemand sehen wird, aber niemand findet ihn, der gerade nicht einlädt, und bei 200 % liegt der Einstieg unter dem sichtbaren Teil.
- **DE5 Ein Name je Haushalt** beantwortet eine Frage, die noch niemand gestellt hat („Mama“ hier, „Peter“ dort). Sie braucht eine Spalte in household_members, eine Entscheidung je neuem Haushalt und eine Regel, welchen Namen die Beitrittsseite zeigt.

## Wo die Änderung ankommt

Der Streifen „Was andere sehen“ auf dieser Seite ändert sich, sobald ein Telefon speichert. In der App liest jede Stelle den aktuellen Profilnamen, nichts hält eine Kopie: Peters Mitgliederliste, Beitrittsanfragen (`join_requests_of`), „2 neu von Lea“ und wer einen Eintrag übernommen hat (der Mitgliederkatalog des Haushalts), die Einkaufsübersicht und die Beitrittsseite von Leas Einladung (`preview_invite_public`, erstes Wort, nie der E-Mail-Teil). Die Vorausfüllung im Meldeformular (Job 281, noch nicht auf main) muss ebenfalls den aktuellen Namen lesen; das prüfen, sobald er landet. Profile werden nicht über Realtime veröffentlicht. Andere sehen den neuen Namen also, wenn diese Bildschirme die Mitglieder das nächste Mal laden, nicht live (DE-Q4).

## Gemessen

Das Prüfskript geht jede Option ab der Liste mit echten Klicks durch, tippt einen neuen Namen und speichert. Danach prüft es, dass Mitgliederliste, Liste und Beitrittsseite im Streifen ihn zeigen. „Einstieg sichtbar“ heißt, das Bearbeiten-Element steht ganz über der schwebenden Tab-Leiste, auf dem Bildschirm, wo es liegt, ohne Scrollen. Überlauf wurde auf jedem Bildschirm jedes Durchgangs und jedes Bildes geprüft, auf Englisch und Deutsch, bei 100 %, 200 % (das Größte bei Android) und 310 % (das Größte bei iOS), ausgehend von fünf Namen (ein E-Mail-Teil, Googles „Lea Brandt“, ein Apple-Relay-Teil, ein Name mit 49 Zeichen, „Lea 🌻“), gespeichert wurde „Lea Maria Brandt-Sommerfeld“.

<!-- table:start -->
| Option | Tipps ab der Liste bis gespeichert | Bildschirme und Blätter | Einstieg ohne Scrollen sichtbar (100 % / 200 % / 310 %) | Zeilen von Mehr nach unten (100 % / 200 % / 310 %) | Überlauf bei 100 % und 200 % | Überlauf bei 310 % |
| --- | --- | --- | --- | --- | --- | --- |
| DE1 | 4 | 4 | ja / ja / ja | 0 | keiner | keiner |
| DE2 | 4 | 4 | ja / ja / nein | 0 | keiner | keiner |
| DE3 | 3 | 2 | ja / ja / ja | 108 px / 217 px / 444 px | keiner | keiner |
| DE4 | 4 | 4 | ja / nein / nein | 0 | keiner | keiner |
| DE5 | 4 | 4 | ja / ja / nein | 0 | keiner | keiner |
<!-- table:end -->

Ein Zeilentitel mit einem Wort, das länger als die Zeile ist, wie die E-Mail bei 200 %, bricht im Wort, wie Flutters Text. Bei 310 % rutscht auch bei DE2 und DE5 der Einstieg unter den sichtbaren Teil (bei DE4 schon bei 200 %), und die Karte von DE3 schiebt die Zeilen von Mehr fast um einen ganzen Bildschirm nach unten.

## Offene Fragen

- **DE-Q1** Ein Einstieg oder zwei? Vorschlag: nur DE1. Der Stift von DE2 auf der eigenen Mitgliederzeile kann später dasselbe Blatt öffnen, falls Testende dort suchen.
- **DE-Q2** Darf der Name leer werden? Vorschlag: nein. Speichern bleibt bei leerem Feld aus (1 bis 80 Zeichen, wie in DN-Q2), damit niemand zu „Ohne Namen“ oder einem E-Mail-Teil zurückfällt.
- **DE-Q3** Ein Name oder einer je Haushalt? Vorschlag: ein Name für alle Haushalte (`profiles.display_name`, wie heute). DE5 wird nicht gebaut.
- **DE-Q4** Sehen die anderen im Haushalt die Änderung sofort? Vorschlag: beim nächsten Laden ihrer Mitgliederliste, Liste oder Beitrittsseite, ohne neuen Realtime-Kanal. Soll es live sein, `profiles` mit haushaltsbezogenem Filter über Realtime veröffentlichen. Das ist ein eigener Job mit eigenem RLS-Fall.
- **DE-Q5** Ersetzt der neue Name den alten an älteren Stellen (übernommene Einträge, Einkaufsübersichten, Beitrittsanfragen)? Vorschlag: ja. Alle lesen den aktuellen Namen, es muss nichts migriert werden.
- **DE-Q6** Die anderen benachrichtigen? Vorschlag: keine Nachricht, kein Verlauf und keine Grenze, wie oft man ihn ändert.
- **DE-Q7** Was zeigt die Zeile bei einem E-Mail-Teil als Namen? Vorschlag: „Namen eintragen“, und das Blatt öffnet leer mit dem Hinweis „z. B. Lea“, nicht vorausgefüllt mit „lea.brandt87“.
- **DE-Q8** Wie wird gespeichert? Vorschlag: über `updateUser(data: {display_name})`, nicht direkt in `profiles`, damit ein späterer Name von Google oder Apple ihn nicht überschreibt (DN-Q4).
