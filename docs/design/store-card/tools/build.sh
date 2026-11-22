#!/usr/bin/env bash
# Builds the preview: every file of the base deployment (older rounds keep their links), round SC under /store-card/,
# the app's fonts, and the overview's link. Usage: VERCEL_TOKEN=… tools/build.sh <out> [--base <dpl id>]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/../../.." && pwd)"
out="${1:?usage: build.sh <out> [--base <dpl id>]}"
base="dpl_Bwp6TTMjH1omf95D8dhyz9ijd3t1"
if [[ "${2:-}" == "--base" ]]; then base="$3"; fi
rm -rf "$out"
node "$here/tools/fetch-base.mjs" "$base" "$out"
mkdir -p "$out/store-card/fonts" "$out/store-card/sc/real"
cp "$here"/*.mjs "$here"/*.css "$out/store-card/"
rm "$out/store-card/verify.mjs"
cp "$here"/sc/index.html "$here"/sc/*.md "$here"/sc/measured.json "$out/store-card/sc/"
cp "$here"/sc/real/* "$out/store-card/sc/real/"
cp "$repo"/app/assets/fonts/*.ttf "$repo"/app/assets/fonts/OFL-*.txt "$out/store-card/fonts/"
node "$here/tools/link-overview.mjs" "$out"
