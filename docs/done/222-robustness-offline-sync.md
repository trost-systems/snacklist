# Job 222: offline and sync error paths, mapped and five gaps closed (2026-11-14)

Peter (t841u): improve robustness of the offline and sync error paths, with evidence first and
tests before fixes. The job mapped every error path of the list's sync and of the surfaces
around it against the tests on main `3344381d`, fixed the gaps that could lose or stall
something a user did, and labels the rest below. No new UI, no flag, no migration.

## What shipped (PR #469)

Each fix has a test that fails without it (the mutation table under Proof).

- **A tick is not lost with its row.** A tapped row commits its tick when it has closed, 440 ms
  after the tap (260 ms with reduced motion). Until then the tick was in neither the queue nor
  the device's cache, and it came from the end of the row's animation. It was lost when the row
  went away first, and it waited when no frame was drawn. Now
  (`app/lib/list/list_view/item_row.dart:68-134`, `shopping_list_view.dart:342`):
  - **The app is hidden** (phone to the background, page reloaded, tab closed, another tab in
    front): the tick commits at once (`AppLifecycleListener(onHide:)`). The list queues it on
    the device in the same turn, so a reload or a restart sends it.
  - **The row goes away** (its store is folded, the column count changes, the lazy list drops
    it, the user switches to another household): the tick commits right after the row's end,
    on the list the row was built on.
  - **A switch to another household** closed a list with nothing queued at once, before that
    tick came. The shown list is now held (`ListHolds`, job 229's mechanism) until its rows are
    gone, so it closes like any hidden list: once its queue, the tick included, reached the
    server (`list_scope.dart:322`, `:388`).
  - **No frames** (a tab behind another): a wall-clock timer commits on time, not the
    animation's end.
- **A closing list arms no timer.** `ListCubit.close()` awaits the channel's end. A write or a
  reload answered in that window armed the 3 s retry, the 1.5 s usuals reload or the 300 ms
  save on a list that was already gone (`list_cubit.dart:1926`, `:1952`, `:1970`). The state
  still shows the answer; nothing is scheduled.
- **A gateway's 401, 408 or 429 refuses no change.** postgrest-dart sets the error code to the
  HTTP status when the body is no PostgREST error. Only 5xx counted as trouble, so a 401, 408 or
  429 from a proxy in front of the database dropped the queued change with "Änderung abgelehnt".
  They now count as trouble: the change stays queued and is sent again
  (`list_repository.dart:138-148`). A 401 with a PostgREST body (PGRST301, PGRST303) already did.
- **A merge whose follow-up read fails is trouble, not a refusal.** After `merge_items` answers
  "item gone" (P0002) the repository reads both rows. A 503 on that read surfaced as an
  unhandled error of the second read; both reads are now awaited together and the op is asked
  again (`list_repository.dart:516`).
- **A start asks until the server's households show.** `SessionCubit._load` marked the user as
  loaded when its own read returned. When a second reload (resume, the switcher, a second auth
  event) passed the first, the first's answer was dropped as the older one; when the second
  then failed, nothing asked again: stale households with a cache, the loading screen until a
  restart without one. `_loadedFor` is now set where an answer is applied, and `_load` arms its
  3 s retry whenever the user's answer has not shown (`session_cubit.dart:411-431`, `:541`).

## The map: error paths and their tests

Checked against main `3344381d`. "UNTESTED" means no test injects that failure. Paths are
`app/test/...` unless they start with `e2e/`.

### The list (queue, retry, conflict, auth expiry, partial failure, reconnect)

| Path | Tests | State |
| --- | --- | --- |
| Offline ops stay visible, queue, flush on reconnect | `list/list_cubit_test.dart:264`, `:288`; `e2e/tests/connectivity.spec.ts:6`, `live-sync.spec.ts:105`, `offline-start.spec.ts:32` | covered |
| Queue across restarts | `list_cubit_test.dart:1740` (group), `list/hidden_queue_test.dart` | covered |
| A tick inside the row's leave: app hidden, row disposed, no frames, household switched | `list/item_row_test.dart:197`, `list/list_screen_test.dart:374`, `list/hidden_queue_test.dart:114`, `e2e/tests/tick-leave.spec.ts` | **was UNTESTED and lost; fixed here** |
| A refused op is dropped, reported, the view resyncs | `list_cubit_test.dart:321`; `e2e/tests/list-header.spec.ts:76` (no refusal on 503) | covered |
| 5xx and transient SQLSTATEs keep the op ("Sync gestört") | `list_cubit_test.dart:370` (job 161), `:476` (job 165); `list/list_repository_test.dart:73` | covered |
| Expired token mid-write (PGRST301/303) | `list_repository_test.dart:73-74`; `e2e/tests/offline-start.spec.ts:122` | covered |
| 401, 408, 429 without a PostgREST body | `list_repository_test.dart:126` | **was UNTESTED and dropped the change; fixed here.** No e2e |
| Merge (rename onto an open item) with the item gone, follow-up read fails | `list_repository_test.dart:1194` | **was UNTESTED; fixed here** |
| Conflicts: same-name add, tick replayed onto the partner's item, rename onto open | `list/sync_regressions_test.dart` (6 seeds), `fuzz/sync_fuzz_test.dart:93` (seeds 1 to 100 per run); `e2e/tests/already-on-list.spec.ts:20`, `rename-onto-open.spec.ts:63`, `:82` | covered |
| Overlapping resyncs, a failed one, missed changes | `list_cubit_test.dart:343`, `:349`, `:359` | covered |
| Realtime: join gap, `phx_close`, socket close, dead-but-open socket, freeze and resume | `list_cubit_test.dart:645` (job 166), `:1261`, `:1299`, `:1319`; `e2e/tests/live-sync.spec.ts:130`, `:206-235`, `connectivity.spec.ts:35` | covered |
| Start and resume grace | `list_cubit_test.dart:937` (job 212); `e2e/tests/offline-start.spec.ts:32` | covered, policy untouched |
| Answers that arrive while the list closes | `list_cubit_test.dart:1987-2060` (three tests) | **was UNTESTED; timers armed; fixed here** |
| A send that never answers (no HTTP timeout on writes) | none | UNTESTED, open by decision (below) |
| A resync read that never answers | none | UNTESTED, open (job 122's finding stands) |
| Delete wins over a replayed add | none (`docs/hillclimb/hc-sync-proposals/put_item_delete_wins.sql` is a proposal) | UNTESTED, open |
| Fuzz fake: JWT expiry, catalog edits, `place_item`/`move_item`, single dropped events, four devices | none | UNTESTED, open (job 99's list) |
| Resume resubscribes a down channel at once | none | UNTESTED, open (job 212's "Not done") |
| Flight mode on a real phone | none | UNTESTED, needs a phone |

### Around the list

| Surface | Tests | UNTESTED |
| --- | --- | --- |
| Session start: no network, retryable auth error, switch in flight | `session/session_cubit_test.dart:64`, `:78`, `:91`, `:97`, `:698`, `:717` | A start read that never answers (no timeout, below) |
| Session start: a read passed by a newer one that failed | `session/session_cubit_test.dart:756` (group, 6 tests) | **was UNTESTED and stuck; fixed here** |
| Session writes after a lost answer (create, leave, unarchive) | `session_cubit_test.dart:466`, `:524`, `:540`, `:618`, `:633`; `e2e/tests/onboarding.spec.ts:153`, `:379` | Join after a lost answer (`_unansweredJoin`) |
| Forced sign-out | `session_cubit_test.dart:113`, `app/device_cache_test.dart:119`, `:128` (the forget is pinned) | A refused token refresh signs out and drops the queued ops with the device's data: intended, never warned (below) |
| A non-retryable auth stream error | `auth/login_screen_test.dart:52` only | `SignedOut` without clearing `_loadedFor` |
| Household switch with a queue | `list/hidden_queue_test.dart:82`, `:108`, `:143`, `:162` | none ranked |
| Network watch | `app/network_test.dart:66`, `:90`, `:107` | none |
| Trips | `trip/trip_cubit_test.dart:450`, `:466`, `:488`, `:630`, `:665` | A save answered after `close()` (sent again by id, harmless) |
| Grocery log | `log/log_cubit_test.dart:54`, `:64`, `log/trip_prompt_test.dart:262` | Overlapping refreshes are unordered (cosmetic) |
| Entitlements | `purchases/entitlements_test.dart:57`, `:68`, `:164`, `:291`, `:610` | A first read that fails with the socket up: unknown until resume |
| Invites, join | `household/invites_poll_test.dart:65`, `household/invite_sheet_test.dart:287`, `household/onboarding_test.dart:128`, `:144`, `:540` | `create` without a request id (a lost answer and a retry make two invites) |
| Realtime channels other than the list's (entitlements, own join requests, a household's join requests, invites) | none closes or errors one | After a server `phx_close` the library never rejoins and the app does not either (below) |
| Feedback | `feedback/feedback_cubit_test.dart:97`, `:117`; `e2e/tests/feedback.spec.ts:180`, `:208`, `:299` | none |

## Proof

- **Failing first.** Every test named "(job 222)" was seen red on the code before its fix.
- **Mutation check** (`app/lib` changed by a script, the named tests run, the tree compared with
  the commit before and after):

  | Mutant | Tests that fail |
  | --- | ---: |
  | No commit when the row goes away | 4 |
  | No commit when the app is hidden | 3 |
  | Commit at the animation's end, not by timer | 1 |
  | A tick after the view ended is dropped | 1 |
  | The shown list is not held until its rows are gone | 1 |
  | The hold is let go before the rows' ticks | 1 |
  | Closing list: retry timer armed | 1 |
  | Closing list: usuals reload armed | 1 |
  | Closing list: debounced save armed | 1 |
  | Gateway 401/408/429 refuse again | 1 |
  | Merge follow-up reads awaited one by one | 1 |
  | Start: loaded once its own read returned | 2 |
  | Start: retry without the signed-in check | 1 |

  Not pinned: the `!isClosed` clause in `_load`'s retry condition (the timer's own callback
  checks it again).
- **e2e before and after** (`e2e/tests/tick-leave.spec.ts`: click a row, then reload or close
  the tab at once; the item must be ticked on the device and `bought` on the server). One hold
  of the e2e lock, local stack, the release web build, 14 November 22:07 to 22:24:

  | `app/lib` | Runs | Passed | Failed |
  | --- | ---: | ---: | ---: |
  | main `3344381d` (`--repeat-each=3`) | 18 | 3 | 15 |
  | this branch (`--repeat-each=5`) | 30 | 30 | 0 |

  - On main Chromium and Firefox failed 6 of 6 each and WebKit's reload 3 of 3: the row was
    back after the reload. The fixtures refused the retries ("no host stall, so its failure is
    real").
  - WebKit's closed tab passed 3 of 3 on main too: its close takes longer than the row's
    440 ms, so that one case shows nothing on WebKit. It stays in for the other two engines.
  - The box's load average was 7 to 13 in the main run and 5 to 7 in the branch run. A first
    main run is not counted: the spec had a wrong status name and failed before the click.
  - The branch run predates the list hold for a household switch (found while writing this
    file); that change is not on the spec's path, and CI runs the spec on the final head.
- **Sync fuzz** (`tool/hillclimb/hc-sync/measure.sh`, seeds 1 to 1000, one run each): 0 failures
  on main's `app/lib` (92.1 s) and 0 on the branch (93.0 s). No change, as expected: the fuzz
  calls the cubit directly and none of the fixed paths is in its model.
- **`flutter test`** (whole suite, the final tree): 3152 passed, 98 skipped, 2 min 17 s.
- **Fable 5.2 review:** REVIEWLINE.

## Remaining gaps

Labelled, not fixed. The first four are in `docs/NEEDS_LEAD.md`, "Job 222".

- **A write that never answers stalls the queue.** No HTTP timeout on item writes. Job 122
  found why one is not safe alone: a timed-out write that still lands later reorders
  last-write-wins writes. It needs a stale-write guard on the server first.
- **A forced sign-out drops queued changes.** A token refresh the server refuses signs the user
  out, and sign-out forgets the device's data, queued adds and ticks included, without a word.
  Intended (job 122 in `docs/DECISIONS.md`: without a session the writes cannot be sent, and
  the next sign-in may be another user); keeping the queue per user or warning is a product
  call.
- **Realtime channels other than the list's do not come back after a server `phx_close`.**
  Entitlements and invites re-read on a rejoin, but a closed channel never rejoins; the two
  join-request channels re-read nothing. Resume refreshes cover most of it; an owner with the
  approval section open can miss a request until the section is rebuilt. Read from the code,
  not reproduced.
- **A start read that never answers is never asked again.** `_load` has no timeout. One was
  tried on paper and left out: the retry would drop a slow answer that is still coming, and on
  a slow network could do so every time. The platform's HTTP timeout bounds it. Not measured.
- **A tick less than 440 ms before signing out** goes with the device's data (sign-out forgets
  the queue, as above).
- **Job 219's CI trace** (`docs/NEEDS_LEAD.md`, job 219, point 4: WebKit, a reload right
  after the row was gone from the page, no write before or after). Read from the code, that is
  the case fixed here: the row is gone from the page before its tick commits. A committed tick
  is written to the device in the same turn, the path the new spec drives at the reload. The
  CI trace itself was not reproduced, so that it was this and nothing else is inferred.
- **No e2e for a body-less 401, 408 or 429**: unit-tested at the repository only.
- From earlier jobs, still open and untested: delete wins over a replayed add (job 99), the
  fuzz fake's omissions (job 99), resume resubscribing a down channel at once and catalog
  changes during a grace (job 212), flight mode on a real phone (job 166), the stack-pause
  stress pass (job 122), entitlements unknown after a failed first read, a non-retryable auth
  stream error, invite creation without a request id, a join after a lost answer.

## Not changed

- Job 212's banner grace, the banner's look and copy, and every timeout.
- "Tick at the tap, animate apart" was considered and left: it changes what the row shows
  while it leaves (the dividers and "Zuletzt verwendet" move under it), which is a design
  change. The commit-early paths give the same guarantee with the row unchanged.
- Voice, Siri, trip-mode UI, legal and store metadata (the brief's stay-off list).
