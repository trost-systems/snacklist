# Hill-climb hc-design-v2-web (job 154)

Design quality of the public site hummlist.com, scored by a council of three fresh Claude Opus judges against a rubric researched and frozen before the baseline (10 aspects: typography, hierarchy, colour and contrast, spacing, layout, design-system consistency, accessibility, motion, iconography, empty and error states; motion is not scorable from stills and is left out). Each judge answers every criterion yes/no/n.a., then scores each aspect 1-10 against anchors. Aspect score = median of the 3 judges; overall = minimum of the aspect medians (the mean is reported too).

The judges, the rubric, the prompts and the screenshot harness live in the job's ops directory, outside this repo; nothing in the repo calls a model. Judges are separate processes with an empty working directory and only the screenshots; they never see scores, steps, diffs or which version is new. The harness refuses to score (score 0) when any frozen input's hash differs.

## Keep rule

A step is kept only if (1) a blind pairwise council prefers it: baseline and candidate shown as "Version P" / "Version Q" in a random order per judge, each judge picks P, Q or tie per aspect, aspect verdict = majority, step verdict = majority of the decided aspects; (2) the absolute minimum does not drop by more than the noise band below the best kept state; (3) every guardrail passes.

## Screenshot set (fixed before the baseline)

40 shots of a local production build of site/ served on 127.0.0.1: /de (1440 light, every tile; 1440 dark, 2 tiles; 390 light, every tile; 390 dark, 2; 390 light at text 150 %, 2; keyboard focus after 3 Tabs), /en, /de/anleitungen, /de/anleitungen/siri-kurzbefehl (also at text 150 %), /de/changelog, /datenschutz (also at text 150 %), /support and the 404 page, at 1440 and 390 px, light and dark. Text 150 % is the browser's default font size raised from 16 to 24 px. Two renders of the same tree are byte-identical.

## Baseline

Main at `5e639d3a`. Three absolute runs: minimum [4, 4, 4], mean [6.556, 6.444, 6.556]. Score (median) **4**, noise band 0.5 (max - min, floor 0.5).

| aspect | typography | hierarchy | color_contrast | spacing | layout | consistency | accessibility | iconography | empty_error_states |
|---|---|---|---|---|---|---|---|---|---|
| run 1 | 6 | 8 | 8 | 7 | 7 | 5 | 7 | 7 | 4 |
| run 2 | 6 | 8 | 7 | 7 | 7 | 5 | 7 | 7 | 4 |
| run 3 | 6 | 8 | 8 | 7 | 7 | 5 | 7 | 7 | 4 |

A-vs-A check (identical images as P and Q, 3 runs): 27 of 27 aspect verdicts tie, 81 of 81 single judge votes tie; seeds [[4042588824, 1315228522, 1139922973], [2523588036, 157228610, 757001154], [3829715989, 4274223690, 1574030434]].

## Steps

