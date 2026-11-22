# AN1: anonymous start, step one (design and Legal draft)

Status: DRAFT for Legal (job 375, 2026-11-22). Nothing here is built. Anonymous sign-in and manual
linking stay off, no flag changes, no live page changes. A later job builds this after Legal's hash
GO on this file. Legal's review of 22 Nov 2026 (GO with conditions, N-370 to N-395) is applied in
place and listed in section 13 (job 396). Facts about today's code carry file:line references as of main `688a9023d`.

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
    captcha in step one (it would add a processor; a future one needs its own Legal GO, Q6); a kill
    switch and a daily count instead.
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
4. „Liste löschen“ (was „Verwerfen“, N-390) ends the old anonymous user through `delete_account` at
   once, after a confirmation line (U7). Two more conditions from Legal (Q4): the one-time transfer
   code is never logged (not by the app, the database or a function), and `claim_account_transfer`
   is rate-limited (section 6).
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
or purged is lost. The feedback form says so below the message box for anonymous users (copy F1,
N-389): replies appear only in the app while the anonymous account exists. U2 does not cover
feedback.
**Deviation from the brief:** the research lists feedback replies among the account-only features.
This design allows them while anonymous, because the reply lives in the same account as the note
and is lost only with it, and a gate would only stop people from telling us what is wrong. If
Peter or Legal want the research's rule, the build gates the replies list (not sending) behind the
upgrade: question 10 (Legal decided Q10a: GO, with F1).

### 4.6 Sign-out, reinstall, browser, second device

| Event | Own anonymous list | Mitigation in step one |
| --- | --- | --- |
| Sign-out | Lost for good | Sign-out for an anonymous user opens a dialog (copy U5): „Konto erstellen“ or „Liste und Konto löschen“. The second runs `delete_account`, so nothing is orphaned. No plain sign-out. |
| Delete the app, reinstall | Lost (the session lives in app storage) | Said before the choice (A3) and on the Konto page (U2). Upgrade offered at payoff moments (4.8). The purge removes the orphan. |
| Clear browser storage | Not applicable to own lists in step one (web start off). A helper opens the link again and gets a new grant under a new anonymous user: the items added before stay on the list but can no longer be edited by them, and the browser counts again toward the 10-browser cap and in H10 until the old grant ages out after 30 days. Safari does this after 7 days without a visit, so a monthly helper on an iPhone meets it every time. | H6 says items can be changed only while this browser keeps its data; the cap is sized for it |
| Second device | Cannot reach it | Signing in on a second device needs an account; the Konto page says how (U2). |
| Phone lost | Lost | Same as reinstall. |

Considered and not in step one: keeping the refresh token in the iOS Keychain so it survives a
reinstall. It helps only iOS, adds device storage Legal must review, and a cleared Keychain still
loses the list. Revisit with data from the upgrade funnel.

### 4.7 Web helpers („Helferlink“)

For a relative who adds a few things now and then, in a browser, without an app or account.

**Member side (full account; with `join_approval` on, only owners and admins create a link):** under
the invite sheet, „Helferlink teilen“. The member picks the list (default: the open one) and types who it is for (label, e.g. „Oma Ruth“; 1-40
characters; optional, default „Helferlink“). The link `https://app.snacklist.app/h/<code>` goes out
through the share sheet like any invite link (N-18: user-shared, Snacklist sends nothing). Valid 30
days. With „Beitritte bestätigen“ (`join_approval`) on, only owners and admins create helper links
(N-384, build condition; ending stays open to every member, since it only reduces exposure); any
member sees the household's helper links under Mehr › Haushalt › Helferlinks, with label,
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
   items stay with the list, `added_by` null and `items.helper_link_id` null for the rows the helper
added, N-371). That is how a helper uses Art. 15, 17 and 20.
7. No name ask. Members see helper items as „über Helferlink „Oma Ruth““ (the label the member
   typed, read through `items.helper_link_id`), in the item details where „hinzugefügt von“ shows
   today. The label stays after the grant ends and goes when the link is deleted, or when the helper deletes
their data (N-371).
8. A full user who is a member of that household is sent to the list instead. A full user who is
   not gets the helper view; the grant does not appear in their household switcher.

**Ends:** the member ends the link (all grants end at once); the link expires; a grant is unused
for 30 days. An ended link shows copy H8. A browser that lost its storage opens the link again and
gets a new grant.

**Limits:** 10 browsers per link within 30 days, 50 adds per grant per day, 5 open helper links per
household. The code has 128 random bits and is stored hashed, so guessing is moot. The code stays out of
Vercel's path logs and referrers (N-385): it travels in the URL fragment
(`https://app.snacklist.app/h#<code>`, never sent to Vercel), or, if it stays in the path, `/h/*` is
served with `Referrer-Policy: no-referrer`, `X-Robots-Tag: noindex, nofollow` and
`Cache-Control: no-store`, and R4 names Vercel's 30-day path log. The build decides; the DEEP_LINKS row
follows. Helper error states: H8 for an ended link, the 10-browser cap and the `helper_links` switch
off; H11 for a burst limit (N-394).

