# Runde SS: Empfehlung

<!-- pick: SS2 -->
<!-- runner-up: SS5 -->

## Empfehlung

**Wahl: SS2, tippen wie heute, mit angebotenen Treffern und einem „Ist das Lidl?“.** Das Feld zum Hinzufügen bleibt, wie es ist. Die Treffer darunter suchen erst im Land des Handys, dann in jedem Land. So findet „Hofer“ das österreichische Hofer und „Carre“ Carrefour, ganz ohne Land-Einstellung. Ein getippter Name, der passt, fragt einmal. Ein Name ohne Treffer wird gespeichert wie heute, ohne Frage. Der eigene Name des Ladens ändert sich nie: „Aldi am Bahnhof“ bleibt die Beschriftung, die Verbindung steht daneben.

Zwei Regeln aus SS5 gehören zur Wahl:
- **Vorhandene Läden:** nur dort fragen, wo die Verbindung etwas Sichtbares ändert, heute also bei einem Laden, dessen Kette eine App hat. Einmal je Laden, als Karte auf der Liste.
- **Land:** die Region des Handys beim Hinzufügen nehmen, keine Einstellung im Haushalt. Damit sinkt SS2s Weg „Land wechseln“ von 8 Tipps auf die 5 von SS5.

**Zweite Wahl: SS5, faul.** Es fragt am wenigsten, und Läden ohne App bleiben unberührt. Der Preis: es erkennt nur Ketten mit App, also bräuchten Prospekte (OF1) oder Laufwege für andere Ketten später einen zweiten Durchgang.

Nicht empfohlen:
- **SS1, eine Auswahl.** Ausdrücklich und vorhersehbar, aber vorhandene Läden zu verbinden kostet 9 Tipps, und ein Land ist etwas, das man verstehen muss.
- **SS3, in der Nähe.** Die einzige Option mit echter Filiale, und die Filiale bestimmt das Land. Aber sie schickt den Standort an einen Kartendienst, und Google Places ist eine kostenpflichtige API. Das öffentliche Nominatim von OpenStreetMap erlaubt keine Nutzung in App-Größe. Erst wieder ansehen, wenn Funktionen je Filiale kommen.
- **SS4, ein Verzeichnis.** Es trägt nicht über ein paar Dutzend Ketten je Land hinaus, und der Haushalt braucht eine Land-Einstellung.

## Gemessen

Das sind die Tipps von der Liste bis zum Ende jedes Szenarios (`verify.mjs` liest sie aus den Wegen). „Land wechseln“ geht bei SS2 und SS4 über Mehr › Einstellungen › Einkaufsland.

| Option | Vorhandene Läden | Ein neuer Laden | Nicht in der Liste | Eine Kette, zwei Länder | Land wechseln | Tippen | Standort | Land |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **SS1** Ketten-Auswahl | 9 | 3 | 3 | 5 | 5 | Suche | nein | je Laden, aus der Handy-Region, „Ändern“ |
| **SS2** Treffer beim Tippen, „Ist das Lidl?“ | 3 | 4 | 3 | 3 | 8 | wie heute | nein | Einstellung im Haushalt; Treffer in jedem Land |
| **SS3** In der Nähe | 6 | 5 | 5 | 5 | 5 | keins (oder ein Ort) | ja, einmal je Suche, an einen Kartendienst | aus der Filiale |
| **SS4** Verzeichnis nach Ländern | 4 | 3 | 4 | 4 | 8 | nur „Anderer“ | nein | Einstellung im Haushalt |
| **SS5** Faul | 3 | 4 | 3 | 5 | 5 | wie heute | nein | Handy-Region, dann jedes Land |

- „Vorhandene Läden“ verbindet dm, Lidl und „Aldi“ (in Deutschland zwei Ketten, also eine Wahl mehr) und lässt den Markt, wie er ist.
- „Ein neuer Laden“ kostet bei SS2 4 Tipps, wenn man den Namen einfach speichert und die Frage beantwortet, und 3, wenn man den Vorschlag antippt.
- SS2 und SS5 setzen eine Karte auf die Liste, solange sie fragen: eine Karte, etwa 120 px bei 100 %, weg nach der Antwort.

## Vorschlag für das Datenmodell

Ein Verzeichnis der Händler, mit Kette und Land (ISO 3166-1 alpha-2) als Schlüssel und den App-IDs je Land. Es ist im Repo versioniert und wird aus Supabase ausgeliefert, also kommt ein neues Land ohne App-Release.

```
registry/retailers.json (Quelle der Wahrheit, in PRs geprüft)
  { chain: "aldi-sued", country: "AT", name: "Hofer", aliases: ["hofer", "aldi"],
    app: { name: "HOFER", android: "de.apptiv.business.android.aldi_at", ios: "395677652",
           universalLink: "https://www.hofer.at/homescreen",
           storeFallback: { android: "market://details?id=…", ios: "itms-apps://apps.apple.com/app/id395677652" } },
    status: "verified", verified: "2026-11-18", sources: [ … ] }

public.retailers (chain text, country char(2), name text, aliases text[], app jsonb, status text, verified date,
                  primary key (chain, country))       -- öffentliche Daten: RLS an, lesen für anon und authenticated
public.stores    + retailer_chain text null, + retailer_country char(2) null, + branch text null
                  foreign key (retailer_chain, retailer_country) references retailers on delete set null
public.match_retailer(household uuid, name text, country char(2)) -> (chain, country)[]
                  -- auf dem Server, neben classify_item, mit store_name_key; App, MCP und Siri rufen sie alle auf
```

