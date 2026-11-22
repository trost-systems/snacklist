# AN1: anonymous start, step one (design and Legal draft)

Status: DRAFT for Legal (job 375, 2026-11-22). Nothing here is built. Anonymous sign-in and manual
linking stay off, no flag changes, no live page changes. A later job builds this after Legal's hash
GO on this file. Facts about today's code carry file:line references as of main `688a9023d`.

Research this builds on: PM report of 2026-11-22, Q2 and the Q1 note (job brief `in/`), and the
O3 "Try first" option in [`docs/onboarding/PLAN.md`](../../onboarding/PLAN.md). The server
inventory behind section 6 was read from the migrations and a local database at main `688a9023d`.

All names and examples are fictional (the Brandt family, „Oma Ruth“).

## 1. The decision in 12 lines

1. **Anonymous start (apps only in step one).** The guided start's account step gets a second
   button, „Erst mal ohne Konto“. It signs in anonymously and turns the draft into a household,
   exactly as a sign-up does today. The list works at once.
2. **Same user id for life.** The upgrade links an email (`updateUser(email)`) or a Google/Apple
   identity (`linkIdentity` / `linkIdentityWithIdToken`) to the same user. RLS, RevenueCat's App
   User ID and history stay as they are; nothing is copied.
3. **Taken email or identity.** Supabase refuses the link. The user signs in to the existing
   account, and a one-time transfer moves the anonymous household into it.
4. **An account is required to share or to leave the device.** Inviting, joining, helper links, API
   keys, MCP and Alexa consent, Siri, Premium purchase and restore, and a second device all ask for
   the upgrade first. The server refuses them for anonymous users; the app shows the upgrade.
5. **Invites never join an anonymous id.** An anonymous user who opens an invite upgrades first,
   then joins. Their own list stays as a second household.
6. **The name step moves into the upgrade.** „Wie sollen wir dich nennen?“ is not asked while
   anonymous. It comes right after the link, prefilled from Google/Apple as today.
7. **Web helpers („Helferlink“).** A member shares a link to one list. A relative opens it in the
   browser and adds items without an account. The browser holds an anonymous session with a
   helper grant for that list only. A helper is never a household member and owns nothing.
8. **Web own-household start stays account-first in step one.** Safari wipes a site's script
   storage after 7 days without a visit, so an anonymous web list would vanish silently.
9. **Data loss is mitigated where we can and stated plainly where we cannot.** Sign-out becomes
   "create an account or delete the list"; a second device asks for the upgrade; the upgrade is
   offered at moments that pay off. Reinstall or a cleared browser loses an anonymous list, and
   the account step says so before the user chooses.
10. **Abuse.** Every guard reads `auth.users.is_anonymous` on the server. Anonymous users get one
    household, capped lists and items, capped feedback, and none of the credentials above. No
    captcha in step one (it would add a processor); a kill switch and a daily count instead.
11. **Purge.** A nightly job deletes anonymous users after 90 days without use (30 for helper-only,
    7 for neither), through today's `delete_account`.
12. **Legal.** No new processor. New processing: anonymous accounts, linking, the transfer code,
    helper links and grants, the purge. Redlines for the privacy policy are in section 11.

## 2. What exists today

| Area | Fact | Where |
| --- | --- | --- |
| Auth config | Anonymous sign-in off, manual linking off, 30 anonymous sign-ins per hour per IP, no captcha, `email_sent = 2` per hour | `supabase/config.toml:184,186,209,205,219-223` |
| Hosted auth config | Set by hand-run scripts that PATCH the Management API; none sets anonymous sign-in, linking or captcha | `supabase/deploy/auth_urls.ts:66-77`, `auth_mail.ts:60-84`, `scripts/configure-social-auth.mjs` |
| SDK | `signInAnonymously`, `linkIdentity` (redirect), `linkIdentityWithIdToken` (native), `updateUser`, `User.isAnonymous` exist in the locked versions | gotrue 2.27.3 `gotrue_client.dart:240,1162`, supabase_flutter 2.18.3 `supabase_auth.dart:440` |
| `is_anonymous` | No app, SQL or function code reads it; only the ops script for beta grants excludes anonymous users | `scripts/iap/beta-lifetime.ts:189` |
| Sessions | `SignedOut`, `NeedsHousehold`, `InHousehold`; no notion of account kind | `app/lib/session/session_cubit.dart:166-221` |
| Routing | Signed out goes to `/start`; the name step after consent; an invite goes to `/join/<code>` | `app/lib/shell/router.dart:353-417` |
| Guided start | Local-only draft (usage, who, household name, stores, items) until the account step; `setup` turns it into the household | `app/lib/onboarding/draft.dart:10-24`, `steps.dart:45,525` |
| Account step copy | „Konto erstellen“ / „Fast geschafft. Mit einem Konto speichern wir eure Liste, und du kannst jemanden einladen.“ | `app/l10n/app_de.arb:700-702` |
| Name step | `/your-name`, „Wie sollen wir dich nennen?“, flag `display-name` full | `app/lib/session/your_name.dart:59-70`, `app_de.arb:1585` |
| RLS | `is_household_member(household_id)` on every household table | CLAUDE.md, `supabase/tests/rls.test.sql` |
| RevenueCat | App User ID is the Supabase user id; `logIn` on user change | `app/lib/purchases/purchase_cubit.dart:100-104`, `revenuecat_repository.dart:41-55` |
| PostHog | Keyed to an install id, not the user | `app/lib/analytics/posthog_client.dart:69` |
| Display name | Defaults from metadata, else the email's local part; `''` without an email. Gaining an email re-derives it unless chosen | `supabase/migrations/20261022190526_provider_display_names.sql:5-17`, `20261117211652_display_name_chosen.sql:10-30` |
| Export | `account.email` from `auth.users`, null for an anonymous user | `supabase/migrations/20261122020000_trip_detection.sql:1809-1821` |
| Deletion | `delete_account(uuid)`, service only, through `F/account`; idempotent; cascades and triggers clean up | `supabase/migrations/20261122020000_trip_detection.sql:1719`, `docs/ACCOUNT_DELETION.md` |
| User purge | None. Nightly purge crons exist for other data (join requests, removals, tokens, feedback and more) | e.g. `20261108144412_households_join_approval.sql:106` |
| Web join page | Static page, „Im Browser beitreten“ opens the web app at `/?invite=<code>`, which asks to sign in | `app/web/join/join.js:24,141` |

## 3. The model

One user, one id, and a kind that only ever moves from anonymous to full:

