#!/usr/bin/env bash
# Builds round AI's page into <out>/app-icon/ai/ (images and measured.json from tools/render.mjs).
# Usage: build.sh <out dir>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:?usage: build.sh <out dir>}/app-icon/ai"
mkdir -p "$out"
node "$here/tools/render.mjs" "$out" >/dev/null
cp "$here"/{index.html,page.css,page.js,copy.js,options.js} "$out/"
cmp -s "$out/measured.json" "$here/measured.json" || { echo "measured.json differs from a fresh run: node tools/render.mjs <dir> and copy it" >&2; exit 1; }
echo "built $out"
