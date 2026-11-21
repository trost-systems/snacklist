# Detecting shopping trips from plain ticks (job 351)

A beta user and Lea never start a trip. They only tick. Learned order (IO4, job 347, draft PR #604) can only learn from a walk through a store, so the app has to notice a walk in plain ticks. This page red-teams Peter's approved starting rule against chaotic shopping, proposes the smallest fixes and the rule that results, and measures both rules on synthetic households. It also covers what users see, what happens to the trip question users already see on every tick, and how they fix a wrong trip. Job 352 builds on it. Nothing here ships.

Synthetic data only. No real tick history was read (see "Real data").

## In short

- The starting rule holds for clean walks. It breaks on the habits that matter most for Lea and the beta user: ticking at the checkout, catching up at home, "we still have that" ticks at home, and a phone that was offline in the store. In the simulation it hands the learner the wrong order for 10 to 34 % of item pairs. 253 of the 1,806 keys it writes into `item_store_memory` end at a store the household does not usually buy them at (14 %). With job 347's learner, its order ends below the untaught prior in 8 of 9 households: learning made the list worse.
- The final rule has two lines of defence. The first is how a walk looks: a **pace rule** (a median of at least 20 s between steps, because people walk between shelves), **the phone's own tap time** instead of the server's commit time, steps of ticks under 6 s apart, and travel time between stores. The second does not depend on pace: once a store has 3 taught walks, a walk that agrees with its known order on fewer than 60 % of pairs is a **shuffle** and teaches neither order nor store memory. And an item moves to another store in store memory only after the **second** walk that bought it there.
- Order accuracy after 12 weeks rises in all 9 households, by 4 to 14 points over the starting rule with job 347's learner. The detector alone (same learner on both sides) is worth 0 to 6 points; the learner alone −1 to 12 (12 where a couple splits the list). Store memory keys ending at the wrong store: 7 of 141 (5 %).
- **What the pace rule alone does not catch.** If a delivery is unpacked slowly (15 to 60 s per item) or a catch-up at home is slow, those ticks look like a walk. The shuffle gate then rescues the order (slow unpacking: 84 % with the gate, 78 % without, prior 80 %), and confirmation keeps store memory clean (0 of 12 keys wrong; 41 of 193 with the approved T4a). What remains: the first 3 walks at a store are not gated, a slow catch-up in the order the list shows teaches that order again (15 % wrong pairs in the simulation; in the app the list shows the learned order, so that is mostly a no-op), and both thresholds are calibrated on the generator's assumptions only (TD-Q8).
- Every change to Peter's rule is its own question with its own variant row: H1 (TD-Q10), H2 (TD-Q1), T1a pause (TD-Q2), T1a "all ticked" end (TD-Q11), T3a travel time (TD-Q12), tap time (TD-Q13), T4a confirmation and gate (TD-Q14). T2a and T5a stay as written.
- The trip question „Kaufst du gerade ein?" opens after every own tick today, and „Nein, nur abgehakt" is forgotten at once. With detection, it asks once per shop: after „Nein" it stays quiet until 30 minutes without a tick. A detected trip appears afterwards in Verlauf with "Aus deinen Häkchen erkannt". No live "Looks like you're at Rewe" hint (TD-Q4, TD-Q5).

## What the server knows today

Checked in `supabase/migrations/` on main at a1edd966.

| Fact | Where | What it means for detection |
| --- | --- | --- |
| Every tick and untick writes an `item_events` row: `action` bought or restored, `actor`, `list_id`, `created_at` | `20261022150000_foundation.sql:204`, `20261108144409_households_lists.sql:368` | The tick history exists. There is no store, no source and no device time. |
| `created_at` and `items.bought_at` are the server's `now()` at commit | `items_before_write` (`20261121120100_items_created_at_bounds.sql`) | An offline walk arrives as one burst at the exit, and its times say nothing about the walk. |
| The app has the tap time (`SetStatus.at`, `app/lib/list/model.dart:1167`) but does not send it | `_sendOne` in `app/lib/list/list_repository.dart:650` sends only `status` and `store_id` (the review drive saw `PATCH /items {"status":"bought"}`) | Job 352 must send it. |
| `item_events` has no source | `items_log_event` | Siri, Alexa, MCP and API ticks look like app ticks. T5a needs a column. |
| `item_events` has no store | same | The store at the tick time is gone once an item moves. Job 347 already plans `item_events.store_id`. |
| Every household member can read every member's `item_events` rows, `actor` and `created_at` included | policy `item_events_select` (`foundation.sql:419`), table-level select for `authenticated` | The review read another member's ticks with microsecond times through PostgREST. The app reads it only through `suggest_items`, which runs as the member (`security invoker`), so a revoke has to change that function too. See Legal notes. |
| `trip_sessions.source` is `ask` or `manual`; `started_by` is one person | `20261114181718_trip_mode.sql:13` | A detected trip fits with a new source `detected`; a two-person trip needs a second column. |
| A trip at a pharmacy is never saved (GL-2) | `20261114213100_trip_mode_skips_pharmacies.sql` | Detection must skip pharmacies too. |
| The trip question opens after every own tick; „Nein" is not remembered | `features/trip-mode.md` (`tm-ask`) | The people this job is for dismiss a sheet on every tick today. |

## Final rule

```text
input: item_events of the household, action bought or restored,
       with store_id, source and client_at (all proposed for job 352)

1  ticks   := events where source = 'app'                                   -- T5a
   time(e) := e.client_at + offset(e.actor)                                 -- F1, TD-Q13
              offset = 10th percentile of (created_at - client_at) over the actor's ticks
              with a client_at, from 7 days before the tick to the run (at most 36 hours
              after it); online ticks set it, offline ones commit late;
              created_at when client_at is null (old app builds, or a tap time
              outside 7 days before to 24 hours after the commit)
   drop every bought tick the same person restored within 10 minutes,
   and the restored tick                                                    -- T5a

2  per person, in time order:
   run      := ticks no more than 10 minutes apart                          -- T1a; the "all
               ticked" end is dropped (TD-Q11)
   pieces   := split each run where the item's store changes,               -- F4, TD-Q12
               but only where at least 2 minutes passed (getting there takes time).
               A short stretch of another store between two stretches of one store
               belongs to the surrounding store. A single tick at the start or end
               joins its neighbour unless it is the last open item of its store (T3a).
   steps    := ticks of a piece less than 6 s apart are one step            -- F2
   walk     := piece with at least 3 steps                                  -- H1 in steps
               and a median gap between steps of at least 20 s             -- F3, TD-Q10
               or a piece of 1 or 2 ticks that ticks the last open items of
               its store within 5 minutes                                   -- T3a
   burst    := any other piece

3  trip    := a walk; the person's next walk at the same store within 30 minutes
               joins it (a pause)                                           -- F5, TD-Q2
   a burst within 30 minutes after a walk of the same person (same store, or no store)
               joins that trip                                              -- F6
   a burst of 5 or more ticks that joins no trip is a trip of its own       -- F6, H2, TD-Q1
   anything else is a plain tick, as today
   store(trip) := the store most of its tagged ticks have                   -- T4a
   trips of different people at the same store, overlapping
               (plus 10 minutes), are one household trip                    -- T2a
   no trip at a pharmacy                                                    -- GL-2

4  teach order: each walk at a known store, as its steps in time order
               (keys of one step are tied); bursts never teach              -- F7
   learner: the walk's keys trade places to match the walk, halfway          -- F8
   shuffle: once the store has 3 taught walks, a walk whose pairs agree with
               the store's order less than 60 % of the time teaches nothing -- F9

5  teach store memory (T4a): a storeless item, or an item tagged to another store,
               in a walk that is not a shuffle, proposes the walk's store.
               The item moves on the second proposal of that store          -- F10, TD-Q14
```

**When it runs.** A pg_cron job (free tier) every 5 minutes picks households with an app tick older than 10 minutes that no run has seen (a `detected_through` timestamp per household) and calls `detect_trips(household)`, a `security definer` function. It recomputes the 36 hours before the newest tick. pg_cron is on in the hosted project's extensions list for the free plan; job 352 checks that it is enabled before relying on it.

### Changes to the approved rule

Each row is a question for Peter. "Variant" names the row in the variant table below that puts the approved rule back into the final rule, all households pooled.

| Rule | Approved | Proposed | Variant: approved → proposed | Question |
| --- | --- | --- | --- | --- |
| H1 | 3 ticks, gaps under 5 min | 3 steps (ticks under 6 s apart are one), median step at least 20 s; ticks up to 10 minutes apart stay one run | "H1 as approved": precision 82 → 90 %, phantom trips 303 → 128, walk pairs wrong 20 → 11 %, store memory keys wrong 19/291 → 7/141, order 84 → 86 %. Recall drops 88 → 84 %: checkouts and catch-ups stop being sessions (checkout-ticker: walk pairs wrong 27 → 3 %). For the gap, "gap 5 min": recall 84 → 82 %, split visits 44 → 59 | TD-Q10 |
| H2 | every detected session is a trip | a walk is a trip; a burst only from 5 ticks, and never teaches | "bursts from 3 ticks": phantom 303 → 128 for recall 88 → 84 %. "bursts never trips": recall 63 % | TD-Q1 |
| T1a, end | 10 min quiet, or every item of the store ticked | 10 min quiet only | "T1a all-ticked end kept": precision 88 → 90 %, phantom 137 → 128; everything else equal. A forgotten add-and-tick right after the last item no longer starts a second trip | TD-Q11 |
| T1a, later | same person, same store later = new trip | within 30 min the trip continues | "no pause merge": split visits 104 → 44 | TD-Q2 |
| T1a, gap | 10 min | 10 min (kept) | "gap 15 min" is a little better here (recall 85 %, 36 splits) and "gap 5 min" worse (82 %, 59). The difference is small and generator-bound, so 10 min stays | none |
| T3a | a store with under 3 items counts if all ticked within 5 min | the same, and a store change needs 2 min without a tick | "T3a as approved": precision 87 → 90 %, phantom 141 → 128. A lone item tagged to another store and ticked last no longer makes a 1-item trip there | TD-Q12 |
| new | server commit time | the phone's tap time, corrected by its usual offset; stored within 7 days before to 24 hours after the commit | "commit times": offline household (clock an hour ahead) order 86 → 89 %, recall 87 → 89 %, store memory keys wrong 15 → 7 %. "client_at clamped to 5 min ahead" (this report's first proposal) is as bad as no tap time for a phone running ahead | TD-Q13 |
| T4a | minority and storeless items learn the majority store at once | a walk that is not a shuffle proposes; the second proposal moves the item | "T4a as approved": 128 of 1,226 keys end wrong (10 %) → 7 of 141 (5 %). Slow-unpacker: 41/193 → 0/12. The simulator under-counts what confirmation learns, because it never feeds store memory back into later adds; in the app the cost is one more walk before an item moves | TD-Q14 |
| T2a, T5a | as written | as written | | none |

