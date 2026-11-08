# Invite loops, deferred deep links, group switching, per-household pricing (desk research, 2026-11-07)

Method: web search and page fetches only. No installs, no sign-ups, nobody contacted. Every claim
has a URL. Claims with no source, or only a weak one, are marked **unverified**. Vendor marketing
(deep-link SDK sellers, referral-tool sellers) is labelled as such. This report does not repeat
`/home/agents/groceries-ops/jobs/168-onboarding/research/comparable-apps.md`: that file covers
first-run steps, invite placement in onboarding and the email-based sharing of Bring!, AnyList,
OurGroceries and Splitwise.

Hummlist today (repo, for context): invites are 8-character codes, single use, valid 7 days
(DECISIONS "Job 22"). `https://app.hummlist.com/join/<code>` opens the installed app through
Universal Links and App Links. Without the app, the same URL opens the **web app**, which can
complete the join. `PendingInvite` keeps the code through an app kill, but not through an App
Store install (`docs/DEEP_LINKS.md`). `preview_invite` already exists server-side.

---

## 1. Viral invite loops for shared-list and group apps

### 1.1 The arithmetic
- K = i x c: i is invites sent per user, c is the share of invites that convert. K > 1 means
  self-sustaining growth. Cycle time matters as much as K: K 1.2 with a 3-day cycle outgrows
  K 1.5 with a 30-day cycle. K falls as a cohort ages, because the eager sharers invite first.
  "30 % of signups are referred" is a referred-signup ratio, not K. Source (referral-tool vendor
  blog): https://blog.getlaunchlist.com/blog/viral-coefficient-k-factor-guide
- Typical consumer values are said to be K 0.1-0.3, with K > 1 rare. Source: same vendor blog
  and https://userjot.com/tools/viral-coefficient-calculator/description . **Treat as folklore.**
  No primary dataset exists.
- Andrew Chen: each step of the loop leaks. Expect "up to 80% to 90% attrition if you are asking
  them to register for a username/password". The loop works best when the product is itself
  communication. https://andrewchen.com/whats-your-viral-loop-understanding-the-engine-of-adoption/
  Chen's "magic moment" summary: onboarding should create the context for the core value to occur
  "as quickly as possible after a user signs up".
  https://sachinjain024.github.io/awesome-books-mindmap/cold-start-problem/chapters/chapter-04.html
  (book summary, secondary)

The levers for a shared grocery list are:
- **i (invite rate):** whether the product needs a second person. A shared list is pointless alone
  for a couple, so i is high for the first partner. After that, i depends on new groups (family,
  shared flat, club).
- **c (conversion):** friction between tapping the link and seeing the shared list: install,
  account, consent screens. This is the lever Hummlist controls most.
- **Cycle time:** a partner usually joins within hours, so the cycle is short.

