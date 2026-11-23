# Reviewer account (synthetic)

Reviewers of both directories sign in as one synthetic user. It holds invented data only. This file
holds no password and no real credential: Ops chooses the password and gives it to the vendors
through their secure forms or email (see `docs/done/415.md`, "FOR OPS").

## What Ops creates

1. The user `hello+aireview@snacklist.app` (the address, per the lead, 2026-11-23), created
   **confirmed** with a password of Ops' choosing, in the production Supabase project. Dashboard:
   Authentication, Users, "Add user", "Create new user", with "Auto Confirm User" ticked. The
   password goes in a password manager, 20+ random characters.
2. Its household and data, by the seed script (idempotent, run once):
   ```bash
   AI_REVIEWER_DB_URL='<postgres URL of production, from the secrets store>' \
     scripts/seed-ai-reviewer.sh <the user's id from the Users page>
   ```
   It creates "Haushalt Beispiel (Testkonto)" with the stores dm, Lidl and Edeka in their usual
   sections and IKEA with a walk order the script sets itself (furnishings first, fresh food and
   drugstore hidden; the app has no seeded IKEA layout), and 11 invented items (test-cases.md lists them). Running it again adds nothing that is already open;
   it does not move an item a reviewer moved or remove one a reviewer added, so for a clean slate
   after review delete the household and run it again. It refuses a user id that does not exist (exit 3). It was proved on
   a local stack: two runs, one household, 4 stores, 11 items.
3. Access for the reviewer: while the server switch `integration_lock` is off, as in production
   today, nothing else is needed. If it is turned on before review, the account needs whatever the
   lock admits (the research and `docs/PURCHASES.md` describe the grant); decide that then.
4. Leave the server switch `mcp_lists_stores` **off** for the submission: the five list and store
   tools wait for Legal's privacy section 7 text (`docs/MCP.md`, NEEDS_LEAD Job 345), so the
   directories see 17 tools. Switch it on only after Legal's yes, and then before the portal syncs.

## Sign-in check (the password flow on our consent page)

Checked in code on 2026-11-23, with the existing e2e test `a signed-out user signs in on the way to
the consent page and lands back on it` (`e2e/tests/mcp.spec.ts`) as the proof of the whole path:
authorize, sign-in page, password, consent page, redirect with a code.

| Question | Answer |
| --- | --- |
| Email confirmation | A password sign-in works only for a **confirmed** user; an unconfirmed one gets Supabase's "Email not confirmed". Create the user confirmed (step 1). |
| Captcha / Turnstile | The app sends no captcha token (`app/lib/session/login_screen.dart` calls `signInWithPassword(email, password)` only), and `supabase/config.toml` has none. If the production project had captcha on, every password sign-in would fail, so it must be off; confirm in the dashboard under Authentication, Attack Protection. Not checkable from this box. |
| MFA | The app has no MFA screen. Local config has TOTP and phone MFA off. Do not enrol a factor on the reviewer user. |
| Magic link | Not required. It is an alternative on the same page. |
| Anything else on the way | In a browser tab that carries an OAuth consent URL (`next`), the router skips the analytics consent and the name step (`authRedirect` in `app/lib/shell/router.dart`). The user needs a household, which the seed creates; without one the onboarding would come first. |

No code change was needed. Before sending credentials, Ops signs in once in a private window through
a real authorization: add the connector in Claude (or run `scripts/mcp-smoke.sh` and a client), sign in
with email and password, and reach "Erlauben". The language is German by default.

## After review

Rotate the password or disable the user once both reviews are done. To remove the data, delete the
account in the app (More, delete account) or delete the household first; deleting only the auth user
in the dashboard leaves the household behind.