**Why not an invite variant:** a helper never becomes a member, so the rule „an invite must not
join under a throwaway anonymous id“ holds, and a helper owns nothing that can be lost. Their
items belong to the household; purging or deleting the helper's user sets `added_by` and
`helper_link_id` to null on the rows they added (N-371, `delete_account` nulls `helper_link_id` where
`added_by = p_user_id` before it nulls `added_by`, with a pgTAP assertion), so no label stays on
their entries.

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
- Konto page: anonymous state (U2), „Konto erstellen“, export, „Liste und Konto löschen“.
- Purchases: Buy and Restore hidden behind the gate sheet; `note_revenuecat_customer` is refused.
- OAuth consent screen: anonymous users get the gate sheet, not the approve button.
- Helper page `/h/<code>`: its own scaffold (list and add bar only), no tabs, no switcher.
- Analytics (`eventCatalog`, `docs/ANALYTICS.md`, no text): `anonymous_started`,
  `account_upgraded {method: email|google|apple, days_anonymous: bucket}`,
  `account_transfer {result: moved|deleted}`, `upgrade_prompt {trigger, action}`,
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
| `delete_account`, `F/account` | Service only, session JWT | Anonymous users use it for „Liste und Konto löschen“. Change (N-371): when deleting a user, set `items.helper_link_id = null` on rows where `added_by = p_user_id` before `added_by` is nulled; a pgTAP assertion; the same on purge |
| Content reports, `F/report` `/report/app` | `APP_LIMITS = { perUserHour: 5, perHour: 200 }` and a confirmation mail to any address in the body (`supabase/functions/report/handler.ts:58,289-299`). Fresh anonymous ids would give 150 reports an hour per IP, nearly the global 200, and mail to addresses of the sender's choice | Reports stay open to anonymous users (DSA Art. 16), with three changes for them: `email` is dropped server-side (the app hides the field; no confirmation mail), their own global bucket of 20 an hour (`anonPerHour`) so the 200 for everyone else cannot be used up by them, and 2 per user an hour. The form says that a confirmation by email comes with the web form (`/inhalte-melden`), which keeps its own limits. Function tests for each; Legal question 10. **Legal conditions (N-377):** the categories `danger` and `csam` are exempt from `anonPerHour` (20 an hour) and `perUserHour` (2 an hour); when rate-limited the app shows the same `support@snacklist.app` fallback copy as `inhalte-melden.md:41`; after sending, the app always shows the `{ref}` report number on screen and the anonymous report sheet has a 1-tap link to `/inhalte-melden` (`/en/report`): „Für Bestätigung und Entscheidung per E-Mail: Web-Formular öffnen“ / „For confirmation and decision by e-mail: open web form“. Addendum: the web form `/report` must **offer** name and e-mail fields (needed for the receipt confirmation and the decision notice under Art. 16(4)-(5) DSA) but never make them mandatory for `csam`, and should not block a report without them in other categories |
| New: `prepare_account_transfer`, `claim_account_transfer` | none | 4.3. `claim_account_transfer` is rate-limited and the transfer code is never logged (N-390) |
| New: `begin_email_upgrade` | none | 4.2: 3 email upgrade attempts per anonymous user a day, counted in the daily total |
| New: `create_helper_link`, `end_helper_link`, `household_helper_links`, `claim_helper_link`, `helper_list`, `helper_put_item`, `helper_delete_item` | none | 4.7; all `security definer`, membership or grant checked inside; full accounts only for the member functions; with `join_approval` on, `create_helper_link` only for owners and admins; `end_helper_link` stays open to every member (N-384) |
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
widget on every sign-in, so it waits for evidence, and any future captcha needs its own Legal GO first (Q6, 13.1).

## 7. Copy (proposed, DE and EN)

Keys are proposals for the build job; nothing is added to the ARB files now.

