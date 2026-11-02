# Decisions

Calls made without a human in the loop, with the reason. Peter can overturn
any of them; each entry says what changing it would touch.

## Job 1 (foundation), 2026-10-22

1. **App identifiers.** Bundle id and applicationId
   `com.petertrost.familygroceries`; display name "Einkauf". Changing them
   touches `app/android/app/build.gradle.kts`, the Xcode project and
   `Info.plist`.
2. **One household per user.** `household_members.user_id` is unique.
   Joining another household moves the user; if they were the last member,
   the old household and its list are deleted (the app warns before joining).
   Peter and Lea share one list, so multi-household support would only add
   a switcher nobody needs.
3. **Invites are codes, never sent.** 8 characters from an alphabet without
   look-alikes (no 0/O/1/I), valid 14 days, reusable until then, revocable
   via `revoked_at`. The app shows the code and a `/join/<code>` link to copy.
4. **Fallback category "Sonstiges".** Seeded as an 11th category (sort order
   1000, `seed_key = 'other'`) so every item always has a category and a
   correction can target it. A trigger forbids deleting it.
5. **Seeded rows carry a `seed_key`.** Categories and stores keep a stable
   identity (`produce`, `drugstore`, `dm`, ...) when renamed, so later jobs
   (store layouts, the classifier dictionary) can address them.
6. **Placeholder classifier in Postgres.** `classify_item(household, name)`
   matches about 60 keywords by exact or suffix match ("Vollmilch" ends in
   "milch"), else the fallback. The items insert trigger calls it when no
   category is given. Job 2 replaces the body; callers do not change.
7. **Klopapier/Toilettenpapier go to Haushalt** in the stub (paper goods
   sit with household goods in Lidl and Edeka). Job 2 revisits this with the
   store layouts.
8. **Quantity is free text.** `items.quantity` holds "2", "500 g",
   "3 Dosen". The app parses a leading amount ("2 Gurken") or a trailing
   amount with a unit ("Hack 500 g"); a bare trailing number stays part of
   the name ("Windeln Größe 4").
9. **History.** Ticked items keep `status = 'bought'` with `bought_at` and
   `bought_by`; the app shows the last 20 under "Zuletzt gekauft" for a
   one-tap re-add. Every insert, tick, restore, edit and delete is also
   written to `item_events` by a trigger (append-only for clients).
10. **Optimistic writes as idempotent ops.** The app applies each change
    locally at once, queues it, and replays it until the server answers.
    Client-generated UUIDs make adds idempotent (`upsert ... ignoreDuplicates`).
    Network errors keep the op queued and retry every 3 s; a refused write is
    dropped and reported. On every realtime (re)subscribe and on app resume
    the app refetches and folds pending ops on top.
11. **Cold start needs the network.** The app keeps no local copy of the
    list yet: offline at launch it shows a spinner and retries until online.
    Changes made while online stay queued across connection loss.
    Tracked in https://github.com/peter-trost/family-groceries/issues/3.
12. **Duplicates.** Adding an item whose name matches an active item
    (case-insensitive) does not add a second row; the app says it is
    already on the list.
13. **State management: flutter_bloc cubits, go_router, no codegen.** Same
    libraries as emotely, without freezed/get_it to keep the app small.
14. **Path URLs on web** (`/join/CODE`, later `/oauth/consent`). Static
    hosting needs an SPA fallback to `index.html` (`e2e/serve.mjs` does this).
15. **Semantics always on for web.** `SemanticsBinding.ensureSemantics()`
    makes the DOM accessible to screen readers and to Playwright.
16. **Flutter web focus workarounds**, found by experiment (see the PR):
    the add field handles a hardware Enter in `Focus.onKeyEvent` instead of
    the text-input action, which otherwise blurs the field and leaves it
    unable to take the next item; the tick checkbox is wrapped in
    `ExcludeFocus` because a focused element that disappears with its row
    leaves the field unable to receive text on the next tap.
17. **No web hosting yet.** The hosted Auth site URL and redirect list wait
    for a public web URL (GitHub Pages is the free candidate); see
    `NEEDS_PETER.md`. Superseded by 7.x: the web app is on Vercel.
18. **Local stack trims.** Studio, Storage and Analytics are disabled in
    `supabase/config.toml` to fit the shared 15 GB box; enable them locally
    when needed.
19. **pstack models.** `/setup-pstack` ran non-interactively on 2026-10-22
    with budget "large": Opus for code and judgment, Sonnet for swarm
    workers and second opinions (Grok slugs do not exist in Claude Code).
    Written to `~/.cursor/rules/pstack-models.mdc`.
20. **Node 20 on this box.** supabase-js needs a WebSocket for realtime in
    Node < 22, so the e2e helpers pass `ws` as the transport. CI uses Node 22.
21. **Repository location.** The repo moved from `petertrost-bot/family-groceries`
    to `peter-trost/family-groceries` (GitHub redirect seen on the first push,
    2026-10-22). The local remote points at the new URL; nothing else in the
    repo names the owner.
22. **Android APK builds on this box.** `scripts/bootstrap.sh --android`
    installs OpenJDK 21 and the Android command-line tools; `flutter build apk
    --release` then produces `app-release.apk` (56.5 MB, 3.6 min cold). It is
    signed with the debug key until job 4 adds release signing via secrets.

## Job 1 review fixes (review 0), 2026-10-22

23. **`classify_item` is members-only for signed-in callers.** It returned
    another household's category ids to anyone who knew that household's id.
    Migration `20261022190000_classify_item_members_only.sql` raises
    `not_a_member` (42501) when `auth.uid()` is set and is not a member.
    Calls without a user (service role for MCP and Siri, the database
    itself) stay allowed; the items trigger runs as the caller, so member
    inserts are unaffected.
24. **Merge author.** The squash commits `26e9d06` (#1) and `13dfe23` (#2) on
    `main` carry `petertrost-bot <bot@petertrost.com>`, the account's default
    email, instead of the required
    `341616691+petertrost-bot@users.noreply.github.com`. `main` is not
    rewritten (no force-push). GitHub rejects the noreply address as a merge
    `--author-email` ("Invalid email address"), so `scripts/merge-pr.sh`
    squashes the PR locally into one commit authored with the noreply address
    and titled "<PR title> (#n)", pushes it to the PR branch, and once
    `ci-ok` passes on it, rebase-merges it. A rebase merge keeps the commit
    author, and one commit keeps `main` as linear as a squash merge.
    One slip while building this: commit `008e2b0` (adds only
    `scripts/merge-pr.sh`) was pushed straight to `main` after a failed
    branch checkout left the shell on `main`. It was a fast-forward, not a
    force-push; it stays, and CI ran on it like any `main` push.
25. **Input length caps in the app.** The add field and the edit sheet cap the
    name at 120 characters and the quantity at 40, matching the table checks,
    so a long paste no longer ends in a server rejection.
26. **No pstack config in the repo.** `/setup-pstack` writes only the
    per-user rule `~/.cursor/rules/pstack-models.mdc` (see #19); the repo
    carries none by design.
27. **Node 20 stays on this box.** Bootstrap does not replace the system
    Node, because other workloads share the box. CI runs Node 22. The
    supabase-js deprecation warning in local Playwright runs is expected.

## Job 1b (Sign in with Google and Apple), 2026-10-22

1. **Flows.** Google is native on iOS and Android, and Apple is native on
   iOS; both use `signInWithIdToken`. Apple on Android and both providers on
   web use the OAuth redirect with PKCE. These are the flows Supabase
   documents. google_sign_in on web cannot hand an ID token to our own
   button. Details in `docs/AUTH.md`.
2. **Nonce check on, one Google nonce per app run.** google_sign_in's
   `initialize` (the only place its nonce goes) may run once per process,
   so Google gets one random nonce per app run and Apple gets a fresh one
   per attempt. `skip_nonce_check` stays false. If real iPhones ever return a
   cached token with an old nonce, the fallback is `skip_nonce_check = true`
   for Google only.
3. **No google_sign_in app package.** The app depends on
   `google_sign_in_platform_interface` plus the Android and iOS
   implementations. The app-facing package would add `google_sign_in_web`,
   which loads Google's script on every page view of the web app (seen in
   the Playwright network log) although web signs in by redirect. Without
   it, no request goes to Google before the user taps the button. The cost
   is the platform interface's slightly lower-level API in
   `plugin_sign_in.dart`.
4. **Configuration is public client IDs in `app/config/auth.json`,** read
   with `--dart-define-from-file`. An empty value hides the button. Secrets
   live only in Supabase. The iOS reversed client ID also has to be in
   `ios/Flutter/Auth.xcconfig` because `Info.plist` is static; a unit test
   keeps the two files in step.
5. **Apple's name.** The app stores it with `updateUser` on the first native
   sign-in. A trigger copies `full_name` into `profiles.display_name` while
   the profile still has the derived name. A failed `updateUser` does not
   fail the sign-in, because the user is already signed in at that point.
6. **Hosted config by script, never invented.** `scripts/configure-social-auth.mjs`
   enables a provider only when its credentials are in the environment.
   Run on 2026-10-22 without provider credentials, it added only the app's
   deep link to the redirect allow list.
7. **Mobile deep link `com.petertrost.familygroceries://login-callback`**
   for Apple on Android and for magic links on the phones. Before this job,
   mobile magic links went to the site URL, which is the web app.
8. **Local test provider.** `[auth.external.keycloak]` in `config.toml`
   points at `e2e/fake-oidc.mjs` on `host.docker.internal:54399`. GoTrue
   runs the same ID-token, nonce and linking code for it as for Google and
   Apple, whose issuers are hard-coded. Its signing key comes from a fixed
   seed, so parallel worktrees can share one running copy. The deploy
   workflow does not push `config.toml`; never enable this provider on the
   hosted project.
9. **Button label "Mit Google anmelden"** as the brief asks. Google's German
   guideline page prefers „Über Google anmelden“ but allows localized
   labels. The Google "G" was cut from Google's 2026 asset kit with Chromium
   (transparent PNG at 1x, 2x and 3x).
10. **Cancel is reported.** A canceled provider dialog or `access_denied` on
    the return URL shows "Anmeldung abgebrochen", as the brief asks.
    Supabase's examples treat it as silent.

## Job 3 (MCP server, OAuth 2.1, personal access tokens), 2026-10-22

Numbered 3.x so parallel jobs don't collide. Details and sources: `docs/MCP.md`.

3.1. **Tools run as the user, not the service role.** `_shared/db.ts` opens one
     Postgres transaction per tool call on `SUPABASE_DB_URL` with role
     `authenticated` and `request.jwt.claims.sub` set to the caller. RLS,
     triggers and `classify_item` (members-only since #4) behave as for the
     app, and a missing household filter cannot leak another household's data.
     The alternative, the service role with explicit `household_id` filters,
     would have made every query a possible leak and given `auth.uid()` no
     value in triggers.
3.2. **Audience check = issuer + signature + `client_id`.** Supabase ignores
     RFC 8707 `resource` for `aud` (always `authenticated`; verified on a real
     token). The MCP endpoint accepts a JWT only with the project's issuer,
     a JWKS signature (ES256/RS256), `role = authenticated` and a `client_id`
     claim, so a token issued to the app is not accepted. `authenticate()`
     still reports app session tokens as `via: 'session'`, because job 4's
     voice endpoint is called by the app itself.
3.3. **Both MCP protocol eras.** The latest spec (2026-07-28) is breaking:
     no `initialize`, no sessions. `@modelcontextprotocol/server` 2.3.1's
     `createMcpHandler` serves it and 2025-era clients from one tool
     definition, stateless, `GET`/`DELETE` → 405. A fresh server per request
     keeps the authenticated caller in a closure, not in shared state.
3.4. **Protected Resource Metadata under the function path.** An edge function
     cannot serve `https://<ref>.supabase.co/.well-known/…`, so the metadata
     lives at `<endpoint>/.well-known/oauth-protected-resource` (and at
     `<endpoint>/oauth-protected-resource`, Supabase's own helper path). The
     `WWW-Authenticate` header points at it, which the spec lists first.
3.5. **Advertised scopes `openid email`.** Supabase rejects custom scopes, and
     the tools need none; household access comes from membership.
3.6. **Origin check with an allowlist.** Browser requests must come from the
     project host, localhost, or `MCP_ALLOWED_ORIGIN_HOSTS`; requests without
     an `Origin` (all native and server-side clients) pass. CORS stays open,
     because no cookies are involved.
3.7. **Personal access tokens.** Format `fgp_` + 32 random bytes, base64url.
     The table stores a SHA-256 hash (no salt or slow hash needed: the token
     has 256 bits of entropy) and the last four characters. A token acts as
     its creator in the household it was created in, and stops working when
     the creator leaves it. At most 20 active tokens per user. Revocation is
     one-way (trigger). Revoked tokens are hidden in the app.
     The cross-household cases for this table live in
     `supabase/tests/personal_access_tokens.test.sql`, not `rls.test.sql`,
     to stay out of other jobs' merge conflicts.
3.8. **Consent survives sign-in.** `authRedirect` carries the consent URL as
     `next` through `/login` and `/welcome`. Only a same-origin
     `/oauth/consent` URL is accepted, so `next` cannot become an open
     redirect.
3.9. **Settings screen "Zugänge"** (menu entry) holds the MCP URL, the tokens
     (create, shown once, revoke) and the OAuth grants (`listGrants`,
     `revokeGrant`), so a connected assistant can be disconnected without
     the dashboard.
3.10. **`add_items` through the items insert path for now.** MCP inserts rows
      without a category, so the items trigger calls `classify_item`. Job 2's
      `public.add_items` RPC replaces this inside `mcp/list.ts` `addItems()`
      once it is on main.
3.11. **Local edge runtime policy `oneshot`.** With `per_worker`,
      `supabase start` reuses one worker until its 1 s CPU soft limit, then
      ends it, and requests in flight fail with 503 after about 13 s (seen as
      "CPU time soft limit reached" in the edge runtime log; it failed one in
      four full e2e runs). `oneshot` starts a worker per request, which
      matches the hosted per-request CPU limit. Three full runs were clean
      afterwards.
3.12. **Local DB host alias.** Under `supabase start`, `SUPABASE_DB_URL` names
      the host `supabase_db_<project>`, which Deno's resolvers reject
      (underscore). `_shared/db.ts` maps it to the container alias `db`.
      Hosted URLs are unaffected.
3.13. **Remote OAuth server enabled through the Management API**
      (`SUPABASE_ACCESS_TOKEN` was available): OAuth server on, dynamic
      registration on, authorization path `/oauth/consent`. The project
      already signed with ES256. Deploying the function and migrations is
      still Peter's step (no DB password on the box), see `NEEDS_PETER.md`.

## Job 2 (classifier and stores), 2026-10-22

28. **One item key for the classifier and both memories.** `public.item_key(name)`
    lowercases the name and folds umlauts and accents (`ä` and `ae` both become
    `a`). It turns `ß` into `ss`, drops quantities with units and percentages,
    and turns punctuation into spaces. Then it stems each word by stripping one
    plural ending (`-n` after e/l/r, then `-e`, then `-s`). So "2 kg Äpfel" and
    "Aepfel" share the key `apfel`, and so do Gurke and Gurken. Plurals in
    `-er` (Eier, Kräuter) are not reduced, so the dictionary lists both forms.
    The key is a matching key, never shown.
29. **Pipeline order: memory, dictionary, fallback.** `classify_item` checks
    the household's learned memory by exact key first. Then it checks the
    dictionary, and the first rule that matches wins:
    1. A multi-word phrase found in the name.
    2. The whole name is a term.
    3. A frozen marker. "TK", or a word starting with Tiefkühl, tiefgekühlt
       or gefroren, sends the item to Tiefkühl, so TK-Spinat is not produce.
    4. Per word, the longest term the word ends with (compound heads:
       Vollmilch → milch).
    5. The longest term of four or more letters the word starts with.

    When matches tie, the later word wins, because the head of a German
    noun phrase comes last. Terms under three letters (ei, öl) only match
    whole words. Anything else goes to "Sonstiges". Pet food is Haushalt.
30. **Learning lives in a trigger, not in the callers.** An `UPDATE` that
    changes `items.category_id` is a correction. It goes into
    `category_memory` keyed by item key and category, with a count, and the
    latest correction wins. The edit sheet's category picker and drag between
    groups both write that column, and so will MCP's move tool. Edits that
    keep the category teach nothing. Moves caused by deleting a category teach
    nothing either (a transaction-local `family_groceries.learning = off`).
31. **Dictionary as a TSV plus a generated migration.** The reviewable file is
    `supabase/classifier/dictionary.tsv`. `generate.ts` writes it into a
    migration, and a Deno test in CI fails if the newest
    `*_classifier_dictionary*.sql` migration differs from the TSV. To change
    the dictionary: edit the TSV, create a new migration, and run the
    generator on it. A migration already on `main` is never edited.
32. **Tea and coffee are Vorrat; plant milks are Kühlregal.** This follows
    where Lidl and Edeka shelve them: coffee and tea sit with the dry goods,
    oat and soy drinks sit next to milk. Ready-to-drink tea (Eistee) is
    Getränke. Baby food jars and porridge are 👶 Drogerie, like the baby aisle.
33. **Klopapier stays in Haushalt** (#7 revisited). Toilet paper sits with the
    paper goods in Lidl and Edeka, and dm shows Haushalt in its view, so
    untagged toilet paper still appears when shopping at dm.
34. **Store layouts.** The defaults come from store reports and are documented
    with sources in `docs/STORE_LAYOUTS.md`. Every store has a row for every
    category, with a `hidden` flag for categories the store does not carry.
    dm hides produce, bakery, chilled, meat and frozen. A new category goes
    after the last shown category in each store, or just before Sonstiges
    when Sonstiges is the last shown one.
35. **Store views.** A store view shows the items tagged to that store plus
    the untagged ones, in the store's order. An untagged item in a category
    the store hides is left out. A footer counts these items and can show
    them. An item tagged to the store always shows. Items tagged to another
    store never show.
36. **Item→store memory.** It is learned from two things. Ticking an item off
    inside a store view tags the item with that store. Choosing a store in
    the edit sheet tags it by hand. Both write `items.store_id`, and the
    trigger records it, latest wins. A new item with no store gets the
    remembered store. Setting "Alle Geschäfte" in the edit sheet clears the
    memory, which means the item can be bought anywhere again. An item typed
    inside a store view is tagged with that store, so it stays visible where
    it was typed. Typing it in "Alle" leaves the memory in charge. A consequence: an
    untagged item ticked off at Lidl is a Lidl item from then on. It no longer
    shows in the Edeka or dm view until someone retags it in the edit sheet
    (or sets "Alle Geschäfte").
37. **The store picker resets to "Alle" on launch.** Planning at home happens
    in "Alle", and the picker is one tap away in the store. It sits under the
    add field and never takes focus, so autofocus on open is unchanged.
38. **Deleting a category moves its items** (active and bought) to a category
    the user picks, by default Sonstiges, which cannot be deleted. The
    category's learned corrections go with it. Its seed identity passes to the
    target (`categories.absorbed_seed_keys`), so dictionary hits for a deleted
    "Tiefkühl" land where its items went instead of in Sonstiges.
39. **`add_items` is the shared add path for MCP and Siri** (announced on the
    job board). Each entry may carry a quantity, which `public.parse_entry`
    parses with the same rules as the app's `parseEntry`. An entry whose item
    key is already active returns the existing row instead of a duplicate.
    `p_store` tags the new items. Without it, the remembered store applies.

## Job 4 (voice and release), 2026-10-22

<!-- job4-voice -->
- **Voice splitting lives in the `voice` edge function** (`parse.ts`), not
  in SQL: a token-based splitter with table-driven Deno tests (about 200
  sentences, plus a 759-sentence adversarial pass). Siri and the in-app
  mic share it; the app calls it with `mode: "parse"` and adds the entries
  through its own optimistic ops, so dictated items behave like typed ones
  (instant, offline-queued, duplicates refused).
- **Siri gets plain text.** `?format=text` answers with the sentence only,
  so the Shortcut is exactly Diktieren → Inhalte von URL abrufen → Text
  sprechen with no dictionary step. Errors also come back as German
  sentences with a matching HTTP status, so Siri speaks them too.
- **The voice function checks its own bearer token** (`verify_jwt = false`):
  PATs are not JWTs. It accepts PATs and app session JWTs through the shared
  `authenticate()` and writes as the user (role `authenticated`), so RLS,
  triggers and the classifier run exactly as for the app.
- **Items already on the list are not added twice** and Siri names them
  ("Schon auf der Liste: Milch."). An amount said after a comma joins the
  item before it ("Äpfel, ein Kilo" → 1 kg Äpfel).
- **"Kein Zucker" becomes "Zucker".** Leading "kein/keine" is dropped,
  because "Wir haben keine Milch mehr" is how people say it; a negative
  entry on a shopping list is not a real use.
- **No mic on web.** The browser's Web Speech API sends audio to Google's
  servers and is not on-device; typing is the web fallback. iOS and
  Android use the platform recognizer through `speech_to_text` in de-DE
  (free, no API key). On-device recognition is not forced, so devices
  without a German offline model still work.
- **The Android release build declares INTERNET.** Flutter's template grants
  it only to debug and profile builds; a release APK could not reach
  Supabase without it.
- **Shortcut name "Einkaufsliste"**, as the brief asks. If Siri routes that
  to Reminders' grocery list, `docs/SIRI_SHORTCUT.md` suggests
  "Einkauf notieren".
- **The list is cached on the device** (closes #3, supersedes #11). A
  versioned `ListSnapshot` (catalog with stores and layouts, server rows,
  pending `ItemOp`s) lives in shared preferences per user and household,
  next to each user's last household. A start without network opens that
  household and its list with the offline indicator; the usual resync and
  flush take over once Supabase answers, and replayed ops are harmless
  because they are idempotent (#10). A change to the queue is saved at
  once, server churn 300 ms after it settles. Signing out drops the whole
  cache; a household switch or leaving drops the user's other lists, and a
  list only saves while it is the user's current household, so a closing
  list cannot write a stale copy back. An access token that expired while
  offline no longer signs the user out: the failed refresh is retried by
  supabase_flutter, which keeps the session.

- **Duplicates compare `item_name_key`, the memory keeps `item_key`**
  (review 0). `item_key` drops every number, so "Windeln Größe 5" counted as
  already on the list after "Größe 4". `add_items` and MCP now compare
  `item_name_key` (`item_key` plus the numbers left in the name); the
  classifier and store memory still use `item_key`, so sizes share a
  learned category. Migration `20261023070910_item_name_key.sql`.
- **More than 30 items in one sentence**: the first 30 are added and Siri
  says the rest was not taken ("Mehr als dreißig auf einmal gehen nicht …");
  the JSON answer has `truncated: true`.

<!-- job4-release -->
- **Releases are manual.** The Release workflow runs only from the Actions
  tab, not on every merge like emotely: two users do not need a build per
  merge, and each run costs macOS minutes. Build numbers stay
  `1000 + run number`.
- **Missing release secrets skip, not fail.** Same rule as the Supabase
  deploy workflow: until Peter finishes the store setup, a run is green and
  names the missing secrets in a notice.
- **Team ID and match repo URL come from the environment**
  (`APPLE_TEAM_ID`, `MATCH_GIT_URL`), so the public repo holds no account
  identifiers and the export options are generated by the lane.
- **Release signing falls back to the debug key** when
  `android/key.properties` is absent, so local release builds need no
  secrets. Proven on the box with a throwaway keystore under `/tmp`.
- **The icon is generated** by `scripts/icons.py` (white basket on the theme
  green `#2E7D32`), including an Android adaptive icon with a monochrome
  layer, instead of adding `flutter_launcher_icons` to `pubspec.yaml`.
- **iOS builds are unverified on this box.** Linux cannot run Xcode; the iOS
  lane is checked only by `fastlane lanes` parsing it and by mirroring
  emotely's working lane.

## Job 5 (verification skill), 2026-10-23

5.1. **Primary surface is the Linux desktop debug app, not the Android
     emulator, on the build box.** Creating a KVM vCPU on this VM hits
     `kernel BUG at arch/x86/kvm/x86.c:702` (`vmx_vcpu_create`; three oopses,
     kernel tainted). Retrying risks the shared host, so
     `~/.config/fg/kvm-broken` records it and `fg` refuses the emulator while
     the marker exists. The same Flutter app (same widget tree, the same
     Marionette binding) runs as a Linux desktop window on Xvfb. It is real
     native Flutter, not a browser. Android stays fully implemented in `fg`
     for machines with a working emulator and is listed as unverified.
5.2. **`app/linux/` added** (`flutter create --platforms linux`, application
     id `com.petertrost.familygroceries`, phone-sized 412×892 window). Needed
     for 5.1; it also makes the app runnable as a desktop app.
5.3. **Marionette entrypoint `app/test_driver/main_marionette.dart`;
     `marionette_flutter` is a dev dependency.** Same pattern as
     flutter_driver's `test_driver/app.dart`. Code under `lib/` cannot import
     it (`depend_on_referenced_packages` fails `flutter analyze`). Release
     builds use `lib/main.dart`; a release `libapp.so` has no Marionette
     strings (checked). The entrypoint throws if built in release mode.
5.4. **One CLI (`scripts/fg` → `.cursor/skills/verify-family-groceries/fg`,
     Deno) instead of markdown recipes.** Deno is already in the toolchain
     and CI. Commands are one table (help, flags, `--dry-run`, JSON errors
     generated from it), and every process call goes through an injectable
     shell, so the CLI's own tests run without a stack (16 tests in CI).
5.5. **Supabase runs from a generated workdir** (`~/.cache/fg/<prefix>/stack`:
     config.toml with the port lines and project id rewritten, symlinks to
     migrations, functions and tests). Parallel agents never edit the tracked
     `config.toml` to get their own instance.
5.6. **Seeded users** `peter@fg.test` and `lea@fg.test` (password
     `test-password-123`, local only) in "Familie Test", created through the app's
     own RPCs (`create_household`, `create_invite`, `join_household`).
5.7. **Second client is a second real app** (two Linux instances, about
     650 MB each) with separate session storage via `XDG_*` dirs. `fg peer`
     (REST and Realtime as a user) is the light alternative, and the only
     one when the primary client is the emulator.
5.8. **Debug builds allow cleartext HTTP**
     (`app/android/app/src/debug/AndroidManifest.xml`) so the emulator can
     reach `http://10.0.2.2:<port>`. Release keeps Android's block.
5.9. **`flutter.inspector.structuredErrors=false` in fg builds.** Otherwise
     debug builds send Flutter errors only to the VM service, and `fg logs`
     would show nothing for a red error screen.
5.10. **Minimal ValueKeys** only where Marionette cannot reach a field by
      text: `login-email`, `login-password`, `household-name`, `invite-code`,
      `add-item-field`. Buttons are reached by their text; keyless fields by
      label (`fg type --label`).

## Job 3b (MCP follow-ups), 2026-10-23

3b.1. **Disconnect = session check per request.** Supabase's OAuth server
      cannot revoke an issued access token: its discovery document has no
      revocation or introspection endpoint. `revokeGrant` does delete the
      client's `auth.sessions` rows. `authenticate()` now accepts a JWT only
      while `auth.sessions` has its `session_id` for that user and
      `oauth_client_id`, and answers `401 invalid_token` otherwise. That is
      one primary-key lookup per request, run in parallel with the
      household lookup. Asking `/auth/v1/user` would also notice the missing
      session, but costs an HTTP round trip through Auth. Shorter token
      lifetimes would only shrink the window. App session tokens get the
      same check, so signing out also ends the voice endpoint's access.
3b.2. **MCP `add_items` calls `public.add_items` once per item.** That keeps
      the per-item `store` and the order of results. An explicit `quantity`
      overwrites the parsed one (an update that teaches nothing). An
      explicit `category` is applied as an update after the add, so the
      items trigger learns it. The tool tells assistants to send it only
      when the user names a category, so it is the user's correction.
      Supersedes 3.10.
3b.3. **Each checkout's e2e run uses its own port block.** `e2e/stack.ts`
      reads the URL, key and Mailpit URL from the environment or from
      `supabase status` and throws when one is missing, with no 543xx
      default. The web server port defaults to `<API port prefix>80`
      (54321 → 54380, 54621 → 54680). Before, all checkouts used 3100 with
      `reuseExistingServer`, so one job could test another job's build.
      `config.toml` allows loopback redirects on any port for this. The
      fake identity provider runs on the port of the Keycloak URL in the
      checkout's `config.toml` (`<prefix>99`). Before, every job used 54399
      with `reuseExistingServer`, and a run failed when the job owning the
      server finished (seen here: `ECONNREFUSED 127.0.0.1:54399` in 6
      id-token tests).
3b.4. **Playwright runs one worker locally** (CI keeps 2). With 3 workers,
      mem-guard paused this job for 45 s during a run (low RAM), and the
      paused MCP request timed out the test.

## Job 7 (Vercel hosting, auth config, API-only deploy), 2026-10-23

7.1. **Vercel hosts the web app** (Peter's decision, 2026-10-23 10:58,
     instead of GitHub Pages). A Git-linked Vercel project builds every push
     from `vercel.json`; production is `main` (since 2026-10-29: `release`,
     section "web-release-align"). The app is served at the
     domain root, so `WEB_BASE_PATH` and the Pages workflow are gone.
7.2. **The Flutter SDK lives in `node_modules/.flutter`.** Vercel's build
     cache keeps only `node_modules/**`. The SDK is a shallow clone of the
     version in `ci.yml` (one source for CI and Vercel); the pub cache sits
     next to it. Measured in Amazon Linux 2023 (`scripts/vercel-local.sh`):
     cold install 50 s, cached install 20 s, build 35 s. SDK plus pub cache
     are 1.55 GB uncompressed against Vercel's 1.5 GB cache limit; whether
     the compressed cache fits is unknown until the first Vercel builds. If
     it does not, every build pays the 50 s cold install.
7.3. **SPA rewrite for extensionless paths only.** `/oauth/consent`,
     `/join/CODE` and `/settings` serve `index.html`; a missing `.js` or
     `.png` stays a 404 instead of HTML that the browser would try to run.
7.4. **Cache headers.** Flutter's output is not content-hashed
     (`main.dart.js` keeps its name), so every file revalidates
     (`max-age=0, must-revalidate`, Vercel serves ETags), and the app routes,
     `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`,
     `version.json` and `manifest.json` are `no-cache`.
7.5. **The Vercel build refuses a wrong key.** `SUPABASE_URL` must be
     `https://<ref>.supabase.co` and `SUPABASE_PUBLISHABLE_KEY` must start
     with `sb_publishable_`; a missing or secret-looking value fails the
     build instead of shipping the compiled-in defaults.
7.6. **Edge function import maps via `config.toml`.** `supabase functions
     deploy --use-api` bundles only the uploaded files and never saw
     `supabase/functions/deno.json`, so bare imports (`jose`,
     `@modelcontextprotocol/server`) failed. Each `[functions.<name>]` now
     sets `import_map = "./functions/deno.json"`: one map shared with
     `deno test`/`lint`, no per-function copies to drift.
     `supabase/deploy/config_test.ts` fails for a function directory without
     it (checked: it fails on the old config).
7.7. **Migrations deploy through the Management API**
     (`supabase/deploy/migrate.ts`). This box and an API-only workflow have
     no Postgres connection. Each pending migration runs with its
     `supabase_migrations.schema_migrations` row (repo version and name) in
     one transaction, so `supabase migration list` and `db push` see the same
     history. Checked against the local database: a migration that fails
     leaves neither its objects nor its row, and the CLI lists an applied one.
     It stops on drift: a remote version missing locally, or a pending
     migration older than the newest remote one (rename it, as
     COORDINATION.md says).
7.8. **The Supabase deploy workflow fails without credentials.** It needs
     only `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` (no database
     password, no Docker) and ends with a smoke test of `health` and the MCP
     metadata. Before, missing secrets skipped every step and the run showed
     green in 6 s.
7.9. **Production redirect list has no localhost entries.** Earlier notes
     suggested `http://localhost:3000/**`; local development uses the local
     stack, and a localhost redirect on production would hand tokens to
     whatever runs on that port. `supabase/deploy/auth_urls.ts` sets the
     Site URL, the redirect list and the consent path and keeps entries added
     by hand.
## Job 2b (follow-ups to jobs 2 and 5), 2026-10-23

2b.1. **Bags and brand names have dictionary entries.** `-tüte` and
      `-beutel` are Haushalt (Mülltüten, Gefriertüten, Zipbeutel); Teebeutel,
      Windelbeutel and Filtertüten stay where explicit entries put them.
      Common cleaning and drugstore brands (Somat, Frosch, Lenor, Elmex,
      Blend-a-med, Penaten) stand for their product. `kleber` is listed so
      Sekundenkleber stops matching `leber` (Fleisch). Briefmarken stays
      Sonstiges: stamps have no supermarket aisle, as the dictionary test
      already said. Kaffeefilter and Filtertüten sit with the coffee
      (Vorrat), Hustenbonbons with sweets. Found with a sweep of 345 common
      non-food items through `classify_item`; 45 of the fixes are rows in
      `supabase/tests/classifier_dictionary.test.sql`.
2b.2. **The classifier folder has its own `deno.json`.** CI and
      `scripts/verify.sh` run `deno fmt --check && deno lint && deno test`
      inside `supabase/classifier`, the same command a developer runs there.
2b.3. **Screenshots wait for two identical frames.** Flutter animates on
      its canvas, which Playwright's `animations: 'disabled'` cannot reach.
      The grey Edeka chip in job 2's `06-store-dm.png` was the chip's
      deselect animation, not hover: the dm chip was mid fade-in in the same
      frame. `screenshot()` (e2e helpers) now polls until two frames 100 ms
      apart agree (2 s cap).
2b.4. **Each resync keeps its own ack map.** The list opens with two
      resyncs at once (start, and the channel's first `subscribed`). They
      shared one nullable map; the first to finish nulled it and the other
      threw, so the list showed Offline until the next write (3/3 menu joins
      on the web build, 2/3 creates on the Linux app). A resync that answers
      now also brings the list back online, but only while the realtime
      channel is subscribed, so a dead channel still shows Offline.
2b.5. **No postgrest GET retries.** postgrest 2.9.1 retries each GET three
      times (1 + 2 + 4 s), invisibly. The session and list cubits already
      retry every 3 s and writes are idempotent ops retried until acked, so
      the library retries only delayed an offline cold start (7.7 s to the
      cached list, 15 s to the Offline indicator; now 0.7 s). The option
      only reaches `client.rest` (`client.from` builds its query builder
      without it), so the app reads and writes through `client.rest`.
2b.6. **e2e tests close the contexts they open.** Specs open one context
      per user with `browser.newContext()` and the browser lives for the
      worker, so every earlier test's app kept running: 48 renderers and
      9.4 GB RSS by the end of a one-worker run. That load was the "OAuth e2e
      flake" (a consent test waited 34 s for its first page) and much of the
      box's memory pressure. `e2e/tests/fixtures.ts` extends `test` with an
      auto fixture that closes them; `conventions.spec.ts` fails if a spec
      imports `test` from `@playwright/test` directly. mcp.spec's
      `retries: 1` (job 4) is gone.
2b.7. **A catalog reload awaits before it reads the state.**
      `emit(state.copyWith(catalog: await fetch()))` evaluated `state` before
      the await and wrote the old pending ops and server rows back. An add
      acked during the fetch came back as pending forever (1 in 20 runs of
      offline-start), and an op queued during it could vanish unsent.
2b.8. **The web bootstrap reloads once a boot asset load fails.** Chromium
      aborts in-flight requests with `ERR_NETWORK_CHANGED` when the host's
      interfaces change; Chromium declines to make that configurable. One
      aborted `canvaskit.js` or `main.dart.js` left a blank page with no
      error. `app/web/flutter_bootstrap.js` reloads, at most twice per tab
      session (sessionStorage), and catches a failed `main.dart.js` with a
      capture-phase listener because the loader's callback mode ignores the
      script tag's error. On this box Docker bridges from other jobs' stacks
      trigger it; for users a Wi-Fi or VPN switch during load does.
2b.9. **The list resyncs when Realtime says it is live.** Realtime confirms
      the channel join before its Postgres listener runs and announces it
      later with a `system` event ("Subscribed to PostgreSQL", 2.5 s after
      the join on this stack). A change in between was never delivered, so
      an item added by voice or MCP right after the list opened stayed
      missing (seen in a full e2e run, and around the local stack's periodic
      "tenant terminated: rebalancing"). `watch()` now reports that event as
      online, which resyncs. `realtime_client` already turns a `system`
      error into `channelError`, which shows Offline.
2b.10. **The list resubscribes a channel the server closed.**
      `realtime_client` rejoins a channel after an error or timeout, but not
      after the server closes it (`phx_close`, sent when the local Realtime
      terminates its tenant for "rebalancing"). The list then showed Offline
      and missed changes until restart (review 0 reproduced it once under
      load; an e2e test that injects `phx_close` failed every time). The
      cubit now subscribes again while the channel is down (3 s, doubling to
      30 s, reset once live) and ignores callbacks from a replaced channel.
      A dropped socket already recovered through the library's reconnect;
      an e2e test keeps that covered too.
2b.11. **No generic `karte`.** It made "Schokokarte" Haushalt. Cards are
      listed explicitly (Geburtstagskarte, Glückwunschkarte, Geschenkkarte,
      Guthabenkarte), "Chipstüte" is sweets ahead of `tüte`, and "Spüli" is
      Haushalt. pgTAP rows guard food compounds next to the short terms
      (Kartoffelsalat, Fanta, Chipstüte, Schokokarte).
2b.12. **The 345-item sweep is a checked-in regression list.**
      `supabase/classifier/sweep.tsv` holds every swept item with its
      category; `sweep.sh` classifies them on the local stack and prints the
      rows that moved. CI's database job and `scripts/verify.sh` run it, so
      a dictionary change that moves one of them fails until the list is
      refreshed (`sweep.sh --print`) on purpose. Rerunning it showed
      Babytücher and "Feuchte Tücher" in Haushalt (via `tücher`) while
      Feuchttücher is Drogerie; both are now Drogerie.
      Guthabenkarte), "Chipstüte"
      is sweets ahead of `tüte`, and "Spüli" is Haushalt. pgTAP rows guard
      food compounds next to the short terms (Kartoffelsalat, Fanta,
      Chipstüte, Schokokarte).

## Job 8 (who added, new since you looked, usuals), 2026-10-23

8.1. **Usuals come from `item_events`, grouped by `item_name_key`.** Only
     `added` and `bought` count; `edited` (classifier moves), `restored` and
     `deleted` are not uses. A tick undone within 10 minutes (the snackbar's
     Rückgängig) is no purchase, and an item added and deleted without being
     bought (a typo) is no history. The last quantity comes from the newest
     `items` row of that key: bought rows are never purged, so no quantity
     column on `item_events` is needed.
8.2. **"Due" needs two purchases, not three.** Purchases are distinct
     Europe/Berlin days with a counted tick. With n >= 2 the usual gap is
     (last day - first day) / (n - 1), at least one day, and an item is due
     from 1x to 4x that gap after its last purchase. Peter and Lea buy most
     staples weekly, so two purchases a week apart already make a usual;
     with three, the row would stay empty for most of the first month. The
     4x cap drops what they stopped buying (seasonal fruit, a one-off
     recipe). Proven with a fixed clock in `supabase/tests/suggest_items.test.sql`.
8.3. **One year of history.** `suggest_items` reads the last 365 days. A
     usual nobody touched for a year is not a usual, and the cost stays flat:
     measured 0.34 s for 6000 events and 3000 rows (about two years of a
     household). The first version took 26.6 s because it keyed every items
     row inside correlated subqueries; names are now keyed once in
     materialized CTEs.
8.4. **The app fetches all usuals once and filters while typing on the
     device.** `fetchUsuals` asks for up to 200 with an empty prefix; the
     cubit matches the typed text the way the server matches `p_prefix`
     (folded name starts with it first, then a word starts with it). Chips
     therefore show at the first keystroke, offline too, with no request
     per keystroke, so there is no typing debounce. The cache refreshes with
     every resync and, debounced by 1.5 s, after the set of active names
     changes (a ticked item comes back as a suggestion). `p_prefix` stays on
     the RPC for MCP and other callers.
8.5. **Usuals live in the list snapshot, which becomes version 2.** The
     snapshot gains a per-version migrator chain (`ListSnapshot._upgrades`):
     a v1 snapshot from an older app loads with its pending ops, and new
     nullable fields such as `added_by` are read tolerantly without a
     version bump. A snapshot newer than the app (a downgrade, which TestFlight
     and the stores don't do) is still dropped.
8.6. **"Neu" is a server-time watermark plus a set of ids, per device.** The
     seen mark (`SeenMark`, DeviceCache key `seen.<user>.<household>`, outside
     the snapshot) holds `until`, the newest server `created_at` the user has
     seen past, and the ids seen after it. Comparing server times with server
     times keeps a wrong phone clock out of it. A first start sets `until`
     to the newest row already there, so nothing old lights up. A partner
     item turns plain after it has been at least half on screen for 3 s
     while the app shows (VisibilityDetector per tile; web counts an
     unfocused window as showing). Once every new item is seen, `until`
     moves past them. A seen item that is ticked and put back stays seen.
8.7. **Partner initial: first letter, two when another member shares it.**
     No badge on own items, on items whose author left the household, or
     before the server confirms an add. An add by someone not in the
     catalog's members reloads the catalog, so a new member's initial shows.
8.8. **Web: a tap next to the add field gives its focus back after the
     engine's deferred blur.** Tapping a semantics node (a chip, the send
     icon) blurs the field's DOM input while Flutter keeps the field
     focused, and the engine's `safeBlur` of the closed text connection runs
     on a zero-delay timer that beats a refocus in the next frames (traced
     with a JS stack hook). The tap unfocuses and refocuses 50 ms later.
     Mobile is untouched (the keyboard would flicker). The Enter path is
     unchanged; it never blurs.

## Job 4b (voice follow-ups), 2026-10-23

4b.1. **DeviceCache writes its own file on Linux** (`device_cache.json`, via
      `SharedPreferencesLinuxOptions`). supabase_flutter keeps the session
      through the legacy `SharedPreferences`, the cache uses
      `SharedPreferencesAsync`, and on Linux both plugins hold their own
      in-memory copy of `shared_preferences.json` and rewrite the whole file
      on each write, so a cache write dropped the session (relaunch came back
      signed out). Android, iOS and web ignore Linux options, so their stores
      and keys are unchanged. Not migrated: Linux is a debug target, and the
      household/list keys left in the old file are a cache that refills on
      the next online start.
4b.2. **Dictation is on-device only** (spec), superseding the job 4 note
      "on-device recognition is not forced". `speech_to_text` 7.5 with
      `onDevice: true` is strict on iOS (`requiresOnDeviceRecognition`) but on
      Android silently uses the network recognizer when on-device
      recognition is unavailable, and on iOS it answers a device without
      on-device German twice. So the app asks first, over its own channel
      `familygroceries/speech` (`MainActivity.kt`, `AppDelegate.swift`): iOS
      `SFSpeechRecognizer(de_DE).supportsOnDeviceRecognition`; Android API 31+
      `isOnDeviceRecognitionAvailable` and, on 33+, German among the installed
      on-device languages. Without it the mic explains in German that the
      offline German recognizer is missing and listens to nothing. An Android
      12 device without German reports `error_language_*` once listening
      starts; that gets the same message. Not 7.6.0-beta.4's
      `hasOnDeviceSupport`: a beta, and its Android answer ignores the
      language.
4b.3. **The mic shows on iOS and Android only.** Linux and web have no
      on-device recognizer; the Linux build used to show a button that could
      only fail.
4b.4. **CI compiles the native code** (`android-build`: debug APK on
      Ubuntu; `ios-build`: simulator debug build on macOS, free for public
      repositories). The app now has its own Kotlin and Swift, and nothing
      compiled them before.
4b.5. **Offline start: cache first, and list reads fail fast.** Review 1's
      offline-start failure was the cached list missing 10 s after an offline
      reload. Measured: the list appeared 7.6 s after the reload and
      "Offline:" 7.3 s later. postgrest-dart 2.9 retries every GET three
      times on network errors (1, 2 and 4 s), and `SupabaseClient.from()`
      ignores `postgrestOptions.retryEnabled` (supabase 2.16.5), so the
      session's household lookup and the list fetches each took about 7 s to
      fail. Now SessionCubit opens the device's household before it asks the
      server. The retries themselves are off through 02b's change (reads go
      through `client.rest` with `retryEnabled: false`, 2b's decisions); this
      branch had used `.retry(enabled: false)` per read and dropped it on
      rebase. ListCubit and SessionCubit retry on their own every 3 s.
      After: list 0.5 s, banner 0.6 s after an offline reload.
4b.6. **Review 1's three e2e failures had one trigger.** The run (09:27 to
      09:37) was frozen by mem-guard from 09:30:38 to 09:35:04 (SIGSTOP,
      `mem-guard.log`), and with 3 workers exactly three tests were in
      flight; each failed after 4.6 to 4.8 minutes on wall-clock timeouts.
      Fixes for what made them fragile: 4b.5 for offline-start, 3b.3 (own
      fake OIDC port) for social-sign-in, and one worker locally (3b.4).
4b.7. **merge-pr.sh ends the squashed message with Peter's trailer**
      (COMMON.md: every commit message ends with it) and re-squashes a head
      that doesn't. Before, the Claude trailer came last. The Claude line
      names the model that does the work (Claude Opus 5.5 here); COMMON.md
      requires only Peter's line, so a later job on another model updates
      `TRAILERS` in the script.
4b.8. **The ops DONE_SUMMARY.md is a copy of `docs/done/<job>.md`**
      (COORDINATION.md), byte for byte; the root `DONE_SUMMARY.md` only links
      it. Job 4's repo copy gained the "Merged as PR #10" line its ops copy
      already had.
4b.9. **The 5-run Playwright streak is evidenced on CI for the landing
      commit.** On 2026-10-24 the box froze every 5 to 30 minutes for 2 to
      53 minutes (host VM pauses; mem-guard gaps, Postgres walsender
      timeouts and 'virtual machine fork' at each wake), so five consecutive
      local runs of ~4 minutes didn't fit between freezes. Every local run
      without a freeze passed; CI ran the full suite six times in a row on
      the squashed commit, all green. Local runs log their longest
      mem-guard gap, so a red run can be told apart from a stall.

## Job 7b: loose ends of the Vercel hosting

7b.1. **`APP_URL` lives in `app/config/auth.json`.** The phone apps' invite
      links need the web origin. Dart no longer hardcodes it: `Environment.appUrl`
      reads only the `APP_URL` define and is empty without it (the dialog then
      shows only the code). Every production build already passes
      `--dart-define-from-file=config/auth.json` (both fastlane lanes and
      `scripts/vercel.sh`), so that file is the one source of truth; a custom
      domain is a one-line JSON change. `auth_config_test.dart` fails when a
      production build command drops the file (checked by removing it from a
      Fastfile lane and from `vercel.sh`) or `APP_URL` is not an https origin.
      Rejected: Vercel's `VERCEL_PROJECT_PRODUCTION_URL`, because the phone
      builds don't run on Vercel and the web app links to its own origin.
7b.2. **SPA rewrite by asset type, not by "has a dot".** The old rule
      `/((?!.*\.\w+$).*)` 404ed deep links like `/join/AB.CD`. The rewrite now
      skips only Flutter's asset folders (`assets/`, `canvaskit/`, `icons/`)
      and the file extensions a Flutter web build emits, so a missing asset is
      still a 404. `e2e/web-smoke.mjs` checks both sides. Limit: a path
      whose last segment ends in one of those extensions (`/join/ab.png`,
      `/lists/a.json`) is still a 404. No real link has that shape today:
      invite codes are eight characters from `A-Z` and `2-9` without a dot
      (`create_invite`), and `/join/:code` is the only route that takes a
      path parameter.
7b.3. **Deleted the unused repo secret `SUPABASE_DB_PASSWORD`.** Nothing read
      it since 7.8. The value stays in `~/groceries-ops/env`, so it can be
      set again with `gh secret set`. The remaining repo hits of the name are
      `docs/SPEC.md` (the ops spec, copied verbatim) and past job records in
      `docs/done/`.

## Job 9 (account deletion and data export), 2026-10-24

9.1. **What the stores require.** Researched 2026-10-24.
     - Apple, App Review Guideline 5.1.1(v) and "Offering account deletion
       in your app"
       (https://developer.apple.com/support/offering-account-deletion-in-your-app/).
       The app must let people start deletion inside the app, and the
       option must be easy to find, typically in account settings. It must
       delete the whole account record and the personal data, not just
       deactivate it. A confirmation step is allowed, but deletion must not
       be "unnecessarily difficult" and must not need a support contact.
       Data kept for legal reasons must be named. A manual or delayed
       process is fine if the user is told how long it takes. Apps with Sign
       in with Apple "should use the Sign in with Apple REST API to revoke
       user tokens".
     - Apple TN3194
       (https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).
       Revoke with `POST /auth/revoke`. When the app holds no token or
       code, it must still delete the account and point the user to the
       Apple ID settings.
     - Google Play, "Understanding Google Play's app account deletion
       requirements"
       (https://support.google.com/googleplay/android-developer/answer/13327111).
       The app needs an in-app deletion path and a web URL where users can
       request deletion without reinstalling the app. The page must name the
       app or developer as on the listing, give the steps, and say what is
       deleted, what is kept and for how long. The URL goes into the Data
       safety form.
     - GDPR Art. 20: an export in a structured, commonly used,
       machine-readable format. Neither store requires an export.
9.2. **An edge function, not an RPC.** Apple revocation needs HTTPS calls
     signed with the Sign in with Apple key, which Postgres cannot make. The
     database half is still one SQL function, `public.delete_account(uuid)`,
     granted to `service_role` only. The function deletes `auth.users` in
     the same transaction as the household cleanup, so deletion either
     completes or leaves nothing half-done. It does not use the Auth admin
     API afterwards. Every auth table cascades from `auth.users` (checked in
     `pg_constraint`), and the hosted `postgres` role has DELETE on it
     (checked read-only through the Management API).
9.3. **Fixed on main: no user who had added an item could be deleted.**
     `items_before_write` restored `added_by` on every UPDATE, including the
     `ON DELETE SET NULL` that deleting the user triggers, so the foreign key
     failed. The same failure hit the Supabase dashboard and the admin API.
     The trigger now passes such a set-null through, but only when the
     referenced user is really gone. It is security definer because it
     reads `auth.users`. The set-null also bumps no `updated_at`, and
     `items_log_event` no longer logs updates that change nothing visible.
     Clients still cannot rewrite `added_by`.
9.4. **The household after a deletion.** If other members remain, the
     household and its list stay. The leaver's items keep their place with
     `added_by`/`bought_by` null. Their history rows stay with `actor` null,
     in every household. Ownership passes to the earliest-joined remaining
     member. If the leaver was the last member, the household goes with all
     its rows. The household row is locked `FOR UPDATE`, so a concurrent
     `join_household` or a second member deleting at the same moment
     serializes behind it, and no orphaned household can be left behind.
9.5. **Only the app's own session may delete.** `authenticateSession` in
     `_shared/auth.ts` answers 403 `session_required` to personal access
     tokens and to OAuth client tokens (MCP), so a connected assistant cannot
     delete the account. Unlike `authenticate`, it needs no household. A
     retry whose first call succeeded but lost its response gets 200 again.
     The JWT still verifies, its user is gone, and a signature cannot be
     forged for a user who never existed.
9.6. **Sign in with Apple revocation.** On iOS the app asks Apple for a
     fresh authorization code after the typed confirmation. The function
     exchanges it with the bundle ID as client ID, checks that the code's
     `sub` is the account's Apple identity, and revokes the refresh token
     once the database delete has succeeded (9.12). Web and Android sign in with Apple through
     Supabase's redirect, and Supabase keeps no provider token (supabase/auth
     #1308), so they take TN3194's fallback. The account is deleted and the
     app shows the Apple ID settings path. Re-running an Apple redirect just
     to get a token was rejected: it adds a full-page round trip to every
     Apple deletion on the web for a case Apple documents as acceptable. Any
     Apple failure (no key configured, network, `invalid_grant`, wrong
     `sub`) never blocks deletion and ends in the same fallback. The key
     reaches the hosted function only as a secret Peter sets
     (`docs/NEEDS_PETER.md`, job 9). The box did not push the private key to
     production on its own.
9.7. **Confirmation by typing LÖSCHEN.** It is one deliberate step that
     Apple's "not unnecessarily difficult" allows, and it needs no email
     round trip. `LOESCHEN` also counts, for keyboards without umlauts.
     There is no re-authentication beyond Apple's sheet on iOS. The session
     already proves the user, and a password prompt does not exist for
     Google or Apple users.
9.8. **Online only.** Deletion is not an `ItemOp` and is never queued. When
     offline, the dialog refuses and says nothing was deleted. Queuing an
     irreversible action for later would surprise the user.
9.9. **Export as an RPC.** `public.export_my_data()` returns the caller's
     own data only, never other members' names, and never token hashes.
     OAuth client tokens get `session_required`, because PostgREST accepts
     them too. The app saves it as `einkauf-daten-YYYY-MM-DD.json`: a
     download on the web, the share sheet on the phones, the Downloads folder
     on the desktop debug build that the verify skill drives.
9.10. **Where the entry lives.** It sits in a "Konto" section of the
      settings screen, opened from its own "Konto" menu entry on the list,
      so it is one tap from the menu as Apple asks. It is also a button on
      the welcome screen, so a user who never joined a household can delete
      their account.
9.11. **The public deletion page is a static file.** It lives at
      `app/web/konto-loeschen.html`, not in a Flutter route. It loads
      without JavaScript, crawlers and Play reviewers can read it, and it
      bypasses `authRedirect`. Vercel's SPA rewrite skips paths with a file
      extension. It carries `noindex` and the ENTWURF banner until Peter
      approves it.
9.12. **Review 0: a dropped call is retried once; Apple comes after the
      delete.** CI run 40121325467 failed the shared deletion with an
      empty 503 from the local edge runtime ("connection aborted", a cold
      `oneshot` worker under two parallel first calls). Job 12 could not
      reproduce it with 44 concurrent calls. The hosted gateway also answers
      502, 503, 504 or 546 when a worker fails to boot. These are transient
      states at the network boundary, and the endpoint is idempotent, so
      `SupabaseAccountRepository.delete` retries once after one second when
      the error lacks the handler's JSON `error`. Errors the handler
      answered are not retried. The function now reads the Apple subject
      first, deletes, and only then calls Apple. A failed delete therefore
      never spends the single-use code, and a retry can still revoke. A
      retry that finds the account gone answers `apple: "manual"`: the
      first call may have died between the delete and Apple, and the hint
      is the safe answer.

## Job 12 (structural lints and schema guards), 2026-10-24

12.1. **ast-grep, not an analyzer plugin.** Every rule is syntactic and runs
      in `scripts/lint.sh`. An analyzer plugin would add an isolate to every
      agent's analysis server on a 16 GB box shared by several jobs. The cost
      is that `no-hardcoded-ui-text` cannot see types (12.3).
12.2. **Only `DeviceCache` opens a shared-preferences store, not `main.dart`.**
      The Linux sign-out came from `DeviceCache(SharedPreferencesAsync())` in
      `main.dart` (c4ed2e4^), so allowing `main.dart` would have let the bug
      through. A second rule, `device-cache-own-file`, requires the store
      inside `DeviceCache` to carry `SharedPreferencesLinuxOptions` with a
      file other than `shared_preferences`. Tests are not checked: they set
      up fakes.
12.3. **What counts as hard-coded UI text.** A string literal in `app/lib`
      (not `l10n/`) whose own text has a letter and is not a path. It counts
      when it is the text of `Text` or `SelectableText`, or the value of a
      named argument that Flutter uses for text. The rule looks through a
      ternary's branches, `??`, `+`, parentheses and switch-expression arms
      to that position, so `Text(done ? 'Erledigt' : 'Offen')` and
      `Text(n + ' Stück')` fail (review 0). It also follows `!`, list and
      set elements, map values, and the receiver of a method call, property
      or index: `Text('Hallo'.toUpperCase())`, `Text(['Eins', 'Zwei'][i])`
      and `Text(<String>['Eins'].join(', '))` fail (review 1). Index and map
      keys, conditions, switch patterns, and arguments of other calls
      (`DateFormat('dd.MM.')`, `json['name']`) are data and pass. Collection
      `if` and `for` elements are walked like list elements, and a name
      declared in the same file is followed to its value when the name
      reaches a text position: a constant, final, local or field, including
      list and map constants (`const _labels = ['Eins']; Text(_labels[0])`),
      a later assignment (`msg = 'Gespeichert'`), a parameter's default
      value, an enum constant's arguments when one of the enum's fields is
      shown (`fruit('Obst')` with `Text(c.label)`), and the result of a
      getter, function or method (`String get _title => 'Titel'`, `String
      _nr(int n) => 'Nr. $n'`, `return 'Ja';`). The literal is reported
      where it is declared (job 12b). Names are matched, not resolved: a
      `title` getter in one class counts when another object's `.title` is
      shown in the same file, and an enum constant's other literal
      arguments (a JSON key next to the label) count too; give those an
      ignore with the reason or move the label to l10n. `toString`
      overrides are skipped, since `Text(n.toString())` shows `n`. Four cases stay out of
      reach for a syntactic rule: a value that goes into another call's
      argument and comes back as its result (a closure in `.map((e) => 'Nr.
      $e')`, a custom widget's positional parameter that it shows with
      `Text`), a declaration whose value is another declaration's name
      (`const _b = _a;`, ast-grep binds one name per match), and a constant
      imported from another file. They would need the analyzer's types and
      data flow (12.1). The named-argument list adds the date, time, about
      and search dialogs' texts (`confirmText`, `cancelText`, `helpText`,
      `fieldLabelText`, `searchFieldLabel`, ...) to emotely's
      `avoid_hardcoded_ui_text` list, so a custom widget's named `title:`
      or `label:` argument is caught. A non-widget class with a parameter
      named `message` or `title` is reported too; pass it a localized value.
      Main had no findings.
12.4. **`dispose-after-dialog` looks at the whole function body.** It reports
      a local `TextEditingController`, `FocusNode`, `ScrollController` or
      `SearchController` that is disposed in a function that also awaits a
      route: `show*Dialog`, `show*BottomSheet`, `showCupertinoModalPopup`,
      the date, date-range and time pickers, `showMenu`, `showSearch`,
      `showAboutDialog`, `showLicensePage`, or a Navigator or go_router
      `push*`. A `finally` block counts too, and so does a dispose in the
      route's `.then` or `.whenComplete` callback without an await (job
      12b). A picker builds its own controllers, but its `builder` can wrap
      the caller's field, so pickers are in. The fix is a route widget whose
      State owns the controller. The rule does not check order inside the
      function, so a dispose written before the await is reported too. It
      does not follow a route that a helper function opens and the caller
      awaits (that needs a call graph), or a route's Future stored in a
      variable and awaited later.
12.5. **squawk rules as an allow-list in `schema_check.ts`.** squawk has no
      "only these rules" switch, so the check keeps the backward-compatibility
      rules from its JSON report (`COMPAT_RULES`) plus parse errors. Those
      rules ban dropping or renaming a column or table, NOT NULL without a
      default, setting NOT NULL, dropping NOT NULL, type changes, and
      dropping a function, view or database. Lock, timeout and style rules
      stay off. squawk reads only migrations that are not on main. Main's
      migrations are frozen anyway.
12.6. **Every public table enables RLS, with or without `household_id`.**
      PostgREST serves any public table to the API, so a table without RLS is
      readable with the publishable key. Main already complies.
12.7. **"Covered in a pgTAP test" means a test that sets up two
      households.** The table must appear as `public.<table>` in a
      `supabase/tests/*.test.sql` file that calls `create_household(` at
      least twice. A mention in a single-household test does not count.
      `personal_access_tokens` meets this in its own test file. A table
      created with `(like public.<table> ...)` inherits that table's
      `household_id` and needs its own RLS, policy and test (review 0).
      Quoting does not matter: `"public"."items"`, `public."items"` and
      `public.items` are the same table (job 12b).
12.8. **The base is `origin/main`.** `lint.sh` fetches it at depth 1 when the
      ref is missing, as it is in a CI pull-request checkout. A new migration
      must sort after main's newest, and main's files must match byte for
      byte.
12.9. **CI's versions are the only versions.** `ci.yml` pins
      `AST_GREP_VERSION` and `SQUAWK_VERSION`. `bootstrap.sh` installs
      exactly those versions, and `lint.sh` refuses to run with others,
      because rule snapshots and squawk findings change between releases.
12.10. **Exceptions say why.** The forms are
       `// ast-grep-ignore: <rule> -- <reason>` and
       `-- squawk-ignore <rule> -- <reason>`, where the reason has at least
       three words (`ignore-needs-reason`, `checkIgnores`). Both tools accept
       the ` -- ` suffix. There were no violations on main, so the PR adds
       no ignores and fixes no code.
12.11. **`fromEnvironment` and `go('/login')` had no history.** No commit
       on any branch ever broke these two conventions, so their rule tests
       use probes instead of historical code.

## Job 12b (lint and schema-guard follow-ups), 2026-10-25

12b.1. **`auth-navigation-only-in-router` reports the route names, not only
       navigation calls.** Nothing in `app/lib` outside `router.dart` has a
       reason to name `/login` or `/welcome`, so any such path literal,
       `loginPath`/`welcomePath`, and `'login'`/`'welcome'` as a `*Named`
       route name fail. A constant (`const _p = '/login'; go(_p)`) and
       `Uri(path: '/welcome')` are then caught without data flow. A path
       built at run time (`'/' + name`) is not.
12b.2. **`schema_check.ts` reads names with one parser.** `qualifiedName`
       splits a name on the dot and unquotes each part, and `statements()`
       keeps the case inside double quotes, so `create table
       "public"."items2"` is `public.items2` and `public."Mixed"` keeps its
       case in the fix hint. Before, `"public"."items2"` was read as the
       table `public` (review 2). The same scanner now honours `E'...'`
       backslash escapes and nested block comments, both of which used to
       swallow the DDL after them, and test SQL is read without its
       comments. `alter policy` (new `using`, rename), `rename column` to
       or from `household_id` and `set schema` are followed.
12b.3. **A table finding names the migration that last changed the table.**
       Renames, `alter table` and policy changes move it. The earlier file
       is often on main and frozen, so the fix goes after the last change:
       a rename probe used to be reported against the foundation migration.
12b.4. **`lint.sh` runs the schema check before its unit tests.** A probe
       migration also fails the unit test over the repository's own
       migrations, whose assertion diff hid the check's message.
12b.5. **Port blocks stay where they are; the kernel reserves them.** Linux
       picks outgoing connections' source ports from 32768-60999, and every
       job's block (543xx-561xx) and CI's 543xx lie inside it. A container
       that binds a port an outgoing connection holds fails with `bind:
       address already in use`; review 2 hit it twice on 55522 during `db
       reset`. On the box, 9 of 3000 loopback connections drew a source port
       in 55500-55599, and 0 of 3000 after `sysctl
       net.ipv4.ip_local_reserved_ports=55500-55599`; an explicit bind on
       55522 still worked. `reserve_port_block` (`scripts/lib.sh`) reserves
       the checkout's `<prefix>00-99` before `supabase start` and `db
       reset`, locally and on CI runners. Moving the blocks below 32768
       would also work but renumbers every job, and the verify skill's own
       stacks (`fg`, `~/.cache/fg/<prefix>`) don't go through `lib.sh`, so
       the box itself should reserve 54300-56199 at boot (BOARD, job 12b).
12b.6. **`typeInto` waits for Flutter's frame, not for more time.** On web,
       a DOM focus on a semantics text field only asks the app to focus it;
       the engine attaches its editor to the `<input>` with the next
       frame's semantics update (`semantics/text_field.dart`, `update()` ->
       `activate`). Text inserted before that frame is in the DOM but not in
       the app, and the frame writes the app's value back. The old helper
       checked the DOM right after inserting, so it passed. Then, under
       load, `auth.spec.ts` sent the old password (full run 1, 10:36, no
       freeze). With frames held back 1.5 s, the old helper left the field
       empty and the new one kept the text (probe in
       `docs/screenshots/12b-lints-followups/typeinto-frame-probe.*`).
       `typeInto` now waits two `requestAnimationFrame`s after focus and
       again before its value check. Review 2's partner-news failure was
       different: a 7-minute VM freeze inside a click (mem-guard gap
       01:42:58-01:50:18), void under the board's ruling.

## Job 11: one CI run per merge, one gate definition, measured CI speedups

11.1. **One script per gate, called by CI and `verify.sh`.** Each `ci.yml` job
      installs tools and runs `scripts/gates/<job>.sh`; `verify.sh` runs the
      same scripts in a fixed order (`--only <gate>` for some).
      `scripts/check-gates.sh` (lint gate) fails when a gate lacks its job,
      its `ci-ok` need, its `verify.sh` entry or its executable bit, or when
      `ci.yml`/`verify.sh` run a check command themselves. That turns the old
      drift into a lint error: `verify.sh` had no production web build, no
      fastlane parse and no `--fatal-infos`. The last one was cosmetic:
      `flutter analyze` defaults to `--fatal-infos` on Flutter 3.47, checked
      with an info-level probe (`omit_local_variable_types: info`). The
      gate states the flag anyway, so a default change can't loosen it.
      `android` and `ios` are CI-only in `verify.sh` (macOS, Gradle RAM).
11.2. **`scripts/push-pr.sh` pushes the commit main takes.** It rebases onto
      `origin/main`, squashes to `<PR title> (#n)` with the noreply author and
      trailers, and pushes with `--force-with-lease`; it refuses `main` and
      uncommitted changes. `merge-pr.sh` then finds a compliant head and only
      checks `ci-ok`, so a merge costs one CI run instead of two. The squash
      body keeps every commit subject, so fix rounds stay readable. Shared
      code (author, trailers, the compliance check, the squash) is in
      `scripts/lib.sh`. `merge-pr.sh` keeps its old behavior for PRs pushed
      the old way and gains `--wait` and `--dry-run`. Not removable: if
      `main` moves after the push, one more rebase, push and CI run is
      needed; merge-pr.sh says so.
11.3. **push-pr.sh carries skip-worktree edits across the rebase.** Every
      worktree keeps its port block in `supabase/config.toml` as a
      skip-worktree edit, and git refuses to rebase over it once `main`
      changes that file (it did: job 9's `[functions.account]`). The rebase
      saves those edits as a patch, restores the files, rebases, reapplies
      the patch and marks the files skip-worktree again.
11.4. **A pre-push hook warns, never blocks.** `.githooks/pre-push` warns
      when a PR branch goes up with more than one commit over `origin/main`.
      The first push before `gh pr create` is legitimately several commits.
      `core.hooksPath=.githooks` is in the shared repository config and
      resolves per worktree; shown by the warning from a worktree in /tmp.
11.5. **Box-wide e2e lock.** The e2e gate holds `flock /tmp/fg-e2e.lock` from
      stack start through Playwright and writes its checkout and pid into
      the file; a second run prints that and waits. Rejected `pgrep
      playwright`: it matches the caller's own command line (it matched an
      agent's shell during this job). Playwright arguments pass through
      (`verify.sh --only e2e -- tests/x.spec.ts`), so subset runs take the
      lock too.
11.6. **A database started alone is not a running stack.** `supabase status`
      exits 0 when only the database runs, and `supabase start` then reports
      "already running" and starts nothing else. `supabase_up` checks for an
      API URL and stops a database-only stack before starting the full one;
      the db gate starts the full stack when nothing runs, so CI and a local
      run take the same path.
11.7. **Path filters (`scripts/ci-changes.sh`).** Docs-only changes (`docs/`,
      Markdown outside `.cursor/`/`.claude/`) run only gitleaks and lint;
      `android`/`ios` need `app/ios/`, `app/android/` or `app/pubspec.*`;
      `fastlane` needs `app/fastlane/` or the Gemfile. The native builds
      compile Swift, Kotlin and the pubspec's plugin registrant; Dart that
      passes `flutter analyze`/`flutter test` and both web builds also
      compiles to the iOS and Android debug kernels. With e2e sharded, ios
      (median 4:48 running) was the floor of every app PR, and most app
      PRs touch only `app/lib/`. A change to `ci.yml`, the filter, `lib.sh` or a gate runs
      everything, and so do pushes to `main` and manual runs. Not filtered:
      db, functions, fg-cli, flutter and web-prod. They are off the critical
      path, so a filter would save runner minutes only, at the risk of a
      wrongly skipped gate.
11.8. **Kept the production web build in CI** (`web-prod`, ~1:20, parallel
      and off the critical path). Vercel builds every push (job 07), but its
      result is not in `ci-ok`.
11.9. **Dependabot, not Renovate.** Grouped weekly PRs for GitHub Actions,
      pub and npm, labelled `dependencies` and `agent-ready`; majors in their
      own group. Renovate would also bump the versions pinned in `ci.yml`
      env, but needs its app installed on Peter's account.
11.10. **Speedups kept, each with its measurement** (`scripts/ci-timings.sh`,
       numbers in `docs/CI.md`):
       - Supabase images from ghcr.io (`SUPABASE_INTERNAL_IMAGE_REGISTRY`).
         Every baseline e2e log has 21 "toomanyrequests" lines from
         public.ecr.aws and ~14 s of retries before the CLI fell back to
         ghcr.io; the new runs have none.
       - The stack starts in the background before the tool installs.
         Before, `supabase start` (1:04) ran after them; now the gate waits
         21-32 s for it.
       - Gradle and the NDK/CMake cached: android 4:38 running → 2:38.
         Without it android would be the limiter once e2e is sharded.
       - e2e in two shards: Playwright was the longest step (2:46-3:48 of
         e2e's ~5:30 running). Each shard ends at ~4:10, so ios (~4:05
         running) and e2e now finish together.
       - Playwright's apt dependencies only when Chromium can't launch:
         `--with-deps` once took 6:37 (25.9 MB at 70 kB/s from the runner's
         Ubuntu mirror); the runner image already has the libraries headless
         Chromium needs, and no test compares screenshots.
11.11. **Measured and dropped:**
       - Building the web app while the stack starts (URL from config.toml,
         the CLI's fixed local publishable key, rebuild on mismatch). It cut
         gate start → Playwright start from 60 s to 51 s (medians, 5 runs
         each). 9 s is below the noise and not worth the prediction code.
       - The Playwright browser cache: the download takes ~6 s, the restore
         ~4 s.
       - `supabase start -x`: config.toml already disables studio, storage,
         imgproxy, analytics and the pooler; the CI log shows exactly the 7
         images e2e uses being pulled.
       - A Deno cache: the functions and fg-cli jobs run 0:12 and are never
         on the critical path.
       - Docker image caching: with the background start, image pulls are
         off the critical path.
11.12. **Runner speed is the noise to read through.** Playwright took either
       ~2.9 m or ~3.8 m per full run, and in a slow run nearly every test is
       1.3-1.5× slower, from the first spec to the last. That is runner
       hardware, not this repo. Medians over 5 runs per variant, with the
       range shown; a change is judged on the segment it touches when the
       medians move less than that noise.
11.13. **Review 0 fixes.**
       - Every job in every workflow sets `timeout-minutes`: release secrets 5,
         release builds 60, Supabase deploy 15. `check-gates.sh` now fails on
         a job without one (a reusable-workflow job is exempt), so a new job
         can't miss it.
       - `merge-pr.sh --wait` gives up after `MERGE_WAIT_MINUTES` (default 30)
         and exits 1, so a `ci-ok` that never reports can't hold the merge
         lock forever.
       - `push-pr.sh` and `merge-pr.sh` refuse a branch with no commits on top
         of main. They used to squash it into an empty commit and push it.
       - The squash keeps other people's `Co-authored-by` lines: it moves them
         into the trailer block once each, case-insensitively. Ours come last,
         so Peter's trailer still ends the message.
       - The e2e gate clears its holder record when it exits. The wait message
         says that a plain `flock` user records nothing.
       - Kept: the `Co-Authored-By: Claude` trailer. This box's commit
         attribution rules ask for it on every commit an agent makes, and
         Peter's trailer stays last.

## Job 13 (keepalive, deploy smoke test, function rollback), 2026-10-24

13.1. **Supabase pauses free projects after 7 days of low database activity.**
      Researched 2026-10-24 in "Project Pausing"
      (https://supabase.com/docs/guides/platform/free-project-pausing). A
      Free plan project is paused when it gets too little "user database
      activity" over a 7-day window. The docs give no exact threshold: a few
      database requests a day usually keep a project active. Supabase emails
      a warning about a week before it pauses, and a paused project can be
      restored for up to 1 year. Only a paid plan turns pausing off, so that
      is out (free tier only). A connection that runs no query may not count
      (a forum answer, not the docs), so the keepalive runs a real query.
13.2. **GitHub disables scheduled workflows after 60 days.** "Events that
      trigger workflows", section `schedule`
      (https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows):
      "In a public repository, scheduled workflows are automatically
      disabled when no repository activity has occurred in 60 days." The
      docs don't define activity. Re-enabling uses
      `PUT /repos/{owner}/{repo}/actions/workflows/{id}/enable`
      ("Disabling and enabling a workflow",
      https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/disabling-and-enabling-a-workflow).
      What is guaranteed (review 1): every push to `main` re-enables the
      keepalive (13.11), and a push is repository activity, so the schedule
      is never off for longer than the time until the next merge. With no
      pushes at all, the stated recovery is the manual
      `gh workflow enable keepalive.yml` in docs/DEPLOY.md, and Supabase's
      own warning email reaches Peter as the owner before a pause. Best
      effort only: the keepalive also enables itself on every run
      (`permissions: actions: write`). Community tools
      (gh-workflow-immortality) say that resets the 60-day clock; GitHub
      doesn't document it, and it can't be tested short of 60 quiet days.
      Dummy commits were rejected: they pollute `main`, which takes one
      commit per PR, and the best-known action that made them,
      gautamkrishnar/keepalive-workflow, is now disabled by GitHub Staff
      for a terms-of-service violation.
13.3. **Job 06's nightly run doesn't keep the project awake.** Job 06 is
      not started (status `waiting`) and has no workflow on `main`. Its brief
      lets it choose a test household on the remote project or another
      option, so it may never hit production. The keepalive is one request
      a day; if 06 later reads the remote project nightly, the keepalive can
      be dropped then.
13.4. **`health` became a readiness check.** It now runs
      `select exists (select from public.classifier_terms)`: one indexed
      read of the shared seed dictionary, no user data, over the functions'
      existing `SUPABASE_DB_URL` pool. It answers 503 with
      `{"ok": false, "database": false}` when Postgres doesn't answer, so
      the smoke test also proves the database is reachable after a deploy.
      The read has a 5-second deadline (review 0): without it, a dead
      database took the driver's 30-second connect timeout, and the callers
      (curl, 20 to 30 seconds) saw a timeout instead of the 503.
      Calling it through the function (instead of PostgREST with the
      publishable key) keeps the keepalive free of keys and also exercises
      the edge runtime.
13.5. **The MCP 401 lost its `WWW-Authenticate` header in production.**
      Found by the new smoke test: for a bad or expired token, the hosted
      `mcp` function answered 401 with no `WWW-Authenticate`, so an MCP client
      couldn't find the Protected Resource Metadata to sign in again. The
      header's `error_description` carried the German message
      ("Token ungültig: ..."). RFC 6750 section 3 limits it to printable
      ASCII, and the hosted gateway drops a header with other bytes (the
      missing-token 401, which has no description, kept its header). The
      challenge now transliterates umlauts and drops anything outside the
      RFC 6750 set; the JSON body keeps the German text.
13.6. **Rollback deploys functions only, from main, with the commit's own
      smoke test.** The `ref` input must name a commit on `main` (reviewed
      code only), and that commit must contain `scripts/smoke-remote.sh`.
      Older commits have the health check without Postgres and the MCP
      header bug, so they would fail the smoke test anyway. The run uses
      that commit's own smoke script, which tests the functions against the
      contract they shipped with. Migrations are skipped: the database is
      forward-only (docs/DEPLOY.md, "fix forward").
13.7. **Deploys only from `main`.** A manual dispatch on another branch used
      to deploy that branch's functions and migrations to production. The
      credentials step now refuses any ref other than `refs/heads/main`.
13.8. **A failed keepalive opens an issue.** GitHub sends a scheduled run's
      failure mail only to whoever last edited its cron line
      ("Events that trigger workflows", `schedule`, "actor"), which is the
      bot account. The failure step opens one issue titled "Keepalive
      failed", or comments on the open one. The body names the step that
      failed. The next green run closes it. It matches the title through
      the plain issue list: in a test, `gh issue list --search` missed an
      issue created seconds earlier and opened a duplicate.
13.9. **actionlint comes from job 11's lint gate.** This job first added its
      own actionlint step to `ci.yml` and `verify.sh`. Job 11 landed first
      with actionlint in `scripts/gates/lint.sh` (same pinned 1.7.12), so
      the rebase dropped this job's copy. A broken keepalive file still
      fails CI.
13.10. **Backups stay a proposal.** The free plan has no backups, and runners
       reach Postgres only through the session pooler. Details and the plan
       are in docs/NEEDS_PETER.md, "Job 13: database backups".
13.11. **Every push to `main` re-enables the keepalive** (review 0). GitHub
       doesn't turn a schedule back on that it disabled for inactivity, and
       a disabled schedule never runs, so it can't report itself. A
       `keepalive-schedule` job in `ci.yml` runs `gh workflow enable` on
       push events. It is not part of `ci-ok`.

## Job 13b (nightly encrypted database backups), 2026-10-25

Peter approved the proposal in docs/NEEDS_PETER.md ("Job 13: database
backups") with three changes: nightly instead of weekly, 90 days of
retention, `auth.users` and `auth.identities` included. Runbook:
docs/BACKUP.md.

13b.1. **`pg_dump --data-only --table='public.*' --table=auth.users
       --table=auth.identities --strict-names --quote-all-identifiers`.**
       `--schema` has no effect once any `--table` is given (pg_dump docs,
       "-n pattern"), so `--schema=public --table=auth.users` would back up
       only the two auth tables. The drill proves it: with that variant it
       fails. `public.*` also selects the sequences, so the dump sets
       `item_events_id_seq` and new history rows continue after the
       restored ids (the drill inserts one). `--strict-names` fails the
       dump if a pattern stops matching (a renamed auth table) instead of
       silently leaving it out. `--quote-all-identifiers` keeps the dump
       loadable if a later Postgres reserves a word we use as a name.
       `--no-owner` and `--no-privileges` are left out: a data-only dump
       has no ownership or grant statements.
13b.2. **The schema comes from the migrations, not the dump.** Supabase's
       own schemas (auth, storage, realtime) belong to the platform, and a
       full schema dump would recreate objects the target project already
       has. Our schema is fully described by `supabase/migrations/`.
13b.3. **Repository secret, not an environment secret.** The proposal
       suggested a `backup` environment. The Engineering Lead set the
       repository secret `SUPABASE_DB_PASSWORD` instead. Only
       `backup.yml` reads it, `ci.yml` never does, and pull requests from
       forks get no secrets. An environment would add nothing without
       required reviewers, which a nightly unattended job can't have.
       The workflow fails, and opens the issue, when the secret is
       missing or empty: a silent skip would look like a backup.
13b.4. **Restore in replica mode, replacing all data.**
       `scripts/backup/restore.sh` runs `SET session_replication_role =
       replica` in the same psql session as the load, inside one
       `--single-transaction -v ON_ERROR_STOP=1` run, as Supabase documents
       for restores (https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).
       Without it, `items_before_write` sets `bought_by` from `auth.uid()`
       and `item_events` gains rows: the drill run without replica mode
       failed on a duplicate `item_events` key. Before the load it
       truncates `auth.users`, `auth.identities` and every `public` table
       with `CASCADE`. That handles the rows migrations seed
       (`classifier_terms`, the only top-level seed insert; the backup holds
       the full dictionary) and makes the same command restore into the
       live project after data loss, not only into an empty one. CASCADE
       also empties the auth tables that point at users (sessions, refresh
       tokens, MFA, one-time tokens, OAuth consents): their rows would refer
       to the users being replaced. psql names each one.
13b.5. **Recipient in `supabase/backup/recipient.txt`.** The brief's path;
       it sits next to the other Supabase operations files. The private key
       never touches the repo, CI or a secret. `dump.sh` checks the file
       holds one `age1...` recipient.
13b.6. **A failed dump leaves no file.** age writes a valid header before
       it has seen any input, so a pg_dump that dies mid-stream would leave a
       file that passes the header check. `dump.sh` runs with `pipefail` and
       deletes the output on any error, then checks the header and a
       16 KiB minimum (the shared classifier dictionary alone is larger).
13b.7. **The restore drill is part of the `db` gate.** docs/CI.md: a check
       goes into the gate it belongs to. The db gate already starts a stack
       and resets it, so the drill costs about a minute and no extra runner.
       It creates users through GoTrue's admin API (real `auth.users` and
       `auth.identities` rows), writes fixtures through the app's RPCs and
       triggers (`scripts/backup/fixtures.sql`), requires rows in every
       backed-up table, dumps with a throwaway key from `age-keygen`, resets
       to the migrations, restores, and compares row count and an md5 of the
       ordered rows per table. Then the restored users sign in with their
       passwords and a new write runs the triggers again. Job 18's fixtures
       aren't on `main` yet; when they land, the drill can seed from them.
       A new table without fixture rows fails the drill, so every new table
       is proven to round-trip.
13b.8. **gitleaks already catches age private keys.** Its default rule
       `age-secret-key` flagged a throwaway `AGE-SECRET-KEY-1...` committed
       to a scratch repository, so no rule was added. The drill keeps its
       key in a `mktemp -d` directory outside the repository and deletes it
       on exit.
13b.9. **pg_dump 17 from PGDG on runners.** Ubuntu 24.04 ships
       postgresql-client-16, and pg_dump refuses a newer server.
       `scripts/backup/install-tools.sh` adds the PGDG repository only when
       the distribution lacks `postgresql-client-17` (Debian 13, the build
       box, has it) and fails unless `pg_dump --version` is 17. The first
       probe run failed that check: the runner image already has PGDG and
       a PostgreSQL 16 server, and Ubuntu's `/usr/bin/pg_dump` wrapper
       follows the installed server, not the newest client. So the scripts
       put `/usr/lib/postgresql/17/bin` first on `PATH`.
13b.10. **Every push to `main` re-enables the backup schedule**, in the
        same `keepalive-schedule` CI job as the keepalive (13.11).

## Job 11b: job 11's loose ends, 2026-10-25

11b.1. **The landed body is the PR description.** `squash_commit` used to
       join every working commit's message into the commit on `main`, so
       lines like `done: PR number` and whole changelogs landed. Now the
       body is the PR description from `gh pr view --json body`. GitHub's
       CRLF line ends are stripped. The description is the text a
       reviewer reads, and anyone can edit it with `gh pr edit`. Commit
       messages still count for one thing: their `Co-authored-by` lines
       join the trailer block.
11b.2. **The model trailer comes from `MODEL_CO_AUTHOR`, or it is left
       out.** The hard-coded `Claude Opus 5.5` line credited that model for
       every PR, whichever model built it. An agent's own commits carry its
       co-author line, and that line is kept. So the env var is needed only
       when the commits lack the line. A value that is not `Name <email>`
       stops the push rather than landing a broken trailer.
11b.3. **`MERGE_WAIT_MINUTES` takes whole minutes.** It is checked before
       merge-pr.sh calls gh, and anything else exits 2 with a message.
       `08` is read as decimal (`10#`), not as an invalid octal number.
       Sub-minute waits help nobody: CI runs take minutes.

## Job 20 (rename to Hummlist), 2026-10-25

Peter approved the name "Hummlist" and the ID `com.hummlist.app` on
2026-10-25. This supersedes job 1, decision 1.

1. **One ID everywhere.** Bundle ID, Android `applicationId` and
   `namespace`, the Kotlin package (`MainActivity.kt` moved to
   `kotlin/com/hummlist/app/`), the Linux `APPLICATION_ID` and the fastlane
   `APP_ID`/Appfile/Matchfile are `com.hummlist.app`; RunnerTests is
   `com.hummlist.app.RunnerTests`. The Dart package `family_groceries`, the
   MethodChannel `familygroceries/speech`, the Linux binary name, the repo,
   the Vercel project and its URL, and the export format id
   `family-groceries-export` stay: none of them is visible as the app's
   name, and renaming them would break imports, old exports or links.
2. **Both deep links stay allowed.** The app now redirects to
   `com.hummlist.app://login-callback`. TestFlight 0.1.0 (1001) and any
   installed build still use `com.petertrost.familygroceries://login-callback`,
   so `supabase/config.toml`, `supabase/deploy/auth_urls.ts` and
   `scripts/configure-social-auth.mjs` keep both. Dropping the old one would
   break magic links and Apple-on-Android for those builds.
3. **Apple client IDs as one comma list.** `configure-social-auth.mjs` writes
   `external_apple_client_id` = Services ID, old bundle ID, new bundle ID and
   an empty `external_apple_additional_client_ids`, exactly the hosted state
   the Lead set. Before, it wrote the bundle ID into the additional list, so a
   rerun would have dropped `com.hummlist.app` and broken native Apple
   sign-in on the new builds. Checked with `--dry-run` against a stubbed
   Management API returning the live values (no call to the real API).
4. **Account deletion revokes for both bundle IDs.** An Apple authorization
   code only exchanges with the client ID it was issued to, and the request
   does not say which build sent it. `supabase/functions/account/apple.ts`
   tries `com.hummlist.app`, then `com.petertrost.familygroceries`, moving on
   on `invalid_grant` (another app's code) or `invalid_client` (the key does
   not cover that ID yet), and revokes with the ID that worked. The
   `APPLE_BUNDLE_ID` secret is no longer read: a single configurable ID
   would always be wrong for one of the two builds.
5. **What carries the name "Hummlist".** Home-screen and store names
   (`CFBundleDisplayName`, `CFBundleName`, `android:label`), the iOS
   microphone and speech prompts, the web `<title>`, Apple web-app title and
   manifest `name`/`short_name`, `konto-loeschen.html`, `appTitle` and
   `accountDeletedApple`, the voice errors ("in der Hummlist-App"), the MCP
   server (`name: hummlist`, title and `resource_name` "Hummlist", the
   instructions start with "Hummlist:"), the Linux window title, README and
   the user docs. "Einkauf" stays where it is the ordinary word
   (Einkaufsliste, "Gemeinsame Einkaufsliste", the Shortcut name "Einkauf
   notieren"), and historical records (done summaries, the old App Store
   record "Einkauf Familie") keep the old name. The name is always the full
   word "Hummlist".
6. **No new UI for the name.** The sign-in screen keeps its title
   "Anmelden"; the name shows in the browser tab, the installed web app and
   the phones' home screens. Putting it on the sign-in screen is a design
   change, not part of the rename.
7. **Production URL `https://app.hummlist.com`.** Peter bought
   `hummlist.com`; the Lead attached `app.hummlist.com` on Vercel and made it
   the hosted Site URL (2026-10-25). `APP_URL` in `app/config/auth.json`
   (the phone apps' invite links), the link on `konto-loeschen.html` and the
   docs now name it. The old `family-groceries-pied.vercel.app` keeps
   serving and stays in the redirect allow list, so links already sent and
   bookmarked keep working. The Vercel project keeps its name.

## Job 23 (weekly release pipeline), 2026-10-27

1. **Why no TestFlight build was installable.** App Store Connect (read-only
   API, 2026-10-27) shows every unexpired build of the team expired within
   two seconds on 2026-10-26, 13:14:02 to 13:14:03 UTC: Hummlist 1002
   (uploaded 2026-10-25 20:20 UTC), build 1001 of the old app record
   (`6826907810`) and all 65 builds of another app of the team uploaded since
   2026-09-13, weeks before their 90 days were up; a fourth app's builds had
   expired normally after 90 days. No Beta App Review submission exists, no
   newer build of either Hummlist version replaced 1002, the certificate and
   the profile are `ACTIVE`, the API key works, and the team's live App Store
   app is still `READY_FOR_SALE` (so, as far as the API shows, the membership
   did not lapse). Manual expiry is ruled out: nobody expires 67 builds of
   three apps in two seconds. Apple's developer forums (thread 813703) report
   the same team-wide mass expiry for other teams in January, July and August
   2026; Apple's TestFlight team acknowledged it and gave no cause.
   Conclusion: an Apple-side event, not this pipeline. The weekly run
   counters it: when no TestFlight build is installable, an unchanged `main`
   ships again; a build that comes out of processing already expired fails
   the run and points to `RELEASE.md` (Apple Developer Support case, Peter's
   step in `NEEDS_PETER.md`, Job 23).
2. **"Last upload" is a job name, not a tag.** A run uploaded when its
   `Uploaded` job succeeded; the plan job pages through successful Release
   runs on `main` with the Actions API. No tags, no `contents: write`, and
   dry runs or skips never count. The same lookup gives the notes' start
   commit.
3. **Re-ship an unchanged `main`** when TestFlight has no installable build
   (item 1) or the last upload is 60 days old, so testers never hit the
   90-day expiry on a quiet `main`.
4. **Only green `main` ships, and `force` does not override it.** The plan
   reads the newest `ci.yml` push run on the commit (a green rerun counts)
   and needs `status: completed`, `conclusion: success`; `ci-ok` fails that
   run whenever a gate fails. A scheduled run that skips for this opens the
   failure issue: a red `main` on Monday is a failed release.
5. **The failure issue.** Scheduled runs and `simulate_failure` dispatches
   open or comment on "Weekly release failed"; other failed dispatches
   don't (whoever started them watches). A green upload run or an
   "unchanged" skip closes it; dry runs never touch it, since they prove the
   build but not the upload.
6. **Play is keyless.** fastlane 2.241's supply reads `external_account`
   credentials (checked in the gem source, `supply/client.rb`), so
   `google-github-actions/auth` with Workload Identity Federation replaces a
   JSON key. The service account `play-release@family-groceries-ci` has no
   key and no project roles; its only binding is
   `roles/iam.workloadIdentityUser` for the subject
   `repo:trost-systems@267752722/family-groceries@1429864759:environment:release`
   (the repo uses GitHub's immutable subject format), so only jobs in the
   `release` environment, which deploys from `main` only, can act as it.
   Narrower than the provider's repo-wide condition. `PLAY_SERVICE_ACCOUNT_JSON`
   is gone from the secrets check.
7. **`PLAY_RELEASE_STATUS` is the Play setup state.** Unset: no upload; the
   run proves the token exchange and reports whether Play lets the account
   in (`android play_access`), and the AAB is an artifact for the Lead's
   first manual upload. `draft`, then `completed`: every run uploads, and a
   missing grant fails the run. One variable instead of a separate on/off
   switch. A failed token exchange always fails the job: that is our setup.
8. **fastlane 2.241.1 to 2.241.2.** The patch release fixes security
   advisories in spaceship and match, both of which run with the signing
   secrets here.
9. **What to Test is set by `wait_processing`, not by pilot.** pilot waits
   for the build only when `changelog` is set and ignores
   `localized_build_info` for that check, and a retried upload would trip
   over it. The upload is retried once; the wait lane sets de-DE and en-US
   as soon as the build appears and then polls for `VALID`.
   `notify_external_testers` stays unset: there are no external groups and
   `distribute_external` is false; internal testers get TestFlight's normal
   notice.
10. **Dry runs validate.** iOS runs `altool --validate-app` with the API key
    (written to `~/.appstoreconnect/private_keys` for the call and deleted);
    Android runs the upload with `validate_only` once Play is set up. Both
    check the signing: the IPA through match's profile, the AAB through
    `check-aab.sh` against the upload certificate's SHA-256.
11. **Upload key.** PKCS12 keystores have one password; keytool ignores a
    separate key password, so `key.properties` names the same random
    32-character password twice. The first `keytool` call failed before
    writing a keystore (the password variable was not exported); its
    stray `key.properties` was deleted and both files were generated again.
12. **The release tests run in the lint gate**, next to
    `scripts/landing-test.sh`. The lint gate runs on every PR; the fastlane
    gate is path-filtered to `app/fastlane` and the Gemfile and would skip a
    change to `scripts/release/`. The lint gate's shellcheck line now covers
    `scripts/release/*.sh`.
13. **5-green, adapted.** The PR touches `scripts/gates/lint.sh`, a gate
    `verify.sh` runs, but none of `app/` (other than `app/fastlane` and the
    Gemfile), `supabase/` or `e2e/`. The Lead's rule for CI-only changes
    applies: CI `ci-ok` on the final head (the gate edit makes CI run every
    gate), `scripts/verify.sh --only lint,fastlane,gitleaks` locally, then
    5 consecutive green `upload: false` Release runs on `main` and one real
    upload run. No local Supabase stack, Playwright or Flutter build: the
    lint gate edit cannot change what those gates run.
14. **Capabilities without the Certificates workflow.** `ios renew_profile`
    runs match with `readonly: false`, `force: true` and
    `certificate_id: GN85KDC962`; match creates a certificate only when the
    repo holds none, so it regenerates the profile and nothing else. The
    box's network blocks SSH to GitHub (ports 22 and 443), so the box uses
    the HTTPS match URL with `gh` as the credential helper; the no-change
    run (`MATCH_FORCE=false`) passed and left the match repo's HEAD as it
    was. The plan's `ios preflight` fails early on an `INVALID` profile.
15. **Build number guard.** The plan fails a run whose number is not above
    TestFlight's highest, naming `BUILD_NUMBER_OFFSET`, instead of letting
    the upload fail after an hour of macOS build.
16. **One local appbundle build, for the Lead.** The Lead created the Play
    app while #52 waited for CI (ghcr.io refused runners for hours), and L3
    needs a signed AAB before any Release run on `main` can make one. The
    box builds it (`--build-number=1003`, MemAvailable 9 GB, no other
    flutter build running, the `~/.gradle` limits), checks its signer with
    `check-aab.sh` and installs it at
    `~/groceries-ops/artifacts/app-release.aab`. The first attempt (22:37)
    copied the keystore and `key.properties` into `app/android/` and was
    killed with the session before it finished, so its cleanup never ran
    and both copies stayed in the worktree (gitignored, never committed;
    review 0 found them). They were deleted. The build that counts
    (`/tmp`-only script, detached so a session end cannot cut it) copies no
    keystore: its `key.properties` names the keystore in
    `~/groceries-ops/secrets/android/` by absolute path and is deleted by an
    exit trap. Only that one build ran; the first never produced a bundle.
    `BUILD_NUMBER_OFFSET` went from 1000 to 1010 so CI's next number (1013)
    is above both stores' highest.
17. **Review round before merge** (independent reviewer, read-only): What
    to Test is sanitized with pilot's `sanitize_changelog` and a refusal
    only warns (a red `ios` job after a good upload would reopen the issue
    and re-ship the same commit); the notes drop titles about the repo's own
    machinery; an Actions API error in the last-upload lookup now fails the
    plan instead of reading as "no earlier upload"; the upload retry first
    looks for the build for 10 minutes; preflight accepts any ACTIVE profile
    of the name (a regenerated profile can leave an INVALID twin); the notes
    output uses a random heredoc delimiter; the signing secrets moved from
    the `ios` job's env to the two fastlane steps, out of reach of the
    third-party actions.
18. **ghcr.io refused runners** (`toomanyrequests` on every Supabase image
    pull, seven attempts over two hours, githubstatus green). #52 takes
    15b's one-line `ci.yml` change (`SUPABASE_INTERNAL_IMAGE_REGISTRY:
    docker.io`) byte-for-byte, so whichever of #49 and #52 lands second
    rebases cleanly.

## Job 15 (design H, part 1: data, parser, edit sheet), 2026-10-25

The build spec for design H (jobs 15 to 17) is
[`docs/design/h-satz-final/SPEC.md`](design/h-satz-final/SPEC.md): Peter's
decisions, the prototype's tokens, where the app differs from the prototype
on purpose, and the interfaces this job ships.

1. **The parser is SQL (`public.parse_item`).** One implementation that the
   app (RPC), MCP and Siri (`public.add_item`, which `add_items` calls) all
   reach. A Deno module would have needed a second copy in Dart for the app,
   and the parser needs the household's memories and learned brands, which
   live in Postgres. Offline, the app's add flow falls back to `parseEntry`
   (name and quantity). Changing it means changing the function, not the
   callers.
2. **Properties are one text column** (`items.properties`, parts joined with
   `", "`). The edit sheet shows one field, as the prototype does. Splitting on
   ", ", "·" or ";" keeps "1,5 %" whole. A text array would need a migration of
   every caller (MCP, voice, export) for no visible gain.
3. **Walk order is a `double precision` `sort_key` per (store, category)
   group.** A move rewrites one row (midpoint). When the gap falls under
   0.001, `place_item` renumbers that one group in steps of 1024 first. Bought
   items keep their key, so Undo and re-add put an item back where it was.
   A plain edit that changes the store or category puts the item at the end
   of its new group. The backfill numbered existing rows by `created_at`, with
   triggers off, so neither `updated_at` nor the history changed.
4. **Two drag RPCs instead of one with modes.** `place_item(item, anchor,
   edge)` is a drop on a row: the item adopts the anchor's store and category.
   `move_item(item, store, category)` is a drop on a divider: the end of that
   group, where a null store means "Ohne Laden". Each has one meaning and no flags.
   Learning stays in the triggers, so both learn exactly like an edit.
5. **Brands are data.** `supabase/classifier/brands.tsv` (608 brands, each
   with an optional product and the store for a store's own brand) becomes a
   migration through `generate_brands.ts`, like the dictionary. `brand_key`
   folds case, umlauts, ß, spaces, dots, hyphens and apostrophes and keeps & and !
   (Coca Cola = Coca-Cola; "Ja!" is a brand, "ja" is not). Ordinary words are
   excluded on purpose (Kinder, Danke, Ja, Bio, Müller, Harry, ...), and a test
   checks that. Households learn brands the list lacks
   (`household_brands`) from any write of `items.brand`.
6. **Laden for a new entry**: item→store memory, then the brand's own store
   (Balea → dm), then the category's hint (drugstore → the household's dm),
   else none. This applies to MCP, Siri and job 17's add sheet. Rows the app
   writes without a store still get only the memory (the trigger), as before.
7. **Duplicates compare name, brand and properties.** "Windeln Pampers
   Größe 3" and "Windeln Größe 4" are two items, and "Gurke" is still "2 Gurken".
8. **Edits are patches.** `EditItem` carries only the changed columns
   (`ItemChanges`, with `SetTo<T>` for nullable columns so "unchanged" and
   "clear" differ). The same map is the PATCH body, so Fertig can never
   overwrite a partner's change to another field. The offline snapshot is
   v3. Its migrator turns queued v2 edits into full patches and v2 moves into
   category-only patches, which is exactly the old PATCH.
9. **Long press is 300 ms (was 500), as in the prototype.** Releasing within
   8 px opens the edit sheet. Moving further starts the drag. The empty drop
   targets appear only after 8 px, so the list does not jump under a press
   that opens the sheet. A plain tap still opens edit until job 16 makes it
   tick.
10. **Right click on web opens edit.** The browser's context menu is off only
    while the pointer is over the list, so text fields keep paste and
    spelling.
11. **Menge −/+** changes only the leading number and keeps the unit and the
    decimal comma. The step is 1, or 100 for g and ml from 100 up ("500 g" → "600 g").
    An empty Menge counts as 1. The steppers hide when the Menge does not
    start with a number ("eine Packung").
12. **The edit sheet is a Material modal bottom sheet** with the prototype's
    emphasized-decelerate curve (280 ms open, 200 ms close, none when
    animations are off). A spring is not cheap with the Material sheet route.
    The content column decides the height (no fraction), and the sheet
    scrolls only when the keyboard leaves less room than the content needs.
13. **No added-by initial on rows** (Peter's decision). `Catalog.initialOf`
    and the strings only it used are deleted. `added_by`, `Member` and "N neu
    von Lea" stay. The highlight adds no glyph to the row, so it does not
    conflict with the design, and nothing is needed from Peter.
14. **`app_en.arb` starts with the keys this job adds.** gen-l10n's
    untranslated-messages file moved to `.dart_tool/` because `build/` does
    not exist on a fresh checkout. Job 17 completes the English.
15. **Parser rules settled in review (0 and 1).** One rule for amounts: a
    leading count or amount is the Menge, else the first amount with a unit
    wherever it stands, else a count anywhere ("Äpfel 1 kg bio" and "1 kg
    Mehl" both give Menge 1 kg). Halves become `1/2`, or `0,5 <unit>`
    before a unit, and "anderthalb" becomes `1,5`. Multipacks are one
    property written `6x1,5 l`. Plain descriptors (Bio, laktosefrei, ...)
    count up front too; flavours up front stay the name ("Paprika rot").
    Letter sizes are sizes ("Größe M"). `parse_item` reads one entry and
    keeps a list comma or "und" in the name instead of dropping it. Splitting
    sentences stays the voice splitter's job, which the app already calls,
    so the three callers cannot diverge. Every parsed field is capped at its
    column (cut at a space). An explicit over-long `add_item` field raises
    22001 before anything is written. Each rule is a row in
    `supabase/tests/parse_item.test.sql` or a test in
    `item_details.test.sql`.
16. **The voice splitter reads at most six integer digits as an amount.**
    A longer run of digits used to come back as "1e+60 l". It now stays in
    the name, and a spoken quantity is cut to the column's 40 characters.
17. **Paar, Dutzend, Laib and Kopf are units in `parse_item`** ("3 Paar
    Socken" gives Socken, Menge `3 Paar`), as they already were in the voice
    splitter, so the two parsers read counting nouns alike (review 2).

### Job 15b (landing #49), 2026-10-26

1. **The box has two kinds of host stall, and only one breaks tests.** A
   heartbeat that logs the wall and the monotonic clock every second
   (`/tmp/fg15b/heartbeat.log`) saw both on 2026-10-26: at 12:44 the wall
   clock jumped 525 s and the monotonic clock 524 s, and at 12:53 the wall
   clock jumped 1954 s while the monotonic clock moved 11 s. In the first
   kind every deadline (a test's 60 s, an expect's 10 s, Kong's 60 s
   upstream timeout) has passed when the box resumes, so the test fails
   however its waits are written. The second kind leaves monotonic timers
   alone: a full e2e run passed 73/73 straight through the 1954 s hole.
   Job 15's four failed tests (live-sync join, STORE ORDERING,
   CLASSIFIER-LEARNING twice, live layout sync) each ran 2.8 to 7.1 min
   against a 60 s test timeout. That overshoot needs a stall with the clock
   running, and each error is a spent budget: the test timeout, the 20 s
   `typeInto` budget, and Kong's 504. CLASSIFIER-LEARNING otherwise passes
   in 10 to 11 s.
2. **A test cut by such a stall gets one retry, and nothing else does.**
   Playwright runs with `retries: 1`. The `stallRetry` fixture
   (`e2e/tests/fixtures.ts`) lets the retry run only if the failed attempt
   measured a runner pause of 2 s or more (18b's `hostStall`, which leaves a
   mark the moment its 1 s tick sees the pause, so a pause that times out a
   fixture teardown still counts; 18c measured the tick at most 16 ms late
   at load 21). Any other failure fails its retry at once with "not
   retried", so a real failure still fails the gate. A stall-retried test
   shows as flaky in the summary. Longer timeouts would not help, because
   the stall eats any budget, and a blind retry would hide real failures.
   Proven with a probe spec (SIGSTOP of the runner for 15 s during an
   `expect.poll`: retried and passed. A plain failure: refused).
3. **`account/apple_test.ts` checks each Apple client secret instead of
   comparing them.** Each request signs its own secret, so the token and
   revoke secrets differ once a second ticks over between the calls. This
   was a real flake on main (18b's run, no stall), and a 1.1 s delay
   between the calls makes the old test fail every time.
4. **gitleaks scans what could be committed** (18b's change on #35, taken
   byte-identical): Playwright traces under the ignored `e2e/test-results/`
   hold local session JWTs and no longer fail a local run.
5. **`db_reset` stops realtime before `supabase db reset`** (18b's fix on
   #35, DECISIONS 18.18 there, taken unchanged). Run 9 of #49's 5-green
   failed in the db gate with no host stall, at "Initialising schema",
   the same signature 18b traced to two realtime writers migrating one
   fresh database. The db gate and the backup drill use it.
6. **CI pulls the Supabase images from Docker Hub.** From about 20:20 on
   2026-10-27, ghcr.io answered every image pull from GitHub's runners with
   "toomanyrequests" (main, #49, #35 and job 23 alike, for over two hours),
   while the same pulls from the box went through. A `docker login ghcr.io`
   with the run's token did not help (probe run 40582681259). With
   `SUPABASE_INTERNAL_IMAGE_REGISTRY: docker.io` the db job pulled every
   image and passed (probe run 40582999552). The variable stays the one
   switch to change if Docker Hub ever limits runners too.
7. **The edit-sheet size check waits for the sheet to hold still.** Run 22
   failed with no host stall (its retry refused, as designed):
   `expectHugsContent` read the sheet's box and Abbrechen's a frame apart
   while the category options were still folding out, so Abbrechen sat
   32 px "above" the sheet. The check now first polls until the sheet's
   box is the same across two frames. Measuring right after the chip tap,
   the old check failed 3 of 3 (-16 to -136 px) and the new one passed 3 of
   3. The app was right.

## Job 18 (test fixtures and multi-client sync), 2026-10-25

18.1. **One CLI.** Fixtures and sync are `fg` subcommands (`scenario list|show`,
      `seed <scenario>`, `runs`, `teardown`, `sync`), with fg's JSON, error and
      `--dry-run` contract. Plain `fg seed` keeps resetting to peter + lea, so
      existing recipes work unchanged.
18.2. **Scenarios are YAML with a JSON Schema** (`test/fixtures/`), validated
      with Ajv plus cross-reference checks in `cli/scenario.ts`, so every error
      names its field. YAML because scenarios are written and reviewed by hand
      and need comments. Times are relative ("-3d 18:10" in Berlin time), so a
      scenario never goes stale; clock times need days >= 1, so they are always
      in the past at any hour.
18.3. **No migration.** A run is identified by the email
      `<handle>.<run>@fg-test.invalid` (`.invalid` is reserved, RFC 2606, so no
      mail can ever be delivered), `app_metadata.fg_run`, and a manifest of
      created ids. Teardown finds a run by any of the three, so a lost manifest
      still tears down.
18.4. **Seeding goes through the app's own paths where they exist.**
      `create_household` (categories, stores, layouts), `create_category`,
      `reorder_categories`, `set_store_layout`, `create_invite`, and inserts and
      ticks under each member's own session, so the classifier, `added_by`,
      item→store memory and `item_events` come from the real triggers. Only
      what no user can do uses the service role: adding members without an
      invite, backdating `created_at`/`bought_at`/event times, expiring or
      revoking an invite. History is replayed oldest first, so "latest wins"
      memories are right; their own `updated_at` is the seeding time.
18.5. **Teardown deletes users with `public.delete_account`** (the app's path:
      it locks the household row, deletes it with its last member, hands
      ownership on otherwise, nulls event actors). There is no bulk household
      delete before it: a user outside the run who joins between reading the
      members and deleting would lose their household. Only a household the
      run created that is left without members is deleted directly. The
      leftover check counts 16 tables by household and by user and fails on
      any non-zero count. Ctrl-C during seeding only flags an abort; seeding
      stops at its next request and teardown starts after it, so teardown
      sees every record (an independent review found the race).
18.6. **Member refs.** `--as`, `peer`, `login`, `mail --to`, `up --clients` and
      `--client` take `peter`, `lea`, `<run>:<handle>`, or a bare handle of the
      last run seeded on that stack. Scenario handles may not be `peter` or
      `lea`. Linux clients for members get X displays `:<prefix>3..9`.
18.7. **Credentials** live only in the run manifest
      (`$FG_STATE_DIR/runs/<run>.json`, directory 700, file 600) and, during a
      sync, in a 600 config file in the state dir that is deleted afterwards.
      Seed output, logs, evidence and screenshots never contain them.
18.8. **`fg sync` drives web, in one Chromium.** Each client is an isolated
      context (about 250 MB) instead of a Linux debug app (about 650 MB), so
      three clients fit on the shared box. The driver is a plain Node script
      (`e2e/sync/engine.mjs`) using e2e's Playwright, not a Playwright test,
      so it runs one long scenario with its own capture loop. The script
      language is parsed in Deno (`cli/sync_dsl.ts`, unit-tested) and handed to
      the driver as JSON, so a Marionette driver can run the same steps. A
      native `--surface linux` driver was left out: three Linux clients plus
      the stack do not fit in this box's RAM (docs/TEST_FIXTURES.md, "Other
      surfaces").
18.9. **Changes are detected in the page.** A MutationObserver on Flutter's
      semantics DOM reports each change of the visible rows, chips and texts
      with the time of the frame; the driver then screenshots all clients at
      once. The same log decides expectations and their latency, so the
      latency resolution is one rendered frame, not a polling interval.
18.10. **Latency** is reported from the acting client's server ack (its first
      successful REST write after the input), from the input, and from the
      `item_events` row (local only, shared clock). The acting client's own
      optimistic view, expectations that held before the action, and
      catch-up after `online` are kept out of the live numbers; catch-up is
      reported apart.
18.11. **Offline closes the open realtime socket too.** With only Chromium's
      offline emulation, the open WebSocket stayed up: the offline client got
      nothing while offline and showed the missed add 48 ms after `online`
      (measured; it looks like held traffic flushed on reconnect, inferred).
      That never exercises the app's reconnect. So every realtime socket runs
      through Playwright's WebSocket route and `offline` also closes it: the
      app sees a real disconnect and recovers through its reconnect and resync
      (about 3 s here, reported as catch-up). The relay adds no measurable
      latency: p50 from ack 288 and 290 ms with it, 307 and 304 ms without
      (2 runs each, 8 observations per run, `FG_SYNC_DIRECT_WS=1`).
18.12. **The e2e lock.** `fg sync` builds the web app, then takes
      `/tmp/fg-e2e.lock` (waiting up to `--lock-wait` seconds, else
      `e2e_lock_busy`), and only then seeds, so a run never waits idle for
      the lock: a kill while waiting leaves nothing behind (review 0). A lock
      already held by a parent process is detected by an open descriptor on
      the lock file in this process or an ancestor, and reused, so
      `flock /tmp/fg-e2e.lock scripts/fg sync ...` and the e2e gate's
      `flock 9` do not deadlock.
18.13. **Hosted target** (`--target hosted`): test-domain accounts only, the
      service key fetched per run through the Management API and kept in
      memory, teardown on any failure or Ctrl-C, and non-test row counts
      (counts only) recorded before and compared after. `fg sync --target
      hosted` uses the production web build configuration.
18.14. **Job 15 fields** (`brand`, `properties`, `walkOrder`) are accepted by
      the schema and feature-detected at seed time; a database without the
      column fails with `needs_column` before anything is created. The
      walk-order column is assumed to be `items.sort_key`
      (`ITEM_EXTENSION_COLUMNS` in `cli/fixtures.ts`).
18.15. **Capturing does not slow what it measures.** With change frames on,
      p50 from ack was 218 and 223 ms; with them off
      (`FG_SYNC_NO_CHANGE_FRAMES=1`), 315 and 318 ms (3 clients, 12
      observations per run, alternating runs). Headless Chromium seems to
      schedule frames later in contexts nothing screenshots (inferred), so
      the absolute numbers are this harness's view of propagation, not an
      app benchmark; compare runs made the same way. Across all runs on this
      box, live p50 from ack (all clients) ranged from 93 to 290 ms; catch-up after a
      reconnect took about 3 s.
18.16. **Stop signals (review 0).** SIGINT, SIGTERM and SIGHUP abort one
      AbortSignal that reaches every slow step: seeding checks it between
      requests, and the lock wait (`flock`), the web build and the browser
      driver are child processes started with it, so they are killed at
      once. The command's own cleanup (web server, lock, config file) runs
      while it unwinds; then a run it seeded is torn down and fg exits
      130/143/129. A seed that fails or is stopped is torn down on both
      targets (a half-seeded run is useless). SIGKILL cannot be caught;
      `fg runs` and `fg teardown --stale` cover it. Unit tests drive the
      handler with injected signals (`cancel_test.ts`); `e2e/sync-smoke.sh`
      sends a real SIGTERM in the lock wait and in the browser run.
18.17. **Flakes the 5-green found (job 18b).** Each failure was matched
      against mem-guard's once-a-minute samples. A gap of minutes followed
      by `load=0.00` is a VM freeze. Every Playwright failure (list:53,
      offline-start:30 and :84, voice:27, live-sync:171, stores:113) fell
      in one; some freezes (182 s, 239 s) were shorter than the 300 s the
      runner script counted as a freeze, so they looked like flakes. A
      paused VM resumes with every deadline already passed, so no wait in a
      spec survives it, and longer timeouts would only hide real hangs.
      What changed instead:
      - The cubit unit tests waited wall time (`Future.delayed`) for
        work the cubit's own timers start. In flutter_tester, timers that
        come due together run back to back before any microtask, so after
        a stall the test resumed mid-reload ("Expected 'Ana', Actual
        null"). `elapse()` waits, then drains the event queue; a stall
        injected after both timers exist fails the old test and passes the
        new one.
      - `e2e/tests/fixtures.ts` names a host stall: an auto fixture ticks
        every second and, when the runner was paused 10 s or more, prints
        `[host-stall] <test>: the host paused the test runner for N s` and
        annotates the test. A freeze is then read off the run's own log,
        not guessed from another process's samples.
      - The gitleaks gate scans what git could commit (tracked plus
        untracked, not ignored) instead of every file on disk. Playwright
        traces in `e2e/test-results/` hold local-stack session JWTs and
        failed the next local run; ignored files reach a commit only with
        `git add -f`, which the pre-commit hook scans. The path allowlist
        (all of it gitignored) went with it.
      - An app bug found on the way: a write PostgREST answered with a JWT
        error (`PGRST3xx`, a token that lapsed in flight, e.g. after a
        freeze or a phone waking) counted as refused, so the queued op was
        dropped with "Änderung abgelehnt". It now counts as offline and is
        retried with a fresh token (offline-start.spec "a write the server
        answers with an expired token is retried, not dropped" failed
        before the fix).
18.18. **`db reset` without two realtime writers (job 18b).** One 5-green
      run failed in the db gate with no stall: `supabase db reset` exited
      1, and the gate's `>/dev/null` hid the CLI's message, which goes to
      stdout (`DbSetupError: error running container: exit 1`, at
      "Initialising schema"). Seen once more in about 90 resets by hand; both failures came
      while another job's stack was busy. A reset recreates the database
      and runs a one-shot realtime container that migrates and seeds it;
      meanwhile the realtime service, which lost its database, restarts and
      runs the same migrations and seeds against the same database
      (`docker events`: both up in the same second). That overlap is the
      only concurrency in the step and the likely cause, but it is
      unconfirmed: the failing container's own log was never caught (about
      70 more resets with capture passed). `db_reset` (`scripts/lib.sh`, used
      by the db gate and the backup drill) stops the realtime service first,
      so the one-shot container is the only writer; the CLI starts the
      service again at "Restarting containers". A failure now prints the
      CLI's error.
18.19. **Apple client secrets are checked, not compared (job 18b).**
      `apple_test.ts` asserted the revoke request reused the token
      request's client secret. `revokeAppleGrant` signs one per request,
      each with its own `iat`, so the two differ whenever the requests
      straddle a second; Apple accepts any valid one. The test now verifies
      both secrets. The app did not change.
18.20. **A sweep for the same two timing classes (job 18b).** After the
      cubit and Apple fixes, every unit test (functions, classifier, deploy,
      fg CLI, Flutter) was read for wall-time waits racing timers and for
      equal values from two clock reads. Three more could flake on a
      stalled box: `cancel_test.ts` assumed its lock holder had the lock
      after 200 ms (it now waits for the holder to say so), and aborted on a
      300 ms timer that could fire before `takeE2eLock` spawned flock (it
      now aborts once the waiting flock exists; `takeE2eLock` also checks
      the signal again after its ancestor walk, so a stop there is
      `interrupted`, not a raw AbortError); the usuals debounce test checked
      "no refresh yet" against a real 1.5 s timer (it now runs under
      `fakeAsync`). Each was proven: a 1 s delay before the holder locks
      fails the old lock test and passes the new one; a 1000 ms debounce
      fails the new usuals test.
18.21. **Host stalls: one rerun, accepted only with proof (job 18b review 0).**
      Review 0 rejected voiding failed runs: a void rule that counted stall
      lines could excuse a real failure in another test, and it never
      showed the app recovers after a pause. Now:
      - Playwright retries a failed test once (`retries: 1`), and
        `e2e/host-stall-reporter.ts` fails the run when a test passed only
        on its rerun and a failed attempt has no `host-stall` annotation.
        A test the host paused gets its one rerun; any other flake fails
        the run as before. A 75 s SIGSTOP of the runner and its Chromium in
        live-sync.spec failed the paused test, its rerun passed, and the run
        exited 0; a test that fails once with no pause failed the run
        ("FLAKY without a host stall").
      - Extending the test timeout by the pause was tried and dropped: in
        the same 75 s stall the failure came from an inner deadline
        (`typeInto`'s 20 s `toPass`), which no test timeout covers.
      - Recovery after a pause is tested on its own: live-sync.spec "a
        phone that sleeps through a dropped connection ..." freezes the page
        (CDP `Page.setWebLifecycleState`, which holds every timer: a 50 ms
        interval stood still while frozen and fired 20 times on waking),
        kills its Realtime connection and adds an item meanwhile; after
        waking the item shows, the channel is live again and adds flow both
        ways. Waiting for Realtime to drop a silent socket was tried first;
        the local server had not closed it after 150 s.
      - The 5-green loop voids nothing: every failed run resets the count.
        It goes on only when each failed test has its own `[host-stall]`
        line (matched by title) on both attempts, at most twice per head
        and never twice for one test; anything else stops it.
      - Every stall the detector reported since the 1 s bash heartbeat
        (`/tmp/fg18b/heartbeat.log`) started matches a heartbeat hole within
        3 s (docs/done/18-test-fixtures-sync.md lists them).
18.22. **A rerun after a host pause is accepted, nothing else (job 18b
      review 1).** Accepted: a test whose failed attempt the in-run
      detector saw paused for 10 s or more, rerun once, passing. A pause
      stops the runner, Chromium and every deadline, Playwright's own
      included (in a 75 s stall the failure came from `typeInto`'s 20 s
      `toPass`, not from the spec), so no wait in a spec can be written that
      survives it; making the waits longer would only hide real hangs. What
      a pause does to the app (a dead socket, overdue timers, an expired
      token) is tested on its own: live-sync.spec's sleeping phone, the
      socket and channel drop tests, and the `PGRST3xx` retry (e2e and
      `list_repository_test.dart`). The evidence has a gap: the 10-25
      failures predate the 1 s heartbeat and are matched only to
      mem-guard's once-a-minute samples and, for three of them, to error
      types (a reload, a page setup and a context teardown that timed out
      before or after the spec's own steps). Reading those specs found no
      test or app race, which is weaker than a heartbeat match. If one of
      them fails again without its own `[host-stall]` line, the reporter
      fails the run and it gets the treatment the cubit race got.
18.23. **Each flaky spec traced to a cause (job 18c).** Review 2 asked for
      a root cause per spec or a stated policy. Both came out of it:
      - Load is not a cause. The five specs (list:53, offline-start:30
        and :84, voice:27, stores:113) ran 30 times with retries off under
        8 CPU burners, a direct-I/O disk writer and job 15b's run (load
        15 to 21). 27 passed. Each of the 3 failures fell inside a whole-VM
        pause that the 1 s heartbeat saw to the second (217, 1000 and
        184 s). Under load 21 the runner's 1 s tick ran at most 16 ms late,
        so load does not make the gaps the stall detector looks for.
      - The pauses are the VM's. Since 2026-10-27 22:00 the VM was paused
        for 80 to 91% of every hour, in holes of 150 to 2900 s. Both
        heartbeats and mem-guard go silent together, and in some holes the
        monotonic clock stops too.
      - A test defect, under short pauses. While the runner and Chromium
        were stopped for 8 s every 6 s (the stack kept running, like a
        server while a phone sleeps), stores:113 failed 2 of 3 with no VM
        hole and no stall line. The latency checks in stores:113,
        live-sync:7, mcp:26 and offline-start:31 had 2 to 3 s budgets on
        the wall clock, so a pause shorter than the 10 s stall threshold
        failed them with no excuse. `within(ms, check)` (e2e helpers.ts) now
        counts the budget in time the runner ran: rounds of 250 ms, and
        each round counts at most 1 s. A check that never passes still
        fails after 2.06 s. One that turns true at 1 s passes at 1.0 s.
        Under 8 s pauses every second, a never-passing check throws after
        9 s of wall time.
        With 8 s pauses every 6 s and retries off, the four specs then
        passed 11 of 12. The one failure fell in a 310 s VM hole, which the
        detector named.
      - The stall threshold is 2 s, not 10 s, so a pause that breaks an
        ordinary 10 s wait is named too.
      - A pause in a fixture teardown was never named. If the pause timed
        the test out there, Playwright skipped the teardowns still to come,
        hostStall's own check among them, and the retry was refused. This
        was seen live: a 149 s hole in a context teardown. hostStall now
        writes the retry mark on the tick that sees the gap. A 3 s
        event-loop block in a teardown that times the test out got "not
        retried" before the fix; after it the retry runs and passes. The
        same timeout without a block is still refused. stallRetry clears
        the mark when attempt 0 starts, so a pause in an attempt that
        passed cannot excuse a later failure.
      - The accepted policy: a test that the runner saw paused for 2 s or
        more gets one retry, and the retry must pass. Every other failure
        fails the run. A VM pause stops the runner, Chromium and the stack,
        and they resume with every deadline already passed. No spec can
        wait through a 3000 s pause without dropping its deadlines, and
        that would hide real hangs. What a pause does to the app (a dead
        socket, overdue timers, an expired token) has tests of its own
        (18.21, 18.22). What the policy cannot see: an app race that shows
        only in an attempt that was also paused. The passing retry is the
        evidence against it, and a race that shows up twice fails the run.
      - Job 18b's `host-stall-reporter.ts` is gone. #49's stallRetry
        fixture does the same job (no retry without a stall mark).

## Job 24a (guides site on hummlist.com), 2026-10-28

1. **A small Node generator, not Astro.** `site/build.mjs` (markdown-it,
   gray-matter; node-html-parser for the output checks) turns
   `site/content/**/*.md` into `site/dist`. Seven pages need no framework,
   and every check the brief asks for (frontmatter, one h1, heading order,
   alt text, no script, no external resource, internal links, placeholders)
   runs on the HTML the build writes. Page kinds (guide, legal page, index)
   and locales are two registries, so a guide is one file and a language is
   one entry.
2. **Its own Vercel project, the app untouched.** `site/vercel.json` carries
   install, build and output, so the Lead only sets Root Directory `site`.
   The app's `vercel.json` builds `app/` into `app/build/web` and reads
   nothing in `site/`. A release web build on this branch is byte-identical
   to `main`'s (44 files, same SHA-256), with `site/` and the new Dart file
   present. The app project still redeploys on a `site/`-only push (same
   output); skipping that is a Vercel "Ignored Build Step" setting, the
   Lead's call, not a repo change.
3. **The Siri guide's app link is a const plus a test.** The app has no
   Siri setup screen or link today, so per the brief no UI:
   `app/lib/app/guides.dart` holds `guidesBaseUrl` and `siriGuideUrl(lang)`
   (German UI to `/de/anleitungen/siri-kurzbefehl`, anything else to
   `/en/guides/siri-shortcut`). It has no caller yet, so dart2js drops it;
   its test also fails if either guide file is renamed.
4. **`/` redirects by `Accept-Language`** in `site/vercel.json`: a header
   starting with `de` goes to `/de/anleitungen`, any other header to
   `/en/guides`, none to `/de/anleitungen` (307, `Vary: Accept-Language`).
   A static `index.html` with a meta refresh to `/de/anleitungen` covers
   hosts without redirects. `x-default` points at the German version.
5. **noindex everywhere until the beta launch** (`X-Robots-Tag` header on
   every response), with a strict CSP (`default-src 'self'`), no cookies,
   no scripts, no third-party resources or fonts. Removing the header is in
   `NEEDS_PETER.md`.
6. **Lighthouse thresholds: performance >= 90, accessibility >= 95** on
   mobile (Spec #5 AC5, adjusted). Measured on the local preview server,
   which applies `vercel.json`'s headers: 100/100 on every page type. SEO
   scores 63 only because of the intended noindex.
7. **Impressum placeholders.** Open facts are written `[PETER: …]`; a
   production build (`VERCEL_ENV=production`) fails while a published page
   contains one, a preview build only warns. Peter answered both on
   2026-10-27 (address; support@hummlist.com), so none are left.
8. **The legal pages come later, into `site/`.** Job 24 adds `/datenschutz`,
   `/privacy` and `/support` as `site/content/legal/*.md` and sets
   `legalPublished: true` in `site/config.json`. Until then the footer shows
   only Impressum; a footer link to a missing page fails the build. The job
   24 brief carries this note.
9. **CI: a new `site` gate, the normal CI gate for landing.** It always
   runs (guides are Markdown, which `ci-changes.sh` counts as docs): tests,
   a production build, and a repo-wide `git grep` for a real access token
   (`fgp_` plus 43 characters; binary files such as images are searched
   too). App code changes only by an unused const and its unit test, so the
   five-green e2e rule does not apply.
10. **Copy is verbatim.** The guide bodies match
    `~/groceries-ops/jobs/24a-guides-site/content/` byte for byte; only
    `translation_key` and `updated` were added. The index intros are the
    approved paragraphs; their hand-written lists became the generated list
    (title and description from frontmatter), so a new guide needs no index
    edit.

## Job 26 (public MCP URL mcp.hummlist.com), 2026-10-28

1. **A rewrite-only Vercel project, not a domain on the app project.**
   Peter approved `https://mcp.hummlist.com` as the public MCP URL through a
   new Vercel project (`hummlist-mcp`, Root Directory `mcp-proxy/`) that
   rewrites to the `mcp` edge function. The directory holds only
   `vercel.json` and a README: no build, no functions, no env vars. The app
   project (repo root `vercel.json`, output `app/build/web`) and the guides
   site (`site/`, PR #54) each read only their own Root Directory's `vercel.json`,
   so neither sees `mcp-proxy/`.
2. **Both URLs stay valid.** Clients already connected to
   `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp` keep it.
   Supabase does not bind tokens to the `resource` (MCP.md, research notes),
   so one token works on both hosts, and the local authorization server
   accepted `resource=https://mcp.hummlist.com` at `oauth/authorize` (302 to
   the consent page). The issuer and `authorization_servers` stay
   supabase.co on both hosts.
3. **The function advertises the URL the client came through.** Through the
   proxy, the metadata says `resource: https://mcp.hummlist.com`, and the
   401/403 challenge points at
   `https://mcp.hummlist.com/.well-known/oauth-protected-resource` (the
   RFC 9728 path for a resource without a path). Any other request gets
   exactly the supabase.co values from before. An MCP client checks that the
   metadata's `resource` matches the URL it connected to, so each host must
   name itself.
4. **Two proxy signals, both allow-listed.** The request counts as proxied
   when the query has the marker `via=mcp-hummlist` that `vercel.json` adds
   to every destination, or when the first `x-forwarded-host` value (case
   folded, port stripped) equals the `MCP_PUBLIC_URL` host. The brief asked
   for the header with the marker as a fallback. The local stack's gateway
   (Kong) replaces a client's `x-forwarded-host` with its own host
   (checked 2026-10-28: the function saw `127.0.0.1`), while query
   parameters and other headers arrive. The hosted gateway may do the same,
   so the marker ships from the start instead of after a second deploy. A
   spoofed marker or header only makes the function advertise the
   allow-listed public URL, which serves the same function: harmless. Item
   11, written after the deploy, records which signal arrives on the hosted
   project.
5. **`MCP_PUBLIC_URL` has a committed default.** It is not a secret, and a
   default (`https://mcp.hummlist.com`) means no manual secret step on the
   hosted project. Only its origin counts, since the proxy serves the
   function at the root.
6. **The public host is always an allowed `Origin`**, proxied or not, like
   the project host.
7. **No caching.** Vercel caches external rewrites by default for projects
   created after 2026-04-06, honoring upstream `cache-control`.
   `x-vercel-enable-rewrite-caching: 0` on every path turns that off, as
   Vercel documents. A `Cache-Control: no-store` override would replace the
   function's own `no-cache, no-transform` on SSE responses, so the proxy
   leaves response headers alone. `mcp-smoke.sh` fails on
   `x-vercel-cache: HIT` for the metadata.
8. **`/.well-known` on Vercel.** The rewrites docs say the path "is reserved
   and cannot be redirected or rewritten" (next to an unrelated SSL
   sentence). Our app project rewrites `/.well-known/oauth-protected-resource`
   to its index.html today (checked with curl, 2026-10-28). That is a
   same-project rewrite, not an external one, so it shows the path is not
   blocked outright but does not prove an external rewrite of it; the rule
   ships as briefed and the Lead's smoke run settles it. If the live smoke test shows Vercel refuses it, the
   fix is one line in `proxied()` (handler.ts): advertise
   `https://mcp.hummlist.com/oauth-protected-resource`, a path the function
   already serves and the catch-all rewrite reaches. Clients follow the
   `resource_metadata` URL from the challenge, so they keep working.
9. **Smoke script.** `scripts/mcp-smoke.sh <MCP URL>` walks discovery as a
   client does: the 401 challenge, its metadata on the same host with
   `resource` equal to the URL, the authorization server's metadata (RFC
   8414 path-inserted first, then the issuer-relative paths), then
   `initialize` and `tools/list` with `MCP_SMOKE_TOKEN` or `SKIP` without.
   `smoke-remote.sh` runs it for the supabase.co URL after every deploy
   instead of its two older MCP checks. CI has no token, so the deploy
   smoke reports the tools check as `SKIP`.
10. **No build settings beyond `vercel.json`.** Empty `installCommand`,
    `buildCommand` and `outputDirectory` plus `"framework": null` skip
    every build step whatever the dashboard says. `npx vercel build` (no
    login) compiles it with status `ok` and only the routes; nothing static
    shadows them. `trailingSlash` is left unset: `false` adds a 308 for
    every path ending in `/`.
11. **The marker is the live signal** (checked on the hosted project after
    the deploy of #80, 2026-10-28). A request straight to
    `…supabase.co/functions/v1/mcp` with `x-forwarded-host: mcp.hummlist.com`
    still got the supabase.co `resource` and challenge: the hosted gateway
    replaces that header, as Kong does locally. The same request with
    `?via=mcp-hummlist` got `https://mcp.hummlist.com` in both. A foreign
    header or marker value got supabase.co, and a request with neither got
    exactly the values from before #80. The header check stays: it costs
    one line, is tested, and keeps working if a gateway ever passes the
    header through.
12. **The app shows `https://mcp.hummlist.com` only in production builds**
    (part B). `Environment.mcpUrl` stays one const: the public URL when
    `SUPABASE_URL` is the production project, else
    `<SUPABASE_URL>/functions/v1/mcp`. A build for the local stack therefore
    shows a URL that reaches its own function, and the e2e MCP spec asserts
    exactly that. The widget test runs with the production default and
    asserts the public URL. The screenshots come from a release web build
    with production defaults whose supabase.co requests Playwright answered
    from the local stack, so they show the real production value.
13. **`/.well-known` through Vercel works** (Lead: mcp.hummlist.com live,
    15:44). `scripts/mcp-smoke.sh https://mcp.hummlist.com` passed all four
    discovery checks, the root
    `https://mcp.hummlist.com/.well-known/oauth-protected-resource` included,
    so Vercel's "reserved" note does not cover this external rewrite and the
    item 8 fallback is not needed. Two fetches of the metadata both came
    back `x-vercel-cache: MISS`.

## Job 16 (design H, part 2: the list), 2026-10-28

The list between the header and the add bar is design H's: stores as
sections, one block per category in the store's walk order, rows in walk
order, drag and drop, folding, ticking with Undo. The code is in
`app/lib/list/list_view/`; the interfaces job 17 builds on are in
[`docs/design/h-satz-final/SPEC.md`](design/h-satz-final/SPEC.md), part 4.

1. **The store filter is gone.** H folds stores instead of filtering them.
   The chips ("Alle", one per store), `StoreFilter`, `AtStore`, the hidden
   items toggle and `groupActive` are removed. What they did is covered:
   - each store is a section in its own walk order, always;
   - its category order is editable inline (drag a category divider) and on
     the store layout screen, which opens from the store divider's menu
     (hold it without moving, or right click: "Reihenfolge bearbeiten");
   - the categories screen opens from the menu of the section without a
     store and from the app menu.
   Two behaviours went with the filter, because H has no "store I'm in":
   an add no longer takes the viewed store (job 17's add sheet has a store
   chip), and a tick no longer tags an untagged item to the viewed store.
   Item→store memory still learns from every store change: a drop on a
   store, a drop on a row in another store, the edit sheet's store chip,
   MCP. NEEDS_PETER.md asks whether he misses the chips.
2. **The per-store "carries this category" switches are gone from the
   store layout screen.** They only hid untagged items in a store view. In
   H an item without a store sits under "Ohne Laden" and a store shows
   every item tagged to it, so the switch would change nothing. The
   `hidden` values stay in the database and are saved back unchanged.
   Nothing else depends on them: in `supabase/` only `set_store_layout`,
   `apply_default_store_layouts` and the new-category placement in
   `20261022233800_classifier_stores.sql` write the column, and no function,
   MCP tool or voice path reads it. Older app builds (TestFlight, Play) still
   show store views with their switches; their data is untouched.
   Item→store memory doesn't use it either; review 0's failing re-add in
   `stores.spec.ts` was a test race (a re-add during the 260 ms tick
   animation finds the item still on the list), fixed in the `tick` helper.
3. **Every store is a section, also an empty one** ("Edeka, 0 Artikel", no
   rows), so it stays a place to drop an item and to reorder stores. The
   section without a store comes last and shows when it has items or while
   an item is dragged. It is at the end, so showing it moves nothing above
   the finger.
   Superseded by job 17b, 1 and 2: an empty store is hidden and shows only
   while an item is dragged.
4. **A drop on a store divider (folded or not) keeps the item's category**
   and puts it at the end of that category in the store (`move_item` with
   the store and the category). Every store walks every category: its
   layout rows first, the rest in route order, so the item always has its
   block there. An item still waiting for the server to classify it (an
   optimistic add, no category yet) can't be dragged until it has one.
5. **Category order per section.** In a store, a dragged category divider
   saves that store's layout (`set_store_layout`, the store layout screen's
   data, hidden flags unchanged). In "Ohne Laden" the order is the route
   order, so a drag there reorders the route (`reorder_categories`, the
   categories screen's data). While a category is dragged, its siblings
   fold to dividers; while a store is dragged, every store does.
6. **Offline: item moves queue, store and category orders don't.** An item
   drop is an `ItemOp` (`MoveItem`/`PlaceItem`, job 15), applied at once,
   kept in the offline snapshot and sent when the list is back online. A
   store or category reorder is a catalog write: offline it is refused with
   "Die Reihenfolge lässt sich nur mit Verbindung ändern." and nothing moves,
   instead of showing an order no one else sees. A catalog write that fails
   on the way (online at the start) is undone on screen and reported, then
   the catalog reloads. An item move the server refuses is dropped from the
   queue, reported, and the resync puts the item back.
7. **Fold state and the explainer card live on the device**
   (`ListPrefs`, DeviceCache key `listprefs.<user>.<household>`), kept and
   removed like the list snapshot. Folded ids of deleted stores are
   ignored when drawing. The prototype kept folds per tab
   (`sessionStorage`); Peter wants them kept.
8. **Row icons are emoji from the name, else the category.** The app has
   no item emoji. `itemIcon` matches word endings of the folded name against
   about 80 common groceries (so "Vollmilch" gets 🥛), and falls back to an
   emoji per seeded category, or the one a category name starts with. It is
   display only, on the device. The category divider drops a leading emoji
   from the name ("👶 Drogerie" reads DROGERIE, as H has no emoji on
   dividers); its semantics label keeps the full name.
9. **Accessibility.** A row is a button named by the item, then "Marke ·
   Eigenschaften", then the quantity (the order rows had since job 15), then
   "Neu" while unseen; tap ticks, long press
   edits (both as semantics actions). The store divider is a button
   "<store>, <n> Artikel" with its expanded state and a "Zuklappen" or
   "Aufklappen" hint. Non-drag alternatives: the edit sheet's store and
   category chips move an item; store and category dividers carry "nach
   oben" and "nach unten" as custom semantics actions and in their menu.
   Each column of the wide layout is its own semantics node, read before
   the next; sorted by position, a screen reader would mix the stores row
   by row.
10. **Wide layouts.** One `CustomScrollView`; from 840 px a
    `SliverCrossAxisGroup` holds two columns, from 1200 px three, each at
    most 560 px. The stores are cut into runs in household order (a store
    never splits) so that the tallest column is as short as possible
    (folded and empty stores count as one row). Reading order stays store
    by store, column by column. Between 600 and 840 px one column, centred,
    at most 640 px. Drag and drop works across columns; it is one list.
11. **Drag mechanics.** `LongPressDraggable` with a 300 ms hold; a hold that
    ends within 8 px edits (rows) or opens the menu (dividers), and the
    lifted pill only shows once the hold moves. The edge of the drop comes
    from the pointer against the hovered row's half height. Auto-scroll
    runs while the pointer is in the outer 8 % of the list, up to 14 px a
    frame. A lifted row is kept alive (`AutomaticKeepAlive`) and a
    `Listener` tracks the pointer and ends the session on pointer up:
    Flutter's `Draggable` only reports how a drag ended while its source
    is mounted, and auto-scroll can carry the source off screen.
12. **Kept from before H:** swipe left to delete with Undo
    (`dismiss-<id>`), "Zuletzt gekauft" with re-add (`bought-<id>`) at the
    end of the list, and job 8's tint and "Neu" on unseen partner rows.
    None conflicts with H (no glyph on rows), so nothing went to
    NEEDS_PETER for them.
13. **Small deviations.** "Verstanden" is 44 px tall, not 36, for the tap
    target rule. The category divider's hit area stays 32 px, the documented
    exception; a taller hit area would take the space of the rows next to it.
    A store name too long for a narrow column ends in an ellipsis rather than
    pushing the count out.

## Job web-release-align (web production follows the store release), 2026-10-29

Peter (2026-10-29 17:17): `app.hummlist.com` must not run ahead of the
stores, and `main` needs a Vercel-login-guarded preview on its own subdomain.

1. **Vercel's production branch is `release`; `release.yml` fast-forwards it.**
   Options weighed:
   - Production branch `release`, moved by the Release run with the
     workflow's `GITHUB_TOKEN` (chosen). No Vercel credential in GitHub (the
     repository is public), Vercel's own Git integration still builds and
     assigns production, `main` becomes an ordinary preview branch so the
     branch domain `preview.app.hummlist.com` can track it, and a plain push
     can only fast-forward, so production never moves backwards by accident.
     Cost: production is a second build of the same commit (about two
     minutes), not the preview's bytes.
   - Keep `main` as production branch, turn off auto-assignment of production
     domains and promote from `release.yml` with a Vercel token (rejected):
     needs a long-lived Vercel token in GitHub secrets, and Vercel refuses a
     branch domain on the production branch
     (`cannot_set_production_branch_as_preview`), so the preview subdomain
     could not follow `main`.
   - A deploy hook or `vercel deploy --prod` from CI (rejected): also a
     credential in GitHub, and a second deploy path next to the Git one.
2. **The preview is a branch domain, not a production alias.** Vercel
   Authentication on this project is Standard Protection
   (`all_except_custom_domains`): production custom domains stay public,
   everything else, branch domains included, asks for a Vercel login. The
   setting is unchanged.
3. **Web ships after any real store upload** (`Uploaded` job green), also an
   iOS-only run: the web app then matches the newest TestFlight build. A dry
   run or a skipped run leaves production alone.

## Job 27 (on-demand e2e on GitHub Actions), 2026-10-29

`scripts/ci-e2e.sh` dispatches `.github/workflows/e2e.yml`, which runs the
e2e gate (optionally one spec) and the db gate for a pushed branch, and
reports back (docs/CI.md, On-demand e2e). Peter wants Docker, Supabase and
Playwright off the Mac runner and the box.

1. **Shared through composite actions, not a reusable workflow.** A reusable
   workflow would turn ci.yml's `e2e` job into a `uses:` job. Its checks
   would then be named `e2e (1) / …`, `check-gates.sh`'s "the job runs
   scripts/gates/e2e.sh" rule would no longer hold, and it could not read
   ci.yml's `env` pins (a caller's `with:` has no `env` context), so the pins
   would be duplicated anyway. Three composite actions (`e2e-setup`,
   `e2e-report`, `db-setup`) hold the steps before and after the gate. Both
   workflows' jobs keep their names, their matrix and their own `run:
   scripts/gates/<gate>.sh` line. ci.yml's behavior is unchanged: same steps
   in the same order, same artifact names (`playwright-<shard>`), same
   `ci-ok` needs. The one addition is the job summary and a small
   `e2e-results-<shard>` artifact.
2. **What stays duplicated, and the guard.** Three pins and the job
   skeletons (checkout, the actions, the gate line). `check-gates.sh` fails
   when the pins differ, or when the `e2e` or `db` jobs of the two workflows
   use different actions, versions or action inputs, or when e2e.yml's no longer runs its
   gate. Tried by editing each: a Flutter pin, the registry, an extra step in
   ci.yml, a hard-coded version, a dropped report action, a dropped db gate.
3. **`e2e-report` passes `job.status` in** and gives its steps `always()`.
   A status function inside a composite action does not see the caller's
   failed steps reliably, and the failure logs must show after a failed gate.
4. **The run is found by a `request_id` input shown in `run-name:`.** Only
   recent gh versions print the new run's URL after `workflow run` (the box
   and the Mac need not have the same gh), and "the newest run on the
   branch" can be a neighbour's. The script polls `gh run list` for the run
   whose title ends in `[<id>]`.
5. **The summary comes from Playwright's JSON reporter** (on CI only,
   `e2e/playwright-results.json`), read by `scripts/e2e-summary.sh` (jq). It
   is also uploaded on its own (a few KB), so the script prints failed titles
   without downloading traces.
6. **The spec is split like shell words by `xargs`,** which honours quotes
   and runs nothing. An unbalanced quote stops the job instead of falling
   back to the full suite. Inputs reach the shell through `env:`, never
   `${{ }}` in the script.
7. **`FG_SYNC_SMOKE=1|0` in the e2e gate** overrides its "full run or shard
   1" rule for the `sync_smoke` input. Unset, the gate behaves as before. A
   bad value fails before the stack starts.
8. **A sharded spec run passes `--pass-with-no-tests`,** because a one-test
   spec leaves shard 2 empty. ci-e2e.sh then fails a passing run in which no
   test ran, so a typo in `--spec` still fails.
9. **e2e.yml and ci-e2e.sh alone count as documentation for
   ci-changes.sh,** because ci.yml runs neither. The always-on lint gate
   checks them (actionlint, shellcheck, check-gates). `.github/actions/` and
   `scripts/e2e-summary.sh` are part of ci.yml's e2e job, so they run
   everything.
10. **Proving it before main.** `gh workflow run e2e.yml` needs the workflow
    registered, which for a `workflow_dispatch`-only file happens on the
    default branch. A temporary `push: branches: [job/27-ci-e2e-on-demand]`
    trigger registered it with one push, which also ran the full suite. The
    next commit removed the trigger, and every later run was a real dispatch
    through `scripts/ci-e2e.sh` against this branch's e2e.yml. The
    deliberately failing spec (`e2e/tests/zz-job27-fail.spec.ts`) was only
    on the branch and was dropped before landing.
11. **No `supabase/seed.sql`; the seed is off** (lead, 2026-10-29 18:12: CI
    backends should have seed data; resolve the missing file). Since job 1,
    `config.toml` named `./seed.sql` with the seed enabled, but the file
    never existed, so every `supabase start` and `db reset` printed "no files
    matched pattern: supabase/seed.sql" and loaded nothing. The data a
    backend needs is already there without it. Reference data
    (categories, the classifier dictionary, default store layouts) is in
    migrations, so production has it too. Accounts, households, lists and
    stores come from the job-18 fixtures: `scripts/fg seed <scenario>`
    (test/fixtures/scenarios/) creates them through the Auth API in a known
    state, the db gate's fixtures test checks they seed, stay apart under
    RLS and tear down to zero rows, and e2e specs create their own users. A
    static seed.sql with test users would sit in every local and CI database
    outside that bookkeeping and could break the tests that expect a fresh
    database. So `[db.seed] enabled = false`, with a comment pointing to the
    fixtures. A seed file can come back later by adding it and flipping
    the switch (the verify skill's `stack.ts` already links one when it
    exists).

## Job 17 (design H, part 3: add sheet, app shell, English), 2026-10-29

The add bar and add sheet, the List and More tabs, the settings in More,
and English throughout. The code is in `app/lib/list/add_sheet/`,
`app/lib/list/list_screen.dart`, `app/lib/app/shell.dart` and
`app/lib/more/`; the suggestions come from `public.suggest_entries`.

1. **The rows come from the server.** `public.suggest_entries(household,
   text)` returns the parsed entry first, then up to 3 earlier purchases
   (any status, last year, name starting like the typed name, each with its
   own brand and details), other packs and other details
   seen on the same name before, Größe ±1, other brands (the household's
   own first, then `public.brands` for the product) and up to 3 dictionary
   words starting like the last typed word, deduplicated and cut at 8. The
   prototype invents packs and brands from a mock catalogue; the app has no
   product catalogue, so these rows come from what the household bought and
   the brand list. One function serves every client, like `parse_item`.
   Every row is at the store and in the category the list guesses for it
   now (`classify_item`, `guess_store`), not where an old purchase was:
   the memory already holds the latest tag, and a row tapped without a
   chip pick must not teach an old category or store back (review of
   9dc1304: an old "Milch, laktosefrei" in Getränke would have overruled a
   newer Kühlregal correction).
2. **Fetching.** The sheet asks 120 ms after the last keystroke and keeps
   the answer per text, so backspacing is instant. Until the answer for the
   new text arrives the previous rows stay (the first keystroke shows the
   text split on the device). Enter takes the first row for exactly what is
   typed: it waits up to 3 s for that answer, then falls back to the device
   split. Offline the rows are the device split plus the household's usuals
   that start like it.
3. **Labels.** The source labels are the prototype's (SPEC 2.7): "Schon
   mal gekauft", not the brief's "Zuletzt gekauft", which is already the
   name of job 16's bought section. Due usuals in the empty sheet are
   labelled "Wieder fällig". Alternatives already on the list are left out,
   as the old chips did; the typed row always stays and says "steht schon
   auf der Liste" when taken.
4. **A picked store or category is learned on insert.** The items trigger
   learned only from updates, so a store chip picked in the sheet would be
   forgotten. An AFTER INSERT statement trigger now records a correction
   when the row's category or store differs from the guess
   (`public.guess_store` repeats `parse_item`'s store rule: memory, then the
   brand's store, then the drugstore hint). A row that equals the guess
   teaches nothing, so only chip picks teach (decision 1). "Ohne Laden"
   picked on add is sent as the add plus an edit that clears the store,
   because the insert trigger fills a missing store from memory. Putting a
   deleted item back (the delete snackbar's Rückgängig, an insert of an id
   with a `deleted` event in the last day) teaches nothing: its store and
   category are history. Deleting an item within 10 minutes of the add
   that taught a memory row takes the lesson back
   (`items_unlearn_delete`): the add sheet's Rückgängig undoes the pick
   too. Each memory row keeps what the last insert did to it (`undo_item`,
   `undo_by`, `undo_prev_at`, `undo_at`, nullable columns); a row created
   by the add goes, an older one gets its count and `updated_at` back, and
   a row anything learned on since is left alone.
5. **Same item twice.** An add is refused as "steht schon auf der Liste"
   only when name, Marke and Eigenschaften all match an active item, as in
   `add_item`; Windeln Pampers Größe 3 and Windeln Pampers Größe 4 can both
   be on the list. Eigenschaften match in any order, folded like names.
   The device does not stem names (Gurke and Gurken are two entries on the
   device, one for `add_item`), as before this job: a German stemmer in
   Dart for a duplicate warning is not worth a second copy of
   `item_key`.
6. **Height.** The surface is `min(content, max)`, with max = the space
   above the add bar minus the safe top minus 28 px. Before anything is
   typed it is at most half the screen, bar and tabs included, so the
   first opening stays small; due usuals beyond that scroll. There is no
   other floor (Peter's override of the prototype's 50 % minimum).
7. **Motion.** Only the surface's size animates (`AnimatedSize`, 280 ms,
   `Easing.emphasizedDecelerate` growing, `emphasizedAccelerate` closing,
   0 with reduced motion). The content is laid out once at its own height,
   top-aligned and clipped while the surface catches up, so the rows never
   reflow per frame (the review's concern about animating height). While
   closing, the content keeps hanging from the surface's top edge and is
   dropped 40 ms after it settles. No spring: `AnimatedSize` takes a curve,
   and a spring would need a custom render object for a curve that looks
   the same at 280 ms.
8. **The input never moves.** It is the List tab's bottom bar, not part of
   the sheet. The shell's tab band keeps its height while the tabs slide
   away and shows the hint "Antippen fügt hinzu · ↵ nimmt den ersten
   Vorschlag" instead, so nothing above it shifts. From 840 px there is no
   tab band and no hint; the ↵ key cap on the first row says the same.
9. **The closed bar has no outlined pill.** SPEC 2.7 describes a 2 px
   primary pill, but the prototype draws it behind the sheet surface
   (`z-index: -1`), so it never shows; its screenshots have none, and the
   app follows the screenshots.
10. **Opening and closing.** A tap on the field or typing opens the sheet.
    On desktop and web the field is focused on open (as before) without
    opening the sheet, so the list stays visible until the first key;
    phones focus nothing until tapped, so no keyboard covers the list on
    launch. Escape, "Schließen" or a tap on the scrim closes the sheet and
    clears the field, as the prototype resets once the sheet has settled.
    The list behind an open sheet is out of focus order and semantics.
11. **Shell.** go_router `StatefulShellRoute.indexedStack` with two
    branches: `/` (List) and `/more`, `/more/privacy` and `/settings`
    (More). `/settings?section=account` keeps working inside the More tab.
    Login, welcome, consent and join stay outside; any other path, an
    unknown `/more/…` included, goes to the list. An invite link
    (`?invite=`) opens the join page from any path, `/settings` included,
    where it used to stay on settings. The `ListCubit` moved up
    into `ListScope` so More can manage categories and stores; the List tab
    has its own `ScaffoldMessenger`, so its snackbars float above the add
    bar.
12. **More.** Haushalt (invite, join, categories, a new "Läden" screen that
    orders the stores and opens each store's walking order), Zugänge and
    Konto (both open the existing settings page; Konto scrolled to its
    section, as `/settings?section=account` did), Abmelden, Sprache,
    Rechtliches and the version. Impressum opens hummlist.com/impressum
    (or /en/imprint): the page exists in `site/` (job 24a). Datenschutz has
    no text anywhere yet, so it opens an in-app page marked "Entwurf"
    (`privacyPolicyUrl` in `app/lib/app/guides.dart` switches it to a link).
    Lizenzen is `showLicensePage` with "Hummlist" and the version from
    `package_info_plus` (new dependency).
13. **Language.** The device's language picks German or English, German
    for anything else. Sprache (Wie Gerät, Deutsch, English) overrides it,
    applies at once and is stored on the device (`DeviceCache`, key
    `language`), read before the first frame and kept across sign-outs.
14. **English.** `app_en.arb` has every key of `app_de.arb`;
    `test/l10n/arb_parity_test.dart` checks keys, placeholders and that no
    English text equals the German one unless allow-listed. Seeded category
    names are data in German; `category_names.dart` shows a seeded category
    the household has not renamed under its name for the UI language
    ("Kühlregal" reads "Chilled"), everywhere the app names a category. The
    account deletion check also accepts DELETE, which the English dialog
    asks for. Server texts (MCP and voice answers, emails) stay German: out
    of scope.
15. **Wide layouts.** A `NavigationRail` from 840 px. The add bar and sheet
    keep to 640 px, centred like the one-column list (from 840 px the list
    has two or three columns and the sheet stays a centred 640 px sheet).
    More shows its list (360 px) beside the selected page from 840 px.
16. **Eight rows fit on 844 px.** The app's rows have one second line; the
    prototype's mock data adds "Standard Pack" and wraps to two. So
    "Windeln Pampers Größe 3" (8 rows) ends below the top gap on 390×844
    and reaches it on a 390×667 phone, where the rows then scroll. The e2e
    spec proves both.
17. **Dictation** is its own widget (`app/lib/list/dictation_button.dart`)
    in the add bar, so job 10 (voice paste) changes one file.

## Job 17b (hide stores with no items on the list), 2026-10-29

Peter, answering job 16's question: "we don't want to show stores that have
0 articles on the list." The code is `shownSections` and `withDropTargets`
in `app/lib/list/list_view/sections.dart`, used by
`shopping_list_view.dart`.

1. **What counts.** A section shows when it has active items, the same
   number its divider shows ("N Artikel"). Bought items never count: they
   leave the store section for "Zuletzt gekauft". A ticked item still
   counts during its 260 ms tick-out animation, because it is still active
   then. Its store hides in the same frame as the row, and undo brings
   both back. "Ohne Laden" follows the same rule; it already did.
2. **Drag and drop.** Once a dragged item moves past the 8 px slop, every
   store shows, an empty one as a folded divider "<Store>, 0 Artikel",
   and so does an empty "Ohne Laden". They show only after the move, not
   on lift: a hold that stays put opens the edit sheet, and the list should
   not jump for that. When the drag ends (drop, cancel, or a drop where it
   started), a store that is still empty hides again. A store whose last
   item moved out hides then too. While the item is in the air its own
   store still holds it, so it does not hide yet.
3. **The list moves when the empty stores show.** Dividers that show above
   the dragged row push it down. The row then scrolls the list back by that
   amount in the next frame, so it stays under the finger. While the
   empty stores show, the list's cache extent grows by 120 px per empty
   store. That keeps the lifted row laid out however far they push it
   (a kept-alive row outside the cache extent is not laid out and would
   report its old position). The list cannot scroll above its top, so at
   the very top of a short list the rows still move down by the dividers'
   height. That is on purpose, after review. A bottom spacer could make
   room to scroll, but it would scroll the dividers that just showed off
   the top of the screen: the user would see no new drop target exactly
   in the case they need one (a new household, every item in "Ohne
   Laden"). The finger has moved only 8 px by then. The dragged item
   follows the finger, and the divider under it is tinted as the drop
   target, so a drop there is visible before letting go.
4. **Store reordering** (dragging a store divider, or its menu) shows only
   the stores with items, folded. "Laden nach oben/unten" steps over the
   hidden ones: the store goes next to the visible neighbour. The empty
   stores keep their place among the others in the household order. Empty
   stores are reordered on More > Stores, which lists every store.
5. **Wide columns** are balanced over the stores with items only, and
   there are never more columns than such stores. One store with items
   reads as one centred 640 px column, not a single column across the
   screen (review). While
   an item is dragged, each empty section shows in the column of the
   section before it in household order, or in the first column if none
   comes before it. No store with items changes column under the finger.
   "Ohne Laden" comes last, so it joins the last column, as it did before.
6. **Every store empty:** no section shows, and the existing empty-list
   state shows (`shown.isEmpty`). Before, the check was a zero item total
   with no drag.
7. **Test drivers measure the target after the lift.** An empty store
   exists on screen only during a drag. The widget test `drag` helper, the
   e2e `holdAndDrop`/`dragItemToStore` (their `up` direction is asked once
   the item moves) and `fg drag` all look up the drop target once the item
   has moved past the slop, not before the press.

## Job 28 (WebAssembly web build, iOS Safari tap focus), 2026-10-29

1. **Every web build is `flutter build web --wasm`** (`scripts/vercel.sh`,
   `scripts/gates/web-prod.sh`, `scripts/gates/e2e.sh`, `fg sync`). One build
   holds both apps: `main.dart.wasm` (dart2wasm, skwasm renderer) and
   `main.dart.js` (dart2js, CanvasKit). `flutter_bootstrap.js` picks wasm
   where the browser has WasmGC and its engine is on Flutter's
   `wasmAllowList`, JS everywhere else; that is Flutter's own fallback, kept
   as is. Every dependency already compiles to wasm (the app uses
   `package:web` and `dart:js_interop` only; the build fails on `dart:html`
   or `package:js`). The web-prod gate fails if a build lacks either app or
   a build script drops `--wasm`. The boot retry in `flutter_bootstrap.js`
   covers the wasm files too (`boot.spec.ts`: `skwasm.js`, `main.dart.mjs`,
   `main.dart.wasm` failing once, `main.dart.wasm` failing for good).
2. **WebKit stays on JS: Flutter's default allow list, unchanged.** Flutter
   3.47 runs wasm only on Chromium (`wasmAllowList` blink on, webkit and
   gecko off). So Safari, and every iOS browser, still runs `main.dart.js`
   after this job, Peter's iPhone included. We could opt WebKit in with one
   line (`config: { wasmAllowList: { webkit: true } }` in
   `app/web/flutter_bootstrap.js`), but not safely on 3.47. Its loader checks
   only for WasmGC, so Safari 18.2 to 26.1 (WasmGC, plus the WebKit bug that
   keeps Flutter off Safari, flutter/flutter#154344) would take the wasm
   path with no fallback. Flutter 3.50 checks the features Safari 26.2 added
   and documents the opt-in for Safari 26.2+, and the Flutter team only now
   runs Safari wasm suites in CI (flutter/flutter#195347). Gating it
   ourselves would mean user-agent or Safari-version code, which Peter ruled
   out (no Safari-specific code). Measured in CI's WebKit (Linux, no GPU;
   runs 40939521469 and 40941887799): the wasm build drew frames about 3x
   faster while scrolling (mean 111-117 ms against 300-469 ms) and drew the
   list sooner (1087-1091 ms against 1698-1987 ms, median of three). **Follow-up:** after the Flutter upgrade to 3.50 or later, add
   the opt-in and rerun `scripts/ci-e2e.sh --spec tests/perf.spec.ts`.
3. **No cross-origin isolation (no COOP/COEP headers).** skwasm runs
   single-threaded. Isolated, it renders on a worker, but measured in
   Chromium (the only engine on wasm) it changed nothing beyond noise:
   scroll frames 17.7-19.0 ms mean against 17.8-20.0 ms, list drawn after
   793-876 ms against 806-956 ms (same two runs). The headers do change how the browser treats
   every cross-origin request. In the measurement, Chromium applied Local
   Network Access to the isolated page and blocked its Supabase calls until
   that check was switched off. COEP `credentialless` does not exist in
   Safari, and `require-corp` blocks cross-origin subresources without a
   CORP header: the Vercel toolbar on previews, third-party scripts like the
   planned analytics. COOP `same-origin` cuts `window.opener` for popup
   sign-in (Google and Apple use full-page redirects today, so a later popup
   flow would break silently). No measured gain for a real risk: revisit
   only with a number that shows one.
4. **`vercel.json` sets the content types of `.wasm` (`application/wasm`,
   which streaming compilation needs) and `.mjs` (`text/javascript`)**
   rather than relying on Vercel's defaults. `e2e/web-smoke.mjs` checks both
   on a deployment, and that Chromium loads `main.dart.wasm`.
5. **iOS Safari double tap: our first tap is clean.** No Safari-specific
   code (Peter). The `iphone` Playwright project (WebKit as an iPhone 15)
   logs every DOM focus change and `focus()`/`blur()` call around a tap on
   the add field. One tap moves the focus into the field's input natively,
   during the tap's `touchend`. Nothing blurs it or moves the focus later;
   the engine's `placeElement` calls `focus()` again on the input that is
   already focused, which is a no-op. So the first tap has what iOS needs to
   show the keyboard, and the two-tap open is Flutter's or Safari's. The
   upstream fix for fields that stop taking taps on iOS 27 after a caret
   drag (flutter/flutter#188781) is in our Flutter 3.47.8. A real keyboard
   cannot be checked from here: Playwright's WebKit has no soft keyboard, so
   the spec checks the focus events iOS keys the keyboard on.
   Playwright's iPhone profile leaves `navigator.platform` at the host's
   ("Linux x86_64"), and Flutter reads the OS from it, so the spec reports
   "iPhone" as Safari does. Otherwise Flutter takes the page for Linux and
   autofocuses the field.
6. **After a tapped suggestion: checked, unchanged.** The tap on a row or
   chip blurs the field's input, so the keyboard goes away. The field keeps
   Flutter's focus for the next item, and on its next semantics update the
   engine focuses the input again (`semantics/text_field.dart`, `update()`),
   outside the tap, so no keyboard. The next tap on the field calls
   `focus()` on the input from inside the tap (the engine's `click`
   listener), and iOS shows the keyboard for a tap that refocuses the
   focused element (WebKit's `elementDidRefocus` in
   `completeSyntheticClick`, bug 195824, r243044). One tap, then typing
   reaches the app (`iphone.spec.ts`). Our desktop-web refocus
   (`_refocusAfterTap`, DECISIONS 8.8) runs in phone browsers too, though
   8.8 says "mobile is untouched". Skipping it there was tried and changed
   nothing: the engine's own refocus came 137 ms after the tap instead of
   185 ms. So per Peter's rule the code stays as it was.
7. **Timings are opt-in.** `e2e/tests/perf.spec.ts` measures, per build,
   the time from navigation to the drawn list (three signed-in reloads) and
   the `requestAnimationFrame` intervals while the wheel scrolls a 200-item
   list down and back up, twice. It runs Chromium with wasm, wasm isolated
   and JS, and WebKit with JS and wasm. It takes 4-5 minutes, so it runs
   only when named (`--spec tests/perf.spec.ts`; `playwright.config.ts`
   filters the `@perf` tag otherwise). The job summary shows a table of its
   `PERF` lines. A CI runner has no GPU, so compare builds within one run,
   never with a phone.
8. **CI installs WebKit next to Chromium** (`.github/actions/e2e-setup`,
   apt dependencies only when a launch fails, like Chromium). Projects:
   `chromium` (every spec but the iPhone one), `iphone` (`iphone.spec.ts`)
   and `webkit` (the timings, as a desktop: the wheel does not scroll a
   mobile WebKit page). WebKit does not start on the Mac runner (no window
   server for the `agents` user), so WebKit runs on GitHub Actions only.

## Job 19 (kill-gate and LTV analytics, error tracking in PostHog EU), 2026-10-29

Overview and definitions: [ANALYTICS.md](ANALYTICS.md).

1. **No PostHog SDK; the app posts to PostHog's capture API itself.** The brief named
   posthog_flutter (and posthog-js on web). I built `Analytics` on a ~60-line `PostHogSink`
   (`POST https://eu.i.posthog.com/batch/`, the public endpoint the SDKs use) instead, because:
   (a) every byte then passes the allow-list (`checkEvent`, `checkContext`), while the native SDKs
   add their own device properties and posthog-js adds `$current_url`, `$pathname` and
   `$referrer`, which here carry invite codes (`/join/<code>`) and OAuth authorization ids;
   (b) posthog-js fetches remote config and feature flags (`/flags`, `config.js`) as soon as it
   starts, and project settings such as exception or web-vitals autocapture can switch features on
   from the server, so "nothing but our events" could not be guaranteed by client config;
   (c) "off stops at once, nothing queued" is exact with our in-memory queue, while the native SDKs
   keep their own disk queue; (d) one code path on iOS, Android and web, and e2e can answer the
   PostHog host with a fake collector, which tests the production sender itself. Cost: no native
   crash capture (out of the small scope) and an in-memory queue (a batch not sent before the app
   is killed is lost; flushed every 5 s, on hide and before sign-out). The `$exception_list` shape
   (type, value, mechanism, raw frames, `chunk_id`) copies posthog_flutter 5.58's, so PostHog's
   error tracking reads it the same way; the proofs show it does (11, 19).
2. **`first_open` is sent at the consent, once per install id** (Peter, 2026-10-27), with
   `household_id` null. Someone who declines and later switches analytics on under More sends it
   then: their install cohort starts at their first consented open. It is remembered in
   `DeviceCache` (`analytics.first_open` = the install id it went out for).
3. **Consent route.** `/analytics-consent`, gated in `authRedirect` (`askConsent`): signed in and
   undecided goes there first, with `?invite=` carried. After the answer: `NeedsHousehold` →
   `/welcome` (with the invite), `InHousehold` → the list, or `/join/<code>` with an invite. A
   `next=/oauth/consent…` flow is not interrupted. A build without a key (CI, fg, local debug)
   never asks: nothing could be sent, so asking would only mislead.
4. **The decision is per install, not per account.** `DeviceCache` keys `analytics.install_id`,
   `analytics.consent`, `analytics.first_open`, `analytics.internal` (shared preferences, the only
   store the lints allow) survive sign-out (`forget()` only drops the household, list, seen and
   prefs keys). On web a "device" is a browser profile: localStorage.
5. **Signed out, nothing is captured** (not even errors, so the login screen sends nothing).
   Sign-out first sends what waits (at most 2 s), then signs out; whatever is left is dropped.
6. **Off drops the queue instead of sending it**, also a batch that fails while the user switches
   off. "Stops sending at once" wins over the few seconds of events captured just before.
7. **One event per action.** Events fire in the cubit methods the UI calls for a user action, not
   in the op flush, so an offline tick sent on reconnect, a realtime echo or a resync sends
   nothing. Undo sends nothing and no compensating event (PostHog can't retract one; the tick was
   a real action); undo then tick again is a second `item_ticked`. A tick counts when the user
   makes it, even offline; in the rare case the server then refuses the op (the item was deleted
   by the partner meanwhile), the event stays: we measure user actions, and the refusal is shown
   to the user. Reorders count only once the server took them (they are not queued), and only
   when the order changed; hiding a category in a store is not a reorder.
8. **`source`** follows the PM's typed / spoken / suggestion: the add sheet's "Wie getippt" row
   (also Enter) is `typed`, any other row (history, pack, size, variant, brand, dictionary, due)
   and a re-add from recently bought are `suggestion`, in-app dictation is `spoken`. MCP and Siri
   adds and ticks are not sent (PM, 2026-10-25); no server-side consent flag, no migration.
9. **`invite_accepted` without a migration.** `join_household` returns the household id whether
   the user joined or was a member already, so `SessionCubit.join` compares it with the household
   it was in before: a different one is a new membership. `method` is `link` when the code came
   from `/join/<code>` or `?invite=` and was not edited (the welcome form, the join screen),
   `code` when typed (the welcome form, More's join dialog, which tells the join screen through
   go_router's `extra`).
10. **`actor_role` and `household_size`** come from the list's catalog; the members query now also
    reads `household_members.role` (`Member.role`, nullable for lists cached before). No actor
    key or per-member hash (PM).
11. **`is_internal`**: debug and profile builds, the internal device mark (a long press on the
    version under More, which also shows "Testfehler senden" for error-tracking checks), the
    households in `ANALYTICS_INTERNAL_HOUSEHOLDS`, and e-mail domains that can't belong to a
    customer: the reserved TLDs `.test`, `.invalid`, `.example`, `.localhost` and
    `example.com/.net/.org` (covers `fg.test`, `fg-test.invalid` and e2e's `example.test`), plus
    `ANALYTICS_INTERNAL_EMAIL_DOMAINS`. The queries drop every install and household that ever
    sent `is_internal = true`: a filter written into each query, because PostHog cohorts need
    person profiles and the app sends personless events.
12. **Retention periods are fixed 7 and 30 days from the household's first event**, so every
    cohort's month k has the same length; weeks 0-12 and months 0-11 (Peter, 2026-10-25: no
    export, PostHog only, a year).
13. **Edge-function exceptions are sent without a consent check.** They carry no user: the
    `distinct_id` is `edge-function-<name>`, the message is scrubbed to a code or runtime text,
    and the request (body, headers, token) is never read. No personal data, so no consent to ask
    for. Server events that do concern a person (purchases) need the install's consent.
14. **The edge functions need `POSTHOG_HOST` set explicitly** (only `https://eu.i.posthog.com`
    accepted), like the app: no host fallback in code.
15. **Source maps are uploaded from the Vercel build, not a GitHub Actions step.** Peter planned a
    GitHub secret, but the deployed `main.dart.js` is built by Vercel; the chunk ids
    `posthog-cli` injects must be in the files users load, so the upload has to happen in the same
    build. `scripts/vercel.sh` does it when `POSTHOG_PERSONAL_API_KEY` and `POSTHOG_PROJECT_ID`
    are set in the Vercel project, then deletes the maps from the deployment; a failed upload
    only leaves traces minified. No GitHub Actions step exists, so CI never talks to PostHog.
16. **Web wasm (job 28):** Chromium runs dart2wasm, whose frames carry Dart function names but no
    lines, and PostHog can't symbolicate wasm. The JS build (Safari, Firefox) maps back to Dart
    through the uploaded source map. Common error types are named in code, because dart2js
    minifies `runtimeType` (`minified:hm`).
17. **Purchases: interface, mapping and events, no real verification** (PM: AC6 and AC8 partial
    until the IAP job). `PurchaseVerifier` with `FakePurchaseVerifier`, `fromApple`/`fromGoogle`
    from the stores' payload shapes, `netAmount`, `recordPurchase`, tested with fixture payloads.
    The JWS chain check against Apple Root CA - G3 and its self-made test chain belong with the
    real verifier in the IAP job; ANALYTICS.md "Purchases" has the design.
18. **e2e**: the e2e build gets a stand-in key and `https://posthog.invalid` (`app/config/e2e.json`),
    which can never reach PostHog even unanswered; `fakeCollector` answers it and fails on any
    request to a real PostHog host. `signUp` answers the consent (declined unless asked), every
    other first sign-in in a fresh context calls `answerConsent`, so the sign-in → consent →
    onboarding order runs in every spec. `no_posthog_in_ci` (lib.sh) fails a CI build that has a
    key, and checks the stand-in and that `config/auth.json` names no PostHog define.
19. **Proofs used the personal key that turned up in `~/groceries-ops/env`.** The brief expected no
    PostHog API access. The key (error tracking scope) reads the error-tracking issue list and
    uploads symbol sets; it can't run queries (`query:read` is missing). I used it only to upload
    one source map for the AC11 build and to list the issues. In project 319492 that created, all
    internal: 3 error-tracking issues (`StateError` "Hummlist test error", `TypeError` "Job 19
    forced test exception (edge function voice)", `Error` "23505"), 1 symbol set and the release
    `hummlist-web@job19-proof`, plus 2 events (`first_open`, `$exception`) from a fake user
    `proof-ac11@fg.test`. Nothing else was created or changed.
20. **Focus after the consent: the consent page is one list, like the welcome page.** With the
    answers pinned below a scrolling text (a `Column` with an `Expanded` scroll view), the list
    opened from it lost the add field's browser focus on the web, also on the iPhone after the
    first tap (Chromium wasm and JS, WebKit). A stack trace on a profile build showed why: in the
    semantics update that brings the list, the web engine moves the field's DOM element, which
    blurs and refocuses it; the blur queues the engine's deferred `safeBlur`
    (`SemanticsTextEditingStrategy.disable`), which then runs on the refocused input and hands
    the focus to the Flutter view. Login → list and welcome → list don't move the element, and
    neither does the consent page once it is a single `ListView` (title, text, draft chip, the
    two equal buttons; checked 3 of 3 on a local wasm build with Supabase faked by routes). An
    earlier repair in the list screen (refocusing when the browser lost it) was removed: it
    treated the symptom, and on the iPhone a focus outside the tap opens no keyboard. The page
    also got an app bar title ("Nutzungsdaten") so a new page starts on a heading for screen
    readers instead of the sign-out button.
21. **Review fixes (self-review before the Sonnet review).** A flush waits for a send already on
    its way (sign-out used to drop what was queued meanwhile); on the web the batch is sent with
    `fetch(keepalive)`, so a batch sent as the tab is hidden or closed still arrives; a frame's
    `chunk_id` matches its file name exactly (`main.dart.js` is not `main.dart.js_1.part.js`);
    Vercel deployments other than production build with `ANALYTICS_INTERNAL_BUILD=true` (preview
    testers are ours); `first_open` is claimed in memory before the write (a double tap sent two);
    `household_created` and `invite_accepted` are tracked with the household the RPC returned,
    before the reload, so a failed reload doesn't lose them. Kept as is: the consent hop sends an
    already signed-in user to the list rather than back to e.g. `/more` (login behaves the same).

## Job 29c (swipe left edits instead of deleting), 2026-10-30

Peter, 2026-10-29: "replace delete with edit in the swipe-left action. Tap
and hold doesn't work on mobile browser, that always triggers the move
action." The code is `ItemRow` in `app/lib/list/list_view/item_row.dart`.

1. **The swipe edits.** A swipe to the left past 40 % of the row (or a
   fling) calls `onEdit`, the same edit sheet a right click or a still hold
   opens. `Dismissible.confirmDismiss` returns false, so the row springs
   back and stays where it was; the swipe writes nothing. The background
   under the swipe is the secondary container with a pencil, no longer the
   error colour with a bin. Rows still being sorted (no category yet) swipe
   the same way. `shopping_list_view.dart` is unchanged (29b and 19 change
   it): the row already had `onEdit`.
2. **Delete lives in the edit sheet.** Its Löschen deletes with the undo
   snackbar, as since job 15. One tap more than the old swipe, and no
   accidental deletes from a swipe meant to scroll. Screen readers also get
   "Bearbeiten" and "Löschen" as custom actions on the row (the strings
   `editSheet` and `delete` already existed, so no l10n change); that is
   what keeps `onDelete` on the row.
3. **No item action needs a hold.** Tick: a tap. Edit: the swipe, a right
   click, or a hold that stays put. Delete: the sheet's Löschen. Move to
   another category or store: the sheet's chips. Only reordering within a
   category (or dropping on a particular row) is a hold and drag, as a
   drag has to start somewhere; the chips put the item at the end of its
   new category, which covers moving it.
4. **Why a hold became a move on a phone's browser.** A lifted item counted
   as moving once the finger had travelled 8 px in total, for as long as it
   was held. Nothing shows on lift (the pill appears only once it moves, so
   a hold that edits shows nothing lifted), so a finger waits and drifts,
   and 8 px is below Flutter's own touch slop (`kTouchSlop`, 18 px).
   Now a touch, stylus or unknown pointer gets 18 px, a mouse keeps 8 px
   (`holdSlop` in `drag.dart`). Store and category dividers use it too:
   their menus open on a hold that stays put, and the same drift turned
   those into drags.
   This is the likely cause, not a proven one: no real phone here. The
   e2e specs hold a finger still for 700 ms, drift 12 px and expect the
   sheet, in Chrome as an Android phone (real touch events over CDP,
   `edit-sheet.spec.ts`) and in WebKit as an iPhone (Safari's touch
   pointer events, `iphone.spec.ts`). Whatever the cause, the swipe no
   longer depends on a hold.
5. **Tests.** Widget tests in `app/test/list/list_screen_test.dart`: swipe
   opens the sheet and the row stays, a short swipe springs back, delete
   from a swiped-open sheet with undo, a row still being sorted, every
   action without a hold, a drifting finger edits where a mouse drags, and
   the screen-reader actions, and a drifting finger on a store and a
   category divider opens the menu. Drags in the tests now move 24 px
   (past the touch slop) before they count as drags.
6. **The explainer card names the swipe.** It read "Halten bearbeitet",
   pointing phone users at the gesture that failed for them. Now "Tippen
   hakt ab · Nach links wischen bearbeitet · Halten und ziehen verschiebt"
   (English "Swipe left edits"). That is the one l10n change of this job:
   the value of `listHint` in both ARB files, no new key.
7. **A mouse swipe faster than 200 ms ticks on web.** Flutter web holds a
   press on a tappable semantics node back for 200 ms (its click
   debouncer, `pointer_binding.dart`). If the button comes back up within
   that time, the browser's `click` reaches the engine while it is still
   holding the events back. The engine then sends the row a semantic tap
   and drops the drag, so the item ticks. A finger swipe produces no click
   and is unaffected; a mouse drag at a hand's pace takes longer than
   200 ms. It was the same for the old swipe-to-delete. The app never sees
   the dropped drag, so it can't tell the difference; the e2e mouse swipe
   moves at a hand's pace (seen on CI when the whole drag ran in under
   200 ms under load).

## Job 30 (every green merge to the internal testers), 2026-10-30

Peter (2026-10-29 22:05): "internal testing / test flight should be pushed on
every merge to main. Only public releases should be published after thorough
end to end testing weekly (or multiple times a week when the system is
efficient and high quality)." Tester Max still had the old design because
only the Monday schedule uploaded. `docs/RELEASE.md` describes the result.

1. **Trigger: `workflow_run` on CI, green push runs on `main` only.** The
   plan job's `if` requires `conclusion == 'success'`, `event == 'push'` and
   the head repository to be this one, so a red CI, a dispatched CI run and
   a fork PR from a branch named `main` (which `branches: [main]` alone lets
   through) leave every job skipped, `report` included. Options weighed:
   - `push` on `main` with a job that waits for `ci-ok` (rejected): a runner
     polling for 20 minutes per merge, and a second definition of "green".
   - `workflow_run` and also running the plan after a red CI to ship an
     older green commit (rejected): the brief wants no run after a red CI,
     and the next green merge, or a green rerun of the red one (also a
     `workflow_run` event), ships anyway.
2. **A run ships the newest green `main` commit, not the commit that started
   it.** `gather` fetches `main` and walks it from the tip to the last
   upload; the first commit whose newest push CI run is green ships, newer
   ones still running are left to their own run, red ones never ship. This
   is what makes merge bursts safe: GitHub keeps one pending run per
   concurrency group and cancels the older pending one, in arrival order,
   which is CI completion order, not commit order. With "ship the trigger"
   a late older commit's run could cancel the newer one's pending run and
   ship the older commit last. Now every surviving run ships everything
   green so far, and a run whose commit is older than the last upload skips
   and says so. Rejected: skipping while a newer commit's CI still runs (one
   upload per burst instead of one or two), because if that newer commit
   then goes red, no run ever ships the green ones before it.
3. **The last upload's commit is in the `Uploaded` job's name**
   (`Uploaded <sha>`). A `workflow_run` run's `head_sha` is `main`'s tip when
   the run was created, which may be newer than what it shipped. Rejected:
   tags or a branch (needs `contents: write` on every run), artifacts (expire,
   one download per run). Older runs' `Uploaded` jobs still count, with their
   `head_sha`, which for a dispatch is the shipped commit.
4. **A dispatch keeps its meaning** (ship the tip it was started on if green;
   `force`, `upload=false`, `platform`, `simulate_failure` as before) with one
   fix the new trigger made necessary: a dispatch that waited in the queue
   while an automatic run shipped a newer commit now finds no candidates and
   skips, instead of uploading the older commit with a higher build number.
5. **No build when the app did not change.** If nothing under `app/` or in
   `release.yml` changed between the last upload and the newest green commit
   (docs, CI, scripts, backend, site), the run skips: the testers would get a
   byte-identical app and a TestFlight notification for nothing. The expiry
   rules (no installable TestFlight build, last upload 60 days old) and
   `force` still ship. Backend changes reach every app through Supabase
   without a store build.
6. **The Monday schedule stays as a catch-up**, deciding like an automatic
   run: it uploads only for the expiry rules or a green commit whose
   `workflow_run` run never came (for example while the workflow was
   disabled for inactivity, which `ci.yml`'s `keepalive-schedule` undoes on
   the next push).
7. **`app.hummlist.com` moves only with a dispatch.** Since web-release-align
   the `Web production` job fast-forwarded `release` after every upload.
   With an upload per merge that would make the public web app follow
   `main` within the hour, which is what `preview.app.hummlist.com` is for,
   and Peter wants public releases to come after thorough end-to-end testing.
   So the automatic runs reach the internal testers only, and a dispatched
   run (the manual gate for now) still moves the web app. The rule from
   web-release-align holds: the web app never runs ahead of the stores. If
   Peter wants the web app on every merge too, the job's `if` loses
   `github.event_name == 'workflow_dispatch'`.
8. **No public store release path.** No production track, no App Store review
   submission, no external TestFlight group; the Paid Applications agreement
   stays unaccepted. `RELEASE.md`, "Public releases", says that this is a
   separate, later, manually gated step after a full e2e pass.
9. **One failure issue, renamed "Internal release failed".** Automatic runs
   (`workflow_run`, `schedule`) open it or comment on the open one, so a day
   of merges with a broken pipeline is one issue. A run that uploads, or
   finds the testers on the newest green `main` (plan output `current`,
   replacing the match on the reason text), closes it. Dispatches still
   leave it alone unless `simulate_failure`. The old issue (#53, "Weekly
   release failed") is closed; nothing renames it.
10. **Build numbers.** `offset + run number` stays. The run number counts
    every run of the workflow whatever its event, skipped and cancelled
    pending runs included, and with rule 2 and the dispatch fix in 4 a newer
    run never ships an older commit, so build number and commit rise
    together on both stores. A rerun keeps its run number, so `RELEASE.md`
    now says to rerun failed jobs only on the newest run.
11. **Release notes unchanged.** `notes.sh` lists the PR titles from the last
    upload to the shipped commit, which for a per-merge run is usually the
    one merged PR.

## Job 29b (no undo snackbar on a tick, "Zuletzt verwendet" with the list's row), 2026-10-30

Peter, 2026-10-29 20:49: "remove the 'undo' snackbar. If someone wants to
undo a checked off item, they can click on it in the 'recently bought'
section to bring it back. Let's also rename to 'recently used'." 20:50:
"for the 'recently used' section let's use the same element with icon as in
the normal list."

1. **A tick shows nothing.** `_tick` in `shopping_list_view.dart` only ticks;
   the row's own leave animation (fill, strike line, 260 ms) is the
   feedback. The string `itemTicked` ("{name} abgehakt") is gone from both
   ARBs, as nothing shows it. The edit sheet's delete keeps its snackbar with
   "Rückgängig" (Peter's words are about the tick), and so does the add
   sheet's note.
2. **"Zuletzt verwendet" / "Recently used".** The ARB key is now
   `recentlyUsed`, `recentlyBought()` in `model.dart` is `recentlyUsed()`,
   the section's key `recently-used`, a row's key `used-<id>`. "Verwendet"
   because Peter said "used"; the German follows the app's style of short
   plain labels ("Zuletzt gekauft" before). The MCP `tick_items` description
   and the docs say the new name too. The database keeps `bought`.
3. **The list's own row.** Each item there is an `ItemRow`, the same widget
   as the list (icon from `itemIcon` with the item's category, quantity,
   brand and details, the same rules between rows), wrapped in
   `shopping_list_view.dart` so `item_row.dart` (29c's) is unchanged:
   `Opacity(0.55)` marks it as used, `IgnorePointer` turns off the row's
   own gestures (its tap would tick, its swipe and hold edit, its hold and
   drag move, its DragTarget take drops), and a `GestureDetector` over it
   puts the item back on a tap. A still hold is a tap there too (only a tap
   recognizer is in the arena), which also puts it back; a swipe or right
   click does nothing. The old trailing "+" button is gone: the whole row is
   the button, as on the list.
4. **Screen readers.** The used row's own semantics are excluded (they offer
   tick, edit and delete). It is one button labelled like a list row plus
   "Wieder auf die Liste" (`readd`), e.g. "Bananen, 2, Wieder auf die
   Liste", whose tap puts it back. The action is part of the label, not a
   hint, so a list row and its used row never share a name: e2e's `itemRow`
   skips names ending in it, `usedRow` finds them.
5. **Putting back confirms with "<name> steht wieder auf der Liste"**, the
   plain snackbar from before (no action). The item can come back far above
   the section, off screen, so the line says it happened.
6. **The put-back within 10 minutes of the tick is the tick's undo for
   analytics.** `ListCubit.readd` sends `item_added` (source `suggestion`)
   only when the item's `bought_at` is more than `ListCubit.undoWindow` (10
   minutes) ago. That is the window in which `suggest_items` already treats a
   restore as the undo, not a purchase, and it keeps the rule "undo sends
   nothing" now that this tap is the only undo. It goes by `bought_at`, so a
   partner's tick put back right away counts the same. `untick` stays for
   callers that undo without asking.
7. **pstack skills.** `~/.claude/skills` (poteto-mode, pstack) does not exist
   for the Mac runner's user, so the job followed the brief directly: a
   widget or unit test for each behavior, then the real web build on CI
   (Playwright) for the proof and the screenshots.

## Job 29d (More: Zugänge and Konto on separate pages), 2026-10-30

Peter: "In 'More' access and account lead to the same page. Split them up."

1. **What each page holds.** Zugänge (`/more/access`, `AccessScreen`) keeps
   what the shared page had above its Konto section: the MCP server, the
   personal access tokens and the connected apps. Konto (`/more/account`,
   `AccountScreen`) holds the signed-in email address, "Meine Daten
   exportieren" and "Konto löschen". The brief glossed access as "household
   members/sharing"; in this app those live in More's Haushalt section
   (invite, join), and Zugänge has always meant ways in for other apps, so
   the split follows the page that existed. Abmelden stays a row of More's
   Konto section (one tap, and every recipe and spec uses it there).
2. **The email on Konto.** A page called Konto with only two actions did not
   say whose account it is. `AccountRepository.email` (the Supabase user's
   email) feeds a read-only row (`account-email`), left out for a sign-in
   without an email. No new UI text, so no ARB change in 29b's files.
3. **Routes below `/more`.** Both are child routes of `/more`, like
   `/more/privacy`, so the app bar's back arrow and the system back pop to
   the More list, also after a deep link (go_router builds `/more` beneath
   it). That removes the `PopScope` + `go(morePath)` workaround the
   top-level `/settings` route needed, and `fg back` no longer closes the
   Linux app on these pages. From 840 px the two-pane More hides the back
   arrow: beside the list there is nothing to go back to.
4. **Old links redirect.** `/settings` goes to `/more/access`,
   `/settings?section=account` to `/more/account` (route-level redirect,
   `legacySettingsRedirect`). `authRedirect` still runs first, so an invite
   on an old link (`/settings?invite=…`) still opens the join page and a
   signed-out user still gets the login. Keys are unchanged (`more-access`,
   `menu-account`, `account-export`, `account-delete`); new ones are
   `access-screen`, `account-screen`, `account-email`.
5. **One route table.** `moreTabRoutes()` in `router.dart` is the More
   branch for `buildRouter` and for the widget-test harness
   (`test/more/more_harness.dart`), which used to copy the routes by hand
   and could drift from the app.
6. **The scroll-to-section code goes.** `showAccount`, the `GlobalKey` and
   the listener that re-scrolled when tokens loaded only existed to land on
   the Konto section of the shared page. Zugänge is a lazy `ListView` again.

## Job 21 (in-app feedback for beta testers, Spec #2), 2026-10-30

Overview: [FEEDBACK.md](FEEDBACK.md). Peter's decisions of 2026-10-27, which close the spec's
open questions 1-5:

- **D1. No notification of any kind** on new feedback: no e-mail digest, push, Slack or function
  that sends anything. The PM reads the table every Monday (FEEDBACK.md, "Monday summary").
- **D2. No shake-to-open and no long press on a title.** Mehr → "Feedback senden" is the only
  entry point; spec AC13 does not apply. `entry_point` stays an enum (`settings`) for later.
- **D3. No screenshots**, now or as a hidden option: the typed note and the context fields only.
- **D4. Feedback ships in the public release (DACH)**, not only in beta builds; no flag.
- **D5. Rows are deleted 12 months after `created_at`** by a scheduled cleanup in the database.

The job's own calls:

1. **A direct insert, not an RPC.** RLS policy `feedback_insert_own` (`user_id = auth.uid()` and
   the household, if any, the caller's own), a column grant without `created_at` and
   `household_id`, and a `before insert` trigger that sets `household_id` from
   `household_members`, `created_at`, the trimmed message, and `is_internal` for test accounts.
   With a direct insert the spec's AC5 holds literally (own insert yes, another `user_id` refused,
   select/update/delete refused, anon refused), which an RPC could only imitate. The insert policy
   calls `is_household_member(household_id)`, which is also what the schema check asks of a
   table with `household_id`.
2. **Idempotency in the trigger.** A repeat of the signed-in sender's own id is skipped (the
   trigger returns null: no error, no second row, nothing read back). Someone else's id fails on
   the primary key (23505). Two requests with one id in flight at once: the second waits on the
   key and gets 23505; the app then sends once more, which the trigger skips. A second 23505 is a
   foreign id (practically impossible with v4 UUIDs): the app takes a new id and offers Retry.
   PostgREST's upsert was not an option: it needs a select or update policy.
3. **"Empty" and "2,000 characters" mean the same in the app and the database.** Postgres'
   `btrim` strips only spaces, Dart's `trim()` all Unicode white space, and Dart's `length`
   counts UTF-16 units while `char_length` counts code points. `public.feedback_trim` strips
   Dart's white-space set, the check is `char_length(feedback_trim(message)) between 1 and 2000`,
   and the app counts `trim().runes`. So `'\n\t '` is empty for both, and 2,000 emoji are 2,000
   characters for both (pgTAP and widget tests).
4. **No hard input limit; the counter shows from 1,800 characters** ("1950 / 2000"), and over
   2,000 the field says "Höchstens 2000 Zeichen" and Send is disabled. A pasted long text stays
   editable instead of being cut silently.
5. **The note survives closing the form.** `FeedbackCubit` lives in the app (like the language),
   so a sheet swiped away after a failure, or by accident, comes back with the text, the category,
   the checkbox and the same id; a Retry later is still one row. It starts blank after a send
   and when another account opens it. Changing the note after a failed send gives it a new id: if
   the first try did arrive, the corrected text is not dropped as its repeat (the PM may then see
   both versions, which is honest).
6. **Screen name** (the spec's engineering Q6, the lead's rule). `screenNameOf` and
   `screenNames` in `app/lib/app/router.dart` (route literals may only live there, lint rule
   `auth-navigation-only-in-router`) map a router location to a fixed name: `list`, `more`,
   `privacy`, `access`, `account`, `login`, `welcome`, `analytics_consent`,
   `oauth_consent`, `join` (never the code), `other`. `ScreenTracker` (`app/lib/feedback/`)
   follows the router delegate. Since More is the only entry, `screen` is the last screen before
   the More tab (`list` from the list, AC3's "opened from the list stores list"); More's own pages
   in between do not count; when the form opens beside a More page (wide layouts, where More's
   list stays next to the page), that page's name (`account`, `access`; an old `/settings` link redirects and maps to the same). Job 29d moved Zugänge and Konto to `/more/access` and `/more/account` while this job was open; the names follow the routes. Categories and stores
   are pages pushed above `/more`, and sheets (add, edit) are not routes: they report the route
   under them. A reload straight on `/more` reports `more` (the app reads the first location after the first frame too, since the router may set it before the tracker listens; found by the review). No `name:` was added to the GoRoutes
   and no NavigatorObserver: the map keys on paths the router already has.
7. **Context fields.** App version and build from package_info_plus (the source of More's
   version line), the build `none` where a platform has none. OS version from device_info_plus
   (new dependency): `Android 14 (SDK 34)`, `iOS 18.1`, `macOS 15.1`, Linux's pretty name,
   Windows' product name; on the web only `<browser family> on <OS>` parsed from the user agent
   (`webOsVersion`), never the user agent itself. Locale is the app's language (`de`/`en`), not
   the device's list. Each value is cleaned of control characters and capped as the database
   checks it. The device model is not sent.
8. **`is_internal`** comes from 19's `isInternal` (new `Analytics.internalNow`, which works with
   or without consent and without a PostHog key, since feedback is stored either way). The
   database adds the reserved test domains from `internal.dart` (`.test`, `.invalid`,
   `.example`, `.localhost`, `example.com/.net/.org`: `fg.test`, `fg-test.invalid`, e2e's
   `example.test`), so a client can't mark those external. Peter's household is internal through
   the `ANALYTICS_INTERNAL_HOUSEHOLDS` define (NEEDS_PETER Job 19); the database does not know
   his household id, so a build without that define reports his notes as external until he sets
   it (NEEDS_PETER Job 21).
9. **The event `feedback_submitted`** goes through 19's `Analytics.track` only after the insert
   succeeded, once per note id (the cubit remembers ids it tracked), with `category` (`none` when
   unpicked), `entry_point`, `screen` (a `OneOf(screenNames)` rule, so no free text) and
   `contact_ok`. Without consent nothing is sent and the row is stored.
10. **Confirmation**: the sheet closes and a snackbar says "Danke!"; there is nothing else to do
    on the form. **Failure**: "Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal."
    under the form, Send becomes "Erneut senden". Nothing is queued or sent later; job 8's
    offline op queue is not used (it is for list items, and a note must not go out unseen).
    A send without an answer within 15 s counts as failed.
11. **Place in More**: its own section "Feedback" after Konto/Abmelden and before Sprache, with
    the hint "Fehler, Ideen und Fragen an Peter", so testers find it without scrolling far.
12. **Retention with pg_cron.** `create extension if not exists pg_cron with schema pg_catalog`
    (Supabase's documented form, free tier) and `cron.schedule('purge-old-feedback',
    '17 3 * * *', 'select public.purge_old_feedback()')`; the same name replaces the job, so a
    second apply keeps one (pgTAP). `purge_old_feedback()` is security definer, revoked from
    anon and authenticated, and returns the count. No keepalive fallback was needed: pg_cron
    runs on the local stack (CI's db gate) and is available on the hosted free tier.
13. **Data export**: the user's own notes are their data (GDPR Art. 15), so `export_my_data`
    gained a `feedback` section (all columns but `user_id`); additions keep version 1.
14. **Monday summary**: "the last 7 days (Europe/Berlin week)" is the previous full calendar
    week in Berlin time, Monday 00:00 to Monday 00:00, so Mondays never overlap or miss a note.
    No view or function: two plain queries (notes, counts) and a contact lookup.
    `scripts/feedback-monday.sh` (db gate) runs them straight from FEEDBACK.md on fake notes
    around the week's edges and checks the result, so the doc and the SQL can't drift.
15. **Account deletion** needs no change in `delete_account`: `user_id ... on delete cascade`
    removes the notes with the user (spec engineering Q7), `household_id ... on delete set null`
    keeps other people's notes when a household goes. pgTAP covers the household-kept and
    household-deleted paths and a former member's note, e2e the app's deletion.

## Job 29e (Einstellungen: theme and a scalable language list), 2026-10-30

Peter (2026-10-29): "the language selector isn't scalable once we add many
languages. Move it a settings submenu and make it more scalable like a
dropdown or another pattern if one is nicer than that. Also add a menu where
we can put the light/dark/system mode switch and add dark+light mode."

1. **One Einstellungen page under More** (`/more/settings`, row
   `more-settings` where the Sprache section was). It holds what belongs to
   the device rather than the account: Darstellung and Sprache. Zugänge and
   Konto stay their own pages (job 29d); Nutzungsdaten stays on More, since
   job 19's recipes and specs find it there and it is a consent, not a
   preference.
2. **Language: a list page, not a dropdown.** `/more/settings/language`
   lists "Wie Gerät" first (its line names what the device gives now,
   "Gerade Deutsch") and then every `AppLanguage` in its own name, as radio
   rows. Against a dropdown: a menu hides the options until opened, shows
   few at a time on a phone and is clumsy with a screen reader; a list page
   takes any number of languages, shows the pick at a glance and is the
   pattern iOS and Android settings use. Segments (the old control) stop
   fitting at four. No search field yet: with two languages it is noise;
   add one above the list when it no longer fits a screen (about 12). The
   Sprache row on Einstellungen names the pick, so the page is one tap away
   only when changing it. A pick applies at once and the page stays open,
   so the change is seen where it was made.
3. **Language names live in `AppLanguage`, not the ARB files.** A language
   is shown in its own name in every UI language (`nativeName`), so the
   ARB keys `languageGerman`/`languageEnglish` went: every new ARB would
   have had to repeat every name unchanged. A new language is now one enum
   value plus its `app_<code>.arb`.
4. **Theme: Wie Gerät / Hell / Dunkel as radio rows**, default Wie Gerät,
   stored per device in `DeviceCache` (key `theme`, `light` or `dark`,
   absent = device; kept across sign-out like the language) and read before
   the first frame in `main.dart`, so a dark pick never starts light.
   `ThemeCubit` in `app/lib/app/theme.dart`.
5. **The dark theme is design H's own scheme in dark.** Design SPEC 2 makes
   every colour a `ColorScheme` role of the seed 0xFF2E7D32's tonal-spot
   scheme, so `appTheme(Brightness.dark)` from the same seed is the design
   in dark; no second token set to drift. The light and dark `ThemeData` are
   built once in `App`. `test/app/theme_test.dart` checks WCAG AA for every
   text role pair the app uses (surface, sheets, dialogs, snackbars,
   containers, error) and 3:1 for outlines in both themes.
6. **Store colours on dark.** The fixed store colours are the one exception
   to roles (design SPEC 2.9). Aldi's navy (#00005F) and Edeka's blue on a
   near-black surface fall below 3:1, so the divider rule would vanish.
   `storeTint(store, surface)` now mixes the brand colour toward white (on
   dark) or black (on light) in 5 % steps until it reaches 3:1 (WCAG
   1.4.11); a colour that already reads stays the brand colour (all of
   them on light). The badge's 8 % black ring is invisible on dark, so the
   dark theme rings badges in white at 20 %. The badges' own colours stay:
   they are the chains' logos.
7. **The web page behind the app follows the device** (`<meta
   name="color-scheme" content="light dark">` in `web/index.html`), so a
   dark device does not flash white before Flutter's first frame. A user
   who picked Hell on a dark device sees a dark blank for that moment; the
   pick is in the app's storage, which the page cannot read before Flutter
   starts.
8. **`accountDeleteExportHint`** said the export was "in den Einstellungen";
   since job 29d it is on Konto, so it says "unter Konto" / "under Account".
9. **The iOS launch screen follows the device too.** Its background was a
   fixed white, so a dark iPhone flashed white before the first frame. It
   is now `systemBackgroundColor` (white on light, black on dark), compiled
   by the CI `ios` gate. Android's launch theme already had a
   `values-night` variant.
10. **Two new screen names** (job 21's `screenNames` in `router.dart`):
   `settings` for `/more/settings` and `language` for its list, so feedback
   sent from either page names it rather than `other`. Both match the
   `feedback.screen` check (`^[a-z][a-z_]{0,39}$`); the analytics
   allow-list takes them from the same set.

## Job 29a (fixed-height top bar, no household name or count), 2026-10-30

1. **Why the list jumped.** `_SyncIndicator` was `SizedBox.shrink()` while
   synced and a 48 px padded icon while offline or pending. The header was a
   `Row` of the two text lines (about 36 px) and that indicator, so its
   height followed the taller child: about 50 px synced, 62 px with the
   cloud. A short pending state after every tick or add (the icon shows
   until the server acknowledges) made the bar, and the whole list under it,
   jump by about 12 px for a moment.
2. **One height in every state.** The bar (`_Header`, key `list-header`) is
   a `SizedBox` of `_Header.height` = 44 px below the top inset, whatever it
   holds. The sync icon sits centred in a fixed 44 x 44 slot (also its tap
   target for the tooltip), which is empty while synced; the partner note is
   one line with an ellipsis, so neither a long name nor a large text scale
   can make the bar grow. The widget test "the bar above the list keeps its
   height in every sync state" checks the bar's height and the list's top
   through synced, pending, offline, reconnecting, synced again and a
   partner add, with a 47 px notch; `e2e/tests/list-header.spec.ts` checks
   the first divider's position in the browser with a held write and a cut
   network.
3. **No household name, no count (Peter).** The name was on screen all the
   time and said nothing new (one household per user), and the count
   duplicated the store dividers' "N Artikel". Both are gone from the list,
   and so is the bar's heading semantics. The household name stays where it
   helps: Mehr (household section, invite, join confirm). `ShoppingList` no
   longer takes the household (`ListScreen` still waits for `InHousehold`),
   so five widget tests lost a `household:` line.
4. **What the bar keeps.** The "N neu (von X)" note for a partner's live
   adds (left) and the sync icon (right), the two things that change. While
   neither shows, the bar is an empty 44 px band with its bottom line. It is
   kept rather than collapsed, because a bar that appears with the first
   note or icon would move the list again.
5. **String left in place.** `listItemCount` is now unused but stays in
   `app_de.arb`/`app_en.arb` and the generated files: 19 and 29b edit the
   l10n files in parallel. Remove it in a later cleanup. (`appTitle`, the
   old fallback for an unnamed household, is still the window title and the
   licenses page's name.)
6. **Tests that read the header.** e2e: `listArea` takes the bar's fixed
   height (`listBarHeight` in `helpers.ts`) instead of the "N Artikel"
   line; `web-build.ts` `signIn` waits for the add field; `perf.spec.ts`
   times the list by the "Ohne Laden, 200 Artikel" divider (in the markup,
   since it is an aria-label); `groupHeadings` no longer drops a first
   heading. The verify recipes (`SKILL.md`, `auth.md`, `household.md`,
   `live-sync.md`) stop reading `list-title`; `list-walk-order.md` has
   `lw-top-bar`.

## Job 32a (spelling variants and synonyms in the classifier, Spec #8 Part A), 2026-10-30

Peter's decisions (2026-10-29, verbatim):

- "Split it: category fix right after the feedback job, before Alexa; duplicate hint with or after onboarding"
- "Show a hint with a one-tap merge, still add by default" (applies to 32b; this job adds no UI)

The job's own calls:

1. **Where it lives.** Everything is in the database, new migrations only:
   `20261030110000_classifier_variants.sql` (functions, tables, columns, the redefined trigger
   functions), `20261030110001_classifier_dictionary_variants.sql` (the dictionary, regenerated
   unchanged, now ending with the lexicon refresh) and `20261030110002_classifier_synonyms.sql`
   (generated from `supabase/classifier/synonyms.tsv`). `classify_item`, `suggest_store`,
   `dictionary_category`, `items_before_write` and `items_learn_insert` keep their signatures, so
   the app, `add_item`/`add_items` (MCP, Siri, voice), `parse_item` and `suggest_entries` (the add
   sheet) and the coming Alexa skill get the new behaviour without a change on their side.
2. **The order of the rules** (`classify_item_detail`): the household's correction for the item
   key, then for its canonical key; the dictionary's rules as before (phrase, whole key, frozen
   marker, compound ending); the lexicon after folding spelling, or a synonym; a household
   correction a typo away; the lexicon's typo match; the dictionary's weakest rule (a word starts
   with a term); Sonstiges. The dictionary still wins over everything new, except where its
   compound-ending rule matched a short head and the lexicon recognizes a longer form: a folded
   exact one (Erdnusbutter is Erdnussbutter, Vorrat, not "Butter") or one a single edit away
   whose ending differs (Feuchttüscher is Feuchttücher, not "Schere"; Spültücher stays "Tücher"
   because Spucktücher ends the same: the typo would not be in the head). With these rules every
   one of the 1,202 dictionary terms, every brand product and all 345 items of the job-2 sweep
   classify exactly as before (checked by the pgTAP suite, `sweep.sh` and a one-off comparison).
3. **Normalization** (`fold_word`, on top of `item_key`'s case, umlauts, ß and plurals): doubled
   letters single, ph/th/gh, c to k (not in ch/ce/ci), ck/dt/tz, an h after a vowel before a
   consonant. A word under 5 letters is not folded, and neither is one that drops under 5 by
   losing its doubled letters: otherwise Kasse folds to Käse and Hack to Haken (both seen in the
   word list). No two dictionary terms of different categories share a folded form (pgTAP).
4. **Fuzzy match** (`lexicon_fuzzy`): Levenshtein from `fuzzystrmatch` (an adjacent swap counts
   as one edit), same first letter, never under 5 letters; two 5-letter words only by a swap
   (Mlich), one edit once the longer word has 6+ letters, two when both have 8+; the nearest forms
   must agree on the category, else nothing is guessed. Stricter than the spec's "under 4 letters
   exact only": with one edit at 5 letters, Tisch became Tusche (Drogerie).
5. **"Household history" is the household's corrections** (`category_memory`), matched by their
   canonical key and, a typo away, fuzzily. Items the household added without correcting them
   carry the dictionary's category already, so they would add nothing but cost.
6. **A correction holds for the canonical key**, not only the typed spelling: moving "Karrotten"
   to Getränke also sends "Möhren" and "Karotten" there in that household (Spec Part A item 4,
   "its normalized variants"; synonyms are "categorized the same"). An exact correction of the
   other spelling still wins, as the item key is checked first.
7. **The canonical key** (`public.canonical_key(name)`, column `items.canonical_key`): the item
   key, folded, every synonym replaced by its canonical term, every recognized typo by the word
   it means. "Karotten", "Karrotten", "Möhren", "Mohrrüben", "Gelbe Rüben" and "carrots" all give
   `mor`. It also sits on `category_memory` and `item_store_memory` (kept by a trigger), so a
   store remembered for Mohrrüben is guessed for Karotten (`suggest_store`, and so `guess_store`
   and `parse_item`). Job 32b's duplicate hint matches on `items.canonical_key`.
8. **The synonym table.** Regional German (DE/AT/CH, the spec's pairs and about 70 more) and
   common English words, 160 variants, each pointing to a dictionary term. Left out because they
   end other words or collide: Randen (Swiss Rote Bete; "Deodorand" ended in it), Brause
   (Duschbrause), Kraut (Sauerkraut), Pfannkuchen (Berliner in Berlin, a crêpe elsewhere) and
   English "beer" (stems to "beer", the dictionary's Beere). `generate_synonyms.ts` refuses a
   variant whose dictionary category differs from its canonical's.
9. **AC4 word list** (`supabase/classifier/wordlist.tsv`): 210 common words, 138 realistic
   misspellings, 47 regional and English variants, 26 non-groceries. Local run: words 210/210,
   variants 47/47, misspellings 130/138 (94.2%), false matches 2/421 (0.48%). The two false
   matches are the dictionary's compound-ending rule from job 2, unchanged by this job:
   "Fahrradschlauch" ends in "lauch" (Obst & Gemüse) and "Nagel" in "gel" (Drogerie). They stay
   in the list so the rate is honest. The eight misses stay in Sonstiges (no wrong guess):
   Kartoffen, Knoblauh, Mören, Nudlen, Essich, Kaffe, Kakau, Rotwien (too short after stemming,
   or two edits in a short word). Four negatives of a first draft (Geburtstagskarte,
   Kugelschreiber, Blumenerde, Druckerpapier) were dropped: the dictionary lists them as Haushalt
   on purpose.
10. **AC8 latency.** `latency.sh` times `classify_item` against main's classifier from before this
    job (copied verbatim into temp functions) word by word, alternating, in one session, so both
    see the same machine. The first version was 3 times slower (p95 2.4 ms vs 0.7 ms): SQL
    functions are planned on every call in Postgres 17 and the LIKE joins scanned every term. The
    rules are now PL/pgSQL (cached plans) and each one an index lookup of the key's endings,
    beginnings and word runs (the same matches as the LIKEs), so the new classifier is faster than
    the old one: locally p50 0.13 ms vs 0.57 ms, p95 0.21 ms vs 0.71 ms. CI's numbers are in the
    PR. No network call either way.
11. **`categorized_via` and the event.** The items trigger runs the classifier on every insert (it
    did already for inserts without a category, and `items_learn_insert` ran it for the others; it
    now reads `categorized_via = 'picked'` instead, so the classifier runs once per insert). The
    column says household, exact (also after folding), synonym, fuzzy, fallback, or picked (the
    add brought a category other than the guess). The app sends `item_categorized {via}` once per
    added item when the server confirms the add, also after a retry whose first answer was lost
    (an op is acknowledged once); not for a restored deletion (`AddItem.restored`, kept in the
    queue's JSON) or a realtime echo. Unlike the other list events it fires on the server's answer,
    because only the server knows how it categorized. MCP, Siri and voice adds send nothing, as
    for `item_added` (PM, 2026-10-25). `dedupe_hint_shown`, `_merged` and `_ignored` are in the
    allow-list with `actor_role` and `household_size` for 32b to emit.
12. **No text changes.** Typed text is stored and shown as entered; only the category and the
    hidden `canonical_key`/`categorized_via` are the server's. Nothing is auto-corrected or merged.
## Job 22 (onboarding: create or join a household, invite a partner, Spec #3), 2026-10-30

Peter's decisions (2026-10-27), as given:

1. **Invites last 7 days and are single use.** Once one person has joined with an invite, its link
   and code stop working. Any member can revoke one.
2. **The analytics consent (job 19) comes right after sign-in, before onboarding**, so
   `household_created` can be counted. Declined, onboarding works the same and sends nothing.
3. **Specs #1 (analytics), #2 (feedback) and #3 (this) are all live before the friends-and-family
   beta.**
4. **Someone in a household who opens an invite may switch after a warning** (Join or Cancel;
   Cancel is the prominent answer). If they are the last member, the old household is deleted
   with its list, and the warning says so.

Calls made in this job:

5. **Server: one migration, `20261030120000_onboarding_invites.sql`.** `invites.expires_at`
   defaults to 7 days; open invites made under the old 14-day rule were clamped to
   `least(expires_at, created_at + 7 days)`. New columns `used_at` and `used_by` (set null when that
   account is deleted). `accept_invite(p_code)` consumes an invite with one conditional `UPDATE ...
   WHERE used_at IS NULL AND revoked_at IS NULL AND expires_at > now()`. Of two people racing for
   one code, the second waits for the row lock, finds `used_at` set and gets `invalid_invite`.
   e2e "two people racing for one code" runs that race through two real sessions; pgTAP runs in
   one transaction, so it covers the sequence. A double tap by the same user loses the race to
   themselves and is answered `member`.
6. **One answer for every bad code.** Made-up, expired, revoked and used codes all answer
   `invalid_invite`, from `preview_invite` and from `accept_invite`. A member of the code's
   household gets `member` whatever state the invite is in, without using it up, and lands on the
   list. Nobody else learns whether the household exists.
7. **The rate limit records failures without raising.** A plpgsql `raise` would roll back the row
   it just wrote. So `check_invite` (internal) returns a status: `too_many_attempts` once the user
   has 10 failures in `invite_attempts` within the last hour, `member`, `invalid_invite` (recorded),
   or `ok`. `preview_invite` and `accept_invite` return `{status, ...}` jsonb, and a bad code
   never raises. Refused attempts are not recorded, so the window clears an hour after the 10th
   failure. Even a valid code waits until then. A per-user advisory lock counts a burst of
   parallel guesses one by one. Rows older than a day are purged whenever a failure is
   recorded. The table has RLS with no policy and no grants, and cascades with the user.
8. **The old `join_household(text)` stays, but returns null for a bad code** instead of raising
   `invalid_invite` (old apps then show no error; a valid code still joins). It raises only
   `too_many_attempts`, because a raise on a bad code would drop the recorded failure and leave
   this path without a rate limit. Every caller in the repo (scripts/fg, fixtures, smoke,
   backup fixtures, pgTAP) still works. Since job 30, every green merge ships new store builds,
   and the web app follows each store release, so old clients are short-lived.
9. **`revoke_invite(p_invite)`; the column grant `update (revoked_at)` and its policy are gone.**
   Members can no longer set `revoked_at` back to null. Revoking twice keeps the first time.
10. **`create_household(p_name, p_default_stores default true)` replaces `create_household(text)`**
    in the same migration (drop and create, with `squawk-ignore ban-drop-function` and its
    reason). A second overload would have made every one-argument call ambiguous; the one
    function takes every old call. `seed_household(uuid, boolean)` seeds the 11 categories
    (with the fallback `Sonstiges`) always, and dm, Lidl and Edeka with their layouts only with
    stores. `seed_household(uuid)` stays as a wrapper.
11. **A double tap or a retry after a lost answer makes one household.** The server answers
    the second create with `already_in_household`; the app takes that as success and loads the
    household. `household_created` goes out once. When the first answer was lost, it goes out
    with the retry, with the store choice of the first try (`SessionCubit._unansweredCreate`).
    Joins work the same way (`_unansweredJoin`: a `member` answer to the same code after a
    lost answer sends the one `invite_accepted`). e2e drops the first response of both RPCs.
12. **Austrian and Swiss users get the same default stores for now.** dm and Lidl exist there;
    Edeka is Germany-only and can be deleted. NEEDS_PETER asks about country sets later.
13. **The flow.** The router (`authRedirect`) is the only gate. After sign-in, consent comes
    first if undecided. Without a household: `/welcome` (Step 1), `/welcome/create` (2a),
    `/join` (2b, typed code), or `/join/<code>` at once for an invite. In a household,
    `/welcome/create` turns into `/welcome/invite` (Step 3, "Später" goes to the list), and an
    invite opens `/join/<code>`, which warns first. An MCP authorization (`next`) rides along
    every onboarding step and wins once there is a household. The join screen previews the
    household name before joining. A preview of the user's own household's link lands on the
    list. Onboarding screens leave through the list (`leaveStep`), which the router turns into
    Step 1; only `router.dart` names `/welcome` (lint `auth-navigation-only-in-router`).
14. **Pending invite on the device (AC6 on all platforms).** `PendingInvite`, stored in
    `DeviceCache` as `invite.pending` = `{code, at}`, deliberately outside `forget()`'s prefixes,
    because a signed-out start forgets. It is kept the moment the router sees `/join/<code>` or
    `?invite=` and lasts 7 days. It survives the custom-scheme sign-in return
    (`com.hummlist.app://login-callback`, whose location has no invite), app kills, the consent
    and onboarding. A join, a Cancel or an invalid code answers it. An answered code is not kept
    again this run (the router still sees `/join/<code>` while the screen hands over to the
    list); a sign-out clears it all. The router reads it synchronously when the location has no
    invite. It is never logged, sent to analytics or crash reports, or named in a screen name
    (`/join/<code>` is `join`).
15. **Universal links and App Links were possible without placeholders.** Both browser steps
    from the brief were already done: the Lead enabled Associated Domains on
    `com.hummlist.app` and `renew_profile` made profile `5T4AGK7RF2` with associated domains
    (NEEDS_LEAD L6, 2026-10-27). The Play App Signing SHA-256 is in RELEASE.md (L3,
    2026-10-28). So `Runner.entitlements` gets `applinks:app.hummlist.com`, the manifest an
    `autoVerify` https filter for `/join/`, and `app/web/.well-known/` holds the AASA
    (`VCZSHMZY25.com.hummlist.app`, `/join/*`) and `assetlinks.json`. It lists the Play app
    signing key, which signs what testers install, and the upload key, which signs CI's own
    APK/AAB artifacts. `vercel.json` keeps `.well-known/` out of the SPA rewrite and serves
    the AASA as `application/json`. `deep_links_config_test.dart` checks that the five files
    agree and that the fingerprints are RELEASE.md's; `web-prod.sh` checks that the build
    copies both; `e2e/web-smoke.mjs` checks them on a deployed URL. They reach app.hummlist.com
    with the next dispatched store release (web follows the release, job web-release-align).
16. **Share.** iOS and Android open the system share sheet right after the invite exists. On
    the web, the invite shows with its code, its link, "Link kopieren" and "Code kopieren",
    plus "Teilen" where the browser has the Web Share API. The sheet is not opened by itself
    there: Web Share needs a fresh tap, which the server's answer outlasts. share_plus's
    mailto fallback is off. The share text is ARB `inviteShareText` (DE: "Komm in unseren
    Hummlist-Haushalt: <link> · Code: <code>"). Each share or copy tap is one `invite_sent`.
17. **Invite management** is More, Haushalt, "Partner einladen" (`/more/invites`): a new
    invite, the open ones with "gültig bis <Datum>, <Uhrzeit> Uhr", and revoke per invite.
    Used, revoked and expired invites are not listed (the list reloads when the page opens).
    The old invite dialog and More's join dialog are gone; "Anderem Haushalt beitreten" opens
    the join screen.
18. **The data export lists `invites_created`** (code, created, expires, used and revoked
    times): household data the user made. Who used an invite is someone else's data and is
    left out. `invite_attempts` is not exported; it holds nothing but the user's id and a time,
    and it lasts a day.
19. **Mobile proof without devices.** No emulator or simulator on the runner. Router tests feed
    the URIs the platforms deliver (`https://app.hummlist.com/join/ABCD2345`,
    `com.hummlist.app://login-callback?code=…`), with and without a pending invite (a cold start
    reads it back from the store). The Linux app via scripts/fg needs a local Supabase stack,
    which the Mac runner does not run (no Docker); the web e2e on CI drives the same Flutter
    code. The device check is a NEEDS_PETER checklist.
20. **Review fixes (an independent read of the diff before the Sonnet review).** After a join, the
    join screen leaves through the list with the MCP `next` kept (`leaveStep`), so an
    authorization on the way is not dropped. A refused code answers the pending invite only if it
    is that code: a typo after opening a link keeps the link. The cubit's lost-answer marks are
    reset on sign-out and account deletion, so one user's retry state never sends an event for
    another. `create_household` turns the unique violation of a create racing on the user's
    other device into `already_in_household`, which the app answers by loading the household.
    Kept as decided: old builds get null for a bad code (8). The export lists codes the user made
    also for a household they left (their own data).

## Job 33b (legal fixes in the app), 2026-10-30

From the legal review of 2026-10-30 (H-01 app part, H-03, H-07, H-08, H-17;
the review and the engineering answers to its open facts are local files,
not in this public repo). Peter set the priority at 07:46. The PR waits for
his legal OK and is not merged by the job.

1. **One privacy URL.** `privacyPolicyUrl(languageCode)` in
   `app/lib/app/guides.dart`, shaped like `imprintUrl`: `de` gets
   https://hummlist.com/datenschutz, every other language
   https://hummlist.com/en/privacy (the paths job 33a publishes; the review's
   one-constant redline would have sent English users to the German page).
   More → Datenschutz, the login footer and the consent screen all call it.
   The in-app draft page is gone with its route `/more/privacy`,
   `MorePage.privacy` and the keys `privacyDraftBody` and `draft`. An old
   `/more/privacy` link lands on the list, like any unknown path.
2. **Legal pages open outside the app** (engineering answer 15). Impressum
   and Datenschutz open with `LaunchMode.externalApplication`
   (`openLegalPage`, `LegalLink` in `app/lib/app/legal_links.dart`): the
   system browser on iOS and Android, a new tab on the web. With no
   in-app browser view the App Store age-rating answer "Unrestricted Web
   Access: No" is unambiguous. The links in the login footer and the
   consent text are url_launcher `Link`s, so the web build renders them as
   `<a href … target="_blank">`. Social sign-in and the MCP consent redirect
   keep their own launch modes; they are sign-in flows, not pages to read.
3. **Login footer.** "Impressum · Datenschutz" / "Imprint · Privacy" sits
   below the scrolling form, outside it, so it is on screen without
   scrolling (tested at 320×568 and 1280×720 in widget tests, 360×640 and
   1280×720 on the web). The login screen has one state: sign-in, sign-up
   and the magic link are buttons on the same form, so one footer covers
   all three.
4. **Consent wording verbatim from the review's redline**, DE and EN, with
   "Peter Trost" spelled out. The body is split around the link instead of
   parsing it: `analyticsConsentBody` ends with "Mehr in der" / "More in
   the", `analyticsConsentPrivacyLink` is the link label, and the screen adds
   the space and the full stop. Peter approved the wording on 2026-10-30
   at 07:51, so the lead's update (08:05) had the ENTWURF chip and
   `analyticsDraftNote` removed in this PR, and the `@…` descriptions say
   "approved by Peter 2026-10-30".
5. **Install id only after a yes** (H-08, TDDDG §25). `Analytics.load()`
   never makes an id: with consent it reads the stored one (or makes one if
   it is missing or malformed, which the consent covers); without consent it
   deletes any stored id and `first_open` mark, which removes the ids builds
   since job 19 wrote before anyone answered. `decide(granted: true)` makes
   and stores the id if there is none. `decide(granted: false)` drops the
   queue and deletes the id and the `first_open` mark
   (`AnalyticsStore.forgetInstallId`), so the toggle hint "Ausschalten
   löscht die Kennung auf diesem Gerät" is true. A later yes is a new
   pseudonymous install: new id, one more `first_open`. That counts the
   same person twice in install cohorts after an off-and-on, which is the
   price of actually deleting the id; it is rare and `docs/ANALYTICS.md`
   says so.
6. **Purchases and the internal mark need no change.** The app has no
   purchase code yet; `recordPurchase` in `_shared/purchases.ts` already
   sends nothing unless the app reports `consent` and an `installId`, so the
   purchase job only has to pass `installId: null` without consent. The
   internal-install mark under More is a separate boolean, not an id, and
   keeps working with or without an install id (`more_toggle_test.dart`).
7. **H-17 is in.** `consentListAccess` takes `{client}` and tells the user
   that the client and its provider receive the list contents: the ARB keys,
   the call in `app/lib/oauth/consent_screen.dart` and its test.
8. **Where the engineering answers correct the review.** The review says
   purchase events go out without consent (H-05); they don't (answer 7), so
   nothing changes in the app for H-05. The review's English privacy URL
   `/en/privacy` is used although the site's footer still says `/privacy`;
   job 33a moves the site to `/en/privacy`.
9. **On a phone, the e2e helper scrolls the consent text with a finger.**
   On CI both iPhone focus tests (`e2e/tests/iphone.spec.ts`, WebKit with
   the iPhone platform) failed on this branch: the add field took `focusin`
   and then wasn't focused. Throwaway branches off `main` (on-demand e2e,
   iPhone spec only) narrowed it down:
   - the new consent text alone fails; the install id change and the legal
     links alone pass;
   - the same text in a smaller style that fits the screen passes, and so
     does the overflowing text with the buttons above it;
   - so the trigger is how the test reached buttons below the fold: the
     helper `answerConsent` used the mouse wheel (or, in one attempt, a
     synthetic click on the button's semantics node). Neither a
     `NoTransitionPage` nor jumping the list back to the top before
     answering helped, and swapping url_launcher's `Link` for a plain tap
     didn't either;
   - scrolling with touch pointer events, as a finger does, and then
     tapping the button passes (3 of 3).
   A phone has no mouse wheel, so this was the test harness, not the app.
   On touch devices `answerConsent` now swipes with touch pointer events
   (`touchSwipeUp` in `e2e/tests/helpers.ts`) and taps the answer. The app
   code is unchanged for this. Why a wheel-scrolled consent page breaks
   the next page's focus on an emulated iPhone is not known; a guess is the
   engine behavior of 19.20.

## Job 33a (privacy policy on hummlist.com, corrected deletion page), 2026-10-30

Source: the legal review of 2026-10-30, sections B.1, B.2, H-05, H-06, H-19,
and the engineering facts answers of the same day (both kept off the repo).
Where the answers correct the review, the answers win. This job supersedes
job 24's policy part.

1. **Paths.** `/datenschutz` (German, authoritative) and `/en/privacy`
   (English). `/privacy` is a permanent redirect to `/en/privacy` in
   `site/vercel.json`; the headers stay as they were, `X-Robots-Tag: noindex`
   included.
2. **Footer flags split.** `legalPublished` turned on both the privacy and
   the support link, and the build fails without a `/support` page. Now
   `privacyPublished` (true in this PR) and `supportPublished` (false until
   job 24 adds `/support`). The flag only takes effect when the PR merges,
   and the merge waits for Peter.
3. **Heading anchors.** A heading ending in `{#id}` gets that id (a small
   markdown-it rule in `build.mjs`). Section 15 is `/datenschutz#rechte`
   (Apple's User Privacy Choices URL) and `/en/privacy#rights`.
4. **The site gate builds in preview mode.** The gate ran
   `VERCEL_ENV=production npm run build`, which fails on a `[PETER:`
   placeholder, so a PR carrying the policy's open facts could never get
   `ci-ok`. The gate now runs `npm run build` (every check, placeholders
   only warn), and a test fills the placeholders and builds in production
   mode, so everything else stays checked. Vercel's production build of
   hummlist-site still fails on a placeholder: that is the second publish
   gate, and hummlist.com keeps its last good deploy until they are filled.
5. **Texts are §B verbatim except for these fact fixes** (facts answers
   wins over the review):
   - §2/§3: no Vercel Functions in any of the three projects, so "statische
     Dateien"; log retention depends on the plan, a placeholder.
   - §3 uses the interim sentence (lead's update 08:05, Peter approved the
     wording at 07:51): „Die Web-App lädt derzeit Programmbibliotheken und
     Schriften von Servern von Google (gstatic.com); dabei erhält Google
     deine IP-Adresse. Wir stellen das in Kürze um.“ So 33a does not wait for
     job 33c, which swaps back to „Alle Programmdateien und Schriften kommen
     von unserem eigenen Server“ when self-hosted CanvasKit and fonts reach
     app.hummlist.com. §12 lists Google as independent controller for those
     loads while they last. §2's "keine Inhalte von anderen Servern" is about
     hummlist.com, which loads none, so it stays.
   - §4: the repo configures no SMTP (`supabase/config.toml`), so the auth
     mails go "über unseren Dienstleister Supabase", with a placeholder for
     Peter to confirm in the dashboard.
   - §5: invites expire after 14 days:
     `supabase/migrations/20261022150000_foundation.sql` line 62
     (`expires_at … default now() + interval '14 days'`); no later
     migration changes it. Job 24's brief said 7.
   - §6: no online fallback. `app/lib/list/dictation.dart` refuses unless
     `MainActivity.kt` `offlineGerman` confirms on-device German (Android)
     and iOS asks with `onDevice: true`; `list_screen.dart` `dictationFor`
     offers no dictation on the web. The ⟦Android Online-Erkennung⟧
     sentence is gone; the text says recognition happens only on the
     device and the browser has none (H-16).
   - §9 written as active (keys set 2026-10-30 07:33), accurate to
     `app/lib/analytics/events.dart` (events and their properties, adding
     `first_open`) and to `$geoip_disable` / `$process_person_profile:false`.
     "Installationskennung nur mit Einwilligung" relies on job 33b (H-08:
     today `Analytics.load()` writes the id on every start); 33a must not
     go live without 33b. Purchase events carry install and household id
     and are sent only with consent (`supabase/functions/_shared/purchases.ts`
     `recordPurchase`), so they sit in the consent paragraph, not under
     legitimate interest; the review's H-05 premise was wrong there.
   - §9 server error reports (H-05): the payload was checked in
     `_shared/telemetry.ts`: `$exception` with `distinct_id`
     `edge-function-<fn>`, no user, household or install id, no request,
     `$geoip_disable`. Unquoted words in a runtime error's message passed
     the scrub (`cannot parse Hafermilch 2 Liter`), so a runtime error's
     message is now reduced to its shape: only words of the runtime's own
     error templates stay, any other word becomes `<w>`, digits `<n>`, at
     most 120 characters. `telemetry_test.ts` proves no personal value from
     the request or the message reaches PostHog. The app's own scrubber
     (`app/lib/analytics/exceptions.dart`) had the same gap and gets the
     same rule, since §9 promises no item names in any error report. The
     ⟦bestätigen⟧ marker is gone; retention 1 year like the rest.
   - §11: backups are on GitHub Inc. (USA), encrypted, 90 days. Moving them
     (H-11) is Peter's decision, not this job.
   - §12/§13: Supabase functions run at the edge location nearest the
     caller, also outside the EU; only the database is in Frankfurt. Both
     sections say so. Transfer basis, the Google contracting entity and the
     AI support provider are placeholders.
   - §14 (H-12): "so lange der Haushalt besteht", the history included. Job
     21 (feedback, with a 12-month purge) is not on main yet (PR #103 open).
     [LEAD: Feedback-Abschnitt nach Job 21] Once 21 lands, the policy needs
     a feedback paragraph (what is stored, deleted after 12 months).
   - "Stand: 30. Oktober 2026" / "Last updated: 30 October 2026" (lead's
     update 08:05), the same as the front matter's `updated`.
6. **Name and address without placeholders.** "Peter Trost" (Peter, 07:50;
   the review's H-23 says the full name is not required) and Yalovastr. 5
   (confirmed 07:50). The Impressum already says both and is unchanged.
7. **Deletion page.** H-06 redlines verbatim (backups, entries and history
   kept for the others), `peter@petertrost.com` replaced by
   `support@hummlist.com` (H-19), a link to the policy added. Peter approved
   the wording (07:51), so the ENTWURF banner, its CSS and the page's
   `noindex` meta are gone (lead's update 08:05); `account.spec.ts` checks
   the page has neither. hummlist.com's site-wide `X-Robots-Tag: noindex`
   stays.
8. **One line beyond the approved text on the deletion page.** Step 2 said
   „Tippe oben rechts auf das Menü und dann auf Konto“, but the app has had a
   „Mehr“ tab (bottom bar, a side rail on wide windows, `app/lib/app/shell.dart`)
   since job 29a/29d. It now says „Tippe auf **Mehr** und dann auf
   **Konto**.“, true on both layouts. The PR body flags it for Peter.
9. **Facts the lead filled before merge (2026-10-30, after Peter's OK).**
   Vercel's address „440 N Barranca Ave #4133, Covina, CA 91723, USA“ (Vercel
   privacy notice and DPF listing). Log retention „höchstens 30 Tage“: the team
   is on Vercel Pro (team API, billing.plan = pro), whose runtime logs keep 1 day,
   or 30 days with Observability Plus (vercel.com/docs/logs/runtime), so 30 days
   is the upper bound either way. Auth mail: no custom SMTP in the repo, no
   hummlist.com domain in Resend, SPF of hummlist.com allows only Google, and the
   hosted auth log answered the third mail request within two minutes with
   `429: email rate limit exceeded` (the built-in mailer's tiny hourly limit;
   custom SMTP starts at 30 an hour), so „über unseren Dienstleister Supabase“
   stays without the SMTP question. The other `[PETER: …]` stay; Vercel's
   production build keeps refusing to publish until Peter fills them.

## Job 33c (self-host CanvasKit and fonts, legal review H-02), 2026-10-30

1. **The loader takes the engine and fonts from our origin.**
   `app/web/flutter_bootstrap.js` passes
   `config: { canvasKitBaseUrl: '/canvaskit/', fontFallbackBaseUrl: '/fonts/' }`
   (review H-02's redline, Flutter's web initialization docs). One base URL
   covers both apps of the job 28 `--wasm` build. The same object also goes
   to `engineInitializer.initializeEngine(config)`: the loader reads
   `canvasKitBaseUrl` from `load()`, but the engine reads
   `fontFallbackBaseUrl` only from `initializeEngine()`. Our own
   `onEntrypointLoaded` (the boot retry) called it with no argument, so the
   first CI run still fetched the Noto fonts from fonts.gstatic.com, and the
   CSP blocked them (DECISIONS 33c.5). Flutter's loader takes
   `canvaskit.js`/`chromium/canvaskit.js` (JS app) and `skwasm.js` or
   `skwasm_heavy.js` (wasm app) from it. `flutter build web` always puts every
   variant in `build/web/canvaskit/`, so the Vercel output had them before
   this job too, unused. `vercel.json` already kept `/canvaskit/` out of the
   SPA rewrite and serves `.wasm` as `application/wasm`. Measured before the
   change on a local Vercel-style build, login screen, no interaction:
   Chromium fetched `skwasm.js` and `skwasm.wasm` from www.gstatic.com and
   Roboto from fonts.gstatic.com, and Firefox fetched `canvaskit.js`,
   `canvaskit.wasm` and Roboto. That matches the lead's live baseline.
2. **Roboto comes from Flutter's own local build, not from a pubspec font.**
   The brief asked for Roboto in `app/pubspec.yaml` as the theme's font. A
   `--no-web-resources-cdn` build already does that for the web only: Flutter
   adds the engine's Roboto 2 Regular (Apache 2.0) to `FontManifest.json` as
   the family `Roboto`, and the engine then never fetches its own Roboto.
   `scripts/vercel.sh` now builds with that flag, like the web-prod and e2e
   gates and `fg sync` already did. A pubspec font would have gone into the
   iOS and Android apps too. On Android the family name `Roboto` would have
   replaced the system font, whose real 600/800/900 weights the app uses,
   with a bundled file. On the web the default typography already resolves
   to the manifest's Roboto, so no theme change is needed.
3. **Every fallback font is shipped, not a subset.** The engine names 724
   Noto fallback fonts (emoji in 12 slices, CJK in about 100 slices per
   language, symbols, every other script) plus Roboto, 21.7 MB in total. A
   browser downloads only the slices for glyphs it has to draw, so the size
   costs no first load, and no script ends up as tofu. `app/web/fonts/`
   mirrors the fonts.gstatic.com/s/ paths the engine asks for.
   `scripts/web-fonts.sh` reads the list from the Flutter SDK
   (`font_fallback_data.dart`), downloads what is missing, deletes what the
   engine no longer names, and writes `LICENSES.md` (the copyright line of
   every family from google/fonts, all SIL OFL 1.1, plus `OFL.txt`) and
   `Roboto-LICENSE.txt`. The files are committed (about 24 MB in git, once
   per Flutter font roll), so a build never depends on Google's servers. If a
   font were missing, the engine treats the 404 as permanent for that font
   (no retry) and draws tofu for its glyphs only. The web-prod gate fails
   when `main.dart.js` names a font `app/web/fonts/` lacks, or when the
   bootstrap config or a CanvasKit variant is missing. Font files get
   `Cache-Control: public, max-age=31536000, immutable`, since each path
   carries the font version and a hash.
4. **No in-app license entry for the web fonts.** OFL condition 2 is met by
   the license files served next to the fonts (`/fonts/OFL.txt`,
   `/fonts/LICENSES.md`) and the copyright fields inside each font file. The
   bundled Roboto is the engine's own file, like CanvasKit.
5. **A CSP guards against a regression.** `vercel.json` sends
   `default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https://jdwqrallbpdbshrdhenk.supabase.co wss://jdwqrallbpdbshrdhenk.supabase.co https://eu.i.posthog.com; worker-src 'self' blob:; object-src 'none'; base-uri 'self'`.
   `wasm-unsafe-eval` compiles the engine and `main.dart.wasm`, and
   `unsafe-inline` styles cover the `<style>` elements Flutter injects.
   Google and Apple sign-in on the web are redirects (`SignInFlow.redirect`,
   Supabase's `/authorize`), and so is the OAuth consent's `_self` launch.
   CSP does not govern top-level navigation, so neither provider needs an
   origin. On preview deployments the CSP also blocks Vercel's comment
   toolbar (vercel.live), which only Vercel team members see. A new host the
   app fetches from must be added here.
6. **The whole e2e suite runs under that CSP.** `e2e/serve.mjs --csp
   <supabase-url> <posthog-host>` sends vercel.json's policy with the
   production Supabase and PostHog origins swapped for the e2e stack's and
   the stand-in collector's. It also routes like Vercel now: a path the
   rewrite matches falls back to `index.html`, and any other missing file
   is a 404 instead of `index.html`.
7. **The behavior test runs in three engines.** `e2e/tests/no-google.spec.ts`
   runs in the `chromium` (wasm), `webkit` and a new `firefox` project (both
   on the JS app, facts-answers #5). It signs in to a list with emoji,
   umlauts, Chinese, Arabic and Cyrillic names, then opens the add sheet. It
   fails on any request to a Google host, on any host besides ours,
   Supabase and the PostHog stand-in, on PostHog before consent, and on any
   CSP violation. It also checks that the emoji, CJK and Arabic fallback
   fonts were fetched from `/fonts/`. Cyrillic needs no fallback, since
   Roboto 2 covers it. CI installs Firefox next to Chromium and WebKit.
   `e2e/host-census.mjs <url>` runs the same host count against any URL (a
   deployment, `app.hummlist.com`) for the live check after release.
8. **Wording.** This job changes no user-facing text. 33a's privacy policy
   says nothing is loaded from Google, which is true only once this job has
   reached `app.hummlist.com` (with a dispatched release, `docs/DEPLOY.md`).

## Job 31 (Alexa skill "Hummlist", add items by voice, de-DE, Spec #7), 2026-10-30

Peter's decisions (2026-10-29 22:10 CET, his words), closing the spec's open questions 1-3:

1. "Yes, build Alexa right after the feedback job" (slot after 21).
2. "Use hello@hummlist.com for the Amazon Developer account" (Peter/Hummlist Ops create it; this
   job does not).
3. "Include list read-back now if it fits" (ReadListIntent in this job if it fits; otherwise the
   very next follow-up). **It fit: ReadListIntent is in this job.**

Beta invites and certification each need Peter's separate yes later; this job does neither and
took no action at Amazon (no account, no ASK CLI or SMAPI call, no upload).

Calls made here:

1. **Account linking reuses Supabase Auth's OAuth 2.1 server; no shim.** Read in
   `supabase/auth` (`internal/api/oauthserver`: `client_auth.go`, `authorize.go`, `service.go`)
   and proven end to end on the CI stack (e2e `alexa.spec.ts`, transcript in the PR): it registers
   confidential clients (`client_secret_basic`/`_post`, also by dynamic registration), checks the
   secret at the token endpoint, matches redirect URIs exactly, issues refresh tokens, and
   **requires PKCE** on every authorization. Alexa sends PKCE (S256) when the skill enables it
   (`pkceConfiguration`, documented in Amazon's account-linking schema), so PKCE must be on in the
   skill; without it Supabase refuses the authorization. The production client is registered by
   `scripts/alexa-oauth-client.sh` (dynamic registration, prints the secret once for the Alexa
   console). Scopes: none (Supabase's default).
2. **The linked token's user, their current household.** The function resolves the access token
   with the shared `authenticate()` (JWT, issuer, audience, and the session must still exist) and
   takes the household from `household_members` at request time; nothing in the request names a
   household. Only `via: 'oauth'` counts as a link (a PAT or an app session in Alexa's token slot
   is refused as unlinked). `Auth`'s OAuth variant gained `sessionId` for that.
3. **Revocation.** A revoked or expired token is unlinked (LinkAccount card, nothing added).
   Revoked are: disconnecting "Amazon Alexa" under Zugänge, account deletion, sign-out
   everywhere, and two skill events subscribed in `skill.json`: `SkillDisabled` (only Alexa's
   user id in it, so the function keeps `alexa_links`: SHA-256 of the Alexa user id → the session
   it holds, written on every request, service connection only) deletes those sessions;
   `SkillAccountLinked` revokes the sessions the same Alexa account held before. A plain "unlink"
   in the Alexa app sends no event (Amazon has none); Alexa deletes the only copy of the tokens,
   so the next request is unlinked, and the grant stays visible in Zugänge until removed. Not
   expired by a timer: a linked user who does not talk to Alexa for months must not be unlinked.
4. **Request verification is our own code** (`verify.ts`, `@peculiar/x509` 1.14.3 on WebCrypto, no
   Node TLS store in the edge runtime). The chain must reach a pinned root: Amazon Root CA 1-4 and
   Starfield Services Root CA G2 (Amazon's published chains end there; a real chain is a test
   fixture). Skill events get one hour of timestamp skew (Amazon delivers and retries them later;
   the ASK SDK allows the same), everything else 150 s. `@peculiar/x509` 3.x needs a
   `reflect-metadata` polyfill at the entry point, so 1.14.3 is pinned.
5. **Tests sign with a test CA, only in a local stack.** `scripts/alexa-test-ca.sh` (run by
   `supabase_up`) makes a CA with openssl, keeps the key in `supabase/.temp/alexa-test/`
   (gitignored), and puts the public root and chain plus the test skill id into
   `supabase/functions/.env`, which `supabase start` loads. The function honours them only when
   `SUPABASE_URL` is the local stack's `http://kong:8000`; the hosted project has
   `https://<ref>.supabase.co` and trusts Amazon's roots only (`config_test.ts`). No private key is
   committed (Deno tests make theirs in memory).
6. **The slot is `AMAZON.SearchQuery`**, the one free-text type, so whatever Alexa heard reaches
   the Siri splitter unchanged ("zwei Liter Milch und Eier"). Each intent sample has a carrier
   phrase; the slot samples may be the slot alone, which lets "Milch" answer "Was soll auf die
   Liste?" (`Dialog.ElicitSlot` on Launch and on the re-prompt). One SearchQuery per intent.
7. **Parsing and adding are the Siri path, imported, not copied.** `alexa` imports
   `voice/parse.ts` (`parseSentence`), `voice/items.ts` (`addItems` through `public.add_item`) and
   `mcp/list.ts` (`listItems` for the read-back, the app's aisle order). Edge function deploys
   bundle relative imports, as `_shared` already relies on. Duplicates behave as for Siri: an open
   item is named ("Schon auf der Hummlist: Milch.") and not added again.
8. **Replies.** Spec: "Milch und Eier sind auf der Hummlist." for several items. A single item is
   "Ich habe Milch auf die Hummlist gesetzt.", which is grammatical for plural names too ("Eier
   ist auf der Hummlist" would not be). Units are said in words (2 l → "2 Liter", 1 kg → "1
   Kilo"). The read-back says at most 10 items, then "und N weitere" (PM). Every reply ends the
   session except Launch, Help and the one re-prompt.
9. **Re-prompt once, never a guess.** Nothing understood (an empty or filler-only slot, the
   fallback intent, or the server's parser finding no item) asks once ("Das habe ich nicht
   verstanden. Was soll auf die Liste?", session attribute `retry`); the second time ends with
   "… Ich habe nichts auf die Hummlist gesetzt." An unlinked user is asked to link instead.
10. **Rate limit: 30 items a minute per user** (PM's figure), a fixed window in `alexa_rate`
    (`alexa_take_adds`, service connection), counted per item asked for. MCP and voice have no
    limit to reuse; this one is Alexa's own. More than 30 items in one phrase: the first 30 are
    added and Alexa says so (the Siri rule); over 1000 characters nothing is added.
11. **Analytics: the existing `item_added` with `source: alexa`** (the app's event, so retention
    and the gate queries count Alexa adds as activity), added to the server catalog in
    `telemetry.ts` with `actor_role` and `household_size` only. Consent is per install and lives
    on the device, so the server could not know it: the app now records each install's answer
    (`record_analytics_consent(p_install, p_consent, p_internal)`, table `analytics_consents`)
    when the user answers, switches, or signs in. An Alexa add is counted only while the user's
    newest answer (by when it last changed, not when an app last started) is yes, under that
    install id (`is_internal` from that install too). A build without a PostHog key records
    nothing. The table keeps the 20 newest installs per user and goes with the account; it is in
    "Meine Daten exportieren". This reverses "MCP and Siri adds are not counted" (PM 2026-10-25)
    for Alexa only, as Spec #7 asks.
12. **Error tracking**: the function runs under `withTelemetry('alexa')`; caught failures
    (database, auth lookup, bookkeeping) go to `telemetry.exception`, whose scrubber drops names
    and tokens (a test throws an error naming an item and checks the payload).
13. **Skill package files**, deployable with ASK CLI v2 (`ask deploy --target skill-metadata`):
    `skill.json` (de-DE only; distribution DE, AT, CH, LU, LI; category SHOPPING; privacy URL
    `https://hummlist.com/datenschutz`), the de-DE model, icons made from the app icon (108 and
    512 px), `ask-resources.json`, and `account-linking.json` without the secret. Validated by
    `skill_package_test.ts` (Amazon publishes no JSON schema for these; the test checks the rules
    certification applies: example phrases match samples, carrier phrases, built-ins present,
    one SearchQuery, prompts exist, no "Humm" alone).
14. **`export_my_data` gains `analytics_decisions` and `alexa_links`** (last use only, no hash).
    Job 22 redefines the same function in parallel; whichever lands second keeps both additions.
15. **German capitals for a lowercase utterance.** Alexa's recognizer may hand the slot over in
    lowercase ("milch ohne laktose"). The Siri splitter already capitalizes an item's first
    letter; when the whole phrase has no capital letter, the function also capitalizes the other
    words of each name except small words ("Milch ohne Laktose"), as German nouns are typed. A
    phrase that has capitals is left as heard.
16. **A no without an install id (after job 33b).** Since 33b an install has an id only after a
    yes and deletes it on a no. The app records a no under the id it had (before deleting it), and
    an install that never had one under the nil UUID (one row per user for all such installs). An
    answer the user gives (`p_answered`) always becomes their newest; a sign-in or start records
    only a new or changed answer. A yes without an install id is refused: events need one.

## Job 33d (verified facts in the privacy policy, sections 12 and 13), 2026-10-30

The lead filled only facts checked against official sources on 2026-10-30 (sources in PR #119):

1. **DPF status** (dataprivacyframework.gov participant API, status Active, EU-US, non-HR data):
   Vercel Inc. (6847, until 2027-04-29), GitHub (6174, until 2027-08-03), PostHog Inc (2915, until
   2027-03-10), Google LLC (5780, until 2027-09-13). Supabase: no entry, active or inactive.
2. **Supabase's contracting entity is Supabase Pte. Ltd., Singapore**, not Supabase Inc.: the
   Supabase Terms name Supabase, Inc. only for AWS Marketplace purchases; our org is on the free
   plan, bought directly. Its DPA (clause 12, Schedule 2) incorporates the 2021 SCCs, module 2, with
   Supabase Pte. Ltd. as data importer. Section 12 now names Pte. Ltd.; section 13 relies on SCCs.
3. **SCCs as a second basis only where the DPA says so:** Vercel DPA (Schedule 3, applies to Pro)
   and PostHog DPA (10.4, "notwithstanding" its DPF clause 10.3) incorporate SCCs. Google's Cloud
   Data Processing Addendum (4.1) applies SCCs only if Google has no Alternative Transfer Solution;
   Google adopted the DPF as that on 2023-09-01, so the text says SCCs apply if Google stops relying
   on the DPF. GitHub: DPF only in the text; its DPA (7.B) also offers SCCs, but it covers
   Enterprise/Team/Copilot and our plan could not be read, so we do not claim it.
4. **PostHog EU** stores data in Frankfurt (AWS eu-central-1, PostHog handbook "Security"), but
   its DPA 10.2 allows processing in the US through sub-processors; section 13 says so.
5. **Google Workspace contracting entity: Google Cloud EMEA Limited, Dublin, Ireland**
   (cloud.google.com/terms/google-entity: Workspace agreements, EMEA except France, Italy, Poland;
   the petertrost.com Workspace invoice of 2026-10-02 is issued by the same entity). The archived
   2020 EEA Workspace agreement naming Google Ireland Limited is superseded.
6. Left as `[PETER: …]`: AI support provider and location, who sends replies, support-mail
   deletion period (section 10) and the AI provider's transfer basis (section 13).

## Job 33e (support facts in the privacy policy, sections 10, 12, 13), 2026-10-30

1. **Section 10 from Peter's answers (2026-10-30 14:21):** the AI support assistant is "Hummlist
   Support" on Grok Bot; it only drafts, sends no automated replies, and Peter reviews and sends
   every reply; support e-mails are deleted 6 months after the request is closed.
2. **Grok Bot's provider is Anysphere, Inc., USA (a Texas corporation).** Sources checked
   2026-10-30: the X-Subscription Consumer Terms (x.ai/legal/x-subscription-terms-of-service,
   updated 2026-10-27): the agreement is with SpaceX Super Intelligence LLC, but "access to Cursor,
   Grok Bot, or the Third-Party AI Models ... is provided by Anysphere, Inc., a Texas corporation";
   the Grok Bot Terms (cursor.com/terms/grok-bot, 2026-10-12) define the Provider as the entity
   providing Grok Bot under the agreement; Peter's plan is The X Subscription Premium (receipt
   2026-10-13, issued by SpaceXAI, LLC, the earlier name of SpaceX Super Intelligence LLC), which
   includes Grok Bot (docs.x.ai/x-subscription/grok-bot). Sections 10 and 12 name Anysphere, Inc., USA.
3. **Transfer basis not verifiable, left as the only `[PETER: …]`:** the DPF participant API has no
   entry for Anysphere, SpaceX Super Intelligence, SpaceXAI or xAI (active or inactive). Anysphere's
   DPA (cursor.com/terms/dpa, 2025-11-05) incorporates the 2021 SCCs (module 2) but applies under
   the Anysphere Master Services Agreement (Teams/Enterprise); Cursor's help page says the DPA does
   not apply to individual plans. Writing "SCCs" would claim a contract we cannot show.

## Job 24 (help and contact page, data map; privacy policy moved to 33a), 2026-10-30

1. **Scope after the split.** The brief predates three later rulings: 24a built the guides
   site (`site/`, its own Vercel project on hummlist.com), the Lead's 2026-10-30 07:52 ruling
   gave the privacy policy to 33a (#105) and the in-app privacy links (login footer, consent
   link, More → Datenschutz, `privacyPolicyUrl`) to 33b (#107). Job 24 therefore builds the
   help and contact page (`/support`, `/en/support`), the More entry "Hilfe & Kontakt", the
   data map (`docs/PRIVACY_DATA_MAP.md`) and the open items for Peter and the Lead. It touches
   33a, 33b and 33c landed while this job ran; it rebased onto them and uses their interfaces
   (`supportPublished`, `openLegalPage`, the launcher fake).
2. **Where the pages live: `site/`, not the app's web build.** The 2026-10-28 addendum puts
   legal pages into `site/content/legal/`. The app's `vercel.json` and build are unchanged, so
   app.hummlist.com answers /support, /datenschutz, /privacy and /impressum exactly as before
   (the SPA); nothing there needs a production-vs-preview proof any more.
3. **Unpublished draft = `draft: true` in the frontmatter.** hummlist.com is already live from
   `main` (24a, Peter 2026-10-27 22:12), so a gate in config alone would publish the page on
   merge. A draft page is built with a visible banner ("ENTWURF: Freigabe durch Peter" /
   "DRAFT: pending Peter's approval"), the same text in an HTML comment and
   `<meta name="robots" content="noindex">` in preview and local builds, and left out of Vercel
   production builds (`VERCEL_ENV=production`), where its path stays a 404. The whole site keeps
   sending `X-Robots-Tag: noindex` (24a) until the beta launch. Placeholders in a draft only
   warn; once published, the existing production check fails on any `[PETER:`. A footer link to
   a draft page fails the production build (broken-link check), so the footer flag cannot go
   on before the page. Publishing = drop `draft: true` from `support.md` and `support-en.md`,
   set the footer flag `supportPublished` (33a's) and flip
   `supportPagePublished` in `app/lib/app/guides.dart`: one small PR with Peter's OK.
4. **Paths.** German `/support` (footer label "Hilfe", as 24a set it), English `/en/support`
   like `/en/imprint` and 33a's `/en/privacy`. The only change to 24a's/33a's footer is the
   English support href `/support` → `/en/support` in `site/build.mjs`. The help page links the
   Impressum and the privacy policy.
5. **Contact.** support@hummlist.com, the address the published Impressum already gives. No
   new mailbox, no DNS. The page does not say who reads the mail: 33a's policy still asks
   Peter whether an AI assistant pre-sorts support mail.
6. **In-app link and its flag.** More → Feedback section → "Hilfe & Kontakt" / "Help &
   contact" (`more-help`, `helpRow`/`helpRowHint`), opening `supportUrl(languageCode)` (de →
   /support, otherwise /en/support) through 33b's `openLegalPage` (`LaunchMode.externalApplication`):
   the system browser, never a web view and never the app's own router. Shown when `supportPagePublished` (const,
   false) or `Environment.legalDrafts` (`LEGAL_DRAFTS`, default `kDebugMode`). So: on in debug
   builds and widget tests, on in e2e (`app/config/e2e.json`), off in release builds (store,
   TestFlight, app.hummlist.com and its Vercel previews). Deviation from the brief ("on in
   preview"): the link points at hummlist.com, where the draft is a 404 until publishing; the
   draft is only on hummlist-site's protected preview, so a row in the app preview would open
   a 404. Login footer and consent-screen links are 33b's.
7. **Proof of both states.** Site: `site/test/draft.test.mjs` builds preview (no env and
   `VERCEL_ENV=preview`) and production and serves each through `scripts/preview.mjs`
   (vercel.json's headers and clean URLs): 200 with banner, comment, meta noindex and
   `X-Robots-Tag` vs. 404 with the site's 404 page; a published simulation (draft line removed)
   has no banner and fails production on a placeholder. Removing the production filter fails 3
   of these tests (checked). App: widget tests for the DE/EN URL and the external mode, and
   More built with `showHelp: false` (as release) without the row; e2e `help.spec.ts` clicks
   the row in the e2e web build and checks the new tab's URL while the app stays put.
8. **Stale directions fixed.** The Siri guide, `docs/SIRI_SHORTCUT.md` and the voice function's
   401 text still said "Menü (⋮) → Zugänge" (the menu became the More tab in 29d). Now "Mehr →
   Zugänge"; the guide's `updated` is 2026-10-30. Same kind of fix 33a made on the deletion page.
9. **Data map.** `docs/PRIVACY_DATA_MAP.md` lists each data item with table/storage, purpose,
   basis, retention, processor/region, deletion path and the source file, for job 14's store
   forms and as the fact base of 33a's policy. Unknowns stay `[PETER: …]` as in 33a. No
   difference to 33a's draft found; two short-lived items the draft does not name
   (`invite_attempts`, about a day; function error logs, max. one day).
10. **Requirements checked (not legal advice; Peter approves, optionally a lawyer):**
    GDPR Art. 13 (information at collection: controller, purposes, bases, recipients, transfers,
    retention, rights, complaint; https://eur-lex.europa.eu/eli/reg/2016/679/oj);
    TDDDG §25 (consent for storing/reading non-essential information on the device; the
    analytics install id, job 19/33b; https://www.gesetze-im-internet.de/ttdsg/__25.html);
    DDG §5 (Impressum, live since 24a; https://www.gesetze-im-internet.de/ddg/__5.html);
    Apple App Review Guideline 5.1.1 (privacy policy link in App Store Connect and in the app,
    in-app account deletion; https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage),
    App Store Connect also requires a Support URL (this page);
    Google Play User Data policy (privacy policy link in Play Console and in the app;
    https://support.google.com/googleplay/android-developer/answer/10144311).
11. **Checks.** Site tests (`npm test`, 48, 8 of them for drafts), axe (WCAG 2.1 A/AA, light and dark: 0 violations)
    and 320/390/1366 px without horizontal scroll on both pages, HTML validated with
    html-validate (only `doctype-style`, the site's lowercase doctype), all run locally with
    Chromium and no Supabase. Lighthouse needs the deployed preview, which is behind Vercel
    Authentication; not run.
12. **Alexa in the privacy policy.** Job 31 asked "job 24's privacy page" to name the Alexa
    skill. Job 33f (#121) added that section ("### Amazon Alexa" in section 7) while this job
    was landing, so job 24 adds nothing to the policy; the data map has the Alexa and
    `analytics_consents` rows.
13. **Fix 1 (review 0).** The help page linked `app.hummlist.com/konto-loeschen`, which the app
    host (`cleanUrls: false`, SPA fallback) answers with the Flutter app; now `.html`, and
    `site/test/consistency.test.mjs` requires every `app.hummlist.com/<path>` link in
    `site/content` to be a file in `app/web`. The same test pins the three publish switches
    (`draft: true` in both help pages, `supportPublished`, `supportPagePublished`) to agree. The
    data map follows 33b/33g; the FAQ gains Alexa. Lighthouse mobile on the local preview build:
    100/100/100 (performance, accessibility, best practices), SEO 63 from the intended noindex.

## Job 32b (duplicate hint with one-tap merge, Spec #8 Part B), 2026-10-30

Peter's decisions (2026-10-29, verbatim):

- "Split it: category fix right after the feedback job, before Alexa; duplicate hint with or after onboarding"
- "Show a hint with a one-tap merge, still add by default"

The PM's merge rule (2026-10-29) and unit ruling (22:50), as built: g/kg and ml/l convert and
sum; Stück sums only with Stück; two items without a quantity merge as 2; anything else keeps the
open item's text and adds the other quantity as a note ("1 Bund + 500 g"); the merge runs on the
server in one transaction and is always undoable, also after other members synced.

The job's own calls:

1. **When the hint shows.** After the server acknowledges the user's own add: the server sets
   `items.canonical_key` (job 32a), so the app knows only then that "Karotten" is "mohr". The add
   itself never waits and is never refused for it. No hint for a partner's add (it is theirs to
   merge), a delete's undo, a retry or a realtime echo. An add made offline hints when it syncs.
2. **What counts as similar** (`public.similar_items`, mirrored by `similarItems` in
   `app/lib/list/model.dart`): another open item in the household with the same non-empty
   canonical key, unless brand or properties are set on both and differ ("Windeln Größe 3" and
   "Windeln Größe 4" are two things; "Milch" and "Milch Weihenstephan" may be one). The exact same
   text is still caught earlier and not added at all (job 2's duplicate check, unchanged). With
   several similar items the hint names the oldest.
3. **The hint lives where the eyes are.** While the add sheet is open it is a line under the
   added note ("✓ Hinzugefügt: Karotten", then "Möhren steht schon auf der Liste" with
   "Zusammenführen"; after a merge "Zusammengeführt: 1,5 kg Möhren" with "Rückgängig"), and the
   sheet may grow for it: a snackbar there would cover the sheet's own rows and its Rückgängig
   (a widget test tapped the wrong button that way). Typing the next item, the add's undo or a
   new add drop it (ignored). When the sheet closes with a hint or merge still open, it goes on
   as a snackbar (the existing `alreadyOnList` string with "Zusammenführen", six seconds,
   `persist: false` like the delete undo; the merge as "Zusammengeführt: …" with "Rückgängig",
   the actionSnackBar pattern). Adds made with the sheet closed (dictation, an offline add that
   syncs later) get the snackbar directly; it queues behind one already showing. A hint whose
   items are no longer both open (the add undone, a partner ticked one) goes away. The snackbar's
   action closes the hint itself: hiding it from the handler too would, with animations off (the
   web's semantics, screen readers), close the "Zusammengeführt" snackbar instead (seen on CI;
   a widget test with accessible navigation covers it).
4. **Merge = keep the open item.** It keeps its name, brand and properties; a brand or properties
   only the new item had fill the gap (nothing is lost; the hint only pairs items whose details
   do not conflict). The new item is deleted. Learning is off for the merge and its undo
   (`family_groceries.learning`): a merge is not a correction, and deleting the merged item must
   not take back what its add taught (store memory).
5. **Quantity terms.** A quantity is a list of "number unit" terms joined by " + ", so a second
   merge sums into the matching term ("1 Bund + 500 g" + "200 g" = "1 Bund + 700 g"). Sums of
   g/ml show in kg/l from 1000 up ("1,5 kg"), German decimal comma, at most four decimals.
   "1.000 g" (a point and three digits, not after a lone 0) is a thousand. Units other than
   g/kg/ml/l sum only with themselves, singular and plural as one ("1 Packung" + "2 Packungen" =
   "3 Packungen", case as the open item wrote it); cl is not converted (not in the ruling).
   Terms that are not a number and a unit ("etwas", "2x500 g") are kept as text.
6. **"1 + 1 = 2 Stück" is written "2".** The app stores a count as a bare number ("2 Gurken" is
   quantity "2"), so two items without a quantity merge to "2", and "2" + "3 Stück" to
   "5 Stück" (the word stays when one side wrote it). A bare number and Stück are both counts;
   the ruling's "unit" is a measuring unit.
7. **A missing quantity** is one piece only when the other side counts pieces ("" + "2" = "3");
   next to a measured quantity it adds nothing ("" + "500 g" = "500 g"): the note rule adds the
   other quantity, and there is none.
8. **Too long.** A merged quantity over the 40-character column is refused (22001), on the device
   before sending and on the server; both items stay and the list says "Möhren konnte nicht
   zusammengeführt werden". Nothing is cut.
9. **One rule, two places.** The server decides (`public.merge_quantities`); the app computes the
   same (`app/lib/list/quantity.dart`) only to show the merge at once, also offline. Both are
   tested against one table, `supabase/tests/merge_quantities.tsv` (the Dart test reads it, the
   db gate's `dedupe_integration_test.ts` runs it through Postgres), so they cannot drift.
10. **Undo storage.** `item_merges` keeps both rows as JSON (members read, nobody writes but the
    two functions; 30 days, pruned on the next merge in the household). `unmerge_items` puts the
    merged row back with its id, name, quantity, details, category, store, sort key, author,
    created time and `categorized_via`; a category or store deleted since is left out like any
    deleted one, an author whose account is gone too. The kept item gets its quantity and
    details back only if nobody changed them since the merge (a partner's later edit wins); a
    kept item deleted since stays deleted. Merge and undo are idempotent by the client's merge
    id, so retries after a lost answer change nothing.
    Account deletion: `merged_by` is set null by its foreign key, and a trigger on `auth.users`
    deletes clears the user's id from the stored rows (`added_by`, `bought_by`), for
    `delete_account` and for a delete from the dashboard alike; a deleted household takes its
    merges with it.
11. **App ops.** `MergeItems` and `UnmergeItems` are new `ItemOp`s, queued, retried and cached
    like every write; they fold over two items (`ItemOp.applyTo`). `ListRepository.send` now
    answers the rows an op touched by id, so a merge acknowledges both items at once.
12. **Non-UI paths (AC10).** MCP `add_items` returns `similarOnList: [{added, onList: [item]}]`
    next to `added` and `alreadyOnList`, and its description tells the model to mention it.
    Voice/Siri items carry `similarOnList: [names]` and Siri adds "Möhren steht schon auf der
    Liste." to the confirmation. Alexa (job 31, which landed while this was in review) adds
    through the same `voice/items.ts` and says "Möhren steht schon auf der Hummlist." (its own
    word for the list). All of them add normally; nothing merges.
13. **Analytics (AC11).** `dedupe_hint_shown` when the snackbar shows, then exactly one of
    `dedupe_hint_merged` (the action) or `dedupe_hint_ignored` (any other close: timeout, swipe,
    replaced); the undo sends nothing. Properties are only `actor_role` and `household_size`
    (job 19's allow-list, listed by 32a); never item names.
14. **No local stack on the Mac runner.** The SQL was developed against Postgres 17 binaries
    without Docker (the 32a recipe); CI's db gate (pgTAP, `supabase db lint`, the integration
    tests) and the e2e shards are the proof.

## Job 31b (deploy the Alexa skill, de-DE beta, no certification), 2026-10-30

1. **Reused what the cut-off attempt left.** It had created the skill, the OAuth client
   "Amazon Alexa" (redirects for the vendor id), the linking, the enablement, the beta test and
   the `ALEXA_SKILL_ID` secret. Checked each against the repo and SMAPI instead of creating
   anything twice: one skill for the vendor, one live confidential client (wrong secret refused,
   stored secret accepted by the token endpoint), the model identical to `de-DE.json`.
2. **Converged with the repo's own path.** `ask deploy --target skill-metadata` against the
   existing skill id (a gitignored `ask-states.json`), and the linking sent again with the stored
   secret, so the live skill is what the repo says and the documented redeploy is proven.
3. **`manifestVersion` moved into `manifest`.** ask deploy uploaded only `manifest`, so the
   live manifest lost `manifestVersion`. Restored it live, fixed `skill.json`, and a test fails
   on the old layout.
4. **Smoke test through `invoke-skill-end-point`.** The simulation API never dispatched to the
   skill (see NEEDS_PETER "Job 31b"). Ruled out by trying each: waiting about 15 min after the build,
   an explicit model rebuild (all steps SUCCEEDED), adding US to the distribution countries,
   `skipOnEnablement`, restoring `manifestVersion`; each reverted. Amazon-signed requests via
   `invoke-skill-end-point` reach the function, pass verification and get the link prompt.
5. **Beta left as found: running, 0 testers, no invites.** It was already started by the cut-off
   attempt; starting a beta needs no certification, and the brief allowed it. The invitation
   link stays out of the repo and the board.

## Job 34 (the add field drops the first key after Schließen), 2026-10-30

1. **Cause: the web engine's semantics text field takes over the DOM input one frame late.** With
   semantics on (always, on the web), a tap focuses the field's `<input>` at once. The engine asks
   the app to focus the field (`SemanticsAction.focus`), but it attaches its `input` listener only
   with the next frame's semantics update, and that update writes the app's text (empty) over the
   input (`semantics/text_field.dart`, `update()` -> `SemanticsTextEditingStrategy.activate` ->
   `DefaultTextEditingStrategy.enable` -> `setEditingState(lastEditingState)`). A key typed before
   that frame lands in the DOM, then is erased; the app gets only the keys after it. This is the
   gap 12b.6 found for `typeInto`. After Schließen the field is unfocused, so the next tap reopens
   that gap. The tap also opens the sheet, a heavy frame, and in the failed CI attempt (run
   41054432634) the "B" went out 5 ms after the click returned, while the close's 320 ms settle
   timer was due.
2. **Fix in the app: `EarlyKeys`, for every text field** (`app/lib/app/early_keys.dart`, started
   in `main.dart` next to `ensureSemantics()`, on the web only). It follows the primary focus.
   From the moment a text field gains it until the end of the next frame, a printable key down is
   typed into that field through `EditableTextState.userUpdateTextEditingValue` (so formatters,
   `maxLength` and `onChanged` apply as for any typed key) and marked handled. The app's text then
   holds the key, so when the engine attaches the input it writes the key back instead of erasing
   it. After the frame, keys are left to the input as before, so nothing is typed twice. Ctrl and
   Meta shortcuts and control characters are not typed; Ctrl+Alt is, since that is AltGr (@, €)
   on Windows. Native text input has no such semantics hand-over, so it is not started there.
3. **App-wide, not only the add field.** The first version wrapped the add field alone. Every
   other field (login, join code, edit sheet, feedback, ten in all) has the same gap: the login
   test below loses its first key without the fix. One handler at the root covers them all and
   new fields too, instead of a wrapper per field.
4. **Not chosen.** A wait in the test (12b.6 did that for `typeInto`, but this test is the user
   who taps and types at once). Keeping the add field focused after Schließen: any other blur (a
   tap on the list, the scrim) reopens the same gap, and other fields would keep it. Forcing a
   frame synchronously from the focus change: not a supported API. Fixing the engine: the app
   builds on stable 3.47.8.
5. **Regression checks.** `add-sheet.spec.ts` "after Schließen, a key typed before the next frame
   still reaches the app" (wasm and js) holds `requestAnimationFrame` back (`holdFrames`,
   `helpers.ts`), taps the field, types "B", releases the frames and types "rot" with the
   original 120 ms delay. Without the fix it failed 60 of 60 (30 wasm, 30 js; the row read "rot",
   or "ot" when the "r" also beat the released frame), the CI failure made deterministic.
   `auth.spec.ts` does the same on the login page's Passwort field (wasm and js); on the box
   (js build, no Supabase needed) it failed 5 of 5 without the fix ("heim-123") and passed 5 of 5
   with it. The widget test `app/test/app/early_keys_test.dart` covers typing in the gap,
   formatters, nothing typed after the frame, refocus, shortcuts and AltGr; with the handler off,
   the 4 gap tests fail. The original test keeps its assertion.
6. **Numbers** (on demand e2e, `-g Schließen`, one shard). Before the fix, run 41062722302 on
   5c07a0b, `--repeat-each=30`: the original test failed 1 of 30 ("rot, Wie getippt", no host
   stall), the new test 60 of 60. With the first (add field only) version, run 41063065757 on
   1ac2a11, `--repeat-each=40`: 120 passed, 0 failed, 0 flaky. The app-wide version, run 41066142423 on d95bc72, the
   add sheet and login tests (`-g "Schließen|next frame"`), `--repeat-each=40`: 200 passed, 0
   failed, 0 flaky.
## Job 25: Hummlist Lifetime in-app purchase (sandbox), 2026-10-30

The brief's calls are the Lead's defaults; each is in NEEDS_PETER "Job 25" as "confirm or
change". Overview: docs/PURCHASES.md.

1. **Product.** One non-consumable, `com.hummlist.app.lifetime` on both stores (Play allows dots
   in product ids, so no separate `lifetime`), reference and display name "Hummlist Lifetime"
   (DE and EN), EUR 9.99 with Germany as the base territory; every other territory uses the
   stores' automatic prices. The AT and CH prices cannot be read before the product exists (both
   need the Paid Apps agreement or the payments profile); `scripts/iap/apple_product.ts` and
   `google_product.ts` print them, and the Lead adds them here (NEEDS_LEAD P1, P5). Single source
   of id, names and price: `scripts/iap/product.ts`, pinned to the StoreKit file and the
   function by `product_test.ts`.
2. **The unlock is the household's, per purchase.** `purchases` holds each store transaction once
   (unique per store and transaction id); `entitlements` maps a purchase to at most one household
   (`purchase_id` is its key), and a household is unlocked while it has at least one row. It stays
   with the household where it was bought when the buyer joins another household or deletes the
   account. Restoring it elsewhere answers `used_elsewhere` while that household exists; once it
   is deleted (its last member left), the purchase unlocks the household it is restored in. A
   second purchase in the same household (the partner on another store account) adds a second
   row, so refunding one keeps the other's unlock.
3. **Family Sharing off** (`familySharable: false`, the StoreKit file too).
4. **Nothing gated.** `Entitlements.isUnlocked` exists; no feature reads it yet.
5. **Web never sells**, the fake store included; More shows the iOS/Android note and the unlock.
6. **Apple: verified locally, then with Apple when a key exists.** The chain check follows Apple's
   App Store Server Library (pinned G3 root by bytes, WWDR and receipt-signing OIDs, validity at
   `signedDate`, ES256). No OCSP: with the In-App Purchase key, Get Transaction Info is asked on
   the environment's host (from the JWS), and Apple's current record decides; without the key a
   refund still arrives as a notification. Forum reports show sandbox ids against the production
   host failing, so the host follows the JWS's `environment`, not a fallback on 404.
7. **Which environments unlock is configuration.** `PURCHASES_ENVIRONMENTS` lists them; a Sandbox
   JWS against a Production-only configuration is refused (the brief's case, tested). The hosted
   project needs `Sandbox` for TestFlight now and `Production,Sandbox` from the App Store review
   on, because App Review buys in the sandbox; sandbox purchases never count as revenue (8, 12).
8. **Google: a JSON key, and a daily poll for refunds.** The edge function cannot use the keyless
   GitHub federation of job 23's `play-release` account, so a separate service account with a
   JSON key, set only as a function secret by the Lead. Real-time developer notifications need a
   Pub/Sub topic, which needs Cloud billing (not allowed), so `purchases-voided.yml` polls the
   Voided Purchases API daily, 7 days back (idempotent). The function acknowledges after the
   unlock (Play refunds unacknowledged purchases after 3 days); the app's `completePurchase`
   acknowledges too. `purchaseType` 0 (license test) is Sandbox; promo and rewarded grants are
   Production. A canceled purchase counts as revoked. A test purchase without an order id gets
   `token:` plus a hash of the token as its transaction id. Google fixtures are built from the
   documented response shapes, not recorded (no Play access yet); the first live run checks them.
9. **Account deletion and tax.** The purchase row loses its buyer (`user_id` set null) and stays,
   without a person, to match refunds and stop a second unlock; the household keeps its unlock;
   a deleted household takes it along. Hummlist issues no invoices and keeps no tax records about
   buyers: Apple sells as commissionaire (Schedule 2 exhibits of the Apple Developer Program
   License Agreement), Google as merchant of record and remits EU VAT (Google Play Payments
   Center help, "Region and country-specific guidelines"). The export has a `purchases` section.
10. **Inert until configured.** Without `PURCHASES_ENVIRONMENTS` every route but `GET` answers 503
    `not_configured`; without a Google key Google answers 503; a key Apple or Google refuses is a
    503 that reaches error tracking. A deploy before the store setup unlocks nothing.
11. **Idempotent and replay-safe.** `purchase_grant` inserts on conflict nothing, then locks the
    row, so a double tap, a retry after a lost answer and a restart mid-purchase all converge on
    one row and one unlock (`restored` the second time). `purchase_revoke` acts only on the
    `revoked_at` null → set transition, so `purchase_refunded` goes out once however often Apple
    or the poll repeat themselves. 20 verifications a minute per user.
12. **Analytics from the server, for the buyer's consent.** Job 19 planned the app to send its
    install id and consent with the purchase; since job 31 the server knows each user's newest
    answer (`analytics_consents`), so the function uses that, also for refunds, which carry no
    install id. `purchase_restored` only when the user restored (the app says `source: restore`),
    never for a retry. A Sandbox purchase is `is_internal`, which takes its household out of the
    gate insights (`analytics/fixtures.ts` H8): a household that buys in the sandbox is a tester.
13. **Refund reversed.** Apple's `REFUND_REVERSED` clears `revoked_at`; the household it unlocked
    is no longer known, so it unlocks again on the next restore.
14. **Local testing without Apple.** `scripts/iap-test-ca.sh` makes an Apple-like CA (same OIDs)
    for the local stack, and the function serves `POST /purchases/test/sign` only when it trusts
    that CA, which `config.ts` allows only for the local stack's URL (the Alexa pattern). The app's
    fake store, fg and the e2e spec play the App Store through it; the real verify path runs.
15. **Privacy text as a draft page.** The policy is live on hummlist.com; unapproved text must not
    go there. The purchase section is draft section 5a on preview-only pages
    (`datenschutz-kaeufe.md`, `privacy-purchases.md`), moved into the policy after Peter's OK.
16. **StoreKit tests: written, not in CI yet.** `RunnerTests.swift` holds StoreKitTest XCTests
    (`SKTestSession` with `Hummlist.storekit`): product, purchase, restore, refund, Ask to Buy.
    In the `ios` gate on GitHub's macOS runner the test host app did not launch (run 41106494074:
    "(ipc/mig) server died" after 930 s; run 41110616634, one simulator booted, no parallel
    testing: all three failed after 290 s with no assertion run). Two CI rounds spent; the gate is
    back to its compile check and `scripts/ios-storekit-test.sh` runs the tests on a Mac with
    Xcode (issue #130). Xcode signs those transactions with a local certificate (environment
    Xcode), which the server refuses, as it must; the server's own chain is proven with the test
    CA.
17. **No `appAccountToken`.** *Superseded by job 43 (DECISIONS 43, RevenueCat with the household
    id as App User ID): RevenueCat passes the household id to Apple as `appAccountToken`, never a
    user id; job 47 verified it in the SDK source (docs/PURCHASES.md "What Apple and Google
    receive").* It would hand Apple our user id; the server ties purchases to the
    session that verifies them instead.
18. **ASC product creation is a Lead step.** The App Store Connect API key is not on the job
    runners (Mac, Hetzner), so whether the API creates an in-app purchase before the Paid Apps
    agreement is active could not be tried here; `apple_product.ts` runs on the box (dry run
    first) and the manual steps are in NEEDS_LEAD P1.
19. **Plugin.** `in_app_purchase` 3.3.1 (resolves `in_app_purchase_storekit` 0.4.x, where StoreKit 2
    is the default and `serverVerificationData` is the transaction's JWS, and
    `in_app_purchase_android` 0.5.x on Play Billing), behind `PurchaseRepository` with the plugin,
    an unsupported (web, desktop) and a fake implementation (`app/lib/purchases/`).
20. **Finish only after the server's final word.** The app finishes a store transaction after
    `granted`, `restored`, `used_elsewhere`, `revoked` or `refunded`. Offline, 429, 401/403, 5xx,
    503 and also 400/422 keep it unfinished: StoreKit hands it over again at every start, and an
    unacknowledged Play purchase is refunded by Google after three days, which is right for a
    proof our server refused.
21. **Android start-up recovery.** Play does not hand unacknowledged purchases to the listener at
    start as StoreKit 2 does, so the app restores silently once per start in a household; only
    purchases Play has not acknowledged, or all of them after a tap on Restore, are verified.
22. **Ask to Buy does not block Buy.** iOS never reports a declined request, so Buy stays
    available while a purchase waits for approval (asking again is harmless); the first draft
    blocked it until the next start, changed in review.
23. **"Nothing to restore"** is shown 2 s after the store's restore call returned without a
    transaction: the plugin has no "restore found nothing" signal.
24. **Fake store** (`FAKE_STORE`, non-release builds, never on the web): scenarios `ok`, `pending`,
    `cancel`, `error`, `unavailable`, `offline`; it keeps what it sold in `fake_store.json` (app
    support directory), so a purchase interrupted by a killed app is verified at the next start
    like StoreKit's. fg builds pass `FG_FAKE_STORE` (default `ok`).
25. **One semantics node per block** on the Lifetime page, so a screen reader (and Flutter web's
    DOM) reads "Freigeschaltet …" as its own line instead of the whole page as one.
26. **Screenshots of native states** come from `app/test/purchases/screenshots_test.dart` (the
    real page in More with the fake store, Roboto and Material icons from the SDK): the Hetzner
    runner has no clang, CMake or GTK headers for a Linux desktop build. The web states come from
    the e2e spec on a real web build.
27. **Sandbox unlocks are marked.** `entitlements.environment` copies the purchase's. From App
    Review on the hosted project accepts Sandbox (7), so TestFlight testers and App Review get a
    real, lasting unlock; with nothing gated that costs nothing today. At launch Peter decides
    whether tester unlocks stay (NEEDS_PETER Job 25, item 8); dropping them is one statement:
    `delete from public.entitlements where environment = 'Sandbox'`.
28. **A refund before the first verification is recorded** (review finding). `purchase_revoke`
    inserts the unknown transaction as revoked (product, environment and purchase date from the
    notification; for Play's voided list, which names neither, the one product and Production),
    so a receipt saved before its refund never unlocks later, also when the first grant and the
    refund race (the insert waits for the concurrent one, then the revoke finds its row).
29. **Review fixes in the app and function.** A store `finish` that throws no longer leaves the
    page on "verifying" (the store hands the transaction over again at the next start); a user who
    left the household between the session check and the grant gets 403, not 500.
30. **A second Realtime channel.** `Entitlements` subscribes to `entitlements:<household>` next to
    the list's `household:<household>`. The live-sync spec "a change made before the channel is
    live" intercepted every channel's "Subscribed to PostgreSQL" frame and released whichever came
    first; when the entitlements channel won, the list never caught up (CI run 41116236878). The
    spec now holds back only the list channel's frames.

## Job 25b: Hummlist Lifetime review follow-ups, 2026-10-30

Job 25's review 0 (PASS) listed nice-to-haves that are real behavior gaps; these are the calls.

1. **A refused proof is a final word: the app finishes it.** The function answers 400 or 422
   for a proof it will never accept as sent: wrong environment, product or app, a forged or
   malformed JWS, a purchase the store does not know. The app used to keep such a transaction
   unfinished, send it again on every retry and session change (each try spends one of the
   user's verifications before the refusal), show the error with a Retry that could not help,
   and get it from the store again at every launch. Now `VerificationRefused` is its own answer,
   next to `Verified`: the cubit finishes the transaction with the store and shows one note
   (`lifetime-not-accepted`, "… tippe später auf „Käufe wiederherstellen“"), without Retry.
   Offline, 429, 401/403 and 5xx (502 store unavailable, 503 not configured) stay
   `VerificationFailed`: unfinished, sent again on retry, on session change and at the next start.
   Why finishing can't lose a purchase that would verify later (for example after
   `PURCHASES_ENVIRONMENTS` changes):
   - Finishing a non-consumable only tells the store the app has handled it. It is not consumed
     and not refunded. A restore the user asks for hands it over again. On iOS the plugin's
     `restorePurchases` reads `Transaction.currentEntitlements`, which holds finished
     non-consumables until a refund. On Android it calls `queryPurchases(inapp)`, which returns
     every owned purchase, acknowledged or not. The cubit verifies a restored, already finished
     transaction only when the user asked for the restore, with `source: restore`. The server
     then decides under its configuration at that time. A refusal writes nothing on the server,
     so nothing blocks a later grant (`purchase_cubit_test.dart` covers the refusal, then a restore
     that grants).
   - Leaving it unfinished doesn't help, and on Android it does harm. Only a change on the server
     changes the answer (its environment list, a code fix), and the app can't see that change. A
     purchase that stays unacknowledged for three days is refunded by Play, so keeping it open is
     what would lose it there.
   - The note tells the user how to get it back: restore later. Peter or support can tell them
     the same once the configuration is fixed.
2. **Production without Sandbox makes the function inert, not refusing.** Take the case of a
   TestFlight or App Review purchase against `PURCHASES_ENVIRONMENTS=Production`. App Review buys
   in the sandbox for every submission, and so do TestFlight testers. With such a list, every one
   of those purchases would get a 422 `wrong_environment`, which is now final for the app (1),
   and only a manual restore would bring it back. So `configFrom` doesn't accept that list. With
   Production but no Sandbox it logs an error and leaves `environments` empty. Every verification
   then answers 503 `not_configured` (`GET /purchases` shows `configured: false`), and 503 is
   transient: the app keeps the purchase unfinished and verifies it by itself as soon as the list
   is fixed. The two valid settings stay as in docs/PURCHASES.md: `Sandbox` before review,
   `Production,Sandbox` from review on. Sandbox purchases are marked internal and their unlocks
   are marked Sandbox (25.27), so accepting Sandbox in production costs nothing.
3. **A notification's transaction must come from the notification's environment.** The handler
   checks `data.environment` against the allowed list, then acts on `signedTransactionInfo`.
   `appleNotification` now refuses a payload whose transaction has a different `environment`
   (`environment_mismatch`, answered 400, nothing changed). Apple signs both, so a mismatch can't
   be forged. The check makes "the environment we checked is the one we act on" hold by
   construction, and the transaction's environment is allowed through the outer check.
4. **`scripts/gates/e2e.sh -- <spec>` narrows to the spec.** Playwright ignores every argument
   after a `--` and runs the whole suite, which the reviewer hit (18 minutes instead of one spec).
   The gate now drops a leading `--`, so `e2e.sh -- <spec>`, `e2e.sh <spec>` and `verify.sh --only
   e2e -- <spec>` all run one spec. `scripts/e2e-gate-test.sh` (lint gate) runs the real gate
   with the stack, the build and Playwright stubbed out. It checks the arguments Playwright gets
   and when the fg sync smoke test runs.

## Job 37: stale "Menü" directions, health comment, debug-entrypoint Zone mismatch, 2026-10-31

1. **`bootstrap(binding)` in `lib/main.dart` takes the binding.** The Marionette entrypoint
   initialized its binding outside the zone `runApp` runs in, and Flutter's "Zone mismatch"
   assertion printed an EXCEPTION block on every debug launch. `main()` is now
   `bootstrap(WidgetsFlutterBinding.ensureInitialized)`, and `test_driver/main_marionette.dart`
   calls `bootstrap(MarionetteBinding.ensureInitialized)`. Each binding starts inside the one
   `runZonedGuarded` body at the old spot, so the release entrypoint keeps its order and error
   reporting. Rejected: a second `runZonedGuarded` in the debug entrypoint. It would nest a zone
   around the app's own zone, and the debug app would report errors differently from the
   release app.
2. **The l10n string `menu` is gone.** Nothing read it after the More tab replaced the list
   menu (job 29d).

## Job 38: hummlist.com guides follow the live store version; public release record, 2026-10-31

1. **The record is `releases/releases.json`, checked by one module.** `site/releases.mjs`
   (`parseRecord`) is the format: the site build, the site tests and
   `scripts/release/record.mjs` all go through it, and it rejects unknown fields. It lives in
   `site/` because the site is the record's reader and its build must start even when Vercel can't
   see files outside `site/`, so that the missing record fails with our message instead of a
   module-not-found trace. The brief's shape stays, with two changes. `identities` (name, GitHub
   login, bot flag, e-mail addresses) is added: main's 98 commits carry the bot under two addresses
   (`…+petertrost-bot@users.noreply.github.com` and `bot@petertrost.com`) and `Co-Authored-By:
   Claude <noreply@anthropic.com>` trailers on 68 commits. Neither dedupe by address nor a name
   heuristic would merge the bot and mark Claude as a bot. Peter's login `peter-trost` is the repo
   collaborator of that name. `channel` allows only `public` so far, so a typo can't hide a release.
2. **Consistency is checked, not trusted.** `day` must equal the days from `day_zero` (day 0,
   2026-10-22, the first commit) to `date`. Versions are strict `MAJOR.MINOR.PATCH`, unique and
   ascending. Builds go up and dates don't go back. `previous_sha` must be the previous
   release's `sha` (`null` for the first). The file is sorted oldest first and written in one
   canonical form, so a record commit's diff is just the new entry.
3. **Stats are computed once, at record time.** `commits` counts `previous_sha..sha` (everything
   up to `sha` for the first release). `additions`, `deletions` and `files_changed` are the net
   diff of that range, the numbers GitHub's compare view shows. Each contributor gets the commits
   they authored or co-authored (`Co-authored-by:` matched case-insensitively), deduplicated per
   commit, with those commits' added and deleted lines. A commit by the bot with Peter as
   co-author counts for both, so per-person lines can add up to more than the net diff.
4. **Live version.** It is the newest `public` release's version. Before the first public release
   it is the version in `app/pubspec.yaml` on the built commit, which is what TestFlight and Play
   internal testers get from `main`, so today everything that has reached the testers shows. The
   record must always be readable, and the pubspec whenever there is no public release. A missing
   file fails the build and names the Vercel setting, so a project that stops seeing files outside
   `site/` fails loudly instead of showing everything. The build logs one `live version:` line.
5. **One tag, three levels.** It is `since: X` in a guide's frontmatter, `{since=X}` in a heading
   suffix (with `{#id}`), and a `::: since X` container (markdown-it-container) for blocks. The
   container is a block rule, so it never fires inside a code fence; the hiding runs as a core
   rule over tokens, not as text preprocessing. Production leaves unreleased content out
   entirely, and a link to an unreleased guide fails the production build like a link to a draft.
   Preview and local builds show it with the draft banner ("Ab Version X, noch nicht im Store").
   `since` is refused on legal pages and indexes, which aren't versioned.
6. **The "Ab App-Version X" note** shows only for content newer than the first public release.
   Before that there is no public version to compare against, so it never shows today.
   A section or block shows no note when its guide's own note already names that version or a
   newer one, and unreleased content in preview shows the banner instead (screenshots showed
   the same version two or three times on one page).
7. **Redeploy by commit, not by hook.** `public-release-record.yml` (dispatch and `workflow_call`,
   `dry_run` default true) runs `record.mjs` and pushes the entry to `main`. Vercel builds
   hummlist-site's production from every push to `main`, so that commit is the redeploy, with no
   deploy hook and no new secret. It can't start a store upload. A push with `GITHUB_TOKEN` starts
   no workflow (so no CI run and no Release run), and `plan.sh` counts only `app/` and
   `release.yml` as app changes (fixture test in `scripts/release/test.sh`). Unproven until the
   first real release: whether Vercel builds a push made by the Actions token. It builds every
   push by this author today, and the workflow commits as petertrost-bot. If it doesn't, the next
   merge to `main` builds the site anyway.
8. **History page (not built).** `/history` will render `releases` newest first from the record
   alone, with no git at build time. Each entry shows the date, `version`, "Tag N" / "Day N" from
   `day`, `stats.commits`, the net `+additions / -deletions` and `files_changed`, the contributor
   count, and the top contributors: `stats.contributors` sorted by `commits` (the record keeps
   that order), with humans and bots marked by `bot` and avatars from `github`. `notes.de` or
   `notes.en` follows the page locale. A totals row sums the entries, and "Tag N" since `day_zero`
   is shown in the header. Every page's footer gets a "Versionen" / "History" link once the page
   exists; with an empty record it would say "Noch keine öffentliche Version".

## Job 39: user-facing changelog from the PRs' notes, 2026-10-31

Peter asked for a changelog for the stores' "What's new" field and for interested users, like
x.ai/changelog/bot. He wants it automated, published only once a version is live, and limited to
changes users notice. Format and flow: `docs/CHANGELOG.md`.

1. **The note lives in the PR description, and the collector reads it from git.** push-pr.sh
   already lands the description as the body of the one commit `main` takes. So
   `changelog.mjs draft` reads the notes with `git log --first-parent` and needs neither the GitHub
   API nor a token. This also covers PRs that GitHub shows as Closed after a landed merge (#118),
   and the tests run against a scratch repository. A commit without a section counts as `none`.
   Old PRs are not backfilled.
2. **The format is strict in structure and lenient in wording.** An item is a paragraph: a
   category line, a `de:` line and an `en:` line, or the section is just `none`. Case, a trailing
   colon, list dashes and the German category words (`neu`, `verbessert`, `behoben`, `keine`) are
   accepted. An unknown category, a missing language, an empty or duplicate line, `none` with
   items, an empty section or two sections are errors with a message. A paragraph that is neither
   an item nor `none` ends the section, because the agents' "Generated with" line and trailers
   follow it. But a later paragraph that looks like an item is an error, so a note can't be lost
   silently. An untouched template (only the comment) is an empty section, so an error: the author
   has to choose. The wording itself (one sentence, user words) is guidance for the author, not a
   check.
3. **A missing section means `none` only when nothing users could notice changes.** The brief
   ties this to the Release run's rule (`plan.sh ships-app`: `app/` or `release.yml`), and that
   rule is reused. The review showed the rule alone gives `none` silently to an Alexa, Siri, MCP
   or classifier change: those go live from `main` without an app release, and the brief's own
   example item is an Alexa feature. So `supabase/` and `alexa/` also need a written section
   (deviation from the brief). For an internal backend change, the author writes `none`, one
   word. Such a note lands in the next release's changelog, the first store version that
   carries it. A Dependabot branch gets `none` as well, matching the CI
   skip, since a dependency bump is no change users see. push-pr.sh adds the line to the PR description with
   `gh pr edit` before it squashes, so the description and the landed commit agree, and
   merge-pr.sh's stale-description check still holds.
4. **The CI check is a small gate of its own, `changelog`.** `check-gates.sh` requires every check
   to be a gate script with a job of the same name in `ci-ok`'s needs, so it can't be a step in an
   existing job. The job is a checkout (depth 2) and node, which the runner already has, and takes
   seconds. It runs on `pull_request` only, and is skipped by job-level `if` for Dependabot (actor
   or `dependabot/` head ref). A skipped job is neither failure nor cancelled, so `ci-ok` stays
   green on #33 and #34. It checks the PR head's message (`HEAD^2` of the merge checkout). When
   that message has no section (a head pushed with plain `git push`), it checks the description in
   the event payload instead, which is what merge-pr.sh's squash would land. A non-app PR without
   a section passes there, as push-pr.sh will add `none`. Locally (verify.sh) the gate checks
   HEAD's message only if it has a section, because branch commits are working commits until
   push-pr.sh squashes them.
5. **Store limits are counted the strict way.** Apple documents "4000 characters", but fastlane's
   pilot cuts at 4000 UTF-8 bytes, so the App Store text is counted in bytes ("ä" counts 2). Google
   Play documents "500 Unicode characters per language", counted as code points after NFC. That is
   never fewer than the characters a person sees. When a text is too long, whole items go from the
   end, fixed first, then improved, then new, and a line with the anchored URL
   (`hummlist.com/de/changelog#v1-0-0`) follows. Sentences are never cut. Emoji and `<` are
   stripped from both stores' texts, like pilot's `sanitize_changelog`, so both texts are built by
   one rule. "Emoji" is what renders as one: emoji presentation, or a pictograph with the emoji
   selector U+FE0F. That is close to pilot's RGI emoji set. ©, ™, arrows and a plain ✔ are text
   and stay. A space left before punctuation is removed, and an item that is only emoji gets no
   line. The site keeps the items as written. `parseRecord` and `parseDraft` reject any store
   text over its limit, also one edited by hand. Bullets are `•`, plain text, no Markdown, since
   neither store renders it.
6. **Order and duplicates.** Within a category, items keep merge order, oldest first, so a release
   reads like its history. A second item with the same German and English sentence is dropped, even
   in another category; the first one wins. Each item keeps `pr` and `sha` for tracing; the site
   never renders them.
7. **A draft is never overwritten.** `draft` refuses an existing file unless `--force`. Detecting
   "edited" would need a fingerprint field, and merging regenerated items into reviewed ones has
   no right answer when wording changed. Rather than regenerate, a reviewer edits the file by hand
   and runs `changelog.mjs store --version X`, which rewrites only the store texts from the edited
   title and items. The changelog gate (`changelog.mjs drafts`) and `record.mjs` refuse a draft
   whose store texts don't match its title and items. Without this, a reviewed item could show
   on hummlist.com while the stores say "Bug fixes and improvements." (found in review). The
   title starts empty: the script doesn't propose one, because a headline
   built from item sentences would be invented wording. `draft` prints a reminder instead.
8. **An invalid note on main stops the draft.** CI makes this unlikely, but if it happens,
   `draft` names every bad commit. `--skip <sha>` passes over one after its item has been written
   into the draft by hand. A silent skip would lose a user-visible change.
9. **Handover: the draft moves into the record and the file is deleted.** `record.mjs add` copies
   `title`, `items` (with `pr` and `sha`) and `store` into the entry as `changelog`, and deletes
   `releases/changelog/<version>.json` in the same commit. The workflow stages all of `releases/`.
   Keeping the file with `status: released` would leave two copies to keep in sync. With `pr` and
   `sha` in the record, nothing is lost. Without a draft the release is recorded without
   `changelog`, with a warning. A draft collected from another range than the release's warns but
   doesn't stop: the reviewed text is what Peter approved. `notes` keeps its job 38 meaning (free
   text from the workflow inputs) and is not filled from the changelog, so no 38 field changes
   meaning or shape.
10. **History compatibility.** `changelog` is an optional, additive field, and `parseRecord` is
    strict only when it is present. Job 38's entries and tests pass unchanged, and no 38 field was
    renamed or restructured. The planned `/history` page can read `changelog.title` as each
    entry's headline next to the stats.
11. **The site lists every public release.** The brief says both "only releases that have a
    changelog" and "a public release without a changelog shows version, date and 'Fehlerbehebungen
    und Verbesserungen.'". The second is the more specific rule, and hiding a public release would
    make the list look like versions are missing, so every public release is listed. Drafts are
    validated in every build, production included. A broken draft fails the build loudly instead
    of disappearing. CI's site gate builds the same files before anything reaches main.
12. **Footer.** The link „Neuigkeiten“ / "What's new" is the last item in the existing footer nav.
    That nav is labelled "Rechtliches" / "Legal" and already holds "Hilfe". Relabelling it would
    change every page beyond the one added line, so it stays for now. The page carries no
    page-level noindex: like job 38's unreleased sections, a draft is marked by its banner. Preview
    deployments are behind Vercel's login anyway, and `site/vercel.json` is unchanged.
13. **This PR's own note is `none`.** It adds a page to the site and tooling around the release;
    the site is not an app release, and nothing in the app changes.

## Job 40: flag- and hold-gated changelog items, the 1.0 launch text, 2026-10-31

Peter decided on 2026-10-31: (1) 1.0 gets its own "What's new" for first-time users, short, the
standout features, no "improved/fixed" against the beta; (2) a feature behind a feature flag, or
not certified yet (the Alexa skill), stays out of the public changelog until everyone has it.
Format and flow: `docs/CHANGELOG.md`, "Gated items" and "Override".

1. **The gate source is a repo file, `releases/flags.json`.** The app has no feature-flag
   mechanism: `grep -rniE "featureflag|feature_flag|isFeatureEnabled|getFeatureFlag|remote.?config"`
   over `app/lib`, `supabase/functions` and `alexa/` finds nothing. PostHog is analytics only, and
   job 19 chose not to load its SDK partly so that no flags are fetched (Job 19, item 1). The
   collector stays offline, so the file is edited by hand when a rollout changes. If the app
   later adopts PostHog flags, the file is still set by hand when a flag reaches 100 %. A later
   job may add a read-only comparison, never against project 262464.
2. **Unknown keys are errors at every step, PR time included.** `changelog.mjs check` (push-pr.sh,
   the CI gate) refuses a `flag:` or `hold:` key that `flags.json` doesn't list, and so do
   `draft`, `drafts` and `record.mjs`. So a PR that adds a flagged item adds its flag in the same
   PR, a typo can't make an item public, and a flag can't leave the file while an item in a
   draft or `pending.json` still names it.
3. **`pending.json` is written by `record.mjs add`, not by `draft`.** Had `draft` moved items
   in and out of `pending.json`, a draft that took an item out (its gate open) and was then thrown
   away or redrafted would lose that item for good: its commit is before the previous release,
   so no later range sees it again. `draft` only reads `pending.json` and lists the closed items
   in the draft's `held`. `record.mjs`, in the one release commit, sets `pending.json` to the
   draft's `held` plus the gated items of commits after the draft's `--sha` (never reviewed; without
   a draft, the whole range plus what was pending). It refuses when an item pending before is
   neither published nor held by the draft (matched by commit, flag and hold, so reworded items
   still count). A job 39 draft without `held` leaves `pending.json` as it is. Throwing a draft
   away therefore costs nothing, and the record and `pending.json` change together.
4. **Released items keep their `flag` / `hold` field** in the draft and the record, for tracing;
   the site never renders it. Within a category, items from `pending.json` come first (older
   merges), then the new range, in merge order; the job 39 dedupe by sentence runs over both.
5. **Alexa is held by `match` words, not only by the author remembering `hold:`.** The hold
   `alexa-certification` (`released: false`) lists `match: ["alexa"]`. While it is not released,
   `check` refuses an item that mentions Alexa as a whole word (German or English) without that
   hold. `draft` and `record.mjs` hold back such an item if one reaches `main` anyway, and `draft`
   warns. No item on `main` has a note yet besides `none` (the 1.0.0 dry run collects 0 items),
   so no existing Alexa note needed changing. The examples in the template, `docs/CHANGELOG.md`
   and push-pr.sh's format message now carry `hold: alexa-certification`.
6. **The override replaces the title and both store texts, and the items stay.** The site keeps
   listing the collected items under the override's title. A version's page is its history, and
   the items are what Peter reviews in the draft anyway. For 1.0 he can delete items there (beta
   fixes, for example). A separate site summary would have been a third text to keep in sync.
   The store text is used exactly as written. The title is not put in front of it, so the
   writer decides what the store shows first. One text without `### play` / `### app_store`
   blocks serves both stores and must fit Play's 500. Limits and stripping are job 39's
   (Play 500 code points, App Store 4000 UTF-8 bytes, emoji and `<` removed).
7. **`status: draft` blocks `record.mjs add`, and a dry run only warns.** Peter's approval is
   deleting that line in a PR. The Public release record workflow's dry run still shows the
   entry while the text waits for him. The override is deleted with the draft when the version
   is recorded, because the record holds the texts from then on. An override without a draft
   can't be recorded, since the release would silently lose its texts.
8. **The 1.0.0 text was checked against the app on main.** Stores are grouped, but the order
   through the shop is set by the user ("Reihenfolge bearbeiten"), not learned, so the text says
   "in the order you walk through the shop". Siri needs a Shortcut on iPhone ("auf dem iPhone
   auch mit Siri", "a Siri Shortcut"). The in-app mic exists on iOS and Android, which is what the
   store texts are for. AI assistants (MCP: Claude, ChatGPT) can read, add and check off.
   Suggestions are "Schon mal gekauft" / "Wieder fällig". Offline sync exists. No Alexa, no beta
   comparison. The test `the 1.0.0 launch text` checks the limits, that it is still a draft, and
   that it contains none of Alexa, beta, improved or fixed.
9. **What gets published is checked again at the end, not only at draft time** (from the
   independent review). The changelog gate and `record.mjs` run every published item through the
   gates again and scan titles, store texts and overrides for held words. They refuse a draft
   collected at a commit that is not the release commit or an ancestor, and a draft without
   `held` while `pending.json` has items. Before this, a flag set back to `partial`, a hand edit,
   an "Alexa" in the override or a draft from another branch could publish a held item or lose a
   pending one. Held words match at a word start (soft hyphens removed), so German forms such as
   "Alexas" and "Alexaskill" are caught. A name such as "Alexandra" would be held too, which fails
   safe. A note reverted and relanded is pending once, not twice.
10. **This PR's own note is `none`.** It changes release tooling and docs; nothing in the app.

## Job 43: Hummlist Lifetime as a household-bound unlock (model A), 2026-10-31

Peter chose model A on 2026-10-31 (relayed by the Hummlist PM, final wording 13:26 CET), with
five addenda the same afternoon: archive on last leave, tester grants, Legal Review H-49 to H-56,
RevenueCat instead of our own store verification (Peter, 14:03), and Legal Review's conditions for
RevenueCat (ADDENDUM 5). Entries 1 to 19 were written for the self-verifying design; where 20 and
later change them, the later entry wins.
Migration `20261031123504_household_bound_lifetime.sql`; docs/PURCHASES.md has the behavior.

1. **A purchase is bound to its first household, for good (supersedes 25.2's restore clause).**
   25.2 let a purchase unlock another household once its own was deleted. Peter: nothing moves
   with the user; Legal Review H-56: a restore only ever re-applies to the original household.
   `purchases.bound_household` is set at the first grant and never changed. It is not a foreign
   key, so deleting the household doesn't make the purchase look unbound. `purchase_grant`
   answers `used_elsewhere` for any other household, with `household_gone` when the bound one no
   longer exists (the app then says so instead of "another household"). The re-bind path is
   gone from the SQL (`purchase_grant` in both signatures), the function and the docs; the job 25
   migration's comment still describes it, because a migration on main is never edited. A
   `household_gone` flag rather than a new outcome: apps before job 43 parse an unknown outcome
   as a server failure and would retry it forever.
2. **Legacy rows that unlock nothing get the nil UUID.** Before this migration a purchase whose
   household was deleted, or that was refunded (the refund dropped its row), had no record of its
   household. Leaving it unbound would let its next restore bind it anywhere, the path H-56 rules
   out, so it is bound to `00000000-…`, a household that never exists. Only sandbox purchases
   existed (nothing was sold), so no customer loses anything. A refund reversed later
   (`REFUND_REVERSED`) now unlocks the purchase's own household again if it still exists.
3. **A second purchase in an unlocked household keeps its own row** (unchanged from 25), and
   `purchase_grant` says `already_unlocked` for it. It locks the household row
   (`for no key update`) so that of two purchases landing at once exactly one is flagged; that lock
   doesn't block item writes, whose foreign keys take key-share locks.
4. **Buy only on a known "no Lifetime".** `Entitlements.canOffer(Entitlement.lifetime)` is the one
   check; `EntitlementsUnknown` (loading, offline) says no, and the page shows a "Wir prüfen …"
   note. A member of an unlocked household whose phone is offline would otherwise see Buy and could
   pay twice. Restore stays available while unknown: it costs nothing.
5. **Refund help is a sheet, not a route.** It opens from the Lifetime page, the
   `already_unlocked` result, and the join screen. The join screen is also used before the user
   has a household, where `authRedirect` lets nobody into More, and a route would drop the join's
   state. Content: we can't refund; Apple's Report a Problem (https://reportaproblem.apple.com/,
   steps per https://support.apple.com/en-us/118223); Google Play's Budget & order history →
   Report a problem (https://support.google.com/googleplay/answer/15574897, read 2026-10-31);
   the reason "Mein Haushalt war schon freigeschaltet." StoreKit's `beginRefundRequest` is not
   used: `in_app_purchase_storekit` 0.4.15 doesn't expose it, and native code for one sheet isn't
   worth it.
6. **"Recent purchase" is 30 days.** `preview_invite`'s `recent_purchase` is the caller's own
   verified purchase (`purchases.user_id`), not refunded, bought in the last 30 days. Apple names
   no deadline for refund requests; Google's general rule is 48 hours for self-service and the
   developer after that, but its EEA and UK page (German buyers,
   https://support.google.com/googleplay/answer/15575720) offers the Play request form for in-app
   purchases without a deadline. 30 days keeps the link to cases where a request is plausible,
   without nagging people who bought long ago. Google buyers outside the EEA after 48 hours are
   referred to the developer by Google: NEEDS_PETER Job 43 asks whether Hummlist answers those.
7. **The join screen tells, never blocks.** (a) An unlocked target says "Du musst nichts kaufen."
   (c) With a recent own purchase it links the refund help. (b) The last member of an unlocked
   household sees what joining does (below) before joining. `preview_invite` computes all three
   flags server-side (purchases are service-only), only for a valid invite.
8. **Archive instead of delete (addendum 1).** When the last member leaves an unlocked household
   by joining another, `accept_invite(code, true)` archives it: `households.archived_at` and
   `archived_by` are set, the membership goes, list and unlock stay. Nobody can read an archived
   household (RLS is membership); its invites answer `invalid_invite` (`check_invite`). The
   archiving user lists it (`archived_households()`) and re-enables it
   (`unarchive_household(id, true)`, which leaves their current household like a join and makes
   them its owner). Only an unlocked household is archived; one without Lifetime is deleted as
   before, so archiving can't become a way to keep data indefinitely for free. The old signatures
   (`accept_invite(code)`, `leave_current_household()`) still delete, for apps before job 43.
9. **Declining the archive asks once more.** "Löschen und beitreten" opens a dialog: the household
   is deleted and its Lifetime is not refunded, with the refund help link. Cancel is the
   prominent answer on the join screen, as for every switch.
10. **The archive UI is off in releases (`HOUSEHOLD_ARCHIVE`, default false).** The live privacy
    policy §14, the support FAQ and `app/web/konto-loeschen.html` say the household is deleted
    when the last member leaves; Legal Review owns those texts. With the flag off the join screen
    shows the decline warning and "Trotzdem beitreten", which matches today's behavior; the
    server side, its tests and the widget tests for both states ship. e2e builds turn it on
    (`app/config/e2e.json`, like `LEGAL_DRAFTS`). Turning it on is a NEEDS_LEAD Job 43 step after
    Legal Review. A build define rather than job 40's `releases/flags.json`: that file is not on
    main, and it gates changelog notes, not app code.
11. **An archived household goes with its archiver's account.** `delete_account` deletes the
    households the user archived before it deletes the user: nobody else could ever re-enable
    them. `archived_by` is `on delete set null`, not `cascade`: a cascade raced the invites'
    `created_by` set null and failed the deletion (found by pgTAP). A user deleted outside
    `delete_account` would leave an unreachable archived household; that path is not used.
12. **Testers: a grant count; grants stay with households (addendum 2, supersedes the first
    design).** `lifetime_testers(user_id, grants default 1, note, added_at)`, service-only. A grant
    applies itself (`tester_grant_apply`, by trigger) to a household the tester is in that has no
    Lifetime: when they are added or their count is raised, and when they create or join one.
    Automatic rather than a button: the Lead decides who is a tester, and a button would be one
    more UI only testers see. Used grants are `entitlements` rows (`source` tester, `tester` the
    user, `on delete set null`), one per household and tester; lowering the count or removing the
    tester keeps them, like purchases. The note holds no names or e-mail; the script resolves the
    e-mail at run time.
13. **Sandbox and tester unlocks stay after launch (NEEDS_PETER Job 25 item 8, Peter
    2026-10-31).** Both are internal for analytics: the function marks a tester's purchase, and
    any purchase in a household a tester unlocked, `is_internal` (as for Sandbox); the app marks
    every event of a household whose rows include a tester grant (`isInternal`'s
    `testerHousehold`, fed from `Entitlements`), so the internal filter drops those households from
    every gate query. No new event or property.
14. **Members don't read who paid (H-55).** `authenticated` has column-level select on
    `entitlements` (`id, purchase_id, household_id, kind, source, product_id, store, environment,
    granted_at`), not on `granted_by` or `tester`. `select *` fails for a member, so the app and
    tests name their columns. Realtime still delivers inserts and deletes to the partner
    (`e2e/tests/purchases.spec.ts`, run against the restriction).
15. **An entitlement kind (forward-compat for model D).** `kind` on purchases and entitlements,
    checked `in ('lifetime')`; the function derives it from the product id in one map
    (`productKinds` in `purchases/types.ts`, pinned to `scripts/iap/product.ts` by
    `product_test.ts`); every product check goes through `kindOf`. The app asks
    `has(Entitlement.lifetime)`; an unknown kind unlocks nothing. Extension steps:
    PURCHASES.md "A second entitlement".
16. **Frankfurt (H-54).** The app's calls to `purchases` (now only the claim) pass
    `region: 'eu-central-1'` (`x-region` and `forceFunctionRegion`); RevenueCat's webhook URL
    carries `?forceFunctionRegion=eu-central-1` (entry 24). Supabase documents both
    (https://supabase.com/docs/guides/functions/regional-invocation, read 2026-10-31). The local
    stack ignores them.
17. **Analytics: paying households over WAH, no PostHog groups.** `paying_households_d35.sql`
    (cohort by the household's first event) and `paying_share_wah.sql` (the kill gate: the share
    of weekly active households with a non-refunded paid unlock by that week, at least 2 % in the
    Berlin week containing day 35 after launch) use `properties.household_id`; group analytics
    stays off. A refunded purchase never counts, as in `unlock_d35`. A buyer who declined analytics
    sends no `purchase_completed`, so the share is a lower bound. No new event was needed, so
    nothing waits in NEEDS_LEAD for a privacy-policy change.
18. **Web copy.** "Kaufen kannst du Hummlist Lifetime in der iPhone- oder Android-App. Danach ist
    es auch hier für deinen ganzen Haushalt freigeschaltet." No checkout, no external link.
19. **Changelog: one `new` item on hold `premium-launch`.** Job 40's `hold:` lines reached main
    while this job ran, so the brief's rule applies: one item describing the household-wide
    Lifetime and the refund help, held by the new `premium-launch` hold (`released: false` in
    `releases/flags.json`, `match: ["lifetime"]`, so any later item that mentions Lifetime must
    carry it). Nothing is sold or gated yet; releasing the hold is the launch's job.
20. **RevenueCat verifies; our function only listens (ADDENDUM 4, Peter 14:03: "Let's just use
    RevenueCat and let them handle it").** `apple.ts`, `google.ts`, the test CA and signer, the
    app's verify call, Apple's notification route, the Play voided poll and its workflow, and the
    `in_app_purchase` plugin are gone; `purchase_grant` is dropped. `purchases` receives
    RevenueCat's webhook and the app's claim. Sources (read by the Lead 2026-10-31): pricing
    https://www.revenuecat.com/pricing/, restore behavior
    https://www.revenuecat.com/docs/projects/restore-behavior, webhooks
    https://www.revenuecat.com/docs/integrations/webhooks and
    https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields (re-read
    2026-10-31 for the field list, the `X-RevenueCat-Webhook-Signature` format and the retry
    policy), identity https://www.revenuecat.com/docs/customers/identifying-customers, refunds
    https://www.revenuecat.com/docs/subscription-guidance/refunds, customer deletion
    https://www.revenuecat.com/docs/api-v1/customers, DPA https://www.revenuecat.com/dpa/,
    privacy https://www.revenuecat.com/privacy/.
21. **The RevenueCat customer is the household.** App User ID = `households.id`, never a user id,
    never anonymous, never `logOut`. With the project's restore behavior "Keep with original App
    User ID" (Ops), RevenueCat itself refuses a purchase restored or re-bought under another
    household; a deleted household's id is never reused. The server checks independently:
    `purchase_record` binds a transaction to `app_user_id` once (`bound_household`), refuses any
    other household, refuses an id that is no household, and refuses a tombstoned transaction.
    The rejected alternative (App User ID = user id, the webhook maps to a household) makes the
    purchase follow the person, against Peter's rule.
22. **The SDK starts late and knows nothing but the household (ADDENDUM 5, C3).** Configured only
    when the Lifetime page is open and Supabase says the household has no Lifetime; never at app
    start. No customer attributes, no device or ad identifiers, no integrations, no Paywalls or
    Customer Center. Two ast-grep rules make it structural: `purchases-flutter-only-in-revenuecat-repository` (only
    `revenuecat_repository.dart` imports the SDK) and `no-revenuecat-customer-data` (no `Purchases.set…`,
    `collectDeviceIdentifiers`, `enableAdServices…`, `logOut`). `purchases_flutter` ^11.0.0: the
    iOS app builds with Swift Package Manager (no Podfile), so the CocoaPods delay of 11.0.0 doesn't
    apply; Kotlin is 2.4 (11.0.0 needs 2.1).
23. **The buyer comes from a claim through the function, not a plain RPC.** H-55 needs the buyer
    recorded and hidden from members; analytics needs `purchase_completed` under the buyer's
    consent, which only the function can send (PostHog, `analytics_consents`). So the app posts
    `purchases/claim` with its session; `purchase_claim` checks membership and either sets the
    buyer (first member wins) or keeps the claim until the webhook arrives. `purchase_completed`
    goes out exactly once, from whichever of webhook and claim comes second
    (`purchases.completed_sent_at`). No claim: the unlock stands, the buyer stays unknown, no
    event. The transaction id the app claims is `StoreTransaction.transactionIdentifier`: the
    StoreKit transaction id on iOS, the Play order id on Android (RevenueCat's hybrid mapper
    returns `orderId` there, checked in `purchases-hybrid-common`'s `StoreTransactionMapper.kt`),
    matching the webhook's `transaction_id` (`GPA.…` in RevenueCat's Play samples).
24. **The webhook's security and region (C7).** The `Authorization` header is compared in
    constant time with `REVENUECAT_WEBHOOK_AUTH`; with `REVENUECAT_WEBHOOK_HMAC_SECRET` set, the
    HMAC signature over the raw body and a 5-minute timestamp window are required too. Event ids
    are stored in the same transaction as the writes, so a failed write (500) lets RevenueCat's
    retry run again, and a duplicate does nothing. The URL Ops registers ends in
    `?forceFunctionRegion=eu-central-1`.
25. **"Bought twice" comes from Supabase.** With RevenueCat there is no verify answer to carry
    `already_unlocked` to the buyer's phone. Every member's Lifetime page shows a note when the
    household has more than one purchase row, with the refund help. The SQL still computes
    `already_unlocked` for logs.
26. **Retention (ADDENDUM 4 proposal, ADDENDUM 5 conditions).** A deleted household's purchase
    rows go 30 days later (`purge_purchases`, pg_cron); each leaves only an HMAC-SHA256 of its
    store transaction id under one key (`REVENUECAT_TOMBSTONE_HMAC_KEY`, not a per-row salt, so a
    later event can be matched), with nothing attached. The HMAC is computed by the function when
    it records the purchase and stored with the row, so the database purge never needs the key.
    The RevenueCat customer is deleted by the function (entry 32). Webhook ids 90 days, unmatched
    claims 30 days.
27. **Tester grants count what they used** (review finding): `lifetime_testers.used` instead of
    counting live rows, which a deleted household would hand back. `tester_grant_apply` takes the
    same household lock as `purchase_record`.
28. **Join and archive can't race** (review finding): `accept_invite(code, archive)` takes a share
    lock on the target household and refuses an archived one before it uses the invite;
    `leave_current_household(archive)` locks the household it leaves before it counts the
    members. Without that, a join and the last member's archive could both commit, leaving a
    member in an archived household.
29. **The purchase screen is off by default (`REVENUECAT_PURCHASES`, ADDENDUM 5).** Until Peter
    approves the new legal texts, no build shows Buy or Restore, TestFlight and Play internal
    included; the page says "Hummlist Lifetime ist bald verfügbar." A build define like
    `HOUSEHOLD_ARCHIVE`, set only for Peter's own builds first.

30. **A late unlock never invites a second purchase.** After a purchase the page says "Wird
    freigeschaltet …" until Supabase's unlock arrives. If RevenueCat's webhook takes longer than a
    minute (retrying, an outage), the page says the purchase arrived and the unlock follows, and Buy
    stays disabled for that visit, instead of offering Buy again.
31. **What gets no claim.** A purchase approved later (Ask to Buy, a Play pending payment) and a
    restore send no claim: the app no longer holds that store transaction. The unlock still comes
    from the webhook; the buyer stays unknown and `purchase_completed` is not sent (the documented
    undercount). `productAlreadyPurchasedError` shows as a store error with its code; Restore
    resolves it.
32. **ADDENDUM 6 (the Lead's RevenueCat setup).** The webhook route is
    `/purchases/revenuecat/webhook`; a bare `POST /purchases` is 404. `REVENUECAT_WEBHOOK_AUTH`
    holds the whole header value, `Bearer ` included, and is compared whole. The app's SDK key
    defines are `REVENUECAT_APPLE_API_KEY` and `REVENUECAT_GOOGLE_API_KEY`. `REVENUECAT_SECRET_KEY`
    is a v2 key set as a function secret with `REVENUECAT_PROJECT_ID`, so the function deletes
    customers itself: `POST /purchases/revenuecat/deletions` calls API v2 `DELETE` and `GET
    /projects/{project}/customers/{id}` (v1's `GET /subscribers` would create the customer again).
    The route takes no input and only works the due queue (25 a run, each customer at most hourly),
    so it needs no auth; a daily workflow calls it. Every deleted household is queued, not only
    those with a purchase: opening the purchase page already creates the customer at RevenueCat
    (review finding).
33. **Second review's SQL findings.** `purchase_claim` takes the household lock that
    `purchase_record` takes, so a claim and a webhook arriving together always meet. The claim
    pickup reads one claim, then deletes all for the transaction, so claims for both of its ids
    can't fail the record. Refund-only rows without a household are purged after 30 days.
34. **The tester trigger takes no lock for non-testers** (found by CI's "two people racing for one
    code"). The grant trigger runs on every join; it used to lock the household before checking
    whether the joiner is a tester, which deadlocked against the other joiner's share lock (entry
    28). It now returns at once for anyone without an unused grant. Only a tester with grants left
    racing someone else for the same single invite can still deadlock; Postgres aborts one join,
    which the app shows as a failed join to try again.

## Job 44: all-in on PostHog: posthog_flutter, error tracking, feature flags, 2026-10-31

Peter decided on 2026-10-31: PostHog only, no Sentry or other vendor; what PostHog lacks goes
upstream. This reverses Job 19, item 1. Overview: [ANALYTICS.md](ANALYTICS.md); open steps:
[NEEDS_LEAD.md](NEEDS_LEAD.md), "Job 44".

1. **Versions.** `posthog_flutter: 5.58.3` (pub.dev, published 2026-10-30, the newest), pinned
   exactly in `app/pubspec.yaml`. Under it on the web posthog-js 1.444.0 (npm, 2026-10-30),
   vendored as `app/web/posthog/array.js` by `scripts/posthog-js.sh` (version and sha256 in
   `app/web/posthog/VERSION`). The plugin asks for posthog-android `[3.72.9, 4.0.0)`;
   `app/android/app/build.gradle.kts` pins 3.75.0 strictly, the version this job's research
   read. posthog-ios comes through Swift Package Manager as `3.92.3 ..< 4.0.0` with no
   committed lockfile, so an iOS build takes the newest 3.x (3.93.1 today; its diff to 3.92.3
   touches replay and stack frames only).
2. **The SDK is set up only after the yes, never before.** I read posthog-ios 3.92.3 and
   posthog-android 3.72.9/3.75.0: `optOut` does not stop the remote config
   (`/array/<token>/config`) or `/flags` requests, setup writes an anonymous id and a device id
   to disk even while opted out, and already queued events still go out. So opting out is no
   consent gate. `Analytics` calls `Posthog().setup()` only once the install's answer is yes,
   and `Posthog().close()` at a no. Before the yes the SDK makes no request and writes nothing:
   `analytics_test.dart` checks that not even `setup` reaches the native side, and the e2e spec
   checks that `posthog/array.js` is not even fetched. `com.posthog.posthog.AUTO_INIT` is false
   in the Android manifest and the iOS Info.plist, and iOS's push-open prewarm
   (`CAPTURE_PUSH_NOTIFICATION_OPENED`) is off, so nothing starts from the platform side.
3. **Off: close the SDK, then delete what it keeps on the device.** The More switch promises
   that off deletes the install id on the device (legal review H-08). `close()` keeps the native
   SDK's files: its anonymous id, a separate device id, queued events, cached flags and remote
   config, super properties. `reset()` cannot help: it keeps the device id and requests flags at
   once under a new id. So after `close()` the app deletes them itself (`forgetPostHogState`):
   on iOS the `posthog.*` files in `Application Support/<bundle id>`, on Android through
   `MainActivity` (`familygroceries/posthog`, `forget`) the `posthog-android-<token>`
   preferences, cleared with Android's API because the SDK also holds them in memory, and its
   queue folders; on Linux the SDK's folder. A start with a stored no deletes them again, so an
   off whose clean-up was cut short converges. The web keeps nothing (item 9). An event handed
   to the SDK just before the off is sent if `close()` gets it out at once, else deleted with
   the queue (Job 19, item 6 dropped it always). Nothing captured after the off is taken.
   Sign-out (Job 19, item 5) stops nothing: what the SDK holds is sent, and nothing is taken
   while signed out.
4. **The install id is the SDK's distinct id.** A yes makes a random id and seeds it as the SDK's
   bootstrap id. If the native SDK kept an id from an earlier yes on this device (bootstrap only
   applies while none is stored), `reset()` gives a new one and that is the install id. At a
   start with a stored yes the stored id is the bootstrap, so installs from job 19 builds keep
   their id and their cohort. The id is a UUIDv4 or, after a reset, a UUIDv7; both are accepted.
   The `DeviceCache` keys are unchanged (`analytics.install_id` etc.).
5. **Two gates on every Dart-side event.** `track` checks the event against `eventCatalog`;
   then the SDK's `beforeSend` (`Analytics._admit`) checks it and the context again, drops it if
   analytics is no longer live, and removes `$screen_name` (the facade adds the last screen it
   was told of; a route can carry an invite code; the app never calls `screen()`).
   `posthog-flutter-only-in-posthog-client` (ast-grep) keeps the SDK in
   `app/lib/analytics/posthog_client.dart`, so no other file can call `screen()`, `identify()`
   or `capture()` past the gate.
6. **Context changes.** `distinct_id`, `$lib` and `$lib_version` are no longer our properties:
   the SDK sets the event's distinct id and its own `$lib` (`posthog-flutter`, `posthog-ios`,
   `posthog-android`; `posthog-flutter` on the web). `event_id` is gone: its one use was PostHog's
   dedup by `uuid`, which the SDK now does itself (its uuid, sent again on a retry). No query
   reads either (`analytics/queries/`). `household_id` before a household is absent instead of
   null; HogQL reads both as null. Every other event and property name is unchanged; the job
   19/43 fixtures in `analytics/metrics_test.ts` pass unchanged.
7. **The context is also registered as super properties** (`install_id`, `household_id`,
   `platform`, `app_version`, `is_internal`, `$geoip_disable`), kept current on sign-in, household
   change and the internal mark. Events the native SDK builds itself, the native crash reports,
   never pass the Dart gate; this way they still carry `$geoip_disable: true` and `is_internal`.
8. **What the native SDKs add cannot be stripped from Dart.** `beforeSend` sees only our
   properties; posthog-ios and posthog-android add device and app properties afterwards (list
   in ANALYTICS.md, "What the SDKs add"), among them device model, OS version, locale, time zone,
   screen size, network type and, on Android, the carrier and the HTTP user agent, plus an
   in-memory `$session_id`. Both native SDKs have a `beforeSend` that could strip them, but the
   plugin exposes none. That is a change in what is sent: the sentences for the Legal Review are
   in NEEDS_LEAD "Job 44", and an upstream issue draft too. On the web we do strip them (item 9).
9. **Web: posthog-js from our origin, after the yes, stripped by our own `before_send`.**
   `loadPostHogJs` (`posthog_platform_web.dart`) injects `posthog/array.js` and calls `posthog.init`
   at the first start of the SDK: persistence `memory` (no cookie, no localStorage; the install
   id comes from our store as bootstrap at every page load), no autocapture, pageviews,
   pageleave, replay, surveys, heatmaps, dead clicks, rage clicks, web vitals or exception
   autocapture, `disable_external_dependency_loading`, no compression. Its `before_send` drops
   every event outside the catalog and every property outside `webEventKeys` (events.dart),
   which removes `$current_url`, `$pathname`, `$host`, `$referrer`, the user agent, `$session_id`,
   `$window_id` and `$device_id`. `opt_out_useragent_filter` is on: posthog-js otherwise drops
   events from user agents that look like bots (the e2e browser's "HeadlessChrome" among them),
   and only a signed-in user's yes loads it, so no crawler gets there.
10. **Web: remote config stays blocked.** For the EU host posthog-js fetches remote config from
    `https://eu-assets.i.posthog.com`. The app's CSP (`vercel.json`, `connect-src`) allows only
    `https://eu.i.posthog.com`, so that request fails and posthog-js runs on the local config
    above; it then loads flags itself. The CSP stays as it is: project settings cannot switch
    anything on in the browser. The e2e collector refuses the request the same way.
11. **Error tracking.** Dart errors go through our own hooks (`reportUncaughtErrors`: the
    framework's `FlutterError.onError`, still presented as before, and `PlatformDispatcher`; and
    the zone in `main`) into `Analytics.captureException`, which hands the error to PostHog's
    `captureException` with the scrubbed type and message (`errorType`, `scrubMessage`) next to
    it; `_admit` then replaces the SDK's `$exception_list` values with them, gives every cause
    `<redacted>`, keeps code locations only in frames, and drops everything else (also the SDK's
    `flutter_error_details`, whose text can hold widget descriptions such as `Text("Milch")`).
    The SDK's own Dart hooks (`captureFlutterErrors`, `capturePlatformDispatcherErrors`,
    `captureIsolateErrors`) are off: they would hand `beforeSend` only strings, and the scrubber
    needs the error. Native exceptions and crashes are on (`captureNativeExceptions`,
    `captureNativeCrashes`): iOS through PLCrashReporter (experimental at PostHog), Android for
    JVM exceptions and, from Android 12, native crashes read on the next launch. They need the
    project's exception autocapture setting, which Peter turned on in job 19. Gaps:
    ANALYTICS.md, "Error tracking".
12. **No isolate hook.** The app spawns no isolate (`grep -rn "Isolate\.\|compute(" app/lib`
    finds none). Errors in the main isolate reach the zone or `PlatformDispatcher`. A listener
    on the isolate would only get strings, which the scrubber reduces to `<redacted>`.
13. **Events captured while the SDK starts are kept.** Found on the Linux run: an item added right
    after the yes, while `setup` ran, was dropped. `track` and `captureException` now take the
    event at once, and hand it to the SDK after the start, with the context of that moment, or
    drop it if analytics is no longer live by then.
14. **Feature flags: `Analytics.flags`** (`Flags`, `app/lib/analytics/flags.dart`), the one place
    the app reads PostHog flags: `isOn(key)` is false for an unknown key, before the yes, after a
    no, in a build without a key, and offline until a first answer; later the SDK serves what it
    received last, also offline. Flags are read with `getAllFeatureFlags()` after the start and
    whenever the SDK reports new ones; `sendFeatureFlagEvent` is off, so reading a flag sends
    nothing. Only installs that said yes get flags at all: the flag request carries the install
    id. A rollout through a flag therefore never reaches users who declined; a feature that
    must reach everyone needs a release, not a flag. No flag exists yet; the Lead creates them in
    project 319492.
15. **`releases/flags.json` stays for the changelog.** It records which changelog items wait for a
    rollout or a hold (job 40); PostHog flags switch app behavior at runtime. When a feature
    behind a PostHog flag reaches 100 %, its key is set to `full` in `flags.json` by hand, as
    job 40 item 1 foresaw. Written down in CHANGELOG.md, releases/README.md and ANALYTICS.md.
16. **Edge functions keep their own sender** (brief item 6). A prototype ran posthog-node 5.61.1
    (`npm:posthog-node@5.61.1/edge`) in Supabase's edge runtime image v1.77.8 against a local
    collector. It works, but: `captureException` sends the raw message (an item name, an e-mail)
    and the node build adds source lines around each frame, so we would skip it and send our own
    `$exception_list` through `capture`; `$lib` cannot be set; by default a flush against a
    collector that answers 503 took 9 s and one that never answers 21 s (3 retries), so it needs
    `fetchRetryCount: 0` and `requestTimeout` plus our own try/catch for the never-throws
    contract; 6.4 MB of packages, rxjs and OpenTelemetry included, released almost daily, on the
    privacy path. For one POST to `/batch/` that is mostly configuration that switches the SDK
    off. Revisit for server-side flags.
17. **Verification surfaces.** The web build runs posthog-js in Chromium against the e2e
    collector. The native proof is the Linux desktop app (fg's `linux` surface), where
    posthog_flutter runs its Dart core against `cli/posthog_collector.ts` (`FG_POSTHOG_HOST`, new
    in the verify skill). iOS and Android are built in CI (`android` and `ios` gates) but not run:
    this runner has no Android SDK and no access to `/dev/kvm`, and the Mac has no simulators. Their
    request behavior is from reading the SDK source (item 2), and the method-channel tests prove
    what Dart hands to the native side.
18. **Not deleted at an off:** posthog-android's `posthog-native-crash` preferences (timestamps
    of the native crashes already reported, no id; deleting them would report old crashes
    again), and iOS PLCrashReporter's pending crash report (see item 11 and ANALYTICS.md, "Gaps").

## Job 47: purchase legal fixes (Legal Review K.11), 2026-10-31

Legal Review K.11 (H-67, H-50, H-70, H-69, H-68/H-73, H-72) and the job 43 review leftovers.
Migration `20261031194500_purchase_legal_fixes.sql`; docs/PURCHASES.md has the behavior. The new
legal texts came in #147 (merged as 01ad47c after Peter's approval, while this job ran); this job
does not touch them.

1. **No price before the tap (H-67, option a).** The SDK may not run before the user asks to buy,
   and the price came from it (`getProducts`). Of the three options the brief allowed, (a) needs no
   second price source that could disagree with the store: the page says "Weiter zum Kauf" and
   "Den Preis zeigen dir der App Store oder Google Play, bevor du kaufst.", and the store's own
   sheet shows the price before anything is paid. (b) would need a server value per storefront
   (Apple and Google equalize EUR 9.99 into other currencies) plus a "may differ" note; it can be
   added later without touching the SDK path.
2. **One call per tap, `canOffer` still decides.** `PurchaseRepository` lost `loadProduct`;
   `buy(household)` configures (or `logIn`s), loads the product and opens the sheet in one go, and
   answers `ProductMissing` or `StoreOffline` when that fails, shown after the tap. The cubit no
   longer knows whether the page is open (`pageOpened`/`pageClosed` and `retry` are gone; Buy
   itself retries). Buy and Restore show only where `Entitlements.canOffer(Entitlement.lifetime)`
   is true, as before. The buy is for the session's household at the moment of the tap.
3. **24 months, then the normal deletion (H-50); no reminder e-mail.** `purge_purchases` (the
   existing daily pg_cron job) deletes households archived more than 24 months ago with a plain
   `delete from households`, the same statement a last member's leave runs, so the existing delete
   trigger starts the purchases' 30 days and queues the RevenueCat customer. No sibling job: one
   schedule is easier to reason about. `archive_deletes_at()` is the one formula, used by the purge
   and by `archived_households()` (`deletes_at`), so the date shown is the date used. Hummlist has
   no e-mail of its own on main (only Supabase Auth's sign-in mails; no mail provider, no sender
   in the functions), so there is no reminder; NEEDS_LEAD "Job 47" says so for Legal Review.
4. **The archive switch refuses only what would archive (H-70).** `app_switches` (public schema,
   RLS on, no policy, every client grant revoked; the service role writes it) holds
   `household_archive`, seeded off. The check sits in `leave_current_household`, which
   `accept_invite` and `unarchive_household` call, at the point where it would archive: it raises
   `archive_disabled` (P0001, HTTP 400 through PostgREST), which rolls the whole call back (the
   invite stays unused, the membership stays). A call with `p_archive` that would not archive
   anyway (others stay, no Lifetime) goes on as without it. Why not refuse every `p_archive =>
   true`: the app's `unarchive` always passes it, and re-enabling an archived household must keep
   working with the switch off so no one's data gets stuck. No edge function archives (checked).
   The app maps the error to its own message.
5. **Nil-bound sandbox rows go (H-69).** The migration deletes `bound_household` = nil UUID rows
   with `environment = 'Sandbox'` (all of them were test data from job 25); `purge_purchases`
   deletes any such row 30 days after `verified_at`, tombstoning it if it has an HMAC. A nil-bound
   `Production` row is left for a person: it cannot exist, and deleting real purchase data on a
   guess would be worse than keeping it.
6. **Sign-out leaves the SDK's storage (H-73).** The SDK keeps the App User ID and the
   household's CustomerInfo (docs/PURCHASES.md "What the SDK keeps on the device"). The only SDK
   call that clears them is `logOut`, which creates an anonymous RevenueCat customer and contacts
   RevenueCat (C3 forbids both; the lint rule stays). Deleting the SDK's files from Dart would race
   the SDK when it is configured in the same run and depends on its private file layout. So
   sign-out and account deletion call nothing at RevenueCat (a cubit test checks no store call
   follows a sign-out); the data stays until the next Buy or Restore for another household
   replaces it, or uninstall. Legal Review decides whether 5a needs to say so (NEEDS_LEAD).
7. **SDK facts from source, pinned to the lock (H-68).** purchases_flutter 11.0.0 → hybrid common
   20.0.0 → purchases-ios 5.99.0, purchases-android 11.0.0, read at those tags. They match draft
   5a; details and links in docs/PURCHASES.md. `scripts/iap/sdk_version_test.ts` fails when
   `app/pubspec.lock` moves to another purchases_flutter until both docs name the new version, so
   the facts get read again.
8. **The claim names the purchase's household, membership at the purchase time.** The claim
   body carries `householdId` (the household the app bought for, the App User ID); the function
   takes only the app session and passes that household to `purchase_claim`. To know who was a
   member when buying after they left, leaving a household now writes `household_departures`
   (household, user, joined, left), kept one hour: the app claims seconds after the purchase.
   `was_member_at(user, household, at)` accepts a current member who joined before `at`, or a
   departure within the hour whose span holds `at`, with ten minutes either way for the store's
   clock. A claim before the webhook is taken from a member or someone who left within the hour.
   The old body without `householdId` is refused (400): no released app sends claims
   (`REVENUECAT_PURCHASES` was never on).
9. **The deletions route takes a cron secret.** `x-deletions-secret` against the function secret
   `REVENUECAT_DELETIONS_SECRET`, compared like the webhook's (SHA-256 of both, then constant
   time); unset is 503 (fail closed), wrong or missing 401. Not the service role key: the
   workflow would need the most powerful key in GitHub for a route that needs none of its power.
   This supersedes 43.32's "needs no auth".
10. **Routes match exactly.** The handler compares the path, after the gateway's `/functions/v1`,
    with `routes` (`webhook` is `webhookPath`, which the docs test checks); `endsWith` let
    `/x/purchases/revenuecat/webhook` through.
11. **Removing a tester clears their mark (H-72).** A trigger on `lifetime_testers` deletion nulls
    `entitlements.tester`, so `testers.ts remove` (a plain delete) and any other removal do it;
    the unlock stays. Account deletion already did (`on delete set null`).
12. **Not done: H-74** (no tombstone for refunded transactions). Whether a refunded purchase may
    later bind to another household after a refund reversal is a Legal Review question, so it is
    listed in NEEDS_LEAD instead of guessed.
13. **Refund help strings (ADDENDUM 1 and 2, H-76, Peter's decision 2026-10-31 19:59).**
    `refundHelpBody`, `refundHelpGoogle` (ADDENDUM 2's text with the e-mail option),
    `lifetimeBoughtTwice` and `joinLifetimeEnds` are Legal Review's R-8 texts word for word, in DE
    and EN; every old text matched main before the change. The sheet links the FAQ
    (`supportUrl`, "Mehr in den häufigen Fragen" / "More in the FAQ"); the FAQ's refund question
    has no anchor and #148's pages stay untouched, so the link opens the page. The longer text
    makes the sheet taller; it stays scrollable and closes with its drag handle or back.

## Job 51: native Siri (App Intents, English and German), 2026-10-31

Spec #9 "Native Siri", approved by Peter on 2026-10-31. Migrations
`20261031213000_siri_credentials.sql` and `20261031213001_classifier_synonyms_english.sql`.
Apple facts were read on 2026-10-31. The full sheet with quotes is in the job's ops directory
(`apple-facts.md`). The sources:
WWDC22 10169 and 10170, WWDC23 10102 (https://developer.apple.com/videos/play/wwdc2023/10102/),
WWDC25 244, the HIG page "App Shortcuts"
(https://developer.apple.com/design/human-interface-guidelines/app-shortcuts), the entitlement page
(https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri),
`supportedModes`/`IntentModes` (https://developer.apple.com/documentation/appintents/intentmodes),
and the Apple DTS forum answers in threads 777854 and 759909.

1. **No free text in the invocation phrase.** A phrase needs `\(.applicationName)` and at most one
   parameter, which must be an AppEntity or AppEnum. Apple DTS: "App Shortcuts do not support
   arbitrary string parameters in the invocation phrase." So "Add milk, eggs and bread to
   Hummlist" can't be one utterance. `AddItemsIntent` has phrases without a parameter ("Add to
   Hummlist", "Füge etwas zu Hummlist hinzu"), and Siri asks for the items ("What should I add?",
   "Was soll auf die Liste?"). The answer may hold several items.
2. **The one-shot "Add milk to Hummlist" works for known items only.** The phrase "Add
   \(\.$item) to \(.applicationName)" takes an `ItemSuggestion` entity. The app sends the names to
   the iPhone: the household's usuals, then what's on the list, then recent purchases, at most
   50, names only. Every change calls `updateAppShortcutParameters()`. Apple caps the expansion
   ("can't be unbounded", 1,000 phrases per app including every parameter value), so 50 names
   times the parameterized phrases stays inside it. An unknown item falls back to the follow-up
   question. Apple may use entity display names to train its models (App Shortcuts page). That
   means household grocery names go to Apple: a Legal Review point (NEEDS_LEAD).
3. **iOS 17 and up.** The intents and the provider are `@available(iOS 17.0, *)`. The deployment
   target stays 15.0, and iOS 15 and 16 users keep the Shortcut recipe. Why not 16: per-locale
   phrase sets from the string catalog and flexible matching are documented "only to apps
   targeting iOS 17" (WWDC23 10102). Without them the German phrases are not proven to work.
   The phrases are `en.lproj`/`de.lproj` `AppShortcuts.strings`, not the brief's
   `AppShortcuts.xcstrings`. Xcode 26 refuses the catalog for this app: "AppShortcuts.xcstrings is
   only supported for iOS 17.0 and above. Use AppShortcuts.strings for previous versions." (CI run
   41236774729). The deployment target stays 15.0, so each Swift phrase has exactly one German
   translation and no extra per-locale phrases. CI's "Validate app shortcut strings metadata" step
   checks the files, and `AppShortcutPhraseTests` checks that every phrase has an entry in both.
4. **Background only.** With neither `openAppWhenRun` nor `supportedModes` set, an intent
   "typically" runs in the background (Apple, "Configuring the runtime behavior"). `supportedModes
   = .background` is set where the iOS 26 SDK has it. Nothing foregrounds the app: HomePod can't,
   and Siri stays in its sheet. `.lockedHousehold` speaks and offers no "open the app" step.
5. **No Siri entitlement in this PR.** Apple's entitlement page requires
   `com.apple.developer.siri` for "Intents app extensions that handle any Siri requests other than
   shortcut requests". App Intents are not SiriKit extensions. Apple's own App Shortcuts sample has
   an empty entitlements file and no `NSSiriUsageDescription`. No Apple sentence says so outright
   (inferred), so Peter's TestFlight device test decides. If Siri doesn't hear the phrases by
   voice, NEEDS_LEAD "Job 51" has the capability steps. Turning the capability on invalidates
   the App Store profile (RELEASE.md "Capabilities"), so it can't ride along in a code PR.
   `NSSiriUsageDescription` belongs to `INPreferences.requestSiriAuthorization`, which the app
   doesn't call.
6. **Intents in the Runner target, not an extension.** The Runner target is the same process as
   the app, with the same Keychain. That means no App Group, no keychain sharing and no new
   profile. When Siri runs an intent with the app killed, iOS starts the app process in the
   background. The intents are plain Swift, so they never wait for the Flutter engine.
7. **Auth: a Siri credential bound to the app's session (chosen over reading the session from
   Swift).** Reading supabase_flutter's session in Swift would need a refresh from Swift once the
   access token expires (1 h). Supabase refresh tokens are single-use, so two refreshers sign the
   app out, and without a refresh Siri fails whenever the app wasn't opened within the hour.
   Instead, after sign-in the app calls `create_siri_credential()`. That is a
   `personal_access_tokens` row of kind `siri` with the same `fgp_` format and hash at rest. Its
   `session_id` is the Supabase session that created it. The app stores it in the Keychain
   (service `com.hummlist.app.siri`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
   `authenticate_access_token` accepts a Siri row only while that session exists.
   - What ends the credential: signing out (GoTrue deletes the session; the app also revokes the
     row first, at most 2 s, and clears the Keychain), signing in again (new session, the app
     replaces the row with `p_replace`), account deletion (cascade), and leaving the household
     (membership check).
   - What the function refuses: OAuth client tokens (`client_id` claim) and a JWT without
     `session_id`. It keeps at most 5 active Siri rows per user and doesn't count toward the 20
     PATs.
   - Only `voice` opts in (`authenticate(req, deps, { siri: true })`). `mcp`, `alexa` and
     `account` refuse it. `authenticate_personal_access_token` (the pre-job-51 lookup a rolled-back
     function would use) now refuses Siri rows too.
   - The session can only age out on a paid plan (time-boxed sessions). On the free plan it lives
     until sign-out.
   - The RPC is called through PostgREST, like `create_personal_access_token`, rather than through a
     session-only edge function. The SQL refuses what the edge function would refuse (OAuth
     tokens; PATs can't reach PostgREST), so it is one hop less.
8. **Revoking "Siri (this iPhone)" in Zugänge is a reset, not an off switch.** The app issues a new
   credential at its next start in the household, and the confirm text says so. Turning Siri off
   for the app is iOS's per-app Siri setting. A revoke from another device
   still stops a lost iPhone until someone opens Hummlist on it.
9. **The server contract stays the Shortcut's.** A request without `lang` gets exactly the old
   answers: German, the same statuses, no new fields. One e2e test compares the whole JSON body.
   A request with `lang` (the native client always sends it) gets `outcome` in every JSON answer:
   `added`, `nothing_added`, `parsed`, `read` or the failure code, which is also `error`. The
   Swift client branches on `outcome`, never on wording. `list` is accepted and ignored, for a
   future list id. There is one list per household and one household per user, so the intents
   have no list parameter.
10. **English parsing** is `voice/parse_en.ts`, and the copy is `voice/copy.ts`. German behavior and
    strings are byte-identical. "mac and cheese", "macaroni and cheese" and "half and half" stay
    one item each. "salt and pepper" is two. English names keep Siri's casing ("milk"), so the
    read-back says "Added milk, eggs and bread to Hummlist." German names keep their capital
    letter. "Hummlist" joined the German and English filler ("Füge Milch zu Hummlist hinzu" gives
    Milch), which helps Alexa too.
11. **English classification.** 50 common English grocery words go through `add_item` in pgTAP
    (`english_groceries.test.sql`). fish, chocolate, cereal and bell pepper(s) needed synonyms.
    Known gaps:
    - "beer" lands in Obst & Gemüse. The German stemmer folds "beer" and "Beere" into one key, and
      a synonym would move every berry to drinks. Fixing it needs a dictionary-level exception,
      left out of this job. The household's category memory fixes it after one move.
    - "peppers" alone goes to Vorrat (the spice).
12. **No offline queue.** Siri says "Added" only after the server's 200 with `added` or
    `nothing_added`. Offline, 5xx, 401 or any refusal gets a sentence saying nothing was added. A
    timeout (8 s in all), a dropped connection or a reply without a known outcome is different:
    the server may have added the items. Siri then says "I can't confirm that anything was added.
    Please check the list." rather than claiming nothing was. A queued item would be a silent
    maybe (Spec #9 AC4).
    Analytics: `track()` waits for one consent lookup before the answer. That is one indexed
    query on the open pool, and it saves keeping the request alive after the response for
    `withTelemetry`'s flush.
13. **Which language.** No API on the iOS 26 SDK tells an intent Siri's language
    (`IntentSystemContext.locale` is newer, and `INPreferences.siriLanguageCode()` is
    "informational purposes only"). So the intent detects the language of the dictated text with
    `NLLanguageRecognizer`, constrained to English and German, because Siri transcribes in its own
    language. When that is unsure, and for "What's on my Hummlist?", it uses the app's
    localization. The dialogs come from the app's string tables.
14. **Premium seam only.** `premium_required` is in the copy table (DE exactly job 50's
    placeholder; EN "Voice commands are part of Hummlist Premium. You can unlock it in the app
    under More, Hummlist Premium. I didn't add anything.") and in the outcome type, with HTTP 200
    for the Shortcut. No code path returns it, and a test proves that. The Swift client maps it at
    any status to `.lockedHousehold`. Job 50's `requirePremium` gate then works for native Siri
    with no Swift change.
15. **Analytics.** `siri_add` and `siri_read` are server events with `result`, `reason`,
    `language`, `source` (`native` for the Siri credential, `shortcut` for a PAT) and `count`. They
    are sent only after authentication and only under the user's newest analytics yes (job 31's
    `analytics_consents`). Never a name or text. The voice function's error logs now carry the
    error type and the scrubbed message only, never the request's items.
16. **The Shortcut recipe stays (AC9).** It works unchanged through beta and launch. Zugänge shows
    the native card on iOS. Users whose PAT is named like the recipe's ("Siri", "Kurzbefehl",
    "Shortcut") get a hint that they can delete the old token; nothing is revoked automatically.
    The guides put native Siri first, in a `since=1.0.0` section: preview builds show it, and
    production shows it from the launch release on. Retiring the recipe is a later decision, made
    on data (`siri_add` with `source: shortcut`).
17. **Not built:** an Apple Watch app (App Shortcuts from the iPhone "cannot be run on the Watch",
    WWDC23 10102), a tick-off intent, and a gradual rollout. The changelog item holds on
    `native-siri` until Hummlist Launch.

## Job 52: the design system (6b Hex Frische, option 6's yellow) in the app, app icon #5, 2026-11-01

Peter, 2026-10-31 21:06: "6 has a brighter yellow that I like more, let's use that on 6b. We'll
lock in 6b with 6's yellow now [...] We go with app icon 5." Reference: docs/DESIGN.md.

1. **The yellow change is dark mode only.** In light mode 6 and 6b already used the same lemon
   `#ffe24a`. The brighter yellow Peter saw is 6's dark-mode yellow: 6 keeps `#ffe24a` at night,
   6b dimmed it to option 5's `#e8cb3c`. So `color.dark.honey` is `#ffe24a` and
   `color.dark.honey-edge` is 6's `#b39b1a`; everything else is 6b verbatim. Every icon and splash
   colour is read from the token file, so no `#e8cb3c` is left anywhere.
2. **One token source, owned by this job.** `design/tokens/hummlist.tokens.json` (6b's
   tokens.json structure) and `node design/tokens/build.mjs`, which writes
   `app/lib/design/tokens.g.dart` and `site/public/tokens.css` (6b's `--hl-*` names; the values
   equal 6b's except the two dark tokens). Plain Node without packages: 6b's Style Dictionary
   pipeline needs npm in the lint job and is far more than two small writers. The lint gate runs
   `--check`. Job 53 takes these files verbatim.
3. **The components are Material's widgets in the 6b look, through the theme, not ported POC
   widgets.** The POC's `HexButton`, `HexChip`, `ListRow` and `Pressable` are built on
   `widgets.dart` with their own semantics and keyboard handling. Swapping the app's 77 Material
   buttons, chips and checkboxes for them would change each control's semantics node, focus
   behaviour and the roles e2e finds them by: the opposite of "no behaviour change". Instead
   `appTheme` gives the Material widgets the 6b look: `HexBorder` is ported as is (the soft hex
   with its parallel outset), and the POC's tactile face (`tactile.dart`) plugs into
   `ButtonStyle.backgroundBuilder`/`foregroundBuilder`, so every `FilledButton` and
   `OutlinedButton` in the app sinks into its edge and springs back, with Material's semantics,
   keys and tap target untouched. Chips, checkboxes and the navigation indicator take
   `HexBorder` as their shape. No screen needed a component swap. `HexBadge` was not ported: the
   app's badges are the stores' own logos (`store_badge.dart`), which keep their brand shape and
   colours. The POC's `list_row` has no counterpart either: the app's item row is its own
   (`list_view/item_row.dart`) and keeps its layout. The Widgetbook shows the real widgets.
4. **A button with its own background opts out.** A widget whose `ButtonStyle` sets
   `backgroundColor` (the delete confirmation in the error colour, the Google button's
   brand colours, the fold-out chips) means "my colours": it stays a plain Material button and
   keeps its ink, because `styleFrom(foregroundColor:)` derives its own overlay. The two sheet
   buttons that only set a `StadiumBorder` shape (edit "Fertig", feedback "Senden") lost that
   line so they become lemon hex buttons like every other main action.
5. **The tactile button's Material shape is its box grown by the focus ring.** With a background
   builder, `ButtonStyleButton` clips to its shape by default (`Clip.antiAlias`), and
   `clipBehavior` is not a style property. A hex clip would cut the 2 px hover lift, the 3 px
   focus ring 2 px outside the face and the tips of the face itself. The ink overlay is off for
   tactile buttons; the moving face is the feedback.
6. **Material's type sizes, the 6b fonts.** Bricolage Grotesque 700/800 for display, headline,
   title, store names and counts; Inter for the rest. The sizes and line heights stay Material's
   (6b's web sizes, body 17 px, would move every layout and the e2e geometry checks); text
   scaling is unchanged. Fonts are static TTFs from the projects' releases (Bricolage
   Grotesque from ateliertriay/bricolage `fonts/ttf`, Inter 4.1 from rsms/inter `extras/ttf`), not
   the variable fonts: Flutter picks a static face per `FontWeight`, while a variable font needs
   `fontVariations` on every style, which Material's component styles don't set. A button whose
   own `textStyle` replaces the theme's names `HlFont.sans`.
7. **No input decoration theme.** A first version gave fields an outlined `focusedBorder`. The
   add field sets only `border: InputBorder.none`, so it gained an outline and new padding when
   focused: the add sheet grew 6 px and a tap on the focused field stopped opening it (e2e
   `add-sheet.spec.ts:61`, `list.spec.ts:12`). Fields keep Material's defaults; the focus colour is
   cobalt through `primary`.
8. **Spinners in lemon buttons take the label colour.** The theme's progress colour is
   `primary`, which is `#9fb6ff` in dark mode: 1.53:1 on lemon.
9. **Contrast rules live in the token file.** `contrastPairs` (with an optional mode) and
   `contourRequired` (pairs that fail alone and need the navy contour, or are never used) feed
   `app/test/design/contrast_test.dart`, which also pins the brief's lemon numbers. The test
   failed on a planted change (`text-muted` lightened: four failures).
10. **Icon colours.** Light: cobalt, lemon ring, white inner hex, cobalt check. Dark: deep
    `#0b1024`, lemon ring, `#9fb6ff` inner hex, deep check; the dark icon keeps an opaque
    background (Apple allows a transparent one). The ring and the inner hex never touch: 20 of
    1024 units of background lie between them, so white or `#9fb6ff` next to lemon (1.29, 1.53)
    never meet. Monochrome (Android themed, iOS tinted): the ring and the check, the inner hex
    left out. The generator is plain Node with its own rasterizer and PNG encoder
    (`design/app-icon/`), deterministic, with a `--check` in the lint gate; it replaces
    `scripts/icons.py`, which needed Pillow.
11. **Splash.** The 6b mark (cobalt hex, white check, lemon cell) centred on the surface,
    `#f7f7f2` or `#0b1024`, on iOS (named colour and image set with dark appearances), Android
    (`launch_background`, night variants, and `windowSplashScreen*` from API 31) and web
    (`#splash` in index.html, removed on Flutter's `flutter-first-frame` event, never
    intercepting pointers). In dark mode the mark's cobalt body is 2.48:1 on the deep surface; it
    is a logo (WCAG 1.4.11 exempts logotypes), and its white check (7.6) and lemon cell (14.6)
    carry it.
12. **Web manifest.** `background_color` is the light surface `#f7f7f2` (the colour the page
    shows before the first frame), `theme_color` cobalt `#1b3fae`.
13. **The changelog item waits for Peter.** Hold `new-design` (`match: ["design"]`) in
    releases/flags.json: merging still ships the build to internal TestFlight, which is Peter's
    look check; the note reaches the public changelog when he releases the hold.
14. **iOS ships both icon formats under the one name `AppIcon`.** `Runner/AppIcon.icon` is an
    Icon Composer bundle (icon.json plus the three layer SVGs: the ring group "Wabe außen", the
    inner hex and the check in "Wabe innen", with Default, Dark and Tinted fills) generated by
    `design/app-icon/build.mjs`, so iOS 26 renders the layered Liquid Glass icon.
    `Assets.xcassets/AppIcon.appiconset` keeps the Xcode 16 single-size set (1024 light, dark,
    tinted) for older iOS. Proof: on CI's macos-26 job (Xcode 26) actool compiled the bundle into
    `IconImageStack` renditions for light, dark and tintable next to the catalog's flat images
    (run 41254285525, job `ios`); `scripts/gates/ios.sh` now fails if either is missing. Wiring
    the bundle took four lines in `project.pbxproj` (a file reference of type
    `folder.iconcomposer.icon`, the build file, the Runner group and the Resources phase); the
    bundle id, entitlements, capabilities and signing are untouched. Glass, specular and shadow
    stay at Icon Composer's defaults; Peter can fine-tune the bundle in Icon Composer and commit
    it, but the generator would then overwrite it, so a tuned bundle means moving its settings
    into `build.mjs`.
15. **A field that gets focus back after a close opens the sheet (a main bug fixed here).** On
    the web with semantics on, a click on the add field sometimes reaches the app as a
    semantics tap or focus action instead of pointer events. `TextField` answers both by
    requesting focus or the keyboard and never calls `onTap`, which is what opens the sheet. So
    the click showed a cursor but no sheet: e2e `list.spec.ts` "adds are grouped" failed 3 of 3 on
    this runner with `origin/main`'s own build too (job 44 saw it in classifier, list and feedback
    specs; main's CI run for 3ff970d failed `feedback.spec.ts` the same way). Now closing the
    sheet (`_close`: Escape, Schließen, the scrim) arms a flag, and the field's next focus, by any
    route, opens the sheet like a tap. A tap on the list does not arm it: a first version did, and
    the fg sync smoke test's clients then found the sheet open after sign-in: after the hint card's
    "Verstanden" the field got focus back without a tap (most likely the browser restoring focus;
    not traced further). Autofocus at start,
    the refocus after an add and the focus after dictation don't arm it either; dictated text still
    waits for a tap.
    `test/list/add_sheet_test.dart` performs both semantics actions on the field's node (they
    failed before the fix), and `shell_tabs_test.dart` checks that leaving for Mehr and coming
    back keeps a closed sheet closed.
16. **The fold-out chips' labels are 14 px.** Inter is wider than Roboto: at 15 px "Laden:
    automatisch" and a category took 373 px of the 366 px row on a 390 px phone, wrapped, and the
    sheet grew past half the screen (e2e `add-sheet.spec.ts:61`). A widget test with the real fonts
    keeps both chips on one line; it fails at 15 px.
17. **`household-bound.spec.ts` formats its expected date in Europe/Berlin**, the browser's zone
    in `playwright.config.ts`. On a UTC runner just before midnight the runner's day and the app's
    day differ ("31. Oktober 2028" against "1. November 2028"); CI hit it at 23:55 UTC.

## Job 49: Hummlist Premium, yearly and Lifetime under one entitlement, 2026-11-01

Peter's Spec #4 decision (2026-10-31 20:18 CET): Hummlist Premium is sold as two household-bound
products, `com.hummlist.app.yearly` (auto-renewing, 9.99 €/year) and `com.hummlist.app.lifetime`
(one-time, 29.99 €), under one RevenueCat entitlement, `premium`. ADDENDUM 1 (static price
conditions), ADDENDUM 2 (Legal Review K.13 must-fixes, the store price read before the tap, the
store facts) and ADDENDUM 3 (country prices, yearly-only storefronts) refined it the same evening;
where they differ, the later one wins, as noted below. Legal Review §K.13 itself was not on this
host; ADDENDUM 2 restates it. Migration `20261031214500_premium_yearly.sql`; docs/PURCHASES.md has
the behavior. Nothing is gated and nothing is sold: `REVENUECAT_PURCHASES` stays off, the new
server switch `premium_offer` is seeded off.

1. **One kind, `premium`; the plan is a column.** `purchases.kind` and `entitlements.kind` hold
   `premium` (rows migrated from `lifetime`; the checks say `in ('premium')`, so a later
   running-cost entitlement adds its kind there). How a row grants it is `purchases.plan`
   (`yearly` | `lifetime`) and `entitlements.premium_source` (`yearly` | `lifetime` |
   `tester_grant`). A check ties `premium_source` to `source` and a yearly row to its end date,
   so an impossible row can't be written. `plan` keeps the default `lifetime`, so a function
   deployed a few minutes before or after the migration fails loudly (the kind check) instead of
   writing a wrong plan; RevenueCat retries.
2. **The legacy wire value `lifetime` reads as premium in the app** (`Entitlement.parse`). It
   covers a row the migration has not reached (a project not yet migrated) and keeps the tests'
   old rows meaningful. It can go once the migration runs everywhere the app talks to; that is
   the job 49 deploy. Builds from before job 49 (TestFlight) read `premium` as an unknown kind and
   show no unlock; nothing is gated and nothing is sold there, so nothing breaks.
3. **Active is computed at read time.** A yearly row keeps `expires_at` (the paid period's end,
   or the grace end during a billing issue). `household_premium(household)` applies the one rule:
   a lifetime or tester row wins (no end; lifetime before tester), else the latest end of the yearly
   rows still ahead of `now()`, else none. `household_has_premium(household)` wraps it for the
   integration gate (job 50); both are server-only (service connection, `security definer`, no
   client grant). No cron decides premium, so a missed EXPIRATION never leaves it on, and a late
   RENEWAL brings it back. The app applies the same rule to the rows (`HouseholdUnlocks.premiumAt`)
   and re-reads the rows when a yearly end within a day passes; Realtime now also listens to
   updates of `entitlements` (a renewal or cancellation updates a row).
4. **Entitlement rows are a projection of purchases.** The subscription's state lives on
   `purchases` (service-only: `expires_at`, `auto_renew`, `billing_issue`, `state_at`);
   `purchase_entitlement_sync` writes the member-readable copy (`premium_source`, `expires_at`,
   `auto_renew`) in the bound household. A refund deletes the row as before; REFUND_REVERSED
   re-creates it with the stored state.
5. **Lifecycle events by the original transaction, newest wins.** `purchase_record` (INITIAL_
   PURCHASE, NON_RENEWING_PURCHASE, RENEWAL) creates or updates; `purchase_lifecycle`
   (CANCELLATION without refund, UNCANCELLATION, BILLING_ISSUE, EXPIRATION, SUBSCRIPTION_EXTENDED,
   SUBSCRIPTION_PAUSED) only updates a known yearly row and answers `unknown` otherwise (no write,
   nothing granted). Each event carries `event_timestamp_ms`; `state_at` keeps the newest applied,
   so an EXPIRATION delivered after a later RENEWAL is `stale`. A lifecycle event changes the
   state of the transaction wherever it is bound, never the binding (H-56): RENEWAL reported for
   another household's App User ID is `used_elsewhere`.
6. **Cancel reasons (A2-1, H-81).** Only a refund revokes: `cancel_reason` CUSTOMER_SUPPORT, a
   negative `price` or `price_in_purchased_currency` (RevenueCat's refund marker), or any
   CANCELLATION of the one-time purchase (as job 43). UNSUBSCRIBE, BILLING_ERROR,
   DEVELOPER_INITIATED, PRICE_INCREASE, UNKNOWN and a missing reason set `auto_renew = false`;
   premium runs until `expires_at`, and only EXPIRATION ends it. UNKNOWN is App Store only
   ("Apple did not provide the reason", RevenueCat event types, read 2026-11-01); a refund comes
   with CUSTOMER_SUPPORT and a negative price, so UNKNOWN with a positive price is not one.
   `cancel_reason` and `expiration_reason` are read in flight and neither stored nor logged
   (H-87; this supersedes the brief's "expiration_reason logged").
7. **A refunded yearly plan can renew.** RevenueCat: a subscription refund fires CANCELLATION
   "only when the latest period is refunded", and "auto-renewal may still be active". So a
   RENEWAL newer than the refund, in the plan's own household, lifts the revocation; an older one
   and every later event of a refunded Lifetime stay `revoked`. Found while checking the research;
   the brief did not cover it.
8. **BILLING_ISSUE** keeps premium to `grace_period_expiration_at_ms` when RevenueCat sends one,
   else to the period's end (`expiration_at_ms`); no grace length is hard-coded (Google's 14 days
   are an Ops setting). Google's account hold arrives as EXPIRATION: premium off until a RENEWAL.
   EXPIRATION ends premium at the reported end, never later than the event.
9. **PRODUCT_CHANGE and TRANSFER write nothing** (logged by type). There is one subscription
   product; RevenueCat's following RENEWAL carries the new product id, which maps to premium.
   SUBSCRIPTION_PAUSED turns auto-renew off and keeps premium to the period's end; EXPIRATION with
   reason SUBSCRIPTION_PAUSED ends it; a resume is a RENEWAL. TEMPORARY_ENTITLEMENT_GRANT, TEST and
   the rest: 200, no write.
10. **Play ids.** RevenueCat names a Play subscription `<subscription id>:<base plan id>` for
    products set up after February 2023, in webhooks and the SDK. The function accepts
    `com.hummlist.app.yearly` and `com.hummlist.app.yearly:yearly` (base plan `yearly`, Ops) and
    stores the bare id (the `product_id` check allows no colon); another base plan is ignored like
    an unknown product. `entitlement_ids` is not read: the product decides, so events naming the
    old `lifetime` entitlement or the new `premium` both work during the transition (A2-7).
11. **A second yearly plan is its own row (A2-3, H-84).** Two members' store accounts can each
    subscribe. `purchase_record` keeps both (money was taken), never merges or extends one with
    the other, flags `second_yearly` in its answer and the function logs it. The app hides the
    yearly card while any premium is active, so only a race or another device can get there; the
    page then says the household has two plans and shows the manage link.
12. **What the app offers (`canOffer(Entitlement.premium, plan)`, still the one decision
    point).** No premium: both plans. An active yearly plan: Lifetime only (the upgrade; never a
    second yearly plan). Lifetime or a tester grant: nothing. Unknown (loading, offline): nothing.
    Restore shows with any offered plan.
13. **Lifetime while yearly runs: warn before the store sheet (A2-3).** When a renewing yearly
    plan is active, Buy Lifetime opens Legal Review's text first (subscriber variant when
    `my_yearly_plan().subscriber`), "Trotzdem kaufen" / "Abbrechen"; RevenueCat starts only on
    "Trotzdem kaufen" (H-67). A plan with auto-renew off is not billed again, so it gets no
    warning. After the purchase the page keeps the same text with the manage link while the plan
    renews. Legal's `[Abos verwalten]` marks the link; `LinkedText` shows it as a link without
    brackets, so the string stays word for word.
14. **The store's price, read before the tap, through a minimal channel (A2-5, supersedes
    change 4's static price and ADDENDUM 1's K13-1/K13-2).** Opening the page reads the server
    switch and then, only when it is on, the prices once: StoreKit 2 `Product.products(for:)`
    (`displayPrice`, `priceFormatStyle.currencyCode`) on iOS, Play Billing 9.1.0
    `queryProductDetailsAsync` (the `yearly` base plan's recurring phase, the one-time offer) on
    Android, over `familygroceries/store_prices` (`app/lib/purchases/store_prices.dart`). Not the
    `in_app_purchase` plugin: its StoreKit plugin adds an `SKPaymentQueue` transaction observer at
    app launch (plugin registration builds `FIAPaymentQueueHandler`, which calls
    `addTransactionObserver`, flutter/packages source read 2026-11-01), next to RevenueCat's, and
    its Android manager connects a BillingClient with a purchases listener on first use. The
    channel's Android client has a no-op listener and ends its connection after the query; it
    never purchases. The Billing version matches purchases-android 11.0.0's (9.1.0). Lint rules
    `store-price-channel-only-in-store-prices`, `store-prices-channel-methods` (only `prices` and
    `manageSubscriptions`) and `no-in-app-purchase` keep it that way. No price that the store did
    not return is ever shown: no repo amount, nothing derived from locale or region. "inkl.
    MwSt." / "incl. VAT" only for EUR (K.13.P.3). No price read (offline, timeout, error, nothing
    returned): no Buy, the "nicht verfügbar" line. A plan the store doesn't return is not sold in
    that storefront and is hidden silently (ADDENDUM 3; BR, MX, IN sell yearly only). "Der Preis im
    Store kann abweichen." is gone. 47.1's option (a) is superseded for the paywall.
15. **The server switch `premium_offer` (A2-5).** Job 47's `app_switches` gets the key, seeded
    off; `premium_offer()` (security definer, granted to `authenticated`) returns only it.
    Off, unreadable or `REVENUECAT_PURCHASES` off: no card, no Buy, no price query. Job 44 brought
    PostHog feature flags (`Analytics.flags`), but they load only after the analytics yes and
    through the PostHog SDK; a purchase switch must work for everyone without either, so the
    existing table is the simpler mechanism. Setting it: NEEDS_LEAD "Job 49".
16. **The subscriber's own view: `my_yearly_plan()`.** Members read a plan's end and renewal from
    the rows; who pays and whether a payment failed stay hidden (H-55, H-87). The RPC answers the
    caller only: `subscriber` (they claimed an active plan of their current household),
    `renewing`, `billing_issue` with `until`, and `elsewhere` (they pay a renewing plan for
    another household, archived, left or deleted). The billing-problem notice
    (`premiumBillingIssue`) shows only when `subscriber` and `billing_issue` (A2-2; it replaces the
    brief's household-wide "Zahlung fehlgeschlagen" line).
17. **Billing continues (A2-4, H-85).** `confirmBillingContinues` runs before account deletion,
    before a join that leaves the current household (plain, "Löschen und beitreten", "Archivieren
    und beitreten") and before re-enabling an archived household (which leaves the current one).
    The subscriber of a renewing plan (and, for account deletion, of one for another household)
    gets Legal Review's text with "Abo verwalten" (opens the store, stays) and "Trotzdem
    fortfahren"; another member of a billed household gets the Lead's placeholder line with
    "Abbrechen" / "Trotzdem fortfahren". If the RPC can't be read, the flow goes on as before
    (the warning never blocks a deletion).
18. **Manage (A2-2).** "Abo verwalten oder kündigen" shows whenever the household has an active
    yearly plan or a renewing one next to Lifetime. iOS: StoreKit's
    `AppStore.showManageSubscriptions(in:)` sheet; Apple documents no web URL, and an App Review
    rejection on the developer forums was for linking out to `apps.apple.com/account/subscriptions`,
    which stays only as the fallback. Android: Play's
    `/store/account/subscriptions?sku=com.hummlist.app.yearly&package=com.hummlist.app` (Play
    Billing "deep link" docs, read 2026-11-01). Web: a line with both pages.
19. **Disclosures and links.** The yearly card carries title, length, price per period, automatic
    renewal unless cancelled at least 24 hours before the period ends, charging at confirmation
    and renewal, and where to cancel; the cards are followed by the terms (Apple's standard EULA
    on iOS, the support page as a placeholder elsewhere: no Hummlist terms exist, H-93) and the
    privacy policy. Apple's subscription page asks for name, duration, the full renewal price and
    restore on the sign-up screen; the "24 hours" wording is in Apple's Media Services Terms, not
    in the guideline (read 2026-11-01). All copy is placeholder (ARB descriptions say so) until
    Legal Review K.13 / Hummlist Launch.
20. **Strings.** New keys for the Premium page; Legal Review's A2-2..A2-4 strings word for word.
    The 26 "Hummlist Lifetime" values (S-11) are unchanged: renaming them is a legal text change
    for Peter (NEEDS_LEAD). The page uses new `premium*` keys for its own copy (title, web note,
    coming soon, status) and keeps the old keys only for the flow states and job 47's H-76 texts;
    the refund sheet gets a separate yearly note under the H-76 texts.
21. **The route stays `/more/lifetime`**, screen name `lifetime`: links and the analytics screen
    name keep working. The code calls it `premiumPath` / `MorePage.premium` / `PremiumScreen`.
22. **Archive eligibility is "has premium now".** `leave_current_household`,
    `archived_households` and `preview_invite` use `household_has_premium`. An archived household's
    yearly plan keeps being billed until cancelled; at its end premium stops and the archive stays.
    A household whose yearly plan has lapsed is deleted on the last leave like a free one.
23. **Tester grants beat yearly and apply to a yearly household.** `tester_grant_apply` now needs
    a household without a lifetime or tester row; a household with only a yearly plan gets the
    grant, which wins (no end). The table and `scripts/iap/testers.ts` keep their names.
24. **Product facts in one place.** `scripts/iap/product.ts` holds both products (ids, Apple IDs
    `6829293557` / `6829223747`, group `22532621` "Hummlist Premium", base plan `yearly`, P1Y,
    9.99 / 29.99 €) and the drift check's expected prices; `app/ios/Hummlist.storekit` mirrors
    them (product_test.ts pins both to `purchases/types.ts`). The lifetime internalID in the
    StoreKit file changed from 6826922725 to Ops' 6829223747. `apple_product.ts` and
    `google_product.ts` still create only Lifetime (Ops creates the subscription).
25. **Price drift check (A2-5, ADDENDUM 3).** `scripts/iap/price_drift.ts` reads both stores'
    prices (App Store Connect API, Play Developer API) and fails on any listed storefront whose
    price differs, and if Lifetime appears in BR, MX or IN; BR/MX/IN yearly amounts are printed
    to record. A missing secret is "SKIPPED: … missing" (exit 0, or 2 with `--require`, which the
    daily `price-drift.yml` uses so the missing setup stays visible). The secrets don't exist yet:
    NEEDS_LEAD. Drift turns `premium_offer` off by hand (one SQL line); switching from CI would
    need a service-role secret in CI, which this job does not add.
26. **Analytics.** `purchase_completed` and `purchase_refunded` carry `premium_source`
    (`yearly` | `lifetime`), in the server catalog as `oneOf`. A renewal sends no event. The gate
    queries count a household that paid for either product; the WAH share counts a yearly purchase
    for 365 + 14 days from its `purchase_completed` (docs/ANALYTICS.md, the approximation and its
    error). No new event (a renewal or expiry event would need a privacy-policy change; proposed in
    NEEDS_LEAD).
27. **Why not RevenueCat offerings.** The app still loads products by id (`getProducts` with
    `ProductCategory.subscription` / `nonSubscription`). What to show is decided before the tap
    from Supabase and the store's own price read; the offering (`$rc_annual`, `$rc_lifetime`) would
    need the SDK before the tap (H-67). Switching later is a change inside
    `RevenueCatRepository.buy`.
28. **Google's original transaction across renewals.** RevenueCat staff: Google generates a new
    transaction id per renewal that increments from the original; `original_transaction_id` stays
    (community answer 2023-08-08). Google: a resubscribe after expiry creates a new purchase token,
    so a lapsed Play plan bought again is a new row (same household by H-56). Apple's
    `originalTransactionId` stays across renewals and lapsed resubscribes in the group (Apple
    commerce engineer, developer forums). NEEDS_LEAD "Job 49" lists this for Legal's S-8.

## Job 50: integration lock (Siri, Alexa and MCP are Hummlist Premium), 2026-11-01

Spec #4 (Peter, 2026-10-31 20:18 CET): Siri, Alexa and AI-assistant access (MCP) are part of
Hummlist Premium; the list, sync, categories, the app and the web app stay free. Everything is
behind a release flag that stays off until Peter says go. Migration
`20261101081327_integration_lock.sql`; docs/PURCHASES.md ("Integration lock") has the behavior and
the go-live order.

1. **Two switches, both off.** The server's `app_switches.integration_lock` (job 47's table,
   seeded off) decides enforcement; the app's `INTEGRATION_LOCK` define (off) decides whether the
   app shows anything. The app also reads the server switch (`integration_lock()`, members may
   call it), so the card shows only while the server really refuses: turning the switch off again
   hides it in every build. Order: server switch first, then the define.
2. **One check, in Postgres.** `integration_gate(household, integration)` (service connection
   only) returns open while the switch is off, else `household_has_premium` (job 49's rule at read
   time: yearly not ended, Lifetime, tester grant). `_shared/premium.ts` (`requirePremium`) only
   calls it and reports; no premium rule lives in TypeScript. Every endpoint calls it right after
   `authenticate` (Alexa: after verification and linking).
3. **What is premium (`authenticate(` on main, classified).**
   | Endpoint | Credential | Class |
   | --- | --- | --- |
   | `voice` add, read, parse | PAT (the Shortcut), Siri credential (native Siri), OAuth | premium, `siri` |
   | `voice` parse, add, read | the app's own session (in-app dictation) | free: part of the app; the same session writes through PostgREST anyway (job 67: the code never gated add and read for a session, the table said parse only) |
   | `alexa` AddItemIntent, ReadListIntent, LaunchRequest | the account link (OAuth) | premium, `alexa` |
   | `alexa` Help, Stop, Cancel, Fallback, SessionEnded, skill events (linked, disabled) | any | free: the user hears why and can unlink |
   | `mcp` tools/call (all six tools read or write household data) | OAuth, PAT | premium, `mcp` |
   | `mcp` discovery, initialize, tools/list | none or any | free: clients connect and show the tools |
   | `account`, `purchases` | the app's own session only | free |
   | `health` | none | free |
   The app's own Supabase access (RLS, the list, Realtime, the web app) is never gated. Not gated
   either: an OAuth access token a client sends straight to PostgREST instead of MCP; it is a
   Supabase user token under the same RLS as the app. No MCP client does that; gating it would
   mean a client check in every policy, which the app's own access must never meet. Listed in
   NEEDS_LEAD "Job 50".
4. **Locked answers.** Voice: `premium_required` with HTTP 200 (job 51 prepared code, copy and the
   iOS client): the Shortcut speaks only a 200's answer, native Siri branches on `outcome`. One
   sentence for add and read; it says nothing was added. Alexa: `premiumAdd` ("... Ich habe nichts
   hinzugefügt.") for adds, `premium` for reading and at launch, each with a card, session ended.
   Launch answers at once instead of asking for items it would refuse. The rate limit is not
   touched by a refusal. MCP: a tool result with `isError: true` and HTTP 200, German unless the
   client prefers English (Accept-Language), never 401/403: those make clients run OAuth again,
   and AC4 wants no relinking. Nothing is queued or kept for later.
5. **Fail-safe.** A failing check (database down) throws: the endpoint gives its normal transient
   error (voice `server`, Alexa `failed`/`listFailed`, MCP an error like any database failure),
   never the premium answer and never an add. With the switch off this changes nothing a user
   could see: the same request would have failed at its first database call.
6. **Linking while locked is allowed.** Tokens, Siri on an iPhone, Alexa linking and OAuth
   connections can be set up while locked; unlocking later needs nothing redone. A lock or a lapse
   deletes, revokes or disconnects nothing; the integration settings list every connection with
   "Pausiert: braucht Hummlist Premium" and offer only the usual revoke/disconnect.
7. **`integration_blocked`, once an hour.** The first refusal per household and integration in an
   hour is noted in `integration_blocks` (service only; RLS policy for members, no grant) and sent
   to PostHog as `integration_blocked` with `integration` only, under the install of the caller's
   newest analytics decision if that was yes (as Alexa's `item_added`). Hammering a locked endpoint
   costs one row update an hour, not one event per request. The note is taken whether or not the
   event can go (no consent): the count is per household. The event can only happen with the
   switch on; privacy section 9 does not list it yet, so the switch waits for Legal Review
   (NEEDS_LEAD "Job 50").
8. **The app's one decision.** `integrationAccess` (`app/lib/settings/integration_lock.dart`):
   locked only when the server enforces the lock and `canOffer(Entitlement.premium, yearly)` is
   true (the household is known to have no premium; false while loading or offline, so an unlocked
   household never sees Buy). Then Buy (opens job 49's Premium page) where this build sells and
   `premium_offer` is on, "Bald verfügbar" where it does not (`REVENUECAT_PURCHASES` off, or the
   switch off), and job 49's "buy it in the iPhone or Android app" note on the web. Opening the
   settings reads the two switches over Supabase; RevenueCat is never asked (H-67). Entitlements'
   Realtime watch updates the card for every member within one sync.
9. **`paywall_viewed` is new.** Job 49 shipped no such event; AC7 asks for it. The Premium page
   sends it once per visit when it shows a plan with its price to a household that can buy it,
   with `entry_point` (`more`, or `integrations` from the card's Buy), as soon as both the prices
   and the household's rows are known, whichever comes last. Off today in practice (the
   page offers nothing while `premium_offer` and `REVENUECAT_PURCHASES` are off).
10. **Free screens.** AC5 is tested on the screens the app has: the list, More, settings (theme,
    app icon, language), account, invites, categories and stores. The app has no item photos or
    home-screen widget settings yet; when they come they must not read the lock.
11. **The e2e spec runs alone.** `integration-lock.spec.ts` turns the global switch on, which every
    other Siri, Alexa and MCP spec relies on being off, so `scripts/gates/e2e.sh` runs it after the
    suite (full runs, or with the arguments when they name it) with `FG_E2E_INTEGRATION_LOCK=1`,
    which gives it its own Playwright project and report files
    (`playwright-results-integration-lock.json`, `playwright-report-integration-lock/`). The CI
    report action uploads and summarizes both result files, and `scripts/ci-e2e.sh` reads both.
12. **Changelog: `none`.** Nothing changes for users while the flag is off. `releases/flags.json`
    gets the hold `integration-lock` (released: false) for the item the go-live PR writes.

## Job 53: first hummlist.com homepage (landing pages /de and /en), 2026-11-01

1. **Routes `/de` and `/en`.** The landing pages sit at the language root, next to
   `/de/anleitungen` and `/en/guides`, and form one translation group (`hreflang` de, en,
   `x-default` /de). `/` keeps its `Accept-Language` redirects (`de…` to `/de`, any other language
   to `/en`, no header to `/de`, `Vary: Accept-Language`) and only changes the targets;
   `dist/index.html` refreshes to `/de`. Every other route, guide, changelog, legal page,
   `/privacy` and the footer flags work as before (site tests). `de.html` beside a `de/` folder is
   the pattern `/en/guides` already uses in production. Changing the paths touches
   `LOCALES.landing` in `site/build.mjs`, `site/vercel.json` and the tests.
2. **Tokens from job 52, verbatim.** Job 52 owns `design/tokens/hummlist.tokens.json` and
   `design/tokens/build.mjs`, which writes `site/public/tokens.css` and
   `app/lib/design/tokens.g.dart`. 52 had not merged, so this branch takes all four files from
   `origin/job/52-design-6b-app` unchanged, plus the `--check` line in `scripts/gates/lint.sh`
   (not 52's app-icon check, whose generator is not here). On every rebase onto a main with 52,
   take 52's versions. The site never hand-edits `tokens.css`: `styles.css` and `landing.css` use
   only its `--hl-*` variables. The favicons (`favicon.svg`, `favicon.png`,
   `apple-touch-icon.png`) are copies of 52's generated app icon #5 web outputs.
3. **Noindex, checked and unchanged.** `site/vercel.json` sends `X-Robots-Tag: noindex` on
   `/(.*)`, which covers every response: `/`, the landing pages, every asset and the 404.
   `build.mjs` adds `<meta name="robots" content="noindex">` only to pages with a notice (draft or
   unreleased); the landing pages have none, so they carry only the header, like the guides. There
   is no `robots.txt` and no sitemap, and none was added. Tests: every built file and route is
   served with the header (`preview.test.mjs`), including `/de`, `/en` and the media.
4. **One copy file for both languages.** `site/content/landing/copy.yml` maps a copy id to `de`,
   `en`, `status` (`draft` or `reused`) and `source`. A missing language, an unknown field or an
   unused id fails the build. Each string is rendered with `data-copy-id`, and
   `site/scripts/copy-needed.mjs` generates `site/COPY_NEEDED.md` from the YAML. A test fails while
   it is stale, so the list for Hummlist Launch cannot drift from the page. Copy reused from the
   6b prototype (DE only) counts as a draft, since its English is new; only strings already
   published word for word (the help page's „geschlossener Test für Familie und Freunde“, the
   privacy policy's „keine Werbung und verkauft keine Daten“)
   are `reused`.
5. **Claims follow published pages.** The privacy block repeats the privacy policy and the help
   page. The prototype's „Konto weg, Daten weg“ became „Löschen geht in der App“, because the
   policy keeps deleted data in backups up to 90 days. No pricing (the paywall is off), no store
   badges (no listing yet): the calls to action are the web app at app.hummlist.com (the help page
   links it already) and the test block. The prototype's Alexa card is gone. MCP is described
   generically ("ein KI-Assistent wie Claude"). Siri is marked „Bald“ / "Coming soon" with draft
   copy and points to the shortcut guide that works today.
6. **Three demo-video slots, not five.** The brief listed add and tick, household sync and voice
   (Siri, Android, AI chat via MCP). Peter dropped the Siri and Assistant videos for job 54
   (54 ADDENDUM 1, 2026-10-31 21:33), so the slots are `add-tick`, `household-sync` and
   `mcp-chat`; `site/public/media/README.md` names the files job 54 drops in.
7. **Video slot design.** A `<picture>` poster (light and dark, wide 16:9 and compact 4:5,
   switched at 600 px like the videos) is the slot's ground. The `<video>` appears only when all
   four files (WebM and MP4, wide and compact) and the captions exist. Half a set fails the build,
   and so does a poster of the wrong shape. The video is `muted loop playsinline preload="none"`,
   with `controls`, a `poster`, `<source media>` per width, a captions `<track>` and an
   `aria-label` (the text alternative); it never has `autoplay`. `public/demo.js`, the site's
   only script (self-hosted, so the CSP `default-src 'self'` allows it), removes the native
   controls, shows a hex play/pause button, and plays a video only while half of it is in view
   and `prefers-reduced-motion` is not `reduce`. With reduced motion the poster stays until the
   button is pressed; without JavaScript the native controls stay. The build's HTML check now
   allows script files of this site only, no inline code, and requires every local resource (img,
   source, video poster, track, script) and every `#anchor` to exist.
8. **Illustrations are filmed stills, not live HTML.** Per the hummlist-ui-craft skill, the hero
   and the feature cards are HTML/CSS scenes in `site/scenes/` (not part of the build), filmed by
   `node site/scenes/film-all.mjs` into 40 WebP stills (5 scenes, DE and EN, wide and compact,
   light and dark, 29 to 50 KB each). No loops: the three demo slots get job 54's real app
   footage, and a still hero paints fast and looks the same with reduced motion. Members are the
   fictional Mia, Noah and Ida of the demo household „Familie Brandt“, never Peter or Lea. The
   seeded stores dm, Lidl and Edeka appear as text in Hummlist colours, never as logos. The item
   emoji follow the app's own `item_icon.dart`.
9. **Shared header and footer on every page.** The brand (app icon #5) links the landing page of
   the page's language. The header links Anleitungen/Guides and Neuigkeiten/What's new (with
   `aria-current`), the language switch and "Im Browser öffnen". The footer has a site nav
   (guides, changelog) and the legal nav (imprint, plus privacy and help by their flags) and a
   tagline. Every page gets a skip link to `main#inhalt`. Guides, legal pages and the changelog
   keep their content and get the 6b type and colours.
10. **Browser checks are manual, not a CI gate.** `site/checks/` (Playwright, axe-core,
    Lighthouse) needs Chromium and takes minutes; the `site` gate stays a fast Node build and
    test. Run the checks after any change to the site's CSS, templates or media
    (`site/checks/README.md`).
11. **Icons** in the page are Material Symbols paths (Apache 2.0): check, play, pause, open in new.
    `js-yaml` 3.15.2 (already in the lockfile under gray-matter) is now a direct dependency to read
    the copy file.
12. **Fresh-eye review, what stands.** A reviewer saw only the screenshots. Fixed: the hex
    decoration behind the hero button (the hero has no empty corner, so it has none now), the footer
    links' gutter on phones, the nested shadow in the voice card, plus the crawl's findings (the Siri
    link's focus ring in dark mode, `tabindex="0"` on the guides' sideways-scrolling code blocks and
    tables). Kept on purpose: the framed white media box in each colour card. It holds job 54's
    real video footage, which needs a rectangle with its own ground, and the 6b prototype frames its
    feature visuals the same way. Also kept: the tomato test button on the lemon block (6b's choice,
    allowed with the navy contour), the five equal colour blocks (6b's rhythm), and the „euch“ (the
    household) beside „du“ (the reader) in the prototype copy, which is Launch's call
    (COPY_NEEDED.md). The filler bars in the cropped rows and the cropped next message in the
    compact chat follow the hummlist-ui-craft word budget.

## Job 54: demo videos for hummlist.com, 2026-11-01

Three silent, captioned loops for job 53's video slots, from the real app: `add-tick`,
`household-sync`, `mcp-chat`, each in German and English, wide and compact. Sources in
`marketing/videos/` (README there); finals in `site/public/media/`.

1. **Branch and PR.** `job/54-demo-videos` sits on `origin/job/53-homepage-v1` (46b531d) and its
   PR targets that branch, so the diff is only the videos (brief). Job 52 landed on main
   (c4d4090) during the job; I filmed 52's PR head 2dcd896. Between that head and main the app
   differs only in job 51's iOS Siri code and the Access screen, none of which is on screen in the
   videos, so the footage is main's app. I did not rebase onto main: 53 is not rebased yet, and a
   54 on main would show main's four new commits in a diff against 53. Until 53 rebases, the lint
   gate's schema check fails on this PR (and would on 53's) because main has two newer migrations;
   nothing in this PR touches migrations. Pushes go with `--force-with-lease` to my branch, not
   push-pr.sh (it would squash 53's commit). Once 53 is merged: rebase onto main, retarget the PR
   to main, push with push-pr.sh. Never merged here: Peter approves 53 and 54.
2. **Capture: the Linux profile build, real input, one clock.** `capture/driver.ts` runs each
   member's app on its own Xvfb display at 3× (`GDK_SCALE=3`), signs in through the real login
   screen (fields filled by Marionette, not filmed) and films with ffmpeg `x11grab` (30 fps,
   near-lossless 4:4:4, no pointer). Taps and typing are real X events (xdotool, unpacked into
   ~/tools without root); Marionette only reports widget bounds. One ffmpeg grabs all displays and
   the take reads each input's own start stamp, so the three phones of `household-sync` share one
   clock and the sync latency on screen is the real one. Profile mode has no debug banner.
   Research §1.1 named `integration_test` as the driver: Marionette plus X input is the repo's
   existing way to drive the Linux app (verify-family-groceries) and gives real key strokes, which
   `enterText` does not.
3. **Software renderer with Skia.** Under Xvfb the engine's OpenGL path (llvmpipe, no DRI3)
   presented a frame only when an X event arrived: the 240 ms tick (blue fill, strike line, fade)
   showed as one frame and the add sheet popped. Measured at 1×, 2× and 3× with the same result, so
   not pixel cost; `vblank_mode=0` made it worse. `FLUTTER_LINUX_RENDERER=software` with
   `--enable-impeller=false` (Impeller cannot draw to the software surface) renders every frame.
   Phones run Impeller; on these screens (flat colours, text, emoji) the two look the same.
4. **Test data.** New scenarios `demo-familie` and `demo-family-en`: the fictional Brandt family
   (Mia, Noah, Ida, as on 53's hero) with no store tags, so the seeded dm/Lidl/Edeka never show.
   Items were picked against the real classifier and brand table: no item that suggests real
   brands (Kaffee showed Dallmayr, Eduscho, illy), and English names only where the synonyms sort
   them right (`Bread rolls` landed in Haushalt, `Chocolate` and `Frozen peas` in Sonstiges, so they
   were replaced). Each take seeds a fresh run and tears it down. `mcp-chat` uses `solo-long-list`
   (Sams Wohnung, member sam) only, as the brief says, in both languages: the English cut shows
   Sam's German rows next to the new "Honey" and "Jam" (COPY_NEEDED and NEEDS_LEAD flag it).
5. **Real MCP results.** The `mcp-chat` take signs Sam in over the auth API, creates a personal
   access token through `create_personal_access_token` (the app's own RPC), keeps it in memory and
   calls the local `mcp` function's `add_items` and `tick_items`. The chat shows exactly what came
   back (names, categories; English cut: the app's own English category labels from `app_en.arb`)
   at the time it came back: add answered in 344 ms, rows in the app 646 ms after the call (DE).
   The token never reaches a file; the fixture teardown deletes it with the user.
6. **Compositor: HyperFrames 0.8.225, local only.** Pinned in `marketing/videos/package.json`
   with GSAP 3.13.0; `telemetry disable`, `browser ensure`, `doctor --json` gated on Node, FFmpeg and
   Chrome. No sign-in, cloud render or media generation; GSAP, tokens, fonts and the app icon are
   copied into each project. One generated project per video, language and format
   (`build.mjs`), from the take's event log: touch dots land on the logged taps.
   The HyperFrames skills (`hyperframes`, `hyperframes-cli`, their review and format references)
   were read from the pinned package (`node_modules/hyperframes/dist/skills/`) rather than installed
   with `skills update`, which writes into the runner's shared `~/.claude`. No HyperFrames agent ran:
   the projects are generated, and they carry no audio, so the skill's music rule never applied.
7. **Framing (hummlist-ui-craft).** The site shows a video at 576 × 324 (wide) or 358 × 448
   (compact), so the app sits at 0.55× to 0.85× of its logical size, cropped to where the story
   happens, the phone running off the frame; text stays at 10 px or more on screen. The phone body
   is 53's (navy, 10 px, contour, sticker shadow). No status bar is drawn: the Linux window has
   none. Where a crop would put a screen edge above mid-list content, the phone's head dissolves
   into the ground under the caption instead (hummlist-ui-craft "fade at the foot", turned over).
   `household-sync`: wide fans Ida and Noah (0.55×) behind Mia; compact is a deck, Mia (cause) on
   top, then Noah's and Ida's phones as two bands, each showing its "1 neu von Mia Brandt" note
   and the mint row (review 0: an earlier compact hid Ida behind Noah). Their lists were scrolled
   before filming so the new row sits under the header.
8. **Loops.** Every loop starts and ends on the same app state with a seen cause: what was added
   is ticked off (add-tick, household-sync), and the chat's thread leaves upwards after the tick
   (mcp-chat, a conveyor). Seams measured on the rendered masters: SSIM 0.997 to 0.998 (the rest is
   keyframe versus predicted-frame noise). Lengths 10.5 to 10.9 s.
9. **Captions** are display lines with a hex glyph from the app's icon font (wide: beside the
   phone or above the satellites; compact: one line on top), from `copy.json`, plus WebVTT tracks
   for 53's `<track>`. Name tags carry the members' colours. Silent: no audio track at all.
10. **Generic AI chat.** Built in HTML/CSS from the 6b tokens per the skill: raised card, navy
    contour, cobalt user bubbles, the result as a Hummlist card with the app icon. No vendor
    layout, avatar, logo, name, model picker, sparkle or purple; caption "Jeder KI-Assistent mit
    MCP." / "Any AI assistant with MCP." (drafts). The first request is typed, the second spoken
    (mic state and moving bars, UI only), as the brief asks.
11. **Poster attribute dropped.** 53's template gave each `<video>` `poster=<wide webp>`. With
    real videos in place Lighthouse mobile went from 94 to 87–89 (LCP 3.1 s to 4.0 s): a poster
    attribute is not responsive, so phones fetched three wide posters first. The lazy, responsive
    `<picture>` already is the poster (demo.js keeps it on top until frames play; without JS the
    controls sit over it), so the attribute is gone and the score is back to 93–94. The dark
    posters of the three slots are gone too: the videos are light, and a slot without a dark
    poster shows the light one (53's rule).
12. **Caption track not `default`.** 53's `<track default>` made the browser draw the captions a
    second time over the lower part of the picture (seen in the page screenshots), on top of the
    words already in the video, and fetched the files up front. Without `default` the track stays
    for assistive tech and a visitor's caption preference.
13. **Sizes.** Web files are 0.28 to 0.45 MB each, under the brief's 1.5 to 3 MB: the loops are
    flat UI, and at CRF 24 (H.264) and 38 (VP9) text stays sharp in full-size stills. Twelve loops,
    24 files, 9 MB together.

Research items applied: §2.3 instruction block as the work loop (copy file, no stops, silence,
local only, determinism, loop seam, master 1920 × 1080 at 30 fps plus 4:5, check → snapshot →
notes → render → stills from the render → encode → ffprobe → REVIEW.md); §2.4 storyboards 1 and 2
(Video 3 is only its MCP part, ADDENDUM 1); §2.5 review loop; §3 output specs (WebM VP9 before
MP4 H.264, `yuv420p`, even sizes, `+faststart`, `-an`, poster, captions, reduced motion shows the
poster); §6 licences. Pitfalls handled: 1 (copy file, real UI only), 2 (beat ranges), 3 (real
recordings, no animated screenshots), 4 (fixed locale per take; no status bar or clock on screen),
5 (no goldens used), 6 (Xvfb), 7 (no emulator needed), 8 (no Siri, ADDENDUM 1), 9
(`--no-low-memory-mode --workers 6`), 10 (doctor gated on JSON), 11 (no network at render), 12
(`check --json` clean), 13 (no Docker render), 14 (`browser ensure`), 17 (no stops), 19 and 21
(brand gate, own look), 20 (even sizes), 22 (no paid run). Not applicable: 15, 16, 18 (no
transcript).

Deviations from the research: no bee mascot, no honey-and-brown theme and no "Hummlist +
hummlist.com" end card (locked 6b design; the card already sits on hummlist.com); no Siri or
Android segments and no slots for them (ADDENDUM 1); no `device_frame` package (53's phone body);
Remotion not used; stageshow not used (ADDENDUM 3); a capture driver of our own instead of
`integration_test` (item 2); the software renderer (item 3); loops of 10.5 to 10.9 s instead of 12
to 14 s for videos 1 and 2 (each beat at its real length, no padding); the research's poster advice
for autoplay loops (no poster) yields to 53's reduced-motion poster, which is a picture element.

## Job 59: fuzzy suggestions while typing, 2026-11-01

1. **Edit distance decides a typo, pg_trgm only orders.** The brief offered pg_trgm `similarity`
   or `word_similarity` for the match. Measured on the dictionary's words, neither separates typos
   from other words: `mlch`/`milch` and `kaese`/`kase` score 0.38 (`similarity`), while
   `hafermlch`/`haferkekse` scores 0.50 and `brot`/`brokkoli` 0.60 (`word_similarity`). A bounded
   Levenshtein (`fuzzystrmatch`, already in `extensions`) does: a word of the name, or the whole
   name, with the same first letter and at most 1 edit for 3 to 5 letters, 2 from 6 (the app's
   offline rule from the brief, so server and device agree). `extensions.similarity` (pg_trgm, in
   `extensions` per Supabase convention) orders in-word and typo matches within a source.
   `public.suggest_match(typed, name)` returns the tier: 0 exact, 1 prefix, 2 in-word, 3 typo.
2. **In-word from 4 letters, typos from 3, prefixes from any.** Three letters inside a word are
   mostly noise: "Eis" in Fleisch, "Rot" in Brot, "Übe" in Aubergine (item_key folds ü to u). The
   brief's under-3 rule (prefix only) holds; in-word waits one letter more. Without it the
   existing "Übe" catalog test would change too.
3. **Order within a source.** Exact, prefix, in-word, typo. Exact and prefix keep the old order
   (history latest first, catalog shortest first); in-word and typo go most similar first, then
   the same. History still ranks above the catalog and the caps are unchanged; a history row
   still hides the catalog's same entry (suggestion_key).
4. **The catalog corrects only a one-word name.** It replaces the last word, so after other words
   a typo fix ignores them ("Rote Bete" offered "Rote Besen") and a phrase found by a later word
   repeats them ("Rote Rote Beete"). After other words it completes a prefix, or a one-word term
   containing the typed part.
5. **History read once, through a security-definer helper.** The items policy calls
   `is_household_member` per row (about 9 µs: 47 ms for 5000 rows). The old prefix match hid this
   because `starts_with` is leakproof and filtered first; a fuzzy match can't.
   `public.suggest_history(household)` checks membership once and returns the same year of rows
   the caller may read; names are matched once per distinct name, and the per-row loop checks a
   source's cap before the costly `suggestion_key`.
6. **No trigram index.** EXPLAIN on 5000 items in one household and the 1202 dictionary terms:
   reading the household's year is 2.5 ms, matching all terms 3.7 ms, and a GIN/GiST index cannot
   serve a Levenshtein bound. `supabase/bench/suggest_latency.sh` (in the db gate) fails at a p95
   of 50 ms. Before: p50 7.6 ms, p95 21 ms (prefix only). After: p50 about 16 ms, p95 about 28 ms;
   the rest is the extra rows found (each catalog row runs `parse_item`).
7. **Offline matches the same way** (`suggestionMatch` in `app/lib/list/model.dart`, over the
   cached usuals): same name, starts with, a word starts with (the device's old second group,
   which `suggest_items` ranks the same), inside from 4 letters, typo from 3 with the server's
   edit bounds; the server's order within each.
8. **Recently used on the empty field comes from the usuals.** `suggest_items` already returns
   `last_used` (last added or bought) and leaves out what is on the list; the app keeps it with
   the usuals (and in the device cache), so online and offline show the same rows: the due ones,
   then those used in the last 30 days that are not due, latest first, 10 rows in all, labelled
   "Zuletzt verwendet". No server change. A cache from before has no `last_used`: no recent rows
   until the next usuals load.
9. **No Enter mark before typing.** The first row's highlight and ↵ key say what Enter takes;
   with the field empty Enter takes nothing (as before), so the due and recent rows go without it.
   With recent rows the empty sheet is rarely empty, and the mark would have promised an add.

## Job 60: Hummlist feature map (verify-hummlist) and how-to clips, 2026-11-01

1. **A new skill next to the old one.** `verify-hummlist` (`.cursor/skills/verify-hummlist/`, linked
   from `.claude/skills/`) drives the web release build with Playwright. `verify-family-groceries`
   and its `fg` CLI stay unchanged in place, because jobs 58 and 59 edit them. The new skill reuses
   `scripts/fg seed` and `fg teardown` (scenarios, leftover check) and `e2e/serve.mjs` instead of
   copies. The old `SKILL.md` and `features/README.md` now start with "The current feature map is
   `.cursor/skills/verify-hummlist/features/`."
2. **What it builds.** Production defines (`app/config/auth.json`'s switches) with two local
   swaps: a fake Google client id, and the e2e stand-in PostHog host. It has no LEGAL_DRAFTS,
   HOUSEHOLD_ARCHIVE or INTEGRATION_LOCK, so a drive shows what a normal user sees. The e2e build
   keeps those switches for its specs.
3. **Journeys are Node scripts, not Playwright tests.** `journeys/<id>.mjs` and the clip scripts
   load Playwright from `e2e/package.json` (as `film.mjs` does). The test runner would not resolve
   `@playwright/test` from `.cursor/`. The scripts run against a launched instance instead of the
   suite's per-test sign-ups.
4. **Build to `app/build/web`, then copy.** `flutter build web --output <dir>` (3.47.8) leaves out
   `assets/FontManifest.json` and `AssetManifest.bin.json`, and the app then renders no text.
5. **Baseline household.** The `demo-familie` scenario (job 54's fictional Brandt family, no store
   tags), so verification, screenshots and clips share one tidy household with no real data.
6. **The "8-digit code".** The app has no screen to type an emailed code: sign-in is password, a
   link by email, Google or Apple. A read-only look at the hosted auth config (Management API,
   2026-11-01) shows an OTP length of 8, but the sign-in and confirmation emails carry only a
   link. The only 8-character code users see is the household invite code. `sign-in.md` and
   FEATURES-FOR-WRITERS.md say so.
7. **Store badges.** Main shows chain-coloured letter badges (dm red, Edeka and Lidl yellow on
   blue). Legal N-23 asks for no chain colours and job 58 replaces them, so the writers' file
   forbids mentioning them and the clip skill avoids filming store sections. Job 57 then shipped the
   neutral name pill; the follow-up PR updated the map and the clip gotcha.
8. **Clip capture.** Chromium's screencast delivers frames at CSS pixels (390×844) even at DPR 2,
   and a DPR 2 screenshot loop reaches only about 13 fps. So MP4 and WebM are 390×844 at 30 fps,
   the GIF scales to 480 px, and GIF frame 1 and the PNG come from a sharp DPR 2 screenshot of the
   end state. The brief asks for DPR 2 on stills.
9. **GIF frame 1 is the result.** Outlook desktop shows only frame 1, so the GIF opens on the
   finished state for 0.9 s, then plays the journey, which ends on that state. The loop has one cut
   (result to start), which is acceptable for email.
10. **English clips type a German catalogue word.** The add sheet's catalogue rows are German in
    both UI languages ("Yogh" finds nothing, "Ched" finds „Cheddar“). The writers' file and
    `language.md` say this.
11. **Port blocks above 599.** `fg` rejected `FG_PORT_PREFIX=601` and `fg_on_repo_stack` in
    `scripts/lib.sh` read only 5xx ports. Both now accept 500 to 649, which job 60 is the first to
    need. That is a tooling fix, not an app change.
12. **No CI hint.** The brief made a soft CI hint optional. A PR template checkbox and the pointers
    in AGENTS.md and `docs/FEATURE_MAP.md` carry the rule without a new gate.
13. **Feature map research.** Five agents read code, ARB files and specs per feature group. I then
    corrected their output against drives:
    - the More tab order and the Premium hint;
    - quick-add in DE and EN, including the „Eingabe leeren“ button;
    - the hosted auth settings;
    - the analytics key in production builds;
    - the guide URLs;
    - the household name and seed (they had assumed "Familie Demo").

## Job 57: list rows without a check box, a polished strike-through, design alignment, 2026-11-01

1. **No check box in the app's rows, and none added.** The app's rows had none since design H;
   the brief's hex check box was only in the homepage scenes. Nothing in `app/` or Widgetbook drew
   one on a list row. The hex `Checkbox` theme and its Widgetbook stories stay, as do the consent
   and opt-in check boxes elsewhere (Peter, 13:01).
2. **The line crosses the words, not the row.** `StrikePainter` (`item_row.dart`) lays the name
   out as its `Text.rich` does, at the width the text got, and draws one line per text line
   (`HlBorder.width`, 2 px, in `text-muted`, job 56 item 2), as wide as that line's words plus 2 px
   each side, at 0.28 em above the baseline (the middle of the lowercase letters). A wrapped name
   is struck on each line, drawn one after the other, so the pen reads left to right. Brand and
   properties under the name stay unstruck: they describe the item, the line says it is done.
3. **Timing from the tokens, and the gap closes.** The skill (motion.md: "a ticked item leaves
   and its gap closes as one eased motion; a struck-through row that vanishes in one frame is a
   pop") asks for more than the old 260 ms and pop. One `AnimationController` of
   `HlDuration.short + HlDuration.medium` (440 ms): the line draws, the name turns muted and the
   row tints in the first 180 ms (`HlEasing.standard`), then the content fades (`HlEasing.exit`)
   and the height closes (`HlEasing.standard`) in 260 ms, then `onTick` runs. The tick commits
   180 ms later than before; the tap's feedback is immediate and the rows below move up as the
   row goes instead of jumping. Ticking the last row of a category or store first closed the row
   and then popped its heading; now the list's shared session (`DragSession.leaving`) names the
   closing rows, and a divider whose rows all close closes with them on the same curves.
4. **Reduced motion keeps the result visible.** With `disableAnimations` the struck, tinted row
   shows at once and holds for `HlDuration.medium`, then the tick commits without a close (before:
   the row vanished on the tap with nothing seen). motion.md: drop presentation, keep reading time.
5. **A checkbox to assistive tech.** The row keeps `button: true` and gains `checked` (false while
   open, true from the tap), and the tap announces "<Name> abgehakt" / "<name> ticked off"
   (`itemTicked`); the tick has no snackbar since job 29b, so the announcement is the only spoken
   confirmation. Flutter web gives a node with a checked state the role `checkbox`, so the e2e
   helper `itemRow` now finds rows by that role.
6. **Site scenes left as they are (ADDENDUM 1).** The homepage stills and demo loops are not
   re-recorded in this job; the scene edits, the stills and loops they change and the effort are
   in DONE_SUMMARY's "Site follow-up (not done)", with the ready patch in the job's ops directory
   (`jobs/57-list-tick-align/site-followup/site-scenes.patch`).
7. **The theme is one segmented control (Peter, 14:20, replacing his 13:02 switches).** "System" /
   "Hell" / "Dunkel" (EN System / Light / Dark), all three visible, one tap picks, never a cycling
   button. `HexSegmented<T>` (`app/lib/design/hex_segmented.dart`) sits on Flutter's
   `RadioGroup`/`RawRadio` like `HexRadio`, so each segment is a radio in a mutually exclusive
   group with its checked state, Tab focus, arrow keys, Space/Enter and a 48 dp height come from
   Flutter; the group is named "Darstellung"/"Theme". A hex track with the 2 px contour, a honey
   hex indicator that slides to the pick (`HlDuration.medium`, `HlEasing.standard`, a jump with
   reduced motion). Storage is unchanged (key `theme`; none for the system, `light`, `dark`), so an
   old pick reads 1:1 (`app/test/app/theme_test.dart` per stored value). The two-switch version of
   13:02 is gone (`themeSwitches` deleted).
8. **`HexSwitch` and `HexRadio` stay in the design system.** Material's `Switch` cannot change its
   track shape, so `HexSwitch` sits on Flutter's `ToggleableStateMixin` (switch role, toggled
   state, keyboard, focus): a 56 × 30 hex track with the contour, a nested hex thumb, 260 ms
   travel, a jump with reduced motion, 48 dp. More's usage-data row is a `HexSwitchTile`; the
   language list and the create-household "Läden" choice (job 56 item 5) are `HexRadioTile`s.
   Section titles on settings use `HlSectionLabel`, the list's category-label style (item 29). The
   hex `checkboxTheme` stays.
9. **The done row is mint, like the site (job 56 item 2).** A ticked row tints to `mint-soft`
   (`tertiaryContainer`) with its text and line in `text-muted`, the site's `.item--done`, instead
   of the earlier `accent-soft` with a cobalt line and the whole row at 35 %. A partner's new row
   is honey since addendum 5 (below).
10. **List density from the site, the tap target kept (item 7).** Names in Bricolage 17/1.25
    w700, a 28 px emoji column, a 10 px gap, details 13 w500, 16 px sides. The site's rows are 44
    px; the app keeps 48 (`HlSpace.s7`), because the whole row is the tap target. Rows are 4 px
    shorter than before (52), and the e2e geometry follows.
11. **Dividers (items 8, 24), drag pills (22), "Zuletzt verwendet" (19).** Store rules 3 px with
    full radius, counts 15 px Bricolage over a 13 px label; category labels 11 px w800 with 0.12 em
    tracking. A lifted row or divider is an `HlSticker` pill (raised face, contour, hard shadow,
    `HlShadow` tokens now generated into Dart by `design/tokens/build.mjs`). "Zuletzt verwendet"
    shows each thing once (`canonical_key`, else the folded name), its newest purchase, and nothing
    that is on the list again.
12. **Job 56's SAFE items, all 30 in this PR.** Besides the rows: the hex compose field, the
    household header, the sticker explainer, the wide frame, muted suggestion lines, hex chips and
    steppers (items 1, 6, 9, 15, 20, 27, 28); the hex checkbox (4), the rail's hex indicator (10),
    floating sticker snackbars (18), contoured cards and `HlSticker` cards for the welcome choices,
    Zugänge and the Premium page (21, 25); the consent screen's stacked buttons under 400 px and its
    icon without sparkles (3, 12); the app icon #5 brand block on login and welcome, exported by
    `design/app-icon/build.mjs` to `app/assets/brand/`, never redrawn, and the login's repeated
    "Anmelden" title gone (11); a shorter join title (13); the OAuth error without raw server text
    (14); store layout, categories and Läden as hex pills with numbered hex steps, clear of the FAB
    and centred on wide screens (16, 17, 26); section titles in the list's label style (29); equal
    provider buttons (30); token durations, curves and radii (23). PETER items 31 to 34 are not
    built here but decided by Peter in addendum 5 (below); SITE-FOLLOWUP items 35 and 36 are in
    DONE_SUMMARY. Item 6 is left out (below).
13. **A checked hex box is honey, not the site's mint.** The site's mint `.cb` is the list's done
    tick; an opt-in is a choice, and every picked control (switch, radio, chip, segment, bottom
    bar) is honey. `HexCheckbox` (pointy-top 26 px, contour, navy check, 48 dp) serves opt-ins;
    the Material `checkboxTheme` keeps its hex and now its contour when checked.
14. **Snackbars and cards get the contour, not the hard shadow, from the theme.** A
    `SnackBarThemeData` or `CardThemeData` only knows Material's blurred elevation; the hard
    sticker shadow comes from `HlSticker` where a card matters (welcome, Zugänge, Premium).
15. **Apple's button is drawn with the package's logo painter.** `sign_in_with_apple` sizes its
    label at 0.43 × the height (20 px at 48), next to Google's 14 px; the app draws the button
    itself (`AppleLogoPainter`, black/white per Apple's rules, 15 px label, 48 px) so the two match.
    Needs one look on a real iOS build (NEEDS_PETER).
16. **Item 6 (household name, count and member hexes over the list) is left to Peter.** Job 56
    filed it SAFE, but it reverses Peter's own job 29a call ("no household name, no count": one
    household per user, and the count repeats the dividers' "N Artikel"). That is a taste call, so
    the bar stays 29a's: the partner note left, the sync icon right, 44 px in every state, now
    inside the list's frame (item 27). Built once and dropped: a 56 px band with the name in caps,
    "N Artikel" and up to four 30 px member hexes. NEEDS_PETER asks.
17. **Wide screens: one frame (item 27).** `ShoppingListView.frameFor` places the bar, the
    explainer, the columns, the add field and the sheet; the field and sheet sit over the first
    column instead of the window's centre. Settings pages (store layout, categories, Läden) cap at
    `pageMaxWidth` (640, `app/app/shell.dart`).

### Job 57 addendum 5: Peter's calls on job 56 items 31 to 34 (2026-11-01, 15:17)

1. **Empty list (item 31, E1).** The 🧺 emoji is gone: a 72 px pointy honey hex with the navy
   contour holding `Icons.shopping_cart_outlined` (`PointyHex`, like the site's numbered step
   hexes), over the unchanged copy. Key `list-empty-mark`.
2. **Store badges (item 32).** Peter's target is the store's logo in a hexagon, never a first
   letter. Logos wait for the Legal Review, so `StoreBadge` now shows the store's full name in a
   horizontal hex pill: raised face, navy contour, Bricolage, one line with an ellipsis, the full
   name in semantics, the same for chains and own stores. The retailer colour table, the letter
   squares and `storeTint` are gone; every store's divider rule is the brand cobalt. In the divider
   the badge is the name (no second name text); the fold-out store chip and its options are already
   hex pills with the name, so they nest no badge. `StoreBadgeStyle { name, logo }` with a private
   asset map by seed key is the one switch point for the logo step and job 58's custom stores; only
   `name` is built. Site follow-up: the scenes show no badge; they can draw the same name pill.
3. **Text fields (item 33, T2).** Every single-line field is a hex like the compose field (login,
   join code, household name, dialogs, the edit sheet), from one `InputDecorationTheme`
   (`app/lib/design/field_border.dart`): raised face, 2 px contour, cobalt contour plus the 3 px
   focus ring when focused, error colour, faded when disabled, labels inside the face, text clear
   of the tips, 48 dp. A theme cannot see `maxLines`, so the one multi-line field (the feedback
   message) wraps itself in `RoundedFields` (radius s). The add field sits under an empty local
   input theme, which closes every property at once (job 52 item 7 broke on one that got past
   `InputBorder.none`); a test proves it neither moves nor draws a contour with the theme on.
   `HexInputBorder` from earlier in this job is gone; the quantity field takes the theme.
4. **A partner's new row is honey (item 34, F1).** `fresh` rows tint `honey-soft`: yellow is new,
   mint is done, as on the homepage hero. Site follow-up: `household-sync.html` drops
   `.item--arrived` (mint plus edge bar) for `.item--fresh` and is re-filmed; the household-sync
   demo loop shows the new honey once re-taken.
## Job 58: the household's own stores, 2026-11-01

Peter (Q22 = S1): picking a store while adding an item offers "+ Neuer Laden" with an inline field
that creates the store and selects it; Mehr → Läden adds, renames and deletes stores. The landing
page and the onboarding hint ("Du kannst sie später unter Mehr anlegen") already promised this.

- **One name, one store.** `public.store_name_key(name)` (trimmed, spaces collapsed, lower case)
  is unique per household (`stores_household_name_key`), replacing in effect the case-sensitive
  `unique (household_id, name)`, which stays. Existing names that clash under the key keep their
  store, items and layout; all but the first by sort order get a number ("Lidl (2)") in the
  migration, so nothing is merged or lost and the household can rename or delete them.
- **`add_store` is idempotent.** A name the household has in any case or spacing returns that
  store's id instead of failing, so "type a name, confirm" always ends with a selected store, also
  when two members create the same store at once (`on conflict do nothing`, then the lookup). The
  app looks in its catalog first and only calls the server for a new name.
- **40 characters.** The RPCs refuse longer names (`store_name_too_long`, 22001); the column's
  60-character check stays the hard limit for names households already have. A store name sits in
  a section divider, a badge and a picker row on a 358 px screen; 40 still fits "Edeka Center
  Musterstadt-Südost" with room to spare.
- **Rename clash** raises `store_name_taken` with SQLSTATE 23505, which `RejectedOp.nameTaken`
  already maps; the app says "Einen Laden „…“ gibt es schon."
- **A new store's layout** is a full copy of the household's route order, every category shown
  (the "Ohne Laden" order), so the layout screen edits it like a preset store's.
  `create_category` already extends every store's layout, custom ones included (pgTAP).
- **Preset stores are household data:** dm, Lidl and Edeka can be renamed and deleted like any
  other store. Renaming one to another name clears its `seed_key`: "dm" renamed to "Rossmann" is
  no longer dm, so dm's brand defaults (Balea → dm, drugstore items → dm) stop picking it and the
  badge no longer treats it as the chain. A change of case or spacing ("dm" → "DM") keeps it.
- **Delete** lets the foreign keys do it: items (open and bought) fall back to no store, layout
  and item→store memories go (cascade). The app's confirmation names how many open items move to
  "Ohne Laden".
- **Online only.** Like the store and category orders, adding, renaming and deleting a store is
  not queued: offline the app says "Läden lassen sich nur mit Verbindung anlegen, umbenennen oder
  löschen." An existing store is still picked offline, by name too. A queued create would need a
  client-made id and a queued item tagged with a store the server does not know yet.
- **RPCs are security invoker** with the member check, like `create_category` and
  `set_store_layout`: RLS (`stores_member`) is a second guard, and nothing needs the owner's
  rights.
- **Realtime:** `stores` and `store_category_order` were in the publication since the foundation
  and the list's channel reloads the catalog on any change there; deletes are unfiltered and
  reload too. Items untagged by a delete arrive as item updates. No change needed.
- **Data export:** stores have no section of their own (items carry their store's name), so the
  export is unchanged; household deletion cascades to stores as before.
- **No analytics event** for store changes: category creation has none either, and the gate
  insights do not need one.
- **MCP:** `resolve` first tries the name in any case and spacing, then the folded and partial
  matches as before, so "Aldi Süd" and "Aldi Sued" (two stores to the database) stay reachable by
  name. The `store` argument's description names the household's stores (`list_stores`) with
  "Rewe" as an own example. Siri, the voice endpoint and Alexa never match stores by name (the
  store comes from memory or the preset chains' defaults), so they work with any store as they
  are; a custom store is picked automatically once an item was bought or tagged there.
- **Logos:** none. Retailer logos wait for a legal check (Peter). Job 57's `StoreBadge` already
  has the slot (`StoreBadgeStyle.logo`, an empty logo table by seed key); an own store shows its
  full name in the badge like every store. A "Logos:" comment on `Store`
  (`app/lib/list/model.dart`) points there; the analyzer's `todo` diagnostic is an error in this
  repo, so it is not written as a TODO. No column, no assets.
- **Onboarding picks the stores (ADDENDUM 3, Peter 15:46).** New households no longer start with
  dm, Lidl and Edeka. Step 2a offers EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto,
  Penny, dm and Rossmann (`app/lib/household/popular_stores.dart`, the one place to change the
  offer), nothing picked, as hex filter chips (compact on 358 px, checked semantics built in),
  plus "+ Eigenen Laden hinzufügen" with the same inline field as the picker. The stores are
  created with the household in the order picked (`create_household(p_stores)`, one transaction,
  so a lost answer and its retry cannot leave half the stores). "Überspringen" creates it without
  stores, and the hint says they can be added under Mehr, which is now true.
- **The server keeps `p_default_stores`,** default true: builds before this one still show "dm,
  Lidl und Edeka" and send true for it, and the scripts, fixtures and pgTAP tests that create a
  household without arguments keep their data. The new app always sends false. No existing
  household or row changes.
- **"dm", "Lidl" or "EDEKA" in any case is that chain** when the household does not have it yet
  (`add_store`, so for onboarding, the picker and Mehr → Läden alike): its seed key (brand
  defaults like Balea → dm) and its researched walking order. Any other name, "REWE" included,
  starts from the route order; only those three chains have a researched layout. The layouts now
  live in one function, `apply_store_layout(store)`; `apply_default_store_layouts` calls it.
- **Analytics:** `household_created` sends `store_count` (0 to 50) instead of `default_stores`,
  never the names; the old key stays allowed for old builds.
- **The store-name disclaimer (Legal L-7, N-23; Peter "L1", 15:45)** stands word for word under
  Mehr → Läden, under the onboarding store choices, and on hummlist.com's Impressum and imprint
  pages ("Ladennamen" / "Shop names"). The app has no About screen; Mehr → Impressum opens that
  site page.
- **No chain colours for any store (ADDENDUM 1):** job 57's `StoreBadge` draws every store the
  same, from tokens; nothing in the app colours by seed key or name any more.
- **A household with no stores** works on every path: MCP `list_stores` answers `[]`, adds land
  without a store (also items dm would get), a store name gets "Laden „…“ nicht gefunden.
  Vorhanden: (keine).", voice and Siri add, Alexa reads back
  (`supabase/functions/_shared/zero_stores_integration_test.ts`, in the db gate).
- **Picker search from six stores.** More than five stores make a second row of option pills on
  a 358 px phone; from there a search field (`store-search`) sits above them. Enter on a name the
  household has picks it; any other text opens the new-store field with it. Partial matches are
  tapped, not guessed, so "Re" + Enter never picks "Rewe" by surprise.
- **Focus.** The new-store field asks for focus itself after its first frame (`autofocus` yields
  to the add field or the search field, which have focus already). After confirming in the add or
  edit sheet the options fold back and focus returns where a pick returns it (the add field);
  after a cancel it goes to the "+ Neuer Laden" option. Escape and Android back close only the
  field, not the sheet.

## Job 63: Home Screen widgets, 2026-11-01

Peter asked for Home Screen widgets with Anton Borri's `home_widget` package
(0.10.0). Design and contract: docs/HOME_WIDGETS.md.

- **One payload, one key.** The app writes one JSON string (`hummlist_widget`,
  version 1, state `ready` / `signedOut` / `noHousehold`, the open count and
  the first six open items with the store's full name). Both widgets parse the
  same shape; an unknown version is the "open Hummlist" prompt, so a future
  version 2 never shows half a list on an old widget.
- **The app's own order.** `readyPayloadOf` reuses `sectionsOf`, so the widget
  lists stores in the household's order and categories in each store's walk
  order, exactly like the List tab. Folded sections are included: a fold is a
  view of the tab, not of the list.
- **When it writes.** `HomeWidgetSync` follows the session and the list cubit
  (like `SiriSuggestions`), at most once a second, only when the payload
  changed, never a list of another household than the session's. No network
  call of its own: offline, the cached snapshot goes out as soon as the cubit
  loads it. A partner's change reaches the widget only once the app on this
  phone saw it; a background refresh would mean a native Supabase client in
  both extensions, which v1 does not earn.
- **Taps.** `hummlist-widget://open/?homeWidget` and `.../add/?homeWidget`
  (the `homeWidget` query item is what the iOS plugin claims). One handler in
  `App` maps them to `go(listPath)` plus an `AddSheetRequest` the List tab
  takes, even when the tab is built after the request (cold start). No general
  deep-link system (that is the Nov 7 job); auth gating stays in
  `authRedirect`, so a signed-out tap ends on sign-in.
- **Android: Jetpack Glance**, as the home_widget docs recommend for new
  widgets (`HomeWidgetGlanceWidgetReceiver`, `HomeWidgetGlanceStateDefinition`).
  Glance cannot clip shapes, so the store pill and the Add button are
  nine-patch PNGs with real hex ends, drawn by `design/widget/build.mjs` from
  the tokens and the app icon's geometry (checked in the lint gate); in
  `drawable-xxxhdpi` so the tips scale with the density.
- **iOS: WidgetKit extension `HomeWidget`**, iOS 17.0 (containerBackground,
  previews with timelines); the app stays on 15.0, and on 15 and 16 there is
  simply no widget. The extension takes its version from Flutter's xcconfig
  and the `ios` gate fails if it drifts from the app's. The target is added by
  `scripts/ios/home-widget-target.rb` (xcodeproj gem, idempotent), with
  "Embed Foundation Extensions" before "Thin Binary" (Flutter's cycle error).
- **Colours.** `design/tokens/build.mjs` now also writes
  `HummlistColors.swift` and `values{,-night}/hummlist_tokens.xml`; nothing is
  copied by hand. The widgets follow the phone's light or dark mode, not the
  app's theme choice (neither OS hands a widget the app's setting).
- **No ticking from the widget (the optional stretch, skipped).** Glance
  actions and iOS 17 App Intents could tick without opening the app, but a
  tick must go through the app's op queue (`ItemOp`, retried until acked) or
  it is lost offline, and a second, native op queue on two platforms is not
  cheap. Tapping the widget opens the list instead.
- **No Premium gating.** The integration lock is off and widgets are not
  decided.
- **Signing.** The App Group and the extension's App ID need the Apple
  portal (the ASC API key cannot create or assign an App Group), then
  `renew_profile`. The PR must not merge before that (docs/NEEDS_PETER.md,
  job 63): `preflight` would stop every iOS release on main.
- **Held.** The changelog item carries `hold: home-widgets`; the guides
  (`/de/anleitungen/widget`, `/en/guides/widget`) are `draft: true`, because
  the site has no hold mechanism, only `since:` and drafts, and a version
  would publish them with the next release whether or not the device test
  passed.

## Job 61: typed quantities at the end of a line (2026-11-01)

Peter added "Karotten 2" and "2 Karotten" and lost the 2. Two causes: a bare number at the end
was always part of the name (app and server), and a suggestion row tapped while the rows for the
new text were still loading carried the quantity of the text before ("Karotten" while "2 Karotten"
loaded).

- **The rule (Peter/PM, 2026-11-01).** A bare number at the end is the Menge only when it is a
  whole 1 to 20, the word before it is no size or unit word (Größe, Gr., Stufe, Nr., No., size,
  typ, Klasse, Pack, pcs, mAh, cl, %, and every unit) and has no digit, it is not glued to
  letters (D3, 7up), and the rest is a known name. "Karotten x2" and "Karotten 2x" are explicit
  counts and need no known name. `supabase/tests/quantity_parse.tsv` is the one table the app and
  the server pass.
- **Known name on the server: `public.is_known_name(household, name)`**, a classifier word of
  the name with a category (`classifier_words`: dictionary, synonyms such as "carrots", typos) or
  an item of the household with that `normalized_name` (its history). In SQL, not TS, because
  `parse_item` is already the one parser behind `add_item` (MCP add_items, Siri/voice, Alexa) and
  `suggest_entries`, so one change covers every server path.
- **Known name in the app: a bundled copy of `classifier_lexicon`'s forms**
  (`app/lib/list/lexicon_forms.dart`, 1322 forms, about 10 KB) plus the usuals and items on the
  device. `parseEntry` runs only without the server (offline rows), so it has to know words
  offline; the Dart port of `item_key`/`fold_key` matched Postgres on all 421 words of
  `wordlist.tsv`. `supabase/classifier/client_lexicon.sh` writes the file from the local stack, and
  the db gate fails (`--check`) when a classifier migration changes the forms without it. Typo
  matching (`lexicon_fuzzy`) stays server-only.
- **Voice/Siri/Alexa.** The sentence splitter (`voice/parse.ts`) used to take any bare trailing
  number ("Eier zehn" = 10 Eier). It now hands a bare count to `add_item` as digits in the text
  ("Eier 10") with no explicit quantity, so `parse_item` applies the same rule; read-backs come
  from the stored row, so Alexa still says "10 Eier". A trailing number with a unit or "x" is read
  by the splitter as before.
- **Stale rows.** While the rows for a new text load, the rows on screen take the quantity typed
  now (`AddSheetCubit._withTyped`), so what a tap adds is what the row shows. A text that drops
  its quantity keeps the old rows' quantity for that moment; the server's rows follow within
  about 150 ms.
- **The row shows the quantity after the name**, "Karotten · 2", in the bold accent colour it
  had in front. The semantics label is unchanged ("2× Karotten, Wie getippt"): the list rows,
  e2e tests and recipes read it that way.
- **Changed expectation:** `entry_test.dart`'s 'Eier   10' was Entry('Eier 10', null); under the
  rule it is Eier with 10 (Eier is a dictionary word). The case now lives in the shared table.

## Job 62: MCP for testers, 2026-11-01

- **`list_items` counts.** Next to `items` the result carries `counts: {open, checkedLast24h}`
  for the whole list, whatever the `store` or `category` filter: an assistant asked "how much is
  left?" while showing only dm should not answer with dm's share. The filtered count is
  `items.length` already. "Checked" means ticked in the last 24 hours, the shopping trip so far:
  ticked items stay as history for good, so an all-time count would only grow and say nothing.
  A day window needs no time zone. One query, both counts, on `items_household_status_idx`.
- **The blank page after Erlauben is Claude's.** Traced (docs/MCP.md, Claude): our page reaches
  the client's `redirect_uri` about 50 ms after the tap; Claude's callback then exchanges the code
  and connects before answering. Nothing on our side to speed up beyond a cold function start.
  The consent page therefore says the user is done („Verbunden“, „Fertig, du kannst zu Claude
  zurückkehren.“) once the decision is recorded, and the browser keeps that page up while the
  callback is pending. Shown only after the server answered, so it never claims a connection
  that failed on our side. The page names the client from its registration, so other clients get
  their own name; an earlier approval (no client name) says „zu deiner App“.
- **Warming the function from the consent page: no.** Supabase runs edge functions near the
  caller, and Claude's servers call from elsewhere than the user's browser; a warm-up request
  from the page would likely warm the wrong instance. Unmeasured, so not built.
- **Tester guide.** `site/content/guides/{de,en}/claude.md`, slug `claude`. No `since`: the
  connection works with today's app; the "Fertig" page arrives with the next web release, so the
  guide describes both ("zeigt … oder bleibt bis zu zehn Sekunden leer"). Claude's menu names
  are given in English too, unverified on a live Claude account (like the feature map says).
  No page-level noindex, like the other guides: the whole site sends `X-Robots-Tag: noindex`.

## Job 66: deep links (app.hummlist.com opens the app), 2026-11-02

Peter (Notion comment, 2026-11-01): app.hummlist.com links, e.g. the E2 onboarding email's
`/more/invites`, should open the matching screen of the installed app and the web app otherwise.
Route table and how to add a link: `docs/DEEP_LINKS.md`.

1. **An explicit list of paths, not `/*`.** `appLinks` in `app/lib/app/deep_links.dart` claims
   `/list`, `/add`, `/stores/*`, `/more`, `/more/*` and `/join/*`; the AASA `components` and the
   Android filter's `<data android:path|pathPrefix>` are checked against it
   (`deep_links_config_test.dart`, which fails when one drifts). `/` is not claimed: web sign-in
   (Google, Apple, magic link) returns there with a PKCE code that only the browser that started
   it can redeem, and on a phone with the app installed a claimed root could hand that return to
   the app. For the same reason the sign-in, onboarding, analytics-consent and MCP consent pages
   stay unclaimed, and the legacy `/settings` (Zugänge) too. `/list` is the list's link instead.
2. **One `next` parameter for every continuation.** It carried only the MCP consent URL; now it
   also carries an app link's location, vetted (relative, no scheme or authority, a path the
   router shows signed in: `/list`, `/add`, `/stores/<id>`, the More tab; anything else is
   dropped, so it is no open redirect). Signed out, a link goes to `/login?next=<location>`; an
   account without a household carries it through onboarding (`_keepNext`) and lands on it
   instead of Step 3. The analytics question is skipped only for an MCP consent `next`, as
   before; a link waits until it is answered. Invites keep their own `invite` mechanism.
3. **A link-continuing web sign-in returns to `/?next=<link>`,** not to the link, so the browser
   (unclaimed root) and not the app receives the code.
4. **A sign-out carries nothing.** `RedirectMemory` in `router.dart` remembers the last session;
   a change from signed in to signed out sends plain `/login`, so the next person to sign in on
   that device does not land on the previous user's Konto page.
5. **The pending link lives in memory only.** A sign-in that leaves the app (magic link, Apple on
   Android) comes back through `com.hummlist.app://login-callback`, which go_router sees as `/`;
   `RedirectMemory` keeps the link for that and clears it once signed in. Unlike invites
   (`PendingInvite`, 7 days on the device) a lost link costs a tap, not a join, so after an app
   kill the app opens the list.
6. **`/add` and `/stores/<id>` are requests to the list, not pages.** The redirect sends both to
   `/` and, once the session is in a household, puts a `ListLink` (`AddLink`, `StoreLink`) into
   `ListLinks` (`app/lib/list/list_link.dart`), which the list takes once: the add sheet opens
   with the field focused, or the store's section unfolds and its divider scrolls to the top
   (lazy rows: the list jumps toward the estimated offset and looks again, at most six frames).
   An unknown id, another household's store or a store without open items leaves the list as is.
   The URL never stays on them, so back and reload behave as on the list.
7. **One verified Android filter** with all paths, so `autoVerify` covers them together and the
   manifest lists them where the test reads them. The sign-in callback keeps its own filter.
   Flutter's deep linking stays at its default (on) on both platforms; no Info.plist change.
8. **Home Screen widgets (job 63, #185, landed while this job ran).** Its
   `hummlist-widget://open|add` and its own `AddSheetRequest` are left alone, next to `ListLinks`
   in the list screen. The widget's Add could become `router.go('/add')` and its request could go;
   that touches job 63's files, so it is a follow-up, not part of this job.
9. **Changelog category.** The brief asked for one `added` item; the changelog gate knows `new`,
   `improved` and `fixed`, so the item is `new`.

## Job 67: paywall release readiness, 2026-11-02

Nothing was switched on: `REVENUECAT_PURCHASES`, `premium_offer`, `integration_lock`,
`INTEGRATION_LOCK` and the `premium-launch` hold are as they were. The go-live order is
`docs/PAYWALL_RELEASE.md`.

1. **The store builds take the Premium defines from the release environment.** Fastlane's
   `PREMIUM_DEFINES` (`REVENUECAT_PURCHASES`, `REVENUECAT_APPLE_API_KEY`,
   `REVENUECAT_GOOGLE_API_KEY`, `INTEGRATION_LOCK`) are passed only when set, like the analytics
   defines; `release.yml` reads them from variables (switches) and secrets (SDK keys); the web
   build takes `INTEGRATION_LOCK` from the Vercel project. Before, turning the purchase screen on
   in the store builds needed a code change; now it is a variable.
2. **An unreadable `premium_offer` is "gerade nicht verfügbar", not "bald verfügbar".**
   `PremiumServer.offerSwitch()` answers on, off or unreadable. Offline the page says what
   PURCHASES.md always promised, and the integration card links to the page instead of "Bald
   verfügbar". An unreadable `integration_lock` still counts as off in the app: the server decides.
3. **Restore counts what is active now**, by product, from `CustomerInfo.entitlements.active`.
   `allPurchasedProductIdentifiers` lists lapsed plans too, and waiting for their unlock blocked
   Buy for the rest of the app run.
4. **Play buys the base plan's option.** RevenueCat's `defaultOption` would pick a trial or an
   intro offer once Play has one, and the page shows the base plan's price (A2-5).
5. **Purchase notes are per visit; what is under way stays.** `PurchaseCubit.pageOpened()` clears
   canceled, failed, not available, used elsewhere and nothing restored. Waiting for approval,
   unlocking and unlock delayed stay, since a second purchase would be paid twice.
6. **Premium is recomputed when a read fails and on resume.** A failed read re-emits the last
   rows, so an end that passed offline turns premium off; only the newest read started may emit.
   An unknown `premium_source` unlocks nothing (a missing one is still Lifetime).
7. **The grace period holds against the CANCELLATION next to BILLING_ISSUE.** While a billing
   problem is open, an event that says nothing about billing never moves the end earlier
   (`20261102001623_premium_grace_kept.sql`). Changing the TypeScript mapping instead would have
   needed the stored state there; the SQL already has it.
8. **A RENEWAL under another App User ID renews the plan where it is bound**, and still answers
   `used_elsewhere`. Nothing is granted to the other household.
9. **A recent lifecycle event for an unknown transaction is redelivered.** Younger than 2 hours:
   503 `not_recorded_yet` without storing the event id. RevenueCat retries for about 80 minutes,
   so 2 hours covers its whole retry window; older events are acknowledged as before.
10. **RevenueCat calls time out after 10 s** (`AbortSignal.timeout`, raced), as 502
    `revenuecat_unavailable`: the promotional read runs under the household lock, and a hung call
    held a pool connection and that household's purchases.
11. **The changelog check lets an item with a closed hold of its own name another hold's word.**
    One hold line per item made the integration lock's item impossible ("Premium" demands
    `premium-launch`, "Siri … Premium" is about `integration-lock`). The draft already kept such an
    item back until every matching hold is released, so only the check changed.
12. **Widgets stay unlocked** (the brief): they read the list the app has and call no gated
    endpoint. Whether they become Premium is Peter's call and new work.
13. **Local ports 567xx**, since 671xx is past 65535 (job 66 did the same with 566xx).

## Job 64: polish from the Play reshoot, 2026-11-02

- **No default stores anywhere** (Peter, job 58). `create_household`'s `p_default_stores` now
  defaults to false (`20261102084411_no_default_stores.sql`). The app sends false since job 22,
  so real new households already got no store unless one was picked; the change reaches only
  builds older than job 22 and the scripts, fixtures and tests that left the argument out. `true`
  still seeds dm, Lidl and Edeka for builds whose onboarding ticked them.
- **Fixtures and tests use generic stores** (Supermarkt, Drogerie, Bäckerei, Wochenmarkt; two more
  in `many-stores` and `h-prototype`: Discounter, Großmarkt, Biomarkt, Tierbedarf, Hofladen,
  Apotheke). A scenario declares every store it uses; fg creates them with `add_store`, the app's
  path. The e2e `createHousehold` picks nothing by default, as onboarding does. Tests whose subject
  is a chain (Lidl's walking order, dm hiding food, Balea → dm, the drugstore hint) pick dm, Lidl
  and Edeka explicitly (`chainStores` in `e2e/tests/helpers.ts`, `p_stores` in pgTAP).
- **One open item per name, brand and details, server-side** (`20261102084412_one_open_item.sql`).
  Found as a real race, not a helper shortcut: the app's duplicate check only knows its own list,
  so two members (or a phone and Siri) adding "Milch" at the same moment both inserted. A BEFORE
  INSERT trigger (`items_skip_duplicate`) takes a per-household advisory lock and skips an active
  insert whose key (`open_item_key`: the app's `_sameItem` rule, name and brand folded, details in
  any order) is already open. The app's upsert then got no row back, looked its own id up, found
  nothing and dropped its copy; it did not get the row that is there (corrected in Job 64b: an
  undone delete or a replayed offline add vanished until the next reload).
  `add_item` (MCP, Siri, Alexa) takes the same lock before its own check and returns the open row
  when the trigger skipped. Updates are not checked: putting an item back or an edit that makes
  two rows alike stays possible. Not a unique index: existing duplicates would block the
  migration, and a violation would turn into a retried, then rejected op in the app instead of a
  quiet merge.
- **„Wieder fällig“ was right; the sheet hid it.** The due rule (purchases on two or more days,
  due from one usual gap after the last purchase to four gaps) returned eleven due items for the
  heavy-history household. The empty sheet was capped at half the screen minus the bar and tabs,
  with a 200 px floor that assumed one line of chips. On a 360 px phone (the Play captures,
  1080×1920) the „Laden: automatisch“ and „Kategorie: automatisch“ chips wrap, so one row was
  left, cut in half by the input; after an add the note took that room. That is also the "last
  row hidden behind the input" of the reshoot. Before anything is typed the sheet now shows its
  notes and at most three whole suggestion rows (60 px each); the rest scroll. This replaces
  Job 17's half-screen rule (6. Height) for the empty field: the first opening stays small, but
  never shows one row cut by the input. The typed sheet is unchanged.
- **Hummlist Premium is not listed in Mehr before the launch.** The row shows once Premium may be
  offered (`premium_offer` on and, in the iPhone and Android apps, `REVENUECAT_PURCHASES`), or for
  a household that has Premium (a tester grant), whose status stays reachable. The web lists it
  once `premium_offer` is on, since the page there says to buy in the apps. The page itself stays
  at `/more/lifetime` for the integration settings' card (only with the integration lock on).
  No flag was changed.
- **Escape right after a tap closes the sheet** (found by CI on this job's e2e,
  `add-sheet.spec.ts`). On the web a tap on a row unfocused the input and refocused it 50 ms later;
  an Escape in that gap reached nothing, and the timer then refocused the input. The gap now holds
  focus on the add bar's own node (`_barFocus`, which already took Escape and Enter), the timer is
  cancelled on close, a close parks focus there instead of unfocusing (a focused row leaving with
  the sheet no longer hands focus back to the input, which reopened it), and a non-focusable
  `Focus` around the sheet takes Escape from its rows and chips. That wrapper has
  `includeSemantics: false`: with semantics on, a node the size of the list area took every tap.

## Job 68: account deletion Premium warning, voice read-back wording (2026-11-02)

1. **Account deletion never archives.** Peter's rule for the last member of an unlocked household
   (offer the archive, else confirm that Premium is not refunded, job 43) assumes someone can bring
   the archive back. Only the archiving user can (`unarchive_household`), and DECISIONS 43.11
   deletes their archived households with their account. An archive made by deleting the account
   would be data nobody can ever reach, kept for 24 months for nothing. So the deletion dialog
   offers no archive; its warning says why and names the one way the household keeps its Premium:
   invite someone, and delete the account after they joined (the household then stays with them,
   `FateKept`). This is also what the deletion page already promises (point 3). Peter can override
   it in NEEDS_LEAD "Job 68".
2. **What the dialog says (behind `HOUSEHOLD_ARCHIVE`).** For the last member of a household with
   premium now (`leaves_unlocked()`, the archive rule of DECISIONS 47.22, so a yearly plan or a
   promotional grant counts as well as Lifetime): a red card with what ends, the refund help link
   (job 43's sheet) and a box "Ich habe verstanden: Hummlist Premium endet und wird nicht
   automatisch erstattet." that Delete waits for, on top of the typed LÖSCHEN. "nicht automatisch":
   Apple and Google may still refund on request, which the refund help explains. The user's
   archived households are named too, since they go with the account; one with premium asks for
   the same tick. A yearly plan's billing warning (H-85) still comes first, unchanged.
3. **Shown with job 43's `HOUSEHOLD_ARCHIVE` or the `premium_offer` switch.** The texts wait for
   the same Legal Review as the archive UI, so the define shows them. But once Premium is on sale
   (`premium_offer`, read right before the dialog opens, false when unreadable) the warning must
   not depend on a second step: then it shows too, archive UI or not. Today both are off, so
   releases show the dialog exactly as before (testers' promotional grants included). The texts
   agree with `app/web/konto-loeschen.html` as it stands: the last member's household goes "mit
   … einer Freischaltung mit Hummlist Lifetime", archived households go too, refunds are on the
   help page; that page is not edited here.
4. **`leaves_unlocked()` is a new RPC** rather than the app's `Entitlements`: the dialog then has
   the server's rule and no loading state to wait for, and `household_has_premium` stays
   service-only.
5. **One read-back sentence per outcome (Alexa, and Siri in German and English).** "Karotten und
   Mohrrüben sind auf der Hummlist. Möhren steht schon auf der Hummlist." put "sind auf" and
   "steht schon" side by side. Now the added items get one sentence in the perfect tense ("Ich habe
   Karotten und Mohrrüben auf die Hummlist gesetzt."), and everything already open, exact
   duplicates first and then the other spellings or synonyms of new items, gets one ("Schon auf der
   Hummlist: Milch und Möhren."), each name once. The Alexa skill is German only (de-DE model), so
   the English half of the brief is Siri's voice function, which had the same three-sentence
   shape. The app's own snackbar ("Möhren steht schon auf der Liste" with Zusammenführen) is a
   different surface and stays.
6. **The onboarding skip hint names the place.** „Du kannst sie später unter Mehr → Läden anlegen.“
   / "You can add them later under More → Stores." Mehr → Läden has „Neuer Laden“ since job 58, so
   the promise holds; the old "unter Mehr" left out where.

## Job 69: Alexa skill icon and phrasings that reach the skill, 2026-11-02

1. **The skill icons come from `design/app-icon/build.mjs`**, like every other platform icon:
   the light icon at 108 and 512 px, full bleed and without a mask, the same art as the App
   Store icon. The lint gate's `build.mjs --check` fails when a committed skill icon differs, so
   the regenerate-and-compare check the brief asks for is the one that already guards the app
   icons (it flagged the old basket icons as stale). Opaque RGB, since the cobalt fills the square;
   should Amazon crop to a circle, the art (radius 380 of 512) stays inside.
2. **Invocation name stays `hummlist`** (ADDENDUM 1, Peter's Q36 = V3); no research, no swap prep.
3. **One-shot samples**: „setz/setze/pack/packe/schreib {items} drauf“, „ich brauche noch“,
   „füg/füge noch {items} hinzu“. No sample names Hummlist: „setz Milch auf die Hummlist“
   never reaches the skill (Alexa's own lists take it), so the fix for it is the guide.
4. **„drauf“ is trailing filler in the shared splitter** (`voice/parse.ts`): „Setz Milch drauf“
   through Siri added „Milch drauf“. Alexa gets the slot without it when the new samples match,
   and the splitter catches it when a slot keeps it.
5. **Guide ↔ model test lives in the site tests**: they already read the repo (`REPO_DIR`), the
   functions tests run without file access.
6. **Development-stage deploy from the box**: the Hetzner runner has no ASK CLI login (the LWA
   tokens are in the box's ops secrets), so the job ships `scripts/alexa-deploy-dev.sh` and the
   box runs it. It cannot certify, publish or invite.
7. **Local ports 569xx**, since 691xx is past 65535.
8. **ADDENDA 3-7 extend PR #193** instead of a second PR: the icon and guide part was green, and
   the English locales change the same package files.
9. **The launch bug (ADDENDUM 3A) is upstream of the skill** (inferred, not reproduced: the
   simulator needs the box): production edge logs and
   `alexa_links` show no request after the 08:25:41 link event, so no response shape could have
   caused „Ich weiß nicht“. The launch response is still pinned in a test (the whole JSON). The
   check that tells the two remaining causes apart (misheard name, Echo on another account) is
   Peter's (NEEDS_PETER, Job 69).
10. **English goes into `speech_en.ts` and `voices.ts`**, not into `speech.ts`: job 68 rewrites
    `speech.ts` in parallel, and `Voice.speech` is typed with `speech.ts`'s keys, so a German line
    added there fails the type check until English has it too.
11. **English names are stored as heard** ("milk"), like Siri in English (`voice/parse_en.ts`);
    German keeps its capitals rule.
12. **No Alexa line says Premium, buying or unlocking** (ADDENDUM 7, Legal N-27; review 0): the
    German and English lock lines say only that Hummlist takes no voice requests for the
    household right now. `skill_package_test.ts` scans both speech modules. Job 72 removes the
    lock itself.
13. **No tick-off intent in English**: de-DE has none, and „mirroring de-DE“ (ADDENDUM 3B) keeps
    both languages on add and read. Ticking off by voice would be new work for both.
14. **`usesPersonalInfo` stays true**: account linking signs in to a Hummlist account with an
    e-mail address, which is personal information in Amazon's sense.
15. **Testing instructions without Ops' draft**: the draft lives on the box only. `skill.json`
    has a German and English text without credentials; the test fails on a password. Ops' draft
    can replace it (keep its placeholders).
16. **Five identical English models** instead of one shared file: the ASK package needs one file
    per locale; a test keeps them equal.

## Job 71: German native Siri only opened the app, 2026-11-02

1. **The cause is the app name, not the phrase tables.** The ios gate's build log (run
   41401075259, Xcode 26.6) shows every German phrase compiled and trained for `de`
   (`appintentsnltrainingprocessor … Training 'Füge etwas zu ${+applicationName} hinzu|…' for de`)
   and the app name trained as only `Application name 'Hummlist' for de`. The ten German phrases
   share nothing but that token, and every one of them failed, while the same build ran the
   English phrases. Siri opening the app means it found the app by name and no App Shortcut
   phrase matched. So German Siri writes "Hummlist" as a German word ("Hummliste", "Humm Liste")
   that the phrase's app-name slot does not accept. This is inferred: no iPhone reaches this
   runner. `docs/NEEDS_LEAD.md` "Job 71" separates the two remaining causes on a device (Type to
   Siri skips speech recognition).
2. **Fix: localized `INAlternativeAppNames`** (Info.plist variables, `{de,en}.lproj/InfoPlist.strings`,
   three per language, Apple's limit). An Apple engineer confirmed they apply to App Shortcuts
   phrases (developer forums thread 832258: "INAlternativeAppNames will continue to work for App
   Shortcuts"). German: Hummliste, Humm Liste, Hummelliste. English: Humm List, Hum List,
   Humlist. All are spellings of the app's own name, as Apple requires. PR #194's first ios run
   trains `Application name 'HummlistHummlisteHumm ListeHummelliste' for de`, where main trained
   `'Hummlist'`. The same run trained the raw variables for `Base`
   (`'HummlistHUMMLIST_NAME_1…'`), so `Base.lproj/InfoPlist.strings` carries the English names.
   The ios gate fails on a `root.ssu.yaml` without Hummliste or with a variable in it.
3. **No `com.apple.developer.siri` entitlement in this PR.** Apple's SiriKit page says alternative
   names need an Intents extension, and another app's German Siri fix needed the entitlement
   (henemm/loose-ends #348). Adding it without the App ID capability breaks the release signing,
   and enabling the capability needs the Apple account. It stays the documented next step
   ("Job 51" section 2) if the device test still opens the app.
4. **German phrases with an article.** „Füge etwas zu Hummlist hinzu“ lacks the article German
   speakers use, so „…zur Hummlist…“, „Setz etwas auf meine Hummlist“ and „Lies die Hummlist vor“
   were added and the old phrases kept. A `.strings` table maps one phrase to one translation,
   and the target is iOS 15, so a multi-variant `AppShortcuts.xcstrings` is out. Each German
   variant comes with an English phrase of its own (18 per language). The Zugänge dialog and the
   card now show full sentences instead of „Auf meine Hummlist“.
5. **The voice parser drops the same spellings** (`parse.ts`, `parse_en.ts`). Otherwise a
   dictation like „Füge Milch zur Hummliste hinzu“ would have added „Milch zur Hummliste“.
6. **`scripts/siri-phrases.ts` in the lint gate.** It runs on Linux, and on every PR, unlike
   RunnerTests (macOS, native changes only). It checks phrase parity, placeholders, untranslated
   German, the alternative names, and that every phrase the app shows is one Siri knows. Its
   mutations (a dropped `${applicationName}`, a missing translation, an English value in `de`, a
   shown phrase Siri lacks, main's Info.plist) each fail it.
7. **Changelog `none`.** Native Siri is behind the `native-siri` hold and unannounced.
8. **Local ports 587xx.** 711xx is past 65535, and job 47's stack holds 571xx.

## Job 70: sign-in without autofocus, Google and Apple first, 2026-11-02

From Peter's device test: the email field took focus on open, and the keyboard stayed up over
the Google sheet.

1. **No field on the login screen takes focus by itself.** The email field lost `autofocus`; the
   keyboard opens when the user taps a field. The invite-code field on the join screen keeps its
   autofocus: it is not a credential, and the user went there to type the code.
2. **Where Google or Apple is offered, the email form waits behind „Weiter mit E-Mail“ /
   "Continue with email".** The button is the app's secondary button at the providers' 48 px,
   under them. Two fields and three buttons under two provider buttons read as "make an email
   account"; one button each says three equal ways in. Opening the form focuses no field either:
   the brief says the keyboard opens only on a tap in a field. Builds without providers (the
   Linux desktop build, a web build without Google) show the form at once, as before, so
   `fg login` and the Marionette keys are unchanged. The provider labels stay „Mit Google
   anmelden“ / „Mit Apple anmelden“: Google's and Apple's guidelines allow them, and "anmelden"
   does not promise an existing account.
3. **A provider tap unfocuses first.** `FocusManager.instance.primaryFocus?.unfocus()` before the
   provider's sheet or redirect. With nothing focused there is nothing for Flutter to show the
   keyboard for again when the app resumes after a cancel. Widget tests cover both providers
   through a full inactive/paused/resumed cycle.
4. **Port block 570xx instead of 701xx.** 70121 is over 65535 (memory "port blocks above 65").

## Job 72: Alexa data cleanup (Legal Review N-24, N-28), 2026-11-02

Migration `20261102093000_alexa_cleanup.sql`; the retention table is in docs/ALEXA.md, the fact
answers for Legal Review in docs/NEEDS_LEAD.md "Job 72".

1. **A trigger on `auth.sessions`, not only the daily job.** Every way an Alexa connection ends
   deletes its Hummlist session (GoTrue's grant revocation, `alexa_revoke`, sign-out everywhere,
   account deletion), so an `after delete ... for each statement` trigger with a transition
   table removes the links and, with the user's last link, the counter, in the same
   transaction. The hosted `postgres` role has TRIGGER on `auth.sessions` (checked read-only),
   and the repo already has triggers on `auth.users`. The trigger only deletes from two public
   tables by indexed columns (new index `alexa_links_session`), so a GoTrue sign-out cannot fail
   on it short of a database error. `alexa_remember` lost its own stale-link cleanup: the
   trigger does it.
2. **SkillDisabled deletes the grant.** Zugänge lists active `auth.oauth_consents` rows, and
   `alexa_revoke` left Amazon's in place, so a disabled skill stayed listed. It is deleted once
   the user holds no other session of the Alexa client (a second Echo account linked to the same
   Hummlist user keeps it). Linking again (`p_keep` set) keeps it. GoTrue's own revocation only
   sets `revoked_at`; the daily job deletes revoked Alexa grants, because the text promises
   deletion.
3. **The Alexa client is found by its redirect URIs** (`alexa_client_ids()`: Amazon's
   `/api/skill/link/` URLs on layla, pitangui, alexa.amazon.co.jp), not by the name "Amazon
   Alexa": dynamic registration lets anyone name a client that. A client with Amazon's redirect
   gets its codes sent to Amazon, so treating it as Alexa harms nobody.
4. **Counters go once their minute has passed**, not once a day old: the rate check starts a
   new window after a minute anyway, and with a daily job "older than a day" would keep one up
   to two days.
5. **Unused means neither `last_seen` nor the session's `refreshed_at`/`updated_at`/`created_at`
   moved for 12 months**, and the 12-month rule deletes sessions; their links follow because
   their session is gone. `last_seen` alone misses an Alexa session whose link was never
   written or not moved (a failed `alexa_remember`, a user without a household whose token
   Alexa still refreshes), and deleting such a link while its session lives would leave
   SkillDisabled unable to revoke it. Grants with no session left go after a day's grace, unless
   GoTrue made an authorization for that user and client in the last day (it reuses an existing
   grant without moving `granted_at`, so a link in progress must not lose it). That also clears
   the entry after "sign out everywhere", when the link no longer works.
6. **pgTAP fix, unrelated to the feature:** `alexa.test.sql`'s "same answer given again" case
   tied two `decided_at = now()` rows and failed on a database with a different heap order
   (it failed on this runner on main's file too); the nil-UUID row now moves a minute back first.

7. **Alexa stays free (ADDENDUM 1, Peter Q39 = AP1, Legal Review N-27).** The alexa function lost
   its Premium check (`requirePremium`, `speech.premium`/`premiumAdd`), `Integration` is
   `'siri' | 'mcp'`, and `integration_blocked` no longer allows `alexa`. A new migration
   (`20261102120000_alexa_free.sql`) makes `integration_gate` answer `alexa` open instead of
   dropping it from the check constraints: an alexa function deployed before this one still asks,
   and squawk forbids narrowing what old builds use. The app drops Alexa from the Premium copy and
   card, and never shows the Amazon Alexa tile in Zugänge as paused; it matches the grant by the
   client name "Amazon Alexa", the only field the grant list carries (the server matches by
   redirect URIs).
8. **The 12-month purge is proved end to end for one user (ADDENDUM 2):** an only Alexa session
   unused for 12 months takes its link, its counter and the grant (the Zugänge entry) in the same
   `purge_alexa()` run.
## Job 64b: an add that is already on the list never vanishes, 2026-11-02

- **The bug.** Job 64's `items_skip_duplicate` skips an open insert whose item is already open.
  The app's add was an upsert; skipped, it got no row back, looked its own id up, found nothing
  and dropped its copy. An undone delete while another member had put the item back, or an
  offline add replayed after someone added the same item, disappeared until the next reload or
  realtime event, and a tick or edit queued for it offline was lost. The e2e spec
  `already-on-list.spec.ts` failed on main that way (empty list after Rückgängig; the offline tick
  never reached the server).
- **The server answers with the row the add is.** The trigger notes the open item it matched in a
  transaction setting (`family_groceries.open_duplicate`). `put_item`, the app's add from now on,
  inserts the client's id or answers with: its own row (a retry), else the noted open item. One
  round trip, and the answer is the row the trigger actually matched, not a second lookup that
  could disagree. `add_item` (MCP, Siri, Alexa) reads the same note instead of its own fallback
  query, which could return an empty row when its key and the trigger's differed. The lock
  (`lock_household_items`) and `parse_item` are unchanged. `put_item` is security invoker: RLS
  decides as for the upsert, and the noted id is read under RLS, so another household learns
  nothing. Old builds keep their upsert; the server answers them as before.
- **Keep the existing row, do not merge quantities.** The add takes the open item as it is
  (quantity, store, details). This is the rule the app already applies when you type an item that
  is open („steht schon auf der Liste“, nothing merged) and what `add_item` returns. Merging
  (Job 32b's rule) stays an explicit tap: two people noticing that the milk is out is not "buy
  two", and Peter's Job 32b call was "show a hint, still add by default", never a silent merge.
- **The app folds its copy into that item.** `send` answers `{own id: null, kept id: row}`; the
  cubit shows the kept row at once (no realtime needed) and moves the ops queued for its copy onto
  it (`ItemOp.ontoKept`): a tick, edit, move or placement go to the kept item; a delete of the copy
  is dropped, since the kept item is someone else's entry (or an older one); a merge that would
  pair the item with itself is dropped. Adds and merge undos stay as they are (a later restore of
  the copy resolves on the server again).
- **"No store" is part of the add.** It was a second op (`EditItem` store null) after the add; folded
  onto a kept item, it would have cleared that item's store. `AddItem.noStore` sends it in the add
  (`p_no_store`). A restored item without a store now keeps having none instead of picking up the
  remembered store („keeps its place“). Ops cached by older builds (an add plus the edit) still
  replay as before.
- **Large text: the third „Wieder fällig“ row was out of reach** (the job 64 review's note). The app
  does not clamp the text scale (Android's largest is 2.0, iOS's accessibility sizes about 3.0),
  and at 2.0 and 3.0 on a 320 or 360 px phone the sheet gave the rows no room at all: beside a
  full-width „Schließen“ the title wrapped a letter per line, and header and chips filled the
  sheet. A label's button now takes at most half its row (`_TextAndAction`, also for the added
  and duplicate notes); the "everything scrolls" threshold (200 px) grows with the text scale; the
  three-row cap adds up a row's real height at that scale instead of 60 px. Scrolling to the third
  row is fine; a widget test scrolls it whole into view above the input and hit-tests it.
- **The rest of the list at large text.** The same tests found more: the explainer card, store
  headers, category dividers, Mehr headings and the edit sheet overflowed, and a store badge
  squeezed to 18.5 px (the count took the header's width) crashed the hexagon with NaN. A label
  in a row now gets a width limit and wraps or ends in „…“; above text scale 1.3 the explainer's
  „Verstanden“ moves under the hint; the store count takes at most half the header; dividers and
  headings wrap to two lines; the edit sheet's „Abbrechen“ takes at most half its row and
  „Fertig“ moves above „Löschen“ when both do not fit; a hexagon narrower than its tips is drawn
  as a rhombus. Nothing changes at text scale 1.0 (the goldens are unchanged).
## Job 74: one privacy-safe request line in the Alexa function, 2026-11-02

1. **More reply kinds than the brief's seven** (`link|launch|added|read|help|empty|error`):
   `no-household`, `goodbye`, `reprompt`, `not-understood`, `too-long`, `rate-limited` and
   `refused` too (`locked` was dropped on the rebase onto #195: Alexa is free, no Premium check). Folding them in would mislabel exactly the answers a launch bug is debugged
   by (a goodbye is not help, a refused signature is not an error of ours). They are one list,
   `replyKinds` in `alexa/handler.ts`; the test fails when a kind has no case.
2. **`linked` means "Alexa sent an access token"**, not "the token resolved". That is the fact
   Amazon controls; whether we accepted it shows in the kind (`linked=true -> link` is a dead
   token). Help and stop never authenticate, so a resolved-only flag would read false for them.
3. **The line goes through `Deps.log`**, so the tests read it without stubbing `console`, and
   is written in a `finally`: an exception still logs `-> error`.
4. **It replaces the two warnings** ("alexa request refused: <reason>", "Alexa reported an
   error"): a refusal is `-> refused <reason>`, `System.ExceptionEncountered` is its request
   type. One line per request, no second format to grep.
5. **Fields are reduced to one word of `[A-Za-z0-9_.:-]`, 64 characters**: they come from a
   verified Amazon body, but a stray space or newline would break the format or let free text in.

## Job 73: the Hummlist API, 2026-11-02

Peter: "Let's add an API alongside the MCP so people can build automations for the app." "Keep
rate limiting etc in mind there." Addendum 1 (Q41 = PA2): the API is Premium. Guide
[`API.md`](API.md), contract [`api/openapi.yaml`](api/openapi.yaml).

1. **One list module for MCP and API.** `mcp/list.ts` moved to `_shared/list.ts`; the MCP tools and
   the API call the same add, list, tick and move code, which calls the same database functions as
   the app and Siri. The two differ only in how they render an item (the API adds ids, status and
   `addedAt`). The MCP tool results are unchanged: its tests changed only their import paths.
2. **API keys are personal access tokens of a third kind, `api`, with scopes.** Not the MCP tokens
   with a scope column: a key for an automation should not also open the MCP server, and the
   MCP's 20 tokens keep their meaning. `authenticate_access_token` already passed only `pat` and
   session-bound `siri` rows, so MCP and Siri refuse an API key without a code change; the API's
   lookup (`api_begin`) takes only `api` rows. Scopes are `{read}` or `{read,write}`; write alone
   would be a key that adds items it cannot read back.
3. **Only the app's own session makes a key** (`create_api_token` refuses a `client_id` claim or
   a missing `session_id`), like the Siri credential: an OAuth-connected assistant cannot mint
   itself a long-lived key.
4. **Ids in the path, names allowed in bodies and filters.** REST paths take item ids (a name in a
   path would fuzzy-match). `store` and `category` take an id or a name, matched like the MCP tools,
   because a Shortcut or an n8n flow knows "dm", not a UUID.
5. **One database call per request for authentication and limits** (`api_begin`): the address's
   failure budget, the key, the key's token bucket and the household's day, in one transaction
   with row locks in a fixed order. The limits are arguments from `api/limits.ts`, so the numbers
   live in one file. A token bucket (20, refilled at one a second) gives the asked-for "60 a
   minute, burst 20" exactly; a fixed minute window would allow 120 across a window edge.
6. **Every response carries X-RateLimit-* of the limit closest to running out**, unauthenticated
   ones the failed-authentication budget, so "on every response" holds without inventing a limit.
   Reset is seconds until full again (delta seconds, as in the IETF RateLimit draft), not an epoch.
7. **Idempotency inside the operation's transaction.** The claim on `(key id, Idempotency-Key)`,
   the operation as the user and the stored response commit together; a concurrent duplicate
   waits on the row lock and replays. An error stores nothing: nothing changed, so a retry may run
   again. Records live 24 hours.
8. **The address is the gateway's `X-Real-IP`, never `X-Forwarded-For`** (review 0, lead's
   must-fix 2). Checked on the hosted project on 2026-11-02: a request to `health` with forged
   `X-Forwarded-For: 203.0.113.77` and `X-Real-IP: 203.0.113.78` reached the function with
   `x-forwarded-for` exactly as forged and `x-real-ip` and `cf-connecting-ip` set to the runner's
   real address (function_edge_logs, read through the Management API's logs endpoint); a forged
   `cf-connecting-ip` makes Cloudflare refuse the request (403). The local Kong overwrites
   `X-Real-IP` with the socket peer too (`proxy_set_header X-Real-IP $remote_addr`, no
   `set_real_ip_from`). So a caller can no longer rotate addresses or name a victim's. Without the
   header all callers share one budget instead of the throttle going off. Keys have 256 random
   bits, so the throttle's job is to cap work and rows, not to protect a secret.
9. **Premium through the integration lock** (`integration_gate(household, 'api')`), checked after
   the rate limit (a locked household still counts requests) and before validation of the body.
   `402 premium_required`, not 403: the key is fine, the household needs Premium, and the key works
   again once it unlocks.
10. **The flag gates the app's UI only.** With `public-api` off nobody sees the API section, but
    `create_api_token` and the function work for anyone who calls them: the API reaches only the
    caller's own household under RLS and its limits, so a server switch would protect nothing. API
    keys that exist are always listed, so they can always be revoked. (Superseded by job 75: the
    server switch `app_switches.public_api` now closes token creation and the function.)
11. **Requests are strict, responses grow.** Unknown body fields and query parameters are a 400, so
    a field added to v1 later can never change what an old request meant.
12. **camelCase fields**, like the MCP tools' JSON, so one item shape serves both docs.
13. **Served under the Supabase functions URL**; `api.hummlist.com` needs Peter's OK (brief).
14. **Only unknown keys count against an address, and only they are blocked** (lead's must-fix
    3). A valid key always goes through; a missing key or one we know that ended (revoked, its
    creator left, an MCP or Siri token) answers 401 and counts nothing, so a Zap polling with a
    revoked key cannot block everyone behind the same Zapier, n8n or Home Assistant Cloud
    address. This gives up hiding which guesses are valid keys from a blocked address, which is
    worthless against 256-bit keys. An ended key is known for 30 days after it ended (then the
    daily `purge_access_tokens` deletes it and it counts as unknown). New failures delete up to a
    hundred ended windows each, so `api_auth_failures` holds about the addresses of the last ten
    minutes however fast someone sends.
15. **Older app builds list API keys among their MCP tokens** (they read an unknown kind as `pat`);
    their delete button still revokes the key. Nothing to do: the API section ships with this build.
16. **Local ports 583xx**, since 731xx is past 65535.

## Job 75: the API has a server switch, 2026-11-02

1. **`app_switches.public_api`, seeded off**, like `household_archive`, `premium_offer` and
   `integration_lock`: one table, one reader (`app_switch`), flipped by the service role. A PostHog
   flag can be bypassed by calling the RPC or the function directly; the lead ruled (brief) that an
   open, free API before launch is not acceptable, which overrides job 73's decision 10.
2. **Checked inside `api_begin`, the one database call every request already makes**, as its first
   statement: a new outcome `disabled`. No second round trip, and a switched-off API reads no key,
   counts no failure and touches no bucket, day or `last_used_at`.
3. **404 `not_found`, the same body as an unknown path, and no rate-limit headers.** The brief
   allowed 404 or 403. A 403 would announce an API that exists but is closed and invite probing;
   404 says nothing beyond "no such endpoint", and a client sees the same answer whether or not it
   sent a key. CORS and `X-Request-Id` stay, so a support request can still be traced in the logs.
4. **`create_api_token` refuses with `api_disabled` (42501)** right after the sign-in check, before
   the session, membership and scope checks, so a closed server gives one clear reason. The app maps
   it to its own message instead of the generic error.
5. **Existing keys are kept, listable and revocable.** Turning the switch off and on again must not
   cost anyone their keys; while off they simply get 404.
6. **MCP, Siri, Alexa and `integration_gate` are untouched.** The switch is the API's alone; MCP
   tokens (kind `pat`) never went through `api_begin`.
7. **Tests flip the switch inside their own scope**: pgTAP inside its rolled-back transaction, the
   Deno integration tests save and restore it like `integration_lock`, the e2e spec turns it on
   for the local stack only. Production's value comes only from the migration's default.
8. **Local ports 576xx**, since 751xx is past 65535.

## Job 76: the add sheet closes for good after Escape (add-sheet.spec.ts flake), 2026-11-02

1. **The flake was an app bug, not the test.** `add-sheet.spec.ts:139` failed on CI for #199 and
   #197 at its last step, Escape after Tab, Tab, Enter on a row. The CI trace's frames show
   Escape did close the sheet, and 50 ms later the sheet opened again, empty. Logging on a local
   release build with wasm names, plus a hook on `HTMLElement.focus`, traced it. Fifty ms after the
   add, the refocus timer (DECISIONS 8.8) focuses the field. In the next frame the engine focuses
   the field's DOM input. Its `focus` listener reports that back as `SemanticsAction.focus`, but
   during a frame it defers the report with `Timer.run` (`invokeOnSemanticsAction`). An Escape
   queued before that timer closes the sheet first (`_close`, which arms `_openOnFocus`). Then the
   report lands: `TextField`'s semantics `onFocus` asks for focus, and `_openOnFocus` reads that as
   the user coming back to type. The test is right: a user's Escape 100 ms after an add must
   close the sheet, so the assertion stays as it was.
2. **A close lets the field's next focus open the sheet only once the engine's reports are
   through.** `_close` parks focus on the bar as before, and `_settleClose` waits for the next frame
   and then a zero-delay timer. Timers of equal delay run in the order they started (HTML timer
   ordering), so a report from a frame before the close always runs first. If it took focus,
   focus goes back to the bar, and only then is `_openOnFocus` set. Considered and dropped: arming
   at the end of the close animation (with reduced motion it ends at once), keeping focus in the
   field on close (a click on a focused field reaches no `onTap` on the web, so it would no longer
   reopen), and asking the DOM whether the input really has focus (web-only code in the list
   screen for what the frame order already gives).
3. **A close cancels an Enter that still waits for its rows.** The same reopen came from a second
   place: `takeFirst` waits for the server's rows, the user presses Escape meanwhile, the rows
   arrive, the item was added into the closed sheet and `_afterAdd` focused the field, which
   reopened it (7 of 16 tries locally with Enter then Escape at once). Whether the add happened
   at all depended on the server: slower than the close animation, `settled()` had cleared the
   text and nothing was added. Now `takeFirst` adds nothing once the sheet closed, so Escape always
   means "never mind" for an add the user has not seen yet. An Enter whose rows are already there
   adds at once, as before.
4. **Proof.** A deterministic e2e case (`add-sheet.spec.ts`, "an Escape between the refocus after
   a row and its focus report closes the sheet for good"): a hook on `HTMLElement.focus` starts a
   zero-delay timer that sends Escape when the engine focuses the input, so the Escape always
   lands between the refocus and its report. Before the fix it failed 3 of 3 (a probe of the same
   trigger reopened 18 of 18 times), after it 19 of 19 and 3 of 3 passed. The widget test "Escape
   while Enter waits for its rows cancels the add" fails before the fix (the add was sent). The
   whole spec file passed 20 times in a row locally (`--repeat-each=20 --workers=1`).
5. **CI: the apt packages for WebKit and Firefox are cached.** The second shard's "hang" on #197
   was `playwright install --with-deps webkit`. The runner image lacks WebKit's and Firefox's
   libraries, so every e2e job fetched 181 packages (114 MB) from the Ubuntu mirror, and that run
   got about 50 kB/s for half an hour until the 30-minute job timeout. In the last 40 CI runs 1 of
   132 e2e setups hung like this, and the rest took up to 3 minutes. `e2e-setup` now points apt's
   archive directory at a cached one (key: runner image and version, Playwright lockfile, ffmpeg),
   so apt only fetches packages missing there. Only `apt-get update` still reads the mirror.
6. **Local ports 577xx**, since 761xx is past 65535.

## Job 78: stores and categories under Liste → Anpassen, nothing on the list drags, 2026-11-02

Peter's feedback of 2026-11-02 (20:38 CET): move store and category management to the List tab,
simplify the stores screen, drop drag on the list, and tighten the add bar and add sheet.

1. **Routes under the List branch.** `/edit` is the stores screen, `/edit/<id>` a store's details,
   `/edit/none` the section without a store, all children of `/`, so back stays in the List tab
   and the tab bar stays. The header button and the store rows use `context.go`, which builds the
   same back stack and keeps the address bar and the screen tracker on the real location
   (`push` left go_router's location at `/`, and the tracker reported `list`). `authRedirect` keeps
   these paths for a member (`inListTab`). Analytics screen name `stores` for all of them; a
   store's id never reaches analytics.
2. **One details screen for a store and for „Ohne Laden“.** It replaces the categories screen and
   the store layout screen: rename at the top (stores only), the categories in walking order with
   drag handles, tap renames, a trash icon per category (not „Sonstiges“), „Kategorie hinzufügen“.
   For „Ohne Laden“ the order is the household's route order.
3. **Trash on a category in a store's details deletes the category everywhere.** Categories are
   household-wide; there is no per-store category to remove (the old `hidden` flag has no effect
   on the list). The dialog says so („Sie verschwindet aus allen Läden.“) and asks where the
   items go, as before. NEEDS_LEAD Job 78.
4. **„Ohne Laden“, not „Kein Laden“.** The brief's "Kein Laden" is the section the list already
   labels „Ohne Laden“; one name on both screens. It is pinned last, where the list shows it,
   as a flat muted pill with a hint line and a chevron: no handle, no trash, no rename.
5. **Store delete: confirm, no undo.** The app has no undo for deleting a store (the server
   deletes it and untags its items); the existing confirm dialog stays.
6. **No disclaimer on the stores screen.** Stores are no longer prefilled, so every name there is
   the user's own. The approved L-7 text stays in the onboarding store step, which still offers
   store names. No retailer names in hints, examples or feature-map copy (N-23).
7. **All drag on the list is gone, not just reordering.** Items no longer drag to another store or
   category either; the edit sheet's chips do that (the e2e specs move items there). Without a
   drag to rule out, a hold opens the edit sheet while the finger is still down. A hold or right
   click on any divider opens that section's store details (no menu, no up/down moves). The
   `MoveItem` and `PlaceItem` ops stay in the model: a device updating from an older build may
   still have one queued.
8. **The add bar has no disc.** The „+“ hex was not tappable; it and the first row's icon it
   showed while open are gone. The whole compose hex is one tap target with no semantics node of
   its own, so the field stays the only target on the web.
9. **The add sheet has no title row.** „Hinzufügen“ looked like a button. The store and category
   chips share the first line with a ✕ close button (name and tooltip „Schließen“, key
   `add-sheet-close`); the sheet keeps „Hinzufügen“ as its screen-reader name. Adding is a tap on
   a suggestion or Enter, as before.
10. **„Automatisch“ without the word.** Until the user picks, a chip shows the guessed store or
    category in a muted style with a small circled „A“ (`Icons.hdr_auto_outlined`) in place of its
    icon; screen readers hear „Laden: automatisch“ or „Kategorie: automatisch, Kühlregal“. Not a
    sparkle: the hummlist-ui-craft skill rules out stock AI sparkles. Picking, even the guessed
    value, makes it a normal chip.
11. **More → „Anderem Haushalt beitreten“ is `/more/join`**, a page of the More branch, so back
    returns to More and the address bar, a reload and the screen name (`join`) agree. A pushed
    `/join` also popped back to More, but go_router does not put pushed pages in the web address
    bar, which stayed `/more`. The join screen's cancel pops when it can; onboarding still reaches
    `/join` with `go`.
12. **A category name that starts with an emoji shows it once.** The seeded „👶 Drogerie“ showed
    the baby twice in the categories screen (icon and name); the details rows use the label
    without the leading emoji, as the list's dividers do.
13. **A household switch under the open tabs starts the list screen over.** With the join screen
    inside the More tab, the tabs stay mounted while the household changes, and go_router's branch
    navigators keep their state across it (GlobalKeys). The add sheet's cubit held the old
    household's `ListCubit`, so an add right after joining went to the household that was left
    and vanished (`live-sync.spec.ts`). The list screen's add-sheet provider is keyed by the
    `ListCubit` it gets, so it starts over with the new one. This also fixes restoring an archived
    household from More, which switched under the open tabs before.
14. **A divider hold uses `go` like the rest**, so back from those details goes to the stores
    screen first, then the list. The hold fires at 300 ms, as the old drag lift did; a scroll that
    moves past the touch slop first still wins.
15. **No swipe-to-edit either** (Peter's addendum, 20:56 CET). A hold or a right click is the
    only edit gesture on a row; a horizontal drag does nothing, so it can't fight the vertical
    scroll. Screen readers keep the „Bearbeiten“ and „Löschen“ actions. The explainer reads
    „Tippen hakt ab · Halten bearbeitet“ / "Tap ticks off · Hold to edit".
16. **Settings as the style reference** (addendum): the new screens add no new control type. The
    stores screen and the details reuse the hex pill rows, step numbers, drag handles and
    extended FAB the stores and categories screens already had; the add sheet keeps its fold-out
    chips. Settings' segmented switchers fit a choice of a few values, not a list you sort, so
    nothing here copies them. „Ohne Laden“ is a flat pill, set apart from the raised store rows
    because it can't be moved, renamed or deleted. Whether the rows should be lighter, closer to
    Settings' plain list rows, is a look call for the lead (NEEDS_LEAD Job 78).
17. **Local ports 578xx**, since 781xx is past 65535.
## Job 80: connected apps, token hint, Siri text, email copy, 2026-11-02

- **Connected apps show a device, not scopes.** The scope list („Deine Anmeldung bestätigen ·
  Deine E-Mail-Adresse · Dauerhaft angemeldet bleiben“) on every row meant nothing to users. A row
  now reads „Chrome · macOS · Verbunden am … · Zuletzt aktiv …“; the scopes moved into a details
  sheet in plain words (tap on the row), which also has the disconnect button. The trailing
  disconnect icon stays: e2e and the deletion page's instructions („Tippe auf das Symbol zum
  Trennen“) use it.
- **Where the device label comes from.** Supabase Auth's sessions for an OAuth client carry the
  client's HTTP library as user agent (production on 2026-11-02: `undici`, `python-httpx`,
  `Apache-HttpClient`, `codex-mcp-client`), so they cannot name a device. The consent page knows
  the user's browser, so it records a short label after „Erlauben“ (`record_oauth_device`). Only
  the label is stored, checked by the server (40 characters, letters, digits, `.()·-`), never the
  user agent, IP or location; a trigger on `auth.oauth_consents` deletes it with the grant
  (NEEDS_LEAD "Job 80" for Legal Review). A failed recording never blocks the connection. A
  client approved before skips the consent page and keeps its old label (or none).
- **„Zuletzt aktiv“ is the newest token refresh** of the client's sessions in `auth.sessions`,
  which Auth already stores. Apps refresh about hourly while in use, so the day shown is right;
  counting every MCP request would need a write per request for a date-level display.
- **The token hint follows the API flag.** While the API section is hidden the hint speaks of
  automations on the MCP server only; with the flag on it points to the API below for programs
  without MCP. Siri text: „Sag zum Beispiel: „Hey Siri, füge etwas zur Hummlist hinzu“.“ replaces
  „Siri funktioniert jetzt ohne Einrichtung“, which suggested earlier users had to set it up.
- **The account email is not selectable** (a selection on a single line fought with taps and
  long-presses); a copy button with the tooltip „E-Mail-Adresse kopieren“ copies it and shows
  „Kopiert“.

## Job 80: tips card, 2026-11-02

1. **One tip per start.** The List tab picks its tip once, when it is built. The X hides the card
   and stores its id; the next tip in the queue waits for the next app start, so the user never
   meets a stack of cards.
2. **Not on an empty list, and not beside the gesture card.** The tip shows only when the list has
   an active item (the same test as the empty state) and the gesture card ("Tippen hakt ab …") is
   dismissed. The first empty list stays clean, and there is never more than one card.
3. **In the list's scroll view**, right under the gesture card's slot, not in the column above the
   list: at a large text scale the card is taller than a small phone's free space and would
   overflow a fixed column, while in the list it scrolls away.
4. **Dismissed ids per user on this device** (`DeviceCache`, key `tips.<user id>`), kept across
   sign-outs: ids only, nothing personal, and a returning user has already seen them.
5. **Targeting:** a tip names its surfaces (iOS, Android, web, macOS, Windows, Linux; none means
   everywhere) and an inclusive `x.y.z` version range compared per segment (0.1.10 after 0.1.9),
   build number ignored. A tip with a range is skipped when the version cannot be read. The queue
   is `tips` in `app/lib/tips/tips.dart`.

## Job 89: a count said after the item is its quantity again (2026-11-03)

Peter dictated „Gurken zwei“ in the app and got the item „Gurken 2“ with no quantity, a
regression from job 61.

- **Root cause.** Job 61 made the voice splitter (`voice/parse.ts`) hand a bare count after the
  item back as digits in the name („Gurken zwei“ → name „Gurken 2“, no quantity), so that
  `public.parse_item`'s typed rule would decide. Only `add_item` runs `parse_item`. In-app
  dictation calls the voice function with `mode: parse` and adds the returned name and quantity
  itself, so it stored „Gurken 2“ as the name. Siri and Alexa went through `add_item` and got the
  typed rule, which keeps the number in the name unless it is 1 to 20 after a known name („Eier
  dreißig“, „Büroklammern hundert“, „Plimbel drei“ all stayed in the name). Reproduced on the local
  stack: `mode: parse` with „Gurken zwei“ returned `{"name":"Gurken 2","quantity":null}`.
- **Fix at the root: the splitter decides for speech, as it did before job 61.** A count said
  after the item, as a word or digits, is the quantity in every voice path (Siri, Alexa, in-app
  dictation), because they all share the splitter and pass its quantity to `add_item` as the
  explicit one. The typed rule exists because typed text has „Vitamin D3“, „7up“ and „Büroklammern
  100“ written as part of the product. Speech has no such product names worth the cost; spoken
  „Größe vier“, „Typ 405“, „Nr. 5“, „Stufe 3“ still stay in the name (size words, unchanged).
  Typed input is unchanged (MCP, the app's add sheet, `parse_item`).
- **English gets the same.** `parse_en.ts` never read an amount after the item, so „cucumbers
  two“ stayed one name. It now reads a bare count there, with its own size words (size, type, no,
  number, stage: „diapers size 4“ stays whole). Units after an English item („milk 2 liters“) stay
  as they were (in the name), because the brief keeps today's unit behaviour.
- **Trailing „ein“/„eine“ is not a count.** „Gurken eins“ is 1, but „ein“, „eine“ and their
  inflections after an item stay as they were: „Trag Milch ein“ would otherwise become Milch ×1.
- **One table, two modes.** `supabase/tests/quantity_parse.tsv` gains a `mode` column (`typed`,
  `spoken`, none = both) and a `lang` column (the splitter a spoken row goes through, de or en).
  `entry_test.dart` and the MCP path read the typed rows; the voice path in
  `add_paths_integration_test.ts` reads the spoken ones with the German or English splitter.
- **Found, not fixed: typed „zwei Gurken“ offline.** The server reads Gurken ×2; the app's
  offline `parseEntry` keeps „zwei Gurken“ as the name. Online the add sheet uses the server's
  parse, so only offline adds see it. Typed behaviour is out of this job's scope; the table marks
  that row `spoken` and NEEDS_LEAD „Job 89“ asks whether to port the number words.
- **Alexa skill model: unchanged.** The slot is free text; nothing in `alexa/skill-package/`
  changes, so nothing to deploy or certify.

## Job 88: an own store named like an offered chain ticks the chain, 2026-11-03

Peter's bug of 2026-11-03 (20:07 CET): in onboarding, „Eigenen Laden hinzufügen“ with a name such
as „edeka“ made a hidden duplicate of the EDEKA chip.

1. **PR #186 (job 64) did not touch this flow.** It changed the defaults (no store seeded unless
   picked) and the list, not `create_household_screen.dart`, whose own-store code dates from job 58
   (#176). The fix builds on main as it is.
2. **The cause was in the app only.** `_addOwn` kept the typed spelling („edeka“) in the picked
   list. The chips compared exact names, so EDEKA showed unticked and the typed entry was hidden
   (it matched an offered chain, so it got no own chip). A tap on EDEKA then removed the hidden
   entry (the toggle compares by `storeNameKey`) and still showed unticked: the first tap seemed
   to do nothing. Now a typed name whose key (trimmed, spacing collapsed, case folded) is an
   offered chain adds that chain's own spelling, so its chip ticks and toggles as if tapped. A
   name already picked stays picked, once.
3. **No server change.** The server never stored two rows: `stores_household_name_key` is a
   unique index on `(household_id, store_name_key(name))` and `add_store` (which
   `create_household` calls per picked name) does `on conflict do nothing`, so every writer (app,
   MCP, API, scripts) gets one store per key. `supabase/tests/stores.test.sql` already covers
   `p_stores => ['EDEKA', 'REWE', 'dm', 'rewe']` giving three stores. Only the stored spelling
   changes: a typed „edeka“ is now stored as „EDEKA“, as the chip names it.
4. **e2e uses the chip's spelling.** `chainStores` in `e2e/tests/helpers.ts` typed „Edeka“ to get
   a store spelled that way; it now ticks the EDEKA chip, so the specs name the store „EDEKA“.
5. **Legal N-23.** Nothing new is shown: the chips stay plain text from `popularStores`.

## Job 85: More is M-P2, 2026-11-02

Peter picked M-P2 from job 79's prototypes (PR #206, `docs/design/menu-research.md`). Calls made
on the way:

1. **The menu is data.** `_Item` in `more_screen.dart` names each row's glyph, key and hex face;
   `_Item.groups` is the order: Konto and Premium; invite, join, archived; Zugänge; Einstellungen
   and Datenschutz; feedback, help, Rechtliches; Abmelden alone. A row that may not show (Premium
   before the offer, invite outside a household, help and archive behind their flags) drops out,
   and a group without rows drops with it. The Premium decision moved up into the list, so a
   hidden Premium row leaves no hairline behind.
2. **No row hints.** M-P2 shows one line per row. The hint strings (`accessRowHint`,
   `accountRowHint`, `premiumRowHint`, `lifetimeUnlocked`, …) and the „Feedback“ section label are
   gone. The Premium page still says whether the household has Premium.
3. **Datenschutz and Rechtliches are pages of the More branch** (`/more/privacy`,
   `/more/legal`, `MorePage.privacy` and `.legal`), like Konto and Einstellungen, so back, a
   reload, deep links and the wide layout (beside the list, row selected) work as for the other
   pages. Their screen names are `privacy` and `legal`. The prototype pushed plain routes, which
   the wide layout and the address bar would not show.
4. **The usage-data switch is the same widget under the same heading.** The Datenschutz page
   keeps the section „Nutzungsdaten“ with „Nutzungsdaten und Fehlerberichte senden“ and its hint,
   only in builds with a PostHog key, and calls `Analytics.decide` as before. Below it the
   privacy policy link. The heading stays so the approved consent text's „Mehr → Nutzungsdaten“
   still leads somewhere recognisable; the text itself is versioned and Legal-approved, so it is
   not changed here (NEEDS_LEAD Job 85).
5. **The policy link is „Datenschutzerklärung“ / "Privacy policy"** (`privacyPolicy`), since
   „Datenschutz“ / "Privacy" now names the menu row and page. It appears on both pages.
6. **The update card is a typed stub.** The app has no update check (no Shorebird, no store
   lookup), so `AppUpdates` (`app/lib/more/app_update.dart`) has one implementation,
   `NoAppUpdates`, which never offers anything. The card renders `PatchReady` („Update bereit“,
   „Neu starten“) and `StoreVersion` („Neue Version da“, „Aktualisieren“); closing it hides it
   until More is built anew. Wiring a real check means one new `AppUpdates` passed to
   `MoreScreen`.
7. **Job 79's prototype switcher never landed** (PR #206 is a draft, not for merge), so there was
   nothing to remove from main.

### Job 85, addendum 1 (Peter via lead, 2026-11-03)

8. **Rechtliches is a section of More, not a page.** Below help, a small „Rechtliches“ label
   (the list's section label) heads a group of direct rows: Impressum, Datenschutzerklärung,
   „Nutzungsbedingungen (EULA)“ (`termsUrl`, as on the Premium page: Apple's EULA on iOS, the
   support page elsewhere until Hummlist has terms) and Lizenzen. The imprint is two taps from
   the list (Mehr → Impressum), as §5 DDG wants it („unmittelbar erreichbar“). The privacy
   notes for purchases (`/datenschutz-kaeufe`) are not linked anywhere in the app today, so
   they get no row. The `/more/legal` page is gone; the path redirects to `/more`. The label is
   the only section label on More: M-P2 has none, but a legal group without a name read like
   more help rows. Replaces item 3's Rechtliches page and item 5's second policy link.
9. **The usage-data row is „Nutzungsdaten“, not „Datenschutz“.** Next to a „Datenschutzerklärung“
   row, a „Datenschutz“ row that holds a switch was easy to mistake for the policy. The row,
   the page title and the route (`/more/usage-data`, screen name `usage_data`) now say what is
   there; the page holds only the switch. It sits with Einstellungen (a setting of this device),
   the policy with the legal rows. In builds without a PostHog key the row is hidden, since its
   page would be empty. This also makes the approved consent text and the privacy policy right
   again: they say „Mehr → Nutzungsdaten“. Replaces items 3 and 4's Datenschutz page.

## Job 82: the hummlist.com waitlist (Spec #10), 2026-11-02

1. **Off until Peter turns it on, so it can merge.** Every push to `main` deploys hummlist.com,
   and the brief allows a merge only if production doesn't change. The site builds a waitlist
   mode only when `HUMMLIST_WAITLIST=on` or in a non-production build. The Vercel function answers
   404 without its two env vars, and the edge function answers 404 without its two secrets.
   `site/scripts/classic-diff.mjs` builds `origin/main` and the branch with production settings
   and compares `dist/`: 95 files each, identical except one added
   `<meta name="robots" content="noindex">` on `/de` and `/en`, which replaces the header
   (point 3).
2. **The logic lives in a Supabase edge function behind a thin Vercel function.** Legal wants the
   form to post to hummlist.com and run in fra1. The Vercel function only hashes the IP and
   forwards, so the database credentials and the Resend key stay in Supabase, and the logic is
   tested with Deno and pgTAP like the other functions. A shared secret keeps everyone else out of
   the edge function.
3. **Noindex per path.** PM override 2: only the landing pages lose noindex, and only once the copy
   is live. `vercel.json` sends `X-Robots-Tag: noindex` on every path except `/de` and `/en`,
   and those two carry a robots meta tag in every build except a production waitlist build.
   That build can only succeed without placeholders (point 4).
4. **Placeholders block production.** Unapproved texts carry `⟦LAUNCH COPY⟧`, `⟦LEGAL W2⟧` and
   similar markers. A production build fails on any marker, and the edge function won't mail a
   marked template unless `WAITLIST_ALLOW_PLACEHOLDERS=1`. That makes AC21 a build rule rather
   than a reminder.
5. **Answer before the work (AC6).** The sign-up answers right after validation and the rate
   counter, and stores and mails in `EdgeRuntime.waitUntil`. A new address, a known one and a
   dropped bot get the same body at the same time. The local stack's oneshot workers drop
   `waitUntil` work, so locally the function finishes the work first.
6. **Tokens in the fragment, actions on a button.** Mail links carry the token in `#…`, so no
   server log sees it, and the page sends it only when the button is pressed (Legal: no action on
   GET, mail scanners). Unsubscribe links are signed with an HMAC of the row id, so links in old
   mails keep working without storing a second token.
7. **Rate limit in Postgres.** Counters keyed by SHA-256 of a daily HMAC of the IP, per hour,
   deleted after 2 hours: in-memory counters don't survive Vercel's instances
   (NEEDS_LEAD "Job 82", point 1).
8. **Recipients closed by default.** Without `WAITLIST_MAIL_ALLOW=*` only `hello+…@hummlist.com`
   is stored and mailed, so a preview can't mail a stranger before Peter opens it.
9. **Invites are a script, never automatic** (Addendum 2): `scripts/waitlist/invite.ts`, dry run by
   default with counts only, `--confirm <batch>` repeating the batch id.
10. **Root `/` unchanged.** Live it already redirects to the landing pages by language (307), not
    to the browser app (PM override 3).
11. **app.hummlist.com gets noindex.** AC15 says the browser app "still has noindex", but on
    2026-11-03 it had none (no `X-Robots-Tag`, no robots meta, `robots.txt` 404). The app's
    `vercel.json` now sends `X-Robots-Tag: noindex` on every path. preview.app.hummlist.com gets
    it with this merge, and app.hummlist.com with the next store release (`docs/DEPLOY.md`, "Web
    app").
