# Deploys, smoke test, rollback, keepalive

This page covers the hosted Supabase project `jdwqrallbpdbshrdhenk`: how
changes reach it, how each deploy is checked, how to roll back, and what
keeps the free project from pausing. Nightly backups and restores are in
[`BACKUP.md`](BACKUP.md). Releases of the apps are in
[`RELEASE.md`](RELEASE.md).

## Deploy

Every push to `main` that touches `supabase/**`,
`scripts/smoke-remote.sh`, `scripts/mcp-smoke.sh` or the workflow file runs **Supabase deploy**
(`.github/workflows/supabase-deploy.yml`):

1. Migrations, through the Management API (`supabase/deploy/migrate.ts`).
2. Edge functions, bundled by Supabase (`supabase functions deploy --use-api`). It deploys
   every directory under `supabase/functions/` except `_shared`, so a new function needs no list
   entry, only its `[functions.<name>]` section in `supabase/config.toml` (the shared import map,
   checked by `supabase/deploy/config_test.ts`, and `verify_jwt`).
3. Smoke test, `scripts/smoke-remote.sh` (see below). The step retries
   for about half a minute while the new version rolls out, then fails the run.

The workflow runs from `main` only. A dispatch on another branch fails
before it deploys anything.

The guides site waits for this workflow: a site build of a push that ran it
goes live only after the run has passed all three steps (see "Guides site"
below). The workflow itself waits for nothing.

## Web app: preview from main, production with the store release

The Vercel project `peter-trost/family-groceries` builds the Flutter web app
(`vercel.json`, `scripts/vercel.sh`) only for the `release` branch, and only
when the push changes the app (see "Build skips" below). Since job
web-release-align (2026-10-29), production moves only with a store
upload, so the web app never runs ahead of TestFlight and Play. Since job 30
(2026-10-30) every green merge goes to the internal testers by itself, and
when that Release run's `Uploaded` job succeeds it also moves
production (public; [`RELEASE.md`](RELEASE.md)):

| URL | Serves | Who can open it |
| --- | --- | --- |
| `https://preview.app.hummlist.com` (no `preview.app.snacklist.app` yet: that domain is not set up in Vercel) | frozen: the last build of `main` from before 2026-11-09, since `main` no longer builds (a branch domain on `main`) | Vercel Authentication: members of the Vercel team only, or a share link |
| `https://app.snacklist.app` and `https://app.hummlist.com` (alias `family-groceries-pied.vercel.app`) | the newest build of the `release` branch, Vercel's production branch | everyone |
| `https://family-groceries-git-<branch>-peter-trost.vercel.app` | frozen: no branch builds since 2026-11-09 | Vercel Authentication |

How production moves:

1. A Release run (automatic after CI on `main`, the Monday schedule, or a
   dispatch via `gh workflow run release.yml`) ships green `main` to
   TestFlight and/or Play internal. Its `Uploaded <sha>` job succeeds.
2. Its `Web production` job then pushes that commit to the `release` branch
   with the workflow's own token. If `release` already contains the commit (a
   rerun of an older Release run), the job changes nothing; otherwise the
   plain push only fast-forwards, so production never moves back from here.
   No branch protection or ruleset may cover `release`: one that blocks
   pushes without a PR, or from `github-actions`, fails this job after a
   store already got the build. None does; check both kinds with
   `gh api repos/trost-systems/family-groceries/rules/branches/release`
   (rulesets, must print `[]`) and
   `gh api repos/trost-systems/family-groceries/branches/release --jq .protected`
   (classic protection, must print `false`).
3. If the push changes the app, Vercel builds `release` as a production deployment and assigns
   both production domains to it (a few minutes). No Vercel token is stored in
   GitHub. The production branch is a project setting (Settings,
   Environments, Production, Branch Tracking; API
   `PATCH /v9/projects/{id}/branch`, read back as `link.productionBranch`),
   and auto-assignment of production domains must stay on.

### Build skips

