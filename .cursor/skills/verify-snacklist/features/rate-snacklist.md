# Rate Snacklist

In the iPhone and Android apps, More has a row „Snacklist bewerten“ / "Rate Snacklist" between „Feedback senden“ and „Hilfe & Kontakt“. It opens Snacklist's page in the App Store or on Google Play, where the user can write a rating. Separately, a public store build may ask for a rating with the system's own rating dialog, at most a few times a year. It asks only after a shopping trip is done (a list of at least three items ticked off completely), once the user has been idle for 3 seconds, and only when the user has used the app for a while without trouble. Snacklist shows no question of its own before it, no text and no snackbar. Whether the system then shows its dialog is up to Apple or Google. Debug builds, Play internal testing and the web app never ask; an iPhone TestFlight build may ask, but Apple never shows the dialog there.

## Sub-features

- `rate-row` „Snacklist bewerten“ / "Rate Snacklist" (row key `more-rate`, external-link icon) on More in the iPhone and Android apps opens the store page; if it cannot open (no store app, no connection) a snackbar says „Der Store ist gerade nicht erreichbar. Prüfe die Verbindung.“ / "The store can't be reached right now. Check your connection." The web app and desktop builds have no such row.
- `rate-prompt` the system rating dialog after a completed trip, in public store builds only, behind every rule below.
- `rate-prompt-rules` it asks only when all hold: a public store build; first start at least 7 days ago; the app opened on at least 3 different days; at least 2 trips completed (a trip counts each item once; emptying the list again within 10 minutes, by putting an item back from „Zuletzt verwendet“ and ticking it, is the same trip); at least 25 items added on this device; no change the server refused (a taken name or a change refused offline up front does not count), no app error, or 60 seconds offline or with sync failing (the server in trouble) with changes waiting while the app is open (a shorter spell, offline in the background or offline with nothing to send does not count) in this or the previous session (a session starts at launch and whenever the app comes back from the background; pulling down Control Center or a Face ID prompt does not start one) or the last 24 hours; the store says it can ask; at least 120 days since the last ask; at most 2 asks per app version and 3 per 365 days.
- `rate-prompt-idle` it waits 3 seconds after the last tick. A tap anywhere in the app (the tab bar included) or a key press in that time, an open keyboard, an open dialog or sheet, the microphone listening, the List tab no longer showing or a page opened over the list cancels the ask until the next completed trip.
- `rate-prompt-force` QA override `--dart-define=REVIEW_PROMPT_FORCE=true` (ignored by public store builds): every rule but "the store says it can ask" is skipped, and any completed trip asks after the 3 seconds.

## How to get to it (user POV)

- Rate row: „Mehr“ / "More" → „Snacklist bewerten“ / "Rate Snacklist" (iPhone and Android apps).
- Prompt: tick off every item of a list with at least three items, then leave the phone alone for 3 seconds. Only in a public store build that passes every rule.

## Driving it with Playwright

Preconditions:

- Baseline household „Familie Brandt“ on the web build (verify-snacklist `launch.sh`), signed in.

- **Journey.** `helpers/drive.sh rate-snacklist` (fresh baseline, German) runs the web bullets below and logs the device counters.
- **A return from the background starts a session, on the web.** Right after sign-in, set `document.visibilityState` to `hidden` and dispatch `visibilitychange`, then `visible` again. Observable: `session_start` moves to now and `previous_session_start` is the launch's.
- **Same trip after an undo, on the web.** After the whole list is ticked, open „Zuletzt verwendet“, tap a row's put-back button (name ends in „{readd}“), tick the item again. Observable: `completed_trips` stays the same.
- **Offline grace, on the web.** `page.context().setOffline(true)`, tick one row, see the sync indicator (with the add sheet closed: it hides with the top bar while the sheet is open) (a button named „Offline: …“), back online after 10 s. Observable: no `last_error_at`. Then offline again, add „Kaffee“ (the add sheet stays open: Escape before reading the ARIA tree), wait 70 s. Observable: `last_error_at` set about 60 s after the list went offline. Playwright's offline mode keeps the open realtime socket, so the list notices only when an op fails: always make a change while offline.
- **Rate row absent on the web.** `openTab(page, 'Mehr')`, wheel to the end of More. Observable: `getByRole('button', {name: /^Snacklist bewerten/})` has count 0, „Feedback senden“ is followed by „Hilfe & Kontakt“.
- **A trip is counted, nothing asked, on the web.** Tick every open row (`getByRole('checkbox', {checked: false})`, until none is left: rows build lazily). Observable: localStorage `…review.state` goes from `"completed_trips":0` to `1`, holds counts and dates only (no item names, no ids), `"requests":[]`, and no page error.
- **Rate row on iPhone and Android.** The web build cannot show it. Proof is the widget test `app/test/more/more_screen_test.dart` (group "Snacklist bewerten (job 155)": DE and EN label, tap opens the store listing, never the rating dialog) and the More goldens (`app/test/design/goldens/more-*.png`, drawn as Android).
- **Prompt rules and idle wait.** Native dialog, no web or Linux equivalent. Proof is `app/test/review/` (each rule passing and failing, cooldown, caps, beta builds, errors, the idle cancel, keyboard, dialog and microphone). On a phone with a debug build: `flutter run --dart-define=REVIEW_PROMPT_FORCE=true`, add three items, tick all three, wait 3 seconds. Observable: the system rating dialog (iOS shows it in debug builds; Android shows it only for an app installed from Play, internal app sharing or an internal track, so on a sideloaded build nothing appears).

## Gotchas

- With `feedback-fb4` on, the row before it is „Feedback & Ideen“, and `journeys/rate-snacklist.mjs` (which looks for „Feedback senden“ to check the order) fails: drive it on a build without that flag.
- `unverified` on a device: no iPhone or Android device on the runner. The dialog itself is the store's; Apple shows it at most 3 times a year per app and never in TestFlight; Google shows it under its own quota. Snacklist logs "asked", never "shown".
- Who can be asked today: nobody. iPhone release builds may ask, but every one is in TestFlight, where Apple never shows the dialog; Android asks only in a build with `--dart-define=STORE_RELEASE=true`, which only the future Play production build gets (docs/RELEASE.md, "Public releases").
- The counters live on the device (no ids, no item names). Reinstalling starts them over.
- With usage data on, an ask sends the event `review_prompt_requested`; without, nothing is sent.
- Do not write copy that promises a rating dialog, or that Snacklist asks "Do you like Snacklist?". It never asks that.