### 1.2 Published numbers (what exists, and what does not)
| App | Number | Source |
| --- | --- | --- |
| Dropbox | Two-sided storage bonus (500 MB each). Houston: signups "permanently increased by 60%". 2.8 M referral invites in the first 18 months; ~35 % of signups from referrals at peak. Word of mouth was already about a third of signups before the programme, so the 60 % is not a clean effect | https://www.entrepreneur.com/growing-a-business/how-airbnb-and-dropbox-achieved-tremendous-growth-with/248867 , https://referralrock.com/blog/dropbox-referral-program/ (secondary) |
| Airbnb | Personalised referral landing pages showing the inviter's name and photo. Referrals reportedly raised bookings "by over 25% in some markets". Airbnb did not publish the effect of the photo alone | https://ina-herlihy.squarespace.com/blog/2014/12/21/how-to-optimize-referral-programs (secondary). Primary: https://medium.com/airbnb-engineering/hacking-word-of-mouth-making-referrals-work-for-airbnb-46468e7790a6 (returned 403, not read) |
| Life360 | One subscription covers the whole Circle. New Paying Circles come "primarily" from free members converting, who are "pulled rather than pushed". Q3 2025: 91.6 M MAU, 2.7 M Paying Circles, ARPPC US$137.63/yr. That is ~34 MAU per paying circle, which shows how far free group members outnumber paying groups | https://www.sec.gov/Archives/edgar/data/1581760/000158176022000007/lifx-20220630.htm , https://investors.life360.com/news-releases/news-release-details/life360-reports-record-q3-2025-results |
| Splitwise | Growth "through word of mouth" (CEO). Strategy: the free tier must be useful enough "that users are willing to invite friends without... an overly pushy commercial environment". Free-to-paid conversion has not declined as the base grew. No invite-rate numbers | https://pbn.com/five-questions-with-jon-bittner98206/ , https://techcrunch.com/2021/04/28/splitwise-raises-20m-series-a-to-help-everyone-in-the-world-divvy-expenses |
| Spond | 4 M MAU in 19 countries, >50,000 clubs and teams, ~500,000 users in Germany. No acquisition breakdown | https://stripe.com/en-br/customers/spond |
| Doodle | Every poll shows the product to every participant. 10 M monthly users in 2011. No K published | https://www.startup.ch/Doodle , https://thenextweb.com/news/its-not-sexy-but-it-sure-is-popular-group-scheduling-tool-doodle-hits-10m-monthly-users |
| Notion | Template share-and-duplicate loop. All figures (e.g. "95 % organic") come from secondary blogs | https://blog.vortexsoftware.com/how-notion-cracked-the-template-viral-loop-code (secondary, **unverified** numbers) |
| Bring!, Todoist, Cozi, Tricount | No published invite rate, K or share of members who invite | Gap (Bring! sizes are in the 168 file) |

Bottom line: no shared-list app publishes K or invite-to-join conversion. Hummlist has to measure
its own (PostHog: `invite_created` -> link opened -> `invite_accepted`).

### 1.3 Invite moments
- At or right after the magic moment, and where sharing is useful rather than forced.
  (third-party: https://viral-loops.com/blog/increase-app-downloads/ ; the "don't force virality"
  advice comes from the same family of growth blogs, **weak**)
- Bring! asks for an invite ~28 s into onboarding (in the 168 file). Splitwise and Doodle invite
  *as part of the task itself*: you cannot split a bill or schedule a poll without naming the
  others. For Hummlist, the matching moments are:
  1. Creating a household ("Who shops with you?").
  2. The first item added. The list now has something to share.
  3. Creating a second household (club, family). The invite is the reason to create it.
  4. After a shopping trip ("Lea could have taken the milk"). **Unverified** idea, not from a
     source.
- Doodle and Spond show a second loop: **each invitee sees the product in use**. A club list that
  members open from a link exposes every member to Hummlist.

### 1.4 Invite copy and the landing page
- WhatsApp group link preview: group name, photo, member count, description, then a Join button.
  An admin can reset the link to invalidate it. Sources are secondary guides; the official FAQ
  URL returned "page not found": https://macmyths.com/whatsapp-group-invite-links-how-to-share-manage-and-use-them-safely/
  (**secondary**). This is the model most German users know from group link joins.
- Tricount: anyone with the link gets full access, and joining needs no account. The link page
  offers "open in app" (official FAQ): https://tricount.com/en/who-can-access-my-tricount ,
  https://www.tricount.com/en/do-i-need-a-login-or-account . One user lost all tricounts after
  changing phones without an account, which is the cost of no-account joins:
  https://tricount.com/blog/how-pierre-uses-tricount
- Spond: the group link or a 5-letter code works in the app only, not on the web. The joiner
  installs the app, creates a profile, and an admin approves the request:
  https://help.spond.com/en/articles/25848-spond-app-how-to-invite-new-members-to-a-group-with-a-group-link-code ,
  https://help.spond.com/app/en/articles/130403-join-a-group
- Todoist: "Share Link" copies an invitation link to a project, and invitees always get "Can
  Edit": https://todoist.com/help/articles/use-shared-projects-in-todoist-tzkGUy
- Airbnb named the inviter and showed a photo. Wealthfront deliberately leaves the photo out
  (sensitive context): https://ina-herlihy.squarespace.com/blog/2014/12/21/how-to-optimize-referral-programs
- No published A/B test isolates the effect of showing the inviter's name or a list preview
  (search found only vendor pages). The value is plausible but **unverified**. A/B test it if
  traffic allows.
