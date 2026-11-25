#!/usr/bin/env bash
# Tests auth-templates-no-draft.sh on a scratch directory. Run by scripts/lint.sh.
set -euo pipefail
check="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auth-templates-no-draft.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for n in confirmation magic_link recovery email_change invite reauthentication; do echo '<p>ok</p>' >"$tmp/$n.html"; done
echo '<p data-hl-draft="x">n</p>' >"$tmp/password_changed_notification.html"
"$check" "$tmp" || { echo "FAIL: clean active templates plus a drafted notification should pass" >&2; exit 1; }
echo '<p data-hl-draft="reason">x</p>' >"$tmp/recovery.html"
if "$check" "$tmp" 2>/dev/null; then echo "FAIL: drafted active template should fail" >&2; exit 1; fi
echo '<p>ok</p>' >"$tmp/recovery.html"; rm "$tmp/invite.html"
if "$check" "$tmp" 2>/dev/null; then echo "FAIL: missing active template should fail" >&2; exit 1; fi
echo "auth-templates-no-draft: ok"
