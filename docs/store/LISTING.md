# Store listing copy

Ready-to-paste texts for the App Store and Google Play, German (de-DE) and English (en-US), written from
`.cursor/skills/verify-snacklist/features/FEATURES-FOR-WRITERS.md`, `docs/PURCHASES.md`, `docs/SPEC.md`,
`releases/flags.json` and `app/l10n/app_de.arb`. Nothing here is uploaded. A person pastes it into App Store
Connect and the Play Console after Legal's check.

## How to use

- Files are in fastlane deliver layout under `app/fastlane/metadata/`. One file is one field; the file's text
  is the field's value (a trailing newline is not part of it).
- iOS: `<de-DE|en-US>/{name,subtitle,keywords,promotional_text,description}.txt`.
- Android: `android/<de-DE|en-US>/{title,short_description,full_description}.txt`.
- In-app products: `iap/<de-DE|en-US>/{yearly,lifetime}.txt`, display name on line 1, description on line 2.
  Yearly is `com.snacklist.app.yearly` (auto-renewing, 1 year), Lifetime `com.snacklist.app.lifetime` (one-time).
- Check limits and Legal's word rules: `node app/fastlane/metadata/check.mjs` (exits 1 on a breach, prints the table below).
- The Play description has no Siri line (Siri is iPhone only) and names Google Play and the Google account for the
  subscription terms; the App Store description names Apple's EULA and the Apple account.

## Launch build facts the copy follows

- Categories are hidden for everyone (`hide-categories` on): no copy mentions categories, sorting into them or ordering them.
  The list is described as split by store only. No draggable order is promised.
- HP2 (Peter, 22 Nov 2026): prices, totals, trip mode and History („Verlauf“) are off for everyone at launch (flags
  `prices-and-trip-total`, `total-priced-only`, `trip-mode`, `grocery-log`). No field names them: no „Preise notieren“,
  „Einkaufssumme“, „Einkaufsmodus“, „Verlauf“, „bezahlte Beträge“, "log a trip", and no `preise`/`verlauf`/`prices`/`history`
  keyword. Put one back only in the PR that turns its flag on for everyone. `check.mjs` refuses these words.
- No price, no "kostenlos"/"free". Brand names follow BN-1 (section "Brand rule BN-1" below, status in `docs/store/BRAND_LIVE.md`,
  checked by `scripts/store-brands.ts`): never in the name, subtitle, keywords, promotional text, Play title, Play short description or
  in-app purchase texts; in a long description only while `BRAND_LIVE.md` marks the brand live, and then in BN-1's wording. No brand is
  live yet, so AI assistants stay generic („KI-Assistenten, die MCP unterstützen“ / "AI assistants that support MCP"), and Siri only
  through a Shortcut set up once. No widget, Apple Watch, Google Assistant, push, recipes or price tracking, no retailer or
  competitor names, no "hexagon".
- Alexa (Legal N-366, 22 Nov 2026; the skill is live in de-DE and five English locales since 16 Nov):
  - Replaced by BN-1 (2026-11-27) for the name: only „Snacklist-Skill für Amazon Alexa“ / "Snacklist skill for Amazon Alexa". The
    N-366 form „der Snacklist-Skill für Alexa“ / "the Snacklist skill for Alexa" in today's descriptions is in
    `scripts/store-brands.baseline.json` until a Legal copy job changes it. Say what the skill lets the user
    do („Mit dem Snacklist-Skill für Alexa fügst du …“), never "Alexa does …".
  - An example sentence starts with "Alexa," (never "Hey Alexa") and must work exactly as written in the certified skill
    (`docs/ALEXA.md`, `alexa/skill-package/interactionModels/custom/`). The descriptions carry none today.
  - "Alexa" stays out of the name, subtitle, Play short description and keywords (Apple 2.3.7); the long descriptions may name it.
  - A description naming Alexa ends with the trademark notice. App Store: „Siri ist eine Marke von Apple Inc. Amazon, Alexa und alle
    zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen.“ / "Siri is a trademark of Apple Inc. Amazon,
    Alexa, and all related marks are trademarks of Amazon.com, Inc. or its affiliates." Play: only the Amazon sentence.
  - Text only: no Alexa logo, no "Just Ask Alexa" badge, no Echo image in any screenshot, feature graphic or preview. Store videos show no
    Alexa until Amazon's review of them; at most a still of Snacklist's own "Amazon Alexa" connection screen.
  - The skill pages (support pages and the site) come from `ALEXA_SKILL_URLS` in `site/config/stores.mjs`, not the listing.