- Copy pattern seen across these apps (**synthesis, unverified as data**): "<Name> invites you to
  <household> on Hummlist" + what you get ("shared shopping list, live sync") + one button. The
  share-sheet message is written by the inviter, so pre-fill it in the inviter's voice
  ("Hier ist unsere Einkaufsliste: <link>").
- Preview content: showing a few list items before joining leaks household data to anyone who
  holds the link. WhatsApp shows only the name, photo and count. Safer: household name, inviter
  first name, member count, item count ("12 Sachen auf der Liste"), no item names. **Design
  judgement**, not sourced.

### 1.5 Two-sided incentives
- Double-sided give-and-get (a free month each) is the common pattern for consumer apps
  (vendor): https://referralrock.com/industries/consumer-apps/ . Examples: YNAB (friend gets a
  6-week trial, both get a free month when the friend pays): https://ynab.com/referral/ ; Setapp
  (both get a free month after the friend pays): https://setapp.com/news/setapp-launches-a-new-bring-a-friend-program ;
  Roadie (both get a month, only through the in-app link, iOS only):
  https://support.roadiemusic.com/support/solutions/articles/67000715241-how-can-i-refer-a-friend-to-get-free-subscription-
- Apple constraints: 3.1.1 "you must use in-app purchase" to unlock features and "may not use
  [your] own mechanisms to unlock content or functionality". 3.1.2(a) says subscribers must get
  what they paid for without extra tasks such as "posting on social media, uploading contacts".
  The guidelines contain no explicit referral rule.
  https://developer.apple.com/app-store/review/guidelines/ . A server-granted "Premium extended
  for the household" for a referral sits in a grey zone (**unverified** how App Review treats
  it). The safer free routes are StoreKit offer codes or promotional offers, which this research
  did not cover.
- Per-household Premium already *is* a built-in two-sided incentive: a new member gets Premium the
  moment they join a paying household (AnyList household plan and Life360 Circle work this way;
  see section 4). Messaging can say "Premium gilt für alle im Haushalt".

---

## 2. Deep links and deferred deep links without paid SDKs (2025-2026)

### 2.1 Firebase Dynamic Links is gone
- Shut down **25 August 2025**. Links return HTTP 404, the API fails, and `.page.link` domains
  cannot be transferred. Google's guidance: a third-party provider (Adjust, Branch, AppsFlyer,
  not vetted by Google) for full parity, or **App Links + Universal Links** if you only need
  links for installed apps. Google names no free replacement for deferred deep linking.
  https://firebase.google.com/support/dynamic-links-faq
- Many vendors sell themselves as the replacement (AppsOnAir, Airbridge, Linkrunner, Dynalinks,
  Branch...): https://www.branch.io/resources/blog/firebase-dynamic-links-shutting-down ,
  https://linkrunner.io/blog/firebase-dynamic-links-migration-guide-2026-what-to-do-now-that-it-s-shut-down
  (vendor). Hummlist does not need them (below).

### 2.2 Installed app: Universal Links + App Links (Hummlist has these)
- Flutter supports both through its deep-linking support plus the platform cookbooks:
  https://docs.flutter.dev/ui/navigation/deep-linking
- Known iOS gaps: Universal Links do not fire in some in-app browsers (Instagram, Pinterest,
  Telegram are named as not working; WhatsApp works), nor when the URL is pasted into Safari's
  address bar, nor behind click-tracking redirects. If a user once picked "Open in Safari", iOS
  stops opening the app for that domain.
  https://help.branch.io/developer-hub/ios-universal-links.md (vendor docs),
  https://linkrunner.io/blog/why-your-deep-links-break-on-ios-and-how-to-fix-every-failure-mode
  (vendor). Mitigation: the web page at the link needs a visible "In der App öffnen" button and
  must work by itself.

