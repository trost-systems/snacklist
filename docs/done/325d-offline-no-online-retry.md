# Job 325d: no "Offline" when the OS never says the network is back

Merged as: the next commit on main (this PR).

## What changed

- `app/lib/list/list_cubit.dart`: in the start grace, a request that fails after the OS said
  "no network" no longer shows "Offline" just because no "online" event came within 1.5 s. The app
  sends one more request then (`_downAsk`) and shows the card only if that one fails too.
- `app/test/list/list_cubit_test.dart`: four tests (review 2, F4 and F1, a slow extra request, flight
  mode at the extra request's failure). The first three fail on main.
- `journeys/cold-start-offline.mjs`: `--no-online` keeps the browser's network at none and fires no
  `online` after `--radio-down`. Recipe and writers' notes updated (`offline.md`,
  FEATURES-FOR-WRITERS "Working offline" step 4 and stamp). DECISIONS "Job 325d".

## Verified

- Flutter 3.50.0: `flutter test` in app/, 4020 passed, 0 failed; `test/list` 1248 passed.
- Web release build on a local stack (block 588xx), `--os-none stays --radio-down 800 --no-online`:
  - main 1b0a278e: "Offline" from 2.6 s to 4.1-4.2 s in 3 of 3 starts.
  - this branch: 0 polls in 3 of 3 starts; with `--slow-channel 3000` 0 in 3 of 3; review 1's
    `--radio-down 800` (with `online`) 0 in 2 of 2; `--airplane` shows from 2.6 s in 2 of 2.
- Screenshots: `docs/screenshots/325d/`.

## Open

- Device check on TestFlight (NEEDS_LEAD "Job 325"): it now points at the first build carrying this PR.