```
AccountKind = anonymous | full          (auth.users.is_anonymous; flips once, on link)

Session (app):
  SignedOut
  NeedsHousehold(userId, account: AccountKind, requests)
  InHousehold(userId, account: AccountKind, household, households, requests)

Server facts (new):
  helper_links(id, household_id, list_id, label, code_hash, created_by, created_at,
               expires_at, revoked_at)
  helper_grants(id, household_id, link_id, user_id, first_used_at, last_used_at)
  account_transfers(code_hash, from_user, created_at)       -- one-time, 1 hour
  items.helper_link_id  -> helper_links on delete set null   -- the label on helper items
```

Invariants the build pins with pgTAP:

- An anonymous user is a member of at most one household, and every household with an anonymous
  member has exactly one member. (Anonymous users can neither invite nor join, so nobody else can
  get in.)
- A helper grant gives access to the open items of exactly one list, through `security definer`
  functions only. No RLS policy names helpers; `is_household_member` stays the only way into a
  household table.
- `helper_links` and `helper_grants` carry `household_id` (the grant's equals its link's, by a
  composite foreign key) and the RLS policy `is_household_member(household_id)` for members' reads,
  with the cross-household case in `rls.test.sql`, as CLAUDE.md asks of every household table.
  Helpers read neither table directly.
- `household_members` never holds a helper grant's user for that grant's household: a join
  (`accept_invite`, `join_household`) deletes the caller's grants for that household first.

Why the session carries `account` instead of a fourth session state: an anonymous user goes
through the same household states (needs one, has one), and every rule that differs is a guard on
a path. A separate `Anonymous` state would duplicate every `NeedsHousehold`/`InHousehold` rule in
`authRedirect`.

## 4. Flows

### 4.1 Anonymous start (iOS and Android)

1. The guided start runs as today up to the account step.
2. The account step shows the provider buttons as today, and under them a text button
   „Erst mal ohne Konto“ with one line under it (copy A2, A3).
3. Tap: `signInAnonymously()`. The session becomes `NeedsHousehold(account: anonymous)` and the
   router continues to `setup`, which creates the household from the draft, as for a sign-up. The
   analytics question is usually answered already (it is step 1 of the guided start); if not, the
   router asks it after the sign-in as it does today.
4. The name step is skipped while anonymous. The draft's invite step is skipped too (inviting
   needs an account); the user lands on the list.
5. Not shown when an invite or a `next` link is pending: those paths keep sign-up first.

Web: the button is not shown in step one (decision 8). The router allows anonymous sessions on the
web anyway, for helpers (4.7). Once anonymous sign-in is on in the hosted project, the server cannot
tell a web caller from an app: a hand-made call from a browser could still create the one household
an anonymous user may have. The caps and the purge hold for it; the web UI simply never offers it.

### 4.2 Upgrade („Konto erstellen“)

Route `/upgrade` (new constant in `router.dart`, carries `next`). One screen, the same provider
buttons as sign-in:

- **Google / Apple, native:** the provider's ID token, then `linkIdentityWithIdToken`. Apple's
  name comes along as today (`social_sign_in.dart:144-160`). Needs manual linking on.
- **Google / Apple, web:** `linkIdentity` (redirect). Needs manual linking on too.
- **Email:** `updateUser(email: …)`. Supabase sends a confirmation link; once opened (on any
  device), the account is full. The screen waits and refreshes the session on resume. A password
  can be set later under Konto, as today for magic-link users. Rate limit: hosted
  `email_sent` must allow this mail alongside sign-in mails (build job checks the hosted value).
  The app uses PKCE, which ties a code to the device that asked; the build must prove with an e2e
  case that the upgrade completes when the link is opened on another device (the change is
  server-side, so a session refresh on the first device should see it), or else change U8 to „auf
  diesem Gerät“.
  Abuse: each anonymous id could make Supabase mail an address of its choice and spend the
  project-wide `email_sent` budget that sign-in mails share. The upgrade screen therefore runs
  through `begin_email_upgrade()`, which counts attempts per user (3 a day) and in the daily total
  (section 6), before the app calls `updateUser`. The count is advisory for the app; the hard
  limit stays GoTrue's `email_sent`.

After a successful link the session is refreshed and `account` becomes `full`. The upgrade flow
then opens „Wie sollen wir dich nennen?“ (`/your-name?next=…`) itself, once, whatever `asksName`
would say: prefilled with the provider's name (Google, or Apple on its native flow), empty for an
email. „Ja, das bin ich“ saves it; „Jetzt nicht“ keeps the derived name, as for an email sign-up
today. Then `next` or the list. Nothing is copied: same user id, same household, same RevenueCat
id, same PostHog install id.

Why the flow opens it rather than `asksName`: after a native Apple link `_saveName` writes
`full_name`, the display-name trigger replaces `''` with it, `from_email` turns false, and
`asksName` (`app/lib/session/your_name.dart:59-70`) would skip the step. While anonymous, `''`
counts as `from_email`, so `asksName` itself gets the anonymous exception (false), not only
`authRedirect`. The trigger stays as it is (an email becomes the derived name until one is chosen,
as today). Router tests and a pgTAP case pin both.

### 4.3 Email or identity already taken

Supabase refuses the link (`email_exists`, `identity_already_exists`). The user then has two users:
the anonymous one on this device and an existing full one. Merge is ours to write:

1. Before signing in, the anonymous session calls `prepare_account_transfer()`. It returns a random
   code, stores its hash with `from_user`, valid 1 hour, one per user.
2. The app keeps the code in memory only and signs in to the existing account (any method).
3. The app asks „Liste „{household}“ in dein Konto übernehmen?“ (copy U7). Yes calls
   `claim_account_transfer(code)`, which only a full caller may call. It moves the anonymous user's
   single membership to the caller (role owner), then re-points every row that references the old
   user to the new one: the build derives the list from the foreign keys to `auth.users` (today
   e.g. `items.added_by`, history actors, `lists.created_by`, trip sessions and detected trips,
   claims, feedback, consent rows) and a pgTAP case asserts that no row references `from_user`
   before `delete_account` removes it. `is_default` stays with the receiver's existing default.
   Helper grants of the anonymous user move to the receiver too (`helper_grants.user_id`), unless the
   receiver is a member of that grant's household, in which case they are deleted (invariant in
   section 3). Idempotent: a second call with a used code answers `already_moved`. A receiver already at the
   20-household cap gets `too_many_households` and copy U7b; nothing moves and the code stays valid
   for its hour.
4. No ends the old anonymous user through `delete_account` at once.
5. If the app dies in between, the code expires; the anonymous user is unreachable and the purge
   removes it (section 8). The copy at U6 says to finish on this device.

The household cap (20) still applies to the receiving account.

### 4.4 Invites

