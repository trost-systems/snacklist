# Design history

How the family-groceries UI came to be. Reference material only, not app code. All data is mock data.

- **Round 1:** directions A–D (`a-grid`, `b-paper`, `c-cards`, `d-sentence`).
- **Round 2:** "Satz" variants E–G (`e-satz-zeilen`, `f-satz-etikett`, `g-satz-fliesstext`).
- **Round 3 / final:** H, "Satz · Laufweg" (`h-satz-final`): one sentence-style composer, list grouped by store in walking order.

- **Prices and trip total (job 189):** five price-entry prototypes and a recommendation in [`prices-trip/`](prices-trip/README.md). Not yet chosen (job 190).

Rounds 1 to 3 live in [`h-satz-final/`](h-satz-final/): sources (`sandbox-src/`), built previews (`h-dist/`, `r2-dist/`), screenshots (`shots/`), and the round-3 brief and review (`design-job-round3/`). Design rationale: `h-satz-final/sandbox-src/DESIGN_NOTES.md`.

## Run the sandbox locally

```sh
cd docs/design/h-satz-final/sandbox-src
npm ci
npm run dev        # open the printed URL; index at #/, final design at #/h-satz-final
npm test           # unit tests (vitest)
npm run e2e        # Playwright, one run at a time
```

Or serve a prebuilt preview without installing anything:

```sh
python3 -m http.server 8771 --directory docs/design/h-satz-final/h-dist
# http://127.0.0.1:8771/#/h-satz-final
```

## Feature prototypes

- **Grocery log (job 198):** [`grocery-log/`](grocery-log/), five interactive approaches behind one switcher, plus [`RECOMMENDATION.md`](grocery-log/RECOMMENDATION.md). Serve the repo root (`python3 -m http.server 4198 --bind 127.0.0.1`) and open `/docs/design/grocery-log/index.html`.

- **Feedback experience (job 260):** [`feedback-experience/`](feedback-experience/README.md): research, Today and five end-to-end feedback flows (FB1–FB5) with storyboards, a comparison table and [`RECOMMENDATION.md`](feedback-experience/RECOMMENDATION.md) (FB3, runner-up FB2). `verify.mjs` drives and screenshots every flow. Draft PR only; the preview is built by `build.sh` together with #414's overview.