### 2.3 Carrying an invite through a store install: free options
| Option | Platform | How | Cost and limits | Privacy |
| --- | --- | --- | --- | --- |
| **Join on the web first** | all | `/join/<code>` works in the browser. The invitee signs in on the web and joins; the server stores the membership. When they later install the app and sign in with the same account, the household is there | Free. Hummlist already does this. Needs the same sign-in method in both places | None (account data, no device matching) |
| **Play Install Referrer API** | Android | Landing page links to `play.google.com/store/apps/details?id=…&referrer=<url-encoded invite=CODE>`. On first launch the app reads `installReferrer` | Free Google library. Data kept **90 days**, read once after install; Play Store installs only. https://developer.android.com/google/play/installreferrer/library . Flutter wrappers: https://pub.dev/documentation/play_install_referrer/latest , https://pub.dev/documentation/flutter_play_install_referrer/latest/ . Link format: https://dub.co/docs/concepts/deep-links/deferred-deep-linking.md | Deterministic: the string the user's own click carried. No fingerprint |
| **Smart App Banner `app-argument`** | iOS Safari | `<meta name="apple-itunes-app" content="app-id=…, app-argument=https://app.hummlist.com/join/CODE">` on the join page. Apple: after the download "the View button changes to an Open button, and tapping the banner opens the app while preserving the user's content from your website" | Free. Works only if the user goes back to Safari and taps Open. Not shown in in-app browsers or frames. https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners | None |
| **Clipboard handoff** | iOS (and Android) | Landing page button "Code kopieren & App laden" copies the link on a user tap. On first launch the app offers "Einladung einfügen" | Since iOS 16 a programmatic read shows the system "Allow Paste" prompt. A `UIPasteControl` button, the edit menu or a keyboard shortcut does not prompt. iOS 16.1 added a per-app Ask/Deny/Allow setting. https://www.branch.io/resources/blog/everything-you-need-to-know-about-ios-16-and-pasteboard-opt-ins/ (vendor), https://macrumors.com/2022/10/17/ios-16-1-paste-from-other-apps-settings . `detectPatterns`/`detectValues` (`probableWebURL`) read metadata without the prompt, so the app can check first and only offer the paste button when a URL is there: https://developer.apple.com/forums/thread/649996 , https://developer.apple.com/documentation/uikit/uipasteboard/detectionpattern/probableweburl.md . Flutter has no built-in `UIPasteControl`; it needs a platform view or channel (**unverified** that a maintained plugin exists) | Silent clipboard reads on launch look like snooping. Read only after a user tap |
| **Code to type** | all | Landing page shows the 8-character code large; onboarding has "Ich habe einen Code" | Free, robust, some friction. Spond does exactly this (5-letter code) | None |
| **App Clip** | iOS 17+ | A light join experience from the link; data goes to the full app through an App Group container or the keychain (iOS 15.4+) | The size limit is 100 MB for digital-only invocation with iOS 17 minimum, 15 MB for iOS 16: https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes . Flutter supports an App Clip target, with manual Xcode work: https://docs.flutter.dev/platform-integration/ios/ios-app-clip . Handoff: https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app . The invocation URL is not forwarded on install from the card: https://github.com/AppsFlyerSDK/appsflyer-apple-app-clips-sample-app (vendor sample) | None |
| Fingerprint matching (IP + device model + time) | iOS/Android | What paid SDKs used to do | **Not OK.** Apple: "you may not derive data from a device for the purpose of uniquely identifying it… Apps… that reference SDKs (including… Attribution services)… may be rejected". Third-party deferred deep-linking tools need ATT when they create a shared identity across companies: https://developer.apple.com/app-store/user-privacy-and-data-use/ . EU: the EDPB counts fingerprinting as access under ePrivacy Art. 5(3), so consent is needed: https://edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf | Excluded |

### 2.4 Recommendation for Flutter (free)
1. Keep `/join/<code>` as the only invite URL (UL/App Links for the installed app, web join for
   the rest). Make the web join page the "landing page": inviter, household, Join button.
2. On that page, offer three ways forward: **"Im Browser beitreten"** (done in seconds; then
   "Hol dir die App" with the account already a member); **"App laden"**; and the code shown
   large with "Code kopieren".
3. Android: the store button carries `&referrer=invite%3D<CODE>`. On first launch, read it once
   with a Play Install Referrer plugin and put it into `PendingInvite`.
4. iOS: add the Smart App Banner with `app-argument=<the join URL>` on `/join/*`. On first launch
   without an account, the onboarding offers "Einladung einfügen". It checks the pasteboard with
   `detectPatterns` (native channel, no prompt) and reads it only on a tap. Typing the code stays
   as the fallback.