- Alexa is free in the launch build: the newest `public.integration_gate` never locks `'siri'` or `'alexa'`
  (`supabase/migrations/20261115100000_key_checks_without_waiting.sql:196`), and the alexa function never asks for Premium. Hence
  „Siri, Alexa und die Liste selbst brauchen kein Premium.“ (Play: „Alexa und die Liste selbst …“).
- Premium, see the next section.

## Brand rule BN-1

Peter approved BN-1 on 2026-11-27 08:57 Europe/Berlin. It replaces the 2026-10-31 "no assistant brand named" rule
(Legal N-80..N-86, "no marketing strings naming Claude; keep the brand-free AI line"). Copied verbatim from Legal Review
`2026-11-26-snacklist-715-release-notes.md`, section "LH4.2 Rule BN-1 (paste-ready)". Each brand's status is in
`docs/store/BRAND_LIVE.md`; `scripts/store-brands.ts` checks the listing texts against both (`--publish` on the day a
text goes public).

> **BN-1: naming other companies' products (Snacklist). Replaces the 2026-10-31 "no assistant brand named" rule when Peter approves. Applies to Siri (Apple), Alexa (Amazon), Claude (Anthropic), ChatGPT (OpenAI) and every future brand.**
>
> **1. Trigger (all must hold, checked on the day the text goes public).** The integration is public and works for an **ordinary user** (fresh account in Germany, not a tester or admin, on the plan the text names), in the countries the text covers. "In review", "approved but not published", "certified but not enabled" and "coming soon" do not count. Plans and countries that do not work must be named in the text or left out.
> **2. Who verifies, and how.** Ops runs the end-to-end check on the day and saves dated proof (URL, screenshot, account type, time); Engineering Lead confirms in writing; Legal Review records a hash-bound brand check for the exact text. The result goes into `docs/store/BRAND_LIVE.md` (one row per brand: URL, last verified date, proof path, texts that depend on it). Re-verify on each store release and weekly while a brand is named.
> **3. Surfaces.**
> - **Never, for any brand:** app name, subtitle, keywords field, promotional text, Play title and short description, screenshots, preview videos, captions and media file names, in-app purchase names and descriptions, paywall and Premium benefit lines, logos, badges, icons.
> - **Allowed for a brand that meets the trigger:** store release notes and long description (one plain mention per brand per text), website (landing, guides, support, FAQ), in-app setup and how-to screens (for example "connect Snacklist to Claude"), social posts (plain text, no @-tags or hashtags of the brand, no reposted brand artwork).
> - **Claude on marketing surfaces** (release notes, store description, landing, social, email) needs Anthropic's written OK for the exact wording first, because its Directory Terms bind us to its Trademark Guidelines. How-to guides, support and in-app setup need no OK.
> - **Premium benefit lines name the capability, not the brand**: "KI-Assistenten, die MCP unterstützen".
> **4. Phrasing.** Use only: "in [Brand]" / "available in [Brand]", "für [Brand]", "mit [Brand] nutzen" (Siri: "per Siri-Kurzbefehl" until the native device test has passed, then "mit Siri"); Alexa only as "Snacklist-Skill für Amazon Alexa" / "Snacklist skill for Amazon Alexa". Never: "Works with Alexa" (a certified badge), "works with" or "compatible with" for ChatGPT or Claude, "partner", "official", "certified", "recommended by", "powered by", "built with", "by [Brand]", "[Brand] app" for our own product, a brand inside a product or feature name, "Alexa-Snacklist", Alexa as verb, possessive or plural, a brand more prominent than "Snacklist", ™ or ®, translated brand names, a brand's slogans.
> **5. Trademark notices.** The imprint names every brand we name (Siri/Apple, Alexa/Amazon, Claude/Anthropic, ChatGPT/OpenAI, Google Play and Android). The App Store release notes and description carry the notice sentences for the brands named in that text: "Siri ist eine Marke von Apple Inc." / "Amazon, Alexa und alle zugehörigen Marken sind Marken von Amazon.com, Inc. oder seinen verbundenen Unternehmen." / "Claude ist eine Marke von Anthropic." / "ChatGPT ist eine Marke von OpenAI." (EN equivalents). Where space is short (Play release notes) the notice may stay in the listing and imprint. No ™ or ®.
> **6. Premium and plan qualifiers.** Every line that names an AI assistant or the API carries "mit Snacklist Premium" / "with Snacklist Premium" as long as the integration lock is on, and is used only while Premium can be bought. Lines for Siri and Alexa never mention Premium and must not share a sentence with the Premium line. A plan or country limit on the other side (for example ChatGPT plans) is named ("je nach ChatGPT-Tarif und Land") unless the day-of check shows it works for every plan and country the text covers.
> **7. Removal.** A brand comes out of every surface it is on **within one working day** (store texts at the next update, or at once on Play and the website) when: the listing, plugin or skill is delisted, rejected, paused or disabled; the brand owner objects; a plan, country or Premium change makes the claim untrue; or the weekly check fails. Engineering Lead owns the removal; Ops owns the weekly check; the `BRAND_LIVE.md` row is updated the same day.
> **8. Keyword and metadata ban.** No brand name in the App Store keywords field, app name, subtitle or promotional text, and none in the Play title, short description or tags (Apple 2.3.7; Play metadata policy). Brand names in URLs only in how-to slugs (for example `/guides/claude`), never in titles or paths of marketing pages.
> **9. Future brands.** A brand not named above is generic-only until Legal Review adds a row to this rule after checking (a) the owner's trademark and brand guidelines, (b) the platform or directory terms we accepted, (c) plan and region limits, (d) the notice sentence, (e) the live check. No new question to Peter is needed if the brand passes; a brand that fails stays generic.