The first version of this report credited T4a "narrowing" (75 % one store, never the first or last tick) with 273 → 0 wrong writes. That was wrong: almost all of it came from walk detection. With narrowing switched on inside the final rule, keys ending wrong move from 7/141 to 6/105, and it learns a quarter fewer keys ("T4a narrowed too"). It is dropped.

**Rejected after measuring.** In the simulator: narrowing T4a (above); an outlier gate of 0.5 (slow-unpacker 82 % instead of 84 %) or 0.7 (same as 0.6); a pace of 40 s (fewer wrong pairs, but 5 % of real walks in the generator have a median step under 41 s). In one-off runs of the first round that are not in the shipped simulator: pairwise votes with the prior as one vote (never beat the prior, because 160 unseen items dilute every learned pair), teaching a backwards walk through a known store as its reverse (no gain), and a catch-up burst joining another member's trip (35 splits became 33).

## Red team

"Start" is the starting rule, "Final" the final rule. A test name is in `sim/detect_test.ts`. "Sim" points to a household in the simulation table.

| # | Case | Start | Final | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Ticks everything at home after shopping, 2 s apart | A trip, and it teaches the screen order back to itself | A trip in history, teaches nothing (F3, F6) | test "ticking everything at home afterwards" |
| 2 | The same, slowly: 15 to 60 s per item while putting things away | A trip, teaches the screen order | Looks like a walk and teaches the order the list showed. In the app that is the learned order, so it mostly confirms it; in the simulator (which shows the prior) 15 % of its pairs are wrong. **Remains** | sim slow-catchup: order 85 %, prior 83 % |
| 3 | Ticks 3 or 4 items at home: "we still have that" | A phantom trip that teaches order and moves store memory | No trip (F6) | test "three or four quick ticks"; sim home-sweeper: 129 phantom trips become 8 |
| 4 | Ticks at the checkout, in conveyor order | Teaches the conveyor order | A trip from 5 ticks, teaches nothing | sim checkout-ticker: walk pairs wrong 27 % become 3 % |
| 5 | Ticks the forgotten rows in the car | A second trip, or part of the walk if under 10 min | Joins the walk's trip, teaches nothing | test "catching up on forgotten ticks in the car" |
| 6 | Two stores back to back, 3 to 9 min apart | One session; the first store's items move to the second store in store memory | Two trips; no store memory | test "two stores back to back" |
| 7 | Two stores in one mall, under 2 min apart | One session, majority store | One trip, majority store. **Remains**: the minority items show under the wrong store and propose it in store memory (they move only if a second walk agrees). Fix by "New trip from here" | by design |
| 8 | Bought an item tagged for another store, mid-walk | Moves to this store at once | Moves after the second such walk | test "an item bought where it is not tagged" |
| 9 | The same at the last tick | Moves at once | Stays in the trip; proposes this store | test "a last tick tagged to a store with items left" |
| 10 | A storeless item in a walk | Joins, learns the store | Joins; learns the store on the second walk | same tests |
| 11 | Partner at home ticks 1 to 3 "we have that" while the other shops | Part of the household trip if 3 ticks | Out of the trip | test "a partner ticking" |
| 12 | Partner at home ticks 5 or more while the other shops at that store | Merged into the trip | Merged into the trip. **Remains**, rare; fix by removing the lines | by design |
| 13 | Phone offline in the store, syncs at the exit | Times are a 1 s burst at the exit | Walk from the tap times (F1) | test "offline"; sim offline-wrong-clock |
| 14 | Phone clock off, or a hand-set time zone | Unaffected (server time) | Corrected by the person's usual offset, ahead or behind, offline walks included, as long as the tap time is within 7 days before to 24 hours after the commit. A phone more than 24 hours ahead, or a walk synced more than 7 days later, falls back to commit times (an offline walk then teaches nothing) | tests "a device clock an hour off", "a phone clock an hour ahead", "the clock offset comes from online ticks", "a tap time beyond the stored bounds", "a walk synced three days later"; sim offline-wrong-clock (an hour ahead) |
| 15 | The clock is put right after weeks of being off | Unaffected | The offset reads the last 7 days only | test "the clock offset uses the last week only" |
| 16 | Ticks from two devices, or retried ops, arrive out of order | Server order | Tap-time order; a late tick reshapes the trip on the next run | by design; reconciliation in "For job 352" |
| 17 | The clock jumps mid-trip (network time fix) | Unaffected | One step lands out of place; the halfway learner damps it. **Remains**, rare | not simulated |
| 18 | A stray tick, undone within seconds | Dropped (T5a) | Dropped | test "a stray tick" |
| 19 | Unticked after the trip closed ("wasn't bought") | Stays in the trip | Leaves the trip on the next run within 36 h; its order lesson goes on recompute | by design |
| 20 | A 12 min wait at the deli counter | Two trips | One trip, taught as two walks (F5) | test "a 12-minute wait"; sim slow-trips: 43 splits become 0 |
| 21 | A slow store (IKEA), 2 to 8 min between items | One trip | One trip; slow is fine for the pace rule | sim (store ikea in every household) |
| 22 | A child taps rows on a parent's phone | A trip if 3 taps | A burst: no trip under 5 taps, never teaches. Age 16+, no child accounts | by design |
| 23 | Item not found, left on the list | No effect, the trip ends by time | Same | generator: 5 % of items |
| 24 | Item not found, ticked away at the end anyway | Teaches a late place | Same, damped to half a step; the next trip corrects it. **Remains** | by design |
| 25 | Adds an item at the shelf and ticks it | Teaches its place | Same, which is right: it was picked there | generator: impulse adds |
| 26 | Adds and ticks gum at the checkout | Teaches "at the end" | Same, which is right for checkout shelves | by design |
| 27 | Ticks the store's last item, then adds and ticks one more | A second trip (T1a "all ticked") | One trip | test "T1a as approved" |
| 28 | Ticks across two lists in one shop | Per person, across lists | Same; a detected trip spanning lists gets `list_id` null | by design |
| 29 | One item at a small store, then the big one | Joins the big store's session; the item's store memory moves | Its own trip (T3a), nothing moves | test "one item at a small store" |
| 30 | The same store twice a day | Two trips | Two trips when over 30 min apart | test "the same store again in the evening" |
| 31 | Back at the same store 20 min later for something forgotten | Two trips | One trip, two walks | by design (F5) |
| 32 | Siri, Alexa, MCP or API ticks during a walk | Excluded (needs a source column) | Excluded; they do not break the walk's chain | test "Siri, Alexa and agent ticks" |
| 33 | Delivery unpacked at home, a tick every 4 to 20 s | A trip; teaches random order; store memory moves | A trip in history ("Einkauf bei Rewe"), teaches nothing. Arguably right for a delivery | test "a delivery unpacked"; sim delivery |
| 34 | Delivery unpacked slowly, 15 to 60 s per item | As 33 | Passes the pace rule. Once the store has 3 taught walks, the shuffle gate turns it away: no order, no store memory. **Remains**: the first 3 walks at a store are not gated | test "once a store is learned, a walk that shuffles"; sim slow-unpacker: order 84 % (78 % without the gate, prior 80 %), store memory keys wrong 0/12 |
| 35 | Two people split the list, one starts at the back | Two trips or one; the backwards walk teaches the reverse | One household trip, both walks teach; the positions-only learner limits the damage to that half. **Remains**: 16 % wrong walk pairs (TD-Q6) | test "two people splitting"; sim split-couple: order 73 % becomes 85 %; with the final learner on both sides 85 → 85, so the gain is the learner's |
| 36 | Two people at different stores at once | Separate trips | Same | by design |
| 37 | Neighbours from one shelf ticked together in list order | Teaches the list order between them | One step, tied | test "neighbours ticked together" |
| 38 | A pharmacy | Not covered by the rule | Never a trip, no order, no store memory (GL-2) | test "a pharmacy" |
| 39 | A manual trip is running | Not covered | Its ticks belong to the manual trip; detection skips that person while it runs | by design |
| 40 | Plans at the desktop and ticks rows away ("have that") | As 3 | As 3 | by design |
| 41 | Answers „Nein, nur abgehakt", then walks the store | The sheet asks again on every tick | Asked once; the walk is detected (TD-Q5) | UX below |
| 42 | Dismisses the trip question after every tick | Not modelled | Today a dismissal takes 3.5 s or more (the review drive's scripted tick and „Nein"), so a shelf batch can split into single steps; walks stay walks. With the proposed UX (asked once per shop) only the first tick of a shop pays it. The simulator models 3 s per tick for Lea, which keeps batches together | sim peter-lea (Lea dismisses) |

## Simulation

`sim/` is a seeded generator of households, the two detectors, two learners and an evaluator. In this folder, `deno run sim/evaluate.ts 5` prints the tables below (5 households per persona, 12 weeks each, about 4 s), and `deno test --allow-read` runs the cases. The lint gate runs the tests (`scripts/lint.sh`), and one of them fails when the tables here differ from the simulator's output.

**What a household is.** Four stores: Rewe and Aldi with aisles near the route order, IKEA with an unrelated one, and a pharmacy. Each store sells 160 of 360 keys in 12 categories, and the household buys from 45 of them. The prior (the order before any trip) is the route order of categories, as `walkingOrder` is today. About 2.5 visits a week. Each visit plans 5 to 18 items: 10 % without a store, 5 % tagged to another store. A walk takes 4 s plus the distance times 10 to 17 minutes for the whole store, plus 2 to 25 s at the shelf. Neighbours under 4 % of the store apart are ticked together half of the time. Each member has habits: walk, checkout or catch up at home; offline; clock skew; stray ticks; impulse adds; "we have that" ticks; voice ticks; seconds lost dismissing the trip question. The list a catch-up follows is the prior (the generator has no learned order to show). Store memory is never fed back into later adds. Personas turn one habit up each:

| Persona | Turned up |
| --- | --- |
| peter-lea | Peter walks (85 %), clock 40 s off; Lea walks 40 %, checkout 35 %, ticks "we have that" weekly, dismisses the trip question after every tick (3 s) |
| offline-wrong-clock | offline in 50 % of walks, clock an hour ahead, many stray ticks and impulse adds |
| checkout-ticker | 70 % and 50 % of visits ticked at the checkout |
| home-sweeper | two "we have that" bursts a week, one member mostly catches up at home |
| delivery | a delivery unpacked and ticked at home every week, 4 to 20 s per item |
| split-couple | 80 % of visits together, half of those with one partner starting at the back |
| slow-trips | 60 % of walks with a 6 to 14 min wait, many same-day returns and second stores |
| slow-unpacker | as delivery, but 15 to 60 s per item |
| slow-catchup | both members mostly catch up at home, 15 to 60 s per item |

**Scores.** A trip matches a visit when at least half its ticks are from that visit and its store is the visit's store. Precision is matched trips over all trips. Recall is visits matched over visits with an app tick (pharmacy visits excluded, GL-2). Phantom trips are mostly ticks from no visit. Split visits are matched by two or more trips. "Store memory writes wrong" counts writes from a tick of no visit or for another store than the visit's; a delivery's writes count as wrong even where the delivering store is arguably right. "Store memory keys wrong at the end" replays the writes and counts keys whose last store is not the store the household bought them at most. "Walk pairs wrong" is the share of key pairs the detector hands the learner in the opposite of the store's real order, before the shuffle gate. Order accuracy is the share of pairs of the household's bought keys that the learned order puts as the store does, after 12 weeks. "Prior only" is no learning. "Every visit taught" feeds every real visit in its true order: the ceiling for any detector. Both detectors skip pharmacies (GL-2), so the comparison is about the heuristics only.

<!-- sim:begin -->
| Household | Rule | Visits | Trips | Precision | Recall | Phantom | Split | Wrong store | Store memory writes wrong | Store memory keys wrong at the end | Walk pairs wrong | Order accuracy |
| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |
| peter-lea | starting rule + ema | 192 | 227 | 78 % | 86 % | 45 | 11 | 5 | 32/260 | 13/197 | 15 % | 80 % |
| peter-lea | starting rule + final learner | 192 | 227 | 78 % | 86 % | 45 | 11 | 5 | 32/260 | 13/197 | 15 % | 86 % |
| peter-lea | final rule + ema | 192 | 161 | 99 % | 82 % | 0 | 2 | 2 | 0/10 | 0/10 | 4 % | 87 % |
| peter-lea | final rule + final learner | 192 | 161 | 99 % | 82 % | 0 | 2 | 2 | 0/10 | 0/10 | 4 % | 87 % |
| peter-lea | prior only / every visit taught | | | | | | | | | | | 81 % / 92 % |
| offline-wrong-clock | starting rule + ema | 191 | 181 | 98 % | 90 % | 0 | 6 | 3 | 17/249 | 24/196 | 26 % | 75 % |
| offline-wrong-clock | starting rule + final learner | 191 | 181 | 98 % | 90 % | 0 | 6 | 3 | 17/249 | 24/196 | 26 % | 83 % |
| offline-wrong-clock | final rule + ema | 191 | 172 | 99 % | 89 % | 0 | 0 | 2 | 0/31 | 2/28 | 4 % | 89 % |
| offline-wrong-clock | final rule + final learner | 191 | 172 | 99 % | 89 % | 0 | 0 | 2 | 0/31 | 2/28 | 4 % | 89 % |
| offline-wrong-clock | prior only / every visit taught | | | | | | | | | | | 80 % / 92 % |
| checkout-ticker | starting rule + ema | 186 | 187 | 94 % | 89 % | 9 | 11 | 2 | 6/250 | 14/185 | 27 % | 74 % |
| checkout-ticker | starting rule + final learner | 186 | 187 | 94 % | 89 % | 9 | 11 | 2 | 6/250 | 14/185 | 27 % | 81 % |
| checkout-ticker | final rule + ema | 186 | 149 | 99 % | 78 % | 0 | 3 | 1 | 0/1 | 0/1 | 3 % | 83 % |
| checkout-ticker | final rule + final learner | 186 | 149 | 99 % | 78 % | 0 | 3 | 1 | 0/1 | 0/1 | 3 % | 84 % |
| checkout-ticker | prior only / every visit taught | | | | | | | | | | | 82 % / 92 % |
| home-sweeper | starting rule + ema | 181 | 310 | 57 % | 90 % | 129 | 16 | 3 | 67/289 | 38/220 | 21 % | 75 % |
| home-sweeper | starting rule + final learner | 181 | 310 | 57 % | 90 % | 129 | 16 | 3 | 67/289 | 38/220 | 21 % | 80 % |
| home-sweeper | final rule + ema | 181 | 167 | 95 % | 82 % | 8 | 11 | 0 | 0/4 | 0/4 | 1 % | 83 % |
| home-sweeper | final rule + final learner | 181 | 167 | 95 % | 82 % | 8 | 11 | 0 | 0/4 | 0/4 | 1 % | 83 % |
| home-sweeper | prior only / every visit taught | | | | | | | | | | | 80 % / 92 % |
| delivery | starting rule + ema | 105 | 179 | 60 % | 90 % | 64 | 13 | 7 | 115/222 | 44/183 | 32 % | 75 % |
| delivery | starting rule + final learner | 105 | 179 | 60 % | 90 % | 64 | 13 | 7 | 115/222 | 44/183 | 32 % | 80 % |
| delivery | final rule + ema | 105 | 163 | 61 % | 91 % | 60 | 4 | 3 | 0/3 | 0/3 | 2 % | 85 % |
| delivery | final rule + final learner | 105 | 163 | 61 % | 91 % | 60 | 4 | 3 | 0/3 | 0/3 | 2 % | 84 % |
| delivery | prior only / every visit taught | | | | | | | | | | | 78 % / 88 % |
| split-couple | starting rule + ema | 188 | 237 | 94 % | 88 % | 1 | 55 | 13 | 9/246 | 18/200 | 22 % | 73 % |
| split-couple | starting rule + final learner | 188 | 237 | 94 % | 88 % | 1 | 55 | 13 | 9/246 | 18/200 | 22 % | 85 % |
| split-couple | final rule + ema | 188 | 186 | 97 % | 88 % | 0 | 15 | 6 | 0/26 | 2/25 | 16 % | 73 % |
| split-couple | final rule + final learner | 188 | 186 | 97 % | 88 % | 0 | 15 | 6 | 0/26 | 2/25 | 16 % | 85 % |
| split-couple | prior only / every visit taught | | | | | | | | | | | 81 % / 91 % |
| slow-trips | starting rule + ema | 258 | 247 | 98 % | 77 % | 0 | 43 | 6 | 27/302 | 25/223 | 10 % | 84 % |
| slow-trips | starting rule + final learner | 258 | 247 | 98 % | 77 % | 0 | 43 | 6 | 27/302 | 25/223 | 10 % | 88 % |
| slow-trips | final rule + ema | 258 | 209 | 99 % | 80 % | 0 | 0 | 2 | 0/38 | 2/32 | 2 % | 88 % |
| slow-trips | final rule + final learner | 258 | 209 | 99 % | 80 % | 0 | 0 | 2 | 0/38 | 2/32 | 2 % | 90 % |
| slow-trips | prior only / every visit taught | | | | | | | | | | | 81 % / 92 % |
| slow-unpacker | starting rule + ema | 109 | 168 | 58 % | 84 % | 66 | 6 | 4 | 142/283 | 51/219 | 34 % | 74 % |
| slow-unpacker | starting rule + final learner | 109 | 168 | 58 % | 84 % | 66 | 6 | 4 | 142/283 | 51/219 | 34 % | 83 % |
| slow-unpacker | final rule + ema | 109 | 160 | 59 % | 87 % | 60 | 0 | 5 | 2/12 | 0/12 | 32 % | 75 % |
| slow-unpacker | final rule + final learner | 109 | 160 | 59 % | 87 % | 60 | 0 | 5 | 2/12 | 0/12 | 32 % | 84 % |
| slow-unpacker | prior only / every visit taught | | | | | | | | | | | 80 % / 90 % |
| slow-catchup | starting rule + ema | 178 | 181 | 95 % | 90 % | 5 | 11 | 4 | 19/233 | 26/183 | 17 % | 81 % |
| slow-catchup | starting rule + final learner | 178 | 181 | 95 % | 90 % | 5 | 11 | 4 | 19/233 | 26/183 | 17 % | 84 % |
| slow-catchup | final rule + ema | 178 | 166 | 99 % | 87 % | 0 | 9 | 2 | 1/28 | 1/26 | 15 % | 83 % |
| slow-catchup | final rule + final learner | 178 | 166 | 99 % | 87 % | 0 | 9 | 2 | 1/28 | 1/26 | 15 % | 85 % |
| slow-catchup | prior only / every visit taught | | | | | | | | | | | 83 % / 92 % |

| Variant of the final rule | Precision | Recall | Phantom | Split | Store memory writes wrong | Store memory keys wrong at the end | Walk pairs wrong | Order accuracy | Most affected household: final → variant |
| --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |
| final | 90 % | 84 % | 128 | 44 | 3/153 | 7/141 | 11 % | 86 % |  |
| H1 as approved: no pace rule, no clumps | 82 % | 88 % | 303 | 53 | 12/333 | 19/291 | 20 % | 84 % | checkout-ticker: order 84 % → 81 %, recall 78 % → 90 %, memory keys wrong 0 % → 9 %, pairs wrong 3 % → 27 % |
| T1a as approved: all ticked ends the trip, no pause | 88 % | 84 % | 139 | 110 | 3/149 | 7/137 | 11 % | 86 % | slow-trips: order 90 % → 90 %, recall 80 % → 80 %, memory keys wrong 6 % → 7 %, pairs wrong 2 % → 2 % |
| T1a all-ticked end kept (pause stays) | 88 % | 84 % | 137 | 44 | 3/149 | 7/137 | 11 % | 86 % | slow-trips: order 90 % → 90 %, recall 80 % → 80 %, memory keys wrong 6 % → 7 %, pairs wrong 2 % → 2 % |
| T3a as approved: no travel time | 87 % | 84 % | 141 | 43 | 3/137 | 6/127 | 11 % | 86 % | slow-trips: order 90 % → 90 %, recall 80 % → 80 %, memory keys wrong 6 % → 4 %, pairs wrong 2 % → 2 % |
| T4a as approved: immediate, shuffles not gated | 90 % | 84 % | 128 | 44 | 168/1468 | 128/1226 | 11 % | 86 % | slow-unpacker: order 84 % → 84 %, recall 87 % → 87 %, memory keys wrong 0 % → 21 %, pairs wrong 32 % → 32 % |
| T4a immediate (shuffles gated) | 90 % | 84 % | 128 | 44 | 90/1305 | 106/1124 | 11 % | 86 % | slow-unpacker: order 84 % → 84 %, recall 87 % → 87 %, memory keys wrong 0 % → 18 %, pairs wrong 32 % → 32 % |
| T4a narrowed too: 75 % one store, not the edge ticks | 90 % | 84 % | 128 | 44 | 2/113 | 6/105 | 11 % | 86 % | slow-trips: order 90 % → 90 %, recall 80 % → 80 %, memory keys wrong 6 % → 12 %, pairs wrong 2 % → 2 % |
| commit times (no tap time) | 90 % | 84 % | 128 | 45 | 3/131 | 7/123 | 12 % | 85 % | offline-wrong-clock: order 89 % → 86 %, recall 89 % → 87 %, memory keys wrong 7 % → 15 %, pairs wrong 4 % → 3 % |
| client_at clamped to 5 min ahead (first proposal) | 90 % | 84 % | 128 | 44 | 3/135 | 7/126 | 12 % | 85 % | offline-wrong-clock: order 89 % → 86 %, recall 89 % → 87 %, memory keys wrong 7 % → 15 %, pairs wrong 4 % → 3 % |
| store memory not gated by shuffles | 90 % | 84 % | 128 | 44 | 21/186 | 14/167 | 11 % | 86 % | slow-unpacker: order 84 % → 84 %, recall 87 % → 87 %, memory keys wrong 0 % → 23 %, pairs wrong 32 % → 32 % |
| no outlier gate | 90 % | 84 % | 128 | 44 | 3/153 | 7/141 | 11 % | 85 % | slow-unpacker: order 84 % → 78 %, recall 87 % → 87 %, memory keys wrong 0 % → 0 %, pairs wrong 32 % → 32 % |
| no pace rule | 90 % | 84 % | 128 | 44 | 4/163 | 7/149 | 15 % | 85 % | delivery: order 84 % → 81 %, recall 91 % → 91 %, memory keys wrong 0 % → 0 %, pairs wrong 2 % → 33 % |
| no pace rule, no outlier gate | 90 % | 84 % | 128 | 44 | 4/163 | 7/149 | 15 % | 84 % | delivery: order 84 % → 76 %, recall 91 % → 91 %, memory keys wrong 0 % → 0 %, pairs wrong 2 % → 33 % |
| outlier gate 0.5 | 90 % | 84 % | 128 | 44 | 3/153 | 7/141 | 11 % | 86 % | slow-unpacker: order 84 % → 82 %, recall 87 % → 87 %, memory keys wrong 0 % → 0 %, pairs wrong 32 % → 32 % |
| outlier gate 0.7 | 90 % | 84 % | 128 | 44 | 3/153 | 7/141 | 11 % | 86 % | slow-unpacker: order 84 % → 84 %, recall 87 % → 87 %, memory keys wrong 0 % → 0 %, pairs wrong 32 % → 32 % |
| no clumps (each tick its own) | 90 % | 85 % | 128 | 48 | 3/151 | 7/138 | 13 % | 85 % | peter-lea: order 87 % → 87 %, recall 82 % → 84 %, memory keys wrong 0 % → 0 %, pairs wrong 4 % → 5 % |
| pace 40 s | 90 % | 84 % | 128 | 47 | 3/125 | 5/116 | 7 % | 86 % | slow-unpacker: order 84 % → 86 %, recall 87 % → 87 %, memory keys wrong 0 % → 0 %, pairs wrong 32 % → 22 % |
| clump 3 s | 90 % | 84 % | 128 | 45 | 3/152 | 7/141 | 12 % | 86 % | peter-lea: order 87 % → 87 %, recall 82 % → 82 %, memory keys wrong 0 % → 0 %, pairs wrong 4 % → 4 % |
| clump 10 s | 90 % | 84 % | 128 | 44 | 3/153 | 7/141 | 11 % | 86 % | delivery: order 84 % → 84 %, recall 91 % → 90 %, memory keys wrong 0 % → 0 %, pairs wrong 2 % → 2 % |
| gap 5 min | 90 % | 82 % | 128 | 59 | 1/126 | 6/118 | 12 % | 85 % | slow-trips: order 90 % → 89 %, recall 80 % → 75 %, memory keys wrong 6 % → 4 %, pairs wrong 2 % → 2 % |
| gap 15 min | 90 % | 85 % | 128 | 36 | 4/167 | 7/152 | 11 % | 86 % | slow-trips: order 90 % → 91 %, recall 80 % → 82 %, memory keys wrong 6 % → 5 %, pairs wrong 2 % → 3 % |
| no pause merge | 90 % | 84 % | 128 | 104 | 3/153 | 7/141 | 11 % | 86 % | none |
| bursts never trips | 92 % | 63 % | 69 | 9 | 3/153 | 7/141 | 11 % | 86 % | checkout-ticker: order 84 % → 84 %, recall 78 % → 22 %, memory keys wrong 0 % → 0 %, pairs wrong 3 % → 3 % |
| bursts from 3 ticks | 82 % | 88 % | 303 | 63 | 3/153 | 7/141 | 11 % | 86 % | checkout-ticker: order 84 % → 84 %, recall 78 % → 90 %, memory keys wrong 0 % → 0 %, pairs wrong 3 % → 3 % |
<!-- sim:end -->

**Reading it.**

- The starting rule's damage comes from what it teaches, more than from how many trips it finds. Its recall (77 to 90 %) is higher in five households, but it hands the learner 10 to 34 % wrong pairs. With job 347's learner, its order ends below the prior in 8 of 9 households.
- The final rule hands over 1 to 4 % wrong pairs in six households; 15 % (slow catch-up), 16 % (split couple) and 32 % (slow unpacking) in the other three. Order accuracy ends 2 to 9 points above the prior and 2 to 9 below the ceiling in every household.
- Detection and learning each carry part of the gain. With the final learner on both sides, the final rule adds 0 to 6 points. With the final rule on both sides, the final learner adds −1 to 12 points, most where walks are partial (split-couple) or shuffled (slow-unpacker).
- Remaining phantom trips are deliveries (120 of 128).
- These numbers measure the rule against the generator's assumptions, and the thresholds are tuned against them. The pace of a real walk, how often people batch ticks, how fast they unpack a delivery and how well real walks agree with each other are guesses until real data is measured (TD-Q8).

## Real data

Skipped. No read-only path to production tick history exists. The ops env has the database password, which is full access, and `scripts/feedback-monday.sh` reads the local stack only. Using full access would mean opening a new path to users' data, which the brief rules out. The anonymous aggregates that would calibrate the rule are listed in TD-Q8.

## What users see

**The principle.** The benefit users notice is the order improving by itself. The detected trip is its receipt. So detection stays quiet while it happens and is easy to correct afterwards. And the app should interrupt less than it does today, not more.

**The trip question.** Today the sheet „Kaufst du gerade ein?" opens after every own tick while no trip runs, and „Nein, nur abgehakt" is forgotten at once (`tm-ask`). Lea and the beta user, who never start a trip, dismiss it on every tick. With detection on:

- It asks on the first tick of a shop, as today.
- After „Nein, nur abgehakt" (or a dismissal) it stays quiet until 30 minutes pass without an own tick (the same pause that keeps a detected trip together).
- After „Nein" three shops in a row, it stops asking. The first-trip card and Settings say how to bring it back.
- „Ja, Einkauf starten" still starts a manual trip; the button in the list stays.

The sheet gets one line under its buttons, outside them:

| | German | English |
| --- | --- | --- |
| Under „Nein, nur abgehakt" | Wir fragen erst beim nächsten Einkauf wieder. | We'll ask again on your next shop. |
| Settings switch | Beim Abhaken fragen, ob ich einkaufe | Ask if I'm shopping when I tick |
| After three „Nein" (one snackbar, once) | Wir fragen nicht mehr. Einkäufe erkennt Snacklist trotzdem. Einstellungen › Beim Abhaken fragen | We'll stop asking. Snacklist still notices your trips. Settings › Ask if I'm shopping |

**During shopping.** Nothing else. No live "Looks like you're at Rewe" hint (TD-Q4): detection needs three steps (several minutes), a wrong guess at home ("at Rewe?" while unpacking) reads as tracking, and the person has just answered the trip question.

**After the first detected trip.** One card on the list, once per person:

| | German | English |
| --- | --- | --- |
| Title | Einkauf bei {store} erkannt | Shopping at {store} detected |
| Body | Snacklist merkt sich, in welcher Reihenfolge du abhakst, und sortiert die Liste beim nächsten Mal so. Den Einkauf findest du im Verlauf. | Snacklist remembers the order you tick in and sorts the list that way next time. You'll find the trip in History. |
| Actions | Ansehen · Verstanden | View · Got it |

**In Verlauf.** A detected trip looks like any other trip, with one line of secondary text under the store's name. It is not a pill or badge, so there is no hint copy inside a control.

| | German | English |
| --- | --- | --- |
| Your own trip | Aus deinen Häkchen erkannt | Detected from your ticks |
| Another member's trip | Aus {name}s Häkchen erkannt | Detected from {name}'s ticks |
| Two people, you among them | Aus deinen und {name}s Häkchen erkannt | Detected from your and {name}'s ticks |
| Two other people | Aus {name1}s und {name2}s Häkchen erkannt | Detected from {name1}'s and {name2}'s ticks |
| A burst without a walk (no duration) | Abgehakt, ohne Dauer | Ticked, no duration |

A detected trip shows day, store, duration and items. It shows no clock times on another member's trip. That is a display choice; the times themselves are readable by members today (Legal notes).

**Without Premium (PB3a).** A detected trip's page shows what a Free member sees of any trip: the head (day, store, duration, "5 Artikel abgehakt") and the Premium card, no rows. Change store, merge and „Kein Einkauf" work without Premium, because they correct what the household's order learns. "New trip from here" needs the rows, so it is Premium only, unless Peter wants corrections to stay free (TD-Q15).

**Fixing a wrong one.** On a detected trip's page, any member can (GL-3):

| Action | German | English | What happens |
| --- | --- | --- | --- |
| Change the store | Laden ändern | Change store | The trip moves to the store; its order lesson moves to that store's order; store memory relearns |
| Split | Ab hier neuer Einkauf (on a line) | New trip from here | Two trips, each teaches its own part |
| Merge | Mit dem Einkauf davor zusammenführen | Merge with the trip before | One trip; shown only for the same day and within 3 hours |
| Remove | Kein Einkauf | Not a shopping trip | Confirm: „Kein Einkauf? Die Häkchen bleiben, aber die Reihenfolge lernt nicht mehr daraus." / "Not a shopping trip? The ticks stay, but the order no longer learns from it." Then a snackbar with undo: „Entfernt" / "Removed" |

An edited or removed trip is frozen: detection never rewrites or re-detects it ("For job 352").

**Opting out.** One switch per person under More › Settings, on for everybody by default:

| | German | English |
| --- | --- | --- |
| Switch | Einkäufe aus meinen Häkchen erkennen | Detect trips from my ticks |
| Below it | Nutzt nur, wann du abhakst. Kein Standort. | Uses only when you tick. No location. |

**If Peter wants a live hint anyway** (TD-Q4), it replaces the trip question for people who said „Nein" three times, as a line above the list, never a dialog. German: „Sieht nach Einkauf bei {store} aus. Die Reihenfolge lernt mit." English: "Looks like you're shopping at {store}. The order learns as you go." It shows after the third step of a walk and goes away by itself. A tap opens the trip question.

## For job 352

**Columns.** `item_events` gains `client_at timestamptz` (the tap time, from `SetStatus.at`, stored as sent when it lies within 7 days before to 24 hours after the commit, else null; the per-person offset absorbs any skew inside those bounds, ahead or behind. This report first proposed "5 minutes after `now()`", which nulls every tick of a phone running ahead: see TD-Q13), `source text` (`app`, `voice`, `agent`; edge functions set it through a transaction-local setting the trigger reads) and `store_id uuid` (the item's store at the event, as job 347 plans). All three are nullable, so old app builds keep working. Their ticks fall back to commit times, so an offline walk becomes a burst and teaches nothing: a safe failure. The app sends `ticked_at` with the status update; `items.bought_at` stays the server's time.

**Detected trips.** They go into `trip_sessions` with `source = 'detected'` and `end_reason = 'auto'`, plus `trips` rows as trip mode writes them. Three new nullable columns:

- `tick_ids bigint[]`: the `item_events` ids the trip was built from.
- `detected_by uuid[]`: everyone whose ticks are in it (T2a). `started_by` is the first of them. Leaving the household, removal and account deletion remove the person from the array, as they null `started_by` today. The Verlauf line uses the array (copy above).
- `frozen_at timestamptz` and `removed_at timestamptz`: set by a member's edit or „Kein Einkauf". `source` stays `detected`, so the "Aus … Häkchen erkannt" line and the detected-trip actions keep working after an edit.

**Reconciliation, each run.** `detect_trips(household)` runs in one transaction, under the household's advisory lock:

1. Window: the 36 hours before the newest app tick, widened back to the start of every unfrozen detected trip that overlaps it, so no trip is cut at the window's edge. Ticks in `tick_ids` of a frozen or removed trip are taken out of the input, so a removed trip is never detected again and an edited one keeps its ticks.
2. Detect trips from the rest.
3. Delete the household's detected trips that are neither frozen nor removed and lie in the window (after step 1, every one that overlaps it does), with their `trips` rows. Insert the new ones with fresh ids. A late offline tick, a T2a merge or an untick therefore replaces a trip instead of leaving a stale duplicate; ids are not stable and nothing outside the function refers to an unfrozen detected trip.
4. Hand the new walks to IO4's learner, or replay a store when a taught walk changed (next section).
5. Set `detected_through`.

A removed trip keeps its row (with `removed_at`) only as a tombstone, without lines: its `lines` are emptied and its `trips` rows deleted. Verlauf and exports skip it.

**Feeding IO4's learner.** Job 347's IO4 keeps the learned order in `item_order_memory` (`source learned | manual`, a `trips` count, a migration seed with `trips = 0`, manual places from „Neben…", `place_item` and `set_store_order`, and "a manual position moves only after three contradicting trips"), and plans its own learning trigger: "when a trip ends (or after 20 minutes without a tick)", reading a trip's `bought` events (`jobs/347-item-order-prototypes/out/APPROACHES.md`, "Data, migration and sync"). Detection fits into that design like this:

- **One entry point.** `detect_trips` replaces IO4's trigger; it is the only code that hands walks to the learner. There is no second learner at a trip's end.
- **Manual trips go through it too.** `trip_sessions` has no tick sequence, so a manual trip's walks come from the same `item_events`: the starter's app ticks between `started_at` and `ended_at`, outside its pauses, through the same step, pace and shuffle tests. The manual trip only fixes the trip's boundary and its Verlauf row; its checkout ticks teach nothing, as anywhere else.
- **Taught walks are stored.** `trip_sessions.walks jsonb` holds each taught walk of a trip (store, time, steps of canonical keys, and each key's store tag for store memory). A replay needs them, because `item_events` change under late ticks and the gate's verdict depends on the order at the time.
- **The normal case is incremental.** A new walk is applied once to `item_order_memory` with IO4's rules: learned rows move, and each walk that contradicts a manual place counts toward its three-trip override.
- **A replay starts from the seed and the manual places.** When a taught walk is removed, changes store, or is reshaped by a rerun, the touched store is rebuilt. The rebuild starts from the seed. IO4 keeps the seed in a `seed_position` column, written by its migration, so it survives learning. Then, in time order, it applies every walk of the store's non-removed trips and every current manual place at its `updated_at`. It counts the three-trip override along the way, as live learning would have. Learned rows are rewritten. A manual row stays manual unless the replayed override lifts it. So no manual place and no seed is lost. Store memory is rebuilt from the stored proposals the same way.
- **The running trip holds the order** (IO4's sync rule). Detection runs only after 10 minutes without a tick, so nothing reorders under a shopper's thumb.
- **The learner changes.** This report's learner (F8: the walk's keys trade places among the positions they hold, halfway) replaces IO4's "moves each key's position toward its rank in the trip", and the shuffle gate (F9) is new. Evidence: same detector, IO4's learner vs F8, split-couple 73 → 85 %, slow-unpacker 75 → 84 %, the others within 2 points. That is TD-Q16 for job 352 and 347's design.

**Tests.** The simulator here is the reference for the rule. Port the cases in `sim/detect_test.ts` to pgTAP cases of the SQL function, plus: a rerun after a late earlier tick leaves one trip; a removed trip stays removed after a rerun; an edited trip keeps its ticks.

## Legal notes

- **New derived data.** Inferred store visits: who shopped, where, on which day, for how long, and in what order they ticked. Until now a trip was recorded only when someone started it. A detected trip is recorded without that act. It needs a row in `docs/PRIVACY_DATA_MAP.md` and a sentence in the privacy notice: Snacklist recognizes shopping trips from the times items are ticked, without location.
- **Inside the household, today already.** Every member can read every member's `item_events` rows through the API (`item_events_select`, `foundation.sql:419`). That covers who ticked what, with the server time to the microsecond. The review proved it on the local stack. So "other members see the day, not clock times" holds on screen only, and the new `client_at` would be readable the same way.
- **Who reads `item_events` as a member.** No app code reads the table directly. But `public.suggest_items` (the add sheet's usuals, called at `list_repository.dart:540`) is `security invoker` and reads it as the member. Review 1 ran a plain revoke and got "permission denied for table item_events" from `suggest_items`. A scan of every function's latest definition in `supabase/migrations` (functions without a `security` clause count as invokers) finds one other invoker reader: `merge_duplicate_categories`. Its execute right is revoked from every role, and it ran once in its migration. No view reads the table. The test tools (`fg sync` at `cli/sync.ts:248`, the scenario fixtures, e2e's admin client) read and patch it with the service role (`cli/target.ts:133`: no token means the service role), so a revoke from `authenticated` leaves them working.
- **Proposal for job 352, in one migration.**
  1. `suggest_items` becomes `security definer` and starts with an explicit `is_household_member(p_household)` check that raises `not_a_member`. Today its `items` read relies on RLS, which a definer function bypasses, so the check must guard the whole function, not only the events part.
  2. `revoke select on public.item_events from authenticated`.
  3. pgTAP cases: a member still gets usuals, an outsider gets `not_a_member`, and a member's `select` on `item_events` is refused.

  A column-level revoke (`created_at`, `actor`, `client_at`) is not enough on its own, because `suggest_items` reads `created_at` as the member. After the change, members still see `last_used` per name from `suggest_items`: the household's latest purchase time of an item, without who bought it. Until the migration ships, Legal should treat tick times as visible to all members.
- **Mitigations proposed.** Other members see the day and the store of a detected trip, not clock times (and, with the revoke above, cannot read them elsewhere either); a per-person switch turns detection off for one's own ticks; any member can remove a trip (GL-3). Legal should confirm that this is enough (TD-Q3).
- **No location.** Detection uses tick times and the store the user tagged. No GPS, no Wi-Fi, no geofence. The copy says so.
- **Pharmacies (GL-2).** No detected trip, no order learning and no store memory at a pharmacy. Tick events at a pharmacy are already stored today; nothing new derives from them.
- **Tap time.** `client_at` is the device's time at the tap. It carries no more than `created_at` already does, except for offline ticks. It follows `item_events`' retention and deletion.
- **Export and deletion.** Detected trips join the user's export as trips they were part of. Leaving the household, removal and account deletion remove the person from `detected_by` and null `started_by`, as for `trip_sessions` today (Legal N-115). A removed trip is a tombstone without items.
- **Retention.** As trips: until the trip or the household is deleted.

## Open questions

- **TD-Q1 (Peter).** H2: a burst of fast ticks is a trip in history only from 5 ticks, and never teaches order. Recommendation: accept. Alternative: no bursts as trips at all (fewest phantoms, but recall falls to 63 %, and a household that ticks at the checkout gets almost no history).
- **TD-Q2 (Peter).** T1a: the same person at the same store again within 30 minutes continues the trip. Recommendation: accept.
- **TD-Q3 (Legal).** Are a per-person opt-out, no clock times on others' detected trips, and revoking members' direct read of `item_events` (with `suggest_items` made `security definer`) enough for inferred visits inside a household? Is a privacy notice sentence enough, or does detection need an explicit yes first?
- **TD-Q4 (Peter).** No live "Looks like you're at Rewe" hint; the trip question asks once per shop instead of on every tick. Recommendation: accept. Alternative: the live line above replaces the question for people who said „Nein" three times.
- **TD-Q5 (Peter).** After „Nein, nur abgehakt", that shop is still detected: the order learns and Verlauf shows the trip with "Aus deinen Häkchen erkannt". Recommendation: accept, since „Nein" today means "no stopwatch", not "this was not a shop". Alternative: no Verlauf trip for that shop, order still learns.
- **TD-Q6 (job 352).** A partner who walks the store from the back hands the learner reverse pairs (16 % wrong in split-couple). Per-person direction would fix it, at the cost of a second order. Measure on real trips first.
- **TD-Q7 (job 352).** A device id on each event would let the clock offset be per device rather than per person. It matters only for people with two devices and different clocks.
- **TD-Q8 (lead).** Calibration needs a read-only path that returns only aggregates: the distribution of gaps between one person's consecutive app ticks (bucketed), burst sizes, the share of ticks with a commit time more than 10 s after the tap (once `client_at` exists), and how well a household's walks at one store agree with each other (for the 60 % shuffle gate). Should one be built, for example a `security definer` function that returns histograms only? Until then the pace rule (20 s) and the gate (60 % after 3 walks) are synthetic guesses, and slow unpacking or slow catch-ups can teach the first walks at a store.
- **TD-Q9 (job 352).** Delivery unpacking shows up as a trip with no duration. Should a household be able to mark a store as a delivery service, so its bursts and walks never show as trips or teach?
- **TD-Q10 (Peter).** H1: a walk needs 3 steps (ticks under 6 s apart count as one) and a median of at least 20 s between them, and ticks up to 10 minutes apart stay one run (T1a's quiet time). Approved: 3 ticks under 5 min apart. Recommendation: accept (numbers in "Changes").
- **TD-Q11 (Peter).** T1a: ticking the store's last item no longer ends the trip; only 10 minutes of quiet do. Recommendation: accept; the difference is small (precision 88 → 90 %).
- **TD-Q12 (Peter).** T3a: a change of store needs 2 minutes without a tick. Recommendation: accept.
- **TD-Q13 (Peter).** Times come from the phone's tap, corrected by its usual offset, instead of the server's commit. Recommendation: accept; it needs the app to send the tap time.
- **TD-Q14 (Peter).** T4a: an item moves to another store in store memory only after the second walk that bought it there, and never from a shuffle. Approved: at once. Recommendation: accept; the cost is one more walk before an item moves.
- **TD-Q15 (Peter).** Without Premium a detected trip shows no rows, so "New trip from here" cannot work. Should corrections of a detected trip show its rows to Free members (an exception to PB3a), or stay Premium?
- **TD-Q16 (job 352, 347's design).** The learner: F8 (the walk's keys trade places among the positions they hold, halfway) plus the shuffle gate, instead of IO4's move toward the rank in the trip. Recommendation: accept. It changes only how a walk updates `item_order_memory`; the table, manual places, the three-trip override and the seed stay as IO4 designs them.
