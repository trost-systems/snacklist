# Fable improvement programme, November 2026

Jobs 218 to 224 record here what they measured, what they changed and what it cost. Each job
appends one `## Job <n>` section at the end of the file and adds later rounds as `###` subsections
of its own section. Numbers are measured unless a line says otherwise; what could not be measured
is labelled as such.

## Job 218: coupled hotspots and merge collisions, 2026-11-13

The brief: find where jobs collide or where files only change together, from evidence, and land
small refactors there without changing behaviour. No scores from code-health products.

### Evidence

Three scripts in `tool/hotspots/` produce every number below; rerun them to check or to see
whether a hotspot cooled down.

**Where main changes** (`tool/hotspots/history.py`, 315 commits on main `61434faf`, one commit
per PR; lines at that commit). A selection of the script's list: the logs, then the files this
section talks about. The generated l10n files, the verify skill's files and the tests follow their
sources and are left out.

| Commits | Lines | File |
| ---: | ---: | --- |
| 209 | 12,085 | `docs/DECISIONS.md` |
| 165 | 742 | `DONE_SUMMARY.md` |
| 79 | 1,787 | `docs/NEEDS_PETER.md` |
| 74 | (moved) | `FEATURES-FOR-WRITERS.md`, counted under its path before the rename |
| 73 | 1,315 | `app/l10n/app_de.arb` (and the generated l10n files with it) |
| 49 | 203 | `AGENTS.md` |
| 48 | 2,153 | `docs/NEEDS_LEAD.md` |
| 41 | 967 | `e2e/tests/helpers.ts` |
| 39 | 1,212 | `app/lib/list/list_screen.dart` |
| 33 | 1,915 | `app/lib/list/list_cubit.dart` |
| 32 | 536 | `docs/ANALYTICS.md` |
| 30 | 715 | `app/lib/more/more_screen.dart` |
| 30 | 224 | `app/lib/main.dart` |
| 29 | 352 | `.github/workflows/ci.yml` |
| 27 | 62 | `scripts/gates/db.sh` |

