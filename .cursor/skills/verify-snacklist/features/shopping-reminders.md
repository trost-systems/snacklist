# Shopping reminders SR1 (flag `push-shopping-reminders`, off; job 472)

Under Mehr → „Benachrichtigungen & Erinnerungen“ / "Notifications & Reminders", in iPhone and Android builds with push, the section „Einkaufserinnerungen“ / "Shopping reminders" lists the person's reminders. Each is a shopping day, „Am Tag davor“ / "The day before" or „Am Einkaufstag“ / "On the day", and a time; at that local time the push „Morgen ist Einkaufstag“ / "Shopping day tomorrow" (the day before) or „Heute ist Einkaufstag“ / "Shopping day today" (on the day) comes with the count of open items. Reminders are per person; other household members never see them. No reminder means off, everyone's start. Today nobody sees it: the flag is off for everyone, its privacy text waits behind the hold `shopping-reminders`, and sending needs the server switch `push_shopping_day` (off). With the flag on it replaces the [weekday chips](./shopping-day-reminder.md).

## Sub-features

- `sr-empty` with none: the hint „Lege Erinnerungen für deine Einkaufstage an. …“ (Legal M4), „Noch keine Erinnerung.“ and „Erinnerung hinzufügen“. Opening the page asks nothing and saves nothing.
- `sr-sheet` „Erinnerung hinzufügen“ opens „Neue Erinnerung“: weekday chips (one day, none picked), „Wann“ with „Am Tag davor“ (picked) / „Am Einkaufstag“, „Uhrzeit“ 19:00 with hour chips and five-minute chips (24 hours in German, the phone's setting in English). Save is off until a day is picked; „Abbrechen“ stores nothing.
- `sr-save` Save shows the row at once (shopping day, „Am Tag davor, 19:00“, „Nächste: Fr., 27. Nov., 19:00“); the first Save asks for notification permission, a refusal takes the row back with „Mitteilungen sind für Snacklist ausgeschaltet. …“ and saves nothing.
- `sr-passed` saved at or after today's time: today is skipped and the snackbar says „Gespeichert. Heute ist 19:00 schon vorbei, die erste Erinnerung kommt am …“.
- `sr-duplicate` the same day, offset and time again: „Diese Erinnerung hast du schon.“ in the sheet; two different times on one shopping day are fine and both fire.
- `sr-cap` at 14 the add button is off and „Das sind 14 Erinnerungen, mehr geht nicht. …“ shows.
- `sr-edit` a row opens „Erinnerung bearbeiten“ with its values; Save changes it, „Löschen“ deletes it. A save or delete the server refuses goes back with „Die Änderung konnte nicht gespeichert werden.“
- `sr-last` deleting the last reminder turns reminders off; with the household-add alert off too the phone leaves push, as on sign-out.
- `sr-export` every reminder with all its fields is in „Meine Daten exportieren“ under `shopping_reminders`.

## How to get to it (user POV)

- Mehr → „Benachrichtigungen & Erinnerungen“ (`/more/notifications`, below Einstellungen) → „Einkaufserinnerungen“, below the household-add switches and the name switch. Phone apps only, only with the flag on.

## Driving it

- Not on the web: the web build has no push service, so the section never shows, even with `FLAGS_ON=push-shopping-reminders`.
- Widget tests: `app/test/settings/shopping_reminders_test.dart` (every case above) and `app/test/more/notifications_page_test.dart` (flag switching, the name switch on the same page, the alert switch alone creates no reminder). Goldens: `app/test/design/notifications_label_golden_test.dart`.
- SQL: `supabase/tests/shopping_reminders.test.sql` (one store, isolation, cap, duplicates, due times, DST, saved late, the 12 texts, export).

## Gotchas

- Saving the old weekday chips (flag off, or an old build) replaces every reminder of the person with day-before 19:00 ones.
- The cron runs every 10 minutes: a reminder at 19:05 arrives with the 19:10 run.
- The push itself is unverified on a device (needs Firebase in the build, docs/PUSH.md).
