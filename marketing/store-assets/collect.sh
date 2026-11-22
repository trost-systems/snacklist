#!/usr/bin/env bash
# Copies the finished store screenshots (marketing/store-screenshots/out) and App Store app previews
# (marketing/store-previews/out) next to this script, where Ops finds them, and writes SHA256SUMS.
# Nothing is uploaded anywhere. Run it after scripts/store-screenshots.sh and
# marketing/store-previews/make-previews.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
shots="$here/../store-screenshots/out" previews="$here/../store-previews/out"
[[ -d $shots/de-DE && -d $previews/de-DE ]] || { echo "collect: run store-screenshots.sh and make-previews.sh first" >&2; exit 1; }
rm -rf "$here/screenshots" "$here/previews"
mkdir -p "$here/screenshots" "$here/previews"
for locale in de-DE en-US; do
  cp -r "$shots/$locale" "$here/screenshots/$locale"
  cp -r "$previews/$locale" "$here/previews/$locale"
  # The canonical icon from the generator (design/app-icon/build.mjs), byte for byte, not compose's re-encode.
  cp "$here/../store-icons/play-512.png" "$here/screenshots/$locale/play/icon-512.png"
done
# Held frames (Legal rule, N-358) never reach the folder Ops uploads from.
held="$(find "$here/screenshots" "$here/previews" -name '*.BLOCKED.*' -o -name '*.ON-HOLD.*' | sort)"
if [[ -n $held ]]; then
  echo "collect: leaving out the held files:" >&2
  while read -r f; do echo "  ${f#"$here"/}" >&2; rm -f "$f"; done <<<"$held"
fi
cp "$shots/CAPTIONS.md" "$shots/summary.md" "$shots/manifest.json" "$here/screenshots/"
(cd "$here" && find screenshots previews -type f ! -name '*.sha256' | sort | xargs sha256sum >SHA256SUMS)
echo "collect: $(wc -l <"$here/SHA256SUMS") files, $(du -sh "$here" | cut -f1)"
