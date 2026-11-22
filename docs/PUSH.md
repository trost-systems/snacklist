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

Answers and logs carry counts and fixed codes only: never a token, a user
id or notification text.

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
- **Sign-out.** Before the session ends the app unregisters the token
  (2 s at most), deletes it at FCM (3 s at most) and forgets the opt-in,
  so the next account on the device starts without push. Account
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
