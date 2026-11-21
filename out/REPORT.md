# Job 354: beta feedback code check (main a1edd966, read-only)

## B1 Trip prompt „Kaufst du gerade ein?“

**Short answer: there is no snooze.** Peter's assumption is wrong. A "no" is remembered nowhere, so the next own tick asks again.

**Repro:** tick an item, answer „Nein, nur abgehakt“, tick another: asked again, by design. A snooze would be a product decision; its natural scope is the per-household `TripCubit` (state would live there; today nothing does).

### (a) Suppression after "no"
- `TripCubit.no()` sets `NoTrip` and emits `QuestionAnswered(no)`; its doc says "nothing is remembered" (`app/lib/trip/trip_cubit.dart:200-207`). No timestamp, counter or per-store/list/household/device field exists (grep for snooze/suppress in `app/lib/trip` and `list_cubit.dart`: no hits).
- Dismissing the sheet counts as "no": `showTripAsk(...) ?? AskAnswer.no` (`trip/ask_sheet.dart:9-22`), then `trips.no()` (`trip/trip_on_list.dart:58-70`).
- Duration 0 s. Scope: none. The only gate is the cubit state: a tick asks only in `NoTrip` or `Ended` (`trip_cubit.dart:343-345`, `_ticked`).
- Scope of that state: one `TripCubit` per household scope on the device (`shell/list_scope.dart:312-322`); a running trip is kept per user in `DeviceCache` (`trip_cubit.dart:563-600`).

### (b) Ticks in two stores within minutes
Yes, twice: tick 1 → "no" → `NoTrip`; tick 2 (any store) → `_ticked` sees `NoTrip` and sets `Asking` again (`trip_cubit.dart:367`). Store is never read except the pharmacy exemption (below). So there are no "separate timeouts per store". Tick while the sheet is still open: ignored (`state` is `Asking`, line 343-345 guard), so no stacked sheets.