5. No App Clip for now: it means Xcode target maintenance and a second binary under a size limit,
   for a step the web join already covers.
6. No fingerprinting, no paid SDK. The referrer and clipboard values are the user's own click, so
   no consent banner is needed for this. Analytics events on top stay consent-gated as today.

---

## 3. Switching between groups (household switcher UX)

| App | Where the switcher lives | Activity per group | Source |
| --- | --- | --- | --- |
| Slack | Desktop: workspace icon top-left opens a list, or a persistent sidebar of workspace icons (Cmd/Ctrl+Shift+S), drag to reorder. Mobile: swipe right on Home, tap a workspace | Article does not mention badges | https://slack.com/help/articles/1500002200741-Switch-between-workspaces |
| Discord | Left rail of server icons; white dot = unread, red badge = mentions; "Mark as read" | User threads only (forum) | https://support.discord.com/hc/sv/community/posts/360051295334-Disable-unread-indicators-on-dock-taskbar-icons-and-server-list-icon-in-notification-settings |
| Notion | Desktop: click the workspace name in the sidebar to get a list; shortcut Ctrl+Shift+number | Not documented | https://www.notion.com/help/create-delete-and-switch-workspaces |
| Todoist | Compact picker: "My Projects" (personal) vs a named team, checkmark on the current one. A team is "completely separate" from the personal space | Not documented | https://screensdesign.com/articles/mobile-workspace-team-switcher-ux/ , https://techcrunch.com/2024/02/07/todoist-adds-team-workspaces-to-its-task-manager |
| Other apps (Runway, Photoroom, Craft, UNUM…) | Bottom sheet listing workspaces with a "Current"/checkmark, plan or role and member count. "Even a one-entry picker benefits from stating that the visible item is already active"; "Keep switching separate from moving content and changing account"; "Do not leave a new team label over old team data, even briefly" | n/a | https://screensdesign.com/articles/mobile-workspace-team-switcher-ux/ |
| Splitwise | Groups tab lists each group with its balance; sort by recent activity is reported. Layout descriptions conflict across sources | Activity feed + push | https://robots.net/fintech/how-to-create-a-group-on-splitwise/ (secondary, **unverified**) |
| Bring! | Several lists, each shared with different people; switching by voice "ändere meine Liste auf Zuhause" (Alexa). In-app switcher UI not documented | Activity log, messages and emojis to list members | https://apps.apple.com/de/app/bring-einkaufsliste-rezepte/id580669177 , https://www.homeandsmart.de/alexa-skill-bring-einkaufsliste-per-sprache-verwalten-499098 , https://getbring.com/blog-posts/your-activities-at-a-glance |
| AnyList | A "Lists" screen of lists; sharing is per list; folders need Complete. One household per subscription | Push when a list is shared | https://help.anylist.com/articles/duplicate-list , https://help.anylist.com/articles/share-list/ |
| Cozi | **No switcher**: one family account per email. "Please do not use the same e-mail address in more than one Cozi account" | n/a | https://www.cozi.com/help-mobile-email-addresses/ |
| Life360 | Several Circles are normal ("Each Circle operates independently") | Not researched | https://www.life360.com/en-mx/learn/how-many-members-life360-circle |
| Spond | Groups and subgroups, links per group | Not researched | https://help.spond.com/app/en/articles/131166-invite-and-add-members-to-main-groups-and-subgroups |

Patterns:
- **Top-left name or avatar that opens a list** (Slack desktop, Notion, Todoist): best for 2-5
  groups. It shows the current group name all the time, which Hummlist needs because the list
  screen must say whose list it is.
- **Bottom sheet with checkmark, role and member count** (most mobile apps): fits Flutter's modal
  sheet. The repo rule `popups-on-root-navigator` applies.
- **Swipe** (Slack mobile): hidden. Bad for a grocery list, where horizontal swipes already mean
  item actions (**judgement**).
- **Rail of icons** (Discord, Slack desktop sidebar): only for many groups and power users.
- **Activity per group**: dot for unread (Discord white dot, red badge for mentions). For a list:
  "3 neu" since last visit on each household row. Sources only show that the pattern exists, not
  that it works better.
