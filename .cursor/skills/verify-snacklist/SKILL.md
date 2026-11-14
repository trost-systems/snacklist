---
name: verify-snacklist
description: "Drive the real Snacklist app (the Flutter web release build in Chromium via Playwright) against this checkout's local Supabase stack with a seeded demo household, and prove behavior with screenshots, ARIA snapshots, video and database state. Use before claiming a Snacklist feature works, to reproduce a bug, to capture PR evidence, or to look up what the app does today (features/, and features/FEATURES-FOR-WRITERS.md for copy). Also when a scripts/verify.sh gate fails: how to read its verdict line, and the recipes for failures seen before (recipes/)."
---

# Verify Snacklist

The surface is the web build users get at app.snacklist.app and app.hummlist.com: release mode, production defines, wasm, served under the production CSP. It runs against your checkout's own Supabase stack and is driven by Playwright from `e2e/node_modules`. Everything a user can do is mapped in [`features/`](features/README.md), one file per feature. Read the matching file before you drive.

Other surfaces:

| Surface | Drivable here | How |
| --- | --- | --- |
| iOS, Android apps | No simulators or emulators on the build boxes | The Linux desktop debug app through `scripts/fg` (verify-family-groceries skill, `FG_SURFACE=linux`). Native-only behavior (microphone, Siri intents, store purchases, keyboards) stays unverified |
| Siri | Server side only | `POST /functions/v1/voice` with a Siri key, as `e2e/tests/voice.spec.ts` does (`features/siri.md`) |
| Alexa (beta) | Server side only | Signed requests through `scripts/alexa-say.sh` and `e2e/tests/alexa-helpers.ts` (`features/alexa.md`) |
| MCP / AI assistants | Yes, over HTTP | Local `/functions/v1/mcp` with an access key or OAuth (`e2e/tests/mcp-helpers.ts`, `features/ai-assistants.md`) |

Drive Siri, Alexa and MCP only against a local test household. Never against the hosted project or a real user's household.

One instance per checkout: the ports come from your `supabase/config.toml` port block (`<prefix>21` API, `<prefix>81` web). Two checkouts with different blocks run side by side. Never drive another checkout's instance.

## Launch

```bash
.cursor/skills/verify-snacklist/helpers/launch.sh                      # demo-familie (German)
.cursor/skills/verify-snacklist/helpers/launch.sh --scenario demo-family-en --fresh   # English household
```

It goes from nothing to a signed-in household and is idempotent.

1. It starts the stack (`supabase start`, which applies every migration to an empty database) unless it already runs.
2. It builds the release web app when `app/` or CI's Flutter version (`FLUTTER_VERSION` in `.github/workflows/ci.yml`) changed. It refuses to build with any other Flutter version, as the gates do: `scripts/lib.sh` puts `FLUTTER_DIR` first on PATH, else `~/flutter-<that version>` when it exists, else `~/flutter`. The build takes about 80 s; a rerun with no change takes about 5 s.
3. It serves the build on `http://127.0.0.1:<prefix>81` with `e2e/serve.mjs`.
4. It seeds the scenario with `scripts/fg seed`.
5. It signs the first member in through the login screen, reopens the app, and checks that the add field has focus and a seeded item shows.

The ready signal is the last line: `READY http://127.0.0.1:<prefix>81 run=<run>`. A failure exits non-zero and names the log to read.

`--fresh` replaces the seeded run. `--rebuild` forces the build. State lives in `~/.cache/verify-snacklist/<prefix>/`: `instance.json`, the `fg/runs/<run>.json` credentials (mode 600; never paste them) and the build and serve logs.

The build has production defines with two local swaps. Google sign-in points at a fake client id. PostHog points at the e2e stand-in host, `https://posthog.invalid`, so nothing reaches a real analytics project. It has none of the e2e-only switches (LEGAL_DRAFTS, HOUSEHOLD_ARCHIVE, INTEGRATION_LOCK), so it shows what a normal user sees. To build with more defines, set `VH_DEFINES` to space-separated `NAME=value` pairs for `launch.sh`, for example `VH_DEFINES="FLAGS_ON=public-api INTEGRATION_LOCK=true"`. `FLAGS_ON` turns PostHog feature flags on in a build that cannot reach PostHog (docs/ANALYTICS.md, "Feature flags"). The build stamp includes them, so the next plain `launch.sh` rebuilds without them. Export the same `VH_DEFINES` for `doctor.sh` and `drive.sh` too: without it they call the build stale and `drive.sh` stops with "doctor fails".

Teardown is `helpers/cleanup.sh` (see Cleanup).

