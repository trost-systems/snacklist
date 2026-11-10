# Privacy policy draft for job 169b (several households, invite loop)

Status: DRAFT for Legal. The texts are `site/content/legal/datenschutz.md` (binding) and
`site/content/legal/privacy.md` (translation). Facts come from the branches `job/169b-households-p2`
(PR #327, wave 1), `job/169b-w2` (wave 2, PR #332 at `bb37668e`) and `job/169b-w3` (wave 3, PR #333 at
`a09c8701`), contracts in
`docs/households/W1.md`, `W2.md` and `W3.md`. Migrations:
`supabase/migrations/20261108125048_households_multi.sql` (W1),
`20261108133253_households_invite_loop.sql` (W2), `20261108144409_households_lists.sql`,
`20261108144410_households_claims.sql` and `20261108144412_households_join_approval.sql` (W3).

The draft also holds a data processing agreement for clubs: `site/content/legal/avv.md` (German,
binding) and `site/content/legal/dpa.md` (English). Both carry `draft: true`: the site build turns
every file in `site/content/legal/` into a page, and a draft page is left out of Vercel production
builds (404 on snacklist.app, not in the footer, sitemap or llms.txt); preview and local builds show
it with the draft banner and `noindex`. Nothing links to them.

## Changes

| Section | Change | Fact behind it | Proposed legal basis |
| --- | --- | --- | --- |
| Head | Stand / Last updated 8 November 2026, `updated:` 2026-11-08 | Placeholder, see question 10 | none |
| 3 | Device storage: lists (plural), the household last opened on this device, an opened invite until joining | W1 device cache per user and household; `DeviceCache` keys `invite.pending`, `invite.referrer_read` | § 25 Abs. 2 Nr. 2 TDDDG (unchanged) |
| 5 | Several households; household kind if given; roles and join dates; members of one household don't see your others; default household chosen by the user, first one until then | W1 migration: `household_members.is_default`, insert trigger, `households.kind`, `my_households()`, `household_members_of()` | Art. 6 Abs. 1 lit. b |
| 5 | Several lists per household (name, order, creator, created); deleting a list deletes its items | W3 `lists` table, `items.list_id` with `on delete cascade`, `create_list` / `delete_list` | Art. 6 Abs. 1 lit. b |
| 5, new paragraph | "Ich bringe das": who brings which item, optional amount, all members see it with the display name; ends on take-back, tick, item or list delete, leave, removal, account deletion | W3 `item_claims` (RLS `is_household_member`), triggers `items_end_claims`, `household_members_end_claims`, foreign keys `on delete cascade` to `items` and `auth.users`. Update 2: each claim has its own random id as primary key, so a Realtime delete event carries only that id and tells no other household who held it. No text change | Art. 6 Abs. 1 lit. b |
| 5, new "Rollen und Einladungen" | Owner ("Hauptadmin"), admins, removal of members, owner succession | W2: `set_member_role`, `remove_member`, succession in `leave_household_as` / `delete_account` | Art. 6 Abs. 1 lit. b |
| 5, new paragraph (update 2) | Removal records: household, removed user, time. For 30 days invites made before the removal and invites from plain members don't let the person back in; only a new owner/admin invite does. No member sees them in the app. Deleted after 30 days, on that rejoin, with the account or the household; in the removed user's export | W2 `household_removals` (no grant to clients; written by `remove_member`, read by `check_invite`, `claim_invite` deletes on join), daily `purge_household_removals` (pg_cron `purge-household-removals`, 03:47 UTC, `removed_at` older than 30 days); W3 `decide_join_request` deletes it on approval; DECISIONS 169b invite loop item 10; `docs/PRIVACY_DATA_MAP.md` | Art. 6 Abs. 1 lit. f (question 26) |
| 5 | Replaces "Einladungslinks laufen nach 7 Tagen ab und gelten nur einmal": person link 7 days, one use; group link 30 days, 50 joins, owner/admins only, and only they can revoke it (update 2); Snacklist sends no invites (N-18) | W2: `invites.kind`, `max_uses`, `create_invite` intervals 7 / 30 days; `revoke_invite` answers `not_admin` to a member for a group link (DECISIONS item 11). Old store builds read `invites` directly; its select policy now shows person invites only, so they never list a group link (no text change) | Art. 6 Abs. 1 lit. b |
| 5 | Per invite: creator, expiry, join count, join-page open count (no identities); per join: invite and time, shown to members under "Wer ist beigetreten"; deleted when the member leaves or is removed | `invites.use_count`, `preview_count`; table `invite_uses`; trigger `invite_uses_end_with_membership` (W2 commit `cc18547a` on `job/169b-w2`). Update 2: the app refreshes "Wer ist beigetreten" by asking the server every 5 s while the panel is on screen; `invite_uses` and `household_members` are not in the Realtime publication, because Realtime sends delete events to every subscriber regardless of RLS and would have told every signed-in user when someone left (DECISIONS item 13). No text change | Art. 6 Abs. 1 lit. b |
| 5, new paragraph | Join approval ("Beitritte bestätigen"): owner/admins switch it on, on from the start for club households; a join request stores requester, household, invite, time, decision, when and who decided; only the requester and owner/admins see it, with the requester's display name; open until decided or withdrawn, decided ones deleted after 7 days by a daily job. Update 2: a membership closes the user's open request for that household, however they got in; after a decline the user can ask the same household again only after 24 hours, checked against the stored decision time (no new field) | W3 `households.join_approval` (on for new `kind = 'club'` in `create_household`), `join_requests` (RLS: own row or `is_household_admin`), `household_join_requests()` returns `display_name`, `purge_join_requests` (pg_cron `purge-join-requests`, 03:47 UTC); trigger `join_requests_close_on_join` on `household_members` insert (W3 DECISIONS item 8); `claim_invite` answers `declined_recently` while a decline is under 24 hours old | Art. 6 Abs. 1 lit. b (question 16) |
| 5 | Public join page: inviter's first name (only with a display name of their own), household name and kind, member and open-item counts, Premium; never item names, emails or ids | `preview_invite_public()` (anon), `app/web/join/` | Art. 6 Abs. 1 lit. f (question 1) |
| 5 | Rate limit: salted SHA-256 of `X-Real-IP` and of the code per hour, with a count; no raw IP; past hours deleted at the next join-page request | `invite_preview_rate`, `invite_preview_salt`, `invite_preview_hit()`; the delete runs at the top of `preview_invite_public()` | Art. 6 Abs. 1 lit. f (question 2) |
| 5 | Android Install Referrer read once at first start; only the invite code and the click time are kept, on the device | `app/lib/household/install_referrer.dart` (`inviteInReferrer` reads only `invite`; `clickedAt` dates the pending invite) | Art. 6 Abs. 1 lit. b; § 25 Abs. 2 Nr. 2 TDDDG (question 4) |
| 5 | "Einladung einfügen" reads the clipboard only on that tap and keeps only an invite link or code | `app/lib/household/paste_invite.dart`, the only `Clipboard.getData` in `app/lib` | Art. 6 Abs. 1 lit. b; § 25 Abs. 2 Nr. 2 TDDDG (question 5) |
| 7 | Access tokens bound to their household; an OAuth connection works in the default household, sees names and member counts of the others and can act in them when the service names one | W1 `create_personal_access_token(..., p_household)`; `supabase/functions/mcp/tools.ts` `households()` (OAuth: all, token: its own), `household` argument | Art. 6 Abs. 1 lit. b (question 7) |
| 7 Siri | Token works while member of at least one household, acts in the default, follows a changed default; ends when leaving the last household; suggestions are item names of the household open in the app | W1 migration lines 655-770 (Siri tokens follow `is_default`, revoked only without any membership); `app/lib/list/list_scope.dart` builds `SiriSuggestions` from the open list | Art. 6 Abs. 1 lit. b (question 6) |
| 7 Alexa | "aktuellen Haushalts" becomes the default household | `householdOf()` in `supabase/functions/_shared/db.ts` reads `is_default` | Art. 6 Abs. 1 lit. b |
| 8 | Export holds all households, the invites joined through, the lists created, the claims, the join requests, the removal records (update 2) and each added item's list | `export_my_data()` in the W3 join-approval migration (`households`, `invite_uses`, `lists_created`, `item_claims`, `join_requests`, `household_removals`, `items_added[].list`) | unchanged |
| 14 | Account deletion also deletes the join records, claims and join requests; leaving or a removal deletes the join record and the claims in that household; a deleted household takes its lists, invites, join requests and join records with it; join-page check values after the hour, decided join requests after 7 days | `invite_uses`, `item_claims`, `join_requests` foreign keys `on delete cascade` to `auth.users` and `households`; the W2 and W3 triggers on `household_members` delete. Update 2: removal records go with the account and the household (`household_removals` foreign keys `on delete cascade`) and after 30 days | unchanged |

