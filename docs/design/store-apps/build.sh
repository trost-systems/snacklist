#!/usr/bin/env bash
# Builds the static folder for the Vercel preview: both rounds and their overview in <out>/store-apps/, self-contained.
# With --base <deployment id>, every file of that earlier preview (job 293's dpl_2wt4ZzVtvWc1u3vYiN6U6mYdmw46 holds the
# rounds before this one and #414's overview at the root) is fetched first, byte for byte, so old links keep working.
# Usage: build.sh <out-dir> [--base <deployment id>]   (--base needs VERCEL_TOKEN)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../../site/public"
out="${1:?out dir}"
rm -rf "$out"
mkdir -p "$out"
if [ "${2:-}" = "--base" ]; then
  node "$here/tools/fetch-base.mjs" "${3:?deployment id}" "$out"
fi
dst="$out/store-apps"
rm -rf "$dst"
mkdir -p "$dst/vendor/fonts" "$dst/tools" "$dst/registry"
cp "$here"/{index.html,proto.css,page.js,phone.js,os.js,ss.js,copy.js,data.js,icons.js,measured.json,verify.mjs,README.md} "$dst/"
cp "$here/tools/serve.mjs" "$dst/tools/"
cp "$here/registry"/{retailers.json,REGISTRY.md,verify-registry.mjs} "$dst/registry/"
for r in os ss; do
  mkdir -p "$dst/$r"
  cp "$here/$r"/{index.html,RECOMMENDATION.md,RECOMMENDATION.de.md} "$dst/$r/"
  sed -i 's#\.\./\.\./\.\./\.\./site/public/tokens\.css#../vendor/tokens.css#' "$dst/$r/index.html"
done
sed -i 's#\.\./\.\./\.\./site/public/tokens\.css#vendor/tokens.css#' "$dst/index.html"
cp "$site/tokens.css" "$dst/vendor/"
cp "$site"/fonts/{bricolage-grotesque-latin-standard-normal,inter-latin-wght-normal}.woff2 "$dst/vendor/fonts/"
sed -i 's#\.\./\.\./\.\./site/public/fonts/#vendor/fonts/#' "$dst/proto.css"
echo "built $dst"
