# Feedback

Mehr → „Feedback senden“ opens a sheet for a free-text note to Snacklist Support. The user writes the note (up to 2000 characters), optionally picks a kind (Bug, Idee, Sonstiges) and may tick that Snacklist Support may contact them. The note is sent with app version, build, platform, OS/browser family, and language, never list items or a screen name. After sending, the sheet closes with the snackbar „Danke!“. If sending fails the note stays and the button becomes „Erneut senden“.

## Sub-features

- `fb-open` the sheet from More; heading „Feedback senden“, close button „Schließen“.
- `fb-message` multiline field „Deine Nachricht“ (hint „Was ist dir aufgefallen?“), required.
- `fb-kind` three optional chips: „Bug“, „Idee“, „Sonstiges“ under „Art (optional)“; tapping the chosen one again clears it.
- `fb-contact` checkbox „Snacklist Support darf mich dazu kontaktieren“, off by default (job 267: no „Peter“ in the app's feedback strings).
- `fb-attached` fixed line „Wird mitgeschickt: App-Version, Gerät und Sprache. Keine Listeneinträge.“
- `fb-limit` at 1800 characters a counter „{count} / 2000“ shows; above 2000 the field shows „Höchstens 2000 Zeichen“ and Send is disabled.
- `fb-send` „Senden“ (disabled while empty, too long or sending; spinner labelled „Wird gesendet …“), then sheet closes, snackbar „Danke!“.
- `fb-fail` „Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.“ with the note kept and „Erneut senden“; a retry of an unchanged note stores one row, an edited note counts as a new one (editing clears the error and the button reads „Senden“ again).
- `fb-draft` an unsent note survives closing the sheet; a sent note, or another account signing in, starts blank.

EN labels: "Send feedback", "Close", "Your message", "What did you notice?", "Type (optional)", "Bug", "Idea", "Other", "Snacklist Support may contact me about this", "Included: App version, device and language. No list items.", "{count} / 2000", "Up to {max} characters" ("Up to 2000 characters"), "Send", "Sending…", "Thanks!", "Not sent. Check your connection and try again.", "Retry".

## How to get to it (user POV)

- „Mehr“ / "More" → row „Feedback senden“ / "Send feedback" (second in the group, after „Tipps“ and before „Hilfe & Kontakt“ on the web; in the iPhone and Android apps „Snacklist bewerten“ sits between them; above the legal rows; no hint since job 85). It is the only entry point with the flag `feedback-fb2` off (no shake gesture, none from the list).
- Works from a phone and beside an open More page on wide screens; the note's "screen" is null (since job 259 More's row sends none; the shake entry of job 138, if it ships, sends the live screen).

## With the flag `feedback-fb2` (job 267)

- `fb-shot-menu` with the flag on, switching to the More tab pictures the screen being left; the form then offers „Bildschirmfoto hinzufügen“ / "Add screenshot". It opens the annotator: the frozen screen, centred, and below it one set of tools: ✕ („Schließen“ / "Close", ends it without a picture), „Markiere, was nicht stimmt. Übermale, was niemand sehen soll.“, „Fertig“ / "Done", the segmented „Stift“ / „Rechteck“ / „Text“ ("Pen" / "Rectangle" / "Text", all in tomato) and one undo („Rückgängig“ / "Undo") that takes back the last mark of any tool. „Fertig“ attaches the PNG, which holds every mark shown; the form shows switch „Bildschirmfoto“ / "Screenshot" with „Zeigt alles, was auf dem Bildschirm war, auch Listeneinträge, die du nicht übermalt hast.“ and a preview (role img „Vorschau des Bildschirmfotos“ / "Screenshot preview"). While the switch is on, `fb-attached` reads „Wird mitgeschickt: App-Version, Gerät und Sprache.“ (no „Keine Listeneinträge.“); switched off, the full line returns. Sent with the switch on, the PNG goes to the private bucket `feedback-screenshots` as `<user id>/<note id>.png` before the row, whose `screenshot` names it; switched off, nothing is uploaded. More never sends a screen name.
- `fb-shake` (iOS and Android only, so not drivable here; widget tests `app/test/feedback/fb2_test.dart`): a shake asks in a bottom sheet „Problem mit diesem Bildschirm melden?“ with „Mit Bildschirmfoto“ / „Ohne Bildschirmfoto“, ✕ or a tap beside to dismiss, and „Schütteln ausschalten: Mehr › Einstellungen“. The form after it has switch „Bildschirmname“ / "Screen name" with the live screen's name; with no screenshot the included line keeps „Keine Listeneinträge.“ Einstellungen has „Schütteln für Feedback“ (on by default, phones only).
- Flag on in Playwright: `fakeCollector(context, { flags: { 'feedback-fb2': true } })` and sign up with `consent: 'accept'` (flags arrive only after the analytics yes). Spec: "flag on: a screenshot from More is marked up, uploaded and named by the row" in `e2e/tests/feedback.spec.ts`; read the object with `adminClient().storage.from('feedback-screenshots').download(name)`.
- With the flag off everything above is absent and the form reads as before.

