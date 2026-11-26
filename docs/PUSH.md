# Push notifications (job 376, foundation)

Server push through Firebase Cloud Messaging (FCM): Android directly, iOS
through APNs via FCM. No web push and no local notifications. This job
lands the plumbing only. No notification is sent in production until Ops
has created the Firebase project and its secrets ("Ops setup" below),
and until a feature that sends one (P1 job 377
`push-household-add`, P2 job 378 `push-shopping-day`) is rolled out behind
its flag after Legal's GO.

## Devices: `public.push_tokens`

One row per device token, owned by the signed-in user.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | primary key |
| `user_id` | `uuid` | `auth.users`, `on delete cascade` (account deletion removes the rows) |
| `token` | `text` | the FCM registration token, unique, 1 to 4096 characters |
| `platform` | `text` | `ios` or `android` |
| `created_at`, `updated_at` | `timestamptz` | `updated_at` moves on every registration |

RLS is on. A user can select their own rows (`user_id = auth.uid()`) and
nothing else. Writes go through two RPCs only:

- `register_push_token(p_token text, p_platform text)`: upserts the token
  for `auth.uid()`. A token another account registered on the same device
  moves to the caller. A user keeps at most 10 devices; registering an
  11th drops the one with the oldest `updated_at`.
- `unregister_push_token(p_token text)`: deletes the caller's row for that
  token. The app calls it before sign-out, while the session still exists.

A token is a device secret: whoever has it can move the device's row to
their own account, and FCM delivers to it. Never log it, show it in the
UI, put it in an answer or analytics, or send it anywhere but these two
RPCs and FCM.

Rows not registered again for 270 days (FCM drops such tokens) go in the
daily cleanup (pg_cron `purge-push-tokens`, `public.purge_push_tokens()`).
The app registers again on every start while push is on, which moves
`updated_at`.

Tokens are user-owned, not household-owned: the send function picks the
devices of a household's members at send time, so leaving a household
needs no cleanup. `export_my_data()` lists a user's devices (platform and
times, not the token).

## Sending: the `push` edge function

Internal only. P1 and P2 call it from the database (pg_net, like the
feedback digest) or from another function.

```
POST /functions/v1/push
x-push-secret: <PUSH_SEND_SECRET>
content-type: application/json

{
  "household_id": "<uuid>",
  "list_id": "<uuid>",
  "recipients": [
    { "user_id": "<uuid>", "title": "<1-100 chars>", "body": "<0-400 chars>" }
  ],
  "dry_run": false,
  "ttl_seconds": 86400
}
```

The caller writes the text per recipient, in that user's language.
`recipients` holds 1 to 50 users, each once. `dry_run` defaults to `false`.
`ttl_seconds` (optional, 60 to 86400, default 86400) is how long FCM, and
APNs on iOS, keep a notification for a device that is offline; after that it
is dropped instead of kept for FCM's default of 4 weeks. The function sends only to the devices
of recipients who are members of `household_id`, and only when `list_id`
is a list of that household.

| Answer | When |
| --- | --- |
| `200 {"status":"sent","devices":n,"sent":n,"failed":n,"removed":n}` | sent; `failed` counts every message FCM did not take, `removed` those of them whose token FCM called unregistered (404, or `UNREGISTERED`, or a 400 on `message.token`), which are deleted |
| `200 {"status":"dry_run","devices":n,"message":{...}}` | `dry_run: true`: nothing goes to FCM; `message` is the first FCM message with the token and the text replaced by `<token>`, `<title>` and `<body>`, `null` when no recipient has a device |
| `400 {"error":"invalid_request"}` | the body does not parse |
| `401 {"error":"unauthorized"}` | wrong or missing `x-push-secret` |
| `422 {"error":"unknown_list"}` | the list is not in the household |
| `503 {"error":"not_configured"}` | no `PUSH_SEND_SECRET` (every request), or no `FCM_SERVICE_ACCOUNT_JSON` (every request but a dry run) |
| `500 {"error":"failed"}` | the database failed; the log has its SQLSTATE |

Logs carry counts and fixed codes only: never a token, a user id or
notification text. A `dry_run: true` response also includes `household_id`,
`list_id`, and a `message` object whose token and text are replaced by
`<token>`, `<title>` and `<body>`.

### Secrets of the function

