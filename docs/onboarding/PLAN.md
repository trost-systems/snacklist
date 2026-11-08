# Onboarding, first-run activation and contextual hints (job 168, phase 1)

Status: plan for Peter's pick. Nothing here is built yet. The prototype of the recommended flow is
`site/public/internal/onboarding.html` (preview URL in the PR and in the job's PHASE1_DONE).
Research behind it: `research/best-practice.md` (activation, good friction, consent law, hint
patterns, notification asks) and `research/comparable-apps.md` (Bring!, AnyList, OurGroceries,
Todoist, Splitwise, Listonic, Cozi). The growth research file the brief names
(`growth-research-2026-11-06.md`) was not on the Hetzner runner; this plan is built from the brief
and the two research files above, and gets a pass against it once it arrives.

## The decision in 10 lines

1. Aha moment: something one member adds or ticks shows up on the other member's phone. Hummlist
   is multiplayer, so activation is counted per household, not per user.
2. Activation metric: a household with 2 or more members and 5 or more items, where a member other
   than the creator wrote at least once, all within 7 days of creation (`household_activated`).
3. Today: sign-in, analytics question, two cards, name and stores, invite, then an empty list.
   Nothing says what Hummlist is before sign-in, the first list is empty, and a skipped invite is
   never offered again.
4. O1 Polish (2.5 lane-days): same screens, plus starter chips in the empty list, a value line on
   sign-in, the invite offered again from the list, and a 3-step "Erste Schritte" card.
5. **O2 Guided start (4.5 lane-days, recommended):** O1 plus two short steps that pay off at once
   ("Mit wem kaufst du ein?" and "Was fehlt gerade?"), invite copy that fits the answer, and a
   club path that leads to the AI assistant setup.
6. O3 Try first (10 lane-days): a guest list before any account, signing up only to share. Highest
   upside, but too big and too risky before Nov 28.
7. Hints: H1 Tips 2 (1.5 lane-days), **H2 Trigger hints (3 lane-days, recommended)**, H3 remotely
   tuned hints (5 lane-days). H2 shows a hint only after the behaviour that makes it useful, at
   most one hint per day, and never again after X or after the feature is used.
8. Data: collect only answers that configure the app right away (who you shop with, stores,
   starter items). Everything sent to PostHog stays behind the existing analytics yes. No diet,
   age, contacts, location or newsletter questions.
9. Invite loop (job 169): the invite step, the checklist's invite item and the `invite-partner`
   hint are the three invite moments. The club answer is the entry point to multi-member
   households.
10. Peter decides 5 questions (Q-O1 to Q-O5 at the end). Defaults apply if he says nothing.

## What exists today (code and feature map, 2026-11-07)

| Step | Screen | Facts |
| --- | --- | --- |
| 0 | `/login` | Icon, wordmark, Google, Apple, "Weiter mit E-Mail". No sentence about what Hummlist is. No guest use (`enable_anonymous_sign_ins = false`). |
| 1 | `/analytics-consent` | Builds with an analytics key ask once per install, equal buttons, versioned text (2026-11-01). The legal text is fixed. |
| 2 | `/welcome` | "Haushalt erstellen" or "Einladung annehmen". An invite link skips to `/join/<code>`. |
| 3 | `/welcome/create` | Name (prefilled "Unser Haushalt"), 11 store chips, own stores, "Überspringen". |
| 4 | `/welcome/invite` | "Partner einladen" or "Später". After "Später" nothing offers the invite again except More. |
| 5 | `/` | Empty list: "Die Liste ist leer. Tippe unten ein, was fehlt." plus the gesture card "Tippen hakt ab · Halten bearbeitet". Phones do not focus the add field. |
| later | tip card | Job 80: a fixed queue of 2 tips, one card, after the first item and the gesture card. X hides it for good. No trigger, no cooldown, no "used it already" check, no way to read tips again. |

Paywall: nothing is sold or gated today (`premium_offer` off); when on, it shows only under More and
the integrations page. It stays out of onboarding in every option. The app has no push
notifications, so no option asks for the notification permission.

Analytics today: `first_open`, `household_created`, `invite_sent`, `invite_accepted`, `item_added`,
`item_ticked` and a few more, consented installs only. No onboarding funnel and no activation query
exist.

## Activation metric

**Aha:** "Lea's Milch is on my phone" or "what I ticked is gone from Peter's list". A solo user who
adds 20 items has done setup, not the aha (research A).

**`household_activated` (primary):** within 7 days of `household_created`:
- 2 or more members,
- 5 or more items added,
- at least one add or tick by a member who did not create the household.

**`solo_value` (secondary, for households that stay alone):** 3 or more items in the first session
and the list opened again on another day within 7 days.

Measured two ways:
- PostHog (HogQL in `analytics/queries/activation.sql`), consented installs only, so a biased
  sample. It gives the funnel per step.
- A Postgres aggregate (counts only, no ids leave the database) over `household_members` and
  `items.added_by`, run read-only by Peter or the weekly report. It covers every household,
  consent or not, because it reads the service's own data for its own statistics (Art. 6(1)(f),
  balancing note in `docs/PRIVACY_DATA_MAP.md`).