**What changes together** (same script; code files only, sweeps over 60 files skipped; degree is
the share of the rarer file's commits that also touch the other):

| Shared commits | Degree | Pair |
| ---: | ---: | --- |
| 21 | 0.88 | `list_cubit.dart`, `list_cubit_test.dart` |
| 20 | 0.95 | `list_cubit.dart`, `test/list/fake_repository.dart` |
| 17 | 0.94 | `list_cubit.dart`, `list/model.dart` |
| 17 | 0.89 | `list_cubit.dart`, `list_repository.dart` |
| 13 | 0.76 | `more_screen.dart`, `test/more/more_harness.dart` |
| 12 | 0.86 | `scripts/backup/fixtures.sql`, `supabase/tests/account_deletion.test.sql` |
| 12 | 0.67 | `app/app.dart`, `main.dart` |
| 11 | 1.00 | `ci.yml`, `scripts/verify.sh` |
| 11 | 0.73 | `app/router.dart`, `more_screen.dart` |

Change counts say where edits meet, not that they collide. The next two measure collisions.

**Conflicts the job agents ran into** (`tool/hotspots/conflicts.py ~/groceries-ops/jobs`, the
transcripts of 198 jobs at 20:51, this job's left out; main's history is linear and keeps no
trace of a conflict):

| Conflict events | Jobs | File |
| ---: | ---: | --- |
| 118 | 78 | `docs/DECISIONS.md` |
| 17 | 14 | `DONE_SUMMARY.md` |
| 15 | 12 | `docs/NEEDS_LEAD.md` |
| 11 | 9 | `FEATURES-FOR-WRITERS.md` |
| 5 | 5 | `docs/NEEDS_PETER.md` |
| 4 | 3 | each of 12 list and add-sheet goldens (`app/test/design/goldens/*.png`) |
| 3 | 3 | `docs/PRIVACY_DATA_MAP.md` |
| 3 | 2 | `app/lib/list/list_screen.dart`, `docs/ANALYTICS.md`, `scripts/gates/db.sh` (each) |

- 79 of 198 jobs (40 %) stopped at least once in a conflict in one of the logs every job appends
  to. In 102 of all 145 conflict events nothing else conflicted.
- 64 times the transcript goes on from such an event to a finished rebase or push (a second
  conflict on the way counts into the same stretch): median 9 assistant entries in the
  transcript (an entry is a part of a message; review 1 counted about two per message) and 55 s
  each. Their token cost is not measured (the transcripts repeat usage
  per stream chunk).
- An event is a tool result with git's conflict lines, so a job that only reads such lines counts
  too. Review 0 found one of those among the 145 (job 219 reading a table that quotes one).
- The larger cost is lead time, and it is only partly measured. A PR that is green and reviewed
  goes back to CONFLICTING whenever another job lands first, since every job appends to
  `docs/DECISIONS.md`. On 13 November the watcher queued two extra jobs for that alone
  (BOARD 18:15 `204b-rebase-merge-400`, at 19:46 "Only conflicts were DECISIONS.md appends";
  20:01 `204c-land-400`: "CONFLICTING again (DECISIONS.md appends only)") and a third,
  `207b-rebase-merge-405` (19:48), for `DECISIONS.md` and three feature files. Each such round is
  one more rebase, push and CI run (median 21 minutes from created to updated over the last 24
  green PR runs of `ci.yml`, `gh run list` at 21:25).
- A resolution by hand can go wrong without anyone noticing: PR #386 left a paragraph of job 196
  under job 189 in `DONE_SUMMARY.md`, glued to the next heading. PR 1 repairs it.

**Replay of main's history** (`tool/hotspots/replay.py`): for every PR that changed a file while
another PR changed it too, the script rebuilds the PR's change from the commit that landed, on
main as it was when the PR was opened, and merges it the way a rebase would. "Stops" is a
conflict. The branches themselves are gone, so the replay cannot see what a PR looked like before
its author resolved a conflict; it sees where the landed text would have sat.

| File | PRs with a concurrent change | Stop with git's default merge |
| --- | ---: | ---: |
| `docs/DECISIONS.md` | 145 of 209 | 141 |
| `DONE_SUMMARY.md` | 94 of 165 | 70 (2 more could not be rebuilt) |
| `docs/NEEDS_LEAD.md` | 31 of 48 | 27 |
| `docs/NEEDS_PETER.md` | 25 of 79 | 18 |
| `scripts/gates/db.sh` | 11 of 27 | 3 (6 more could not be rebuilt) |
| `docs/ANALYTICS.md` | 13 of 32 | 3 (1 more could not be rebuilt) |
| `AGENTS.md` | 18 of 49 | 2 (1 more could not be rebuilt) |
| `app/l10n/app_de.arb` | 33 of 73 | 2 (4 more could not be rebuilt) |
| `e2e/tests/helpers.ts` | 15 of 41 | 1 (1 more could not be rebuilt) |

The replay finds more conflicts than the transcripts because one push often rebased over several
landed PRs at once, and because early jobs have no transcript.

So the collisions are not in the code. They are in four files that every job appends to, and they
are a design problem: 200 jobs write to the same last line.

### PR 1: both appended sections stay (merge driver `append-log`)

`.gitattributes` names a merge driver for `docs/DECISIONS.md`, `docs/NEEDS_LEAD.md`,
`docs/NEEDS_PETER.md`, `DONE_SUMMARY.md` and this file. The driver is
`scripts/merge-append-log.sh`: when both sides only inserted text at the same place, both
insertions stay, ours first (in a rebase that is main's section, then the PR's). It stops in a
conflict, as git does today, when

- either side edits or deletes lines, both sides created the file, or the merged file would not
  end in a newline,
- an entry is there twice, as when a commit is replayed after its section landed: a line ours
  added is also the first line theirs adds, or a later heading of theirs of that level (where
  theirs starts without a heading: any line of theirs that is none), or
- ours adds a heading above the level theirs starts at: a paragraph or a `###` subsection that
  continues an older section would otherwise land under main's newest `##` section. A line that
  starts with one to six `#` and a space counts as a heading, also a comment in fenced code.

`rebase_onto_main` (`scripts/lib.sh`), which `push-pr.sh` runs, stores the driver's command in
the clone's git config, because git reads a driver's command only from there. A clone without it
merges as before. The script itself never writes a conflict: when it does not take a merge it
exits and leaves the file alone, and the stored command then runs `git merge-file`, which is what
git does without a driver (up to the diff algorithm, see the limits). A checkout without the
script, or an awk that fails, ends the same way.

Replayed on the conflicts above:

| File | Default conflicts | Merged by the driver | As it landed, byte for byte | Still stops |
| --- | ---: | ---: | ---: | ---: |
| `docs/DECISIONS.md` | 141 | 136 | 135 | 5 |
| `DONE_SUMMARY.md` | 70 | 59 | 58 | 11 |
| `docs/NEEDS_LEAD.md` | 27 | 27 | 27 | 0 |
| `docs/NEEDS_PETER.md` | 18 | 16 | 15 | 2 |
| Total | 256 | 238 (93 %) | 235 | 18 |

- The numbers are the same before and after the fixes of reviews 0 and 1 (main `61434faf`, 312
  merged PRs). Review 1 took the duplicate guard out and got the same 256 outcomes: it stops no
  merge in main's history.
- "As it landed" says what people did by hand, not that the driver is right: the PR's text is
  rebuilt from the landed commit, so the result matches whenever the landed text sits after
  main's. 235 of 238 hand resolutions were "main's section first, then the PR's", which is the
  order the driver produces.
- The three merged results that differ from what landed hold the same lines: two put two whole
  sections in the other order (#284, #5) and one differs in a blank line. No result differs in
  content.
- The 18 that still stop: 3 are edits of existing lines (#91 in `DECISIONS.md`, #89 and #336 in
  `NEEDS_PETER.md`). In the other 15 main had added a `##` section and the PR's text at the same
  place starts without a heading or with a lower one: a follow-up paragraph for an older section,
  a `### fix round` (#386, the PR whose hand resolution went wrong), a one-line entry. The third
  guard stops them on purpose, although 9 of them landed in exactly that order.
- Git's built-in `merge=union` was the first candidate and is rejected on the same replay: it
  never stops, 140 of its 256 results lose a blank line (the one before a heading), and for #89
  and #336 it keeps the old and the new version of an edited line side by side.

Live check on open PRs, each head rebased in a scratch clone onto main without and with the
driver (13 November). The first run, before review 0, on main `9efe6c19` at 20:15: #400, #408,
#409 and #410 stopped in `docs/DECISIONS.md` and #412 in `DONE_SUMMARY.md` without the driver, none
of them with it; #405 went from five conflicted files to its three feature files. The second run,
with the driver as it is now, on main `61434faf` at 20:51 (several of those PRs had been rebased
by hand in between):

| PR | Conflicted files without | With the driver |
| --- | --- | --- |
| #400, #409 | `docs/DECISIONS.md` | none |
| #412 | `DONE_SUMMARY.md` | none |
| #401 | `DONE_SUMMARY.md`, `docs/DECISIONS.md` | `docs/DECISIONS.md` |
| #281, #405, #408, #410, #414 to #421 | none | none |

#401 still stops on purpose: it adds its section as `### Job 205`, one level below the
`## Job 211` main added at the same place, and the third guard will not put it there.

The test `scripts/merge-append-log-test.sh` runs in the lint gate, in a scratch repository with
this checkout's `.gitattributes`. The log must stop a real rebase while the config has no driver.
Then `rebase_onto_main`, the rebase `push-pr.sh` runs, must store the command and merge the log,
while a file without the attribute still stops. The stored command then runs the way git runs it:
43 cases on three files, a file git cannot merge (it stays as it was and conflicts), and the
command in a directory without the script (a conflict has git's markers, a clean merge merges).
Last, a merge puts the branch's section first, and a branch stacked on one whose section already
landed stops with markers. 50 mutants of the script, the stored command, `install_merge_driver`,
its call in `rebase_onto_main` and `.gitattributes` all fail it (each guard removed or weakened,
the reset of each per-place variable, heading depth and form, the marker size without
each file and each marker character, markers inside a line, the final newline, the fallback and
its exit status, an older stored command kept, a log or the anchor dropped). Review 0 had found
four survivors in the first version, review 1 nine in the second, the missing call in
`rebase_onto_main` among them, and review 2 a dozen in the third. Reviews 3 and 5 found more.
Those that change a merge or the conflict left behind are covered now; the ones left concern
headings the script does not see by design (a tab, an indent), the path of one log in
`.gitattributes` and the two messages. It passes with gawk, `gawk --posix`, mawk and busybox
awk; macOS awk is not tried here (the Mac box runs `push-pr.sh`; an awk that fails there ends in
git's own merge, a conflict as today).

Limits:

- GitHub does not run merge drivers. A PR still shows CONFLICTING after another job appended; the
  next `push-pr.sh` rebases it without a stop.
- A clone learns the driver at the first `push-pr.sh` of a branch that has this change. A hand
  `git rebase` before that stops as before.
- Two sides that each add a numbered item to the same older section both stay, with the same
  number twice.
- For the five files `-X ours` and `-X theirs` no longer apply, and conflict markers are labelled
  `ours`, `base`, `theirs` instead of the commits.
- The duplicate guard compares lines, within one place and one heading level. A section that
  landed and is replayed under a changed heading is added a second time, and so is one that
  ours holds at another place of the file or that theirs replays below a higher heading.
- Headings are `#`s and a space at the start of a line. Underlined (setext) headings, indented
  and empty ones and `#` with a tab are not seen, so the third guard does not know them. The
  logs have no such heading (review 3 compared the script's headings with a Markdown parser's
  on the five files). A `#` comment at the start of a line in fenced code counts as a heading:
  after one in ours a merge may stop that could have been taken, and an insertion of theirs
  that starts with one counts as a new section.
- A fence that ours' insertion leaves open does not stop the merge: theirs lands in it, as the
  next section appended to that file would.
- The script and the fallback merge with `git merge-file`, which diffs with Myers. A rebase
  diffs with histogram, and `git merge-file` takes that option only from git 2.44 on (hz has
  2.43, so a branch for it could not be tested here and is left out). Where both sides insert the
  same repeated lines the two can place a hunk differently, both results valid. Review 0 measured
  it: 3 of 1,500 synthetic triples differed, none of 1,946 clean merges built from lines of
  `DECISIONS.md`.
- The command is one string in the clone's config. A later change of it makes worktrees on older
  commits write the old string back at their next `push-pr.sh`, until they are rebased; both
  versions run the script of their own checkout.
- Git runs the script of the tree that is checked out. Merging in a checkout of someone else's
  branch runs their copy, the same trust as running their `push-pr.sh`.
- A new log gets the driver only when it is listed in `.gitattributes`, and should be listed only
  if its entries start with a heading or are single lines.

Review 0 (in-job, `claude-fable-5-2`, verdict FIX) found three defects in the first version, all
fixed before the first push: a section already on main but not first there was added a second
time (reproduced with a real rebase of a stacked branch); a file `git merge-file` cannot read
came out empty with exit 0; and `DONE_SUMMARY.md` in `.gitattributes` also matched a sixth file
under `docs/design/`. The script used to write the conflict markers itself, so a script that
failed early left a conflict without markers; that is why the fallback moved into the stored
command. The rework took the script from three `git merge-file` runs to one.

Review 1 (in-job, `claude-fable-5-2`, verdict FIX, no must-fix) found no wrong merge on a
realistic file and seven smaller things, fixed as well: the test called `install_merge_driver`
itself, so the call in `rebase_onto_main` could vanish with green gates; a clean merge of a file
without a final newline gained one; an unclosed fence in ours hid ours' later headings from the
third guard; nine mutants survived; and two examples of rebase jobs in this file
and in `NEEDS_LEAD.md` named `207b`, which also had real conflicts.

Review 2 (in-job, `claude-fable-5-2`, verdict FIX, no must-fix) reran the replay, the history
table and the 33 mutants and got the same results, and its fuzz (2,800 triples against
`git merge-file`) found no merge that loses, repeats or reorders lines. It found one way to a
misplaced section: two lines of ours that start with inline code in three backticks counted as
a fence around the `##` heading between them. The logs have no such line. It also found two
sentences here that said more than the script does (both corrected), and a dozen mutants of its
own that the test let through: the test got 12 more cases.

Review 3 (in-job, `claude-fable-5-2`, verdict FIX on wording, no must-fix) fuzzed 9,000 triples
and found no merge that loses, repeats or reorders lines. Of 860 real merges cut from
`DECISIONS.md`, the 628 that git merges cleanly came out the same with the driver. It corrected
three sentences here.

Review 4 (in-job, `claude-fable-5-2`, a check of those corrections, verdict FIX on wording) read
review 3's fuzz output again: 148 of the 9,000 merges had put a section in the wrong place, 87
of them through a fence line inside another fence, the rest through headings and fences the
script did not see. That was the third review in a row with a hole in the fence rule, so the
rule went. Until then a `#` line in fenced code was not a heading, and a fence ours left open
stopped the merge. Now every line of ours that starts with one to six `#` and a space is a
heading, which only makes the third guard stop more often, and an open fence no longer stops
(the next section appended to that file lands in it either way). The replay does not change:
all 256 conflicts come out as before, and the four logs it covers have four fence lines at the
start of a line today and no `#` line between them.

Review 5 (in-job, `claude-fable-5-2`, on the script without fence parsing, verdict FIX on two
sentences, no must-fix) ran the script against the one before on 20,000 fuzzed triples. Where
both merge, the bytes are the same. The new one merges 1,451 that the old one stopped, all at a
fence ours leaves open, and stops 369 that the old one merged, all after a `#` line in a fence
of ours. By its Markdown reading 1,381 merges put theirs under a section of ours: 1,272 through
an open fence and 109 through headings the script does not see (both in the limits above),
none through a `#` heading at the start of a line. Of 900 real merges cut from `DECISIONS.md`,
the 665 that git merges cleanly came out the same with the driver.

Review 6 (in-job, `claude-fable-5-2`, a check of those corrections, 10 minutes, verdict PASS)
found both sentences fixed, the test, the mutants and the replay as written here, and nothing
wrong in 22 triples of its own beyond the limits. Its two should-fixes are in: where the driver
stops, the test now compares the file with git's own merge of the three (a script that had
already written into the file passed before), and the limit of the duplicate guard names place
and heading level.

Cost of PR 1 up to its review 2, measured at 21:55 (the job started at 19:47):

- Wall time 2 h 8 min. The three review rounds ran 17, 22 and 18 minutes of it, the three
  evidence searches (in parallel) 10 minutes.
- Tokens, from the usage fields of the job's transcripts, each message id counted once, every
  message on `claude-fable-5-2`: the main session wrote 0.71 M tokens to the cache, read 16.3 M
  from it and put out 253 k; the six subagents (three evidence searches, three reviews) wrote
  1.11 M, read 24.3 M and put out 345 k. Uncached input is under 1,000 tokens in both.
- Gates: `scripts/verify.sh --only gitleaks,lint,changelog,nexus` took 1 min 34 s with the new
  test in the lint gate; the test alone ran 0.9 s then and 1.2 to 1.6 s with the later cases.
  The other gates run in CI, not locally.
- Review rounds: 0 to 2 up to then (each FIX: review 0 with three must-fixes, 1 and 2 with
  none), then reviews 3 (18 minutes), 4 (5 minutes) and 5 (21 minutes), each FIX on wording
  without a must-fix, and review 6 (10 minutes), PASS, all before the first push. No flaky run
  so far.
- Not measured here: CI time and the land of this PR (they go into the job's done summary), and
  what the driver saves from now on. The 55 s and 9 entries per conflict above are what a stop
  cost before; how many stops go away shows in a rerun of `conflicts.py` in some weeks.

Not done: one decisions file per job (`docs/decisions/<job>.md`) would remove the shared file
altogether. It changes where 200 sections live, every doc that cites "DECISIONS job n" and the
lead's standing instructions, for the 7 % of conflicts the driver leaves. Recorded in
`docs/NEEDS_LEAD.md` as an option.

### Hotspots after PR 1

| Hotspot | Evidence | State |
| --- | --- | --- |
| The append-only logs | 79 of 198 jobs, 256 replayed conflicts | PR 1 |
| List cluster: `list_cubit.dart`, `list_repository.dart`, `model.dart`, `fake_repository.dart`, `list_screen.dart` | strongest co-change (0.88 to 0.95); 3 conflict events | Blocked: job 212 owns these files and jobs 221 and 222 wait for it |
| `FEATURES-FOR-WRITERS.md` and the verify feature files | 11 events in 9 jobs; #405 conflicted in three of them on 13 November | Not append-only: jobs edit a feature's section in place, so the driver does not fit. Job 219 works on the verify skill; left to it |
| Goldens (`app/test/design/goldens/*.png`) | 4 events in 3 jobs per file | Inherent to binary files: regenerate after the rebase. No refactor helps |
| `scripts/gates/db.sh` | 27 commits for 62 lines, 3 events, 3 replayed conflicts: every new integration test adds itself to one list | PR 2, after #405 and #431 (each added to the list) |
| `more_screen.dart` with `more_harness.dart` and `router.dart` | 0.73 to 0.76 | Blocked: #281 and job 206 |
| `app.dart` with `main.dart` | 0.67 | Blocked: `main.dart` is job 212's |
| `ci.yml` with `verify.sh` | 1.00 | By design: `scripts/check-gates.sh` ties one CI job to one gate script. Job 221 owns iteration speed |
| ARB and generated l10n | 73 commits, 2 replayed conflicts | Many edits, few collisions (keys are spread over the file). Nothing to fix |
| `e2e/tests/helpers.ts` | 41 commits, 1 replayed conflict | Few collisions, and little to dedupe: 13 spare copies of helpers in the specs, 44 lines (below). Not done |
| `merge-pr.sh` right after `push-pr.sh` | 17 lands in 16 jobs refused as "behind main" on GitHub's stale record of the head | PR 3 |
| `scripts/gates/lint.sh` | 15 commits, 3 events in 1 job; a header sentence and a line per script test | Left: PR #420 edited it and was open until 14 November 09:09 (PR 3, below) |

### PR 2: the db gate finds its integration tests by pattern

`scripts/gates/db.sh` ran the functions' integration tests from a list of file names, with a
comment line per job above it. A job with a new `*_integration_test.ts` added a name at the end
of the list and a comment at the end of the block, the same two places as every other such job.

- 17 of the 27 commits on main that touch the file add a name to the list, and 15 of them
  change nothing else in it. 2 more only add to the comment block (`git log --first-parent
  7bfae2ed -- scripts/gates/db.sh`, counted on each commit's diff of the file). The transcripts
  hold 3 conflict events in the file and the replay 3 conflicts, with 6 more PRs it could not
  rebuild. #405 (`95316b50`, 14 November) was commit 28, the 18th to add a name (the list's
  19th: one commit, `6d2a193e`, had added two). It added
  `_shared/default_list_integration_test.ts` and two comment lines, and this PR's rebase
  conflicted with it in both places. #431 (`b97deee7`, the same morning) added
  `feedback-digest/digest_integration_test.ts` and one comment line while this PR waited for
  PR 1 in the merge queue: the next rebase conflicted in both places again.
- A test file that nobody added to the list was never run, without a message. None was missing
  at `7bfae2ed`: the list and `find supabase/functions -name '*_integration_test.ts'` both name
  the same 18 files.

Now the step is `deno test ... '**/*_integration_test.ts'`. The pattern is quoted: deno expands
it, so the step does not depend on the shell's `globstar` setting. The comment block is gone;
every one of the files says in its header what it proves, and two lines in the gate say where
to look. A new integration test needs no edit of the gate.

The same tests run, measured on a fresh local stack on hz (block 628, the step cut out of both
versions of the script at `8c1a9177`, which has main's migrations up to `7bfae2ed`, `db reset`
in between):

| | Files | Tests passed | Failed | Ignored | Time |
| --- | ---: | ---: | ---: | ---: | ---: |
| The list (before) | 18 | 118 | 0 | 0 | 31 s |
| The pattern (after) | 18 | 118 | 0 | 0 | 31 s |

The 118 pairs of file and test name are the same in both runs. The order of the files is not.
Deno ran the listed files grouped by directory (`purchases`, `waitlist`, `_shared`, `alexa`,
`voice`, `api`, `mcp`), in the list's order inside a directory; it runs the pattern's files
sorted by path. Both orders pass, one run each. With no match the step fails ("No test modules
found", exit 1), so a typo in the pattern cannot pass as an empty run.

On main there were 19 files with #405 and 20 with #431. No local stack ran for them (the box
was short of memory on 14 November); the comparison is main's CI against the pattern's listing:

- The list, in CI's db job on `055d33ec` (PR 1's head on #431, run 43568327834, deno 2.9.8):
  20 files, 128 passed, 0 failed, 31 s.
- The pattern on that tree, run without a stack, so every test reports as ignored: the same 20
  files, 128 tests, and the same 128 pairs of file and test name as in the CI log. (Compared the
  same way at #405: 19 files, 127 tests, run 43561038725.)
- That the 128 pass in path order is for the db job of this PR's own CI run to show; its
  counts are in the job's done summary.

One check is new. The list failed the gate when a listed file was renamed or deleted (deno
found no such file); the pattern runs what matches, so a file renamed off the suffix would drop
out without a message. The functions gate skips these tests (they read `FG_DB_TEST`), so no gate
would run it. The gate now stops when a file under `supabase/functions` reads `FG_DB_TEST` and
is not named `*_integration_test.ts`. All 20 that read it have the suffix; renaming one, and
adding one in a new directory under another name, each stopped the check (run by hand on the
18 before #405, then undone).

Limits: a test that only passes after another file's leftovers shows up when the order changes,
and a new file now changes the order where it sorts in; no such pair showed in the one sorted
run of the 18 on a fresh database. The new check finds a misnamed test only if it is a tracked
`.ts` file that reads `FG_DB_TEST` itself. A deleted test file no longer fails the gate: the
list did when the name stayed behind, and nothing does now (a job that deleted both the file and
its name passed before too). The rest of the gate (pgTAP, the classifier checks, the latency
benches, db lint, the backup drill, the fixtures test) is untouched.

**Measured and not done: helpers copied between e2e specs.** `tool/hotspots/e2e-duplicates.mjs`
parses `e2e/tests/*.ts` and prints the top-level functions whose code is the same in several
files: 13 spare copies, 44 lines of the 11,741 in those files (`cat e2e/tests/*.ts | wc -l`,
0.4 %), 6 of the copies between `club.spec.ts` and `invite-loop.spec.ts`. Eight specs have a
`newPage`, in four variants (the viewport or the options they take differ). Moving them is a PR
that runs the whole e2e gate and takes a place in the merge queue for 44 lines, and
`invite-loop.spec.ts` is in open PR #429. Left as it is; the script is there to see whether the
number grows.

### PR 3: merge-pr.sh waits for GitHub's record of the pushed head

A land is `scripts/push-pr.sh && scripts/merge-pr.sh --wait <n>` in one hold of the merge lock.
push-pr.sh rebases onto `origin/main` and pushes. merge-pr.sh then asked GitHub for the PR's head
(`gh pr view --json headRefOid`), and for some seconds after a push that record still names the
head before it. The old head is not on top of main, so merge-pr.sh stopped with "is behind main;
run scripts/push-pr.sh", the lock was released, and the land went back to the end of the queue.

- `tool/hotspots/stale-head.py ~/groceries-ops/jobs` (14 November, 07:05, 211 jobs with
  transcripts): 17 pushes in 16 jobs were refused that way in the same tool result as the push.
  That the record lagged is inferred from the order of the two lines, not read from GitHub.
  Review 1 checked the other reading, a main that moved between the two scripts: each of the 17
  pushed commits has its parent on main, and main's next commit came after the refusal. 30 more
  "behind main" results in 17 jobs have no push before them (main had moved, two separate
  commands, a log read again, or this job's own test output) and are not counted.
- This job's PR 1 was one of the 17: queued at 23:09, at the lock at 01:40, pushed `6845602d`,
  refused right after the push, back to the queue (2 h 31 min for nothing).
- Jobs had started to work around it one by one. Of the 9 other job directories with a land
  script in `/tmp` on hz that morning, 4 had a `sleep 20` between the two scripts (jobs 201,
  208, 219 and 220). Job 219's also retried on "is behind main"; that the other sleeps were for
  the record is inferred, their scripts do not say. Scratch files, not versioned: seen, not
  reproducible later.

Now merge-pr.sh takes the head from the branch (`git fetch origin <branch>`, `FETCH_HEAD`) and
waits until the record names it: 5 s between two looks, 24 times (2 min), then it stops with a
message that says what to check. With the record current, as in every later run, the loop ends
at its first look. Nothing else in the script changed: the checks on the head, the wait for
`ci-ok` and `gh pr merge --match-head-commit` are as before, now on the branch's head.

`scripts/landing-test.sh` (lint gate) has three cases against its fake `gh`: a record that
names the old head for two looks (the PR merges, after two 5 s sleeps), one that never follows
(exit 1 after 24 sleeps, nothing merged), and a main that moved after the push with the record
current (still "is behind main", no sleep, nothing merged; no case covered that refusal
before). Six mutants of merge-pr.sh each fail it: main's script as it was, the head read from
the record again, giving up after 2 looks, never giving up, a 1 s sleep, and no check for
"behind main". The test ran 5.4 to 7.1 s with the three cases and 3.8 to 4.0 s before them
(three runs each, at different times on a box whose load changes: about two seconds more).

Limits: how long the record lags was not measured (the 20 s sleeps of the other jobs worked for
them). The wait covers the head only. A description edited after the push is still refused, as
before. Whether `gh pr checks` can show the old head's `ci-ok` for a moment after the record
names the new head was not tested; `gh pr merge --match-head-commit` names the head either way.

Two more places where lands meet, measured and left:

- `scripts/gates/lint.sh`: one header sentence names every script test and one line per test
  runs it, so two jobs with a new test conflict twice. 15 commits on main, 3 conflict events in
  1 job in the transcripts (job 219, whose land script then redid its edit of the file by
  itself), and this job's PR 1 met #423's test in the same sentence on 14 November. The tests
  have no common name (`landing-test.sh`, `release/test.sh`, `ci/download-test.sh`), so a
  pattern as in PR 2 needs renames first. PR #420 edited the file and was open until 09:09 on
  14 November, when this job's last PR was reviewed; not done, recorded in
  `docs/NEEDS_LEAD.md`.
- The merge queue itself. A land holds the lock from its push to the merge, so through one CI
  run. Between 13 November 23:12 and 14 November 06:40 main took 17 commits, a median 25 min
  apart, with jobs waiting all night; the last 26 green CI runs on PRs took a median 23.8 min
  from creation to green (2 min for a docs-only PR, 49.5 for one with a rerun). The queue moves
  at one CI run per land. Changing that (CI before the lock, or a merge queue on GitHub) is the
  lead's design and no refactor; the number is here for it.

### Landing and totals, 2026-11-14

| PR | Review rounds | Rebases that stopped | CI on the landed head | On main |
| --- | --- | --- | --- | --- |
| 1, #426: merge driver `append-log` | 7 (0 to 6: six FIX, then PASS) | 1, in `scripts/gates/lint.sh` | 26 min, first attempt | `fe56ff6e`, 14 November 08:17 |
| 2, #438: db gate by pattern | 3 (FIX, FIX, FIX on one clause, then PASS) | 2, both in the list it removes (#405, #431) | 31 min, first attempt (33 min on the head before it, `7eaff830`) | `5c83230d`, 14 November 12:16 |
| 3: merge-pr.sh waits for the record | 3 (FIX, PASS, and PASS on the closing docs) | 0 | in the job's done summary | in the job's done summary |

PR 2's own CI shows what its section left open: the db job on its landed head (`5642a208`, run
43586832198) ran the pattern's 20 files in path order, 128 passed, 0 failed, 27 s, the same
128 pairs of file and test name as the list's run on `055d33ec`. So did the run on the head
before it (`7eaff830`, run 43574486351, 30 s).

Every review ran on `claude-fable-5-2`, as did the build. No review found a change in what
the app or a gate does beyond what its PR says; the must-fixes were three in PR 1's review 0
(the driver's guards), none after.

**PR 1's way to main** took 9 h 8 min from its PASS (queued at the merge lock at 23:09 on 13
November) to the merge at 08:17:

- 2 h 31 min in the queue, then the push and the refusal on GitHub's stale record (PR 3).
- 4 h 55 min in which nobody queued it again: the job was stopped by its usage limit from 23:37
  to 06:32, and the land script had ended at 01:41.
- 1 h 16 min for the second try, 36 min of it the wait for the Mac's lock, which was not
  reachable, and 40 min behind two other lands (#431, and a try of #420 that failed in CI).
- 26 min for CI (run 43568327834, green at the first attempt), inside the lock.

The driver worked on its own PR. Before it was on main, this job's worktree had it through a
scratch entry in the clone's config (removed after the merge). The last rebase, from `95316b50`
onto `b97deee7`, met job 225's new section at the end of `docs/DECISIONS.md`: plain git stops
there (`git merge-tree` in a clone without the driver), the land's rebase did not, and main has
both sections, job 225's first. The hand rebase before it stopped once, in
`scripts/gates/lint.sh` on #423's test, and not in the logs.

It worked a second time from main, on PR 2's last rebase (from `86d5d8c5` onto `f80960a7`,
inside the lock at 11:46). Main had a new section at the end of `docs/DECISIONS.md` (job 225's
review 0), where PR 2 adds its own. Plain git stops there (`git merge-tree
--merge-base=86d5d8c5 f80960a7 7eaff830` in a clone without the driver); `push-pr.sh` ran
through and pushed. A stop would have cost that turn at the lock.

**The baseline for a later rerun.** `tool/hotspots/conflicts.py ~/groceries-ops/jobs
218-fable-hotspot-refactor` at 08:22 on 14 November, five minutes after the driver reached main:
168 conflict events in 210 jobs, 115 of them in the logs alone, 86 jobs with a conflict in a log
(145, 102 and 79 of 198 jobs at 20:51 the evening before). What the driver saves is the growth
of the 115 from here on; not measurable yet. Clones that have not run `push-pr.sh` from a branch
with PR 1 still stop as before.

**Cost of the whole job**, measured at 11:50 on 14 November (PR 3's own land is not in
it):

- Wall time: 16 h 3 min from the start at 19:47 on 13 November, 6 h 55 min of it stopped by the
  usage limit. Most of the rest of the second day was waiting for the merge lock and CI.
- Tokens, from the usage fields of the transcripts, each message id counted once, every model
  message on `claude-fable-5-2` (the two other entries are the harness's limit notices, without
  tokens): the main session wrote 1.56 M tokens to the cache, read 46.6 M from it and put out
  532 k; the 15 subagent runs (three evidence searches, the reviews; a
  reviewer asked again counts once) wrote 2.47 M, read 49.1 M and put out 678 k. Uncached
  input is about 1,000 tokens in each.
- Gates: the lint gates (`scripts/verify.sh --only gitleaks,lint,changelog,nexus`) ran before
  every push, 1.5 to 2 min each. The db gate did not run locally for PR 2's final base (no
  memory for a second stack on 14 November); CI's db job ran it.
- Flakes: none in this job's CI runs, each green at its first attempt.
- Failures: one land lost to the stale record (above); one usage-limit stop; a rebase of PR 2
  twice into the list it removes; and PR 2's first turn at the lock, which ended without a
  merge. Its CI run (43574486351) took 33 min, 33 of them the iOS job, and `merge-pr.sh --wait`
  gives up after 30. The run turned green 3 min later; the merge had to queue for the lock
  again (2 h 5 min, behind five other lands). By then main had moved, so the second turn was
  one more push and CI run (43586832198).

## Job 220: security hardening, 2026-11-13

The brief: review the database policies, the edge functions, secrets in the repo and CI, and
dependency and Actions pinning from evidence, then land the well-supported hardenings in small
PRs, each with a test that fails without it. Findings and what remains:
`docs/done/220-security-hardening.md`. Build and review ran on `claude-fable-5-2`; every reviewer
stated its model.

### What the checks say, before and after

Each number comes from a command a reader can rerun; "main" is `9efe6c19`, where the review
started, unless a line says otherwise.

| Check | Before | After |
| --- | --- | --- |
| `supabase/tests/least_privilege.test.sql` (9 tests, new) | 6 fail on main's schema | 9 pass (#416) |
| Functions `anon` may execute in `public` beyond the one meant for it | 3 | 0 (#416) |
| `scripts/workflow-hardening.ts` on main's workflows (new, 4 rules) | 16 findings | 0; 12 fixed, 4 behind 3 allow-list entries for `supabase-deploy.yml` (#421) |
| `uses:` lines that name an action in another repository, pinned to a commit SHA (14 more name a local action) | 73 of 73, by habit | 73 of 73, a lint rule (#421) |
| Jobs with secrets or a write token that restore an Actions cache | 5 (release `plan`, `ios`, `android`; `certificates`; supabase-deploy `deploy`) | 1, on the allow-list (#421) |
| `scripts/pinned-deps.ts` on main's files (new) | 3 errors (two ranges, no Gradle checksum) | 0 (#418) |
| Gates that refuse a dependency the lockfile does not record | 0 of 6 (flutter, web-prod, e2e; functions, fg-cli, nexus) | 6 of 6 (#418) |
| Fetches of a known MCP client's document that strangers can block for an hour | all (shared limit of 600 an hour, 30 per host) | none; a known client has its own count (#417) |
| Alexa certificate chains kept per worker | one per distinct URL, query string included, no cap | at most 16, keyed on host and path (#417) |

Not measured: whether any of the closed gaps was ever used. The review found no sign of it and
had no production access to look.

### Tests and mutation runs

| PR | New tests | Mutations of the new check, killed |
| --- | --- | --- |
| #416 | 9 pgTAP | not run (the 6 failing-without tests are the proof) |
| #417 | 3 deno (`alexa/verify_test.ts`, `mcp/cimd_integration_test.ts`) | not run |
| #418 | 62 deno (`scripts/pinned-deps_test.ts`) | 37 of 37 |
| #421 | 32 deno (`scripts/workflow-hardening_test.ts`) | 28 of 28 |

The mutation lists grew with the reviews: each surviving mutant a reviewer reported became a
test and an entry in the list (`pinned-deps` 18 to 37, `workflow-hardening` 21 to 28).

### Cost

Wall time: 14 h 43 min from the start (13 November, 19:51 CET) to the last code PR's merge
(14 November, 10:34), of which the session did not run for 6 h 52 min (23:40 to 06:32) and most
of the rest after 21:19 was waiting for the merge lock (below). The docs PR's own land is not in
these numbers. Tokens are the sums the harness reported per delegate, and for the main thread the
usage fields of its session log (largest value per message id).

| Part | Runs | Tokens | Wall time |
| --- | ---: | ---: | ---: |
| Review delegates (functions, CI and secrets, dependencies) | 3 | 274,366 | 577 s, 736 s, 771 s (in parallel) |
| Build delegates (#418, #421 first versions) | 2 | 215,317 | 727 s, 1,010 s |
| Reviewers #416 | 1 | 130,050 | 445 s |
| Reviewers #417 | 4 | 389,492 | 1,437 s |
| Reviewers #418 | 5 | 592,381 | 3,930 s |
| Reviewers #421 (one of them for the cache rule before it was folded in) | 5 | 605,830 | 4,203 s |
| Reviewers docs PR #444 | 3 | 420,445 | 1,292 s |
| Main thread, to #418's merge | 1 | output 505,150; input 902; cache written 1,931,127; cache read 48,864,934 | the whole job |

Review verdicts in order. #416: PASS. #417: FAIL, FAIL, FAIL, PASS. #418: PASS, FAIL, FAIL, FAIL, PASS. #421:
FAIL, PASS, FAIL (cache rule), FAIL, PASS. Docs PR #444: FAIL, FAIL, PASS (both failures were steps
in NEEDS_PETER that would have broken CI or the automatic release if followed).

CI (`ci.yml`, created to last update), 27 runs on the four code PRs: 11 green (19.9 to 33.8
minutes; #416 three, #417 two, #418 four, #421 two), 2 failed on a flake (below) and 14 were
cancelled, each by the next push of a fix round or by the rebase a land made. One on-demand e2e
run (`tests/boot.spec.ts` on #421's branch): 10.7 minutes (run 43497126475).

Merge lock (times CET; every wait includes the 30 minutes `merge-lock` waits for the Mac lock,
which was unreachable all night):

| PR | Queued | Lock held | Waited | Held | Outcome |
| --- | --- | --- | ---: | ---: | --- |
| #416 | 21:19 | 22:46 | 88 min | 25 min | merged 23:12 |
| #417 | 22:06 | 00:31 | 145 min | 22 min | merged 00:52 |
| #421 | 22:36 | 00:52 | 137 min | 28 min | merged 01:20 |
| #418 | 22:56 | 01:40 | 165 min | under 1 min | rebase conflict with #421, which had merged 20 minutes before |
| #418 | 06:36 | 08:17 | 101 min | 31 min | no merge: CI took 33.5 minutes, `merge-pr.sh --wait` gives up after 30 |
| #418 | 08:53 | 10:08 | 75 min | 27 min | merged 10:34 |

Waited: 711 minutes in all (the queues overlapped). Held: 133 minutes, of which 31 landed
nothing.

Release jobs after #421 took the Actions cache out of them (job time from start to end, medians
of the 10 release runs before the merge and the 6 after, all on 13 and 14 November):

| Job | Before | After | Reading |
| --- | ---: | ---: | --- |
| `plan` | 32 s (26 to 46) | 55 s (47 to 58) | Slower. Over all green release runs of those days, most of which run `plan` only (20 before, 9 after): 31 s (25 to 50) and 54 s (43 to 65) |
| `android` | 572 s (464 to 668) | 564 s (540 to 698) | No difference seen |
| `ios` | 858 s (719 to 1,576) | 986 s (721 to 1,334) | Not decided: the ranges overlap almost fully |

### Flakes seen

Neither PR touches the app, the e2e tests or the function under test; both reruns were a new
push, not a retry of the same commit. No other run on this job's PRs failed.

- `e2e (2)`, `[chromium] tests/mcp.spec.ts:203`, run 43499255912 (#418): the MCP SDK's
  `connect()` hung for about 52 s; the trace reports no host stall.
- `e2e (2)`, `[firefox] tests/wasm-boot.spec.ts:71`, run 43500256507 (#421): "could not scroll
  ... Brot into view".

### What the rounds taught

- **A check's PR text should list forms, not promise completeness.** The last failed rounds of
  #418 (rounds 3 and 4) and of #421 (the cache rule's own round and round 3) each reported one
  more form the check missed, found against a sentence that said "every" or "the one place".
  After the texts listed what fails and what is known to pass, the next round of each passed
  (#421 round 4, #418 round 5) and reported the forms still open as notes, which the texts now
  list. The rounds were not wasted: each closed a form Deno or GitHub really accepts (a JSX
  pragma that resolves a range, `cache-jdk`, `export ... from`), with a probe that showed it.
- **Mutation lists catch what a reviewer would otherwise find.** Every allow-list or pattern
  finding that failed a round was a mutant no test killed. Running the reviewer's mutants before
  asking for the next round took one to two minutes per list.
- **Small PRs cost a CI run and a lock hold each.** Five PRs at about 30 minutes of CI and a
  shared lock is why the cache rule went into #421 instead of a PR of its own (DECISIONS,
  Job 220).
- **Two PRs that add a row to the same table collide at the land, not before.** #418 and #421
  each add a lint row to `AGENTS.md` and three lines to `scripts/lint.sh`. The second to land
  stopped in its rebase inside the lock. The session was not running then, so it sat for 4 h 52
  min until the next check found it; keeping both sides took two minutes. One PR for both
  checks' lint wiring, or landing the second right after the first from one script, would have
  saved a lock hold and a CI run.
- **`merge-pr.sh --wait` gives up after 30 minutes; a green CI run took up to 33.8.** One lock
  hold of 31 minutes landed nothing. This job's land script then waited a second time while a
  check was still pending. The setting for it existed all along and this job missed it:
  `MERGE_WAIT_MINUTES` (default 30, `docs/CI.md`). A land with `MERGE_WAIT_MINUTES=40` would
  have merged in that hold. The default is the lead's call (NEEDS_LEAD, Job 220).
- **A stay-off file still gets a recorded finding and a fence.** `supabase-deploy.yml` could not
  be changed here; the allow-list entries name exactly what is excepted, fail when stale, and the
  done doc carries the fix for the job that owns the file.

## Job 219: verification tooling, 2026-11-14

The brief: make the checks an agent runs after an edit objective and reproducible, with a bounded
fix loop; fix the evidenced flakes and slow steps that dominate that loop; keep recurring local
fixes as narrow recipes. No gate weakened, no quality score added. The mining scripts, the raw
tables, the review reports and the flake evidence are in the job's research folder
(`research/219-verify-skill-tooling/`, out of tree); the paths below are relative to it.

### Baseline

Measured on 13 November 2026, before this job changed anything. The files are in the job's research
folder (`research/219-verify-skill-tooling/baseline/`, out of tree). `summary.md` mines 399
transcript files of 199 jobs (30 October to 13 November), `ci-summary.md` reads 14 days of `ci.yml`
runs from the GitHub API, and `gates-run1.tsv` times each gate script once.

**What runs where** (`scripts/verify.sh`, `scripts/ci-changes.sh` and `ci.yml` on main `aa953203`).
`verify.sh` runs 14 gates in the table's order and stops at the first that fails. `ci.yml` has 19
jobs: 16 gate jobs (e2e in two shards with a stack each), `changes`, `keepalive-schedule` and
`ci-ok`, the one required check. `android` and `ios` run locally only when `--only` names them.

| Gate | Local, s | CI median | CI p90 | CI runs it |
| --- | ---: | ---: | ---: | --- |
| gitleaks | 11.6 | 0:24 | 0:29 | always |
| lint | 101.4 | 2:00 | 2:18 | always |
| changelog | 0.3 | 0:11 | 0:14 | on pull requests |
| site | 25.2 | 0:42 | 0:47 | always |
| site-agent | 31.6 | 0:59 | 1:35 | always |
| emails | 4.4 | 0:18 | 0:23 | when the mails' sources or outputs change |
| db | 145.0 | 3:22 | 3:43 | heavy |
| functions | 27.3 | 0:41 | 0:47 | heavy |
| nexus | 3.6 | 0:17 | 0:22 | heavy |
| fg-cli | 5.4 | 0:19 | 0:23 | heavy |
| flutter | 197.2 | 5:13 | 6:03 | heavy |
| web-prod | 88.8 | 2:16 | 2:37 | heavy |
| fastlane | 1.9 | 0:14 | 0:20 | when `app/fastlane/` or the Gemfile changes |
| e2e | not timed | 15:51 and 17:08 | 18:20 and 23:15 | heavy, shards 1 and 2 |
| android | CI only | 4:34 | 5:25 | native |
| ios | CI only | 23:42 | 32:06 | native, on macOS |

- "Heavy" is any change that is not documentation only, "native" one to the native projects, the
  pubspec or the two gate scripts. A push to main or a change to the CI definition runs all.
- Local is the gate script alone, one run on the shared box at `9efe6c19` (load average 2.76 to
  14.72 at a gate's start), so a reading and no distribution. The 13 timings sum to 643.7 s.
- CI is the whole job with its setup in green first attempts, from the 77 code runs, for emails,
  fastlane, android and ios from the native runs (n 50, 100, 110, 110). `ci-ok` ends with the
  slowest job, `e2e (2)` in code runs (17:32, p90 23:47) and `ios` in native runs (24:48, 32:39).

**CI wall time to `ci-ok` and failed first attempts** (the cap set, the 400 most recent completed
runs, 7 to 13 November. Times are m:ss from the run's start, over first attempts that succeeded).

| Run class | n | Median | p90 | Max | First attempt failed |
| --- | ---: | ---: | ---: | ---: | ---: |
| docs (the heavy gates were skipped) | 53 | 2:12 | 2:32 | 3:23 | 5.4 % |
| code (e2e ran, ios did not) | 77 | 17:40 | 23:53 | 25:29 | 22.2 % |
| native (ios ran) | 110 | 24:53 | 32:44 | 46:54 | 17.9 % |

**Failures per CI job** (cap set, first attempts that ended in success or failure).

- `ci-ok` failed in 47 of 289 first attempts (16.3 %). 7 of the 47 passed on a rerun of the same
  commit (14.9 %), a lower bound of the flake share, because most failures get a new push instead.
- Per job: `e2e (2)` 18 of 233 (7.7 %), `e2e (1)` 16 of 232 (6.9 %), `site` 6 of 289 (2.1 %),
  `flutter` 4 of 233 (1.7 %), `ios` 2 of 131 (1.5 %), `lint` 3 of 289 (1 %), the others under 1 %.
- Reruns over the whole window (1419 runs, 61 rerun): `e2e (1)` went green in 22 of 23, `e2e (2)`
  in 13 of 15, `ios` in 4 of 5, `db` in 3 of 3. 46 of 69 failed `e2e (1)` jobs were never rerun.

**The e2e tests that failed most** (whole window, the 103 failed e2e jobs with at most 3 failed
tests. "Ran" counts shard results of the cap set only, so it is no denominator for "Alone").

| Alone | Rerun green | Branches | Last 7 d | Ran | Test |
| ---: | ---: | ---: | ---: | ---: | --- |
| 12 | 5 | 7 | 0 | 250 | `classifier.spec.ts`, seed dictionary spot checks |
| 12 | 5 | 11 | 12 | 249 | `mcp.spec.ts`, MCP over OAuth 2.1 |
| 8 | 3 | 7 | 7 | 188 | `integration-lock.spec.ts`, locked household |
| 7 | 5 | 7 | 0 | 250 | `add-sheet.spec.ts`, a tap adds the row with every field |
| 6 | 0 | 3 | 1 | 249 | `stores.spec.ts`, category and store layout changes sync live |

- The classifier and add-sheet rows are two app bugs that #156 and #205 fixed on 1 and 2 November,
  and 6 of the 8 integration-lock failures are a race that #370 fixed on 12 November.
- The MCP test is the live one. All 12 hang in the same step, after `5062100c` (#260) changed the
  edge runtime's policy. The mcp shard had 0 hangs in 542 executions before, 15 in 420 after.

**The local loop** (`summary.md`. 8826 verification runs, 4171 passed, 1996 failed, 2659 unknown).

- A job ran a median of 26 verification commands and 5 failed (13 and 2.5 in the latest 30 jobs).
  Verification is a median 76 % of a job's wall time. The median wall is 2.1 h, the wait 0.9 h.
- Waiting for CI took 172.7 h in 188 jobs and the merge lock 55.8 h in 36 jobs, of 602.4 h wall
  over all jobs. `verify.sh` with several gates blocked 11.8 h in 475 runs (median 77 s, p90 196 s).
- 28 of the 206 failed `verify.sh` or gate runs did not show which gate failed, and 79 of 754
  foreground runs showed neither pass nor fail (tail, grep or head cut the output).
- The 206 by cause, from the message text alone: product 97, unclear 49, timeout or flake 1,
  environment 59 (`stale-migrations` 17, `deno-lock-fmt` 12, `host-fake-oidc` 12, `format-drift` 6,
  and smaller classes). By gate: e2e 57, lint 43, db 33, flutter 17, site 12.
- 32 fail-then-pass pairs of one command had no file change in between (11 of them no environment
  action either). They are 4 `verify.sh` or gate runs (lint 2, android 1, db 1), 14 direct test
  tools, 11 `merge-pr.sh --wait` and 3 `push-pr.sh`. A pair is evidence of a flake, not proof.
- Red streaks that a pass ended, p90 length per gate: db 4, e2e 3, flutter, site, functions and
  nexus 2, lint, gitleaks and fg-cli 1, the other five none.

**Escaped failures** (`ci-summary.md`, "Failures on pushes to main", whole window. Main takes a
commit only with `ci-ok` green, so these failed on commits whose PR run was green).

- 25 jobs failed in push runs on main: `e2e (1)` 10, `ios` 7, `e2e (2)` 3, `db` 3, `android` 1,
  `gitleaks` 1. 24 were not rerun and 1 went green on a rerun. The next push was green after 19.
- By signature: 8 the add sheet that did not open (to 1 November), 5 ios without a simulator, 4
  download or docker faults, 2 each the MCP timeout, integration-lock and StoreKit tests, 2 other.
- `known-flakes.md` lists 14 documented escapes of another kind, defects found after a green gate.

**Not measured**

- A local time for e2e, android and ios, and the e2e-lock wait inside a foreground `verify.sh`.
- The verdict of 155 of 819 background or detached runs nobody read back, verification inside
  scripts the transcript never shows, its tokens and cost, and causes beyond the message text.
- Job data of the 1013 older CI runs the cap cut off (per-job timings and failure rates, e2e
  artifacts), and 31 cap-set jobs that failed in an attempt a newer push cancelled (lint 11).
- Flakes that pass inside one job (Playwright's flaky status is 0 in 491 shard results by design),
  the mechanism of a failure seen after its fix, and the request that hangs in the MCP timeout.
- Escapes to production beyond the docs, workflows other than `ci.yml`, and the length of Monitor
  and ScheduleWakeup waits.

### What landed

Eight PRs, one commit each. Each has a test in a gate, a `claude-fable-5-2` review that ended in
PASS and `ci-ok` green on the merged head. A ninth, docs only, carries this section and one
sentence for `AGENTS.md` and `docs/CI.md`: a land whose CI run has the ios job waits with
`MERGE_WAIT_MINUTES=45` (23 of the baseline's 110 green runs with ios took over 30 minutes to
`ci-ok`, the default wait; one took over 45).

| PR | Merged as | Change | Evidence it rests on |
| --- | --- | --- | --- |
| #420 | `86d5d8c5` | `verify.sh` ends on a plain verdict line, keeps each gate run's output in its own file, times each gate, keeps a ledger and notes a gate with both results on one tree or three failures in a row; `--history` | 28 of 206 failed local runs hid the gate, 79 of 754 hid the result, 620 calls stripped colour by hand |
| #423 | `31a0de87` | a failed e2e job keeps every stack container's log with timestamps; `ci-timings.sh --steps e2e` finds the shards | two flake causes ended at "no log in CI"; no MCP hang could say which container held the request |
| #439 | `7c3e2faf` | the gates that run Flutter require CI's version and name the fix (`scripts/install-flutter.sh`); the schema check no longer reports a migration main gained after the branch left it as deleted | 3.47.8 on the box against CI's 3.50.0: 4 lockfile changes and 1 analyzer error CI does not have; "is on main and was deleted" in 12 jobs |
| #440 | `f80960a7` | a function behind `withTelemetry` reads the request's body before it answers; the MCP specs' requests fail after 15 s with the request named; a finished answer keeps its Content-Length | the mcp shard hung in 15 of 420 runs since #260, in 0 of 542 before |
| #441 | `868340c2` | five e2e tests wait until the server took a tick before they reload (`tickSaved`) | `wasm-boot.spec.ts` failed twice on WebKit in CI; the one trace read (run 43503369675) has the tick lost |
| #442 | `789ffd6a` | the e2e gate resets a running stack whose applied migrations are not the checkout's | job 168c's ten spec files over a stale stack; 28 of 203 jobs reset by hand (124 commands) |
| #445 | `78659c8f` | recipes in the verify-snacklist skill, named by the FAILED verdict (`seen before? <recipe>`); the skill's "Gates" section; first recipe: the fake sign-in provider the runner's containers cannot reach | at least 20 of 199 jobs have local failed lines of the ten tests it covers |
| #451 | `43453367` | the fg-cli gate's test ends the one process it started, and a bystander `sleep 20` must outlive it; `merge-pr.sh --wait` goes on, and says so, when a signal ends only its sleep | the test's `pkill -f '^sleep 20$'` ended every `sleep 20` on the machine, the poll of `merge-pr.sh --wait` among them: #445's land exited 143 twice in the seconds another job's fg-cli gate ran; by 17:25 on 14 November seven jobs' transcripts held a wait for `ci-ok` that ended "Terminated" |

Looked at and left alone, with the reason:

- The integration-lock, deep-links and club e2e flakes were fixed before this job (#370, #314): 0
  of 79, 0 of 247 and 0 of 81 runs since their fixes (`flakes/lock-deeplinks/diagnosis.md`).
- CI's shape (shards, the ios job's phases) is job 221's.
- A finer table from changed files to gates for `verify.sh`: the local gates are 2 % of the jobs'
  wall time (11.8 h of 602.4 h), and a wrong table gives false greens.
- A retry anywhere. No test, gate or request got one.

### Before and after

Measured, on the runner or in CI's artifacts:

| What | Before | After | How measured |
| --- | --- | --- | --- |
| A failed `verify.sh` run shows which gate failed | 178 of 206 | every run, as its last line | before: transcripts; after: by test (`scripts/verify-test.sh`, a 40 MB burst, a left-over server and two runs at once among the cases), no count yet |
| A POST with an unread body gets no byte back in 3 s (local stack, edge runtime on one core) | 55, 53 and 49 of 150 on three functions; 11 of 300 SDK connects got a late 503 | 0 of 150 on each; 0 of 1000 SDK connects | `e2e/early-answer-probe.mjs`, `flakes/mcp-oauth/repro/counts.tsv` |
| The two MCP e2e tests, 15 times each, runtime on one core | 29 of 30 (the body read removed) | 30 of 30 | `--repeat-each 15 --workers 2 --retries 0` |
| A hung MCP request in CI | the test's 60 s timeout, nothing named | `no response headers after 15005 ms: POST <url>` | the failing run without the body read |
| An e2e run on a stack one migration behind | fails as if the app were broken (job 168c: about 14 tests) | resets and passes: 109 s with a cold web build, 38 s warm, against 19 s with nothing to reset | `flakes/stale-stack/` |
| The flutter gate on the runner without `FLUTTER_DIR` | ran 3.47.8: 4 lockfile changes, 1 analyzer error CI does not have | passes on 3.50.0 | `env -u FLUTTER_DIR scripts/verify.sh --only flutter` |
| The schema check on a branch one migration behind `origin/main` | exit 1, "is on main and was deleted" | passes with a note to rebase | scratch clone, forced before and after |
| The cause of a CI hang, from the run's own artifacts | not readable in any of 15 hangs | read to the request in run 43566212940, the first hang the job read after #423 (run 43552637024 on main hung 2.8 h earlier; its logs are saved and unread) | trace, edge runtime log and Kong log of that run |
| The three specs that tick and reload, three times each | no local failure on record (CI: 2) | 54 of 54 | `--repeat-each 3 --retries 0` |
| An e2e run on the runner that fails in the fake sign-in provider's tests | nothing in the output names the cause; 8 of the 18 jobs counted at #445's second review called it known at their first mention | the verdict ends `seen before? .cursor/skills/verify-snacklist/recipes/e2e-fake-oidc-unreachable.md` | the real gate on `id-token.spec.ts` (6 failed, 156 s); `scripts/verify-test.sh` |

What the job's own tests cost the lint gate, measured:

- On the runner, three alternating rounds of `scripts/gates/lint.sh` (load 1.2 to 2.6): 78.8,
  79.0 and 85.7 s at `fe56ff6e` (main before #420, with #423), 108.5, 108.6 and 108.6 s with
  #420, #439, #442 and #445's first version applied (`measurements/lint-ab.tsv`). So 23 to 30 s
  more. `scripts/verify-test.sh` alone takes 28.9 to 29.0 s as merged with #445 (three runs,
  `measurements/verify-test-time.txt`): its cases wait on real seconds for the lock-wait and
  left-over-server checks, and it runs `verify.sh` once for every line of a recipe's Example.
- In CI the lint job took a median 120.5 s on the 30 pushes to main before #420 (95 to 150 s)
  and 146.5 s on the 10 from #420 to #442 (125 to 184 s). Not this job's alone: #418 changed
  the lint gate in the same window.

Not measured, and why:

- CI's failure rates after these PRs. `ci-ok` failed 16.3 % of first attempts in the baseline and
  the mcp shard hung in 3.6 % of its runs since #260. The tick-and-reload tests failed twice, once
  in the baseline and once on this job's #423. The fixes reached main on 14 November; a rate
  needs a week of runs. `ci-summary.md`'s script reads it again (`scripts/` in the research
  folder).
- The gates' local times after these PRs, apart from lint above and the e2e gate's reset. The
  baseline has one reading per gate; the ledger #420 added now collects one per run (the flutter
  gate, which #439 moved to CI's SDK on the runner: its 10 passes in the ledger
  by 18:15 CET on 14 November took 127 to 214 s, against the baseline's one reading of 197.2 s
  and under other loads).
- How many lands the fg-cli test's kill by name ended before #451. By 17:25 CET on 14 November
  seven jobs' transcripts (162, 204c, 212, 213, 229, 236 and this one) hold a `waiting for ci-ok`
  that ended "Terminated": one wait each, two for this job
  (`measurements/merge-pr-terminated.txt`). Three are matched to a gate run by the ledger:
  this job's two, and job 236's, which ended before `ci-ok` on its head turned green at 16:18:54,
  most likely at 16:17:00 in job 231's fg-cli gate (3 s, done 16:17:02). That is the second
  this job's third land of #445 got the lock, so that turn began early at job 236's cost. Job
  229's ended between 16:41 and 17:00; job 215's gate (done 16:51:44) is the likely sender, not
  proven. A land that ran detached wrote to a log file and is not counted unless the session
  printed that log, and the baseline's 11 `merge-pr.sh --wait` fail-then-pass pairs were not
  split by cause.
- How often the verdict line, the ledger's notes and the recipe change what an agent does next.
  The ledger had 100 rows by 13:10 CET on 14 November: 55 from this job's branches and 45 from
  eight other jobs' branches, the first of those at 10:24. The 45 are 39 passes and 6 failures,
  all of the db gate. One tree has both results (job 225c: db failed after 35 s and passed
  after 124 s two minutes later), and job 229 has five db failures in a row over four trees, so
  both notes were printed at least once outside this job. What those jobs did next was not
  read.
- The hosted project. Whether it loses an early answer the way the local runtime does was not
  probed.
- The share of the 124 hand resets that a stale stack caused.

### Cost

Measured where a counter exists; anything else is labelled.

- **Lead time.** Started 13 November 19:47 CET; #451, the last change, merged 14 November
  18:15: 22.5 h. For 6.9 h of it (23:38 to 06:32) the job was stopped by the usage
  limit (`limit-blocked`), while two detached lands went on.
- **Tokens, run 1** (to the stop; the CLI's result line): 494 turns in 3.83 h, input 113,787,
  output 2,740,776, cache read 176,846,944, cache creation 7,952,450; 67.64 USD at the CLI's
  prices.
- **Tokens, run 2** (from 06:32; read from the transcript stream at 18:15 CET, which has no
  full output counts and no price): the main thread 907 messages with cache read
  101,092,159 and cache creation 2,847,822; subagents 1,093 messages with 105,812,879 and
  5,544,016.
- **Subagents**, inside those totals: 4,189,449 tokens over the 45 runs that
  handed a total back (reviews and delegates, both runs of the job; read from the session
  transcript at the same time, `measurements/subagent-tokens.tsv`). Two of the
  47 subagent transcripts have no total there.
- **Reviews.** 38 rounds of `claude-fable-5-2` over the eight PRs before each PASS: #420 5,
  #423 5, #439 7, #440 4, #441 3, #442 4, #445 6, #451 4. Each FAIL named a measured
  defect, a sentence of the PR that claimed more than its test pinned, or a figure in the
  description that did not match its source. #445's rounds were
  mostly the second kind, until its test compared whole outputs in place of single lines. This
  record had five rounds of its own; the first found the sender of the signal that
  ended #445's land, which the author had searched for and not found, and so #451. #451's
  first review in turn showed that the test's fix alone reaches a checkout only when it
  rebases, and that a wait in `merge-pr.sh` which logs the signal hides nothing; its second
  that the new test passed for a wait that never looked at `ci-ok` again. Its third reviewer ran
  an old checkout's fg-cli gate by mistake (a `cd` that went into the background with the list
  it led) and so sent the kill itself, at 16:24:00: it ended the wait of #445's land, which the
  land script started again, and two waiting loops of job 236's session, which went on. The
  fourth brief asked for absolute paths in every command and nothing in the background.
- **CI.** `ci.yml` ran 35 times on the eight PRs' branches: 26 green, 5 red and 4 cancelled by a
  newer push. A green run took 18.9 to 40.8 min from its creation (median 23.4). Per PR: #420 9 (6
  green, 2 red, 1 cancelled), #423 6 (2 green, 1 red, 3 cancelled), #439 2 (2 green), #440 2 (2
  green), #441 2 (2 green), #442 2 (2 green), #445 7 (5 green, 2 red), #451 5 (5 green). Of the
  five red runs one was #420's own new test (the burst of output, fixed before the merge). Two were
  defects this job fixed in another PR: the lost tick (#423's run, the trace #441 rests on) and the
  MCP hang (#420's second land). The two on #445 were the schema check's "is on main and was
  deleted" while #445 was stacked on #442's branch, which was behind main: CI checks out a shallow
  clone of the merge into that branch, where the check finds no merge base and #439's relief does
  not apply. That is a limit of stacked PRs #439 left open; the next run, with #445 on main, was
  green.
- **Not measured:** output tokens and price of run 2, the subagent runs without a total, and
  the job's share of the runner's load.

The lands, all under the Hetzner-only merge lock (times CET, 14 November unless said; queued is
when the land's log file was created):

| PR | Queued | Lock | Done | Waited | Held | Result |
| --- | --- | --- | --- | ---: | ---: | --- |
| #423 | 13 Nov 23:19 | 01:41 | 02:07 | 2 h 22 min | 26 min | merged |
| #420 | 13 Nov 23:19 | 02:07 | 02:39 | 2 h 48 min | 32 min | `merge-pr.sh` gave up after its 30 min; `ci-ok` turned green 2.6 min later (the ios job started 4.7 min into the run and ran 28.9) |
| #420 | 06:35 | 07:24 | 07:51 | 50 min | 26 min | `ci-ok` red: the MCP hang, the first one read to its request (the cause #440 fixes) |
| #420 | 07:52 | 08:48 | 09:09 | 56 min | 21 min | merged |
| #441 | 09:12 | 10:34 | 10:59 | 1 h 22 min | 25 min | merged |
| #439 | 09:12 | 10:59 | 11:24 | 1 h 47 min | 24 min | merged |
| #440 | 09:12 | 11:24 | 11:46 | 2 h 11 min | 22 min | merged |
| #442 | 11:24 | 12:40 | 13:07 | 1 h 16 min | 27 min | merged |
| #445 | 13:10 | 14:07 | 14:21 | 56 min | 15 min | ended by the fg-cli test's kill by name 14 min into `merge-pr.sh`'s wait ("Terminated", exit 143); `ci-ok` turned green 7 min later |
| #445 | 14:22 | 14:56 | 15:05 | 34 min | 9 min | ended the same way 9 min into the wait (exit 143), by another job's fg-cli gate |
| #445 | 15:05 | 16:17 | 16:40 | 1 h 11 min | 23 min | the wait was ended once (16:24:00, by this job's own reviewer) and started again by the land script; then `gh pr merge` got a 502 from GitHub 20 s after `ci-ok` turned green (exit 1, the PR still open) |
| #445 | 16:41 | 17:11 | 17:32 | 30 min | 21 min | merged |
| #451 | 17:03 | 17:54 | 18:15 | 51 min | 21 min | merged |

Every wait begins with the 30 to 38 minutes `merge-lock` tried the Mac lock, which was unavailable
at each of these turns (its log: "tunnel down?"). The waits sum to 17.6 h and overlap where
several of the job's PRs queued at once. 5 of the 13 turns merged nothing: one to
`merge-pr.sh`'s 30 minutes, one to the MCP hang, two to the fg-cli test's kill by name
(#451) and one to a 502 from GitHub on the merge call. The land of this section's own PR is not
in the table.

### For the lead

Ten points are in `docs/NEEDS_LEAD.md`, "Job 219". The three that cost this job the most: the
wait at the merge lock (the table above), `merge-pr.sh --wait` giving up after 30 minutes when
the ios job needs longer (now a sentence in `AGENTS.md`; the default is the lead's), and the
lands that the fg-cli test's kill by name ended (fixed by #451; the point says what is left). A
fourth lost one turn: a 502 from GitHub on the merge call (not fixed; the point names the fix).
Two are about the product or production and were not probed: a tick right before a reload, and
whether the hosted edge runtime loses an early answer.

## Job 221: CI wait and list CPU, measured, 2026-11-15

The brief: baseline the CI and build wall time, the app's startup and the list's in-memory work
with real commands, and land small changes that make the loop or the app faster, each with a
measured before and after. No check weakened, no behaviour changed, no closed climb redone
without a measured gap. The scripts, the raw tables, the review reports and the mutant scripts
are in the job's research folder (`research/221-perf-iteration-hillclimbs/`, out of tree); the
paths below are relative to it.

### Baseline

Measured on 14 November 2026, before this job changed anything.

**CI** (`scripts/ci-timings.sh --limit 12 --branch main --steps e2e`: the 12 green `main` runs
created on 14 November from 12:07 to 17:53 UTC; `baseline/ci-timings-main-before.txt`). Running
time of a job, the queue not counted:

| Job | Median | Range |
| --- | ---: | --- |
| ios | 28:45 | 11:36-32:54 |
| e2e (2) | 19:53 | 18:19-24:24 |
| e2e (1) | 17:19 | 14:55-18:21 |
| flutter | 5:14 | 4:27-6:25 |
| android | 3:34 | 3:08-4:17 |
| db | 3:23 | 3:10-3:34 |
| lint | 2:40 | 2:13-3:04 |
| web-prod | 1:59 | 1:39-2:20 |
| each of the other nine gates | under 1:05 | |

`ci-ok` turned green 29:17 after a run's start (20:08-33:28). All 12 runs had the ios job, since
a push to `main` runs every gate. In 9 of the 12 the ios job ended last. In the other 3 `e2e (2)`
did (ios ended 22:36, 11:49 and 12:57 after the run's creation there, and `ci-ok` came after
23:40, 20:17 and 20:08). So two things set the wait: the ios job in most runs that have it, and
the slower e2e shard in the rest and in every run without ios. #460's texts say that a run with
the ios job "still waits for it" (`docs/DECISIONS.md`, and `docs/CI.md` until this record's PR
corrected it there); that held in 9 of these 12 runs.

Which of the two a PR waits for, by the filter's rule (`scripts/ci-changes.sh` of 14 November
applied to the full file list of each of the 136 PRs merged from 7 November to 14 November 19:13
UTC, `baseline/v3/`; a replay of the rule, not a count of what ran): 74 run e2e without the
native gates, 32 run the native gates (14 for a native path, 18 for the CI definition), and 30
changed only documentation and run no e2e.

The ios job's phases in 8 of the 12 runs (`baseline/ios-phases-main-before.txt`): build 2.3 to
5.2 min, simulator boot 1.6 to 8.9, tests 0.8 to 4.2, the StoreKit boot 1.2 to 6.3 and its tests
3.1 to 8.7. The two runs that took 11 and 12 minutes were faster than each of the other six in
the build, both boots and the StoreKit tests (not in setup, and one of them not in the tests
phase), so the spread looks like the runner's and not one step's (inferred from those two runs;
not traced).

**Startup** (job 100's harness `tool/hillclimb/hc-size-start/measure.sh`, repaired by #470, on
`main` a0cd3c73; Linux profile build, three runs of 15 launches at load 6 to 7): first frame 267,
288 and 346 ms, list interactive 368, 401 and 536 ms. Job 100 measured 292 and 445 ms with a
noise band of 0.128. No gap outside the spread, so nothing changed there.

**The list's in-memory work** (the new harness `tool/hillclimb/hc-list-cpu/measure.sh`, Linux
profile build, the hc-ui-perf household of 300 open items in 10 stores):

- What one build of the list derives: about 0.2 ms (0.18 to 0.75 over 20 launches of the
  branch's probe binaries; 0.18 to 0.30 in the `main` binary's seven launches). Not hot.
- One tick and the text of its save: 4.54 ms on the UI isolate (the table below). `ListCubit`
  saves when an op is queued and again when the server acknowledges it, and each save built
  the whole list's JSON.

**Frame times** (job 108's harness `tool/hillclimb/hc-ui-perf/measure.sh`, repaired by #470): two
runs on `main` scored 133 and 161 against job 108's 7.479, at load 10 to 15. Job 108 started a
measurement only below load 3.5 and repeated one that ended above 6, so they are no verdict, and
the size of the gap is not explained.
The probe now scrolls a store divider into reach before it taps it, so its sections flow can
hold scroll frames that job 108's did not.

Not measured in the baseline: the local gates' times (job 219's baseline above has one reading
per gate, and `scripts/verify.sh --history` collects one per run since #420), a phone, the web
build's startup, and the Android download size (job 100's other number).

### What landed

Four PRs, one commit each. Each has a `claude-fable-5-2` review that ended in PASS and `ci-ok`
green on the merged head. A fifth, docs only, carries this section.

| PR | Merged as | Change | Evidence it rests on |
| --- | --- | --- | --- |
| #472 | `88d0fbdc` | the declutter total test prices its item today (`pricedAt: DateTime.now()`) | from 15 November 00:00 on the test failed on untouched `main` 46f0ae0d (one run of the file on the runner, 15 of 16 tests passing) and in 8 of 8 runs of the file on #470's branch: its price was dated 14 November, and a price counts on its calendar day only |
| #462 | `f96c2ecf` | a PR that changes only another gate's script runs neither android and ios nor fastlane and emails; `scripts/siri-vocabulary.py` and `scripts/app-shortcuts-bundle.py` join the native rule; the filter reads the range with `--no-renames`; the filter's first test, `scripts/ci-changes-test.sh`, in the lint gate | `android.sh`, `ios.sh`, `fastlane.sh` and `emails.sh` source only `scripts/lib.sh`; 10 of the 136 PRs ran the ios job for a change to `db.sh`, `lint.sh`, `functions.sh` or `site-agent.sh` |
| #460 | `07e1ad35` | CI runs the e2e suite in four shards (`ci.yml`, and `e2e.yml` for an on-demand full suite; `scripts/ci-e2e.sh --shards 1..6`); `scripts/check-gates.sh` holds the lines the count travels on; `scripts/ci-timings.sh --steps` prints a true median | 74 of the 136 PRs wait for the slowest e2e shard |
| #470 | `6877ea5a` | the save after a tick, an add or an edit encodes the changed row, not every row (`ListSnapshot.encode()` keeps each item's JSON text with its `Item`); the device cache asks for the text after its household check; the harness `hc-list-cpu`; `hc-size-start` and `hc-ui-perf` run on `main` again | on `main` the save's text was 4.3 of the 4.5 ms that a tick and its save's text took on the UI isolate (the probe's per-save counter, 4,317 µs in the median of the seven launches) |

Looked at and left alone, with the reason:

- **Shards packed by test duration.** Replayed from five `main` runs, the slowest of four takes
  457 s against 513 s. One real shard moved by 3 minutes between two runs of the same commit,
  and a planner needs a durations file kept current. Not built.
- **Six shards.** 385 s in the replay, about 2 minutes under four, for two more stacks per run.
  No real run, and the 20 jobs that run at once come closer. `scripts/ci-e2e.sh --shards 6`
  can measure it.
- **The ios job's phases.** The spread is across all phases of a run (above), and jobs 118, 127
  and 164 already worked on the steps. No change tried; the point is with the lead.
- **Startup and what a list build derives.** No measured gap (above).
- **Frame times.** No valid run at the runner's load.
- **Other Playwright worker counts than 2.** Not measured.

### Before and after

| What | Before | After | How measured |
| --- | --- | --- | --- |
| The slowest e2e shard's job, running time | 19:53 (18:19-24:24, 12 `main` runs with two shards) | 14:55, 12:33, 14:25, 11:35 and 12:51 (five runs with four shards) | `ci-timings.sh` before; after, the jobs' start and end in #460's CI runs 43632050929, 43664324552 and 43667672579, its on-demand run 43640061280 and #470's CI run 43669960494 (`record/ci/run-jobs.txt`) |
| Linux runner time of all e2e shards per run | 37:12 (the two medians) | 46:28, 44:01, 47:16, 41:59 and 44:17 | the same runs |
| `ci-ok` after a run's creation, for a PR without the native gates | 21:24 and 23:48 (#470's first run 43645275754 and #472's run 43654001792, two shards) | 13:49 (#470 rebased, four shards, run 43669960494) | this job's three such runs (`record/ci/ci-ok.tsv`); one run after, so no median |
| The same for a run with the ios job | 29:17 (20:08-33:28, the 12 `main` runs) | 28:37, 24:43 and 28:50 (#460's three CI runs) | the ios job ended last in all three, 8 to 17 minutes after the last shard, so these three gained nothing; in 3 of the 12 runs before, `e2e (2)` ended after ios, so a run with a fast ios job does gain |
| Tests the shards run | 271 | 271 in each of the five runs, none failed, flaky or retried | the first two runs' `playwright-results.json`; Playwright's summary lines in all five runs' job logs |
| PRs for which the filter turns android and ios on | 32 of 136 | 22 of 136 | the script before and after on each PR's full file list |
| The same for fastlane, and for emails | 28 of 136 each | 15 of 136 each | the same |
| The same for the heavy gates | 106 of 136 | 106 of 136 | the same |
| A file moved from `app/ios/` to `docs/` | neither heavy nor native gates | both | `scripts/ci-changes-test.sh`; a depth-2 fetch of a merge ref in review 2 |
| UI-isolate time of one tick and its save's text | 4.54 ms (3.83-5.87) | 1.11 ms (0.99-1.48) | seven alternating pairs of launches, `main` 46f0ae0d against the branch, 40 timed ticks per launch after 20 warm-up rounds, load 3 to 14 (`runtime/listbench-main2-vs-final2.jsonl`) |
| The same for an untick | 4.32 ms (3.66-6.25) | 1.01 ms (0.97-1.22) | the same |
| The first save after a load or a resync (every row a new `Item`) | 2.86 ms (2.60-4.46) | 3.41 ms (2.98-6.67) | the same seven launches of the new binary, whole encode against kept texts |
| `list_declutter_test.dart` from 15 November | 15 of 16 tests pass | 16 of 16 | `flutter test test/list/list_declutter_test.dart` on `main` 46f0ae0d (one run) and on #472's branch, where the flutter gate then passed |

What the ten spared PRs cost when they ran (measured from their CI runs,
`baseline/v3/spared-runs.tsv`): their 27 runs with a finished ios job took 627 macOS runner
minutes, and in 23 of them `ci-ok` waited for ios after every other job had ended, 186 minutes
in all. For the files each of those runs had changed, the new rule leaves ios off.

What the changes cost:

- Four shards take 5 to 10 more Linux runner minutes per run (4:47 to 10:04: the five runs
  above against the two medians before; #460's text says 7 to 9, from the first two), and a run
  has four stacks that can fail to start instead of two.
- The first save after a load or a resync is 0.4 to 3.6 ms slower per launch (the row above). A
  start with a saved list that reaches the server pays it at least twice. `docs/DECISIONS.md`,
  "Job 221: the save after a tick", says when.
- The kept texts stay in memory with their items, about the size of one saved list (inferred,
  not measured).
- `scripts/ci-changes-test.sh` adds its run to the lint gate (not timed apart).

Not measured, and why:

- A median of `ci-ok`'s time for a PR that runs e2e without the native gates under four shards.
  There is one run, #470's (13:49). Four of the five runs of four shards are #460's own, and a
  change to `ci.yml` runs the ios job. The PRs after the merge give the median:
  `scripts/ci-timings.sh --limit 12 --steps e2e`.
- How long two more jobs per run wait at 20 jobs at once, GitHub's documented limit for the Free
  plan (the organisation's plan was not read). In the week before, 20 ran at once for 492
  seconds in all and 18 or more for 2,815 seconds, a lower bound from first attempts.
- How often one of four stacks fails to start. Five green runs say nothing about a rate.
- How often a land's `merge-pr.sh --wait` ran out because of an ios job the new rule spares.
- A phone, the web build (where an `Expando` is a JavaScript `WeakMap`), frame times, and where
  the saved milliseconds fall against a frame.
- `shared_preferences`' own write of the text, and the household read every save makes first.

### A test that failed by date

Found while #470 was verified after midnight: `scripts/verify.sh --only lint,flutter` failed on
#470's branch in a test the branch does not touch, and the test's file then failed the same way
on untouched `main` 46f0ae0d. `app/test/list/list_declutter_test.dart` priced its item with
`pricedAt: DateTime(2026, 11, 14)`, the day #448 wrote it. A price counts only on its calendar
day (`Price.isCurrent`), and the list reads the device's clock, which the test cannot set
through `ListScope`. So the test passed on 14 November only: on the runner (CET) it failed from
00:00, in CI (UTC) from 01:00 CET. In CI the flutter job of #467's run 43656223668 (job 245)
failed in it at 00:07 UTC. #472 prices the item with `DateTime.now()`, as
`summary_block_test.dart` does. Its review ran the test under several time zones and found no
other test in `app/test` that fails by date (a search, not exhaustive). Left open: a run that
crosses midnight between the test's two clock reads, and a clock seam for `ListScope` so that a
list test can pin the day (with the lead).

A heads-up went to the board at 00:29 CET, before the first CI run could fail. At 01:16 job 245
reported the red gate too and was fixing the same line in #467; #472 merged at 01:23, and the board
line said so.

### Cost

Measured where a counter exists; anything else is labelled.

- **Lead time.** The worker first started on 14 November at 05:18 CET and stopped after 2 s on the
  usage limit. Work began at 20:07 CET; the fourth PR merged at 04:25 CET on 15 November, 8.3 h
  later, and this record's PR came after it. For 1.2 h of it (20:45 to 21:54) the job was stopped by
  the usage limit again; a subagent that was measuring the runtime baseline ended with it, and the
  main thread redid that part.
- **Tokens, run 1** (20:07 to 20:45; the CLI's result line): 77 turns, 35.7 min by its count,
  input 136, output 82,648, cache read 8,009,734, cache creation 354,607; 6.69 USD at the CLI's
  prices.
- **Tokens, both runs** (the session transcripts up to 04:25 CET on 15 November, before this
  record's review; a lower bound, since a transcript holds one count per message): the main thread
  448 messages, input 890, output 441,567, cache read 50,869,835, cache creation 1,679,956; the 17
  subagents 553 messages, input 1,104, output 647,245, cache read 50,394,446, cache creation
  2,279,983. Read by `UNTIL=2026-11-15T03:25:00.000Z scripts/tokens.py`, which leaves out later
  messages so that the reading can be repeated.
- **Models.** The main thread and 16 of the 17 subagents ran on `claude-fable-5-2`. One did
  not: the first subagent, a read-only `Explore` agent that summarized the closed hill-climbs'
  notes (11 messages in 72 s at 20:08 CET), ran on `claude-opus-5-5`, the model that agent type
  carries. It wrote no code and reviewed nothing. Its summary named the harnesses and the
  closed climbs' numbers; the numbers this record cites from jobs 100 and 108 were read again
  in the documents themselves. Every later subagent was started without a type that carries a
  model. Each states its model in the first line of its report, but for the second, which ended
  on the usage limit without a report; its transcript shows `claude-fable-5-2`.
- **Reviews.** 15 rounds of `claude-fable-5-2` over the four PRs, 9 FAIL and 6 PASS: #460 5
  (FAIL, FAIL, PASS, FAIL, PASS), #462 4 (three FAIL, PASS), #470 5 (FAIL, PASS, FAIL, FAIL,
  PASS), #472 1 (PASS). A PR whose text changed after a PASS got a fresh round. This record's
  own review is in its PR and not counted here. What the FAILs found:
  - Counts cut by a `gh` default, twice: `gh pr list --json files` stops at 100 files per PR
    (9 of 120 lists were cut), and `gh pr list` orders by creation, so "merged from 7 to 14
    November" missed #231 and 15 more. The sample is now taken by merge date (136 PRs).
  - A check that passed for forms it did not read: the filter's test let a job ask the filter
    in nine other valid forms, and `check-gates.sh` did not hold `e2e.yml`'s shard list. Both
    got lines and mutants.
  - A number that was not what its label said: a `main` binary built from an older commit, a
    "median" that was the upper middle of 12, a `ci-ok` time that was the ios job's running
    time, a week's concurrency read over two weeks of job 219's table, and "95 of 120 PRs
    gain" where 29 of them run no e2e.
  - A limit scoped wrongly: the 20 jobs at once count the ios job too, which made the week's
    time at the limit 492 s and not 35 s.
  - Sentences about the cold save that the code contradicted: "never the cost of a tap", then
    "twice" where a start makes up to three resyncs.
- **Mutants.** 77 over the three PRs with code (17 for #460, 28 for #462, 32 for #470), each
  failing its test or check. The scripts are in the research folder (`scripts/mutants*.sh`),
  not tests in the repository.
- **CI.** Nine green CI runs on the four PRs, one cancelled after 28 s by the next push,
  and one on-demand e2e run; each a first attempt, none rerun (`record/ci/ci-ok.tsv`). `ci-ok`
  after the run's creation: #460 28:37, 24:43 and 28:50; #462 24:53, 30:43 and 27:06; #470
  21:24 and 13:49; #472 23:48. Two of the nine were the second run of a land, because `main`
  had moved while the land waited for the lock (below). The record PR's own runs are not
  counted. Local gates (`scripts/verify.sh`, the verify ledger's rows of the four PRs'
  branches): lint 122 to 218 s in 12 runs, flutter 139 to 253 s in five (139 s is the run that
  failed by date). No e2e ran on the runner: the shards were measured in CI, where they run.
- **Flakes seen.** None in the ten finished runs: no test was retried or marked flaky in
  any shard's Playwright summary, and no job was rerun. The flutter gate's failure after
  midnight was no flake (above). On the board, job 245 reported one failure of
  `onboarding.spec` AC10 in a run of #467 (two shards, before #460 was on `main`); not this
  job's run and not looked into here.
- **Not measured:** the price of run 2, and the job's share of the runner's load.

The lands (times CET, 15 November). Queued is when the land had pushed and asked for the lock.
Each first waited the 30 minutes `merge-lock` gives the Mac's lock, which did not answer all
night, and then for the Hetzner lock:

| PR | Queued | Lock held | Merged | Waited | Held | What happened |
| --- | --- | --- | --- | ---: | ---: | --- |
| #472 | 00:52:54 | about 01:23 (not logged) | 01:23:06 | 30 min | under 1 min | `ci-ok` was green and `main` had not moved |
| #462 | 01:23:39 | 02:14:07 | 02:41:32 | 50:28 | 27:25 | `main` had moved (#473): a second push and a whole CI run inside the hold |
| #460 | 02:42:04 | 03:24:47 | 03:53:59 | 42:43 | 29:12 | `main` had moved (#474): the same |
| #470 | 03:54:54 | 04:25:15 | 04:25:22 | 30:21 | 0:07 | `ci-ok` was green and `main` had not moved |

The four lands took 3 h 32 min one after the other, 2 h of it the four waits for the Mac.

### For the lead

Seven points are in `docs/NEEDS_LEAD.md`, "Job 221: what the perf job measured and left open":
the four shards read again after a week, the ios job's time, a clock for list tests, the mutants
as a test in the lint gate, the whole list's text written on every tick (with job 222), the
slower first save after a resync, and the 30 minutes every land waits for the Mac (job 219's
point, with this night's numbers). The model deviation is there too.

## Job 222: offline and sync error paths, 2026-11-14

The brief: map the offline and sync error paths (queue, retry, conflict, auth expiry, partial
failure, reconnect) against their tests, close the highest-leverage gaps with a test before each
fix, and record what stays open. Job 212's banner grace was not to change, and it did not. The
map with every test's place, the remaining gaps and the calls are in
`docs/done/222-robustness-offline-sync.md`; this section holds the numbers.

### Covered paths

Five gaps had no test and a real loss or stall behind them. Each got a test that failed, then a
small fix (PR #469):

| Path | Before | After | Tests |
| --- | --- | --- | --- |
| A tick inside the row's 440 ms leave, when the app is hidden, the row goes away or no frame is drawn | Lost (reload, closed tab, killed app, folded store, household switch) or held until the app shows again | Committed at once and queued on the device (880 ms after the tap when no frame is drawn); a list switched away from stays open until the tick is sent. A row that draws commits at its animation's end, as before | 9 row tests, 3 screen tests, 1 switch test, 2 e2e tests on three engines |
| An answer that arrives while the list closes | Armed the retry, usuals-reload or save timer of a closed list | No timer | 3 cubit tests |
| A 401, 408 or 429 without a PostgREST body on a queued write | The change was dropped as refused | Kept and sent again | 1 repository test (3 statuses) |
| A failed follow-up read after a merge found its item gone | Shown as offline while the server answered (the op stayed queued) | "Sync gestört", asked again like any 5xx | 1 repository test |
| A start whose read was passed by a newer reload | Never asked again when that reload failed: stale households, or the loading screen until a restart | Asked again every 3 s until an answer shows and its write to the device went through (the app's store drops a failed write's error, so there: until the write returned). After a dropped answer (where main stopped asking) the newest reload, while it is out, is not passed, and neither the asking's timer nor an auth event sends a read while an order change is on its way. Besides the fix, four more differences from main, each measured below | 56 session tests |

The paths that were covered already (the queue offline and across restarts, refusals, 5xx, an
expired token, conflicts, overlapping resyncs, the realtime join gap and reconnects, the start
grace) are listed with their tests in the done file. They were read and run, not changed.

### Measured before and after

- **The lost tick, e2e** (`e2e/tests/tick-leave.spec.ts`: click a row, reload or close the tab
  at once, expect the item ticked on the device and `bought` on the server). One hold of the e2e
  lock on the shared box, local stack, the release web build, 14 November 22:07 to 22:24 CET:

  | `app/lib` | Chromium | Firefox | WebKit | Passed |
  | --- | --- | --- | --- | ---: |
  | main `3344381d`, `--repeat-each=3` | 0 of 6 | 0 of 6 | 3 of 6 | 3 of 18 |
  | the branch, `--repeat-each=5` | 10 of 10 | 10 of 10 | 10 of 10 | 30 of 30 |

  WebKit's three passes on main are the closed-tab test: WebKit's close takes longer than the
  row's leave, so that case shows nothing there. The load average was 7 to 13 during main's
  run and 5 to 7 during the branch's; the failures on main are the row back on the list after
  the reload, not timeouts. An earlier run on main is not counted (the spec polled for a
  status name the server does not use and failed before the click). The branch run predates
  the list hold for a household switch and review 1's fixes, which are not on the spec's
  path. Run again with `conventions.spec.ts` at 23:40 (load average 6 to 7), on the tree of
  `94574c39` (the commits after it are not on the spec's path): 35 of 35 passed, 30 of them
  this spec on the three engines.
- **Sync fuzz** (`tool/hillclimb/hc-sync/measure.sh`, seeds 1 to 1000, one run each on the same
  box): main's `app/lib` 0 failures in 92.1 s, the branch 0 failures in 93.0 s. No change; the
  fuzz drives the cubit directly, so none of the five paths is in its model. The 0.9 s is
  inside one run's noise (one run each, no distribution).
- **Unit and widget tests:** `flutter test test/list test/fuzz` on main `a0cd3c73` 886 passed, 2
  skipped. The whole suite on the eleventh version with review 9's eight tests and main
  `c8a90ce1` merged in, through the flutter gate, 15 November 11:19, load average 1.7 at
  the start: 3277 passed, 98 skipped, none failed, in 1 min 48 s. Before the eight tests,
  with main `377f1a0f`, at 10:30, load average 0.6: 3269 passed, 98 skipped, in
  1 min 35 s. Before review 8's five tests, with main
  `0c4eb818`, at 09:33, load average 0.2: 3264 passed, 98 skipped, in 1 min 32 s. On the tenth version with main `5c09754b`, at 08:23, load average
  2.8: 3257 passed, 98 skipped, in 1 min 32 s. On `67249a83` (main `c3ea4261` merged in) at 08:20, load average 0.14:
  3255 passed, 98 skipped, in 1 min 34 s. The ninth version with the same main at 07:01, load average
  0.64: 3251 passed, 98 skipped, in 1 min 35 s.
  On the merged head `a4f5efde` (main `683990d8` merged in) at 06:01, load average 4.8: 3232
  passed, 98 skipped, in 1 min 46 s. Before the merges, `e5462c15` on main `88d0fbdc` at 05:27
  (load average 0.66): 3197 passed, 98 skipped, in 1 min 31 s. Earlier heads that day: 3181 passed at 03:28 (2 min 44 s), 3168 at 01:36. At
  00:50, on the base before #472, it had 3162 passed, 98 skipped and one failure, main's and
  by date: `list_declutter_test.dart` priced an item on 14 November, and a price counts on
  its own day only (job 221's PR #472 fixed the test). On 14 November the suite was green:
  3161 passed, 98 skipped on the second pushed head in the reviewer's run; the first pushed
  head 3152 passed in 2 min 17 s, and in 3 min 15 s in the reviewer's run (the box's load,
  not the code). The job added 89 tests (item row 9, list screen 3, household switch 1,
  list cubit 3, repository 2, session 69, e2e 2).
- **Failing first:** of the 87 Dart tests, run at the head `781db370` against main's
  `app/lib` (`0c4eb818`), 34 fail and 53 pass (the 79 before review 9: 33 and 46; the 74
  before review 8: 33 and 41 against
  `5c09754b`; the tenth version's 67 tests: 31 and 36
  against `c3ea4261`; the ninth's 63: 30 and 33 against `88d0fbdc` and again against
  `683990d8`). Of the 53, 33 pin a fault an earlier commit of this branch had (each red
  on that commit) and 20 guard what main already did. Three of the 34 are red on main for
  a 3 s timer that main arms after a sign-out, a close or an account change; it reads
  only if the account it was armed for is signed in again when it fires (the fourth
  difference below). Against the twelve earlier `app/lib` trees 28, 28, 27, 25, 22, 21,
  19, 17, 16, 12, 5 and 3 of the 87 fail (`3176c80b`, `94574c39`, `cf0502ff`, `bb6775e8`,
  `b243599f`, `f5cfb2d2`, `5d21dc45`, `e60c7585`, `e3c7b247`, `659c6a93`, `67249a83`,
  `42b6429a`), none at the head.
- **Mutation check:** 88 mutants of the fixes, each failed 1 to 35 tests (the table in the done
  file; run on `781db370`. The 80 before review 9 ran on `5c29dae4`, 1 to 31 tests each, the 75 before review 8 on `592009a5`, 1 to 30 tests each. The tenth version's 67 ran on `67249a83`, the ninth's 61 on `e5462c15` and again, with the same counts, on the merged head `a4f5efde`). The first pushed head had 13; two survived their first run there (the save timer of a
  closing list, the signed-in check of the start's retry) and got a test each. Review 1's own
  30 mutants found two more unpinned lines (the row's listener never ended, the closed check
  of the start's retry), review 2's 40 two unpinned behaviours (an only-inactive app commits
  nothing, a closing list saves its queue), review 3's 19 three survivors (the retry waiting
  for a reload that is out but no longer the newest, in two forms; a row committing when the
  app comes back). Of review 4's 10, six survived by its table (its summary line says
  five); the done file lists them. Of review 5's 12, nine survived: one was the must-fix's
  own candidate, four are pinned since, three went with the sixth version's rule, and one
  is not pinned (a failed write of the told removals; listed as a gap). Of review 6's 12,
  three survived: two equivalent, and one pinned since (the mark only while the very
  answer still shows). Of review 7's 13, nine survived: three change nothing that shows
  by its reading, one was the must-fix's own candidate, and five are pinned since (four
  tests). All others are pinned since.
- **Review 1 (Fable 5.2, a fresh agent in a shared clone): FIX, two must-fixes, both real.**
  The start's retry of the first version passed a slower reload that was still out and dropped
  its answer: in the reviewer's probe, with reads slower than 3 s and a second auth event, the
  households never showed (22 to 37 reads in 120 s). With the fix the same probe shows them in
  two reads in every row (reads of 3.5 s and 3.2 s: at 6.7 s; of 8 s: at 11.2 s). And `ci-ok`
  was red on the first pushed head (below).
- **Review 2: PASS on `5fd39cd1`, no must-fix, ten nice-to-haves.** One was a row where the
  second version was worse than main: a first read that never answers and a second one that
  failed. Main asked again 3 s after the failure and showed the households at 4.0 s; the
  second version waited for the read that never answers. The third version waited only for
  the newest reload. In the reviewer's 24-row probe that changed six rows, all to main's
  4.0 s: two from never, four from 63.0 s or 23.0 s.
- **Review 3: FIX on the third version (local, not pushed), one must-fix.** The reviewer's 54
  new rows against main: 38 equal, 7 better, 9 worse, on the pushed second version too. The
  nine have a start read that failed and a newer reload still out. Main asked again 3 s after
  the failure; the second and third versions waited for the reload. Five rows never showed
  the households (main: 3.0 s to 5.0 s), four showed them at 4.0 s to 24.0 s (main: 3.0 s to
  5.0 s). The fourth version: a failed read is asked again after 3 s whatever is out, and
  only a dropped answer waits for the newest reload.
- **Review 4: FIX on the fourth version (local, not pushed), one must-fix.** Against the
  three reviewers' 114 rows the fourth version was 104 equal, 10 better, none worse, and
  the job's files said it could not be worse. The reviewer's fourth probe (1222 rows)
  found 18 rows where main showed the households sooner, and two direct rows with the
  repo's own fakes confirmed two classes: after a dropped answer main asked nothing more,
  so the newest reload's answer showed; the fourth version's later failed read, or an auth
  event, sent a read that passed it (main 8.0 s and 2.75 s; the fourth version still
  loading at 120 s and at 2.75 s). The rule now goes by what the start has seen.
- **Two more differences, found by the job after review 4.** Comparing by the time a read
  is sent and with a second seed showed one row where main was sooner (another account
  over the first, whose read fails late): kept, a measured trade. Reading main's `catch`
  line by line showed that the fifth version ended the asking when the device write after
  a shown answer failed, where main read again after 3 s: fixed, and three hand rows give
  main's reads exactly.
- **Review 5: FIX on the sixth version (local, not pushed), one must-fix.** The sixth
  version marked the user as loaded where the answer shows and took the mark back when the
  device write failed. The reviewer's probe 9 gave the device store writes that take time:
  while a write ran the mark stood, so a timer that fired, a start read that failed or a
  token refresh in that window gave up for good. In its five direct rows (a write of 0 to
  0.5 s that fails) the device never kept the households; main kept them 3 s later. The
  mark is set after the write now.
- **Three more faults and two more differences, found by the job after review 5.** The
  seventh version (the mark after the write, for the newest reload's answer only) asked
  every 3 s with the households shown and kept when a reload sent during the write failed
  (41 reads in 120 s against main's 2; the job's probe 10). The eighth (the start's own
  answers too) had the same fault one reload later and counted an answer kept after a
  sign-out; both were found by reading each window between two awaits against main, and
  no probe row shows them (tests do). The rule that stays does not ask which reload
  brought the answer. Reading main's timers the same way found the fourth and fifth
  differences below.
- **The final rule against main** (ten probes under fake time; main's `app/lib` `88d0fbdc`
  against the ninth version's, `bd3d8506` (the table's numbers); run again on
  the merged head `a4f5efde` against main `683990d8`, every printed row the same on both
  sides). "Equal" is the
  same times and the same number of reads. Probes 1 to 8 time when the server's households
  first show within 120 s; probes 9 and 10 also when the device has kept them, with a
  device store whose writes take time and fail until a set moment (a store that throws:
  the tests' store; the app's `DeviceCache` drops a failed write's error, so only the
  rows with slow writes that work are the app's case). The tenth
  version (`67249a83`) and the eleventh (`592009a5`) print the ninth's rows line for line
  in all ten probes and both direct runs: their order changes are answered at once, so
  only the order-change rows below tell the three apart.

  | Probe | Rows | Equal | Same times, head fewer reads | Same times, head more reads | Head sooner, or main never | Main sooner |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | 1: review 1's (reads slower than the retry, a second auth event or reload) | 36 | 36 | 0 | 0 | 0 | 0 |
  | 2: review 2's (a first read that is slow or never answers, a second that fails) | 24 | 20 | 0 | 0 | 4 | 0 |
  | 3: review 3's (failed and dropped start reads, reorders, leaves, account changes) | 54 | 48 | 0 | 0 | 6 | 0 |
  | 4: review 4's (22 by hand, 1200 generated), answers by position | 1222 | 1031 | 72 | 66 | 51 | 2 |
  | 5: the same rows, answers by the time a read is sent | 1222 | 1035 | 69 | 73 | 45 | 0 |
  | 6: as 5 with another seed, 6000 generated | 6022 | 5072 | 354 | 368 | 227 | 1 |
  | 7: another account over the first, whose read fails late (4 by hand) | 4 | 0 | 0 | 1 | 2 | 1 |
  | 8: the device write after a shown answer fails (3 by hand) | 3 | 3 | 0 | 0 | 0 | 0 |
  | 9: review 5's (18 by hand, 3000 generated), device writes that take time and fail | 3018 | 2649 | 76 | 191 | 102 | 0 |
  | 10: as 9 with another seed (12 by hand, 3000 generated) | 3012 | 2668 | 75 | 163 | 104 | 2 |

  - Probe 4's two "main sooner" rows come from answers by position: one more read moves
    every later answer. By time (probe 5) the head is sooner in one and neither shows the
    households in the other.
  - More reads (73 and 368 rows in probes 5 and 6): in 68 and 348 neither version shows the
    households, and the head goes on asking every 3 s where main stopped after a dropped
    answer (up to 41 more reads in 120 s; the most in such a row is 51 on both). In the
    other 5 and 20 the time is the same with 1 to 3 more reads. In probes 9 and 10 (191
    and 163 rows): the device keeps nothing on either version in 165 and 146 (1 to 39 more
    reads); in the other 26 and 17 the times are the same with 1 to 17 more.
  - Fewer reads (69, 354, 76 and 75 rows): main read every 3 s after another reload's
    answer had shown; the head sends 1 to 40 fewer in probes 5 and 6, 1 to 3 fewer in
    probes 9 and 10.
  - Head sooner in probes 5 and 6 (45 and 227 rows): main never shows the households in 43
    and 211; in the other 2 and 16 the head is 0.5 to 7.5 s sooner. Never shown: 231
    against main's 274, and 1251 against 1462.
  - Head sooner in probes 9 and 10 (102 and 104 rows): the device keeps the households on
    the head and never on main in 81 and 85, sooner in 19 and 16 (0.5 to 53.8 s); the
    other 2 and 3 show them sooner or where main never does. Never kept: 615 against
    main's 697, and 627 against 712.
  - Main sooner, three rows of 13,274 by time (probes 5, 6, 9 and 10). One is the
    cross-account trade (the third difference): 9.0 s against 15.4 s. In probe 7 around
    it main never shows the households in two rows, is sooner in one and equal in time in
    one. With main's cancel put back the head's times or reads change in 33 rows, and in
    all 33 it then equals main: this row and its hand copy, the two "never" rows of probe 7, two rows
    of probe 9 where the device then never keeps the households and one where it keeps
    them 4.4 s later, and 26 rows with the same times and fewer reads (in 22 of them the
    households are never shown or never kept on either version, and the head asks on, 1
    to 38 more reads).
    Two are the fourth difference (a read that failed after its account
    signed out, the same account back within 3 s of the failure): shown at 11.1 s against
    15.0 s in one; kept at 12.1 s against 15.2 s in the other, where the head shows them
    4.0 s sooner. With main's timer put back the head equals main in those two, in four
    rows where the head shows the households sooner (0.1 to 3.0 s) and in five where it
    sends fewer reads. With main's whole `catch` put back (both, and the timer main arms
    for an account another one signed in over) the head changes in those 33 and 11 rows
    and no other, and equals main in all 44; the 1,810 rows where it then still differs
    from main (the first and second differences) have none where main is sooner.
  - Probe 8: 2, 4 and 41 reads in 120 s on main and on the head; the fifth version sent
    one read and left nothing on the device.
  - Review 4's two direct rows and review 5's five: the head equals main in all seven.
  - An order change on its way (review 6; 66 hand rows on the head `592009a5`, main
    `5c09754b` and the ninth version; the head's rows are the tenth version's line for
    line: the start's read dropped or failed, the order change at 0.2 s or 3 s taking 0
    to 8 s, accepted or refused, or never answering).
    Old order shown again after a dropped answer: 0 of 33 rows on the head, 0 on main, 11
    on the ninth version (1.2 to 11.2 s). The server's households never show: 0 rows on
    the head, 18 on main (the order changes refused or never answered; the head reads
    within 3 s of the later of their end and the dropped answer, at 4.0 to 18.0 s; in 7
    of the 18 that is 3.5 to 6.8 s after the order change's end, counted from its start
    plus its request time, or plus 15 s when it never answers). After a failed read
    the head and main are the same in time, the old order shown again in the same 11
    rows for the same 1.2 to 11.2 s (main's defect, kept); the head sends one read fewer
    in 11 rows. No row has main sooner. Against the ninth version the head shows the
    server's households 1.2 to 12.0 s later in the 11 rows where the ninth showed the
    old order.
  - An auth event, a resume, two order changes or a second account while an order change
    is on its way (review 7's 62 hand rows, run by the job on the head, main, the ninth
    and the tenth version and `42b6429a`). After a dropped answer and a token refresh or
    a retryable auth error (15 rows): no old order on the head or on main; on the tenth
    version in 14 rows for 0.1 to 13.1 s (8 of them with an accepted order change, 0.1
    to 6.1 s: review 7's must-fix). In the six of those rows whose order change is
    refused or never answered the head shows the server's households at 10.0 s and
    16.0 s, main never; the same in the two such rows with no event. A resume's reload after a dropped answer shows the old order in
    5 of 5 rows for 0.6 to 13.1 s, the same on main and on the head (main's defect,
    kept). After a failed start read (25 rows) the head equals main in the old order's
    time (23 rows, 0.6 to 13.1 s) and in when the households show; main sends one read
    more in 7. The other 12 rows (two order changes one behind the other, an order
    change started after the dropped answer, one whose device write takes 20 s, one
    that changes nothing, another account or the same account back while one is out):
    the head equals main in time in the 5 where main shows the households (10.0 to
    20.2 s; one more read in one) and shows them at 4.0 to 31.0 s in the 7 where main
    never does; no row shows the old order after its drag on the head or on main. In no
    row of the 62 is the head later than main; in 15 main never shows the households
    and the head does (6, 2 and 7). All 310 runs end with no timer left.
  - The account deleted after a dropped answer, an order change still on its way (24
    hand rows of the job's, after review 7: a device sign-out that takes 5 s or throws,
    an auth event before it ends or none). The head prints main's row in all 24;
    `42b6429a` held the auth event's read in the 16 rows that have one, because the
    deletion left the wait in place (`592009a5` forgets it there, as main forgets its
    mark).
  - Review 6's other direct rows, the same on the ninth, the tenth and the eleventh
    version: the app's
    store over preferences that refuse every write (1 read in 120 s, the same on main; 41
    with the tests' store that throws); an older write ending after a newer answer shows
    (4 rows, the same on main); an auth stream error (4 rows: 3 equal to main, in 1 the
    head reads again and shows the households where main stays signed out); the account
    deleted with a fake sign-out that is slow or throws (12 rows: 8 equal to main, in 4
    the head reads again after a dropped answer: 2 reads against 1 in three, 7 against
    1 in 20 s in the one where the sign-out throws and the reads fail).
  - Rows that end with a 3 s timer armed: 147 against main's 70, 746 against 395, 339
    against 247, and 350 against 268 (probes 5, 6, 9, 10). Never more than one timer at a
    time and no read after a sign-out on either.
  - Limits: fake time; a row's later reads follow one script (one way until a set moment,
    another after it); the device fails or delays a write in probes 8, 9 and 10 only, and
    never a write of the told removals; no probe row shows the eighth version's two
    faults; the generators rarely hit account changes with a late failure, and may miss
    other cases as rarely hit.
  - Review 6 (on `659c6a93`, the ninth version): FIX, two must-fixes. The ninth version's
    timer read while an order change was on its way and the old order came back on screen
    (fixed: the tenth version, the grid above), and the files claimed a failed device
    write was asked again, which only the tests' store shows (the app's store drops the
    error; the sentences corrected). Four nice-to-haves, each a sentence, a gap line with
    its measured rows, or a test.
  - Review 7 (on `03b409a8`, the tenth version): FIX, one must-fix. The tenth version
    held the 3 s timer while an order change was on its way, but not the read an auth
    event sends, so after a dropped answer a token refresh put the old order back on
    screen (0.1 to 6.1 s in eight of the reviewer's rows; main: none), and four files
    said the branch stopped its own asking from doing that. Fixed: the wait is one rule
    that both doors ask (the eleventh version, the 62 rows above). Five nice-to-haves,
    all taken: two sentences recomputed from the rows ("15 s at the most", "within 3 s
    of the order change's end"), five surviving mutants of its own pinned (four tests),
    a stale `flutter test` line, two gap lines now measured.
  - Review 8 (on `89d28391`, the eleventh version with main `0c4eb818` merged in): PASS,
    no must-fix. Five nice-to-haves, all taken: a count (15 rows, not 13, where main
    never shows the households and the head does), five surviving mutants of its own 16
    pinned by five tests (80 mutants now), two ranges stamped one 100 ms step early
    (0.0 to 3.0 s and 3.5 to 6.8 s), and two windows it measured that are in the gap
    list now (an auth stream error after a dropped answer; a wait left with no timer
    behind it), no row worse than main in either.
  - Review 9 (on `504f6c6a`, review 8's five tests and main `377f1a0f` merged in): PASS,
    no must-fix. Five nice-to-haves, all taken: eight of its own 13 mutants survived (the
    wait at an auth event and at the timer each on its own, and review 8's rows with a
    second order change, an older reload or a device slow to forget the session) and
    are pinned by eight tests (88 mutants now; one of the eight tests is red on main,
    three pin an earlier commit, four guard), and three sentences were stronger than
    their rows and are reworded. Its 16 own rows: 13 equal to main, 3 where main never
    shows the third household and the head does (at 10.0 s twice and 19.0 s). The
    eight tests were not reviewed again: they are checked by their mutants and against
    main's and the earlier trees' `app/lib`.
- **Failures and flakes:** one failure, the job's own: the first pushed head `3176c80b` failed
  `e2e (1)` with 1 failed and 136 passed. The new spec imported from `@playwright/test`, which
  `conventions.spec.ts` refuses; only the one spec had been run locally. Not a flake. The
  spec's own six runs passed in that CI run on Chromium, WebKit and Firefox. No flake was
  seen in the job's own runs (the e2e runs above, the fuzz, the unit suites). The second
  pushed head's CI run was green at its first attempt. Flakes of the land's own run, if
  any, are in the job's DONE_SUMMARY copy in the ops folder with that run's numbers.
- **Not measured:** how often users lost a tick this way (no event tells a lost tick from one
  never made); the CI trace of job 219's point 4 was not reproduced; a body-less 401, 408 or
  429 was not driven through the web build; a phone was not used.

### Remaining gaps

Open and untested, in the done file with their reasons: a write or a start read that never
answers (no timeout; job 122's reordering finding stands), a forced sign-out dropping the queue
(intended, a product call), realtime channels other than the list's after a server `phx_close`,
a gateway's lasting 401 or 429 asked every 3 s without backoff (read from the code), a
start whose reads keep failing asked every 3 s without backoff (as on main, now also after a
dropped answer), three measured rows where main shows or keeps the households sooner (one
after another account's late failure, two after a sign-out with the same account back within
3 s), a second account's late answer showing to the first when it signs in again over it (on
main too), a read answered while an order change is on its way showing the old order again
(on main too, after a failed start read and after a resume's reload, measured; after a
dropped answer this job holds its own asking at the timer and at an auth event, measured,
and does not hold a reload the app sends itself), another account's order change holding
the asking after a dropped answer (17.0 s and 18.0 s in two rows where main never shows
the households), an auth stream error
during the start answer's device write and an account deleted with a slow device sign-out
(one more read than main, measured), an auth stream error after a dropped answer and a
wait left with no timer after the timer found nobody signed in (review 8's rows N and P:
no row worse than main, no test), a device write that fails (the app's store drops the
error, so the cubit's handling of one is pinned against the tests' store only), two edges of the early commit (a row gone without the rest of its animation
after a hide, a first frame later than 440 ms), delete winning over a replayed add, the fuzz fake's omissions (JWT expiry, catalog edits,
`place_item` and `move_item`, single dropped events, four devices), a resume resubscribing a
down channel at once, flight mode on a real phone, and the stack-pause stress pass. The write,
the start read, the sign-out, the channels and the old order shown again are in
`docs/NEEDS_LEAD.md`, "Job 222".

### Cost

- **Wall time:** the build ran 20:13 to 20:45 and from 21:54 CET on 14 November
  (to the last commit before the land at 11:27 on 15 November: 32 min and 13 h 33 min, with no pause over 15 min in the transcripts; the land's wait for CI comes after it). A first start at 05:18 stopped after 2 s at the usage limit, and the 20:45 stop
  was the limit again: 14 h 56 min and 1 h 10 min queued or blocked, not worked.
- **Tokens,** from the usage fields of the job's transcripts, each message id counted once,
  every one of the 1,848 model messages on `claude-fable-5-2` (five more are the harness's own, with no model and no tokens), read at 11:24 CET on 15 November: 3,696 input, 2,086,310 output, 8,854,255 cache-write and 193,677,422 cache-read tokens. These are lower bounds
  (the stream omits some output counts), and the two mapping delegates and the review are in
  them only as far as their transcripts sit in the job's folder.
- **Gates,** locally through `scripts/verify.sh`, one run each: gitleaks 14 s, lint 150 s,
  flutter 173 s. A first flutter gate run failed after 14 s on seven analyzer findings in the
  job's own lines (escaped quotes, an unneeded `unawaited`), fixed with `dart fix`. The e2e
  gate ran only for the one spec, in the lock hold below. After review 1: gitleaks 13 s,
  flutter 146 s, lint 126 s, and the e2e gate for the two specs 551 s. On the final code
  (`e5462c15`): flutter 133 s. On the merged head: gitleaks 12 s, lint 121 s (on the docs
  before the merge), flutter 151 s; with main `c3ea4261` merged in, flutter 136 s. On the tenth version (`67249a83`, 08:17 on
  15 November): gitleaks 13 s, lint 124 s, flutter 138 s; with main `5c09754b` merged in,
  flutter 135 s. On the eleventh version with main `0c4eb818` merged in (09:31): gitleaks
  12 s, lint 125 s, flutter 137 s. With review 8's five tests and main `377f1a0f` merged in
  (10:30): gitleaks 13 s, lint 124 s, flutter 134 s. With review 9's eight tests and main
  `c8a90ce1` merged in (11:19, load average 1.7 rising to 7.6): gitleaks 13 s, lint 130 s,
  flutter 146 s.
- **Review:** round 1 took about 28 min and 114,582 tokens of the reviewer's own (its report's
  count; 58 tool calls). Round 2 took 34.5 min (2,071 s) and 129,642 tokens (70 tool calls).
  Round 3 took 26.4 min (1,583 s) and 124,304 tokens (60 tool calls). Round 4 took 27.9 min
  (1,674 s) and 131,414 tokens (61 tool calls), round 5 40.1 min (2,406 s) and 90,739
  tokens (86 tool calls), round 6 37.0 min (2,219 s) and 89,949 tokens (112 tool calls); a
  first start of round 6 was cut off by the usage limit and is not counted. Round 7 took 21.3 min (1,278 s) and 63,645 tokens (54 tool calls), round 8
  33.6 min (2,019 s) and 90,226 tokens (108 tool calls), round 9 17.0 min (1,022 s) and
  122,750 tokens (61 tool calls).
- **CI:** run 43645262887 on the first pushed head `3176c80b`, 22:54 to 23:19 CET, 24 min
  26 s: red (`e2e (1)`, the job's own conventions failure above); `e2e (2)` 23 min 57 s,
  `e2e (1)` 14 min 35 s, flutter 5 min 3 s, lint 2 min 59 s, db 3 min 22 s; ios and android
  skipped. Run 43650812055 on the second pushed head `5fd39cd1`, 23:58 to 00:22 CET, 24 min
  46 s: green (`e2e (2)` 24 min 25 s, `e2e (1)` 15 min 20 s, flutter 5 min 19 s, lint
  2 min 44 s, db 3 min 2 s; ios and android skipped). The land's own run, on the final
  head, cannot be in this file, which is part of that commit: it is in the job's
  DONE_SUMMARY copy in the ops folder.
- **The e2e lock:** one hold of 27 min for the three runs (21:57 to 22:24), of which the first
  9 min bought nothing (the spec's wrong status name). A second hold of 9 min at 23:40 for the run after review 1.
