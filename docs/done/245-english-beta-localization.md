# Job 245: English for the beta (2026-11-14)

Peter (Nov 14 21:10): "The beta must be english + german". A phone set to English now sees the
app in English everywhere the app itself writes text; German stays word for word. PR #467.

## What changed

- **Fallback language is English.** `resolveLocale` (`app/lib/app/language.dart`) takes the first
  de or en in the device's preferred languages, else English (was German). fr → English, fr +
  de-CH → German. The mail language (`mail_language.dart`) and the web invite page
  (`app/web/join/join.js`) use the same rule. `preferred-supported-locales: [de]` stays; the
  app's resolution callback decides, so it never forces German.
- **iOS permission prompts.** Microphone and speech recognition were German in every language
  (Info.plist). They now come from `InfoPlist.strings` in en, de and Base.
- **iOS widget gallery.** The example list (`HomeWidget.swift` `.sample`) is localized through
  the widget's `Localizable.xcstrings`.
- **Web shell.** `<html lang>` follows the language shown (`app/lib/app/document_language*.dart`).
  index.html and the manifest describe the app in both languages. The invite page's loading
  heading and noscript text follow the language. `app/web/delete-account.html` is the English
  twin of `konto-loeschen.html`; each links the other.
- **Hardware store chip.** Onboarding and „Neuer Haushalt“ offer „Baumarkt“ / "Hardware store"
  in the UI language (`storeHardware`); `add_store` already maps both to the hardware store.
- **English copy.** All 828 English values reviewed against the German: no German left, 55
  values reworded (list in `docs/DECISIONS.md`, "Job 245"; legal and pricing texts untouched).
  Tests, e2e and feature files follow the new wording.
- **Guards.** `app/test/l10n/no_german_in_lib_test.dart` fails on a German string literal in
  `app/lib` (allow-list with reasons for parser word lists). The verify-snacklist journey
  `journeys/english-sweep.mjs` drives 27 English screens and fails on German in any ARIA
  snapshot. A new `join-page.spec.ts` case checks the invite page on a French browser.

## How to verify

```bash
cd app && flutter test test/l10n test/app/language_test.dart test/settings/settings_screen_test.dart
VH_DEFINES="FLAGS_ON=trip-mode,grocery-log,prices-and-trip-total" \
  .cursor/skills/verify-snacklist/helpers/launch.sh --scenario demo-family-en --fresh
cd .cursor/skills/verify-snacklist && node journeys/english-sweep.mjs /tmp/en-sweep
.cursor/skills/verify-snacklist/helpers/drive.sh onboarding --lang en
```

## Results

- English sweep: 27 screens, 0 with German (`docs/screenshots/245/journey.log`). With
  `accessTitle` set to „Zugänge“ in app_en.arb the same run failed on 3 screens.
- English guided start: PASS; its 11 ARIA snapshots scanned clean; stores step shows "Hardware
  store" (`docs/screenshots/245/onboarding/`).
- `no_german_in_lib_test`: passes; a planted `'Zurück zur Liste'` fails it.
- `scripts/verify.sh --only e2e -- tests/shell-more.spec.ts tests/join-page.spec.ts`: 24 passed
  (shell-more's English test caught the renamed "Device language" radio in CI first).
- An independent in-session review (Opus, read-only) returned FIX on two copy items:
  `checklistShop` said "Finish a shopping trip" for a single tick (now "Go shopping once") and
  the writers' file still quoted "Total Lidl". Both fixed, with the claim-amount labels and the
  "Device language (English)" subtitle made consistent and a widget test for the English
  "Hardware store" chip. Screenshots re-recorded on that build.
- Full `flutter test` green after updating 4 English sync goldens. `scripts/verify.sh --only
  gitleaks,lint,flutter,web-prod`: passed. CI: see the PR.

Screenshots: `docs/screenshots/245/` (also `~/groceries-ops/jobs/245-english-beta-localization/out/`).

## Still German for an English user (not text the app writes, or behavior)

- **In-app dictation** listens in German (`de_DE`) and splits with the German parser. English
  dictation needs a per-language offline check in the native code: a feature, not a string.
- **Catalogue suggestions** in the add sheet („Aus dem Katalog“ rows) are German item names.
- **Old Siri Shortcut recipe** answers in German (its requests carry no language); native Siri
  sends its language.
- **MCP tool texts** (descriptions, errors) are German; only the Premium lock follows
  Accept-Language.
- **Data export** (`export_my_data`) writes category names as stored (German seeds).
- **`parse_item`** rewrites "1.5%" as „1,5 %“.
- **Store names** a German member created („Baumarkt“) show as typed, like any user data.
- **Privacy policy** (site, English) still links the German deletion page; switching it to
  `/delete-account.html` is a legal-text change.
- **English UK/US spelling mix** ("cancelled", "neighbours", "flat") in strings not touched here.

## For Ops (store side, not done here)

- App Store Connect: add an en-US localization (app name, subtitle, description, keywords,
  privacy policy URL `https://snacklist.app/en/privacy`, support URL
  `https://snacklist.app/en/support`) and TestFlight "What to Test" in English.
- Play Console: an en-US store listing; the account-deletion URL for the English listing can be
  `https://app.snacklist.app/delete-account.html` once it is deployed and Legal has read it.
- The iOS permission prompts change only in a new build: the next green main build after merge.
