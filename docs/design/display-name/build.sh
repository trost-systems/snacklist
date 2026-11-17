#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: both rounds and their overview in <out>/display-name/, self-contained.
# With job 278's report-entry folder (and that build's own arguments: 273's add-sheet, #414's list-declutter, 260's
# feedback-experience, 263's household-onboarding), the earlier rounds and #414's overview at the root are built first,
# so old links keep working.
# Usage: build.sh <out-dir> [<report-entry dir> [<add-sheet dir> [<list-declutter dir> [<feedback-experience dir> [<household-onboarding dir>]]]]]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
shift
if [ $# -gt 0 ]; then
  report="$1"
  shift
  bash "$report/build.sh" "$out" "$@"
else
  rm -rf "$out"
  mkdir -p "$out"
fi
dst="$out/display-name"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts" "$dst/tools"
cp "$here"/{index.html,proto.css,page.js,phone.js,copy.js,icons.js,verify.mjs,README.md} "$dst/"
cp "$here/tools/serve.mjs" "$dst/tools/"
for r in dn de; do
  mkdir -p "$dst/$r"
  cp "$here/$r"/{index.html,measured.json,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/$r/"
  sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#' "$dst/$r/index.html"
done
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#' "$dst/index.html"
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
