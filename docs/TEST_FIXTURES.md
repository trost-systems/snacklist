# Test fixtures and multi-client sync

Agents verifying Family Groceries need accounts in interesting states and a
way to watch two or three devices sync. `scripts/fg` does both:

- `fg seed <scenario>` creates test users and their data from a YAML file
  in `test/fixtures/scenarios/`, as one *run*. It never resets the database,
  so runs of different agents and scenarios coexist.
- `fg teardown <run>` deletes exactly what that run created and proves it
  with a leftover check.
- `fg sync <scenario> --clients 3 --script <file>` signs three household
  members into the web app in one Chromium, runs a short script, and
  captures screenshots, videos and propagation latencies by itself.

Every command prints one JSON object. Failures carry `error.code`,
`error.message` and `error.hint` (`fg help <command>` for flags).

## Quick start

```bash
export FG_PORT_PREFIX=560                 # your port block
scripts/fg up --only stack                # the local stack (seeds peter + lea too)
scripts/fg scenario list                  # the scenarios and what each is good for
scripts/fg seed household-3-mid-shop      # prints the run id and member refs
scripts/fg db query "select name, quantity from items where status = 'active'" --as <run>:mia
scripts/fg teardown <run>                 # leftovers: every count 0
```

```bash
scripts/fg sync household-3-mid-shop --clients 3 \
  --script .cursor/skills/verify-family-groceries/journeys/sync-3-clients.fgs
# then open $FG_EVIDENCE_DIR/<run>/sync/index.html
```

## Scenarios

| Scenario | State | Good for |
| --- | --- | --- |
| `empty-new-user` | One confirmed user, no household | Onboarding: the welcome screen, create a household, join with a code, deleting an account without data |
| `solo-long-list` | One person, 64 items over Supermarkt, Wochenmarkt, Bäckerei, Drogerie and no store, every category | Scrolling and grouping, store sections with many items, offline start with a big cache |
| `household-3-mid-shop` | Three members, stores Supermarkt and Drogerie; 8 items ticked 12 minutes ago at the Supermarkt, 10 open; Noah's client has every store but the Supermarkt folded | Live sync with 2 or 3 clients, ticking while shopping at one store, fresh "Zuletzt verwendet" |
| `heavy-history` | Two members, 8 weeks of trips at the Supermarkt (weekly), the Wochenmarkt (weekly), the Drogerie (every 2 weeks) | Usuals and "Brauchen wir wieder?": Milch, Brot, Eier, Windeln, Duschgel are due; Hafermilch, Gurken, Tomaten, Nudeln are usuals but not due |
| `many-stores` | Ten generic stores (Supermarkt, Discounter, Großmarkt, Biomarkt, Drogerie, Wochenmarkt, Tierbedarf, Hofladen, Bäckerei, Apotheke) with distinct walk orders and hidden categories, a "Tiernahrung" category | The store picker with many chips, store layouts, hidden categories, item→store memory |
| `edge-cases` | A German and an English user; a 120-character name, a 40-character quantity, emoji, umlauts, quotes, near-duplicates (Milch and Milch laktosefrei; a second open Milch would be skipped) | Text layout, near-duplicates, quantity display, an `en` user |
| `pending-invite` | A one-person household with one open, one expired and one revoked invite code; a second user without a household | Joining by code or `/join/<code>` (the seed prints the open code), invalid-invite errors, a member arriving live |
| `h-list-walk` | Two members, Drogerie, Supermarkt and Wochenmarkt (in that order) with their own layouts, 14 items with brands, properties and a set walk order inside each group, two without a store | Design H's list (store sections, category dividers, Marke · Eigenschaften rows), drag and drop against a known order, store reordering, the edit sheet prefilled |
| `store-screenshots`, `store-screenshots-en` | „Unser Haushalt“ / „Our Home“ with Anna and Jonas, the generic stores Wochenmarkt, Bäckerei, Supermarkt, Drogerie (English: Farmers market, Bakery, Supermarket, Drugstore) with walk orders, 8 open items, four weekly Supermarkt trips | The store screenshots (`scripts/store-screenshots.sh`, docs/STORE_SCREENSHOTS.md): suggestions from past trips (Joghurt), item→store memory for the voice and assistant adds; no retailer on screen (Legal N-23) |

