# Runde SC: Empfehlung

**Wahl: SC1 Kompakt mit Laden. Zweite Wahl: SC3 Rückblick und Zurücknehmen.**

SC1 gibt genau das zurück, was der Haken weggenommen hat, den Knopf „REWE öffnen“, und braucht dafür am wenigsten Platz: 88 px bei 100 % und 302 px bei 310 %, bei beiden Größen das Kleinste der fünf. Sie braucht keine neuen Daten, keinen Deep Link und keinen Einkaufsbegriff, die Liste zum Start bleibt so einfach wie heute. SC3 ist zweite Wahl, weil „Letzten Haken zurücknehmen“ den einen echten Fehler an der Kasse behebt (der letzte Artikel aus Versehen abgehakt blendet den Abschnitt und seinen Knopf aus). Sie kostet aber 144 px und 498 px, und „Zuletzt verwendet“ holt einen Artikel schon mit einem Tipp zurück.

## Gemessen

iPhone 390×844, Englisch, hell, ganz oben gescrollt. Zeilen sind ganze offene Artikelzeilen zwischen Listenanfang und Eingabefeld. Zusätzlich ist der Kartenplatz (Karte plus je 8 px darüber und darunter), um den jede Zeile nach unten rutscht; Zusätzlich (c) dasselbe mit REWE und Lidl fertig. Die letzte Spalte nennt, wo der Hauptknopf „öffnen“ bei 310 % unter dem Eingabefeld liegt, bis man scrollt. Keine Karte hat Text oder Knöpfe außerhalb, überlappend oder unter 44 px, in keinem Zustand, keiner Sprache, keinem Design, Telefon oder Textgröße (verify.mjs).

| Option | Zeilen (a) | Zeilen (b) | Zeilen (c) | Zusätzlich 100 % | Zusätzlich 310 % | Zusätzlich (c) | Hauptknopf unter dem Eingabefeld bei 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Heute | 9 | 0 | 3 | 0 px | 0 px | 0 px | keine Karte |
| SC1 | 7 | 0 | 3 | 88 px | 302 px | 168 px | Android, (d) auf Deutsch |
| SC2 | 7 | 0 | 3 | 134 px | 442 px | 190 px | Android, (d) auf Deutsch |
| SC3 | 7 | 0 | 3 | 144 px | 498 px | 200 px | Android, (d) auf Englisch und Deutsch |
| SC4 | 7 | 0 | 3 | 140 px | 424 px | 140 px | Android, (d) auf Deutsch |
| SC5 | 7 | 0 | 3 | 124 px | 386 px | 228 px | nie |

Was die Zahlen sagen:
- Jede Karte kostet in (a) dieselben 2 Zeilen. Die 9 Zeilen von heute sind Lidls 7 und die ersten 2 von dm; jede Karte ab 88 px schiebt die 2 von dm hinaus, Lidls 7 bleiben unter allen fünf sichtbar. Die Höhe unterscheidet die Optionen, und SC1 ist bei 100 % 36 px bis 56 px kleiner als die anderen.
- In (b) ist die Liste leer, die Karte kostet nichts. In (c) bleiben die 3 Zeilen von dm unter jeder Karte sichtbar.
- In (c) stapelt SC1 zwei Karten (168 px, 80 px je Laden), SC5 fasst sie zusammen (228 px). SC2 und SC3 wachsen auch, weil der Knopf „Lidl Plus öffnen“ heißt und den zweiten Knopf umbricht. Nur SC4 bleibt bei 140 px. SC-Q3 schlägt eine Karte für den neuesten Laden vor.
- Bei 310 % auf dem kleinen Android-Telefon schiebt der lange Name in (d) „Netto öffnen“ unter das Eingabefeld: bei SC1, SC2 und SC4 auf Deutsch, bei SC3 in beiden Sprachen. Einmal scrollen holt ihn hoch. SC5 passt, weil neben dem Titel („Fertig bei Netto Marken-Discount?“) kein Knopf steht.

