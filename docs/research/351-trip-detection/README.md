# Detecting shopping trips from plain ticks (job 351)

A beta user and Lea never start a trip. They only tick. Learned order (IO4, job 347, draft PR #604) can only learn from
a walk through a store. So the app has to notice a walk in plain ticks. This page red-teams Peter's approved starting
rule against chaotic shopping. It proposes the smallest fixes and the rule that results, and it measures both rules on
synthetic households. It also covers what users see and how they fix a wrong trip. Job 352 builds on it. Nothing here
ships.

Synthetic data only. No real tick history was read (see "Real data").

## In short

- The starting rule holds for clean walks. It breaks on the four habits that matter most for Lea and the beta user:
  ticking at the checkout, catching up at home, "we still have that" ticks at home, and a phone that was offline in the
  store. In the simulation it teaches the wrong order for 10 to 32 % of the item pairs it learns from. It also writes
  the wrong store into `item_store_memory`: 273 of its 1,818 writes, up to half of them in a household that unpacks
  deliveries.
- Eight small changes fix most of it. The one that carries the most weight is a **pace
  rule**: a walk has a median of at least 20 s between steps, because people walk between shelves. **The phone's own
  tap time** in place of the server's commit time rescues walks made offline. With them, wrong pairs drop to 1 to 4 % (16 % for a couple who walk the store from opposite
  ends). Wrong store memory writes drop to none. Order accuracy rises in every simulated household, by 6 to 14 points
  over the starting rule with job 347's learner.
- Bursts of fast ticks still count as trips in history from 5 ticks on, but they never teach order. Bursts of 3 or 4
  ticks are no trip. This trades 4 points of recall for 3.5 times fewer phantom trips. It is a change to H2, proposed
  below as TD-Q1.
- A pause of up to 30 minutes at the same store keeps one trip (T1a says a new trip). This cuts visits split in two from
  90 to 35. It is proposed as TD-Q2.
- Users see a detected trip in Verlauf with a quiet "Aus deinen Häkchen erkannt" line. Any member can change its store,
  split it, merge it or remove it. There is no live "Looks like you're at Rewe" hint (TD-Q4).

## What the server knows today

Checked in `supabase/migrations/` on main at a1edd966.

| Fact                                                                                                             | Where                                                                                    | What it means for detection                                                                          |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Every tick and untick writes an `item_events` row: `action` bought or restored, `actor`, `list_id`, `created_at` | `20261022150000_foundation.sql:204`, `20261108144409_households_lists.sql:368`           | The tick history exists. There is no store, no source and no device time.                            |
| `created_at` and `items.bought_at` are the server's `now()` at commit                                            | `items_before_write` (`20261121120100_items_created_at_bounds.sql`)                      | An offline walk arrives as one burst at the exit, and its times say nothing about the walk.          |
| The app has the tap time (`SetStatus.at`, `app/lib/list/model.dart:1167`) but does not send it                   | `_sendOne` in `app/lib/list/list_repository.dart:650` sends only `status` and `store_id` | Job 352 must send it.                                                                                |
| `item_events` has no source                                                                                      | `items_log_event`                                                                        | Siri, Alexa, MCP and API ticks look like app ticks. T5a needs a column.                              |
| `item_events` has no store                                                                                       | same                                                                                     | The store at the tick time is gone once an item moves. Job 347 already plans `item_events.store_id`. |
| `trip_sessions.source` is `ask` or `manual`                                                                      | `20261114181718_trip_mode.sql:13`                                                        | A detected trip fits this table with a new source `detected`.                                        |
| A trip at a pharmacy is never saved (GL-2)                                                                       | `20261114213100_trip_mode_skips_pharmacies.sql`                                          | Detection must skip pharmacies too.                                                                  |

## Final rule

The rule runs on the server, over each household's app ticks of the last 36 hours, after each new tick has been quiet
for 10 minutes. It is a pure function of the events. A rerun over the same events gives the same trips, so late offline
ticks simply reshape the result (idempotent). A trip a member has edited is frozen and never re-detected.

