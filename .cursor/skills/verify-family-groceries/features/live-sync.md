# Live sync

Two members of one household see each other's changes without reloading. An item added on one phone appears on the other, and an item ticked off on one disappears from the other immediately. Edits and moves sync the same way: a partner's drag to another place, category or store shows on the other phone. Partner items added since this device last looked are tinted, with "N neu von <name>" in the bar above the list, until they have been on screen for 3 seconds.

## Sub-features

- `sync-add` shows an item added by one member on the other member's list.
- `sync-tick` removes an item from the other member's list when one member ticks it.
- `sync-edit` shows a renamed or recategorized item on the other list.
- `sync-move` shows an item a partner dragged (to another row, category or store) in its new place on the other list (`features/list-walk-order.md`, Partner move).
- `sync-delete` removes an item deleted by one member from the other list.
- `sync-reconnect` catches up after the connection comes back: changes made while offline go out, changes made by others come in. An offline add of an item someone else added meanwhile becomes their item (no second row, theirs stays as it is), and an offline tick or edit of it goes to theirs (job 64b, `put_item`; e2e `already-on-list.spec.ts`).
- `sync-after-sleep`: a phone that sleeps through a dropped connection and a partner's add catches up on waking (the item shows, the channel is live again, adds go both ways). e2e: live-sync.spec "a phone that sleeps through a dropped connection ...", which freezes the page with CDP `Page.setWebLifecycleState` and closes its Realtime socket meanwhile.
- `sync-expired-token`: a write the server refuses with a JWT error (`PGRST3xx`, the token lapsed in flight) is retried with a fresh token, not dropped as "Änderung abgelehnt". Covered by the e2e test "a write the server answers with an expired token is retried, not dropped" (`e2e/tests/offline-start.spec.ts`), which fakes the 401 with `page.route`. A 401, 408 or 429 without a PostgREST error code (a gateway answered, not the database) is retried the same way since job 222 (`app/test/list/list_repository_test.dart`, "a gateway's 401, 408 or 429 refuses no change"; no e2e).
- `sync-new` tints partner items added after this device last looked honey-soft (yellow is new, mint is done, job 57) (row name ends in "Neu"), with the subtitle "N neu von <name>" ("N neu" for several partners). An item clears after 3 s more than half on screen while the app shows and stays cleared after a relaunch; a ticked item is not counted while ticked (put back unseen, it is new again). On a first start nothing old is new. The subtitle has the key `new-items-subtitle`.
- `sync-status-icon` the sync indicator (job 161): while offline (at once when the device's network goes down on the web, Android and iOS, job 166, not on the Linux build; `offline-network` in verify-snacklist's offline.md), or once the server answered with errors and the automatic retry about 3 s later failed too (job 165), a floating hex card under the bar says so (one raised hex button, key `sync-indicator` in both forms; the card's content is `sync-card`; navy „Offline“ with „Änderungen werden synchronisiert, sobald du wieder online bist.“, honey „Sync gestört“ with „Deine Änderungen sind auf dem Gerät gespeichert.“ and a retry hex cue). After about 3 s, or at once on a scroll of the list or a swipe up on the card, the same hex folds into a small pill at the top left of the bar in one 360 ms morph of position, size and content (job 165; reduced motion: a 200 ms crossfade instead; the pill's content is `sync-pill`, „Offline“ / „Gestört“, EN "Offline" / "Failing"). A tap on the pill opens the card again; offline, a tap on the open card folds it. Failing, a tap on either retries: the arrows spin, and on success it leaves without any confirmation (screen readers hear „Synchronisiert“); a failed retry leaves the pill with a nudge ("Immer noch gestört"). One button node at a time, named „Offline: Änderungen werden synchronisiert, sobald du wieder online bist.“ (EN "Offline: Your changes will sync once you're back online.") or „Sync gestört: Deine Änderungen sind auf dem Gerät gespeichert.“ (EN "Sync failing: Your changes are saved on this device."). Nothing shows while online, also while changes are on their way. Offline wins over failing.
- `sync-rejected` a write the server refuses (not a lapsed token) shows the snackbar „Änderung abgelehnt: {name}“ and the item goes back to the server's state.