- **Default on launch**: no app documents it. Last used is the common behaviour (**unverified**).
  The Bring! voice switch hints at a "current list" state kept per user.
- **Never show the old group's data under the new name** (screensdesign). In Hummlist this is the
  known "shell state survives household switch" trap (memory note): key the list state on the
  household id.

---

## 4. Pricing per household or group vs per user

| App | Model | Price | Several groups? | Source |
| --- | --- | --- | --- | --- |
| AnyList Complete | Individual or **household** | US$9.99/yr individual, US$14.99/yr household. Upgrade "will unlock all of the premium features… for the other members of your household"; members must have accounts and are added on mobile only. No member cap stated | One household per subscription; behaviour for someone in two households **not documented** | https://www.anylist.com/complete , https://help.anylist.com/articles/individual-household-upgrade , https://help.anylist.com/articles/add-household-user |
| Bring! Premium | Per account (**unverified** whether it covers list members) | DE App Store: €9.99/yr, €1.99/month. Main benefit: no ads (2020 article at €13.99/yr) | Lists are free and unlimited; sharing is free | https://apps.apple.com/de/app/bring-einkaufsliste-rezepte/id580669177 , https://www.mobiflip.de/?p=401895 |
| OurGroceries | Per account, **benefit spills over**: upgrading "will also get rid of the ads for everyone you are sharing your lists with" | ~US$1/month, US$6/yr, US$20 lifetime; varies by country; 7-day trial; sharing never needs upgrade | n/a | https://www.ourgroceries.com/user-guide |
| Cozi Gold | Per family account | US$39/yr ("Accessible by everyone in the family") | One family per email | https://www.cozi.com/cozi-gold/ |
| Life360 | **Per Circle** ("Each subscription covers all members in the payor's Circle") | Silver US$79.99/yr, Gold US$149.99/yr, Platinum US$249.99/yr (secondary); ARPPC US$137.63 | Membership is tied to a circle; users can be in several circles; which circle is covered: **unverified** | https://www.sec.gov/Archives/edgar/data/1581760/000158176022000007/lifx-20220630.htm , https://northlabapps.com/blog/is-life360-free/ (competitor blog) |
| Splitwise Pro | Per user | US$4.99/month or US$39.99/yr (not on Splitwise's own page); free tier capped at ~3-5 new expenses/day, number not official | Pro is for the person, across all groups (**unverified**) | https://www.splitwise.com/pro , https://getfinny.app/blog/splitwise-pricing-2026 (secondary) |
| Todoist | Per user; teams per seat | Pro US$5/month (yearly); Business US$8 per user/month (yearly), every member gets Pro; free: 5 projects, 5 people per project | Personal space + team workspaces | https://www.todoist.com/pricing |
| Notion | Per member of a workspace; guests free | Plus €9.50, Business €19.50 per member/month | Each workspace is billed separately | https://www.notion.com/pricing |
| Spond (clubs) | **Free app**; earns on payments | e.g. Norway 2.99 % + NOK 2 + NOK 27 per membership fee; club website add-on ~€15/month (aggregator) | Unlimited groups | https://help.spond.com/en/articles/25998-spond-is-free-to-download-and-use , https://help.spond.com/en/articles/58192-transaction-costs-for-payments-made-in-spond-club |
| TeamSnap (teams) | **Per team**; clubs custom | Basic ~US$69.99/yr per team; clubs/leagues from ~US$599/yr (aggregators conflict) | Per team | https://go.secondslide.io/teamsnap-pricing (mirror), https://toolradar.com/tools/teamsnap/pricing (aggregator) |

Platform mechanics:
- **Apple Family Sharing for subscriptions** is opt-in per subscription and covers up to five
  family members besides the organiser. It follows the Apple family, not the app's household.
  Reports say it cannot be turned off once on (**unverified**).
  https://developer.apple.com/news/?id=ksfkdwpr
- **RevenueCat**: an entitlement belongs to an App User ID. Using the household id as the App
  User ID makes Premium follow the household; that is Hummlist's job-43 design. Store-account
  overlap (one Apple ID buying for two App User IDs) is handled by the project's
  "restore/transfer" setting.
  https://community.revenuecat.com/general-questions-7/1-store-account-multiple-app-user-id-with-different-subscription-plans-7410
  (forum, staff replies)

What happens with several groups (synthesis):
- Per-group pricing (Life360, AnyList household, TeamSnap) means Premium in household A does
  nothing in household B. Users understand it when the UI says so on the switcher row
  ("Premium" badge per household). **No source** documents how these apps explain it.
- Per-user pricing (Splitwise, Todoist Pro) means Premium follows the person into every group.
  That works against "the household pays once" and does not spread to members.
- Clubs: the market pays per team or group (TeamSnap) or not at all with payment fees (Spond).
  Per-member pricing is only used by B2B tools (Notion, Todoist Business). Per-member pricing for
  a 40-member club list would be an outlier.

---

## Gaps
- No primary invite-rate, K or invite conversion figure for any shared-list app.
- No measured lift for showing the inviter name or a list preview on the landing page.
- How Life360 and AnyList handle a user in two paid groups is not documented.
- Whether App Review accepts a server-granted Premium extension as a referral reward is not
  documented.
- Bring!'s current invite-link UX and whether Premium covers list members: not found.

---

## Implications for Hummlist

1. **Measure our own K.** Instrument `invite_created` -> join page opened (web, anonymous count,
   no consent needed for a server counter) -> `invite_accepted`, per invite moment. No benchmark
   exists to borrow (section 1.2).
2. **Conversion (c) is the lever.** Keep the join path to: link -> household page -> Join ->
   sign-in -> list. Chen's 80-90 % registration loss argues for sign-in as late as possible and
   for one-tap Apple/Google sign-in on the join page.
3. **The web join is our free "deferred deep link".** `/join/<code>` already works in the
   browser. Make it the main path, and offer "App laden" only after the join succeeds. The
   account then carries the household into the app, with no install attribution needed.
4. **Add the two free store bridges.** Android: Play Install Referrer
   (`&referrer=invite%3DCODE`, read once, 90 days). iOS: Smart App Banner `app-argument` on
   `/join/*`, plus an "Einladung einfügen" button that checks the pasteboard with `detectPatterns`
   and reads it only on a tap. Keep the typed code as the fallback. No App Clip, no paid SDK.
5. **Never fingerprint** (Apple's developer agreement, EDPB Art. 5(3)). The referrer and
   clipboard paths are deterministic and user-initiated, which keeps the GDPR story simple.
6. **Landing page: inviter first name, household name, member count, item count. No item names.**
   WhatsApp-style preview; showing items would leak a household's data to anyone with a forwarded
   link. A/B test the name once traffic allows.
7. **Reconsider single-use invites for the club case.** WhatsApp, Tricount, Spond and Todoist use
   reusable group links, with reset/revoke (WhatsApp) or admin approval (Spond). A household
   could have one reusable link for clubs and the current single-use 7-day code for partners.
   This needs the rate limit and a "who joined" list.
8. **Invite moments:** at household creation, after the first items, and as the reason to create
   a second household. Pre-fill the share-sheet text in the inviter's voice. Hummlist still never
   sends anything itself (legal rule).
9. **Switcher: household name top-left of the list, opening a bottom sheet** with a checkmark,
   member count, a "Premium" badge and "n neu" per household, plus "Haushalt erstellen" and
   "Mit Code beitreten". No swipe switching. Open the last-used household. Key all list state on
   the household id so old data never shows under the new name.
10. **Price per household, as now (job 43)**, the model of AnyList household, Life360 Circle and
    Cozi Gold. Say "Premium gilt für alle im Haushalt" on the paywall and the join page. That
    makes every paid household a two-sided incentive without a referral program, and avoids the
    App Review grey zone of server-granted rewards.
11. **Multiple households make per-household Premium visible.** Show Premium per household in the
    switcher and do not move it with the user. Offer a later "Premium for all my households" only
    if users ask (**untested**; no competitor documents it).
12. **Clubs: do not price per member.** The comparable market is per team or group (TeamSnap) or
    free (Spond). A flat per-household Premium, perhaps a "club" tier later, fits. The viral value
    of a 40-member club list (every member sees Hummlist, as with Doodle polls) is worth more
    than seat fees.
