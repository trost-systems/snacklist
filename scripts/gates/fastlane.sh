#!/usr/bin/env bash
# The Gemfile.lock installs and the Fastfile parses (job 4); the Play listing lane's gate, edit
# and read-back against a fake Play client (job 480).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$REPO_ROOT/app"
bundle check >/dev/null || bundle install
bundle exec fastlane lanes
bundle exec ruby fastlane/test/play_listing_test.rb
