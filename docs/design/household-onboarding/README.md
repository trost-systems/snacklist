# Household onboarding: join and create prototypes (job 263)

A throwaway HTML sandbox for two decisions: how a new user who was invited joins a household (round JH) and how a new user creates one (round CH), now that “Paste invite” should go. Nothing here ships; the app is unchanged. Mock data only (the fictional Brandt family of the demo videos).

- `join/`: round JH, Today and JH1 to JH5. `join/RECOMMENDATION.md` (and `.de.md`): the pick (JH3), the runner-up (JH2) and JH-Q1 to JH-Q9.
- `create/`: round CH, Today and CH1 to CH5. `create/RECOMMENDATION.md` (and `.de.md`): the pick (CH1), the runner-up (CH2) and CH-Q1 to CH-Q6.
- `RESEARCH.md`: Stage 1, how comparable apps onboard invited people, deferred deep links, universal links, QR, codes, web join, consent order, and what follows for Snacklist (sources with fetch dates).

Each page has an overview (cards, the comparison table, all options side by side as small phones, the recommendation) and one view per option: the six steps and the hand-off in words, a storyboard of every screen on the path with what is tapped, and a Try-it phone. Controls: the scenario (JH: invite link, QR code or typed code; app installed or not; “Confirm new members” on or off. CH: invite by link, QR or code), English or German (`?lang=de`), light or dark (`?theme=dark`), text at 100, 130 or 200 % (`?ts=200`, the largest the app allows without clamping on Android). The phone is 390 × 844, measured as an iPhone; on a screen narrower than 440 px each phone fills the screen.

## Files

- `join/flows.js`, `create/flows.js`: each option as data: `screens` (state → HTML), `meta` (state → the steps it covers, its caption, its screen group) and `paths(scenario)` → `{ list, app }` (JH) or `{ list, share }` (CH), the steps from the invite (or the start screen) to the goal and how each is reached (`tap`, `type`, `wait`, `auto`, with `n` for actions worth more than one tap). Also the table facts and the option's details.
- `metrics.js`: taps (tap and scan steps, `n` each), screens (distinct screen groups after the first), and the scenario combinations.
- `ui.js`: today's app chrome (start, sign-in, consent, join screen, approval wait, list with the switcher header, switcher sheet and invite page of job 242, invite card) and the phone's system screens (WhatsApp, camera, home screen, App Store, Safari with the static join page, Sign in with Apple, share sheet, App Clip card). Today's strings are copied from `app/l10n/app_*.arb` and `app/web/join/join.js`.
- `model.js`: the mock household, its list, the code `K7QM-4XPA`, and the strings in English and German.
- `proto.js`, `proto.css`: the page. `icons.js`: Material glyphs from Flutter's icon font (`tools/icons.py`).
- `tools/tables.mjs`: writes each round's comparison table into its RECOMMENDATION files from the flows; `--check` compares.
- `tools/serve.mjs`: a static server on 127.0.0.1 for the verify script (not a preview).
- `verify.mjs [<folder or url>] [<out>] [<playwright dir>]`: walks every option, scenario and goal with real clicks in the Try-it phone and checks the tapped count against the measured one, the end state, the required steps (JH: entry, landing, account, consent, the approval wait exactly when it is on, the shared list; CH: start, account, consent, list, and an invite shared), that no screen before the join shows an item name and that every landing names Mia and the household, the table on every scenario, the Markdown tables, the numbered questions with defaults, the pick and runner-up, the back link, and on every storyboard phone in EN and DE, light and dark, 100 and 200 % that nothing sticks out sideways (96 screenshots into `<out>`). On a preview build it also clicks overview → each round → back. The last line is `all checks passed`; any miss exits 1.
- `build.sh <out> [<list-declutter dir>] [<feedback-experience dir>]`: the static folder for the Vercel preview, with #414's overview at the root and job 260's round beside it when given.

## Run

From the repo root: `node docs/design/household-onboarding/verify.mjs` (serves the repo itself). For the preview: `bash docs/design/household-onboarding/build.sh /tmp/dist <#414 checkout>/docs/design/list-declutter <260 checkout>/docs/design/feedback-experience`, then `node docs/design/household-onboarding/verify.mjs /tmp/dist`.

## How taps are counted

A tap on a button, a link, the camera's link pill, a chip or a system sheet counts 1. “Open the App Store and search for Snacklist” counts 2, copying a code from a chat (hold, Copy) 2. Typing, waiting for someone else and switching apps count 0. JH paths start at the invite in front of the user (the chat, Mia's QR, a code), CH paths at the start screen; both sign in with Apple and take Skip where a step offers it.