## Doctor

```bash
.cursor/skills/verify-snacklist/helpers/doctor.sh
```

Read-only. It prints one line per check, `ok` or `FAIL ... -> <fix>`:

- The instance record exists.
- The stack is up, and the migrations applied equal the files in `supabase/migrations`.
- The functions answer `/health`.
- The process on the web port is the server `launch.sh` started.
- The build matches `app/` at HEAD plus local edits.
- The app and its `FontManifest.json` are served.
- The run has credentials.
- The first member signs in and belongs to the seeded household.

It exits 0 only when every check passes. Run it first, and whenever a drive fails strangely. `drive.sh` runs it too.

## Drive

```bash
.cursor/skills/verify-snacklist/helpers/drive.sh quick-add            # a scripted journey: PASS or FAIL: <reason>
.cursor/skills/verify-snacklist/helpers/drive.sh quick-add --lang en
.cursor/skills/verify-snacklist/helpers/drive.sh sign-in              # no journey yet: prints the feature's e2e specs (exit 3)
```

A journey is `journeys/<feature-id>.mjs`, a plain Node script on `helpers/lib.mjs`. To prove a feature without a journey, write one: copy `journeys/quick-add.mjs` and follow the steps of `features/<id>.md`. Commit it only if it is reusable. Building blocks from `helpers/lib.mjs`:

| Helper | Does |
| --- | --- |
| `instance()`, `member(inst, 'mia')` | The launched instance and a seeded member (`email`, `password`, `id`, `householdId`) |
| `openApp(inst, { lang, viewport, dpr, dark, videoDir })` | A fresh Chromium context on the build: `de-DE` or `en-US` locale, 390×844 at DPR 2 by default. Returns `{ browser, context, page, L, errors }` |
| `L(key, params)` / `labels(lang)` | UI text from `app/l10n/app_<lang>.arb` by key, so one script runs in both languages |
| `signIn(page, L, user)` | The login screen with email and password, declines the analytics question, dismisses the „Erste Schritte“ card |
| `addField`, `addSheet`, `itemRow(page, name)`, `openTab(page, L, 'tabMore')`, `headingAbove(page, row)` | Stable handles: the textbox „Was brauchst du?“, the group „Hinzufügen“, a row by item name, the tabs, the category heading above a row |
| `typeInto(field, text, { perKey })` | Focus, then insert (synthetic key events drop umlauts) |
| `apiAs(inst, user)` | supabase-js signed in as the member: the second view of stored state |
| `capture(page, dir, name)`, `logger(dir)` | PNG + ARIA snapshot, a timestamped journey log |

Find widgets by role and accessible name, never by coordinates. Semantics are on in the web build. A row's name is the item name, then the quantity. More's rows are named by their label alone (job 85: no hints). `helpers/lib.mjs` also has `reveal` (like the one in `e2e/tests/helpers.ts`: wheel a lazily built row fully into view, above the add bar and the tabs). Use it before clicking a row by position: Flutter keeps semantics nodes for rows below the screen, so Playwright calls them visible, and a click there lands on whatever is drawn at that spot. The richer TypeScript helpers (`tick`, `putBack`, `openEdit`, `openMore`, `actionSnackBar`, `cutOff`, `finger`) are in `e2e/tests/helpers.ts`. A feature's existing specs run with `scripts/verify.sh --only e2e -- tests/<spec>`. That is the e2e build under `/tmp/fg-e2e.lock`, not this instance.

Local Playwright here is one browser per journey. When you run the e2e suite yourself, use `flock /tmp/fg-e2e.lock` and `--workers=1`. Around `helpers/launch.sh` use `flock -o /tmp/fg-e2e.lock`: without `-o` the web server it leaves running inherits the lock and every other job's e2e waits until it stops (job 73).

## Evidence

`drive.sh` writes to `$VH_EVIDENCE_DIR/<run>/<feature-id>-<HHMMSS>/` (default `~/snacklist-evidence`; set `VH_EVIDENCE_DIR=/workspace/hummlist/research/<job>/evidence` on the Hetzner runner so the box gets a copy). The directory holds:

- `journey.log`, with UTC timestamps, the rows offered and the database row as JSON.
- `NN-<step>.png` and `.aria.txt` before and after each action, plus `99-failure.png` on a failure.
- The context's WebM video.

Proof standards:

- Drive the user path: the field, the row, the menu. Use the API (`apiAs`, `scripts/fg db query --write`) only to set up preconditions.
- Capture the action and the resulting state, not only the final screen.
- Check side effects with a second, read-only view: `apiAs` for rows, a second context for sync, Mailpit (`mailpitUrl` in `instance.json`) for mail.
- Name the entry point you proved. Report a skipped one as skipped.
- For a PR, copy the PNGs you embed to `docs/screenshots/<job>/`. The run directory stays where it is.

## Cleanup

```bash
.cursor/skills/verify-snacklist/helpers/cleanup.sh                 # run torn down, server stopped, stack stopped if launch.sh started it
.cursor/skills/verify-snacklist/helpers/cleanup.sh --keep-stack    # leave the stack up (it was yours already, or you go on)
.cursor/skills/verify-snacklist/helpers/cleanup.sh --purge-build   # also delete app/build/verify-snacklist-web (about 75 MB)
```

Cleanup does these things:

- It tears the seeded run down with `fg teardown`, which proves every leftover count is 0.
- It stops the web server by its recorded pid and command line, never by name.
- It stops the Supabase stack only if `instance.json` says `launch.sh` started it. Only your project id is stopped.
- It removes `instance.json`.

After `--keep-stack` the record is gone, so a later `cleanup.sh` no longer stops the stack: stop it yourself with `supabase stop --no-backup` from the repo root (your project only) when you are done.

It never touches `$VH_EVIDENCE_DIR`. Its last line names the evidence dir and how many files it holds.

## Gates

Driving the app proves a behavior. The gates decide whether a change may land: `scripts/verify.sh` runs the same `scripts/gates/<gate>.sh` scripts as CI. Neither stands in for the other. A journey that passes says nothing about a red gate, a green gate is not evidence that a feature works, and nothing else you can show (screenshots, a smaller diff, a review score) offsets a failed gate.

The loop after an edit:

1. Run the gates the change can break: `scripts/verify.sh --only lint,flutter` (comma-separated), one spec with `--only e2e -- tests/<spec>.spec.ts`. Before pushing, run `scripts/verify.sh` whole.
2. Read the last line. It is `[verify] passed: <gates>` or `[verify] FAILED: <gate> (exit <n>) after <s> s; its output: <file>`. The file holds that run's whole output: open it instead of running the gate again to see the error.
3. `seen before? <recipe>` on that line names a file in [`recipes/`](recipes/README.md): a failure that came back across jobs and whose cause is known. Run the recipe's Condition. The gate has failed either way; the recipe says where its verdict comes from instead.
4. `flake: <gate> had the other result (pass|fail) on this same tree at <time>` means the files git does not ignore are the same, so they are not the cause. Find what differs outside them (`docs/CI.md`, "The local loop", lists the causes found so far) and write it into the PR. A rerun that passes is a second observation, not a fix.
5. `<gate> has failed 3 runs in a row on this branch` means stop patching. Write down what the fixes assumed and test that assumption before a fourth.
6. Take a claim about gate time or flakiness from `scripts/verify.sh --history [<date>]`, which reads the ledger of every local gate run.

Never make a gate pass by skipping, loosening or deleting what it checks. No recipe does any of the three.

## Helpers