- Signed out and opening an invite: unchanged, the sign-in screen first (`router.dart:356-363`).
- Anonymous and opening an invite: the router sends `/join/<code>` to `/upgrade?next=/join/<code>`
  with the copy U4. After the upgrade and the name step, the join runs as today. The user's own list
  stays as a second household; after joining, the joined household is shown (B3 holds).
- The server refuses `accept_invite`, `join_household`, `preview_invite` and `create_invite` for
  anonymous callers (section 6), so no old build or hand-made call can join an anonymous id.

### 4.5 Gated features

Any of these routes or actions for an anonymous user opens the gate sheet (copy U3) with
„Konto erstellen“ (to `/upgrade?next=<where they were>`) and „Abbrechen“:

invite a member (`invitePartnerPath`, `invitesPath`), join by code (`joinCodePath`,
`moreJoinPath`), a second household (`newHouseholdPath`), helper links, API keys and MCP tokens
(`accessPath`), the MCP/Alexa consent (`consentPath`), Siri setup, Premium purchase and restore
(`premiumPath` actions; the page itself may show), idea votes.

Allowed while anonymous: everything inside the own household (items, lists, stores, categories,
trips, history), dictation in the app, analytics choice, language, tips, feedback (capped),
content reports, data export, deleting the list. Feedback replies show in the app as today
(`20261115210000_fb4_feedback_replies.sql`) while the anonymous account exists; „Antwort per
E-Mail“ (`contact_ok`) is not offered, there is no address. A reply to an account that was deleted
or purged is lost, which the feedback form does not need to say twice (U2 covers it).
**Deviation from the brief:** the research lists feedback replies among the account-only features.
This design allows them while anonymous, because the reply lives in the same account as the note
and is lost only with it, and a gate would only stop people from telling us what is wrong. If
Peter or Legal want the research's rule, the build gates the replies list (not sending) behind the
upgrade: question 10.

### 4.6 Sign-out, reinstall, browser, second device

| Event | Own anonymous list | Mitigation in step one |
| --- | --- | --- |
| Sign-out | Lost for good | Sign-out for an anonymous user opens a dialog (copy U5): „Konto erstellen“ or „Liste löschen und abmelden“. The second runs `delete_account`, so nothing is orphaned. No plain sign-out. |
| Delete the app, reinstall | Lost (the session lives in app storage) | Said before the choice (A3) and on the Konto page (U2). Upgrade offered at payoff moments (4.8). The purge removes the orphan. |
| Clear browser storage | Not applicable to own lists in step one (web start off). A helper opens the link again and gets a new grant under a new anonymous user: the items added before stay on the list but can no longer be edited by them, and the browser counts again toward the 10-browser cap and in H10 until the old grant ages out after 30 days. Safari does this after 7 days without a visit, so a monthly helper on an iPhone meets it every time. | H6 says items can be changed only while this browser keeps its data; the cap is sized for it |
| Second device | Cannot reach it | Signing in on a second device needs an account; the Konto page says how (U2). |
| Phone lost | Lost | Same as reinstall. |

Considered and not in step one: keeping the refresh token in the iOS Keychain so it survives a
reinstall. It helps only iOS, adds device storage Legal must review, and a cleared Keychain still
loses the list. Revisit with data from the upgrade funnel.

### 4.7 Web helpers („Helferlink“)

For a relative who adds a few things now and then, in a browser, without an app or account.

**Member side (full account, any role):** under the invite sheet, „Helferlink teilen“. The member
picks the list (default: the open one) and types who it is for (label, e.g. „Oma Ruth“; 1-40
characters; optional, default „Helferlink“). The link `https://app.snacklist.app/h/<code>` goes out
through the share sheet like any invite link (N-18: user-shared, Snacklist sends nothing). Valid 30
days; any member sees the household's helper links under Mehr › Haushalt › Helferlinks, with label,
list, days left, the number of browsers using it, and „Beenden“.

**Helper side:** the link opens the web app at `/h/<code>`. Not claimed by the native apps, so it
stays in the browser (DEEP_LINKS.md gets the row).

1. No session: `signInAnonymously()`, then `claim_helper_link(code)` creates a grant for this
   browser. With a session (anonymous or full), the same call reuses it. `claim_helper_link` and the
   helper item functions read their own switch, `app_switch('helper_links')`: with it off, new grants
   are refused and existing ones read but cannot add. It is separate from `anonymous_start`, so
   either feature can be stopped without the other; the hosted toggle for anonymous sign-ins stops
   both.
2. The page shows the list name, the household name, the open items (name, amount, category; no
   prices, no member names, no history), and the add bar. One line above the bar (copy H6).
3. The helper adds items (classifier as usual) and can edit or delete the items they added while
   still open. Nothing else: no ticks, no claims, no other lists.
4. Updates: the page reads again on focus and every 15 s while visible. Helpers get no Realtime
   (Realtime needs an RLS select policy, which helpers do not have by design).
5. No analytics question and no PostHog on the helper page. Today the web app starts analytics at
   boot, before any route (`app/lib/main.dart:113`, `startAnalytics`), and without consent still asks
   PostHog for flags (privacy section 9). For `/h/*` the build skips that call: `main.dart` reads the
   start path, starts no PostHog client and no flag query, and the page uses every flag's default.
   A web test asserts no request to the PostHog host on `/h/<code>`.
6. „Meine Daten“ and „Löschen“ in the footer (copy H7): the export (`export_my_data`: the grants and
   the items this browser added) and the deletion of the helper's anonymous user (`F/account`,
   items stay with the list, `added_by` null). That is how a helper uses Art. 15, 17 and 20.
7. No name ask. Members see helper items as „über Helferlink „Oma Ruth““ (the label the member
   typed, read through `items.helper_link_id`), in the item details where „hinzugefügt von“ shows
   today. The label stays after the grant ends and goes when the link is deleted.
8. A full user who is a member of that household is sent to the list instead. A full user who is
   not gets the helper view; the grant does not appear in their household switcher.

**Ends:** the member ends the link (all grants end at once); the link expires; a grant is unused
for 30 days. An ended link shows copy H8. A browser that lost its storage opens the link again and
gets a new grant.

**Limits:** 10 browsers per link within 30 days, 50 adds per grant per day, 5 open helper links per
household. The code has 128 random bits and is stored hashed, so guessing is moot.

**Why not an invite variant:** a helper never becomes a member, so the rule „an invite must not
join under a throwaway anonymous id“ holds, and a helper owns nothing that can be lost. Their
items belong to the household; purging or deleting the helper's user sets `added_by` to null as
account deletion does today, and the label goes when the link is deleted (30 days after it ended).

**Path to an own list:** the helper page footer offers „Eigene Liste anlegen“, which opens the
upgrade (4.2) on the web. Linking keeps the same id, so the grant stays.