```text
input: item_events of the household, action bought or restored,
       with store_id, source and client_at (all proposed for job 352)

1  ticks   := events where source = 'app'                                   -- T5a
   time(e) := e.client_at + offset(e.actor)                                 -- fix F1
              offset = 10th percentile of (created_at - client_at) over the actor's ticks
              of the last 7 days; created_at when client_at is null (old app builds)
   drop every bought tick the same person restored within 10 minutes,
   and the restored tick                                                    -- T5a

2  per person, in time order:
   run      := ticks no more than 10 minutes apart                          -- T1a
   pieces   := split each run where the item's store changes,               -- fix F4
               but only where at least 2 minutes passed (getting there takes time).
               A short stretch of another store between two stretches of one store
               belongs to the surrounding store. A single tick at the start or end
               joins its neighbour unless it is the last open item of its store (T3a).
   clumps   := ticks of a piece less than 6 s apart                         -- fix F2
   walk     := piece with at least 3 clumps                                 -- H1, in clumps
               and a median gap between clumps of at least 20 s             -- fix F3
               or a piece of 1 or 2 ticks that ticks the last open items of
               its store within 5 minutes                                   -- T3a
   burst    := any other piece

3  trip    := a walk; the person's next walk at the same store within 30 minutes
               joins it (a pause)                                           -- fix F5
   a burst within 30 minutes after a walk of the same person (same store, or no store)
               joins that trip                                              -- fix F6
   a burst of 5 or more ticks that joins no trip is a trip of its own       -- fix F6, H2
   anything else is a plain tick, as today
   store(trip) := the store most of its tagged ticks have                   -- T4a
   trips of different people at the same store, overlapping
               (plus 10 minutes), are one household trip                    -- T2a
   no trip at a pharmacy                                                    -- GL-2

4  teach order: each walk at a known store, as its clumps in time order
               (keys of one clump are tied); bursts never teach             -- fix F7
   learner: the walk's keys trade places to match the walk, halfway          -- fix F8
               (job 347's moving average, with positions instead of ranks)

5  teach store memory: only from a walk with at least 3 tagged ticks, 75 % of them
               for one store; a storeless tick, or a tick of another store that is
               not the first or last of the walk, learns that store          -- T4a, narrowed
```

### Changes to the approved rule

| Rule | Starting rule                                                                                               | Final rule                                                                                                     | Why (simulation, all households pooled)                                                                                                                                           |
| ---- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H1   | 3 ticks, gaps under 5 min                                                                                   | 3 clumps, median step at least 20 s                                                                            | Without the pace rule, delivery unpacking teaches: order accuracy in that household drops from 85 to 76 %, and 107 store memory writes are wrong.                                 |
| H2   | every detected session is a trip                                                                            | a walk is a trip; a burst is a trip only from 5 ticks, and never teaches                                       | Bursts never trips: recall 60 %. From 3 ticks: 235 phantom trips instead of 68. 5 is the knee. Proposed as TD-Q1.                                                                 |
| T1a  | 10 min quiet ends the trip; also ends when the store's items are all ticked; same store later is a new trip | 10 min quiet ends a walk; a walk at the same store within 30 min continues the trip; "all ticked" ends nothing | Without the pause, 90 visits are split, 35 with it. 5 min quiet: recall 81 %, 49 splits. 15 min: 5 wrong store memory writes from merged stores. 10 min stays. Proposed as TD-Q2. |
| T2a  | as written                                                                                                  | as written; bursts merge too                                                                                   | Kept.                                                                                                                                                                             |
| T3a  | as written                                                                                                  | as written, plus 2 min travel time before a store switch                                                       | The single tick that completes another store made wrong-store trips; with travel time, precision rises from 90 to 93 %.                                                           |
| T4a  | minority and storeless items learn the majority store                                                       | only inside a walk that is 75 % one store, and not at its first or last tick                                   | Starting rule: 273 of 1,818 store memory writes are wrong. Final: 0 of 822.                                                                                                       |
| T5a  | as written                                                                                                  | as written; needs `item_events.source`                                                                         | Kept.                                                                                                                                                                             |
| new  | server commit time                                                                                          | the phone's tap time, corrected by its usual offset                                                            | Offline household: order accuracy 89 % instead of 86 %, recall 89 instead of 87 %.                                                                                                |
| new  | each tick its own step                                                                                      | ticks under 6 s apart are one step                                                                             | Wrong pairs 4 % instead of 6 %; order accuracy unchanged. Cheap insurance for shelf batches, which the generator only roughly models.                                             |

**Rejected after measuring.** Pairwise votes with the prior as one vote: never beat the prior, because 160 unseen items
dilute every learned pair. Teaching a walk that runs backwards through a known store as its reverse: no gain. A catch-up
burst joining another member's trip: 35 splits became 33. Session scores in place of hard thresholds: the thresholds sit
on plateaus (clumps of 3 to 10 s, gaps of 10 to 15 min give the same result), so a score would add opacity without a
measured gain.

## Red team