## How to get to it (user POV)

- Peter and Lea each open the app on their own phone, signed in to the same household.
- One of them adds, ticks, edits or deletes an item. The other only looks at the list.

## Driving it with fg

Preconditions for `fg sync` (web, two or three members, captures by itself):

- A stack: `fg up --only stack`. `fg sync` seeds `household-3-mid-shop` (Mia, Noah, Ida; a list mid-shop) as a fresh run, builds the web app and tears the run down afterwards.

- **Three clients, one command.** Run `fg sync household-3-mid-shop --clients 3 --script .cursor/skills/verify-family-groceries/journeys/sync-3-clients.fgs`. It covers `sync-add`, `sync-tick`, `sync-edit` and `sync-reconnect` (B goes offline, ticks, A adds, B comes back) and exits 0 with per-client latencies. Open `evidence.index` from its JSON: every step and every observed change has a side-by-side frame of all clients, plus one video per client and `videos/composite.webm`.
- **Your own steps.** Write a script (`A add "X"`, `B tick "X"`, `C edit "X" quantity "2"`, `B offline`, `B online`, `expect A,C see|gone "X" within 2000ms`; `fg help sync`) and run it with `--clients 2` or `--clients 3`. `--keep` leaves the run for inspection (`fg db query ... --as <run>:mia`).
- **A failing expectation shows why.** `journeys/sync-failing-expectation.fgs` expects a row that never comes: exit 1, code `sync_failed`, and `error.failureFrames` lists the frames from the step before to the failure.

Preconditions for the Marionette clients (Linux desktop app, peter and lea):

- `fg up --clients peter,lea`, then `fg login peter` and `fg login lea`. `fg doctor` shows `screen list` for both.
- For `sync-new`, peter's app shows the list (the 3 s clock runs only while the item is on screen).
- Neither test item is active: `fg db query "update items set status = 'bought' where status = 'active' and name in ('Milch', 'Butter', 'Hafer', 'Hafermilch') and household_id = (select id from households where name = 'Familie Test')" --write`.

- **One command.** Run `.cursor/skills/verify-family-groceries/journeys/quick-add-live-sync.sh`. It adds Milch on peter through the autofocused field, waits for it on lea, ticks it on lea with a tap on its row, waits for it to leave peter, and checks the stored row (bought, by lea). It records both screens and prints `PASS` with both timings and the evidence directory.
- **Add on one, see on the other.** Run `fg type --key add-item-field --input Butter --submit --client lea` and `fg wait --contains "Hinzugefügt: Butter" --client lea`. Then run `fg wait --text Butter --client peter --timeout 5`, which succeeds with `elapsedMs`.
- **Tick on one, gone on the other.** Run `fg tap --text Butter --client peter` (a tap on the row ticks it). Then `fg wait --text Butter --gone --client lea --timeout 5` succeeds.
- **Edit on one.** On peter, run `fg marionette -- long-press --text Milch` (with Milch on the list), `fg wait --key edit-sheet`, `fg type --key edit-name --input Hafermilch` and `fg tap --key edit-done`. `fg wait --text Hafermilch --client lea` succeeds.
- **Delete on one.** The app has no delete button since job 149; delete as lea through the database: with Butter on the list, run `fg db query "delete from items where name = 'Butter' and status = 'active'" --write --as lea`. `fg wait --text Butter --gone --client peter --timeout 10` succeeds.
- **"neu".** With peter's list open, run `fg peer lea add Hafer`, then at once `fg wait --text Hafer` and `fg screenshot --name sync-new-live`: the row is tinted and the bar above the list reads "1 neu von Lea" (`fg find --key new-items-subtitle`). Rows carry no partner initial (job 15). `fg wait --key new-items-subtitle --gone --timeout 8` succeeds within about 3 s and the tint is gone.
- **Stays seen.** Run `fg restart` (and `fg login peter` if the login screen shows). `fg wait --text Hafer` matches and `fg find --contains neu` returns count 0.
- **Independent observer.** In a second shell, run `fg peer lea watch --until Butter --timeout 20 2>watch.err` and make the change only after `watch.err` shows `watch live after <n> ms`. It prints the realtime INSERT and UPDATE events that lea's session receives, with timestamps (`atMs`, and `liveAtMs` for the moment it went live).
- **Reconnect.** On the Linux clients fg cannot take one client offline, so drive `sync-reconnect` with `fg sync` (`B offline` ... `B online`, above) on web. The e2e test "a tick made while offline syncs when the connection returns" (`e2e/tests/live-sync.spec.ts`) covers it in CI too.
- **Proof.** Record both clients (`fg record start --name sync-peter --client peter` and `--name sync-lea --client lea`). Screenshot the observing client after each change, and show the stored row with `fg db query`.

