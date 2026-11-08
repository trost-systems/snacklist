---
name: verify-family-groceries
description: "Drive the real Family Groceries Flutter app (debug build with the Marionette binding, as a headless Linux desktop app or on an Android emulator) against a local Supabase stack, and prove behavior with screenshots, screen recordings and database state. Use before claiming any app, sync, auth, household or classifier change works, to reproduce a bug, or to capture PR evidence. Covers Edge Functions (HTTP) and Postgres/RLS too."
---

# Verify Family Groceries

The current feature map is `.cursor/skills/verify-hummlist/features/`.

Prove behavior on the real app, not on a proxy. `fg` is this skill's CLI. It starts an isolated instance (Supabase stack, app clients, Marionette), drives the app like a user, and saves evidence. Every command prints one JSON object. A failure carries `error.code`, `error.message` and `error.hint`, and the hint names the command to run instead.

```bash
scripts/fg help              # all commands; scripts/fg is a symlink to .cursor/skills/verify-family-groceries/fg
scripts/fg help tap          # one command: flags and examples
```

## Surfaces

| Surface | What it is | Use for |
| --- | --- | --- |
| `linux` | The debug app (`app/test_driver/main_marionette.dart`) as a Linux desktop window on its own Xvfb display, 412×892 | Default on boxes where the emulator cannot run. Two clients (peter, lea) at once for live-sync proofs. |
| `android` | The same entrypoint as a debug APK on a headless emulator (AVD `fg-<prefix>`, 2 GB) | Mobile-only behavior: the soft keyboard, deep links, the magic-link return. One emulator per instance; lea then runs on linux. |
| backend | `fg db query`, `fg fn call`, `fg peer`, `fg mail` | Server state, RLS, Edge Functions, a UI-less second client, the local inbox. |
| web | `fg sync`: the web build in 1-3 Playwright contexts of one Chromium, each a household member | Multi-client sync with automatic frames, videos and latencies; offline/online per client. `e2e/` Playwright (`scripts/verify.sh`, or on GitHub Actions without local Docker: `scripts/ci-e2e.sh --spec <file>`) stays the CI suite. |

`FG_SURFACE` picks the surface. If unset, it is `android`, unless `~/.config/fg/kvm-broken` exists. On the shared build box that marker exists: starting a KVM guest there crashes the host kernel (`kernel BUG at arch/x86/kvm/x86.c:702`). Never delete the marker to "try again" on that box.

Marionette is debug and profile only. `marionette_flutter` is a dev dependency, and only `app/test_driver/main_marionette.dart` imports it. Release builds compile `lib/main.dart`. Code under `lib/` cannot import a dev dependency: the `depend_on_referenced_packages` lint fails `flutter analyze`, a required CI gate. The entrypoint also throws in release mode. A release build's `libapp.so` contains no Marionette code.

## Launch

```bash
export FG_PORT_PREFIX=548                   # your port block; 543 (the default) is job 1's
scripts/fg setup --dry-run && scripts/fg setup   # once per machine, and after a reboot (re-creates kvm group/permissions)
scripts/fg up --clients peter,lea           # stack + seed + build + both apps + Marionette; idempotent
scripts/fg login peter && scripts/fg login lea
```

