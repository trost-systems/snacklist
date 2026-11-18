# Job 290: the annotator's opaque cover tool (Legal C1, N-267)

Behind `feedback-fb2` (stays off). PR: see the job's PR (not merged by this job).

**What.** The screenshot annotator has a fourth tool, „Verdecken“ / "Cover": a box dragged open
and filled with the theme's ink, fully opaque, square, not anti-aliased. It is painted into the
layer BetterFeedback rasterises, so the PNG that is uploaded holds none of the pixels under it. The
annotator's hint now reads „Markiere, was nicht stimmt. Verdecke, was niemand sehen soll.“ /
"Mark what's wrong. Cover anything nobody should see." The upload call is pinned to Frankfurt by
`?forceFunctionRegion=eu-central-1` only: review 0 found that `region:`'s `x-region` header fails the
functions' CORS preflight on the web in production. A unit test checks the upload's headers against
`corsHeaders`.

**The test Legal asked for.** `app/test/feedback/annotator_test.dart`, "cover: the covered pixels
of the exported PNG are the fill colour, none of the screenshot under it": a screenshot of known
red and green squares, a cover dragged over part of it, Fertig, then every pixel of the PNG the
route pops with inside the cover is exactly the ink, for the box dragged open from each of its
four corners (light and dark theme), and the squares
outside it are still there. Mutants that fail it: the fill at 95 % alpha, an outline instead of a
fill, the cover not painted, anti-aliasing on (the row above the cover must be the untouched
screenshot).

**Also proven.** `e2e/tests/feedback.spec.ts`, "flag on: a screenshot from More is marked up,
uploaded and named by the row", now covers rows with „Verdecken“ and checks the stored PNG's
pixels inside the cover are the ink (passes locally). A drive of the release web build with the
flag on: 51 322 of 51 322 pixels inside the cover were exactly `#0F1530`, the bucket object equals
the bytes posted, the note row names it. (That drive ran with the `x-region` header, which only
local Kong accepts; the fix is checked by the header test and a production preflight probe.)
Screenshots: `docs/screenshots/290/`.

**How to see it.** Flag `feedback-fb2` on for the account (internal testers only), More ›
Feedback senden › Bildschirmfoto hinzufügen › Verdecken. Ships with the next green main build to
TestFlight after merge.

**Review 1.** A cover or frame dragged up or left used to shrink to the pointer
(`Rect.fromPoints(rect.topLeft, at)` with a normalised rect); the drag's start is now kept, and the
test covers all four directions (it fails on the old code). The rectangle had the same bug and is
fixed too. The e2e drags its cover up and to the left.

**Not done here.** The screenshot note (C2) and the policy texts are job 289's. In NEEDS_LEAD:
the dark theme's cover barely contrasts with the list, and a drag that starts beside the
scaled-down screenshot draws nothing.
