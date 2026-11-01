# Deploys, smoke test, rollback, keepalive

This page covers the hosted Supabase project `jdwqrallbpdbshrdhenk`: how
changes reach it, how each deploy is checked, how to roll back, and what
keeps the free project from pausing. Nightly backups and restores are in
[`BACKUP.md`](BACKUP.md). Releases of the apps are in
[`RELEASE.md`](RELEASE.md).

## Deploy

Every push to `main` that touches `supabase/**`,
`scripts/smoke-remote.sh` or the workflow file runs **Supabase deploy**
(`.github/workflows/supabase-deploy.yml`):

1. Migrations, through the Management API (`supabase/deploy/migrate.ts`).
2. Edge functions, bundled by Supabase (`supabase functions deploy --use-api`).
3. Smoke test, `scripts/smoke-remote.sh` (see below). The step retries
   for about half a minute while the new version rolls out, then fails the run.

The workflow runs from `main` only. A dispatch on another branch fails
before it deploys anything.

## Web app: preview from main, production with the store release

The Vercel project `peter-trost/family-groceries` builds the Flutter web app
(`vercel.json`, `scripts/vercel.sh`) from every push. Since job
web-release-align (2026-10-29), `app.hummlist.com` moves only with a store
release, so the web app never runs ahead of TestFlight and Play. Since job 30
(2026-10-30) every green merge goes to the internal testers by itself, but
only a dispatched Release run moves `app.hummlist.com`, which is public
([`RELEASE.md`](RELEASE.md), "Public releases"):

| URL | Serves | Who can open it |
| --- | --- | --- |
| `https://preview.app.hummlist.com` | the newest build of `main` (a branch domain on `main`) | Vercel Authentication: members of the Vercel team only, or a share link |
| `https://app.hummlist.com` (alias `family-groceries-pied.vercel.app`) | the newest build of the `release` branch, Vercel's production branch | everyone |
| `https://family-groceries-git-<branch>-peter-trost.vercel.app` | each branch's newest build | Vercel Authentication |

How production moves:

1. A dispatched Release run (`gh workflow run release.yml`) ships green
   `main` to TestFlight and/or Play internal. Its `Uploaded <sha>` job
   succeeds. The automatic runs after each merge stop here.
2. Its `Web production` job pushes that commit to the `release` branch with
   the workflow's own token. If `release` already contains the commit (a rerun
   of an older Release run), the job changes nothing; otherwise the plain push
   only fast-forwards, so production never moves back from here. No branch
   protection or ruleset may cover `release`: one that blocks pushes without
   a PR, or from `github-actions`, fails this job after a store already got
   the build. None does; check both kinds with
   `gh api repos/trost-systems/family-groceries/rules/branches/release`
   (rulesets, must print `[]`) and
   `gh api repos/trost-systems/family-groceries/branches/release --jq .protected`
   (classic protection, must print `false`).
3. Vercel builds `release` as a production deployment and assigns
   `app.hummlist.com` to it (a few minutes). No Vercel token is stored in
   GitHub. The production branch is a project setting (Settings,
   Environments, Production, Branch Tracking; API
   `PATCH /v9/projects/{id}/branch`, read back as `link.productionBranch`),
   and auto-assignment of production domains must stay on.

A dry run (`upload=false`), a skipped run or an automatic run leaves
`release`, and so `app.hummlist.com`, where it is. A failed `Web production`
job fails the dispatched run (whoever started it watches it; no issue).

Ship the web app by hand (only a commit that is already in a store release):

```bash
git push origin <sha>:refs/heads/release
```

Roll the web app back: Vercel dashboard, project
`peter-trost/family-groceries`, Deployments, the earlier production
deployment, **Instant Rollback**. Vercel then stops assigning new production builds to `app.hummlist.com` until
someone selects **Undo Rollback** (or promotes a deployment), so do that once
the fix has shipped. Pushing an older commit to `release` needs `--force`
and rebuilds; Instant Rollback is faster.

Sign-in on the preview: Google and Apple go through the Supabase redirect
flow ([`AUTH.md`](AUTH.md)), so the only setting is the hosted redirect
allow list, which has `https://preview.app.hummlist.com/**`. The phone apps'
invite links still point at `https://app.hummlist.com` (`APP_URL`).

## Guides site: hummlist.com from every push to main

The Vercel project `hummlist-site` (Root Directory `site`, `site/vercel.json`)
builds the site from every push: the landing pages `/de` and `/en` (where `/`
redirects by `Accept-Language`), the guides, the changelog and the legal pages. A push to `main` is its production
deployment and goes live on `https://hummlist.com` without a manual step
(`www.hummlist.com` and `hummlist-site.vercel.app` redirect there). Every other
branch gets a preview deployment behind Vercel Authentication; the PR shows it
as the commit status "Vercel – hummlist-site".

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

## Smoke test

`scripts/smoke-remote.sh [project URL]` checks a deployed project. It
sends no credentials, writes nothing and prints `PASS` or `FAIL` per
check. It exits 1 if any check fails.

| Check | Passes when |
| --- | --- |
| `GET /functions/v1/health` | 200 and `{"ok": true, "database": true}`: the function read from Postgres. |
| `POST /functions/v1/voice` with a made-up bearer token | 401 and `WWW-Authenticate: Bearer`. |
| `scripts/mcp-smoke.sh <project>/functions/v1/mcp` | Its discovery checks pass: 401 without a token and with a made-up one, both pointing at the metadata on the same host; the metadata names the endpoint as `resource`; the authorization server's metadata has the authorize, token and registration endpoints. `initialize` + `tools/list` report `SKIP` (no token in CI; set `MCP_SMOKE_TOKEN` to run them). |

The public MCP URL `https://mcp.hummlist.com` is a Vercel proxy in front of
the same function ([`MCP.md`](MCP.md#public-url-mcphummlistcom)). It needs no
deploy of its own beyond Vercel building `mcp-proxy/` from `main`; check it
with `scripts/mcp-smoke.sh https://mcp.hummlist.com`.

Run it from any machine with `curl` and `jq`:

```bash
scripts/smoke-remote.sh                                  # production
scripts/smoke-remote.sh http://127.0.0.1:54321           # local stack
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
commit's own `scripts/smoke-remote.sh`. It skips migrations. It refuses:

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
