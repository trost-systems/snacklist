# Job 471: undo snackbar after a tick (CP1), 2026-11-27

Peter's CP1 (26 Nov 2026): "CP1 yes I guess we can show a snackbar for that with an undo
button. Double check texts and decisions to update those." It reverses job 29b (29 Oct 2026,
"A tick shows nothing").

## What changed

- After a tick the list shows its standard snackbar „Abgehakt: <Name>“ / "Ticked: <Name>" with
  „Rückgängig“ / "Undo" (`_tick` in `app/lib/list/list_view/shopping_list_view.dart`, through
  `_snack` and `Notices`). New ARB key `itemTickedUndo`; `undo` reused; `itemTicked` (the
  screen-reader announcement, add sheet, trip sheet) untouched.
- Only the last tick: a new tick replaces the snackbar, and Undo takes back that tick only.
- Undo calls `ListCubit.untick`: at once, in the item's old place, no analytics event. `untick`
  now also reopens a trip the tick ended (`TripReopened`, moved from `readd`, which calls it), so
  a snackbar undo of the list's last tick doesn't leave the review prompt counting a finished trip.
- A refused tick or undo comes back and its „Änderung abgelehnt: <Name>“ snackbar replaces the
  undo snackbar (the existing hide-then-show).
- „Zuletzt verwendet“ stays the fallback; its put-back still shows no message (job 117). Job
  469's `listHint` copy was not touched.

## Texts updated (living docs)

`docs/DECISIONS.md` (new job 471 entry at the end; 29b and 455 entries left as they were),
`docs/SPEC.md`, `docs/ANALYTICS.md`, `docs/research/competitor-pain-points.md` (item 1 and the
2.1 table row; quoted reviews unchanged), `.cursor/skills/verify-snacklist/features/tick-and-undo.md`
(new `tu-tick-undo`), `FEATURES-FOR-WRITERS.md` section "Ticking items, „Zuletzt verwendet“ and
undo" (Tips section left to job 469), `.cursor/skills/verify-family-groceries/features/quick-add.md`,
`.cursor/skills/verify-snacklist/journeys/tick-and-undo.mjs`, `e2e/tests/list.spec.ts`,
`e2e/tests/helpers.ts` comments, `e2e/shard-durations.json` (renamed test key).

## Tests and proof

- `app/test/list/tick_undo_test.dart` (new): the snackbar text and action; Undo restores at once
  (server held back by a gate) and in place; two ticks keep only the last snackbar and Undo takes
  back only that one; a refused tick reverts and its message replaces the undo snackbar; a refused
  undo ticks the item off again and says so. Three of the four fail on the old `_tick`.
- `list_cubit_test.dart`: the snackbar's untick reopens the emptied trip.
- Updated: `list_screen_test.dart` (tick with snackbar, put-back after it timed out; the reduced
  motion test no longer asserts zero running animations, which the snackbar's entrance breaks, and
  clears the accessibility flag in a teardown), `list_trip_widget_test.dart` (TD-Q4 allows the
  tick's own snackbar only).
- `scripts/verify.sh --only flutter` passed. `scripts/lint.sh` passed.
- Web build, local stack: `helpers/drive.sh tick-and-undo` PASS (DE), 2026-11-27.
- Screenshots: `docs/screenshots/471-tick-undo-snackbar/471-tick-undo-{de,en}.png` (widget test
  `app/test/list/tick_undo_screenshots_test.dart`, 390×844, light) and `471-tick-undo-web-de.png`
  (the web journey).

## Review 0 fixes

- Must fix: `.cursor/skills/verify-family-groceries/features/list-walk-order.md` (`lw-tick` and the
  tick recipe) still said a tick shows no snackbar; both now describe and wait for „Abgehakt:
  Bananen“. Rebased onto main (append logs merged by the driver).
- The undo snackbar now closes as soon as its item is open again another way (trip „Zurücknehmen“,
  a partner, a refusal); `list_trip_widget_test` "Zurücknehmen puts the item back" asserts it and
  fails without the fix.
- `list_screen_test` "with animations off": the struck row keeps its full height until it goes
  (fails with animations on, so it proves there is no close), instead of the dropped
  `hasRunningAnimations` check the snackbar's entrance broke.
- `tick_undo_test`: row order checked while the server's answer is still held back.
- An English web-build screenshot (`471-tick-undo-web-en.png`) next to the German one.
- Left as a follow-up candidate: a screen reader hears the tick twice („Butter abgehakt“ from the
  row, then the snackbar „Abgehakt: Butter“). The brief keeps the row's announcement as it is.
