# Einem Haushalt beitreten: Empfehlung (JH1–JH5)

**Empfehlung: JH5, erst der Name, Konto später.** Es sind die wenigsten Tipps bis zur gemeinsamen Liste in der App, in jedem der 12 Szenarien: 2 mit installierter App (Link antippen, Vornamen tippen, Beitreten), 6 ohne, 4 bis 7 mit getipptem Code. Zwei Varianten erreichen ohne App früher eine erste Liste, an einem kleineren Ort: JH2 im Browser und JH4 in einem App Clip (je 4 Tipps). JH5 gewinnt vor allem, weil die Anmeldung zu einer Karte „Zugang sichern“ nach dem Beitritt wandert. Es braucht keinen neuen Dienst (anonyme Supabase-Anmeldungen gehören zu unserem Stack), vom Gerät wird nur die Zwischenablage auf ihren eigenen Einsetzen-Tipp gelesen (wie heute „Einladung einfügen“), und das Warten sagt Ida, was Mia sieht. Der Preis ist eine neue Kontoart: etwa 8 Tage für Gastkonten, späteres Sichern, Missbrauchsgrenzen, Löschung und Export.

**Zweite Wahl: JH3, zwei Türen.** Falls Peter keine Gastkonten will: Eine gleichwertige Tür „Einem Haushalt beitreten“ ersetzt „Einladung einfügen“, die Landeseite nennt Mia und den Haushalt vor jedem Konto, und nichts wird vom Gerät gelesen oder an einen neuen Dienst geschickt, in etwa 4 Tagen. Es kostet Tipps: 5 mit App und 9 ohne (nach der Installation zurück in den Chat ist 1, das Nutzungsdaten-Blatt über der Liste beantworten ist 1), gegenüber 2 und 6 bei JH5; mit Nutzungsdaten als Karte wie bei den anderen wären es 4 und 8.

## Warum

- Eine eingeladene Person hat die App oft noch nicht (eine Annahme; heute misst das nichts). Heute erreicht sie eine Liste nur im Browser (6 Tipps) und die Liste in der App erst nach 14. Jede Variante zeigt Mia und den Haushalt vor dem Konto; die heutige App nicht.
- Tipps bis zur gemeinsamen Liste in der App, Link ohne App: JH5 6, JH1 7, JH4 7, JH3 9, JH2 10 (4 bis zur Liste im Browser), Heute 14. Mit App: JH5 2, JH1, JH2 und JH4 4, JH3 und Heute 5.
- Der Deep-Link-Dienst aus JH1 spart gegenüber JH3 ohne App 2 Tipps, bringt aber einen neuen Auftragsverarbeiter mit US-Mutter und einen Geräte-Abgleich, den Legal N-111 ohne vorherigen Tipp ausschließt; seine Zahlen enthalten diesen Tipp schon. JH5 ist ohne ihn 1 Tipp besser.
- JH4 (App Clip) liegt bei den Tipps gleichauf mit JH1, ist aber nur iOS, braucht ein zweites iOS-Target mit Flutter im Clip und etwa 15 Tage.
- JH2 ist der einzige Weg zu einer gemeinsamen Liste ganz ohne Installation. Seine Schwäche ist der getippte Code (11 Tipps, über Anmeldung und Willkommen).
- Jede neue Variante fragt die Nutzungsdaten nach dem Beitritt, nicht davor, und kein Warten bietet „Eigenen Haushalt anlegen“ als Hauptknopf an.

## Vergleich

