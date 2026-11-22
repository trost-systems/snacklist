# Snacklist product feature map

Living catalogue of what Snacklist has, is building, is considering, and has dropped.

This file is the **repository home** (canonical source). The [living Page](https://cursor.com/canvas/store-1bba9ee2-e28e-47ad-a6b5-ea80faa6498b/1ee9370d-3e32-4854-bc33-cb4729a84b14) is a navigation view of the same catalogue. [Nexus](https://nexus.snacklist.app) links both from its header ("Feature map", "Living view"). Keep the Page and this file in sync.

This is **not** the code-backed inventory of shipped behavior. That inventory lives in [FEATURE_MAP.md](FEATURE_MAP.md) and `.cursor/skills/verify-snacklist/features/`. Do not mix the two, and do not rename those inventory files to match these slugs.

Use **human-readable names**, with stable kebab-case **slugs** where a handle is needed. Do not use letter-and-number codes (F27, UA1, and so on) in new writing. A compact legacy mapping is at the end for historical traceability only. It is not a second code set to learn.

Statuses below were checked against `origin/main` at `764265b0` (13 Nov 2026). Only “Built” if the code exists. Product decisions in this revision: 11 Nov 2026, 07:23–07:25 Europe/Berlin, and the evening's pricing and tier decisions, 20:42–21:26 Europe/Berlin (“Pricing and tiers, 11 Nov 2026 evening” below). Superseded wording stays in place, marked **superseded**, so earlier chats can be traced. Approved work that is not in the tree is marked **pending implementation**. (?) marks judgment or unverified wording. Not legal advice.

## Now and what blocks sales

| | |
| --- | --- |
| Built and live | 12: list, categories, aisle layout, app and web, Alexa, widgets, multi-household, dictation, Siri, no ads, item icons, usuals |
| Built, gated off | 3: MCP, the public API and the grocery log |
| Planned (decided) | 7: prices and trip total, user photos, barcode scan-to-add, catalog photos, last-price memory, shelf-label scanning, Siri AI app actions |
| Considering | 7: spend history, arrival reminders, themes, recipe to list, watch glance, receipt scanning, planned vs bought |
| Blocks sales | Real differentiated Premium value (`premium-differentiation`): which slice is required is open. Free price entry is **not** a sales gate any more (11 Nov 2026 20:42). Shelf-label scanning must not delay sales. |
| Launch | 1 Dec 2026 is a **paid** launch (`dec1-paid-launch`). Premium features needed for sale must be built before then. |
| Yearly / lifetime | €24.99 / €149.99, both at paid launch; no monthly or weekly plan at first (11 Nov 2026 20:42). Approved, not in the stores or the code yet. Superseded: €9.99 / €39.99 (11 Nov morning), €9.99 / €29.99 (stores and code today). |

Nothing is sold today (`REVENUECAT_PURCHASES` and `premium_offer` are off; products are not submitted).

**Sales stay off until Premium carries real differentiated value** (`premium-differentiation`, 11 Nov 2026 20:42 Europe/Berlin). Which slice is required for the paid launch is open. Candidates to evaluate first are the ones already built: the public API and MCP. Free price entry, trip totals and barcode scanning are not sales prerequisites. Shelf-label scanning must not delay sales. Before the first sale, also implement per-user Premium (RevenueCat App User ID = the Snacklist user id, not the household UUID) and have Ops set the approved store prices (`store-prices-ops`). Siri is free in the integration gate and paywall copy (job 184). The 20-household cap per user is enforced since job 200. Day-one rule: sell only what exists.

*Superseded (11 Nov 2026 07:23, replaced at 20:42):* “Sales stay off until prices and trip total ship”, with the Lifetime price moving from €29.99 to €39.99.

**Free and Premium (CS1, 11 Nov 2026 20:42–20:59 Europe/Berlin).** Free covers complete day-to-day list shopping and data capture: price entry, trip totals, unlimited barcode scanning, shelf-label scanning, purchase recording and arrival reminders (the tier each gets when built; none of these is in the app yet). Convenience without an ongoing per-use cost is Free (`free-convenience-no-running-cost`). Premium is insights, analytics, automation, API/MCP, and features with a real per-use cost (cloud receipt scanning, web product images, not the Open Food Facts catalog photos, which stay Free; own photos because of storage), plus themes as a thank-you. Lifetime has the same features as yearly, with explicit allowances for costly processing and API use, not unlimited (`lifetime-allowances`; numbers open, pending a cost check). Siri is free, like Alexa. A user may belong to at most 20 households, Free or Premium (enforced since job 200).

Per-user Premium: one person buys. Peter was leaning toward shared views (own photos; last-price hints while their tier is open) unlocking in the households the buyer belongs to, following the buyer if they leave (**leaning, not a firm approval**; `shared-views` stays open). Seat tools (taking a photo, API/MCP) stay on the buyer’s device. On lapse, entered prices stay visible read-only (`prices-remain-on-lapse`; since prices are Free, this likely matters only if a price view is ever Premium (?)).

*Superseded (11 Nov 2026 morning, replaced 20:42–20:59):* prices and trip total as Premium shared views; entering a price and scanning a shelf label as Premium seat tools on the buyer’s device; barcode scan-to-add as a free taste of 5 scans a day with unlimited scans in Premium (`five-free-scans`); shelf-label scanning as Premium.

Unchanged by the evening's decisions: the UI prototype gate, beta first, the job 182 Legal hold, and the store and legal publication and submission gates.

## Decisions in force

| Decision | Slug | Status |
| --- | --- | --- |
| Per-user Premium. RevenueCat App User ID = Snacklist user id. | `per-user-premium` | **Implemented, dark** (job 185): new builds use the user id; sales switches off; privacy texts and copy pending (NEEDS_PETER "Job 185"). |
| Shared views in every household the buyer belongs to, tighten only on heavy abuse. | `shared-views` | **Leaning, not a firm approval.** `household-limit` does not settle every shared-views detail. |
| On lapse, prices and the last total stay read-only. Nothing is deleted. | `prices-remain-on-lapse` | Approved. Since 20:42 prices and trip totals are Free, so nothing about them likely lapses (?); kept for any later Premium price view. |
| Product images: icons (already built) → Open Food Facts name and photo on a barcode scan → user photos. | `product-images` | Approved direction. |
| Paid readiness depends on real differentiated Premium value (insights, automation, API/MCP, noticeable-cost conveniences), not on free price entry. Shelf-label scanning must not delay sales. | `sales-prerequisite`, `premium-differentiation` | Approved 11 Nov 2026 20:42 Europe/Berlin (t788u). Which slice is required for the paid launch is **open**; evaluate the built API and MCP first. *Superseded:* “No sales until prices and trip total exist” (07:23 the same day), which had itself replaced a hold that also waited on shelf-label scanning. |
| Yearly €24.99 and Lifetime €149.99, both at paid launch. No monthly or weekly plan at first. | `yearly-plan`, `lifetime-plan` | Approved 11 Nov 2026 20:42 Europe/Berlin (t788u). **Approved, not in the stores yet:** the stores still charge €9.99 / €29.99 until Ops sets them (`store-prices-ops`). `expectedPrices` in `scripts/iap/product.ts` holds the approved euro amounts and accepts the superseded ones with a note until then (job 184). *Superseded:* €9.99 / €39.99 (t774u, 11 Nov morning) and €29.99 Lifetime in earlier planning prose. |
| Lifetime has the same features as yearly, with explicit allowances for costly processing and API use. Not unlimited. | `lifetime-allowances` | Approved 11 Nov 2026 20:42 / 20:54. Allowance numbers are **open**, pending a cost check. |
| Price entry, trip totals, barcode scanning and purchase recording are Free. | `prices-and-trip-total`, `free-convenience-no-running-cost` | Approved 11 Nov 2026 20:42 (t788u). *Superseded:* prices and trip total as Premium and as a sales prerequisite. |
| Convenience without ongoing per-use cost is Free. Premium is analytics, insights, automation, API/MCP and features with a real per-use cost (examples: cloud receipt scanning, web product images; Open Food Facts catalog photos stay Free). | `free-convenience-no-running-cost` | Approved 11 Nov 2026 20:54 Europe/Berlin (t791u, CS1). |
| Barcode scanning is unlimited in Free: on-device scan plus the free Open Food Facts lookup. | `barcode-free-limit` | Approved 11 Nov 2026 20:54 (t791u, CS1). Not implemented (no barcode package in the app yet). |
| *Superseded:* five free barcode scans a day, unlimited in Premium. | `five-free-scans` | **Superseded 11 Nov 2026 20:54 by `barcode-free-limit` (CS1).** Peter briefly chose BS2 (five a day, unlimited in Premium) that evening and replaced it with CS1 the same evening. Kept for history only. |
| Tiers under CS1: shelf-label scanning Free (SL1), arrival reminders Free (AR1), themes stay a Premium thank-you (TH1), user photos stay Premium for storage cost (UP1). | `shelf-label-scanning`, `arrival-reminders`, `themes`, `user-photos` | Approved 11 Nov 2026 20:59 (t792u). Tiering only: statuses unchanged, no build or prototype approval. |
| A user may belong to at most 20 households, on both Free and Premium. | `household-limit` | Approved 11 Nov 2026. **Implemented** (job 200): the membership code caps a user at 20 households (`public.household_cap()`); the paywall does not mention a cap yet (job 187). This is a per-user membership cap, not only a Premium shared-view cap. Peter’s answer labelled Q157 was this cap, not a receipt-scanning decision. |
| Cloud receipt scanning uses Vertex AI `gemini-3.5-flash` in `europe-west3` under Google Cloud EMEA Ltd's CDPA (Peter's U2B / Legal option R1, 11 Nov 2026). | `receipt-scanning` | Decision recorded 11 Nov 2026, 21:39 and 21:51 Europe/Berlin. **Approved for docs only; no build yet; no real receipts until N-135..N-144 met; policy/in-app text needs Peter's approval.** Artifact: [legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md](legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md). Do not confuse Legal option R1 (Vertex) with the dropped legacy slug `on-device-receipt-ocr` (legacy ID R1). |
| Siri is free. MCP and the public API stay Premium. | `siri`, `mcp`, `public-api` | Approved. |