| Id | Where | DE | EN |
| --- | --- | --- | --- |
| A2 | Account step, second button | Erst mal ohne Konto | Continue without an account |
| A3 | Under A2 | Ohne Konto ist deine Liste nur auf diesem Gerät. Löschst du die App oder meldest dich ab, ist sie weg. Nutzt du Snacklist 90 Tage nicht, löschen wir sie. Einladen, Siri, Alexa, KI-Assistenten und Premium gehen nur mit Konto. Snacklist ist ab 16. | Without an account, your list is only on this device. If you delete the app or sign out, it is gone. If you don't use Snacklist for 90 days, we delete it. Inviting, Siri, Alexa, AI assistants and Premium need an account. Snacklist is for ages 16+. |
| U1 | List card | **Liste sichern** Mit einem Konto geht deine Liste nicht verloren, und du kannst jemanden einladen. [Konto erstellen] [Später] | **Keep your list** With an account your list can't get lost, and you can invite someone. [Create account] [Later] |
| U2 | Konto page | Du nutzt Snacklist ohne Konto. Deine Liste ist nur auf diesem Gerät. Ohne Nutzung löschen wir sie nach 90 Tagen. Mit einem Konto nutzt du sie auch auf anderen Geräten. | You're using Snacklist without an account. Your list is only on this device. Unused, we delete it after 90 days. With an account you can use it on other devices too. |
| U3 | Gate sheet | **Dafür brauchst du ein Konto** Einladen, Siri, Alexa, KI-Assistenten und Premium gibt es nur mit Konto. Deine Liste bleibt, wie sie ist. [Konto erstellen] [Abbrechen] | **You need an account for this** Inviting, Siri, Alexa, AI assistants and Premium need an account. Your list stays as it is. [Create account] [Cancel] |
| U4 | Invite while anonymous | **Zum Beitreten brauchst du ein Konto** Deine eigene Liste bleibt. Nach dem Beitritt wechselst du oben zwischen beiden Haushalten. | **You need an account to join** Your own list stays. After joining, switch between both households at the top. |
| U5 | Sign-out, anonymous | **Ohne Konto abmelden?** Deine Liste ist dann für immer weg. Erstelle vorher ein Konto, um sie zu behalten. [Konto erstellen] [Liste und Konto löschen] | **Sign out without an account?** Your list will be gone for good. Create an account first to keep it. [Create account] [Delete list and account] |
| U6 | Upgrade, email taken | **Zu dieser Adresse gibt es schon ein Konto** Melde dich dort an. Danach übernehmen wir deine Liste in dieses Konto. Bleib dafür auf diesem Gerät. | **This address already has an account** Sign in to it. We'll then move your list into that account. Stay on this device for it. |
| U6b | Upgrade, Google or Apple account taken | **Dieses Google-Konto nutzt du schon für Snacklist** Melde dich damit an. Danach übernehmen wir deine Liste in dieses Konto. Bleib dafür auf diesem Gerät. (Apple: „Diese Apple-ID …“) | **You already use this Google account for Snacklist** Sign in with it. We'll then move your list into that account. Stay on this device for it. (Apple: "This Apple Account …") |
| U7 | After sign-in | Liste „{household}“ in dein Konto übernehmen? [Übernehmen] [Liste löschen] (mit Bestätigungszeile bei „Liste löschen“: „Deine Liste wird dann sofort gelöscht.“) | Move the list "{household}" into your account? [Move] [Delete list] (confirmation line when „Delete list“ is tapped: "Your list will then be deleted right away.") |
| U7b | Transfer, receiver at the cap | Du bist schon in 20 Haushalten. Verlass zuerst einen, dann übernehmen wir die Liste. | You're already in 20 households. Leave one first, then we'll move the list. |
| U8 | Upgrade, email sent | Wir haben dir einen Link an {email} geschickt. Sobald du ihn öffnest, ist dein Konto fertig. | We sent a link to {email}. Once you open it, your account is ready. |
| C1 | Cap hit, items, lists, stores or categories (anonymous) | **Mehr geht nur mit Konto** Ohne Konto hat deine Liste Platz für {limit}. Mit einem Konto gibt es keine solche Grenze. [Konto erstellen] [OK] | **More needs an account** Without an account your list has room for {limit}. With an account there is no such limit. [Create account] [OK] |
| C1 limits | `{limit}` per cap | 1.000 Einträge · 3 Listen · 20 Läden · 40 Kategorien | 1,000 items · 3 lists · 20 stores · 40 categories |
| C2 | Cap hit, feedback (anonymous) | Heute kannst du ohne Konto keine weitere Rückmeldung schicken. Morgen wieder, oder jetzt mit Konto. | You can't send more feedback today without an account. Try again tomorrow, or create an account now. |
| C3 | Cap hit, email upgrade attempts | Heute haben wir schon dreimal einen Link geschickt. Versuch es morgen wieder oder nimm Google oder Apple. | We've already sent a link three times today. Try again tomorrow, or use Google or Apple. |
| C4 | Helper, 50 adds a day | Für heute ist hier genug eingetragen. Morgen geht es weiter. | That's enough for today. You can add more tomorrow. |
| H1 | Invite sheet entry | Helferlink teilen | Share a helper link |
| H2 | Helper link sheet | **Jemand schreibt nur ab und zu was dazu?** Mit einem Helferlink sieht jemand den Namen eures Haushalts und die offenen Einträge dieser Liste und kann im Browser etwas hinzufügen, ohne Konto und ohne Mitglied zu werden. Der Link gilt 30 Tage. Prüfe vorher, ob auf der Liste nichts steht, was nur Mitglieder sehen sollen (zum Beispiel Apotheken- oder Gesundheitsartikel). | **Someone just adds things now and then?** With a helper link, someone sees your household's name and the open items on this list and can add to it in the browser, without an account and without becoming a member. The link works for 30 days. Check first that the list holds nothing only members should see (for example pharmacy or health items). |
| H3 | Label field | Für wen ist der Link? | Who is the link for? |
| H4 | Label hint (below the field) | z. B. Oma Ruth (bitte keine vollen Namen oder Gesundheitsangaben) | e.g. Grandma Ruth (please no full names or health details) |
| H5 | Share text | Schreib einfach dazu, was wir mitbringen sollen: {url} | Just add what we should pick up: {url} |
| H6 | Helper page, above the add bar, visible without scrolling | Was du hier einträgst, sehen alle im Haushalt sofort. Ändern kannst du es, solange du diesen Browser nutzt und er seine Daten behält. Dafür speichern wir eine zufällige Browser-Kennung, deine IP-Adresse und deine Einträge (Löschung der Kennung nach 30 Tagen ohne Nutzung). Mehr dazu und zu deinem Widerspruchsrecht: [Datenschutz](/datenschutz#helferlinks). | Everyone in the household sees what you add right away. You can change it as long as you use this browser and it keeps its data. For this we store a random browser ID, your IP address and your entries (ID deleted after 30 days without use). Details and your right to object: [Privacy](/en/privacy#helferlinks). |
| H7 | Helper page footer | Ohne Konto · Impressum · Datenschutz · Meine Daten · Löschen · Eigene Liste anlegen | No account · Imprint · Privacy · My data · Delete · Start your own list |
| H8 | Ended link | Dieser Helferlink gilt nicht mehr. Frag nach einem neuen. | This helper link no longer works. Ask for a new one. |
| H9 | Item details, members | über Helferlink „{label}“ | via helper link "{label}" |
| H10 | Helper links list | Helferlinks · noch {days} Tage · {count} Browser · [Beenden] | Helper links · {days} days left · {count} browsers · [End] |
| H12 | Helper page, confirmation after „Löschen“ (N-381) | Deine Daten auf dieser Seite löschen? Deine Einträge bleiben ohne Bezug zu dir auf der Liste. | Delete your data on this page? Your entries stay on the list with no link to you. |
| H11 | Helper, burst limit (N-394) | Gerade sind zu viele Einträge auf einmal eingegangen. Versuch es gleich noch einmal. | Too many additions arrived at once. Please try again in a moment. |
| F1 | Anonymous in-app feedback form, below the message box (N-389) | Ohne Konto antworten wir nur hier in der App, solange dieses Konto besteht. | Without an account we reply only here in the app while this account exists. |

H7 gets „Nutzungsbedingungen“ / „Terms“ only once the terms leave `draft: true` (N-374); H7's „Löschen“
keeps its name with the confirmation H12 (N-381). H8 is reused for the 10-browser cap and the
`helper_links` switch (N-394). U3 names Alexa and AI assistants generically; no brand outside functional help (brand-names lint).
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

An anonymous user cannot be told before the purge (no address). Legal question 3 is decided (N-372): the
90-day rule is stated explicitly in A3 (before the choice) and in U2 (Konto page). Backups keep
deleted data up to 90 more days (N-386): the Supabase session lifetime and inactivity limits are set
where available, and a hashed, non-reversible deletion ledger makes any disaster-recovery restore
run `delete_account` again for IDs that were purged or deleted.

## 9. Stores

- Apple 5.1.1(v): account deletion is offered to every account, anonymous ones included
  („Liste und Konto löschen“, N-381). Apple's App Privacy answers do not change (no new data types).
- Google Play data safety: the account-creation answer becomes "optional"; the deletion URL pages
  (`konto-loeschen.html` and `delete-account.html`) get one paragraph for use without an account (redline R9).
- Store listings and review notes (constraint, Q8, N-391): „in der App ohne Konto starten/nutzen“
  may be mentioned only once `anonymous-start` is on for 100 % of users, and must then name the
  features that need an account (inviting, Siri, Alexa, AI assistants, Premium). Never „anonym“,
  „keine Daten“ or „ohne Anmeldung“ for the web app (user ids, IPs and user agents are
  pseudonymous, § 5 UWG). Google Play Data Safety „Account creation“ becomes **optional** when the
  flag goes public; Apple App Privacy stays unchanged. A competition lawyer reviews the exact
  phrases (lawyer question 6).

## 10. Build sequence (after Legal's GO)

| Job | Scope | Proof |
| --- | --- | --- |
| AN1-1 | Server guards, caps, `caller_is_anonymous`, kill switch, local config on | pgTAP matrix of section 6 |
| AN1-2 | Session `account`, `authRedirect` rules, account step, gate sheet, sign-out dialog, Konto page, flag `anonymous-start` | router and widget tests; verify-family-groceries drive on Android and Linux; a screenshot at 390×844 and at 200 % text proves the `LegalFooter` (Impressum, Datenschutz) stays visible below A2 and the longer A3 (N-374) |
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
| P6 | Purge | deletion of anonymous users by inactivity | nobody | not applicable | Art. 5 Abs. 1 lit. e, Art. 17 i.V.m. Art. 6 Abs. 1 lit. c / lit. f DSGVO (N-392) |
| P7 | Caps and counts | counts per user, household and grant; GoTrue's per-IP limit on anonymous sign-ins (Supabase's, as for sign-ins today); a daily total of new anonymous users for us | nobody | not stored beyond the rows themselves | Art. 6 Abs. 1 lit. f |
| P8 | Device storage | anonymous session; on the helper page, the session and the link | the device | until sign-out, deletion, or the browser clears it | § 25 Abs. 2 Nr. 2 TDDDG |
| P9 | No PostHog on the helper page | the helper page starts no PostHog client and asks no flags, unlike the rest of the web app without consent (section 9) | not applicable | not applicable | not applicable |

No new processor or recipient. Supabase (auth, database), Resend (the confirmation email) and
Vercel (the web app) are used as today. No captcha provider in step one; a future one needs its own Legal GO (Q6).

### 11.2 Proposed redlines (privacy policy, `site/content/legal/datenschutz.md`; `privacy.md` follows)

