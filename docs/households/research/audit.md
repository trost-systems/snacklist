# Job 169 audit: multi-household, invite loop, club-ready households

Repo: /home/agents/fg-wt/169-households-invite (paths below are relative to it). Read-only audit, 2026-11-07.
M/ = supabase/migrations/, F/ = supabase/functions/, A/ = app/lib/.

## 1. Data model

### Tables
- `profiles` (M/20261022150000_foundation.sql:8-12): id, display_name, created_at. **No current-household column.**
- `households` (foundation.sql:32-37): id, name (1-80, default 'Unser Haushalt'), created_by, created_at.
  Job 43 added `archived_at`, `archived_by` + check (M/20261031123504_household_bound_lifetime.sql:531-537).
- `household_members` (foundation.sql:39-46):
  - `household_id`, `user_id uuid not null unique` (line 42, comment line 41: "A user belongs to at most one household; joining another one moves them."), `role text check (role in ('owner','member'))` default 'member' (43), `joined_at`, PK (household_id, user_id) (45).
  - **The `unique (user_id)` constraint is THE hard block on 2+ households.** No later migration drops it (grep for household_members alterations found none).
  - Roles: only owner/member. Creator = owner (create_household). Owner passes to earliest-joined member on account deletion (delete_account, household_bound_lifetime.sql:705-723). Roles gate nothing else today (no RLS uses role).
- `invites` (foundation.sql:56-64): id, household_id, `code` unique, check `^[A-HJ-NP-Z2-9]{8}$`, created_by, created_at, expires_at (default 14 days -> changed to 7 days in M/20261030120000_onboarding_invites.sql:7), revoked_at.
  Added `used_at`, `used_by` (onboarding_invites.sql:11-13). **Single use** (used_at set on accept; accept_invite onboarding_invites.sql:110-112, latest household_bound_lifetime.sql:595-597).
  Who creates: any member via `create_invite(p_household)` (foundation.sql:309-332, checks `is_household_member`). No per-household cap on open invites; no role check.
- `invite_attempts` (onboarding_invites.sql:25-33): failure rate limit, 10/user/hour, no client access.
- `household_departures` (M/20261031194500_purchase_legal_fixes.sql:94+): one-hour record of left memberships for purchase_claim.
- Tokens: `personal_access_tokens` (M/20261022205008_personal_access_tokens.sql:5-16) has **`household_id not null`**; later `kind` (pat/siri/api), `scopes`, `session_id` added (siri_credentials, public_api migrations).
- Premium: `purchases` (M/20261030190000_purchases.sql:14+) with `bound_household` (household_bound_lifetime.sql:19); `entitlements` (purchases.sql:44-58; reshaped household_bound_lifetime.sql:73-93) keyed by `household_id`.

### Helpers
- `is_household_member(p_household uuid)` foundation.sql:48-54: `exists (select 1 from household_members where household_id = p_household and user_id = auth.uid())`. security definer, stable. This is multi-household-safe by itself.
- **No `current_household_id()` helper exists** (grep: none). "Current household" = the (only) row in household_members for the user. Every consumer does `select household_id from household_members where user_id = ...` without `limit`/order (listed in section 2).

### Lifecycle RPCs (latest definitions)
| RPC | Latest def | Single-household behaviour |
|---|---|---|
| `create_household(p_name, p_default_stores, p_stores)` | M/20261102084411_no_default_stores.sql:6-45 | raises `already_in_household` if any membership exists (19-21); unique_violation -> same (27-31) |
| `create_invite(p_household)` | foundation.sql:309-332 | any member; random 8-char code |
| `check_invite` (internal) | household_bound_lifetime.sql:620-652 | statuses too_many_attempts / member / invalid_invite / ok; archived household's invites invalid |
| `preview_invite(p_code)` | M/20261031214500_premium_yearly.sql:562 (job 43 shape at household_bound_lifetime.sql:757-793) | `select m.household_id into v_current ... where m.user_id = v_user` (single-row assumption) for `leaves_unlocked` |
| `accept_invite(p_code, p_archive)` | household_bound_lifetime.sql:573-611 | **calls `leave_current_household(p_archive)` (606) then inserts membership (607-608): joining = moving** |
| `accept_invite(p_code)` | household_bound_lifetime.sql:613-616 | wrapper, archive=false |
| `join_household(p_code)` (legacy) | onboarding_invites.sql:133-143 | wraps accept_invite |
| `revoke_invite(p_invite)` | onboarding_invites.sql:146-155 | any member |
| `leave_current_household(p_archive)` | premium_yearly.sql:519-545 | `delete from household_members where user_id = auth.uid() returning household_id into v_household` (deletes ALL memberships; with 2 rows, `returning into` takes one). Last member -> household deleted, or archived if premium + switch `household_archive` |
| `leave_current_household()` (legacy, void) | foundation.sql:276-287 | same "delete all of mine" |
| `unarchive_household(p_household, p_archive)` | household_bound_lifetime.sql:670-686 | leaves current household first (681) |
| `archived_households()` | premium_yearly.sql:548-560 | lists `archived_by = auth.uid()` |
| `leaves_unlocked()` | M/20261102091002_leaves_unlocked.sql:4-15 | `select ... from household_members m where m.user_id = auth.uid()` scalar subquery: errors with >1 row |
| `delete_account(p_user)` | household_bound_lifetime.sql:689-735 | `select h.id into v_household ... where m.user_id = p_user for update` single household; would only handle one of several |