`fg scenario show <name>` prints the resolved plan: every user, item and
trip with absolute times, and the counts the seed checks.

## Seeding

`fg seed <scenario> [--run-id ID] [--target local|hosted]`

1. Creates each user through the auth admin API with a random password,
   `email_confirm: true` (no mail is sent), the email
   `<handle>.<run>@fg-test.invalid`, `user_metadata.display_name` and
   `locale`, and `app_metadata.fg_run` / `fg_scenario`.
2. Creates each household the way the app does: the owner calls
   `create_household` (which seeds the categories; a household starts
   without stores); the other members are added with the service role.
3. Adds categories (`create_category`) and the route order
   (`reorder_categories`). Creates the scenario's stores in their order
   with `add_store`, as the app does, then sets the walk orders a scenario
   gives (`set_store_layout`). Fixtures use generic store names
   (Supermarkt, Drogerie, Bäckerei, Wochenmarkt); `add_store` would make
   dm, Lidl or EDEKA that chain.
4. Replays the history oldest trip first, through the real triggers: the
   adder inserts the items (classifier, `added_by`, the `added` event), the
   shopper ticks them (the `bought` event, item→store memory when the trip
   has a store), then the service role backdates `bought_at` and the event
   times. Item→store memories keep the replay's order, so "latest wins"
   holds, but their own `updated_at` is the seeding time.
5. Inserts the open list as each adder, with backdated `created_at`. Items
   without a store get one from item→store memory, as in the app.
6. Creates invites as the named member, then expires or revokes them.
7. Checks the result as the members see it, through RLS: members, active
   and bought items, stores, categories and open invites per household;
   users without a household; `suggest_items` for `expect.usuals`, `due`
   and `notDue`; and that each member sees no row of another household.
   A failed check exits 1 with code `assert_failed` and the list.

The output names the run, each member's ref (`<run>:<handle>`), email,
household, the open invite codes, the counts and the checks. It never
contains a password or token. Credentials are in the run manifest
`$FG_STATE_DIR/runs/<run>.json` (default `~/.cache/fg/<prefix>/runs/`,
directory mode 700, file mode 600, outside the repo). The manifest also
lists every id the run created.

A run with an existing `--run-id` is reused when it is ready and of the
same scenario (`reused: true`); otherwise seeding refuses with
`run_exists`.

### Using a run's members

Every user flag takes a member ref: `--as`, `fg peer`, `fg login`,
`fg fn call --as`, `fg mail --to`, `fg up --clients` and `--client`.

```bash
scripts/fg db query "select count(*) from items" --as fx-1025-1432-k3x9:mia
scripts/fg peer fx-1025-1432-k3x9:noah add Hafermilch
scripts/fg login fx-1025-1432-k3x9:ida --api       # a token for curl
scripts/fg db query "select 1" --as mia            # bare handle: the last run seeded here
```

`peter` and `lea` always mean the baseline users of plain `fg seed`, so a
scenario may not use those handles. Plain `fg seed` (no scenario) still
resets the database and creates peter and lea.

To drive the Linux debug app as a member, start a client named after it:
`fg up --clients fx-1025-1432-k3x9:mia`, then
`fg login fx-1025-1432-k3x9:mia` and `--client mia` on drive commands.
Each Linux client costs about 650 MB; use at most two on the shared box.

## Teardown

`fg teardown <run> | --stale | --all [--target local|hosted] [--dry-run]`

- Finds the run's users by `app_metadata.fg_run`, by the email address and
  by the manifest, and only ever accounts in `@fg-test.invalid`.
