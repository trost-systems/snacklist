# Snacklist feature map

This directory is the maintained record of what Snacklist does today, one file per user-facing feature. Agents use it to verify behavior on the web build with the verify-snacklist skill. Writers use [FEATURES-FOR-WRITERS.md](./FEATURES-FOR-WRITERS.md), the plain-language version for emails, site copy and instructions. A PR that changes user-facing behavior updates the feature file and FEATURES-FOR-WRITERS.md (including its last-verified line) in the same PR.

## Baseline preconditions

- Your checkout's `supabase/config.toml` has your job's port block and project id (local only, skip-worktree; COORDINATION.md). Helpers refuse the canonical 543xx block.
- `helpers/launch.sh` printed `READY http://127.0.0.1:<prefix>81 run=<run>`. The stack runs with every migration applied, the release web build of this checkout is served there, and the run seeded the `demo-familie` scenario.
- `helpers/doctor.sh` exits 0.
- Baseline household „Familie Brandt“: members Mia, Noah and Ida Brandt (`member(inst, 'mia' | 'noah' | 'ida')` in `helpers/lib.mjs`, emails `<handle>.<run>@fg-test.invalid`, passwords only in the run file `~/.cache/verify-snacklist/<prefix>/fg/runs/<run>.json`, mode 600). No stores (since job 64 a household starts without one), and the 11 seeded categories. A recipe that needs stores adds them as the app does, `const mia = member(inst, 'mia'); await (await apiAs(inst, mia)).rpc('add_store', { p_household: mia.householdId, p_name: 'Supermarkt' })`: generic names (Supermarkt, Drogerie, Bäckerei, Wochenmarkt) for any store, dm, Lidl or Edeka only for chain behaviour (walk orders, brand defaults). 15 open items, none tagged to a store: „6× Bananen“, „1 kg Äpfel“, „4× Brötchen“, „2× Vollmilch“, Butter, Nudeln, Reis, Schokolade, Mineralwasser, Apfelsaft, Erbsen, Spülmittel, Müllbeutel, Zahnpasta, Duschgel. No purchase history, so nothing is due yet.
- English: `launch.sh --scenario demo-family-en` („Brandt family“, English item names). The app follows the browser locale while its language is „Wie Gerät“; `openApp(inst, { lang: 'en' })` sets `en-US`.
- Other states (heavy history with due items, many stores, a pending invite, a user without a household): `launch.sh --scenario <name>` with any `test/fixtures/scenarios/` file (`docs/TEST_FIXTURES.md`).
- A new install is asked the analytics question after sign-in. `signIn` in `helpers/lib.mjs` declines it and dismisses the „Erste Schritte“ card („Erste Schritte ausblenden“, job 168b).
- Never drive an instance this run did not start, another job's stack, or the hosted project.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise. `launch.sh --fresh` reseeds the baseline (new run, old run torn down).
- Find widgets by ARIA role and accessible name. Semantics are on in the web build. Rows, chips and menu entries are buttons named by their label; a hint is the element's `aria-description`, not part of the name (a store detail's category row is named "Kühlregal", its place „2 von 11“ is the description; „Ohne Laden“ on Läden is just "Ohne Laden" since job 148), so match names with a start-anchored regex.
- Labels in recipes are German (the browser locale is de-DE). For English runs, look labels up by ARB key with `labels('en')` instead of translating by hand.
- Type with `typeInto` (focus first, then insert text). Synthetic key events drop umlauts.
- A snackbar with an action keeps its text in a group's aria-label: find it with `actionSnackBar(page, '<text>')` (e2e helpers). `getByText` hits the screen-reader copy that the engine soon clears.
- The list builds rows lazily. Scroll with `reveal` (e2e helpers) or the mouse wheel before looking for a row far down.
- Set preconditions through the API (`apiAs` in `helpers/lib.mjs`) or `scripts/fg db query --write`. Prove the behavior under test only through the UI.
- Helper names in recipes (`addField`, `itemRow`, `addSheet`, `editSheet`, `openTab`, `openMore`, `tick`, `putBack`, `openEdit`, `pickInSheet`, `saveEdit`, `cutOff`, `signUpWithHousehold`, `createInviteCode`, `joinWithCode`, `answerConsent`) come from `e2e/tests/helpers.ts`. Journeys use the JS copies in `helpers/lib.mjs` where they exist.
- Each file names the e2e specs that already cover the feature. Run them with `scripts/verify.sh --only e2e -- tests/<file>`. That builds the e2e web build (`app/config/e2e.json`, which turns on LEGAL_DRAFTS, HOUSEHOLD_ARCHIVE and INTEGRATION_LOCK) and runs under `/tmp/fg-e2e.lock`.

## Proof and skip reporting

- Capture the user action and the resulting state: `capture(page, dir, name)` before and after (PNG plus ARIA snapshot), and the context's video across the action.
- A mutation needs a second, read-only view of the stored value: `apiAs(inst, user)` as a member, or a second browser context for sync.
- Record the feature id and the entry point with every artifact. `drive.sh` names the evidence dir `<run>/<feature-id>-<time>/`.
- Report an unreachable path with the command you attempted and the unmet precondition. Native iOS and Android, Siri on a device and Alexa on a device cannot be driven on a box without simulators. Their files say what the server side offers instead.
- Do not report a skipped entry point as verified through a different path.
- A claim nobody could prove is marked `unverified` with its reason, in the feature file and in FEATURES-FOR-WRITERS.md.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point, with the exact labels as „DE“ / "EN".
3. `Driving it with Playwright` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact locator or command and its observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run, gated behavior, and unverified claims with their reason.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands and observable proof. Feature ids are the file names; they are stable, so rename one only together with every link to it.

