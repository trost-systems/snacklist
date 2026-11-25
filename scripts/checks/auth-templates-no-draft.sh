#!/usr/bin/env bash
# The active Auth email templates in supabase/templates/ never carry `data-hl-draft`:
# supabase/deploy/auth_mail.ts refuses to deploy a template with one (#434). The *_notification
# templates stay off until enabled and may carry it. Usage: auth-templates-no-draft.sh [templates dir]
set -euo pipefail
dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/supabase/templates}"
bad=0
for name in confirmation magic_link recovery email_change invite reauthentication; do
  f="$dir/$name.html"
  [[ -f "$f" ]] || { echo "auth templates: $f is missing" >&2; bad=1; continue; }
  if grep -q 'data-hl-draft' "$f"; then
    echo "auth templates: $f carries data-hl-draft; the live Auth mail deploy refuses it. Get the line approved and drop the attribute in emails/ (then rebuild), only *_notification templates may keep one." >&2
    bad=1
  fi
done
exit "$bad"
