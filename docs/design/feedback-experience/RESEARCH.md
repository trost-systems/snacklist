# Job 260, Stage 1: how apps handle in-app feedback, and which tools fit Snacklist

Fetch date for every citation: 2026-11-15. Where a page could not be fetched or did not say, the text says so.
Search snippets (not full page reads) are marked "(search result)".

## 1. Scope and rules applied

Snacklist today: a form under More > Feedback inserts a row into `public.feedback` (Supabase, Frankfurt). Peter reads it in the Supabase dashboard.
Hard rules used as filters below:

1. No bot or US processor reads user feedback or the support mailboxes.
2. Diagnostics are opt-in or minimized.
3. No list contents (item names, store or household names, list screenshots) unless the user chooses it and can preview and remove it before sending.
4. Prefer existing services, but record GDPR fit: EU hosting, DPA, what leaves the device, who can read, consent, retention.

## 2. Patterns in consumer and indie apps

### 2.1 Shake-to-report, menu entry, contextual report

- Instagram "Rage Shake": shaking the phone with the app open brings up a report option where the user describes the problem. Instagram uses reports to prioritize fixes. At launch it was limited to the US on iOS and Android. Source: https://techcrunch.com/2021/11/18/instagram-rolls-out-new-rage-shake-feature-and-the-option-to-delete-posts-from-a-carousel/amp/ (fetched 2026-11-15).
- Instagram also has a non-shake route. A third-party guide (not Instagram's own documentation) names Profile > Menu > Help > Report a problem, with a "Report problem without shaking" option, and says the shake dialog can switch the feature off. Source: search result for "Instagram shake to report a problem" (https://www.lilachbullock.com/how-to-report-a-problem-on-instagram/ and https://techcrunch.com/2021/11/18/instagram-rolls-out-new-rage-shake-feature-and-the-option-to-delete-posts-from-a-carousel/amp/), search run 2026-11-15, pages other than TechCrunch not opened.
- One Peruvian outlet describes Rage Shake as sending an automatic report. The other coverage describes a prompt the user fills in. I treat the prompt version as correct. Source: https://larepublica.pe/tecnologia/2021/11/21/instagram-lanza-nueva-funcion-que-reporta-un-problema-si-sacudes-tu-movil (search result, not opened).
- Firebase App Distribution lets a tester shake the device or take a screenshot to start feedback, or lets a developer add a "Send feedback" menu item. It is a tester tool for pre-release builds, not a consumer Google app feature. Source: https://firebase.google.cn/docs/app-distribution/collect-feedback-from-testers (search result, not opened).
- I found no source showing a shake-to-feedback gesture in Google's own consumer apps. Gmail's feedback is a menu entry. Source: https://support.google.com/mail/answer/9212652 (search result, not opened).
- Bring! (the closest competitor): its App Store listings give feedback@getbring.com for suggestions and support. I found no evidence of an in-app feedback form. Source: https://apps.apple.com/app/bring-shopping-list-recipes/id580669177 (search result, listing text only).
- Not found: how Linear, Things, Todoist, AnyList, Slack, Discord, Arc and Raycast handle in-app feedback. One search for Linear, Things and Todoist returned only comparison blogs. I do not describe them. Per-app help-center lookups were not done.

Observation: the large apps that use shake (Instagram) are big enough to need triage at volume. A menu entry is the common baseline, shake is an optional shortcut, and Instagram offers an off switch for it.

### 2.2 Screenshot annotation and redaction

- Google's feedback flow in Gmail captures a screenshot of the last screen automatically, lets the user choose whether to include it, offers "Highlight or hide info", and lets the user remove the screenshot. Source: https://support.google.com/mail/answer/9212652 (search result summary, page not opened).
- Google's generic feedback tool has highlight and "Black out" tools. Source: https://www.google.com/tools/feedback/intl/en/learnmore.html?authuser=1 (search result, not opened).
- Sentry Flutter: screenshot attachment is off by default ("Because screenshots may contain PII, they are an opt-in feature"). Enabled with `options.attachScreenshot = true` and a `SentryWidget` wrapper. Masking is on by default for screenshots (`maskAllText` and `maskAllImages` default true). Third-party widgets need manual mask rules. Source: https://docs.sentry.io/platforms/dart/guides/flutter/enriching-events/screenshots/ (fetched 2026-11-15).
- Luciq (Instabug): automatic type-based screenshot masking works on Flutter, text input fields are masked automatically, manual private views exist, a known limitation is that very rapid animations may not mask correctly. Source: https://docs.luciq.ai/product-guides-and-integrations/product-guides/luciq-pii-masking (fetched 2026-11-15).
- Apple's Feedback Assistant (for Apple's own software, not apps) attaches a sysdiagnose, which can contain private data such as file paths and IP addresses. Sources: https://developer.apple.com/forums/thread/739560 and https://support.apple.com/guide/feedback-assistant/fbad45b5bb25/mac (search result summaries, not opened).
- Apple's Feedback Assistant now asks for consent to use uploaded attachments for AI training, with on-device training and differential privacy claimed by Apple. Sources: https://appleinsider.com/articles/25/04/18/when-you-report-bugs-on-ios-some-content-may-be-used-for-ai-training and https://heise.de/-10358669 (search result summaries, not opened). Relevance: reporters object when attachments feed AI. This supports the "no bot reads feedback" rule as a trust point.

