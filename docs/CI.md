# CI

`.github/workflows/ci.yml` runs on every PR, on every push to `main` and on
demand (`gh workflow run ci.yml --ref <branch>`). `ci-ok` is the one check a
merge waits for (`scripts/merge-pr.sh`). For only the e2e and db gates on a
branch, with a spec filter, use `scripts/ci-e2e.sh` (On-demand e2e, below).

## Gates

Each CI job installs its tools and runs one script in `scripts/gates/`.
`scripts/verify.sh` runs the same scripts locally, so a local run and CI check
the same things.

| Gate | What it checks | Runs locally |
| --- | --- | --- |
| `gitleaks` | No secret in the history or in what the working tree could commit (ignored output such as Playwright traces is skipped) | yes |
| `lint` | actionlint, shellcheck, `tsc --noEmit` for `e2e/`, the TypeScript pack's enforced rules (`tool/lint/ts/strict.ts`, Deno pinned in `.dvmrc`, the version `pack.ts` lists), `scripts/check-gates.sh`, `scripts/lint.sh`, the generated design tokens and app icon against their source (`design/tokens/build.mjs --check`, `design/app-icon/build.mjs --check`) | yes |
| `changelog` | The PR's `## Changelog` section, structure only (pull requests only, not Dependabot), and the changelog drafts in `releases/changelog/`, its `pending.json` and overrides, and `releases/flags.json`; the note's `flag:` / `hold:` keys must be in that file ([`CHANGELOG.md`](CHANGELOG.md)) | the drafts, and HEAD's message if it has a section |
| `site` | The guides site in `site/`: build checks (with the agent checks: llms.txt, `.md` twins, robots, sitemap, hreflang, JSON-LD, links, launch guard), tests, a production build; no real access token in the repo | yes |
| `site-agent` | snacklist.app for AI agents ([`AGENT_FIRST.md`](AGENT_FIRST.md)): the MCP probe's fixture tests and `scripts/mcp-smoke.sh https://mcp.snacklist.app` without credentials, the built site served like Vercel serves it (llms.txt, twins, sitemap, OpenAPI when `public-api` is on) and the waitlist form in Chromium | yes |
| `db` | Migrations on a fresh database, pgTAP, the classifier sweep, `db lint` | yes |
| `functions` | Deno fmt, lint and tests for the functions, the classifier and the deploy tooling | yes |
| `emails` | The mails in `emails/` ([`EMAIL.md`](EMAIL.md)): type checks, `supabase/templates/` and config.toml's template block exactly as `emails/` builds them, the wording, footer and template tests | yes |
| `nexus` | The ops dashboard in `nexus/` ([`nexus/README.md`](../nexus/README.md)): Deno fmt, lint, type check, tests of the snapshot pipeline (fixture ops dir, privacy, hill-climb docs on main) and the page, one browser bundle | yes |
| `fg-cli` | Deno fmt, lint and tests for the verify skill's CLI | yes |
| `flutter` | Generated l10n, format, `flutter analyze --fatal-infos`, tests; the same for the Widgetbook (`app/widgetbook/`) | yes |
| `web-prod` | The production web build, into `app/build/web-prod` | yes |
| `fastlane` | The Gemfile.lock installs and the Fastfile parses | yes |
| `e2e` | Playwright against the release web build and the local stack | yes, under `/tmp/fg-e2e.lock` |
| `android` | Debug APK build (the app's Kotlin) and its JVM unit tests (`WidgetPayloadTest`) | `--only android` |
| `ios` | Simulator build (the app's Swift); the built app holds the app icon (light, dark, tinted, the Icon Composer stacks) and the launch screen's assets; macOS only | no |

`.github/workflows/widgetbook.yml` is not a gate: on pushes to `main` that touch
`app/` and by hand it builds the Widgetbook for the web (`scripts/widgetbook.sh`)
and uploads it as the artifact `widgetbook` (docs/DESIGN.md, "Widgetbook").

```bash
scripts/verify.sh                          # every local gate, e2e last
scripts/verify.sh --only flutter,db        # some gates
scripts/verify.sh --only e2e -- tests/list.spec.ts   # one spec, under the e2e lock
scripts/verify.sh --skip-e2e
scripts/verify.sh --history 2026-11-14     # runs, failures, seconds and flakes per gate since then
```

### The local loop

`verify.sh` stops at the first gate that fails and exits with that gate's
code. Its last lines are plain text, so `| tail` and `grep` still show the
verdict:

```text
[verify] took: gitleaks 12 s, lint 101 s
[verify] FAILED: lint (exit 1) after 101 s; its output: <git dir>/verify/lint.20261113-214502.4711.1.log; not run: changelog site ...
```

A green run ends in `[verify] passed: <gates>`. Each run of a gate writes its
whole output, stdout and stderr, to a file of its own in `<git dir>/verify/`
(`VERIFY_LOG_DIR`); the five newest per gate stay, as does the file of a run
that is still going, and `<gate>.log` there links to the newest. When a
filter cut the failure off, read the file the verdict names instead of
running the gate again: it holds that run's output until five later runs of
the gate, a second run at the same time included. The
`[gate]` lines are blue only on a terminal.

Every gate run is a row in the ledger, `verify-ledger.tsv` in the clone's
`.git` (`VERIFY_LEDGER`; worktrees share it): time, branch, tree, gate, result,
seconds, arguments (`--screenshots` among them), seconds waited for a lock.
The tree is the hash of the working tree: uncommitted and untracked files and
the skip-worktree and assume-unchanged ones (the port block in
`supabase/config.toml`) included,
ignored files (`.env` files, build output) not. `--history` prints, per gate,
the runs, the failed runs, the median and p90 seconds of the passing runs,
and the trees that have both results for the same arguments.

Two notes come from the ledger:

- `flake: <gate> had the other result on this same tree`, with the same
  arguments. The files git does not ignore are the same, so the cause is
  outside them. The causes found in 199 jobs' runs
  (job 219) were all of this kind: another Flutter SDK on `PATH`, a stack that
  is down or still has the schema from before a rebase, a held port,
  `origin/main` moving under the lint gate's migration check, a missing tool
  (`JAVA_HOME`, Playwright's browsers), the host pausing an e2e run. Find the
  one that applies and write it into the PR. A rerun that passes is a second
  observation, not a fix.
- `<gate> has failed 3 runs in a row on this branch`, whatever the arguments.
  Over those jobs the p90 of such streaks was 1 (lint), 2 (flutter), 3 (e2e)
  and 4 (db), so a third failure is at the edge of the normal fix loop or
  past it. Stop patching: write down what the fixes had in common, and test
  that assumption directly before a fourth.

A failed gate's verdict can name `seen before? <file>`: the run's output has
the signal of a recipe in `.cursor/skills/verify-snacklist/recipes/`. A recipe
is one gate failure that came back across jobs and whose cause is known and
is not the change under test: its condition with a command that tells it from
a real failure, the mechanism, what to do and what not, the evidence. The
note is a question and the gate has failed either way. A cause that can be
removed gets removed instead, as the checks below did, so there are few
recipes. The README there says when to add one, and `scripts/verify-test.sh`
runs `verify.sh` on each recipe's example and counter-example.

A local run uses CI's toolchain or says what is missing:

- **Flutter.** `scripts/lib.sh` puts `FLUTTER_DIR` first on `PATH`, else
  `~/flutter-<CI's version>` when that exists, else `~/flutter`. Every gate
  that runs Flutter then checks the version against `FLUTTER_VERSION` in
  `ci.yml` and stops on another one (`require_ci_flutter`), naming
  `scripts/install-flutter.sh`: on Linux it downloads CI's version to
  `~/flutter-<version>` and leaves `~/flutter` alone. Another SDK still
  runs the app, but its gate is not the one CI runs: Flutter 3.47.8 on this
  tree resolved 4 other packages into `app/pubspec.lock` and reported a lint
  error that 3.50.0 does not (measured 2026-11-13). `scripts/fg` and
  `scripts/bootstrap.sh` still use `~/flutter`.
- **Migrations.** The lint gate's schema check compares the branch with
  `origin/main`, which every fetch in any worktree moves. A migration that
  main gained after the branch left it is not reported as deleted, unless
  the branch's own commits touched that file (a branch stacked on a PR that
  main took as another commit had it, so losing it is a deletion); the
  check's last line says how many the branch lacks. A branch's own
  migration still has to sort after main's newest.
- **The stack's schema.** CI starts a new stack for every run. A local stack
  keeps running, and `supabase start` applies nothing to a running one, so
  after a rebase it lacks the migrations main gained. The db gate resets the
  database of a running stack; a stopped one it starts. The e2e gate compares
  the versions the database has applied with the files in
  `supabase/migrations` (`stack_migrations_diff` in `scripts/lib.sh`) and
  resets it when they differ, naming the versions. A reset removes what
  `scripts/fg seed` or the verify-snacklist skill seeded: run
  `scripts/fg seed <scenario>` again, or the skill's
  `.cursor/skills/verify-snacklist/helpers/launch.sh --fresh`. A migration
  edited after it was applied keeps its version and is not noticed: run the
  db gate.

To add a check, add it to the gate script it belongs to. To add a gate, add
`scripts/gates/<name>.sh`, a `ci.yml` job of the same name that runs it, the
name in `ci-ok`'s `needs`, and the name in `GATES` (or `CI_ONLY`) in
`verify.sh`. `scripts/check-gates.sh`, part of the lint gate, fails when one
of these is missing or a check command is written into `ci.yml` or
`verify.sh` directly. It also fails when any job in any workflow has no
`timeout-minutes`.

In CI the e2e job runs as four shards (`--shard=1/4` to `--shard=4/4`), each
on its own runner with its own stack, because Playwright is the longest step
(Measurements, job 221, below). The matrix in `ci.yml` is the one place that
sets the count: the job passes Playwright `strategy.job-total`, and
`check-gates.sh` fails when it does not or when `e2e.yml`'s full suite runs
in another number of shards.
Each shard starts the Supabase stack in the background before installing
Flutter and Playwright; the gate's `supabase_up` (`scripts/lib.sh`) waits on
the same per-project lock and reuses the stack. CI pulls the Supabase images
from Docker Hub (`SUPABASE_INTERNAL_IMAGE_REGISTRY: docker.io`): the default
registry rate-limits runners and cost about 14 s of retries per run, and
ghcr.io refused every runner pull for hours on 2026-10-27.

The e2e gate takes the box-wide lock `/tmp/fg-e2e.lock`, held from stack start
through Playwright. A second run prints the last holder that recorded itself
in the lock file and waits. Anything else that runs Playwright on the box can
take the same lock with `flock /tmp/fg-e2e.lock <command>`. The kernel
releases the lock when the holder exits, however it exits.

A failed e2e test gets one retry only when the host paused the test runner
for 2 s or more during it (a VM stall on the shared box): the line
`[host-stall] <test>: the host paused the test runner for N s` names it, and
the retry shows as flaky. Any other failure fails its retry at once with
"not retried", so the gate still fails (`e2e/tests/fixtures.ts`, DECISIONS
job 15b).
That the app itself recovers from a pause is a test of its own (live-sync.spec,
the sleeping phone).

## Which gates a PR runs

The `changes` job (`scripts/ci-changes.sh`) reads the PR's changed files:

- Only `docs/` and Markdown changed (the verify skill's files under
  `.cursor/` and `.claude/` count as code): only `gitleaks`, `lint`,
  `site` and `site-agent` run. Both site gates always run because the guides
  are Markdown.
- `android` and `ios` run when `app/ios/`, `app/android/` or `app/pubspec.*`
  changed. They compile the app's Swift and Kotlin and the plugin registrant
  generated from pubspec. A Dart change in `app/lib/` is compiled by the
  flutter, web-prod and e2e gates already.
- `fastlane` runs when `app/fastlane/` or `app/Gemfile*` changed.
- `emails` runs when `emails/`, `supabase/templates/`, `supabase/config.toml`,
  `design/tokens/` or `site/public/email/` changed.
- A change to `ci.yml`, `.github/actions/`, `scripts/ci-changes.sh`,
  `scripts/lib.sh`, `scripts/gates/` or `scripts/e2e-summary.sh` runs
  everything, and so does a push to `main` or a manual run.
- `e2e.yml` and `scripts/ci-e2e.sh` (On-demand e2e) count like
  documentation: ci.yml doesn't run them, and the `lint` gate (actionlint,
  shellcheck, `check-gates.sh`) checks them.

A skipped job counts as passed for `ci-ok`. A failed or cancelled one fails
it.

## On-demand e2e (job 27)

`scripts/ci-e2e.sh` runs the Supabase + Playwright e2e, and by default the
db gate, on GitHub Actions for a pushed branch, without the rest of CI. It is
the way to run e2e where Docker is not allowed (the Mac runner), and it takes
that load off the box. It needs only `gh` (logged in), `git` and `jq`.

```bash
scripts/ci-e2e.sh                                  # full suite, 4 shards, db gate, fg sync smoke
scripts/ci-e2e.sh --spec tests/stores.spec.ts      # one spec: 1 shard, no sync smoke
scripts/ci-e2e.sh --spec '-g "drag"' --no-db       # by title, without the db gate
scripts/ci-e2e.sh --spec tests/list.spec.ts --download /tmp/pw   # also fetch report, traces, screenshots
scripts/ci-e2e.sh --ref job/42-foo --shards 2 --sync-smoke
```

- The branch must be pushed: the script refuses when your local branch and
  `origin/<ref>` are different commits, since the run checks out origin's.
  On a PR branch push with `scripts/push-pr.sh` first. Uncommitted changes
  are not part of the run, and the script says so.
- It dispatches `.github/workflows/e2e.yml` with a fresh `request_id`. The
  workflow puts that id into its run name (`run-name:`), so the script finds
  its own run, not one someone else started on the same branch a second
  earlier. Then it waits for the run and prints each job's result with its
  time, each shard's passed, failed and flaky counts with the failed titles,
  and the run URL. It exits 0 when the run passed and at least one test ran,
  1 when the run failed or was cancelled or no test ran, 2 on a usage
  problem. If a run fails, `gh run view <id> --log-failed` says why.
- Inputs of `e2e.yml` (also in the Actions tab, **Run workflow**): `spec`
  (Playwright arguments; empty is the full suite), `shards` (1 to 6; `auto`
  is 4 for the full suite, as in `ci.yml`, and 1 with a spec), `db` (default on: `scripts/gates/db.sh`
  in its own job), `sync_smoke` (`auto` runs the fg sync smoke test on shard
  1 for the full suite only). A sharded spec run passes an empty shard
  (`--pass-with-no-tests`); the script then checks that some test ran.
- One run per branch and spec: a second dispatch with the same spec cancels
  the first (`concurrency`). Different specs run side by side.
- Artifacts, per shard and attempt: `playwright-<shard>-attempt<n>` (HTML
  report, test results with traces, screenshots, sync evidence, and after a
  failed job `stack-logs/`, below) and
  `e2e-results-<shard>-attempt<n>` (only `playwright-results.json`, what the
  script reads). Each e2e job writes a summary of passed, failed and flaky
  tests per spec file onto the run page (`scripts/e2e-summary.sh`); ci.yml's
  e2e jobs write the same summary.
- It is not a required check and does not replace `ci-ok`: a PR still lands
  on ci.yml's run. Once a PR is open, every push runs the full ci.yml anyway;
  use ci-e2e.sh for single specs while iterating.

The backend comes up exactly as in ci.yml's e2e and db jobs and the local
gates. Both workflows' jobs use the same composite actions:
`.github/actions/e2e-setup` (Supabase CLI, ephemeral ports, the stack
started in the background, Flutter, Node and Playwright, Deno, ffmpeg),
`.github/actions/e2e-report` (the stack's logs on failure, the artifacts,
the job summary) and `.github/actions/db-setup`. Between them each job runs
its own `scripts/gates/<gate>.sh`, which calls `supabase_up` with the repo's
migrations and seed, the job-18 fixtures and `e2e/playwright.config.ts`.

When an e2e job fails, in ci.yml or e2e.yml, its `playwright-<shard>` artifact
also holds `stack-logs/<container>.log`: the log of every container of the
stack with UTC timestamps, at most the newest 50 MB of each
(`scripts/ci/stack-logs.sh`; the job log prints the end of the edge
runtime's). A test's start time in the Playwright report finds the lines of
that moment: Kong writes one per request when it answers it, with the status
(499 when the client gave up first), and the edge runtime and auth log their
requests too. Realtime logs a tenant's start and errors, not each socket or
join: its sockets are the `/realtime/v1/websocket` lines in Kong's log, each
written when the socket closes. The database logs errors and the migrations'
DDL statements, not each query. Read them before a rerun: the rerun's stack
is another one.

The pins (`FLUTTER_VERSION`, `SUPABASE_CLI_VERSION`,
`SUPABASE_INTERNAL_IMAGE_REGISTRY`) are written in both workflows, because a
composite action can't read a workflow's `env`. `scripts/check-gates.sh` fails
when the pins differ, when the two `e2e` or `db` jobs use different actions,
versions or action inputs, or when e2e.yml's job no longer runs its gate script. The
gate's `FG_SYNC_SMOKE=1|0` overrides its sync smoke rule (`sync_smoke`).

`gh workflow run` finds a workflow by file name only once GitHub has
registered it, and a `workflow_dispatch` workflow is registered when it
reaches the default branch. To try changes to e2e.yml on a branch before it
is on main, add a temporary `push:` trigger limited to that branch. One
push registers it, and from then on `scripts/ci-e2e.sh --ref <branch>` runs
the branch's own e2e.yml. Remove the trigger before landing (job 27 did
this, DECISIONS job 27).

### Browsers and timings (job 28)

The e2e run has three Playwright projects: `chromium` (every spec but one),
`iphone` (WebKit as an iPhone 15, `tests/iphone.spec.ts`: the add field's tap
focus) and `webkit` (the timings). The web build is `--wasm`, so Chromium runs
the wasm app; `tests/wasm-boot.spec.ts` also boots the JS fallback. WebKit
runs on GitHub Actions only: it does not start on the Mac runner.

The timings (`tests/perf.spec.ts`, 4-5 min) run only when named:

```bash
scripts/ci-e2e.sh --no-db --spec tests/perf.spec.ts
```

Each build measured prints a `PERF {...}` line, and the job summary shows
them as a table: the time from navigation to the drawn list, and the frame
intervals while scrolling a 200-item list (DECISIONS job 28, 7).

## Landing a PR: one CI run

1. Push the branch once (`git push -u origin HEAD`), then `gh pr create`.
2. From then on, push with `scripts/push-pr.sh`. It rebases the branch onto
   `origin/main` and squashes it into the one commit `main` takes: subject
   `<PR title> (#n)`, the noreply author, the trailers. Then it pushes with
   `--force-with-lease`. It refuses `main`.
3. `scripts/merge-pr.sh --wait <n>` waits for `ci-ok` on that commit and
   rebase-merges it. No second squash, no second push, no second CI run.
   `--dry-run` runs every check and stops before the merge. `--wait` gives
   up after `MERGE_WAIT_MINUTES` (default 30) and exits 1, so a stuck run
   can't hold the merge lock. The value is a whole number of minutes, such as
   `MERGE_WAIT_MINUTES=10`. Anything else (`0.5`, `abc`) stops merge-pr.sh
   with exit 2 before it does anything.
   The default is too short for one run in five with the ios job: 23 of 110
   such runs took over 30 minutes from their start to `ci-ok`, one over 45
   (green first attempts, 7 to 13 November; job 219's baseline). A land that
   gives up starts again with a new turn at the merge lock and, when main
   moved meanwhile, a new push and a new CI run. The ios job runs when a PR
   changes the native projects, the pubspec, `scripts/gates/`,
   `scripts/lib.sh` or the CI definition (the list is
   `scripts/ci-changes.sh`): land those with `MERGE_WAIT_MINUTES=45`.
   The wait sleeps 20 s between its looks at `ci-ok`. A signal that ends
   only that sleep (a kill by name elsewhere on the machine, job 219) is
   logged and the wait goes on. The 21st such sleep of one wait stops it
   with exit 1, a sleep that fails without a signal with the sleep's status.

The commit message is the PR as GitHub shows it: the title with ` (#n)` as
the subject and the PR description as the body. Messages of the branch's
working commits are dropped. After `gh pr edit <n> --body-file <file>`, run
`scripts/push-pr.sh` again: it re-squashes when the description changed, so
the commit on `main` carries the current one. merge-pr.sh refuses (exit 1)
a head whose message is not the current description, so a description
edited after the last push can't land stale. Trailers follow the body:

- `Co-authored-by` lines from the description and from the branch's commits,
  once each, in that order.
- `Co-authored-by: $MODEL_CO_AUTHOR` when that variable is set, as
  `MODEL_CO_AUTHOR="Claude Opus 5.5 <noreply@anthropic.com>"`. When unset,
  nothing is added. A value that is not `Name <email>` stops the push.
- Peter's trailer, always last.

The description needs a `## Changelog` section ([`CHANGELOG.md`](CHANGELOG.md)).
push-pr.sh checks it before it squashes. When the section is missing and the
PR changes nothing in the app builds, `supabase/` or `alexa/`, it adds
`## Changelog` + `none` to the PR description. When the section is missing
and one of those changes, or the
section is invalid, it stops and prints the format. The `changelog` gate
checks the same section on the PR head in CI. On a pull request, CI checks out
the merge commit: `HEAD^1` is the base and `HEAD^2` the PR head. The gate
reads `HEAD^2`'s message. A head pushed with plain `git push` has no section
in its message, so the gate reads the PR description from the event instead.
The job is skipped for Dependabot, by actor or by a `dependabot/` head branch,
so its PRs stay green without a note. It is also skipped on pushes to `main`.
A skipped job does not fail `ci-ok`.

`scripts/landing-test.sh` (run by the lint gate) covers these rules against
a scratch remote and a fake `gh`. The gate's own cases (scratch merge
commits) are in `scripts/release/test.sh`.

If `main` moved after your last push, the commit is no longer on top of
`main`. merge-pr.sh then stops and says so. Run `scripts/push-pr.sh` again
(one rebase, one push, one CI run), then merge-pr.sh.

merge-pr.sh may run right after push-pr.sh, in one command. It takes the
head from the branch and waits until GitHub's record of the PR names it (a
look every 5 s, up to 2 min): for some seconds after a push the record still
names the head before it, and the checks and the merge go by the record.
No `sleep` between the two scripts is needed (job 218).

