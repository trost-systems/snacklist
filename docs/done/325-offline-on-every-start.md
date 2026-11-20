# Job 325: no "Offline" on a start with a working network

## Root cause
The list showed "Offline" the moment the phone's operating system said "no network", skipping the 10 s
start grace, and a working server could not clear it until the live connection joined. On iPhones the
system says "no network" for a moment on a working one (connectivity_plus reads a freshly started
`NWPathMonitor`, which reports none until its first update), so a start could show "Offline" every time.

## Built
- `app/lib/list/list_cubit.dart`: an OS "down" starts a resync instead of showing offline. Its failure
  shows "Offline" at once (grace or not); an answer to a request sent after the down ends it.
  A request unanswered 1.5 s after the down shows "Offline" outside the grace; a down channel
  subscribes again at once however the down ends (in-session review).
- Tests: `app/test/list/list_cubit_test.dart` (group "the OS saying no network on a working one (job
  325)": none then wifi, none that stays, slow channel, airplane mode on start, an up missed in the
  background; two 166/212 tests updated), `app/test/list/sync_indicator_test.dart` (no card or pill).
- Journey `.cursor/skills/verify-snacklist/journeys/cold-start-offline.mjs` (`--os-none`,
  `--slow-channel`, `--airplane`, `--wait`).
- DECISIONS "Job 325", feature map `offline.md`, FEATURES-FOR-WRITERS "Working offline", live-sync.md.

## Evidence
- iOS behaviour: GitHub macOS runner (NWPathMonitor `none` right after start, 10/10) and an iOS
  simulator with connectivity_plus 7.3.2 (a check while nothing listens says `none`, 3/3).
- Web build, browser reporting no network on a working one: main 6/6 starts showed "Offline"
  (0.9 to 4.5 s with a 3 s slower channel); the fix 0/12. Airplane start: "Offline" at 1.1 s.
- Screenshots: `docs/screenshots/325/`.

## Hypotheses ruled out
Channel never joining (an answer shows online since job 212), expired token at start (local stack,
2/2: join refused, rejoin works, no "Offline"), start/resume ordering, Supabase init and realtime token.
The household-switch path can still start a fresh iOS monitor; harmless now.

## Release
Next green main build on TestFlight and Play internal. No flag.
