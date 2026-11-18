# More tab, help, guides, legal pages

The app has two tabs, „Liste“ and „Mehr“ (EN "List", "More"), and a third, „Verlauf“ / "History", between them with the flag `grocery-log` on (internal testers; grocery-log): on phones a raised hex pill floating centred above the bottom edge (the selected tab on a honey hex; pages scroll on behind it), a left rail from 840 px width. Since job 85 (design "M-P2") „Mehr“ is a list of inset groups (cards with a 2 px contour): each row is a hexagon icon and one line of text, with no hint below it (the one exception, „Einkauf starten“, shows only with the flag `trip-mode` on). No group has a heading (job 203 removed the last one, „Rechtliches“). The legal rows (Impressum, Datenschutzerklärung, Nutzungsbedingungen, Lizenzen) are a group of their own directly on More, so the imprint is two taps from the list (Mehr, Impressum). Sign-out stands alone, in the same plain style as the other rows (not red); the version line ends the list. Entries either open a page inside the app (on wide screens beside the list, on phones as a full page with a back button) or open a page on the web in a new browser tab (those rows end in an external-link icon instead of a chevron). „Nutzungsdaten“ / "Usage data" is a page of its own with the usage-data switch.

## Sub-features

- `tabs` the two tabs and the wide-screen rail.
- `more-list` every More entry in order (below).
- `more-update-card` (key `more-update-card`) a lemon card on top of the list when an update is ready („Update bereit“ / „Neue Version da“ with „Neu starten“ / „Aktualisieren“ and a close button „Später“). No build checks for updates yet, so it never shows (job 85 stub); do not write copy about it.
- `more-wide` from 840 px More shows the entry list (360 px) on the left and the opened page beside it; „Zugänge“ is shown first by default.
- `help-link` „Hilfe & Kontakt“ opens the help page on snacklist.app (new tab).
- `more-usage-data` „Nutzungsdaten“ / "Usage data" (row key `more-usage-data`, only where the build can send analytics) opens the Nutzungsdaten page (`more-usage-data-page`, `/more/usage-data`, title „Nutzungsdaten“ / "Usage data"): only the switch (`analytics-switch`), no policy link.
- `more-legal` a group of direct rows without a heading, below „Hilfe & Kontakt“ and above „Abmelden“: „Impressum“ / "Imprint" (`more-imprint`), „Datenschutzerklärung“ / "Privacy policy" (`more-privacy-policy`), „Nutzungsbedingungen (EULA)“ / "Terms of Use (EULA)" (`more-terms`), „Lizenzen“ / "Licenses" (`more-licenses`). The first three open in a new tab; the app stays on More. `/more/legal` (the former Rechtliches page) lands on `/more`.
- `imprint-privacy` the imprint and the privacy policy on snacklist.app (new tab), from the legal rows; the imprint is two taps from the list (Mehr, Impressum). The login screen links both too.
- `terms` „Nutzungsbedingungen (EULA)“ opens Apple's standard EULA on iPhone; on Android and the web it opens the help page (/support, /en/support) as a placeholder until Snacklist has terms of its own.
- `licenses` „Lizenzen“ on More opens Flutter's license page, titled Snacklist with the version.
- `version` last line „Version 0.x.y (build)“ (a local build reads „Version 0.1.0 (1)“).
- `sign-out` „Abmelden“ ends the session and shows the login.
- `analytics-switch` „Nutzungsdaten und Fehlerberichte senden“ switch on the Nutzungsdaten page (only where the build can send analytics).
- `internal-install` long press on the version line toggles an internal-install mark (testers only).

More entries in order (groups top to bottom; rows: DE label, EN label; no hints; no group headings):

