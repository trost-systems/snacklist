# Snacklist per Siri: Kurzbefehl einrichten

Mit einem Kurzbefehl setzt du Sachen per Siri auf deine Snacklist, ohne die App zu öffnen. Das ist kein fertiger Knopf in der App: Du legst den Kurzbefehl einmal selbst in der Kurzbefehle-App an. Danach läuft es so:

> **Du:** Hey Siri, Einkaufsliste.  
> **Siri:** Was soll auf die Liste?  
> **Du:** Milch, zwei Gurken und Klopapier.  
> **Siri:** Hinzugefügt: Milch, 2 Gurken, Klopapier.

Siri schickt deinen Satz an Snacklist. Snacklist teilt ihn in einzelne Einträge auf, setzt jeden an die passende Stelle der Liste, und die Einträge erscheinen sofort auf allen Geräten in eurem Haushalt. Das Aufteilen funktioniert bisher nur auf Deutsch.

## Was du brauchst

-   ein iPhone mit der App **Kurzbefehle**
-   die Snacklist-App, in der du angemeldet bist und zu einem Haushalt gehörst
-   etwa fünf Minuten

## Schritt 1: Zugriffstoken in Snacklist erstellen

Der Kurzbefehl meldet sich mit einem persönlichen Zugriffsschlüssel an, nicht mit deinem Passwort. In dieser Anleitung heißt er kurz Token.

1.  Öffne die Snacklist-App.
2.  Tippe auf **Mehr** und dann auf **Zugänge**.
3.  Tippe unter **Zugriffsschlüssel** auf **Schlüssel erstellen**.
4.  Gib als Name `Siri` ein, wähle **Lesen und schreiben** und tippe auf **Erstellen**. Mit **Nur lesen** kann der Kurzbefehl nichts auf die Liste setzen.
5.  Kopiere den Schlüssel. Er beginnt mit `fgp_`.

Die App zeigt den Token nur dieses eine Mal an. Füge ihn am besten direkt in Schritt 2 ein. Wenn du ihn kurz in einer Notiz zwischenspeicherst, lösch die Notiz danach.

## Schritt 2: Kurzbefehl anlegen

1.  Öffne die App **Kurzbefehle** und tippe oben rechts auf **Hinzufügen** (**+**).
2.  Tippe oben auf **Neuer Kurzbefehl** und dann auf **Umbenennen**. Gib `Einkaufsliste` ein und tippe auf **Fertig**. Dieser Name ist der Satz, auf den Siri hört.
3.  Füge die drei Aktionen unten in dieser Reihenfolge hinzu. Du findest jede über **Aktion hinzufügen** oder das Suchfeld unten.

### Aktion 1: Text diktieren

1.  Füge **Text diktieren** hinzu.
2.  Tippe in der Aktion auf **Mehr anzeigen** (den Pfeil **\>**) und stelle ein:
    -   **Sprache:** `Deutsch (Deutschland)`
    -   **Aufnahme beenden:** `Nach Pause`
    -   **Eingabeaufforderung:** `Was soll auf die Liste?`

### Aktion 2: Inhalte von URL abrufen

1.  Füge **Inhalte von URL abrufen** hinzu.

2.  Tippe auf **URL** und gib genau diese Adresse ein:

    ```text
    https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/voice?format=text
    ```

3.  Tippe auf **Mehr anzeigen** (den Pfeil **\>**) und stelle ein:

    -   **Methode:** `POST`
    -   **Header:** Tippe auf **Neuen Header hinzufügen**.
        -   Schlüssel: `Authorization`
        -   Text: `Bearer` (mit Leerzeichen), direkt danach dein Token. Das sieht dann so aus: `Bearer fgp_…`
    -   **Haupttext anfordern:** `JSON`
        -   Tippe auf **Neues Feld hinzufügen** und wähle **Text**.
        -   Schlüssel: `text`
        -   Wert: Tippe in das Feld und wähle über der Tastatur die Variable **Diktierter Text** aus.

### Aktion 3: Text sprechen

1.  Füge **Text sprechen** hinzu.
2.  Als Text muss die Variable **Inhalte der URL** dastehen. Meist setzt Kurzbefehle sie von selbst ein. Falls nicht, tippe auf das Feld und wähle sie aus.
3.  Optional: Tippe auf **Mehr anzeigen** (den Pfeil **\>**) und wähle als **Sprache** `Deutsch (Deutschland)`.

Tippe oben rechts auf **Fertig**.

So sieht der fertige Kurzbefehl aus:

```text
Text diktieren          (Deutsch, nach Pause, „Was soll auf die Liste?“)
↓ Diktierter Text
Inhalte von URL abrufen (POST …/functions/v1/voice?format=text,
                         Authorization: Bearer fgp_…,
                         JSON { text: Diktierter Text })
↓ Inhalte der URL
Text sprechen           (Inhalte der URL)
```

## Schritt 3: Ausprobieren

1.  Tippe in der Kurzbefehle-App auf den Kurzbefehl **Einkaufsliste**. Beim ersten Mal fragt iOS, ob der Kurzbefehl Daten an `jdwqrallbpdbshrdhenk.supabase.co` senden darf. Tippe auf **Immer erlauben**. Dann fragt iOS beim nächsten Mal nicht mehr.
2.  Sag: „Milch, zwei Gurken und Klopapier“.
3.  Siri antwortet „Hinzugefügt: Milch, 2 Gurken, Klopapier.“, und die Einträge stehen in der App.