| Script | Invocation |
| --- | --- |
| `helpers/launch.sh` | `launch.sh [--scenario <name>] [--fresh] [--rebuild]`, ends with `READY <url> run=<run>` |
| `helpers/doctor.sh` | `doctor.sh`, exit 0 when healthy |
| `helpers/drive.sh` | `drive.sh <feature-id> [journey args]`, no id lists the ids |
| `helpers/cleanup.sh` | `cleanup.sh [--keep-stack] [--purge-build]` |
| `helpers/env.sh` | `source` it to get `VH_*` and fg's `FG_*` for this instance (then `scripts/fg db query "..." --as <run>:mia` works) |
| `helpers/lib.mjs` | `import { ... } from '<repo>/.cursor/skills/verify-snacklist/helpers/lib.mjs'` in a journey or clip script |
| `journeys/quick-add.mjs` | `drive.sh quick-add [--lang en] [--prefix Joghu]` |
| `journeys/tick-and-undo.mjs` | `drive.sh tick-and-undo [--lang en] [--item Butter]` |
| `journeys/ai-assistants.mjs` | `drive.sh ai-assistants [--lang en]`: a connected app's row (device, dates), the token hint and the details sheet |
| `journeys/ai-consent-cimd.mjs` | `cd .cursor/skills/verify-snacklist && node journeys/ai-consent-cimd.mjs <evidence dir> [--lang en] [--seed-document]` (ai-assistants, job 94): an MCP 2026-07-28 sign-in with Claude's Client ID Metadata Document, the consent page naming „Claude“, Erlauben, the Zugänge row; deletes the client afterwards. It fetches the real document over the internet; `--seed-document` maps the repo's copy instead, for a box whose DNS gives claude.ai a non-public address |
| `journeys/premium.mjs` | `drive.sh premium` on `demo-familie` (job 185; German only): Mia's own yearly plan through the webhook with her user id as App User ID; the Mehr row and status live in both of her households (it creates „Mias WG“), none for Noah (second browser and his API view), EXPIRATION removes it live, an item added and ticked after the lapse, RENEWAL brings it back; deletes the purchase and the second household afterwards |
| `journeys/grocery-log.mjs` | `drive.sh grocery-log [--lang en] [--dark]` on `demo-familie`, launched with `VH_DEFINES="FLAGS_ON=grocery-log"` (job 199): seeds Lidl, Rewe and eleven trips through `save_trip` (fixed ids), then the Verlauf tab's calendar dots (3 and 5 trips), the day filter, G1 and G2 and the toggle kept over a reload, a Free member's locked 40-day-old trip and locked days, a trip added, edited and deleted (checked through `trip_history`), and the list's card after Lidl's last item; `--compact` checks the 358 px layout only. It ticks Butter, Nudeln and Reis off and logs them |
| `journeys/trip-mode.mjs` | `drive.sh trip-mode [--lang en] [--dark] [--compact]` on `demo-familie`, launched with `VH_DEFINES="FLAGS_ON=trip-mode,grocery-log,prices-and-trip-total"` (job 234): puts the 15 seeded items back over Lidl and Rewe, sets three prices, deletes the household's trips and sessions and Mia's promotional Premium; then the question (Nein, Zurücknehmen, Ja), the strip's Pause and Weiter, Noah's Kaffee during the trip, the Free summary, the Verlauf trips with the session id, the Premium summary (amounts, „War geplant“ checked through `trip_session`, „Einkauf löschen“ checked through `trip_history`), a start from Mehr, and on Playwright's clock the 45-min pause, the 4-h end, its card and „Doch weiter“; `--compact` is 358 × 760. It deletes Verlauf trips, so drive grocery-log after it |
| `journeys/household-join-paths.mjs` | `cd .cursor/skills/verify-snacklist && node journeys/household-join-paths.mjs <evidence dir> [--lang en]` on `demo-familie` (household-invites, job 206): Mia makes Nachbarn, Verein and Oma with an invite each; Ida's sheet „Mit Code beitreten“ opens `/join` and Abbrechen returns to the list, More has no join row from top to end, `/more/join` lands on `/join`, a typed code and a `/join/<code>` link join; Noah signed out opens a link, signs in, joins. Rerunnable: it deletes Mia's three households first |
| `journeys/tips.mjs` | `drive.sh tips [--lang en] [--dark]`: the List tab's tip, dismiss, the next tip after a reload |
| `journeys/tips-first-shop.mjs` | `cd .cursor/skills/verify-snacklist && node journeys/tips-first-shop.mjs <evidence dir> [--lang en]` after `launch.sh --fresh` (tips `checklist`, job 204): Mia's one tick and Noah's one saved edit each do „Einmal einkaufen“ with items still open |
| `journeys/account-deletion.mjs` | `drive.sh account-deletion [--lang en] [--dialog premium\|none]`: the Konto page's email copy button and the clipboard; with `--dialog`, whether „Konto löschen“ shows the Premium warning (then cancels) |
| `journeys/edit-item.mjs` | `drive.sh edit-item [--from Apfelsaft] [--to Mineralwasser]`, or `--to Semmeln --onto Brötchen` for the synonym case, each on a fresh `demo-familie` (on `demo-family-en`: `--lang en --from "Apple juice" --to "Sparkling water"`): a rename onto an open item merges, „Zusammengeführt“, Rückgängig; with `--onto` (a synonym) nothing merges and the duplicate hint shows |
| `journeys/offline.mjs` | `drive.sh offline [--lines "zwei Gurken\|two lemons"]`: lines added offline get the same name and Menge as online |
| `journeys/list-manage.mjs` | `node .cursor/skills/verify-snacklist/journeys/list-manage.mjs <evidence dir> [--lang en] [--dark]` (no feature id of its own, so not through `drive.sh`): screenshots of the list, the add sheet, More, „Läden“, one store's details and „Ohne Laden“ for stores-walk-order and categories; adds and then deletes Wochenmarkt and Bäckerei; checks only that the page logs no errors |
| `journeys/baumarkt.mjs` | `cd .cursor/skills/verify-snacklist && node journeys/baumarkt.mjs <evidence dir> [--lang en]` on a fresh `demo-familie` (it types Schrauben and friends; it fails if one is already on the list, for example after `item-icons.mjs`): the store „Baumarkt“ added under „Anpassen“, its seven categories, DIY items in its section in walking order, Milch outside it |
| `journeys/item-icons.mjs` | `node .cursor/skills/verify-snacklist/journeys/item-icons.mjs <evidence dir> [--lang en] [--remote-revision n]` (stores-walk-order `sw-rows`): a mixed list's row icons in light and dark, then a newer remote icon table (one plain GET, no names) and its icon on a row; `--remote-revision 1` must FAIL. It first puts every open item away, so the seeded rows are gone afterwards: drive tick-and-undo, edit-item and the other journeys that need them before it, or `launch.sh --fresh` after it |
| `journeys/onboarding.mjs` | `drive.sh onboarding [--lang en] [--dark]` (needs no seeded household; signs up two fresh users): the start screen, every guided-start step, a reload resuming at the stores, the household made from the answers, two invites, a second browser joining through the invite page's „Im Browser beitreten“ and „… ist beigetreten“ live, the list |
| `journeys/household-cap.mjs` | `node .cursor/skills/verify-snacklist/journeys/household-cap.mjs <evidence dir> [--lang en]` on `demo-familie` (household-invites `household-cap`): Ida in 20 households is refused joining Mia's „Nachbarn“ and a 21st household, stays in 20, and joins with the same invite once she has left one |
| `journeys/rate-snacklist.mjs` | `drive.sh rate-snacklist [--lang en]` on a fresh `demo-familie`: no „Snacklist bewerten“ row on the web, a whole list ticked off counts one trip in the device counters, putting one back and ticking it again stays one trip, 10 s offline is no failure and 70 s is. It ticks off every item and adds one, so drive it last or `launch.sh --fresh` after it |
| `journeys/hex-surfaces.mjs` | `node .cursor/skills/verify-snacklist/journeys/hex-surfaces.mjs <evidence dir> [--lang en] [--dark]`: screenshots of the top bar at rest and scrolled, „Läden“, one store's category order and the edit sheet; adds and then deletes two generic stores |
| `journeys/top-bar-and-name-dialog.mjs` | `node .cursor/skills/verify-snacklist/journeys/top-bar-and-name-dialog.mjs <evidence dir> [--lang en] [--dark] [--se]` on `demo-familie` (it needs Noah): the top bar synced, with a partner's new item and offline, then a store's rename dialog with and without a keyboard's height; logs the field-to-button gap; `--se` fails when the keyboard hides the field |