## Snacklist Premium in the listing

A listing claims only what the launch build gates. Peter's pitch (P3a, `docs/PRODUCT_FEATURE_MAP.md`) also names an export, which the
app does not have as a Premium feature, so no field names one:

- History and the planned-and-paid comparison, the earlier Premium bullets, are off (HP2) and gone.
- AI assistants (MCP) and the API need the account's own Premium: the server switch `integration_lock` is on in production since
  2026-11-24 (testers keep access). The `integration-lock` hold in `releases/flags.json` stays unreleased until the 1 December go-live, and
  until then no field lists them under Premium (Legal N-354).
  `check.mjs` reads the hold: unreleased, a Premium paragraph naming MCP or the API fails; released, one without them fails.
- There is no Premium export. The account export „Meine Daten exportieren“ (`export_my_data`) is the GDPR copy everyone gets and is never a
  Premium benefit.
- No themes or user photos exist in the app; nothing about them.
- Lifetime is a plan: the same features as the yearly plan, bought once.

So until the lock is released the Premium paragraph names the plans only (as committed). When it is released, replace the paragraph's first
line in all four descriptions with:

```text
Snacklist Premium gibt es jährlich oder als einmaligen Kauf (Lifetime, mit denselben Inhalten wie das Jahresabo). Es schaltet frei:
• KI-Assistenten, die MCP unterstützen, mit deiner Liste verbinden
• Eigene Automationen mit der Snacklist API
```