Each Flutter build costs Build CPU Minutes, so since 2026-11-09 only
`release` builds, and only when the app changed. `vercel.json`'s
`ignoreCommand` runs `scripts/vercel-ignore.sh` before the build (it
overrides the project's Ignored Build Step setting, which still holds the
old one-liner). Vercel skips the build on exit 0, builds on exit 1, and fails
the deployment on any other exit code.

- `main` and every other branch skip, so the preview and branch URLs stay
  frozen. Check a merged change locally (`scripts/vercel-local.sh`) or on
  `app.snacklist.app` after its Release run.
- `release` skips only when `git diff` proves that `app/` (tests excluded),
  `vercel.json`, `scripts/vercel.sh`, `scripts/vercel-ignore.sh` and
  `scripts/join-config.sh` are unchanged since `VERCEL_GIT_PREVIOUS_SHA`, the
  last production deployment's commit. A docs-only release push keeps the
  current production build.
- When that commit is empty or missing, `release` builds. Vercel clones 10
  commits deep, so a release push 10 or more commits past the last
  production build has no previous commit in the clone. The old dashboard
  one-liner then let `git diff` exit 128, and the three production pushes of
  2026-11-10 ended in ERROR before the build (job 180).
- `scripts/vercel-ignore-test.sh` (lint gate) checks these cases in a
  10-commit clone.
- Vercel reads `vercel.json` from the deployed commit. A commit older than
  job 180 still runs the dashboard's one-liner, so ship such a commit by hand
  only when it is at most 9 commits past the last production build.
- To build previews again, change the `case` in `scripts/vercel-ignore.sh`.

`hummlist-site` has its own `ignoreCommand` in `site/vercel.json` (see
"Guides site" below); the old dashboard step, `case "$VERCEL_GIT_COMMIT_REF" in main|"") exit 1;; *) exit 0;; esac`,
is overridden and its branch rule kept, so PRs get no site preview. The other projects keep their step in the dashboard. `hummlist-mcp` runs
`git diff --quiet HEAD^ HEAD -- . || exit 1`, which exits 1 on any git error.
`hummlist-nexus` has no git connection.

A dry run (`upload=false`) or a skipped run leaves `release`, and so
production, where it is. A failed `Web production` job fails the
Release run (the automatic failure issue covers it; a dispatch's starter
watches it).

Ship the web app by hand (only a commit that is already in a store release):

```bash
git push origin <sha>:refs/heads/release
```

Roll the web app back: Vercel dashboard, project
`peter-trost/family-groceries`, Deployments, the earlier production
deployment, **Instant Rollback**. Vercel then stops assigning new production builds to the production domains until
someone selects **Undo Rollback** (or promotes a deployment), so do that once
the fix has shipped. Pushing an older commit to `release` needs `--force`
and rebuilds; Instant Rollback is faster.

Sign-in on the preview: Google and Apple go through the Supabase redirect
flow ([`AUTH.md`](AUTH.md)), so the only setting is the hosted redirect
allow list, which has `https://preview.app.hummlist.com/**`. The phone apps'
invite links point at `https://app.snacklist.app` (`APP_URL`, since job 174);
Hummlist builds keep `https://app.hummlist.com`.

## Guides site: snacklist.app from every push to main

The Vercel project `hummlist-site` (Root Directory `site`, `site/vercel.json`)
builds the site from every push to `main`: the landing pages `/de` and `/en` (where `/`
redirects by `Accept-Language`), the guides, the changelog and the legal pages. A push to `main` is its production
deployment and goes live on `https://snacklist.app`
(`www.snacklist.app` redirects to it; `hummlist.com`, and through it
`www.hummlist.com` and `hummlist-site.vercel.app`, 308 to it by the host rules
in `site/vercel.json`) without a manual step. When the push also runs
**Supabase deploy**, the site goes live only after that run (below). Since job 174
the pages name snacklist.app as canonical (`siteUrl` in `site/config.json`). Every other
branch skips the build since 2026-11-09, so check a
site change locally with `npm run build` in `site/`.

