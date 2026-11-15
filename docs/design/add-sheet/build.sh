#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: the two add-sheet rounds in <out>/add-sheet/, self-contained.
# With #414's list-declutter folder, its overview goes at the root first, so old links keep working and the overview's
# links to ../add-sheet/add-feedback/ and ../add-sheet/reload-indicator/ resolve. The earlier rounds (job 260's
# feedback-experience, job 263's household-onboarding) are built beside them when given.
# Usage: build.sh <out-dir> [<list-declutter dir>] [<feedback-experience dir>] [<household-onboarding dir>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
overview="${2:-}"
feedback="${3:-}"
onboarding="${4:-}"
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
if [ -n "$onboarding" ]; then
  tmp="$(mktemp -d)"
  bash "$onboarding/build.sh" "$tmp/o"
  cp -r "$tmp/o/household-onboarding" "$out/"
  rm -rf "$tmp"
fi
dst="$out/add-sheet"
mkdir -p "$dst/vendor/fonts"
cp "$here"/{proto.css,page.js,sandbox.js,model.js,icons.js} "$dst/"
for r in add-feedback reload-indicator; do
  mkdir -p "$dst/$r"
  cp "$here/$r"/{index.html,options.js,measured.json,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/$r/"
  sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#; s#data-overview="\.\./\.\./list-declutter/"#data-overview="../../"#' "$dst/$r/index.html"
done
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