"Start" is the starting rule, "Final" the final rule. A test name in the last column is in `sim/detect_test.ts`. "Sim"
points to a household in the simulation table.

| #  | Case                                                                    | Start                                                                         | Final                                                                                                                                           | Evidence                                                                       |
| -- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1  | Ticks everything at home after shopping, 2 s apart                      | A trip, and it teaches the screen order back to itself                        | A trip in history, teaches nothing (F3, F6)                                                                                                     | test "ticking everything at home afterwards"                                   |
| 2  | Ticks 3 or 4 items at home: "we still have that"                        | A phantom trip that teaches order and moves store memory                      | No trip (F6)                                                                                                                                    | test "three or four quick ticks"; sim home-sweeper: 129 phantom trips become 8 |
| 3  | Ticks at the checkout, in conveyor order                                | Teaches the conveyor order                                                    | A trip from 5 ticks, teaches nothing                                                                                                            | sim checkout-ticker: wrong pairs 27 % become 3 %                               |
| 4  | Ticks the forgotten rows in the car                                     | A second trip, or part of the walk if under 10 min                            | Joins the walk's trip, teaches nothing                                                                                                          | test "catching up on forgotten ticks in the car"                               |
| 5  | Two stores back to back, 3 to 9 min apart                               | One session; the first store's items move to the second store in store memory | Two trips; no store memory                                                                                                                      | test "two stores back to back"                                                 |
| 6  | Two stores in one mall, under 2 min apart                               | One session, majority store                                                   | One trip, majority store; store memory only if 75 % one store. **Remains**: the minority items show under the wrong store. Fix by "Split here"  | by design                                                                      |
| 7  | Bought an item tagged for another store, mid-walk                       | Learns this store                                                             | Learns this store, only mid-walk                                                                                                                | test "an item tagged to another store"                                         |
| 8  | The same at the last tick (maybe already the next store)                | Learns this store                                                             | Stays in the trip, learns nothing                                                                                                               | same test, edge case                                                           |
| 9  | A storeless item in a walk                                              | Joins, learns the store                                                       | Same                                                                                                                                            | same test                                                                      |
| 10 | Partner at home ticks 1 to 3 "we have that" while the other shops       | Part of the household trip if 3 ticks                                         | Out of the trip                                                                                                                                 | test "a partner ticking"                                                       |
| 11 | Partner at home ticks 5 or more while the other shops at that store     | Merged into the trip                                                          | Merged into the trip. **Remains**, rare; fix by removing the lines                                                                              | by design                                                                      |
| 12 | Phone offline in the store, syncs at the exit                           | Times are a 1 s burst at the exit                                             | Walk from the tap times (F1)                                                                                                                    | test "offline"; sim offline-wrong-clock                                        |
| 13 | Phone clock an hour off, or a hand-set time zone                        | Unaffected (server time)                                                      | Corrected by the person's usual offset                                                                                                          | test "a device clock an hour off"                                              |
| 14 | Ticks from two devices, or retried ops, arrive out of order             | Server order                                                                  | Tap-time order; a late tick reshapes the trip on the next run                                                                                   | by design (idempotent rerun)                                                   |
| 15 | The clock jumps mid-trip (network time fix)                             | Unaffected                                                                    | One step lands out of place; the halfway learner damps it. **Remains**, rare                                                                    | not simulated                                                                  |
| 16 | A stray tick, undone within seconds                                     | Dropped (T5a)                                                                 | Dropped                                                                                                                                         | test "a stray tick"                                                            |
| 17 | Unticked after the trip closed ("wasn't bought")                        | Stays in the trip                                                             | Leaves the trip on the next run within 36 h; its order lesson goes on recompute                                                                 | by design                                                                      |
| 18 | A 12 min wait at the deli counter                                       | Two trips                                                                     | One trip, taught as two walks (F5)                                                                                                              | test "a 12-minute wait"; sim slow-trips: 43 splits become 0                    |
| 19 | A slow store (IKEA), 2 to 8 min between items                           | One trip                                                                      | One trip; slow is fine for the pace rule                                                                                                        | sim (store ikea in every household)                                            |
| 20 | A child taps rows on a parent's phone                                   | A trip if 3 taps                                                              | A burst: no trip under 5 taps, never teaches. Age 16+, no child accounts                                                                        | by design                                                                      |
| 21 | Item not found, left on the list                                        | No effect, the trip ends by time                                              | Same                                                                                                                                            | generator: 5 % of items                                                        |
| 22 | Item not found, ticked away at the end anyway                           | Teaches a late place                                                          | Same, damped to half a step; the next trip corrects it. **Remains**                                                                             | by design                                                                      |
| 23 | Adds an item at the shelf and ticks it                                  | Teaches its place                                                             | Same, which is right: it was picked there                                                                                                       | generator: impulse adds                                                        |
| 24 | Adds and ticks gum at the checkout                                      | Teaches "at the end"                                                          | Same, which is right for checkout shelves                                                                                                       | by design                                                                      |
| 25 | Ticks across two lists in one shop                                      | Per person, across lists                                                      | Same; a detected trip spanning lists gets `list_id` null                                                                                        | by design                                                                      |
| 26 | One item at a small store, then the big one                             | Joins the big store's session; the item's store memory moves                  | Its own trip (T3a), nothing moves                                                                                                               | test "one item at a small store"                                               |
| 27 | The same store twice a day                                              | Two trips                                                                     | Two trips when over 30 min apart                                                                                                                | test "the same store again in the evening"                                     |
| 28 | Back at the same store 20 min later for something forgotten             | Two trips                                                                     | One trip, two walks                                                                                                                             | by design (F5)                                                                 |
| 29 | Siri, Alexa, MCP or API ticks during a walk                             | Excluded (needs a source column)                                              | Excluded; they do not break the walk's chain                                                                                                    | test "Siri, Alexa and agent ticks"                                             |
| 30 | Delivery unpacked at home, a tick every 4 to 20 s                       | A trip; teaches random order; 115 of 222 store memory writes wrong            | A trip in history ("Einkauf bei Rewe"), teaches nothing. Arguably right for a delivery                                                          | test "a delivery unpacked"; sim delivery                                       |
| 31 | Two people split the list, one starts at the back                       | Two trips or one; the backwards walk teaches the reverse                      | One household trip, both walks teach; the halfway, positions-only learner limits the damage to that half. **Remains**: 16 % wrong pairs (TD-Q6) | test "two people splitting"; sim split-couple: order 73 % becomes 84 %         |
| 32 | Two people at different stores at once                                  | Separate trips                                                                | Same                                                                                                                                            | by design                                                                      |
| 33 | Neighbours from one shelf ticked together in list order                 | Teaches the list order between them                                           | One step, tied                                                                                                                                  | test "neighbours ticked together"                                              |
| 34 | A pharmacy                                                              | Not covered by the rule                                                       | Never a trip, no order, no store memory (GL-2)                                                                                                  | test "a pharmacy"                                                              |
| 35 | A manual trip is running                                                | Not covered                                                                   | Its ticks belong to the manual trip; detection skips that person while it runs                                                                  | by design                                                                      |
| 36 | Plans at the desktop and ticks rows away ("have that")                  | As 2                                                                          | As 2                                                                                                                                            | by design                                                                      |
| 37 | Answers "Nein, nur abgehakt" to the trip question, then walks the store | Not covered                                                                   | Open: TD-Q5                                                                                                                                     |                                                                                |

