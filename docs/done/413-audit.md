# Job 413 audit: History and planned-vs-added (2026-11-23)

Peter (via Snacklist PM): both stay off at launch, to be re-enabled only if users ask. Launch Premium is MCP and API
reads only (AC5, job 414); no Premium surface names export. "History" is the Verlauf tab (flag `grocery-log`). "Planned vs added" is the trip summary's
comparison „Geplant und gekauft“ / „Was war geplant, was kam dazu?“ (flag `trip-mode`).

## 1. What controls each feature today

| Feature | Controls | State |
| --- | --- | --- |
| Verlauf tab, `/history`, `/history/trip/:id`, the journal, calendar, by-store view, „Einkauf eintragen“, locked row „Ältere Einkäufe siehst du mit Snacklist Premium“ | PostHog flag `grocery-log` (`groceryLogFlag`, `app/lib/analytics/flags.dart`); `releases/flags.json` `"rollout": "off"` | Off in `flags.json` since 2026-11-22 (HP2, job 401, #648). Router: `/history` redirects to the list (`router.dart` `historyTabRoutes`); the tab shows only with the flag (`shell.dart`). |
| Trip mode: the tick question, trip strip, `/trip/:id` summary with „Geplant und gekauft“, the Premium card „Was war geplant, was kam dazu?“ | PostHog flag `trip-mode` (`tripModeFlag`); `flags.json` `off` | Off in `flags.json` since 2026-11-22 (job 401). Router: `/trip/:id` redirects to the list (`_withTripMode`); More's „Einkauf starten“ and the list's strip need the flag. |
| Learned-order „first detected trip“ card („Der Einkauf steht im Verlauf …“) | `learned-order` and `grocery-log` and `trip-mode` (`trip_on_list.dart`) | Off, since job 401 added the two extra gates. |
| Prices and totals (not part of this job, same HP2) | `prices-and-trip-total`, `total-priced-only` | Off in `flags.json`. |
| app_switches | None: no server switch exists for either feature. The Supabase `app_switches` rows are `household_archive`, `premium_offer`, `integration_lock`, `public_api`, `unified_keys`, `feedback_digest`, `mcp_lists_stores`, `push_*`. | n/a |
| Release holds in `flags.json` | None for either feature. `premium-launch` (`released: false`) holds the Premium sales announcement only. | n/a |
| MCP and API | Neither exposes trips, history or planned-vs-added (no tool or route in `supabase/functions/mcp`, `api`; `_shared/list.ts` mentions history only in comments). | Nothing to hide. |

Is it off for everyone? In the repo: yes, `Flags.isOn` is false for a key PostHog does not serve and the build has no
`FLAGS_ON` define. In PostHog: unverified. The flag sync only creates flags and never switches one off, and the
job key lacks `feature_flag:read`. NEEDS_LEAD "Job 401" still asks the lead to switch the four flags off in PostHog
(project 319492); until then internal and tester accounts could still be served `grocery-log` or `trip-mode`.

Stored data stays: `trips`, `trip_items`, the trip-detection rows and the `trip_history` RPC are untouched, and the
server keeps writing detected trips for `learned-order` testers. No migration drops anything.

## 2. Every mention

Marks: **LEGAL** = a legal file or a string Legal hashed or signed. **gated** = shown only with the flag, so unreachable now.

### App strings (`app/l10n/app_de.arb`, `app_en.arb`)

| Keys | Where it shows | Status |
| --- | --- | --- |
| `tabHistory` (Verlauf / History), `history*`, `trip*` (tripAdd, tripEdit, tripDeleteBody, tripItemCount …), `previousMonth`, `nextMonth` | Verlauf screen and its sheets | gated (`grocery-log`) |
| `historyLockedTitle`, `historyLockedCount`, `historyDayLocked` | Premium lock in Verlauf | gated; promise Premium for older trips |
| `shop*` (shopAskBody, shopSummaryTitle „Geplant und gekauft“, shopLede, shopPlannedSection, shopMarkPlanned, shopCompared …) | Trip question and summary | gated (`trip-mode`) |
| `shopLockedTitle` „Was war geplant, was kam dazu?“, `shopLockedBody` | Premium card in the trip summary | gated; promise Premium for the comparison |
| `detected*` (detectedOwn, detectedCardBody „Der Einkauf steht im Verlauf …“) | learned-order testers | gated (three flags) |
| `accountDeleteDeleted`, `leaveLast` („… mit Liste, Verlauf, Kategorien und Geschäften gelöscht“) | Account deletion and leave dialogs | not gated; describes stored data, true while data is kept. Left. |
| `suggestionHistory` „Schon mal gekauft“, `refundHelpGoogle` („Bestellverlauf“, Google's menu), `feedbackStatusPlanned` | unrelated meanings | left |
| `premiumHeroTitle` (N-348), `premiumWeb` (N-349), `premiumHousehold` (N-350), the other `premium*` keys | Premium page | **LEGAL** (job 383, #639). Checked: none names History or planned-vs-added. Not touched. |

### Premium surfaces
- App Premium page (`premium_screen.dart`): benefits are MCP and API only. No mention.
- Store metadata (`app/fastlane/metadata/**`, `docs/store/LISTING.md`): no mention; `metadata/check.mjs` already refuses Verlauf, history, trips (HP2).
- Site landing (`site/content/landing/copy.yml`), guides, emails (`emails/`): no mention.
- Onboarding, hints, tips: no mention outside the gated screens.

### Docs and feature map that still promise them
- `.cursor/skills/verify-snacklist/features/FEATURES-FOR-WRITERS.md`: "Never claim (everywhere)" bullet (line 22) says two things are locked for
  households without Premium (older trips, planned-and-added) and "Never write that nothing is locked"; the Premium section
  (line ~884) describes both locks; the "Never claim" list (line ~898) says "nothing is locked without Premium (older trips …)". Not legal.
- `.cursor/skills/verify-snacklist/features/premium.md`: intro and `prem-locks` describe both locks, `paywall_viewed` entry points `history` and `trip`. Not legal.
- Other feature files (`grocery-log.md`, `trip-mode.md`, FEATURES-FOR-WRITERS sections „Grocery log“, trip mode, learned order, tabs) already say "not for users".
- `docs/PRODUCT_FEATURE_MAP.md`, `docs/design/**`, `docs/done/**`, DECISIONS: history, not copy. Left.

### Legal files (`site/content/legal/*`)
| File | Mention |
| --- | --- |
| `datenschutz.md` l.81 / `privacy.md` l.62 | „Preise und Einkäufe“ / "Prices and trips": stored trips (true). It ended with a Premium promise: only 4 weeks and a summary without Premium, older trips „mit Premium sichtbar“. **Changed (needs Legal)**: that sentence is now „Ältere Einkäufe und die Einträge bleiben gespeichert.“ / "Older trips and the items stay stored." |
| `datenschutz.md` l.85 / `privacy.md` l.66 | detects trips from ticks (stored data, still true) |
| `datenschutz.md` l.222 / `privacy.md` l.203 | feedback status „geplant“ / "planned" (unrelated) |
| `datenschutz.md` l.271 / `privacy.md` l.252 | retention list |
| `avv.md` l.43 / `dpa.md` l.44 | „Verlauf der Änderungen an Einträgen“ (item change log, unrelated) |
| `support.md` / `support-en.md` | no mention of History or planned-vs-added (Siri hits only) |

`releases/flags.json` is hashed by Legal. Its notes for `grocery-log` and `trip-mode` already say off for everyone.

## 3. What touches Legal-signed text

Two hunks, both the same sentence, needs Legal:

- `site/content/legal/datenschutz.md` l.81: removed „Ohne Snacklist Premium zeigt die App die Einkäufe der letzten 4 Wochen und von gestarteten Einkäufen nur eine Zusammenfassung; ältere Einkäufe und die Einträge bleiben gespeichert und sind mit Premium sichtbar.“, kept „Ältere Einkäufe und die Einträge bleiben gespeichert.“
- `site/content/legal/privacy.md` l.62: the same in English (removed "Without Snacklist Premium the app shows the trips of the last 4 weeks and only a summary of started trips; older trips and the items stay stored and are visible with Premium.", kept "Older trips and the items stay stored.").

Not touched: the #639 strings (N-348..N-350), `releases/flags.json`, every other legal file. The sentence went live on snacklist.app/datenschutz and
/privacy and promised History as Premium; the first audit missed it.

AC5 (job 414, export): no Premium surface names export as a Premium benefit (ARB `premium*`, the Premium page, FEATURES-FOR-WRITERS,
`site/content`, guides, fastlane metadata, `docs/store/LISTING.md`). The free „Meine Daten exportieren“ is unchanged. No hunk needed.

AC1 caveat: "off for everyone" holds for the repo and for any build PostHog serves nothing to. Whether PostHog still serves `grocery-log` or
`trip-mode` to internal or tester accounts is unverified (the runner key gets `permission_denied … feature_flag:read`); it depends on the
Job 401 manual PostHog step.

Deliberately kept: `accountDeleteDeleted` and `leaveLast` name „Verlauf“ (stored data, not a Premium promise).

sha256 at this head (after the privacy edit, recomputed in the NEEDS_LEAD entry): `datenschutz.md` and `privacy.md` changed; the others, `releases/flags.json` included, are unchanged by this PR.