- Deletes each user with `public.delete_account`, the app's own path: it
  locks the household, deletes it with its last member and hands ownership
  on otherwise. A household with any member outside the run therefore stays
  (only the run's users leave it), even one who joined during the teardown.
  A household the run created that has no members left is deleted too.
- Ends with a leftover check: auth users, households, members, items,
  item events, invites, categories, stores, store layouts, category and
  store memories (by household); profiles, memberships, tokens, event
  actors and item authors (by user). Any count above zero fails with code
  `leftovers`.
- Is idempotent: tearing down a gone run returns `alreadyClean: true`.

`fg runs` lists the runs on a target: those with a manifest, plus
`orphaned` ones whose manifest is gone but whose test users exist.
`--stale` (and `fg teardown --stale`) means older than 24 hours;
`--older-than <hours>` changes that.

## Scenario format

One YAML file per scenario, validated by
[`test/fixtures/scenario.schema.json`](../test/fixtures/scenario.schema.json)
(editors pick it up through the `yaml-language-server` comment). Errors
name the field: `households[0].items[3].store: no store "Aldi"`. An item,
trip or view may name only a store the household declares under `stores:`,
and the open list may hold each item once (the database skips an open item
that is already on the list).

```yaml
# yaml-language-server: $schema=../scenario.schema.json
name: my-scenario                 # = the file name
summary: One sentence on the state.
goodFor: [what to test with it]
users:
  - { handle: mia, name: Mia Brandt, locale: de }   # locale de|en
households:
  - name: Familie Brandt
    members: [mia, noah]          # the first one owns it
    categories:
      add: [Tiernahrung]          # before Sonstiges, like the app
      order: [Getränke]           # these first; the rest keep their order
    stores:
      - name: Supermarkt          # households start without stores
        layout: [Obst & Gemüse, Kühlregal]   # walk order; the rest follow
        hidden: [Tiefkühl]
      - name: Wochenmarkt         # no layout: the route order
    items:                        # the open list
      - Milch                     # just a name
      - { name: Hafermilch, quantity: "2", store: Supermarkt, category: Kühlregal, by: noah, at: "-2h" }
    history:                      # past trips
      - at: "-9d 17:30"           # ticked off then (Berlin time)
        by: mia
        store: Wochenmarkt        # ticked in this store's view
        every: 7d                 # repeat, going back
        times: 8
        items: [Milch, Brot]
    invites:
      - { by: mia }               # open, 7 days, works once
      - { expires: "-1d" }        # expired
      - { revoked: true }
views:
  noah: { store: Supermarkt }     # fg sync folds every other store for noah
expect:                           # checked through suggest_items after seeding
  usuals: { home: [Milch] }
  due: { home: [Milch] }
  notDue: { home: [] }
```

Times are relative to the moment of seeding, so a scenario never goes
stale: `now`, `-90m`, `-2h`, `-3d` (exact offsets), or `-3d 18:10` (that
Berlin calendar day at 18:10; days start at 1, so it is always in the
past). Repeated trips keep their wall-clock time across a DST change.

Optional item fields `brand`, `properties` and `walkOrder` need the columns
job 15 adds (`items.brand`, `items.properties`, `items.sort_key`). Until a
database has them, seeding such a scenario fails with code `needs_column`
before it creates anything. If job 15 names the walk-order column
differently, change `ITEM_EXTENSION_COLUMNS` in `cli/fixtures.ts`.

Due items follow `suggest_items`: at least two purchases, and the days
since the last one between the average gap and four times it. Pick the
last trip so that holds at any time of day (for a 7-day rhythm, the last
trip 9 days ago, not 7). `scenario_test.ts` checks `heavy-history` for
every hour of a day.

### Adding a scenario

1. Write `test/fixtures/scenarios/<name>.yaml`.
2. `scripts/fg scenario show <name>` until it validates and the plan
   looks right.
3. `scripts/fg seed <name>`; every check must pass. Then
   `scripts/fg teardown <run>`.
4. Add a row to the table above, and to `scenario_test.ts` if the
   scenario promises a shape (a count, a due item).

## Multi-client sync

`fg sync <scenario> --clients 2|3|<handles> --script <file> [--run-id ID] [--keep] [--target local|hosted]`

1. Picks the clients and checks the script against the scenario, before
   anything is seeded or built: with a number, the first members of the
   first household that has that many (A, B, C in member order); with
   handles, those members. Each client applies its scenario view (`views`).
2. Builds the checkout's web app for the target into
   `$FG_STATE_DIR/web-<target>` (cached by the app's source fingerprint;
   about 40 s; `/tmp/fg-web-build.lock` keeps it to one build at a time),
   unless `--web-build <dir>` names one.
3. Takes `/tmp/fg-e2e.lock` (`FG_E2E_LOCK` overrides the path), waiting up
   to `--lock-wait` seconds (default 1200), else fails with
   `e2e_lock_busy`. A lock held by a parent process
   (`flock /tmp/fg-e2e.lock scripts/fg sync ...`, or the e2e gate's
   `flock 9`) is reused, not deadlocked on.
4. Seeds the scenario as a new run, or reuses `--run-id` (which must be
   ready). Seeding comes after the lock, so no seeded run sits waiting for
   it.
5. Serves the build on port `<prefix>80` (an orphaned static server left
   on that port by a killed run is stopped first; anything else there
   fails with `port_taken` naming the process), opens one Chromium with one
   isolated context per client and signs each in through the login screen.
6. Runs the script, then tears down the run it seeded unless `--keep`, also
   when the run fails. A `--run-id` run is left as it was.

**Stopping it.** Ctrl-C, SIGTERM (`kill`, `timeout`, a CI cancel) and
SIGHUP (a closed terminal) stop `fg sync` and `fg seed` at once: the lock
wait, the web build and the browser driver are killed, a seed stops at its
next request, the web server and the lock are released, a run this command
seeded is torn down, and fg exits 130, 143 or 129. A stop during the lock
wait or the build leaves nothing, because nothing is seeded yet. Only a
hard kill (SIGKILL) skips the teardown; `fg runs` lists what it leaves and
`fg teardown --stale` (or `fg teardown <run>`) removes it. `e2e/sync-smoke.sh`
checks both stops in CI.

### Script language

One step per line; `#` starts a comment. Clients are `A`, `B`, `C` or
their handles.

| Step | Does |
| --- | --- |
| `A add "Hafermilch 2"` | Types into "Was fehlt?" and presses Enter |
| `B tick "Milch"` | Taps the row's checkbox ("Milch abhaken") |
| `C edit "Bananen" quantity "6"` / `name "Banane"` | Opens the row, retypes the field, Speichern |
| `A store "Supermarkt"` / `A store "Alle"` | Shops at that store: folds every other store section except "Ohne Laden" ("Alle" unfolds all; design H has no store chips) |
| `A offline` / `A online` | Cuts the client off: offline emulation plus closing its open realtime socket, so the app sees a real disconnect / reconnects |
| `A reload` | Reloads the page |
| `expect B,C see "X" [within 2000ms]` | Each client shows a list row named X ("X" or "X …", e.g. "Bananen 8"); default 3000 ms |
| `expect A gone "X"` | No row named X |
| `expect A text "Offline"` | Any visible text contains it |
| `wait 500ms` | Pause |
| `screenshot "name"` | An extra frame |

Rows are matched on Flutter's semantics tree, which holds the rows that are
built: on screen plus a small margin. A row far down a long list is not
"seen"; scroll is not a step, so pick scenarios where the rows in play are
near the top, or pass `--viewport 480x1400`.

The first failed expectation stops the script, captures a failure frame
and exits 1 with code `sync_failed`.

### Capture

Capture needs no trigger, because agents are too slow to screenshot after
an add:

- Each page runs a MutationObserver on Flutter's semantics DOM. When the
  visible state of any client changes (a row appears, disappears or
  changes), the driver screenshots every client at once: a *change frame*.
  Changes during a capture fold into one more capture. At most 300 change
  frames per run.
- After each step, every client again: a *step frame*.
- Each frame is composited side by side: client label, member and ref
  above each screen, the frame's kind, time and cause (for example
  `B: +Hafermilch` or the failed step) on top.
