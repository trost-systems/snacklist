## Job 380: N-344 per-account Premium beta notice (legal PR, not merged by the job)

**What.** Legal Review 22 Nov 2026, N-344 (MUST, live before the beta thank-you grants are applied).
`site/content/legal/datenschutz.md` and `site/content/legal/privacy.md` now explain the free
Premium Lifetime unlock that goes to each existing account's ID at RevenueCat:

- `#premium-beta`: new paragraphs (unlock, legal basis Art. 6(1)(b), retention) after the existing
  retention line. The three tester and app-review household paragraphs are unchanged.
- §12 recipient line, §13 RevenueCat bullet (last sentence), §14 RevenueCat deletion sentence.
- Policy date 23 November 2026 (N-279: the day the PR is expected to merge, Europe/Berlin).

The wording is the review's redline byte for byte (`/tmp/job380/apply.py` replaced each old
sentence after asserting exactly one match; a second check compared every redline line with the
files and confirmed the old sentences are gone).

**Verify.** `scripts/verify.sh --only gitleaks,lint,site` passed. In the built `site/dist/`,
`datenschutz.html` and `en/privacy.html` show the new paragraphs at the end of `#premium-beta`
and the new date.

**Not done.** Merge waits for Legal (NEEDS_LEAD "Job 380"). If it merges on another day, bump
the date to that day. Job 374 (#584) edits the same two files: whichever lands second carries
both sides' reviewed text through its rebase.
