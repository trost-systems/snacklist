# Household add alert (flag `push-household-add`, off; job 377)

Under Mehr → „Mitteilungen“ / "Notifications" (its own More page since job 463, `/more/notifications`; a section of Einstellungen before), in phone builds with push, the switch „Wenn jemand etwas hinzufügt“ / "When someone adds something". On (it is off for everyone until they switch it), the user gets a push when another household member adds an item: „Lea hat Milch hinzugefügt“ / "Lea added milk" (the item name as entered). Several adds within a few minutes come as one: „Lea hat 4 Einträge hinzugefügt“ / "Lea added 4 items". A tap opens that household's list. Not on the web (no web push). Needs the server switch `push_household_add`, which stays off until Legal's GO. The privacy policy's push section is live since 26 November 2026 (snacklist.app/datenschutz#mitteilungen; hold `push-notifications` released).

## Sub-features

- `ha-switch` the switch, off by default; turning it on asks the OS for notification permission, a refusal leaves it off with the snackbar „Mitteilungen sind für Snacklist ausgeschaltet. Erlaube sie in den Einstellungen deines Geräts.“ / "Notifications are turned off for Snacklist. Allow them in your device's settings."; a save that does not reach the server leaves the switch as it was with „Die Änderung konnte nicht gespeichert werden.“
- `ha-self` nobody is pushed about their own adds, on any of their devices.
- `ha-batch` an add goes out 2 minutes after the last add of that person to that list, at the latest 5 minutes after the first; several become one count line, unless one of them is a pharmacy or drugstore item (`ha-private`).
- `ha-trip` no push for adds made while the adder shops: within 10 minutes of their own app tick (trip detection's "a trip may still be going on" rule; the running trip of trip mode is only on the device).
- `ha-private` items of the Drogerie category or from a pharmacy or drugstore (dm, Rossmann, Kruidvat, Müller, Budni, pharmacy words) are never named: „Lea hat etwas zur Liste hinzugefügt“ (EN "Lea added something to the list"); a batch holding any such item reads the same, with no count; only a batch of ordinary items is a count.
- `ha-name` (on every platform, the web included) the second switch „Meinen Namen in Mitteilungen weglassen“ / "Leave my name out of notifications": others then read „Jemand hat …“ / "Someone added …".
- `ha-off` turning the switch off also removes this phone from push, as signing out does, unless another push type is still on for the person: while a weekday of the [shopping-day reminder](./shopping-day-reminder.md) is picked, the phone stays registered.
- `ha-readd` an item put back from „Zuletzt verwendet“ later than 10 minutes after its tick counts as an add; an item that arrives ticked, a delete's undo and a tick's undo do not.
- `ha-tap` a tap opens the list (P0's deep link).

## How to get to it (user POV)

- Mehr → „Mitteilungen“ / "Notifications", the row after „Einstellungen“; on the page the first group, with no label of its own (the page title says it), before „Einkaufstag-Erinnerung“. No user sees it (flag off; PostHog shows it to internal installs only, `releases/flags.json`). With the flag, the web lists the row and its page shows only „Meinen Namen in Mitteilungen weglassen“; the add switch needs a phone with push. A tap moves either switch at once; a save the server refuses, or notifications refused by the OS, puts it back with a notice („Die Änderung konnte nicht gespeichert werden.“ or „Mitteilungen sind für Snacklist ausgeschaltet. …“). Quick taps are saved in their order.

## Driving it with Playwright

Preconditions: `VH_DEFINES="FLAGS_ON=push-household-add" helpers/launch.sh` for the name switch; a plain launch for the control (no „Mitteilungen“ row in More, and none in Einstellungen).

- Name switch: `openMore(page, 'Mitteilungen')` → switch `/^Meinen Namen in Mitteilungen weglassen/`, toggle it, read `push_preferences.name_hidden` through `apiAs` (own row only). No „Wenn jemand etwas hinzufügt“ on the web. Driven 2026-11-23 on d023441d with `VH_DEFINES="FLAGS_ON=push-household-add,push-shopping-day"`, before #726, in the old layout (a „Mitteilungen“ section of Einstellungen): the one switch under „Mitteilungen“, `name_hidden` true after the tap. Driven 2026-11-27 on 72516831 with `VH_DEFINES="FLAGS_ON=push-household-add"` on the own More page: „Mitteilungen“ right after „Einstellungen“, `/more/notifications` with the name switch only, which moved at once and saved `name_hidden`; Einstellungen without it. On a plain launch: no row, and `/more/notifications` opens Mehr.
- The add push itself is not drivable in the web build (no FCM there). The decisions run in SQL: `supabase/tests/push_household_add.test.sql` (`supabase test db`), and the switch in `app/test/push/household_add_alert_test.dart`. The send path through pg_net to the `push` function is `public.push_add_flush()`; on the local stack it answers 503 `not_configured` without `PUSH_SEND_SECRET` (docs/PUSH.md, "Household add").

## Gotchas

- Needs both the PostHog flag and the server switch `push_household_add`; with only the flag the switches save but nothing is sent.
- The push and the tap are unverified on a device.