The build reads two files outside `site/`, so the project setting "Include
files outside the root directory in the Build Step" must stay on: the release
record `releases/releases.json` and `app/pubspec.yaml`. Their version decides
which guides and sections production shows (`site/README.md`, "Live
version"). Without them the build fails and the last deployment stays live.

A public release changes what the site shows through the same path: the
**Public release record** workflow commits the new entry to `main`
([`RELEASE.md`](RELEASE.md), "Public releases"), and that push is the
production build with the new live version. No deploy hook or Vercel token
is involved.

### The site waits for Supabase deploy

A site page can describe a function or a policy that only the same commit
deploys, so the site must not go live before the functions (job 209). The
site's `ignoreCommand` (`site/vercel.json`) runs `site/scripts/supabase-gate.mjs`
before the build:

- It lists the commits since the live site (`VERCEL_GIT_PREVIOUS_SHA`, the
  last successful production deployment, up to this commit). Vercel clones
  10 commits deep; when the live site's commit is further back (after a run
  of ERROR builds, say), the gate fetches more history from GitHub, up to
  850 commits. If it still cannot reach that commit, it exits 2: checking
  only this commit would skip an earlier commit whose run failed. Check
  **Supabase deploy** for the commits in between, then Redeploy with the
  Ignore Build Step off.
- None of them touches the workflow's paths (`DEPLOY_PATHS` in the script;
  a site test keeps it equal to `on.push.paths`): the site builds at once.
  This is the case for a site-only push.
- Otherwise it asks the GitHub API for the **Supabase deploy** runs with
  `event=push` on `main`, takes the run of the newest of those commits, and
  polls every 30 s. When this commit itself touches the paths, only its own
  run counts, so a site never goes live on an earlier commit's run. A
  rollback dispatch (`ref`) is a `workflow_dispatch` run and never counts.
- The run succeeded (migrations, functions and smoke test): the site builds
  and goes live.
- The run failed or was cancelled, or 25 minutes passed: the gate exits 2,
  the deployment ends in ERROR and the last good site stays live. Vercel's
  build limit is 45 minutes.

A site-only push that follows a mixed push before that push's site is live
waits for the mixed push's run too: it carries the same pages. Once the site
of a commit with a green run is live, later site-only pushes no longer wait
for anything. A commit whose message has a skip-CI marker (or the
`skip-checks: true` trailer) starts no run; the gate then waits 90 s for one
and builds.

When a mixed push and a site-only push behind it both wait on the same run,
both open when it turns green, about 30 s apart at most. If the older one
finished last and took the domains, the next push corrects it; or promote the
newer deployment in Vercel.

