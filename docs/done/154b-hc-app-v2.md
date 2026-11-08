# Job 154b: app design climb on harness v3

PR #320, landed by job 154c on Peter's go (A107). Continues job 154 (#300) on its app commit rebased
onto main.

## Result

- Blind pairwise, baseline against final: final 6 aspects, baseline 0, 3 ties. This is the real
  evidence.
- Score (minimum aspect median, median of 3 runs) 5 -> 6, which equals the noise band (1). Final
  runs 6, 6, 6 (baseline 5, 5, 6). Per-aspect medians over the runs: the lowest stays 6 -> 6,
  five aspects go 6 -> 7. Mean of aspect medians 6.44 -> 7.0.
- Per aspect (median of 3 runs), baseline -> final: typography 6 -> 7, hierarchy 6 -> 7,
  colour 7 -> 7, spacing 6 -> 7, layout 6 -> 7, consistency 6 -> 6, accessibility 6 -> 7,
  iconography 7 -> 7, empty and error states 8 -> 8.
- 12 steps: 10 kept, 2 reverted. Stopped at the step budget after 1 h 45 min.
- The log, every step's medians and the lowest aspect per step:
  `docs/hillclimb/hc-design-v3-app.md`.

![pairs](../screenshots/154b/app-pairs.jpg)

## Kept steps

1. b1: the add sheet's hint is never cut off at large text.
2. b2: tabs, the hint card's Verstanden and the legal links show 44 pt targets.
3. b4: scrolled content fades out below the status bar.
4. b5: a scroll edge under the status bar and the top bar; More's dividers end inside the cards.
5. b6: dark mode draws the same 3D edge and hex buttons as light. The new-adds capsule beside Anpassen
   follows too (fixed after review 1; b6 had pinned it to the old night shadow).
6. b7: one sheet scrim and one divider language.
7. b9: settings groups like More; More's row icons are line art in both modes.
8. b10: labels and captions are at least 13 px (the add sheet's own-store badge still draws its name at 12 px).
9. b11: rows fade out above the floating add field and tab pill.
10. b12: store details' name row is a field like every other field.

Reverted: b3 (list overline contrast, unseen in the pairwise) and b8 (a two-row page bar that
cost layout and accessibility).

## How to verify

- Run `cd app && flutter analyze && flutter test`: 2220 passed, 92 skipped. Widgetbook: 334.
- Look at `docs/screenshots/154b/` (before, after, pairs).
- Re-measuring needs the ops harness (`jobs/154b-hc-app-v2/harness-v3/measure.sh`).

## Guard

The brief's limit of 16 files per step counts the step's change, not the goldens regenerated after
a keep. The guard changed between b1 and b2 (21:59 CET) and the harness was refrozen (rubric_sha
349b3d66 -> c891b946, guard only). Counting goldens, b2, b6, b7 and b10 exceed 16.

## Open

- Peter granted waiver A105 at 21:34 CET: `_Header` / Anpassen and the empty-state copy may
  change. The climb's prompt predated it, so all rules were kept, `_Header` included.
- Consistency stays at 6. Rounded cards next to hex rows (DESIGN.md) and the Google/Apple pills
  (brand rules) remain lead calls. The first targets for a next climb are Anpassen overlapping a
  store header at 150 % and the empty-state copy (both allowed by A105). Before it, drop the
  `_Header` check from the harness guard and refreeze.