| # | hypothesis | pairwise (cand / base / tie aspects) | min (mean) | verdict | note |
|---|---|---|---|---|---|
| w1 | dark-mode cards use the hard 3D offset instead of a blurred glow (C5 one depth style) | cand 1 / base 0 / tie 8 | 4 (mean 6.778) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w2 | empty changelog and 404 get a hex empty-state mark and a centred focal composition (CSS only) | cand 4 / base 0 / tie 5 | 6 (mean 7.111) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w3 | headings hyphenate long German compounds on narrow screens (hyphens:auto, limit 12 5 5) | cand 3 / base 0 / tie 6 | 6 (mean 7.333) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl (2nd run; 1st timed out on /en/privacy networkidle at load 20) + contrast pass |
| w4 | waitlist email field, iPhone/Android radios and 404 language links drawn as hexes like every other control | cand 2 / base 0 / tie 7 | 7 (mean 7.556) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass (focus rings, dark hex contours); note: the delegate halved one padding line (.wl-option side padding) after this measurement, before the commit; that line was first measured as part of w5 |
| w5 | waitlist fine print and field helper at 1.5 line height with a clear gap under the button | cand 1 / base 0 / tie 8 | 7 (mean 7.333) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass; the measured tree also carried the w4 .wl-option padding tweak (see w4) |
| w6 | landing slabs share one inner padding so their content starts on one vertical line | cand 3 / base 0 / tie 6 | 7 (mean 7.222) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w7 | guide dialogue box gets even inner padding | cand 1 / base 0 / tie 8 | 7 (mean 7.444) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w8 | 404 hex links drop the link underline and use the hex button label style | cand 4 / base 0 / tie 5 | 7 (mean 7.333) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w9 | header nav reflows evenly at large text (no orphaned English link, even gaps) | cand 4 / base 0 / tie 5 | 7 (mean 7.444) | keep | guard-web green: 167/167 site tests, copy identical 27+31 pages, crawl + contrast pass |
| rebase | re-anchor: branch rebased onto main 598291fc (#290 landing store chips; waitlist.css conflict resolved to the hex tiles); one absolute run of the rebased head becomes the pairwise reference | - | 7 (mean 7.333) | re-anchor | medians typography 7, hierarchy 8, colour 8, spacing 7, layout 7, consistency 7, accessibility 8, iconography 7, empty/error 7 |
| w10 | landing slabs separated by a larger, uniform gap from the spacing scale | cand 2 / base 0 / tie 7 | 7 (mean 7.556) | keep | guard-web green: 169/169 site tests, copy identical 27+31 pages, crawl + contrast pass |
| w11 | display headings and hex CTA labels get less negative tracking so letters stop colliding | cand 1 / base 0 / tie 8 | 7 (mean 7.444) | keep | guard-web green: 169/169 site tests, copy identical 27+31 pages, crawl + contrast pass; 222 headings: line counts unchanged at 1440/390/390@150 % |
| w12 | hero status chip drawn as a hex like the other chips and controls | cand 2 / base 0 / tie 7 | 7 (mean 7.556) | keep | guard-web green: 169/169 site tests, copy identical 27+31 pages, crawl + contrast pass |
| r0-web | review 0 must-fix: hero chip falls back to the wrapping pill below 16em of viewport; empty-state grid minmax(0,1fr) + hyphenation for its words; hex label tracking only from 720 px | cand 0 / base 0 / tie 9 (final vs fixed, seeds [189989810, 2388489100, 1051642542]) | 7 (mean 7.778) | fix | post-council guard fix like a9b |
| r0n-web | review 0 nice-to-haves: empty-state class from the templates instead of structural selectors; hex focus ring on the e-mail field where corner-shape is missing | - | - | fix | no visual change in Chromium |

Per-step aspect medians and per-aspect pairwise votes:

- **w1** (keep): medians typography 6, hierarchy 8, color_contrast 8, spacing 7, layout 7, consistency 6, accessibility 7, iconography 8, empty_error_states 4; pairwise consistency cand; seeds [27395677, 613857949, 1652060021].
- **w2** (keep): medians typography 6, hierarchy 8, color_contrast 8, spacing 7, layout 8, consistency 6, accessibility 7, iconography 8, empty_error_states 6; pairwise hierarchy cand, layout cand, iconography cand, empty_error_states cand; seeds [2867220145, 1525753868, 3429092604].
- **w3** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 7, layout 8, consistency 6, accessibility 8, iconography 7, empty_error_states 7; pairwise typography cand, layout cand, accessibility cand; seeds [535183923, 2360257594, 1439814247].
- **w4** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 7, layout 8, consistency 8, accessibility 8, iconography 7, empty_error_states 7; pairwise consistency cand, empty_error_states cand; seeds [2697320612, 2684769579, 27664825].
- **w5** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 7, layout 7, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise typography cand; seeds [2377647206, 4047388693, 2406975861].
- **w6** (keep): medians typography 7, hierarchy 8, color_contrast 7, spacing 7, layout 7, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise spacing cand, layout cand, consistency cand; seeds [676442542, 599206315, 1641683978].
- **w7** (keep): medians typography 7, hierarchy 8, color_contrast 7, spacing 7, layout 8, consistency 7, accessibility 8, iconography 8, empty_error_states 7; pairwise spacing cand; seeds [84511642, 589526624, 1145303209].
- **w8** (keep): medians typography 7, hierarchy 8, color_contrast 7, spacing 7, layout 8, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise typography cand, hierarchy cand, consistency cand, empty_error_states cand; seeds [1842274054, 893622326, 3736770380].
- **w9** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 7, layout 8, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise spacing cand, layout cand, consistency cand, accessibility cand; seeds [176800370, 4064644348, 351887573].
- **w10** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 8, layout 8, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise hierarchy cand, spacing cand; seeds [2659000451, 1801435031, 2096725542].
- **w11** (keep): medians typography 7, hierarchy 8, color_contrast 7, spacing 8, layout 8, consistency 7, accessibility 8, iconography 7, empty_error_states 7; pairwise typography cand; seeds [499622399, 152733097, 2715562490].
- **w12** (keep): medians typography 7, hierarchy 8, color_contrast 8, spacing 7, layout 8, consistency 8, accessibility 8, iconography 7, empty_error_states 7; pairwise consistency cand, accessibility cand; seeds [2583501821, 2024323798, 3066085814].

## Final

Branch head `73a31169`, three absolute runs like the baseline: minimum [7, 7, 7], mean [7.667, 7.667, 7.444]. Score (median) **7** (baseline 4, band 0.5); mean of aspect medians 7.667 (baseline 6.556).

| aspect | baseline (median of 3 runs) | final (median of 3 runs) |
|---|---|---|
| typography | 6 | 7 |
| hierarchy | 8 | 8 |
| color_contrast | 8 | 8 |
| spacing | 7 | 8 |
| layout | 7 | 8 |
| consistency | 5 | 8 |
| accessibility | 7 | 8 |
| iconography | 7 | 7 |
| empty_error_states | 4 | 7 |

## Stop

Step budget reached: 12 steps (w1-w12), all kept, about 4 h 20 min of the 6 h, weekly usage 36 %. A blind pairwise of the baseline shots against the final shots (seeds [1773405988, 1415361597, 2236588500]) prefers the final state on 7 aspects, ties 2, none for the baseline. Review 0 (rows r0-web, r0n-web) fixed two large-text reflow regressions the frozen 390 px set could not see (hero chip, empty-state headings) and added an overflow probe to the guard; a blind pairwise of the final against the fixed site tied on all 9 aspects. Floors left at 7: typography (more than five type sizes on the landing), iconography (colour emoji in the app mock-ups next to line icons), empty and error states (the empty changelog offers no next step; adding one needs words, which this job may not change).

