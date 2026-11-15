# List screen declutter: prototypes (jobs 223, 227 and 230)

A throwaway HTML sandbox for one decision: how to give the list more room on the List tab. Nothing here ships. The app is unchanged.

Each round has its own page, with only that round's sets, phones, recommendation and data (job 238). `index.html` is the overview: it lists the rounds newest first and forwards old links (`/#/st`, `/#/ST3`, `/#/rec1`) to the page that now holds the view. `rounds.js` is the registry of rounds (path, title, the "what you're comparing" line, sets, recommendation, data), plus `linked`: rounds of other features in their own folder beside this one (job 260's `../feedback-experience/`, job 263's `../household-onboarding/join/` and `../household-onboarding/create/`, job 273's `../add-sheet/add-feedback/` and `../add-sheet/reload-indicator/`), listed on the overview only; a new round is one entry there plus a `<path>/index.html` like `st/index.html`, never new buttons on an older round's page. `#/every` (all of one round's phones, for the shoot scripts) exists on each round page only; the overview leaves it alone.

- `st/`: per-store subtotals (job 230, Nov 14). Views `#/st`, `#/recst`, `#/ST1` … `#/ST5`, `#/today`, `#/R2`.
- `ss-bb/`: switcher sheet and bottom area (job 227, Nov 13). Views `#/ss`, `#/bb`, `#/ld4`, `#/rec`, one label such as `#/BB4`.
- `round1/`: round 1 (job 223, Nov 13). Views `#/r1`, `#/rec1`, `#/LD1` … `#/LD5`.

Round 2 (job 227) builds on Peter's feedback on round 1. It has a fixed base (B1 to B6: combined switcher in a fixed see-through header, First steps as today, the total as a list row above "Zuletzt verwendet", three tabs, no plan/shop toggle, LD1's trip prompt) and three sets:

- SS1 to SS5: five ways to add list switching and management to today's household sheet.
- BB1 to BB5: five bottom areas (add field plus three tabs), with a fake keyboard to show the field above it.
- LD4-3T: LD4's dock with three tabs, the switcher kept in the header.

R2 is the base with today's bottom, the yardstick for the BB set.

Job 230 adds the ST set (`st/`, in English unless `?lang=de`): ST1 to ST5, five ways to show subtotals per store and a final total on Peter's round 2 pick (R2's phone, its switcher opening SS5, no trip prompt). The set has its own data (`data=one`, `three`, `mixed`: one store, Lidl, dm and a market with a long name, and the same plus "Ohne Laden"), with weighed items, items without a price and a ticked priced item. Its pick and questions (ST-Q1 to ST-Q7) are `RECOMMENDATION-ST.md` and `RECOMMENDATION-ST.de.md` (`st/#/recst`). `shoot-st.mjs <sandbox-url> <out>` screenshots the set, writes `st-items-visible.tsv` and `st-height-vs-r2.tsv`, and checks that the subtotals add up to the total, that one store shows none, the "ohne Preis" counts, a store bought in full, ST4's fold, the ST3 and ST5 jumps, 48 px targets, nothing sticking out or overlapping at 100, 130 and 160 % in both languages and themes, the phone view at 390 × 664, and that the page opens in English without `lang` and in German with `?lang=de`. It exits 1 on any miss. A third argument names the Playwright module directory (default `~/family-groceries/e2e/node_modules/`).

Round 1 (today, LD1 to LD5) is `round1/`.

- `index.html`, `overview.js`: the overview and the old-link forwarding.
- `rounds.js`: the rounds, one entry each.
- `<round>/index.html`, `proto.js`, `proto.css`: a round's page, the phones and the switchers for set, data, people (rounds 1 and 2), language, theme and text size.
- `model.js`: the synthetic households (`one`, `two`, `many` with long names), the same items and prices as the baseline drive of the real app, and the UI strings in German and English.
- `variants.js`: labels, slugs and the notes next to each phone.
- `icons.js`: the app's Material glyphs, generated from Flutter's `MaterialIcons-Regular.otf`.
- `RECOMMENDATION.md`, `RECOMMENDATION.de.md`: round 2's pick, the counts and the open questions (LQ-R1 to LQ-R6). Round 1's are `RECOMMENDATION-R1*.md` (LQ-D1 to LQ-D8).
- `shoot-st.mjs`: the ST set's checks (above).
- `shoot-pages.mjs <sandbox-url> <out>`: the overview (three rounds and the linked feedback, join and create rounds, newest first, English and `?lang=de`), every old link landing on its round's page with the query kept, each page's title, comparing line and way back, and that each page has only its own buttons. It exits 1 on any miss.
- `shoot.mjs <sandbox-url> <out>`: rounds 1 and 2, screenshots, the items-visible table (`items-visible.tsv`), the bottom heights (`bottom-height.tsv`) and the checks (sheets, list management, tabs, 48 px targets, keyboard, header layer, total row, trip, touch, overflow at 100, 130 and 160 % text, no page errors). It exits 1 on any miss.
- `build.sh <dir>`: copies the sandbox into one static folder for the Vercel preview.

Open locally from the repo root with any static server, then `docs/design/list-declutter/`. The shoot scripts take that folder's URL (ending in `list-declutter/`) and open each view on its round's page. URL parameters (English by default): `?lang=de&theme=dark&data=big&scen=many&ts=130#/SS4` on `ss-bb/`. `trip=1` starts a job 217 trip at load. On a screen narrower than 440 px (Peter's phone) the page shows one phone at a time: it fills the screen under a two-row strip (the set and its variants), without the fake status bar and home indicator, so its bottom area is always in view. "Optionen" unfolds data, people, language, theme and text size. The counts are measured on the 390 × 844 frame on a computer.

The bottom follows the app's geometry: the add band is 72 px (52 px field), and the tab band is the 52 px pill plus max(12, safe area − 8), so 78 px on an iPhone (`app/lib/app/shell.dart`, `_bandHeight`). Text size multiplies every font size in the phone. Rows, bars and buttons grow with it, and the tab labels clamp at 1.5 as the app's pill does.