### (c) Every path that asks again
| Path | Asks? | Evidence |
|---|---|---|
| Next own tick after "no"/dismiss/"Zurücknehmen" | yes | `trip_cubit.dart:201-216, 338-368` |
| Untick (put back from „Zuletzt verwendet“) then retick | yes, each tick | `list_cubit.dart:919-935` fires `OwnItemTicked` for every active→bought |
| App restart / cold start | yes: `Asking` and `NoTrip` are not persisted (`_persist` writes null for them, `trip_cubit.dart:615`); only a `Running` trip or an auto-`Ended` card survives | `trip_cubit.dart:610-616` |
| Household switch / list switch | yes: new household = new cubit and state; lists inside a household share one cubit, `listId` is only carried in `Asking` for the snapshot, no suppression per list | `list_scope.dart:312`, `trip_cubit.dart:340-366` |
| Trip running (any list) | no | state `Running` |
| Trip running in another household (`RunningElsewhere`) | no | `_ticked` guard; `_sync` `trip_cubit.dart:575-580` |
| After a trip ended (`Ended`, incl. auto card) | yes again | guard allows `Ended`, line 343 |
| Another member's tick / realtime echo | no: only `OwnItemTicked` triggers (`list_cubit.dart:935`, listener `trip_cubit.dart:124`) | |
| Tick from add sheet match row | no (job 324) | `trip_cubit.dart:122-126`, `add_sheet_cubit.dart:209` |
| Siri/Alexa/MCP/API ticks | no (not through the app's `tick`) | same |
| Storeless items | yes: the only store rule is the pharmacy exemption (`s.id == before.storeId && s.isPharmacy`, `trip_cubit.dart:348-352`); storeless is never a pharmacy | |
| Pharmacy store item | never asks (Legal GL-2) | `trip_cubit.dart:348-352` |
| Flag `trip-mode` off for the account | never asks (`enabled()` = PostHog flag, `list_scope.dart:318`, `trip_cubit.dart:343`). `releases/flags.json:23-26` says rollout `full`, so testers see the prompt | |

Likely tester story: with no snooze, the second tick after "Nein" asks again regardless of store. Whether the product wants a snooze is a design call (not in SPEC/DECISIONS: no match for snooze/"ask again").

### Job 351
Does not affect this today. Its brief is design and evidence only ("no app code merged", `~/groceries-ops/jobs/351-trip-detection-heuristics/brief.md`); branch `job/351-trip-detection-heuristics` has no output yet (job started 22:25 CET, no `docs/research/351*` in this tree). Its proposals (H1-T5a: sessions of ≥3 ticks, no prompt needed) would make the prompt partly redundant if job 352 builds on it, but nothing is in code.

## B2 Undo / „Zurücknehmen“ reachability

**Answer: no undo button or snackbar follows a tick. The reachable „Rückgängig“ snackbars/notes are delete (screen-reader action only), duplicate merge and the add-sheet note; „Zurücknehmen“ (EN "Untick", `app_en.arb:1063`) lives in the trip prompt.**

**A tick has no undo snackbar** (job 29b). But „Zurücknehmen“ is alive inside the trip prompt, and other „Rückgängig“ buttons remain. Every hit in `app/lib`:

| Hit | Where | Reachable how |
|---|---|---|
| ARB `shopAskTakeBack` „Zurücknehmen“ | `app/l10n/app_de.arb:1420`; used `trip/ask_sheet.dart:92-93`; `trips.takeBack()` → `list.readd` `trip/trip_on_list.dart:68`, `trip_cubit.dart:209-216` | After every own tick while the trip prompt shows (flag `trip-mode`) |
| ARB `undo` „Rückgängig“/„Undo“ `app_de.arb:38`, `app_en.arb:35` | `list/list_view/shopping_list_view.dart:422` (`_snack` action), only caller `:505-507` row delete | Screen-reader action „Löschen“ on a row (VoiceOver/TalkBack); not on web |
| same key | `list/add_sheet/add_sheet.dart:1312,1323` `added-undo`, `:575-578` | Note under the add field after an add (`✓ Hinzugefügt`) until next keystroke; in compact sheet (flag `add-sheet-compact`) the add is undone behind the sheet instead (`:571`) |
| same key | `add_sheet.dart:588` `dedupe-undo` (sheet), `list/list_screen.dart:371-373` (snackbar) | after a duplicate merge („Zusammenführen“) |
| `Icons.undo` (no ARB) | `trip/summary_view.dart:473` | icon on „War geplant“ when marked |
| `feedbackAnnotateUndo` | `app_de.arb:534`, `feedback/annotator.dart:695` | screenshot markup, unrelated |
| Silent undo | `ListCubit.readd` within `undoWindow` 10 min (`list_cubit.dart:958-983`), tap in „Zuletzt verwendet“ | no label |

No flag hides the tick undo; there is no tick snackbar to hide.

**Stale doc mentions** (the user-facing code is fine, these lag or contradict):
- `docs/SPEC.md:24` still contains the old wording "with a short undo snackbar", but the same line goes on "Since job 29b ... the tick has no snackbar": annotated, no fix needed.
- `site/content/landing/copy.yml:60-62` (DE „wer sich vertippt, nimmt es gleich zurück“, EN "a slip of the finger is undone just as fast"). Promise now only via „Zurücknehmen“ in the prompt or „Zuletzt verwendet“; only true with `trip-mode` on or the history.
- `docs/DESIGN.md:388`: generic "snackbar with undo" surface list (still true for delete/merge).
- `.cursor/skills/verify-snacklist/features/FEATURES-FOR-WRITERS.md:305-316`: correct today (line 316 says explicitly there is no undo message). Lines 310 and 313 are right; but line 310 relies on the prompt, which exists only with `trip-mode` on, and the file does not say that there.
- `features/tick-and-undo.md:55` correct; `features/README.md:70` correct.
- `docs/ANALYTICS.md:209` correct.

## B3 Onboarding today (invite joiners)

**Unproven:** all of B3 is static reading (a subagent plus reviewer spot checks of router, start screen, JH2, join cubit); no step was driven in the web build. **Live default of `join-household-jh2` is unknown from the repo** (flags.json `full`, note says "off until Legal approves"): check the PostHog flag for the tester cohort before relying on either flow.

Facts: no guest/anonymous sign-in. Sign-in: Google, Apple, email+password, magic link (`session/login_screen.dart`, `session/social_sign_in.dart:36-58`: web redirect for both; Android native Google, redirect Apple; iOS native Apple, Google only with `googleIosClientId`). **No permission prompt, no paywall/Premium screen in onboarding** (`premium-launch` not released; mic/speech ask on first dictation only). Router order without a household: consent, name, join (`shell/router.dart:353-417`).

Flags: `join-household-jh2` (releases/flags.json says `full`, its note says "off until Legal approves the typed-code preview (JH-Q9)"; the actual state is PostHog's, so which flow below applies is not settled by the repo), `display-name` (full, gates name screen `router.dart:707-709`), analytics consent only if the build has a PostHog key and no decision yet (`analytics/analytics.dart:254`).

### A. Invite link (`/join/<code>` or `/?invite=<code>`)
1. Web only: static page `/join/<code>` (`vercel.json:11`, `app/web/join/join.js`): inviter, household, members, store links, "Im Browser beitreten". Phones with the app skip it (universal/app link).
2. Router keeps the code as `PendingInvite` and sends signed-out users to `/login?invite=<code>` (`router.dart:355-361`); no start screen.
3. Login screen: Google/Apple (per platform), "Weiter mit E-Mail"; "Neu bei Snacklist?" hidden, invite-waiting line shown. JH2 on: one-time sheet "Du bist in einen Haushalt eingeladen" (create account / sign in). Email sign-up needs e-mail confirmation (`signUpCheckEmail`); magic link also offered.
4. Analytics consent (`/analytics-consent`), once per install, if due (`router.dart:366`).
5. „Wie sollen wir dich nennen?“ (`/your-name`), only with `display-name`; prefilled from Google/Apple (`session/your_name.dart:59-61`).
6. Join screen (`household/join_screen.dart`): JH2 off: preview + „Beitreten“ button; JH2 on: auto-join, no confirm (`join_cubit.dart:97-110`). If the household needs approval: waiting screen `/welcome/waiting` (`router.dart:383-390`). Already member: opens household.
7. First list. Extras: web on a phone with JH2 gets the „Öffnen“ card (`core/open_app.dart:93-125`); „Erste Schritte“ checklist (`tips/checklist.dart`; invite step owner-only); hints after 10 s quiet, 1 per 24 h, none while the first-session list is empty (`tips/hints.dart:160-262`).

### B. Invite code typed
**JH2 off**
1. Start screen (signed out): „Los geht's“, „Schon ein Konto? Anmelden“, „Einladung einfügen“ (clipboard on tap, `household/paste_invite.dart`). Pasted link/code continues as A from step 2.
2. Typed: Anmelden → `/login` (no invite sheet), then consent, name.
3. Welcome (`/welcome`): „Haushalt erstellen“ / „Mit Code beitreten“.
4. Join screen `/join`: type code, „Prüfen“, household card, „Beitreten“ (approval waiting screen if required).
5. List, as A7 minus the phone „Öffnen“ card.

**JH2 on** (from the guided start)
1. Start screen: „Los geht's“ / „Schon ein Konto“ only; paste hidden (`onboarding/start_screen.dart:25-30,76`).
2. Usage question first, if consent is due (`onboarding/steps.dart:39,120`).
3. „Wer kauft mit?“, then household-name step with „Bestehendem Haushalt beitreten“ (`steps.dart:323-334`).
4. Join-code screen (`household/join_code_screen.dart`): 8 chars, lookup on complete, preview.
5. Then `/login?invite=<code>` with the JH2 sheet (A3), consent, name, auto-join, list (A4-A7).

Platform: web has the static page, redirect-only social sign-in and the „Öffnen“ card on phones; iOS/Android open the link in-app, native Apple (iOS) / Google (Android), clipboard paste for lost links, dictation hint.