Observation: the good pattern is preview, then remove or redact, then send, with the screenshot off by default. Auto-masking by widget type is imperfect (Luciq says so itself).

### 2.3 Logs, diagnostics, breadcrumbs, flags

- Sentry Flutter: scrub through `beforeSend` and `beforeBreadcrumb`, or disable logging breadcrumbs. `sendDefaultPii` controls automatic user context. Breadcrumbs, stack locals, HTTP context and transaction names can all contain sensitive data. Source: https://docs.sentry.io/platforms/dart/guides/flutter/data-management/sensitive-data/ (fetched 2026-11-15).
- Luciq SDK collects name, email and IP by default and generates a random per-install user UUID. Source: https://docs.luciq.ai/organization-settings/gdpr (fetched 2026-11-15).
- TestFlight crash feedback includes crash details plus tester comment, with device, OS, build and app version metadata. Source: https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/ (fetched 2026-11-15).
- Not researched in a source: feature flag state in reports. Snacklist already has PostHog flags; sending flag names is a design choice, not something a vendor page settles.

### 2.4 Feature requests and voting

- Canny is the dedicated tool. Free plan: 25 tracked users (anyone who posts, votes or comments), unlimited feedback. Pro from $79/month billed yearly. Source: https://canny.io/pricing (fetched 2026-11-15).
- Canny's "Autopilot AI" is included in all plans: feedback discovery from support tools, deduplication and triage, smart replies that answer posts automatically, comment summaries, and MCP connectors to OpenAI and Claude. Source: https://canny.io/pricing (fetched 2026-11-15). Page does not say whether Autopilot can be turned off.
- Canny's GDPR page returned HTTP 404 at https://canny.io/gdpr. The second pass found the answer on Canny's help center: all data is stored in the United States, and the subprocessors include OpenAI and Anthropic (section 6.3).
- Public voting boards mean users post publicly with a name or avatar. That is a separate product surface and a separate privacy decision from private feedback.

### 2.5 Two-way replies and status

- TestFlight: the Apple page covers viewing, downloading, deleting and disabling feedback. It does not describe replying to a tester. Testers invited by public link are anonymous unless they enter an email for that feedback. Source: https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/ (fetched 2026-11-15).
- Google Play closed tests: the developer sets a feedback URL or email shown on the opt-in page, and testers can also send private feedback through Google Play. A help-page summary says developers read and reply in Play Console. The fetched page 9845334 itself did not describe the reply path. Sources: https://support.google.com/googleplay/android-developer/answer/9845334 (fetched, confirms channel and private feedback) and a search result summary for the reply claim (same URL, https://support.google.com/googleplay/android-developer/answer/14151465, not opened).
- Sentry's feedback form pairs feedback with an event and stores name and email if the user gives them. Replies are not part of the Flutter page I fetched. Source: https://docs.sentry.io/platforms/dart/guides/flutter/user-feedback/ (fetched 2026-11-15).
- For a small app the cheapest two-way channel is an optional contact consent plus email reply by Peter. Snacklist's form already has that consent.

### 2.6 In-app surveys and NPS

- PostHog Surveys: NPS, product-market fit and churn-reason examples, open text. Flutter has its own install guide. Source: https://posthog.com/docs/surveys (fetched 2026-11-15) and https://posthog.com/docs/surveys/installation (fetched 2026-11-15).
- Flutter details: `posthog_flutter` 5.8.0 or later required, 5.14.0 or later recommended. Surveys are on by default (`config.surveys = false` turns them off). `PosthogObserver` must be in navigator observers. Android needs API 26 or higher (the page contradicts itself with 21 and 23 in setup text). iOS 13 minimum. On web, Flutter survey config is ignored and the JavaScript web SDK runs surveys. Source: https://posthog.com/docs/surveys/installation/flutter (fetched 2026-11-15).
- PostHog says "mobile platforms have some limitations" versus web. The list is on the SDK feature support page, which I did not fetch. Source: https://posthog.com/docs/surveys/installation (fetched 2026-11-15).
- Surveys are a good fit for one-question pulses, not for free-form bug reports with context.