Dropped: public price-insight posts (including Destatis); on-device receipt OCR; weekly auto-renew and the 7-day pass.

## Pricing and tiers, 11 Nov 2026 evening

Peter's decisions t788u (20:42), t789u (20:49), t791u (20:54), t792u (20:59), t-PM-2115 (21:15, P5b updated 21:16) and t796u (21:26), all Europe/Berlin. Planning only: none of them approves building, prototyping or launching a feature, changing a live store or RevenueCat console, publishing terms, or touching job 182 or PR #363.

| Decision | Slug | What it says |
| --- | --- | --- |
| Lifetime in revenue math | `lifetime-revenue-math` | In revenue and kill-gate math, a €149.99 Lifetime purchase counts as a yearly subscription for 6 years, then cancelled and never re-issued (P1). |
| The Premium pitch | `premium-pitch` | Leads with export, API and MCP (and later `planned-vs-bought`), not spend charts (P3a). `grocery-log` trip history stays separate from bank-style spend graphs. The GDPR account export (`export_my_data`) is not a Premium feature and is never presented as one. |
| AI suggestions | `ai-suggestions-cost-example` | Only an example of a per-use cost. Not an approved feature and not a paywall line (P4a). Any model use starts from a user action. |
| 1 Dec is a paid launch | `dec1-paid-launch` | The 1 Dec public launch sells Premium (P5b). Claude Ultra capacity runs to the end of November (resets 13, 20 and 27 Nov, 00:00 Europe/Berlin); after that only bug fixes, so Premium features needed for sale are built before 1 Dec. *Superseded:* the earlier free-launch fallback. |
| Validation plan | `validation-plan` | F1–F6 approved (F-a). Required PostHog events: F2 `shop_started`, `price_entered`, `trip_total_viewed`; F3 `scan_started`, an item added from a scan, `off_miss` (Open Food Facts miss); F5 `mcp_tool_call`, `api_key_used`. Test and internal accounts must be filterable. Peter sets the pass bars; none are set here. Status (13 Nov 2026): the events are allow-listed since job 195 ([`ANALYTICS.md`](ANALYTICS.md)); the F2 and F3 app events (`events.dart`) are sent only once their UI exists. **F5 measures nothing today:** the two are server events in the functions' catalog (`_shared/telemetry.ts`), `mcp_tool_call` capture is off under Legal N-147 until the consent text covers MCP (#383), and `api_key_used` cannot fire while `public_api` is off. |
| Store prices | `store-prices-ops` | Yearly €24.99, Lifetime €149.99 (SP1). Snacklist Ops sets other currencies accordingly without a further sign-off from Peter. Engineering does not touch the stores. Paywall and store copy read prices from StoreKit / Play Billing and never hardcode an amount, old (€9.99, €29.99, €39.99) or new. Once Ops has set the stores, `expectedPrices` in `scripts/iap/product.ts` is updated to match and serves as the drift check. |
| Fable review | `fable-review-deferred` | Deferred until after 1 Dec; the routine moves to 4 Dec (FB1). *Superseded:* the plan that it could use up to 50 % of the week starting 13 Nov. That week is for beta and sales prerequisites. |
| Household cap work split | `household-limit` | Enforcement is job 200 (`200-household-cap-enforcement`, merged) and does not wait on job 190. Job 187 keeps only the paywall, terms and screenshot preparation for the cap (CAP1). |
| Receipt scanning and N-127 | `receipt-scanning` | At 21:15 N-127 was open: Legal's on-device-first receipt path conflicts with dropping on-device receipt OCR, and cloud receipt scanning only comes after Legal clears N-127. Later that evening (21:39, 21:51) the U2B / Legal option R1 path was recorded for docs only (row above); there is still no build approval and no real receipts until N-135 to N-144 are met. |