There is **no remove-member / kick RPC, no rename RPC (households_update RLS allows direct rename by any member, foundation.sql:398), no plain "leave" UI**. No max-members limit anywhere (grep `max_members`, member count checks: none). Only analytics caps `household_size` at 1-100 (A/analytics/events.dart:69).

## 2. RLS

foundation.sql:376-421:
- profiles: select self or anyone sharing a household (385-392); update self.
- households: select/update if `is_household_member(id)` (396-399). No insert/delete policy (RPC only).
- household_members: select if member of that household (401-402). No insert/update/delete policy: membership only changes through RPCs.
- invites: select for members (404-405). Update policy removed in job 22 (onboarding_invites.sql:20-21), revoke via RPC.
- categories/stores/store_category_order/items: `for all` with `is_household_member(household_id)` (410-417); item_events select (419-420).
- entitlements select for members (purchases.sql:73-75); personal_access_tokens own+member (personal_access_tokens.sql:22-27); api_household_days for members (M/20261102130000_public_api.sql:108).

RLS itself is membership-based and would work for N households per user. **What assumes one household** (each would return arbitrary row, error, or delete everything once user_id is no longer unique):
- `household_members.user_id unique` (foundation.sql:42) - the constraint.
- `create_household` `already_in_household` guard (no_default_stores.sql:19-21, 27-31).
- `accept_invite` -> `leave_current_household` (household_bound_lifetime.sql:606); `unarchive_household` (681).
- `leave_current_household` deletes all of the caller's memberships (premium_yearly.sql:524-525).
- `preview_invite` `select into v_current` (household_bound_lifetime.sql:768 / premium_yearly.sql:562+).
- `leaves_unlocked()` scalar subquery (leaves_unlocked.sql:6-13).
- `create_personal_access_token` `select ... into v_household` (M/20261031213000_siri_credentials.sql:24; original personal_access_tokens.sql:58).
- `create_siri_credential` (siri_credentials.sql:68).
- `create_api_token` (M/20261102200000_public_api_switch.sql:31; orig public_api.sql:49).
- `feedback_before_insert`: `new.household_id := (select m.household_id from household_members m where m.user_id = new.user_id)` (M/20261030070000_feedback.sql:74) - errors "more than one row returned by a subquery".
- `export_my_data` `'household', (select jsonb_build_object(...) ... where m.user_id = v_user)` scalar (latest M/20261102213000_connected_app_devices.sql:122-127) - would error.
- `delete_account` single household (household_bound_lifetime.sql:698-702).
- `tester_grant_trigger` (household_bound_lifetime.sql:148-165) used a single-row select; dropped in M/20261101150000_testers_via_revenuecat.sql:36.
- `purchase_claim` / `purchase_grant` check membership of a named household (fine for multi).
- `limit 1` hits in migrations are classifier / premium-row ordering, not household selection, except `delete_account`'s owner handover (limit 1 on remaining members, fine).

## 3. Invite flow end to end

Create (app):
- More -> "Partner einladen" (`/more/invites`, A/app/router.dart:69) -> `InvitesPage` (A/household/invites_page.dart) -> `InvitesCubit.create()` (A/household/invites_cubit.dart:48-54) -> `SupabaseInviteRepository.create` RPC `create_invite` (A/household/invite_repository.dart:135-141).
- Onboarding Step 3 `/welcome/invite` (A/household/invite_partner_screen.dart:15-19, 81-91): same create + share sheet.
- Open invites: direct select on `invites` (invite_repository.dart:144-155), revoke via `revoke_invite` (157-160).

