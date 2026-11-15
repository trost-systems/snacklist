# Einem Haushalt beitreten: Empfehlung (JH1–JH5)

**Empfehlung: JH3, zwei Türen.** Der Startbildschirm bekommt „Einem Haushalt beitreten“ als gleichwertige zweite Tür statt „Einladung einfügen“, eine installierte App öffnet eine Landeseite, die Mia und den Haushalt vor jedem Konto nennt, und nichts wird vom Gerät gelesen oder an einen neuen Dienst geschickt. Das kostet etwa 4 Tage, hält den Beitritt mit App bei 4 Tipps, und die Code-Tür fängt alle auf, die der Store verliert.

**Zweite Wahl: JH2, erst im Browser beitreten.** Es ist der einzige Weg, der Eingeladene ohne jede Installation in die gemeinsame Liste bringt (4 Tipps), mit dem Stack von heute. Der Preis ist eine zweite Anmeldung und eine zweite Einwilligung, sobald sie die App holt (10 Tipps bis zur Liste in der App).

## Warum

- Eingeladene kommen meist ohne App. Mit dem heutigen Link erreichen sie eine Liste nur im Browser und in der App erst nach 14 Tipps. JH3 bringt sie in 7 Tipps in die Liste der App, JH5 in 6, JH4 in 7.
- Legal N-111 schließt jedes automatische Auslesen beim ersten Start aus. Der Deep-Link-Dienst aus JH1 braucht eines (Gerätedaten beim ersten Start, auf iOS Fingerprinting) oder vorher einen Tipp, dazu einen neuen Auftragsverarbeiter mit US-Mutter. Ohne App spart er gegenüber JH3 nichts (je 7 Tipps).
- JH4 (App Clip) ist auf dem Papier am glattesten, aber nur iOS, braucht ein zweites iOS-Target mit Flutter in der Größengrenze des Clips und etwa 15 Tage. Für später.
- JH5 hat die wenigsten Tipps (2 mit App), bringt aber Gastkonten: eine neue Kontoart für Löschung, Export und Missbrauchsgrenzen, und verlorenen Zugang, wenn ein Gast nie sichert.
- Jede neue Variante fragt die Nutzungsdaten nach dem Beitritt, nicht davor, und das Warten auf Bestätigung bietet „Eigenen Haushalt anlegen“ nicht mehr als Hauptknopf an.

## Vergleich

<!-- table -->
| Variante | Tipps / Bildschirme bis zur ersten gemeinsamen Liste | Tipps / Bildschirme bis zur Liste in der App | „Einladung einfügen“ | Manuell „Ich habe eine Einladung“ | Nicht installiert (verzögerter Link) | Erste Liste in | Warten auf Bestätigung | Einwilligung | Datenschutz-Exposition | Bauaufwand | Fertiger Dienst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Heute** Heute (main) | **6 / 5** (5–11 / 4–8) | **14 / 11** (5–14 / 4–12) | bleibt, auf Start und Anmeldung | „Einladung einfügen“ auf Start und Anmeldung; „Einladung annehmen“ nach der Anmeldung | keiner: Web-Beitritt bleibt im Browser; Einladung einfügen, wenn der Code kopiert wurde | App (installiert) oder Browser | „Anfrage gesendet“; erster Knopf „Eigenen Haushalt anlegen“ | ganzer Bildschirm vor dem Beitritt, je Installation erneut | niedrig: nichts Neues | 0 (live) | keiner |
| **JH1** Der Store merkt sich die Einladung (Deep-Link-Dienst) | **7 / 5** (4–9 / 3–8) | **7 / 5** (4–9 / 3–8) | entfällt | „Ich habe einen Code“ in der Einladungskarte des Startbildschirms | der Dienst ordnet die Installation dem Tipp zu, nach „Ich wurde eingeladen“ (iOS über IP und Gerätetyp; Android über den Store-Referrer) | App | „Mia lässt dich gleich rein“, Liste öffnet sich selbst, kein „eigenen anlegen“ | Karte auf der ersten Liste | hoch: neuer Auftragsverarbeiter mit US-Mutter bekommt IP, User-Agent, Gerätedaten bei Klick und erstem Start | 7 Tage + AVV, Legal | Branch oder AppsFlyer OneLink |
| **JH2** Im Browser beitreten, dann die App holen | **4 / 3** (4–11 / 3–10) | **10 / 7** (4–11 / 3–10) | entfällt | „Einladung annehmen“ auf Willkommen, erst nach der Anmeldung | nicht nötig: Sie tritt im Web bei; die Mitgliedschaft hängt am Konto | Browser (App installiert: App) | freundliches Warten; „App laden“ in der Wartezeit | Karte auf der Liste; in der App erneut (je Installation) | niedrig: nichts Neues | 4 Tage | keiner (heutige Web-App) |
| **JH3** Zwei Türen: Link noch einmal antippen oder Code tippen | **7 / 6** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | entfällt | „Einem Haushalt beitreten“, gleichwertige zweite Tür auf dem Startbildschirm (Code oder QR) | die Beitrittsseite sagt „App laden, dann Link noch einmal antippen“; der Code ist der Ausweg | App | freundliches Warten, sagt, was Mia sieht | Blatt über der ersten Liste | niedrig: nichts wird vom Gerät gelesen | 4 Tage | keiner |
| **JH4** App Clip: beitreten, bevor etwas installiert ist | **4 / 4** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | entfällt | „Ich habe einen Einladungscode“ unter den Start-Knöpfen | iOS: Das App Clip tritt bei und übergibt die Sitzung an die App; Android: Web-Beitritt | App Clip, dann App | freundliches Warten im Clip | keine im Clip; Karte in der App | niedrig: nur Apple (ohnehin der Store) | 15 Tage (zweites iOS-Target, Flutter im Clip) | Apple App Clips |
| **JH5** Erst der Name, Konto später; klares Warten | **6 / 5** (2–7 / 2–7) | **6 / 5** (2–7 / 2–7) | entfällt; ein System-Einsetzen-Knopf beim ersten Start | „Code eintippen“ in der Einladungskarte beim ersten Start | der Store-Knopf der Beitrittsseite kopiert die Einladung; der Einsetzen-Knopf der App liest sie auf ihren Tipp | App | Warten zeigt, was Mia sieht, bietet Bescheid an | Karte auf der Liste, nach „Zugang sichern“ | mittel: Gastkonto ohne E-Mail; Zwischenablage auf ihren Tipp | 8 Tage (anonyme Anmeldung, Upgrade, Missbrauchsgrenzen) | Anonyme Supabase-Anmeldung |

