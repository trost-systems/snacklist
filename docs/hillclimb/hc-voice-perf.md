# Hill climb: hc-voice-perf

2026-11-25. Voice latency of the `alexa` function (Alexa skill) and the `voice` function (Siri and
in-app dictation), cold and warm. Local stack `fg-voice-hc` (port block 617xx) on hz, synthetic
data only, never a hosted project. Bounded at 8 iterations; a change was kept only when it
measured better and every test stayed green.

## How it is measured

`tool/hillclimb/hc-voice-perf/` (Deno; `deno.json` there, run from the repo root):

- `stack.ts` seeds a fresh synthetic account per run and removes it at the end: one user, a
  household with 24 open items, an analytics yes, a Siri credential (`create_siri_credential`),
  and an Alexa account link made by the OAuth flow Alexa runs (dynamic client, PKCE, consent,
  token). The API must be on 127.0.0.1.
- `bench.ts`: the four paths over HTTP through Kong and the edge runtime, as Alexa and the app
  call them. Alexa requests are signed with the stack's test CA (`scripts/alexa-test-ca.sh`), so
  the production `verifyRequest` runs. Each add is undone after it is timed (the three items
  deleted, Alexa's rate window cleared), so every add does the same work.
  - **cold**: the first request a fresh worker answers. The edge runtime container is restarted,
    the main worker is woken through `health`, then one request is timed. Includes worker boot,
    module graph, first DB connections, first Auth discovery and key fetch. Median of 5 per path.
  - **warm**: p50 and p95 of 30 requests per path against the running worker, after 5 warm-ups,
    the paths taken in turns.
  - **in handler**: the function's own `ms=` from its request line (`docker logs`), without boot,
    module graph and routing.
- `profile.ts`: the handlers wired as their `index.ts` wires them, in one Deno process against the
  stack, every dependency call timed. Telemetry is on against a stand-in for PostHog that answers
  after `--posthog-ms` (25 ms assumed; nothing leaves the machine). `--edge-runtime` simulates
  `EdgeRuntime.waitUntil`. `--db-rtt-ms` puts `latency_proxy.ts` between the handlers and
  Postgres, the network a hosted function has to its database and the local stack does not.

Paths: `alexa_launch` (LaunchRequest), `alexa_add` (AddItemIntent "Milch, Eier und Brot"),
`siri_read` (`{"mode": "read"}`), `siri_add` (`{"text": "Milch, Eier und Brot"}`), the last two
with the Siri credential.

Noise: warm numbers drift 10-20 % between runs on the same code as the database accumulates
state, so the final numbers are A/B pairs (this branch, then `origin/main`'s function files, twice)
on a freshly reset database.

## Where the time goes (measured)

- **Every statement costs two waits for the database.** `_shared/db.ts` uses `prepare: false` (for
  Supavisor), and postgres.js then sends Parse/Describe for a statement with parameters, waits for
  the parameter types, and only then Bind/Execute; it sends nothing else on that connection
  meanwhile (`describeFirst` in postgres.js's `connection.js`), so statements never pipeline. With
  10 ms of simulated round trip an Alexa add waits about 39 times, a Siri add 36, a Siri read 14.
  Hosted Siri adds log `ms=640`-`700` (docs/SIRI_SHORTCUT.md), against about 110 ms here.
- **Cold Alexa: `@peculiar/x509` takes 80-100 ms to import** in the edge runtime, a third of a cold
  launch; parsing Amazon's 5 roots another 9.5 ms. The first DB connection is 29-38 ms, Auth
  discovery 3-5 ms. Worker creation and routing (about 130 ms) are the runtime's.
- **DB work of an add**: `add_list_item` about 11 ms per item and the per-item name lookup in
  `voice/items.ts` about 7 ms per item (pg_stat_statements). The lookup keys every open item of
  the list (`item_name_key`) for each spoken item: 1.3 ms at 24 open items, 8 ms at 150.
- Alexa's request verification parsed and walked the whole certificate chain on every request
  (3.6 ms in-process with the 2-certificate test chain; Amazon's chain is longer).

## Attempts

| # | Change | Score | Kept |
| --- | --- | --- | --- |
| 1 | `alexa/verify.ts`: a chain that passed rule 2 is kept per anchors and PEM, with its signer's key, while the leaf and every CA walked through are valid; rule 3 runs every time | n/a (Alexa launch warm p50 13-15 -> 11.3 ms, in handler 10-12 -> 8) | kept |
| 2 | `_shared/after_response.ts`: Alexa's `remember` (not on a new link, whose failure must still answer 500) after the answer through `EdgeRuntime.waitUntil`; inline without the runtime | n/a (Alexa launch warm p50 11.3 -> 7.9 ms) | kept |
| 3 | The same for the analytics subject lookup and the PostHog flush (`counted`, `track`) | n/a (profile with PostHog at 25 ms: Siri read 35 -> 15 ms, Siri add 98 -> 67, Alexa add 97 -> 80) | kept |
| 4 | Open two pool connections and fetch Auth's discovery and JWKS at module load | n/a (cold A/B within noise; dynamic import blocks event loop) | reverted |
| 5 | Pipeline the read-only statements of `voice/items.ts` | n/a (A/B pairs disagree: +3, -6 ms) | reverted |
| 6 | `voice/read.ts` `itemsToSay`: the read-back without `listItems`' `counts`, which scans the household's whole item history | n/a (Siri read warm p50 29.6 -> 27.6 ms, 3 A/B pairs) | kept |
| 7 | Attempt 5 again with 5 ms of simulated round trip | n/a (postgres.js does not pipeline describe-first statements) | reverted |
| 8 | `householdLists`: lists, default list and order mode in one statement instead of three (`listCatalog` + `orderMode`), for the read-back and both adds' `lists` | n/a (5 ms simulated RTT: Siri read 97-100 -> 73.5 ms, Alexa add 316 -> 271-302, Siri add 294 -> 281.5) | kept |
| 8b | Final A/B measurement across all four paths (geometric mean of HTTP warm p50s) | **38.01** (ms; 15.2/126/31.7/116 -> 7.3/112/23.4/109) | kept |

Equivalence: `voice/read_integration_test.ts` checks `householdLists` against `listCatalog` and
`orderMode`, and `itemsToSay` against `listItems`, by categories and by learned places (which
differ for its list), and with another list as the caller's default. Each of these mutants fails
it: the default list not picked, lists in another order, the two orders swapped. The verify
cache's tests (`verify_test.ts`) fail when the cache ignores the validity window.

## Result

Baseline **51.50** (ms, geometric mean of the four paths' HTTP warm p50 on `main`).

HTTP bench, means of 2 A/B pairs on a fresh database (ms):

| Path | Cold median main / now | Warm p50 main / now | Warm p95 main / now |
| --- | --- | --- | --- |
| Alexa launch | 332 / 327 | 15.2 / 7.3 | 17.1 / 8.7 |
| Alexa add | 476 / 457 | 126 / 112 | 132 / 127 |
| Siri read | 252 / 236 | 31.7 / 23.4 | 32.9 / 25.7 |
| Siri add | 332 / 322 | 116 / 109 | 119 / 117 |

Production-like profile (in-process, 5 ms DB round trip, PostHog at 25 ms, `waitUntil`), medians
of 2 runs of 15 (ms):

| Path | main | now |
| --- | --- | --- |
| Alexa launch | 35.7 | 17.1 |
| Alexa add | 363 | 285 |
| Siri read | 155 | 76.5 |
| Siri add | 315 | 277 |

Cold starts did not move beyond noise: what dominates them (worker creation, the x509 import,
the first connection) is the runtime's, `_shared/db.ts`'s or the library's.

## Left for later (not done here)

- The two waits per statement: `prepare: true` behind Supavisor's session port, or fewer
  statements per request (the add loop's lookup, add and similar-items reads in one SQL function).
  `_shared/db.ts` is in the `mcp` function's module graph, frozen while the ChatGPT app is in review.
- The name lookup in `voice/items.ts` grows with the open list; an expression index on
  `item_name_key(name)` was not used by the planner as the query is written (8-11 ms at 150 open
  items with and without it).
- Merging Alexa's `lists` and `addItems` into one transaction saves about 4 waits; it needs a new
  `Deps` shape in `alexa/handler.ts`.
- Replacing `@peculiar/x509` for the chain check would cut a cold Alexa start by about a third;
  a hand-written certificate parser is a security review of its own.
