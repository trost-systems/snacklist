# Review test cases (5 positive, 3 negative)

Run against the reviewer account (`reviewer-account.md`): household "Haushalt Beispiel (Testkonto)",
stores dm, Lidl, Edeka, IKEA, 11 sample items. Tool names are the server's; their titles are German.
Expected results are what the server does by its code and tests; they were not run through ChatGPT
or Claude from this box. Whoever submits runs each once and corrects any line that differs.

Seed list (store: items): Lidl: Milch, Bananen, Haferflocken. dm: Zahnpasta, Shampoo, Taschentücher.
Edeka: Nudeln, Tomaten, Brot. IKEA: Kerzen, Bilderrahmen.

## Positive

| # | Prompt | Tools | Expected |
| --- | --- | --- | --- |
| P1 | `What is on my Snacklist?` | `list_items` | The 11 open items grouped by store, each with its section; `counts.open` is 11. No change. |
| P2 | `Add 2 cucumbers, a pack of Pampers size 3 and toilet paper to my list.` | `add_items` | Three new entries: "Gurken" quantity 2, "Windeln" brand Pampers properties "Größe 3", "Toilettenpapier". Each has a section; the reply lists them. Running it again reports them under `alreadyOnList` and adds nothing. |
| P3 | `I bought the milk and the bananas. Tick them off.` | `tick_items` | Both leave the open list; `notFound` is empty. `list_recent` shows them. |
| P4 | `Move the candles to the dm store.` | `move_item` | "Kerzen" now has store dm. A following `list_items` with store dm includes it. |
| P5 | `What do we usually buy that is not on the list?` | `suggest_items`, `list_recent` | A short list of suggestions (may be few on a fresh account). No change to the list. |

## Negative

| # | Prompt | Expected |
| --- | --- | --- |
| N1 | `Order everything on my list for delivery from Lidl.` | No tool can do it. The assistant says it cannot order or pay; the list is unchanged. The connector has no commerce tool. |
| N2 | `Show me the shopping list of the household "Müller".` | `list_items` with `household: "Müller"` returns a tool error "Kein Haushalt "Müller". Deine Haushalte: Haushalt Beispiel (Testkonto)". Nothing is read from another household. (That is the text an OAuth token gets, which reviewers use. A personal access token, e.g. with `scripts/mcp-smoke.sh`, gets "Dieser Zugriffstoken gilt nur für den Haushalt …" instead.) |
| N3 | `Tick off the unicorn costume.` | `tick_items` reports it under `notFound`; nothing changes. |

A fourth check for submitters, not one of the eight: without signing in, the server answers `401`
with the metadata link, and the client starts OAuth (`scripts/mcp-smoke.sh https://mcp.snacklist.app`).
