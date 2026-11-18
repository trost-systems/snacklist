#!/usr/bin/env bash
# Generated l10n matches the ARB files, format, analyze with infos as errors, unit and widget tests;
# the same for the Widgetbook (app/widgetbook/). --no-tests leaves the tests out (scripts/push-checks.sh).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
tests=1
[[ ${1:-} == --no-tests ]] && tests=0
require_ci_flutter
no_posthog_in_ci
cd "$REPO_ROOT/app"
flutter pub get --enforce-lockfile >/dev/null
flutter gen-l10n
git diff --exit-code -- lib/l10n || {
  echo "app/lib/l10n does not match the ARB files: run flutter gen-l10n in app/ and commit lib/l10n" >&2
  exit 1
}
dart format --output=none --set-exit-if-changed lib test || {
  echo "dart format would change the files above: run dart format lib test in app/ and commit" >&2
  exit 1
}
flutter analyze --fatal-infos
[[ $tests == 0 ]] || flutter test

# Job 52: the Widgetbook (app/widgetbook/, its own package) under the same rules; its tests render
# every story in light and dark. scripts/widgetbook.sh builds it for the web.
cd "$REPO_ROOT/app/widgetbook"
# pub's own message does not say which package's lock it refused.
flutter pub get --enforce-lockfile >/dev/null || {
  echo "flutter pub get --enforce-lockfile failed in app/widgetbook. After a dependency change in app/, run 'flutter pub get' in app/widgetbook and commit its pubspec.lock." >&2
  exit 1
}
dart format --output=none --set-exit-if-changed lib test || {
  echo "dart format would change the files above: run dart format lib test in app/widgetbook and commit" >&2
  exit 1
}
flutter analyze --fatal-infos
[[ $tests == 0 ]] || flutter test