| Name | What |
| --- | --- |
| `PUSH_SEND_SECRET` | shared secret of the callers (pg_net or another function) |
| `FCM_SERVICE_ACCOUNT_JSON` | the Firebase service account key file's JSON (`project_id`, `client_email`, `private_key`, `token_uri`), role "Firebase Cloud Messaging API Admin" |
| `FCM_API_URL` | optional, tests only: replaces `https://fcm.googleapis.com` |

The function signs a JWT with the service account's key (RS256, scope
`https://www.googleapis.com/auth/firebase.messaging`), trades it at
`token_uri` for an access token, keeps that until a minute before it
expires, and posts each message to
`/v1/projects/<project_id>/messages:send`, at most 8 at a time.

The local stack serves the function with the secrets of
`supabase/functions/.env`; without `FCM_SERVICE_ACCOUNT_JSON` there only
dry runs answer. `scripts/smoke-remote.sh` checks a deployed `push` with a
made-up secret (503 before Ops sets `PUSH_SEND_SECRET`, 401 after).

## The message

```json
{
  "message": {
    "token": "<token>",
    "notification": { "title": "<title>", "body": "<body>" },
    "data": { "kind": "list", "v": "1", "household_id": "<uuid>", "list_id": "<uuid>" },
    "android": { "priority": "high", "ttl": "86400s" },
    "apns": {
      "headers": { "apns-expiration": "<unix seconds: now + ttl_seconds>" },
      "payload": { "aps": { "sound": "default" } }
    }
  }
}
```

`data` is the app's contract. `kind` names what a tap opens (`list` is
the only one); `v` is its version. An app ignores a `kind` it does not
know, and reads the ids of a newer `v` as long as they are there.

## The app

`app/lib/push/` (a core folder). Push exists on iOS and Android only, and
only in a build with the Firebase defines (`app/lib/core/environment.dart`):

| Define | What |
| --- | --- |
| `FIREBASE_PROJECT_ID` | the Firebase project id |
| `FIREBASE_MESSAGING_SENDER_ID` | its sender id (project number) |
| `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY` | the iOS app's id and API key |
| `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_API_KEY` | the Android app's |

Without them the build has no push: Firebase is never initialized, and
nothing asks for permission. Firebase is configured from these defines,
not from `google-services.json` or `GoogleService-Info.plist`. Release
builds get them from the `release` environment's variables (`vars.`, not
secrets: they are client config that ships in the app):
`.github/workflows/release.yml` hands the iOS pair and the shared two to
`fastlane ios beta`, the Android pair and the shared two to `fastlane
android build`, and the Fastfile's `PUSH_DEFINES` passes each one that is
set. Only `firebase_push.dart` imports Firebase (lint rule
`firebase-only-in-firebase-push`).

- **Opt-in.** The OS permission prompt appears only from
  `PushRegistration.optIn()`, which a settings toggle calls (P1 and P2 add
  theirs; the foundation has no caller yet, so no build asks). Never on
  first launch. A yes registers the token and remembers
  the opt-in on the device.
- **Start and sign-in.** With the opt-in remembered and permission still
  granted, the app registers the current token again (no prompt), and
  again on every token refresh.
- **Sign-out.** A user-initiated sign-out runs `PushRegistration.forget()`
  before the session ends: the app unregisters the token (2 s at most),
  deletes it at FCM (3 s at most) and forgets the opt-in, so the next
  account on the device starts without push. A remote sign-out or an OS
  revocation cannot use that in-session path; the next start, sign-in or
  opt-in retries any leftover FCM delete (`PushDevice.tokenLeft`). Account
  deletion removes the rows on the server (cascade) and the app forgets
  the same way. A delete FCM does not confirm (the phone is offline) is
  remembered on the device (`PushDevice.tokenLeft`) and tried again at
  the next start, sign-in, sign-out or opt-in, before anything else.
  Once FCM has deleted the token, the next send to it answers
  `UNREGISTERED` and the function deletes the old account's row.