Not applied. To go in with AN1-7 as one PR after Legal's GO and the build. The section numbers are
today's. Legal's rulings of 22 Nov 2026 are applied below (R0, R2, R4, R6, R7, R8, R9, R10, R11);
R1, R3, R5 and R12 were accepted as drafted. Dependency, not edited here: the text lands on `main`'s
privacy files after #584 (section 13, N-373, N-378).

- **R0, `datenschutz.md:67` / `privacy.md:51` (section 3, Web-App, the onboarding bullet; N-378):**
  DE: „deine Antworten bei der Einrichtung, solange du noch nichts angelegt hast (mit wem du
  einkaufst, Haushaltsname, Läden und die ersten Einträge), damit die Einrichtung nach einem Neustart
  weitergeht; mit der Registrierung oder, in der App, wenn du ohne Konto weitermachst, werden daraus
  dein Haushalt und deine Liste, und die Kopie auf dem Gerät wird gelöscht.“ EN: „your answers during
  setup while you have not created anything yet (who you shop with, the household name, stores and
  your first items), so setup continues after a restart, until signing up or, in the app, continuing
  without an account turns them into your household and list and the copy on the device is deleted“
- **R1, section 3 (Web-App), device storage list, new bullet after „deine Anmeldesitzung“
  (`datenschutz.md:68-70`, `privacy.md:51`):** DE: „wenn du einen Helferlink öffnest: eine Sitzung
  ohne Konto und den Link, damit du die Liste beim nächsten Mal wieder siehst,“ EN: „when you open a
  helper link: an account-less session and the link, so you see the list again next time,“
- **R2, section 4 (Konto und Anmeldung), new paragraph at the start (`datenschutz.md:74`,
  `privacy.md:55`; N-373, N-386):**
  „In der App kannst du Snacklist zuerst ohne Konto nutzen. Wir legen dann ein Konto ohne
  E-Mail-Adresse an, das nur eine zufällige Kennung hat und nur von diesem Gerät aus erreichbar ist.
  Meldest du dich ab, löschst du die App oder verlierst du das Gerät, können wir es dir nicht
  wiederherstellen. Erstellst du später ein Konto mit E-Mail-Adresse, Google oder Apple, bleibt es
  dasselbe Konto mit denselben Daten. Gibt es zu deiner Adresse schon ein Konto, übernehmen wir
  deine Liste auf deinen Wunsch in dieses Konto und löschen das Konto ohne E-Mail-Adresse; dafür
  speichern wir eine Stunde lang einen einmaligen Code. Ein Konto ohne E-Mail-Adresse löschen wir mit
  allen Daten, wenn es 90 Tage nicht genutzt wurde; in verschlüsselten Sicherungskopien bleiben
  gelöschte Daten noch bis zu 90 Tage (Abschnitt 11).“ The sentence on the session's IP address and
  user agent leaves R2 (N-373): section 4 states it for every sign-in session, see section 13.
- **R3, section 4, last sentence:** „Für Anmeldelinks und Bestätigungen“ → „Für Anmeldelinks,
  Bestätigungen und das Bestätigen deiner Adresse, wenn du ein Konto ohne E-Mail-Adresse
  sicherst,“ EN: „For sign-in links, confirmations and confirming your address when you secure an
  account without an e-mail address,“
