# Family Groceries verification map

The current feature map is `.cursor/skills/verify-hummlist/features/`.

This directory is the maintained source for verifying the user-facing behavior of Family Groceries. Read this index before driving the app, then use the matching feature file as the recipe. Each recipe drives the real app through `fg` (run it as `scripts/fg` from the repo root).

## Baseline preconditions

- Set your port block: `export FG_PORT_PREFIX=<prefix>` (548 for job 05; never 543 on the shared box, which belongs to job 1).
- Run `fg up --clients peter,lea`. It exits 0 when the stack, the seed and both apps are usable.
- Run `fg doctor` and require `"ok": true` (exit code 0). On a failure it prints `"ok": false` with `error.code` `unhealthy` and every check, each failed one with its `fix`.
- Sign both apps in: `fg login peter` and `fg login lea`. Both users are in the household "Familie Test", password `test-password-123`.
- The seed has no items. Recipes create their own and mark them bought afterwards.
- The seed has no stores either: a household starts without one (job 64). A recipe that needs stores adds them first, in its order, through the app's RPC: `fg db query "select add_store(id, n) from households, unnest(array['dm', 'Lidl', 'Edeka']) n where name = 'Familie Test'" --as peter --write` (`add_store` is idempotent, so a rerun adds nothing). dm, Lidl and Edeka become those chains (researched walk orders, brand defaults such as Pampers → dm): add them only where a recipe checks that, and generic names (Supermarkt, Drogerie, Bäckerei, Wochenmarkt) otherwise.
- For any other state (long lists, weeks of history with usuals, many stores, three members mid-shop, awkward names, a pending invite, a user without a household), seed a scenario instead: `fg scenario list`, `fg seed <scenario>`, then `--as <run>:<handle>` on any user flag, and `fg teardown <run>` at the end. Scenario runs never reset the database. See `docs/TEST_FIXTURES.md`.
- Sync between two or three members is driven on web with `fg sync <scenario> --clients 2|3 --script <file>`, which captures frames, videos and latencies by itself (see [Live sync](./live-sync.md)).
- Never drive an instance that this run did not start.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise. `fg up --fresh` restores the baseline: database reset and both users reseeded. Then `fg login` each client again.
- Prefer ValueKeys (`--key`), then field labels (`--label`), tooltips (`--tooltip`), exact text (`--text`), and coordinates last.
- A list row is one tap target (a checkbox to screen readers, job 57): `fg tap --text "<row text>"` ticks it, `fg marionette -- long-press --text "<row text>"` opens its edit sheet, whose chips move it (the list has no drag since job 78). The row text reads the quantity first ("2 l Milch", "6× Bananen"), a row without a quantity the name. To act on something inside a row, scope to it: `--row "<row text>"`.
- Seeded scenario runs share the stack with the baseline household. Read with `--as peter` (or `--as <run>:<handle>`) so a query sees one household, and filter `--write` preconditions by household.
- Wait for state with `fg wait`. Never use sleep.
- `fg type --key add-item-field --input <item> --submit` adds through the add sheet, which stays open after the add: wait for its note (`fg wait --contains "Hinzugefügt: <item>"`), then `fg press escape` before you check or touch the list. While the sheet is open, `fg find` and `fg wait` don't see the list's rows, and the tabs don't take taps.
- Screens of the More tab open from `fg tap --key tab-more`. The tab reopens the page it last showed (Konto after an `acct-*` recipe, Zugänge after an `mcp-*` one): when `fg wait --key more-screen` times out, tap `tab-more` once more, which goes to the More list. More is a lazy list: run `fg marionette -- scroll-to --key <entry>` before tapping an entry below the fold (from `more-settings` down to `more-sign-out` on a 412×892 client).
- `fg find` and `fg wait` see only widgets the list has built, so a row below the fold doesn't exist for them. Keep the list short (mark earlier items bought with `fg db query --write`) or bring the row in with `fg marionette -- scroll-to --text <name>`.
- Treat every command as literal. Keep quoted names, umlauts and flags unchanged.
- Set preconditions with `fg db query --write` or `fg peer`. Prove the behavior under test only through the app UI.

## Proof and skip reporting

