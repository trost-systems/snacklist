# Job 352: learned order from detected trips (IO4)

Peter approved IO4 from round IO (job 347) with its defaults, learning from trips detected in plain ticks by job 351's final rule (t1121u/t1122u, 21 Nov 2026). Legal Review 21 Nov 2026 (TD-Q3): legitimate interest with a per-person objection switch, N-318 to N-321.

PR: #616 (ready, not merged: needs Legal's hash GO). Flag: `learned-order` (`releases/flags.json` off; the flag sync creates it for internal testers, so Peter and Lea once on main). Decisions: `docs/DECISIONS.md` "Job 352".

## What

IO4 from round IO (Peter t1121u/t1122u): the list learns, per store, the order the household walks it, from trips the server detects in plain ticks (job 351's final rule). Categories stay hidden, and a "Neben …" chip puts one item in its place at once. Agents get the same verbs. Everything is behind the PostHog flag `learned-order` (`releases/flags.json` `off`; the flag sync creates it for internal testers, so Peter and Lea). Households without it behave as before, server side included.





### Server
- `households.order_mode` (`categories` | `learned`), switched by the app through `set_order_mode` when the flag is on. Only `learned` households are detected, learn, and get the new place rules and MCP walk order.
- `item_order_memory`: one position per (store, canonical key), seeded from today's walk order so the first learned list looks exactly like the old one. `items.sort_key` means "place inside the store" there. A re-add returns to its place, a category change keeps it, a store change takes the new store's place.
- `replay_store_order`: job 351's learner (F8 trade, step 0.5, shuffle gate after 3 walks at 60 %) replayed from the seeds over stored walks and manual places, with one change: neighbours a walk swaps flip instead of tying. A manual place holds until three walks in a row disagree. Differential test against 351's TypeScript `trade`: positions equal to 1e-9 on random walks.
- `detect_trips`: 351's `finalRule` in SQL, run by pg_cron every 5 minutes, one transaction per household. Simulator comparison: 9 personas × 2 seeds × 4 weeks, loaded day by day and week by week: **0 differences** in trips and walks.
- Ticks: the app ticks and unticks through `set_item_status` with the tap time. `item_events` gains `client_at` (only for people with detection on), `source` (`app`, `agent` for MCP and API; Siri and Alexa never tick), `store_id`, `store_open_after`.

### App (flag `learned-order`)
- Learned sort, one run per store, no category dividers. The "Neben {name}" / "Ganz vorne" chip replaces the category chip, with a filter above 15 items.
- History: detected trips with "Aus deinen Häkchen erkannt" (four variants), "Kein Einkauf" (confirm, "Entfernt").
- First-trip card (once per person, names the switch). Settings: "Einkäufe aus meinen Häkchen erkennen".
- Trip question: with the flag, one line under the buttons says that "Nein" snoozes it for an hour (main's job 357 snooze). The manual trip button stays.
- Every user's ticks go through `set_item_status`. On a backend without it (PGRST202), the app falls back to the old PATCH.

### API and MCP
- Items gain `position`. MCP `list_items` lists a learned household in walk order. `GET /v1/items?order=walk` pages that way (v1 default unchanged).
- New: MCP `place_item` and `POST /v1/items/{id}/place`, MCP `set_store_order` and `PUT /v1/stores/{id}/order` (learned households; else 409 `order_mode`). Docs: `docs/API.md`, `docs/MCP.md`, `docs/api/openapi.yaml`.

## Legal (Review 21 Nov 2026, TD-Q3)

- **N-318.** A new `docs/PRIVACY_DATA_MAP.md` row ("Detected shopping trips", basis (f) with the objection switch) and an extended `item_events` row. The proposed notice sentences are below. `site/content/legal/*` is unchanged.
- **N-319.** Switching off (`set_trip_detection(false)`) keeps the person's ticks out of detection from every source and deletes their unedited detected trips in every household, under every household's lock (no race with a running detection). Switching on counts only ticks after that moment. A person is detected only after their app has shown them the switch: members without the flag, or with an older build, are never detected. Tap times are stored only for people with detection on.
- **N-320.** Others see a person's detected trips only after that person has seen the first-trip card. The card names the switch.
- **N-321.** Enforced in SQL and tested in pgTAP. `trip_session` sends no start, end or pauses of another member's detected trip. `trip_history_v2` dates its log row at midnight UTC. `trip_history` (older builds) shows no detected trips. Members can no longer select `item_events`. `suggest_items` is `security definer`, ignores a caller's clock and returns `last_used` by the day. No trip and no walk at a pharmacy (GL-2).
- **Still visible as before this job:** `items.bought_at` and `bought_by` show members when and by whom an item was last ticked.

## Privacy (Legal N-318): proposed notice sentences

Legal drafts the final text; `site/content/legal/*` is not edited in this PR.

**DE (Datenschutzerklärung, Abschnitt Einkaufsliste / Verlauf):**
Wenn du Artikel abhakst, erkennt Snacklist daraus Einkäufe: an welchem Tag du in welchem Laden warst, wie lange und in welcher Reihenfolge du abgehakt hast. Dafür nutzen wir nur die Zeit deiner Häkchen (die Uhrzeit deines Geräts beim Tippen) und den Laden, dem du den Artikel zugeordnet hast, keinen Standort, kein WLAN und keine anderen Sensoren. Aus der Reihenfolge lernt die Liste, wie dein Haushalt einen Laden abläuft, und sortiert sie danach. Andere Mitglieder deines Haushalts sehen einen erkannten Einkauf im Verlauf mit Tag, Laden, Dauer und Artikeln, aber ohne Uhrzeiten, und erst, nachdem du den Hinweis zu deinem ersten erkannten Einkauf gesehen hast. In Apotheken erkennt Snacklist keine Einkäufe und lernt nichts. Häkchen von Siri, Alexa, KI-Assistenten und der API werden dafür nicht genutzt. Rechtsgrundlage ist unser berechtigtes Interesse (Art. 6 Abs. 1 lit. f DSGVO), dir eine Liste in der Reihenfolge deines Ladens zu zeigen. Du kannst jederzeit widersprechen: Schalte in der App unter Mehr › Einstellungen „Einkäufe aus meinen Häkchen erkennen" aus. Dann erkennt Snacklist aus deinen Häkchen keine Einkäufe mehr und löscht deine erkannten Einkäufe, die niemand bearbeitet hat; auch wenn du es wieder einschaltest, kommen sie nicht zurück. Jedes Mitglied kann einen erkannten Einkauf mit „Kein Einkauf" entfernen. Erkannte Einkäufe bleiben gespeichert, bis sie entfernt werden oder der Haushalt gelöscht wird, und sind Teil deines Datenexports.

**EN (privacy policy, shopping list / history):**
When you tick items off, Snacklist detects shopping trips from those ticks: on which day you were at which store, for how long, and in which order you ticked. It uses only the time of your ticks (your device's clock at the tap) and the store you gave the item, no location, no Wi-Fi and no other sensors. From that order the list learns how your household walks a store and sorts itself that way. Other members of your household see a detected trip in History with its day, store, duration and items, but without clock times, and only after you have seen the note about your first detected trip. Snacklist detects no trips and learns nothing at pharmacies. Ticks made through Siri, Alexa, AI assistants or the API are not used for this. The legal basis is our legitimate interest (Art. 6(1)(f) GDPR) in showing you the list in your store's order. You can object at any time: in the app, turn off "Detect trips from my ticks" under More › Settings. Snacklist then stops detecting trips from your ticks and deletes your detected trips that nobody has edited; they do not come back if you turn it on again. Any member can remove a detected trip with "Not a shopping trip". Detected trips are kept until they are removed or the household is deleted, and they are part of your data export.

### Changed strings (ARB, DE and EN)


## Open questions answered with the recommended default (brief: list them)

- **TD-Q1.** A burst of 5 or more fast ticks is a trip in Verlauf ("Abgehakt, ohne Dauer") and never teaches.
- **TD-Q2.** The same person at the same store within 30 minutes continues the trip.
- **TD-Q4.** No live "Looks like you're at Rewe" hint. After „Nein“ the question is snoozed by main's 60-minute rule (job 357), which replaced this job's 30-minute quiet. With the flag, a line under the buttons says so.
- **TD-Q5.** A shop after „Nein" is still detected.
- **TD-Q10 to TD-Q14.** 351's proposed rule (pace 20 s, steps under 6 s, 10-minute runs, the 2-minute store change, the tap time). TD-Q14's store memory part is not built (see below).
- **TD-Q16.** F8 plus the shuffle gate, with the tie change above.
- **IO-Q1, Q5, Q6, Q9, Q10, Q12.** As round IO recommends.
- **IO-Q4.** Replaced by detection (Peter's brief).
- **TD-Q6 to TD-Q9.** Left open: they need real data.

## Not in this PR (follow-ups)

- Store memory taught by walks (351 step 5).
- IO-Q11: a new store's first order from the household's average. It starts from its category walk order instead.
- The "Show categories" switch (IO-Q3). Job 350's flag hides them.
- "Ändern" (store), split and merge on a detected trip. Only „Kein Einkauf" is built (TD-Q15).
- "After three „Nein" stop asking" and its switch.
- Per-person direction (TD-Q6), per-device clock offsets (TD-Q7), calibration aggregates (TD-Q8), delivery stores (TD-Q9).
- A learned gap is never renumbered: about 29 places into one gap before two items tie.
- Retroactive detection: none before the household's switch. After an opt-out, the others' trips are re-detected only within 14 days.

## How it was verified

- pgTAP: `learned_order.test.sql`, `trip_detection.test.sql`, `trip_detection_privacy.test.sql` plus the adapted existing files; every review fix has a test seen failing before it.
- Differential tests on a local stack: `replay_store_order` against 351's TypeScript `trade` (40 random trials, 1e-9), and `detect_trips` against `finalRule` (9 personas x 2 seeds x 4 weeks, day by day and week by week, 0 differences).
- e2e `learned-order.spec.ts` (4 cases), with `mcp.spec.ts` and `public-api.spec.ts`: 15 passed. Full e2e once before the main merge: 284 passed; the 10 failures are the fake sign-in provider specs this runner cannot reach (recipe `e2e-fake-oidc-unreachable.md`).
- Real web build with `journeys/learned-order.mjs`: screenshots `docs/screenshots/352/`; feature map `features/learned-order.md`.
- Gates: lint, functions, db, flutter passed on the merged tree. "an add answers within its size and time" (api_integration_test) failed in some full runs under load and passes alone; it touches no code of this job and failed the same way on job 350's PR.

## Review 0 (2026-11-22)

- GL-2: ticks of a pharmacy store are dropped before detection, so a pharmacy tick in the middle of a supermarket walk joins no trip, no walk and no learned order (the simulator reference applies the same filter; 0 differences, 1 of 18 households changed against 351's rule).
- N-321/N-320: clock times only for a trip's sole detector (a shared trip has none for anyone, in the trip page, Verlauf and the export); a co-detected member sees a shared trip only after every other detector has seen their card.
- Opt-out also clears the person's tap times and „Kein Einkauf“ tombstones; no default switch time; OAuth JWTs tick as `agent`; members no longer read `item_order_memory`; editing a detected trip's log entry freezes it; leave, removal and account deletion take the detection lock first.
- App: „Einkauf erkannt“ for a trip without a store (new key `detectedCardTitleNoStore`), a refused switch shows a message, Settings re-reads an unknown switch, a place needs no category.
- Open for Legal: `items.bought_at`/`bought_by` (DECISIONS "Job 352" point 11).

## Review 1 (2026-11-22)

- Peter's binding TD answers (addendum 22 Nov 07:11):
  - TD-Q5: a run answered „Nein“ (or dismissed) is not detected and teaches nothing. The app queues `DeclineShop` → `decline_shop`, the server keeps `shop_declines` for 15 days, and detection skips the person's ticks until a gap of more than 30 minutes.
  - TD-Q2: a same-store return within 30 minutes continues the trip in either order.
  - TD-Q1: a burst counts from 5 ticks and never teaches.
  - TD-Q4: no live hint.
  - Tests named after each.
- The 30-minute quiet's leftovers are aligned with job 357's 60-minute snooze.
- Others' detected trips of one day are no longer ordered by time.
- For the lead: T3a (two fast ticks that finish a store teach a 2-step walk), and bursts that add up to 5.