### 4.8 When the upgrade is offered

Besides the gates, a card in the list's tip slot (H2 budget: one hint a day). X hides it for 14
days, not for good as for other hints, because it is the only protection against losing the list:
after 10 items or the third active day, after the first trip, and on the Konto page always (copy
U1, U2). Never in the first session before the first item.

## 5. App changes (for the build job)

- `Session`: `NeedsHousehold` and `InHousehold` get `AccountKind account`, read from
  `User.isAnonymous` on every auth change (link fires `userUpdated`).
- `authRedirect` (only place for gating, CLAUDE.md):
  - `askName` is false while anonymous.
  - Anonymous plus invite goes to `/upgrade?next=/join/<code>`.
  - Anonymous on a gated path (4.5) goes to `/upgrade?next=<path>`.
  - `/h/*` is never redirected, for any session but `SessionLoading`.
  - On the web, an anonymous session anywhere but `/h/*`, `/upgrade` and the upgrade's own
    `/your-name` goes to the last helper link this browser opened (kept in `DeviceCache` as
    `helper.last_link`), else to `/upgrade`. This rule comes before the consent, name and
    `NeedsHousehold → /welcome` rules (`router.dart:386-389`), so a helper who opens
    `app.snacklist.app/` or taps the logo gets neither the own-household start (decision 8) nor
    the analytics question and PostHog (P9). Router tests: anonymous web session at `/`,
    `/welcome`, `/analytics-consent`, `/more`, with and without a stored helper link; the same
    session in the apps is unaffected.
  - `/upgrade` for a full user goes on to `next` or the list.
- Account step: the second button; onboarding skips `invite` for anonymous.
- Sign-out (More, Konto, welcome, waiting, consent, onboarding frame): the dialog when anonymous.
- Konto page: anonymous state (U2), „Konto erstellen“, export, „Liste löschen“.
- Purchases: Buy and Restore hidden behind the gate sheet; `note_revenuecat_customer` is refused.
- OAuth consent screen: anonymous users get the gate sheet, not the approve button.
- Helper page `/h/<code>`: its own scaffold (list and add bar only), no tabs, no switcher.
- Analytics (`eventCatalog`, `docs/ANALYTICS.md`, no text): `anonymous_started`,
  `account_upgraded {method: email|google|apple, days_anonymous: bucket}`,
  `account_transfer {result: moved|discarded}`, `upgrade_prompt {trigger, action}`,
  `helper_link_created`, `helper_link_ended`. The helper page sends none.
- Flags (`releases/flags.json`, added in the build): `anonymous-start` (app button), `helper-links`
  (member sheet). Both off until Legal's GO and Peter's call.

## 6. Server changes (for the build job)

One helper, read from the database because the column flips at link time and OAuth or PAT calls
carry no fresh claim:

```sql
create function public.caller_is_anonymous() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select u.is_anonymous from auth.users u where u.id = auth.uid()), false)
$$;
```

Refusals raise `account_required` (errcode `42501`), in the style of `session_required`.

| Surface | Today (current definition) | Change |
| --- | --- | --- |
| `create_invite` (both) | Any member, `20261108133253_households_invite_loop.sql:110,160` | Refuse anonymous |
| `accept_invite` (every overload: `(text)`, `(text,bool)`, `(text,text)`), `join_household`, `preview_invite` | `20261031123504_household_bound_lifetime.sql:613` (`(text)`), `20261115130000_checks_before_locks.sql:776,794`, `20261109174625_households_join_cap.sql:127`, `20261108125048_households_multi.sql:450` | Refuse anonymous. Closes the invite-guess hole: `invite_attempts` limits 10 per user per hour, which fresh anonymous ids would multiply |
| `refuse_household_over_cap` trigger | 20 per user (`household_cap()`, `20261111214106_household_cap_twenty.sql:8`; trigger `:11`) | 1 for anonymous users, on members and join requests. The kill switch lives here too: with `app_switch('anonymous_start')` off, any membership insert for an anonymous user is refused, so it covers every way in |
| `create_household` (every overload: `(uuid,text,bool,text[],text)` and the old `(text,bool,text[])`) | `20261111214106_household_cap_twenty.sql:30`, `20261108125048_households_multi.sql:164` | Covered by the trigger (cap and kill switch) in both overloads; the old one is otherwise capped at 1 by `already_in_household` |
| `create_list` | Any member | 3 lists per anonymous household |
| `stores`, `categories` (also `add_store`, `create_category`) | Any member, no cap. Both tables take direct inserts: RLS `stores_member` / `categories_member` `for all to authenticated` (`20261022150000_foundation.sql:410,412`), and insert is not revoked (`:438`), so a client can `POST /rest/v1/stores` without going through the functions | 20 stores and 40 categories per anonymous household (the seeds count), enforced in new `before insert` triggers on the tables, as for items, so the functions and direct inserts are both capped. `store_category_order` (also `for all`) needs no cap of its own: its primary key `(store_id, category_id)` (`foundation.sql:98`) bounds it by the two caps. `lists` has only a select policy, so `create_list` is its only way in |
| Items | `items_member` RLS | 1,000 item rows per anonymous household, in the items insert trigger. Every row counts, open or ticked (ticked rows stay for „Zuletzt verwendet“ and history); a daily cook adding 10 items a day stays under it for the 90-day window |
| `create_personal_access_token` (1 and 2 args), `create_api_token` (2 and 3 args), `create_siri_credential` | Need a session only: `20261122160000_pat_session_required.sql:16` (PAT, 2 args; the 1-arg form delegates, `20261108125048_households_multi.sql:593`), `20261115100000_key_checks_without_waiting.sql:216` (API key, 3 args; the 2-arg wrapper is `households_multi.sql:649`), `20261108125048_households_multi.sql:667-675` (Siri) | Refuse anonymous in every overload |
| `note_revenuecat_customer`, `F/purchases` `/claim` | `20261112232617_per_user_premium.sql:46`, `F/purchases/handler.ts:275` | Refuse anonymous |
| OAuth (MCP, Alexa) | GoTrue's consent; `F/_shared/auth.ts:124` accepts it | `authenticate` refuses `via = 'oauth'` when the user is anonymous (one lookup); the app hides approve |
| `feedback` insert | No limit, `20261108125048_households_multi.sql:790` | 3 per day for anonymous users, `contact_ok` forced false |
| `vote_feedback_idea` | One per household, `20261115210000_fb4_feedback_replies.sql:140` | Refuse anonymous |
| Feedback screenshots | Per-user quota | Refuse anonymous inside `feedback_screenshot_quota_left` (returns false), which the storage insert policy `feedback_screenshots_insert_own` calls (`20261115160000_feedback_screenshots.sql:43-49`), so the refusal holds for direct storage uploads too, not only in the app |
| `export_my_data` | `email` null, `20261122020000_trip_detection.sql:1812` | Add `account.anonymous` (bool) and the user's helper links and grants |
| `delete_account`, `F/account` | Service only, session JWT | Unchanged; anonymous users use it for „Liste löschen“ |
| Content reports, `F/report` `/report/app` | `APP_LIMITS = { perUserHour: 5, perHour: 200 }` and a confirmation mail to any address in the body (`supabase/functions/report/handler.ts:58,289-299`). Fresh anonymous ids would give 150 reports an hour per IP, nearly the global 200, and mail to addresses of the sender's choice | Reports stay open to anonymous users (DSA Art. 16), with three changes for them: `email` is dropped server-side (the app hides the field; no confirmation mail), their own global bucket of 20 an hour (`anonPerHour`) so the 200 for everyone else cannot be used up by them, and 2 per user an hour. The form says that a confirmation by email comes with the web form (`/inhalte-melden`), which keeps its own limits. Function tests for each; Legal question 10 |
| New: `prepare_account_transfer`, `claim_account_transfer` | none | 4.3 |
| New: `begin_email_upgrade` | none | 4.2: 3 email upgrade attempts per anonymous user a day, counted in the daily total |
| New: `create_helper_link`, `end_helper_link`, `household_helper_links`, `claim_helper_link`, `helper_list`, `helper_put_item`, `helper_delete_item` | none | 4.7; all `security definer`, membership or grant checked inside; full accounts only for the member functions |
| Config | `config.toml:184,186` | Local on in the build; hosted through a new converging script beside `auth_urls.ts`, run after Legal's GO |

