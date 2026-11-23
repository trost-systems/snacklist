#!/usr/bin/env bash
# Proof journey: quick-add with autofocus on peter's app, live sync to lea's app and back.
# Needs `fg up --clients peter,lea` with both apps signed in (the script logs them in if not).
# Usage: journeys/quick-add-live-sync.sh [ITEM]   Evidence: the run directory printed at the end.
set -euo pipefail
fg="$(dirname "$(readlink -f "$0")")/../fg"
item="${1:-Milch}"
stamp="$(date +%H%M%S)"

step() { printf '\n== %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; "$fg" record stop >/dev/null 2>&1; exit 1; }
# Runs fg, echoes its JSON to stderr, fails the journey on ok:false.
run() {
  local out
  out="$("$fg" "$@")" || { echo "$out" >&2; fail "fg $*"; }
  echo "$out" | jq -c . >&2
  echo "$out"
}

step "both apps are healthy"
run doctor >/dev/null

for who in peter lea; do
  # Signed out, a client shows the start screen (start-screen) or the login form; fg login handles both.
  if (( $("$fg" find --key start-screen --client "$who" | jq -r .count) + $("$fg" find --key login-email --client "$who" | jq -r .count) )); then
    run login "$who" >/dev/null
  fi
done

step "precondition: neither test item is on the active list (earlier runs marked bought)"
run db query "update items set status = 'bought' where status = 'active' and name in ('$item', 'Äpfel') and household_id = (select id from households where name = 'Familie Test')" --write >/dev/null
run wait --text "$item" --gone --client lea >/dev/null

step "reopen peter's app; nothing tapped in the list yet"
run restart --client peter >/dev/null
run wait --key add-item-field --client peter >/dev/null
run record start --name "peter-quick-add-$stamp" --client peter >/dev/null
run record start --name "lea-live-sync-$stamp" --client lea >/dev/null
run screenshot --name 01-peter-opened --client peter >/dev/null

step "type into whatever has focus (the add field, if autofocus works) and press Enter: the sheet's first row"
run type --input "$item" --client peter >/dev/null
run wait --text "$item, Wie getippt" --client peter --timeout 5 >/dev/null
run press enter --client peter >/dev/null
run wait --contains "Hinzugefügt: $item" --client peter --timeout 5 >/dev/null
run screenshot --name 02-peter-added --client peter >/dev/null

step "focus stays in the field: a second Enter-add without tapping"
run type --input "2 Äpfel" --submit --client peter >/dev/null
run wait --contains "Hinzugefügt: Äpfel" --client peter --timeout 5 >/dev/null

step "Escape closes the sheet; peter's list shows both rows"
run press escape --client peter >/dev/null
run wait --key add-sheet --gone --client peter >/dev/null
run wait --text "$item" --client peter --timeout 5 >/dev/null
run wait --text "2× Äpfel" --client peter --timeout 5 >/dev/null

step "lea's app shows the item without any action on lea's side"
synced="$(run wait --text "$item" --client lea --timeout 5 | jq -r '.elapsedMs')"
run screenshot --name 03-lea-sees-item --client lea >/dev/null

step "lea taps the item's row, which ticks it; it disappears on peter's app"
run tap --text "$item" --client lea >/dev/null
gone="$(run wait --text "$item" --gone --client peter --timeout 5 | jq -r '.elapsedMs')"
run screenshot --name 04-peter-item-gone --client peter >/dev/null

step "server state: the row just added is bought, by lea"
rows="$(run db query "select i.name, i.status, u.email as bought_by from items i left join auth.users u on u.id = i.bought_by where i.name = '$item' and i.household_id = (select id from households where name = 'Familie Test') order by i.created_at desc limit 1")"
[[ "$(echo "$rows" | jq -r '.rows[0].status')" == bought ]] || fail "item is not marked bought in the database"
[[ "$(echo "$rows" | jq -r '.rows[0].bought_by')" == lea@fg.test ]] || fail "item was not bought by lea"

run record stop >/dev/null
dir="$("$fg" env | jq -r .evidenceDir)"
printf '\nPASS: "%s" added by autofocus+Enter on peter, visible on lea after %s ms, gone on peter %s ms after lea ticked it.\nEvidence: %s\n' "$item" "$synced" "$gone" "$dir"