- Capture the user action and the resulting state: a screenshot before and after, and `fg record start/stop` across the action.
- A mutation needs a second, read-only view of the stored value: `fg db query`, or the other client.
- Sync proofs show the change on the client that did not act.
- Record the feature ID and the entry point with every artifact (use them in `--name`).
- Report an unreachable path with the command you attempted and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with fg` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands and observable proof.

## Features

- [List and walk order](./list-walk-order.md) covers design H's list: store sections and category dividers, walk order, a tap that ticks with undo, a hold that edits (nothing drags), a tap on a store divider that folds it (a hold on a divider does nothing), and the explainer card kept per device, and a partner's adds and moves.
- [Quick add](./quick-add.md) covers the add bar and the add sheet: autofocus on desktop, rows with their sources, Enter for the first row, store and category chips, the added note with undo, due usuals, closing, and tick with undo and re-add from history.
- [Shell and More](./shell-more.md) covers the tabs (Liste, Mehr; a rail from 840 px), every entry of the More tab, the Nutzungsdaten page, the Rechtliches rows (imprint, privacy policy, terms, licenses) (and how to read them on a host without a browser).
- [Settings](./settings.md) covers Mehr → Einstellungen: light, dark or the device's theme and the language list, both applied at once and kept on the device across restarts and sign-out.
- [Edit an item](./edit-item.md) covers the edit sheet (Bezeichnung, Marke, Eigenschaften, Menge with −/+, store and category chips, Fertig saving only changes, Abbrechen discarding), the row's "Marke · Eigenschaften" line, and how Siri and MCP entries are split into those fields.
- [Live sync](./live-sync.md) covers two members seeing each other's adds and ticks without reloading.
- [Sign-in](./auth.md) covers email and password, sign-up, magic link through the local inbox, sign-out, and the Google and Apple buttons (web build only).
- [Household](./household.md) covers creating a household, inviting by code and joining with it, the invite list and revoking.
- [Onboarding](./onboarding.md) covers the steps after sign-in: create or join, invite the partner, the pending invite link, errors and events.
- [Classifier](./classifier.md) covers automatic categories for new items, moving an item to another category, and learning from the move.
- [Stores](./stores.md) covers stores as list sections in their own category order, "Ohne Laden", adding your own store (store chip, Liste → Anpassen, onboarding) and renaming or deleting it, tagging items to a store in the edit sheet and remembering it, and each store's details (from Anpassen).
- [Categories](./categories.md) covers Liste → Anpassen → Ohne Laden: adding, renaming, deleting and reordering categories.
- [Analytics and error tracking](./analytics.md) covers the analytics question after the first sign-in (before onboarding or the list), what is sent after a yes and that nothing is sent after a no, the switch under Mehr → Nutzungsdaten, the internal device mark with "Testfehler senden", and error tracking from the app and the edge functions.
- [Feedback](./feedback.md) covers Mehr → Feedback senden: the note with optional kind and contact, what is attached, the length limits, the error with Retry, and the row in `public.feedback` (insert-only).
- [MCP access](./mcp-access.md) covers the consent page an AI app opens (web build only) and Mehr → Zugänge: the MCP URL, creating and revoking access tokens, and disconnecting OAuth apps, each cut off on the next request.
- [Home Screen widgets](./home-widgets.md) covers the iOS and Android widgets: what the app writes for them and when, the small and medium layouts, the prompts, and the taps that open the list or the add sheet (tests and CI builds only; no device here).
- [Voice](./voice.md) covers the Siri endpoint (JSON and the spoken text format, duplicates, German errors, 30-item limit, personal access tokens) and the app's on-device microphone.
- [Alexa skill](./alexa.md) covers adding and reading the list by voice through the Alexa skill "Hummlist": read-back, duplicates, the one re-prompt, account linking through the consent page, revocation under Zugänge or by disabling the skill, and refused unsigned or stale requests (locally through `scripts/alexa-say.sh`).
- [Hummlist Premium](./purchases.md) covers Mehr → Hummlist Premium (not on sale yet): the yearly plan and Lifetime, gifted (promotional) Premium, the store price, buying and restoring through the app's fake store and the real verification, the household's unlock live on both clients, pending, cancel, error, not-available and offline states, a killed app, refunds, and the web's no-sale page.
- [Account](./account.md) covers Mehr → Konto: exporting your data as JSON and deleting your account, with the household kept for the other members or deleted with the last one.
- [Hosted backend](./hosted-backend.md) covers the hosted project: the health check that reads Postgres, the smoke test after every deploy, the daily keepalive, nightly encrypted backups with their restore drill, and rolling edge functions back.
- [Help page and legal links](./legal.md) covers the help and contact page on hummlist.com (published since 2026-10-30), the More entry that opens it, and the site's draft mechanism.
- [Guides on hummlist.com](./guides.md) covers the public guides site: the German and English indexes, the Siri, Alexa and Claude guides (the widget guide is a draft), the language redirect on `/` and the links between translations.
- [Hosted web app](./web-hosting.md) covers the production web app on Vercel: deep links, cache headers, the Google and Apple sign-in pages, and the build Vercel runs.