## Simulation

`sim/` is a seeded generator of households, the two detectors, two learners and an evaluator. Run
`deno run sim/evaluate.ts 5` in this folder for the tables below (5 households per persona, 12 weeks each), and
`deno test` for the cases. The lint gate runs both (`scripts/lint.sh`), and a test fails when the tables here differ
from the simulator's output.

**What a household is.** Four stores: Rewe and Aldi with aisles near the route order, IKEA with an unrelated one, and a
pharmacy. Each store sells 160 of 360 keys in 12 categories, and the household buys from 45 of them. The prior (the
order before any trip) is the route order of categories, as `walkingOrder` is today. About 2.5 visits a week. Each visit
plans 5 to 18 items: 10 % without a store, 5 % tagged to another store. A walk takes 4 s plus the distance times 10 to
17 minutes for the whole store, plus 2 to 25 s at the shelf. Neighbours under 4 % of the store apart are ticked together
half of the time. Each member has habits: walk, checkout or catch up at home; offline; clock skew; stray ticks; impulse
adds; "we have that" ticks; voice ticks. Personas turn one habit up each:

| Persona             | Turned up                                                                                      |
| ------------------- | ---------------------------------------------------------------------------------------------- |
| peter-lea           | Peter walks (85 %), clock 40 s off; Lea walks 40 %, checkout 35 %, ticks "we have that" weekly |
| offline-wrong-clock | offline in 50 % of walks, clock an hour behind, many stray ticks and impulse adds              |
| checkout-ticker     | 70 % and 50 % of visits ticked at the checkout                                                 |
| home-sweeper        | two "we have that" bursts a week, one member mostly catches up at home                         |
| delivery            | a delivery unpacked and ticked at home every week                                              |
| split-couple        | 80 % of visits together, half of those with one partner starting at the back                   |
| slow-trips          | 60 % of walks with a 6 to 14 min wait, many same-day returns and second stores                 |