`fg up` exits 0 only when the instance is usable: Supabase answers, the migrations are applied, `peter@fg.test` and `lea@fg.test` (password `test-password-123`) can sign in and share the household "Familie Test", and Marionette answers in every client. From an empty machine it runs `supabase start` from a generated workdir (`~/.cache/fg/<prefix>/stack`, ports `<prefix>xx`, project `family-groceries-<prefix>`). The tracked `supabase/config.toml` stays untouched. It seeds through the app's own RPCs and builds the debug app (about 30 s warm). Its JSON names the URLs, users, VM service URIs and the evidence directory. Reruns reuse what runs and is current. A changed `app/` rebuilds and relaunches. `--fresh` resets the database; it doesn't restart the stack. The functions' local secrets come from `supabase/functions/.env`, which `fg up` doesn't write: run `scripts/iap-local-env.sh` (Hummlist Premium's local RevenueCat stand-in secrets, `features/purchases.md`) and `scripts/alexa-test-ca.sh` (`features/alexa.md`) first, and after a change to that file run `fg down`, then `fg up`, so the stack loads it.

### Hosts without the Linux toolchain

`fg setup` installs clang, CMake and the GTK headers with `sudo apt-get`. On a host without sudo but with Docker (the Hetzner runner) skip it and build the app in a container:

```bash
export FG_SURFACE=linux                                                           # no ~/.config/fg/kvm-broken here, so the default would be android
export FG_EXTRA_PATH="$PWD/.cursor/skills/verify-family-groceries/linux-build"   # dirs fg puts before ~/flutter/bin
dart pub global activate marionette_cli && flutter config --enable-linux-desktop    # the rest of fg setup
scripts/fg up --clients peter,lea
```

`linux-build/flutter` runs `flutter build linux` in an image built from `linux-build/Dockerfile` on first use (`fg-linux-build:<first 12 hex of the Dockerfile's sha256>`, so an edited Dockerfile gets a new image) and passes every other command to the host's flutter. The bundle runs on the host, which needs only the GTK 3 runtime. For `fg drag`, which needs `xdotool`, unpack it without root: `apt-get download xdotool libxdo3`, `dpkg -x` both into a directory, and put a wrapper that sets `LD_LIBRARY_PATH` to its `usr/lib/x86_64-linux-gnu` on `FG_EXTRA_PATH` too (several directories join with `:`).

Old images pile up: `docker images fg-linux-build` lists them (about 1.5 GB each, most of it layers the tags share). A tag other than the current Dockerfile hash (such as the early `fg-linux-build:1`) is unused, so `docker image rm fg-linux-build:<old tag>` frees its own layers. Leave the current tag: other checkouts on the host build with it.

To drive a checkout's own running stack (its job port block in `supabase/config.toml`, as `verify-hummlist` and the e2e gate use) instead of a generated one, set what `fg_on_repo_stack` in `scripts/lib.sh` sets: `FG_PORT_PREFIX=<block> FG_PROJECT_ID=<its project_id> FG_STACK_WORKDIR=<the checkout's root> FG_STATE_DIR=<a directory of your own>`. `fg up` then reseeds that stack with `supabase db reset` when peter@fg.test and lea@fg.test aren't already in one household there (always with `--fresh`), so a seeded verify-hummlist run on it is gone: tear that down first.

Clients start signed out (`fg up` clears their session storage). `fg restart` quits and reopens an app and keeps its stored data. Use it for launch behavior such as autofocus. The session survives it on every surface.

## Doctor

```bash
scripts/fg doctor
```

Read-only. Checks Docker, then auth, rest, realtime, functions and Mailpit. It checks that every function in the checkout is served, and that the stack was started with the current `config.toml` (a running stack does not reload either; `fg up` restarts it). It compares the migrations applied with the checkout and checks that both users sign in to one household. Per client it checks that the process is alive, that the build matches the checkout (`<client>.build`), and that Marionette is connected, and it reports which screen shows (`login`, `welcome`, `list`). Healthy means `"ok": true` and exit 0, the same contract as every other command. Otherwise it exits 1 with `"ok": false`, `error.code` `unhealthy` and `error.checks`, where each failed check carries its `fix`. Run it first, and whenever a command fails unexpectedly.

## Drive

Every drive command takes `--client peter|lea` (default peter). Prefer stable handles in this order: ValueKey, label, tooltip, exact text, coordinates.

| Handle | Where |
| --- | --- |
| `--key login-email`, `--key login-password` | Login screen fields |
| `--text Anmelden` / `Registrieren` / `"Anmeldelink per E-Mail senden"` | Login buttons (the app bar also says "Anmelden"; `fg login` presses Enter instead) |
| `--key welcome`, `--key onboarding-create`, `--key onboarding-join`; then `--key household-name`, `--key create-household`, `--key invite-code`, `--key invite-check`, `--key join-confirm` | Onboarding (signed in, no household; `features/onboarding.md`) |
| `--key add-item-field` (hint "Was brauchst du?") | The add bar at the bottom of the list; autofocused on open on desktop and web. `add-clear` (✕) empties it while the sheet is open; `dictation-button` shows on phones only |
| `--key add-sheet` (semantics "Hinzufügen"), rows `--key suggestion-0`, `suggestion-1`, … | The add sheet, open while typing or after a tap on the bar. A row's label reads "<qty> <name>, <source>, <brand>, <properties…>, <store>" (`fg wait --text "Milch, Wie getippt"`); Enter (`fg press enter`) takes `suggestion-0`. `chip-store` / `chip-category` fold out `store-option-<id>` / `category-option-<id>` for the next row taken. After an add: `added-note` ("✓ Hinzugefügt: <name> → <store>") and `added-undo`. Empty field: "Wieder fällig" rows or `add-sheet-empty`. `add-sheet-close`, `fg press escape` or a tap on the dimmed list closes it and clears the field |
| `--key list-header`; inside it `new-items-subtitle` ("2 neu von Lea") ; the sync indicator over it (`sync-indicator` the one hex in both forms, its content `sync-card` or `sync-pill`; Semantics label "Offline: …" or "Sync gestört: …", nothing while online) | The bar above the list: 44 px under the top inset in every state, no household name or count since job 29a. The household name shows in Mehr (`features/household.md`) |
| `--text "<row text>"` | Tick an item: a tap on its row. The row text reads the quantity first ("2 l Milch", "6× Bananen"); a row without a quantity reads the name. The row's key is the item id. |
| `fg marionette -- long-press --text "<row text>"` (or `secondary-tap`, a right click) | Open an item's edit sheet (key `edit-sheet`; fields `--key edit-name`, `edit-brand`, `edit-quantity`, `edit-properties`; `--key chip-store` / `chip-category` fold out `store-option-<id>` (`store-option-none` is "Ohne Laden") / `category-option-<id>`; `--key edit-done` saves only what changed, `edit-cancel` discards; no delete since job 149) |
| `--key store-<store id>`, `--key store-none` ("Ohne Laden") | A store divider: a tap folds or unfolds it; `fg marionette -- long-press` or `secondary-tap` on it does nothing (job 171; a store's details open from `list-edit`) |
| `--key category-<store id or none>-<category id>` | A category divider (text in capitals, semantics label the full name); no press action, `long-press` and `secondary-tap` do nothing |
| `fg drag --from-text <text> --to-text <...> [--edge before\|after]` | A real held drag (linux surface); the list has none since job 78 |
| `--key list-edit` ("Anpassen") | The list header's button: the stores screen `stores-screen` (`/edit`), a store's details `store-details` (`/edit/<id>`, `/edit/none` via `store-row-none`). Recipes: `features/stores.md`, `features/categories.md` |
| `--key list-hint-dismiss` | "Verstanden" on the explainer card (`list-hint`); `list-empty` is the empty state |
| `--key tab-list` ("Liste"), `--key tab-more` ("Mehr") | The tabs (a floating hex pill at the bottom on phones, a NavigationRail from 840 px wide). Each reopens its last page; a tap on the current tab goes to its first page. The open add sheet hides them |
| `more-invite`, `more-join` (→ `join-screen`, `/more/join`), `more-access` (→ `access-screen`, `/more/access`), `menu-account` (→ `account-screen`, `/more/account`, `account-email`), `more-sign-out`, `more-feedback`, `more-settings` (→ `settings-screen`, `/more/settings`: segmented control `theme-mode` with `theme-system` / `theme-light` / `theme-dark`, `settings-language` → `language-screen` with `language-system` / `language-de` / `language-en`; `features/settings.md`), `more-usage-data` (→ `more-usage-data-page`, `/more/usage-data`, PostHog-key builds only), `more-imprint`, `more-privacy-policy`, `more-terms`, `more-licenses`, `more-version` | Entries of the More tab (`more-screen`, a lazy list: `fg marionette -- scroll-to --key <entry>` first). Recipe: `features/shell-more.md` |
| `feedback-sheet`, `feedback-message`, `feedback-category-bug` / `-idea` / `-other`, `feedback-contact`, `feedback-send`, `feedback-retry`, `feedback-error`, `feedback-counter`, `feedback-close`, `feedback-thanks` | The feedback form from `more-feedback`. Recipe: `features/feedback.md` |

```bash
scripts/fg find --contains Milch            # what is on screen, as JSON (type, key, text, label, tooltip, bounds)
scripts/fg type --input "2 Äpfel" --submit  # into the focused field; umlauts are safe; the add sheet stays open
scripts/fg press escape                     # closes the add sheet, so the list is in reach again
scripts/fg tap --text "2 l Milch" --client lea   # ticks Milch: the row reads the quantity first
scripts/fg wait --text Milch --gone         # never sleep; wait polls (default 15 s) and reports elapsedMs
scripts/fg marionette -- scroll-to --text "Zuletzt verwendet"   # any other Marionette command
scripts/fg marionette -- swipe --start-x 368 --start-y 116 --end-x 368 --end-y 230   # a drag by coordinates (reorder handles, which need no hold)
```

`find` and `wait` see what Marionette lists: fields, list texts, tooltips and keys. Text inside buttons is not listed, but `tap --text` still finds it. To wait for a dialog, wait for one of its fields or texts instead. `fg tap` taps and `fg marionette -- long-press` holds without moving, but Marionette's `swipe` never holds first, so a held drag needs `fg drag` (linux surface only: it presses through xdotool on the client's Xvfb display). The list itself has no drag since job 78; `fg drag` remains for other held drags.

## Evidence

Evidence goes to `$FG_EVIDENCE_DIR/<run>/` (default `~/fg-evidence/<run>`; on the build box use `FG_EVIDENCE_DIR=~/groceries-ops/evidence`). That is outside the repo, and `fg down` never removes it. The run directory starts with `fg up` (or `--run NAME`). `fg env` prints it.

For review, copy the proof into the PR: commit the screenshots and short recordings (WebM, well under 1 MB each) to `docs/screenshots/<job>/`, embed the PNGs in the PR body, and link the videos. The full run directory stays in `$FG_EVIDENCE_DIR` for anyone re-checking on the box.

```bash
scripts/fg screenshot --name 02-lea-sees-milch --client lea    # PNG of the app frame
scripts/fg record start --name quick-add                       # WebM via Marionette's screencast
scripts/fg record stop                                         # finalizes; reports path and durationSec
scripts/fg screenshot --native                                 # OS capture (X display / adb screencap)
```

Flutter errors, including the cause behind a red error screen, go to the app log: `scripts/fg logs --client lea --grep EXCEPTION`. The CLI builds with `flutter.inspector.structuredErrors=false` so that they print. A fresh launch logs no EXCEPTION block. The debug entrypoint makes Flutter's "Zone mismatch" fatal (job 37): if a client stays blank and `fg logs --grep Uncaught` shows `Uncaught: Zone mismatch`, the binding was initialized outside the zone `bootstrap` in `app/lib/main.dart` runs the app in.

Proof standards:

- Drive the user path (the field, the row, the menu). Do not use RPCs or test hooks for the step under test. Use `db query --write` and `peer` only to set up preconditions.
- Capture the action and the resulting state. Take a screenshot before and after, and a recording across the action.
- Check side effects with a second, read-only view: `fg db query` for rows, the other client for sync, `fg mail` for mail.
- Name the entry point you proved. A skipped entry point is reported as skipped, not as verified through another path.
- A timing from `wait` is an upper bound: the CLI polls every 0.5 s, and each Marionette call takes about 0.2 s.

The reference proof is `journeys/quick-add-live-sync.sh`. It prints `PASS` with timings and the evidence path, or `FAIL: <step>`.

## Fixtures

Seed test accounts in a known state instead of building it by hand. Scenarios live in `test/fixtures/scenarios/*.yaml` (format and every scenario: `docs/TEST_FIXTURES.md`).

```bash
scripts/fg scenario list                         # empty-new-user, solo-long-list, household-3-mid-shop, heavy-history, many-stores, edge-cases, pending-invite, h-list-walk (design H walk), h-prototype
scripts/fg scenario show heavy-history           # the plan with absolute times and the checks
scripts/fg seed heavy-history                    # a run: users <handle>.<run>@fg-test.invalid, data, checks through RLS
scripts/fg db query "select name from items where status = 'active'" --as <run>:jo
scripts/fg runs                                  # runs on this stack; orphaned ones too
scripts/fg teardown <run>                        # deletes exactly the run; leftovers all 0; a second call is a no-op
scripts/fg teardown --stale                      # runs older than 24 h, also those whose manifest is lost
```

- `fg seed <scenario>` never resets the database; plain `fg seed` still resets it to peter + lea.
- Any user flag (`--as`, `fg peer`, `fg login`, `fg mail --to`, `fg up --clients`, `--client`) takes `<run>:<handle>`, or a bare handle of the last run seeded on this stack.
- Passwords stay in `$FG_STATE_DIR/runs/<run>.json` (mode 600). Never paste them anywhere.
- `--target hosted` seeds the real project with test accounts only and tears down on failure; use it only to check production configuration, and tear down yourself (`fg runs --target hosted`).

## Multi-client sync

`fg sync` runs a short script in two or three signed-in web clients of one household and captures by itself: a frame of all clients after every step and whenever any client's screen changes (side by side, labelled, timed), one video per client and a composite video, and the propagation latency per client.

```bash
scripts/fg sync household-3-mid-shop --clients 3 --script .cursor/skills/verify-family-groceries/journeys/sync-3-clients.fgs
open "$(scripts/fg env | jq -r .evidenceDir | xargs dirname)/<run>/sync/index.html"   # or the evidence.index path from the JSON
```

```text
A add "Hafermilch"
expect B,C see "Hafermilch" within 2000ms
B tick "Butter"
expect A,C gone "Butter" within 2000ms
C edit "Bananen" quantity "8"
B offline
B online
```

It takes `/tmp/fg-e2e.lock` itself (one Playwright run per box), exits 1 with `sync_failed` and the failure frames when an expectation fails, and tears down the run it seeded unless `--keep`. Steps and how a native (Marionette) driver plugs in: `docs/TEST_FIXTURES.md`.

## Backend

```bash
scripts/fg db query "select name, status from items order by created_at desc limit 5"   # read-only rows
scripts/fg db query "select count(*) from items" --as lea          # as lea, through RLS (or --as <run>:<handle>)
scripts/fg db query "update items set status = 'bought' where name = 'Milch'" --write --dry-run
scripts/fg fn call health --as anon                                 # Edge Functions over HTTP
scripts/fg peer lea add Butter                                      # REST client as lea
scripts/fg peer lea watch --until Butter --timeout 20               # realtime events as lea; write after its "watch live" line
scripts/fg mail --to lea                                            # Mailpit: subjects and auth links
scripts/fg login peter --api                                        # access token for curl
```

On a loaded box (load average far above the core count), the local edge runtime now and then aborts a request: a 503 with an empty body, and `docker logs supabase_edge_runtime_$(scripts/fg env | jq -r .projectId)` shows `connection aborted (uri: "/<function>")`. Send the request again. A 503 with a JSON body is the function's own answer, such as `health` without its database.

## Cleanup

```bash
scripts/fg down --dry-run && scripts/fg down     # recordings finalized, apps, Xvfb, emulator, this stack only
ls "$(scripts/fg env | jq -r .evidenceDir)"      # evidence survives
```

`fg down` stops only what this instance tracks: pids in `~/.cache/fg/<prefix>/state.json`, and the containers of its own project id. It never kills by process name. Run it after every failed attempt too. Use `--keep-stack` to leave Supabase up for the next `fg up`. On a shared box, stop the stack whenever you stop driving.

## Isolation

One instance per port block. `FG_PORT_PREFIX` sets the Supabase ports (`<prefix>21` API, `22` DB, `24` Mailpit), the project id, the state dir, the X displays (`:<prefix>1`, `:<prefix>2`) and the emulator port. `FG_PROJECT_ID`, `FG_AVD`, `FG_EMU_PORT`, `FG_STATE_DIR` and `FG_EVIDENCE_DIR` override single values; `FG_EXTRA_PATH` puts directories before fg's own tool path. Two agents on different prefixes never touch each other's processes. `scripts/gates/e2e.sh` and `fg sync` take `/tmp/fg-e2e.lock` themselves; never wrap the gate in `flock /tmp/fg-e2e.lock` (it then waits on its own wrapper forever). `node e2e/web-smoke.mjs` takes no lock, so wrap that one. Steps that stop a container of the stack (the health 503 check in `features/hosted-backend.md`) break every drive on that stack, an `fg sync` run included: run them after the other drives. `fg up` refuses a display another live Xvfb holds (`display_taken`). Never drive an instance you did not start.

## Android (not verified on the build box)

On a machine with a working emulator (KVM on Linux, or a Mac): run `fg setup --surface android`, which installs the emulator, the Android 35 Google APIs image for the host CPU (x86_64 or arm64-v8a) and the AVD. Then run `FG_SURFACE=android fg up --clients peter,lea`. The emulator reaches the stack at `10.0.2.2:<prefix>21`. Debug builds allow cleartext HTTP (`app/android/app/src/debug/AndroidManifest.xml`). `fg up` installs the APK, reads the VM service URI from logcat and forwards it with `adb forward`. The build box cannot run the emulator, so these steps have never run end to end. The first Android run must check them: boot, install, logcat URI and forward, Marionette over the forward, `record start` (Marionette falls back to adb reverse), `--native` capture, and opening a magic link with `adb shell am start -a android.intent.action.VIEW -d <link with 10.0.2.2>`.

## Helpers

- `fg` (and `scripts/fg`): the CLI. The source is in `cli/` (Deno). Tests: `cd cli && deno test -A`. CI runs them.
- `journeys/quick-add-live-sync.sh`: the reference end-to-end proof. `journeys/mcp-disconnect.sh` and `journeys/account-deletion.sh` prove `features/mcp-access.md` and `features/account.md` the same way. Each journey starts with peter on the list and leaves both clients there (lea signed in as the seeded lea), so they run back to back in any order. On a failure, `fail` stops the recordings the journey started: an orphaned recording left running on a client spoils the next recording there (`record stop` then reports `recording_failed`). A new journey keeps that contract.
- `linux-build/`: the container build for hosts without the Linux toolchain (Launch).
- `journeys/*.fgs`: `fg sync` scripts (three-client sync with reconnect, a deliberately failing expectation, a hosted sign-in).
- `features/`: one recipe per user-facing feature. Read `features/README.md` first.

When you ship a feature, add or update its `features/<feature>.md` in the same PR, and give new widgets a ValueKey where text is not stable. `/maintain-verification-skill` keeps the map honest.