How-to clips (GIF for emails, MP4/WebM for the site) of the same build: [snacklist-howto-clips](../snacklist-howto-clips/SKILL.md).

## Gotchas

- `flutter build web --output` leaves `assets/FontManifest.json` out and no text renders. `launch.sh` builds into `app/build/web` and copies it. A later e2e gate run in the same checkout rebuilds `app/build/web` with its own defines; the copy here stays.
- Clicking „Erste Schritte ausblenden“ (the checklist's X) takes focus from the add field. Test autofocus after a reload, as `ready.mjs` does.
- The add sheet's note „✓ Hinzugefügt: …“ exists twice in the DOM (the note and a screen-reader announcement). Scope it to `addSheet(page, L)`.
- Catalogue suggestions are German words in both UI languages. In English, type a prefix of a German word ("Ched" → „Cheddar“).
- `fg` accepts port blocks 500 to 649. On the Hetzner runner `env.sh` sources `~/groceries-ops/env.hz` for PATH.
- A host whose `~/flutter` is older than CI's version makes `launch.sh` stop with "flutter on PATH is …, CI builds with …". An older SDK would still build, but it rewrites `app/pubspec.lock` (so doctor never sees a matching build) and serves an app users don't get. Unpack the matching SDK as `~/flutter-<version>` (found without any variable) or somewhere of your own with `FLUTTER_DIR` set; never change a shared `~/flutter`.
- After a box reset Playwright's Chromium can be missing: `launch.sh` then stops at its sign-in check with "Executable doesn't exist at …/ms-playwright/…" while the stack and the server are up. Run `cd e2e && npx playwright install chromium`, then `launch.sh` again.
- `/join/<code>` is the static invite page (`app/web/join/`, served by `e2e/serve.mjs` as on Vercel), not the app: click „Im Browser beitreten“ / "Join in the browser" to reach the app with the invite.
- The local stack signs up without email confirmation, while the hosted project requires it (`features/sign-in.md`).