- Each context records a video; ffmpeg stacks them, aligned on the wall
  clock, into `videos/composite.webm` with labels and the run time.

### Latency

For each expectation, per observing client:

- **from ack**: the first rendered frame showing the change, minus the
  acting client's first successful REST write after its input (its server
  ack). It can be slightly negative: realtime may deliver before the HTTP
  response arrives.
- **from input**: the same frame minus the moment of the input (Enter, the
  tap, Speichern).
- **from event**: the same frame minus the `item_events` row time. Local
  stack only, where the database and the browser share a clock.

The resolution is one rendered frame (about 16 ms) plus the observer
callback; the ack time is a few milliseconds after the response. All
clients run in one browser on one machine, so their clocks agree. The
summary leaves out the acting client's own view and reports delivery after
a reconnect (`catch-up`) apart from live propagation.

### Artifacts

```text
$FG_EVIDENCE_DIR/<run>/sync/          # sync-2, sync-3 for later runs of the same run id
  index.html                          # open this: failure first, steps, latencies, frames, videos
  index.md                            # the same for a terminal or a PR
  result.json                         # everything, machine-readable
  frames/0001-step.png ...            # composites (step, change, failure)
  frames/clients/0001-A.png ...       # each client's screenshot per frame
  videos/A.webm B.webm C.webm         # per client
  videos/composite.webm               # side by side
```