## Open questions for Legal

1. Join page. Anyone holding a link sees, signed out, the inviter's first name, the household name
   and kind, member and open-item counts and Premium. We propose Art. 6 Abs. 1 lit. f. Is that
   right for the inviter's first name, or does it need lit. b (they created the link) plus a hint
   in the invite sheet that the page shows their first name? The app shows no such hint today.
2. Rate-limit hashes. The salted hash of the IP address is pseudonymous personal data. Is lit. f
   with the wording in section 5 enough? The rows of past hours are deleted only when the next join
   page is requested, so with no traffic they stay longer than an hour. The draft says so
   ("beim nächsten Aufruf einer Beitrittsseite"). If you want a hard bound, we would add a scheduled
   cleanup (a code change, not in this draft).
3. Join records after leaving. Answered by a code change: leaving or a removal now deletes the
   member's `invite_uses` row for that household (trigger `invite_uses_end_with_membership`, W2
   commit `cc18547a`; pgTAP "her join record goes with the membership"). Sections 5 and 14 say so;
   the earlier sentence that the record stays is gone. Update 2: a removal now leaves a different
   record, `household_removals` (question 26).
4. Install Referrer. Is reading it at first start covered by § 25 Abs. 2 Nr. 2 TDDDG (the user
   tapped a join link to join), or does it need consent? Is Google an independent controller for
   it and belongs in section 12? The path is only reached once the Play listing is public and the
   join page shows its "App laden" link.