## Features

Getting started

- [sign-in](./sign-in.md): email and password, sign-up with email confirmation, the sign-in link by email (no code), Google and Apple, sign-out.
- [privacy-consent](./privacy-consent.md): the analytics question after the first sign-in on a device, its exact text, and changing it later under Mehr → Nutzungsdaten.
- [onboarding](./onboarding.md): the guided start signed out („Los geht's“, „Mit wem“, name, stores, „Was fehlt gerade?“, the account last, several invites with a live „beigetreten“), kept on the device until the sign-up; „Willkommen bei Snacklist“ and joining with a code.
- [household-invites](./household-invites.md): inviting by code or link (a person link: 7 days, one person; a group link: 30 days, up to 50 people, admins only), the join page, roles and removing members, join approval, joining, revoking, switching households.
- [lists-and-claims](./lists-and-claims.md): several lists per household (tabs, moving items, the household page's „Listen“) and „Ich bringe das“ claims (job 169b K, L).
- [app-links](./app-links.md): app.snacklist.app and app.hummlist.com links to the list, the add sheet, a store, More's pages and invites; they open the installed app or the web app and wait through sign-in.

The website

- [waitlist](./waitlist.md): snacklist.app's waitlist form, confirmation and unsubscribe pages, the FAQ and support page (live since 5 Nov; sign-ups need production settings).

The list

- [quick-add](./quick-add.md): the add bar and add sheet, suggestions and their sources, quantities, tap or Enter to add, store and category chips, the added note with undo, duplicates.
- [usuals](./usuals.md): „Wieder fällig“ suggestions for items the household buys regularly.
- [dictation](./dictation.md): the microphone in the add bar (iOS and Android apps only).
- [tick-and-undo](./tick-and-undo.md): a tap ticks an item off, „Zuletzt verwendet“ and putting items back, which actions have an undo.
- [edit-item](./edit-item.md): the edit sheet (name, brand, details, quantity, store, category), deleting with undo.
- [tips](./tips.md): the dismissible tip card at the top of the List tab, one tip at a time from a typed queue (job 80).
- [classifier](./classifier.md): the automatic category for every new item, learning from moves, spelling variants and synonyms.
- [categories](./categories.md): Liste → „Anpassen“ → „Ohne Laden“ (and every store's details): add, rename, delete, reorder; the 11 seeded categories.
- [stores-walk-order](./stores-walk-order.md): store sections and category dividers in walk order, nothing on the list drags, a tap on a store divider folds it (a hold does nothing), the stores screen under Liste → „Anpassen“ and a store's details (add, rename, delete, reorder), adding a store from the store chip, item→store memory.
- [prices](./prices.md): behind the flag `prices-and-trip-total` (off): a price chip on each row and its editor (Gesamt or pro Stück/kg/l, the scale weight), „Summe <Laden>“ per store section, „Einkaufssumme“ under the list, the household's „Währung“; Free, live for the household.
- [live-sync](./live-sync.md): members see each other's changes live; „N neu von <Name>“ and the sync icon.
- [offline](./offline.md): what works without a connection, what waits, and the messages.
- [grocery-log](./grocery-log.md): behind the flag `grocery-log` (not public): the „Verlauf“ tab with trips by date under a month calendar with store dots, or by store, one toggle; „Einkauf eintragen“ by hand; the list's card after a store's section is ticked off; Free sees 4 weeks.
- [list-declutter](./list-declutter.md): behind the flag `list-declutter` (off): one switcher for household and list in a see-through header, the total as a row of the list, and the household sheet with a page per household (its lists, „Einladen“, the members row) and a members page; long-press reorder of lists and households.
- [trip-mode](./trip-mode.md): behind the flag `trip-mode` (not public): „Kaufst du gerade ein?“ after a tick, the running trip's strip with stopwatch, pause and „Beenden“, its own pause after 45 min and end after 4 h at the last tick, the summary „Geplant und gekauft“ per store with planned and paid prices (Premium; Free sees a locked card), Verlauf trips per store, Mehr › „Einkauf starten“.

Settings, help and account

- [theme](./theme.md): light, dark or device theme under Mehr → Einstellungen.
- [language](./language.md): German, English or the device's language, and which texts stay German.
- [feedback](./feedback.md): Mehr → „Feedback senden“.
- [rate-snacklist](./rate-snacklist.md): Mehr → „Snacklist bewerten“ (iPhone and Android apps) and the system rating dialog after a completed trip in public store builds. Evidence from before the sweep is filed under the old id `rate-hummlist`.
- [more-help](./more-help.md): the tabs, every Mehr entry in order, help and contact, guides on snacklist.app (Siri, Alexa, Claude), the Nutzungsdaten page and the legal rows (imprint, privacy policy, terms, licenses), version.
- [account-deletion](./account-deletion.md): Mehr → Konto: data export, account deletion, deleting single data without deleting the account.

Connections and Premium

- [ai-assistants](./ai-assistants.md): connecting an AI assistant through MCP (https://mcp.snacklist.app), the consent page, Mehr → Zugänge with access tokens and connected apps.
- [siri](./siri.md): the Siri Shortcut today, native Siri (built, announcement held), Siri keys.
- [home-widgets](./home-widgets.md): the iPhone and Android Home Screen widget (built, announcement held).
- [alexa](./alexa.md): the Alexa skill (beta, not certified): linking, adding and reading by voice.
- [premium](./premium.md): what users see of Snacklist Premium while it is not on sale.

Clips of these features for emails and the site: the snacklist-howto-clips skill (`.cursor/skills/snacklist-howto-clips/`).