Fett: Einladungslink, Nicht installiert, Aus; in Klammern der Bereich über alle 12 Szenarien.
<!-- /table -->

## Was JH3 von den anderen übernimmt

- Aus JH5: „App laden“ auf der Beitrittsseite kopiert auch den Code, und der Codeschirm hat den System-Einsetzen-Knopf (er liest die Zwischenablage nur auf diesen Tipp, ohne iOS-Nachfrage). Das ist das heutige Auslesen von „Einladung einfügen“, verlegt dorthin, wo man es erwartet.
- Aus JH2: Die Beitrittsseite behält „Im Browser beitreten“ als Textknopf für alle, die keine App wollen.

## Offene Fragen

1. **JH-Q1** „Einladung einfügen“ von Start und Anmeldung entfernen? Standard: ja. „Einem Haushalt beitreten“ auf dem Start und „Einladung annehmen“ auf Willkommen ersetzen es; der Codeschirm bekommt den Einsetzen-Knopf.
2. **JH-Q2** Welcher Knopf führt auf der Beitrittsseite, wenn die App fehlt? Standard: „App laden“, sobald die Store-Einträge öffentlich sind (`storeListings` in `app/web/join/join.js`); bis dahin bleibt „Im Browser beitreten“ der Hauptknopf.
3. **JH-Q3** Einen Deep-Link-Dienst (JH1) für Installationen ergänzen, die den Link verlieren? Standard: nein. Neu prüfen, wenn auf iOS mehr als 30 % der Aufrufe der Beitrittsseite nicht innerhalb von 24 Stunden zu einem Beitritt führen, gezählt aus unseren eigenen Beitrittsdaten ohne neues Ereignis.
4. **JH-Q4** Den Android-Install-Referrer zurückholen, gelesen erst nach einem Tipp auf „Ich wurde eingeladen“? Standard: nein. Legal nur fragen, wenn Android denselben Verlust zeigt.
5. **JH-Q5** Nutzungsdaten nach dem Beitritt fragen (ein Blatt über der ersten Liste) statt davor? Standard: ja, mit dem heutigen Text und zwei gleichen Knöpfen. Legal bestätigt, dass die neue Reihenfolge keinen neuen Text braucht.
6. **JH-Q6** Beim Warten auf Bestätigung „Eigenen Haushalt anlegen“ als Hauptknopf streichen? Standard: ja. Das Warten sagt, was Mia sieht und dass sich die Liste von selbst öffnet; „Lieber eine eigene Liste anlegen“ wird ein Textknopf.
7. **JH-Q7** Auch für Einladungen für eine Person einen QR-Code zeigen (heute nur Gruppenlinks)? Standard: ja, auf der Einladungskarte.
8. **JH-Q8** Einen QR-Scanner in „Einem Haushalt beitreten“ einbauen? Standard: nicht in der ersten Version. Die Kamera öffnet den Link schon; der Knopf im Prototyp zeigt, wo er hinkäme.
9. **JH-Q9** Darf die Landeseite in der App die Angaben der Beitrittsseite (Vorname, Haushalt, Zahlen, Premium) vor der Anmeldung zeigen? Standard: ja, dieselbe Antwort von `preview_invite_public` und nicht mehr. Legal bestätigt, dass N-112 / N-151b die Anzeige in der App abdecken.
