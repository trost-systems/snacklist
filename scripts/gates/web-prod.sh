#!/usr/bin/env bash
# The web app builds with the production config (what Vercel ships), into its own directory so
# it never replaces the e2e build in app/build/web.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
no_posthog_in_ci
cd "$REPO_ROOT/app"
flutter pub get >/dev/null
flutter build web --release --no-web-resources-cdn --wasm --output build/web-prod

# Job 28: one --wasm build holds both entry points; flutter_bootstrap.js picks the wasm one where
# the browser runs it (WasmGC, allow list) and main.dart.js everywhere else. Every web build
# (Vercel, e2e, fg sync) builds it this way.
out=build/web-prod
for file in main.dart.wasm main.dart.mjs main.dart.js; do
  [[ -s $out/$file ]] || { echo "web-prod: $out/$file is missing; build with --wasm" >&2; exit 1; }
done
for target in '"compileTarget":"dart2wasm"' '"compileTarget":"dart2js"'; do
  grep -q "$target" "$out/flutter_bootstrap.js" \
    || { echo "web-prod: flutter_bootstrap.js has no $target build" >&2; exit 1; }
done
for script in scripts/vercel.sh scripts/gates/e2e.sh .cursor/skills/verify-family-groceries/cli/sync.ts; do
  grep -Eq -- "(flutter build web|'web',).*--wasm|'--wasm'" "$REPO_ROOT/$script" \
    || { echo "web-prod: $script builds the web app without --wasm" >&2; exit 1; }
done

# Job 22 and 66: universal links and App Links read these two from app.hummlist.com/.well-known/;
# the build must copy them unchanged (vercel.json serves them as JSON), and Apple and Google
# drop a file that does not parse (test/app/deep_links_config_test.dart checks the contents).
for file in .well-known/apple-app-site-association .well-known/assetlinks.json; do
  cmp -s "web/$file" "$out/$file" || { echo "web-prod: $out/$file is missing or differs from web/$file" >&2; exit 1; }
  python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$out/$file" \
    || { echo "web-prod: $out/$file is not valid JSON" >&2; exit 1; }
done

# Job 33c (legal review H-02): the engine and every font load from our origin, never gstatic.com.
# The loader reads canvasKitBaseUrl from load(), the engine fontFallbackBaseUrl from initializeEngine().
for code in "const config = { canvasKitBaseUrl: '/canvaskit/', fontFallbackBaseUrl: '/fonts/' };" \
  'config,' 'initializeEngine(config)'; do
  grep -qF "$code" "$out/flutter_bootstrap.js" \
    || { echo "web-prod: flutter_bootstrap.js lacks: $code (job 33c: engine and fonts from our origin)" >&2; exit 1; }
done
for file in canvaskit.wasm chromium/canvaskit.wasm skwasm.wasm skwasm_heavy.wasm; do
  [[ -s $out/canvaskit/$file ]] || { echo "web-prod: $out/canvaskit/$file is missing" >&2; exit 1; }
done
fonts="$(grep -ohE '\b[a-z0-9]+/v[0-9]+/[A-Za-z0-9._-]+\.woff2' "$out/main.dart.js" | sort -u)"
(($(wc -l <<<"$fonts") > 100)) || { echo "web-prod: main.dart.js names only $(wc -l <<<"$fonts") fonts" >&2; exit 1; }
missing="$(while read -r font; do [[ -s $out/fonts/$font ]] || echo "$font"; done <<<"$fonts")"
[[ -z $missing ]] || { echo "web-prod: the engine fetches fonts app/web/fonts lacks; run scripts/web-fonts.sh:" >&2; echo "$missing" >&2; exit 1; }

# Job 169b: the join page (app/web/join) ships in every build, and its config.js defaults are the
# production project of environment.dart's defaults (scripts/join-config.sh overrides both together).
for file in join/index.html join/join.js join/join.css join/tokens.css join/config.js; do
  [[ -s $out/$file ]] || { echo "web-prod: $out/$file is missing" >&2; exit 1; }
done
for name in supabaseUrl publishableKey; do
  value="$(sed -n "s/^export const $name = '\(.*\)';$/\1/p" "$out/join/config.js")"
  if [[ -z $value ]] || ! grep -qF "'$value'" lib/app/environment.dart; then
    echo "web-prod: join/config.js $name '$value' is not environment.dart's default" >&2
    exit 1
  fi
done
