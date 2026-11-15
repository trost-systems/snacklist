# Feedback experience: prototypes (job 260)

A throwaway HTML sandbox for one decision: how users tell Peter what is wrong or what they want, and what Peter gets to debug with. Nothing here ships, and the app is unchanged. Shake-to-feedback (#281) is on hold (SH2), so each option makes its own shake decision. The option Peter picks replaces #281.

- **Today:** main’s More → Send feedback.
- **FB1, More + shake, with a preview:** #281’s shake, on by default, plus a per-field preview with switches.
- **FB2, Shake, then mark it on a screenshot:** shake asks first. The screenshot the app draws has every name and emoji from the list blacked out, and comes with highlight tools, the recent steps and the feature switches. This is the runner-up.
- **FB3, Report this, where it happens:** “Tell Peter” after the user moves an item to another category, on the “Change rejected” snackbar and on the paywall. Shake works only near an error. This is the recommendation.
- **FB4, Feedback with replies and status:** a hub in More with status, Peter’s replies and +1 on ideas. Shake is opt-in.
- **FB5, Ask at the right moment:** a crash prompt, a one-question survey and notes linked to error reports (PostHog EU, Sentry EU). Shake is off.

`RECOMMENDATION.md` and `RECOMMENDATION.de.md` hold the pick, the runner-up, the comparison table and the open questions FB-Q1 to FB-Q10. `RESEARCH.md` is the Stage 1 research: patterns and tools, each with its source and fetch date.

## Files

- `index.html`, `proto.js`, `proto.css`: the page. Its controls set the option, the scenario (wrong category, change rejected, idea), the language (English by default, `?lang=de`), the theme (`?theme=dark`) and the text size (`?ts=130`, `?ts=200`).
- `flows.js`: Today and FB1–FB5. Each flow is a small state machine with these parts:
  - `screens`: one phone state each.
  - `data-go`: the elements that lead from one state to the next.
  - `path`: the shortest way to a sent note, per scenario.
  - `story`: the five required steps (enter, what goes with it, how it is sent, afterwards, what Peter reads), plus extra frames for entries no single scenario covers (FB5’s crash prompt and survey, FB4’s +1, FB3’s paywall).
  - `route` and `peter`: the cards for steps 3 and 5.
- `ui.js`: the app’s chrome as HTML: list, More, sheets, the form’s parts, the preview panel and Peter’s desk cards.
- `model.js`: the strings, the fictional Brandt family’s list, the scenarios, the attachable fields and the eight debugging signals with their weights.
- `metrics.js`: the comparison table, computed from the flows: taps, debug points (signals weighted in `model.js`) and privacy exposure points.
- `icons.js`: Material glyphs from Flutter’s icon font (`tools/icons.py`).
- `verify.mjs <folder url> <out> [playwright dir]`: drives every path with real clicks and checks the taps against the table. It also checks the five steps, the shake decisions, that every switch drops its field, that FB2’s screenshot hides every list name and emoji until one row is revealed and highlights that row, that FB3’s item chip can be removed, that the Markdown tables match the page, that FB-Q1… are numbered and each has a default, and that every chrome string and category name equals the app's ARB (`arbOf` in `model.js`). On every phone it checks that nothing sticks out sideways, that no box is squashed or runs into the next one, that tap targets are 44 px or more, and that each snackbar has the app's style and sits right above what is below it. At 390 px it checks that no control is off screen. It takes 64 screenshots of the whole storyboard, step 5 included: every option in EN and DE, light and dark, at 100 and 200 %, and each scenario once. The last line is `all checks passed`; any miss exits 1.
- `build.sh <out> [list-declutter dir]`: the static folder for the Vercel preview. With #414’s `list-declutter/`, the overview of all rounds goes at the root and this round goes in `feedback-experience/`. The overview lists the round through `linked` in its `rounds.js`.

## Run it

```sh
bash docs/design/feedback-experience/build.sh /tmp/fb-dist ../list-declutter-checkout/docs/design/list-declutter
# serve /tmp/fb-dist with any static server on 127.0.0.1, then:
node docs/design/feedback-experience/verify.mjs http://127.0.0.1:<port>/feedback-experience/ /tmp/fb-shots
```

Without the overview, `build.sh <out>` builds this round alone, and verify skips the round trip to the overview.