What is shared:
- Link `https://app.hummlist.com/join/<CODE>` in apps (`Environment.appUrl`), page origin on web: `inviteLink` A/household/invite_share.dart:74-77, `joinPath` A/app/router.dart:92.
- Text (ARB): DE "Komm in unseren Hummlist-Haushalt: {link} · Code: {code}" (app/l10n/app_de.arb:524), EN "Join our Hummlist household: {link} · Code: {code}" (app/l10n/app_en.arb:496); code-only variant if no APP_URL.
- Channels tracked: share_sheet / copy_link / copy_code (invite_share.dart:27-31).
- Copy is partner-specific ("Partner einladen", "Invite your partner", app_de.arb:72, app_en.arb:66; page text "valid 7 days and for one person").

Link handling:
- Routes: `/join` and `/join/:code` (router.dart:436-440), `/more/join` (376). `inviteIn(uri)` reads `/join/<code>` or `?invite=` (172-179).
- Universal links: app/ios/Runner/Runner.entitlements (`applinks:app.hummlist.com`); app/web/.well-known/apple-app-site-association (`/join/*` component); Android app/android/app/src/main/AndroidManifest.xml:43-54 (autoVerify, pathPrefix `/join/`); app/web/.well-known/assetlinks.json; app table A/app/deep_links.dart:15-22 (checked by test/app/deep_links_config_test.dart). vercel.json:9-11 SPA rewrite excludes `.well-known`, serves AASA as JSON. docs/DEEP_LINKS.md:30.
- **No deferred deep linking**: a user without the app who taps the link gets the web app (sign-in) at app.hummlist.com; if they install from a store instead, the code must be typed (share text includes the code for that reason). No store-redirect / smart banner / install attribution.

Signed-out invitee:
- Router stores the code immediately (`pendingInvite.remember`, router.dart:458-461) in `PendingInvite` (A/household/pending_invite.dart, device storage, 7-day lifetime, line 46) - survives sign-up, custom-scheme callback, app kill, consent, onboarding.
- `authRedirect` (router.dart:203-255): SignedOut -> `/login?invite=<code>` (carry, 225-232); NeedsHousehold + invite -> `/join/<code>` skipping Step 1 (235); InHousehold + invite -> `/join/<code>` (243). Login screen carries invite for magic link (A/session/login_screen.dart:22-46).
- Cleared on join / cancel / invalid / sign-out (pending_invite.dart:73-96).

Join flow:
- `JoinCubit` (A/household/join_cubit.dart): `check` -> `preview_invite`; `join` -> `SessionCubit.join` -> RPC `accept_invite(p_code, p_archive)` (A/session/session_cubit.dart:236-272); then `refresh()`.
- Already in a household: **not blocked; it is a switch**. Join screen warns ("Du bist schon in einem Haushalt", member-count-aware: A/household/join_screen.dart:162-189; strings app_de.arb:109, 515-518) and Cancel is prominent. Server leaves the old household (deleted if last member, archived if premium + `household_archive` switch). DECISIONS Job 22 #4 (docs/DECISIONS.md:3410-3412).
- Billing warning before leaving a household with a yearly plan (join_screen.dart:76-85).
- Server checks: auth, rate limit (10 fails/hour), member short-circuit, unused/unrevoked/unexpired, target not archived, row-lock race for single use (household_bound_lifetime.sql:573-611; onboarding_invites.sql:37-77).
Leaving / removing:
- No leave button, no member list, no remove member, no rename (feature map household-invites.md Gotchas). Leave = join another household or delete account. `leave_current_household` RPC exists and is granted but no app caller (grep).
- Max members: none.

