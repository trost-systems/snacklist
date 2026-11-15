# Hosted backend

The hosted Supabase project stays reachable for the app, MCP clients, Siri and the Alexa skill. Every deploy from `main` ends with a smoke test of the edge functions, a daily keepalive keeps the free project from pausing, a dispatch with an earlier `main` commit rolls the edge functions back, and a nightly encrypted backup keeps 90 days of data. The runbooks are `docs/DEPLOY.md` and `docs/BACKUP.md`.

## Sub-features

- `backend-health` answers `GET /functions/v1/health` with 200 and `{"ok": true, "service": "family-groceries", "database": true}` after one read from Postgres, and 503 with `"database": false` when Postgres doesn't answer within 5 s.
- `backend-smoke` runs `scripts/smoke-remote.sh` after every deploy: health, 401 with `WWW-Authenticate` from `voice` for a bad token, and `scripts/mcp-smoke.sh` on the `mcp` function (401 challenge, a bad token, its Protected Resource Metadata on the same host, the authorization server's metadata, the token endpoint from `<endpoint>/.well-known/openid-configuration` for clients that skip the hint; `initialize` + `tools/list` only with `MCP_SMOKE_TOKEN`), 400 `missing_signature` from `alexa`, and `purchases` (status, test events answering 404 on a hosted project, the webhook refusing a bad secret, claim refusing a request without a session), and `api` without a key (404 `not_found` while the public API is off, 401 `missing_token` once it is on; `SMOKE_PUBLIC_API=1` adds the check for the day it is switched on, `docs/DEPLOY.md` "Smoke test").
- `backend-mcp-domain` serves the same `mcp` function at `https://mcp.snacklist.app` through the Vercel project `hummlist-mcp` (`mcp-proxy/vercel.json`, rewrites only). Through it the function advertises `https://mcp.snacklist.app` as the resource and its root `/.well-known/oauth-protected-resource` as the metadata; requests straight to supabase.co keep the supabase.co values.
- `backend-keepalive` reads through `health` once a day (workflow Keepalive), re-enables its own schedule (and every push to `main` does too), and opens the issue "Keepalive failed" on failure (closed by the next green run).
- `backend-backup` dumps the data of `public` plus `auth.users` and `auth.identities` every night at 02:30 UTC (workflow Backup), encrypted with age to `supabase/backup/recipient.txt`, as the 90-day artifact `db-backup-<UTC date>-<run id>`; a failed run opens the issue "Database backup failed" (closed by the next green run), and every push to `main` re-enables its schedule. The db gate's restore drill (`scripts/backup/drill.sh`) proves dump, decrypt and restore round-trip on the local stack.
- `backend-rollback` redeploys only the edge functions of an earlier `main` commit (workflow Supabase deploy, input `ref`) and smoke-tests them with that commit's script.

## How to get to it (user POV)

- An MCP client or the Siri Shortcut calls the hosted functions at `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/`. An MCP client can use `https://mcp.snacklist.app` instead.
- A maintainer opens Actions › Keepalive, Actions › Backup or Actions › Supabase deploy › Run workflow.

## Driving it with fg

Preconditions:

- No `fg` stack is needed for the hosted checks. They need `curl`, `jq` and, for the workflows, `gh` signed in with access to `trost-systems/family-groceries`. The restore drill needs `age` and `pg_dump` 17 (`scripts/backup/install-tools.sh`).

- **Hosted smoke test.** Run `scripts/smoke-remote.sh` from the repo root. Twenty lines start with `PASS` and two with `SKIP` (`initialize + tools/list`, once per protocol version), the last line is `all checks passed against https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1`, and the exit code is 0.
- **A wrong project fails.** Run `scripts/smoke-remote.sh https://jdwqrallbpdbshrdhenx.supabase.co`. Twenty-two lines start with `FAIL` (the two mcp-smoke wrapper lines included), and the exit code is 1.
- **Public MCP URL.** Run `scripts/mcp-smoke.sh https://mcp.snacklist.app`. Five lines start with `PASS`, one with `SKIP`, the last line is `all checks passed against https://mcp.snacklist.app`, and the exit code is 0. The `PASS` lines name `https://mcp.snacklist.app/.well-known/oauth-protected-resource` and `resource https://mcp.snacklist.app`. With a token from Zugänge in `MCP_SMOKE_TOKEN`, the sixth check passes too and lists the tools.
- **Proxy locally.** No Vercel needed: put `MCP_PUBLIC_URL=http://localhost:<port>` in `supabase/functions/.env` (gitignored), restart the stack, serve a reverse proxy on that port that applies the routes `npx vercel build` compiles from `mcp-proxy/` (`.vercel/output/config.json`, destination host swapped for the local API URL), and run `scripts/mcp-smoke.sh http://localhost:<port>`. Use `localhost`, not `127.0.0.1`: the local gateway sets `x-forwarded-host: 127.0.0.1` on every request, which would make direct requests look proxied too.
- **Local stack.** After `fg up`, `fg fn call health --as anon` returns 200, and `scripts/smoke-remote.sh http://127.0.0.1:${FG_PORT_PREFIX}21` passes every check but one: "FAIL purchases test events: want 404; got HTTP …", because a local stack serves `/purchases/test/event` (RevenueCat's stand-in) on purpose (`features/purchases.md`). Stop the database container (`docker stop "supabase_db_$(fg env | jq -r .projectId)"`), then `curl -s -w ' %{http_code}' http://127.0.0.1:${FG_PORT_PREFIX}21/functions/v1/health` prints `{"ok":false,...,"database":false} 503` after about 5 s. Start the container again and repeat `fg doctor` until it is `"ok": true`: realtime restarts with the database and reports `container starting` for about 30 s.
- **Read-only history.** `gh run list -R trost-systems/family-groceries -w keepalive.yml -L 3` (and `-w backup.yml`, `-w supabase-deploy.yml`) shows the latest runs, and `gh run view <id> --log` their steps. Use it when a dispatch is not warranted.
- **Keepalive.** Run `gh workflow run keepalive.yml -R trost-systems/family-groceries`, then `gh run watch` on the new run. It ends green, with "Postgres answered through ..." in the first step.
- **Backup.** Run `gh workflow run backup.yml -R trost-systems/family-groceries --ref main`, then `gh run watch` on the new run. It ends green and lists one artifact `db-backup-<date>-<run id>`. `gh run download <run id> -R trost-systems/family-groceries -D <tmp dir>`, then `head -c 21 <tmp dir>/*/*.sql.age` prints `age-encryption.org/v1`. Never decrypt the real backup; delete the download.
- **Restore drill.** Run `scripts/backup/drill.sh` from the repo root (it uses the checkout's own stack from `supabase/config.toml`, not an `fg` instance). The last lines read `drill: PASS: <N> tables identical after dump, decrypt and restore:` and one line per table with its row count and md5. The count is every table in `public` plus `auth.users` and `auth.identities`, so it grows with each new table (35 by the migrations on main aa339cc, 2026-11-02; not run). It resets the checkout's local database twice.
- **Rollback.** Run `gh workflow run supabase-deploy.yml -R trost-systems/family-groceries --ref main -f ref=<sha on main>`. The run shows the notice "Rollback: redeploying the edge functions of <sha>", skips Migrations, and Smoke test passes. A SHA not on `main`, or one older than `scripts/smoke-remote.sh`, fails in "Check out the rollback commit" before anything deploys. So does a `ref` that is not a commit SHA, and a dispatch from a branch other than `main` fails earlier, in "Check deploy credentials".

## Gotchas

- A rollback or keepalive dispatch changes or touches production. The smoke test itself is read-only.
- A rollback lasts until the next push to `main` that touches `supabase/**`, `scripts/smoke-remote.sh`, `scripts/mcp-smoke.sh` or the deploy workflow deploys `main` again.
- GitHub starts scheduled runs hours late. On 2026-10-26 and 2026-10-27 the 02:30 UTC backup started at 08:01 and 08:15 UTC, and the 05:23 UTC keepalive at 11:16 and 10:42 UTC. Check `gh run list` for the day's `schedule` run in the afternoon (UTC) before calling it missing.
- `workflow_dispatch` runs only workflows that are on `main`, so a new workflow can't be dispatched from its PR branch.
