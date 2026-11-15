#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: these two rounds in <out>/household-onboarding/, self-contained.
# With #414's list-declutter folder, its overview goes at the root first (as in the earlier previews), so old links keep
# working and the overview's links to ../household-onboarding/join/ and /create/ resolve. With job 260's
# feedback-experience folder, its round is built beside them, so the overview's link to it resolves too.
# Usage: build.sh <out-dir> [<path to docs/design/list-declutter>] [<path to docs/design/feedback-experience>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
overview="${2:-}"
feedback="${3:-}"
rm -rf "$out"
mkdir -p "$out"
[ -n "$overview" ] && bash "$overview/build.sh" "$out"
if [ -n "$feedback" ]; then
  tmp="$(mktemp -d)"
  bash "$feedback/build.sh" "$tmp"
  cp -r "$tmp/feedback-experience" "$out/"
  sed -i 's#data-overview="\./"#data-overview="../"#' "$out/feedback-experience/index.html"
  rm -rf "$tmp"
fi
dst="$out/household-onboarding"
mkdir -p "$dst/vendor/fonts" "$dst/join" "$dst/create"
cp "$here"/{proto.css,proto.js,metrics.js,model.js,ui.js,icons.js} "$dst/"
for r in join create; do cp "$here/$r"/{index.html,flows.js,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/$r/"; done
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#; s#data-overview="\.\./\.\./list-declutter/"#data-overview="../../"#' "$dst/join/index.html" "$dst/create/index.html"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