That rebase does not stop when the only overlap is a section both sides
appended to one of the logs every job writes (`docs/DECISIONS.md`,
`docs/NEEDS_LEAD.md`, `docs/NEEDS_PETER.md`, `DONE_SUMMARY.md`, listed in
`.gitattributes`). The merge driver `scripts/merge-append-log.sh` keeps both
sections, main's first; the rebase stores its command in the clone's git
config (`install_merge_driver` in `scripts/lib.sh`), since git reads a
driver's command only from there. It leaves a conflict as before when a side
edits existing lines, when an entry is there twice (a section of the PR that
main already holds), or when the PR's text continues an older section next to
a section main added. In those cases, and where the script is missing or
fails, the stored command merges with `git merge-file`, as git does without a
driver. `scripts/merge-append-log-test.sh` (lint gate) covers it. GitHub runs no
merge drivers, so such a PR still shows as conflicting until the next
`scripts/push-pr.sh`.

A PR pushed with plain `git push` still lands the old way: merge-pr.sh
squashes it, force-pushes, exits 2, and merges when rerun after `ci-ok`. That
costs a second CI run. The pre-push hook (`.githooks/pre-push`) warns when a
PR branch goes up as several commits. Every worktree runs it, because
`core.hooksPath=.githooks` is in the shared repository config and resolves
against each worktree's root.

