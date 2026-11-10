# Account deletion and data export

Every user can delete their account and export their data from inside the
app. This page says what is deleted, what stays and for how long. The
reasons behind the choices are in `docs/DECISIONS.md`, job 9.

## Where in the app

- **Mehr › Konto › Konto löschen.** The Konto page (`/more/account`, its
  own page since job 29d; the MCP access is on Mehr › Zugänge). The screen
  is `app/lib/settings/account_screen.dart`.
- **Welcome screen.** A signed-in user without a household finds
  "Konto löschen" below the onboarding form.
- **Mehr › Konto › Meine Daten exportieren.** This downloads a JSON
  file on the web. On iOS and Android it opens the share sheet.

The dialog says what happens to the shared household before anything is
deleted. Deletion starts only after the user types `LÖSCHEN` (or
`LOESCHEN`) and taps "Endgültig löschen". Deletion needs a connection.
Offline, the app refuses with a message and deletes nothing. When deletion
succeeds, the app signs out, clears the device cache and shows the sign-in
screen with "Dein Konto wurde gelöscht."

## What is deleted

Deletion is immediate and final. It runs in one database transaction, so
it either completes or deletes nothing.

| Data | What happens |
| --- | --- |
| Account (`auth.users`): email, password hash, sign-in identities (Google, Apple), sessions, refresh tokens, MFA factors, one-time tokens | Deleted |
| Profile (`profiles`): display name | Deleted |
| Household membership (`household_members`) | Deleted |
| Personal access tokens (`personal_access_tokens`) | Deleted. MCP and Siri calls with them answer 401 from then on. |
| OAuth grants for connected apps (`auth.oauth_consents`, `auth.oauth_authorizations`) and their sessions | Deleted. Connected MCP clients lose access at once. |
| Authorship of history (`item_events.actor`) | Removed (set to null) in every household |
| "Added by" and "bought by" on items (`items.added_by`, `items.bought_by`) | Removed (set to null) |
| Sign in with Apple tokens at Apple | Revoked when possible (see below) |
| Local device data (cached list, household, session) | Cleared on the device that deletes |
| Snacklist Lifetime purchases (`purchases.user_id`, `entitlements.granted_by`, job 25) | The link to the account is removed (set to null). The purchase row stays without it, and the household keeps its unlock (see "What stays") |

Leaving a household, or being removed from it, unlinks the user from that
household's content in the same way (Legal N-115, trigger
`household_members_forget_user`): their id goes from its items, history,
lists, merges, invites, join decisions and `households.created_by`. Their
other households keep it. The last member leaving keeps their id: the household
is deleted with its content, or archived for them to bring back as it was.

## What happens to the household

- **Other members remain** (for example, Peter deletes and Lea stays). The
  household, its list, its history, its categories, its stores and its
  learned memory all stay for Lea. Items Peter added stay on the list, but
  without his name. If Peter was the household's owner, ownership passes
  to the member who joined first after him.
- **The user is the last member.** The household is deleted with
  everything in it: items, history, categories, stores, store layouts,
  the learned category and store memory, open invites, every token
  issued for it, and its Snacklist Lifetime unlock.

## Sign in with Apple

Apple requires apps that offer Sign in with Apple to revoke the user's
tokens when the user deletes the account (App Review guideline 5.1.1(v),
Apple TN3194).

- **iPhone.** After the typed confirmation, the app asks Apple for a fresh
  authorization code (the Apple sheet). The `account` edge function
  exchanges it at `https://appleid.apple.com/auth/token` and revokes the
  refresh token at `https://appleid.apple.com/auth/revoke`. Revocation
  runs after the database delete succeeded. Apple codes are single-use and
  valid for five minutes, so a delete that fails leaves the code unspent
  for the retry.
- **Web and Android, or when revocation fails.** In those cases the server
  holds no Apple token (Supabase Auth does not keep provider tokens). The
  account is deleted anyway, as TN3194 requires, and the app tells the user
  where to remove "Snacklist" from their Apple ID. On iOS the path is
  Einstellungen › [Name] › Anmelden & Sicherheit › Mit Apple anmelden.