Warum nicht die anderen:
- **SC2** braucht einen Deep Link zur Kundenkarte. Für keine Kette ist einer geprüft (Job 314 hat DL2–DL4 gestrichen; die Links im Register öffnen den Startbildschirm der App). Ohne ihn würde der Build den Knopf ausblenden, und SC2 wird zu SC1 mit 46 px mehr.
- **SC4**s „Weiter: Lidl“ scrollt in (a) und (d) nirgendwohin, weil Lidl schon unter der Karte beginnt. Es hilft nur, wenn der nächste Laden unter dem sichtbaren Bereich liegt, und das automatische Schließen nach „öffnen“ nimmt den Knopf weg, den man nach einem fehlgeschlagenen Scan wieder braucht.
- **SC5** fragt „Fertig bei REWE?“ und bietet „Ich bin fertig“, das mit ausgeschalteten Einkäufen nichts speichert. Eine Frage ohne Folge, die nach Einkaufsmodus klingt, der zum Start aus ist.

## Offene Fragen

1. **SC-Q1 Schließt „REWE öffnen“ auch die Karte?** Vorschlag: nein. Die Karte bleibt nach „öffnen“, damit ein fehlgeschlagener Scan oder ein zweiter Bezahlversuch die App wieder öffnen kann; X oder SC-Q6 beenden sie.
2. **SC-Q2 Wann kommt eine geschlossene Karte wieder?** Vorschlag: erst wenn der Laden wieder einen offenen Artikel bekommt und man ihn wieder fertig abhakt. Bis dahin bleibt sie geschlossen, auf diesem Gerät.
3. **SC-Q3 Gestapelte oder zusammengefasste Karten, wenn mehrere Läden fertig werden?** Vorschlag: eine Karte für den zuletzt fertigen Laden; sie ersetzt die frühere. Es gibt immer nur eine Kasse zur Zeit, und ein Stapel aus SC1-Karten wächst um 80 px je Laden.
4. **SC-Q4 Deep Links zu Kundenkarte und Bezahlen?** Vorschlag: zum Start keine. Für keine Kette gibt es einen geprüften Deep Link zur Kundenkarte oder zum Bezahlen; der Knopf bleibt ausgeblendet, statt unter „Kundenkarte“ den Startbildschirm der App zu öffnen. Später könnte ein Feld je Kette im Register ihn hinzufügen, erst nach einem Test auf dem Gerät.
5. **SC-Q5 Rückblick als Anzahl oder mit Artikelnamen?** Vorschlag: zum Start kein Rückblick (SC1). Falls SC3 gewählt wird: nur die Anzahl („9 Artikel bei REWE gekauft“), ohne Namen; die Namen brauchten eine zweite Zeile und fallen ab 200 % ohnehin weg.
6. **SC-Q6 Verschwindet die Karte automatisch, wenn man die App nicht öffnet?** Vorschlag: ja, 60 Minuten nach dem letzten Haken des Ladens, oder sofort, wenn man dem Laden einen Artikel hinzufügt (dann sind Abschnitt und Knopf wieder da).
7. **SC-Q7 Flag?** Vorschlag: das bestehende Flag `open-store-app`, kein neues. Die Karte erscheint nur, wo der Knopf in der Kopfzeile erschienen wäre: bei einem Laden, der einer Kette zugeordnet ist, deren App das Register kennt.
8. **SC-Q8 Wer sieht die Karte?** Vorschlag: nur das Gerät, das den letzten Artikel des Ladens abgehakt hat. Ein Haken eines anderen Haushaltsmitglieds zu Hause legt keine Karte auf dieses Telefon.
9. **SC-Q9 Ein Laden ohne App-Link?** Vorschlag: keine Karte; sein Abschnitt verschwindet wie heute.
10. **SC-Q10 Der Fehlhaken an der Kasse ohne SC3?** Vorschlag: „Wieder auf die Liste“ unter „Zuletzt verwendet“ (ein Tipp, gibt es schon) holt den Artikel und den Abschnitt zurück; kein Zurücknehmen auf der Karte.
11. **SC-Q11 Analytics?** Vorschlag: `store_app_opened` (chain, country, outcome) weiter nutzen, mit einer neuen Eigenschaft `source` (`header` oder `card`). Sie braucht eine Regel in der Allow-List, einen Test und eine Zeile in docs/ANALYTICS.md im Build-Job (399).
12. **SC-Q12 Der lange Name bei 310 % auf einem kleinen Telefon?** Vorschlag: so lassen. Die Karte scrollt mit der Liste, einmal scrollen zeigt „öffnen“. „Netto Marken-Discount ist erledigt“ auf den Namen zu kürzen spart höchstens eine Zeile.
