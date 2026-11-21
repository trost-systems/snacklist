#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: round RD in <out>/redesign/, self-contained.
# With --base <deployment id>, every file of that earlier preview is fetched first, byte for byte, so old links keep
# working, and the root overview gets a card for round RD (tools/fetch-base.mjs needs VERCEL_TOKEN).
# Usage: build.sh <out-dir> [--base <deployment id>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/../../.."
out="${1:?out dir}"
rm -rf "$out"
mkdir -p "$out"
if [ "${2:-}" = "--base" ]; then
  node "$here/tools/fetch-base.mjs" "${3:?deployment id}" "$out"
  node "$here/tools/link-overview.mjs" "$out"
fi
dst="$out/redesign"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts" "$dst/tools" "$dst/rd"
cp "$here"/{index.html,proto.css,palette.css,page.js,render.js,measure.js,options.js,data.js,strings.js,icons.js,recommend.js,verify.mjs,build.sh,README.md,HEX-INVENTORY.md} "$dst/"
cp "$here/tools"/{serve.mjs,strings.mjs,palette.mjs,table.mjs,shoot.mjs,fetch-base.mjs,link-overview.mjs,icons.py} "$dst/tools/"
cp "$here/rd"/{index.html,measured.json,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/rd/"
cp "$repo/site/public/fonts"/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
cp "$repo/app/assets/fonts"/{Inter-Regular,Inter-Medium,Inter-SemiBold,Inter-Bold,BricolageGrotesque-Bold,BricolageGrotesque-ExtraBold}.ttf "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#; s#\.\./\.\./\.\./app/assets/fonts/#vendor/fonts/#' "$dst/proto.css"
echo "built $dst"