- Revocation needs the Apple key as a function secret on the hosted
  project. Until Peter sets it (`docs/NEEDS_PETER.md`, job 9), every
  deletion takes the fallback path.

Google sign-in needs no revocation. Google has no such requirement, and
deleting the Supabase user removes the link to the Google account.

## What stays, and for how long

- **The shared household** when other members remain (see above). It is
  their data.
- **Item names and history in that household.** The text "Milch" that
  Peter once added stays in Lea's list and history. It is no longer linked
  to him.
- **Platform logs.** Supabase keeps API and database logs for 1 day on the
  Free plan (https://supabase.com/pricing). They can contain the deleted
  user's id and IP address. They expire on their own.
- **Backups.** The project is on the Free plan, which has no automatic
  backups (https://supabase.com/pricing). Nothing is restored from a backup.
- **Copies outside the app.** An exported JSON file stays wherever the user
  saved it. Apple and Google keep their own records of the sign-in.

- **Snacklist Lifetime purchases** (job 25, `docs/PURCHASES.md`). The store's
  transaction (store, product, transaction id, dates, price, currency,
  country) stays without any link to the account, so a refund can still be
  matched and the same purchase cannot unlock a second household. The
  household keeps its unlock while it exists; the purchase can unlock
  another household only after that one is deleted.

Nothing is kept for legal reasons. Snacklist issues no invoices: Apple sells
in-app purchases as our commissionaire and Google as merchant of record,
and both keep the tax records of the sale (DECISIONS 25.9).

## Data export

"Meine Daten exportieren" calls `public.export_my_data()`. It saves
`einkauf-daten-YYYY-MM-DD.json`, which is JSON per GDPR Art. 20 (a
structured, machine-readable format). The export holds only the caller's
own data:

| Key | Contents |
| --- | --- |
| `format`, `version`, `exported_at` | `family-groceries-export`, `1`, the export time |
| `account` | id, email, created and last sign-in time, sign-in providers |
| `profile` | display name, created time |
| `household` | id, name, role and join time, or null |
| `items_added` | the items you added to your current household, with brand, properties, quantity, status, category, store and times. Items you added in a household you left belong to that household and are not exported; your actions there are in `history`. |
| `history` | your entries in the item history (`added`, `bought` and so on), with item name, category and time |
| `access_tokens` | name, last four characters, created, last used and revoked times. The export never includes the token or its hash. |
| `connected_apps` | the OAuth apps you allowed, with their scopes and grant times |
| `purchases` | the Snacklist Lifetime purchases your account verified: store, product, the store's transaction id, environment, purchase and refund times, price, currency, country, and the household it unlocks (job 25) |

Other members' names and data are not part of the export. Only a session
in the app itself can call the export, never an MCP OAuth token.

## For developers

- Server: `public.delete_account(p_user uuid)`, service role only, and
  `public.export_my_data()` are in the job 9 migration in
  `supabase/migrations/`. Job 15 (`20261025212052_item_details.sql`)
  replaces `export_my_data()` to add brand and properties. The edge function is `supabase/functions/account/`
  (`POST /functions/v1/account/delete`). It accepts only the app's own
  session JWT and refuses personal access tokens and OAuth client tokens
  with 403.
- Retrying is safe. A second call after a successful deletion whose
  response got lost still answers 200.
- The app retries a deletion once, after one second, when the edge
  gateway drops the call (502, 503, 504 or 546 without the handler's JSON
  `error`). The local edge runtime does this now and then on a cold worker,
  and the hosted one on boot failures. A retry that finds the account
  already gone answers `apple: "manual"`, because it cannot know whether
  the first call revoked Apple's grant, so the app shows the Apple ID hint.
- Tests: `supabase/tests/account_deletion.test.sql` (pgTAP),
  `supabase/functions/account/*_test.ts` (Deno),
  `e2e/tests/account.spec.ts` (Playwright) and
  `supabase/functions/account/smoke.sh` (curl against the local stack).
- The verify recipe is `.cursor/skills/verify-family-groceries/features/account.md`.
- The public page for Google Play is `app/web/konto-loeschen.html`
  (`https://app.snacklist.app/konto-loeschen.html`). Peter approved it
  on 2026-10-30 (job 33a); it has no draft banner and no noindex.