## Tool downloads

A CDN answering 504 once used to fail a job: the actionlint download in lint
(issue #246) and setup-deno's binary in functions. Job 113 caches the pinned
tools and retries what is still downloaded.

- `scripts/ci/download.sh <url> <file>` is the one place for retry flags:
  curl with 7 retries on any error and exponential backoff, up to 5 minutes.
  An attempt that stalls (under 1 KB/s for 30 s) ends and is retried. It
  writes to a file, never a pipe, because a retried transfer into a pipe
  repeats bytes. `scripts/ci/download-test.sh` (lint gate) proves the
  retries against a local server that answers 404, 504 or stalls, and the
  Deno resolve and checksum checks.
- gitleaks, actionlint, ast-grep and squawk: `scripts/ci/install-tools.sh`
  installs the versions pinned in `ci.yml`'s env into
  `~/.cache/fg-ci-tools/bin`, which `actions/cache` keeps per tool version.
  A tool that already reports its pinned version is not downloaded again.
- Deno: every workflow uses `.github/actions/deno` instead of
  `denoland/setup-deno`. `scripts/ci/deno-toolcache.sh` picks the version
  setup-deno would pick: the exact version in `.dvmrc` in every CI job, without
  the network, and for `v2.x` (only `supabase-deploy.yml` still asks for it)
  the newest 2.x (its `versions.json` fetch retried by `download.sh`),
  restores it from the Actions cache (or downloads it with
  retries and checks it against the release's `.sha256sum`) and puts it on
  PATH. Deno's problem matcher (error annotations) is not registered;
  failures still fail the job.
  - When resolve fails (`versions.json` unreachable after the retries, or a
    range other than `vN.x`), the step prints a `::warning::` and falls back
    to `denoland/setup-deno`, which retries its download only 3 times and
    `versions.json` for about 8 s.
  - `supabase-deploy.yml` and `price-drift.yml` hold secrets and pass
    `cache: false`: any job that runs on `main` can save a cache entry, so
    those jobs run only a freshly downloaded, checksum-verified binary.
- npm: `ci.yml` and `e2e.yml` set `NPM_CONFIG_FETCH_RETRIES` and its
  timeouts, which cover `npm ci` and the Supabase CLI package install in
  `supabase/setup-cli`. The action's own `bun install` is not covered.
- apt: `scripts/backup/install-tools.sh` and the ffmpeg step pass
  `-o Acquire::Retries=5`.
- Playwright browsers are not cached: `playwright install` already retries 5
  times across 3 CDN mirrors, and the repository's Actions cache already sits
  at its 10 GB limit, so three browsers would evict other entries.
- Flutter comes from `subosito/flutter-action`'s own cache (`cache: true`) in
  the jobs without secrets.
- A job that reads a secret, names an environment or whose token may write
  restores no Actions cache (lint rule `no-cache-in-trusted-job`): any job
  that runs on `main` can save an entry, which that job would unpack and run.
  One exception is on the allow-list: `supabase-deploy.yml`'s `deploy` job
  runs `supabase/setup-cli`, which restores its `bun` binary from the cache
  and has no input to turn that off. `release.yml` downloads Flutter on every
  run, and it and `certificates.yml` install the gems from `Gemfile.lock` in
  a step. The setup steps take about a minute longer per store job (one run
  each in job 220: flutter-action 79 s instead of 54 s on macOS and 64 s
  instead of 22 s on Linux, `bundle install` 42 s and 30 s instead of a
  restore of about 5 s). What the missing pub cache adds to the later steps
  was not measured.
- Not covered: the Supabase CLI's Docker images, the biggest download left,
  which `supabase start` pulls in db and e2e without a retry of ours. They
  come from Docker Hub (`SUPABASE_INTERNAL_IMAGE_REGISTRY`, DECISIONS job
  15b).

## Dependencies

`.github/dependabot.yml` opens grouped weekly PRs for GitHub Actions, pub
(`app/`) and npm (`e2e/`), labelled `dependencies` and `agent-ready`. Major
updates come in their own group. Renovate would also handle the Flutter,
Supabase CLI and gitleaks versions pinned in `ci.yml`, but it needs the
Renovate app installed on Peter's account.

## Measuring

`scripts/ci-timings.sh` prints per-job end times of recent successful runs,
counted from the run's start, and their median and range. With
`--steps <job>` it adds the median step durations of one job (`e2e` takes
every shard's steps, `e2e (1)` one shard's). Use it before and after a CI
change.
`scripts/ci-ios-phases.sh <run-id>...` splits each ios job of those runs
(every attempt) into the phases of `scripts/gates/ios.sh`: config, build,
checks, boot, tests (DECISIONS, Job 118).

```bash
scripts/ci-timings.sh --limit 10 --steps e2e
scripts/ci-timings.sh --branch job/11-ci-flow --since 2026-10-24T18:00:00Z
```

## Measurements (job 11, October 2026)

Wall clock from the run's start to `ci-ok`, full runs (every gate), first
attempt only. Medians with the range over n runs, from `scripts/ci-timings.sh`.

| CI version | n | `ci-ok` | Limiter |
| --- | --- | --- | --- |
| Before: one job per tool group, sequential e2e setup | 15 | 6:10 (5:17-7:05) | e2e, ends at 6:05 |
| Gates, background stack start, ghcr.io images, Gradle/NDK cache | 5 | 5:44 (5:20-6:13) | e2e, ends at 5:38 |
| Plus web build during the stack start (dropped, see DECISIONS 11.11) | 5 | 5:59 (4:52-6:10) | e2e; Playwright on slow runners in 4 of 5 |
| Plus e2e in two shards | 5 | 4:38 (4:12-9:55) | e2e/ios; the 9:55 is a 6:37 apt download |
| Plus apt deps only when Chromium can't launch, no browser cache | 5 | 5:07 (4:26-5:30) | ios, ends at 5:03 (3:34-5:24) |
| Docs-only change | 1 | 0:27 | lint |

What a PR waits for now:

- A change touching `app/ios/`, `app/android/` or `app/pubspec.*` waits for
  the ios job: 9-22 min since job 118 (one build, median 13.4, n=6; median
  20.0 and up to 41 when the gate built the app twice, n=19). The rest is
  the runner: a fresh simulator's first boot takes 2-11 min.
- Any other code change waits for the slower e2e shard. Derived, not
  measured as `ci-ok`: 4:26 median (4:18-4:40) is the end time of `e2e (2)`
  in the 5 full runs above. One real filtered run so far: Dependabot's npm
  PR (#33), `ci-ok` at 3:58.
- A docs-only change waits about 30 s.
- A change to the CI definition runs everything, like a push to `main`.
  After a cache key changes (a Flutter bump, a new NDK), the first run on
  `main` refills the Gradle and NDK cache. The first `main` run after this
  job's merge took 6:49, android 6:43 against ~2:45 once cached. Branch runs
  read `main`'s cache, so they pay this until that run has finished.

Merging costs one CI run instead of two: before, merge-pr.sh squashed and
pushed, and the merge waited for a second full run on identical content.

Playwright itself is the noise: a full run takes ~2.9 m or ~3.8 m depending
on the runner, and on a slow runner nearly every test is 1.3-1.5× slower.