### 2.7 Crash-report linking

- Sentry pairs feedback with the original event through `associatedEventId` (or `Sentry.lastEventId`). On iOS and Android with `onErrorSampleRate` set, the SDK buffers up to 30 seconds of session replay and sends it when the feedback form opens or `captureFeedback()` is called. Requires SDK 9.0.0 or later for this. Source: https://docs.sentry.io/platforms/dart/guides/flutter/user-feedback/ (fetched 2026-11-15).
- TestFlight crash feedback is tied to the crash by design. Crash reports can be downloaded for 120 days. Source: https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/ (fetched 2026-11-15).
- Without a crash tool, linking is limited to a self-generated id (for example the PostHog session or a random report id) stored in the row.

## 3. Tool comparison

All "not verified" cells mean the vendor page I fetched did not say.

| Tool | Good at | Flutter | EU hosting and DPA | AI on feedback | Peter as only reader | Free tier / price | Effort vs today's form |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sentry User Feedback | Feedback tied to events and replay, screenshot with default masking | Yes, `SentryFeedbackForm`, `captureFeedback` | EU region Frankfurt (`de.sentry.io`), chosen at org creation, cannot be changed later. Some data always US (accounts, org settings, tokens, support tickets). DPA includes SCCs | AI summaries and categories of feedback exist. Spam detection is an AI classifier, can be turned off per project. Org-wide "Show Generative AI Features" toggle exists. Default state of AI not stated | Yes if AI toggle is off and alerts go to Peter only. Sentry staff access via support is not addressed | Developer plan includes user feedback, 50 replays. Team $29/month | Medium. New SDK init, `navigatorKey`, privacy scrubbing, a second data store |
| PostHog Surveys (EU cloud) | One-question surveys, NPS, targeting by flag or event | Yes (see 2.6), limits on mobile, web uses JS SDK | Cloud EU in Frankfurt (recommended for GDPR). DPA on request path described, SCCs and subprocessors not on pages I fetched | AI features gated by an org owner or admin setting "AI service providers", off until turned on. Providers named in FAQ search result as OpenAI and Anthropic | Yes if AI setting stays off | Free: 1,500 survey responses a month, "DPA on free" (section 6.4) | Low, SDK already in use and consent-gated. Not a bug-report tool |
| Canny | Public boards, voting, roadmap, changelog | No Flutter SDK evidence found. Web widget or link | All data in the US; standard DPA; subprocessors include OpenAI and Anthropic (section 6.3) | Autopilot AI in all plans (dedupe, auto replies, summaries, MCP to OpenAI and Claude). Manual and automated modes, no master off switch found (section 6.3) | Doubtful: auto replies and AI triage are the product's pitch | Free: 25 tracked users. Pro from $79/month yearly | Low for a link, but a US-default vendor with a bot |
| Instabug, now Luciq | Shake to report, repro steps, masking, session replay | Yes (masking page lists Flutter) | DPA party is Instabug, Inc. d/b/a Luciq, San Francisco. "Global data hosting with optional regional pinning", EU not named. Not verified | Rebranded as "agentic mobile observability". AI Privacy page not fetched | Not established | No free tier on pricing page, demo and sales only | High, and cost rules it out |
| Shake (shakebugs.com) | Shake to report, screenshots, crash reports | Yes per search results (SDK list) | Own page: data in AWS Frankfurt eu-central-1. DPA PDF offered. Subprocessors named: AWS, Stripe. A third-party review claims Contabo, conflicting, not verified | "AI debugging" and an MCP server listed in every plan including Free. Whether feedback goes to an LLM and where is not stated | Unclear until AI debugging is understood | Free: 20 bug reports/month, 1 app, 1 month retention, 10,000 installs. Paid from $160/month | Medium. New SDK, retention 1 month on free |
| TestFlight feedback | Screenshot plus comment, crash feedback, device and build metadata, webhook and API | n/a (iOS testers only) | Apple. Not a Snacklist processor choice for end users | None described | Yes, Peter reads in App Store Connect | Free with the developer account | Zero build effort. Testers only |
| Google Play testing feedback | Private feedback channel plus a feedback URL or email on the opt-in page | n/a (Android testers only) | Google. Same remark | None described | Yes | Free | Zero build effort. Testers only |
| Mail delivery (job 225's digest, as built) | Peter reads in his own mailbox, simple | Server side (edge function) | Resend sends from Ireland and keeps mails and logs 30 days in the US (DPF, SCCs); the mailbox is Google Workspace. See 4.1 | None in Resend; Workspace's Gemini and smart features must stay off for the mailbox | Yes, if the mailbox rule holds | Free tiers in use already | Built, off until Legal GO |

Sources for table cells:
- Sentry: https://docs.sentry.io/organization/data-storage-location/, https://sentry.io/legal/dpa/, https://docs.sentry.io/product/user-feedback/, https://docs.sentry.io/product/ai-in-sentry/, https://sentry.io/pricing/, https://docs.sentry.io/platforms/dart/guides/flutter/user-feedback/ (all fetched 2026-11-15).
- PostHog: https://posthog.com/docs/surveys/installation/flutter, https://posthog.com/docs/privacy/gdpr-compliance, https://posthog.com/docs/business-knowledge/ai-data-processing.md (fetched 2026-11-15). Provider names from https://posthog.com/docs/posthog-ai/faq (search result summary, not opened). https://posthog.com/pricing and https://posthog.com/subprocessors returned only navigation text, https://posthog.com/dpa did too, so no pricing, subprocessor or DPA terms are claimed.
- Canny: https://canny.io/pricing (fetched). https://canny.io/gdpr gave 404.
- Luciq: https://www.luciq.ai/pricing, https://docs.luciq.ai/organization-settings/gdpr, https://docs.luciq.ai/product-guides-and-integrations/product-guides/luciq-pii-masking (fetched), https://luciq.ai/dpa (search result, not opened), rebrand to Luciq in September 2025: https://www.businesswire.com/news/home/20250924435921/en/Instabug-Becomes-Luciq.ai-Pioneers-New-Category (search result, not opened).
- Shake: https://www.shakebugs.com/pricing/ and https://shakebugs.com/?p=89 (fetched). Flutter support and the Contabo claim are from search results only: https://www.shakebugs.com/?p=29 and https://toolradar.com/tools/shake.
- TestFlight and Play: https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/ and https://support.google.com/googleplay/android-developer/answer/9845334 (fetched).

Notes on specific tools:

- Sentry: the strongest fit for crash linking, but it adds a new processor. Even in the EU region, org accounts, tokens and support-ticket data are US-stored per Sentry's own page. The DPA relies on the Data Privacy Framework with SCCs as fallback. The DPA does not mention Seer or AI features, so coverage of AI processing is unclear. Source: https://sentry.io/legal/dpa/ (fetched 2026-11-15). Seer is an add-on, and AI Summaries of User Feedback are listed among AI features. Source: https://docs.sentry.io/product/ai-in-sentry/ (fetched 2026-11-15). That page says Sentry does not train generative AI models on your data by default, but does not name LLM providers, EU handling or the default enablement.
- Luciq: I could not confirm EU hosting. I could not confirm a free tier. Both facts rule it out under the "spend no money" and "EU" constraints until Luciq says otherwise.
- Shake: EU hosting is claimed on Shake's own data page, which is a good sign. AI debugging in the free plan is the open question. Ask before use.
- PostHog: surveys are cheap to add given existing consent-gated PostHog, but a survey is not a bug report.
- Canny: free tier counts tracked users, and the product centres on AI triage and auto replies, which conflicts with the "no bot reads feedback" rule.

## 4. Footnotes

### Mail-based delivery

#### 4.1 The mail path Snacklist already has (repo facts, not vendor pages)

- Job 225's daily digest sends new notes to `hello@snacklist.app` through Resend. It ships off until Legal's GO (`docs/FEEDBACK.md`, "Daily digest").
- Resend is Plus Five Five, Inc., San Francisco. It sends from Ireland and stores emails and delivery logs in the US for 30 days. It is DPF-certified with SCCs in its DPA, and the privacy policy already names it for sign-in and waitlist mails (`docs/PRIVACY_DATA_MAP.md` lines 20 and 164; `site/content/legal/privacy.md` §12 and §13). A digest that carries note text, and with FB3 an item name the user kept, puts that content in Resend's US store for 30 days. The policy has to say so before the digest goes on.
- The mailbox `hello@snacklist.app` is on Google Workspace, as a secondary domain (`docs/NEEDS_PETER.md`, job 174). Google is named in the policy. Peter's no-bot rule means that Workspace's Gemini and smart features stay off for that mailbox. This is a setting Peter checks, and FB-Q5 records it as a condition.
- Neither is a new processor for Snacklist, but both are a second place where note content is kept, next to `public.feedback`.

#### Other mail notes

- Bring! lists a plain email address in its store listings (source in 2.1). TestFlight on very old iOS sends feedback by email to the address in Test Information (https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/, fetched).
- Any mailbox with an AI assistant or auto-triage enabled by the mail provider would break rule 1 (see 4.1 for Workspace).
- Mail loses structure (category, version, device context) unless the edge function builds it into the body. It also copies personal data into a mailbox, so retention then lives in two places.

### Self-hosted options

- GlitchTip: the docs list error tracking, performance, uptime, logs and self-hosting. The fetched page did not say whether it supports Sentry SDK feedback, or where the hosted service runs. Source: https://glitchtip.com/documentation/ (fetched 2026-11-15). I do not make claims beyond that.
- Sentry self-hosted: not researched. It needs a server Peter runs and maintains, which adds ops work for a solo developer.
- Both keep data on a server Peter controls and avoid third-party AI, at the cost of ops time.

## 5. Implications for Snacklist

### What we should not copy

- Auto-triage or auto-reply bots on feedback (Canny Autopilot, Sentry spam classifier and AI summaries when left on). They break "no bot reads feedback" or must be verified off first.
- Silent attachment of diagnostics. Apple's own Feedback Assistant attaches a sysdiagnose by default, and developers criticised the AI-training consent next to it. Snacklist should do the reverse: nothing attached unless the user switches it on.
- Auto-captured screenshots of the list. Auto-masking is by widget type and misses third-party widgets (Sentry) and fast animations (Luciq). For a shopping list, the item names are the content, so masking cannot be trusted. The default is no screenshot.
- Default SDK collection of name, email and IP (Luciq's default).
- Public voting boards as the first step. They need a name and a public surface, and the tracked-user pricing makes them paid quickly.
- Shake as the only entry. Instagram keeps a menu route and an off switch. Snacklist's shake implementation is on hold and can stay there.

### What we can reuse

- The existing form and `public.feedback` table: category, message, contact consent, screen name, app version, device context. This is already the pattern the good tools follow (a menu entry, a category, optional contact).
- The Sentry pattern of "screenshot is opt-in, previewable and removable" as a UX model, without the SDK. Gmail's "highlight or hide info" and "remove screenshot" steps are the interaction to copy, with a plain black-out tool as redaction.
- A self-generated report id plus the PostHog session or event id (analytics are consent-gated already) to link feedback to context, only when analytics consent is yes.
- A short, user-visible "what will be sent" preview listing app version, OS and screen name, each switchable. Breadcrumbs, if added, should be a fixed allow-list of action names and never item or household text, as with the analytics allow-list in `app/lib/analytics/events.dart`.
- PostHog surveys (EU cloud) for a one-question NPS pulse, since the SDK and consent are already there. Keep the AI service providers setting off.
- TestFlight and Play private feedback for testers at no cost. Peter reads both himself. Set the Play feedback channel to a Snacklist mailbox.
- Contact-consent plus reply by email for two-way replies. A "we fixed this" status can be a changelog entry on the site, which already exists.

### Constraints that rule options out

- No spend: Luciq (no free tier, sales only), Canny beyond 25 tracked users, Shake beyond 20 reports a month and 1 month of retention, and Sentry beyond the free Developer plan limits.
- No bot or US processor reading feedback: Canny (AI is the product), any tool with AI summaries unless the toggle is verified off, Sentry only with the generative AI toggle off and its US-stored account data accepted, Luciq until EU hosting and AI privacy are confirmed.
- EU hosting: Luciq is unconfirmed, Canny stores all data in the US (6.3), Sentry works only in the EU region and still stores account data in the US, Shake claims Frankfurt but a third-party source conflicts, PostHog EU is Frankfurt.
- Peter as the only human reader: Sentry support-ticket data and any vendor staff access are not covered by pages I read. A vendor dashboard also adds a second place Peter must keep clean. Supabase (already the sole store) and a mailbox only Peter reads satisfy this today.
- Build effort for a solo developer: a full SDK (Sentry, Shake) adds init, scrubbing, a second store and a DPA to track. That only pays off if crash-to-feedback linking is wanted.

### Open questions (not settled by the pages fetched)

1. ~~Sentry DPA and AI default~~ Resolved in 6.1 (partly): the default state and DPA coverage are still not stated on any page fetched; the toggle, EU availability and subprocessors are sourced.
2. ~~Shake AI debugging data flow~~ Resolved in 6.2 (partly): the Sheldon assistant runs on Amazon Bedrock in Frankfurt and AI debugging is listed on the Free plan; on/off default not stated.
3. ~~Canny hosting and DPA~~ Resolved in 6.3: all data in the United States, standard DPA countersigned via DocuSign, subprocessors include OpenAI and Anthropic; Autopilot has a manual/automated mode, no master off switch found.
4. ~~PostHog allowance and subprocessors~~ Resolved in 6.4: 1,500 free survey responses per month; DPA listed as available on the free plan; subprocessor page text not fully read (search result only).
5. ~~How other apps handle feedback~~ Resolved in 6.5 for Linear, Slack, Raycast, Teams, Outlook, Todoist, Discord, AnyList, Bring!, Arc; Things and Google Maps not confirmed.
6. ~~Flutter survey feature support~~ Resolved in 6.4: matrix fetched; Flutter lacks partial responses, shuffle, cancellation events, delay and custom position.

## 6. Second pass (gaps closed)

All pages fetched 2026-11-15 unless marked "(search result, not opened)" or "not found". Vendor statements are vendor claims.

### 6.1 Sentry generative AI

- The org-wide toggle is "Show Generative AI Features" in Settings, General, Organization Settings. Turning it off disables generative AI for the whole organization. Source: https://docs.sentry.io/product/ai-in-sentry.md and https://www.sentry.help/en/articles/13964177-how-do-i-enable-sentry-s-generative-ai-features (fetched 2026-11-15).
- Default state for a new org (on or off): not found. No page fetched says it. The help article is titled "How do I enable ..." and says the feature is turned on in the toggle, which hints at off by default, but the page does not say so. Treat as unknown and check in a real org.
- Plans: the help article says it applies to "All SaaS Customers". Seer is a separate subscription add-on (https://docs.sentry.io/product/ai-in-sentry/seer.md, fetched 2026-11-15). No Developer-plan-specific statement found.
- EU: the help article says generative AI features are available in both the US and EU regions. Data storage options are US (Iowa) and EU (Frankfurt); the storage page says the selection "determines your data storage location only" and does not say whether AI processing stays in the EU (https://docs.sentry.io/organization/data-storage-location.md, fetched 2026-11-15).
- Granularity for user feedback: the toggle controls whether generative AI processes user feedback data for the whole org. Per project, only spam detection can be turned off; feedback titles and labels stay active while the toggle is on. Same help article.
- The user feedback page says that with Generative AI Features enabled, likely spam is moved to a Spam folder, and the feedback index shows AI-generated categories (https://docs.sentry.io/product/user-feedback.md, fetched 2026-11-15).
- Providers: the privacy page says default models are third-party LLMs "hosted within Sentry's production infrastructure and not accessible by the underlying third-party model providers", and that data is not used for training by default (https://docs.sentry.io/product/ai-in-sentry/ai-privacy-and-security.md, fetched 2026-11-15).
- Subprocessor list lists Anthropic, PBC (AI/ML, United States), OpenAI, L.L.C. (AI/ML, United States) and Google Cloud (EU and US) at https://sentry.io/legal/subprocessors/ (fetched 2026-11-15). The list does not say which feature uses which provider.
- DPA coverage of AI features: not found. The AI privacy page does not mention a DPA. Writing to Sentry is the only way to confirm.
- Seer similarity grouping cannot be disabled by customers, per a search result (not opened): https://www.sentry.help/en/articles/13964152-how-do-i-disable-sentry-seer-for-my-entire-organization.

### 6.2 Shake (shakebugs.com)

- Hosting: AWS, "Amazon's private data center in Frankfurt, Germany" (eu-central-1); TLS in transit, AES-256 at rest. Source: https://shakebugs.com/security/ (fetched 2026-11-15). Subprocessors named: AWS, Stripe. DPA PDF linked from https://shakebugs.com/privacy-policy/ (https://shakebugs.com/wp-content/uploads/2024/09/DPA-Shake-1.pdf, link seen, not opened).
- AI assistant "Sheldon": powered by an LLM hosted on Amazon Bedrock in Frankfurt; data not shared with model providers or used to improve their models. Source: https://help.shakebugs.com/en/articles/12298701-privacy-framework-for-sheldon-ai-assistant (fetched 2026-11-15). Default on/off, opt-out, and which data is sent: not stated on that page.
- AI debugging and an MCP server are listed as included on the Free plan and all paid plans: https://www.shakebugs.com/pricing/ (fetched 2026-11-15). The same page gives inconsistent Free report limits (20 per month in one table, unlimited in another). A Shake blog says AI debugging buttons open ChatGPT or Claude with ticket data (search result, not opened: https://feedback.shakebugs.com/changelog). Whether this sends data automatically: not found.
- Data collected by the SDK (Web page): screenshots, recordings, attachments, activity history, email and custom metadata are optional and may hold PII; device and app metadata are collected; city only is read from the IP and the IP is not saved. Source: https://docs.shakebugs.com/docs/web/configuration-and-data/data-privacy-disclosure/ (fetched 2026-11-15). The Flutter disclosure page was not opened.
- Flutter SDK exists: shake_flutter on pub.dev, bug reporting and user tracking, crash reporting marked unavailable (search result, not opened: https://pub.dev/documentation/shake_flutter).

### 6.3 Canny

- Hosting: "Currently, Canny stores all data in the United States" (https://help.canny.io/en/articles/10517591-where-is-canny-s-data-stored, fetched 2026-11-15). The GDPR page says MongoDB Atlas on AWS and that EU residency is not required, with SCCs as the transfer safeguard (https://help.canny.io/en/articles/1876821-is-canny-gdpr-compliant, fetched 2026-11-15).
- DPA: a standard DPA that Canny countersigns via DocuSign; a customized one needs legal review (same GDPR page).
- Subprocessors on that page, each with a DPA and SCCs: AWS, Google Analytics, MongoDB, Sentry, Mailgun, OpenAI (AI-related services), Cloudflare, Anthropic (AI-related services).
- The privacy policy at https://canny.io/privacy (fetched 2026-11-15) names AWS, Stripe, Google and Facebook (remarketing) and says data is transferred to the US; it does not mention a DPA or AI providers.
- Autopilot: admin-only (Owner or Manager). Choice of manual mode (approve in an inbox) or automated mode (inbox becomes an audit log). Fields marked PII are "not processed by AI". Legacy plans include monthly Autopilot credits, extra credits $0.10 each. Source: https://help.canny.io/en/articles/8202451-autopilot (fetched 2026-11-15). A master off switch: not found. The article does not name the AI provider.

### 6.4 PostHog

- Pricing: Free plan includes the first 1,500 survey responses per month; paid use is pay-as-you-go above that. The page ends with "DPA on free" without explanation. Source: https://posthog.com/pricing.md (fetched 2026-11-15). Search result (not opened) gives $0.10 per response from 1,501 to 2,000, then lower tiers: https://posthog.com/surveys/pricing.
- DPA: the /dpa page text was not readable (navigation only). Only the pricing line above supports availability on the free plan.
- Subprocessors: https://posthog.com/subprocessors returned navigation only. A search result summary (not opened) says AWS (US or Germany by cloud region), Wiz, PlanetScale and Modal Labs, dated March 10, 2026, with no OpenAI or Anthropic. Treat as unconfirmed.
- Flutter surveys (https://posthog.com/docs/surveys/installation/flutter.md, fetched 2026-11-15): posthog_flutter minimum 5.8.0 (5.14.0 or later recommended), PosthogObserver must be installed for surveys to show, iOS 13 minimum, Android API 26 per the Limitations section (the setup step says 21 and 23, inconsistent), surveys on by default (`config.surveys = false` disables), Flutter Web uses the JS SDK.
- Feature matrix (https://posthog.com/docs/surveys/sdk-feature-support.md, fetched 2026-11-15). Flutter supports: device-type targeting 5.1.0, repeated activation 5.18.0, intro screen 5.39.0, event trigger property filters 5.20.0, input styling and text colors and thumbs up/down 5.13.0, wait period 5.18.0. Flutter does not support: custom font, custom position, partial responses, auto-submit on selection, link to flag variant, cancellation events, targeting with actions, shuffle questions and choices, delay popup, response length validation, feedback button surveys, URL targeting (each shown as an open GitHub issue or blank). Web has the most complete support.

### 6.5 Other apps' in-app feedback

| App | Entry point | Screenshot and diagnostics | Reply channel | Source (fetched 2026-11-15) |
| --- | --- | --- | --- | --- |
| Linear mobile | Settings tab, "send feedback" | Not stated in the docs page | Not stated | https://linear.app/docs/get-the-app.md |
| Slack mobile | Profile, Notifications, Troubleshoot Notifications, Send a report (a summary, then compose or send) | Mobile logs not stated; desktop attaches logs | "our Support team" | https://slack.com/help/articles/360001559367-Troubleshoot-Slack-notifications |
| Slack iOS beta | `/feedback` command (search result, not opened) | n/a | n/a | https://slack.com/beta/ios |
| Raycast | Send Feedback command, shortcuts for bug and feature (search result, not opened: https://manual.raycast.com/keyboard-shortcuts), or @raycast-feedback which shows a summary to review before sending | Attachments not stated; troubleshooting page suggests "Copy Raycast Logs" (search result, not opened) | Not stated; support@raycast.com, web form, Slack community | https://manual.raycast.com/contact-support |
| Microsoft Teams mobile | Profile, Settings, Help & feedback, Send feedback or Shake and send feedback | Not stated | Not stated; says admin can collect the data | https://support.microsoft.com/en-us/teams/apps-service/give-feedback-in-microsoft-teams |
| Outlook mobile | Side menu, Help & Feedback, Send Feedback (search result, not opened: https://support.microsoft.com/en-us/office/how-do-i-give-feedback-on-microsoft-365-2b102d44-b43f-4dd2-9ff4-23cf144cfb11) | Not stated | Not stated | same |
| Microsoft apps generally | Help or Feedback menu, "Send feedback" | "Depending on the platform ... you might be able to submit more logs and screenshots" | Status visible later in the feedback portal | https://learn.microsoft.com/en-us/microsoft-365/admin/misc/feedback-provide-microsoft |
| Todoist | Web contact form (todoist.com/contact); the form asks for app version, screenshots or recording, platform (search result, not opened, German and Dutch help). Todoist Comms early access has Help & resources, Contact us (search result, not opened). | Screenshots requested, no automatic diagnostics found | Email via the form | https://www.todoist.com/help/articles/contact-todoist-for-help-PcZc394Kj (the page itself shows only login or continue) |
| Discord | Web form dis.gd/bugreport; asks for steps, expected vs actual, version, device | Not stated | Not stated | https://support.discord.com/hc/en-us/articles/360046057772-Discord-Bugs (search result, page returned 403 when opened) |
| AnyList | Email team@anylist.com or a web form; says every message is read and answered | No in-app diagnostics found | Email | https://www.anylist.com/contact and https://help.anylist.com/articles/getting-started/ (search result, not opened) |
| Bring! | Email feedback@getbring.com from the App Store listing; no in-app flow found | Not found | Email | https://apps.apple.com/app/bring-shopping-list-recipes/id580669177 (search result, not opened) |
| Arc | Help center chat button; Help menu "Record Trace" and "Copy Build Info" for crashes; no longer accepts feedback or feature requests, sunset December 22, 2026 | Performance trace | Support chat | https://resources.arc.net/hc/en-us/articles/19335714372759-Basic-Troubleshooting (search result, not opened) |
| Things 3 | Website contact form per App Store listing; no in-app flow found | Not found | Web form | https://apps.apple.com/app/things-3/id904237743 (search result, not opened) |
| Google Maps | Help article describes Menu, "Your opinions about Maps", optional screenshot (computer steps only); a shake setting on iOS and Android is described by third parties only | Optional screenshot | Not stated; "unlikely to be acted on immediately" | https://support.google.com/maps/answer/3094045 (shake to send feedback: not found on Google pages) |

Microsoft Q&A reports the Teams iOS "Shake and send feedback" toggle turns on after each app update, and a Microsoft answer called this expected (search result, not opened: https://learn.microsoft.com/en-us/answers/questions/4428999/iphones-shake-and-send-feedback-toggles-on-everyti).

### 6.6 Two-way status of a user's report

- Windows Feedback Hub: "My feedback" shows status, and a notification arrives when it changes (also for feedback you upvote). Statuses: We've got it, Looking into it, Working on it, Changes made (names the build or app version containing the change), Needs more info. Source: https://learn.microsoft.com/en-us/windows-insider/tracking-feedback (fetched 2026-11-15).
- Microsoft feedback portal: statuses on each card include "We've got it", "We're reviewing this", "We're looking into this", "We need more details", "We're working on this", "We've closed this", "Already supported", "We've made improvements", "Great News! We've fixed this" and "Not right now"; Microsoft can update status and respond, and says it cannot promise to respond to every report. Source: https://learn.microsoft.com/en-us/microsoft-365/admin/misc/feedback-provide-microsoft (fetched 2026-11-15).
- Apple Feedback Assistant: the user guide describes updating or closing your own feedback and a Requests mailbox for Apple's questions; named status labels are not described there (https://support.apple.com/guide/feedback-assistant/fbac981d715d/mac, fetched 2026-11-15). Developer forum complaints of no acknowledgement are in search results, not opened (https://developer.apple.com/forums/thread/795457).
- Discord bug reports: no status shown to the reporter found.

### 6.7 GlitchTip

- Sentry SDK user feedback: not confirmed. A GitLab issue says Sentry's user-feedback submission endpoint "is not yet implemented into GlitchTip" (https://gitlab.com/glitchtip/glitchtip-backend/-/issues/107, fetched 2026-11-15; no date or state visible on the page). The 3.3.0 "feedback survey" in release notes is a survey of GlitchTip users, not an SDK feature (https://glitchtip.com/blog/2023-07-15-glitchtip-3-3/, fetched 2026-11-15). No current documentation page on user feedback found.
- Hosting: US instance app.glitchtip.com on DigitalOcean NYC1; EU instance eu.glitchtip.com on DigitalOcean FRA1, Frankfurt; separate with no replication. Cloudflare for DNS, and as reverse proxy and WAF for EU only; Mailgun; Stripe; Chatwoot support stored in the US. Source: https://glitchtip.com/documentation/hosted-architecture (fetched 2026-11-15).
