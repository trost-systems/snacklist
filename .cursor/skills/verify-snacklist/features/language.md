# App language

The app speaks German or English. By default it follows the device's preferred languages (English when the device prefers neither, job 245; a French phone with German further down its list reads German). Under Mehr → Einstellungen → Sprache the user can pick „Deutsch“ or „English“ instead. The switch applies live to the whole UI (labels, snackbars, category names of the default categories) without a restart and is stored on the device, also across sign-out. The account keeps only the mail language: the language the app shows is saved as `mail_locale`, so sign-in and confirmation mails follow it (sign-in, `mail-language`).

## Sub-features

- `language-system` „Wie Gerät“ with the line „Gerade Deutsch“ / "Currently English" (the language the device gives).
- `language-de` „Deutsch“ (its own name in every UI language).
- `language-en` „English“ (its own name in every UI language).
- `language-persist` kept on the device across reload and sign-out; the pick is not part of the account and does not move to other devices (only the mail language is saved to the account).

## How to get to it (user POV)

- „Mehr“ / "More" → „Einstellungen“ / "Settings" → row „Sprache“ / "Language" (subtitle: the pick, or „Wie Gerät (Deutsch)“ / "Device language (English)" when following the device) → list page titled „Sprache“ / "Language" with radios „Wie Gerät“ / "Device language" (subtitle „Gerade {language}“ / "Currently {language}"), „Deutsch“, „English“.
- Deep link `/more/settings/language`. On wide screens the list opens beside the More list, with a back button next to the title.

## Driving it with Playwright

Preconditions:

- Seeded household, signed in, German browser locale (de-DE), on the list.

- **Open the list.** `openMore(page, 'Einstellungen')`, then click `getByRole('button',{name:/^Sprache Wie Gerät \(Deutsch\)/})`. Observable: URL `/more/settings/language`, `getByRole('radio',{name:/^Wie Gerät/})` checked.
- **Switch to English.** Click `getByRole('radio',{name:'English', exact:true})`. Observable, live: `getByRole('heading',{name:'Language'})`, `getByRole('tab',{name:'List'})` visible.
- **Persist.** `page.reload()`: heading still "Language". Back (`getByRole('button',{name:'Back'})`): `getByRole('button',{name:/^Language English/})`. List: `getByRole('textbox',{name:'What do you need?'})`, and the default category shows its English name (`getByText('Chilled')`).
- **Back to German.** Tab `More` (it returns to the More page you left); on Settings click `button /^Language/`; then `getByRole('radio',{name:'Deutsch', exact:true})`: heading „Sprache“.
- **English browser.** With `test.use({locale:'en-US'})` the app starts in English without any pick, and no German UI text shows (see the second describe in the spec).
- Spec: `scripts/verify.sh --only e2e -- tests/shell-more.spec.ts`.

## Gotchas

- Only de and en exist. The first of them in the device's preferred languages wins (fr, en gives English; fr, de-CH gives German); English when neither is listed (job 245; German before). The web build sets `<html lang>` to the language shown (`app/lib/app/document_language.dart`), and the invite page `/join/<code>` picks its language by the same rule (`app/web/join/join.js`).
- `en-sweep` (job 245) the English app shows no German outside the household's own data: `node journeys/english-sweep.mjs <evidence dir>` on `demo-family-en` (launched with the trip-mode flags) screenshots and scans 27 screens (start, sign-in, list, add sheet, household sheet and page, invites and the invite sheet, stores, the trip question, strip and summary, Verlauf, More, Settings, Language, Premium, Account and the deletion dialog, feedback, Access, Tips, usage data, new household, join) for umlauts and common German words, and fails on any. Driven 2026-11-14 on commit of job 245: 0 screens with German; with `accessTitle` set to „Zugänge“ in app_en.arb it failed on 3 screens. `app/test/l10n/no_german_in_lib_test.dart` fails on a German string literal in `app/lib` (data word lists have an allow-list with reasons).
- Texts from the server do not follow this setting: the Siri Shortcut always answers in German (its requests carry no language), native Siri (held) sends its own language with each request, the Alexa skill answers in English on an English Alexa device and in German otherwise, the AI-assistant (MCP) tools answer in German (only the held Premium-lock message follows the client's Accept-Language), the Snacklist API's error messages (held) are English, and add-sheet catalogue rows (section „Aus dem Katalog“ / "From the catalog") are German words in both UI languages (driven 2026-11-01). The sign-in and confirmation emails do follow it: German for a German app, English otherwise (driven 2026-11-11, sign-in `mail-language`).
- The setting is per device: a fresh browser context starts on „Wie Gerät“.
- Einstellungen has a section heading „Sprache“ / "Language" too, so `heading 'Language'` is true on both pages: pair it with the URL check.
- Back-button names flip with the language („Zurück“ / "Back").