pgTAP (in `supabase/tests/`): direct-insert cases for every table an anonymous member can write
(`items`, `stores`, `categories`, `store_category_order`) prove the caps hold without the functions;
a case reads `pg_policies` and fails on any `for all` or `for insert` policy for `authenticated` on a
table without such a cap trigger, so a later table cannot reopen the hole. A case walks `pg_proc` for every function name in the table, so no
older overload is left unguarded (old store builds still call them). It also lists, by name, the
functions judged harmless for anonymous callers, so an omission is explicit, not accidental:
`preview_invite_public` (anon and authenticated, with its own per-IP limit), `unarchive_household`,
`decide_join_request`, `set_join_approval`, `set_member_role`, `remove_member`, `revoke_invite`,
`cancel_join_request`, `record_oauth_device`, `leave_household`, `leave_current_household`,
`move_list` and the household-scoped item, list, store and trip writers (an anonymous user can only
ever reach their own single-member household). A function callable by `authenticated` that is in
neither list fails the case. For every row above, an anonymous caller is refused or capped and a
full caller is not; the single-member invariant; a helper reads only the grant's list and none of
the household tables directly; a helper cannot see another household's lists; ending a link ends
every grant; the transfer moves membership, `added_by` and history and is idempotent; the purge
(section 8) deletes exactly the stale users. The RLS cross-household case for each new table.

Abuse arithmetic with the caps: 30 anonymous users per hour per IP (the local `config.toml:209`;
no script sets the hosted value today, so the converging script in AN1-7 reads and sets it) is at
most 720 households a day per IP, each at most 1,000 items. A per-IP limit is weak against someone
with many addresses (an IPv6 range), which is why the per-user caps matter more than the rate. That
is a nuisance, not a takeover; the kill switch (`app_switch` plus the hosted toggle) and a daily
count of new anonymous users are the response. The count runs as its own step in the `ops`
environment with the service key, not in the public `health` function that `keepalive.yml` calls,
and warns above 300 a day. Captcha (Turnstile or hCaptcha) would add a processor and a
widget on every sign-in, so it waits for evidence (Legal question 6).

## 7. Copy (proposed, DE and EN)

Keys are proposals for the build job; nothing is added to the ARB files now.

