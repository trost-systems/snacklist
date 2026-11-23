# Claude directory listing

Portal: `https://claude.ai/directory/manage`, Submit new, "MCP connector". Fields in the portal's
order. Limits are from the portal as read on 2026-11-22; recheck on the day.

| Field | Value |
| --- | --- |
| Server URL | `https://mcp.snacklist.app` |
| Name (max 100) | `Snacklist` |
| One-liner (max 200) | `Your household's shared shopping list. Add things, tick them off and see what's still missing, in the right order for the store.` (131) |
| Categories (1 to 5) | Productivity; Lifestyle (pick the closest the portal offers) |
| URL slug (permanent) | `snacklist` |
| Documentation URL | `https://snacklist.app/en/guides/claude` |
| Privacy policy URL | `https://snacklist.app/en/privacy` |
| Support contact | `https://snacklist.app/en/support` |
| Icon | the app icon, square PNG from `marketing/store-screenshots/` (the icon the script writes; Ops exports it) |
| Company | Peter Trost, sole proprietor; website `https://snacklist.app`; contact as on the imprint |

## Description (EN, max 2000)

```
Snacklist is the shared shopping list of one household. With this connector, Claude can read your
list and change it, so you can plan the weekly shop in a conversation.

What Claude can do:
- Show what is on the list, by store or by section, in the order you walk through the store.
- Add items. "2 cucumbers, Pampers size 3 and toilet paper" becomes three entries with the right
  quantity and brand, each sorted into its section and store.
- Tick items off, put them back, change them or delete them.
- Move an item to another section or store. Snacklist remembers the correction for next time.
- Suggest what your household buys often, and show what was ticked off recently.
- Work with several households, and with several lists once your account has them.

Everything you change appears at once on the phones of everyone in your household.

Sign in with your Snacklist account when Claude asks. You see what Claude may do and allow or
decline it. You can disconnect it any time in the Snacklist app under More, Access.

Snacklist is available in German and English. The connector's tool names and descriptions are in
German; Claude answers in your language.
```

German version (if the form takes a second language):

```
Snacklist ist die gemeinsame Einkaufsliste eines Haushalts. Mit diesem Connector kann Claude deine
Liste lesen und ändern, du planst den Wocheneinkauf also im Gespräch.

Das kann Claude:
- Zeigen, was auf der Liste steht, nach Laden oder Gang, in der Reihenfolge, in der du durch den
  Laden gehst.
- Einträge hinzufügen. „2 Gurken, Pampers Größe 3 und Klopapier“ werden drei Einträge mit Menge
  und Marke, jeder im richtigen Gang und Laden.
- Einträge abhaken, zurücklegen, ändern oder löschen.
- Einen Eintrag in einen anderen Gang oder Laden verschieben. Snacklist merkt sich die Korrektur.
- Vorschläge machen, was dein Haushalt oft kauft, und zeigen, was zuletzt abgehakt wurde.
- Mit mehreren Haushalten und, wenn dein Konto sie hat, mehreren Listen arbeiten.

Jede Änderung erscheint sofort bei allen in deinem Haushalt.

Melde dich mit deinem Snacklist-Konto an, wenn Claude fragt. Du siehst, was Claude darf, und
erlaubst oder lehnst ab. Trennen kannst du jederzeit in der Snacklist-App unter Mehr, Zugänge.
```

German one-liner: `Die gemeinsame Einkaufsliste deines Haushalts: Einträge hinzufügen, abhaken und sehen, was noch fehlt, in der Reihenfolge des Ladens.`

## Use cases (portal field)

1. "Add what I need for pancakes to the Snacklist."
2. "What is still on the list for Lidl?"
3. "I bought the milk and the bananas, tick them off."
4. "Move the candles to dm."
5. "What do we usually buy that is not on the list?"

## What users need first

A Snacklist account (iOS, Android or web at `https://app.snacklist.app`) and a household with
a list. No other setup. Do not mention plans here.

## Authentication and data handling (portal fields)

- Authentication: OAuth 2.1 with PKCE and dynamic client registration; details in `README.md`.
- Data: the connector reads and changes the user's shopping list (item names, quantities, brands,
  stores, sections, household and list names). It collects no conversation data and stores nothing
  Claude says. Free-text item names are the user's own.

## Test and launch

The portal asks to confirm that every tool was run. Run each shown tool once against the reviewer
account (`reviewer-account.md`), with the server switch `mcp_lists_stores` **off**, so 17 tools show. The five list and store
tools stay switched off until Legal's privacy section 7 text exists (`docs/MCP.md`); turn the
switch on only after that, and before the portal syncs the tools.

## Compliance acknowledgments

Seven checkboxes in the portal (guidelines, first-party API use, financial transactions, AI media
generation, prompt injection, conversation data collection, public documentation). The honest
answers: first-party API only; no financial transactions; no AI media generation; tool results are
the user's list, which can contain text a household member typed (note in the prompt-injection field);
no conversation data collected; the documentation is public at the URLs above.

## Review

Community listing follows automatically after the scan. Verified review: if Anthropic emails for a
test account, send the credentials by email only, never in the portal (`reviewer-account.md`).