0. Only with the flag `trip-mode` on and no trip running (internal testers): „Einkauf starten“ / "Start a trip" with the hint „Die Uhr läuft ab jetzt, die Liste, wie sie jetzt ist, gilt als geplant.“, alone in the first group (trip-mode `tm-manual-start`; driven 2026-11-15 on c3ea4261 with the tabs „Liste“, „Verlauf“, „Mehr“).
1. „Konto“ / "Account" (opens Konto: export, deletion); „Snacklist Premium“ (both languages), only once Premium may be offered or for a household that has it (job 64).
2. The household's name ("Familie Brandt"; „Haushalt“ / "Household" when it has none), only when the user is in a household, opens the household page (`/more/household`, household-invites `household-page`); „Leute einladen“ / "Invite people", only when the user is in a household (opens Einladungen; see household-invites); „Archivierte Haushalte“ / "Archived households", hidden on normal builds (see Gotchas). With the flag `list-declutter` on (job 258) the household's name row and „Leute einladen“ are gone from More: the same controls (rename, members, invite, lists, currency, „Beitritte bestätigen“, „Haushalt verlassen“) are on the household page of the list tab's switcher sheet (list-declutter `ld-sheet`). (Job 78 moved „Kategorien verwalten“ and „Läden“ to the list header's „Anpassen“; see stores-walk-order and categories.)
3. „Zugänge“ / "Access".
4. „Einstellungen“ / "Settings"; „Nutzungsdaten“ / "Usage data" (only where the build can send analytics).
5. „Tipps“ / "Tips" (opens `/more/tips`, every tip to read again; see tips); „Feedback senden“ / "Send feedback" (with the flag `feedback-fb4` on, job 268: „Feedback & Ideen“ / "Feedback & ideas" with a forum icon and a count badge, opening the page `/more/feedback` instead of the form; see feedback); „Snacklist bewerten“ / "Rate Snacklist" (external-link icon, iPhone and Android apps only, opens the store page; see rate-snacklist); „Hilfe & Kontakt“ / "Help & contact" (external-link icon).
6. „Impressum“ / "Imprint", „Datenschutzerklärung“ / "Privacy policy", „Nutzungsbedingungen (EULA)“ / "Terms of Use (EULA)" (these three with the external-link icon), „Lizenzen“ / "Licenses".
7. „Abmelden“ / "Sign out", alone, plain like the other rows (job 137: not red).
8. Version line „Version {version}“ (same in EN), version plus build number in brackets when there is a build number.

The Nutzungsdaten page: only the switch „Nutzungsdaten und Fehlerberichte senden“ / "Send usage data and error reports" (its line below: „Pseudonym an PostHog (Server in der EU), ohne Listeninhalte. Gilt für dieses Gerät. Ausschalten löscht die Kennung auf diesem Gerät.“).

## How to get to it (user POV)

