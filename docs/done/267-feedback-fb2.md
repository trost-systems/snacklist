# Job 267: FB2, feedback by shake or from More with an annotated screenshot

PR #499, flag `feedback-fb2`. What was built and why: docs/DECISIONS.md "Job 267". How it works
and how Peter reads it: docs/FEEDBACK.md ("Screenshots"). Summary: DONE_SUMMARY.md "Job 267".

## Remaining gaps

- No device run: the shake is proven on fake sensor samples in widget tests, not on a phone.
- §10 of the privacy policy does not cover screenshots or the shake's screen name yet; the flag
  stays internal until it does (the job's LEGAL-NOTE in the ops folder).
- The export lists a screenshot's file name, not the picture.
- A note that arrives more than 24 h after its upload (a long offline retry) loses its picture to
  the orphan sweep.
- `feedback` 3.2.0 only frames and captures; dropping it for our own capture is a possible
  follow-up.