| Id | Where | DE | EN |
| --- | --- | --- | --- |
| A2 | Account step, second button | Erst mal ohne Konto | Continue without an account |
| A3 | Under A2 | Ohne Konto erreichst du deine Liste nur auf diesem Gerät. Löschst du die App oder meldest dich ab, ist sie weg. | Without an account, your list is only on this device. If you delete the app or sign out, it is gone. |
| U1 | List card | **Liste sichern** Mit einem Konto geht deine Liste nicht verloren, und du kannst jemanden einladen. [Konto erstellen] [Später] | **Keep your list** With an account your list can't get lost, and you can invite someone. [Create account] [Later] |
| U2 | Konto page | Du nutzt Snacklist ohne Konto. Deine Liste ist nur auf diesem Gerät. Mit einem Konto nutzt du sie auch auf anderen Geräten. | You're using Snacklist without an account. Your list is only on this device. With an account you can use it on other devices too. |
| U3 | Gate sheet | **Dafür brauchst du ein Konto** Einladen, Siri, Alexa, KI-Assistenten und Premium gibt es nur mit Konto. Deine Liste bleibt, wie sie ist. [Konto erstellen] [Abbrechen] | **You need an account for this** Inviting, Siri, Alexa, AI assistants and Premium need an account. Your list stays as it is. [Create account] [Cancel] |
| U4 | Invite while anonymous | **Zum Beitreten brauchst du ein Konto** Deine eigene Liste bleibt. Nach dem Beitritt wechselst du oben zwischen beiden Haushalten. | **You need an account to join** Your own list stays. After joining, switch between both households at the top. |
| U5 | Sign-out, anonymous | **Ohne Konto abmelden?** Deine Liste ist dann für immer weg. Erstelle vorher ein Konto, um sie zu behalten. [Konto erstellen] [Liste löschen und abmelden] | **Sign out without an account?** Your list will be gone for good. Create an account first to keep it. [Create account] [Delete list and sign out] |
| U6 | Upgrade, email taken | **Zu dieser Adresse gibt es schon ein Konto** Melde dich dort an. Danach übernehmen wir deine Liste in dieses Konto. Bleib dafür auf diesem Gerät. | **This address already has an account** Sign in to it. We'll then move your list into that account. Stay on this device for it. |
| U6b | Upgrade, Google or Apple account taken | **Dieses Google-Konto nutzt du schon für Snacklist** Melde dich damit an. Danach übernehmen wir deine Liste in dieses Konto. Bleib dafür auf diesem Gerät. (Apple: „Diese Apple-ID …“) | **You already use this Google account for Snacklist** Sign in with it. We'll then move your list into that account. Stay on this device for it. (Apple: "This Apple Account …") |
| U7 | After sign-in | Liste „{household}“ in dein Konto übernehmen? [Übernehmen] [Verwerfen] | Move the list "{household}" into your account? [Move] [Discard] |
| U7b | Transfer, receiver at the cap | Du bist schon in 20 Haushalten. Verlass zuerst einen, dann übernehmen wir die Liste. | You're already in 20 households. Leave one first, then we'll move the list. |
| U8 | Upgrade, email sent | Wir haben dir einen Link an {email} geschickt. Sobald du ihn öffnest, ist dein Konto fertig. | We sent a link to {email}. Once you open it, your account is ready. |
| C1 | Cap hit, items, lists, stores or categories (anonymous) | **Mehr geht nur mit Konto** Ohne Konto hat deine Liste Platz für {limit}. Mit einem Konto gibt es keine solche Grenze. [Konto erstellen] [OK] | **More needs an account** Without an account your list has room for {limit}. With an account there is no such limit. [Create account] [OK] |
| C1 limits | `{limit}` per cap | 1.000 Einträge · 3 Listen · 20 Läden · 40 Kategorien | 1,000 items · 3 lists · 20 stores · 40 categories |
| C2 | Cap hit, feedback (anonymous) | Heute kannst du ohne Konto keine weitere Rückmeldung schicken. Morgen wieder, oder jetzt mit Konto. | You can't send more feedback today without an account. Try again tomorrow, or create an account now. |
| C3 | Cap hit, email upgrade attempts | Heute haben wir schon dreimal einen Link geschickt. Versuch es morgen wieder oder nimm Google oder Apple. | We've already sent a link three times today. Try again tomorrow, or use Google or Apple. |
| C4 | Helper, 50 adds a day | Für heute ist hier genug eingetragen. Morgen geht es weiter. | That's enough for today. You can add more tomorrow. |
| H1 | Invite sheet entry | Helferlink teilen | Share a helper link |
| H2 | Helper link sheet | **Jemand schreibt nur ab und zu was dazu?** Mit einem Helferlink sieht jemand den Namen eures Haushalts und die offenen Einträge dieser Liste und kann im Browser etwas hinzufügen, ohne Konto und ohne Mitglied zu werden. Der Link gilt 30 Tage. | **Someone just adds things now and then?** With a helper link, someone sees your household's name and the open items on this list and can add to it in the browser, without an account and without becoming a member. The link works for 30 days. |
| H3 | Label field | Für wen ist der Link? | Who is the link for? |
| H4 | Label hint (below the field) | z. B. Oma Ruth | e.g. Grandma Ruth |
| H5 | Share text | Schreib einfach dazu, was wir mitbringen sollen: {url} | Just add what we should pick up: {url} |
| H6 | Helper page, above the add bar | Was du hier einträgst, sehen alle im Haushalt sofort. Ändern kannst du es, solange du diesen Browser nutzt und er seine Daten behält. | Everyone in the household sees what you add right away. You can change it as long as you use this browser and it keeps its data. |
| H7 | Helper page footer | Ohne Konto · Datenschutz · Meine Daten · Löschen · Eigene Liste anlegen | No account · Privacy · My data · Delete · Start your own list |
| H8 | Ended link | Dieser Helferlink gilt nicht mehr. Frag nach einem neuen. | This helper link no longer works. Ask for a new one. |
| H9 | Item details, members | über Helferlink „{label}“ | via helper link "{label}" |
| H10 | Helper links list | Helferlinks · noch {days} Tage · {count} Browser · [Beenden] | Helper links · {days} days left · {count} browsers · [End] |

U3 names Alexa and AI assistants generically; no brand outside functional help (brand-names lint).
The name step's copy (`yourName*`) is reused unchanged. A refused item op reaches the user through
today's `RejectedOp` notice (`app/lib/list/list_repository.dart:211-219`), which shows C1 for the
cap answer instead of a generic error; nothing retries in a loop.

## 8. Purge and retention

Nightly `purge-anonymous-users` (pg_cron, 03:57 UTC, at most 500 users a run), calling
`delete_account(id)` for users with `is_anonymous` and last use older than:

| User | Deleted after | Last use |
| --- | --- | --- |
| Anonymous with a household | 90 days | latest of sign-in, session refresh (`auth.sessions`), and an item write by the user |
| Anonymous with only helper grants | 30 days | latest grant use |
| Anonymous with neither | 7 days | creation |

Also nightly: grants unused for 30 days, links 30 days after they ended or expired, transfer codes
after 1 hour. `delete_account` already runs the cascades, the RevenueCat queue (no anonymous user
is ever a customer) and the screenshot sweep. The build checks which `auth.sessions` column moves on
refresh on the hosted GoTrue version, and pins the selection in pgTAP.

An anonymous user cannot be told before the purge (no address). The app shows the 90-day rule on
the Konto page only implicitly (U2); Legal question 3 asks whether it must be explicit.

## 9. Stores

- Apple 5.1.1(v): account deletion is offered to every account, anonymous ones included
  („Liste löschen“). Apple's App Privacy answers do not change (no new data types).
- Google Play data safety: the account-creation answer becomes "optional"; the deletion URL page
  (`konto-loeschen.html`) gets one paragraph for use without an account (redline R9).
- Store listings and review notes: "use without an account" may be mentioned only after the flag is
  on for everyone.

## 10. Build sequence (after Legal's GO)

| Job | Scope | Proof |
| --- | --- | --- |
| AN1-1 | Server guards, caps, `caller_is_anonymous`, kill switch, local config on | pgTAP matrix of section 6 |
| AN1-2 | Session `account`, `authRedirect` rules, account step, gate sheet, sign-out dialog, Konto page, flag `anonymous-start` | router and widget tests; verify-family-groceries drive on Android and Linux |
| AN1-3 | Upgrade (email, Google, Apple), name step after link, list card | e2e (web build with the flag forced for tests), Marionette drive |
| AN1-4 | Transfer for taken emails and identities | pgTAP, e2e |
| AN1-5 | Purge, export fields, keepalive count | pgTAP with stale fixtures |
| AN1-6 | Helper links: server, member sheet, `/h/<code>` page, flag `helper-links` | pgTAP, two-browser e2e (member and helper) |
| AN1-7 | Hosted config script, privacy text apply, store forms, feature map and FEATURES-FOR-WRITERS | smoke on production with the flag off for users |

Size: 6-10 jobs, as the research estimated.

## 11. Legal

### 11.1 New processing

