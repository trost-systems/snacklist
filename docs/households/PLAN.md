# Households and the invite loop: plan (job 169, Phase 1)

Status: proposal for Peter, 2026-11-07. Nothing here is built yet.
Evidence: [`research/audit.md`](research/audit.md) (code audit with file:line citations),
[`research/invite-loops-pricing.md`](research/invite-loops-pricing.md) (invite loops, deep links,
switchers, pricing; one URL per claim), [`research/clubs-niche.md`](research/clubs-niche.md)
(German clubs). Clickable prototype: see "Prototype" below.
Not checked against the lead's growth research (`growth-research-2026-11-06.md`): that file never
reached the Hetzner runner. Compare once it does.

## Summary in 10 lines

1. Today a user can be in exactly one household. A database constraint enforces it, and joining
   another household moves you out of yours. The access policies already work for several
   households; about a dozen functions, the app's session and the integrations assume one.
2. Scope options: **HH1** many households (switcher, second household, join without leaving,
   leave) ~6.5 lane-days; **HH2** HH1 plus the invite loop (link page with inviter and household,
   store bridges, group link, members and roles, a household per AI connection) ~14 lane-days;
   **HH3** HH2 plus club features (several lists, "ich bringe", join approval, data processing
   agreement) ~24 lane-days.
3. Money options: **M-H1** Premium per household, as now (but one store account can pay for one
   household only, so a second household needs another member to pay); **M-H2** Premium per
   person, valid in all their households; **M-H3** M-H1 plus a member cap that makes large
   households (clubs) Premium.
4. Recommendation: **HH2 with M-H1**, in three waves, done before Nov 28. HH3 waits for a cheap
   club demand test.
