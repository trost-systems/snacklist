# Shopping-day reminder (flag `push-shopping-day`, off; job 378)

Under Mehr → Mitteilungen (job 463; it was in Einstellungen before), in iPhone and Android builds with push, a section „Einkaufstag-Erinnerung“ / "Shopping-day reminder" shows one chip per weekday. The evening before each picked day, at 19:00 in the phone's time zone, the user gets the push „Morgen ist Einkaufstag“ / "Shopping day tomorrow" with „5 Artikel stehen auf der Liste. Schau kurz rein.“ / "5 items on the list. Have a quick look." (the open items of their default household's default list, never their names). The days belong to the person, not the household. No day picked means off, which is everyone's start. Today nobody sees it: the flag is off for everyone, and the server switch `push_shopping_day` is off too. Not on the web (no web push).

## Sub-features

- `sd-chips` seven chips under the hint „Wähle deine Einkaufstage. Am Abend davor um 19 Uhr in der Zeitzone deines Geräts schickt Snacklist dir einen Hinweis aufs Handy.“; each chip shows the short day name („Mo“, "Mon") and is read out as the full name („Montag“, "Monday"). A tap picks or unpicks a day and saves at once.
- `sd-permission` the first pick asks the phone for notification permission; a refusal leaves the day unpicked with the snackbar „Mitteilungen sind für Snacklist ausgeschaltet. Schalte sie in den Einstellungen deines Handys ein.“; a failed save puts the chips back and shows „Die Änderung konnte nicht gespeichert werden.“ / "The change could not be saved."
- `sd-push-off` with push off on this phone since (signed out and in, permission withdrawn), the chips show no day picked, though the saved days stay for the next pick.
- `sd-when` the push comes between 19:00 and 19:29 local on the day before a picked weekday, at most once that evening; a day picked after 19:00 does not ping the same evening. The clock follows the phone's time zone over daylight saving; the app saves the zone and the app language again when Mitteilungen opens.
- `sd-text` the text in the person's app language (German, else English); with no open item: „Schau kurz auf die Liste.“ / "Have a quick look at the list."
- `sd-last-type` unpicking the last day while the household add alert ([household-add-alert](./household-add-alert.md)) is off takes this phone off push, as signing out does; while that alert is on the phone stays registered.
- `sd-export` the reminder (days, zone, language, last sent) is in Mehr → Konto → „Meine Daten exportieren“ as `shopping_day_reminder` ([account-deletion](./account-deletion.md)).

## How to get to it (user POV)

- Mehr → „Mitteilungen“ / "Notifications" (`/more/notifications`, the row below Einstellungen) → „Einkaufstag-Erinnerung“ / "Shopping-day reminder", below the household-add switches when those show. Phone apps only, and only with the flag on. A tap moves a chip at once; a save the server refuses puts it back with „Die Änderung konnte nicht gespeichert werden.“, refused notifications with the blocked notice. A second tap while the first saves is kept and saved after it.

## Driving it with Playwright

Preconditions: none on the web. The web build has no push service, so the section never shows there, even with `VH_DEFINES="FLAGS_ON=push-shopping-day"`.

- Web control: on a plain launch, More has no „Mitteilungen“ row and Mehr → Einstellungen has no „Einkaufstag-Erinnerung“ (`getByText('Einkaufstag-Erinnerung')` count 0). Driven 2026-11-23 on d023441d, also with `FLAGS_ON=push-household-add,push-shopping-day`: Einstellungen showed Darstellung, Sprache and „Mitteilungen“ with only the name switch.
- The rules run in SQL: `supabase/tests/shopping_day_reminder.test.sql` (`supabase test db`: due window, DST, once per evening, the text). The section's widget: `app/test/settings/shopping_day_test.dart`.
- The send path is `public.shopping_day_run` through pg_net to the `push` function, every 10 minutes by pg_cron once the switch is on (docs/PUSH.md, "Shopping-day reminder").

## Gotchas

- Needs both the PostHog flag and the server switch `push_shopping_day`; a build with only the flag shows the chips but no push is sent.
- The push needs Firebase in the build (`docs/PUSH.md`); nothing here is drivable without a phone. The push itself is unverified on a device.
- The days are per person, so a second device of the same person shows the same days, but only devices with push on get the reminder.
