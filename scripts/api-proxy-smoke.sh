#!/usr/bin/env bash
# Smoke test of the public REST API through the api.snacklist.app proxy (mcp-proxy/vercel.json):
# the proxy forwards to the api function, passes the caller's query on, drops nothing the API
# needs, and caches nothing. Read-only requests only.
# Without a key: GET <base>/items gets 401 missing_token (404 not_found while
# app_switches.public_api is off), Cache-Control: no-store and no x-vercel-cache: HIT.
# API_SMOKE_KEY=fgp_… (a key with the read scope; never printed) adds: GET
# <base>/categories?via=smoke answers 200 (the proxy's marker arrives, so the function drops every
# via; without it the strict query check answers 400), and GET <base>/items?limit=abc answers 400
# validation_failed (the caller's query reaches the function). From one machine it cannot show
# that two callers get separate unknown-key budgets (x-vercel-forwarded-for); the api tests do.
# Usage: [API_SMOKE_KEY=fgp_…] scripts/api-proxy-smoke.sh [base URL, default https://api.snacklist.app/v1]
# Prints PASS/FAIL/SKIP per check; exits 1 on any FAIL, 2 on a usage error.
set -euo pipefail

[[ $# -le 1 ]] || { echo "usage: $0 [base URL, e.g. https://api.snacklist.app/v1]" >&2; exit 2; }
base="${1:-https://api.snacklist.app/v1}"
base="${base%/}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
skip() { echo "SKIP $1"; }

# request <name> <url> [curl args...]: status, headers and body to $work/<name>.*.
# Retries timeouts and transient 5xx, so a cold start passes and a lasting outage fails.
request() {
  local name=$1
  shift
  curl -sS --max-time 20 --retry 2 --retry-delay 3 --retry-connrefused \
    -D "$work/$name.headers" -o "$work/$name.body" -w '%{http_code}' "$@" \
    >"$work/$name.status" 2>"$work/$name.err" || true
}
status() { cat "$work/$1.status"; }
header() { { grep -i "^$2:" "$work/$1.headers" || true; } | tail -1 | cut -d' ' -f2- | tr -d '\r'; }
code() { jq -r '.error.code // empty' "$work/$1.body" 2>/dev/null || true; }
# The key never reaches the output, even if an answer echoed it.
got() {
  local text
  text="got HTTP $(status "$1") $(head -c 200 "$work/$1.body" 2>/dev/null) $(head -c 200 "$work/$1.err")"
  if [[ -n ${API_SMOKE_KEY:-} ]]; then text="${text//"$API_SMOKE_KEY"/<key>}"; fi
  echo "$text"
}

echo "API proxy smoke test against $base"

request nokey "$base/items" -H 'accept: application/json'
case "$(status nokey) $(code nokey)" in
  '401 missing_token') pass 'no key: 401 missing_token from the api function' ;;
  '404 not_found') pass 'no key: 404 not_found from the api function (app_switches.public_api is off)' ;;
  *) fail "no key: want 401 missing_token, or 404 not_found while the API is off; $(got nokey)" ;;
esac
if [[ $(header nokey cache-control) == no-store ]]; then
  pass 'no key: Cache-Control: no-store'
else
  fail "no key: want Cache-Control: no-store; got '$(header nokey cache-control)'"
fi
request nokey2 "$base/items" -H 'accept: application/json'
if [[ $(header nokey2 x-vercel-cache) == HIT ]]; then
  fail 'no key: the proxy served the answer from its cache (x-vercel-cache: HIT)'
else
  pass "no key: not from the proxy's cache (x-vercel-cache: '$(header nokey2 x-vercel-cache)')"
fi

if [[ -z ${API_SMOKE_KEY:-} ]]; then
  skip 'categories?via=smoke, items?limit=abc: API_SMOKE_KEY not set'
else
  printf 'authorization: Bearer %s\n' "$API_SMOKE_KEY" >"$work/auth"
  auth=(-H @"$work/auth" -H 'accept: application/json')

  request marker "$base/categories?via=smoke" "${auth[@]}"
  if [[ $(status marker) == 200 ]]; then
    pass "categories?via=smoke: 200, so the proxy's via marker arrives and every via is dropped"
  else
    fail "categories?via=smoke: want 200 (a direct call without the marker gets 400); $(got marker)"
  fi

  request bad "$base/items?limit=abc" "${auth[@]}"
  if [[ $(status bad) == 400 && $(code bad) == validation_failed ]]; then
    pass "items?limit=abc: 400 validation_failed, so the caller's query reaches the function"
  else
    fail "items?limit=abc: want 400 validation_failed; $(got bad)"
  fi
fi

if ((failures > 0)); then
  echo "$failures check(s) failed against $base"
  exit 1
fi
echo "all checks passed against $base"