## Gotchas

- `fg sync`'s `tick` taps the item's row, as a user does; `store` and a scenario client's store view (household-3-mid-shop's Noah) fold every other store section by tapping its divider and keep "Ohne Laden" open (`shopAt` in `e2e/sync/engine.mjs`). `journeys/sync-3-clients.fgs` passes with both.
- `fg sync` needs Playwright in `e2e/`: run `cd e2e && npm ci` once per checkout, or it stops with `missing_tool`.
- `fg sync` holds `/tmp/fg-e2e.lock` while its browser runs, so it may wait for another job's Playwright run first (`--lock-wait`). Do not wrap it in a second `flock` from another shell; wrapping the same command in `flock /tmp/fg-e2e.lock` is fine (fg sees the parent holds it).
- `expect ... see` matches rows Flutter has built: on screen plus a small margin. In a long list a row far down is not seen; use a scenario where the rows in play are near the top (household-3-mid-shop fits a 480×900 client) or `--viewport 480x1400`.
- Latency in `fg sync` is measured from the acting client's server ack to the first rendered frame showing the change (resolution: one frame plus the observer). Catch-up after `online` is reported apart from live propagation.
- Each debug app uses about 650 MB of RAM (JIT), so two need about 1.3 GB plus the stack. One app plus `fg peer` is the light variant, and the only one with the android surface (one emulator).
- `elapsedMs` from `fg wait` is an upper bound: polling every 0.5 s plus about 0.2 s per Marionette call.
- A delete from the app (the row's screen-reader action) hides the row on the acting client at once (optimistic); the server delete lands about 1 to 3 s later, and only then does the other client drop the row. Use `--timeout 10` for deletes.
- A precondition written with `fg db query --write` also syncs live, because it is a real update. Write preconditions before you start recording.
- Both apps must be signed in to the same household. A client left on another account from an earlier recipe shows a different list. The list names no household (job 29a): check an item only that household has, or the household in the database.
- Realtime joins a channel before its Postgres listener is live (the `system` message "Subscribed to PostgreSQL" follows ~2.5 s later). The list resyncs on that message too (job 2b), so a change made right after opening still appears. The web e2e test "a change made before the channel is live still shows up" holds that message back to prove it.
- `fg peer watch` reports nothing that was written before its `watch live` line: starting it in the background and writing at once loses the event, and it then fails with `timeout`. A delete reaches the watcher as no event at all; prove deletes on the other client or with `fg db query`.
- The "neu" tint lasts only 3 s on screen. Take its screenshot in the same command chain as the wait, and prove "cleared" with `fg find --contains neu` (count 0) rather than a sleep.
- "New since you looked" is per device: an item lea adds while peter's app is closed is new when it opens; the Playwright spec `e2e/tests/partner-news.spec.ts` drives that path with two browser contexts.