```text
Snacklist Premium comes as a yearly subscription or a one-time purchase (Lifetime, with the same features as the yearly plan). It unlocks:
• Connect AI assistants that support MCP to your list
• Your own automations with the Snacklist API
```

and add „Der Zugang für KI-Assistenten gehört zu Snacklist Premium.“ / "Access for AI assistants is part of Snacklist Premium." to the
end of the KI-ASSISTENTEN / AI ASSISTANTS paragraph. The bullets are the Premium page's `premiumBenefitAi` and `premiumBenefitApi`.

## Character counts

| file | what | count | limit |
| --- | --- | ---: | ---: |
| `de-DE/name.txt` | chars | 24 | 30 |
| `de-DE/subtitle.txt` | chars | 25 | 30 |
| `de-DE/keywords.txt` | chars | 83 | 100 |
| `de-DE/promotional_text.txt` | chars | 118 | 170 |
| `de-DE/description.txt` | chars | 2729 | 4000 |
| `android/de-DE/title.txt` | chars | 24 | 30 |
| `android/de-DE/short_description.txt` | chars | 67 | 80 |
| `android/de-DE/full_description.txt` | chars | 2366 | 4000 |
| `en-US/name.txt` | chars | 24 | 30 |
| `en-US/subtitle.txt` | chars | 22 | 30 |
| `en-US/keywords.txt` | chars | 83 | 100 |
| `en-US/promotional_text.txt` | chars | 130 | 170 |
| `en-US/description.txt` | chars | 2534 | 4000 |
| `android/en-US/title.txt` | chars | 24 | 30 |
| `android/en-US/short_description.txt` | chars | 64 | 80 |
| `android/en-US/full_description.txt` | chars | 2237 | 4000 |
| `iap/de-DE/yearly.txt` | name | 26 | 30 |
| `iap/de-DE/yearly.txt` | description | 39 | 45 |
| `iap/de-DE/lifetime.txt` | name | 26 | 30 |
| `iap/de-DE/lifetime.txt` | description | 31 | 45 |
| `iap/en-US/yearly.txt` | name | 24 | 30 |
| `iap/en-US/yearly.txt` | description | 37 | 45 |
| `iap/en-US/lifetime.txt` | name | 26 | 30 |
| `iap/en-US/lifetime.txt` | description | 35 | 45 |

Limits used: App Store name 30, subtitle 30, keywords 100, promotional text 170, description 4000; Play title 30, short description 80,
full description 4000; in-app product display name 30 and description 45 (App Store). Play's limits for in-app products
(name 55, description 80) are looser, so the same texts meet them. Counts are Unicode code points (`[...text].length` in the check).
Keywords: comma separated, no spaces, none repeats a word of the name or subtitle, none is a trademark, competitor or retailer name
(so no Siri, Alexa, Amazon, Apple or Google keywords either); `check.mjs` enforces this.

## What each file replaces

The repo holds no listing yet, so nothing in the repo is replaced. In the consoles:

| File | Console field it replaces |
| --- | --- |
| `<loc>/name.txt`, `subtitle.txt`, `keywords.txt`, `promotional_text.txt`, `description.txt` | App Store Connect, version page for the locale: Name and Subtitle (App Information), Keywords, Promotional Text, Description |
| `android/<loc>/title.txt`, `short_description.txt`, `full_description.txt` | Play Console, Main store listing for the language: App name, Short description, Full description |
| `iap/<loc>/yearly.txt`, `lifetime.txt` | App Store Connect, the product's localization (Display Name, Description), and Play Console, the product's name and description; the old English-only de-DE Lifetime text ("Unlocks premium for your household, once.") |

The in-app product texts say what Premium is tied to without naming the household: "Für dein Konto" / "For your account".
Reason: `docs/PURCHASES.md` "Per-user Premium" (job 185) has the buyer hold Premium in every household they are in.

