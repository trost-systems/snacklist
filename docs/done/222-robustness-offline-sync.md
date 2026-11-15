# Job 222: offline and sync error paths, mapped and five gaps closed (2026-11-14)

Peter (t841u): improve robustness of the offline and sync error paths, with evidence first and
tests before fixes. The job mapped every error path of the list's sync and of the surfaces
around it against the tests on main `3344381d`, fixed the gaps that could lose or stall
something a user did, and labels the rest below. No new UI, no flag, no migration.

## What shipped (PR #469)

Each fix has a test that fails without it (the mutation table under Proof).

- **A tick is not lost with its row.** A tapped row commits its tick when it has closed: at the
  end of its 440 ms animation (after 260 ms with reduced motion). Until then the tick was in
  neither the queue nor the device's cache. It was lost when the row went away first, and it
  waited when no frame was drawn. The commit at the row's end is unchanged; three more were
  added (`app/lib/list/list_view/item_row.dart:68-136`, `shopping_list_view.dart:342`):
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
  - **No frames** (a tab behind another whose hide the browser did not report): a wall-clock
    timer commits 880 ms after the tap, twice the close. It is the fallback only: a row that
    draws commits at its animation's end, as on main, so a first frame that comes late cuts
    nothing off the close (review 1; the first version's timer ran at 440 ms from the tap).
- **A closing list arms no timer.** `ListCubit.close()` awaits the channel's end. A write or a
  reload answered in that window armed the 3 s retry, the 1.5 s usuals reload or the 300 ms
  save on a list that was already gone (`list_cubit.dart:1926`, `:1952`, `:1970`). The state
  still shows the answer; nothing is scheduled.
- **A gateway's 401, 408 or 429 refuses no change.** postgrest-dart sets the error code to the
  HTTP status when the body is no PostgREST error. Only 5xx counted as trouble, so a 401, 408 or
  429 from a proxy in front of the database dropped the queued change with "Änderung abgelehnt".
  They now count as trouble: the change stays queued and is sent again
  (`list_repository.dart:138-148`). A 401 with a PostgREST body (PGRST301, PGRST303) already did.
- **A merge whose follow-up read fails is the server's trouble, not "offline".** After
  `merge_items` answers "item gone" (P0002) the repository reads both rows. On main a 503 on
  that read came out of the record's `.wait` as a `ParallelWaitError`, which the cubit took for
  no connection: the op stayed queued (nothing was refused or lost), and the list said offline
  while the server was answering. Both reads are now awaited with `Future.wait`, the 503 is
  `ServerTrouble`, and the list says "Sync gestört" as for any other 5xx
  (`list_repository.dart:516`).
- **A start asks until the server's households show and the write to the device went
  through.** `SessionCubit._load` marked the user as loaded when its own read returned
  without an error, also when that read's answer had been dropped as the older one. So
  when a second reload (resume, the switcher, a second auth event) passed the first and
  then failed, nothing asked again: stale households with a cache, the loading screen
  until a restart without one. The user now counts as loaded once an answer shows and its
  write to the device returned without an error (`session_cubit.dart:617-622`), and
  `_load` asks again 3 s later while that has not happened (`:435`, `:457`). What the 3 s
  timer and an auth event then do depends on what the start has seen (`_passedFor`,
  `:314`; `_waitsFor`, `:448`):
  - **Until one of the start's reads came back:** a read that failed is sent again after 3 s,
    whatever else is out, and an auth event sends a read. Main did both.
  - **Once a start read came back and its answer was dropped** (where main stopped asking for
    good): the start waits while the newest reload is out or an order change is on its
    way to the server. While it waits, the timer looks again 3 s later and an auth event
    sends nothing. Both ask the one rule, `_waitsFor`: the timer at `:471`, an auth event
    at `_load`'s guard (`:407`). The newest reload is waited for because a new read would
    drop its answer as the older one (`_reading`, `:322`). An older reload is not waited
    for: its answer is dropped in any case. An order change (`reorderHouseholds`, counted
    in `_reordering`, `:330`) is waited for because a read sent then answers the old
    order, which would show again and go to the device until the order change's own
    reload answered (reviews 6 and 7, measured under "An order change on its way"). A
    reload the app sends itself (a resume, the switcher) is not held, as on main. The
    wait ends where the asking ends: with an answer shown and written, a sign-out,
    another account's sign-in, or the account's deletion (`:1122`).

  **What "the write went through" means in the app.** The app's only store is
  `DeviceCache`, and its `_write` drops every write error (`app/lib/app/device_cache.dart:468-474`,
  the same on main; this job does not touch it). So in the app the write always returns
  without an error and the asking ends when it has returned, whether the device kept the
  households or not: one read in 120 s with the app's store over preferences that refuse
  every write, on main and on the head (review 6's rows, run again here). Every sentence,
  test and probe row below about a write that fails, and "kept on the device" where a
  write fails in the row, holds for a store that throws, which today is the tests' store
  only. A write that takes time is real in the app too: the cubit awaits it, and the
  asking does not end while it runs.

  The start differs from main in five ways. Each is measured under "The start against
  main" below; none is claimed equal or better by argument.
  1. **The asking ends when an answer shows and its write to the device went through,
     whichever reload brought it.** On main it ended when the start's own read returned.
     So it goes on after a dropped answer (the fix). And it ends once another reload's
     answer showed and was written, where main read again 3 s after the start's own read
     had failed, and every 3 s while those reads failed: the head sends fewer reads there.
  2. **After a dropped answer the asking does not pass the newest reload while it is out,
     and neither its timer nor an auth event sends a read while an order change is on its
     way.** On main nothing was asked in that state. An order change that the server
     refuses or never answers ends that wait: each request ends 15 s after it was sent at
     the latest, two order changes are sent one behind the other, and each one's write to
     the device comes before its request. The households are then read within 3 s of the
     later of the order change's end and the dropped answer; on main they were never read
     again there. Two things read while an order change is on its way, on main and on
     the head alike, and the old order shows again then: the timer after a start read
     that failed, and a reload the app sends itself (a resume: measured; the switcher: not
     driven). That is a defect of main this job does not fix (under "Remaining gaps").
  3. **A read of another account that fails late does not cancel the asking of the account
     signed in over it.** Main's `catch` cancelled the timer whoever had armed it. In four
     hand-built rows main is better in one (9.0 s against 15.4 s), never shows the
     households in two, and is equal in time in one.
  4. **A read that fails after its account signed out arms no timer.** Main's `catch` armed
     the 3 s timer then too. It read nothing when it fired, unless the same account was
     signed in again by then: then it sent a read for the new sign-in. Two generated rows
     show it. In one main shows the households sooner (11.1 s against 15.0 s). In the other
     the head shows them sooner (8.0 s against 12.0 s) and main keeps them on the device
     sooner (12.1 s against 15.2 s). The head with main's timer put back was measured too
     and is not taken (under "The start against main").
  5. **An answer written after a sign-out or an account change does not count for the
     same account when it is back by then, while their households do not show again.** On
     main the earlier sign-in's read, returning then, marked the account as loaded: the
     new sign-in's own read, when it failed, was never sent again. The head sends it again
     after 3 s (two tests, red on main). Once the new sign-in's answer shows, an older
     write that ends after it sets the mark, on main and on the head (review 6's three
     rows, equal on both; with a store that throws, the newer answer's failed write is
     then not read again).

  Kept from main on purpose, each with a test: an answer that shows but whose write to the
  device failed (a store that throws) is read again after 3 s, a reload after the start
  starts no asking (also one that fails while the start's answer is being written), and a
  sign-out or another account's sign-in ends it.

  Ten versions came before this rule. Reviews measured the first four, the sixth, the
  ninth and the tenth against main; the job found the fifth, the seventh and the eighth:
  - The first never waited. Review 1: with reads slower than 3 s and a second auth event the
    households never showed (22 to 37 reads in 120 s in the reviewer's probe).
  - The second waited for any read still out. Review 2: a first read that never answers and a
    second one that failed were asked again at 4.0 s on main and never in that version.
  - The third waited for the newest reload after a failed read too. Review 3: main asked
    again 3 s after the failure whatever else was out; nine of the reviewer's 54 rows were
    worse than main, also on the pushed head `5fd39cd1`.
  - The fourth chose by what had armed the timer: a failed read never waited. Review 4: after
    a dropped answer main asked nothing more, so the newest reload's answer showed. The
    fourth version's failed read, or an auth event, sent a read that passed that reload. In
    the reviewer's two direct rows main showed the households at 8.0 s and 2.75 s; the
    fourth version was still loading at 120 s and at 2.75 s. 18 of the reviewer's 1222
    generated rows were worse than main. The rule now goes by what the start has seen, not
    by which read armed the timer.
  - The fifth (`f5cfb2d2`) ended the asking when an answer showed, also when the device
    write after it failed. Main read again 3 s later, and the device had the households
    then. No probe showed it (their device cache never failed a write); it was found by
    comparing with main's code line by line, and probe 8 measures it.
  - The sixth (`5d21dc45`) marked the user as loaded where the answer shows and took the
    mark back when the write failed. Review 5: while the write ran the mark stood, so a
    timer that fired, a start read that failed or a token refresh inside that window gave
    up for good. With a write of 0.1 to 0.5 s that then failed, the households were never
    kept in the reviewer's five rows; main kept them 3 s later. The reviewer's probe 9 has
    a device store whose writes take time.
  - The seventh (`e60c7585`) marked after the write, for the newest reload's answer only.
    The job's probe 10: a reload sent while the start's own answer was being written made
    that answer an older one, so it did not count. When that reload failed, the seventh
    version asked every 3 s (41 reads in 120 s) with the households shown and kept; main
    sent 2 reads.
  - The eighth (`e3c7b247`) counted a start read's own answer too. Reading it against main
    again found two faults no probe row shows. The same case one step later (the answer
    of a reload, kept after a newer reload was sent, which then failed) still asked on
    where main had stopped. And a start read's answer kept after a sign-out counted when
    the same account was back by then, as on main. Whether an answer counted depended on
    which reload had been sent during a write of a few milliseconds. The ninth rule does
    not ask which reload: an answer that shows and is written ends the asking.
  - The ninth (`bd3d8506`, reviewed on `659c6a93`) is the present rule without the order
    change. Review 6: an order change counts the reloads up before its request, so a start
    read still out is dropped (main's guard). Main asked nothing after that; the ninth
    version read again 3 s later, and when the order change took longer than that to
    reach the server, the read answered the old order. It showed again and went to the
    device for 1.2, 4.2 and 2.0 s in the reviewer's three rows (main: not at all), until
    the order change's own reload answered. No probe showed it: their fake applied an
    order change at once, and they recorded whether households show, not their order.
    The tenth rule's timer sent no read while an order change was on its way.
  - The tenth (`67249a83`, reviewed on `03b409a8`) held the timer only. Review 7: an auth
    event after the dropped answer (a token refresh, an offline one) goes through
    `_load`'s guard, which did not ask about the order change. Its read answered the old
    order, which showed again and went to the device for 0.1 to 6.1 s in the reviewer's
    eight rows with an accepted order change (main: not at all). The wait had been put at
    one of the two doors to the read. The eleventh rule (`42b6429a`) puts it in the one
    waiting rule both pass. Reading the eleventh against main once more found one place
    where its guard held an event that main reads on: main forgets that the start was
    loaded when the account is deleted, and the wait was not forgotten there. `592009a5`
    forgets it too (one test, red on `42b6429a`, green on main's code).

## The map: error paths and their tests

Checked against main `3344381d` on 14 November. The measurements under Proof ran on the
base `88d0fbdc`; main `683990d8` was merged in on 15 November (it changes none of the
job's test files and, of the files the job changes in `app/lib`, only
`shopping_list_view.dart`), and what was run again on the merged head is named there.
Main `c3ea4261` was merged in after that (#477 and #475: in `app/` it changes the household
switcher, its tests and the generated strings, nothing under `app/lib/session`,
`app/lib/list` or the job's tests); the whole suite ran again on it.
The tenth version (`67249a83`) came after that merge: the failing-first run, the mutants,
the twelve start probes and the order-change grid ran on it, each named under Proof.
Main `5c09754b` was merged in last (#478: the household switcher's voice row, its tests
and two strings; nothing under `app/lib/session`, `app/lib/list` or the job's tests); the
whole suite ran again on it.
The eleventh version (`42b6429a` and `592009a5`) came after that merge: the failing-first
run, the mutants, the twelve start probes, the order-change grid and reviews 6 and 7's
direct rows ran on `592009a5`, each named under Proof.
Main `0c4eb818` was merged in last (#479 and #458: in `app/` one line in
`lib/list/model.dart`, a pharmacy name, and its test; nothing under `app/lib/session`, in
the files the job changes or in the job's tests); the whole suite ran again on it.
Review 8's five tests (`5c29dae4`, no change to `app/lib`) and main `377f1a0f` (#480: job
215's store screenshots and their docs, nothing under `app/`) came after that; the
failing-first run and the mutants ran again on `5c29dae4`, the whole suite on both.
The line numbers are `592009a5`'s. "UNTESTED" means no test injects that failure. Paths are
`app/test/...` unless they start with `e2e/`.

### The list (queue, retry, conflict, auth expiry, partial failure, reconnect)

| Path | Tests | State |
| --- | --- | --- |
| Offline ops stay visible, queue, flush on reconnect | `list/list_cubit_test.dart:264`, `:288`; `e2e/tests/connectivity.spec.ts:6`, `live-sync.spec.ts:105`, `offline-start.spec.ts:32` | covered |
| Queue across restarts | `list_cubit_test.dart:1740` (group), `list/hidden_queue_test.dart` | covered |
| A tick inside the row's leave: app hidden, row disposed, no frames, household switched | `list/item_row_test.dart:198` (group, 9 tests), `list/list_screen_test.dart:374`, `list/hidden_queue_test.dart:114`, `e2e/tests/tick-leave.spec.ts` | **was UNTESTED and lost; fixed here** |
| A refused op is dropped, reported, the view resyncs | `list_cubit_test.dart:321`; `e2e/tests/list-header.spec.ts:76` (no refusal on 503) | covered |
| 5xx and transient SQLSTATEs keep the op ("Sync gestört") | `list_cubit_test.dart:370` (job 161), `:476` (job 165); `list/list_repository_test.dart:73` | covered |
| Expired token mid-write (PGRST301/303) | `list_repository_test.dart:73-74`; `e2e/tests/offline-start.spec.ts:122` | covered |
| 401, 408, 429 without a PostgREST body | `list_repository_test.dart:127` | **was UNTESTED and dropped the change; fixed here.** No e2e |
| Merge (rename onto an open item) with the item gone, follow-up read fails | `list_repository_test.dart:1195` | **was UNTESTED and shown as offline; fixed here** |
| Conflicts: same-name add, tick replayed onto the partner's item, rename onto open | `list/sync_regressions_test.dart` (6 seeds), `fuzz/sync_fuzz_test.dart:93` (seeds 1 to 100 per run); `e2e/tests/already-on-list.spec.ts:20`, `rename-onto-open.spec.ts:63`, `:82` | covered |
| Overlapping resyncs, a failed one, missed changes | `list_cubit_test.dart:343`, `:349`, `:359` | covered |
| Realtime: join gap, `phx_close`, socket close, dead-but-open socket, freeze and resume | `list_cubit_test.dart:645` (job 166), `:1261`, `:1299`, `:1319`; `e2e/tests/live-sync.spec.ts:130`, `:206-235`, `connectivity.spec.ts:35` | covered |
| Start and resume grace | `list_cubit_test.dart:937` (job 212); `e2e/tests/offline-start.spec.ts:32` | covered, policy untouched |
| Answers that arrive while the list closes | `list_cubit_test.dart:1987-2065` (three tests) | **was UNTESTED; timers armed; fixed here** |
| A send that never answers (no HTTP timeout on writes) | none | UNTESTED, open by decision (below) |
| A resync read that never answers | none | UNTESTED, open (job 122's finding stands) |
| Delete wins over a replayed add | none (`docs/hillclimb/hc-sync-proposals/put_item_delete_wins.sql` is a proposal) | UNTESTED, open |
| Fuzz fake: JWT expiry, catalog edits, `place_item`/`move_item`, single dropped events, four devices | none | UNTESTED, open (job 99's list) |
| Resume resubscribes a down channel at once | none | UNTESTED, open (job 212's "Not done") |
| Flight mode on a real phone | none | UNTESTED, needs a phone |

### Around the list

| Surface | Tests | UNTESTED |
| --- | --- | --- |
| Session start: no network, retryable auth error, switch in flight | `session/session_cubit_test.dart:65`, `:79`, `:92`, `:98`, `:699`, `:718` | A start read that never answers (no timeout, below) |
| Session start: a read passed by a newer one, which failed or is slower than the retry; an answer the device did not keep, or kept while another read was out or after a sign-out; another account signed in over the first; an order change on its way | `session/session_cubit_test.dart:756` (group, 69 tests) | **was UNTESTED and stuck; fixed here** |
| Session writes after a lost answer (create, leave, unarchive) | `session_cubit_test.dart:467`, `:525`, `:541`, `:619`, `:634`; `e2e/tests/onboarding.spec.ts:153`, `:379` | Join after a lost answer (`_unansweredJoin`) |
| Forced sign-out | `session_cubit_test.dart:114`, `app/device_cache_test.dart:119`, `:128` (the forget is pinned) | A refused token refresh signs out and drops the queued ops with the device's data: intended, never warned (below) |
| A non-retryable auth stream error | `session/login_screen_test.dart:52` only | `SignedOut` without clearing `_loadedFor` |
| Household switch with a queue | `list/hidden_queue_test.dart:92`, `:158`, `:179`, `:193`, `:212` | none ranked |
| Network watch | `app/network_test.dart:66`, `:90`, `:107` | none |
| Trips | `trip/trip_cubit_test.dart:450`, `:466`, `:488`, `:630`, `:665` | A save answered after `close()` (sent again by id, harmless) |
| Grocery log | `log/log_cubit_test.dart:54`, `:64`, `log/trip_prompt_test.dart:262` | Overlapping refreshes are unordered (cosmetic) |
| Entitlements | `purchases/entitlements_test.dart:57`, `:68`, `:164`, `:291`, `:610` | A first read that fails with the socket up: unknown until resume |
| Invites, join | `household/invites_poll_test.dart:65`, `household/invite_sheet_test.dart:287`, `household/onboarding_test.dart:128`, `:144`, `:540` | `create` without a request id (a lost answer and a retry make two invites) |
| Realtime channels other than the list's (entitlements, own join requests, a household's join requests, invites) | none closes or errors one | After a server `phx_close` the library never rejoins and the app does not either (below) |
| Feedback | `feedback/feedback_cubit_test.dart:97`, `:117`; `e2e/tests/feedback.spec.ts:180`, `:208`, `:299` | none |

## Proof

- **Failing first.** The job added 87 Dart tests, all named "(job 222)" (session 69, item row
  9, list screen 3, list cubit 3, repository 2, household switch 1). Run at the head
  `781db370` against main's `app/lib` (`0c4eb818`): 34 fail, 53 pass. The 67 tests of the
  tenth version gave 31 and 36 against main `c3ea4261`; the eleventh version added seven
  tests, two red on main and five that pass there (74: 33 and 41 against `5c09754b`);
  review 8's five tests all pass on main (79: 33 and 46), and of review 9's eight one
  is red there.
  - The 34 are the fixes' tests, red without the fix: 15 of the four list fixes and 19 of
    the start's. Three of the start's are red on main for a side effect only: a 3 s timer
    that main arms after a sign-out, after the cubit closed, and for the first account once
    another signed in. The tests assert that none is pending. On a closed cubit the timer
    does nothing when it fires. After a sign-out or an account change it reads if the
    account it was armed for is signed in again by then: the fourth difference above.
  - 33 of the 53 pin a fault an earlier commit of this branch had. Each was run against
    that commit's `app/lib` and is red there (in brackets the last commit it is red on): a
    late first frame cutting the close short (`3176c80b`), the retry passing a slower
    reload (three tests, `3176c80b`), the retry reading for an account that signed in over
    the first (`94574c39`), the retry waiting for an older read (two tests: a first read that never answers, and
    a failed start read with an order change on its way and an older reload still out;
    `cf0502ff`), the retry
    waiting after a failed start read (three tests, `bb6775e8`), the retry's timer reading
    on a closed cubit (`bb6775e8`), review 4's two classes (`b243599f`), an answer not
    kept on the device ending the asking (two tests, `f5cfb2d2`), an answer still being
    written ending it (review 5; four tests, `5d21dc45`), a reload that fails during the
    write of the start's answer asked again for good (three tests, `e60c7585`), the
    same one reload later (`e3c7b247`), the timer's read while an order change is on its
    way after a dropped answer (four tests: the order change before the answer, after
    it, after it while an older reload is still out, and two one behind the other;
    `659c6a93`, the ninth version's `app/lib`), an
    auth event's read in that window (three tests, one of them with an older reload
    still out; `67249a83`, the tenth version's), and
    an auth event held after the account was deleted (three tests: with an order change
    on its way, with none, where the read before it is still out, and with a reload out
    at the deletion; `42b6429a`).
  - 20 guard what main already did, so the fixes cannot undo it: a failed start read is
    asked again after 3 s, a first read passed by one that answered is not, a sign-out or
    another account's sign-in while the read is out ends the asking, another account's
    sign-in after a dropped answer ends it too and the answer is forgotten (two tests), a
    sign-out forgets a dropped answer, a reload after the start whose device write fails
    starts none, an account without a household has its answer too, a start read that
    failed is sent again after 3 s also while an order change is on its way (three tests:
    the order change started after the failure, before it, and two of them before it), a
    sign-out and a sign-in again while an order change is on its way after a dropped
    answer reads at once (three tests: one order change, two, and the sign-in before the
    device forgot the session), so does the first account back over another that signed
    in meanwhile (two tests: one order change and two; review 8's and 9's rows: no
    earlier commit failed these seven tests, fifteen mutants fail at least one of them,
    three of them review 8's and four review 9's), a household
    switched to while the start's answer is being written changes nothing (the answer
    counts and nothing more is read; review 6's surviving mutant), a hidden app commits
    no tick that was not made, and an app that is only inactive commits none.
  - The tests that fail against each earlier `app/lib` of this branch: 28 on `3176c80b`
    (the first pushed head), 28 on `94574c39`, 27 on `cf0502ff` (the second pushed head,
    rebased), 25 on `bb6775e8`, 22 on `b243599f`, 21 on `f5cfb2d2`, 19 on `5d21dc45`, 17 on
    `e60c7585`, 16 on `e3c7b247`, 12 on `659c6a93` (the ninth version), 5 on `67249a83`
    (the tenth), 3 on `42b6429a`, none on the head. Four tests are red on main and on
    most of those trees. One on main and the first nine trees: an answer kept after a
    newer read was sent ends the asking, the ninth rule itself (main sends 6 reads in
    it, the head 3). Three on main and the first ten: after an answer dropped by an order
    change that the server then refuses (two tests, one with an older reload still
    out), or never answers, the households are read
    within 3 s of the refusal, or of the call's end after 15 s (main never reads them
    again; the ninth version read at 4 s, while the order change was still on its way;
    why versions one to eight fail them was not looked at).
- **Mutation check** (`app/lib` changed by a script, the named tests run, the tree compared with
  the commit before and after):

  | Mutant | Tests that fail |
  | --- | ---: |
  | No commit when the row goes away | 5 |
  | No commit when the app is hidden | 4 |
  | No commit at the row's end, the timer only | 11 |
  | No timer for a row that draws no frames | 1 |
  | The no-frames timer at the close's own 440 ms (the first version) | 2 |
  | The row's listener for the app going away is never ended | 1 |
  | The tick is committed when the app is only inactive | 1 |
  | A tick after the view ended is dropped | 1 |
  | The shown list is not held until its rows are gone | 1 |
  | The hold is let go before the rows' ticks | 1 |
  | Closing list: retry timer armed | 1 |
  | Closing list: usuals reload armed | 1 |
  | Closing list: debounced save armed | 1 |
  | Closing list: its queue is not saved | 1 |
  | Gateway 401/408/429 refuse again | 1 |
  | Merge follow-up reads with a record's `.wait` (main) | 1 |
  | Start: no asking again (main) | 35 |
  | Start: loaded once its own read returned (main) | 14 |
  | Start: asks again also when the answer shows | 23 |
  | Start: never waits for a reload still out (the first version) | 8 |
  | Start: a reload that ended still counts as out | 8 |
  | Start: after a dropped answer, waits also when nothing is out | 12 |
  | Start: asks again without the signed-in check | 6 |
  | Start: asks again without the closed check | 1 |
  | Start: another account's asking is cancelled before the check | 2 |
  | Start: an older timer is not cancelled | 2 |
  | Start: a timer left by another account reads for the one signed in over it | 2 |
  | Start: waits for any reload still out, an older one too (the second version) | 2 |
  | Start: a newer reload starting does not take the number over | 7 |
  | Start: a failed read waits for the newest reload too (the third version) | 22 |
  | Start: waits for the reload started last, also once it is no longer the newest | 2 |
  | Start: waits also when one number passed the reload out | 2 |
  | Start: the timer fires without the closed check | 1 |
  | Start: a read that failed after a dropped answer no longer waits (the fourth version) | 1 |
  | Start: an auth event reads although the start waits (the fourth version) | 5 |
  | Start: a timer that finds the start waiting is not set again | 5 |
  | Start: the wait after a dropped answer lasts one more period only | 11 |
  | Start: a dropped answer is remembered across a sign-out and another account | 7 |
  | Start: a dropped answer is forgotten at sign-out only, not when another account signs in | 3 |
  | Start: a read that failed counts as a dropped answer | 9 |
  | Start: the rule inverted, a failed read waits and a dropped answer does not | 25 |
  | Start: a read that failed is asked again after 1 s, not 3 s | 17 |
  | Start: a dropped answer waits only if a reload is out at the moment it is dropped | 8 |
  | Start: a read of the first account that fails ends the asking of the one signed in over it (main) | 1 |
  | Start: answered where the answer shows, kept on the device or not (the fifth version) | 8 |
  | Start: answered where the answer shows, taken back when the write fails (the sixth version) | 6 |
  | Start: answered by the newest reload's answer only (the seventh version) | 5 |
  | Start: answered by an answer kept when another account is signed in already | 1 |
  | Start: answered by its own reads' answers or the newest reload's only (the eighth version) | 4 |
  | Start: answered by an answer kept after a sign-out when the same account is back by then (main) | 2 |
  | Start: answered by an answer kept while another account's households show | 1 |
  | Start: answered only by an answer kept while a household shows, not while none is theirs yet | 1 |
  | Start: once answered, the timer of a dropped answer still waits for a later reload | 1 |
  | Start: an auth event while the start waits starts the 3 s over | 1 |
  | Start: a dropped answer is remembered also when another account signed in before it came | 1 |
  | Start: a dropped answer is forgotten when another account signs in, not at a sign-out | 4 |
  | Start: a read that failed waits like a dropped answer when a newer reload is out at that moment | 1 |
  | Start: a read that failed waits like a dropped answer when an asking is already armed | 1 |
  | Start: after a dropped answer the timer fires without the closed and signed-in check | 1 |
  | Start: an order change on its way is not waited for (the ninth version) | 10 |
  | Start: an order change is waited for also after a read that failed | 10 |
  | Start: an auth event reads while an order change is on its way, the timer does not (the tenth version) | 3 |
  | Start: the timer reads while an order change is on its way, an auth event does not | 3 |
  | Start: an order change counts as on its way only once the device has the order (review 7's survivor) | 1 |
  | Start: one order change that ends takes all of them as ended (review 7's survivor) | 1 |
  | Start: an order change that changes nothing counts as on its way for good (review 7's survivor) | 1 |
  | Start: an order change the server never answered still counts as on its way (review 7's survivor) | 1 |
  | Start: an order change forgets the dropped answer (review 7's survivor) | 4 |
  | Start: a deleted account keeps the wait (`42b6429a`) | 3 |
  | Start: an order change holds only while no read is out (review 8's survivor) | 3 |
  | Start: a read that failed while an order change is on its way counts as a dropped answer (review 8's survivor) | 3 |
  | Start: a deleted account keeps the wait unless an order change is on its way (review 8's survivor) | 2 |
  | Start: a sign-out while an order change is on its way keeps the dropped answer (review 8's survivor) | 3 |
  | Start: another account's sign-in while an order change is on its way keeps the dropped answer (review 8's survivor) | 2 |
  | Start: an auth event is held by an order change only while no read is out, the timer as on the head (review 9's survivor) | 1 |
  | Start: the timer is held by an order change only while no read is out, an auth event as on the head (review 9's survivor) | 1 |
  | Start: a read that failed while two order changes are on their way counts as a dropped answer (review 9's survivor) | 1 |
  | Start: a read that failed while an order change is on its way and another read is out counts as a dropped answer (review 9's survivor) | 1 |
  | Start: a deleted account keeps the wait when a read is out at the deletion (review 9's survivor) | 1 |
  | Start: a sign-out forgets the dropped answer only once the device forgot the session (review 9's survivor) | 1 |
  | Start: a sign-out while two order changes are on their way keeps the dropped answer (review 9's survivor) | 1 |
  | Start: another account's sign-in while two order changes are on their way keeps the dropped answer (review 9's survivor) | 1 |
  | Start: an order change that ended still counts as on its way | 4 |
  | Start: an order change counts as on its way only until the device has the order | 10 |
  | Start: an order change that the server refused still counts as on its way | 4 |
  | Start: answered only while the very answer still shows, no switch or order change since (review 6's survivor) | 1 |
  | The tick is committed when the app comes back as well | 1 |
  | The row commits one frame after the app comes back | 1 |

  All 88 fail at least one test (1 to 35 each). Run on `781db370`, whose `app/lib` is
  `592009a5`'s (the last commit of the job that changes it) with main `0c4eb818` merged
  in. Review 9's eight tests brought eight mutants (one test each) and one to five more
  failing tests to 30 of the 80 before, which ran on `5c29dae4` (1 to 31 each). Review
  8's five tests had brought five mutants (one test each) and one to three more
  failing tests to 14 of the 75 before, which ran on `592009a5`. The 67 of the tenth version ran on `67249a83`; on the
  eleventh, 14 of them fail 1 to 5 more tests (the seven new tests), the other 53 the
  same number. The 61 of the ninth version ran on `e5462c15` and on the merged head
  `a4f5efde` with the same count each.

  Review 1 ran 30 mutants of its own: 26 failed a test, two were equivalent to the code, and two
  showed lines no test pinned (the row's listener never ended, the closed check of the start's
  retry). Both are in the table now. Review 2 ran 40: 36 failed a test, two were equivalent, and
  two showed behaviour no test pinned (an app that is only inactive commits nothing; a closing
  list still saves its queue, which is main's behaviour). Both have a test and a row above
  now. Review 3 ran 19 on the third version: 15 failed a test, one was equivalent, and three
  survived (the retry waiting for a reload that is out but no longer the newest, in two
  forms, and a row committing when the app comes back). All three have a test and a row now.
  Review 4 ran 10 on the fourth version: by its table 4 failed a test and 6 survived (its
  summary line says 5 and 5), none of the six equivalent (a failed read that waits when a
  newer reload is out at that moment, or when an asking is already armed; a wait that lasts
  one more period only; a dropped answer that waits only if a reload is out at that moment;
  no check when a dropped answer's timer fires; a row committing one frame after the app
  comes back). Each has a test now and, in the present rule's form, a row above.
  Review 5 ran 12 on the sixth version: its three controls failed a test and nine survived.
  One of the nine was the must-fix's own candidate (answered only once the answer is kept),
  which is the rule now. Four have a test and a row above: a dropped answer remembered when
  another account signed in before it came, a dropped answer forgotten when another account
  signs in but not at a sign-out, an auth event that starts the 3 s over, and the wait
  without the loaded check (which the reviewer took for equivalent). Three changed how the
  sixth version took its mark back, which is gone; what an answer kept across a sign-out or
  two accounts does has four rows above. One is not pinned: a write of the told removals
  that fails during the start (under "Remaining gaps").
  Review 6 ran 12 on the ninth version: nine failed a test and three survived. Two of the
  three are equivalent for a user and the server (an idle timer that reads nothing; a
  flag set that is set already). The third was not: the mark only while the very answer
  still shows, so a household switch during the device write sent one more read. It has
  a test and a row above now.
  Review 7 ran 13 on the tenth version: four failed a test and nine survived. Three of
  the nine change nothing that shows by the reviewer's reading of the code (not run),
  and one was the must-fix's own candidate (the guard that also holds, the rule now).
  Five changed what a user sees in the reviewer's rows: an order change that counts only
  once the device has the order, one ending that takes all as ended, one that changes
  nothing counting for good, one the server never answered counting on, and an order
  change that forgets the dropped answer. Four new tests pin them, and each has a row
  above.
  The script and its output are with the job's research files, not in the repo.
- **The start against main.** Ten probes drive `SessionCubit` under fake time through
  scripted reads and events. Probes 1 to 8 print when the server's households first show
  within 120 s and how many reads were sent. Probes 9 and 10 also print when the device
  has kept them; their device store takes time for a write and fails writes until a set
  moment (a store that throws: the tests' store, not the app's, which drops a failed
  write's error; the rows with slow writes that work are the app's case too). Each ran against main's `app/lib` (`88d0fbdc`) and against the head's
  (`bd3d8506`, the ninth version; the table's numbers are its). All ten, and the two direct
  runs below, ran again on the merged head `a4f5efde` and on main `683990d8`: every printed
  row is the same as before the merge, on both sides. All twelve ran once more on the
  tenth version (`67249a83`) and on the eleventh (`592009a5`): every printed row is the
  ninth version's, line for line.
  Their order changes are answered at once, so they cannot tell the three apart; the
  rows under "An order change on its way" and the two sections after it do. Main `c3ea4261` was not run for all of
  them: `session_cubit.dart` is the same file as on `683990d8`, and review 6 ran probes
  7 and 8 and the two direct runs on it, with the stored output. "Equal" is the same
  times and the same number of reads.

  | Probe | Rows | Equal | Same times, head fewer reads | Same times, head more reads | Head sooner, or main never | Main sooner |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | 1: review 1's rows | 36 | 36 | 0 | 0 | 0 | 0 |
  | 2: review 2's rows | 24 | 20 | 0 | 0 | 4 | 0 |
  | 3: review 3's rows | 54 | 48 | 0 | 0 | 6 | 0 |
  | 4: review 4's rows (22 by hand, 1200 generated), answers by position | 1222 | 1031 | 72 | 66 | 51 | 2 |
  | 5: the same rows, answers by the time a read is sent | 1222 | 1035 | 69 | 73 | 45 | 0 |
  | 6: as 5 with another seed, 6000 generated | 6022 | 5072 | 354 | 368 | 227 | 1 |
  | 7: another account over the first, whose read fails late (by hand) | 4 | 0 | 0 | 1 | 2 | 1 |
  | 8: the device write after a shown answer fails (by hand) | 3 | 3 | 0 | 0 | 0 | 0 |
  | 9: review 5's rows (18 by hand, 3000 generated), device writes that take time and fail | 3018 | 2649 | 76 | 191 | 102 | 0 |
  | 10: as 9 with another seed (12 by hand, 3000 generated) | 3012 | 2668 | 75 | 163 | 104 | 2 |

  - **Probes 1 to 3:** in the ten rows where the head is better main never showed the
    households.
  - **Probe 4** gives the n-th read the n-th answer, so a version that sends one more read
    moves every later answer. Its two "main sooner" rows are that: in probe 5 the head shows
    the households sooner in one (G527: 2.0 s against 5.0 s) and neither shows them in the
    other (G1078). Probes 5, 6, 9 and 10 decide an answer by when the read is sent, so both
    versions get the same answer for a read sent at the same time.
  - **More reads** (73 and 368 rows in probes 5 and 6): in 68 and 348 of them neither version
    shows the households in 120 s. The head asks every 3 s against a server that fails every
    later read (up to 41 more reads in 120 s), where main stopped after a dropped answer. The
    most reads in a row that never shows are 51 on both. In the other 5 and 20 rows the
    households show at the same time with 1 to 3 more reads.
  - **Fewer reads** (69 and 354 rows): the first difference. Main went on reading every 3 s
    after another reload's answer had shown; the head sends 1 to 40 fewer reads (G9: 3
    against 43).
  - **Head sooner** (45 and 227 rows): main never shows the households in 43 and 211 of them;
    in the other 2 and 16 the head shows them 0.5 to 7.5 s sooner. Rows that never show: 231
    against main's 274 in probe 5, 1251 against 1462 in probe 6.
  - **Main sooner in probes 5 and 6:** one row of the 7244, G5984 of probe 6. It is the
    third difference, and probe 7 is built around it:

    | Row | Main | Head |
    | --- | --- | --- |
    | X1 (G5984): the first account's read fails at 7 s, after the second account's read failed and its next one is out | 9.0 s, 3 reads | 15.4 s, 4 reads |
    | X2: the same failure, nothing of the second account out | never, 2 reads | 8.0 s, 3 reads |
    | X3: X1 with the second account's read never answering | never, 3 reads | 15.4 s, 4 reads |
    | X4: X1 with that read failing | 19.0 s, 4 reads | 19.0 s, 5 reads |

    On main the first account's late failure cancels the second account's 3 s timer. In X1
    and X4 another read of theirs is out, so the cancel saves a read, and 6.4 s in X1,
    where that read answers. In X2 and X3 it ends their asking. The head with main's cancel
    put back was measured on probes 5, 6, 7, 9 and 10 (13,278 rows). Its times or reads
    differ from the head's in 33 rows, and in all 33 it equals main:
    - main sooner: X1 and G5984, the same case;
    - main never shows the households: X2 and X3;
    - main never keeps them on the device: two rows of probe 9 (one is review 5's C1), and
      keeps them 4.4 s later in a third;
    - the same times and more reads on the head in 26: in 21 neither version shows the
      households and in one neither keeps them (the server or the device fails to the
      row's end; the head asks on for the account signed in, 1 to 38 more reads, where
      main's cancel had ended its asking), and in 4 the head sends one read more.

    The job kept the asking (`docs/DECISIONS.md`).
  - **Probe 8:** the answer shows and the write to the device fails once, three times, every
    time. Main and the head are the same: 2, 4 and 41 reads in 120 s, and the households are
    on the device after the first write that works. The fifth version (`f5cfb2d2`) sent one
    read in each row and left nothing on the device.
  - **Probes 9 and 10, shown and kept.** The head is sooner, or main never gets there, in
    102 and 104 rows: the device keeps the households on the head and never on main in 81
    and 85, keeps them sooner in 19 and 16 (0.5 to 53.5 s and 1.3 to 53.8 s), shows them
    where main never does in 1 row of probe 9, and shows them sooner in 1 and 3 (0.1 s; 2.0
    to 3.0 s). Rows where the device never keeps them: 615 against main's 697, and 627
    against 712. Rows that never show them: 291 against 292, and 305 on both. Of the 30
    rows by hand 28 are equal; in the other two (review 5's A5 and C1) the device keeps the
    households at 6.5 s and 7.0 s on the head and never on main.
  - **More reads in probes 9 and 10** (191 and 163 rows): in 165 and 146 of them the
    device keeps nothing on either version in 120 s (1 to 39 more reads; the most reads in
    any row are 45 on both). In the other 26 and 17 rows the times are the same with 1 to 17
    more reads: the asking went on after a dropped answer until a later reload's answer was
    kept. **Fewer reads** (76 and 75 rows): 1 to 3 fewer.
  - **Main sooner in probe 10:** two rows, both the fourth difference (a read that failed
    after its account signed out, and the same account back within 3 s of the failure):

    | Row | Main | Head |
    | --- | --- | --- |
    | G1630: the server fails every read until 10 s | shown 11.1 s, kept 11.7 s, 5 reads | shown 15.0 s, kept 15.6 s, 5 reads |
    | G751: the answers take 4 s, the device fails writes until 9 s | shown 12.0 s, kept 12.1 s, 4 reads | shown 8.0 s, kept 15.2 s, 4 reads |

    Main's timer, armed for the sign-in that ended, sends one more read for the new one.
    In G1630 that moves the later reads so that one falls sooner after the server is back.
    In G751 it passes the new sign-in's own read, so main shows the households 4.0 s later,
    at a moment when the device can write again; the head shows them while it cannot and
    reads again 3 s later. The head with main's timer put back was measured on all rows of
    probes 5, 6, 7, 9 and 10. In probes 5, 6 and 7 it gives the head's times and reads in
    every row. In probes 9 and 10 it differs from the head in 16 and 30 rows, in most of
    them only by a timer that fired and read nothing. In 11 of those 46 the head's times
    or reads differ from main's: the two rows above, 4 rows where the head shows the
    households sooner (0.1, 2.0, 2.5 and 3.0 s; in three of them main's extra read passed
    the new sign-in's own read, which was still out) and 5 where the head sends fewer
    reads. With the timer put back all 11 are equal to main. The job did not put it back
    (`docs/DECISIONS.md`): the timer belongs to a sign-in that ended, and a read that
    passes one still out is the fault this job fixes elsewhere.
  - **Main's whole `catch` put back** (for a read that fails when its account is no longer
    the one signed in: cancel whoever's timer and arm one for that account, also when
    another account is signed in), measured on the same 13,278 rows. It differs from the
    head in 44 rows, the 33 and the 11 above and no other, and equals main in all 44. So
    the timer main arms for an account another one signed in over changes no row beyond
    the cancel. With the `catch` put back no row has main sooner, shown or kept; the head
    still differs from main in 1,810 rows, the first and second differences, and in none
    of those is main sooner.
  - **Review 4's two direct rows:** the head and main show the households at 8.0 s with 3
    reads and at 2.75 s with 2. The fourth version was still loading at 120 s and at 2.75 s.
  - **Review 5's five direct rows** (a device write of 0 to 0.5 s that fails, and a timer,
    a failed start read or a token refresh inside it): the head and main are the same in
    all five, 3 reads in 120 s, the households kept, no timer left. The sixth version never
    kept them.
  - **An order change on its way** (review 6's rows as a grid of 66, by hand; the head
    `592009a5`, main `5c09754b` and the ninth version's `app/lib`; the head's 66 rows
    are the tenth version's, line for line, and main's are `c3ea4261`'s). The device's two
    households show at the start, the server has a third, the start's read is slow, and
    the user drags the second household first meanwhile. The read comes back dropped or
    failed (order change at 0.2 s and read back at 1 s or 4 s; order change at 3 s and
    read back at 6 s); the order change takes 0, 2, 2.5, 5 or 8 s and is accepted or
    refused, or never answers (the call ends after 15 s). Each row records for how long
    the old order shows again while the change is on its way or accepted, when the
    server's third household first shows, and the reads, over 40 s.

    | Start read | Rows | Old order shown again: head | main | ninth version | Third household never shows: head | main | Reads head / main |
    | --- | ---: | --- | --- | --- | ---: | ---: | --- |
    | dropped | 33 | none | none | 11 rows, 1.2 to 11.2 s | 0 | 18 | 2 in all 33 / 2 in 15, 1 in 18 |
    | failed | 33 | 11 rows, 1.2 to 11.2 s | the same 11 rows and times | the same | 0 | 0 | 2 in 29, 3 in 4 / 2 in 18, 3 in 15 |

    - **Dropped answer:** no row shows the old order again on the head or on main. The 18
      rows where main never shows the third household are the order changes that were
      refused or never answered: main asked nothing after the dropped answer, and the
      head reads within 3 s of the later of the order change's end and the dropped
      answer (0.0 to 3.0 s after it, at 4.0 to 18.0 s). In 7 of the 18 the order change
      had ended before the answer came back, and the read comes 3.5 to 6.8 s after the
      order change's end (review 7 recomputed this; the sentence had said "within 3 s of
      the order change's end". Review 8 corrected the two ranges: the probe stamps the
      end one 100 ms step early, so they had read 0.1 and 3.6 s; the end counted here is
      the order change's start plus its request time, or plus 15 s when it never
      answers). In the 15 accepted rows the head equals main: the order
      change's own reload brings the answer. In no row does main show the third
      household sooner.
    - **Against the ninth version** the head shows the third household later in the 11
      rows where the ninth showed the old order: by 1.2 to 12.0 s (16.0 s against 4.0 s
      when the order change never answers). That is the wait's price, and main was never
      sooner there.
    - **Failed read:** the head and main show the old order again in the same 11 rows for
      the same times (1.2 to 11.2 s), and the same times for the third household. The
      head sends one read fewer in 11 rows (the first difference: the order change's own
      reload answered, so the asking ended). This is main's behaviour, kept: the wait
      starts only once an answer was dropped, where main read nothing at all. Holding a
      read after a failed start read too would be a change against main that needs its
      own comparison (under "Remaining gaps").
    - All 198 runs end with no timer left. On the head and on the ninth version every
      row ends with the server's households, in the server's order, on screen and on the
      device; on main the 18 rows above end without the third household on either.
    - The grid has no auth event, no resume, one account and one order change per row.
      Review 7's rows, next, add those.
  - **An auth event, a resume, two order changes or a second account while an order
    change is on its way** (review 7's 62 rows, by hand, as two probes; the head
    `592009a5`, main `5c09754b`, the ninth and the tenth version's `app/lib`, and
    `42b6429a`'s, whose 62 rows are the head's line for line). Same start as the grid;
    each row records for how long the old order shows again, when the server's third
    household first shows, and the reads, over 40 s.
    - *Family A, 50 rows:* the order change at 0.2 s (accepted after 2.5, 5 or 8 s,
      refused after 8 s, or never answered), the start read back at 1 s (dropped or
      failed), then a token refresh at 2 s or 5 s, a retryable auth error at 2 s, a
      resume's reload at 2 s, or nothing.

      | Start read | Then | Rows | Old order shown again: head | main | tenth version |
      | --- | --- | ---: | --- | --- | --- |
      | dropped | a token refresh or a retryable auth error | 15 | none | none | 14 rows, 0.1 to 13.1 s (8 of them accepted, 0.1 to 6.1 s: review 7's must-fix) |
      | dropped | nothing | 5 | none | none | none |
      | dropped | a resume's reload | 5 | 5 rows, 0.6 to 13.1 s | the same rows and times | the same |
      | failed | any of the five | 25 | 23 rows, 0.6 to 13.1 s | the same rows and times | the same |

      After a dropped answer and an auth event the head equals main in the nine accepted
      rows (the order change's own reload brings the third household, 2 reads). In the
      six rows refused or never answered the head shows the third household at 10.0 s
      (refused at 8.2 s) and at 16.0 s (the call ended at 15.2 s), and main never; the
      tenth version read at the event (2.0 or 5.0 s) and showed the old order while the
      order change was still on its way. The two rows with a dropped answer, no event
      and an order change refused or never answered are the same: the head at 10.0 s and
      16.0 s, main never. The resume's reload shows the old order on the
      head exactly as on main (main's defect, under "Remaining gaps"). After a failed
      start read the head equals main in the old order's time and in when the third
      household shows in all 25 rows; main sends one read more in 7 of them (the first
      difference).
    - *The other 12 rows,* one each:

      | Row | Head | Main | Ninth version |
      | --- | --- | --- | --- |
      | B: two order changes at 0.2 and 0.5 s, neither answered (they end at 15.2 and 30.2 s), answer dropped at 1 s | third household at 31.0 s | never | 4.0 s |
      | B: the two refused after 8 s each | 19.0 s | never | 4.0 s |
      | B: the two accepted after 8 s each | 16.2 s | 16.2 s | 4.0 s |
      | C: answer dropped at 1 s, the next read fails at 4 s, order change at 5 s accepted after 8 s | 13.0 s, 4 reads | 13.0 s, 3 reads | 7.0 s, old order for 6.0 s after the drag |
      | D: one account's order change never answers, another signs in over it at 1 s and its answer is dropped | its households at 17.0 s | never | 5.0 s |
      | E: one order change whose device write takes 20 s, accepted at once | 20.2 s | 20.2 s | 4.0 s, old order for 16.2 s after the drag |
      | F: an order change to the order already shown, answer dropped at 1 s | 4.0 s | never | 4.0 s |
      | G: answer dropped at 1 s, order change at 3.9 s with a device write of 2 s and a request of 5 s, accepted | 10.9 s | 10.9 s | 4.0 s, old order for 6.9 s after the drag |
      | I: answer dropped at 1 s, order change at 2 s accepted after 8 s | 10.0 s | 10.0 s | 4.0 s, old order for 6.0 s after the drag |
      | I: the same, refused | 10.0 s | never | 4.0 s |
      | I: the same, never answered | 19.0 s | never | 4.0 s |
      | H: order change at 0.2 s never answers, answer dropped, sign-out at 1 s, the same account back at 2 s and its answer dropped at 3 s | its households at 18.0 s | never, stays signed out | 6.0 s |

      On the head and on main no row shows the old order after its drag. The tenth
      version's twelve rows are the head's. In no row of the 62 is
      the head later than main. In 15 main never shows the households and the head
      does, at 4.0 to 31.0 s (the six with an auth event, the two with none, seven of
      these twelve; review 8 counted them, the summary had said 13); there the head
      waits for the order changes' end, which the ninth version did not. All 310 runs (62 rows
      on five trees) end with no timer left.
  - **The account deleted after a dropped answer, an order change still on its way**
    (24 rows by hand: the device's sign-out takes 5 s or throws; the order change is
    accepted after 8 s or never answers; the server still answers reads or fails them;
    a token refresh or a retryable auth error 0.5 s after the deletion, or none; on the
    head `592009a5`, main `5c09754b` and `42b6429a`). The head prints main's row in all
    24, state by state and read by read. `42b6429a` differs in the 16 rows with an auth
    event: it holds the event's read (1 or 2 reads where main and the head send 2 to
    12), because the deletion left the start's wait in place. That is the one line
    `592009a5` adds. Two things the rows show are main's and stay: with a sign-out that
    throws and a server that fails, the event starts main's 3 s asking for the account
    still signed in (a timer armed at 30 s on main and the head, 11 or 12 reads); and
    the deleted-account notice is replaced when an accepted order change's own reload
    comes after the deletion (`SignedOut` without the notice at 8.2 s in the two rows
    with a slow sign-out and no event), and by the households when the event's read is
    still answered (at 2.5 s; the fake server answers a deleted account's read in half
    the rows, which a real one would refuse).
  - **Review 6's other direct rows,** run again on the head, on main and on the ninth
    version's `app/lib` (and once more on `592009a5` and main `5c09754b`: the head's
    rows are the tenth version's, line for line):
    - *The app's store over preferences that refuse every write* (3 rows): the same on
      all three. `remember`, `rememberToldRemovals` and `forget` return, nothing is kept,
      and a start sends 1 read in 120 s and leaves no timer. With the tests' store that
      throws: 41 reads and a timer armed at the end.
    - *An older write that ends after a newer answer shows* (4 rows): the same on all
      three (the fifth difference's limit, above).
    - *An auth stream error that leaves the session* (a bad sign-in link; 4 rows): after
      the device write both stay `SignedOut` with 1 read; after a failed start read both
      show the households at 3.0 s with 2 reads; while the read is out both show them at
      0.2 s. During the device write the head reads again at 3.2 s and shows the
      households (2 reads), main stays `SignedOut` (1 read). Under "Remaining gaps".
    - *The account deleted while the start read is out* (12 rows, a fake whose sign-out
      takes 5 s or throws): with a sign-out that answers at once all three are equal, and
      so are the rows whose start read failed. After a dropped answer, with the slow or
      throwing sign-out, the head reads again at 3.2 s in 4 rows where main sends 1 read
      and keeps the notice. Under "Remaining gaps". (Here the deletion comes while the
      start read is out; the 24 rows above have it after the dropped answer.)
  - **Safety,** every row of probes 5, 6, 9 and 10 on both versions: never more than one 3 s
    timer at a time and no read after a sign-out; in probes 9 and 10, which count it, no
    read for another account than the one signed in. Rows that end with a 3 s timer armed: 147 against main's 70 in probe 5, 746
    against 395 in probe 6, 339 against 247 in probe 9, 350 against 268 in probe 10. The
    asking goes on where main had given up, in main's 3 s rhythm and without backoff.
  - **A second account's late answer shown to the first,** a defect of main that this job
    does not fix: the first account signs in again over a second one before the second's
    read came back. That read is the newest reload, and its answer then shows the second
    account's households while the first is signed in. One row of probe 6 on both versions
    (G3080), and one row each of probes 9 and 10 on main only (G404, G2177): there the
    first account did not count as loaded on the head, so its new sign-in sent a read,
    which passed the second account's. Counted as the rows where shown households go after
    the row's last account event; the probes' "lost again" mark is wider (it also marks a
    row whose own sign-out or account change took them away). Under "Remaining gaps".
  - **Limits.** Fake time. Each row's later reads follow one script: the server answers one
    way until a set moment and another way after it. The device cache fails or delays a
    write in probes 8, 9 and 10 only, and never a write of the told removals. No probe row
    shows the eighth version's two faults (its output is the head's in every row of probe
    9 and in all but one of probe 10, where one timer count differs); only the tests do.
    Generated rows rarely hit an account change with a late failure (one row in 6022);
    probes 7 and 8 are by hand for that reason, and other cases the generators rarely hit
    may be missing. How often several auth events come within seconds on a real device, or
    a sign-out with the same account back within 3 s, is not measured. The ten probes'
    order changes are answered at once; an order change that takes time is in the grid of
    66 rows and review 7's 62 only, which are by hand. The grid (three pairs of times,
    eleven outcomes, two kinds of read) has one account, one order change and no auth
    event per row; review 7's rows add an auth event or a resume at one or two moments,
    and one row each for two order changes, a second account, a sign-out, a slow device
    write and an order change after the answer. A reload the switcher sends in that
    window was not driven. Whether the real auth client sends a token refresh or a
    retryable error while an order change is on its way, and how often, is not
    measured.
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
  - The branch run predates the list hold for a household switch, review 1's fixes and the
    commit back at the row's end. The spec's path (a hidden app commits at once) is the same
    in all of them. Run again with `conventions.spec.ts` at 23:40, one lock hold of 9 min, on
    the tree of `94574c39`: 35 of 35 passed (30 runs of this spec on the three engines, 5 of
    the conventions). The commits after it change the start's retry and add unit tests;
    none is on the spec's path, and CI ran the whole e2e suite on the later heads.
  - CI ran the spec on the first pushed head `3176c80b` on all three engines: 6 of 6 passed.
    That run's `ci-ok` was red all the same, from this job's own mistake: the new spec imported
    from `@playwright/test`, which `conventions.spec.ts` refuses (review 1, must fix 2). Not a
    flake. Fixed, and both specs are in the local run above.
- **Sync fuzz** (`tool/hillclimb/hc-sync/measure.sh`, seeds 1 to 1000, one run each): 0 failures
  on main's `app/lib` (92.1 s) and 0 on the branch (93.0 s). No change, as expected: the fuzz
  calls the cubit directly and none of the fixed paths is in its model.
- **`flutter test`** (whole suite, through the flutter gate, on the eleventh version with
  review 9's eight tests and main `c8a90ce1` merged in, 15 November 11:19, load average
  1.7 at the start): 3277 passed, 98 skipped, none failed, in 1 min 48 s; `flutter analyze` and the
  format check are clean. Before the eight tests, with main `377f1a0f`, at 10:30 (load
  average 0.6): 3269 passed, 98 skipped, in 1 min 35 s. Before review 8's five tests, with main `0c4eb818`, at 09:33 (load
  average 0.2): 3264 passed, 98 skipped, in 1 min 32 s.
  On the tenth version with main `5c09754b`, at 08:23 (load average 2.8): 3257 passed, 98
  skipped, in 1 min 32 s.
  On `67249a83` with main `c3ea4261`, at 08:20 (load average 0.14): 3255 passed, 98
  skipped, in 1 min 34 s. On the ninth version with the same main, at 07:01 (load average 0.64): 3251
  passed, 98 skipped, in 1 min 35 s. On the merged head
  `a4f5efde` with main `683990d8`, at 06:01 (load average 4.8): 3232 passed, 98 skipped, in
  1 min 46 s. Before the merges, `e5462c15` on main `88d0fbdc` at 05:27 (load average 0.66): 3197 passed, 98
  skipped, in 1 min 31 s. Earlier heads on 15 November: 3181 passed at 03:28 (the sixth version, 2 min 44 s), 3168 at 01:36 (the
  fourth). At 00:50, on the base before #472, the suite had 3162 passed, 98 skipped and one failure that was main's, not this job's:
  `list_declutter_test.dart` priced an item on 14 November and a price counts on its own day only,
  so main went red at midnight (job 221's PR #472 fixed the test). On 14 November the suite was
  green: 3161 passed, 98 skipped on the second pushed head in the reviewer's run; the first pushed
  head 3152 passed in 2 min 17 s here and 3 min 15 s in the reviewer's run. The times follow the
  shared box's load.
- **Fable 5.2 review,** each round a fresh `claude-fable-5-2` agent in a shared clone:
  - Round 1 on `3176c80b`: FIX. Two must-fixes, both real and fixed: the start's retry passed
    a reload that was still out and dropped its answer, and `ci-ok` was red from the spec's
    import. Of nine nice-to-haves, three were code or tests (the timer at the close's own
    time, the row's listener unpinned, the closed check unpinned) and are fixed; the others
    corrected this file (the merge fix's "before", stale line numbers, the inferred 401
    sentence, the constant retry for a lasting 401 or 429).
  - Round 2 on `5fd39cd1`: PASS, no must-fix. Round 1's probe passes in all 36 rows. Ten
    nice-to-haves, all taken: the retry waits only for the newest reload (one row where
    main was better; round 3 found more), the two unpinned behaviours got a test each, and the
    rest corrected
    these files ("each seen red" was too strong: the counts under "Failing first" are
    measured now; test counts, line numbers, the HTTP-timeout sentence labelled as inferred,
    two edges under "Remaining gaps").
  - Round 3 on the local head after round 2's nice-to-haves (the third version, not
    pushed): FIX. One must-fix: the sentence that the second version was worse than main in
    one row was false. The reviewer's 54 new rows showed nine where the second and third
    versions were worse than main, all with a start read that failed and a newer reload
    still out. Fixed in the code, not in the sentence: a failed read is asked again after 3 s
    as on main, and only a dropped answer waits for the newest reload (the reviewer's own
    candidate, which its probes had measured as never worse than main). Five nice-to-haves:
    two unpinned behaviours and the closed check when the timer fires are pinned now (two
    tests and one assertion), one sentence in the hill-climb section was corrected, and the
    fifth noted that the delta was not pushed yet.
  - Round 4 on `b243599f` (the fourth version, not pushed): FIX. One must-fix: five
    sentences (four in these files, one in the PR's text) said that a failed read kept
    main's rule exactly and that no wait could be worse than main. The reviewer's probe 4
    and two direct rows showed two classes where main was better (above). Fixed in the code
    (the rule by what the start has seen) and in the sentences. Eight nice-to-haves: six
    unpinned behaviours (its six surviving mutants) have a test each now, one sentence
    about which tree the mutants ran on was corrected, and one found the real-time
    closing test sound (its hint to leave no real timer behind at the test's end was not
    taken: harmless in its 20 runs).
  - After round 4 the job compared the rewrite with main's code line by line and by time,
    with a second seed, and found two more differences itself: the cross-account row
    (kept, a measured trade) and the device write (fixed, the fifth version's fault).
  - Round 5 on `311a6b3c` (the sixth version, not pushed): FIX. One must-fix: the sixth
    version marked the user as loaded where the answer shows and took the mark back when
    the device write failed, so while the write ran, a timer that fired, a start read that
    failed or a token refresh gave up for good. Six sentences and a test title said such a
    start was read again as on main. The reviewer's probe 9 (a device store whose writes
    take time) and five direct rows showed it. Fixed in the code: the mark is set after the
    write. Six nice-to-haves: seven unpinned mutants (four have a test now, three went
    with the sixth version's mark, one is listed as not pinned), the "41 reads, the same on
    main" sentence (true for probe 8's rows only; corrected under "Remaining gaps"), a
    count of earlier versions that did not match, the map's date against the PR's base,
    two findings that are main's (the households lost again, the told removals' write
    chain; both under "Remaining gaps"), and a token refresh inside the write window (gone
    with the mark after the write).
  - After round 5 the job measured each new version against main again, with probe 9 and
    its own probe 10, and read every window between two awaits against main's code. That
    found the seventh version's fault (probe 10) and the eighth's two (by reading; no
    probe row shows them), and the fourth and fifth differences from main above.
  - Round 6 on `659c6a93` (the ninth version with main `c3ea4261` merged in, not pushed):
    FIX. Two must-fixes. One in the code: after a dropped answer the ninth version's timer
    read while an order change was on its way, and the answer put the old order back on
    screen (the reviewer's two direct rows; main sends no read there). Fixed in the tenth
    version: that timer waits for the order change, with three tests, five mutants and the
    grid of 66 rows above. One in the sentences: the files said a device write that fails
    is asked again, which holds for the tests' store only, since the app's store drops a
    failed write's error (the reviewer ran the app's store over preferences that refuse:
    one read in 120 s on main and here). The sentences say so now, in the five files and
    the PR's text. Four nice-to-haves: difference 5's sentence was wider than its tests
    (reworded); an auth stream error during the device write and an account deleted with
    a slow sign-out read once more here than on main (measured again by the job, 4 and 12
    rows, listed under "Remaining gaps", no code); one own mutant that survived and was
    not equivalent (a household switch during the device write: a test and a mutant now).
  - After round 6 the job measured the order change as a grid instead of the reviewer's
    two rows, on main, the ninth and the tenth version, and printed the order shown, not
    only whether households show. That found the same old order after a failed read on
    main itself (11 of 33 rows), which the job left as found and handed to the lead.
  - Round 7 on `03b409a8` (the tenth version with main `5c09754b` merged in, not
    pushed): FIX. One must-fix, in the code: the tenth version held the 3 s timer while
    an order change was on its way, but not the read an auth event sends. After a
    dropped answer a token refresh or a retryable auth error read while the order
    change was out, and the old order came back for 0.1 to 6.1 s in eight of the
    reviewer's rows (main: none). Four files and the PR's text said "this branch stops
    only its own new asking from doing it". Fixed in the eleventh version: the wait is
    one rule, `_waitsFor`, and both doors ask it (the timer and `_load`'s guard), with
    two tests, two mutants (each door alone) and the reviewer's 62 rows run by the job
    on five trees (above). Five nice-to-haves, all taken: "15 s at the most" was no
    bound (two order changes one behind the other, and the device writes; reworded with
    rows B and E); "within 3 s of the order change's end" was false in 7 of 18 rows
    (reworded: of the later of that end and the dropped answer); five of its own
    mutants survived and changed what a user sees (an order change started after the
    dropped answer, two order changes, one that never answers, one that changes
    nothing: four tests and five mutants now); the PR text's `flutter test` line was
    the ninth version's; two gap lines were measured by its rows C, D and H and say so
    now.
  - After round 7 the job compared where main clears its own mark with where the new
    wait is cleared, and found one place missing: an account deletion left the wait, so
    an auth event before the device signed out sent no read while an order change was
    on its way (main reads). One line (`592009a5`), one test red on `42b6429a` and
    green on main, one mutant, and the 24 rows above.
  - Round 8 on `89d28391` (the eleventh version with main `0c4eb818` merged in, not
    pushed): PASS, no must-fix. Five nice-to-haves, all taken. A count: "in 13" rows
    main never shows the households and the head does was 15 (the summary and the PR's
    text). Five of its 16 own mutants survived and changed what a user sees: an order
    change that holds only while no read is out, a start read that fails while an order
    change is already on its way taken for a dropped answer, a deleted account that
    keeps the wait when no order change is out, and a sign-out or another account's
    sign-in that keeps the dropped answer while an order change is on its way. Five
    tests and five mutants now; three of the tests pass on every earlier commit and
    are held by their mutants only. (Of its other three survivors two are equivalent to
    the code by its reading and one is two of the five together.) Two ranges were
    measured from a stamp one 100 ms step early (0.0 to 3.0 s and 3.5 to 6.8 s now). A
    second window of the auth stream error and a return that leaves the wait with no
    timer were measured by its rows N and P, no row worse than main: both are under
    "Remaining gaps" now, and the decision's sentence on the invariant says what the
    check missed. Its whole-suite run: 3264 passed, 98 skipped, in 1 min 44 s.
  - Round 9 on `504f6c6a` (the same code with review 8's five tests and main `377f1a0f`
    merged in, not pushed; a delta round over what changed since round 8): PASS, no
    must-fix. Five nice-to-haves, all taken. Eight of its 13 own mutants around review
    8's five lines survived, none equivalent to the code. In its 16 own rows the head
    prints main's row in 13, and in 3 main never shows the third household where the
    head does (10.0 s twice, 19.0 s). Two of the eight are the two halves of review
    8's first mutant: the wait is asked at an auth event and at the timer, and the test
    pinned the two only together. The other six: a failed start read with two order
    changes on their way, or with one and an older reload out, taken for a dropped
    answer; a deleted account that keeps the wait when a read is out at the deletion; a
    sign-out that forgets the dropped answer only once the device forgot the session
    (under that mutant the same account, back before that, stays on the signed-out
    screen until an accepted order change reloads, or for good); a sign-out or
    another account's sign-in that keeps the dropped answer while two order changes
    are on their way. Eight tests and eight mutants now (`781db370`), each mutant
    failing exactly its one test: one test is red on main, three on an earlier commit,
    four pass on main and on every earlier commit and are held by their mutants only.
    No code changed. Three sentences were corrected: a count in the guards list ("five
    mutants do" was eleven; fifteen with the new tests), the short gap line on the
    auth stream error (main leaves the error screen too when an accepted order change
    reloads), and the wording of review 8's first mutant in DECISIONS. The eight tests
    were not reviewed again: they are checked by their mutants and against main's and
    the earlier trees' `app/lib`.

## Remaining gaps

Labelled, not fixed. The first four, the old order shown again, the two refused order
changes and the replaced deleted-account notice are in `docs/NEEDS_LEAD.md`, "Job 222".

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
- **A start read that never answers is never asked again,** as on main. `_load` has no
  timeout, so a start read that hangs arms no retry. After a dropped answer the asking
  waits for the newest reload while it is out and looks again every 3 s, so a newest reload
  that hangs holds it too (an older one does not, and until a start read came back nothing
  is waited for). An order change on its way holds it as well, until it ends: each
  request ends 15 s after it was sent at the latest, two order changes are sent one
  behind the other, and each one's write to the device comes before its request (the
  households at 31.0 s after two order changes that never answer, where main never
  shows them; at 20.2 s with a device write of 20 s, as on main; review 7's rows B and
  E). On main nothing was asked in that state at all. A timeout would drop a
  slow answer that is still coming (what review 1 found in the first version's retry). What
  ends a dead connection is the platform's (the browser's fetch, the OS's TCP limits;
  `dart:io` sets no response timeout of its own): inferred, not measured.
- **Rows where main shows or keeps the households sooner,** all measured under Proof:
  - The third difference, one row of 7244 and probe 7's X1 (9.0 s against 15.4 s): the
    first account's read fails after another account signed in over it, that account's own
    read failed too, and its next one is out. Main's cancel saved one read there and ended
    the second account's asking in two neighbouring rows.
  - The fourth difference, two rows of 6030 (shown 11.1 s against 15.0 s; kept 12.1 s
    against 15.2 s, where the head shows them 4.0 s sooner): a read that fails after its
    account signed out, and the same account signed in again within 3 s of the failure.
    The head shows the households sooner in four rows of the same kind.
- **A second account's late answer can show to the first,** on main and on the head: the
  first account signs in again over a second one, without a sign-out between, before the
  second's read came back. That read is the newest reload, and its answer then shows the
  second account's households while the first is signed in. `_refresh` drops an answer by
  its number only, not by the account signed in (`session_cubit.dart:518`). One row of
  probe 6's 6022 on both versions; two more rows on main only (probes 9 and 10; the first
  of them found by review 5). Not fixed here: it is not on the path of this job's fix, and
  a fix (drop an answer whose account is no longer the one signed in) needs its own
  comparison with main.
- **An old sign-in's start read that comes back after a sign-out, with the same account
  signed in again,** asks again for the new sign-in (`session_cubit.dart:435`), also as a
  dropped answer, so the new sign-in's asking then waits for its newest reload. On main
  that read marked the account as loaded and the new sign-in's failed read was never sent
  again (the fifth difference). Read from the code and pinned by two tests for the loaded
  mark; the wait it can start is not driven by a test of its own.
- **A read sent while an order change is on its way shows the old order again,** a
  defect of main. This job adds nothing to it and takes nothing from it:
  - After a dropped answer, where main read nothing, the head holds its own asking at
    both doors, the 3 s timer and an auth event (the grid's 33 rows and 20 of review
    7's: no old order, as on main). The tenth version held the timer only (review 7's
    must-fix).
  - After a start read that failed, main's 3 s timer and an auth event read whatever is
    out, and the head keeps that: when an order change takes longer, the read's answer
    puts the old order back on screen and on the device until the order change's own
    reload answers (11 of the grid's 33 failed-read rows, 1.2 to 11.2 s; 23 of review
    7's 25, 0.6 to 13.1 s; the same rows and times on main and on the head).
  - A reload the app sends itself is held on neither. A resume's reload after a dropped
    answer: 5 rows, 0.6 to 13.1 s of old order, the same on main and on the head. The
    switcher's reload was not driven.

  One way to fix it, not tried: `_refresh` drops an answer read while an order change
  was on its way, whoever asked. It needs its own comparison with main. In
  `docs/NEEDS_LEAD.md`.
- **Two order changes refused one behind the other leave the first one's order on
  screen and on the device,** a defect of main (`reorderHouseholds`, job 229): the
  second's refusal puts back the order it found, which is the first's. In review 7's row
  B (both refused after 8 s each) main ends with that order at 60 s while the server has
  the old one. The head shows it for 2.8 s (16.2 to 19.0 s), then its read brings the
  server's order; the row has a dropped start answer, and without one the head does what
  main does (read from the code, not driven). In `docs/NEEDS_LEAD.md`.
- **Another account's order change holds the asking too:** `_reordering` counts every
  order change on its way, not per account. So after a dropped answer, an account that
  signed in over one whose order change is still out waits for that call's end before
  it reads (review 7's row D: its households at 17.0 s, at 5.0 s on the ninth version,
  never on main). The same account back after a sign-out is held too (row H: 18.0 s,
  6.0 s, never). Main asked nothing in that state.
- **An auth stream error during the start answer's device write** (a bad sign-in link
  while the session stays): the head reads again at 3.2 s and shows the households,
  main stays `SignedOut` (one direct row; the other three are equal). The session is
  still there, so the head's result may be the better one; it was not designed and has
  no test. The map lists the auth stream error as untested on main already.
  A second window, measured by review 8 (its rows N, run by the reviewer on the head,
  main and the tenth version; the job read the outputs and did not run them again):
  the error 1 s after a dropped answer shows `SignedOut` with the error, and the head
  leaves that screen on its own when its timer reads. With no order change the
  households show at 4.0 s (at 2.5 s when the user signs in again then); with an order
  change refused after 8 s at 10.0 s, also when the user signed in again at 2.5 s (the
  order change holds that read); main stays on the error screen in these four rows.
  With the order change accepted both show the households at 8.2 s, and when the
  answer was kept before the error both stay on the error screen. Not designed either,
  no test. Whether the app's auth client sends such an error while the session stays
  is a guess.
- **A wait left standing with no timer** (review 8's rows P, run by the reviewer; read
  by the job, not run again). The wait's rule is: while it stands, a timer is armed or
  a start read is out. One return keeps the wait and arms nothing: the timer fires,
  finds nobody signed in and stops, and no signed-out event follows that would forget
  the wait. If the same account then signs in while an order change is on its way, its
  read is held with no timer behind it. Order change accepted: the households at 8.2 s,
  as on main. Refused or never answered: the row ends `SignedOut` with 1 read and no
  timer, as on main (the tenth version showed the households at 5.0 s). Without an
  order change the head shows them at 5.0 s and main ends `SignedOut`. So no row is
  worse than main, and none has a test. To get there the auth library's sign-out has
  to fail after it removed the session and before it sends the event (read from gotrue
  2.27.3: it removes the session, awaits the storage removal, then sends the event);
  not driven against the real client.
- **The account deleted while the start read is out, with a device sign-out that takes
  more than 3 s or throws:** after a dropped answer the head reads again at 3.2 s. With
  no membership left `NeedsHousehold` replaces the deleted-account notice (and `SignedOut`
  without the notice follows when the sign-out ends); main keeps the notice with 1 read.
  Four of twelve direct rows, driven with a fake sign-out. The auth library removes the
  session before anything it awaits (review 6, read from gotrue 2.27.3), so the timer's
  signed-in check stops it in the app unless forgetting the device's data takes more
  than 3 s. After a failed read main does the same as the head. With the deletion after
  the dropped answer and an order change still on its way the head equals main in all
  24 rows driven; `42b6429a` held an auth event's read there (above).
- **A device write that fails is seen by the tests' store only.** The app's `DeviceCache`
  drops a failed write's error (`device_cache.dart:468-474`), on main and on the head, so
  the start counts as answered when the write returns, and a device that cannot keep the
  households is not asked again: 1 read in 120 s. The cubit's handling of a write that
  throws (read again after 3 s; 41 reads in 120 s in probe 8's rows against a store that
  fails every write, the same on main; the told removals' write chain,
  `_toldWrites`, `session_cubit.dart:355`, which would stay failed after one failed
  write) is behaviour of the `SessionCache` interface that no shipped store reaches.
  Review 5 read the told-removals chain as a defect of main; review 6 measured that the
  app cannot reach it. No test pins it (review 5's mutant V7).
- **An older device write that ends after a newer one** leaves the older households on
  the device, on main and on the head (one of review 6's rows, with the tests' store and
  two held writes). Whether the real preferences can end two writes out of order was not
  checked.
- **A start whose reads fail is asked every 3 s without backoff,** as on main, now also
  after a dropped answer (up to 41 more reads than main in 120 s in the probes). After a
  dropped answer main had stopped and the head asks on (165 rows of probe 9 where the
  tests' store keeps nothing on either, up to 39 more reads).
- **A gateway that answers 401 or 429 for long is asked every 3 s.** The queue's retry has no
  backoff and reads no `Retry-After`; before this job the change was dropped at the first such
  answer. Read from the code, not driven. That a 401 which never goes away ends in the auth
  library's sign-out (its token refresh is refused) is inferred too, not tested.
- **A tick less than 440 ms before signing out** goes with the device's data (sign-out forgets
  the queue, as above).
- **Two edges of the early commit,** read from the code, not driven (review 2). After a commit
  on hide the row is gone when the app shows again, without the rest of its animation. A first
  frame that comes more than 440 ms after the tap lets the 880 ms fallback commit while the
  row still closes: the list moves under a closing row, as in the first version, on a device
  that drew nothing for 440 ms.
- **Job 219's CI trace** (`docs/NEEDS_LEAD.md`, job 219, point 4: WebKit, a reload right
  after the row was gone from the page, no write before or after). Read from the code, that is
  the case fixed here: the row is gone from the page before its tick commits. A committed tick
  is written to the device in the same turn, the path the new spec drives at the reload. The
  CI trace itself was not reproduced, so that it was this and nothing else is inferred.
- **No e2e for a body-less 401, 408 or 429** in the repo: unit-tested at the repository only.
  Review 0 drove them through the web build with its own spec, which is not in the repo (the
  reviewer's measurement: head 4 of 4, main's code fails the three, a 403 stays a refusal).
- **A tick in the instant after sign-out still sends `item_ticked`,** although the device then
  refuses to store the queue. Inferred by review 0 from the code (`ListCubit.tick` tracks
  before anything asks whether the queue was kept); the window is one microtask and nobody
  drove it.
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

## Review 0 (15 November 2026)

The harness review of #469 says every number it reran came out as written. Its one must-fix was
the new spec's margin on WebKit: 33 to 48 s of a 60 s timeout in the four CI runs it read (49.7
s in the job's earlier run 43650812055), 59.2 s for the reload test on the reviewer's loaded
box, and a timeout is not retried. PR #490 gives both tests `test.slow(browserName ===
'webkit')`, as `wasm-boot.spec.ts` and `no-google.spec.ts` have. Measured after, in the
on-demand CI run 43713288298 (the spec three times per browser): 18 of 18 passed, the report
shows a timeout of 180000 ms on WebKit and 60000 ms on Chromium and Firefox, and WebKit took
35.8 to 38.5 s. The closed-tab test now says in a comment that on WebKit it is no proof of the
fix. Two lines under "Remaining gaps" come from the review.