- **R4, section 5, new subsection after „Rollen und Einladungen“, „Helferlinks“ {#helferlinks}
  (N-371, N-384, N-385; DE below):**
  „Mitglieder (bei aktivem „Beitritte bestätigen“: Admins) können einen Helferlink zu einer Liste teilen. Wer ihn öffnet, sieht im Browser die
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
  löschst die Kennung deines Browsers; deine Einträge bleiben dann ohne Bezug zu dir und ohne die
  Bezeichnung des Links auf der Liste.
  Snacklist verschickt keine Helferlinks; ihr teilt sie selbst. Die Helferseite fragt nicht nach
  Nutzungsdaten, sendet nichts an PostHog und fragt dort auch nicht ab, welche Funktionen
  eingeschaltet sind.
  Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO für die Mitglieder; für die Person, die den Link nutzt
  oder in der Bezeichnung genannt ist, unser berechtigtes Interesse, Haushalten das gemeinsame
  Einkaufen mit Helfenden zu ermöglichen (Art. 6 Abs. 1 lit. f DSGVO).“ EN of the deletion sentence
  (N-371): „Via "My data" and "Delete" on the helper page you receive your data or delete your
  browser's identifier; your entries then stay on the list with no link to you and without the
  link's label.“ If the helper code stays in the URL path rather than the `#fragment`, R4 also
  discloses Vercel's 30-day path log (N-385).
- **R5, section 5, „Rollen und Einladungen“ (`datenschutz.md:97`):** add „Ohne Konto kannst du nicht
  einladen und keinem Haushalt beitreten.“ / „Without an account you cannot invite anyone or join a
  household.“
- **R6, section 7 (Siri, Alexa, KI-Assistenten), first paragraph:** add „Dafür brauchst du ein Konto
  mit E-Mail-Adresse, Google oder Apple.“ / „For this you need an account with an e-mail address,
  Google or Apple.“ Plus the six further places where „angemeldet“ / „signed in“ misleads
  (N-379, exact text in section 13).
- **R7, section 8 (Export und Löschen):** add to the export list „ob dein Konto ohne
  E-Mail-Adresse ist, deine Helferlinks und die Helferlinks, die dein Browser genutzt hat“; add
  „Auch ohne Konto kannst du unter Konto › Liste und Konto löschen alles sofort löschen.“ / „Even
  without an account you can delete everything immediately under Account › Delete list and account.“
  (N-381)
- **R8, section 14 (Speicherdauer), after the first sentence:** „Ein Konto ohne E-Mail-Adresse
  löschen wir mit allen Daten nach 90 Tagen ohne Nutzung, eines, das nur Helferlinks genutzt hat,
  nach 30 Tagen, eines ohne Haushalt und ohne Helferlink nach 7 Tagen. Den einmaligen Code zur
  Übernahme einer Liste löschen wir nach einer Stunde. In verschlüsselten Sicherungskopien bleiben
  gelöschte Daten noch bis zu 90 Tage (Abschnitt 11).“ EN: „In encrypted backups, deleted data
  remains for up to 90 more days (section 11).“ And in the household sentence: „Mit einem
  Haushalt löschen wir auch seine Listen, Einladungen, Helferlinks, …“ Applies to **both**
  `::: until premium-launch` and `::: once premium-launch` variants once #584 lands (N-378, N-386).
- **R9, `app/web/konto-loeschen.html` (under „Kein Zugang mehr zur App?“, line 122) and its English
  twin `app/web/delete-account.html` (under „Can't get into the app anymore?“, line 118; N-381):**
  DE: `<p><strong>Ohne Konto:</strong> Unter <strong>Mehr › Konto › Liste und Konto löschen</strong>
  löschst du deine Liste und das Konto ohne E-Mail-Adresse sofort in der App. Ohne Zugang zur App
  können wir ein Konto ohne E-Mail-Adresse auf dieser Seite nicht erkennen; deinstalliere die App und
  ungenutzte Konten ohne E-Mail-Adresse löschen wir automatisch nach 90 Tagen.</p>` EN:
  `<p><strong>Without an account:</strong> Under <strong>More › Account › Delete list and
  account</strong> you delete your list and the account without an e-mail address right away in the
  app. Without access to the app we cannot identify an account without an e-mail address on this
  page; uninstalling the app stops use, and we delete unused accounts without an e-mail address
  automatically after 90 days.</p>`
- **R10, section 17 (Mindestalter, `datenschutz.md:241`, `privacy.md:235`; N-382):** append DE:
  „Das gilt auch, wenn du ohne Konto startest oder einen Helferlink nutzt.“ EN: „This also applies if
  you start without an account or use a helper link.“ Minors and the analytics consent go to a
  data-protection lawyer (section 13).
- **R11, section 5a of `datenschutz.md` / `privacy.md` (`datenschutz-pr584.md:115`,
  `privacy-pr584.md:96`), not the deprecated `datenschutz-kaeufe.md` / `privacy-purchases.md`
  (N-364, N-378):** DE: „In der iPhone- und der Android-App kannst du mit einem Konto
  (E-Mail-Adresse, Google oder Apple) Snacklist Premium für dich kaufen oder wiederherstellen:“ EN:
  „In the iPhone and Android apps, with an account (e-mail address, Google or Apple), you can buy or
  restore Snacklist Premium for yourself:“
- **R12, section 16 (Pflicht zur Bereitstellung):** „Ohne E-Mail-Adresse oder Google-/Apple-Anmeldung
  kannst du kein Konto anlegen“ → „In der App kannst du Snacklist ohne E-Mail-Adresse nutzen
  (Abschnitt 4). Um einzuladen, beizutreten, Siri, Alexa, KI-Assistenten oder die Schnittstelle zu
  verbinden, Premium zu kaufen oder Snacklist auf einem weiteren Gerät zu nutzen, brauchst du ein
  Konto mit E-Mail-Adresse oder Google-/Apple-Anmeldung. Einen Helferlink nutzt du ohne Konto.“ (`datenschutz.md:237`, `privacy.md:231`; accepted as drafted.)

The analytics consent text (version 2026-11-18) does not change: anonymous users are asked the same
question as today (usually step 1 of the guided start, else after the sign-in), and the helper page asks nothing and sends nothing (P9; a
build requirement with its own test, section 4.7).

### 11.3 Questions for Legal

Legal answered all ten on 22 Nov 2026; the decisions are in section 13.1. The questions stay as asked.

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

This file (sha256 in NEEDS_LEAD, job 396). A GO covers: the design's processing (11.1), the redlines
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
5. No captcha in step one; caps, kill switch and a daily count instead. A future captcha needs its
   own Legal GO first (Q6).
6. Purge windows 90 / 30 / 7 days (Legal decided Q3: the 90 days stay, stated in A3 and U2).
7. No Keychain persistence in step one.
8. The display-name trigger stays; the name step right after the link covers it.
9. Helpers export and delete from the helper page; the helper page starts no PostHog client and no
   flag query.
10. Transfers re-point every row keyed to the anonymous user, derived from the foreign keys, before
    deleting it.
11. Anonymous users may send feedback (3 a day) and read in-app replies; no reply by email. This
    deviates from the research's account-only list; Legal question 10 (Q10a: GO, with F1).
12. Anonymous content reports: no email, own bucket of 20 an hour, 2 per user an hour; `danger` and
    `csam` are exempt from both caps (N-377).
13. The kill switch sits in the household cap trigger, so it covers every `create_household`
    overload and every join. Helpers have their own switch, `helper_links`.
14. On the web, an anonymous session outside `/h/*` and the upgrade goes to the last helper link,
    else `/upgrade`.
15. Store and category caps are table triggers, not function checks, because members may insert
    into both tables directly (review 1).
16. Legal's conditions of 22 Nov 2026 (N-370 to N-395) are applied; the list is section 13. Q3 is
    decided: the 90 days are stated in A3 and U2. Q6: no captcha without its own Legal GO. Q8: the
    store-copy rule is a constraint (section 9). N-373 and N-378 depend on #584 and are not edited
    here.

## 13. Legal conditions (review of PR #642, 22 Nov 2026, applied in job 396)

Verdict: **GO with conditions** (design sound, no new processor, account-only boundaries enforced on
the server). The 10 MUST items N-370 to N-379 are resolved before the final build/hash GO and before
`anonymous-start`, `helper-links`, Supabase anonymous sign-in or manual linking are turned on. The
report is job 396's `in/legal-642-an1.md`. The sections above carry the changes in place; this section
lists every finding, where it landed, and the redlines that belong to other files.

### 13.1 Constraints (Legal decisions on Q1 to Q10)

- **Q1** Helpers and a person named in a label: Art. 6 Abs. 1 lit. f DSGVO (not lit. b). R4 is
  approved with N-371, N-375, N-384, N-385. A notice above the add bar is required (H6). For a
  person named in a label who never opens `/h/*`, Art. 14 Abs. 5 lit. b applies. The LIA is still to be
  written before launch (N-392, 13.6).
- **Q2** Anonymous accounts: lit. b is right, provided Art. 13 information is reachable at the tap
  (`LegalFooter` on `_AccountStep`, A3 with N-372, N-374).
- **Q3** The 90-day purge is stated explicitly in A3 and U2 (N-372).
- **Q4** Transfer approved under R2 with three conditions: U7 `[Liste löschen]` (N-390), the
  one-time transfer code is never logged, `claim_account_transfer` is rate-limited.
- **Q5** Age stays 16+; A3 and § 17 say it for anonymous and helper use (N-382); minors go to a
  lawyer.
- **Q6** **Captcha: no vendor is pre-cleared. Any future captcha (Turnstile, hCaptcha) needs its own
  Legal GO first** (new processor, third-country transfer, § 25 TDDDG). Server caps and the kill
  switch stay the response.
- **Q7** Rights without an account are acceptable under Art. 11 Abs. 1-2 DSGVO, disclosed in § 15
  (N-380), with a one-month answer SOP under Art. 12 Abs. 3.
- **Q8** **Store copy** is allowed only with the constraints in section 9 (N-391), and only once
  `anonymous-start` is on for 100 % of users.
- **Q9** Session IP and user agent are disclosed in § 4 for all accounts at once (N-373).
- **Q10a** Anonymous feedback and in-app replies: GO, with N-389 (F1, support and privacy lines
  below).
- **Q10b** Anonymous app reports: keep, with N-377 (section 6).
- **Deviations (a) to (g):** all GO; (b), (d), (e), (g) with the conditions above.

### 13.2 Findings and where they landed

| Id | Class | What | Landed in |
| --- | --- | --- | --- |
| N-370 | MUST | Imprint in the helper footer (§ 5 DDG) | H7 |
| N-371 | MUST | Null `items.helper_link_id` where `added_by = user` on helper delete and purge, pgTAP assertion; R4 deletion sentence | 4.7, section 6 (`delete_account`), R4 |
| N-372 | MUST | 90-day purge stated in A3 and U2 | section 7, section 8 |
| N-373 | MUST | Supabase Auth session IP and user agent for **all** accounts in § 4: **dependency on #584** | 13.3 |
| N-374 | MUST | Keep `LegalFooter` on `_AccountStep` and `/upgrade`; no link to draft terms or Apple's EULA; add terms § 3a | 13.3, 13.4 |
| N-375 | MUST | Art. 13 and 21(4) notice above the add bar, `Datenschutz` link visible without scrolling | H6 |
| N-376 | MUST | `inhalte-melden.md:53` and `report.md:53` | 13.4 |
| N-377 | MUST | Anonymous reports: `danger`/`csam` exempt from caps, e-mail fallback, `{ref}` on screen, link to the web form; web form offers (never requires for `csam`) name and e-mail | section 6, 13.4 |
| N-378 | MUST | R0, R8, R11 reconciled with `main` and #584: **dependency on #584** | R0, R8, R11, 13.3 |
| N-379 | MUST | Six further „angemeldet“ / „signed in“ places | R6, 13.4 |
| N-380 | SHOULD | Art. 11 DSGVO disclosure in § 15 | 13.4 |
| N-381 | SHOULD | „Liste und Konto löschen“, `delete-account.html` parity, support FAQ line | U5, R7, R9, section 9, 13.4 |
| N-382 | SHOULD | 16+ in A3 and § 17 | A3, R10 |
| N-383 | SHOULD | Art. 9 caution in H2 and H4 | H2, H4 |
| N-384 | SHOULD | With `join_approval` on, only owners and admins create helper links; ending stays open to every member | 4.7, section 6; conflict note 13.5 |
| N-385 | SHOULD | Helper code out of Vercel path logs and referrers | 4.7; conflict note 13.5 |
| N-386 | SHOULD | Session time-box, hashed deletion ledger, 90-day backup note | section 8, R2, R8 |
| N-387 | SHOULD | DSA Art. 14 content rules in the draft terms (§ 14a) | 13.4 |
| N-388 | SHOULD | Support FAQ updates | 13.4 |
| N-389 | SHOULD (brief: MUST) | In-app-only replies while the anonymous account exists | F1, 4.5, 13.4 |
| N-390 | SHOULD (brief: MUST) | U7 `[Liste löschen]`, never log the transfer code, rate-limit `claim_account_transfer` | U7, 4.3, section 6 |
| N-391 | SHOULD | Store copy rules, Play Data Safety | section 9 |
| N-392 | SHOULD | LIA for P4, P5, P7; add P1 to P9 to the Art. 30 register; P6 basis | P6, 13.6 |
| N-393 | SHOULD | Test: zero RevenueCat requests while anonymous | 13.6 |
| N-394 | OPTIONAL | Helper error states, H11 | 4.7, section 7 |
| N-395 | OPTIONAL | Breach notice for accounts without a contact, transactional upgrade mail | 13.6 |

### 13.3 Dependencies on #584 (not edited in this PR)

#584 (`datenschutz.md`, `privacy.md`, draft terms) is not touched here. These land with AN1-7 after
#584 rebased onto `main` (N-326: trip detection and the per-account beta thank-you come back):

- **N-373** (§ 4 of `datenschutz.md:74` / `privacy.md:55`, for every account; R2 drops its duplicate):
  - Anchor note: the report quotes #584's wording; today's `main:datenschutz.md:74` reads „der sie über …“
    instead of „die sie über …“. The build matches the sentence on whatever base it lands on.
  - DE: append after „… die sie über unseren Dienstleister Resend verschickt (Abschnitt 12).“, before
    „Rechtsgrundlage:“: „Zu jeder Anmeldesitzung speichert unser Dienstleister Supabase die
    IP-Adresse und die Browser- bzw. Gerätekennung (User-Agent), bis die Sitzung endet oder das Konto
    gelöscht wird.“
  - EN: append after „… which sends them through our service provider Resend (section 12).“, before
    „Legal basis:“: „For each sign-in session, our service provider Supabase stores the IP address and
    the browser or device identifier (user agent) until the session ends or the account is deleted.“
- **N-378:** rebase #584 onto `main` first; apply R8 to both `until premium-launch` and
  `once premium-launch` blocks; R11 goes into § 5a, not into the deprecated purchases pages; R0's
  lead-in is fixed as above.
- **N-374 / N-387 / N-379** edits of the draft terms (13.4) wait for #584's files
  (`nutzungsbedingungen-pr584.md`, `terms-pr584.md`) and for a lawyer's review before `draft: true`
  is removed.

### 13.4 Redlines for other files (applied with AN1-7)

- **N-374, now (build while terms stay `draft: true`):** keep `LegalFooter` (`Impressum ·
  Datenschutz`) visible below the buttons on `_AccountStep` (`steps.dart:582`) and `/upgrade`
  (`SignInPanel`, `LoginScreen`). Do **not** link `/nutzungsbedingungen` (404) or Apple's paid EULA on
  anonymous start or `/h/*`. **Before publishing the terms**, add the provisions below (plus N-379 and
  N-387), clear incorporation and § 327 Abs. 3 / § 312 Abs. 1a BGB with an AGB lawyer, then add
  `Nutzungsbedingungen` / `Terms` to `LegalFooter` (or A3) and to H7.
  - Draft terms, after § 3, DE `## 3a. Nutzung ohne Konto und Helferlinks`: „In der App kannst du
    Snacklist zunächst ohne Konto nutzen. Deine Liste ist dann nur auf diesem Gerät gespeichert;
    löschst du die App oder meldest dich ab, ist sie weg, und nach 90 Tagen ohne Nutzung löschen wir
    sie mit dem Konto. Einladen, Beitreten, Helferlinks, Siri, Alexa, KI-Assistenten, die API und
    Snacklist Premium gibt es nur mit Konto (E-Mail-Adresse, Google oder Apple).“ / „Mit einem
    Helferlink kannst du im Browser Einträge zu einer einzelnen Liste hinzufügen und eigene noch
    offene Einträge ändern oder löschen, ohne ein Konto anzulegen und ohne Mitglied des Haushalts zu
    werden. Ein Helferlink gilt 30 Tage; die Mitglieder des Haushalts können ihn jederzeit beenden.“
  - EN `## 3a. Use without an account and helper links`: „In the app you can start using Snacklist
    without an account. Your list is then stored only on this device; if you delete the app or sign
    out, it is gone, and after 90 days without use we delete it together with the account. Inviting,
    joining, helper links, Siri, Alexa, AI assistants, the API and Snacklist Premium require an
    account (e-mail address, Google or Apple).“ / „With a helper link you can add entries to a single
    list in the browser and edit or delete your own still-open entries, without creating an account
    and without becoming a household member. A helper link is valid for 30 days; the household's
    members can end it at any time.“
- **N-376, `inhalte-melden.md:53` / `report.md:53`:**
  - DE old: „Was du in Snacklist einträgst – Einträge, Listen, Haushaltsnamen, Fotos, Rückmeldungen –,
    sehen nur die Mitglieder deines Haushalts (Rückmeldungen nur wir).“ DE new: „Was du in Snacklist
    einträgst – Einträge, Listen, Haushaltsnamen, Fotos, Rückmeldungen –, sehen die Mitglieder deines
    Haushalts sowie bei einem geteilten Helferlink die Personen mit diesem Link für die offenen
    Einträge der ausgewählten Liste samt Listen- und Haushaltsnamen (Rückmeldungen nur wir).“
  - EN old: „What you put into Snacklist – items, lists, household names, photos, feedback – is seen
    only by the members of your household (feedback only by us).“ EN new: „What you put into
    Snacklist – items, lists, household names, photos, feedback – is seen by the members of your
    household and, if a member shares a helper link, by people with that link for the open items of
    the chosen list together with the list and household names (feedback only by us).“
- **N-377, `inhalte-melden.md:55` / `report.md:55`** (the website form already offers optional name and
  e-mail, so the addendum's correction is met there; AN1 gives helpers no report entry yet; whether
  the helper page links to `/inhalte-melden` / `/en/report` (Art. 16 Abs. 1 DSA, easy access) is open
  for the build, with H7):
  - DE new: „Wer eine E-Mail-Adresse angibt, bekommt eine Eingangsbestätigung und unsere Entscheidung
    mit Begründung. In der App ohne Konto kannst du keine E-Mail-Adresse angeben; die Meldungsnummer
    siehst du dort auf dem Bildschirm. Möchtest du eine Bestätigung per E-Mail, nutze dieses
    Formular.“
  - EN new: „If you give an e-mail address, you get a confirmation of receipt and our decision with
    reasons. In the app without an account you can't enter an e-mail address; you see the reference
    number on screen. If you want a confirmation by e-mail, use this form.“
  - `datenschutz.md:189` DE: before „Wir löschen Meldungen und unsere Entscheidung 12 Monate nach
    Abschluss des Falls, …“ insert „Meldest du in der App ohne Konto, übermittelst du keine
    E-Mail-Adresse und wir schicken keine Bestätigung; möchtest du eine Bestätigung, nutze das
    Formular auf unserer Website.“ `privacy.md:170` EN: before „We delete reports and our decision 12
    months after the case is closed, …“ insert „If you report in the app without an account, you
    provide no e-mail address and we send no confirmation; if you want a confirmation, use the form
    on our website.“
- **N-379 (R6, six further places):**
  - `datenschutz.md:137`: „Wenn du in der iPhone-App angemeldet bist und zu mindestens einem Haushalt
    gehörst“ → „Wenn du in der iPhone-App mit einem Konto (E-Mail-Adresse, Google oder Apple)
    angemeldet bist und zu mindestens einem Haushalt gehörst“
  - `privacy.md:118`: „When you are signed in to the iPhone app and belong to at least one
    household“ → „When you are signed in to the iPhone app with an account (e-mail address, Google or
    Apple) and belong to at least one household“
  - `support.md:89`: „sobald du angemeldet bist und zu einem Haushalt gehörst:“ → „sobald du ein Konto
    (E-Mail-Adresse, Google oder Apple) hast, angemeldet bist und zu einem Haushalt gehörst:“
  - `support-en.md:89`: „as soon as you're signed in and in a household:“ → „as soon as you have an
    account (e-mail address, Google or Apple), are signed in and are in a household:“
  - `nutzungsbedingungen-pr584.md:33`: „… Einkäufe im Verlauf (die der letzten 4 Wochen), Siri und
    Alexa.“ → „… Einkäufe im Verlauf (die der letzten 4 Wochen) sowie, mit Konto, Siri und Alexa.“
  - `terms-pr584.md:33`: „… shopping trips in the history (those of the last 4 weeks), Siri and
    Alexa.“ → „… shopping trips in the history (those of the last 4 weeks) and, with an account, Siri
    and Alexa.“
- **N-380, `datenschutz.md:228` / `privacy.md:223`, append after „Schreib dafür an
  support@snacklist.app.“ / „Write to support@snacklist.app.“:**
  - DE: „Nutzt du Snacklist ohne Konto oder ist der Browser-Zugang eines Helferlinks verloren
    gegangen, können wir dich regelmäßig nicht als Urheber früherer Einträge erkennen und Auskunft,
    Export oder Löschung nicht zuordnen (Art. 11 DSGVO); zusätzliche Daten zur Identifizierung
    speichern wir dafür nicht. In der App unter Konto bzw. auf der Helferseite unter „Meine Daten“
    und „Löschen“ geht es, solange der Zugang besteht; sonst bitte das Mitglied, das den Helferlink
    geteilt hat, Einträge zu löschen oder den Link zu beenden.“
  - EN: „If you use Snacklist without an account or have lost a helper link's browser access, we
    usually cannot tell that you wrote earlier entries and so cannot assign access, export or
    deletion requests to you (Art. 11 GDPR); we do not store additional data to identify you. In the
    app under Account, or on the helper page under "My data" and "Delete", it works while you still
    have access; otherwise, ask the member who shared the helper link to delete entries or end the
    link.“
  - Support SOP: such requests are answered within one month (Art. 12 Abs. 3), explaining why and
    pointing to the member who shared the link.
- **N-381, `support.md:59` / `support-en.md:59`, append:** DE „Ohne Konto: Mehr › Konto › Liste und
  Konto löschen (nach 90 Tagen ohne Nutzung löschen wir ungenutzte Konten ohne E-Mail-Adresse
  automatisch).“ EN „Without an account: More › Account › Delete list and account (after 90 days
  without use we delete unused accounts without an e-mail address automatically).“ Everywhere the
  button was „Liste löschen“ / „Delete list“, it is „Liste und Konto löschen“ / „Delete list and
  account“ (U5, Konto page, R7).
- **N-387, draft terms, new `§ 14a` before `§ 15`, before `draft: true` goes:** DE `## 14a. Inhalte
  und Meldungen`: „Speichere in Snacklist keine rechtswidrigen Inhalte (zum Beispiel Beleidigungen,
  Drohungen, fremde Fotos ohne Erlaubnis oder geschützte Inhalte ohne Rechte). Wie wir Meldungen
  prüfen, Inhalte entfernen oder Konten sperren und welche Rechtsbehelfe bestehen, steht in den Regeln
  unter [Inhalte melden](/inhalte-melden#regeln). Kontaktstelle für Meldungen und Behörden:
  [support@snacklist.app](mailto:support@snacklist.app).“ EN `## 14a. Content and reports`: „Do not
  store illegal content in Snacklist (for example insults, threats, photos of other people without
  permission or content you hold no rights to). How we review notices, remove content or suspend
  accounts, and what redress options apply are set out under [Report content](/en/report#rules).
  Single point of contact for users and authorities:
  [support@snacklist.app](mailto:support@snacklist.app).“
- **N-388, support FAQ** (`support.md` / `support-en.md`):
  - `support.md:17`: „… Das ist der schnellste Weg.“ → „… Das ist der schnellste Weg. Das geht auch
    ohne Konto; ohne Konto antworten wir nur in der App, solange das Konto besteht.“
    `support-en.md:17`: „… This is the fastest way.“ → „… This is the fastest way. This works without
    an account too; without an account we reply only in the app while the account exists.“
  - `support.md:47`: „Tippe auf **Mehr** und dann auf **Leute einladen**.“ → „Dafür brauchst du ein
    Konto. Tippe auf **Mehr** und dann auf **Leute einladen**.“ `support-en.md:47`: „Tap **More**,
    then **Invite people**.“ → „You need an account for this. Tap **More**, then **Invite people**.“
  - `support.md:51`: „… wählst du gleich nach der Anmeldung **Haushalt beitreten**.“ → „… wählst du
    gleich nach der Anmeldung mit einem Konto **Haushalt beitreten**.“ `support-en.md:51`: „… choose
    **Join household** right after signing in.“ → „… choose **Join household** right after signing in
    with an account.“
  - New FAQ DE: „### Kann ich Snacklist ohne Konto nutzen?“ / „In der iPhone- und Android-App ja.
    Deine Liste ist dann nur auf diesem Gerät. Löschst du die App oder meldest dich ab, ist sie weg;
    nach 90 Tagen ohne Nutzung löschen wir sie. Einladen, Beitreten, Helferlinks, Siri, Alexa,
    KI-Assistenten, API und Snacklist Premium gehen nur mit Konto. Ein Konto erstellst du jederzeit
    unter **Mehr › Konto**; deine Liste bleibt dabei erhalten.“ „### Was ist ein Helferlink?“ / „Mit
    einem Helferlink können andere (zum Beispiel Verwandte) im Browser ohne Konto Einträge zu einer
    einzelnen Liste hinzufügen und eigene noch offene Einträge ändern, ohne Mitglied des Haushalts zu
    werden. Der Link gilt 30 Tage; Mitglieder können ihn unter **Mehr › Haushalt › Helferlinks**
    jederzeit beenden.“
  - New FAQ EN: „### Can I use Snacklist without an account?“ / „In the iPhone and Android apps, yes.
    Your list is then only on this device. If you delete the app or sign out, it is gone; after 90
    days without use we delete it. Inviting, joining, helper links, Siri, Alexa, AI assistants, the
    API and Snacklist Premium need an account. You can create an account any time under **More ›
    Account**; your list stays intact.“ „### What is a helper link?“ / „With a helper link, others
    (for example relatives) can add entries to a single list in the browser without an account and
    edit their own still-open entries without becoming a household member. The link works for 30
    days; members can end it any time under **More › Household › Helper links**.“
  - Existing Lifetime-to-per-account Premium lines in `support.md:59, 63-74` stay under N-335 and
    N-363.
- **N-389, `datenschutz.md:179` / `privacy.md:160`:** DE old „Wenn du es erlaubst, antworten wir dir an
  die E-Mail-Adresse deines Kontos.“ → DE new „Wenn du es erlaubst und dein Konto eine E-Mail-Adresse
  hat, antworten wir dir dorthin; ohne Konto antworten wir nur in der App, solange das Konto
  besteht.“ EN old „If you allow it, we reply to your account's e-mail address.“ → EN new „If you
  allow it and your account has an e-mail address, we reply there; without an account we reply only
  in the app while the account exists.“ The form line is F1 (section 7).

### 13.5 Findings that may conflict with Peter's AN1, PS2 or IH2 picks

Checked against the 375 and 379 briefs (the AN1 picks of Peter and the PM, and IH2's invite hand-off):
no conflict found; no "PS2" source exists. Listed so the lead can confirm. All are taken into the doc as
written by Legal unless the lead says otherwise.

- **N-384** changes who may create a helper link (with `join_approval` on, owners and admins only).
  AN1 4.7 said „any role“ before this change (now fixed in 4.7 and R4). It touches the roles of the member sheet (H1) and of IH2's invite loop if
  that job reuses the sheet.
- **N-385** may change the helper URL shape from `/h/<code>` to `/h#<code>` (or adds headers). It
  touches the deep-link row (DEEP_LINKS.md), the router's `/h/*` rule and the share text H5. Not a
  decision until the build job picks the fragment or the headers.
- **N-381** renames the anonymous sign-out and Konto button to „Liste und Konto löschen“; any PS2 or
  IH2 copy that says „Liste löschen“ for an anonymous user follows it.

### 13.6 Build, operations and lawyer follow-ups

- **Push series (P1, job 377, and the later push jobs):** a push for a helper's add would carry the
  helper label („über Helferlink „Oma Ruth““) and item names in FCM/APNs payloads. That bears on N-383
  (labels with health details) and on R4's list of who sees a label; the push job must decide and
  take it to Legal before helper items trigger a push.
- **N-392:** write and save the LIA notes for P4/P5 and P7; add P1 to P9 to the Art. 30 register
  before launch.
- **N-393:** an app or integration test, like the PostHog test in 4.7(5): no request to RevenueCat
  while `AccountKind == anonymous` (the app calls `RevenueCat.logIn` on a user change, AN1 section 2).
- **N-395:** the incident runbook notes that Art. 34 Abs. 3 lit. c (public communication) applies
  where no contact data exists; the `updateUser(email)` Resend template must contain no promotional
  wording (§ 7 UWG).
- **Needs a lawyer (deferred):** (1) Art. 9 data in shared lists and helper links (N-383,
  *Lindenapotheke* C-21/23); (2) Art. 8 and minors with one-tap start (Q5, N-382); (3) Art. 6 Abs. 1
  lit. f and § 25 TDDDG for a helper's retained browser session (Q1, N-375); (4) incorporation of the
  terms and § 327 Abs. 3 / § 312 Abs. 1a BGB (N-374); (5) DSA scope of helper links, not
  „dissemination to the public“ (N-377, N-387); (6) UWG review of the store phrases (Q8, N-391).
- **What Legal's final hash GO still needs:** the MUST items are in this file (hash in NEEDS_LEAD,
  job 396); the live-file edits wait for AN1-7 and #584.