- **Wo die Daten liegen.**
  - *Lokales JSON in der App* braucht für jede neue ID ein Release. Es dient nur als mitgelieferter Stand für den ersten Start ohne Netz.
  - *Eine Supabase-Tabelle* ist die Wahl. Der Deploy lädt sie aus `retailers.json` mit einem idempotenten Upsert, die App liest sie einmal am Tag und speichert sie in `DeviceCache`, und MCP und Siri teilen sie.
  - *PostHog-Flags* schalten nur Funktionen: `open-store-app` und seine Ausrichtung je Land. Payloads sind keine Datenbank.
- **Ein Land hinzufügen.**
  1. Einträge in `retailers.json` ergänzen.
  2. `node registry/verify-registry.mjs --only <CC>` laufen lassen. Es prüft jede ID bei Apple und Google und jeden Link gegen AASA und Asset Links.
  3. Einen PR öffnen. Das Lint-Gate prüft das Schema offline.
  4. Mergen. Der Deploy schreibt die Zeilen, und die App holt sie innerhalb eines Tages.

  Ein App-Release ist nicht nötig. Android startet eine App über den Paketnamen mit `startActivity` und fängt `ActivityNotFoundException` ab; dafür braucht es keinen `<queries>`-Eintrag (Android-Doku, „Package visibility use cases“). iOS öffnet https-Links und `itms-apps://`, die keine Deklaration brauchen.
- **Die heutigen Seeds.** Die `seed_key`s dm, lidl und edeka werden zu Verbindungen `dm:DE`, `lidl:DE` und `edeka:DE`. Die Laufwege hängen dann an der Kette.
- **Das Verzeichnis bisher.** Es hat 58 verifizierte Einträge (Kette und Land) in DE, AT, CH, FR, NL, PL, IT und ES, dazu Dino PL ohne App. Keine ID ist geraten; die Tabelle oben listet sie, und `registry/REGISTRY.md` erklärt, wie sie geprüft wurden. DeutschlandCard und PAYBACK fehlen mit Absicht.

## Datenschutz

Keine Option braucht von sich aus einen Standort. Nur SS3 nutzt ihn. Dort wird er auf einen Tipp hin einmal erfragt („Einmal erlauben“) und an den Kartendienst geschickt, um Läden in der Nähe zu finden. Snacklist speichert ihn nicht. **Hinweis für Legal:** SS3 bräuchte einen Kartendienst als Auftragsverarbeiter; weder Google Places (kostenpflichtig) noch das öffentliche Nominatim von OSM (Nutzungsregeln) passen ohne Vertrag. Der Ladenname, den jemand tippt, bleibt wie heute im Haushalt; der Abgleich läuft auf unserem Server gegen öffentliche Verzeichnisdaten.

## Offene Fragen

1. **SS-Q1 Wo liegt das Verzeichnis?** Standard: `retailers.json` im Repo als Quelle, vom Deploy in eine öffentliche Tabelle `retailers` geladen, die nur gelesen werden kann. Die App speichert sie zwischen und bringt einen Stand für den ersten Start mit. Flags schalten nur.
2. **SS-Q2 Woher kommt das Land eines Ladens?** Standard: aus der Region des Handys beim Hinzufügen, gespeichert je Laden. Der Abgleich versucht erst dieses Land, dann jedes Land. In der ersten Version gibt es keine Einstellung im Haushalt. Ein Laden in einem anderen Land bekommt sein Land vom Treffer („Hofer · Österreich“).
3. **SS-Q3 Welche vorhandenen Läden werden gefragt?** Standard: nur die, deren Treffer eine App hat, einmal je Laden, als Karte auf der Liste. „Nein“ merkt sich der Laden, und er behält seinen freien Text.
4. **SS-Q4 Bekommt ein Laden eine Filiale?** Standard: nicht in der ersten Version. Die Spalte (leer erlaubt) ist da, also können eine freie Filiale auf der Seite des Ladens oder die Wahl in der Nähe aus SS3 später kommen.
5. **SS-Q5 Bekommt Android `<queries>` je Paket, wie im DL1-Auftrag?** Standard: nein. `startActivity` mit dem Start-Intent des Pakets aufrufen, `ActivityNotFoundException` abfangen, dann die Seite bei Google Play öffnen. Neue Länder brauchen dann kein Release. Vor DL1 auf einem echten Android-14-Gerät bestätigen.
6. **SS-Q6 Wer hält die IDs aktuell?** Standard: ein wöchentlicher geplanter Lauf von `verify-registry.mjs`, der ein Issue öffnet, wenn eine ID oder ein Link nicht mehr auflöst. Änderungen gehen nur über PRs.
7. **SS-Q7 Wo läuft der Abgleich?** Standard: Postgres `match_retailer`, neben `classify_item` und mit `store_name_key`, damit App, MCP und Siri übereinstimmen. Die Aliasse liegen im Verzeichnis.
8. **SS-Q8 Welche App bekommt eine Kette mit zwei Apps (BILLA oder jö, Super U oder Courses U und andere)?** Standard: eine App je Kette und Land, die mit Kundenkarte oder Coupons. Die anderen stehen in der Notiz des Eintrags.
9. **SS-Q9 Soll der Hinweis zu Ladennamen unter jedem Ketten-Vorschlag und jeder Auswahl stehen?** Standard: ja, wörtlich. Legal bestätigt, dass L-7 die neuen Stellen abdeckt.
10. **SS-Q10 Soll die Suche über den Standort (SS3) später kommen?** Standard: nein, nicht ohne eine Funktion je Filiale, die sie braucht, und ohne Legals Prüfung eines Kartendienstes.
