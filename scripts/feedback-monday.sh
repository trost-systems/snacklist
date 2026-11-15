#!/usr/bin/env bash
# Proves Peter's Monday queries (docs/FEEDBACK.md) on the local stack, run by the db gate: seeds
# fake notes around last week's Berlin boundaries, runs the three SQL blocks exactly as the doc
# has them, prints their output (for the PR) and checks it. Removes its rows again.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

stack_running || supabase_up
db_url="$(supabase status -o env 2>/dev/null | sed -n 's/^DB_URL="\(.*\)"$/\1/p')"
export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres PGSSLMODE=disable
PGPORT="$(sed -n 's|^postgresql://[^@]*@[^:]*:\([0-9]*\)/.*$|\1|p' <<<"$db_url")"
export PGPORT

fail() { echo "feedback-monday: FAIL: $*" >&2; exit 1; }
sql() { psql --no-psqlrc -X -v ON_ERROR_STOP=1 "$@"; }

# The SQL between <!-- monday-sql:<name> --> and <!-- /monday-sql --> in docs/FEEDBACK.md.
block() {
  local text
  text="$(awk -v name="$1" '
    $0 == "<!-- monday-sql:" name " -->" { inside = 1; next }
    inside && $0 == "<!-- /monday-sql -->" { exit }
    inside && !/^```/ { print }' docs/FEEDBACK.md)"
  [[ -n $text ]] || fail "no monday-sql:$1 block in docs/FEEDBACK.md"
  printf '%s\n' "$text"
}

users="'00000000-0000-4000-8000-00000000fe01', '00000000-0000-4000-8000-00000000fe02', '00000000-0000-4000-8000-00000000fe03'"
cleanup() {
  sql -q -c "delete from public.households where created_by in ($users);
             delete from auth.users where id in ($users);" >/dev/null || true
}
trap cleanup EXIT
cleanup

log "seed fake notes"
sql -q >/dev/null <<'SQL'
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000fe01', 'max.beta@snacklist-tester.de'),
  ('00000000-0000-4000-8000-00000000fe02', 'barbie.beta@snacklist-tester.de'),
  ('00000000-0000-4000-8000-00000000fe03', 'peter@fg.test');
insert into public.households (id, name, created_by) values
  ('00000000-0000-4000-8000-00000000fa01', 'Max und Barbie', '00000000-0000-4000-8000-00000000fe01'),
  ('00000000-0000-4000-8000-00000000fa03', 'Familie Test', '00000000-0000-4000-8000-00000000fe03');
insert into public.household_members (household_id, user_id, role) values
  ('00000000-0000-4000-8000-00000000fa01', '00000000-0000-4000-8000-00000000fe01', 'owner'),
  ('00000000-0000-4000-8000-00000000fa01', '00000000-0000-4000-8000-00000000fe02', 'member'),
  ('00000000-0000-4000-8000-00000000fa03', '00000000-0000-4000-8000-00000000fe03', 'owner');
-- When, as Berlin wall time from last week's Monday 00:00; the trigger sets created_at to now().
create temp table seed (id uuid, user_id uuid, at interval, message text, category text, contact_ok boolean,
  platform text, os_version text, locale text, screen text);
insert into seed values
  ('00000000-0000-4000-8000-0000000fb001', '00000000-0000-4000-8000-00000000fe01', '0 hours',
   'Beim Abhaken springt die Liste nach oben.', null, false, 'web', 'Chrome on Android', 'de', 'account'),
  ('00000000-0000-4000-8000-0000000fb002', '00000000-0000-4000-8000-00000000fe01', '1 day 08:15',
   'Die App stürzt ab, wenn ich offline etwas lösche.', 'bug', true, 'android', 'Android 14 (SDK 34)', 'de', 'list'),
  ('00000000-0000-4000-8000-0000000fb003', '00000000-0000-4000-8000-00000000fe02', '5 days 21:40',
   'Could the list remember my usual Saturday shop?', 'idea', false, 'android', 'Android 15 (SDK 35)', 'en', 'list'),
  ('00000000-0000-4000-8000-0000000fb004', '00000000-0000-4000-8000-00000000fe03', '2 days 12:00',
   'Interner Test: Feedback aus dem Familienhaushalt.', 'other', false, 'ios', 'iOS 18.1', 'de', 'list'),
  -- Outside last week: this Monday 00:00, and the Sunday before last week.
  ('00000000-0000-4000-8000-0000000fb005', '00000000-0000-4000-8000-00000000fe02', '7 days',
   'Schon diese Woche', 'bug', false, 'android', 'Android 15 (SDK 35)', 'de', 'list'),
  ('00000000-0000-4000-8000-0000000fb006', '00000000-0000-4000-8000-00000000fe02', '-00:01',
   'Vorletzte Woche', 'bug', false, 'android', 'Android 15 (SDK 35)', 'de', 'list');
insert into public.feedback (id, user_id, message, category, contact_ok, app_version, build, platform, os_version,
  locale, screen)
select id, user_id, message, category, contact_ok, '0.1.0', '42', platform, os_version, locale, screen from seed;
update public.feedback f
set created_at = ((date_trunc('week', now() at time zone 'Europe/Berlin') - interval '1 week') + s.at)
  at time zone 'Europe/Berlin'
from seed s where s.id = f.id;
-- Job 267: one note carries a screenshot.
update public.feedback set screenshot = user_id || '/' || id || '.png'
where id = '00000000-0000-4000-8000-0000000fb002';
SQL

run() { # name, extra psql args...
  local name="$1"; shift
  block "$name" | sql -q --set=ON_ERROR_STOP=1 -c 'set default_transaction_read_only = on' "$@" -f -
}

log "Monday summary: notes of last week (fake data)"
notes="$(run notes -P pager=off -P footer=off)"
printf '%s\n' "$notes"
log "Monday summary: counts (fake data)"
counts="$(run counts -P pager=off -P footer=off)"
printf '%s\n' "$counts"

log "checks"
ids="$(run notes -At -F ' ' | awk '{ print $1 }' | tr '\n' ' ')"
[[ $ids == "external external external internal " ]] \
  || fail "last week has 3 external then 1 internal note, got: $ids"
grep -q 'Vorletzte Woche\|Schon diese Woche' <<<"$notes" && fail "a note outside last week is listed"
order="$(run notes -At -F '|' | cut -d'|' -f4 | head -3 | tr '\n' '|')"
[[ $order == "Beim Abhaken springt die Liste nach oben.|Die App stürzt ab, wenn ich offline etwas lösche.|Could the list remember my usual Saturday shop?|" ]] \
  || fail "external notes are not in created_at order: $order"
shots="$(run notes -At -F '|' | cut -d'|' -f6 | head -3 | tr '\n' '|')"
[[ $shots == "|00000000-0000-4000-8000-00000000fe01/00000000-0000-4000-8000-0000000fb002.png||" ]] \
  || fail "the screenshot column: got $shots"
got_counts="$(run counts -At -F ' ' | tr '\n' ';')"
want_counts="external category bug 1;external category idea 1;external category none 1;external platform android 2;external platform web 1;internal category other 1;internal platform ios 1;"
[[ $got_counts == "$want_counts" ]] || fail "counts: got $got_counts, want $want_counts"
contact="$(block contact | sql -At -v feedback_id=00000000-0000-4000-8000-0000000fb002 -f -)"
[[ $contact == "max.beta@snacklist-tester.de" ]] || fail "the contact lookup answered '$contact'"
no_contact="$(block contact | sql -At -v feedback_id=00000000-0000-4000-8000-0000000fb003 -f -)"
[[ -z $no_contact ]] || fail "the contact lookup answered for a note without contact_ok"
echo "feedback-monday: PASS: notes (with the screenshot name), counts and the contact lookup as docs/FEEDBACK.md has them" >&2