Ab jetzt geht es ohne Hände: „Hey Siri, Einkaufsliste“ (oder „Siri, Einkaufsliste“, je nachdem, worauf Siri bei dir hört).

> **Wichtig: Dein Token ist wie ein Schlüssel zu deiner Liste**
> 
> -   Teile den fertigen Kurzbefehl nicht mit anderen. Dein Token steckt darin, und wer ihn hat, kann Sachen auf deine Liste setzen.
> -   Zeig deinen Token niemandem und schick ihn nicht per Nachricht oder Mail.
> -   Wenn dein iPhone verloren geht oder du glaubst, jemand kennt deinen Token: Widerrufe ihn in der App: **Mehr** → **Zugänge**, tippe auf **Siri widerrufen** (oder „\[Name\] widerrufen“, wenn du den Token anders genannt hast). Die App fragt „Token widerrufen?“. Bestätige mit **Widerrufen**. Danach hat der Kurzbefehl keinen Zugriff mehr.

## So kannst du sprechen

Sag mehrere Dinge in einem Satz. Trenne sie mit einer kurzen Pause, mit „und“, „sowie“, „noch“ oder „auch“.

| Du sagst | Auf der Liste |
| --- | --- |
| Milch, zwei Gurken und Klopapier | Milch · 2× Gurken · Klopapier |
| Wir brauchen noch Butter und Eier | Butter · Eier |
| Schreib bitte Windeln auf die Liste | Windeln |
| Ein Kilo Äpfel und 500 Gramm Hackfleisch | 1 kg Äpfel · 500 g Hackfleisch |
| Eine Packung Eier sowie zwei Flaschen Wein | 1 Packung Eier · 2 Flaschen Wein |
| Einen Kasten Wasser, auch Kaffee | 1 Kasten Wasser · Kaffee |

Füllwörter wie „bitte“, „wir brauchen“, „schreib auf“, „noch“, „auf die Liste“ und Artikel lässt Snacklist weg. Zahlwörter werden zu Ziffern („zwei“ wird 2). Mengen bleiben als Menge am Eintrag, die App zeigt sie vor dem Namen („2× Gurken“, „1 kg Äpfel“). Was schon auf der Liste steht, kommt nicht doppelt dazu. Siri sagt dann zum Beispiel „Schon auf der Liste: Milch.“ Steht etwas Ähnliches schon drauf, etwa Möhren, wenn du Karotten sagst, kommt der neue Eintrag trotzdem dazu, und Siri sagt „Möhren steht schon auf der Liste.“

## Wenn es nicht klappt

| Siri sagt | Woran es liegt | Was hilft |
| --- | --- | --- |
| „Der Zugriffstoken fehlt oder ist ungültig. Erstelle in der Snacklist-App unter Mehr, Zugänge einen neuen.“ | Der Token fehlt im Kurzbefehl, ist falsch kopiert oder wurde widerrufen. | Erstell in Snacklist unter **Mehr** → **Zugänge** einen neuen Token (Schritt 1). Öffne dann den Kurzbefehl, geh in Aktion 2 zum Header `Authorization` und ersetze den alten Token: `Bearer` , Leerzeichen, dann der ganze neue Token, also `Bearer fgp_…`. |
| „Du bist noch in keinem Haushalt …“ | Das Konto, zu dem der Token gehört, ist in keinem Haushalt. | Leg in der App einen Haushalt an oder tritt einem bei. |
| „Ich habe nichts verstanden, was auf die Liste soll …“ | Das Diktat war leer oder bestand nur aus Füllwörtern. | Versuch es noch einmal, zum Beispiel mit „Milch und Brot“. |
| „Das war zu lang …“ | Mehr als 1000 Zeichen. | Sag weniger auf einmal (höchstens 30 Dinge). |
| „Das hat leider nicht geklappt …“ | Snacklist ist gerade nicht erreichbar. | Versuch es später noch einmal. |

Startet Siri bei „Einkaufsliste“ nicht deinen Kurzbefehl? Prüf, ob er genau so heißt. Sonst gib ihm einen eindeutigeren Namen, etwa `Einkauf notieren`, und sag „Hey Siri, Einkauf notieren“. Zum Umbenennen öffnest du den Kurzbefehl, tippst auf den Pfeil neben seinem Namen und dann auf **Umbenennen**.

## Siri wieder abschalten

1.  Lösch den Kurzbefehl in der Kurzbefehle-App: Leg den Finger auf **Einkaufsliste**, tippe auf **Löschen** und bestätige.
2.  Widerrufe den Token in Snacklist: **Mehr** → **Zugänge**, tippe auf **Siri widerrufen** (oder „\[Name\] widerrufen“, wenn du den Token anders genannt hast). Die App fragt „Token widerrufen?“. Bestätige mit **Widerrufen**.

Damit ist die Verbindung getrennt.

Fragen oder Probleme? Schreib mir in der App über **Mehr** → **Feedback & Ideen**.

Aktualisiert: 30\. Oktober 2026

---

Canonical URL: https://snacklist.app/de/anleitungen/siri-kurzbefehl
Markdown (en): https://snacklist.app/en/guides/siri-shortcut.md