**Scores.** A trip matches a visit when at least half its ticks are from that visit and its store is the visit's store.
Precision is matched trips over all trips. Recall is visits matched over visits with an app tick (pharmacy visits
excluded, GL-2). Phantom trips are mostly ticks from no visit. Split visits are matched by two or more trips. "Taught
pairs wrong" is the share of key pairs a detector teaches in the opposite of the store's real order. Order accuracy is
the share of pairs of the household's bought keys that the learned order puts as the store does, after 12 weeks. "Prior
only" is no learning. "Every visit taught" feeds every real visit in its true order: the ceiling for any detector. Both detectors skip pharmacies (GL-2), so the comparison is about the heuristics only.

<!-- sim:begin -->
| Household | Rule | Visits | Trips | Precision | Recall | Phantom | Split | Wrong store | Store memory wrong | Taught pairs wrong | Order accuracy |
| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |
| peter-lea | starting rule + ema | 192 | 227 | 78 % | 86 % | 45 | 11 | 5 | 32/260 | 15 % | 80 % |
| peter-lea | starting rule + reassign | 192 | 227 | 78 % | 86 % | 45 | 11 | 5 | 32/260 | 15 % | 82 % |
| peter-lea | final rule + ema | 192 | 161 | 99 % | 82 % | 0 | 2 | 2 | 0/124 | 3 % | 87 % |
| peter-lea | final rule + reassign | 192 | 161 | 99 % | 82 % | 0 | 2 | 2 | 0/124 | 3 % | 87 % |
| peter-lea | prior only / every visit taught (reassign) | | | | | | | | | | 81 % / 92 % |
| offline-wrong-clock | starting rule + ema | 191 | 181 | 98 % | 90 % | 0 | 6 | 3 | 17/249 | 26 % | 75 % |
| offline-wrong-clock | starting rule + reassign | 191 | 181 | 98 % | 90 % | 0 | 6 | 3 | 17/249 | 26 % | 77 % |
| offline-wrong-clock | final rule + ema | 191 | 172 | 99 % | 89 % | 0 | 0 | 2 | 0/181 | 4 % | 89 % |
| offline-wrong-clock | final rule + reassign | 191 | 172 | 99 % | 89 % | 0 | 0 | 2 | 0/181 | 4 % | 89 % |
| offline-wrong-clock | prior only / every visit taught (reassign) | | | | | | | | | | 80 % / 92 % |
| checkout-ticker | starting rule + ema | 186 | 187 | 94 % | 89 % | 9 | 11 | 2 | 6/250 | 27 % | 74 % |
| checkout-ticker | starting rule + reassign | 186 | 187 | 94 % | 89 % | 9 | 11 | 2 | 6/250 | 27 % | 77 % |
| checkout-ticker | final rule + ema | 186 | 149 | 99 % | 78 % | 0 | 3 | 1 | 0/46 | 3 % | 83 % |
| checkout-ticker | final rule + reassign | 186 | 149 | 99 % | 78 % | 0 | 3 | 1 | 0/46 | 3 % | 84 % |
| checkout-ticker | prior only / every visit taught (reassign) | | | | | | | | | | 82 % / 92 % |
| home-sweeper | starting rule + ema | 181 | 310 | 57 % | 90 % | 129 | 16 | 3 | 67/289 | 21 % | 75 % |
| home-sweeper | starting rule + reassign | 181 | 310 | 57 % | 90 % | 129 | 16 | 3 | 67/289 | 21 % | 78 % |
| home-sweeper | final rule + ema | 181 | 167 | 95 % | 82 % | 8 | 11 | 0 | 0/57 | 1 % | 83 % |
| home-sweeper | final rule + reassign | 181 | 167 | 95 % | 82 % | 8 | 11 | 0 | 0/57 | 1 % | 83 % |
| home-sweeper | prior only / every visit taught (reassign) | | | | | | | | | | 80 % / 92 % |
| delivery | starting rule + ema | 105 | 179 | 60 % | 90 % | 64 | 13 | 7 | 115/222 | 32 % | 75 % |
| delivery | starting rule + reassign | 105 | 179 | 60 % | 90 % | 64 | 13 | 7 | 115/222 | 32 % | 76 % |
| delivery | final rule + ema | 105 | 163 | 61 % | 91 % | 60 | 4 | 3 | 0/60 | 2 % | 85 % |
| delivery | final rule + reassign | 105 | 163 | 61 % | 91 % | 60 | 4 | 3 | 0/60 | 2 % | 85 % |
| delivery | prior only / every visit taught (reassign) | | | | | | | | | | 78 % / 88 % |
| split-couple | starting rule + ema | 188 | 237 | 94 % | 88 % | 1 | 55 | 13 | 9/246 | 22 % | 73 % |
| split-couple | starting rule + reassign | 188 | 237 | 94 % | 88 % | 1 | 55 | 13 | 9/246 | 22 % | 84 % |
| split-couple | final rule + ema | 188 | 186 | 97 % | 88 % | 0 | 15 | 6 | 0/175 | 16 % | 73 % |
| split-couple | final rule + reassign | 188 | 186 | 97 % | 88 % | 0 | 15 | 6 | 0/175 | 16 % | 84 % |
| split-couple | prior only / every visit taught (reassign) | | | | | | | | | | 81 % / 91 % |
| slow-trips | starting rule + ema | 258 | 247 | 98 % | 77 % | 0 | 43 | 6 | 27/302 | 10 % | 84 % |
| slow-trips | starting rule + reassign | 258 | 247 | 98 % | 77 % | 0 | 43 | 6 | 27/302 | 10 % | 87 % |
| slow-trips | final rule + ema | 258 | 209 | 99 % | 80 % | 0 | 0 | 2 | 0/179 | 2 % | 88 % |
| slow-trips | final rule + reassign | 258 | 209 | 99 % | 80 % | 0 | 0 | 2 | 0/179 | 2 % | 90 % |
| slow-trips | prior only / every visit taught (reassign) | | | | | | | | | | 81 % / 92 % |