5. Clipboard. The read happens only on the user's tap of "Einladung einfügen". Same question:
   § 25 Abs. 2 Nr. 2 TDDDG, or no § 25 case at all?
6. Siri suggestions come from the household open in the app, while Siri writes into the default
   household. The draft describes this as it is. If the two should match, that is a code change.
7. AI connections (OAuth/MCP) reach all of the user's households when the service names one. The
   consent screen says only "Arbeitet in deinem Standard-Haushalt: <Name>" (`consentDefaultHousehold`).
   Should the consent screen say that the other households are reachable too?
8. Section 9 (analytics) lists actions and properties as examples. W1/W2 add the events
   "Haushalt gewechselt" and "Mitglied entfernt" (no properties), the invite's kind and context,
   the join methods "referrer" and "paste", the role "admin" and where a household was created.
   None carries names or text. W3 adds "Liste angelegt", "Liste gewechselt", "Ich bringe"
   (`item_claimed` with role and household size), "Beitritt angefragt" and "Beitrittsanfrage
   entschieden" (`approved` true or false), again without names, items, amounts or the household
   asked. The draft leaves section 9 unchanged; do you want them listed?
9. Section 14 says a Lifetime household is deleted when its last member leaves. The code
   (`leave_household_as`) can archive a Premium household on leave when the user asks and the
   `household_archive` switch is on. This predates 169b; please check the sentence.
10. Date. "Stand" is set to 8 November 2026 as a placeholder. The text describes W1 and W2, which
    are not in a store build yet. It should go live with the release that ships them.
11. Household kind. The server stores it, the join page and share texts use it, but no app screen
    asks for it yet (job 168 will). Keep the sentence now, or add it with job 168?
12. N-18. The draft says "Snacklist verschickt keine Einladungen". Please confirm the wording.
13. Lists created by a member who leaves. `lists.created_by` is nulled only on account deletion. A
    member who leaves stays the stored creator of lists they made in that household (not shown in
    the app, but in the table the other members can read). Fine, or should leaving null it as well?
    Section 14's sentence on what stays after leaving ("ohne Bezug zu dir") predates 169b and
    speaks of items; the same question applies to `items.added_by` on leave.
14. Claims in the export. `item_claims` in the export carries the item's name, which other
    members may have written. We think that is the user's own data in context (what they promised
    to bring). Agree?