- **Tap.** A tap on a notification, from a cold start or from the
  background, opens the named list (`app/lib/shell/push_taps.dart`): the
  app switches to the household if it is another of the user's, then
  shows the list (`ShowListLink`, taken by the list view once that
  household's list has loaded). For a household the user left, the app
  opens the List tab of the household it shows, with the list it shows
  unchanged; a list that is gone leaves the shown one too. Signed out,
  the tap opens sign-in and is dropped. A notification that
  arrives while the app is open is not shown (the foundation's default;
  a feature may change it).

## Shopping-day reminder (job 378, P2, flag `push-shopping-day`)

A person picks one or more weekdays; the evening before each at 19:00 in
their own time zone the push function sends „Morgen ist Einkaufstag“ /
"Shopping day tomorrow" to their devices. Server push, no local
notifications.

- **Off by default, per person.** No row in `public.shopping_day_reminders`
  means off. The row is the person's, not a household's: weekdays (ISO,
  1 Monday to 7 Sunday), the device's IANA time zone, the language (`de` or
  `en`) and `last_sent_on`. A user reads their own row; writes go through
  `set_shopping_day_reminder(p_weekdays, p_time_zone, p_locale)` only (no
  weekday deletes the row). The list and household it names are the
  person's default household and its default list (else its first list),
  read at send time.
- **Time zone and DST.** The app sends the device's IANA zone
  (`flutter_timezone`) with each save. One pg_cron job
  (`shopping-day-reminder`, every 10 minutes, UTC) calls
  `shopping_day_run`. A reminder is due when `now() at time zone <zone>`
  reads 19:00 to 19:29 on the day before a picked weekday and nothing was
  sent that local date. Postgres applies the zone's DST rules, so 19:00
  stays 19:00 local across a clock change (pgTAP covers Europe/Berlin
  around both changes and America/New_York). One frequent job beats a job
  per zone: it reads only the rows of people who opted in, and the
  30-minute window lets a late or failed run still send within the evening.
  A reminder is marked sent before it is posted, so it goes at most once an
  evening; a failed send is not retried. Saved at or after 19:00 local, the
  evening counts as sent, so turning it on late does not ping at once.
- **Open items.** The body names the number of open items of that list
  (`1 Artikel steht auf der Liste. Schau kurz rein.`, none: `Schau kurz auf
  die Liste.`). It is one indexed `count(*)` (`items_list_idx`) per due
  person, never item names. The texts are in `shopping_day_text`.
- **Tap.** The message is the foundation's: `data.kind = list` with the
  household and list id, so a tap opens the list (`push_taps.dart`). The
  ttl is 4 hours: a reminder that reaches an offline phone after bedtime is
  dropped.
- **Switch.** The job exists only while the server switch `push_shopping_day`
  is on: `select public.shopping_day_set(true, '<https URL of /functions/v1/push>')`
  needs the vault secret `push_send_secret` (the function's
  `PUSH_SEND_SECRET`: `select vault.create_secret('<secret>', 'push_send_secret')`);
  `shopping_day_set(false)` removes the job. Both are owner-only. Turn it on
  after Legal's GO and Ops' Firebase setup, together with the PostHog flag.
- **Zone refresh.** Opening Mitteilungen with days saved and push on here calls
  `refresh_shopping_day_reminder(zone, locale)`: zone and language only, never the days or
  `last_sent_on`, so it cannot cancel an evening's reminder. A device that reports a bare offset
  (`GMT+01:00`) sends the fixed zone `Etc/GMT-1` (`ianaZone`); an offset of no whole hour fails the save.
- **Per person, not per device.** The days are the person's. A device without push shows no days, but a
  pick there adds to the saved days (after the permission), so a second device never wipes them.
- **Off in the app (last type, Legal N-436, N-401).** Unpicking the last weekday, when the
  household-add alert is off too, runs `PushRegistration.forget()` first (the sign-out path with
  its offline catch-up) and then saves no weekday, so a clear that cannot reach the server still
  takes this device off push, as the alert's off does. The other type's state is read from the
  server (`HouseholdAddAlert.isOn`); unreadable counts as off, so a phone that cannot be asked
  is taken off push rather than left registered. The alert's off asks the other way
  (`ShoppingDayService.hasDays`, unreadable counts as none).
  A clear the server did not take is kept on the device with its account
  (`DeviceCache.pendingShoppingDayClear`) and sent again at the next start or
  sign-in of that account, or when Mitteilungen opens (N-439, as for the alert).
- **App.** More's Mitteilungen page (`/more/notifications`, job 463) shows the section with the flag on, on iOS and
  Android in a build with push. Picking the first weekday asks for the OS
  permission (`PushRegistration.optIn`). With push off on this device the chips show off
  even if the server has days (no push, no reminder). Refused: nothing is saved and a
  notice says why. `app/lib/settings/shopping_day.dart`.