Funnel: sign-in, consent answered, household created, first item, invite sent, invite accepted,
first cross-member write, back in week 2. The step to optimise is invite accepted.

## Good friction: the rule this plan uses

A step earns its place when its answer visibly changes the next screen, the user builds something
they keep, or the user commits to something (research B). The store picker already passes: the
list is grouped by the stores picked. Steps that only collect data for us fail the test and stay
out of onboarding. Every step has a skip of equal weight, not a grey link under a big button
(EDPB 03/2022, "hidden in plain sight").

## Approaches

### O1 Polish (2.5 lane-days)

Same screens and order as today.
- Sign-in: one value line under the wordmark: „Eine Einkaufsliste für euren Haushalt. Live auf
  jedem Handy.“ / "One shopping list for your household. Live on every phone."
- Empty list: staple chips under the empty-state text ("Milch", "Brot", "Eier", …, 12 chips, the
  user's language). A tap adds the item through the normal `AddItem` op, so it is classified and
  sorted at once.
- Invite again: when the household has one member, the empty state and the checklist offer
  „Partner einladen“.
- "Erste Schritte" card in the gesture card's place, 3 items: list started (done), invite
  someone, one shop done (all ticked). The gesture sentence moves into the last item. X hides it.

Weak spot: the empty list stays the first thing a new user sees, and the invite comes before there
is anything to share.

### O2 Guided start (4.5 lane-days, recommended)

O1, plus two steps inside onboarding. Order (new steps marked):

1. Sign-in with the value line (O1).
2. Analytics question (unchanged, legal text fixed).
3. Welcome: create or join (unchanged; an invite link skips to join).
4. **New: „Mit wem kaufst du ein?“ / "Who do you shop with?"** One tap: Partner·in, Familie, WG,
   Verein oder Team, Nur ich; "Überspringen" as a full button. The answer prefills the household
   name („Unser Haushalt“, „Familie“, „Unsere WG“, „Unser Verein“, „Meine Liste“), picks the invite
   copy and the checklist, and is stored on the household as `kind` (shared with job 169, which
   needs it for clubs; same five values in both plans). "Nur ich" skips the invite step.
5. Name and stores (today's screen, prefilled from step 4).
6. **New: „Was fehlt gerade?“ / "What do you need right now?"** 12 staple chips and a field. Each
   tap drops the item into a live mini-list grouped by the stores and categories just picked, with
   the line „Hummlist sortiert für dich“. This is the labor-illusion payoff for step 5 and ends the
   empty first list. Button „Weiter“ (it says how many items were added) and „Überspringen“.
7. Invite (today's screen), copy by `kind`, for a partner: „Teile die Liste mit der Person, mit
   der du einkaufst. Sie sieht deine 4 Artikel sofort.“ / "Share the list with the person you shop
   with. They see your 4 items right away." For a club: „Teile den Link in eurer Vereinsgruppe.“
   (with job 169's group link, 30 days and up to 50 uses; until it ships, the club copy says one
   link per member, as the prototype does).
   The item count makes the invite concrete.
8. List with the "Erste Schritte" card (O1). For `kind = club` on web and desktop, the card's
   third item is „KI-Assistenten verbinden“ (More → Zugänge), the club niche's own aha.

Each new step is one screen, one tap, skippable, and changes what comes next. Total taps to the
list for a skipper: the same as today plus 2.

### O3 Try first (10 lane-days, not before Nov 28)

A guest list before any account: Supabase anonymous sign-in creates a real user and household, the
user adds items at once, and the account wall comes at the first invite or on a second device
(`linkIdentity` / email upgrade). Duolingo moved its sign-up later and reported about 20 % more
daily users (research B). Costs: anonymous-user cleanup, abuse limits (captcha), account deletion
and consent order for users without an email, the analytics question before any account, store
review of "use without account", and e2e for every path. It also needs O2's screens. Worth a
measured experiment after launch, not a rewrite now.

### Recommendation

O2. It fixes both weak spots of O1 (empty first list, invite before content) for 2 more lane-days,
it gives job 169 the household `kind` it needs, and it keeps the account model. O3 is the right
next experiment once there is traffic to measure it.

## Contextual hints

### Rules (all options)

From Apple's HIG and TipKit, Material feature discovery and NN/g (research E):
- One hint on screen at a time; the gesture card and checklist share the same budget.
- At most one new hint per session and per 24 h.
- Never in the first session before the first item, never in onboarding, never over an open
  sheet, dialog or keyboard, never in the first 10 s after start.
- A hint for a feature the user already used never shows (retired on use).
- X means never again; no snooze. A hint shown 3 times without a tap or X retires itself. After 3
  X in a row, all hints pause for 14 days.
- Title plus at most 2 short sentences, one action, the real icon. No premium upsell in hints.
- Every hint can be read again under More → „Tipps“.
- Placement: the list's tip card slot, or an anchored callout above or below the control it is
  about. Never inside a HexPill or a store badge (Peter, 2026-11-05).
- State lives on the device (`DeviceCache`, per user): ids, counters, timestamps. It is the user's
  own "hide this" choice, needed to honour it (§ 25 (2) no. 2 TDDDG). Hint events go to PostHog
  only after the analytics yes.

### Hint catalogue (first set)

| id | Trigger (eligible when) | Retired when | Surface | Platforms |
| --- | --- | --- | --- | --- |
| `edit-long-press` | 5 items on the list, no long-press yet | first long-press | card | all |
| `quick-add-amounts` | 5 typed adds without an amount | an add with an amount | card | all |
| `dictation` | 10 typed adds, mic never used | mic used | callout above the add bar | iOS, Android |
| `siri` | 3 active days, no Siri add | first Siri add | card | iOS |
| `store-order` | first finished shop in a household with a store | a category reorder | callout under „Anpassen“ | all |
| `add-store` | 3 active days, household has no store | a store added | callout under „Anpassen“ | all |
| `invite-partner` | 1 member, 3 items, 1 day after creation | a member joins | card with the invite button | all |
| `second-household` | 14 active days (ships with job 169) | a second household exists | card | all |
| `ai-assistant` | `kind = club`, or 7 active days on web or desktop | an assistant connected | card | web, macOS, Windows, Linux |
| `home-widget` | 5 active days | a widget placed | card | iOS, Android |

### H1 Tips 2 (1.5 lane-days)

Extend today's `Tip` with `retiredBy` (a usage counter that ends it) and a 24 h cooldown, add the
"Tipps" page under More, and fill the fixed queue with the catalogue above. Order stays fixed;
there are no behaviour triggers, so a tip can arrive long before or after it helps.

### H2 Trigger hints (3 lane-days, recommended)

One `Hint` registry in `app/lib/tips/` replacing the queue:
`Hint(id, trigger: Rule, retiredBy: Signal, surface: card | callout(anchor), platforms, versions)`.
A `UsageLog` on the device counts the signals the app already knows (typed add, add with amount,
mic, Siri add, long-press, reorder, store added, member joined, active day). A pure function
`nextHint(registry, log, now, context)` applies the rules above, so the whole policy is unit-tested
without widgets. The tip card and a new anchored `HintCallout` render the result. New hints are a
registry entry plus two ARB strings.

### H3 Remote-tuned hints (5 lane-days)

H2 plus a public `hint_config` table (enabled, order, thresholds per hint id), read at start, so
Peter can switch hints off or retune triggers without a release. Copy stays in the ARB files (the
`no-hardcoded-ui-text` rule and review), so new hints still need a release. Two extra days for a
knob that saves little once the first set is tuned.

### Recommendation

H2. It is the version of the research's rules that the app can keep without code changes for each
retune: the thresholds live in one table in Dart, and `nextHint` is tested in isolation. H3's
remote switch can be added later on top of H2 if the first weeks show a hint that annoys.

## Data to collect

| Data | Purpose | Legal basis | Consent | Where it lives |
| --- | --- | --- | --- | --- |
| Who you shop with (`kind`: partner, family, flat, club, solo) | Prefills the name, picks invite copy, checklist and hints | 6(1)(b) contract: it configures what the user sees next | No; skippable | `households.kind` (shared with job 169) |
| Household name, stores, their order | List grouping (exists) | 6(1)(b) | No | `households`, `stores` |
| Starter items picked | They are list items | 6(1)(b) | No | `items` |
| Hint state (ids, counters, dates) | Honour "hide", retire on use, cooldown | § 25 (2) no. 2 TDDDG, 6(1)(f) | No | Device only, never sent |
| Onboarding and hint events (`kind`, step, hint id) | Funnel, activation, which hints help | 6(1)(a) | Yes, the existing analytics yes | PostHog EU |
| Referral source („Wie hast du von Hummlist erfahren?“, fixed choices plus „Keine Angabe“) | Which channels work, for marketing spend | 6(1)(a), sent only after the analytics yes | Yes (Q-O3) | PostHog event property |
| Activation counts | Is onboarding working, for everyone | 6(1)(f) on the service's own data, counts only | No; listed in the privacy policy | Postgres aggregate, nothing exported |

Not collected, on purpose: diet, allergies or religion-linked preferences (Art. 9 risk, CJEU
C-184/20), age beyond the 16+ statement, gender, household size as a number (the member count
says it), contacts, location, a newsletter opt-in (Legal N-18 keeps email out of invites).

Each new row goes into `docs/PRIVACY_DATA_MAP.md` and the privacy policy in the phase 2 PR. Legal
reviews the referral row and the activation aggregate before release.

## PostHog events (all in `eventCatalog`, consented installs only, no text)

| Event | Properties | Fires |
| --- | --- | --- |
| `onboarding_step_viewed` | `step`: welcome, kind, stores, starter, invite | each step shown |
| `onboarding_completed` | `kind` (or `skipped`), `starter_count` 0-20, `store_count` 0-50, `invited` bool | list reached from onboarding |
| `item_added` | new `source` value `starter` | a starter chip tapped |
| `checklist_step_done` | `step`: invite, first_shop, assistant | an item of "Erste Schritte" done |
| `checklist_dismissed` | `open_steps` 0-3 | X on the card |
| `hint_shown` / `hint_dismissed` / `hint_acted` | `hint_id` (catalogue ids) | per hint |
| `referral_answered` | `source`: friend, invite, app_store, search, social, ai_assistant, press, other, none | if Q-O3 is yes |

New insight: `analytics/queries/activation.sql` (funnel and `household_activated` share by week of
creation), with a fixture test in the analytics gate like the existing gate insights.

## Ties to the invite loop (job 169)

- `households.kind` is the shared field (`partner`, `family`, `flat`, `club`, `solo`, nullable):
  168 asks for it, 169 uses it for invite copy, club roles and group links. Whichever job lands
  first adds the column; both plans use the same name and values.
- Three invite moments from onboarding: the invite step (with the item count), the checklist's
  invite item, and the `invite-partner` hint after a day alone. All use `invite_share.dart` and the
  user's own share sheet (N-18: Hummlist never emails an invitee).
- The join side: an invite link already skips to the join screen; O2 adds nothing before it, so a
  joiner reaches the shared list in sign-in, consent, join. Joiners skip "Mit wem" and the starter
  step (the list already has items) and see the checklist without the invite item.
- `second-household` hint and the "create a second household" path ship with 169's switcher.
- Club path: `kind = club` gives the club invite copy and the AI assistant item, the start of the
  MCP niche.

## Phase 2 sketch for O2 + H2 (7.5 lane-days)

1. Router and screens: `/welcome/kind`, `/welcome/starter`, value line, copy in both ARB files (1.5).
2. Starter chips (onboarding and empty list) through `AddItem` ops, live mini-list (1).
3. "Erste Schritte" card replacing the gesture card while open, per-kind items (1).
4. `Hint` registry, `UsageLog`, `nextHint`, callout, More → Tipps, catalogue (3).
5. Events, activation query and fixture test, privacy data map, feature files
   (`onboarding.md`, `tips.md`, FEATURES-FOR-WRITERS), e2e for the new steps (1).

## Questions for Peter

- **Q-O1** Approach: O2 (recommended), O1 or O3? Default: O2.
- **Q-O2** Starter step: should tapped staples go on the real list (they can be ticked or deleted),
  or only fill a preview that the user confirms? Default: the real list, because it teaches
  ticking on the user's own items.
- **Q-O3** Ask „Wie hast du von Hummlist erfahren?“ once, after the first finished shop, only for
  users who said yes to analytics? Default: no until Legal confirms the row.
- **Q-O4** Hints: H2 (recommended), H1 or H3? And is 1 hint per 24 h right, or quieter (1 per
  week)? Default: H2, 24 h.
- **Q-O5** Club path: show „KI-Assistenten verbinden“ in the club checklist from day one, or wait
  for job 169's club features? Default: from day one, it only links to the existing Zugänge page.