<!-- table -->
| Variante | Tipps / Bildschirme bis zur ersten gemeinsamen Liste | Tipps / Bildschirme bis zur Liste in der App | „Einladung einfügen“ | Manuell „Ich habe eine Einladung“ | Nicht installiert (verzögerter Link) | Erste Liste in | Warten auf Bestätigung | Einwilligung | Datenschutz-Exposition | Bauaufwand | Fertiger Dienst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Heute** Heute (main) | **6 / 5** (5–11 / 4–8) | **14 / 11** (5–14 / 4–12) | bleibt, auf Start und Anmeldung | „Einladung einfügen“ auf Start und Anmeldung; „Einladung annehmen“ nach der Anmeldung | keiner: Web-Beitritt bleibt im Browser; Einladung einfügen, wenn der Code kopiert wurde | App (installiert) oder Browser | „Anfrage gesendet“; erster Knopf „Eigenen Haushalt anlegen“ | ganzer Bildschirm vor dem Beitritt, je Installation erneut | niedrig: nichts Neues | 0 (live) | keiner |
| **JH1** Der Store merkt sich die Einladung (Deep-Link-Dienst) | **7 / 5** (4–9 / 3–8) | **7 / 5** (4–9 / 3–8) | entfällt | „Ich habe einen Code“ in der Einladungskarte des Startbildschirms | der Dienst ordnet die Installation dem Tipp zu, nach „Ich wurde eingeladen“ (iOS über IP und Gerätetyp; Android über den Store-Referrer) | App | „Mia lässt dich gleich rein“, Liste öffnet sich selbst, kein „eigenen anlegen“ | Karte auf der ersten Liste | hoch: neuer Auftragsverarbeiter mit US-Mutter bekommt IP, User-Agent, Gerätedaten bei Klick und erstem Start | 7 Tage + AVV, Legal | Branch oder AppsFlyer OneLink |
| **JH2** Im Browser beitreten, dann die App holen | **4 / 3** (4–11 / 3–10) | **10 / 7** (4–11 / 3–10) | entfällt | „Einladung annehmen“ auf Willkommen, erst nach der Anmeldung | nicht nötig: Sie tritt im Web bei; die Mitgliedschaft hängt am Konto | Browser (App installiert: App) | freundliches Warten; „App laden“ in der Wartezeit | Karte auf der Liste; in der App erneut (je Installation) | niedrig: nichts Neues | 4 Tage | keiner (heutige Web-App) |
| **JH3** Zwei Türen: Link noch einmal antippen oder Code tippen | **9 / 7** (5–10 / 4–9) | **9 / 7** (5–10 / 4–9) | entfällt | „Einem Haushalt beitreten“, gleichwertige zweite Tür auf dem Startbildschirm (Code oder QR) | die Beitrittsseite sagt „App laden, dann Link noch einmal antippen“; der Code ist der Ausweg | App | freundliches Warten, sagt, was Mia sieht | Blatt über der ersten Liste (1 Tipp) | niedrig: nichts wird vom Gerät gelesen | 4 Tage (Scanner später, JH-Q8) | keiner |
| **JH4** App Clip: beitreten, bevor etwas installiert ist | **4 / 4** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | entfällt | „Ich habe einen Einladungscode“ unter den Start-Knöpfen | iOS: Das App Clip tritt bei und übergibt die Sitzung an die App; Android: Web-Beitritt | App Clip, dann App | freundliches Warten im Clip | keine im Clip; Karte in der App | niedrig: nur Apple (ohnehin der Store) | 15 Tage (zweites iOS-Target, Flutter im Clip) | Apple App Clips |
| **JH5** Erst der Name, Konto später; klares Warten | **6 / 5** (2–7 / 2–7) | **6 / 5** (2–7 / 2–7) | entfällt; ein System-Einsetzen-Knopf beim ersten Start | „Code eintippen“ in der Einladungskarte beim ersten Start | der Store-Knopf der Beitrittsseite kopiert die Einladung; der Einsetzen-Knopf der App liest sie auf ihren Tipp | App | Warten zeigt, was Mia sieht, bietet Bescheid an | Karte auf der Liste, nach „Zugang sichern“ | mittel: Gastkonto ohne E-Mail; Zwischenablage auf ihren Tipp | 8 Tage (anonyme Anmeldung, Upgrade, Missbrauchsgrenzen) | Anonyme Supabase-Anmeldung |

Fett: Einladungslink, Nicht installiert, Aus; in Klammern der Bereich über alle 12 Szenarien.
<!-- /table -->

## Was JH5 von den anderen übernehmen sollte