After a failed run, the site of that commit stays off production. Fix
forward: the next push's run succeeds and its site carries both changes. If
the run is rerun green instead, select **Redeploy** on the ERROR deployment
in the Vercel project `hummlist-site` (keep "Use project's Ignore Build
Step" on), and the gate passes. To publish a site past a failing Supabase
deploy on purpose, Redeploy with that box off.

The gate calls the GitHub API without a token (60 requests per hour per
address; a normal deploy needs about 10, and a spent limit makes the gate
sleep until its reset). Vercel's build machines share addresses with other
customers, so a spent limit is not ours to prevent: a read-only GitHub token
in the project's environment variable `GITHUB_ACTIONS_READ_TOKEN` lifts it,
and is recommended ([`NEEDS_PETER.md`](NEEDS_PETER.md), "Job 209"). Without
it, the sign is `GitHub answered 403` with `remaining 0` in the build log. A waiting build holds one of
the team's concurrent build slots, so an app or MCP proxy build may queue
behind it for those minutes.

Check the gate without Vercel (it only reads GitHub):

```bash
cd site
VERCEL_GIT_COMMIT_REF=main VERCEL_GIT_COMMIT_SHA=<sha> VERCEL_GIT_PREVIOUS_SHA=<sha>^ \
  node scripts/supabase-gate.mjs; echo "exit $?"   # 1 builds, 2 stays off production
```

## Smoke test

`scripts/smoke-remote.sh [project URL]` checks a deployed project. It
sends no credentials, writes nothing and prints `PASS` or `FAIL` per
check. It exits 1 if any check fails. The one exception is the opt-in
`SMOKE_PUBLIC_API=1` part in the table.

| Check | Passes when |
| --- | --- |
| `GET /functions/v1/health` | 200 and `{"ok": true, "database": true}`: the function read from Postgres. |
| `POST /functions/v1/voice` with a made-up bearer token | 401 and `WWW-Authenticate: Bearer`. |
| `scripts/mcp-smoke.sh <project>/functions/v1/mcp` | Its discovery checks pass: 401 without a token and with a made-up one, both pointing at the metadata on the same host; the metadata names the endpoint as `resource`; the authorization server's metadata has the authorize, token and registration endpoints. `initialize` + `tools/list` report `SKIP` (no token in CI; set `MCP_SMOKE_TOKEN` to run them). |
| `GET /functions/v1/api/v1/items` without a key | 404 `not_found` while `app_switches.public_api` is off, 401 `missing_token` once it is on ([`API.md`](API.md)). |
| The same with `SMOKE_PUBLIC_API=1`, for the day the API is switched on | 401 `missing_token`; then unknown keys, each with another made-up address in `X-Forwarded-For` and `X-Real-IP`, get 401 until a 429 `auth_throttled` by request 21: the limit counts the gateway's address, not a header the client sets. This part writes the caller's failure count: unknown keys from that address get 429 for up to 10 minutes, valid keys go on working. Run it once: a second run within those 10 minutes gets its 429 at the first request and fails, since that shows nothing about the headers. |

The public MCP URL `https://mcp.snacklist.app` (also `https://mcp.hummlist.com`) is a Vercel proxy in front of
the same function ([`MCP.md`](MCP.md#public-url-mcpsnacklistapp)). It needs no
deploy of its own beyond Vercel building `mcp-proxy/` from `main`; check it
with `scripts/mcp-smoke.sh https://mcp.snacklist.app`.

The same Vercel project, `hummlist-mcp`, serves the public REST API at
`https://api.snacklist.app/v1`: its first rewrite sends every path on that host to the `api`
function with the marker `via=api-snacklist` ([`mcp-proxy/README.md`](../mcp-proxy/README.md#apisnacklistapp)).
One step by hand, once: the lead adds the domain `api.snacklist.app` to `hummlist-mcp` in the
Vercel dashboard (Settings, Domains). The wildcard DNS record already points at Vercel; until the
domain is attached the host answers `DEPLOYMENT_NOT_FOUND`. Then check it with
`scripts/api-proxy-smoke.sh https://api.snacklist.app/v1`: without a key, `GET /items` gets 401
`missing_token` (404 `not_found` while `app_switches.public_api` is off) with
`Cache-Control: no-store` and no cache hit; with `API_SMOKE_KEY=fgp_…` (a read key, never printed)
also `/categories?via=smoke` answers 200 (the proxy's marker arrives, so every `via` is dropped)
and `/items?limit=abc` 400 `validation_failed` (the caller's query arrives). It cannot show from
one machine that callers get separate unknown-key budgets; the api tests cover that.

Run it from any machine with `curl` and `jq`:

```bash
scripts/smoke-remote.sh                                  # production
scripts/smoke-remote.sh http://127.0.0.1:54321           # local stack
SMOKE_PUBLIC_API=1 scripts/smoke-remote.sh               # production, once the public API is on
```

## Roll back edge functions

1. Find the last good commit on `main`, for example in the history of
   the **Supabase deploy** runs.
2. Open the Actions tab, select **Supabase deploy**, then select **Run
   workflow** on `main`.
3. Enter the commit SHA in `ref` and run.

Or from a shell:

```bash
gh workflow run supabase-deploy.yml -R trost-systems/family-groceries --ref main -f ref=<sha>
```

The run checks out that commit, deploys its edge functions and runs that
commit's own `scripts/smoke-remote.sh`. It skips migrations, and the site
does not wait for it or move with it. It refuses:

- a SHA that is not on `main`, so only reviewed code reaches production;
- a commit older than `scripts/smoke-remote.sh` (job 13), because it
  cannot be smoke-tested. Those versions of `health` never queried
  Postgres, and their `mcp` lost its `WWW-Authenticate` header on the
  hosted gateway.

What a rollback does not change:

- The database. Older functions run against the newer schema. That works
  because migrations stay backward compatible (CLAUDE.md, squawk compat
  rules): old app builds in the stores need the same guarantee.
- A function that did not exist at that commit. It keeps its current
  version.

Once Snacklist Premium is on sale, do not roll `purchases` back past job
185 (`20261112232617_per_user_premium.sql`). An older `purchases` treats
every App User ID as a household: a purchase from a new build (a user id)
gets `no_household`, answers 200, and RevenueCat never sends it again.

The next push to `main` that touches `supabase/**` deploys `main` again.
So land the fix on `main`, or the rollback lasts only until the next
deploy.

## Roll back the database: fix forward

Migrations are forward-only. Production has already run every migration
on `main`, and the deploy refuses a migration that sorts before the
newest one (CLAUDE.md, "schema check: history"). To undo a migration:

1. Write a new migration that reverses the change, for example
   `supabase migration new revert_<name>`. Restore a dropped function or
   policy from the old migration's text. Don't edit or delete the old
   migration.
2. Keep it backward compatible: the squawk rules in `scripts/lint.sh`
   apply to the revert too.
3. If the migration lost data, restore last night's backup
   ([`BACKUP.md`](BACKUP.md)) after the revert has landed.
4. Land it like any PR. The deploy applies it.

## Keepalive

Supabase pauses a free project after 7 days without enough database
activity (sources in `DECISIONS.md`, job 13). **Keepalive**
(`.github/workflows/keepalive.yml`) runs daily at 05:23 UTC and on
demand. It calls `health`, which runs one read-only query
(`select exists (select from public.classifier_terms)`, the shared seed
dictionary, no user data). It fails if the project or its database does
not answer. A failed run opens the issue "Keepalive failed", naming the step
that failed, or comments on it if it is already open. The
next green run closes it. GitHub mails a scheduled run's failure only to
whoever last edited its cron line (the bot account), so the issue is the
signal for Peter: watch the repository's issues.

A second step posts to `feedback-screenshots/sweep`, which removes the screenshots of deleted
feedback notes and uploads that never got a note (`docs/FEEDBACK.md`, "Screenshots"). It needs
no secret. The step fails on anything but 200 with `{"removed": n}`, and the issue names it.

GitHub disables scheduled workflows in a public repository after 60 days
without repository activity, and never turns them back on by itself.
What guarantees the schedule:

- Every push to `main` re-enables it (CI job `keepalive-schedule`). A push
  is also repository activity, so the clock restarts.
- If nothing is pushed for 60 days and the schedule goes off, the Actions
  page shows "This scheduled workflow is disabled". Supabase also emails
  the owner before it pauses the project. Then run the commands below.

Best effort on top: each keepalive run re-enables its own workflow
(`gh workflow enable`, allowed by `permissions: actions: write`). Some
tools claim that restarts GitHub's 60-day clock. GitHub doesn't document
it, so don't rely on it.

```bash
gh workflow enable keepalive.yml -R trost-systems/family-groceries
gh workflow run keepalive.yml -R trost-systems/family-groceries
```

### If the project was paused

Supabase emails the project owner before it pauses a project. A paused
project can be restored for up to a year:

1. Open https://supabase.com/dashboard/project/jdwqrallbpdbshrdhenk.
2. Select **Resume project** and wait until the status is healthy.
3. Run `gh workflow run keepalive.yml -R trost-systems/family-groceries`
   or `scripts/smoke-remote.sh` and check that it passes.