| # | What | Data | Who sees it | Kept | Proposed basis |
| --- | --- | --- | --- | --- | --- |
| P1 | Anonymous account | random user id, creation time, last sign-in and session refresh times, the session on the device, the household and list data as for any account; per session, Supabase Auth keeps the IP address and the user agent (`auth.sessions`, GoTrue's schema; the build confirms the columns) until the session ends or the account goes; Supabase auth logs with IP (as today, at most 1 day) | the user | until upgrade, deletion or purge (section 8) | Art. 6 Abs. 1 lit. b |
| P2 | Linking an email or Google/Apple | the email or provider identity added to the same account; a confirmation email through Supabase and Resend. Manual linking is a project-wide switch: from then on a full account could also link a further identity through the API (the app offers no such screen) | the user | as any account | Art. 6 Abs. 1 lit. b |
| P3 | Transfer code | hash of a one-time code, the anonymous user id, time | nobody | 1 hour, or until used | Art. 6 Abs. 1 lit. b |
| P4 | Helper link | household, list, label typed by the member (may be a first name or a relation), creator, created, expiry, end | all members of the household | until 30 days after it ended or expired, or with the household | Art. 6 Abs. 1 lit. b (members); question 1 for the person named |
| P5 | Helper grant | anonymous user id of the helper's browser, link, first and last use; the session's IP address and user agent at Supabase Auth (as P1); items the helper added (as any item, with the link) | members see the count per link and the label on items; the helper sees the open items of that list | grant: 30 days after last use; items: like any item | Art. 6 Abs. 1 lit. f (question 1) |
| P6 | Purge | deletion of anonymous users by inactivity | nobody | not applicable | Art. 5 Abs. 1 lit. e, Art. 17 |
| P7 | Caps and counts | counts per user, household and grant; GoTrue's per-IP limit on anonymous sign-ins (Supabase's, as for sign-ins today); a daily total of new anonymous users for us | nobody | not stored beyond the rows themselves | Art. 6 Abs. 1 lit. f |
| P8 | Device storage | anonymous session; on the helper page, the session and the link | the device | until sign-out, deletion, or the browser clears it | § 25 Abs. 2 Nr. 2 TDDDG |
| P9 | No PostHog on the helper page | the helper page starts no PostHog client and asks no flags, unlike the rest of the web app without consent (section 9) | not applicable | not applicable | not applicable |

No new processor or recipient. Supabase (auth, database), Resend (the confirmation email) and
Vercel (the web app) are used as today. No captcha provider in step one.

### 11.2 Proposed redlines (privacy policy, `site/content/legal/datenschutz.md`; `privacy.md` follows)

Not applied. To go in with AN1-7 as one PR after Legal's GO and the build. The section numbers are
today's.

- **R0, section 3 (Web-App), the onboarding bullet** („… mit der Registrierung werden daraus dein
  Haushalt und deine Liste …“): „mit der Registrierung oder, in der App, wenn du ohne Konto
  weitermachst, werden daraus dein Haushalt und deine Liste, und die Kopie auf dem Gerät wird
  gelöscht.“
- **R1, section 3 (Web-App), device storage list, new bullet after „deine Anmeldesitzung“:**
  „wenn du einen Helferlink öffnest: eine Sitzung ohne Konto und den Link, damit du die Liste beim
  nächsten Mal wieder siehst,“
- **R2, section 4 (Konto und Anmeldung), new paragraph at the start:**
  „In der App kannst du Snacklist zuerst ohne Konto nutzen. Wir legen dann ein Konto ohne
  E-Mail-Adresse an, das nur eine zufällige Kennung hat und nur von diesem Gerät aus erreichbar ist.
  Meldest du dich ab, löschst du die App oder verlierst du das Gerät, können wir es dir nicht
  wiederherstellen. Erstellst du später ein Konto mit E-Mail-Adresse, Google oder Apple, bleibt es
  dasselbe Konto mit denselben Daten. Gibt es zu deiner Adresse schon ein Konto, übernehmen wir
  deine Liste auf deinen Wunsch in dieses Konto und löschen das Konto ohne E-Mail-Adresse; dafür
  speichern wir eine Stunde lang einen einmaligen Code. Zu jeder Anmeldesitzung, auch ohne
  E-Mail-Adresse, speichert unser Dienstleister Supabase die IP-Adresse und die Browser- bzw.
  Gerätekennung (User-Agent), bis die Sitzung endet oder das Konto gelöscht wird. Ein Konto ohne
  E-Mail-Adresse löschen wir mit allen Daten, wenn es 90 Tage nicht genutzt wurde.“
- **R3, section 4, last sentence:** „Für Anmeldelinks und Bestätigungen“ → „Für Anmeldelinks,
  Bestätigungen und das Bestätigen deiner Adresse, wenn du ein Konto ohne E-Mail-Adresse
  sicherst,“
