---
title: "Snacklist mit Claude verbinden"
description: "Verbinde Claude in unter fünf Minuten mit deiner Snacklist. Dann setzt Claude Sachen auf die Liste, hakt sie ab und sagt dir, was noch fehlt."
slug: claude
locale: de
translation_key: claude
updated: 2026-11-04
---

# Snacklist mit Claude verbinden

Claude kann deine Snacklist lesen, Sachen draufsetzen, ändern, abhaken, wieder draufsetzen, löschen und in einen anderen Laden oder eine andere Liste verschieben. Du schreibst Claude einfach, was du brauchst:

> **Du:** Setz Milch, zwei Gurken und Klopapier auf die Snacklist.
> **Claude:** Ich habe Milch, 2 Gurken und Klopapier auf die Snacklist gesetzt.

Die Einträge stehen sofort auf allen Geräten in eurem Haushalt, an der passenden Stelle der Liste. Das Einrichten dauert keine fünf Minuten. Du musst keinen Schlüssel kopieren: Claude meldet sich mit deinem Snacklist-Konto an.

## Was du brauchst

- ein Claude-Konto auf [claude.ai](https://claude.ai). Mit Claude Free kannst du nur einen eigenen Connector hinzufügen. In einer Claude-Organisation (Team oder Enterprise) muss eventuell ein Admin den Connector hinzufügen.
- die Snacklist-App, in der du angemeldet bist und zu einem Haushalt gehörst
- einen Browser, am besten am Computer. Der Connector steht danach auch in der Claude-App auf dem Handy und am Desktop zur Verfügung.

::: once integration-lock
Der Zugang über KI-Assistenten braucht Snacklist Premium in deinem eigenen Konto.
:::

## Schritt 1: Connector hinzufügen

Die Namen der Menüpunkte in Claude stehen hier auf Deutsch, in Klammern auf Englisch. Sie können je nach Claude-Version leicht anders heißen.

1. Öffne [claude.ai](https://claude.ai) und melde dich an.
2. Öffne **Anpassen** (Customize) und dort **Connectors**.
3. Klicke auf **+ Hinzufügen** (+ Add) und dann auf **Benutzerdefinierten Connector hinzufügen** (Add custom connector).
4. Gib als Name `Snacklist` ein und als URL:

   ```text
   https://mcp.snacklist.app
   ```

   Lass die erweiterten Einstellungen (OAuth Client ID und Secret) leer.
5. Klicke auf **Hinzufügen** (Add).

## Schritt 2: Verbinden und erlauben

1. Klicke in der Liste der Connectors bei **Snacklist** auf **Verbinden** (Connect). Ein neues Fenster öffnet Snacklist.
2. Melde dich an, wenn Snacklist danach fragt, und zwar genauso wie in der App.
3. Snacklist fragt „Zugriff erlauben?“ und zeigt, was Claude darf: Einträge deiner Einkaufsliste lesen, hinzufügen, ändern, abhaken und löschen. Prüf, dass dein Haushalt dasteht, und klicke auf **Erlauben**.
4. Claude braucht danach noch ein paar Sekunden, bis die Verbindung steht. Das Fenster zeigt so lange „Fertig, du kannst zu Claude zurückkehren.“ oder bleibt bis zu zehn Sekunden leer. Warte, bis es sich schließt oder Claude den Connector als verbunden zeigt.

## Schritt 3: Ausprobieren

1. Starte in Claude einen neuen Chat.
2. Prüf im Menü für Tools und Connectors unter dem Eingabefeld, dass **Snacklist** eingeschaltet ist.
3. Schreib zum Beispiel „Was steht auf der Snacklist?“.
4. Beim ersten Mal fragt Claude, ob es Snacklist benutzen darf. Erlaube es einmal oder immer.

| Du schreibst | Was passiert |
| --- | --- |
| Setz Milch, 2 Gurken und Windeln Pampers Größe 3 auf die Snacklist. | Drei Einträge, jeder an seiner Stelle. Bei den Windeln stehen Marke „Pampers“ und „Größe 3“ dabei. |
| Was steht auf der Snacklist? | Claude zählt die offenen Einträge in der Reihenfolge eurer Liste auf und sagt, wie viele es sind. |
| Was brauche ich bei dm? | Alles für dm und alles ohne Laden, in der Reihenfolge von dm. |
| Hak Milch und Gurken ab. | Beide verschwinden von der Liste und stehen in der App unter „Zuletzt verwendet“. |
| Verschieb die Hafermilch zu dm. | Die Hafermilch steht jetzt bei dm. Snacklist merkt sich das für euren Haushalt, beim nächsten Mal landet sie gleich dort. |
| Mach bei den Gurken 3 draus. | Die Menge der Gurken steht jetzt auf 3. |
| Die Milch brauchen wir doch noch. | Die gerade abgehakte Milch steht wieder auf der Liste. |
| Streich den Sekt. | Der Sekt ist gelöscht. Was Snacklist über Sekt gelernt hat (zum Beispiel der Laden), bleibt. |
| Was kaufen wir sonst noch oft? | Was ihr oft kauft und gerade nicht auf der Liste steht, wie die Vorschläge in der App. |
| Was haben wir zuletzt gekauft? | Was zuletzt abgehakt wurde, wie „Zuletzt verwendet“ in der App. |

Was schon auf der Liste steht, kommt nicht doppelt dazu. Claude sagt dir dann, dass es schon draufsteht. Snacklist sortiert deutsche Namen am besten ein. Häufige englische Wörter kennt es auch.

> **Was Claude sieht**
>
> - Claude sieht nur eure Einkaufsliste: Einträge und Läden. Dein Passwort bekommt Claude nicht.
> - Was du Claude schreibst und was Snacklist antwortet, verarbeitet Anthropic nach seinen eigenen Datenschutzbestimmungen.
> - Alles Weitere steht in der [Datenschutzerklärung](/datenschutz) unter „Siri, Alexa und KI-Assistenten“.

## Wenn es nicht klappt

| Was passiert | Woran es liegt | Was hilft |
| --- | --- | --- |
| Nach **Erlauben** bleibt das Fenster ein paar Sekunden leer. | Claude schließt die Verbindung auf seiner Seite ab. | Warte bis zu zehn Sekunden. Zeigt Claude den Connector danach nicht als verbunden, klicke noch einmal auf **Verbinden**. |
| „Diese Anfrage ist ungültig oder abgelaufen. Starte die Verbindung in deiner App neu.“ | Die Anfrage von Claude ist ein paar Minuten alt oder wurde schon benutzt. | Klicke in Claude noch einmal auf **Verbinden**. |
| Claude sagt, es kann nicht auf Snacklist zugreifen. | Snacklist ist in diesem Chat ausgeschaltet. | Schalte **Snacklist** im Menü für Tools und Connectors ein. |
| Claude findet einen Eintrag nicht. | Der Name passt auf mehrere Einträge oder auf keinen. | Schreib den Namen so, wie er in der App steht. Claude bekommt die passenden Namen zur Auswahl. |
| Ein Eintrag steht im falschen Laden. | Snacklist hat den Eintrag einem anderen Laden zugeordnet. | Schreib Claude zum Beispiel „Verschieb Feta zum Wochenmarkt“. Snacklist merkt sich das für euren Haushalt. |

## Claude wieder trennen

Du hast zwei Möglichkeiten. Jede beendet die Verbindung sofort:

- **In Snacklist:** Tippe auf **Mehr** und dann auf **Zugänge**. Tippe unter **Verbundene Apps** neben **Claude** auf das Symbol zum Trennen und bestätige mit **Trennen**.
- **In Claude:** Öffne **Anpassen** (Customize) → **Connectors** und klicke bei **Snacklist** auf **Entfernen** (Remove) oder im Drei-Punkte-Menü auf Entfernen.

## Für Fortgeschrittene: Claude Code und Codex

**Claude Code** verbindet sich mit einem Befehl. Danach in Claude Code `/mcp` aufrufen und **Authenticate** wählen. Es öffnet sich dieselbe Seite „Zugriff erlauben?“.

```bash
claude mcp add --transport http snacklist https://mcp.snacklist.app
```

**Codex** (CLI und IDE-Erweiterung teilen sich `~/.codex/config.toml`) funktioniert genauso, ist aber kein offiziell unterstützter Weg:

```toml
[mcp_servers.snacklist]
url = "https://mcp.snacklist.app"
```

```bash
codex mcp login snacklist
```

::: until unified-keys-guides
Für Skripte und Programme ohne Anmeldung erstellst du in der App unter **Mehr** → **Zugänge** → **Token erstellen** einen Zugriffstoken. Er wird nur einmal angezeigt. Schick ihn als `Authorization: Bearer fgp_…` mit.
:::

::: once unified-keys-guides
Für Skripte und Programme ohne Anmeldung erstellst du in der App unter **Mehr** → **Zugänge** → **Schlüssel erstellen** einen Zugriffsschlüssel. Wähle **Lesen und schreiben**, wenn das Programm die Liste ändern soll. Er wird nur einmal angezeigt. Schick ihn als `Authorization: Bearer fgp_…` mit. Derselbe Schlüssel funktioniert auch für die Snacklist-API.
:::

Fragen oder Probleme? Schreib mir in der App über **Mehr** → **Feedback & Ideen**.
