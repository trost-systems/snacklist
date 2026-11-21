#!/usr/bin/env bash
# Dumps the data of every table in schema public plus auth.users and auth.identities, encrypted
# for one age recipient. The schema is not in the dump: it comes from the migrations (BACKUP.md).
# Usage: scripts/backup/dump.sh <recipient file> <output .sql.age>
# Connection from the libpq environment: PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD PGSSLMODE.
# The plaintext only ever flows through the pipe into age; nothing unencrypted reaches the disk
# or the log.
set -euo pipefail
# Ubuntu's /usr/bin/pg_dump follows the installed server (16 on runners), so 17's own binaries win.
PATH="/usr/lib/postgresql/17/bin:$PATH"

[[ $# == 2 ]] || { echo "usage: $0 <recipient file> <output .sql.age>" >&2; exit 2; }
recipient_file="$1" out="$2"
recipient="$(tr -d '[:space:]' <"$recipient_file")"
[[ $recipient =~ ^age1[a-z0-9]{58}$ ]] || { echo "$recipient_file does not hold one age recipient (age1...)" >&2; exit 2; }

# Anything that fails from here on leaves no file behind: age writes a valid header even when
# pg_dump dies mid-stream, so a partial dump would otherwise look like a backup.
trap 'rm -f "$out"' ERR

# -t patterns, not --schema: pg_dump ignores -n when any -t is given (DECISIONS 13b.1).
# --strict-names fails the dump if a pattern stops matching, e.g. a renamed auth table; it does
# not cover --exclude-table-data, so drill.sh proves each excluded table comes back empty.
# content_report_app_senders: user id and time of app reports, kept a day at most, so never in a
# 90-day backup (Legal N-284).
pg_dump --data-only --quote-all-identifiers --strict-names \
  --table='public.*' --table=auth.users --table=auth.identities \
  --exclude-table-data=public.content_report_app_senders \
  | age --encrypt --recipient "$recipient" --output "$out"

min_bytes=16384
size="$(stat -c %s "$out")"
if [[ "$(head -c 21 "$out")" != "age-encryption.org/v1" ]]; then
  echo "$out does not start with the age header" >&2
  rm -f "$out"
  exit 1
fi
if ((size < min_bytes)); then
  echo "$out has $size bytes, less than $min_bytes: the dump is empty or cut off" >&2
  rm -f "$out"
  exit 1
fi
echo "encrypted dump $out: $size bytes, age header present"
