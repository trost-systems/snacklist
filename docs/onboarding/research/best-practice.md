# Job 168: onboarding, contextual hints and consent-gated UX data: best practice

Web research, 2026-11-07. Scope: activation (A), good friction (B), progressive onboarding (C),
consent and legal bases under GDPR and TDDDG (D), contextual hints (E), notification priming (F).

How to read this:

- Every claim has a source URL. **Primary** means a regulator, a law, a court, a platform
  guideline (Apple, Google), a peer-reviewed paper or NN/g. **Vendor** means a company that sells
  onboarding, push or analytics tools; its numbers come from its own customer base and are not
  independent.
- **[unverified]** marks a claim I could only find in secondary sources (blogs, summaries,
  community posts) or could not check against the original. Do not quote these numbers as fact.
- **[assessment]** marks my own reasoning or legal reading. Section D is not legal advice; the
  table there is a starting point for the privacy policy review, not a sign-off.
- Hummlist context used: the current flow is sign-in, then the analytics question, then
  welcome / create household (name, stores) / invite partner, then the list
  (`.cursor/skills/verify-hummlist/features/onboarding.md`). A one-card tip queue already exists
  (`features/tips.md`, job 80). PostHog runs only after an explicit yes, personless, with an
  event allow-list (`docs/ANALYTICS.md`).

---

## A. Activation for collaborative / list / household apps

### Definitions that hold up

- **Activation metric** = "the earliest point in your onboarding flow that, by showing your
  product's value, is predictive of long-term retention". Lenny Rachitsky's three-step method:
  brainstorm candidate aha moments from usage data, look for an inflection in retention
  (regression), then run experiments, because "a good activation metric is causal for your
  retention, not just correlative".
  <https://www.lennysnewsletter.com/p/how-to-determine-your-activation> (partly paywalled; the
  multiplayer deep dive in it is behind the paywall, I did not read it).
- **Setup, aha, habit** (Reforge's model, as Elena Verna, ex-Miro/Amplitude/SurveyMonkey growth,
  describes it, Oct 2023): setup = "the necessary actions to get to the core value prop"; aha =
  "when the user has received and *realized* the core value"; habit = repeating the aha at the
  product's natural frequency. She warns against counting setup steps as value.
  <https://www.elenaverna.com/p/hey-b2b-i-bet-you-are-measuring-activation>
- **Multiplayer activation.** Verna: activation should be measured for the team, not the
  individual; at Miro "an account wasn't considered activated until collaboration occurred";
  users who never collaborated were "stuck in setup". She suggests making "invite another user"
  a setup step and structuring the aha around two people doing complementary jobs (one creates,
  the other views or reviews). Same source.
- **Atomic network** (Andrew Chen, *The Cold Start Problem*, 2021): the smallest group of users
  for which the product works and people stay; "tool first, network later" products (his Dropbox
  example) are useful alone and better together.
  <https://www.lennysnewsletter.com/p/atomic-network>. Hummlist is the extreme case: the atomic
  network is two people in one household.
