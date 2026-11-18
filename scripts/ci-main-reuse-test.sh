#!/usr/bin/env bash
# Tests scripts/ci-main-reuse.sh in a scratch repository, with a gh stub that answers only the
# three API reads it must make (main's commit's PRs, the PR head, the head's ci-ok), each from the
# case's fixture, and fails any other request. Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

git init -q -b main "$tmp/repo"
cd "$tmp/repo"
c() { git -c user.name=t -c user.email=t@t commit -q --allow-empty "$@"; git rev-parse HEAD; }
base="$(c -m base)"
echo a >f && git add f
main="$(c -m 'the PR (#1)')"
tree="$(git rev-parse "$main^{tree}")"
head=1111111111111111111111111111111111111111

mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<STUB
#!/usr/bin/env bash
# gh api <path> --jq <filter>: the case's fixture for exactly that path through jq, else an error.
[[ \$1 == api && \$3 == --jq ]] || { echo "unexpected gh call: \$*" >&2; exit 2; }
case \$2 in
  repos/o/r/commits/$main/pulls) kind=pulls ;;
  repos/o/r/commits/$head) kind=commit ;;
  'repos/o/r/commits/$head/check-runs?check_name=ci-ok&filter=all&per_page=100') kind=checks ;;
  *) echo "HTTP 404: Not Found (\$2)" >&2; exit 1 ;;
esac
[[ -f \$FIXTURES/\$kind ]] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
jq -r "\$4" "\$FIXTURES/\$kind"
STUB
chmod +x "$tmp/bin/gh"

# reuse() <want> <name> <pulls json> <head commit json> <check-runs json>; "-" leaves a fixture out.
reuse() {
  local want="$1" name="$2" got
  export FIXTURES="$tmp/fixtures/$name"
  mkdir -p "$FIXTURES"
  [[ $3 == - ]] || echo "$3" >"$FIXTURES/pulls"
  [[ $4 == - ]] || echo "$4" >"$FIXTURES/commit"
  [[ $5 == - ]] || echo "$5" >"$FIXTURES/checks"
  got="$(PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r "$REPO_ROOT/scripts/ci-main-reuse.sh" "$main" 2>"$FIXTURES/err")" \
    || fail "$name: exit $?"
  [[ $got == "reuse=$want" ]] || fail "$name: '$got', want reuse=$want ($(cat "$FIXTURES/err"))"
}
pulls="[{\"number\": 1, \"merged_at\": \"2026-11-18T10:00:00Z\", \"base\": {\"ref\": \"main\"}, \"head\": {\"sha\": \"$head\"}}]"
same="{\"commit\": {\"tree\": {\"sha\": \"$tree\"}}, \"parents\": [{\"sha\": \"$base\"}]}"
run() { echo "{\"app\": {\"slug\": \"${3:-github-actions}\"}, \"status\": \"completed\", \"conclusion\": \"$1\", \"completed_at\": \"$2\", \"html_url\": \"https://ci/$1\"}"; }
checks() { local IFS=,; echo "{\"check_runs\": [$*]}"; }
green="$(checks "$(run success 2026-11-18T09:00:00Z)")"

reuse true same-tree-parent-green "$pulls" "$same" "$green"
reuse true green-rerun-after-red "$pulls" "$same" "$(checks "$(run failure 2026-11-18T08:00:00Z)" "$(run success 2026-11-18T09:00:00Z)")"
reuse false red-rerun-after-green "$pulls" "$same" "$(checks "$(run success 2026-11-18T08:00:00Z)" "$(run failure 2026-11-18T09:00:00Z)")"
reuse false no-ci-ok "$pulls" "$same" "$(checks)"
reuse false ci-ok-running "$pulls" "$same" '{"check_runs": [{"app": {"slug": "github-actions"}, "status": "in_progress", "conclusion": null, "completed_at": null}]}'
reuse false ci-ok-of-another-app "$pulls" "$same" "$(checks "$(run success 2026-11-18T09:00:00Z other)")"
reuse false other-tree "$pulls" "{\"commit\": {\"tree\": {\"sha\": \"$head\"}}, \"parents\": [{\"sha\": \"$base\"}]}" "$green"
reuse false other-parent "$pulls" "{\"commit\": {\"tree\": {\"sha\": \"$tree\"}}, \"parents\": [{\"sha\": \"$head\"}]}" "$green"
reuse false merge-commit-head "$pulls" "{\"commit\": {\"tree\": {\"sha\": \"$tree\"}}, \"parents\": [{\"sha\": \"$base\"}, {\"sha\": \"$head\"}]}" "$green"
reuse false no-pr '[]' "$same" "$green"
reuse false open-pr "[{\"number\": 1, \"merged_at\": null, \"base\": {\"ref\": \"main\"}, \"head\": {\"sha\": \"$head\"}}]" "$same" "$green"
reuse false pr-into-other-branch "[{\"number\": 1, \"merged_at\": \"2026-11-18T10:00:00Z\", \"base\": {\"ref\": \"release\"}, \"head\": {\"sha\": \"$head\"}}]" "$same" "$green"
reuse false pulls-api-error - "$same" "$green"
reuse false commit-api-error "$pulls" - "$green"
reuse false checks-api-error "$pulls" "$same" -

[[ $failures == 0 ]] || { echo "ci-main-reuse-test: $failures failed" >&2; exit 1; }
echo "ci-main-reuse-test: ok"