| Variant of the final rule (reassign learner) | Precision | Recall | Phantom | Split | Store memory wrong | Taught pairs wrong | Order accuracy | Most affected household (order accuracy, recall) |
| --- | --: | --: | --: | --: | --: | --: | --: | --- |
| final | 93 % | 84 % | 68 | 35 | 0/822 | 4 % | 86 % |  |
| commit times (no client time) | 93 % | 83 % | 68 | 36 | 0/725 | 5 % | 85 % | offline-wrong-clock: 89 % → 86 %, 89 % → 87 % |
| no clumps (each tick its own) | 93 % | 84 % | 68 | 37 | 0/789 | 6 % | 86 % | peter-lea: 87 % → 87 %, 82 % → 84 % |
| no pace rule | 93 % | 84 % | 68 | 35 | 107/929 | 11 % | 85 % | delivery: 85 % → 76 %, 91 % → 91 % |
| pace 40 s | 93 % | 83 % | 68 | 40 | 0/777 | 4 % | 86 % | offline-wrong-clock: 89 % → 89 %, 89 % → 87 % |
| clump 3 s | 93 % | 84 % | 68 | 36 | 0/821 | 5 % | 86 % | split-couple: 84 % → 84 %, 88 % → 88 % |
| clump 10 s | 93 % | 84 % | 68 | 35 | 0/822 | 4 % | 86 % | delivery: 85 % → 85 %, 91 % → 90 % |
| gap 5 min | 93 % | 81 % | 68 | 49 | 0/764 | 5 % | 86 % | slow-trips: 90 % → 90 %, 80 % → 75 % |
| gap 15 min | 93 % | 84 % | 68 | 29 | 5/866 | 5 % | 86 % | slow-trips: 90 % → 91 %, 80 % → 82 % |
| no pause merge | 93 % | 84 % | 68 | 90 | 0/822 | 4 % | 86 % | none |
| store switch without travel time | 90 % | 84 % | 79 | 34 | 0/781 | 4 % | 86 % | home-sweeper: 83 % → 83 %, 82 % → 81 % |
| bursts never trips | 97 % | 60 % | 9 | 3 | 0/822 | 4 % | 86 % | checkout-ticker: 84 % → 84 %, 78 % → 22 % |
| bursts from 3 ticks | 83 % | 88 % | 235 | 52 | 0/822 | 4 % | 86 % | checkout-ticker: 84 % → 84 %, 78 % → 90 % |
<!-- sim:end -->

**Reading it.**

- The starting rule's damage comes from what it teaches, more than from how many trips it finds. Its recall (77 to 90 %)
  is higher in four households and equal in one, but it teaches 10 to 32 % wrong pairs. With job 347's learner, its
  order ends below the prior in six of seven households: learning made the list worse than no learning.