`FG_EVIDENCE_DIR` defaults to `~/fg-evidence` (on the build box
`~/groceries-ops/evidence`), outside the repo. The engine's config file
holds the passwords; it lives in `$FG_STATE_DIR` with mode 600 and is
deleted after the run. No artifact contains a password or token: the
screenshots show the list, not the login form being filled.

### Other surfaces

The script is surface-agnostic: `cli/sync_dsl.ts` parses it into steps
(`add`, `tick`, `edit`, `store`, `offline`, `online`, `reload`,
`expect see|gone|text`, `wait`, `screenshot`), and `e2e/sync/engine.mjs`
is the web driver. A native driver implements the same steps on
Marionette:

| Step | Marionette (fg's linux surface today) |
| --- | --- |
| add | `enter-text --key add-item-field`, `press-key enter` |
| tick | `tap --row <item> --type Checkbox` |
| edit | `tap --text <item>`, `enter-text` into Name/Menge, `tap --text Speichern` |
| expect see/gone | poll `elements` (fg's `find`) for the row text |
| frames | `screenshot` per client; changes by polling `elements` |
| offline/online | block the stack's port for that client's process |

It would read the same config, write the same `result.json`, and the
report code would not change. On the build box a Linux client costs about
650 MB, so three native clients do not fit next to the stack; a real phone
or Firebase Test Lab (job 06) is the path for native sync runs.

## Local and hosted

The default target is the local stack of `FG_PORT_PREFIX`.

`--target hosted` (on `seed`, `runs`, `teardown` and `sync`) uses the real
project `jdwqrallbpdbshrdhenk`, where Peter's and Lea's data lives. Rules:

- Only accounts in `@fg-test.invalid` are created or deleted; teardown
  refuses a manifest that names any other account, and keeps any household
  that has a member outside the run.
- The service key is fetched at run time through the Management API with
  `SUPABASE_ACCESS_TOKEN` (from the environment or `~/groceries-ops/env`).
  It stays in memory: never printed, logged or written.
- A seed that fails or is stopped (Ctrl-C, SIGTERM, SIGHUP) is torn down
  before fg exits; seeding stops at its next request first, so teardown
  sees every record the run made. A failed check tears a hosted run down
  too. `fg sync --target hosted` tears down the run it seeded at the end
  (unless `--keep`) and on any failure or stop; it seeds only after it holds
  the e2e lock, so no hosted test account waits idle for it. A `--run-id`
  run is left as it was. After `fg seed --target hosted`, run
  `fg teardown <run> --target hosted` yourself. A hard kill (SIGKILL)
  cannot be caught: `fg runs --target hosted` lists leftovers and
  `fg teardown --stale --target hosted` removes them. Member refs
  (`--as <run>:<handle>`) resolve local runs only.
- Seeding records the counts of rows outside pure test households (every
  member in the test domain) and of users outside the test domain: counts
  only, never content. Teardown counts again and reports
  `nonTestCountsUnchanged`. Peter and Lea may change rows meanwhile, so a
  difference is a reason to look at that table, not proof of damage.
- Manifests of hosted runs live in `~/.cache/fg/hosted/runs/`, shared by
  every port block.

Use the hosted target only to check production configuration (auth
settings, the deployed schema). Everything else belongs on the local stack.

## Tests

- `cli/scenario_test.ts`: every shipped scenario validates and has the
  promised shape; errors name fields; relative times across DST; due
  margins at every hour.
- `cli/sync_dsl_test.ts`: the script language and its errors.
- `cli/fixtures_test.ts`, `cli/sync_report_test.ts`: run ids, which users
  and households a teardown takes, no password in the output, latency
  summary and index.
- `cli/fixtures_integration_test.ts` (`FG_INTEGRATION=1`, a running
  stack): two runs seed and pass their checks, cannot see each other
  through RLS, tear down to zero, a second teardown is a no-op, and a run
  with a lost manifest is found and removed.
- `e2e/sync-smoke.sh` (CI Playwright job): a two-client `fg sync` with one
  add and one tick; checks the artifacts and the index.