Spend history, planned vs bought and receipt scanning stay candidates or deferred; the grocery log is built behind the `grocery-log` flag (job 199, t828u/t830u). t788u is not an approval to build every insight discussed.

## Cost overview

Figures are rough, in Europe/Berlin terms, and marked (?) where judged. Store cut is 15–30% depending on programme, so a €24.99 year nets about €17.49–21.24 before VAT effects. Lifetime at €149.99 counts as six years of yearly in revenue math (`lifetime-revenue-math`), and carries explicit allowances for costly processing and API use (`lifetime-allowances`). *Superseded:* a €9.99 year netting about €6.99–8.49, and Lifetime at €39.99 as four years of yearly.

| Item | Build (guess) | Running cost per paying user / year | Note |
| --- | --- | --- | --- |
| Free core (list, categories, aisle layout, app and web, Alexa, widgets, multi-household, dictation, item icons, usuals) | Already built | Hosting only | No LLM, no paid catalogue |
| Barcode scan-to-add + catalog photos | 1–2 weeks (?) | Free (Open Food Facts rate limits: 15 reads / 10 searches per IP per minute) | Cache by EAN; attribution in the UI. Unlimited in Free (`barcode-free-limit`). |
| User photos | 1–2 weeks + a storage cap (?) | Storage cost depends on cap and usage; not a reason to raise Lifetime | Cap storage. Earlier storage figures are unverified estimates. |
| Prices, trip total and last-price memory | 1–2 weeks (?) | Negligible (our database) | Prices and trip total are Free and no longer block sales (11 Nov 2026 20:42) |
| Shelf-label scanning | 2.5–4 weeks, both platforms (?) | None (on-device Apple Vision / ML Kit) | User confirms; never silent-write. Ships later; must not delay sales. |
| Receipt scanning (candidate) | About 2–3 weeks plus Legal path (?) | Vendor and model recorded (Vertex AI `gemini-3.5-flash` in `europe-west3`); per-use cost not approved as a figure to ship | Path decided for docs only (U2B / Legal option R1, 11 Nov 2026). No build yet. No real receipts until N-135 to N-144 are met. No terms signed without Peter. |
| Public API and MCP | Built; extensions later | Rate limits already in v1; photo upload would share the user-photos cap | Candidates for the differentiated Premium slice (`premium-differentiation`). Lifetime gets explicit API allowances, not unlimited use. |
| AI suggestions (cost example only) | Not planned | Per-use model cost | `ai-suggestions-cost-example`: an example of a running cost, not a feature or a paywall line. |

## Legal flags

**Household limit approved: 20 per user, Free and Premium, in code since job 200.** Peter approved a maximum of 20 households per user for both Free and Premium (11 Nov 2026; he labelled this Q157). That should be plenty of room and limit abuse. This is a membership cap, not only a Premium shared-view cap. The code caps every user at 20 since job 200 (it was 10 from job 173); no user was above 10 when it changed. Legal Review (10 Nov 2026) had asked for a numbered cap to be visible on the paywall and in the terms before purchase, and had assumed free joining would stay uncapped with the cap only on Premium shared views. Peter’s number applies to both tiers. Record it on the paywall and in the terms when implemented; do not treat “every household” as firm paywall copy (shared views was a lean, not a firm approval). Not legal advice; Legal still reviews the wording.