- **R4, section 5, new subsection after „Rollen und Einladungen“, „Helferlinks“ {#helferlinks}:**
  „Mitglieder können einen Helferlink zu einer Liste teilen. Wer ihn öffnet, sieht im Browser die
  offenen Einträge dieser Liste (Name, Menge, Kategorie), den Namen der Liste und des Haushalts,
  und kann Einträge hinzufügen und eigene noch offene Einträge ändern oder löschen, ohne Konto und
  ohne Mitglied zu werden. Wir speichern zum Link den Haushalt, die Liste, wer ihn erstellt hat,
  eine Bezeichnung, die das Mitglied eingibt (zum Beispiel „Oma Ruth“), und wann er abläuft oder
  beendet wurde; für jeden Browser, der ihn nutzt, eine zufällige Kennung und wann er ihn zuerst und
  zuletzt genutzt hat, und, wie bei jeder Anmeldesitzung, dessen IP-Adresse und User-Agent
  (Abschnitt 4). Alle Mitglieder sehen die Links, ihre Bezeichnung, wie viele Browser sie
  nutzen, und bei Einträgen, die über einen Link kamen, dessen Bezeichnung. Ein Link gilt 30 Tage
  und endet früher, wenn ein Mitglied ihn beendet. Die Kennung eines Browsers löschen wir, wenn er
  den Link 30 Tage nicht genutzt hat, den Link mit seiner Bezeichnung 30 Tage nach seinem Ende.
  Einträge, die über den Link kamen, gehören zur Liste wie alle anderen; öffnest du den Link in
  einem anderen Browser oder hat dein Browser seine Daten gelöscht, kannst du frühere Einträge nicht
  mehr ändern. Über „Meine Daten“ und „Löschen“ auf der Helferseite erhältst du deine Daten oder
  löschst die Kennung deines Browsers; deine Einträge bleiben dann ohne Bezug zu dir auf der Liste.
  Snacklist verschickt keine Helferlinks; ihr teilt sie selbst. Die Helferseite fragt nicht nach
  Nutzungsdaten, sendet nichts an PostHog und fragt dort auch nicht ab, welche Funktionen
  eingeschaltet sind.
  Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO für die Mitglieder; für die Person, die den Link nutzt
  oder in der Bezeichnung genannt ist, unser berechtigtes Interesse, Haushalten das gemeinsame
  Einkaufen mit Helfenden zu ermöglichen (Art. 6 Abs. 1 lit. f DSGVO).“
- **R5, section 5, „Rollen und Einladungen“:** add „Ohne Konto kannst du nicht einladen und keinem
  Haushalt beitreten.“
- **R6, section 7 (Siri, Alexa, KI-Assistenten), first paragraph:** add „Dafür brauchst du ein Konto
  mit E-Mail-Adresse, Google oder Apple.“
- **R7, section 8 (Export und Löschen):** add to the export list „ob dein Konto ohne
  E-Mail-Adresse ist, deine Helferlinks und die Helferlinks, die dein Browser genutzt hat“; add
  „Auch ohne Konto kannst du unter Konto › Liste löschen alles sofort löschen.“
- **R8, section 14 (Speicherdauer), after the first sentence:** „Ein Konto ohne E-Mail-Adresse
  löschen wir mit allen Daten nach 90 Tagen ohne Nutzung, eines, das nur Helferlinks genutzt hat,
  nach 30 Tagen, eines ohne Haushalt und ohne Helferlink nach 7 Tagen. Den einmaligen Code zur
  Übernahme einer Liste löschen wir nach einer Stunde.“ And in the household sentence: „Mit einem
  Haushalt löschen wir auch seine Listen, Einladungen, Helferlinks, …“
- **R9, `konto-loeschen.html`:** a paragraph: „Ohne Konto: Unter Mehr › Konto › Liste löschen
  löschst du deine Liste und das Konto ohne E-Mail-Adresse sofort. Nutzt du es 90 Tage nicht,
  löschen wir es selbst.“
- **R10, section 17 (Mindestalter):** unchanged text; question 5.
- **R11, `datenschutz-kaeufe.md` / purchases page:** add „Käufe und Wiederherstellen gehen nur mit
  Konto.“
- **R12, section 16 (Pflicht zur Bereitstellung):** „Ohne E-Mail-Adresse oder Google-/Apple-Anmeldung
  kannst du kein Konto anlegen“ → „In der App kannst du Snacklist ohne E-Mail-Adresse nutzen
  (Abschnitt 4). Um einzuladen, beizutreten, Siri, Alexa, KI-Assistenten oder die Schnittstelle zu
  verbinden, Premium zu kaufen oder Snacklist auf einem weiteren Gerät zu nutzen, brauchst du ein
  Konto mit E-Mail-Adresse oder Google-/Apple-Anmeldung. Einen Helferlink nutzt du ohne Konto.“

The analytics consent text (version 2026-11-18) does not change: anonymous users are asked the same
question as today (usually step 1 of the guided start, else after the sign-in), and the helper page asks nothing and sends nothing (P9; a
build requirement with its own test, section 4.7).

### 11.3 Questions for Legal

1. **Helpers and the label.** The helper has no contract with us and the label may name a third
   person („Oma Ruth“). Is lit. f right for both, with the R4 wording? Does the helper page need its
   own short notice beyond the „Datenschutz“ link in H7?
2. **Anonymous accounts as a contract.** Is lit. b right for an account without an email, given that
   we cannot reach the person?
3. **Purge notice.** 90 days without use, then deletion with no warning possible. Is R2 and R8
   enough, or must the Konto page state the 90 days (proposed extra line for U2: „Ohne Nutzung
   löschen wir sie nach 90 Tagen.“ / "Unused, we delete it after 90 days.")?
4. **Transfer.** Moving an anonymous household into an existing account after the user confirms
   (U7). Any concern beyond R2?
5. **Age.** Snacklist is 16+ (section 17) and no screen asks for the age today. Does anonymous use,
   which skips even the email, change that?
6. **Captcha.** If abuse appears, Turnstile or hCaptcha would add a processor and a transfer
   question. Pre-clear one now, or decide when needed?
7. **Rights without an account.** This design gives export and deletion to anonymous users (Konto
   page) and to helpers („Meine Daten“, „Löschen“ on the helper page). A helper who lost the browser
   session can no longer be identified as the author of earlier items. Is that acceptable, or must a
   request by other means (support mail with the link) be answered for them?
8. **Store copy.** Any constraint on saying "ohne Konto" in the store listing once live?
9. **Session IP and user agent.** Supabase Auth keeps them per session for every account today, and
   the privacy policy does not name them. R2 and R4 add them for anonymous users and helpers. Should
   section 4 say it for all accounts in the same PR?
10. **Deviations to confirm (Legal and Peter).** (a) Anonymous users may send feedback and read
    in-app replies, though the research lists replies as account-only (4.5). (b) Anonymous app
    reports get no confirmation mail and their own small limit; N-241 says every app report with
    an address is confirmed, and these carry none (section 6). Keep both, or gate them?

### 11.4 What Legal's GO covers

This file (sha256 in NEEDS_LEAD, job 375). A GO covers: the design's processing (11.1), the redlines
R0-R12 as the basis for the final text, and the copy in section 7 as drafts. The final privacy text
and ARB strings come back for a hash GO in AN1-7.

## 12. Decisions taken here (also in docs/DECISIONS.md, job 375)

1. Web own-household anonymous start is out of step one (Safari's 7-day script-storage cap);
   helpers are in.
2. Helpers get a per-list grant through `security definer` functions, never membership, never an RLS
   path; no Realtime for them.
3. Guards read `auth.users.is_anonymous`, not the JWT claim.
4. Anonymous users may export and delete; they may not invite, join, mint credentials, consent to
   OAuth, buy, restore or vote.
5. No captcha in step one; caps, kill switch and a daily count instead.
6. Purge windows 90 / 30 / 7 days (Legal question 3 may change the first).
7. No Keychain persistence in step one.
8. The display-name trigger stays; the name step right after the link covers it.
9. Helpers export and delete from the helper page; the helper page starts no PostHog client and no
   flag query.
10. Transfers re-point every row keyed to the anonymous user, derived from the foreign keys, before
    deleting it.
11. Anonymous users may send feedback (3 a day) and read in-app replies; no reply by email. This
    deviates from the research's account-only list; Legal question 10.
12. Anonymous content reports: no email, own bucket of 20 an hour, 2 per user an hour.
13. The kill switch sits in the household cap trigger, so it covers every `create_household`
    overload and every join. Helpers have their own switch, `helper_links`.
14. On the web, an anonymous session outside `/h/*` and the upgrade goes to the last helper link,
    else `/upgrade`.
15. Store and category caps are table triggers, not function checks, because members may insert
    into both tables directly (review 1).
