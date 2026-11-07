# Live sync between household members

Members of one household see each other's changes without reloading: an item one adds appears on the other's list, a tick makes it vanish, edits and moves show in the new place, a delete removes it. Partner adds the user has not looked at yet are tinted and the bar above the list says „1 neu von Noah Brandt“ (the partner's display name) until each item has been more than half on screen for 3 seconds. Offline or while syncing fails, the sync indicator (job 161) shows a card under the bar that folds into a pill at its top left; nothing shows while online, also while changes are being sent.

## Sub-features

- `sync-add` / `sync-tick` / `sync-edit` / `sync-delete` a partner's add, tick, edit or delete shows on the other list within a couple of seconds.
- `sync-move` a partner's move of an item to another category or store shows in its new place.
- `news-subtitle` bar text „{n} neu von {name}“ (EN "{n} new from {name}") when the unseen adds are all from one partner; „{n} neu“ / "{n} new" when from several; empty otherwise. The bar floats over the top of the list (job 148): „Anpassen“ at the top right is a raised button with no frame around it (job 152); this text sits in their own small hex capsule to its left, shown only while there is something to say. The bar keeps its height and „Anpassen“ its place in every state, and the rows scroll on under it.
- `news-row` an unseen partner item's row is tinted honey (since job 57) and "Neu" (EN "New") ends its accessible name, after the details and quantity: "Kaffee Neu", "Bananen 6 Neu".
- `news-clear` an item stops being new after 3 s more than half on screen while the app is showing; stays cleared after reload. A ticked item is not counted while it is ticked; put back before it was seen, it is new again. Own adds are never new. On first start nothing old is new. Items added while the app was closed are new on the next open.
- `sync-status-icon` the sync indicator (job 161): while offline, or once the server answered with errors and the automatic retry about 3 s later failed too (job 165: one error the retry gets past, such as a single 503 or a token refreshed mid-request, shows nothing), a floating hex card under the bar says so (one raised hex button, key `sync-indicator` in both forms; the card's content is `sync-card`; navy „Offline“ with „Änderungen werden synchronisiert, sobald du wieder online bist.“, honey „Sync gestört“ with „Deine Änderungen sind auf dem Gerät gespeichert.“ and a retry hex cue). After about 3 s, or at once on a scroll of the list or a swipe up on the card, the same hex folds into a small pill at the top left of the bar in one 360 ms morph of position, size and content (job 165; reduced motion: a 200 ms crossfade instead; the pill's content is `sync-pill`, „Offline“ / „Gestört“, EN "Offline" / "Failing"). A tap on the pill opens the card again; offline, a tap on the open card folds it. Failing, a tap on either retries: the arrows spin, and on success it leaves without any confirmation (screen readers hear „Synchronisiert“); a failed retry leaves the pill with a nudge ("Immer noch gestört"). One button node at a time, named „Offline: Änderungen werden synchronisiert, sobald du wieder online bist.“ (EN "Offline: Your changes will sync once you're back online.") or „Sync gestört: Deine Änderungen sind auf dem Gerät gespeichert.“ (EN "Sync failing: Your changes are saved on this device."). Nothing shows while online, also while changes are on their way. Offline wins over failing. Recipe and Playwright steps: [offline.md](./offline.md).
- `sync-reconnect` changes made offline go out when the connection returns; the other side's changes come in (resync); also on app resume and after Realtime drops (retry about 3 s, backing off to 30 s). A Realtime error, timeout or close, or a failed resync, shows the offline icon until the channel is live again or a write is acknowledged.
- `sync-rejected` a write the server refuses shows a snackbar „Änderung abgelehnt: {name}“ (EN "Change refused: {name}") and the item reverts; the snackbar shows above an open sheet or dialog (job 116). A lapsed token is retried, not refused.

## How to get to it (user POV)

- No screen of its own: two members signed in to the same household (one invites with „Mehr“ → „Partner einladen“, the other joins with the link or code), both on „Liste“. The bar is the strip at the top of the list; the icon sits in a small capsule just left of „Anpassen“ / "Edit" at its right end.

## Driving it with Playwright

Preconditions:

- The seeded household „Familie Brandt“ (`demo-familie`) with its three demo members (Mia, Noah, Ida; `member(inst, 'noah')` in `helpers/lib.mjs`). Use two browser contexts (`browser.newContext()`), A signed in as Noah, B as Mia (or: member A signs up with `signUpWithHousehold`, `createInviteCode`, member B `signUp` + `joinWithCode`, as the specs do). Both pages on „Liste“. The steps below use seeded items (Bananen, Mineralwasser, Apfelsaft, Spülmittel) plus Kaffee, Tomaten and Eier, which A adds.
- Names: the partner's display name appears in the bar, „Noah Brandt“ in the seed; with sign-up accounts it is the email's local part.

- **Add.** On A `addItem(a, 'Kaffee')`. On B observe `itemRow(b, 'Kaffee')` visible within 2 s (`within(2_000, ...)`). Its accessible name is "Kaffee Neu" until seen.
- **Partner news.** On B `getByText('1 neu von Noah Brandt')` visible while the row has "Neu" in its name; after about 3 s on screen `itemRow(b,'Kaffee')` loses "Neu" (`not.toHaveAccessibleName(/Neu/)`) and the text is gone (`getByText(/ neu( von|$)/)` count 0; allow 15 s). Reload: still cleared.
- **Added while away.** Close B's page, A adds Tomaten, open a new page in B's context: `itemRow(b,'Tomaten')` has "Neu" and the subtitle shows; the add field stays focused (the highlight never takes focus).
- **Tick.** `tick(a, 'Mineralwasser')`; on B `itemRow(b,'Mineralwasser')` count 0 within 2 s.
- **Edit.** On A `openEdit(a,'Bananen')`, `typeInto(editField(a,'Menge'),'8')`, `saveEdit(a)`; on B `itemRow(b,'Bananen')` has accessible name `/^Bananen 8( Neu)?$/` ("Neu" comes last).
- **Delete.** The app has no delete button since job 149, so delete as B through the API: `(await apiAs(inst, member(inst, 'mia'))).from('items').delete().eq('name', 'Spülmittel')` (`helpers/lib.mjs`; in a spec `apiAs(email)` from `e2e/tests/helpers.ts`); on A `itemRow(a,'Spülmittel')` count 0.
- **Offline then back.** `const network = await cutOff(a)` (or A's `context.setOffline(true)`) then `tick(a,'Apfelsaft')` and `addItem(a,'Eier')`: A shows both at once, `offlineIndicator(a)` count 1, B still shows Apfelsaft. `network.restore()`: within 15 s B loses Apfelsaft and shows Eier.
- **Sync indicator.** `offlineIndicator(page)` for offline (`cutOff(page)` then `restore()`), `failingIndicator(page)` for a server answering 503 (see offline.md); nothing while writes are merely held.
- Specs: `scripts/verify.sh --only e2e -- tests/live-sync.spec.ts` (also: Realtime drops, a phone that sleeps through a drop, a change made before the channel is live), `tests/partner-news.spec.ts`, `tests/list-header.spec.ts`.

## Gotchas

- The 3 s "Neu" clock runs only while the row is more than half on screen and the app is showing; a 2 s sync assertion must allow the name to end in "Neu" (regex `( Neu)?$`).
- Deletes land a second or so later on the server; allow a longer timeout than for adds.
- The bar never shows the household name or an item count (checked by the spec).
- A change from the viewer's own other session counts as theirs: only a different user's adds are news.
- Realtime joins before its database listener is live; the app resyncs when the listener is live, so an add made right after opening still appears (e2e covers it).
- Hetzner containers cannot reach host ports, so specs that need fake OIDC time out there; the sync specs above do not.
- Ordering moves of stores/categories (not items) need a connection; see offline.