- The final rule teaches 1 to 4 % wrong pairs outside split-couple. Order accuracy ends 2 to 9 points above the prior
  and 2 to 9 below the ceiling. The gap to the ceiling is the visits it does not teach from (checkouts, catch-ups) and
  the half step per trip.
- The new learner matters only where walks are partial: split-couple goes from 73 to 84 %. With a whole-store walk, both
  learners score the same.
- Remaining phantom trips are deliveries (60 of 68).
- These numbers measure the rule against the generator's assumptions, and the thresholds are tuned against them. The
  pace of a real walk, how often people batch ticks, and how fast they unpack a delivery are guesses until real gaps are
  measured (TD-Q8).

## Real data

Skipped. No read-only path to production tick history exists. The ops env has the database password, which is full
access, and `scripts/feedback-monday.sh` reads the local stack only. Using full access would mean opening a new path to
users' data, which the brief rules out. The anonymous aggregates that would calibrate the rule are listed in TD-Q8.

## What users see

**The principle.** The benefit users notice is the order improving by itself. The detected trip is its receipt. So
detection stays quiet while it happens and is easy to correct afterwards.

**During shopping.** Nothing. No live hint (TD-Q4). The trip question ("Kaufst du gerade ein?") keeps working as today,
and the manual trip button stays.

**After the first detected trip.** One card on the list, once per person:

|         | German                                                                                                                                   | English                                                                                                           |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Title   | Einkauf bei {store} erkannt                                                                                                              | Shopping at {store} detected                                                                                      |
| Body    | Snacklist merkt sich, in welcher Reihenfolge du abhakst, und sortiert die Liste beim nächsten Mal so. Den Einkauf findest du im Verlauf. | Snacklist remembers the order you tick in and sorts the list that way next time. You'll find the trip in History. |
| Actions | Ansehen · Verstanden                                                                                                                     | View · Got it                                                                                                     |

**In Verlauf.** A detected trip looks like any other trip, with one line of secondary text under the store's name. It is
not a pill or badge, so there is no hint copy inside a control.

|                                      | German                      | English                      |
| ------------------------------------ | --------------------------- | ---------------------------- |
| Line under the store                 | Aus deinen Häkchen erkannt  | Detected from your ticks     |
| Line for another member's trip       | Aus {name}s Häkchen erkannt | Detected from {name}'s ticks |
| A burst without a walk (no duration) | Abgehakt, ohne Dauer        | Ticked, no duration          |

A detected trip shows day, store, duration and items. It shows no clock times when another member views it (Legal
notes).

**Fixing a wrong one.** On a detected trip's page, any member can (GL-3):

| Action           | German                               | English                    | What happens                                                                                                                                                                                                                   |
| ---------------- | ------------------------------------ | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Change the store | Laden ändern                         | Change store               | The trip moves to the store; its order lesson moves to that store's order; store memory relearns                                                                                                                               |
| Split            | Ab hier neuer Einkauf (on a line)    | New trip from here         | Two trips, each teaches its own part                                                                                                                                                                                           |
| Merge            | Mit dem Einkauf davor zusammenführen | Merge with the trip before | One trip; shown only for the same day and within 3 hours                                                                                                                                                                       |
| Remove           | Kein Einkauf                         | Not a shopping trip        | Confirm: "Kein Einkauf? Die Häkchen bleiben, aber die Reihenfolge lernt nicht mehr daraus." / "Not a shopping trip? The ticks stay, but the order no longer learns from it." Then a snackbar with undo: "Entfernt" / "Removed" |

An edited trip is frozen: detection never rewrites it.

**Opting out.** One switch per person under More › Settings, off for nobody by default:

|          | German                                     | English                               |
| -------- | ------------------------------------------ | ------------------------------------- |
| Switch   | Einkäufe aus meinen Häkchen erkennen       | Detect trips from my ticks            |
| Below it | Nutzt nur, wann du abhakst. Kein Standort. | Uses only when you tick. No location. |

**If Peter wants the live hint anyway** (TD-Q4), the copy is a line above the list, never a dialog. German: "Sieht nach
Einkauf bei {store} aus. Die Reihenfolge lernt mit." English: "Looks like you're shopping at {store}. The order learns
as you go." It shows after the third step of a walk and goes away by itself. A tap opens the trip question.

## For job 352