## 4. Session / household state (A/session/)
- States: `SessionLoading`, `SignedOut`, `NeedsHousehold(userId)`, `InHousehold(userId, Household{id,name})` (session_cubit.dart:11-38). Exactly one household in state.
- Picks the household: `refresh()` = `from('household_members').select('households(id, name)').eq('user_id', userId).maybeSingle()` (session_cubit.dart:161-165). **`maybeSingle` throws with 2+ rows** (PostgREST error).
- `SessionCache` / `DeviceCache` stores one household per user (`household.<userId>`) and `remember` drops the user's cached lists of any other household (A/app/device_cache.dart:296-320; DECISIONS.md:364-372).
- No switcher UI. The "switch" is joining another household via invite or `unarchive` (session_cubit.dart:277-289).
- `ListScope` (A/list/list_scope.dart:19-46) provides `ListCubit` keyed `ValueKey(household.id)`: a new household id rebuilds the ListCubit (new repository, new device cache slot) while the `AppShell`/StatefulShellRoute (A/app/shell.dart:135, router.dart:399-405) persists. That is the "shell state survives household switch" behaviour. ListCubit notes it closes on household switches (A/list/list_cubit.dart:1477).
- Other single-household reads in app: A/settings/account_repository.dart:151-155 (`maybeSingle` for deletion fate), A/oauth/consent_screen.dart:126-143 (consent shows the one household), A/siri/siri_credentials.dart:125 (credential per InHousehold), A/home_widget (one payload), A/purchases/entitlements.dart:256-268 (watches the session's household), A/list/list_repository.dart:191-200 (profiles of everyone the user shares any household with, filtered by member ids: multi-safe).

## 5. Paywall / RevenueCat
- **Premium is per household.** RevenueCat App User ID = household UUID: A/purchases/revenuecat_repository.dart:22-37 (`..appUserID = householdId`, `Purchases.logIn(householdId)`); docs/PURCHASES.md:29-32. Model A: "One member pays; the whole household has it" (PURCHASES.md:15-25). Purchase bound to first household forever (`purchases.bound_household`, household_bound_lifetime.sql:19-25).
- Server: `entitlements` (household_id, kind 'premium', source purchase/promotional, premium_source yearly/lifetime/promotional, expires_at, auto_renew); `household_premium(p_household)` latest M/20261101150000_testers_via_revenuecat.sql:87-109; `household_has_premium` M/20261031214500_premium_yearly.sql:112-115; `household_internal` testers_via_revenuecat.sql:117-122. Webhook F/purchases/handler.ts (claim requires buyer was member of named household, 281-290).
- Gates today: only integrations via `integration_gate(household, integration)` (M/20261102130000_public_api.sql:289-311): Siri, MCP, API locked without premium when `app_switches.integration_lock` on; Alexa free (M/20261102120000_alexa_free.sql). Premium card lists Siri + AI assistants (A/purchases/premium_features_card.dart:39-41). Switches `integration_lock`, `premium_offer`, `household_archive` all seeded off; app defines `REVENUECAT_PURCHASES`, `INTEGRATION_LOCK`, `HOUSEHOLD_ARCHIVE` off (A/app/environment.dart:83-91).
- **No free limits** on members, lists, stores or items. The list, sync, categories, app and web stay free (PURCHASES.md:519-523). API has per-household rate limit 1000/day (docs/API.md:237).
- Multi-household implications: buying in household A doesn't unlock B; a user in 2 households would see per-household premium; archive rules use "last member leaving".

## 6. Integrations: how the household is resolved
| Surface | Credential | Household resolution | Bound to household id? |
|---|---|---|---|
| MCP (F/mcp) | OAuth JWT (Supabase OAuth 2.1) or app session | `_shared/auth.ts:98-108` -> `householdOf(userId)` (F/_shared/db.ts:72-77: `select household_id from household_members where user_id = $1`, takes first row) per request | **No** (OAuth grant is per user/client; follows the user's current household) |
| MCP / voice via PAT `fgp_` | personal_access_tokens kind pat | `authenticate_access_token` (siri_credentials.sql:105-120) returns row's household if creator still member | **Yes** (`household_id` set at creation from the single membership) |
| Siri native credential | kind siri | same, plus session must exist | **Yes** |
| Public API (F/api) | api key (kind api, scopes) | `api_begin` (public_api_switch.sql:75-201) joins token.household_id with membership | **Yes** |
| Alexa (F/alexa) | Supabase OAuth via account linking | `authenticate` -> `householdOf` (F/alexa/deps.ts:13-17; header comment F/alexa/handler.ts:4-7 "user's CURRENT household ... read per request"); analytics subject joins household_members `limit 1` (F/alexa/store.ts:55-80) | **No** |
| voice (F/voice) | PAT or siri credential (`authenticate` with siri:true) | token's household | Yes |
- MCP tools use `auth.householdId` (F/mcp/tools.ts:89). REST helpers in F/_shared/list.ts take `household` explicitly and run as the user under RLS (multi-safe).
- Tokens are revoked when the creator leaves that household (trigger M/20261101100000_access_key_retention.sql:31-45). With multi-household, tokens already carry household_id; only creation (select into from membership) needs a household parameter. OAuth/Alexa need a "which household" rule (default household per user or per grant).
- Voice protocol ignores a `list` param "for a future list id" (DECISIONS.md:5192-5197).

## 7. Onboarding / first run
- After sign-in: analytics consent (if undecided) -> NeedsHousehold -> `/welcome` (A/household/welcome_screen.dart:14-16; two cards: create `createHouseholdPath` line 42, join `joinCodePath` line 50) -> `/welcome/create` (A/household/create_household_screen.dart:26-31; name + stores, "Überspringen") -> `/welcome/invite` Step 3 (invite_partner_screen.dart) -> list. Invite link skips Step 1 to `/join/<code>`.
- Router `_beforeHousehold = {welcome, create, join}` (router.dart:183) and InHousehold redirect: `/welcome/create` while InHousehold -> `/welcome/invite` (245); InHousehold users can't stay on `/welcome` or `/welcome/create` (falls to list, 252).
- Hook for "create second household": would need (a) server `create_household` without the guard, (b) a route reachable while InHousehold (router currently redirects `/welcome/create` -> Step 3 only right after creation via the session change; navigating there while InHousehold yields `/welcome/invite`), e.g. a `/more/households/new` page reusing CreateHouseholdScreen, and (c) More's household group (A/more/more_screen.dart:188-208, 244-262, 320-334: rows invite, join, archived) for a switcher.

## 8. Analytics
A/analytics/events.dart:
- `JoinMethod {link, code}` (36-38); `household_created {default_stores, store_count 0-50}` (78-81); `invite_accepted {method}` (82); `invite_sent {channel: share_sheet|copy_link|copy_code, context: onboarding|settings}` (85-88); `actor_role owner|member`, `household_size 1-100` on item events (68-69, 92-113); `household_id` super-property (186).
docs/ANALYTICS.md: event table lines 146-148 (household_created, invite_accepted, invite_sent); `household_id` person/property and optional `$groups: {household}` with `ANALYTICS_HOUSEHOLD_GROUPS` (135-139); WAH, paying share, household retention keyed on household (12-16, 386-399). No events for invite_opened/previewed, invite_link_landed, join_cancelled, household_switched, member count growth, invite conversion funnel. Analytics `setUser` takes one householdId (session_cubit.dart:293-306, 343-353).

## 9. DECISIONS (docs/DECISIONS.md)
- 1.2 "One household per user" (line 12-16): `user_id` unique; joining moves the user; last member -> household deleted; "multi-household support would only add a switcher nobody needs" (Peter and Lea share one list). **The decision to supersede.**
- 1.3 "Invites are codes, never sent" (17-19): 8 chars, originally 14 days reusable (superseded by job 22).
- 3.7 PATs (207-215): token acts in the household it was created in; dies when creator leaves.
- 9.4 household after deletion (851-857): others keep it, owner passes to earliest-joined.
- Offline cache (364-372): household switch drops the user's other cached lists.
- Job 29a #3 (3287): no household name in the list header "one household per user".
- Job 22 (3400-3521): #1 invites 7 days, single use, any member revokes; #4 switch after warning, Cancel prominent; #5-#9 accept_invite/check_invite/rate limit/revoke; #11 idempotent create; #13 router flow; #14 PendingInvite; #15 universal links/App Links; #16 share text; #17 invite management in More.
- Job 43 (4654+): #1 purchase bound to first household; #7 join screen tells, never blocks; #8 archive instead of delete on last leave; #10 archive UI off in releases (`HOUSEHOLD_ARCHIVE`).
- Job 47 (5021+): `household_archive` server switch, 24-month archive deletion.
- Job 49 #22 (5520-5523): archive eligibility = has premium now.
- Job 51 (5192-5197): voice intents have no list parameter because one list per household and one household per user.
- Job 66 (6291+): explicit app-link path list incl. `/join/*`.
- Job 73/75 (6713+, 6783): API key household-bound; per-household rate limit; integration lock.
- Job 31 #2 (Alexa, ~3837): linked token's user, their current household, read at request time.

## 10. Feature map (.cursor/skills/verify-hummlist/features/)
- `household-invites.md` (only matching file; also onboarding.md and app-links.md cover joins). Says today: one household shares one list; a member creates an 8-char code + link (7 days, single use), shares/copies, revokes; join by code or link; someone in a household is warned that joining moves them; link survives sign-in/onboarding; rate limit; premium notes on join; archive off in prod. **"There is no screen to rename a household, list its members or leave it without joining another (or deleting the account)"**; no remove-member; no revoke-all.
- `onboarding.md`: Step 1 welcome (create vs accept invite), 2a create (name + stores), 3 invite partner ("Später"), 2b join.
- `app-links.md`: `/join/<code>` opens join screen; signed out -> `/login?invite=<code>`.