- Manage or cancel subscription: already built in the Premium screen, labelled “Abo verwalten oder kündigen”. Legal still requires this to be permanent, to open the store page, and to sit next to clear paywall text on price, period and auto-renew before the yearly plan is sold. Do not add a Snacklist “Verträge hier kündigen” button while sales are store-only.
- Fair-use terms: Legal’s draft can use N = 20, in “du”, but the approved rule is a 20-household membership cap per user on both Free and Premium, not only a Premium shared-view cap. The older paid-terms draft that says Premium belongs to one household is stale and must be rewritten before sale. Do not publish terms in the change that lands this file.
- Receipt scanning path recorded as U2B / Legal option R1 (11 Nov 2026, 21:39 and 21:51 Europe/Berlin): Vertex AI `gemini-3.5-flash` in `europe-west3` under Google Cloud EMEA Ltd's CDPA. **Approved for docs only; no build yet; no real receipts until N-135 to N-144 are met; policy and in-app text need Peter's approval before they go live.** Conditions include a signed Art. 28 DPA (Peter accepts the terms himself), a Frankfurt-pinned server function, no training, immediate or zero retention (hard ceiling 24 h), server-side stripping of payment, loyalty, cashier, address, time and receipt/TSE numbers, grocery-only with pharmacy discard and Art. 9(2)(a) consent, a one-time permission screen, and policy/store-label updates in the same release. Artifact: [legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md](legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md). Not legal advice; no terms signed without Peter.
- Price-insight posts are dropped, so Legal’s Destatis vs user-data-posts question is closed unless Peter re-opens it.

## Built and live

These run for every household today. Hormozi impact is from the 10 Nov 2026 value report: D×L of 12 or more can lead a pitch; the index is (D×L) / ((6−T)×(6−E)).

| Name | Slug | What it is / example | Tier | Impact | Cost | Deps / decisions |
| --- | --- | --- | --- | --- | --- | --- |
| List and live sync | `list-and-live-sync` | Shared list that updates for everyone. Example: Anna adds Milch; Ben sees it on his phone at once. | Free | D×L 25, index 25 | Already built | Core |
| Categories | `categories` | Items land in a category. Example: Milch goes under Chilled. | Free | D×L 15, index 15 | Already built | Core |
| Aisle / store layout | `aisle-layout` | List follows the store, including learned item→store memory. Example: at Rewe, Milch appears in the dairy stretch of the walk. | Free | D×L 20, index 5.0 | Already built | Core, coverage grows with use |
| App and web | `app-and-web` | iOS, Android and the web app. Example: Anna is in the aisle; Ben adds from the laptop. | Free | D×L 20, index 10 | Already built | Core |
| Alexa | `alexa` | Add and read by voice on Echo. Example: “Alexa, add butter to Snacklist.” | Free (legal) | D×L 16, index 2.7 | Already built; stays free | Stays free by legal and product decision. |
| Home-screen widgets | `home-screen-widgets` | Glance the list without opening the app. | Free, ungated | D×L 15, index 7.5 | Already built | No Premium gating. |
| Multi-household | `multi-household` | Create, join and switch households. Example: Anna is in Home and Parents. Approved cap (`household-limit`, enforced since job 200): a user may belong to at most 20 households, Free or Premium. | Free (cap applies to both tiers) | D×L 15, index 7.5 | Already built; cap of 20 enforced (job 200) | `household-limit`, 11 Nov 2026. The code caps a user at 20 households (job 200). |
| On-device dictation and parse | `dictation` | Speak a line; the app splits quantity, brand and properties (`parse_item`). Example: “Zwei Packungen Barilla Spaghetti” becomes qty 2, brand Barilla. Languages: German and English, the app's language (de_DE; en_US or the device's English variant, job 256). Offline speech for that language is required on the device; Android 13+ asks the system to download a missing one. | Free | D×L 12, index 12 | Already built (`speech_to_text` onDevice, `addSpoken`). English, and the new per-language native check and download request for both languages: unverified on a real device (job 256's device script, in the job's ops directory) | Brand is parsed for free. No Premium split on brand. |
| Siri | `siri` | Add and read via Shortcut or native Siri on iPhone, without opening the app. | Free (decided) | D×L 16, index 2.7 | Already built and live (lock is off) | Treated like Alexa in the gate and dropped from paywall copy (job 184). |
| No ads | `no-ads` | The free app does not show ads. There is no ad SDK in the tree. | Free (a promise, not a paid item) | Index 15 only if ads existed to remove | None | Do not sell “ad-free” |
| Item icons | `item-icons` | Bundled emoji icons from a keyword table, with a remote refresh. Example: Milch shows a milk carton. | Free (first `product-images` layer) | D×L 10, index 10 (bonus) | Already built (`item_icons` + remote JSON) | `product-images` |
| Usuals and “Need these again?” | `usuals` | Suggestions from household history, and a due row for staples. Example: the add sheet offers Milch because the household buys it often. | Free | D×L 16, index 8.0 | Already built (`suggest_items`, `dueSuggestions`) | A weekday-prediction Premium slice is not planned unless usage shows a gap. |

## Built, gated off

The code exists and works when switches are on, but sales and the integration lock are off, so everyone can use these today. They become Premium only when the lock and the offer are turned on. The Siri-free gate change is done (job 184). They are the first candidates for the differentiated Premium slice (`premium-differentiation`). *Superseded:* turning them on only after prices and trip total. The grocery log is different: it sits behind its own PostHog flag `grocery-log`, off for everyone until the Lead releases it, and its older-than-4-weeks history needs the per-user Premium entitlement already.

