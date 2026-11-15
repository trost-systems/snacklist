# Database backups

The hosted Supabase project `jdwqrallbpdbshrdhenk` is on the free plan,
which has no backups of its own. **Backup** (`.github/workflows/backup.yml`)
makes one every night, encrypted, and keeps it for 90 days. Decisions and
sources are in [`DECISIONS.md`](DECISIONS.md), job 13b.

## What is backed up, and when

- Every night at 02:30 UTC, and on demand (Actions, **Backup**, **Run
  workflow**, or `gh workflow run backup.yml -R trost-systems/family-groceries --ref main`).
- The **data** of every table in schema `public` (households, members,
  items, categories, stores and layouts, item history, invites, tokens,
  the classifier's memories and dictionary) plus `auth.users` and
  `auth.identities`, so everyone keeps their account, password and Google
  or Apple sign-in, and every row still points at its user.
- Not the schema. Tables, functions, policies and triggers come from
  `supabase/migrations/`, so a restore applies the migrations first.

`scripts/backup/dump.sh` makes the backup. It runs `pg_dump 17 --data-only`
through the session pooler (`aws-1-eu-central-1.pooler.supabase.com:5432`,
user `postgres.jdwqrallbpdbshrdhenk`, TLS required) with the password from
the secret `SUPABASE_DB_PASSWORD` (a repository secret until it moves into
the environment `ops`, which the job names: NEEDS_PETER, Job 220), and pipes
the output straight
into `age`, encrypted to the public key in `supabase/backup/recipient.txt`.
Nothing unencrypted reaches the disk or the log. The script deletes the
file and fails if `pg_dump` fails, if the file doesn't start with
`age-encryption.org/v1`, or if it is smaller than 16 KiB.

## Where the backups are

Actions, **Backup**, a run, **Artifacts**: `db-backup-<UTC date>-<run id>`,
holding `db-backup-<UTC date>-<run id>.sql.age`. Each artifact expires after
90 days, the maximum for a public repository, so about 90 nightly copies
exist. The repository is public, so anyone can download them. Without the
private key they are unreadable.

```bash
gh run list -R trost-systems/family-groceries --workflow backup.yml --status success --limit 5
gh run download <run id> -R trost-systems/family-groceries -D ~/fg-restore
```

## Failures

A failed run opens the issue "Database backup failed", naming the step
that failed, or comments on it if it is already open. The next green run
closes it. Watch the repository's issues (Watch, Custom, Issues), as for
the keepalive ([`DEPLOY.md`](DEPLOY.md)).

| Failed step | Meaning | What to do |
| --- | --- | --- |
| Password secret | `SUPABASE_DB_PASSWORD` is missing or empty | Set it: `gh secret set SUPABASE_DB_PASSWORD -R trost-systems/snacklist` (the value from Project Settings, Database); with `--env ops` once the secret lives in the environment (NEEDS_PETER, Job 220) |
| Dump and encrypt, "password authentication failed" | The database password changed | Update the secret as above |
| Dump and encrypt, "Tenant or user not found" or a timeout | The project is paused, or the pooler host changed | Resume the project ([`DEPLOY.md`](DEPLOY.md)); compare the host with Connect, Session pooler in the dashboard |
| pg_dump and age | apt or the PGDG repository was down | Rerun the workflow |

GitHub disables the schedule after 60 days without repository activity.
Every push to `main` re-enables it (CI job `keepalive-schedule`). By hand:
`gh workflow enable backup.yml -R trost-systems/family-groceries`.

## The key

- Public key (recipient): `supabase/backup/recipient.txt`, in the repo.
- Private key: in Peter's password manager and on the build box at
  `~/groceries-ops/backup-age-key.txt`. It never goes into the repo, CI or
  a secret.
- **If the private key is lost, every backup is unreadable.** Nobody can
  recover it. Keep two copies in separate places.

### Rotate the key

1. On your own computer: `age-keygen -o backup-age-key-<year>.txt`. It
   prints the new public key (`age1...`).
2. Store the new private key next to the old one in the password manager.
3. Replace the line in `supabase/backup/recipient.txt` with the new public
   key and land it like any PR. From the next night on, backups use it.
4. Keep the old private key for 90 days: older artifacts still need it.
   Then delete it.

If the old private key leaked, also delete the old artifacts:
`gh api repos/trost-systems/family-groceries/actions/artifacts --paginate --jq '.artifacts[] | select(.name | startswith("db-backup-")) | .id'`,
then `gh api -X DELETE repos/trost-systems/family-groceries/actions/artifacts/<id>` for each.

## Restore

A restore **replaces** all data in the target: `scripts/backup/restore.sh`
empties every `public` table and `auth.users` (with everything that points
at users, see below) and loads the backup, in one transaction. On any error
it rolls back and nothing changes. The CI restore drill proves these exact
steps on every run of the `db` gate (`scripts/backup/drill.sh`).

You need: `age`, `psql` 17 (`scripts/backup/install-tools.sh` installs
both on Debian or Ubuntu; on a Mac, `brew install age postgresql@17` and
`export PATH="$(brew --prefix postgresql@17)/bin:$PATH"`), the
Supabase CLI, a checkout of this repository at the `main` commit from the
backup's date or later, and the private key.

### 1. Pick the target

- **The same project** (data was lost or broken by a bug): its schema is
  already current. Continue with step 3.
- **A fresh Supabase project** (the old one is gone): create it, then apply
  the migrations:

  ```bash
  supabase link --project-ref <new ref>
  supabase db push
  ```

  Then redo the rest of the setup on the new ref: `SUPABASE_PROJECT_REF`
  variable, edge functions and their secrets, auth URLs and providers
  ([`DEPLOY.md`](DEPLOY.md), [`NEEDS_PETER.md`](NEEDS_PETER.md)).
- **The local stack** (to look at a backup): `supabase start`, then
  `supabase db reset` (migrations only).

Migrations first, data second, always: the backup holds no schema.

### 2. Stop writes

On the same project, writes during the restore are lost. Tell Lea, and
consider pausing the MCP and Siri clients. Nothing else is needed: the
restore is one transaction.

### 3. Connect

Hosted (from a machine that reaches Postgres; the build box doesn't, its
DNS points database hosts at a local proxy):

```bash
export PGHOST=aws-1-eu-central-1.pooler.supabase.com PGPORT=5432 PGDATABASE=postgres \
  PGUSER=postgres.<project ref> PGSSLMODE=require
read -rs PGPASSWORD && export PGPASSWORD    # Project Settings, Database
```

Local stack:

```bash
export PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
```

### 4. Load

```bash
age -d -i backup-age-key.txt ~/fg-restore/db-backup-<date>-<run id>/db-backup-<date>-<run id>.sql.age \
  | scripts/backup/restore.sh
```

`restore.sh` runs, in one psql session and one transaction:

```bash
psql --single-transaction -v ON_ERROR_STOP=1 \
  -c 'SET session_replication_role = replica' \
  -c 'TRUNCATE auth.users, auth.identities, <every public table> CASCADE' \
  -f -
```

`session_replication_role = replica` keeps every trigger from firing while
the rows go in, as Supabase documents for restores. Otherwise
`items_before_write` would overwrite `bought_by` with the restoring user,
`items_log_event` would add history rows, `on_auth_user_created` would add
profiles twice. It lasts only for this session. The `TRUNCATE` removes the
rows the migrations seed (`classifier_terms`) and whatever the target held.
psql prints one `NOTICE: truncate cascades to table ...` per auth table that
points at users.

### 5. Check

```bash
psql -c 'select count(*) from auth.users' -c 'select count(*) from public.items'
```

Sign in to the app. Everyone signs in again (see below).

## What a restore does not bring back

- **Sessions and refresh tokens**: everyone signs in again. The truncate
  also clears MFA factors, one-time tokens (open magic links, password
  resets) and WebAuthn credentials. None are in the backup.
- **OAuth consents and authorizations** of the MCP server: MCP clients
  (Claude) connect again. Personal access tokens are in the backup and keep
  working.
- **Storage objects** (feedback screenshots since job 267: restored notes keep the name of an
  image that is gone) and anything else outside
  `public`, `auth.users` and `auth.identities`, such as the auth audit log.
- **Project settings**: edge function secrets, auth URLs and providers,
  the database password, Vercel's environment variables. They live in the
  dashboard, GitHub and Vercel, not in Postgres.
- **Writes after the backup**: up to one day of changes.

A backup restores onto the schema of its own date or a newer one, because
migrations only add (the squawk rules in `scripts/lint.sh`). If a later
migration added a column with a default, restored rows get that default.
A newer Supabase Auth version that dropped a column of `auth.users` would
make the load fail and roll back. Then restore onto a local stack of the
backup's date and copy the rows across.
