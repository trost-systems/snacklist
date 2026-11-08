# Job 171: a store divider only folds

**What changed.** On the list, a tap on a store's divider („Ohne Laden“ included) folds or
unfolds its section and does nothing else. A hold or a right click on a store divider or a
category divider does nothing: no store details, no fold, no menu. A store's details open from
Liste → „Anpassen“ → the store. Item rows are unchanged (a hold or right click edits).

**Where.** `app/lib/list/list_view/dividers.dart` (no `onEdit`; the store divider sits in an
empty `Hold`, so a hold of a row's length is no tap), `shopping_list_view.dart` (no
`_editStore`), `hold.dart` (no `tappable`: rows and the store divider both sit in tappable
semantics nodes), the widgetbook story, the feature files and `docs/STORE_LAYOUTS.md`. Reasons:
`docs/DECISIONS.md`, job 171.

**How to verify.**
- `cd app && flutter test test/list/list_screen_test.dart`: "a hold or right click on a divider
  does nothing; a tap on a store divider only folds it" and "a screen reader's store divider
  offers a tap that folds and no long press, up or down moves". The first fails on main (the
  hold opens `/edit/lidl`) and without the empty `Hold` (the hold folds).
- `scripts/verify.sh --only e2e -- tests/list-walk-order.spec.ts`: "nothing on the list drags:
  a hold on a row edits, a hold or right click on a divider does nothing, a tap folds" (web
  build, mouse hold 700 ms and right click on the Lidl divider and the Kühlregal heading; URL
  and outline unchanged; a click folds Lidl). Screenshots `walk-hold-divider-nothing` and
  `walk-tap-divider-folds` with `SCREENSHOT_DIR` (CI artifacts).

**Tests.** Flutter gate locally: 334 widgetbook tests and the app suite pass, analyze clean.
e2e runs in CI (the hz e2e lock queue was three runs deep).
