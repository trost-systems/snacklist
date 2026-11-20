#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: rounds AS and AM and their overview in <out>/after-add/, self-contained.
# With --base <deployment id>, every file of that earlier preview is fetched first, byte for byte, so old links keep
# working (tools/fetch-base.mjs, needs VERCEL_TOKEN).
# Usage: build.sh <out-dir> [--base <deployment id>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
rm -rf "$out"
mkdir -p "$out"
if [ "${2:-}" = "--base" ]; then
  node "$here/tools/fetch-base.mjs" "${3:?deployment id}" "$out"
fi
dst="$out/after-add"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts" "$dst/tools" "$dst/as"
cp "$here"/{index.html,proto.css,page.js,phone.js,model.js,walk.js,text.js,icons.js,measured.json,verify.mjs,README.md,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/"
cp "$here/tools/serve.mjs" "$dst/tools/"
cp "$here/as/index.html" "$dst/as/"
mkdir -p "$dst/am"
cp "$here"/am/{index.html,am.css,model.js,phone.js,walk.js,text.js,page.js,verify.mjs,measured.json,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/am/"
sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#' "$dst/as/index.html" "$dst/page.js" "$dst/am/index.html" "$dst/am/page.js"
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#' "$dst/index.html" "$dst/page.js"
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
echo "built $dst"