- The hint says 19:00 is in the device's time zone (N-435).
- Data: the weekday choice, time zone and language in the export as
  `shopping_day_reminder` (next to `push_devices` and `push_preferences`:
  this migration sorts after the household-add one and carries its
  `export_my_data`, N-434); the account's deletion removes the row.

## Native

- iOS: `aps-environment` = `development` in `Runner.entitlements`, the
  value Xcode writes for the capability. Signing takes the value of the
  provisioning profile, so the App Store profile ships `production`. The
  App ID `com.snacklist.app` needs the Push Notifications capability and
  renewed App Store profiles before this lands, or the release run's
  `plan` stops with "Profile ... is INVALID" (`docs/RELEASE.md`,
  "Capabilities"; "Ops setup" below). The Home Screen widget gets no
  push.
- Android: `android.permission.POST_NOTIFICATIONS` (Android 13 and later
  ask at opt-in).
- `app/test/push/push_native_config_test.dart` pins both, and the six
  defines in the Fastfile and `release.yml`.

## Ops setup

What has to exist before push works in production (placeholders only;
nothing real goes in the repo):

1. A Firebase project for Snacklist with the FCM HTTP v1 API.
2. In it, an iOS app (`com.snacklist.app`) and an Android app
   (`com.snacklist.app`). Their client config goes into six variables of
   the GitHub `release` environment: the `FIREBASE_*` defines above.
3. An APNs auth key (.p8) with its Key ID and Team ID, uploaded in
   Firebase for the iOS app. The key stays in the ops secret store.
4. Push Notifications on the App ID `com.snacklist.app` and renewed App
   Store profiles, before the `aps-environment` entitlement reaches `main`.
5. A service account with the role "Firebase Cloud Messaging API Admin";
   its key JSON is the Supabase secret `FCM_SERVICE_ACCOUNT_JSON`.
6. A random `PUSH_SEND_SECRET` as a Supabase secret, and wherever the
   callers (P1, P2) need it.

## Household add (job 377, P1)