26. Removal records (new in update 2). When an owner or admin removes a member, we keep household,
    user and time for 30 days, so the person can't walk back in through the group link still in
    the club's chat or through an invite a plain member made for them; a new invite from the owner
    or an admin lets them in and deletes the record. We propose Art. 6 Abs. 1 lit. f, the
    household's interest that a removal holds. Is that the right basis, and is it the household's
    interest or ours? Is 30 days right? It matches the longest invite (group link, 30 days); after
    that a plain member's invite works for them again. The removed person is not told why an old
    link fails (the app shows the message for a revoked link). Does Art. 13/14 need more than the
    sentence in section 5, for example a hint in the app when someone is removed? The draft AVV
    (section 5 of `avv.md` / `dpa.md`) now lists removals among the household data it covers,
    which fits the club's interest reading; with our interest they would come out of it.
27. Rejoin after a decline (update 2). A declined user can ask the same household again only after
    24 hours. This uses the decision time already stored with the request (deleted after 7 days),
    so no new data. Section 5 now says so. Fine?

## Open questions for Legal: data processing agreement for clubs

15. Role. Is Snacklist a processor for the club at all? Every member has their own account and their
    own contract with Snacklist; the club has no contract with Snacklist and pays nothing unless a
    member buys Premium for the household. The draft takes the view in `docs/households/W3.md` (the
    club that puts members' names on a shared list is the controller for the household's content)
    and leaves accounts, analytics, support and purchases with Snacklist as controller. Is that split
    sound, or are the members individual users and Snacklist the sole controller (then no AVV, and
    the privacy policy covers clubs as it is)? A third reading is joint control (Art. 26) for the
    household content.
16. Join-request decisions. The table keeps who decided and when for 7 days, then the whole request
    goes. Does a club need a longer log of who let whom in (for its own accountability), or is the
    short window right because it minimises data? If a club needs a log, should it be the club's
    instruction (a setting) rather than our default?
17. Conclusion. Is a click-through AVV acceptable: an owner or admin of a club household accepts it
    in the app, and we store who accepted it, for which household, which version and when? No such
    screen or table exists today; the draft is text only. Who may accept for a club (the household's
    owner is a person, not necessarily the club's board)?
18. Ending and deletion. There is no "delete household" action: a household is deleted when its last
    member leaves (or archived, for Lifetime). Section 13 says Snacklist deletes the data when the
    contract ends; today that would be a manual delete by Peter, removing the household for every
    member. Acceptable, or do we need an owner action "Haushalt löschen" first?
19. Return of data. Section 13 promises the household's data as JSON on request. The app's export
    covers only the requesting user's own data; a household export would be manual (SQL by Peter).
    Acceptable for a draft, or should an owner export exist before the AVV goes live?
20. Sub-processors. The draft lists Supabase, Vercel and GitHub, which hold or carry household
    content. PostHog (household id with the member's consent), RevenueCat (household id for
    Premium) and Google Workspace (support mail) are left out as Snacklist's own processing. Agree?
    Is the 30-day objection period with a termination right enough for Art. 28 Abs. 2 Satz 2?
21. Who has access. Section 8 says only Peter Trost and the automated processes he set up reach the
    data outside the app. Development and operations also use AI coding agents run by Peter on his
    own servers, some of which hold production credentials (deploys, logs). Are those covered by
    "automatische Abläufe", or does the AVV (and section 12 of the privacy policy) need to name the
    model provider as a sub-processor?
22. TOMs. Section 9 lists only facts from the repo (Frankfurt database, TLS, RLS with pgTAP cases,
    hashed passwords and tokens, age-encrypted backups for 90 days, 1-day database logs, CI gates).
    Encryption at rest at Supabase and access logging are not stated because we have not verified
    them in this repo. Is a short list in the contract enough, or do you want a separate TOM annex?
23. Audits. On-site audits with 14 days' notice: with a one-person provider, can we limit audits to
    written information and certificates of the sub-processors, once a year, unless there is a
    breach?
24. Liability. Section 15 is statute only (Art. 82 DSGVO), no cap and no Kardinalpflichten clause
    (K.13.S). Please confirm.
25. Publication. Should the AVV be a page at all (`/avv`, `/en/dpa`, both drafts today), or a PDF
    sent on request? The privacy policy would then need a sentence for clubs.
