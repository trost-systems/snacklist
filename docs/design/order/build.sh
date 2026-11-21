#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: round IO and its overview in <out>/order/, self-contained.
# With --base <deployment id>, every file of that earlier preview is fetched first, byte for byte, so old links keep
# working, and the root overview gets a card for round IO (tools/fetch-base.mjs needs VERCEL_TOKEN).
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
dst="$out/order"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts" "$dst/tools" "$dst/io/real"
cp "$here"/{index.html,proto.css,page.js,phone.js,options.js,paths.js,model.js,strings.js,text.js,icons.js,verify.mjs,README.md,APPROACHES.md} "$dst/"
cp "$here/tools"/{serve.mjs,strings.mjs,shots.mjs} "$dst/tools/"
cp "$here/io"/{index.html,measured.json,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/io/"
cp "$here/io/real"/* "$dst/io/real/"
sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#' "$dst/io/index.html" "$dst/page.js"
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#' "$dst/index.html" "$dst/page.js"
cp "$repo/site/public/tokens.css" "$dst/vendor/"
cp "$repo/site/public/fonts"/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
cp "$repo/app/assets/fonts"/{Inter-Regular,Inter-Medium,Inter-SemiBold,Inter-Bold,BricolageGrotesque-Bold,BricolageGrotesque-ExtraBold}.ttf "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#; s#\.\./\.\./\.\./app/assets/fonts/#vendor/fonts/#' "$dst/proto.css"
echo "built $dst"
