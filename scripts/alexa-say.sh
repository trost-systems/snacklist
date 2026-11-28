#!/usr/bin/env bash
# Job 31: plays Alexa against a LOCAL stack's `alexa` function: builds the request Alexa would send
# for an utterance and signs it with the test CA of scripts/alexa-test-ca.sh (which the local
# function trusts; a hosted one does not). Prints the function's JSON answer.
#
#   scripts/alexa-say.sh [options] "Milch und Eier"     AddItemIntent with that slot value
#   scripts/alexa-say.sh [options] --list Geburtstag "Luftballons"
#                                                       AddToListIntent with slots itemphrase and list
#   scripts/alexa-say.sh [options] --read               ReadListIntent
#   scripts/alexa-say.sh [options] --launch             "Alexa, öffne snacklist"
#   scripts/alexa-say.sh [options] --disable            AlexaSkillEvent.SkillDisabled
# Options: --token <OAuth access token from account linking> (none: an unlinked user),
#          --user <Alexa user id> (default amzn1.ask.account.LOCAL), --retry (the second try after
#          the re-prompt), --unsigned, --stale (timestamp 200 s old), --url <API URL>,
#          --locale <Alexa locale> (default de-DE; en-US and the other en-* get English),
#          --confirm <CONFIRMED|DENIED> (the answer to a Q79 question) with --attributes <JSON>
#          (the session attributes the question came with, e.g. '{"list":"<list id>"}').
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key="$REPO_ROOT/supabase/.temp/alexa-test/leaf.key"
skill='amzn1.ask.skill.00000000-0000-4000-8000-00000000e2e0'
token='' user='amzn1.ask.account.LOCAL' kind='add' items='' sign=1 skew=0 attributes='null' locale='de-DE'
list='' confirm='NONE'
url="${SUPABASE_URL:-}"
while (($#)); do
  case $1 in
    --token) token=$2; shift ;;
    --user) user=$2; shift ;;
    --url) url=$2; shift ;;
    --locale) locale=$2; shift ;;
    --list) list=$2; shift ;;
    --confirm) confirm=$2; shift ;;
    --attributes) attributes=$2; shift ;;
    --read) kind='read' ;;
    --launch) kind='launch' ;;
    --disable) kind='disable' ;;
    --retry) attributes='{"retry":1}' ;;
    --unsigned) sign=0 ;;
    --stale) skew=200 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) items=$1 ;;
  esac
  shift
done
if [[ -z $url ]]; then
  url="$(cd "$REPO_ROOT" && supabase status -o env 2>/dev/null | sed -n 's/^API_URL="\(.*\)"$/\1/p')"
fi
[[ -n $url ]] || { echo "no local stack: start it (scripts/dev.sh) or pass --url" >&2; exit 1; }
[[ -s $key ]] || { echo "no test CA: run scripts/alexa-test-ca.sh, then restart the stack" >&2; exit 1; }

timestamp="$(date -u -d "-$skew seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$skew"S +%Y-%m-%dT%H:%M:%SZ)"
case $kind in
  add)
    if [[ -n $list ]]; then
      request="$(jq -n --arg v "$items" --arg l "$list" --arg c "$confirm" '{type: "IntentRequest", intent: {name: "AddToListIntent", confirmationStatus: $c, slots: {itemphrase: {name: "itemphrase", value: $v}, list: {name: "list", value: $l}}}}')"
    else
      request="$(jq -n --arg v "$items" --arg c "$confirm" '{type: "IntentRequest", intent: {name: "AddItemIntent", confirmationStatus: $c, slots: {items: {name: "items", value: $v}}}}')"
    fi ;;
  read) request='{"type":"IntentRequest","intent":{"name":"ReadListIntent","confirmationStatus":"NONE"}}' ;;
  launch) request='{"type":"LaunchRequest"}' ;;
  disable) request='{"type":"AlexaSkillEvent.SkillDisabled","body":{}}' ;;
esac
body="$(jq -cn --arg locale "$locale" --arg skill "$skill" --arg user "$user" --arg token "$token" --arg ts "$timestamp" \
  --argjson request "$request" --argjson attributes "$attributes" '
  ({userId: $user} + (if $token == "" then {} else {accessToken: $token} end)) as $u
  | {version: "1.0",
     session: {new: ($attributes == null), sessionId: "amzn1.echo-api.session.local",
               application: {applicationId: $skill}, attributes: $attributes, user: $u},
     context: {System: {application: {applicationId: $skill}, user: $u}},
     request: ({requestId: "amzn1.echo-api.request.local", timestamp: $ts, locale: $locale} + $request)}')"
headers=(-H 'content-type: application/json')
if ((sign)); then
  signature="$(printf '%s' "$body" | openssl dgst -sha256 -sign "$key" | base64 | tr -d '\n')"
  headers+=(-H 'signaturecertchainurl: https://s3.amazonaws.com/echo.api/echo-api-cert-test.pem' -H "signature-256: $signature")
fi
curl -sS -w '\n' -X POST "${url%/}/functions/v1/alexa" "${headers[@]}" --data-binary "$body"