- Aus JH3: „Einem Haushalt beitreten“ als sichtbare zweite Tür auf dem Startbildschirm, für alle mit Code und ohne Link.
- Aus JH2: Die Beitrittsseite behält „Im Browser beitreten“ als Textknopf für alle, die keine App wollen.
- Ein Code-Einstieg, nicht zwei: Die Tür öffnet denselben Codeschirm wie „Code eintippen“ aus JH5, also behält der Startbildschirm die Tür und die Einsetzen-Karte beim ersten Start und lässt „Code eintippen“ weg.
- Ohne App brauchen die 6 Tipps von JH5 den App-Store-Knopf der Beitrittsseite, der erst erscheint, wenn die Store-Einträge öffentlich sind (JH-Q2). Bis dahin geht der Weg über „Im Browser beitreten“ oder einen getippten Code.

## Offene Fragen

1. **JH-Q1** „Einladung einfügen“ von Start und Anmeldung entfernen? Standard: ja. Die Karte beim ersten Start aus JH5 („Kommst du von einer Einladung?“ mit System-Einsetzen-Knopf und „Code eintippen“) und „Einladung annehmen“ auf Willkommen ersetzen es.
2. **JH-Q2** Welcher Knopf führt auf der Beitrittsseite, wenn die App fehlt? Standard: „App laden“, sobald die Store-Einträge öffentlich sind (`storeListings` in `app/web/join/join.js`); bis dahin bleibt „Im Browser beitreten“ der Hauptknopf.
3. **JH-Q3** Einen Deep-Link-Dienst (JH1) für Installationen ergänzen, die den Link verlieren? Standard: nein. Neu prüfen, wenn auf iOS mehr als 30 % der Aufrufe der Beitrittsseite nicht innerhalb von 24 Stunden zu einem Beitritt führen, gezählt aus unseren eigenen Beitrittsdaten ohne neues Ereignis.
4. **JH-Q4** Den Android-Install-Referrer zurückholen, gelesen erst nach einem Tipp auf „Ich wurde eingeladen“? Standard: nein. Legal nur fragen, wenn Android denselben Verlust zeigt.
5. **JH-Q5** Nutzungsdaten nach dem Beitritt fragen statt davor? Standard: ja, eine Karte auf der ersten Liste mit dem heutigen vollen Text (der Prototyp zeigt ihn) und zwei gleichen Knöpfen. Legal bestätigt, dass die neue Reihenfolge keinen neuen Text braucht.
6. **JH-Q6** Beim Warten auf Bestätigung „Eigenen Haushalt anlegen“ als Hauptknopf streichen? Standard: ja. Das Warten sagt, was Mia sieht und dass sich die Liste von selbst öffnet; „Lieber eine eigene Liste anlegen“ wird ein Textknopf auf der Landeseite.
7. **JH-Q7** Auch für Einladungen für eine Person einen QR-Code zeigen (heute nur Gruppenlinks)? Standard: ja, auf der Einladungskarte.
8. **JH-Q8** Einen QR-Scanner in „Einem Haushalt beitreten“ einbauen? Standard: nicht in der ersten Version. Die Kamera öffnet den Link schon; der Knopf im Prototyp zeigt, wo er hinkäme.
9. **JH-Q9** Darf die Landeseite in der App die Angaben der Beitrittsseite (Vorname, Haushalt, Zahlen, Premium) vor der Anmeldung zeigen? Standard: ja, dieselbe Antwort von `preview_invite_public` und nicht mehr. Legal bestätigt, dass N-112 / N-151b die Anzeige in der App abdecken.
10. **JH-Q10** Gastkonten (anonyme Supabase-Anmeldung) für JH5 bauen? Standard: ja, nur für den Beitritt per Einladung: Ein Gastkonto entsteht nur zusammen mit einem gültigen Einladungscode (ein Gast kann nichts, bis ein gültiger Code ihn beitreten lässt, und der Beitritt per Code ist schon begrenzt), und Supabase begrenzt anonyme Anmeldungen je IP; kein Captcha, also kein neuer Auftragsverarbeiter. Eine Karte „Zugang sichern“ verknüpft Apple, Google oder E-Mail; ein nie gesichertes Gastkonto fällt unter die normalen Regeln des Haushalts. Falls nein: JH3.
11. **JH-Q11** Darf „App laden“ auf der Beitrittsseite die Einladung in die Zwischenablage kopieren (JH5)? Standard: ja, nur auf diesen Tipp, mit der Zeile „Der Knopf kopiert deine Einladung“ darunter; die App liest sie nur auf den Einsetzen-Tipp.