5. The switcher is the household name at the top left of the list, opening a sheet (prototype S1).
6. The loop: create household → invite (link, QR for groups) → a light join page shows who invites
   to what → join in the browser or the app → a new member gets one nudge to start their own
   household. The Premium of a household covers everyone in it, which makes the join page
   two-sided without a referral programme once Premium is on sale (it isn't yet).
7. Invites stay links the user shares (N-18). No paid deep-link SDK, no fingerprinting. Android
   carries the code through the Play install; iPhone users paste it with one tap or type it.
8. Clubs: 629,000 registered clubs in Germany, but our estimate of organisers who can write through
   an AI agent is 0.5–1.5 %. That is a good story and a test, not the growth engine.
9. Main risks: old store builds break when a user has two households (fix: the server keeps showing
   old apps one default household), integrations that pick an arbitrary household, and the
   forwarded group link.
10. Questions for Peter: Q-HH1 to Q-HH5 at the end.

## 1. What exists (audit)

- `household_members.user_id` is `unique` (`supabase/migrations/20261022150000_foundation.sql:42`).
  Roles `owner` and `member` exist but gate nothing.
- `create_household` refuses a second household (`already_in_household`). `accept_invite` and
  `unarchive_household` first call `leave_current_household`, which deletes all your memberships.
- No "current household" concept: every reader takes "the" row. Functions that error or pick an
  arbitrary row with two memberships: `feedback_before_insert`, `export_my_data`,
  `leaves_unlocked`, `preview_invite`, `create_personal_access_token`, `create_siri_credential`,
  `create_api_token`, `delete_account`, and `householdOf()` in `supabase/functions/_shared/db.ts`.
- App: `SessionCubit.refresh()` reads the membership with `.maybeSingle()`, which throws with two
  rows. `DeviceCache` keeps one household per user and drops the others' lists. `ListScope` already
  keys the list on the household id, so a switch rebuilds the list cleanly.
- Invites: 8-character code, 7 days, single use, any member creates or revokes, link
  `https://app.hummlist.com/join/<CODE>`, universal links and App Links in place, the code survives
  sign-in and onboarding on the device (`PendingInvite`). No deferred deep link: after a store
  install the code is typed. Copy says "Partner".
- No member list, rename, leave or remove-member screen.
- Premium is per household: RevenueCat's user id is the household id; a purchase stays with its
  first household. Premium gates only Siri, MCP and the API, and all those switches are off.
- Integrations: personal tokens, Siri credentials and API keys store a `household_id` (fine).
  MCP and Alexa over OAuth resolve "the user's household" on every request (needs a rule).
- Analytics stop at `invite_sent`: no count of opened invite links, switches or member growth.
- Decisions to supersede: DECISIONS 1.2 "One household per user", Job 22 #4 "joining switches",
  Job 51's note on voice lists.

## 2. Data model and migration

Shape (one migration plus pgTAP, all additive except the dropped constraint):

```sql
-- membership: many households per user, one default
alter table household_members drop constraint household_members_user_id_key;
alter table household_members add column is_default boolean not null default false;
update household_members set is_default = true;               -- today every user has one row
create unique index household_members_one_default
  on household_members (user_id) where is_default;
alter table household_members drop constraint household_members_role_check,
  add constraint household_members_role_check check (role in ('owner','admin','member'));

-- household kind (shared with job 168, whichever lands first adds it)
alter table households add column kind text
  check (kind in ('partner','family','flat','club','solo'));

-- invites: person (today) or group link
alter table invites add column kind text not null default 'person'
  check (kind in ('person','group')),
  add column max_uses int not null default 1 check (max_uses between 1 and 200),
  add column use_count int not null default 0,
  add column preview_count int not null default 0;  -- join page opens, a counter, no identities
create table invite_uses (invite_id uuid references invites on delete cascade,
  household_id uuid not null, user_id uuid not null, joined_at timestamptz default now(),
  primary key (invite_id, user_id));   -- RLS: is_household_member(household_id)

-- AI connections: which household an OAuth client acts in
create table connection_households (user_id uuid, client_id text, household_id uuid,
  primary key (user_id, client_id));   -- RLS: own rows, and is_household_member(household_id)
```

New and changed functions:

| Function | Change |
| --- | --- |
| `my_households()` | New: id, name, kind, role, member count, item count, premium, is_default. The app's switcher reads this. |
| `set_default_household(h)` | New: moves `is_default`. The default serves old apps, Siri/Alexa and AI connections without a choice. |
| `create_household(...)` | New optional `p_request_id`. With it (new apps): no `already_in_household` guard; a unique index on `households (created_by, request_id)` makes a retry or double tap return the same household and replaces the old race guard. Without it (old store builds, which treat `already_in_household` as "it's there already"): the guard stays exactly as today, so an old app's retry never creates a second household. Free cap: 10 households per user (abuse guard). |
| `accept_invite(code, mode)` | New mode `add` (new apps): adds a membership and leaves nothing. The old signatures keep "move", but only out of the default household: they leave the default, insert the new membership and make it the default (`set_default_household`), so the old app shows the household it just joined and can't wipe the others. They refuse when the target is already one of the user's households (`check_invite`'s `member` status, extended to non-default memberships). |
| `leave_household(h)` | New: leave one household; the last member's household is deleted or archived as today. |
| `leave_current_household()`, `leave_current_household(p_archive)`, `unarchive_household(h, p_archive)` (old signatures) | Act on the default membership only: leave the default household (the trigger promotes the next), and `unarchive_household` then makes the restored household the default. Today they delete all of the caller's memberships, and `delete … returning household_id into` raises "more than one row" with 2+; old builds offer the restore under Mehr, so an old app would fail or wipe the other households. |
| `remove_member(h, user)`, `set_role(h, user, role)` | New (HH2): owner/admin only; the owner can't be removed. |
| `create_invite(h, kind)` | Group links: admin/owner only, 30 days, up to 50 uses, revocable; person links stay 7 days and single use. |
| `preview_invite_public(code)` | New (HH2), callable signed out: inviter first name, household name, member and item counts, never item names. Counts `preview_count`. Rate-limited per `X-Real-IP` and per code. |
| 9 single-row readers (audit section 2) | Take an optional household parameter; `export_my_data` exports all households and `delete_account` loops over all. Without the parameter (what old store builds send) they read the default: `feedback_before_insert` files feedback under the default household, `preview_invite` and `leaves_unlocked` judge the old join screen's warning against the default, and `create_personal_access_token`, `create_siri_credential` and `create_api_token` bind the new credential to the default. |
| `householdOf()` (functions) | Becomes: `connection_households` for this OAuth client, else the default household. |

**Old store builds.** TestFlight and Play builds lag `main`, and today's app reads
`household_members ... where user_id = me` with `.maybeSingle()`, which throws once a user has two
rows. Fix in the same migration: the `household_members` select policy shows a user's own rows only
when `is_default` (other members' rows stay visible as today). The new app never reads its own rows
directly: it uses `my_households()`, and member lists come from `household_members_of(h)` (security
definer, membership-checked), since the plain select would now hide the user's own row in a
non-default household. `is_household_member()` is security definer and unaffected,
so all list access keeps working. Checked in a scratch Postgres
([`proofs/old-app-policy.md`](proofs/old-app-policy.md)); Phase 2 makes it pgTAP. Until users update, an old app
shows the default household; switching on a new device moves nothing on the old one.

**Every user with a membership has exactly one default.** The old-app policy and the default for
Siri, Alexa and AI connections both depend on it. A membership can end by `leave_household`,
`remove_member`, a deleted household (cascade) or `delete_account`'s handover, so the rule sits in
one place that sees all of them: an `after delete` trigger on `household_members` that, when the
deleted row was the default, makes the user's oldest remaining membership (`joined_at`, then
`household_id`) the default in the same transaction. The trigger's subquery locks its pick
(`order by joined_at, household_id limit 1 for update`): without the lock, two leaves at once (an
admin's removal and the user's own leave, a deleted household and a leave) can pick a row the other
transaction just deleted, and the user ends with memberships but no default. Reproduced and fixed
in [`proofs/concurrent-leave.sh`](proofs/concurrent-leave.sh): without the lock the user is left
with household 3 and `is_default = f`, with it `is_default = t`. A user who left their last household has no
row and goes to onboarding, as today. The scratch proof covers leave and cascade
([`proofs/old-app-policy.md`](proofs/old-app-policy.md)): without the trigger the old app's query
returned 0 rows (the reviewer's run), with it the oldest remaining household.

**Phase 2 pgTAP cases** (in `supabase/tests/`): the old app's query returns one row with 2+
memberships; `household_members_of` for a member and a non-member; default promotion after a leave,
a removal, a deleted household and an account deletion; no default and no error after the last
leave; the old `accept_invite` makes the joined household the default and refuses a household the
user is already in; the new mode `add` leaves the default alone; one default per user (the partial
unique index) under concurrent joins and concurrent leaves (two sessions, as in
`proofs/concurrent-leave.sh`); `create_household` without a request id still answers
`already_in_household` to a member, with a request id a repeat returns the same household; the old
`leave_current_household` and `unarchive_household` touch only the default membership and leave
the others; `invite_uses` and `connection_households` across two
households in `rls.test.sql`.

**Data migration.** No row moves: every existing membership becomes the user's default. Rollback
before any user joins a second household is dropping the new objects; after that it is a forward
fix. The squawk compat rules allow all of it except the dropped constraint, which gets a
`-- squawk-ignore` line with the reason.

**RLS.** No new household-owned table without `is_household_member(household_id)`: `invite_uses`
and `connection_households` get the policy and a two-household case in
`supabase/tests/rls.test.sql`. The new risk is cross-household mixing inside one user's session:
every app query and realtime channel already filters by household id; the list cache key moves to
(user, household).

## 3. Switcher UX

Prototype variants (all clickable):

- **S1 (recommended):** household name chip top left of the list, opening a bottom sheet. One row
  per household: name, members, items, a check on the current one, "3 neu" beside it when others
  added items since you last looked, Premium as a one-word badge. Then "Neuer Haushalt" and "Mit
  Code beitreten", and a footer row "Sprachassistenten nutzen: Zuhause" for the default. This is
  Slack's, Notion's and Todoist's pattern (research section 3).
- **S2:** the household as the first segment of the tab pill. Always visible, but it crowds the
  pill on 358 px and mixes navigation with context.
- **S3:** swipe between households with page dots. Fast for two, lost at five, and a mis-swipe adds
  items to the wrong list. Rejected.

Rules: the app opens the last household used on this device. Each household keeps its own cached
list, scroll position and store view. A one-household user sees the chip too, so they discover a
second household; the chip carries only the name and an expand icon (no hint text in hex
controls). Leaving and the members list live in a household's page under More.

## 4. Invite loop

**Moments** (where we ask; 168 owns the onboarding ones):

| # | Moment | Who | Copy (DE) |
| --- | --- | --- | --- |
| 1 | Right after creating a household (onboarding and the switcher) | creator | „Wer kauft mit ein?" |
| 2 | Household alone, 3 items, 1 day later (168's `invite-partner` hint) | sole member | „Teile die Liste mit deinen Leuten." |
| 3 | Sheet row "Einladen" for any household | any member, admins for group links | „Leute einladen" |
| 4 | New hint `own-household`: the user's households were all created by others; their 2nd active day in the joined household (168's rules: never in the first session, one hint per day); retired when they create a household | invited member | „Auch eine Liste für zuhause? Lege einen eigenen Haushalt an und lade deine Leute ein." |
| 5 | Premium bought or active | payer | „Premium gilt für alle im Haushalt." (in the invite sheet) |
| 6 | 168's `second-household` hint: the user runs their own household, 14 active days | creator | „Noch ein Haushalt? Für Eltern, WG oder Verein." |

Moment 4 is the second hop: every invited member is a potential creator. Moments 4 and 6 are two
hints for two audiences: an invitee without a household of their own is offered one early, a
creator is offered a further one after two weeks. The prototype shows the moment-4 card right after
the join only to keep the demo short. Copy follows the
household `kind` (partner, family, flat, club, just me) instead of "Partner".

**Link and join page.** The shared text stays the user's own message:
„Komm in „Sommerfest" auf Hummlist: https://app.hummlist.com/join/K7Q2M9XD · Code: K7Q2-M9XD".
With the app installed, the link opens the app (universal link / App Link, as today). Without it:

1. A light page on `/join/<code>` (static HTML, no Flutter download first) shows "Peter lädt dich
   zu „Sommerfest" ein", the member and item counts, and "Premium gilt für alle im Haushalt" when
   true. No item names: a forwarded link must not leak the list.
2. Primary button "Im Browser beitreten": the Flutter web app's join flow as today. The account then
   carries the household into the app on any device. This is the free deferred deep link.
3. "App laden": on Android the Play link carries `referrer=invite%3D<code>`; the app reads it once
   with the Play Install Referrer API (free, 90 days). On iPhone the page has a Smart App Banner and
   a "Code kopieren" button; on first launch the welcome screen offers "Einladung einfügen". The
   app checks for a link without reading (`detectPatterns`, no prompt) and reads only on the tap.
   A Flutter button's read still shows iOS's "Einsetzen erlauben?" prompt once; only Apple's
   native paste control avoids it, and Flutter has none built in. Plan: accept the prompt in HH2
   (it follows the user's own tap); a native paste control as a platform view would cost about one
   more lane-day in part G.
4. Typing the code stays the fallback everywhere.

Not used: Branch, AppsFlyer, Firebase Dynamic Links (shut down 25 Aug 2025), App Clips,
fingerprinting (Apple's agreement and EDPB treat it as needing consent).

**Group link (HH2).** For clubs and big families: one link (and a QR code for the club meeting),
30 days, up to 50 joins, revocable, created by admins. "Wer ist beigetreten" lists names from
`invite_uses`. Person links stay single use for partners.

**Measuring the loop** (counts, consent-safe):

- Server, no consent needed (counts only, in the weekly report): invites created per household and
  kind, `preview_count`, `use_count`; households with 2+ members; new households whose creator
  joined another household first (second hop).
- App events (consent-gated, allow-list): `invite_sent` gets `context` values `switcher`,
  `second_hop`, and `kind: person|group`; `invite_accepted.method` gets `referrer` and `paste`;
  new `household_switched` (no properties) and `household_created.context: onboarding|switcher`.
- The loop's number: k = invites accepted ÷ households created, per week. No benchmark exists
  (research section 1), so the first month sets ours. 168's `household_activated` (2+ members,
  5+ items, a second writer within 7 days) is the activation side.

## 5. Monetisation options

| Option | What | For | Against |
| --- | --- | --- | --- |
| **M-H1 (recommended)** | Premium per household, as built: one member pays, everyone in that household has it; each household separately. | No migration. Once Premium is on sale, every paid household is a two-sided invite incentive. Today it is not: Premium isn't sold yet (hold `premium-launch`), the integration lock is off, and Premium would unlock only Siri, MCP and the API. AnyList household, Life360 Circle, Cozi Gold work this way. | A user with three households sees Premium in one only; the switcher must show it per household. A store account can unlock one household only: Apple allows one subscription per group per Apple ID, Lifetime is a non-consumable that stays with its first household, and RevenueCat answers `receiptAlreadyInUse` elsewhere (`docs/PURCHASES.md`, "Cases"). Peter can pay for „Zuhause" but never for „Sommerfest" from his own account; another member there has to. M-H2 removes this limit. |
| M-H2 | Premium per person: the buyer's Premium covers every household they are in. | Feels fair for multi-household users. | RevenueCat user id changes from household to user (migration of every purchase, Legal Review terms change); members who don't pay lose the "everyone has it" story; a club gets Premium free when one member has it. |
| M-H3 | M-H1 plus a free cap, e.g. 8 members or group links only with Premium. | The only option that charges clubs. | Clubs pay little (Spond is free, ClubDesk free to 50 members); the cap blocks exactly the viral club loop. Only worth an experiment after we see households above 8 members. |

## 6. Scope options

Effort in lane-days (one agent lane on the Hetzner runner for a day), estimates from comparable
jobs, not measured.

| Part | HH1 | HH2 | HH3 |
| --- | --- | --- | --- |
| A. Multi-membership migration, the 12 functions, old-app policy, pgTAP | 1.5 | 1.5 | 1.5 |
| B. App: session with several households, S1 switcher, create second household, join without leaving, leave | 2 | 2 | 2 |
| C. Integrations: default household, MCP `list_households` and an optional `household` argument, token creation per household | 1 | 1 | 1 |
| D. Invite copy by kind, moments 3–5, counters and events | 1 | 1 | 1 |
| E. e2e (switch, isolation, join without leaving), feature map, DECISIONS | 1 | 1 | 1 |
| F. Join page with preview, Smart App Banner, Play referrer link | | 1.5 | 1.5 |
| G. App store bridges: Install Referrer, paste-invite button | | 1.5 | 1.5 |
| H. Group link, QR, "Wer ist beigetreten" | | 1.5 | 1.5 |
| I. Members: list, roles, remove, rename | | 2 | 2 |
| J. AI connection picks its household at consent | | 1 | 1 |
| K. Several lists per household (items, realtime, stores, MCP, API, Alexa) | | | 5 |
| L. "Ich bringe" claims with quantities | | | 2 |
| M. Join approval, data processing agreement page (needs Legal Review) | | | 2 |
| N. Club landing page and waitlist question | | | 1 |
| **Total** | **6.5** | **14** | **24** |

- **HH1, many households.** Solves Peter's wish (partner, family, club side by side). The invite
  loop stays as today plus better copy. Club use works for small groups with person links only.
- **HH2, loop-ready (recommended).** Adds what turns one invite into many: a join page that says
  who invites to what, installs that don't lose the code, one link for a whole group, and admins
  who can remove someone. Enough for a club pilot on a household.
- **HH3, club-ready.** Adds what clubs asked for in the research (several lists, claims, approval,
  AVV). Several lists is a deep change to every item path. Clubs can use one household per list
  in HH2 meanwhile.

## 7. Recommendation

HH2 with M-H1, in three waves that each end green and merged:

1. Wave 1 (A–E, ~6.5 lane-days, two lanes in parallel: server+integrations, app): many households.
2. Wave 2 (F–H, ~4.5): join page, bridges, group link. Needs wave 1's `accept_invite` mode.
3. Wave 3 (I–J, ~3): members and roles, household per AI connection.

With two to three lanes this fits before Nov 28 next to job 168. Club niche: test demand without
building HH3 (club question on the waitlist, a pilot with 3–5 clubs that Peter recruits, a count
of households with more than 4 members).

## 8. Risks

| Risk | Mitigation |
| --- | --- |
| Old store builds throw with two memberships | Default-only select policy for own rows (section 2); pgTAP proves the old query returns one row. |
| The default membership ends (leave, removal, deleted household, account deletion) and an old app sees 0 rows, shows onboarding and creates a stray household; Siri and Alexa lose their household | `after delete` trigger promotes the oldest remaining membership in the same transaction (section 2); pgTAP for each path. |
| An old app retries `create_household` (double tap, lost answer, two devices) and gets a second household | The guard stays for calls without a request id; the new app's request id and a unique index cover retries (section 2); pgTAP for both. |
| An old app's restore (`unarchive_household`) or leave (`leave_current_household`) fails with "more than one row" or wipes the user's other households | Old signatures act on the default membership only (section 2); pgTAP. |
| Two leaves at once leave a user without a default | The trigger locks its pick (`for update`); proven in `proofs/concurrent-leave.sh`; pgTAP with two sessions. |
| Old `accept_invite` joins a household the user is already in, or leaves the new one non-default | Old signature refuses a target that is already a membership and makes the joined household the default (section 2). |
| A function picks an arbitrary household (data in the wrong household) | The single-row readers in audit section 2 are the checklist; a schema check fails on new `select ... into` from `household_members` without a household filter. |
| Voice or an agent writes into the club list by surprise | Default household changes only by an explicit choice or when the default membership ends (then the oldest remaining one); AI connections name their household on the consent screen; the Siri/Alexa answer names the household when the user has more than one. |
| Forwarded group link lets strangers in | 50-use cap, 30 days, revoke and "Wer ist beigetreten", remove member; join approval in HH3. |
| Join page enumerates codes | 40-bit codes, per-IP and per-code rate limits, counts but no item names. |
| The join page is a new signed-out exposure: today `/join/<code>` signed out goes to the login; the page would show the inviter's first name and a household name such as „Familie Brandt" to anyone holding the link | Only to link holders, and the inviter chose to share it; the first name and household name are what the shared text already says. Before HH2 ships: Legal confirms the basis (Art. 6(1)(f), the inviter's interest in being recognised) and the privacy notice gets a line under the invite section (N-18 stays: Hummlist sends nothing). |
| `list_repository` loads the profiles of everyone the user shares any household with, then filters to this household; a 50-member club next to the family grows every list load | Load profiles through `household_members_of(h)` joined to `profiles` for the current household only (part B). |
| Club GDPR: members see each other | Display names only (no emails anywhere today); a club data processing agreement before any club marketing (HH3, Legal). |
| Cache shows the old household's list after a switch | List state keyed on household id (already); cache keyed on (user, household); e2e covers it. |
| Premium confusion across households | Switcher shows Premium per household; the paywall names the household it unlocks. |

## 9. Coordination with job 168

168 owns onboarding: its welcome flow asks "Mit wem kaufst du ein?" and stores the answer as
`households.kind`, which this plan reuses for invite copy (whichever job lands first adds the
column). 168's `invite-partner` and `second-household` hints are moments 2 and 6 here; moment 4
(`own-household`, for invitees) is a new hint in 168's registry under 168's rules; its
`household_activated` metric is the activation side of the loop. Joining by invite skips 168's
questions (the household exists). Creating a second household reuses 168's create screen from the
switcher.

## Prototype

Static, throwaway, behind Vercel Authentication: `site/public/internal/households.html` on the
branch preview (URL in PHASE1_DONE). Two phones: Peter (switcher S1/S2/S3, new household, invite
sheet person/group) and Mia (join page, first run with the invite, joined list with the
second-hop card). DE/EN, light/dark. Screenshots in `docs/screenshots/169/`.

## Questions for Peter

- **Q-HH1** Scope: HH1, HH2 (recommended) or HH3?
- **Q-HH2** Money: M-H1 (recommended), M-H2 or M-H3?
- **Q-HH3** Group links: OK with one reusable link per household (30 days, 50 joins, revocable,
  admins only), or should every join need an admin's approval (slower, safer)?
- **Q-HH4** Siri, Alexa and AI agents: one default household per account that you choose
  (recommended), or always the household last opened in the app?
- **Q-HH5** Clubs: will you recruit 3–5 clubs for a pilot on HH2 (we may not contact anyone), or
  park the club niche until after launch?
