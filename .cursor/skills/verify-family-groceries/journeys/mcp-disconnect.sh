#!/usr/bin/env bash
# Proof journey: an OAuth app and a personal access token lose MCP access the moment peter
# disconnects or revokes them in the app (Mehr → Zugänge), not when their tokens expire.
# Needs `fg up --clients peter` (the script signs peter in if not).
# Usage: journeys/mcp-disconnect.sh   Evidence: the run directory printed at the end.
set -euo pipefail
fg="$(dirname "$(readlink -f "$0")")/../fg"
stamp="$(date +%H%M%S)"
app="Journey Client $stamp"
pat="Journey $stamp"

step() { printf '\n== %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; "$fg" record stop >/dev/null 2>&1; exit 1; }
run() {
  local out
  out="$("$fg" "$@")" || { echo "$out" >&2; fail "fg $*"; }
  echo "$out" | jq -c . >&2
  echo "$out"
}
# Opens an entry of the More tab (the list is a lazy ListView, so scroll to it first).
open_more() {
  [[ "$("$fg" find --key add-sheet-close --client "$1" | jq -r .count)" == 0 ]] || run tap --key add-sheet-close --client "$1" >/dev/null
  run tap --key tab-more --client "$1" >/dev/null
  # The tab reopens its last page; a second tap on it goes to the More list.
  "$fg" wait --key more-screen --timeout 2 --client "$1" >/dev/null 2>&1 || run tap --key tab-more --client "$1" >/dev/null
  run wait --key more-screen --client "$1" >/dev/null
  run marionette --client "$1" -- scroll-to --key "$2" >/dev/null
  run tap --key "$2" --client "$1" >/dev/null
}

api="$("$fg" env | jq -r .apiUrl)"
mcp="$api/functions/v1/mcp"
# The HTTP status of an MCP tools/list call with the given bearer token.
mcp_status() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST "$mcp" -H "authorization: Bearer $1" \
    -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
}

step "peter is signed in"
run doctor >/dev/null
# Signed out, the client shows the start screen (start-screen) or the login form; fg login handles both.
if (( $("$fg" find --key start-screen | jq -r .count) + $("$fg" find --key login-email | jq -r .count) )); then run login peter >/dev/null; fi
# Tokens stay out of the log: these two calls bypass run's echo.
user_token="$("$fg" login peter --api | jq -r .accessToken)"

step "precondition: '$app' is connected over OAuth (registration, PKCE, consent, token over HTTP)"
redirect='http://127.0.0.1:8976/callback'
client_id="$(curl -sS -X POST "$api/auth/v1/oauth/clients/register" -H 'content-type: application/json' \
  -d "{\"client_name\":\"$app\",\"redirect_uris\":[\"$redirect\"],\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"response_types\":[\"code\"],\"token_endpoint_auth_method\":\"none\"}" \
  | jq -r .client_id)"
verifier="$(openssl rand -base64 48 | tr -d '=+/\n' | cut -c1-64)"
challenge="$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
consent="$(curl -sS -o /dev/null -w '%{redirect_url}' -G "$api/auth/v1/oauth/authorize" \
  --data-urlencode response_type=code --data-urlencode "client_id=$client_id" \
  --data-urlencode "redirect_uri=$redirect" --data-urlencode code_challenge_method=S256 \
  --data-urlencode "code_challenge=$challenge" --data-urlencode state=journey --data-urlencode 'scope=openid email')"
authorization_id="$(sed -n 's/.*authorization_id=\([^&]*\).*/\1/p' <<<"$consent")"
[[ -n "$authorization_id" ]] || fail "authorize did not redirect to the consent page: $consent"
# As the consent page does: read the request as the signed-in user, then approve it.
curl -sS -o /dev/null "$api/auth/v1/oauth/authorizations/$authorization_id" -H "authorization: Bearer $user_token"
code_url="$(curl -sS -X POST "$api/auth/v1/oauth/authorizations/$authorization_id/consent" \
  -H "authorization: Bearer $user_token" -H 'content-type: application/json' -d '{"action":"approve"}' | jq -r .redirect_url)"
code="$(sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' <<<"$code_url")"
access_token="$(curl -sS -X POST "$api/auth/v1/oauth/token" \
  --data-urlencode grant_type=authorization_code --data-urlencode "code=$code" \
  --data-urlencode "redirect_uri=$redirect" --data-urlencode "client_id=$client_id" \
  --data-urlencode "code_verifier=$verifier" | jq -r .access_token)"
[[ "$(mcp_status "$access_token")" == 200 ]] || fail "the fresh OAuth token does not reach MCP"
expires_in_min=$(( ($(jq -R 'split(".")[1] | @base64d | fromjson | .exp' <<<"$access_token") - $(date +%s)) / 60 ))
echo "OAuth token reaches MCP (200), expires in $expires_in_min min" >&2

step "peter opens Zugänge and sees the app"
open_more peter more-access
run wait --text "$app" >/dev/null
run record start --name "mcp-disconnect-$stamp" >/dev/null
run screenshot --name mcp-01-connected >/dev/null

step "peter disconnects it; its next MCP call gets 401"
run tap --tooltip "$app trennen" >/dev/null
run wait --text "$app trennen?" >/dev/null
run tap --text Trennen >/dev/null
run wait --text "$app" --gone >/dev/null
run screenshot --name mcp-02-disconnected >/dev/null
after_disconnect="$(mcp_status "$access_token")"
[[ "$after_disconnect" == 401 ]] || fail "after disconnecting, MCP answered $after_disconnect, not 401"
sessions="$(run db query "select count(*)::int as n from auth.sessions where oauth_client_id = '$client_id'" | jq -r '.rows[0].n')"
[[ "$sessions" == 0 ]] || fail "the client still has $sessions sessions"

step "peter creates a token in the app; it reaches MCP"
run tap --text "Token erstellen" >/dev/null
run wait --label Name >/dev/null
run type --label Name --input "$pat" >/dev/null
run tap --text Erstellen >/dev/null
token="$("$fg" wait --contains fgp_ | jq -r '[.. | strings | select(test("^fgp_[A-Za-z0-9_-]{43}$"))][0]')"
[[ "$token" == fgp_* ]] || fail "no token shown after creating it"
[[ "$(mcp_status "$token")" == 200 ]] || fail "the new token does not reach MCP"
run tap --text Fertig >/dev/null

step "peter revokes it; its next MCP call gets 401"
run tap --tooltip "$pat widerrufen" >/dev/null
run wait --text "Token widerrufen?" >/dev/null
run tap --text Widerrufen >/dev/null
run wait --tooltip "$pat widerrufen" --gone >/dev/null
run screenshot --name mcp-03-token-revoked >/dev/null
after_revoke="$(mcp_status "$token")"
[[ "$after_revoke" == 401 ]] || fail "after revoking, MCP answered $after_revoke, not 401"
revoked="$(run db query "select revoked_at is not null as revoked from personal_access_tokens where name = '$pat'" | jq -r '.rows[0].revoked')"
[[ "$revoked" == true ]] || fail "the token row is not revoked"
run record stop >/dev/null

step "peter goes back to the list, where the next journey starts"
run tap --key tab-list >/dev/null
run wait --key add-item-field >/dev/null

dir="$("$fg" env | jq -r .evidenceDir)"
printf '\nPASS: "%s" disconnected in Zugänge -> next MCP call %s (token had %s min left); "%s" revoked -> next MCP call %s.\nEvidence: %s\n' \
  "$app" "$after_disconnect" "$expires_in_min" "$pat" "$after_revoke" "$dir"
