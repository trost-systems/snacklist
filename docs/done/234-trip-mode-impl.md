# Job 234: trip mode behind `trip-mode` (2026-11-14)

PR #454 (https://github.com/trost-systems/snacklist/pull/454). Built from Peter's pick t864u on job
217's prototypes. Decisions: `docs/DECISIONS.md` "Job 234". Peter's questions and the flag
targeting: `docs/NEEDS_PETER.md` "Job 234". Feature file:
`.cursor/skills/verify-snacklist/features/trip-mode.md`.

## What was built

- **The question.** TM2's sheet „Kaufst du gerade ein?“ appears on every own tick while no trip
  runs. „Nein, nur abgehakt“ or a dismiss just ticks. „Zurücknehmen“ puts the item back. Mehr ›
  „Einkauf starten“ starts a trip by hand.
- **The strip.** TM1's slim dark strip sits above the add field and the list total: the
  stopwatch, Pause/Weiter and Beenden. TM2's timings apply. After 45 min without a tick the trip
  pauses itself and Beenden reads „Beenden um <last tick>“. After 4 h it ends itself at the last
  tick, and the list shows a card with „Doch weiter“.
- **The summary.** TM1's page has a section per store: planned and extra items, „von Lea“ and
  „War geplant“. Each section ends with paid vs planned per item, a store total, the difference
  and the counts of items without a planned or paid price. The page ends with the overall total
  and a note on what counts. The same page opens after Beenden and from the trip's Verlauf
  entries, and it can delete the trip.
- **Free.** TM2's card shows without blur. The server holds the lines back without Premium.
- **Server.** `public.trip_sessions`, `save_trip_session`, `trip_session`,
  `mark_trip_line_planned`, `delete_trip_session`. One Verlauf entry is written per store
  (`trips.session_id`) when `grocery-log` is on. The forget and export rules cover the new table.
  Analytics: `shop_started`, `shop_asked`, `shop_ended`.
- **Code.** App: `app/lib/trip/` (model, rules, summary, cubit, repository, widgets). Migration:
  `supabase/migrations/20261114181718_trip_mode.sql`. Tests: `app/test/trip/`,
  `supabase/tests/trip_mode.test.sql`. Journey: `.cursor/skills/verify-snacklist/journeys/trip-mode.mjs`.

- **Legal GL-2 (review 0):** no trip question and no „Einkauf eintragen?“ card for a pharmacy.
  The predicate is `Store.isPharmacy` (`app/lib/list/model.dart:70`; words apotheke, pharmacy,
  pharmacie, farmacia, apteka, eczane, name or seed key, any case). The ask checks it at
  `app/lib/trip/trip_cubit.dart:301` and job 199's card filter at
  `app/lib/log/trip_prompts.dart:76`. dm and Rossmann still ask. Legal's N-167 answer is marked
  in `docs/NEEDS_PETER.md` (job 199's Art. 9 item).
- **Review 0 fixes:** a trip's end takes the items it logged out of job 199's pending ticks
  (`app/lib/trip/trip_on_list.dart:55`, `TripTicks.forgetting`), so no card logs them twice. The
  duration rounds to the nearest minute, and under half a minute reads „Unter 1 Min.“.

## Flags

- `trip-mode` is new (`releases/flags.json`, rollout off). The lead creates it in PostHog,
  internal only.
- The amounts need `prices-and-trip-total`, the Verlauf entries `grocery-log`. Widen none of them
  until Legal's N-163 to N-168 land.

## How to verify

- `export FLUTTER_DIR=~/flutter-3.50.0 VH_DEFINES="FLAGS_ON=trip-mode,grocery-log,prices-and-trip-total"`,
  `.cursor/skills/verify-snacklist/helpers/launch.sh`, then `helpers/drive.sh trip-mode`
  (`--lang en`, `--dark`, `--compact`). All four passed on the branch; de again after the last
  app change (c33048f4), plus a 1100 px check of the rail layout (`docs/screenshots/234/wide-*`).
- `cd app && flutter test test/trip` for the unit and widget tests (rule, summary, cubit, widgets,
  semantics, 358 px and 130 % fits).
- `scripts/verify.sh --only db` for the pgTAP tests.

## TQ items

| TQ | Status |
| --- | --- |
| TQ1 where a running trip lives | Decided: on the device. Server-side left open for Peter. |
| TQ2 two shoppers | Decided for now: every member's ticks count. Open for Peter. |
| TQ3 how long „Nein“ holds | Decided by Peter: it asks on every tick. |
| TQ4 long-running rule | Decided: TM2's 45 min / 4 h, end at the last tick. No notification. |
| TQ5 ticks during a pause | Decided: they count. |
| TQ6 others' unbought additions | Decided: shown as „nicht gekauft · von Lea“. |
| TQ7 own early additions | Decided: extras, „War geplant“ fixes them. |
| TQ8 Free gate | Decided by Peter: TM2's card. The stopwatch is free. |
| TQ9 one record with the grocery log | Decided: yes, one Verlauf entry per store. |
| TQ10 two stores | Decided: two entries that open one summary. |
| TQ11 strip and price total | Decided: the strip sits above the total and does not carry it. |
| TQ12 undo an end | Decided: „Weiter einkaufen“ / „Doch weiter“ while the page or card shows. |
| TQ13 privacy and analytics | Decided: data map row, forget, export, three allow-listed events. |
| TQ14 en, dark, 130 %, 358 px, tablet | Done and tested; from 840 px (the rail) the strip and the summary keep to the list's column. |
| TQ15 visible manual start | Decided: Mehr only. |

## Test results

- `flutter test test/trip test/list test/log`: 1062 passed. The wider set (trip, log, list, more,
  analytics, purchases, app) passed with 2085 tests in the fix round.
- `scripts/verify.sh`: every gate passed up to e2e (gitleaks, lint, changelog, site, site-agent,
  emails, db, functions, nexus, fg-cli, flutter, web-prod, fastlane). Local e2e: 252 passed and
  10 failed. Eight of the failures are the fake-OIDC specs (id-token, onboarding AC6,
  social-sign-in 71/86), which time out on the Hetzner runner. The other two were `rls.spec.ts`,
  whose sign-up hit the same auth timeout; it passed when rerun alone. CI's e2e shards ran all of
  them green on the PR head.
- CI (`ci-ok`) was green on the first push of #454.

## Review 0 (FIX), addressed

- All three must-fix items are done, each with tests that failed before the fix.
  - GL-2: `model_test`, `trip_prompts_test`, `list_trip_widget_test` („a pharmacy tick asks
    nothing; dm and Rossmann ask“).
  - The NEEDS_PETER mark.
  - Double logging: `trip_prompts_test`, `list_trip_widget_test` („a trip's ticks are not
    offered again …“).
- The journey now also ticks Aspirin at „APOTHEKE am Markt“: no question and no card. On
  3bf4394f it passed in de, in en with dark, and at 358 px.
- After the rebase: `flutter test` (8 folders) passed with 2095 tests;
  `verify.sh --only lint,changelog,flutter` passed.
- Lead calls: `~/groceries-ops/NEEDS_LEAD.md` "Job 234" (DocMorris, pharmacy lines inside a
  user-started trip, `trip_sessions` outside grocery-log).

## Open

- Lands under the merge lock after review. Merge SHA: (after the land). TestFlight: the next
  green main build after the merge carries it, behind `trip-mode` (on for Peter's internal
  install only).
- Peter: the flag targeting and the TQ answers in `docs/NEEDS_PETER.md` "Job 234".