## Driving it with Playwright

Preconditions:

- Seeded household, signed in, consent declined, on the list.
- To read the stored row: service-role client (`adminClient()` in `e2e/tests/helpers.ts`) on table `feedback`, filtered by the user's id.

- **Open.** `openMore(page, 'Feedback senden')` (it wheels the lazy list to the row; in a journey `openTab(page, L, 'tabMore')` plus `reveal`). Observable: `getByRole('group',{name:'Feedback senden', exact:true})` visible; `getByRole('button',{name:'Senden', exact:true})` disabled.
- **Write.** `typeInto(page.getByRole('textbox',{name:'Deine Nachricht'}), 'Beim Abhaken springt die Liste nach oben.')`. Use `typeInto` (umlauts). Send becomes enabled.
- **Kind.** `getByRole('checkbox',{name:'Idee', exact:true}).click()`; contact: `getByRole('checkbox',{name:'Snacklist Support darf mich dazu kontaktieren'})`.
- **Send.** `getByRole('button',{name:'Senden', exact:true}).click()`. Observable: sheet group gone; snackbar text „Danke!“ (find with `page.locator('[id^="flt-semantic-node-"]').getByText('Danke!',{exact:true}).first()`); one `feedback` row: message, category (`bug`/`idea`/`other`/null), contact_ok, platform `web`, locale `de`, screen null.
- **Limits.** Fill 2001 characters: `getByText('Höchstens 2000 Zeichen')`, `getByText('2001 / 2000')`, Send disabled; at 2000 `getByText('2000 / 2000')` and Send enabled.
- **Offline / retry.** `context.setOffline(true)`, Send: `getByText('Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.').first()` visible, textbox keeps its value, `getByRole('button',{name:'Erneut senden', exact:true})` enabled; `setOffline(false)`, click it: „Danke!“, exactly one row.
- **Double tap** on Send stores one row.
- Specs: `scripts/verify.sh --only e2e -- tests/feedback.spec.ts`.

## Gotchas

- Kind chips are checkboxes in the accessibility tree, not buttons or radios.
- The message is trimmed; length is counted in characters as trimmed, 1 to 2000.
- A feedback row is stored with or without analytics consent; the analytics event `feedback_submitted` (category bug/idea/other/none, entry_point settings, no screen, contact_ok; no text) goes out only with consent. Accounts on test domains are marked internal (`.test`, `.invalid`, `.example`, `.localhost`, example.com/net/org), so the baseline's `fg-test.invalid` members store `is_internal: true` (driven 2026-11-04).
- The e2e build and this skill's build both point analytics at a fake collector (posthog.invalid); feedback itself goes to Supabase.
- Rows older than 12 months are deleted by the server (migration); that is not visible in the app.
- The sender cannot read notes back in the app, but Konto → „Meine Daten exportieren“ (EN "Export my data") includes their own notes (section `feedback` of the export).
- Peter reads the notes himself (`docs/FEEDBACK.md`). A daily mail digest of new notes to him is built (job 225) but ships off (`app_switches.feedback_digest`) until Legal's GO; nothing about it shows in the app.
