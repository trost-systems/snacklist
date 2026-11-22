# Household add alert (flag `push-household-add`, off; job 377)

Under Mehr → Einstellungen, in phone builds with push, a section „Mitteilungen“ / "Notifications" has the switch „Wenn jemand etwas hinzufügt“ / "When someone adds something". On (it is off for everyone until they switch it), the user gets a push when another household member adds an item: „Lea hat Milch hinzugefügt“ / "Lea added Milk". Several adds within a few minutes come as one: „Lea hat 4 Einträge hinzugefügt“ / "Lea added 4 items". A tap opens that household's list. Not on the web (no web push). Needs the server switch `push_household_add`, which stays off until Legal's GO.

## Sub-features

- `ha-switch` the switch, off by default; turning it on asks the OS for notification permission, a refusal leaves it off with the note „Mitteilungen sind für Snacklist ausgeschaltet …“.
- `ha-self` nobody is pushed about their own adds, on any of their devices.
- `ha-batch` an add goes out 2 minutes after the last add of that person to that list, at the latest 5 minutes after the first; several become one count line.
- `ha-trip` no push for adds made while the adder shops: within 10 minutes of their own app tick (trip detection's "a trip may still be going on" rule; the running trip of trip mode is only on the device).
- `ha-tap` a tap opens the list (P0's deep link).

## Driving it

Not drivable in the web build (no FCM there). The decisions run in SQL: `supabase/tests/push_household_add.test.sql` (`supabase test db`), and the switch in `app/test/push/household_add_alert_test.dart`. The send path through pg_net to the `push` function is `public.push_add_flush()`; on the local stack it answers 503 `not_configured` without `PUSH_SEND_SECRET` (docs/PUSH.md, "Household add").
