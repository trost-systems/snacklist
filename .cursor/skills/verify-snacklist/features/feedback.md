# Feedback

Mehr → „Feedback senden“ opens a sheet for a free-text note to Peter. The user writes the note (up to 2000 characters), optionally picks a kind (Bug, Idee, Sonstiges) and may tick that Peter may contact them. The note is sent with app version, build, platform, OS/browser family, language and the screen the user came from, never list items. After sending, the sheet closes with the snackbar „Danke!“. If sending fails the note stays and the button becomes „Erneut senden“.

## Sub-features

- `fb-open` the sheet from More; heading „Feedback senden“, close button „Schließen“.
- `fb-message` multiline field „Deine Nachricht“ (hint „Was ist dir aufgefallen?“), required.
- `fb-kind` three optional chips: „Bug“, „Idee“, „Sonstiges“ under „Art (optional)“; tapping the chosen one again clears it.
- `fb-contact` checkbox „Peter darf mich dazu kontaktieren“, off by default.
- `fb-attached` fixed line „Wird mitgeschickt: App-Version, Gerät, Sprache und aktueller Bildschirm. Keine Listeneinträge.“
- `fb-limit` at 1800 characters a counter „{count} / 2000“ shows; above 2000 the field shows „Höchstens 2000 Zeichen“ and Send is disabled.
- `fb-send` „Senden“ (disabled while empty, too long or sending; spinner labelled „Wird gesendet …“), then sheet closes, snackbar „Danke!“.
- `fb-fail` „Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.“ with the note kept and „Erneut senden“; a retry of an unchanged note stores one row, an edited note counts as a new one (editing clears the error and the button reads „Senden“ again).
- `fb-draft` an unsent note survives closing the sheet; a sent note, or another account signing in, starts blank.

EN labels: "Send feedback", "Close", "Your message", "What did you notice?", "Type (optional)", "Bug", "Idea", "Other", "Peter may contact me about this", "Included: App version, device, language and current screen. No list items.", "{count} / 2000", "Up to {max} characters" ("Up to 2000 characters"), "Send", "Sending…", "Thanks!", "Not sent. Check your connection and try again.", "Retry".

## How to get to it (user POV)

- „Mehr“ / "More" → row „Feedback senden“ / "Send feedback" (second in the group, after „Tipps“ and before „Hilfe & Kontakt“ on the web; in the iPhone and Android apps „Snacklist bewerten“ sits between them; above the legal rows; no hint since job 85). It is the only entry point (no shake gesture, none from the list).
- Works from a phone and beside an open More page on wide screens; the note's "screen" is the page the user was on before More (e.g. the list), or the open More page on wide layouts.

## Driving it with Playwright

Preconditions:

- Seeded household, signed in, consent declined, on the list.
- To read the stored row: service-role client (`adminClient()` in `e2e/tests/helpers.ts`) on table `feedback`, filtered by the user's id.

- **Open.** `openMore(page, 'Feedback senden')` (it wheels the lazy list to the row; in a journey `openTab(page, L, 'tabMore')` plus `reveal`). Observable: `getByRole('group',{name:'Feedback senden', exact:true})` visible; `getByRole('button',{name:'Senden', exact:true})` disabled.
- **Write.** `typeInto(page.getByRole('textbox',{name:'Deine Nachricht'}), 'Beim Abhaken springt die Liste nach oben.')`. Use `typeInto` (umlauts). Send becomes enabled.
- **Kind.** `getByRole('checkbox',{name:'Idee', exact:true}).click()`; contact: `getByRole('checkbox',{name:'Peter darf mich dazu kontaktieren'})`.
- **Send.** `getByRole('button',{name:'Senden', exact:true}).click()`. Observable: sheet group gone; snackbar text „Danke!“ (find with `page.locator('[id^="flt-semantic-node-"]').getByText('Danke!',{exact:true}).first()`); one `feedback` row: message, category (`bug`/`idea`/`other`/null), contact_ok, platform `web`, locale `de`, screen `list`.
- **Limits.** Fill 2001 characters: `getByText('Höchstens 2000 Zeichen')`, `getByText('2001 / 2000')`, Send disabled; at 2000 `getByText('2000 / 2000')` and Send enabled.
- **Offline / retry.** `context.setOffline(true)`, Send: `getByText('Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.').first()` visible, textbox keeps its value, `getByRole('button',{name:'Erneut senden', exact:true})` enabled; `setOffline(false)`, click it: „Danke!“, exactly one row.
- **Double tap** on Send stores one row.
- Specs: `scripts/verify.sh --only e2e -- tests/feedback.spec.ts`.

## Gotchas

- Kind chips are checkboxes in the accessibility tree, not buttons or radios.
- The message is trimmed; length is counted in characters as trimmed, 1 to 2000.
- A feedback row is stored with or without analytics consent; the analytics event `feedback_submitted` (category bug/idea/other/none, entry_point settings, screen, contact_ok; no text) goes out only with consent. Accounts on test domains are marked internal (`.test`, `.invalid`, `.example`, `.localhost`, example.com/net/org), so the baseline's `fg-test.invalid` members store `is_internal: true` (driven 2026-11-04).
- The e2e build and this skill's build both point analytics at a fake collector (posthog.invalid); feedback itself goes to Supabase.
- Rows older than 12 months are deleted by the server (migration); that is not visible in the app.
- The sender cannot read notes back in the app, but Konto → „Meine Daten exportieren“ (EN "Export my data") includes their own notes (section `feedback` of the export).
- Whether Peter actually gets a notification of a new note is not in the app: unverified (outside app code).
