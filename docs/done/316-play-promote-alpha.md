# Job 316: Play promote to closed testing as a draft

Merged as: next commit on main (PR "Play promote: an uploaded build as alpha draft (job 316)").

- `.github/workflows/play-promote.yml`: workflow_dispatch, `release` environment, keyless WIF as in
  release.yml. Inputs `version_code` (required), `track` (`alpha` only), `commit` (default on).
- `app/fastlane/Fastfile` lane `android promote_draft`: refuses a versionCode missing from the
  bundle library and any track but alpha; keeps alpha's other releases, replaces its draft; commits
  with `changesNotSentForReview`; reads alpha back from a second, deleted edit and fails without the
  draft.
- `docs/RELEASE.md` section "Promote a build to closed testing"; DECISIONS "Job 316".

Verify: `gh workflow run play-promote.yml -f version_code=1414 -f track=alpha`, then the run log's
"Before"/"After" lines; `-f commit=false` reads the tracks again without changing anything.
Tested here against a stubbed Play client (keep 1368, replace old draft, unknown versionCode,
non-alpha track, validate-only); the real run is in the job's ops summary.