- **Classic examples** (all **[unverified]**, they circulate through secondary sources only):
  Facebook "7 friends in 10 days", Slack "2,000 team messages" (with "93% of those teams still
  using Slack"). <https://medium.com/parsa-vc/how-to-discover-your-apps-aha-moment-5f75dd7b6536>,
  <https://www.goodreads.com/notes/56962799-the-cold-start-problem/84411704-mikko-ikola/435bc888-c6a7-45f1-83c2-6c66617e1ab2>.
  Verna's point applies: "7 friends" is arguably a setup milestone, not the aha.

### Benchmarks

| Metric | Number | Source | Quality |
| --- | --- | --- | --- |
| Activation rate, 500+ products | mean 34 %, median 25 %; SaaS mean ~36 %, median 30 % | Lenny Rachitsky and Yuriy Timen survey, via <https://www.lennysnewsletter.com/i/77646597/what-is-activation-rate> and <https://gigazine.net/gsc_news/en/20221114-good-activation-rate> | survey of self-reported numbers; definitions vary per company |
| "Users who activate should retain at least 2x better than those who don't" | rule of thumb | attributed to Rachitsky in secondary summaries; the readable part of his post only shows a 2x example (two orders vs one) | **[unverified]** as a general rule |
| Day-7 "return" rate | 7 % returning on day 7 puts a product in the top 25 %; median enterprise product 2.1 %, top 10 % 12.4 %; 69 % of top day-7 performers were top performers at 3 months | Amplitude 2025 Product Benchmark Report, 2,600+ companies, <https://www.amplitude.com/blog/7-percent-retention-rule> (2025-09-30) | vendor; mixes web, B2B and mobile, so far lower than mobile-app retention tables below |
| Mobile app retention, all categories | D1 ~26 %, D7 ~13 %, D30 ~7 % | attributed to Adjust, via <https://trysonar.app/blog/app-user-retention-benchmarks-and-what-moves-it> and <https://getstream.io/blog/app-retention-guide> | **[unverified]**: I could not open the Adjust or AppsFlyer tables themselves |
| Utilities / productivity apps | D1 24-28 %, D7 11-17 %, D30 7-9 % | same two secondary sources; they disagree with each other | **[unverified]** |

There is no published benchmark for "partner joined within N days" in household apps that I
could find. The only "2x retention when a teammate joins" claims I found were on template or
vendor glossary pages without methodology (**[unverified]**,
<https://saber.app/glossary/onboarding-metrics>).

### Time to value

- Apple HIG: onboarding should be "fast, fun, and optional"; "Postpone nonessential setup flows
  or customization steps. Provide reasonable default settings so most people can immediately
  start interacting." <https://developer.apple.com/design/human-interface-guidelines/onboarding>
  (change log: updated 2024-06-10).
- Material (Quickstart model): "Start the user directly in the app", prioritise the first key
  action, "Don't force education upfront".
  <https://m1.material.io/growth-communications/onboarding.html> (older Material 1 guidance; no
  Material 3 equivalent found).

### Implications for Hummlist

- **[assessment]** Hummlist's aha is two-sided: *"something my partner added shows up on my
  phone"* or *"what I ticked off disappears on theirs"*. A solo user who adds 20 items has done
  setup, not the aha. Count activation per **household**, not per user (Verna, Miro).
- Proposed candidate metric to test against `retention_weekly.sql`: **household activated = within
  7 days of household creation, a second member joined AND each member did at least one write
  (add or tick) that the other saw**. Cheaper proxy: "2 members + at least 5 items added + at least
  1 tick-off by a member other than the adder within 7 days". Validate with Rachitsky's method
  (does the activated cohort retain clearly better, then an experiment), not by assuming it.
- Track the funnel as setup (household created, stores picked) -> invite sent -> invite accepted
  -> first cross-member sync -> week-2 return. The invite-accepted step is the one to optimise;
  everything before it is setup.
- Solo value matters too (Chen's "tool first"): a single user must get a good list on day 1, since
  the partner may join days later. Measure "solo D1 value" (first item added, list used in a store)
  separately from multiplayer activation.
- Treat published D7 numbers only as a sanity range (roughly 10-17 % for utilities, **[unverified]**).
  Our own baseline from PostHog consented users is the real reference, with the caveat that
  consenting users are a biased sample.

---

## B. Good friction: when extra steps help, and when they hurt

### Evidence that well-chosen steps help

- **Headspace x Irrational Labs** (primary case study by the behavioural-science firm that ran
  it): adding a short quiz about meditation experience and goals, *even when everyone then got
  the same Basics course*, raised course starts from 31.25 % (control) to 62.97 %. Questions alone
  vs "default to basics" added 7.6 points. A precommitment step (pick days and a trigger) raised
  app opens by 7.5 % and unique open days by 4 %. **But** average active days did not differ
  significantly in any variant; the precommitment effect faded after 2-3 days. Sample size not
  published. <https://irrationallabs.com/case-studies/headspace-doubled-course-starts/>
  Take-away: a few questions raise perceived fit and first action; they do not on their own build
  a habit.
- **IKEA effect** (Norton, Mochon, Ariely, *Journal of Consumer Psychology* 22(3), 2012): people
  value things they assembled themselves more, **but only if they complete them**; when the
  creation failed or was destroyed, the effect disappeared.
  <https://dash.harvard.edu/handle/1/12136084>
- **Labor illusion** (Buell and Norton, *Management Science* 57(9), 2011): when a service shows
  the work it does ("operational transparency"), people value it more and can even prefer a
  longer wait. <https://ideas.repec.org/a/inm/ormnsc/v57y2011i9p1564-1579.html>
- **Endowed progress** (Nunes and Drèze, *Journal of Consumer Research* 32(4), 2006): a loyalty
  card with 2 of 10 stamps pre-filled was completed more often than an empty 8-stamp card (field
  study, 300 car-wash customers). The often-quoted "34 % vs 19 %" is **[unverified]**, I could not
  open the paper. <https://knowledge.wharton.upenn.edu/podcast/knowledge-at-wharton-podcast/the-lowdown-on-customer-loyalty-programs-which-are-the-most-effective-and-why/>
- **Duolingo**: Gina Gotthilf (ex-VP Growth) on record: "Simply moving the sign-up screen back a
  few steps led to about a 20 % increase in DAUs"; later soft sign-up walls added 8.2 % DAU; hard
  walls without soft walls first "perform significantly worse". Goal setting during account setup
  "moved the needle" (no number given).
  <https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker>
  That is friction *removed* before value, and friction (goal setting) *added* after.
- **Moderate friction maximises LTV** (Jon Martinez, five onboarding friction tests): moderate
  friction gave the highest lifetime value, heavy friction collapsed conversion. Practitioner
  write-up, no full method. <https://techcrunch.com/2023/06/06/you-need-to-add-some-friction-to-your-growth-funnel/>
  **[unverified]** as a general result.
- **Noom** (113-screen web funnel) and claims that long quizzes lift trial starts (Lose It!, Cal AI)
  are frequently cited; I found no published controlled result. **[unverified]**.
  <https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel>

### Evidence that friction hurts

- **Account walls before value**: Baymard reports 18 % of US shoppers abandoned an order because
  the site wanted them to create an account (checkout context, not apps).
  <https://baymard.com/blog/reduce-cart-abandonment>. Duolingo's 20 % DAU gain above is the app
  analogue.
- **Irrelevant questions**: Material: "Don't ask for preferences that can be garnered from normal
  usage"; keep self-select choices on one screen and fewer than ten.
  <https://m1.material.io/growth-communications/onboarding.html>
- **Too much teaching**: Apple HIG: "if you try to teach too much, people can feel overwhelmed
  and may be less likely to remember what they learned."
  <https://developer.apple.com/design/human-interface-guidelines/onboarding>
- A growth-marketplace case reports conversion fell "by over 80 %" after a friction-loaded
  onboarding, while survey-based matching later raised activation. Single vendor blog,
  **[unverified]**. <https://www.growthmentor.com/blog/user-onboarding-friction>

### The pattern across sources [assessment]

Friction pays when the step (1) visibly changes what the user gets next (personalisation that
shows up on the next screen), (2) is a commitment the user makes for themselves (goal, plan,
invite), or (3) is the user building something they will own (IKEA effect), and it is finished.
Friction hurts when it is (a) a wall before any value, (b) a question whose answer the user never
sees used, or (c) long enough that people drop out before completion.

### Implications for Hummlist

- Keep the store picker: it is good friction by every criterion above (the answer immediately
  orders the list, the household "builds" its list, it is one screen, it can be skipped). Show the
  payoff right after: the first list already grouped in their stores' order (labor illusion: "Wir
  sortieren deine Liste nach REWE, dm, ...").
- Treat **"invite your partner"** as the commitment step. Keep it in onboarding, skippable, and
  re-offer it from the list (empty state, one hint) because the aha depends on it.
- Candidate question with visible payoff: **"Wie viele Leute kauft ihr ein?"** only if it changes
  something (e.g. default quantities or the invite copy). If it changes nothing, it is research,
  not setup, and belongs in a later optional survey (see D).
- Consider a **pre-filled starter list** (a few typical items the user can keep or remove) as
  endowed progress plus learning by doing: the first list is never empty, and ticking an item
  teaches the gesture. Test it; do not assume it.
- Biggest structural friction today is sign-in before any value. A guest/local list before
  sign-up (Duolingo pattern) is a large architectural change for a synced, household-scoped app
  (RLS on `household_id`); flag it as a separate decision, not part of this job.
- Do not copy Noom-length flows: Hummlist is a utility; the evidence for long quizzes is from
  paid health/coaching products with a paywall at the end, and it is mostly unverified.

---

## C. Progressive onboarding vs upfront tours

### Evidence

- **NN/g, "Onboarding Tutorials vs. Contextual Help"** (Page Laubheimer, 2023-02-12): "Tutorials
  interrupt users, don't necessarily improve task performance, and are quickly forgotten"; "we
  find that users frequently skip them"; "Users want to start using the product right away."
  Recommends pull revelations (help triggered by a signal the user would benefit), "Make it easy
  to dismiss (and recall) the help content", "Skip the obvious stuff."
  <https://www.nngroup.com/articles/onboarding-tutorials/>
- **NN/g, "Mobile-App Onboarding: An Analysis of Components and Techniques"** (Alita Kendrick,
  2020-06-21): deck-of-cards (carousel) tutorials can make a simple interface look harder and
  strain memory; "Even if users decide to skip your onboarding, they still have to click or tap
  to do so"; "Interactive walkthroughs enable users to learn by doing"; test the app without
  onboarding first and add it only if a prototype improves results.
  <https://www.nngroup.com/articles/mobile-app-onboarding/>
- **Apple HIG Onboarding**: "Teach through interactivity"; "Consider providing a collection of
  context-specific tips instead of a single onboarding flow"; if a tutorial is skipped, "don't
  present it again on subsequent launches, but make sure it's easy for people to find".
  <https://developer.apple.com/design/human-interface-guidelines/onboarding>
- **Tour completion by length** (vendor data):
  - Produktly, 464 SaaS companies, Jan-Jun 2026: median completion 73 % for 1-2 step tours, 38 %
    for 3-5, 25 % for 6-8, 8 % for 9+; user-started tours 69 % vs auto-started 23 %; tooltips
    ("smart tips") median 0.1 % opens per impression.
    <https://produktly.com/research/saas-onboarding-benchmarks-2026>
  - Chameleon, 15 M interactions: average tour completion 61 %; self-serve (user-started) tours
    123 % higher completion; checklist-triggered tours 21 % more likely completed.
    <https://www.chameleon.io/blog/product-tour-benchmarks-highlights>
  - Intercom: 5-step tours median completion 34 %.
    <https://www.intercom.com/help/en/articles/3027087-see-how-your-product-tours-are-performing>
  - Caveat from Produktly itself: users who start a tour themselves were already interested, so
    the gap is not all causal.
- **Checklists**: beyond Chameleon's 21 % figure I found no independent checklist benchmark.
  Endowed progress (section B) is the mechanism usually cited for "pre-ticked first item".
- **Empty states as onboarding**: widely recommended (explain why it is empty, show the next
  action), but the sources are design blogs and design systems, not studies, e.g.
  <https://smashingmagazine.com/2017/02/user-onboarding-empty-states-mobile-apps>. One design
  system cautions they are "not a replacement for onboarding experiences" (ServiceTitan Anvil,
  <https://anvil.servicetitan.com/docs/web/patterns/empty-states>).
- **Vendor case** (**[unverified]**, vendor-published): Trainual moved video tutorials into
  in-context hotspots and reports activation +100 %, conversion +80 %.
  <https://appcues.com/examples/trainual-video-tutorials>

### Implications for Hummlist

- No carousel and no multi-step tour at first start. Hummlist's core interactions (type, tick)
  are conventional; NN/g says skip help for conventional patterns.
- **Learning by doing** for the one unconventional thing (tap ticks, long-press edits, drag):
  the existing gesture card ("Tippen hakt ab · Halten bearbeitet") is the right idea; better still
  if the first list has an item to try it on (starter item or the user's first item).
- **Empty list = onboarding surface**: the empty list should show the next action (add the first
  item, invite the partner if alone) instead of a blank screen.
- If a checklist is used, keep it to 3 items with the first already done ("Haushalt erstellt ✓",
  "Ersten Artikel hinzufügen", "Partner einladen"), dismissible, gone once done. Treat it as an
  experiment against no checklist.
- Everything taught in onboarding must also be findable later (Apple, NN/g): the tips should be
  re-readable under More / Help.

---

## D. Consent UX and legal bases (GDPR + TDDDG)

### The rules that matter

1. **§ 25 TDDDG (device access)**: storing information on, or reading it from, the user's device
   needs consent unless it is "unbedingt erforderlich" so the provider can supply a digital
   service the user has expressly requested (§ 25 Abs. 2 Nr. 2).
   <https://www.gesetze-im-internet.de/ttdsg/__25.html>, <https://lxgesetze.de/tdddg/25>.
   It applies to apps as well as websites, and to any information, personal or not.
2. **DSK, OH Digitale Dienste v1.2 (Nov 2024)**, the German supervisory authorities' reading:
   - The service is split into a base service and add-on functions. Add-ons (the DSK lists
     language settings, push messages, log-in areas, consent management, wish/favourite lists)
     are "wished" only once the user actually uses them (Rn. 74, 76).
   - "Unbedingt erforderlich" is read strictly as *technically* necessary; economic necessity for
     the business model does not count (Rn. 78).
   - Storage may only start when the function is used, and only as long and as much as needed;
     a preference can be stored as a non-identifying value like `language: de`, without a user ID
     (Rn. 79-81, 95).
   - Measurement / analytics and A/B tests are "not per se" part of the base service; the DSK
     refuses a blanket statement that reach measurement is exempt and says it depends on the
     exact configuration and purpose (Rn. 77, 87-90).
   <https://datenschutzkonferenz-online.de/media/oh/OH_Digitale_Dienste.pdf>
3. **EDPB Guidelines 2/2023 on the technical scope of Art. 5(3) ePrivacy** (final v2.0, adopted
   2024-10-07) read "gaining access" broadly (covers SDKs, pixels, fingerprinting-like reads).
   <https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf>
4. **Art. 6(1)(b) contract** (EDPB Guidelines 2/2019, final): processing must be *objectively
   necessary* for the contract. Para 48-49: collecting "details of user engagement" and processing
   "for the purposes of improving a service or developing new functions" is generally **not**
   covered by 6(1)(b); use legitimate interest or consent. Para 57: personalisation can be
   necessary when it is "an intrinsic and expected element" of the service, judged by the nature
   of the service, the average user's expectations and whether the service works without it.
   <https://www.edpb.europa.eu/sites/default/files/files/file1/edpb_guidelines-art_6-1-b-adopted_after_public_consultation_en.pdf>
   The CJEU confirmed a strict reading of 6(1)(b) in *Meta v Bundeskartellamt*, C-252/21,
   2023-07-04 (<https://privacymatters.dlapiper.com/2023/07/eu-cjeus-landmark-decision-in-meta-vs-bundeskartellamt/>).
5. **Art. 6(1)(f) legitimate interest** (EDPB Guidelines 1/2024, v1.0 adopted 2024-10-08 for
   consultation; check whether a final version exists): three cumulative steps, a legitimate
   interest, necessity ("more than what is useful"), and a balancing test the controller must
   document; Art. 21 objection right and Art. 13 information apply.
   <https://www.edpb.europa.eu/our-work-tools/documents/public-consultations/2024/guidelines-12024-processing-personal-data-based_en>
6. **Art. 6(1)(a) consent** (EDPB Guidelines 05/2020): freely given (no conditioning a service on
   unnecessary data, Art. 7(4)), specific and granular per purpose, informed, unambiguous,
   withdrawable as easily as given.
   <https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-052020-consent-under-regulation-2016679_en>
   Age: Germany kept the Art. 8 GDPR age of 16 for information society services; Hummlist's
   16+ floor fits **[assessment]**.
7. **Art. 9 special categories, inferred data**: the CJEU held that data that *indirectly*
   reveals a special category (by "comparison, inference or deduction") is itself special-category
   data (*OT v Vyriausioji*, C-184/20, 2022-08-01,
   <https://www.insideprivacy.com/eu-data-protection/special-category-data-by-inference-cjeu-significantly-expands-the-scope-of-article-9-gdpr/>),
   and applied the same to app/website usage in C-252/21. A diet answer like *halal*, *kosher*
   (religion) or *gluten-free / lactose-free because of an allergy* (health) is therefore at high
   risk of being Art. 9 data, needing explicit consent under Art. 9(2)(a) on top of an Art. 6
   basis. No regulator text on meal preferences specifically was found; vendor guides agree
   (**[unverified]** as a regulator position): <https://dev.to/custodiaadmin/gdpr-for-caterers-a-complete-compliance-guide-1h9a>.
   *Vegan / vegetarian* is lower risk but can still signal religion (e.g. Hindu vegetarian) or
   health **[assessment]**.
8. **Deceptive design** (EDPB Guidelines 03/2022, final v2.0 adopted 2023-02-14; written for
   social media, applied more widely):
   - Options need not "look exactly the same", but "if controllers decide to highlight one option
     more than the other(s), the highlighted one needs to be the most restrictive regarding data
     processing" (Deceptive snugness).
   - A big "continue" plus a small "skip this step" link under it is the *Hidden in plain sight*
     pattern (their Example 9).
   - *Continuous prompting*: asking again for data or consent the user already refused.
   - *Emotional steering*: wording or visuals that make users feel rewarded for sharing or guilty
     for refusing; "especially strong" during sign-up.
   - Pre-ticked boxes and inactivity are not consent.
   <https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-032022-deceptive-design-patterns-social-media_en>
9. **Purpose limitation and minimisation** (Art. 5(1)(b), (c) GDPR): an answer collected to
   configure the list may not be reused for marketing or research without a compatible purpose or
   a new basis. <https://eur-lex.europa.eu/eli/reg/2016/679/oj>

### Can optional profile questions in onboarding rest on contract (6(1)(b))? [assessment]

Only if the answer is actually used to deliver what the user asked for and the user can see it
being used. "Which stores do you shop at?" orders the list by store: necessary for a feature the
user chose, so 6(1)(b) works (and the user can skip it). "How many people are in your household?"
qualifies only if it changes the product (e.g. default quantities); if it is collected "to learn
about our users", it is research and needs 6(1)(f) or consent. Making a question optional does not
by itself create a legal basis; it is the *use* that decides (EDPB 2/2019 para 48-49, 57). Mixing
"configure my list" and "help us improve" in one screen is a purpose-mixing risk; split them.

### Practical table

| Data item | Recommended legal basis | Consent needed? | Risk notes |
| --- | --- | --- | --- |
| Household name, store list and order | 6(1)(b) contract | No | Already collected; the list ordering is the visible use. |
| Household size (people) | 6(1)(b) **only if** it drives a visible feature (default quantities, invite copy); else 6(1)(f) or (a) | No if contract; yes if consent-based research | Do not store it "just in case". Coarse buckets (1, 2, 3-4, 5+) are enough. |
| "How do you shop?" (weekly big shop vs daily, who shops) | 6(1)(b) if it sets a feature (e.g. reminder cadence); otherwise research -> 6(1)(f) with opt-out or 6(1)(a) | Depends on use | If no feature uses it, ask it later in an optional survey, not in onboarding. |
| Which stores (as research, e.g. market share) | 6(1)(f) for aggregate analysis of data already held for the contract, documented balancing | No, but Art. 13 notice + Art. 21 objection | Aggregate only; purpose compatibility test (Art. 6(4)) since it was collected for list ordering. |
| Why they joined / jobs to be done | 6(1)(a) consent or 6(1)(f) | Recommended: optional question, clearly marked as "hilft uns", skip equal weight | Free text invites over-sharing (names, health). Prefer fixed choices; if free text, keep it out of PostHog (it already forbids free text). |
| Referral source "Wie hast du von Hummlist erfahren?" | 6(1)(f) (measuring marketing channels) with one-tap "keine Angabe" | No **[assessment]** | Fixed list only. Not an analytics event with identifiers; store per household or aggregate. If it is sent to PostHog, it needs the analytics consent. |
| Diet (vegan, vegetarian, halal, kosher, gluten-free, lactose-free, allergies) | Avoid. If ever needed: 6(1)(a) + 9(2)(a) explicit consent, separate screen, purpose-bound | Yes, explicit | High Art. 9 risk (religion, health) per C-184/20. Better: let users create such filters themselves as plain list features without the app labelling *why*. Never in analytics. |
| Analytics events (PostHog) | 6(1)(a) consent, plus § 25 Abs. 1 TDDDG consent for SDK storage/reads | Yes (already done) | Keep the yes/no screen equal weight; no "recommended" highlight on Yes (EDPB 03/2022). Withdrawal as easy as consent (Settings). |
| Error reports / crash logs | Arguably 6(1)(f) + § 25 exemption for technically necessary stability; DSK does not give a blanket exemption | Currently consent-gated; keep it so unless a lawyer signs off **[assessment]** | Today they ride on the analytics yes (docs/ANALYTICS.md). |
| Notification permission + push token | § 25 Abs. 2 Nr. 2 (push is a wished add-on once the user turns it on, DSK Rn. 74/76) + 6(1)(b) | OS permission only, no extra GDPR consent | Ask only when the user wants a push feature (F). Content of pushes: no item names on the lock screen if they could be sensitive **[assessment]**. |
| Tip/hint dismissals, "seen" counters on device | § 25 Abs. 2 Nr. 2: storing the user's own "hide this" choice is technically necessary to honour it **[assessment]** | No | Store as non-identifying flags (`tip.edit-long-press: dismissed`), like the DSK's `language: de` example (Rn. 81). Do not sync to analytics without consent. |
| Hint *engagement* analytics (shown, tapped, dismissed) | 6(1)(a) via analytics consent | Yes | Only for consenting users; allow-listed event without text. |
| Product research questions in-app (NPS, "what's missing?") | 6(1)(a) consent per survey, or 6(1)(f) with opt-out for short fixed-choice surveys | Recommended consent; always optional | Rate-limit (no continuous prompting); one "nicht mehr fragen" that sticks. |
| Email for research interviews | 6(1)(a) | Yes, separate checkbox, unticked | Separate from account email purpose. |

### Implications for Hummlist

- Split onboarding questions into two visibly different groups: **setup** (stores, maybe household
  size if it drives something; contract basis, skippable) and **"Hilf uns, Hummlist besser zu
  machen"** (optional, consent or LI, equal-weight skip). Never mix them on one screen.
- Every optional question gets a skip that is **as visible as the answer** (a real button or
  "Keine Angabe" chip, not a grey text link under a big CTA): EDPB *Hidden in plain sight*.
- No diet or allergy question in onboarding. If dietary filters come later, they are user-made
  list features, not a profile field.
- Do not re-ask a declined analytics question or survey (no continuous prompting). One re-ask
  path only via Settings, initiated by the user.
- Keep device-side hint state minimal and non-identifying; keep it out of PostHog for users who
  said no.
- Before shipping new data items: add them to the privacy policy (Art. 13), record purpose and
  basis (Art. 30), and run the 6(1)(f) balancing for the referral and research items. Ask the
  legal reviewer to confirm the table; it is an engineering reading of the sources.

---

## E. Contextual hints: patterns and a default rule set

### What the platform guidance says

- **Apple HIG, Offering help -> Creating tips** (added 2023-09-12): a tip is "a small, transient
  view"; for "new or less obvious features" or "faster ways to accomplish a task"; "If a feature
  requires more than three actions, it's probably too complicated for a tip"; "Keep your tips to
  one or two sentences"; no promotional content; "Use parameter-based or event-based eligibility
  rules ... only display a tip if someone might benefit"; "people who've already used a feature
  won't appreciate viewing a tip that describes it"; "When your app has more than one tip, set the
  display frequency so tips display at a reasonable cadence — for example, once every 24 hours."
  General: "make it easy for people to dismiss or avoid the help"; don't explain standard
  components. <https://developer.apple.com/design/human-interface-guidelines/offering-help>
- **TipKit mechanics** (Apple developer docs): event rules (e.g. show only after an event
  "occurs three or more times"), parameter rules (app state), global
  `displayFrequency(.immediate/.hourly/.daily/.weekly/.monthly)` = "minimum duration after one
  tip is shown before another tip will become eligible", per-tip `MaxDisplayCount` (no limit by
  default) and `MaxDisplayDuration`, `IgnoresDisplayFrequency`, and `invalidate(reason:)` which
  "permanently invalidates a tip" (e.g. when the user performed the action).
  <https://developer.apple.com/documentation/tipkit/tips/rule>,
  <https://developer.apple.com/documentation/tipkit/tips/configurationoption/displayfrequency>,
  <https://developer.apple.com/documentation/tipkit/tip/maxdisplaycount>
- **Material feature discovery (tap targets)** (Material 1, still the only Google guidance of
  its kind): for single-tap features; one action per prompt; "Limit the number of feature
  discovery messages ... don't display more than one per session"; show them "at moments when
  they will help the user better complete the action they're taking", not on app open; "If the
  user dismisses a message, don't show it or a similar message again for a more substantial
  period of time." <https://m1.material.io/growth-communications/feature-discovery.html>
- **NN/g, instructional overlays / coach marks** (Aurora Harley, 2014, older but still cited):
  one interaction per hint; chains of tips make users "dismiss hints more quickly"; visuals over
  text; make hints look different from real controls.
  <https://www.nngroup.com/articles/mobile-instructional-overlay/>
- **NN/g 2023** (above): pull revelations triggered by a signal; easy to dismiss and to find again.
  <https://www.nngroup.com/articles/onboarding-tutorials/>
- **Engagement reality check**: median tooltip open rate 0.1 % per impression in Produktly's 2026
  data (<https://produktly.com/research/saas-onboarding-benchmarks-2026>). Passive "did you know"
  tips are mostly ignored; behaviour-triggered ones have a reason to be read **[assessment]**.

### Gesture discoverability

Long-press, swipe and drag are invisible affordances. Apple: "If your experience introduces a
unique control or expects people to use an input device in a nonstandard way ... orient people
quickly, preferring animation or graphics". NN/g: use visuals with ultra-short text. Pattern:
teach the gesture **on a real row** the first time the user is on that screen with a row to try,
and retire the hint as soon as the gesture is used once (TipKit-style invalidation).

### Proposed default rule set for Hummlist [assessment, synthesised from the sources above]

| Rule | Default | Source basis |
| --- | --- | --- |
| Max hints visible at once | 1 | Material, NN/g (no chains) |
| Global cooldown between two different hints | 24 h, and at most 1 hint per app session | Apple HIG example (24 h), Material (1 per session) |
| Quiet start | No hint in a user's first session until the first item is on the list (first-run belongs to onboarding); no hint while onboarding, a dialog, a sheet or the keyboard is open, or during the first 10 s after app start | Material ("not on app open", not at interruptive moments) |
| Eligibility | Every hint has a *trigger* (behaviour signal) and a *already-knows* condition; a hint for feature X is never shown to someone who has used X | Apple HIG, TipKit event rules |
| Behaviour triggers (examples) | After the 3rd item added by typing one by one in a session -> "Mehrere auf einmal: mit Komma trennen"; after the 3rd time editing via a dialog path -> long-press hint; after 2 manual reorders -> store order hint; after partner's first add -> realtime / notification hint; when list has 0 items and user is alone for > 1 day -> invite nudge | TipKit "event occurs three or more times" |
| Retire on use | Using the feature invalidates its hint for good (sync across the user's devices if cheap; device-local is acceptable) | TipKit `invalidate` |
| Max display count | A hint shown and ignored (not dismissed, not used) 3 times is retired | TipKit `MaxDisplayCount` pattern |
| Dismiss semantics | X = "never show this hint again" (current behaviour, keep). No snooze button (adds a decision, and snooze-loops become continuous prompting) | NN/g "easy to dismiss"; EDPB continuous prompting (for data asks) |
| Dismissal backoff | After a user dismisses 3 hints in a row without using any feature, pause all hints for 14 days | Material "more substantial period" after dismissal |
| Recall | Every hint is re-readable later (More -> Tipps) | NN/g, Apple ("easy to find") |
| Content | Title + max 2 short sentences, one action, the real gesture/icon; no promo, no premium upsell in tips | Apple HIG |
| Upsell separation | Premium prompts are not tips and follow their own (stricter) rules | Apple HIG (no promotional content in tips) |
| Measurement | `hint_shown`, `hint_dismissed`, `hint_feature_used_within_7d` (ids only, no text), only for consenting users | D, `eventCatalog` |

### Implications for Hummlist

- The existing tip card (job 80) already matches the 1-at-a-time and dismiss-forever rules. The
  gaps are: **triggers** (today it is a fixed queue, not behaviour-based), **retire-on-use**
  (a user who already long-presses still sees the long-press tip), a **global cooldown** (today
  the next tip shows from the next app start, which can be minutes later), and **recall**.
- Reuse the TipKit vocabulary in the Dart design (rule, event count, display frequency, max
  display count, invalidate reason) so iOS developers and the docs speak the same language, even
  though Flutter cannot use TipKit itself.
- The gesture card and the tip card should share one budget (they are both hints).

---

## F. Notification permission priming

### Platform rules

- **Apple, "Asking permission to use notifications"**: the system prompts only once ("Subsequent
  authorization requests don't prompt the person"); "Make the request in a context that helps
  people understand why ... In a task-tracking app ... you might make the request after the person
  schedules a first task"; this "provides a better experience than automatically requesting
  authorization on first launch". **Provisional authorization** sends quiet notifications to
  Notification Center without asking; the user then taps Keep or Turn Off on a real notification.
  <https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications>
- **Apple HIG, Privacy**: "Avoid requesting permission at launch unless the data or resource is
  required for your app to function." For custom **pre-alert screens** (Apple lists camera,
  microphone, location, contacts, calendar and tracking): "Include only one button and make it
  clear that it opens the system alert"; use "Continue" or "Next", not "Allow"; no cancel or close.
  Notifications are not on that list.
  <https://developer.apple.com/design/human-interface-guidelines/privacy>
- **Android 13+ (`POST_NOTIFICATIONS`)**: new installs start with notifications **off**; apps
  targeting 13+ control when the dialog appears. "Before you ask users to grant any permissions,
  let them familiarize themselves with your app"; trigger from a user action (e.g. tapping a bell)
  or wait "until the third or fourth time the user launches your app"; request "in the correct
  context". <https://developer.android.com/develop/ui/views/notifications/notification-permission>
- **Android, denial**: "if the user taps Deny for a specific permission more than once ... the user
  will no longer see the system permissions dialog"; educational UI should include a "cancel" or
  "no thanks" button; "persistent nagging to reconsider is not respectful"; don't link to settings
  "in an effort to convince the user". <https://developer.android.com/training/permissions/requesting>
- **NN/g, permission requests** (Maria Rosala, 2019): stating a reason made users "12 % more likely
  to grant a permission" (study of 15 apps); ask when the user selects a feature that needs it;
  focus on user benefits; vague reasons ("a better experience") raise suspicion.
  <https://www.nngroup.com/articles/permission-requests/>

### Opt-in benchmarks (all vendor data)

| Source | Android | iOS | Notes |
| --- | --- | --- | --- |
| OneSignal 2024, Utilities | 51.5 % | 51.6 % | Productivity 53.6 / 44.8 %, Lifestyle 38.8 / 34 %. Says an in-app message before the native prompt "significantly increases opt-in rates" (no number). <https://onesignal.com/mobile-app-benchmarks-2024> |
| Airship medians | 53.3 % (2025), down from 71.3 % (2023) | 48.85 % (2025) | via secondary source, **[unverified]** against Airship's PDF. <https://admiral.media/push-notification-strategy-mobile-apps/>, primary: <https://growth.airship.com/rs/313-QPJ-195/images/Airship-2025-Push-Notification-Benchmarks-EN.pdf?version=0> |
| Batch (France-centric CRM data) | 85 % -> 67 % in one year after Android 13 | ~56-58 % | **[unverified]**, partly from secondary summaries. <https://batch.com/blog/case-studies/benchmark-notifications-push-crm-mobile> |

Read: since Android 13, Android and iOS converge around **~50 %** opt-in for utility apps; the
prompt is a one-shot on iOS and a two-shot on Android, so timing matters more than copy.

### Implications for Hummlist

- **Never at first launch or inside onboarding.** Hummlist works without push; the value of a push
  ("Lea hat Milch hinzugefügt", "Peter ist im Laden") only exists once a partner is in the
  household.
- **Trigger in context**, e.g. the first time a partner's change arrives while the app is open, or
  when the user taps an explicit "Benachrichtigen" toggle/bell, or after inviting the partner
  ("Sag mir, wenn Lea beitritt"). That is a user action, which both Apple and Android recommend.
- **Soft ask as an inline card, not a modal**: one sentence with the concrete benefit, button
  "Einschalten" (opens the system prompt), and a dismiss X / "Jetzt nicht" of equal weight
  (Android requires a way out; Apple's single-button rule covers listed resources, not
  notifications **[assessment]**). Never title our button "Erlauben".
- **One soft ask, at most one re-offer** (e.g. after 30 days, only if a new trigger fires), then
  only via Settings. On Android, never let the system prompt be shown twice without a fresh user
  action: a second Deny is permanent.
- Consider **iOS provisional authorization** for the "partner added items" notification: quiet
  delivery, the user decides on a real example. Test it; Apple forum threads report quirks with
  the Keep flow on iOS 16/17 (<https://developer.apple.com/forums/thread/732230>).
- Measure: soft-ask shown / accepted / system granted, per platform, consenting users only. Target
  roughly the ~50 % utility benchmark for system-prompt grants; a good soft-ask flow should land
  well above it among those who tap "Einschalten" **[assessment]**.

---

## Source quality summary

- Strong (primary): Apple HIG and developer docs, Android developer docs, NN/g (2019, 2020, 2023;
  the 2014 overlay article is old), DSK OH Digitale Dienste v1.2, EDPB Guidelines 2/2019, 03/2022,
  05/2020, 2/2023, 1/2024 (draft status to be checked), § 25 TDDDG, CJEU C-184/20 and C-252/21
  (read through law-firm summaries, not the judgments), Norton/Mochon/Ariely 2012, Buell/Norton
  2011, Irrational Labs Headspace case, Gotthilf interview.
- Medium (vendor, own customer data): Amplitude, Produktly, Chameleon, Intercom, OneSignal,
  Baymard, Lenny's survey.
- Weak, marked **[unverified]**: retention tables attributed to Adjust/AppsFlyer, Airship and
  Batch opt-in series, Facebook/Slack aha numbers, the 2x-retention rule, Noom/long-quiz claims,
  Trainual case, endowed-progress percentages, multiplayer "2x when a teammate joins".