- `item_events`: add `client_at timestamptz` (the tap time, from `SetStatus.at`; clamped to the 7 days before and 5
  minutes after `now()`, else null), `source text` (`app`, `voice`, `agent`; edge functions set it through a
  transaction-local setting the trigger reads) and `store_id uuid` (the item's store at the event, as job 347 plans).
  All three are nullable, so old app builds keep working. Their ticks fall back to commit times and an offline walk
  becomes a burst, which teaches nothing: a safe failure.
- The app sends `ticked_at` with the status update. `items.bought_at` stays the server's time, so nothing that reads it
  changes.
- Detected trips go into `trip_sessions` with `source = 'detected'` and `end_reason = 'auto'`, plus `trips` rows as trip
  mode writes them. Their id is md5 of the actor and the first tick's id, so a rerun updates the same row. A member's
  edit sets `source` to `manual`, which freezes the trip.
- Learning is recomputed per store from its taught walks in time order when a trip is removed or changes store. The
  halfway learner cannot subtract one trip, and a store has tens to hundreds of trips, so a replay is cheap.
- The simulator here is the reference for the rule. Port the tests in `sim/detect_test.ts` to pgTAP cases of the SQL
  function.

## Legal notes

- **New derived data.** Inferred store visits: who shopped, where, on which day, for how long, and in what order they
  ticked. Until now a trip was recorded only when someone started it. A detected trip is recorded without that act. It
  needs a row in `docs/PRIVACY_DATA_MAP.md` and a sentence in the privacy notice: Snacklist recognizes shopping trips
  from the times items are ticked, without location.
- **Inside the household.** Other members see the trip. A detected trip can show a partner where they were and when,
  which they did not choose to share. Mitigations proposed: other members see the day and the store, not clock times; a
  per-person switch turns detection off for one's own ticks; any member can remove a trip (GL-3). Legal should confirm
  that this is enough (TD-Q3).
- **No location.** Detection uses tick times and the store the user tagged. No GPS, no Wi-Fi, no geofence. The copy says
  so.
- **Pharmacies (GL-2).** No detected trip, no order learning and no store memory at a pharmacy. Tick events at a
  pharmacy are already stored today; nothing new derives from them.
- **Tap time.** `client_at` is a new field: the device's time at the tap. It carries no more than `created_at` already
  does, except for offline ticks. It follows `item_events`' retention and deletion.
- **Export and deletion.** Detected trips join the user's export as trips they started. Leaving the household, removal
  and account deletion null the person on them, as for `trip_sessions` today (Legal N-115).
- **Retention.** As trips: until the trip or the household is deleted.

## Open questions

- **TD-Q1 (Peter).** H2 change: a burst of fast ticks is a trip in history only from 5 ticks, and never teaches order.
  Starting rule: every 3-tick session is a trip. Recommendation: accept. Alternative: no bursts as trips at all (fewest
  phantoms, but recall falls to 60 %, and a household that ticks at the checkout gets almost no history).
- **TD-Q2 (Peter).** T1a change: the same person at the same store again within 30 minutes continues the trip. Starting
  rule: a new trip. Recommendation: accept.
- **TD-Q3 (Legal).** Are a per-person opt-out and no clock times for others' detected trips enough for inferred visits
  inside a household? Is a privacy notice sentence enough, or does detection need an explicit yes first?
- **TD-Q4 (Peter).** Live "Looks like you're at Rewe" hint: recommendation no. Detection needs three steps (several
  minutes), a wrong guess at home ("at Rewe?" while unpacking) reads as tracking, and hands are full in the store. The
  first-trip card explains the feature once.
- **TD-Q5 (Peter).** After "Nein, nur abgehakt" on the trip question, should that run still be detected? Recommendation:
  no trip in history for that run, but the order still learns, since order is household data, not a record of the
  person.
- **TD-Q6 (job 352).** A partner who walks the store from the back teaches reverse pairs (16 % wrong in split-couple).
  Per-person direction would fix it, at the cost of a second order. Measure on real trips first.
- **TD-Q7 (job 352).** A device id on each event would let the clock offset be per device rather than per person. It
  matters only for people with two devices and different clocks.
- **TD-Q8 (lead).** Calibration needs a read-only path that returns only aggregates: the distribution of gaps between
  one person's consecutive app ticks (bucketed), burst sizes, and the share of ticks with a commit time more than 10 s
  after the tap (once `client_at` exists). Should one be built, for example a `security definer` function that returns
  histograms only?
- **TD-Q9 (job 352).** Delivery unpacking shows up as a trip with no duration. Should a household be able to mark a
  store as a delivery service, so its bursts never show as trips?
