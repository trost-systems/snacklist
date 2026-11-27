# Releases

Every green merge to `main` reaches the internal testers with no human step
(Peter, 2026-10-29: "internal testing / test flight should be pushed on every
merge to main"). The Release workflow (`.github/workflows/release.yml`) starts
when CI (`ci.yml`) finishes green on a push to `main` and ships the newest
green `main` commit:

- iOS to TestFlight, internal group "Familie" only. No external groups, no
  Beta App Review, no App Store submission.
- Android to the Play internal testing track.

The public web app moves with these runs once a store upload succeeds:
`https://app.snacklist.app` and `https://app.hummlist.com` follow the same commit (via the
`release` branch).
`main` itself is also on `https://preview.app.hummlist.com`
([`DEPLOY.md`](DEPLOY.md), section "Web app").

Both platforms get the same build number in a run. The one-time store setup
that needs a browser is in [`NEEDS_LEAD.md`](NEEDS_LEAD.md); decisions are in
[`DECISIONS.md`](DECISIONS.md), sections "Job 23" and "Job 30".

## Public releases

There is no public release path yet: no Play production track, no App Store
review, no external TestFlight group, and the Paid Applications agreement
stays unaccepted. Nothing in this workflow promotes a build beyond the
internal testers. A public release will be a separate, later step with a
manual gate: a build that the internal testers have had, after a full
end-to-end pass on it, weekly or more often once that is quick and reliable.
It needs its own job and Peter's go.

Update, 26 Nov 2026: Ops put build 1541 (1.0.0) on Play production by hand in
Play Console; it is approved and held by managed publishing until the
1 December launch (Peter MP1). No workflow touches production. The staged
Play listing goes out with that publish, see [Store listing upload](#store-listing-upload).

The reliability beta from 2026-11-15 (job 183) is not a public release.
Beta testers get the same internal builds: TestFlight group "Familie" and
the Play internal track, uploaded after every green `main` as above. Work
keeps merging during the beta (no freeze); unfinished features stay behind
flags.

The store rating prompt (job 155, `app/lib/review/`) fits this:

- iOS: no define. Every iPhone release build may ask, and StoreKit never
  shows the prompt in TestFlight, so the testers' build is the one App Store
  review gets, unchanged.
- Android: a Play internal install can show the prompt, so only a build with
  `--dart-define=STORE_RELEASE=true` asks. The production AAB is the commit
  the testers had, built once more with that define (and a new version
  code); the internal-track builds never pass it. Promoting the internal AAB
  unchanged also works: then the Android app never asks.

What is public is recorded in [`releases/releases.json`](../releases/README.md),
empty until the first public release. The public release step, once it exists,
must end like this: after both stores have accepted the build, it calls the
**Public release record** workflow
(`.github/workflows/public-release-record.yml`, `workflow_call` or a
dispatch) with `version`, `sha` (the released `main` commit), `build` and
`dry_run: false`. The workflow computes the release's day and git stats
(`scripts/release/record.mjs`), commits the entry to `main` as
`Release <version>: public release record` and pushes it. That push
redeploys snacklist.app, whose guides then show what the new version has
([`DEPLOY.md`](DEPLOY.md), "Guides site"). It starts no store upload: a push
with the workflow's token starts no other workflow, and `plan.sh` counts only
`app/` and `release.yml` as app changes. A dispatch defaults to
`dry_run: true`, which prints the entry and changes nothing.

### Changelog and store texts (job 39)

Each public release has a user-facing changelog, collected from the
`## Changelog` notes in the PRs ([`CHANGELOG.md`](CHANGELOG.md)). The order:

1. **Cut.** Choose the version and the `main` commit, then run
   `node scripts/release/changelog.mjs draft --version X --sha S`. It writes
   `releases/changelog/X.json` with the items since the previous public
   release and the "What's new" texts: App Store up to 4000 (counted as UTF-8
   bytes), Google Play up to 500 Unicode characters, in German and English.
   Commit the draft in a PR.
   The dry run (`--dry-run`) also lists the items held back by a flag or a
   hold, and the items of `releases/changelog/pending.json` whose gate is
   open now (job 40, [`CHANGELOG.md`](CHANGELOG.md), "Gated items").
2. **Review.** Peter reviews and edits the wording in that PR. He fills in the
   headline (`title`) and approves the release; a public release needs his yes
   anyway. He also checks:
   - **Held items** (the draft's `held`): is each one still not out for
     everyone? If a flag reached 100 % or a hold is over (Alexa certified),
     the same PR sets it in `releases/flags.json` and redrafts with `--force`.
   - **The override**, if the version has one
     (`releases/changelog/X.override.md`, the 1.0 launch text): he approves
     it by deleting its `status: draft` line. Until then `record.mjs add`
     refuses to record the version.
   After any edit, run
   `node scripts/release/changelog.mjs store --version X`. Preview builds of
   the site show the draft on the changelog page with the banner
   "Entwurf, noch nicht im Store". Production does not show it.
3. **Submit.** The store submission uses the draft's `store.app_store` and
   `store.play` texts as "What's new". That step does not exist yet: no
   metadata upload, no review submission.
4. **Publish.** After both stores accept the build, the public release step
   runs the Public release record workflow (above). `record.mjs` puts the
   draft into the new entry as `changelog` and deletes the draft file (and
   the override) in the same commit. In that commit it also writes the
   still-held items to `releases/changelog/pending.json`. That push to `main` redeploys snacklist.app, so the changelog
   page shows the version only once it is live in the stores.

Without a draft, the release is recorded without a changelog: the workflow
warns, and the page shows "Fehlerbehebungen und Verbesserungen.". TestFlight's
"What to Test" is written from the same notes, per upload, for the internal
testers ([What to Test](#what-to-test)).

## Store release checklist

### Before submitting a public build

- [ ] Peter's go for the public release (see [Public releases](#public-releases)).
- [ ] App Privacy (Apple) and Data safety (Play) cover every data type the build sends; Snacklist Ops confirms.

### Before launch day: Play listing preflight

- [ ] **By 30 November 2026, Lead:** `gh workflow run play-listing.yml -f mode=preflight -f published_version_code=1541`. It opens no edit and changes nothing. It must log `Production releases: APPROVED_NOT_PUBLISHED 1541` and pass ([Store listing upload](#store-listing-upload)). If it fails, the launch-day upload would fail too: fix that first.

### Launch day, before the Play publish (Ops)

- [ ] Preflight once more (as above). It must still show `APPROVED_NOT_PUBLISHED 1541`.
- [ ] **Required: Play listing upload with read-back** (Peter K1, Legal LK1). From 1 December 2026 00:00 Berlin, before 1541 is published: `gh workflow run play-listing.yml -f mode=upload -f published_version_code=1541 -f with_held_release=true`. The run must end with "Play's listing equals the repo text". It fails on any field whose sha256 differs.
- [ ] At the planned publish: if Google has approved the listing change, publish 1541 and the listing together in the Publishing overview. If it has not, publish 1541 alone as planned (MP1), and publish the listing change once Google approves it. If the held-release upload did not happen, run it after the publish without `with_held_release`.

### After both stores have the build live

- [ ] `gh workflow run play-listing.yml -f mode=check` passes once the listing change is published: Play's de-DE and en-US listing and the public store pages equal the repo files by sha256, and the de-DE page no longer has „Kostenlos, ohne Werbung, für den ganzen Haushalt.“ If only the store page part fails on the US runner, use the manual check in [Store listing upload](#store-listing-upload).
- [ ] Only after that check passes: the sale opens ([`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md) 5.4, `premium_offer`). Until the staged listing is live, nobody outside the internal testers may be able to buy Premium (Legal LK1).
- [ ] Public release record workflow ran (see above).
- [ ] Flag rollouts that wait for a live store build (list below): open each, refresh its dates, get Legal's hash GO, merge.

### Flag rollouts waiting for a live store build

| Flag | PR / job | Needs before merge |
| --- | --- | --- |
| `report-content-entry` (in-app Report content, RC2, #524) | job 333 rollout PR | Both public store builds contain #524 and are live; Play Data safety "Other user-generated content" lists the purpose "Fraud prevention, security, and compliance" (Ops, Peter's DS1 yes; Apple already OK); N-279 dates on impressum, imprint, datenschutz, privacy set to the merge date; Legal's hash GO on the final head (Legal review 2026-11-21, Addenda B and C). |

When a flagged feature's rollout depends on a public build, add a row here.

## When a run ships

Three events start a run:

| Event | When | Ships |
| --- | --- | --- |
| `workflow_run` | CI finished on `main` | The newest green `main` commit. Only a green CI run on a push to this repository starts the plan; after a red one (or a fork's PR from a branch named `main`, or a dispatched CI run) every job is skipped and nothing ships. |
| `schedule` | Mondays 03:00 UTC | The same as `workflow_run`. A catch-up: it ships nothing when the testers have the newest green `main`, but re-ships before TestFlight's 90-day expiry or after Apple expired the builds, and picks up a commit whose `workflow_run` event never came. |
| `workflow_dispatch` | By hand | The `main` commit it was started on, which must be green ([Run it by hand](#run-it-by-hand)). Like the automatic runs, a successful upload also moves the production web app. |

The `plan` job gathers facts (`scripts/release/plan.sh gather`) and decides
(`plan.sh decide`, a pure function with fixture tests in
`scripts/release/test.sh`).

Which commit: `gather` walks `main` from its tip (fetched when the plan runs,
so possibly newer than the commit whose CI started the run) back to the last
upload, reading the newest `ci.yml` push run of each commit (a green rerun
counts). An automatic run takes the first green commit: newer commits whose
CI still runs ship with their own run, red ones never ship. A dispatch takes
the tip only.

Whether it ships: the first rule that matches wins.

| Facts | Result |
| --- | --- |
| Dispatch: the newest `ci.yml` push run on the commit has not finished, or did not conclude `success` | Skip with a notice. `force` does not override this: only green `main` ships. |
| Automatic: no green commit since the last upload, and no upload ever | Skip. |
| The build number is not above TestFlight's highest build | Fail, naming `BUILD_NUMBER_OFFSET`. |
| `upload` is off | Build, sign and validate (dry run). |
| `force` is on | Ship. |
| No earlier upload run | Ship. |
| A newer green commit than the last upload, and something under `app/` or `release.yml` changed since it | Ship. |
| TestFlight has no installable build (all expired) | Ship (again). |
| The last upload run is 60 or more days old | Ship (again), before TestFlight's 90-day expiry. |
| A newer green commit, but only docs, CI, scripts or the backend changed | Skip: the testers already have this app. |
| Otherwise | Skip with the notice "main is unchanged since the last upload". |

The last two skips set the plan output `current`, which closes the failure
issue. When the commit that started the run is older than the last upload
(its CI finished after a newer commit's), the notice says so.

The last upload run is the newest successful Release run on `main` whose
`Uploaded <sha>` job succeeded; the job's name carries the commit it shipped,
since a `workflow_run` run's own commit is `main`'s tip when it started.
(Runs before job 30 named it `Uploaded` and shipped their own commit.) That
job runs only after a real upload, so dry runs and skipped runs never count.
The workflow needs no tags and no `contents: write` for this; `actions: read`
on the plan job is enough.

### Merge bursts

The workflow's concurrency group `release` runs one Release run at a time
and never cancels one in progress, so an upload always finishes. GitHub keeps
at most one run pending and cancels the older pending run when a newer one
arrives. Every run picks the newest green commit when its plan starts, so
whichever run survives ships everything merged so far: three quick merges
give one or two uploads, never an older commit after a newer one. CI on
`main` runs per commit (`ci.yml` groups push runs by SHA), so an older
commit's CI can finish after a newer one's; its run then finds the newer
commit already shipped and skips. A run after a CI run that was no push (the
nightly one, a dispatch) or not green ships nothing and queues in a group of its own, so it
never replaces a pending run that would ship (job 308).

## Run it by hand

A `workflow_run` or scheduled run has no inputs; the plan job gives it the
dispatch defaults, so all three events take the same path from there. The log
line `Release plan (workflow_run): platform=both upload=true force=false
main=<sha> trigger=<sha>` (or `(schedule)`, `(workflow_dispatch)`) shows it.

```bash
gh workflow run release.yml                       # main's tip, if green and not shipped yet; upload also moves the web app
gh workflow run release.yml -f force=true         # ship even if the testers already have it
gh workflow run release.yml -f upload=false       # build, sign and validate only
gh workflow run release.yml -f platform=android   # one platform
```

| Input | Default | Meaning |
| --- | --- | --- |
| `platform` | `both` | `both`, `ios` or `android`. |
| `upload` | `true` | Off: iOS builds, signs and runs `altool --validate-app`; Android builds, signs, checks the signer and, once Play is set up, runs the upload with `validate_only`. Nothing is published. |
| `force` | `false` | Ship even if the testers already have this app (main unchanged, or only non-app files changed). |
| `simulate_failure` | `false` | Fail the plan job on purpose, to test the failure issue. |

A dispatch that finds `main` unchanged skips, so it does not move
the production web app either; to publish the web app of a commit the testers
already have, use `force=true` (a new store build of the same commit) or the
manual push in [`DEPLOY.md`](DEPLOY.md), section "Web app".

The `release` environment allows deployments from `main` only, so a run on
another branch fails at its first job. `workflow_run` and scheduled runs
always run on `main`.

## Failures

An automatic run (`workflow_run` or `schedule`) that fails opens the issue
"Internal release failed" with the run link, the commit, the failing job
(`plan`, `ios`, `android`) and what reached TestFlight and Play internal
("may not" where a stopped job cannot tell). While it is open, every further
failed run comments on it instead of opening another, so a broken pipeline
during a day of merges is one issue with one comment per run. The next run
that uploads, or that finds the testers on the newest green `main`
(`current`), closes it. Dry runs never touch it. A failed dispatch does not
open the issue, since whoever started it watches the run; `simulate_failure`
does (and its body also says whether the production web app moved). Until job 30
the issue was "Weekly release failed" (#53, closed). Watch the repository's
issues (Watch, Custom, Issues) to get these.

A red CI on `main` starts no release and opens no issue here: CI itself is
the signal, and the next green commit ships.

What to do, by failing job:

- `plan`, "CI concluded failure" (dispatch only): fix `main`; the merge that
  fixes it ships by itself once its CI is green.
- `plan`, "Profile ... is INVALID": see [Capabilities](#capabilities).
- `plan`, "Build number ... is not above": a build was uploaded outside this
  workflow. Raise `BUILD_NUMBER_OFFSET` in `release.yml` so that
  `offset + run number` is above it.
- `ios`, upload: an Apple outage gets one retry, after the lane has looked
  for the build in App Store Connect for 10 minutes (a first attempt may have
  arrived after all). Check
  <https://developer.apple.com/system-status/> and rerun the failed jobs, but
  only of the newest Release run: a rerun keeps its run number and its
  commit, so rerunning an older run after a newer one shipped would upload an
  older build. For an older run, let the next merge (or a dispatch) ship.
- `ios`, "Wait for TestFlight processing": `INVALID` or `FAILED` means Apple
  rejected the binary; Apple's email to the account holder says why. A build
  still processing after 45 minutes usually turns `VALID` later; check
  TestFlight before rerunning.
- `ios`, "VALID but already expired": see
  [TestFlight builds expired](#testflight-builds-expired).
- `android`, "is signed by ..., not by the upload key": `ANDROID_KEYSTORE_BASE64`
  holds another key; restore it from `~/groceries-ops/secrets/android/`.
- `android`, upload: Play's error names the cause. "Only releases with status
  draft may be created on draft app" means `PLAY_RELEASE_STATUS` must be
  `draft` until the app leaves draft (`NEEDS_LEAD.md`, L3).
- `web` (`Web production`, after `Uploaded`), push rejected: `release` holds a commit that is
  not an ancestor of this one (someone force-pushed it), or a branch rule
  blocks the push (there must be none on `release`). The issue says which
  stores got the build; check what `release` holds, then `git push --force
  origin <sha>:refs/heads/release` once you are sure, or let the next release
  move it.

### TestFlight builds expired

On 2026-10-26 at 13:14:02 to 13:14:03 UTC, Apple expired every unexpired
TestFlight build of the team at once: Hummlist 1002 (uploaded the day
before), build 1001 of the old app record (`6826907810`) and all 65 builds of
another app of the team that were younger than 90 days (uploaded since
2026-09-13). No build of ours was expired by hand, no Beta App Review
submission exists, no newer build replaced them, and the certificate, profile
and membership-bound API access kept working. Other teams report the same
mass expiry on Apple's developer forums (thread 813703: January, July and
August 2026); Apple's TestFlight team acknowledged an investigation and has
not named a cause.
`DECISIONS.md`, Job 23, has the query results.

The next run handles it: when TestFlight has no installable build, the
newest green commit ships again even if the testers had it (rule above), so
testers have a build again after the next merge, or the next Monday's
catch-up at the latest. To get one sooner, dispatch the workflow with the
defaults. If a new build comes out expired too, the run fails ("VALID but
already expired"): then the account holder opens a case with Apple Developer
Support (developer.apple.com/contact, TestFlight) quoting the build number;
nothing in the account or the repo fixes it.

## App identity

The app is "Snacklist", bundle ID and Android `applicationId`
`com.snacklist.app` since job 174 (decision B2). From job 20 it was
"Hummlist", `com.hummlist.app`. `app/fastlane/Appfile`, `Matchfile` and
`APP_ID` in the `Fastfile` name it. Release runs build Snacklist only; the
branch `hummlist-maint` keeps the code from before the rename for a Hummlist
hotfix.

Since job 63 the iOS app embeds a second bundle, the Home Screen widget
extension `com.snacklist.app.HomeWidget` (Xcode target `HomeWidget`,
[HOME_WIDGETS.md](HOME_WIDGETS.md)). It is signed with its own App Store
profile; `Matchfile` and `WIDGET_ID` in the `Fastfile` name it. The app and
the extension share the App Group `group.com.snacklist.app`. The extension
takes the app's version and build number (`FLUTTER_BUILD_NAME`,
`FLUTTER_BUILD_NUMBER`), as App Store Connect requires.

- iOS: App Store Connect app "Snacklist", Apple ID `6832756448`, SKU
  `snacklist-ios`, primary language de-DE.
- Android: Play app "Snacklist" (app ID `4975647801932295032`, package
  `com.snacklist.app`). It has no upload yet: the first bundle goes up by
  hand (the run's artifact `snacklist-<build>-aab`), and until then Play
  refuses the upload runs.
- Hummlist, until it retires: App Store Connect app "Hummlist", Apple ID
  `6826922741`. Its internal group "Familie" had access to all builds, so
  every `VALID` build reached it. The old app record (`6826907810`,
  `com.petertrost.familygroceries`) gets no further builds. Play app
  "Hummlist" (app ID `4972374295718364245`), created by the Lead on
  2026-10-27. The Lead uploaded the first bundle (0.1.0, version code 1003,
  built on the box) by hand to internal testing, list "Familie", on
  2026-10-28 and set `PLAY_RELEASE_STATUS` to `completed`; from then on every
  upload run rolled out to internal testers until job 174.

## Promote a build to closed testing

`release.yml` uploads only to the internal track. To give closed testing
(`alpha`, tester list "Snacklist Beta") a build Play already has, the Play
promote workflow (`.github/workflows/play-promote.yml`, lane
`android promote_draft`) sets that versionCode as alpha's draft release:

```bash
gh workflow run play-promote.yml -f version_code=<versionCode> -f commit=false   # validate only, first
gh workflow run play-promote.yml -f version_code=<versionCode> -f track=alpha
```

Run it right after the release run that uploaded the build, and check with
`commit=false` first. Observed in job 316, not documented by Google: the Play
API stops offering an internal bundle once newer ones replace it. Its edit
listed build 1414 at 07:59 UTC on 2026-11-19; by 08:53 UTC, after Release run
411 had uploaded 1421, Play refused it with "The following APK version codes
could not be found", and 1415 too. When Play gives that answer, add the build
by hand in Play Console: Closed testing, alpha, Create release, Add from
library, and save it as a draft without rolling it out.

It never uploads a bundle, never touches production and creates only a draft,
which the commit neither sends for review nor rolls out. The commit sets
`changesNotSentForReview`; when Play answers "Changes are sent for review
automatically", supply commits again without it, as release.yml's uploads
always do. Alpha's other
releases stay, so its testers keep their build until someone rolls the draft
out in Play Console; an older draft is replaced. The release notes are copied
from a release that already carries the versionCode (internal first), else the
draft has none. Play refuses a versionCode it does not have when the lane
sets the track or at validate or commit; the commit is atomic, so a refused
run changes nothing, and the lane deletes its edit. The draft's name carries
the versionCode, such as `0.1.0 (1422)`, so it differs from a live release of
the same version. The log lists the edit's bundles and every track before, and alpha read back afterwards from a
second edit that is deleted; the run fails if alpha then has no draft with
the versionCode. Like a release run, it works from `main` only (the `release`
environment).

## Store listing upload

`release.yml` never uploads the store listing (`android internal` skips it). The
Play listing text staged in `app/fastlane/metadata/android/<locale>/`
(`title.txt`, `short_description.txt`, `full_description.txt`; Legal owns the
words, [`store/LISTING.md`](store/LISTING.md)) goes up with the Play listing
workflow (`.github/workflows/play-listing.yml`, lanes `android listing` and
`android listing_check`):

```bash
gh workflow run play-listing.yml -f mode=preflight -f published_version_code=1541  # production's state, no edit, any day
gh workflow run play-listing.yml                                                   # validate only
gh workflow run play-listing.yml -f mode=upload -f published_version_code=1541 -f with_held_release=true   # 1 Dec, before the publish
gh workflow run play-listing.yml -f mode=upload -f published_version_code=1541                            # or: after the publish
gh workflow run play-listing.yml -f mode=check                                     # read-back, any time
```

It goes out with the production release, never on its own before it (Peter
K1, 26 Nov 2026). Production build 1541 is approved and held by managed
publishing until 1 December. Only Play Console's Publishing overview publishes
it; the API cannot. So the listing gets its own edit, in one of two orders:

1. **With the held release (default on 1 December).** From
   `held_release_from` (default 1 December 2026 00:00 Europe/Berlin), with
   `with_held_release=true`. Google reviews the listing change. Once it is
   approved, one click in the Publishing overview publishes 1541 and the
   listing together.
2. **After the publish.** Without `with_held_release`, once 1541 is published.
   The listing then goes live a Google review and a second publish later.

Either way, the sale waits until `check` passes (Legal LK1). If Google has
not approved the listing by the planned publish time, publish 1541 alone as
planned (MP1); the listing follows, and the sale moves to when `check` passes.
That is the risk to the sale time T ([`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md)
5.3a, [`NEEDS_PETER.md`](NEEDS_PETER.md) "Job 480").

The gate reads production's releases from Play's releases endpoint
(`tracks/production/releases`) before it opens any edit. That endpoint gives
each release's lifecycle state: `APPROVED_NOT_PUBLISHED` while managed
publishing holds it, `PUBLISHED` once it is out. An upload refuses, and opens
no edit, unless the release carrying `published_version_code` is:

- with the held release: `APPROVED_NOT_PUBLISHED`, and it is
  `held_release_from` or later. A held release only exists while managed
  publishing is on, so this state also shows the switch is on.
- after the publish: `PUBLISHED`.

The public store page plays no part in an upload. The store watch has read
`APPROVED_NOT_PUBLISHED` for 1541 from the same endpoint since 25 Nov 2026.

What a run does:

- **preflight**: no edit. Logs production's releases and, for each upload
  path, whether an upload would commit now or what stops it. Fails unless the
  named build is held or published.
- **validate** (default): one edit sets every staged locale's title, short and
  full description, validates the edit and deletes it. Nothing changes on Play.
  It logs each locale's full description sha256 and whether an upload would
  refuse now. Before launch day, use preflight instead: it needs no edit at all
  (Peter K1).
- **upload** (`RELEASE_UPLOAD=true`): the same edit, committed, then a second
  edit reads every field back and the run fails unless each equals the repo
  file. The video link stays as it is. No bundle, track, release notes, image
  or screenshot is touched. A locale folder holding anything else (images,
  `video.txt`) refuses the run: none is staged, and LISTING.md and Legal N-354
  decide when one may be.
- **check**: reads Play's listing in an edit it deletes, and each locale's
  public store page (de-DE with `hl=de&gl=DE`, en-US with `hl=en&gl=US`), and
  fails unless both equal the repo text. The page renders each line break as
  `<br>`, which maps back, so it is compared exactly and its sha256 is logged
  next to the repo's. A failure says whether the text differs only in
  whitespace or in its words. The de-DE page must not have „Kostenlos, ohne
  Werbung, für den ganzen Haushalt.“ (Legal LK1). If the API read-back matches
  and the page differs only in whitespace, Play renders the text differently
  from how the API stores it; Lead decides, with Legal, whether that closes LK1.
  The page is fetched from a US GitHub runner. If Play answers it differently
  there (the app is not offered in the US), check by hand from Germany:
  `curl -s 'https://play.google.com/store/apps/details?id=com.snacklist.app&hl=de&gl=DE'`,
  read the description with `PlayListing.public_description` (in `app/`:
  `ruby -r ./fastlane/play_listing -e 'print PlayListing.public_description(File.read(ARGV[0]))' page.html | sha256sum`),
  and compare it with the repo hash below. Lead records the result in the
  release notes of the day; it then stands in for the page part of `check`.

The hash is Legal's: sha256 of the file's text without its trailing newline,
`head -c -1 app/fastlane/metadata/android/de-DE/full_description.txt | sha256sum`
(each file ends in exactly one newline). The commit sends the listing to
Google's review; with managed publishing on, Play holds the approved change
until someone publishes it in the Publishing overview. If Play refuses to send
changes for review from the API, supply commits them without review; Play
Console then shows the change as not sent, and someone sends it in the
Publishing overview. An upload whose read-back fails has still committed: the
log says so, and running it again sends the same text. Until `check` passes, the Premium purchase screen stays off (Legal
LK1, [Store release checklist](#store-release-checklist)). Play keeps one edit
current: a Release run that commits its internal upload while the listing edit
is open makes Play refuse the listing commit, and a listing commit does the same
to a Release run's open edit. The refused run deletes its edit and fails;
running it again is safe. Start the listing run when no Release run is
uploading (`gh run list --workflow release.yml --status in_progress`). A shared
concurrency group would not help: GitHub cancels a pending run when a third
one queues in the same group, which would drop a Release upload.
Like a release run, it works from `main` only (the `release` environment).

## Lanes

Run lanes from `app/` with `bundle exec fastlane <platform> <lane>`.

| Lane | What it does |
| --- | --- |
| `ios certificates` | Creates or renews the distribution certificate and profiles in the match repo. Run by the manual Certificates workflow only; the team keeps its three distribution certificates, so don't run it. |
| `ios preflight` | Fails if either App Store profile (the app's, the widget's) is not `ACTIVE`, naming the ones that are not; writes TestFlight's highest build number and whether any build is installable to `TESTFLIGHT_JSON`. The plan job runs it. |
| `ios beta` | Installs the certificate and both profiles from match (read-only), signs `Runner` and `HomeWidget` manually, each with its own profile, runs `flutter build ipa`. `RELEASE_UPLOAD=true` uploads to TestFlight (internal only, one retry), otherwise `altool --validate-app` validates the IPA. |
| `ios wait_processing` | Sets What to Test (de-DE and en-US) as soon as the build shows up (a refusal only warns), then polls until it is `VALID` (at most `WAIT_MINUTES`, 45). Fails on `INVALID`, `FAILED`, an expired build or two API errors in a row. |
| `ios renew_profile` | Regenerates both App Store profiles (every identifier in the `Matchfile`) with the existing certificate `GN85KDC962` and pushes them to the match repo ([Capabilities](#capabilities)). |
| `android build` | `flutter build appbundle`, signed with `android/key.properties`. |
| `android play_access` | Gets a Google token for the service account (fails if that does not work), then tries to open a Play edit; writes `ok` or Play's refusal to `PLAY_ACCESS_FILE`. |
| `android internal` | Uploads the AAB to the `internal` track with `PLAY_RELEASE_STATUS`, or validates it only (`RELEASE_UPLOAD` not `true`). Uploads no listing, changelog or images. The listing goes up with `android listing`. |
| `android listing` | Sets the staged Play listing text (title, short and full description of each locale) in one edit; with `RELEASE_UPLOAD=true` commits it only when production's release `PLAY_PUBLISHED_VERSION_CODE` is `PUBLISHED`, or, with `PLAY_LISTING_WITH_HELD_RELEASE=true`, `APPROVED_NOT_PUBLISHED` and it is `PLAY_LISTING_HELD_FROM` or later, then reads it back and fails on any difference; otherwise validates and deletes the edit. [Store listing upload](#store-listing-upload). |
| `android listing_check` | Read only: Play's listing and the public store pages must equal the repo text. |
| `android listing_preflight` | No edit: production's releases and which listing upload path would commit now; fails unless `PLAY_PUBLISHED_VERSION_CODE` is held or published. |
| `android promote_draft` | Sets `VERSION_CODE` (already in Play's bundle library) as the draft release of `PROMOTE_TRACK` (`alpha` only), keeping the track's other releases; commits with `PROMOTE_COMMIT=true`, else validates only. [Promote a build to closed testing](#promote-a-build-to-closed-testing). |

The lint gate runs `scripts/release/test.sh` and shellchecks
`scripts/release/`; CI's `fastlane` job checks that the Gemfile.lock installs
and the Fastfile parses, and runs `app/fastlane/test/play_listing_test.rb` (the
listing lane's gate, edit and read-back against a fake Play client, and Play's
limits on the staged text). The lint gate's `check.mjs` holds the same limits.

## What to Test

`node scripts/release/changelog.mjs notes --lang <de|en> --previous-sha <last
upload> --sha <shipped commit>` writes the TestFlight notes for the commits
`main` took since the last upload's commit (one `<PR title> (#n)` commit per
PR), newest first, at most 12 lines. Each commit gives:

- its `## Changelog` items (`docs/CHANGELOG.md`) in the note's language, so
  testers read the same sentences the stores and snacklist.app get, `flag:`
  and `hold:` items included;
- nothing when the section says `none`;
- its title, without the `Job <n>:` prefix, PR number and anything that looks
  like an e-mail address, when it has no section (before job 39).

The lane removes what Apple rejects (emoji, `<`) and cuts to 4000 bytes; if
App Store Connect still refuses the notes, the run warns and stays green,
since the build reached the testers anyway. de-DE gets a German heading,
en-US an English one. Play gets no release notes (`skip_upload_changelogs`;
job 14 owns store metadata).

The first upload (Release run 11, build 1021) had no earlier upload to start
from, so the script took the last 20 `main` commits, and after the filters
only "rename the app to Hummlist (com.hummlist.app)" was left. That note was
a one-off: from build 1021 on, every run lists the PRs since the previous
upload.

Until job 167 the notes were PR titles filtered by a word list. Build 1201
(2026-11-07) told testers about "nexus.hummlist.com: ops control room
dashboard" and a privacy-page PR, and the word "e2e" hid the app fix that
build was for. `docs/screenshots/167/notes-before-after.txt` shows both
versions of today's notes.

### Internal work stays out

A commit is internal, and gives no note and no changelog item, when one of
these holds (`internalReason` in `scripts/release/changelog.mjs`, job 167):

1. **It changes nothing that reaches users.** At least one changed path must be
   on the allowlist and not on the denylist.
   - Allowlist: `app/lib/`, `app/l10n/`, `app/assets/`, `app/android/`,
     `app/ios/`, `app/web/`, `app/pubspec.yaml`, `app/pubspec.lock`,
     `supabase/migrations/`, `supabase/functions/`, `supabase/classifier/`,
     `alexa/`.
   - Denylist inside it: `test/`, `tests/`, `test_driver/`,
     `integration_test/` and `fastlane/` directories, `*_test.dart`,
     `*_test.ts`, `*.test.ts`, `*.test.mjs` and `*.md` files.
   So Nexus (`nexus/`), CI, `scripts/`, `docs/`, `e2e/`, `mcp-proxy/`,
   `analytics/`, the verify skills, the lint packs, the hz lanes and the site
   never show up.
2. **Its PR description has a paragraph `Changelog: skip`** (or
   `Changelog: internal`) outside HTML comments and code blocks. Put it
   above the `## Changelog` section. Use it for an internal change
   that touches an allowlisted path, such as a debug-only screen. It is not
   the `## Changelog` heading; that section still says `none` or lists items.
3. **It has no `## Changelog` section and its title starts with `docs:`,
   `ci:`, `chore:`, `test:`, `build:` or `style:`** (scope allowed), or
   `Revert "`.

The changelog draft applies the same rule and names each commit whose
items it left out, so the reviewer can add an item back by hand if users
see it after all.

## Secrets and variables

All live in the `release` environment (Settings, Environments, `release`;
deployments from `main` only). Values marked "variable" may also be secrets.

| Name | Kind | Used by | Value |
| --- | --- | --- | --- |
| `APPLE_TEAM_ID` | variable | iOS | `VCZSHMZY25`. |
| `MATCH_GIT_URL` | variable | iOS | SSH URL of the private certificates repo. |
| `MATCH_DEPLOY_KEY` | secret | iOS | Private SSH key; its public half is a deploy key on the certificates repo. |
| `MATCH_PASSWORD` | secret | iOS | Passphrase that encrypts the certificates repo. |
| `APP_STORE_CONNECT_API_KEY_ID` | secret | iOS | Key ID of the App Store Connect API key (`family-groceries-ci`). |
| `APP_STORE_CONNECT_ISSUER_ID` | secret | iOS | Issuer ID shown above the API keys list. |
| `APP_STORE_CONNECT_API_KEY_P8` | secret | iOS | Full text of the `AuthKey_<id>.p8` file. |
| `ANDROID_KEYSTORE_BASE64` | secret | Android | The upload keystore, base64-encoded. |
| `ANDROID_KEY_PROPERTIES` | secret | Android | The `key.properties` file (format below). |
| `PLAY_RELEASE_STATUS` | variable | Android | Unset: Play is not set up, no upload. `draft`: upload as a draft release (until the app leaves draft). `completed`: upload and roll out to internal testers. |
| `REVENUECAT_PURCHASES` | variable | both | Unset: no purchase screen ("bald verfügbar"). `true` at the paywall go-live ([`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md)). |
| `REVENUECAT_APPLE_API_KEY` | secret | iOS | RevenueCat's public App Store SDK key (`appl_…`). Without it the build sells nothing. |
| `REVENUECAT_GOOGLE_API_KEY` | secret | Android | RevenueCat's public Play SDK key (`goog_…`). Without it the build sells nothing. |

Play needs no key: the Android job signs in to Google with Workload Identity
Federation (below). The workflow's `env` holds the non-secret identifiers:
`BUILD_NUMBER_OFFSET`, `UPLOAD_CERT_SHA256`, the workload identity provider
and the service account email.

The build needs no Supabase defines: `app/lib/core/environment.dart` defaults
to the production URL and publishable key. Both platforms pass
`--dart-define-from-file=config/auth.json`, the public Google and Apple
sign-in client IDs and `APP_URL`.

## Build numbers and versions

The build number is `BUILD_NUMBER_OFFSET + GITHUB_RUN_NUMBER` (offset 1010).
Every run, dry runs and skips included, takes a new run number, so the
number only grows on both stores, and iOS and Android get the same one in a
run. The run number counts all runs of the workflow, whatever started them
(`workflow_run`, `schedule`, `workflow_dispatch`), and a newer run never
ships an older commit, so build numbers and commits rise together. A run
cancelled while pending still uses up its number; gaps are fine. A rerun
keeps its number (see Failures, `ios`). When the schedule started, TestFlight's highest was 1002
(Release run 2, offset 1000 then) and Play's first bundle, built on the box
for the Lead's first manual upload, had version code 1003. The offset went
to 1010 so that the next run (3) builds 1013, above both. The plan job fails
a run whose number is not above TestFlight's highest; Play rejects a version
code it already has, and the offset is the fix for both.

The version name comes from `version` in `app/pubspec.yaml` (`1.0.0+1`; the
`+1` is ignored because the lanes pass `--build-number`). To bump it, change
`version` in a PR, for example to `0.2.0+1`. The next run uploads 0.2.0 with
the next build number. TestFlight groups builds by version; Play shows the
version name. A version bump never resets the build number.

## Android signing

`app/android/app/build.gradle.kts` signs release builds with the key named in
`app/android/key.properties`:

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=../upload-keystore.jks
```

`storeFile` resolves from `app/android/app`, so `../upload-keystore.jks` is
`app/android/upload-keystore.jks`; that is where the workflow writes the
keystore, and it deletes both files after the build. Without
`key.properties`, release builds sign with the debug key, so local builds
work without secrets; the workflow's `check-aab.sh` step fails a bundle
signed by anything but the upload key. `key.properties` and keystores are in
`.gitignore`.

The upload key (created 2026-10-27, job 23): PKCS12, RSA 4096, alias
`upload`, `CN=Hummlist, O=Trost Systems`, valid until 2054-03-14. The
keystore and its `key.properties` are on the build box in
`~/groceries-ops/secrets/android/` (mode 600) and in the `release` secrets
above. Copy both to a password manager; Google can reset a lost upload key,
but only through Play Console support.

| Certificate | SHA-1 | SHA-256 |
| --- | --- | --- |
| Upload key | `D4:9D:98:9E:AD:E3:2E:FE:D2:D3:A1:7A:71:B2:95:29:84:81:78:69` | `2C:9B:48:6D:AF:1B:94:AB:3F:92:38:49:CC:0F:C3:42:EF:09:64:2C:32:40:74:97:69:25:61:74:0C:BA:84:F5` |
| Hummlist Play app signing key (Google-generated, Play Console, Setup, App signing; L3, 2026-10-28) | `77:B6:9B:5E:8F:10:5D:3F:46:3C:62:C3:BC:BE:A8:3D:EA:10:08:53` | `27:0E:40:2B:04:1D:4D:C8:E7:65:10:C6:B4:36:FE:E8:51:D9:08:E6:00:43:89:7F:4E:AF:B9:2F:BC:7B:E4:2A` |
| Snacklist Play app signing key (Google-generated, Play Console, Setup, App signing; first upload 2026-11-10) | `06:6E:7F:EE:F7:62:4E:90:7D:BC:F8:42:30:95:30:EE:5B:F1:17:75` | `C8:6F:D9:57:C8:05:6B:68:E1:C1:7C:BC:1B:C5:50:A3:45:36:59:0A:9B:F4:9E:25:4E:18:63:0C:8F:91:2A:EB` |

Play App Signing holds the app signing key, which signs what testers
install. Snacklist's Play app has its own Google-generated key (first upload
2026-11-10). `assetlinks.json` lists that SHA-256 for `com.snacklist.app` and
Hummlist's for `com.hummlist.app`; both also list the upload key. Google
sign-in on Play builds and `assetlinks.json` (job 22) need the app signing
key's fingerprints; debug and locally signed builds need the upload key's.

### Play service account

`play-release@family-groceries-ci.iam.gserviceaccount.com` (Google Cloud
project `family-groceries-ci`, Android Publisher API enabled) has no key and
no project roles. Only jobs in this repo's `release` environment can act as
it: its `roles/iam.workloadIdentityUser` binding names the subject
`repo:trost-systems@267752722/snacklist@1429864759:environment:release`
on the workload identity pool `github`, provider `family-groceries` (the provider keeps
its id). Since the repo rename on 2026-11-12 the binding and the provider's attribute
condition must name `snacklist`; until Peter changes them the Play upload fails
(`NEEDS_PETER.md`, "Job 201").
`google-github-actions/auth` exchanges the job's GitHub OIDC token and writes
an `external_account` credentials file, which fastlane's supply reads as
`json_key`. Play Console grants the account access to Hummlist
(`NEEDS_LEAD.md`, L4); Snacklist needs the same grant.

## iOS signing

[match](https://docs.fastlane.tools/actions/match/) keeps the distribution
certificate (`GN85KDC962`, Apple Distribution, expires 2027-10-25) and the
App Store profiles "match AppStore com.snacklist.app" and "match AppStore
com.snacklist.app.HomeWidget" (Hummlist's `com.hummlist.app` ones stay next to
them), encrypted with
`MATCH_PASSWORD`, in the private repo
`trost-systems/family-groceries-certificates`. The workflow loads
`MATCH_DEPLOY_KEY` into an SSH agent so match can clone it.
`app/fastlane/Matchfile` is read-only by default, so a release run never
creates certificates. The Xcode project keeps automatic signing for local
development; `ios beta` switches to manual signing for the release build only.

`Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`, so TestFlight
does not ask the export compliance question for each build.

### Capabilities

Enabling a capability on the App ID `com.snacklist.app` or
`com.snacklist.app.HomeWidget` (for example Associated Domains for job 22)
makes that App ID's App Store profile `INVALID`. The next Release run then
fails in `plan` ("Profile ... is INVALID") before any build; a profile that
does not exist yet fails the same way ("is missing"). The sequence:

1. The Lead enables the capability in the browser (`NEEDS_LEAD.md`, L6).
   For the Home Screen widget (job 63) that is, under Certificates,
   Identifiers & Profiles: register the App Group `group.com.snacklist.app`;
   register the App ID `com.snacklist.app.HomeWidget`; enable App Groups on
   both `com.snacklist.app` and `com.snacklist.app.HomeWidget` and assign the
   group to each.
2. From CI: Actions, Certificates, Run workflow on `main` with lane
   `renew_profile` and confirm `renew` (`gh workflow run certificates.yml
   -f lane=renew_profile -f confirm=renew`). The log lists every profile of
   both App IDs with its type and state before and after; lane `profiles`
   lists them without changing anything. `match_types` `appstore,adhoc` also
   renews an ad hoc profile. Development profiles stay Xcode's: the match repo
   holds no development certificate, and the lane refuses rather than let
   match create one. It also stops when certificate `GN85KDC962` is gone from
   the portal. Or from the build box, in `app/` (the box reaches GitHub over
   HTTPS only, so the match URL is the HTTPS one; `gh` is the git credential
   helper):

   ```bash
   set -a; . ~/groceries-ops/env; set +a   # MATCH_PASSWORD
   APPLE_TEAM_ID=VCZSHMZY25 \
   MATCH_GIT_URL=https://github.com/trost-systems/family-groceries-certificates.git \
   APP_STORE_CONNECT_API_KEY_ID=4J3N457M89 \
   APP_STORE_CONNECT_ISSUER_ID=<issuer ID> \
   APP_STORE_CONNECT_API_KEY_P8="$(cat ~/groceries-ops/AuthKey_4J3N457M89.p8)" \
   bundle exec fastlane ios renew_profile
   ```

   match regenerates the profiles of every identifier in the `Matchfile`
   (and creates a missing one, such as the widget's the first time) with the
   certificate `GN85KDC962` and pushes them to the match repo. It creates a certificate only when the repo holds
   none, so it creates and revokes none here. `MATCH_FORCE=false` checks
   without regenerating (proven 2026-10-27: "All required keys, certificates
   and provisioning profiles are installed", repo unchanged).
3. The PR that adds the entitlement (for example
   `com.apple.developer.associated-domains` in
   `ios/Runner/Runner.entitlements`, or job 63's
   `com.apple.security.application-groups` there and in
   `ios/HomeWidget/HomeWidget.entitlements`) lands after step 2.
4. Dispatch the Release workflow; the plan's preflight passes and the build
   signs with the new profile.

Order matters only between 1 and 2: a run between them fails in `plan` with
the message above and costs nothing else. A run after step 2 but
before step 3 builds fine; the new profile allows the capability without
requiring it.

## Build locally

Android, from `app/`:

```bash
flutter build apk --release --dart-define-from-file=config/auth.json        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release --dart-define-from-file=config/auth.json  # build/app/outputs/bundle/release/app-release.aab
```

Add `--build-number=<n>` to match a store build. To check which key signed a
build, run `keytool -printcert -jarfile <aab>` or
`apksigner verify --print-certs <apk>`.

iOS builds need macOS and Xcode. On a Mac with the match secrets in the
environment, `BUILD_NUMBER=<n> RELEASE_UPLOAD=true bundle exec fastlane ios beta` builds and
uploads; `flutter build ipa` alone builds with automatic signing.

Ruby for the lanes: `app/.ruby-version` names the version CI uses. Run
`bundle install` in `app/` once.

## App icon

`scripts/icons.py` (Python 3 with Pillow) draws the icon and writes every
size: `app/assets/icon/icon.png` (1024 px source), the iOS `AppIcon` set, the
Android launcher and adaptive icon mipmaps, and the web icons and favicon.
Change the drawing there and rerun `python3 scripts/icons.py`.
