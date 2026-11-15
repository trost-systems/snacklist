# Job 263 Stage 1 research: joining a household without "Paste invite"

Date: 2026-11-15. Desk research only: web search and page fetches, no app was installed or driven.
Anything not backed by a source is marked "not verified". Vendor blogs are marked as such because
they sell the product they describe. Repo paths are relative to the job worktree.

## 0. What Snacklist has today (repo facts)

- Join links are `https://app.snacklist.app/join/<code>`. Installed: iOS universal link or Android
  App Link opens the join screen. Not installed: the static join page (`app/web/join/`, no Flutter
  load) shows who invites to what, then the web app. No deferred deep link (`docs/DEEP_LINKS.md`).
- The static join page calls `preview_invite_public`, the only function `anon` may call. It shows the
  inviter's first name only when they set a display name, the household name and kind, member and
  open-item counts, and Premium; never item names. Store buttons and the Smart App Banner are off
  until a listing is public (`storeListings` in `join.js`). Rate limits: 30 per hour per client and
  60 per hour per code, keyed by a salted hash of `X-Real-IP` (DECISIONS "Job 169b: the invite loop,
  wave 2", items 3 and 4).
- Codes: 8 characters from A-Z and 2-9 without I, O, 0, 1, case-insensitive, a dash after the fourth
  accepted (`app/lib/household/pending_invite.dart`). Person invites last 7 days, group links 30
  days, 50 joins, revocable by owner and admins (DECISIONS 169b W2 items 1, 2, 10, 11).
- `PendingInvite` keeps a code on the device through sign-in, the analytics consent, onboarding and an
  app kill, for 7 days. The code never leaves the device and is not sent to analytics.
- Store bridges without SDK: job 169b W2 (DECISIONS item 8) built a Play Install Referrer read on first
  start, but **job 178 removed it** (Legal Review 10 Nov, N-111 MUST; Peter picked "V3 A, no referrer"
  on 10 Nov 20:21; DECISIONS "Job 178", item 2). The read, `play_install_referrer`, `JoinMethod.referrer`
  and the join page's `&referrer=invite%3D<code>` are gone. Legal's reason: a read of the device on
  every first start, also for people who never came from an invite, is not "unbedingt erforderlich"
  under § 25 Abs. 2 Nr. 2 TDDDG, so it would need consent (§ 25 Abs. 1). What remains is "Einladung
  einfügen" (`paste_invite.dart`), which reads the clipboard only on that tap. "No fingerprinting, no
  paid deep-link service" still stands. So **neither platform has a deferred link today**, and any new
  one must start from a user's tap, not from an automatic read.
- A household can confirm joins, then the joiner waits (`join_request_waiting.dart`: "Anfrage
  gesendet", withdraw, or create own household instead).
- Invites are links the user shares; the app never calls `inviteUserByEmail` (`docs/EMAIL.md`, Legal
  N-18). Analytics only after a yes (`docs/ANALYTICS.md`: PostHog EU Cloud, consent first).
- Older notes in `docs/onboarding/research/comparable-apps.md` already say: avoid invite flows that
  need the invitee's existing account or the same email (AnyList, OurGroceries, Listonic), show the
  inviter's name, and do not copy Splitwise's "needs a second person" cliff. This file adds the
  referral-specific mechanics. `docs/onboarding/research/best-practice.md` treats "invite your partner"
  as the commitment step and "partner joined within N days" as the metric to optimise; it found no
  published benchmark.

## 1. How comparable apps onboard an invited person

Public documentation is thin. "Entry" is how the invite travels, "before sign-up" what the invitee
sees before creating an account.

| App | Entry | Before sign-up | Account step | Skips owner's setup | Approval | First screen |
| --- | --- | --- | --- | --- | --- | --- |
| Bring! | Invite by email address from the list ("Invite Friends", long press on a list); link sharing documented for templates, not lists | not verified | Account first | not verified | not verified | The invitation shows inside the app after opening [S1] |
| OurGroceries | Same email address entered on each device; a confirmation email per phone (third-party listing) | n/a | Email is the identity; anonymous without one | n/a (no household object) | Confirmation email click | The shared list [S2, S3] |
| AnyList | Email invite from the list | Email with an app link | Invitee registers with the same email that got the invite; until then the list is not shared [S4] | n/a | None | Shared list |
| Splitwise | Add by email or phone, or "Invite via link" in group settings | Not described for new users; the help page assumes logging into an existing account after opening the link [S5] | Account needed | Yes (group exists) | None found | The group, added to the account |
| Todoist | Invite by email to a project, or a copy-link option; team invite link for teams [S6, S7] | Invite email "with the option to set up a free account" (Todoist help) | Account needed | Yes | Invitee gets Can Edit; team link joins directly | Project; team links: join by clicking "Join" in the project |
| Life360 | A circle member sends a code through any messaging app ("Send Code"); the code expires after 72 hours [S8] | Nothing found | New user creates an account (phone number and email), then enters the code on the next screen; or taps "Get Started" without a code. Existing users: Circle Switcher, "Join a Circle" [S8, S9] | Yes (code field sits in the account setup) | None found | The circle map |
| Tricount | Link (sent by email, SMS, any app); "Join an existing tricount" in app, paste the link [S10] | Only the access link is needed to use a tricount; no login required for use per its FAQ [S10] | No login needed to use; the app asks who you are in the group | Yes | None; anyone with the link has full access [S10] | The shared tricount |
| Cozi | The owner adds a name and email under Family > Settings; Cozi emails the member a verification link; one shared password [S11] | n/a | One family account, shared password, member logs in with own email and the family password | Yes | None | Family calendar and lists |
| Google Family group | The manager enters an email; invitee accepts by email or text while signed in to the right Google account; invitations expire (about two weeks per one secondary source) [S12] | Invitation email | Existing Google account required | Yes | The invitee must accept | Family group |
| Google Keep | Collaborator by name or email, mobile or desktop [S13] | Not verified | Google account | n/a | Not verified | Shared note |
| Notion | Page: share by email, the invitee gets an email and, without account, signs up first. Workspace: a secret invite link from Settings > Members that anyone opens to join as a paid member, can be turned off [S14] | Not verified | Sign up first | Yes | Owner can switch the link off; on Enterprise guest requests need approval | The shared page or workspace |

Patterns worth noting:

1. Email invites dominate (Bring!, AnyList, OurGroceries, Cozi, Google, Notion pages, Todoist, Splitwise by
   email). Snacklist must not copy them: N-18 forbids emailing invitees. Only Life360 (code via any
   messenger), Tricount (link), Splitwise "Invite via link" and Notion/Todoist team links match our
   "user shares a link" model.
2. Life360 is the closest precedent for referred new users: the code field sits inside account
   creation, so the invitee never builds their own circle first, and the code expires after 72 hours.
   Its code length is not verified: official pages do not state it, one third-party guide says six
   digits.
3. Tricount shows the lowest-friction end: link only, no account needed to use it. That works because
   a tricount holds no per-person private data. A household list with RLS needs a user id, so we need
   at least an anonymous or social account; Peter's rule already points to Apple, Google or email.
4. None of the documented flows describes a deferred deep link; for new users they rely on the invitee
   installing the app and then re-opening the email or entering a code/email manually. Life360's help
   says the invitee must "download and install the app and then join a circle using the code"
   [S8 via search summary; official page itself returned 403 to the fetch tool].
5. Approval steps are rare in these apps; Google's family invite and Notion Enterprise have them.
   Snacklist's optional "household confirms joins" is closer to Google's model.

## 2. Deferred deep links (invite opened before the app is installed)

### 2.1 Android: Play Install Referrer (built in job 169b, removed in job 178 on Legal N-111)

- A Play Store URL can carry a `referrer` value; after install the app reads it with the Play Install
  Referrer API (`com.android.installreferrer:installreferrer:2.2`). It returns the referrer string,
  click and install-begin timestamps (client and server), the install version and whether an instant
  experience was launched [S15, S16].
- Google says the information is available for 90 days, does not change unless the app is reinstalled,
  and should be fetched once on first run [S15].
- It is on-device through the Play Store app; no third-party service sees anything. The exact syntax of
  the `referrer` query parameter on a Play URL and its length limit: not verified in Google docs here
  (the search did not return the URL builder page). A Branch guide says it works only if the app is not
  installed and needs a Play Store URL, not a Chrome intent [S17, vendor blog].
- Limit: the link must go through a Play Store URL carrying the referrer. So the join page's Android
  "Get the app" button has to build that URL with `referrer=invite%3D<code>`; a plain
  `https://app.snacklist.app/join/<code>` link tapped by a non-installed user lands on the web page, not
  on Play. The code is in the page, so the page can build the button.
- Snacklist kept the value for 7 days (the invite's life) until job 178 removed the read.
- Legal N-111 (the Legal Review draft of 10 Nov 2026, finding N-111, in the ops research folder)
  objects to the *automatic* read on every first start, not to the API. A read the user asks for
  (a tap on "Ich wurde eingeladen" / "Find my invite" on the first screen) is the case § 25 Abs. 2
  Nr. 2 TDDDG names ("vom Nutzer ausdrücklich gewünschten digitalen Dienst"). Whether Legal accepts
  that is open; the prototypes that use it mark it as a question for Peter and Legal.

### 2.2 iOS: nothing official

- Apple provides no deferred deep link. The Smart App Banner takes an optional `app-argument` that is
  delivered only when the app is already installed and the user taps Open; when it is not installed the
  banner opens the App Store page and the argument is lost (the Apple docs page fetch returned only the
  title; this behaviour is from general knowledge and is widely documented, not verified on Apple's page
  here) [S18].
- Options in use:
  1. Clipboard hand-off: the web page copies the link or code, the app reads the clipboard on first
     launch. Since iOS 16, a programmatic read of the pasteboard shows a "Allow Paste" alert; Apple's
     `UIPasteControl` (iOS 16.0+) lets the user paste without the alert, and reports say the edit-menu
     Paste does not prompt either [S19, S20]. iOS 16.1 added a per-app Allow/Deny setting [S21]. Writing
     to the pasteboard from Safari needs a user gesture on the web side (general knowledge, not
     verified here).
  2. Fingerprint matching (IP, user agent, device model, OS version, screen size) at click time and at
     first launch. Done by the vendors; accuracy on iOS is quoted at 60-85 percent by one vendor blog
     [S22]. Sources disagree on whether Apple allows it: Airbridge says Apple has prohibited matching
     by IP and device characteristics since iOS 14.5; Branch says others continue IP matching for users
     without iCloud Private Relay [S22]. Treat as unresolved. Private Relay shuffles IPs, which hurts
     accuracy.
  3. App Store custom product pages: not verified as a carrier of per-invite data and not useful for one
     code per household; skip.
  4. App Clips: an invocation URL (a QR code, a link in Messages or Safari, NFC) opens a small part of
     the app without installing it, and the clip can hand data to the full app through a shared App
     Group container (third-party sources; Apple's own page text was not returned) [S23]. "Cannot share
     data with other apps" in Apple's snippet means apps other than its own full app. A clip can offer
     Sign in with Apple, so a referred person could join and see the list before installing anything.
     Costs: a second iOS target built and signed with the app, a size limit, a Flutter engine inside it
     (no first-party Flutter support; not verified how large), App Clip experiences configured in App
     Store Connect, and links in WhatsApp do not show the clip card (not verified). It is the only
     Apple-owned way to carry an invite across the install. Prototyped as JH4, not recommended now.
  5. SKAdNetwork: attribution of installs to campaigns, no per-user payload. Not usable.
- GDPR and ePrivacy on fingerprinting: the EDPB Guidelines 2/2023 (version 2.0, adopted 7 October 2024)
  say Article 5(3) of the ePrivacy Directive applies not only to cookies but also to tracking links,
  pixels and other fingerprinting techniques, and that gaining access to information on the terminal
  equipment is enough [S24, secondary summary by Hunton; the EDPB PDF text itself was not read]. Whether
  a click-time IP plus user-agent match for an invite code counts as "gaining access" is a legal
  question for Legal; the cautious reading is that a vendor SDK that matches devices needs consent, and
  consent before the join would be exactly the bundling we want to avoid. Apple additionally treats
  fingerprinting as prohibited and runs the required-reason API declarations to police it [S25,
  secondary]; exact guideline text not verified.

### 2.3 Firebase Dynamic Links

Verified. Google's FAQ: Dynamic Links shut down on 25 August 2025; clicked links return HTTP 404 on
custom domains and on `page.link`; the domains cannot be kept or transferred [S26]. (Branch's blog says
links may still redirect; Google's own FAQ says 404. Google's statement is the authority.) It is not an
option, and a vendor's disappearance is the cautionary tale for relying on a third party for the join
path.

### 2.4 Vendors (what exists in 2026)

| Vendor | Hosting and GDPR | Data that leaves the device | Cost | Down means |
| --- | --- | --- | --- | --- |
| Branch | DPA, SCCs and EU-US Data Privacy Framework certification; "EU Hosted Data" stores data in AWS Ireland, but it is an add-on via sales, log-level data lands in North America first and is then moved, aggregate and account metadata stay in North America [S27, S28] | SDK sends device data and IP; exact field list not verified | Sources conflict: a free tier up to 10k MAU in third-party listings, a reported removal of the free plan in July 2025 on a forum, paid tiers from about 39 to 499 USD per month [S29]; check on Branch's site | Their short link would fail unless links are our own domain with universal links; not verified for Branch fallback |
| AppsFlyer OneLink | DPA incorporated by reference; its FAQ says customer data is stored in the EU; no standalone EU region page found [S30] | SDK; iOS deferred matching relies on IP plus user agent when ATT is declined (secondary sources) [S31] | Not verified | Not verified |
| Adjust | Data Residency (EEA, USA, Turkey) is a paid growth solution via sales, with EU endpoints for deep links `eu.adj.st` [S32] | SDK; attribution data | Not verified | Not verified |
| Kochava | Acts as processor; audited annually per its privacy page (via search); EU residency not verified [S33] | SDK | Free tier with SmartLinks per a third-party listing; reported data-licence condition of the free analytics tier comes from a competitor's page, verify [S33] | Not verified |
| Airbridge | Not verified | SDK | Not verified | Not verified |
| ChottuLink | Page says "hosted on AWS", no region or GDPR statement; $0 plan listed [S34] | Not stated; matching method not stated | $0 listed, limits not stated | Not verified |
| Self-hosted OSS (LinkForty Core AGPL-3.0, blynk-deferlink, `melmathari/deeplink`) | You host it in the EU yourself | They use Install Referrer, iOS clipboard hand-off and probabilistic fingerprint matching as fallback [S35, search summary] | Hosting and maintenance | You own the outage |
| Detour (Software Mansion) | Self-hosting listed as upcoming [S35]; hosting not verified | Not verified | Not verified | Not verified |
| DeepLinkNow, Dynalinks, Linkrunner, Smler, DeepTap | Not verified | Dynalinks describes a fingerprint SDK that matches without user interaction [S22] | Some $0 tiers listed; not verified | Not verified |

Gaps: I did not verify any vendor's published list of collected fields, any Flutter SDK's privacy
manifest, or an EU-company vendor with a deterministic-only iOS method. No source showed an
EU-based service that avoids fingerprinting on iOS; the logic says none can, because iOS offers no
other signal (clipboard excepted).

### 2.5 Assessment for Snacklist

- Peter's rule is to prefer an existing service. Snacklist already runs on Supabase (EU) and PostHog EU
  and treats a new US-parented processor as a cost. The only items a vendor would add over what exists
  is iOS first-open matching, and that is the part that relies on fingerprinting, the legally
  cautious part.
- Fall-back behaviour matters: our links are on our own domain (universal links and web join page), so a
  vendor outage would not break the link, but a vendor SDK on first launch could delay the first screen
  (not verified per vendor).
- No-vendor option for iOS (works with what we have):
  1. The join page offers the store button. After install, the invitee goes back to the message and
     taps the same link: with the app installed it is now a universal link and opens the join screen
     with the code. The page can say so in one line ("Nach der Installation den Link noch einmal
     öffnen"). Zero data leaves the device.
  2. The join page also writes the code to the clipboard on the store-button tap, and the app's first
     screen offers a Paste control that does not trigger the iOS alert (UIPasteControl, via a platform
     view or plugin; Flutter support for it: not verified).
  3. A typed-code field on the first screen replaces the "Paste invite" button, shows the same code
     the join page displays ("ABCD-2345"), and covers every failure of 1 and 2.
- Web-first alternative: let the invitee join on the web (the web app is the product; sign-in with
  Apple, Google or email works there), use the list there, and offer the app afterwards, signing in with
  the same account. Nothing needs to be carried across install; membership is bound to the account.

## 3. Universal Links and App Links when installed

Sources: Linkrunner and Branch pages (vendor blogs, secondary), Apple developer forum threads [S36].

- In-app browsers (Instagram, Facebook, TikTok, LinkedIn, X, Snapchat) use embedded web views, which do
  not hand a tapped link to the system, so the join page loads inside the web view instead of opening
  the app. The workaround vendors name is a landing page with an explicit "Open in app" button; the
  tapped button counts as a user gesture. WhatsApp and iMessage are not in that list in the sources I
  found; whether WhatsApp's in-app browser handles Universal Links: not verified.
- Safari quirk: a link typed or pasted into the address bar does not open the app; a redirect from a
  page may not either; tapping a link on a page does. If the user once chose "Open in Safari" from the
  banner at the top of the page, iOS remembers it for that domain (a vendor blog says Universal Links
  are then off for that domain, until the user long-presses the link and picks "Open in app"). Branch's
  long-press advice is from the iOS 9/10 era; current behaviour not verified.
- Android: App Links need domain verification through `assetlinks.json`; Snacklist's claim files go
  live with the next release upload (`docs/DEEP_LINKS.md`, "Rollout": on 2026-11-10 the live files
  listed only the app id from before the rename). Check whether that has happened before relying on it; otherwise
  installed users get the web page.
- Implication: the join page needs a visible "In der App öffnen" button, which Snacklist's join page can
  carry now: the static page does not load Flutter, so it works inside any in-app browser.

## 4. QR codes

- A QR code scanned with the phone camera opens its URL in the default browser; with the app installed
  the universal link then opens the app (same rules as section 3). With the app not installed the
  invitee lands on the join page, then the section-2 path.
- In-app scanner: one more permission (camera) on first run, one more screen to build, and it only
  helps people who already have the app, who could just tap the link. Its one gain is a person who has
  the app and sits next to the inviter and whose camera app does not offer the link. Pros: no
  clipboard, no typing. Cons: camera permission prompt, accessibility, an in-app scan can also land in
  the household switcher where a typed code already works.
- Splitwise and Tricount: Tricount's QR code is for creating a tricount, not for joining one [S10].
  Notion, Life360 and Splitwise help pages I found do not mention QR for joining. QR use for joining is
  therefore not an established household-app convention; it fits the in-person case (same kitchen).
- Recommendation: keep showing the QR (it encodes the universal link). Do not build an in-app scanner
  in this job.

## 5. Short codes typed by hand

- Snacklist's alphabet (A-Z, 2-9, no I, O, 0, 1) has 32 symbols; 8 characters give 32^8, about 1.1e12
  combinations. With 60 attempts per hour per code and 30 per hour per client already in place,
  guessing is impractical. Case-insensitive input and an optional dash after the fourth character are
  already handled (`normalizeInviteCode`).
- Life360 uses codes with 72-hour expiry [S8]; length not verified (third-party guide: six digits).
  Splitwise's help describes link invites, not typed codes. OurGroceries and AnyList use email as the key.
  I found no further documented typed-code system in the apps above; Notion and Todoist use links.
- Typed codes are the universal fallback: no clipboard, no install carry-over, works from a spoken
  code or a note. Display it grouped ("ABCD-2345") wherever the link is shown (join page, share text,
  QR sheet) so the reader can type it.
- Rate limiting is already per client (salted hash of `X-Real-IP`) and per code.
- Expiry: 7 days for person invites matches a "send now, join this week" pattern; Life360's 72 hours is
  tighter. No change recommended; the group link's 30 days is for clubs.

## 6. Web-app join (today's fallback)

Pros:
- Works on every device and inside any in-app browser; no install, no store; nothing carries across
  install, so no deferred deep link is needed.
- The invitee sees inviter first name, household, member and item counts before any account
  (`preview_invite_public`) and joins from the page; all of that exists.
- A phone user who installs the app later signs in with the same account and finds the household.
Cons:
- Flutter web is heavy to load on phones and is not an installed app: no push, no widgets, no
  voice-assistant integrations (Siri, Alexa) and no persistent session on some browsers (not verified
  per browser). People who bounce there may never install.
- Web sign-in returns to the app URL with a code only the starting browser can redeem (`docs/DEEP_LINKS.md`), so
  the sign-in is bound to that browser: after installing, the user signs in once more in the app.
- Referral via web means the invite should not need a store hop to be useful. That is also the
  argument for making the web path first-class.

## 7. Ordering consent, legal and account creation for a referred user

Proposed order (checks against what the repo says; legal wording is Legal's call):
1. Join page or app link: the invitee sees what the public page may disclose (inviter first name,
   household name, counts, Premium) with a line "Mit Konto fortfahren akzeptierst du die
   Nutzungsbedingungen und die Datenschutzerklärung" next to the account buttons. Terms and privacy
   as a link line next to the primary button is common; whether acceptance by use is enough is
   Legal's question (not verified here).
2. Account: Apple, Google or email (all exist). `PendingInvite` already survives the sign-in (also the
   mobile custom-scheme return that loses the location).
3. Join screen: confirm ("Beitreten zu <Haushalt>") or, when the household confirms joins, the wait
   screen with "withdraw" and "create own household instead".
4. First screen: the household's list, not Step 1 guided start (which is for creating a household).
   For a referred user the guided start's household name, stores and "invite partner" steps do not
   apply: the household exists. One optional line "Einkaufszettel anpassen" later is fine.
5. Analytics consent: today it comes first on a new install, then the link's screen (`docs/DEEP_LINKS.md`).
   GDPR consent must be freely given, specific and not bundled with accepting terms or access to
   the service; asking after the join, or on the first list screen as a non-blocking card with
   equal "Ja" and "Nein", satisfies that more clearly than a gate in front of the invite. This is
   the general rule from the EDPB's consent guidance; the specific EDPB text was not fetched in this
   research (not verified). Note the ePrivacy angle in 2.2: no device matching before the yes.
6. Notification and other permission prompts: only when a reason appears (a partner adds something),
   as in `comparable-apps.md` pattern 8.
7. Metrics must not depend on consent: the app does not log or send the code
   (`PendingInvite`), and join method (`link`, `paste`) already passes the allow-list; any new event
   needs a rule in `app/lib/analytics/events.dart` and a row in `docs/ANALYTICS.md`.

## 8. Implications for Snacklist

Constraints that rule options out:
- N-18: no emails to invitees, so email-first mechanics (AnyList, Bring!, OurGroceries, Cozi, Google,
  Splitwise by email, Notion pages) are out; only the user's own share sheet or Web Share sends.
- The public join page may disclose only inviter's first name, household name, member count, open-item
  count and Premium status. Nothing else is added to it (no photo, no item names, no member names).
- No new US-only processor if avoidable. Branch EU hosting is a sales-only add-on with North America
  intermediate processing; AppsFlyer and Adjust sell EU storage but both need an SDK on every first
  launch. All of the iOS matching vendors use IP and user-agent fingerprinting or the clipboard.
- Fingerprinting needs consent under Art. 5(3) ePrivacy by the cautious EDPB reading, and the consent
  must come before the match, which is before the user has joined: a poor fit.
- Legal N-111 and § 25 TDDDG: no automatic read of the device on first start (install referrer,
  clipboard, a vendor SDK's device data) without consent. A read the user starts with a tap is the
  only consent-free route, and Legal has not ruled on it yet. This also rules out a vendor SDK that
  matches on its own at first launch.
- Hosted third-party links can disappear (Firebase Dynamic Links returned 404 from 25 August 2025);
  keep the join link on our own domain.

What we can reuse:
- `PendingInvite` (survives sign-in, kill, consent, onboarding; 7 days), `inviteCodeIn` (accepts whole
  shared messages, links and codes), the static join page (store buttons and Smart App Banner are
  built and wait for public listings), the QR sheet, universal links and App Links, join approval and
  the waiting screen, rate limits. The removed referrer code is in git history (job 169b) if Legal
  accepts a tap-started read.

What not to copy:
- Email invites, same-email matching (AnyList, OurGroceries), a shared family password (Cozi), a
  mandatory own-household guided start for someone who came to join, a clipboard read on app start
  without a user tap (shows the iOS alert before the user knows why), device fingerprinting.

### Recommendation per channel

- Deferred link, Android: no automatic referrer read (N-111). If Legal accepts a read that the user
  starts ("Ich wurde eingeladen" on the first screen), bring back the job 169b bridge behind that tap;
  until then Android uses the same fallbacks as iOS.
- Deferred link, iOS: no vendor. After the store, "open the same link again" (it is a universal link
  once installed), the join page copies the code on the store-button tap (writing needs no prompt), and
  the app's first screen offers a Paste control that does not raise the iOS alert plus a code field.
  Expect some loss; the code fallback covers it. Revisit a vendor only if the measured share of
  referred iOS installs that fail to join justifies the fingerprinting and consent cost; no number
  exists yet (define it: invite link opened on web page vs joined within 24 hours, on our own join
  records, no extra event).
- Universal links and App Links: keep; add the visible "In der App öffnen" button on the join page for
  in-app browsers; confirm that the live AASA and `assetlinks.json` list `com.snacklist.app` (the file
  was stale on 2026-11-10).
- QR: keep showing it, no in-app scanner now.
- Typed code: keep, grouped as "ABCD-2345", as a visible field on the first screen (replacing the "Paste
  invite" button), with a clear invalid or expired message. Do not shorten the alphabet or length.
- Web join: make it first class: join on the web without installing, then offer the app with the same
  account; it is the one channel that needs no carry-over.

### Overall recommendation

Remove the "Paste invite" button from the start screens and replace it with one line, "Du hast eine
Einladung?", that opens a code field (the typed code plus, on iOS, a no-prompt Paste control; on
Android a referrer read only if Legal accepts it behind the user's tap). Make the join link itself carry the flow: invitee sees who invites
to what on the join page, picks web or the app, signs in with Apple, Google or email with a terms line,
joins without the guided household start and lands on the list, then gets the analytics question as a
non-blocking card on the first list screen. No deep-link vendor, no fingerprinting, no email to the
invitee. The open decision for Peter is whether the iOS loss without a vendor is acceptable; the
fallbacks above (re-open the link, typed code, web join) make it a small loss, but it is not measured.

## Sources (all fetched 2026-11-15)

- S1 https://www.getbring.com/help-center-main-categories/items-lists (search summary only; the page was not opened) fetched 2026-11-15
- S2 https://www.ourgroceries.com/user-guide fetched 2026-11-15 (via earlier research file and search)
- S3 https://alternativeto.net/software/ourgroceries/about (search snippet) fetched 2026-11-15
- S4 https://help.anylist.com/articles/share-list/ fetched 2026-11-15
- S5 https://kb.splitwise.com/groups/how-do-i-join-an-existing-group fetched 2026-11-15
- S6 https://todoist.com/help/articles/360000031079 (search snippet) fetched 2026-11-15
- S7 https://www.todoist.com/help/articles/invite-or-remove-people-from-your-todoist-team-fAfiZjRb (search snippet) fetched 2026-11-15
- S8 https://support.life360.com/hc/en-us/articles/23053441527319-Join-a-Circle and https://support.life360.com/hc/en-us/articles/23053409850647-Add-a-New-Member-to-My-Circle (fetch returned 403; content from search summaries) fetched 2026-11-15
- S9 https://support.life360.com/hc/en-us/articles/23053525850519-Create-a-Life360-Account (search snippet) fetched 2026-11-15
- S10 https://tricount.com/en/do-i-need-a-login-or-account , https://tricount.com/en/how-to-share-tricount , https://tricount.com/link/join (search snippets) fetched 2026-11-15
- S11 https://www.cozi.com/blog/how-to-add-family-to-cozi/ (search snippet) fetched 2026-11-15
- S12 https://support.google.com/families/answer/7103337 (search snippet) fetched 2026-11-15
- S13 https://support.google.com/keep/answer/6101196 (search snippet) fetched 2026-11-15
- S14 https://www.notion.com/help/add-members-admins-guests-and-groups and https://www.notion.com/help/sharing-and-permissions (search snippets) fetched 2026-11-15
- S15 https://developer.android.com/google/play/installreferrer/library fetched 2026-11-15
- S16 https://developer.android.com/google/play/installreferrer/igetinstallreferrerservice fetched 2026-11-15
- S17 https://www.branch.io/resources/blog/technical-guide-to-google-play-referrer/ (search snippet, vendor) fetched 2026-11-15
- S18 https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners (page body not returned; behaviour from general knowledge) fetched 2026-11-15
- S19 https://developer.apple.com/documentation/uikit/uipastecontrol (search snippet) fetched 2026-11-15
- S20 https://www.branch.io/resources/blog/everything-you-need-to-know-about-ios-16-and-pasteboard-opt-ins/ (search snippet, vendor) fetched 2026-11-15
- S21 https://www.macrumors.com/2022/10/17/ios-16-1-paste-from-other-apps-settings/ fetched 2026-11-15
- S22 https://deeplinks.linkrunner.io/glossary/what-is-deferred-deep-linking , https://www.airbridge.io/en/blog/deferred-deeplink-post-idfa-accuracy , https://www.branch.io/resources/blog/how-to-set-up-deferred-deep-linking-on-ios/ , https://docs.dynalinks.app/ios/privacy-compliance (vendor blogs, search snippets) fetched 2026-11-15
- S23 https://developer.apple.com/documentation/appclip (search snippet) fetched 2026-11-15
- S24 https://www.edpb.europa.eu/public-consultations/guidelines-22023-on-technical-scope-of-art-53-of-eprivacy-directive_en and https://www.hunton.com/privacy-and-cybersecurity-law-blog/edpb-publishes-guidelines-to-clarify-scope-of-eu-cookie-notice-and-consent-requirements (summaries) fetched 2026-11-15
- S25 https://developer.apple.com/news/?id=z6fu1dcu (search snippet) fetched 2026-11-15
- S26 https://firebase.google.com/support/dynamic-links-faq fetched 2026-11-15
- S27 https://help.branch.io/docs/eu-hosted-data fetched 2026-11-15
- S28 https://legal.branch.io/saas/dpa-faq/ (search snippet) fetched 2026-11-15
- S29 https://community.flutterflow.io/discussions/post/branch-io-pricing-change-to-499-dollars-per-month-VXz7xJMLnZzYKss , https://toolradar.com/tools/branch/pricing (third-party) fetched 2026-11-15
- S30 https://www.appsflyer.com/product/gdpr (search snippet) fetched 2026-11-15
- S31 https://dev.appsflyer.com/hc/docs/dl_ios_unified_deep_linking and https://dev.appsflyer.com/hc/docs/dl_ios_private_relay (search snippets) fetched 2026-11-15
- S32 https://help.adjust.com/en/article/data-residency (search snippet) fetched 2026-11-15
- S33 https://www.consentstack.io/vendors/kochava and https://www.adjust.com/compare/adjust-vs-kochava/ (third party, competitor) fetched 2026-11-15
- S34 https://chottulink.com/ fetched 2026-11-15
- S35 https://github.com/Newtdev/blynk-deferlink , https://github.com/melmathari/deeplink , https://swmansion.com/blog/deferred-deep-linking-for-mobile-developers-with-detour/ (search snippets) fetched 2026-11-15
- S36 https://linkrunner.io/blog/universal-links-app-links-break-in-app-browsers , https://developer.apple.com/forums/thread/771780 , https://help.branch.io/using-branch/docs/universal-links (search snippets) fetched 2026-11-15
- Repo: `docs/DEEP_LINKS.md`, `docs/DECISIONS.md` (Job 169b), `docs/EMAIL.md`, `docs/ANALYTICS.md`, `docs/onboarding/research/comparable-apps.md`, `docs/onboarding/research/best-practice.md`, `app/lib/household/paste_invite.dart`, `pending_invite.dart`, `join_request_waiting.dart`.
