#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: this round in <out>/feedback-experience/, self-contained.
# With a list-declutter folder (#414's branch) as the second argument, its overview goes at the root first, as in
# the earlier previews, so old links keep working and the overview's link to ../feedback-experience/ resolves.
# Usage: build.sh <out-dir> [<path to docs/design/list-declutter>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
overview="${2:-}"
rm -rf "$out"
if [ -n "$overview" ]; then
  bash "$overview/build.sh" "$out"
fi
dst="$out/feedback-experience"
mkdir -p "$dst/vendor/fonts"
cp "$here"/{index.html,proto.css,proto.js,flows.js,ui.js,model.js,metrics.js,icons.js,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/"
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#' "$dst/index.html"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
if [ -n "$overview" ]; then
  sed -i 's#data-overview="\.\./list-declutter/"#data-overview="../"#' "$dst/index.html"
else
  sed -i 's#data-overview="\.\./list-declutter/"#data-overview="./"#' "$dst/index.html"
fi
