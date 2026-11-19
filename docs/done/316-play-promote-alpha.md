# Job 316: Play promote to closed testing as a draft

Merged as 3696581f (#559), with fixes 5da25542 (#561), c78ab09d (#562), d0793fcb (#563) and the
review 0 follow-up (next commit on main).

- `.github/workflows/play-promote.yml`: workflow_dispatch, `release` environment, keyless WIF as in
  release.yml. Inputs `version_code` (required), `track` (`alpha` only), `commit` (default on).
- `app/fastlane/Fastfile` lane `android promote_draft`: refuses any track but alpha; logs the
  edit's bundle list and leaves an unknown versionCode to Play's refusal; keeps alpha's other
  releases, replaces its draft (named with the versionCode); commits with
  `changesNotSentForReview`, or without it when Play requires that (supply's rescue); deletes its
  edit on failure; reads alpha back from a second, deleted edit and fails without the draft.
- `docs/RELEASE.md` section "Promote a build to closed testing"; DECISIONS "Job 316".

Verify: right after a release run, `gh workflow run play-promote.yml -f version_code=<build>
-f commit=false`, then the run log's "Before"/"After" lines; without `commit=false` it commits the
draft. Outcome: Play no longer had 1414 or 1415 by the time the lane worked ("could not be found"),
so alpha has no draft from this job; a validate-only run on 1422 passed (review 0). Details and run
URLs are in the job's ops summary and NEEDS_LEAD "Job 316".