## Open questions for Legal and Peter

1. Household or account. Settled for the page by Legal N-348 to N-350 and N-362 to N-365: `premiumHeroBody` „Snacklist Premium gilt
   für dich, in jedem Haushalt, in dem du Mitglied bist.“ The in-app product texts say "Für dein Konto" / "For your account"; the listings
   say nothing about households.
2. AI assistants inside Premium. Still unreleased (`integration-lock`): see "Snacklist Premium in the listing". With HP2 the launch
   Premium paragraph names no benefit at all. The lock is on (Peter TL-A, 24 Nov); paste the block when the hold is released on 1 December.
3. The Snacklist API. The Premium page also lists "Eigene Automationen mit der Snacklist API", which the lock covers. The listings leave
   the API out (the earlier caption rules, N-187 to N-195, keep it out of the screenshots). Legal decides whether the description names it.
4. Premium on sale. The texts name Premium as an optional in-app purchase and say nothing about a price, so they hold on any day. FEATURES-FOR-WRITERS
   says nothing is on sale yet. The Play listing goes live at or before the sale, never after it (Legal LK1, 26 Nov 2026): the purchase screen
   (`premium_offer`) opens only once `play-listing.yml` `mode=check` passes (`docs/RELEASE.md`, "Store listing upload"; `docs/PAYWALL_RELEASE.md` 5.4).
5. Subscription disclosure block. The auto-renewal paragraph is the app's `premiumYearlyTerms` text, adapted per store (Apple account or
   Google account, the store's subscription settings). It is marked pending in the ARB; Legal approves it. The App Store needs a working privacy
   policy link and a terms link. Per Legal L24-6 (option A) the en-US and de-DE App Store descriptions carry these two lines
   (verbatim, U+2019 in "Apple’s"), directly under the privacy policy line (URL unchanged) and directly before the Siri/Alexa trademark
   notice of item 6, which stays the last line (Legal, 24 Nov 2026; N-366). `app/fastlane/metadata/{en-US,de-DE}/description.txt` carry them:
   en-US: `Terms of Use: https://snacklist.app/en/terms` and
   `Apple’s Licensed Application End User License Agreement: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.
   de-DE: `Nutzungsbedingungen: https://snacklist.app/nutzungsbedingungen` and
   `Standard-Lizenzvertrag von Apple (Licensed Application End User License Agreement): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.
   The custom EULA field in App Store Connect stays empty (our terms are not pasted into it). The privacy policy goes in the App
   Privacy URL field. Google Play takes the privacy policy in the Play Console field; the
   link in the text is a convenience. The English page paths are from `site/content/legal`; confirm they are live on release.
6. Trademarks. Settled by Legal N-366 (22 Nov 2026): the notice wording, the skill's name and the Alexa bullet as above; Legal re-checks
   the hashes before upload.
7. Siri line. "Siri: mit einem Kurzbefehl, den du einmal einrichtest (Anleitung auf snacklist.app, bisher auf Deutsch)" matches the
   Shortcut's state (German only, no setup-free Siri). Remove it if Legal wants Siri off the App Store text; the Play text has none.
8. Voice claim. "Die Spracherkennung läuft auf dem Gerät" follows FEATURES-FOR-WRITERS "Dictation", which was read from code, not run on a
   real device ("Unverified"). Verify on an iPhone and an Android phone before upload.
9. Age rating. The listing assumes 16+ in the consoles; no text names the age.
10. Promotional text may change without a new review on the App Store; the other fields need a version.
11. The English description says "Access" for „Zugänge“, as the English app does; check it on the release build.

## Store-upload gate list

Open items that must be closed before any store upload:

- N-438: re-film the en-US `1-add-tick.mp4` (it shows the German suggestion „Honig“ at about 4.6 s), plus any site clip cut from the same take, before upload.
