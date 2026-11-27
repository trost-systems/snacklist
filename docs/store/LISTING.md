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
- No price, no "kostenlos"/"free", no AI brand names (only "KI-Assistenten, die MCP unterstützen" / "AI assistants that support MCP"),
  Siri only through a Shortcut set up once, no widget, Apple Watch, Google Assistant, push, recipes or price tracking, no retailer or
  competitor names, no "hexagon".
- Alexa (Legal N-366, 22 Nov 2026; the skill is live in de-DE and five English locales since 16 Nov):
  - Name it „der Snacklist-Skill für Alexa“ / "the Snacklist skill for Alexa", never "Amazon Alexa". Say what the skill lets the user
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