| Name | Slug | What it is / example | Tier | Impact | Cost | Deps / decisions |
| --- | --- | --- | --- | --- | --- | --- |
| MCP / AI assistants | `mcp` | Connect an MCP client to list, add, change, tick, untick, merge, move and remove, and to read the usuals, what was ticked lately and a store's walk order (list and store writes wait behind `mcp_lists_stores`). Example: a developer’s assistant ticks Milch after the shop. Discovery stays free; `tools/call` is the lock. | Premium (leads the pitch, `premium-pitch`) | D×L 6, index 0.5 (niche) | Already built; no running model cost | `integration_lock`; extensions (prices, EAN, photos) wait for `prices-and-trip-total`, `barcode-scan-to-add` and `user-photos`. Lifetime: explicit allowance (`lifetime-allowances`). Evaluate as the paid-launch slice. |
| Public REST API | `public-api` | Personal household-bound keys: items, categories, stores, lists. Example: a kitchen display polls open items. `public_api` is seeded false. | Premium (leads the pitch, `premium-pitch`) | D×L 8, index 0.7 (niche) | Already built; rate limits in v1 | Under `per-user-premium` the Premium check should follow the key creator, not the household. Confirm before switch-on. Later extensions (PATCH name, prices, EAN, image upload, webhooks, changes feed, OAuth, api.snacklist.app) are not in v1. Lifetime: explicit allowance (`lifetime-allowances`). Evaluate as the paid-launch slice. |
| Grocery log | `grocery-log` | Log a shopping trip (store, day, items with amounts) by hand or through trip mode (the list's inline card once a store's section was fully ticked was removed in job 264), and browse past trips in the Verlauf tab: G1 journal by date with a month calendar (one dot per trip in the store's colour, at most 3, no +N) or G2 store timeline, one button cycles them (t828u, 13 Nov 2026 07:51 Europe/Berlin). Example: Lidl twice and Rewe once on Thursday show three overlapping dots. | Logging Free and unlimited; browsing Free for the last 4 weeks; older history Premium (per-user entitlement) and kept, never purged (t830u, 13 Nov 2026 07:57 Europe/Berlin). | Not scored | Built (job 199) | Behind the PostHog flag `grocery-log` (`releases/flags.json` rollout off; can be released to internal installs by `is_internal`). Trips are logged only by hand or through trip mode (t864u); job 199's post-shop card (H2, H3) is removed (Peter t952u/t953u, 15 Nov 2026, job 264), deletion with account and household and in the GDPR export, not on the API or MCP (H4). No prices, totals, spend graphs or receipt scanning; those stay with `prices-and-trip-total`, `spend-history`, `receipt-scanning`. Art. 9 question for drugstore lines in NEEDS_PETER (Job 199). Prototypes: [design/grocery-log/](design/grocery-log/). |

Paywall, RevenueCat and “Abo verwalten oder kündigen” are also built and gated off. The paywall shows the store's price. The stores still charge €9.99 / €29.99; `expectedPrices` holds the approved €24.99 / €149.99 and accepts the old amounts with a note until Ops sets the stores (`store-prices-ops`, job 184). App User ID is still the household UUID.

## Planned (decided)

Decided, not in the tree at `764265b0`. Prices and trip total, barcode scanning and shelf-label scanning are Free (11 Nov 2026 20:42–20:59) and none of them blocks sales. *Superseded:* prices and trip total as the sales gate (07:23). None may be advertised before it exists.

| Name | Slug | What it is / example | Tier | Impact | Cost | Deps / decisions |
| --- | --- | --- | --- | --- | --- | --- |
| Prices and trip total | `prices-and-trip-total` | Type or confirm a price on an item; see a running total. Example: Anna enters €1.19 on Milch and sees the running total. | Free (11 Nov 2026 20:42). *Superseded:* Premium, shared view if `shared-views` is confirmed (Ben would see the total only where shared views were offered). | D×L 16, index 2.7 typed, 4.0 with shelf-label scanning | 1–2 weeks (?); storage negligible | Not a sales prerequisite any more (`premium-differentiation`). *Superseded:* sales prerequisite (07:23). `household-limit` enforced. **Built behind the flag `prices-and-trip-total` (job 190, 13 Nov 2026, rollout off):** `inline-row-price` (t832u). Price and tick are separate; list total across all stores plus a subtotal per store section; −9999 to 9999 per item, 0 and deposits allowed, 50 kg; whole household live; household currency (ISO code, default EUR). Locked by Peter (t833u): the unit price is kept and the line scales when the quantity changes (LQ2); the planned weight is the quantity and the scale weight replaces it (PW1); the unit follows the item (Stück, kg, l). Peter reviews it on TestFlight with the flag on for his install (t834u). The approach-3 end-of-trip summary is a later screen (DECISIONS, Job 190). |
| Shelf-label scanning | `shelf-label-scanning` | On-device OCR of a German shelf label; user confirms the selling price, not the Grundpreis. Example: Anna points the camera at the Milch tag, taps €1.19. | Free (SL1, 11 Nov 2026 20:59). *Superseded:* Premium seat tool. | D×L 16, index 4.0 | 2.5–4 weeks, both platforms (?); no cloud cost | Planned, but not a sales gate (11 Nov 2026). The tier change is not a new build approval. Ships later when ready. On-device Apple Vision / ML Kit. No silent write. No camera or ML Kit dependency in the app yet. |
| Barcode scan-to-add | `barcode-scan-to-add` | Scan a pack to add the item. Example: at home, Ben scans the empty Milch carton; the name appears. Scanning is unlimited. | Free, unlimited (`barcode-free-limit`, CS1, 11 Nov 2026 20:54). *Superseded:* a free taste of 5 a day with unlimited scans in Premium (`five-free-scans`). | Taste D×L 12, index 6.0 (paid-slice score no longer applies) | 1–2 weeks with `catalog-photos` (?) | `barcode-free-limit`. On-device scan plus the free Open Food Facts lookup. No barcode package in the app yet. |
| Catalog photo (Open Food Facts) | `catalog-photos` | A successful barcode add can show the Open Food Facts pack photo, with attribution. Example: the scanned Milch carton shows the brand pack shot. | Free (`product-images`); every scan is Free (`barcode-free-limit`). *Superseded:* “on a free or Premium scan” (`five-free-scans`). | D×L 9, index 2.25 | Open Food Facts is free; 15 reads/min per IP | Needs `barcode-scan-to-add`. Legal check of ODbL / CC BY-SA still open. US fallback (USDA names only) only after measuring misses. |
| User photos | `user-photos` | Attach your own photo to an item. Example: Anna photographs the exact yogurt so Ben does not buy the wrong one. | Premium, for ongoing storage cost (UP1, 11 Nov 2026 20:59); shared view once added if `shared-views` is confirmed | D×L 20, index 3.3 | 1–2 weeks + storage cap. Earlier yearly storage figures are unverified estimates. | `product-images`. No item photo column yet. |
| Last-price memory | `last-price-memory` | Prefill “last time this was €1.19” at this store; the user confirms. Example: next week the Milch row already shows last week’s price. | Not re-tiered (?). Was Premium (shared view) while prices were Premium; under `free-convenience-no-running-cost` it would read as Free, but Peter has not said so. | D×L 12, index 2.0 | Small, ships with `prices-and-trip-total` | Needs `prices-and-trip-total`. Not a third-party price feed. Tier open. Job 190 ships only the comparison with last time's price in the price panel (“0,30 € teurer als zuletzt”), Free behind the same flag, until Peter re-tiers it; no prefill, no history view. |
| Siri AI app actions (App Intents) | `siri-ai-app-actions` | Let the new Siri (Apple Intelligence) use Snacklist's actions and list content through App Intents. Example: Anna asks Siri to put milk and eggs on the Rewe list, then asks what is still on it. Candidate actions, chosen at build time: add one or more items to a named or the default list, read a list, tick items. | Free, like `siri` (Siri is free, Decisions in force) | Not scored | Not estimated. A Flutter app needs a thin native layer over Dart; the existing native Siri (job 51) already has `AddItemsIntent`, `ReadListIntent`, `OpenListIntent` and the `ItemSuggestion` entity in `app/ios/Runner/AppIntents/`, and no tick intent. | Decided 14 Nov 2026 12:55 CET (Peter, t871u). **No implementation now.** Timing: start the build about 1 to 3 months before Siri AI reaches EU users, or before a Snacklist US launch, whichever comes first, and not before. The EU availability date is unknown as of 14 Nov 2026; the lead checks it monthly. Platform state (VGV, [“Siri AI: is your app ready?”](https://verygood.ventures/blog/siri-ai-is-your-app-ready/), 9 Nov 2026): Apple opened the Siri AI developer preview to all apps on 3 Nov 2026 (iOS 27.3 beta); during the preview it runs only in dev-signed builds and internal TestFlight, on Apple Intelligence devices, and the API may change; App Store submissions and customer access open in spring 2027. Builds on `siri`. |

## Considering

Not decided for a build slot. Strict: none of these are in the code. Receipt scanning's vendor path is recorded (U2B / Legal option R1) but is not approved to build. Spend history, planned vs bought and receipt scanning stay candidates (11 Nov 2026 20:42). The grocery log moved to Built, gated off (job 199, 13 Nov 2026).

| Name | Slug | What it is / example | Tier | Impact | Cost | Deps / decisions |
| --- | --- | --- | --- | --- | --- | --- |
| Receipt scanning (cloud LLM) | `receipt-scanning` | Photograph a German grocery receipt; match lines to ticked items; store confirmed prices; later graphs. Example: Anna scans the Rewe receipt, confirms “H-MILCH 3,5% ↔ Milch, €1.19”, and later sees Milch over time. On-device receipt OCR is dropped. Path: Vertex AI `gemini-3.5-flash` in `europe-west3` under Google Cloud EMEA Ltd's CDPA (U2B / Legal option R1). | Premium (later, after prices, spend history, and related features) | Shopper D×L 12, index 1.33; cost-tracker D×L 15, index 1.67 | Build ~2–3 weeks plus Legal path (?). Vendor and region recorded; per-use cost is an estimate only. | Decision recorded 11 Nov 2026, 21:39 and 21:51 Europe/Berlin. **Approved for docs only; no build yet; no real receipts until N-135..N-144 met; policy/in-app text needs Peter's approval.** Artifact: [legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md](legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md). No terms signed without Peter. |
| Planned vs bought (candidate) | `planned-vs-bought` | After a trip, compare what was on the list with what the receipt says was bought, for people who want less impulse buying or simply more awareness of spending. Compares a snapshot of the list taken when shopping starts, not the list as edited later, against confirmed receipt purchases. Example: the list had milk and bread; the receipt shows milk, bread and snacks, so snacks show as unplanned, with their price as unplanned spend when prices are available. | Not decided. Named as a later Premium pitch line (`premium-pitch`). | Qualitative: spending awareness. Not scored. | Not estimated yet | Builds on `receipt-scanning` plus matching purchases to list items. Idea recorded 11 Nov 2026 08:09 Europe/Berlin; not an approved build and not a launch or sales prerequisite. Neutral wording: no health or moral judgments about what was bought. Examples use made-up data, never real user data. Prototypes (job 196, 12 Nov 2026): five approaches in [design/planned-vs-bought/](design/planned-vs-bought/), compared against ticked or logged purchases with a receipt only as an optional later input; recommended `trip-review-unplanned`, waiting for Peter's pick (job 197). |
| Spend history and graphs | `spend-history` | Prices over time, spend per trip or month. Example: “We spent €87 at Rewe this month.” | Premium (insights) | D×L 12, index 0.8 (slow payoff) | Build after `prices-and-trip-total`; storage small | Needed if `receipt-scanning` shows graphs. Weeks of use before it feels valuable. |
| Arrival reminders | `arrival-reminders` | A nudge when you arrive at the store. Example: “You are at Rewe, 4 items open.” | Free (AR1, 11 Nov 2026 20:59). *Superseded:* Premium. | D×L 12, index 2.0 | 1–2 weeks (?); no cloud | Location permission. Only helps people who sometimes shop. |
| Themes | `themes` | A different look for the list. | Premium thank-you, cosmetic, not a convenience (TH1, 11 Nov 2026 20:59) | D×L 10, index 5.0 | Cheap if designed | Does not lead a pitch. Not approved to build. |
| Recipe to list | `recipe-to-list` | Paste or photograph a recipe; ingredients become items. | Premium, later | D×L 16, index 1.8 | 2–4 weeks (?) | Fits a family list, but parsing is messy. Not day one. |
| Watch glance | `watch-glance` | The list on a watch. Paywall copy already mentions Apple Watch as later, not built. No watch target in the tree. | Free-leaning when built (earlier lean) | D×L 12, index 3.0 | A real watch app, not a small job | Do not advertise until it exists. |

Receipt scanning's path is recorded (U2B / Legal option R1, 11 Nov 2026): Vertex AI `gemini-3.5-flash` in `europe-west3` under Google Cloud EMEA Ltd's CDPA. It is approved for docs only; there is no build approval; no real receipts until N-135 to N-144 are met; policy and in-app text still need Peter's approval. Not legal advice; no vendor terms signed without Peter.

## Dropped

Closed. Do not plan work here unless Peter re-opens it. Price-insight posts and on-device receipt OCR were dropped on 10 Nov 2026. Weekly billing was rejected with the yearly-plan decision.

| Name | Slug | Why it is closed |
| --- | --- | --- |
| Public price-insight posts (including Destatis-only posts) | `public-price-insights` | Peter dropped price insights. Legal had also said not to use user prices for posts without a separate opt-in, and not to treat aggregates as anonymous. |
| On-device receipt OCR | `on-device-receipt-ocr` | Peter dropped this approach. Receipt scanning, if built, is a cloud LLM path, not on-device parsing of the whole receipt. |
| Weekly auto-renew and 7-day pass | `weekly-billing` | No short-term tier at launch. Weekly auto-renew looks like a dark pattern. A 7-day pass would need custom expiry on iOS (exception to “use RevenueCat as intended”). |
| Open Prices hint | `open-prices-hint` | No reliable German shelf-price feed; already not recommended. |
| Store offers / loyalty cards | `store-offers` | Does not fit a family grocery list: running data-licence costs, and it is a flyer product. Keep out of Lifetime. |
| AI meal plan | `ai-meal-plan` | Does not fit positioning (“do not lead with unasked-for AI”). Running cost; keep out of Lifetime. |
| Pantry-photo suggestions | `pantry-photo-suggestions` | Unasked-for cloud vision; weak Hormozi score (index 0.44). Does not fit. |

## Open decisions

Already answered and not re-asked: `yearly-plan` (€24.99), `lifetime-plan` (€149.99), `barcode-free-limit` (unlimited in Free; `five-free-scans` superseded), `free-convenience-no-running-cost`, `prices-and-trip-total` is Free, the CS1 tiers of shelf-label scanning, arrival reminders, themes and user photos, `lifetime-revenue-math`, `premium-pitch`, `ai-suggestions-cost-example`, `dec1-paid-launch`, `validation-plan` (pass bars are Peter's), `store-prices-ops`, `fable-review-deferred`, drop `public-price-insights`, drop `on-device-receipt-ocr`, Siri free, `per-user-premium`, `prices-remain-on-lapse`, `product-images`, `household-limit` (Peter’s 11 Nov answer labelled Q157 was this cap, not a receipt-scanning decision), `sales-prerequisite` (now `premium-differentiation`; shelf-label scanning and free price entry do not gate sales), `receipt-scanning` path (U2B / Legal option R1, recorded 11 Nov 2026 21:39 and 21:51 Europe/Berlin; docs only).

1. **Which differentiated Premium slice is required for the paid launch** (`premium-differentiation`)? Evaluate the built public API and MCP first. Whatever is chosen must be built before 1 Dec (`dec1-paid-launch`).
2. **Lifetime allowances** (`lifetime-allowances`): the numbers for costly processing and API use, after a cost check. Not unlimited; no numbers are set yet.
3. **Shared views** (`shared-views`): still a lean, not a firm approval. With prices Free, what (if anything) a shared view would unlock is open.
4. **Last-price memory tier**: not re-tiered on 11 Nov; Free under `free-convenience-no-running-cost` reads as likely (?), but Peter has not said so.
5. *Answered 13 Nov 2026 (t830u):* grocery-log history beyond 4 weeks is Premium; logging and the last 4 weeks stay Free (`grocery-log`).

6. **Receipt scanning build and conditions** (path recorded, not approved to build). Vendor path is U2B / Legal option R1: Vertex AI `gemini-3.5-flash` in `europe-west3` under Google Cloud EMEA Ltd's CDPA. Status: approved for docs only; no build yet; no real receipts until N-135 to N-144 are met; policy and in-app text need Peter's approval. No terms signed without Peter.
7. **Public API extensions** (candidates for `premium-differentiation`; what is needed for sale is built before 1 Dec, `dec1-paid-launch`): still PATCH name/quantity/brand and api.snacklist.app first, then prices, barcode and image upload, then a changes feed, webhooks and OAuth? Shelf-label scanning is not a sales gate.
8. **US barcode fallback:** only after measuring Open Food Facts miss rate on real scans, then USDA FoodData Central for names only (no pack photos)?
9. **Fair-use terms:** send Legal’s draft (EN + DE, with N = 20, “du”) as the terms and paywall line, adjusted to a 20-household membership cap per user on both Free and Premium, and rewrite the stale “one household” paid-terms section before sale? Do not publish in the change that lands this file.
10. **Next considering feature** (judged by `premium-differentiation` and the 1 Dec paid launch): user photos (Premium; needed for a fuller `product-images` day-one story), spend history (Premium), arrival reminders (Free since AR1, so not a Premium slice), or receipt scanning (path recorded, not approved to build)? Shelf-label scanning ships later when ready and does not gate this choice or sales.

## Legacy IDs

Older notes used letter-and-number codes. They are kept here only so earlier chats, reviews and memos can be traced. Use the names and slugs above in new work; do not learn this as a second code set. The code-backed inventory of shipped behavior (verify-snacklist feature files) is separate and is not renamed by this map.

| Legacy ID | Slug | Name |
| --- | --- | --- |
| F1 | `list-and-live-sync` | List and live sync |
| F2 | `categories` | Categories |
| F3 | `aisle-layout` | Aisle / store layout |
| F4 | `app-and-web` | App and web |
| F5 | `alexa` | Alexa |
| F6 | `home-screen-widgets` | Home-screen widgets |
| F7 | `multi-household` | Multi-household |
| F8 | `dictation` | On-device dictation and parse |
| F9 | `siri` | Siri |
| F10 | `mcp` | MCP / AI assistants |
| F11 | `public-api` | Public REST API |
| F12 | `prices-and-trip-total` | Prices and trip total |
| F13 | `spend-history` | Spend history and graphs |
| F14 | `arrival-reminders` | Arrival reminders |
| F15 | `user-photos` | User photos |
| F16 | `themes` | Themes |
| F17 | `recipe-to-list` | Recipe to list |
| F18 | `no-ads` | No ads |
| F19 | `barcode-scan-to-add` | Barcode scan-to-add |
| F20 | `watch-glance` | Watch glance |
| F21 | `store-offers` | Store offers / loyalty cards (dropped) |
| F22 | `ai-meal-plan` | AI meal plan (dropped) |
| F23 | `catalog-photos` | Catalog photo (Open Food Facts) |
| F24 | `item-icons` | Item icons |
| F25 | `last-price-memory` | Last-price memory |
| F26 | `open-prices-hint` | Open Prices hint (dropped) |
| F27 | `shelf-label-scanning` | Shelf-label scanning |
| F28 | `receipt-scanning` | Receipt scanning |
| F29 | `usuals` | Usuals and “Need these again?” |
| UA1 | `per-user-premium` | Per-user Premium |
| PB2 | `shared-views` | Shared views (leaning, not firm) |
| LP1 | `prices-remain-on-lapse` | Prices remain on lapse |
| IM1 | `product-images` | Product images |
| LA1 | `sales-prerequisite` | Sales prerequisite (shelf-label hold superseded 11 Nov 2026 07:23; prices-before-sale superseded 20:42 by `premium-differentiation`) |
| PR1 | `yearly-plan` | Yearly plan, no weekly tier |
| LT1 | `lifetime-plan` | Lifetime plan |
| SC1 | `five-free-scans` | Five free barcode scans a day (superseded 11 Nov 2026 20:54 by `barcode-free-limit`, CS1) |
| HH20 / Q157 cap | `household-limit` | Household limit (20 per user, both tiers) |
| PI* | `public-price-insights` | Public price-insight posts (dropped) |
| R1 | `on-device-receipt-ocr` | On-device receipt OCR (dropped) |
| PR2 / PR3 | `weekly-billing` | Weekly auto-renew and 7-day pass (dropped) |
| C7 | `pantry-photo-suggestions` | Pantry-photo suggestions (dropped) |

## Sources and method

- Code check: `origin/main` `764265b0`, 13 Nov 2026.
- Decisions in this revision: 11 Nov 2026 07:23–07:25 Europe/Berlin (`household-limit`, `sales-prerequisite`, topic slugs); 11 Nov 2026 21:39 and 21:51 Europe/Berlin (`receipt-scanning` U2B / Legal option R1, docs only); 11 Nov 2026 20:42–21:26 Europe/Berlin (t788u, t789u, t791u, t792u, t-PM-2115, t796u: pricing, CS1 tiers, `grocery-log`, planning slugs), recorded in job 194 from the lead's brief. The living Page was not read and this map is not cross-checked against it yet.
- Added 14 Nov 2026 (job 235): `siri-ai-app-actions` in Planned (decided), Peter t871u, 12:55 CET. Source: Very Good Ventures, https://verygood.ventures/blog/siri-ai-is-your-app-ready/ (9 Nov 2026), checked against the post on 14 Nov 2026 (job 235 review).
- Legal background: Legal Review's Premium review of 10 Nov 2026 (`reviews/2026-11-10-snacklist-premium.md`, not in this repo). N-127 cloud receipt scanning review and Addendum A: [legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md](legal/reviews/2026-11-11-snacklist-n127-cloud-ocr.md) (in this repo). The path is recorded; it is not a build approval.
- Hormozi scores from the 10 Nov 2026 value and follow-up reports.
- Living view: https://cursor.com/canvas/store-1bba9ee2-e28e-47ad-a6b5-ea80faa6498b/1ee9370d-3e32-4854-bc33-cb4729a84b14
- Nexus: https://nexus.snacklist.app
- Code-backed inventory: [FEATURE_MAP.md](FEATURE_MAP.md)

Not legal advice. Product name: Snacklist.
