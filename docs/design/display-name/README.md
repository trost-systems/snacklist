# Display name: prototype rounds DN and DE (job 293)

A throwaway HTML sandbox for two decisions about the display name. Nothing here ships; the app is unchanged. Mock data only (Lea and Peter of the fictional Familie Brandt), no network calls.

- `index.html`: the overview. It links both rounds and shows each round's pick and runner-up.
- `dn/`: round DN. How the guided start, and the join path, ask “How should we call you?”. Today and DN1 to DN5. `RECOMMENDATION.md` (and `.de.md`) holds the pick (DN3), the runner-up (DN4), the measured table and DN-Q1 to DN-Q8.
- `de/`: round DE. Where a signed-in user changes the name, and where the change shows. Today and DE1 to DE5. `RECOMMENDATION.md` (and `.de.md`) holds the pick (DE1), the runner-up (DE2), the measured table and DE-Q1 to DE-Q7.

Each round page shows every option as live phones. The first phone walks the whole path (DN: from “Who do you shop with?” or the join page to the list; DE: from the list to a saved name), with its taps, screens and sheets counted under it. The others open on the option's own screen. Below them, “What others see” shows Peter's member list, his list and the join page of Lea's invite, fed by the last walk or save. The controls are English or German (`?lang=de`), light or dark (`?theme=dark`), text at 100 %, 200 % (`?ts=200`, Android's largest) or 310 % (`?ts=310`, iOS's largest accessibility size), and the scenario (`?persona=email|google|appleHidden|long|emoji`). DN also has the path (`?role=create|join`).

## Files

- `copy.js`: the app strings (the ARB's where the app has one, new copy for the options) and the mock people. `derivedName` is what `handle_new_user` stores without a name (the e-mail's local part). `firstName` is what `preview_invite_public` shows (the first word, never the derived name).
- `phone.js`: the phone. It holds the state (screen, sheet, draft, profile `{ name, source: derived|social|chosen }`), the flows per option (`flow()`), the actions and the screens. Every `[data-act]` click counts as one tap. So does a tap into a field that doesn't get the focus by itself.
- `page.js`, `proto.css`: the round pages and the overview. `icons.js` holds Material glyphs from Flutter's icon font (`tools/icons.py`). Tokens and fonts come from `site/public/`.
- `verify.mjs [<repo root or build dir>] [<screenshot dir>] [<playwright dir>] [--write]`: drives both rounds in Chromium.
  - DN walks every option for five people (e-mail, Google, Apple without a name, a 49-character name, a name with an emoji), creating and joining, in English and German, at 100 %, 200 % and 310 %. It walks the complete path and the skip path, and checks every screen for text that is cut, spills past the phone, overlaps, or is a target under 44 px.
  - It pins that the typed name reaches Peter and the join page, that DN1 and DN3 can't be skipped, that a name typed before the account wins over Google's, that DN3 and DN4 need no typing with Google, and that today shows “lea.brandt87” and no name on the join page.
  - DE walks every option from the list to a saved name and checks that the strip shows it. It measures whether the entry is visible without scrolling and how far DE3 pushes More's rows.
  - In a 390 px mobile context (Peter's phone) it checks that the overview and both rounds never scroll sideways, in five settings each.
  - It checks the overview links, the back link, both languages, the pick and runner-up in both RECOMMENDATION files, and compares the measurements with `<round>/measured.json` and the tables in both RECOMMENDATION files. `--write` updates them.
  - It writes screenshots into `<out>` (default `$TMPDIR/display-name-shots`; the PR's set is in `docs/screenshots/293/`). The last line is `all checks passed (N)`; any miss exits 1.
- `tools/serve.mjs`: a static server on 127.0.0.1 for the verify script (not a preview).
- `build.sh <out> [<report-entry dir> …]`: the static folder for the preview. This round goes in `<out>/display-name/`, and the earlier rounds and #414's overview are built first when given.

## Run

From the repo root: `node docs/design/display-name/verify.mjs`. For the preview: `bash docs/design/display-name/build.sh /tmp/dist <278>/docs/design/report-entry <273>/docs/design/add-sheet <#414>/docs/design/list-declutter <260>/docs/design/feedback-experience <263>/docs/design/household-onboarding`, then `node docs/design/display-name/verify.mjs /tmp/dist`.

## How taps are counted

Every tap counts one: a chip, a button, a Google or Apple sheet's account row or Continue, and a tap into a field that has no autofocus. A screen whose purpose is the name focuses its field on arrival, so that field costs no tap. Typing and scrolling count no taps; the table says whether a path needs typing. The usage-data question and the sign-in's own screens are the same in every option and are left out or counted the same.