- Bottom tab „Mehr“ / "More" on phones (under 840 px); left rail button „Mehr“ from 840 px. Tapping the already-open tab returns to its first page (the list of entries).
- Help page: „Mehr“ → „Hilfe & Kontakt“ / "Help & contact" opens https://snacklist.app/support (German UI) or https://snacklist.app/en/support (English UI) in a new browser tab. The page „Hilfe und Kontakt“ gives the support email address support@snacklist.app and answers FAQs (since 5 Nov first the waitlist and beta questions: the email address, installing the beta on iPhone and on Android, a wrong sign-up email, a missing invite; then invite partner, join with a code, export data, delete account, Snacklist Lifetime (what happens to it when the last member leaves a household, and refunds through Apple or Google), usage data, Siri, Alexa, AI assistants, TestFlight/Google Play testing).
- Imprint: „Mehr“ → „Impressum“ (in the group below „Hilfe & Kontakt“) opens https://snacklist.app/impressum (DE) or https://snacklist.app/en/imprint (EN). Privacy policy: „Mehr“ → „Datenschutzerklärung“ opens https://snacklist.app/datenschutz (DE) or https://snacklist.app/en/privacy (EN). On the login screen the same two links sit under the form as „Impressum · Datenschutz“.
- Usage data: „Mehr“ → „Nutzungsdaten“ → switch „Nutzungsdaten und Fehlerberichte senden“.
- Terms: „Mehr“ → „Nutzungsbedingungen (EULA)“.
- Guides on snacklist.app (not linked from anywhere in the app; the site's nav links the index /de/anleitungen, /en/guides and the changelog, its footer also „Chronik“ / "History" (/history, /en/history, the release timeline), the help page links the Alexa and Claude guides and, while native Siri is held, the Siri Shortcut guide; the landing page links the Siri guide): German „Snacklist per Siri: Kurzbefehl einrichten“ at /de/anleitungen/siri-kurzbefehl, „Snacklist per Alexa: Skill einrichten“ at /de/anleitungen/alexa, „Snacklist mit Claude verbinden“ at /de/anleitungen/claude; English "Snacklist with Siri (German only for now)" at /en/guides/siri-shortcut (says Siri is German-only and points to the German guide), "Snacklist with Alexa: set up the skill" at /en/guides/alexa and "Connect Snacklist to Claude" at /en/guides/claude (both full English guides). The widget guides „Snacklist auf dem Home-Bildschirm: das Widget“ / "Snacklist on your Home Screen: the widget" (/de/anleitungen/widget, /en/guides/widget) are drafts: preview builds only, not in production (`site/content/guides/`).
- Deep links: /more, /more/access, /more/account, /more/invites, /more/lifetime, /more/settings, /more/settings/language, /more/usage-data, /more/household, /more/tips, and with `feedback-fb4` on /more/feedback and /more/feedback/<id> (without it they land on /more); /more/legal lands on /more, /more/join (More's join page until job 206) on /join.

## Driving it with Playwright

Preconditions:

- Seeded household „Familie Brandt“, signed in, consent declined, on the list (phone 390x844, or 1366x1024 for the wide layout).
- For the external pages stub the site so the test never hits the live site: `page.context().route('https://snacklist.app/**', r => r.fulfill({contentType:'text/html', body:'<title>stub</title>'}))`.
- More is a lazy list taller than the window: wheel to a row before clicking it (`wheelTo` in `e2e/tests/helpers.ts`: `page.mouse.wheel(0, 250)` over the list until the row is above the tab pill; `openMore` does it for you).

- **Open More.** Click the tab. `openTab(page, 'Mehr')` (`getByRole('tab', {name:'Mehr', exact:true})`, on phones and on the rail alike since Flutter 3.50). URL `/more`, heading „Mehr“.
- **Open an entry.** `openMore(page, 'Einstellungen')` (taps Mehr, makes sure the list is shown, clicks `getByRole('button', {name: /^Einstellungen( |$)/})`). Rows are buttons named by their label alone (job 85: no hints; „Einkauf starten“ carries its hint in the name, so match it with `/^Einkauf starten/`), so match exactly, e.g. `getByRole('button', {name: 'Konto', exact: true})`; `openMore` matches the label followed by a space or the end.
- **Help page.** `wheelTo(page, getByRole('button',{name:/^Hilfe & Kontakt/}))`, then `const popup = page.waitForEvent('popup'); await row.click()`. Observable: `(await popup).url()` equals `https://snacklist.app/support`; the app URL is unchanged. Spec: `e2e/tests/help.spec.ts` (also the English URL and 1366 px).
- **Nutzungsdaten.** `openMore(page, 'Nutzungsdaten')`. Observable: URL `/more/usage-data`, heading „Nutzungsdaten“, the switch `getByRole('switch',{name:/^Nutzungsdaten und Fehlerberichte senden/})` (e2e and verify-snacklist builds), no „Datenschutzerklärung“ button. „Zurück“ returns to `/more`.
- **Legal rows, imprint, privacy policy, terms.** On More, `wheelTo` the button `{name:'Impressum', exact:true}`; no heading sits above it (`getByRole('heading',{name:'Rechtliches', exact:true})` has count 0 since job 203). The popup pattern with `getByRole('button',{name:'Impressum', exact:true})`, `{name:'Datenschutzerklärung', exact:true}` and `{name:'Nutzungsbedingungen (EULA)', exact:true}` gives `https://snacklist.app/impressum`, `https://snacklist.app/datenschutz` and (Chromium on desktop, not iOS) `https://snacklist.app/support`; the app stays on `/more`. `page.goto('/more/legal')` ends on `/more`. Spec: `e2e/tests/shell-more.spec.ts` ("the Impressum is two taps from the list …"), `e2e/tests/legal.spec.ts` (login footer links).
- **Licenses.** On More click `getByRole('button',{name:'Lizenzen', exact:true})`. Observable: `page.locator('body').ariaSnapshot()` matches `/Snacklist[\s\S]*Flutter[\s\S]*bloc/`; „Zurück“ returns to More.
- **Version.** `page.getByText(/^Version \d+\.\d+\.\d+/)` visible at the end of the list.
- **Sign out.** Click `getByRole('button',{name:/^Abmelden/})`. Observable: `getByRole('textbox',{name:'E-Mail'})` visible, URL contains `/login`.
- **Wide layout.** `page.setViewportSize({width:1366,height:1024})`, click `getByRole('tab',{name:'Mehr',exact:true})`. Observable: the entries and `getByText('MCP-Server',{exact:true})` side by side; „Zurück“ buttons absent; clicking the button „Konto“ (exact) shows Konto alone (URL `/more/account`). At 820 px the tab pill returns.
- Specs to run: `scripts/verify.sh --only e2e -- tests/shell-more.spec.ts`, `tests/help.spec.ts`, `tests/legal.spec.ts`.

## Gotchas

- „Archivierte Haushalte“ shows only in builds with HOUSEHOLD_ARCHIVE (the e2e build has it; the verify-snacklist build and a normal user do not see it); archiving itself also needs the server's switch. „Hilfe & Kontakt“ is on for everyone now (the help page is published).
- The „Nutzungsdaten“ row and its page exist only when the build has an analytics key; without one More has no „Nutzungsdaten“ row. Production has one: the production web bundle carries a PostHog project key, and the store builds get it from the `release` environment secret (checked 2026-11-01). The e2e and verify-snacklist builds carry the stand-in key, so the switch shows there too.
- More is reachable only in a household (a user without one lands on the welcome screen), so „Leute einladen“ shows there whenever `list-declutter` is off.
- The Premium row has no hint any more (job 85): neither „Freigeschaltet“ nor „Siri und KI-Assistenten“.
- The household's name is a row of its own (job 169b), not a hint: job 85 dropped the hint under „Leute einladen“. On the seeded household the second row reads „Familie Brandt“ (driven 2026-11-14 on main 97b2907e, web, 390 px, Mia: Konto, Familie Brandt, Leute einladen, Zugänge, Einstellungen, Nutzungsdaten, Tipps, Feedback senden, Hilfe & Kontakt, Impressum, Datenschutzerklärung, Nutzungsbedingungen (EULA), Lizenzen, Abmelden; no „Rechtliches“ heading, no join row). The same order on main c2183ca6 (2026-11-16); with `list-declutter` and `trip-mode` on: Einkauf starten, Konto, Zugänge, Einstellungen, Nutzungsdaten, Tipps, Feedback senden, Hilfe & Kontakt, Impressum, Datenschutzerklärung, Nutzungsbedingungen (EULA), Lizenzen, Abmelden.
- The tabs are role `tab` on the phone's bar and on the rail alike (driven 2026-11-13 at 390 and 1366 px). Use `openTab`.
- Pages open by deep link: back goes to the More list, not out of the app.
- Opening snacklist.app pages stays external everywhere; never an in-app browser. Real site pages are not reachable offline; stub them.
- Long-press on the version line (touch only in practice) toggles „Interne Installation“ and shows „Testfehler senden“ and, while usage data is on, „Installations-ID kopieren: {id}“ / "Copy installation ID: {id}"; internal testers only, not for copy.
- Wide More page title: „Mehr“ heading; language page adds a back button next to its title.
- More has no section headings since job 203 (until then „Rechtliches“ / "Legal" stood above the legal rows). „Nutzungsdaten“ (the usage-data switch) and „Datenschutzerklärung“ (the policy) are different rows: the first is a setting, the second the legal text.