When another member adds an item, the members who switched the alert on get
a push (flag `push-household-add`, off until Legal's GO). The app side is
the switch on More's Mitteilungen page (job 463)
(`app/lib/push/household_add_settings.dart`); the decisions are in the
database (`supabase/migrations/20261122232004_push_household_add.sql`,
`supabase/tests/push_household_add.test.sql` and `..._privacy.test.sql`).

- **Opt-in, per person.** `public.push_preferences.household_add` defaults
  off (no row is off). The switch calls `set_push_household_add(on,
  language)`; turning it on first asks the OS for permission
  (`PushRegistration.optIn()`), and a refusal leaves it off. Turning it off
  runs `PushRegistration.forget()` (before the save, so an off that cannot
  reach the server still takes this device off push), the path of a sign-out
  (unregister, delete at FCM, offline catch-up; Legal N-401). `language` is
  the app's (`de` or `en`), because the server knows no locale. The settings
  read the choice each time they open (and write the language again when it
  changed); another account signing in on the device starts with none. The
  switch reads „on“ only while the server's row is on **and** this device is
  opted in: the row is the account's, so after a sign-out and in, or on a
  second phone, it reads off until that device's own yes.
- **Art. 21 (N-401).** `push_preferences.name_hidden`
  (`set_push_name_hidden`, the second switch): the member's name reads
  „Jemand“ / "Someone" in others' pushes, whether or not they switched the
  alert on.
- **Never my own adds, on any device.** Recipients are members of the
  household other than the adder; the push function picks tokens by recipient.
- **What counts as an add.** An insert of an active item, and an item put back
  from „Zuletzt verwendet“ (an update bought → active more than 10 minutes
  after the tick, the app's undo window). Not: an item that arrives ticked, an
  item re-inserted within 10 minutes of its deletion (the undo of a delete), a
  tick's undo within 10 minutes. Retried `put_item` calls insert once.
- **Only while someone wants it.** The items trigger queues an add
  (`push_add_queue`: household, list, item id, adder, time) only when the
  server switch `app_switches.push_household_add` is on and at least one other
  member switched the alert on. The item name is not stored: it is read from the
  item when the group is sent, so an item deleted, ticked or edited meanwhile
  drops out or is sent as it is then, and a group with nothing left sends
  nothing.
- **Not while the adder shops (d).** No row when the adder has an app tick
  (`bought` or `restored`, `item_events.source = 'app'`) in the household
  within the last 10 minutes (`recent_app_tick`, the one function trip
  detection's `detect_due_households` uses for „a trip may still be going on“,
  T1a). Trip mode's running trip lives on the device only, so this is the
  server's only trip signal. It reads the ticks of people whose trip
  detection is off too; its only effect is a push left out. It is checked again
  when the group is sent, so an adder who started ticking after the add is not
  announced either.
- **Pharmacy and drugstore (Legal N-401, rule N-423, permanent).** An item is
  never named when any of these holds (`push_item_sensitive`, read from the
  live item when the group is sent, so a move to a pharmacy meanwhile counts):
  (1) its category's `seed_key`, or one it absorbed, is `drugstore`; (2) its
  store's name or `seed_key` holds `apotheke`, `pharmacy`, `pharmacie`,
  `farmacia`, `apteka`, `eczane` or `docmorris` (`Store.pharmacyWords`,
  pinned to the SQL list through `supabase/tests/pharmacy_words.json`); (3) its store's
  `retailer_chain` or `seed_key` is dm, rossmann or kruidvat (add a chain id
  here when the registry gains a drugstore chain), or its name says Müller,
  Budni or Drogerie; (4) its category or store name says Drogerie or Drugstore, or its category name a pharmacy word;
  (5) its name says a medicine or contraception (Insulin, Pille, Ovulationstest,
  Schwangerschaftstest, Kondom, …) although the classifier files some of them
  under „Sonstiges“: a stopgap name list in the same function until the
  dictionary lists them as Drogerie. The pharmacy words of (2) are pinned to
  `supabase/tests/pharmacy_words.json` by an app test and a server test.
  The name stopgap list (medicine and contraception words in the item's own name, whole words so a cooking recipe or a dishwasher tablet is not caught) is an extra beyond N-423. Legal's next rule replaces the body of that one function. Queue hygiene
  (N-428): every minute flush deletes rows older than an hour, also while the
  alert is off; the ops switch off empties the queue; a group whose adder left
  the household is dropped unsent. Last alert off (N-427): the switch's off
  forgets the device unless `otherAlertsOn` says another alert needs it: the
  shopping-day reminder has a weekday picked (`ShoppingDayService.hasDays`,
  read from the server; unreadable counts as none, the device is forgotten).
- **Batching (b).** A group (household, list, adder; adds to two lists within the
  window are two pushes) goes out when its newest
  add is 2 minutes old, or its oldest 5 minutes (`push_add_take`). Title
  `Snacklist`; the body lines, which Legal reviews here with the ARB strings:

  | Case | DE | EN |
  | --- | --- | --- |
  | one item | „Lea hat Milch hinzugefügt“ | "Lea added Milk" |
  | one drugstore or pharmacy item | „Lea hat etwas zur Liste hinzugefügt“ | "Lea added something to the list" |
  | several, none drugstore or pharmacy | „Lea hat 4 Einträge hinzugefügt“ | "Lea added 4 items" |
  | several, any drugstore or pharmacy (N-440) | „Lea hat etwas zur Liste hinzugefügt“ | "Lea added something to the list" |
  | no name, or hidden | „Jemand hat …“ | "Someone added …" |

  ARB: `settingsPush`, `pushHouseholdAdd`, `pushHouseholdAddHint`,
  `pushBlocked`, `pushNameHidden`, `pushNameHiddenHint`.
- **Sending.** `push_add_flush()` runs every minute (pg_cron job
  `push-household-add`) and posts what `push_add_take()` returns to the
  `push` function with `pg_net`, using the vault secrets `push_send_secret`
  and `push_url`. The post is fire and forget: a failure drops that push (a
  notification this late is not worth a retry); queue rows older than an hour
  are deleted unsent. TTL 1 hour.
- **Tap (e).** The data of the message is P0's: it opens that household's
  list (`push_taps.dart`).
- **Switching on (Ops, after Legal's GO).** In the vault: `select
  vault.create_secret('<PUSH_SEND_SECRET>', 'push_send_secret');`, then as
  the service role `select public.push_household_add_set(true, '<push function
  URL>');`; `push_household_add_set(false)` switches it off and stops the cron
  job. Then the PostHog flag `push-household-add` for the app's switch.
