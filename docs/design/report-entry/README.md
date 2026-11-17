# Report content entry prototypes (job 278)

A throwaway HTML page for one decision: how the in-app “Report content” entry (DSA Art. 16, Legal Addendum B N-226 to N-229) sits next to feedback. Nothing here ships; the app is unchanged. Demo data only (the fictional Brandt family), no network calls.

- RC1 Chooser sheet, RC2 Two buttons in the hub, RC3 Its own More row (plus RC2’s hub button), and Today (main) as the baseline. Each option shows four live phones: More, the entry choice, the report form, the confirmation. The form is the same in every option and has its own section (filled in, the “Where” picker, “Somewhere else” with Legal’s N-260 hint, child abuse material, missing fields, over 5,000 characters, good faith and Send).
- `RECOMMENDATION.md` (and `.de.md`): the round, the measured table, the pick (RC2), the runner-up (RC3) and RC-Q1 to RC-Q6. The page renders it, so the page and the PR say the same.
- Controls: English or German (`?lang=de`), light or dark (`?theme=dark`), text at 100 % or 200 % (`?ts=200`), and FB4’s hub on or off (`?fb4=off`; it is off for every user today, and N-226 wants the entry either way).

## Files

- `copy.js`: every string. App strings are main’s ARB values; the form, its help texts and the confirmation are Legal’s B.4 copy word for word, with the two cuts the file’s header names; strings marked “proto” are this round’s proposal.
- `phone.js`: the options as a table (`options`: More’s rows and what the hub offers), the phone’s state (screen, sheet, back stack, the form) and its rendering. `missing()` holds the form’s rules: a kind, a place (a picked item, list or household name, or a description), 20 to 5,000 characters, good faith. Name and e-mail are never required.
- `page.js`, `proto.css`, `index.html`: the round page. `icons.js`: Material glyphs from Flutter’s icon font (`tools/icons.py`). Tokens and fonts come from `site/public/`.
- `verify.mjs [<folder or url>] [<out>] [<playwright dir>] [--write]`: drives the page in Chromium (Playwright from `<playwright dir>`, default the repo's `e2e/`, falling back to `~/family-groceries/e2e`). For every option, in English and German, at 100 % and 200 %, with FB4 on and off, it walks fresh phones with real clicks: taps from More to the report form, to writing feedback and to the hub, whether the report choice is in view where it is offered, whether the feedback screen offers reporting, the feedback group’s height on More. It checks Legal’s rules on a form reached from More, in every option with FB4 on and off (six kinds in B.4’s order, child abuse material hiding name and e-mail and another kind showing them again, the picked item shown, 19 characters refused, 5,001 refused, 5,000 fine, good faith required, sending without name and e-mail, B.4’s confirmation word for word with the number, Done back to the start, nothing under Your notes, the feedback form’s kinds exactly Bug, Idea and Other), every B.4 string in `copy.js` against Legal’s addendum (`LEGAL_ADDENDUM`, skipped where the file isn’t), text cut sideways or below, outside the phone or overlapping and 44 px targets on every frame in every look, page errors, the 390 px page, and in a build the back link and overview → round. It writes the screenshots into `<out>`, and compares the tables in both RECOMMENDATION files with the measurement (`--write` updates them). The last line is `all checks passed (N)`; any miss exits 1.
- `tools/serve.mjs`: a static server on 127.0.0.1 for the verify script (not a preview).
- `build.sh <out> [<add-sheet dir> [<list-declutter dir> [<feedback-experience dir> [<household-onboarding dir>]]]]`: the static folder for the preview. With job 273’s add-sheet folder and its arguments, #414’s overview sits at the root and the earlier rounds beside this one.

## Run

From the repo root: `node docs/design/report-entry/verify.mjs` (serves the repo; Playwright from `e2e/node_modules`). For the preview: `bash docs/design/report-entry/build.sh /tmp/dist <273>/docs/design/add-sheet <#414>/docs/design/list-declutter <260>/docs/design/feedback-experience <263>/docs/design/household-onboarding`, then `node docs/design/report-entry/verify.mjs /tmp/dist`. The overview’s link is an entry in #414’s `rounds.js` (`linked`, `href: '../report-entry/'`).

## How taps are counted

Every tap counts one, the tap that opens a sheet included. Scrolling counts none. A walk taps, on each screen, the first control that leads to its goal and that is not under an open sheet’s scrim.
