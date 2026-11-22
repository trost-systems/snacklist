# Round SC: the card after a store's last item (job 400)

A prototype round, never app code. When the last item of a store with an app link is ticked, its section hides and
the "Open app" key in its header goes with it. SC1 to SC5 are five cards for the top of the list that help at the
till. The recommendation and the open questions SC-Q1 to SC-Q12 are in `sc/RECOMMENDATION.md` (German: `.de.md`).

- `sc/index.html` is the round page. It takes `?lang=de`, `?theme=dark`, `?ts=310`, `?device=android` and
  `?links=today` (SC2 without a verified deep link).
- `phone.mjs` draws one phone: the launch list (RD1, categories hidden, `open-store-app` on; no prices, totals,
  trips or log) with a card in HintCard's slot. `measure()` reads rows, the card's height and its layout problems.
- `data.mjs` is the mock list (the Brandt family) and the states (a) to (d). `copy.mjs` holds every word.
- `sc/real/` is the release web build with the launch flags, captured by `tools/capture-today.mjs` (verify-snacklist's
  `launch.sh` with `VH_FLAGS_OFF=grocery-log,prices-and-trip-total,trip-mode VH_DEFINES="FLAGS_ON=open-store-app"`).
  verify.mjs checks that Today's headers and rows sit within 2 px of it at 100 % and 4 px at 310 %.
- `node docs/design/store-card/verify.mjs` checks every option in every state, language, theme, text size and phone,
  writes screenshots to `/tmp/p400/shots`, recomputes `sc/measured.json` and the tables in both recommendations,
  and ends with `all checks passed (n)`. `--write` updates `sc/measured.json` after a change.
- `tools/build.sh <out>` builds the preview on top of the previous design deployment, so older rounds keep their
  links, and puts round SC first in the overview.
