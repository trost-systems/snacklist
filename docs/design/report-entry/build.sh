#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: this round in <out>/report-entry/, self-contained.
# With job 273's add-sheet folder (and that build's own arguments: #414's list-declutter, 260's feedback-experience,
# 263's household-onboarding), the earlier rounds and #414's overview at the root are built first, so old links
# keep working and the overview's link to ../report-entry/ resolves.
# Usage: build.sh <out-dir> [<add-sheet dir> [<list-declutter dir> [<feedback-experience dir> [<household-onboarding dir>]]]]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
shift
if [ $# -gt 0 ]; then
  addsheet="$1"
  shift
  bash "$addsheet/build.sh" "$out" "$@"
else
  rm -rf "$out"
  mkdir -p "$out"
fi
dst="$out/report-entry"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts"
cp "$here"/{index.html,proto.css,page.js,phone.js,copy.js,icons.js,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/"
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#; s#data-overview="\.\./list-declutter/"#data-overview="../"#' "$dst/index.html"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
