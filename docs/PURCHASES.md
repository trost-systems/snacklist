# Purchases: Snacklist Premium

Snacklist sells **Snacklist Premium** for the whole household, in two ways (Peter, Spec #4,
2026-10-31): **yearly**, an auto-renewing subscription `com.snacklist.app.yearly`, and
**Lifetime**, a one-time purchase `com.snacklist.app.lifetime`. Approved prices: EUR 24.99 a year
and EUR 149.99 Lifetime (11 Nov 2026); the stores charge EUR 9.99 / 29.99 until Ops moves them
("Expected prices" below).
Hummlist builds sell the same two as `com.hummlist.app.yearly` and `com.hummlist.app.lifetime`
until Hummlist retires (job 174); the server records both.
Both grant one entitlement, `premium`, which unlocks the integrations (MCP/AI assistants and the
API; Siri, job 184, and the Alexa skill, job 72, stay free) once the integration lock is on ("Integration lock" below, job 50; off). Nothing is
gated by it yet, and nothing is sold: the
purchase screen is behind the build define `REVENUECAT_PURCHASES` and the server switch
`premium_offer`, both off, until Peter turns them on. Built in job 25 (sandbox, our own store
verification), rebuilt in job 43 on RevenueCat, changed in job 47 for Legal Review K.11 (the SDK
starts only on a tap) and in job 49 for the yearly plan (Legal Review K.13). Decisions:
DECISIONS.md "Job 25", "Job 25b", "Job 43", "Job 47" and "Job 49".

**Model A (Peter, 2026-10-31; both products since job 49).** One member pays; the whole
household has it. A purchase
belongs to the household it was bought in, for good: it stays there when the buyer leaves, hands
the household over or deletes the account, and it never unlocks another household, also not after
its own is deleted. Nothing moves with the user. The app offers Buy only to a household it knows
has no Lifetime, so no member pays twice. Someone who paid and then joins an unlocked household is
pointed to the refund help (H-76, Peter 2026-10-31: Apple alone refunds App Store purchases;
for Google Play, Google in the first 48 hours, after that our support case by case in the Play
Console). Testers and anyone else the Lead picks (App and Play Review) get it free through a
RevenueCat promotional grant ("Free premium: RevenueCat promotional grants", "Testers"). A later subscription for running-cost features (model D) would be a second entitlement kind
next to premium ("A second entitlement" below). The yearly plan is household-bound the same way:
its renewals stay with the household it was bought for, and the same Apple ID cannot pay a second
plan of the group for another household ("Cases").

**RevenueCat (Peter, 2026-10-31 14:03; Legal Review's conditions, ADDENDUM 5).** RevenueCat
verifies purchases with Apple and Google; our server no longer talks to either store. The
RevenueCat customer was the **household** until job 185: the App User ID was the household's UUID,
never anonymous. Since job 185 new app builds use the **Snacklist user id** ("Per-user Premium"
below); a household id from an older build or an existing promotional grant still works.

## Per-user Premium (job 185)

Peter approved per-user Premium on 11 Nov 2026 (t774u): one person buys, and entitlement, restore
and lapse follow that person. Nothing is sold yet, so nothing changes for users today; the
sentences above and below that say "household" describe the household path, which stays for
older builds and for promotional grants on household customers. DECISIONS "Job 185" has the
reasons.

- **App User ID = `auth.users.id`.** Buy and Restore configure `purchases_flutter` with the
  signed-in user's id (`RevenueCatUserId` in `app/lib/purchases/purchase_repository.dart`, built
  only from the session's user). Switching households never logs in again; signing in as another
  account calls `logIn(<that user>)`. Before the SDK starts, the app calls
  `note_revenuecat_customer()`, so the server knows the account id reached RevenueCat; if that
  call fails, the tap ends as "offline" and RevenueCat is not contacted.
- **No claim.** The webhook knows the buyer: the App User ID. `POST /purchases/claim` stays for
  older builds; new builds never call it.
- **Binding.** The webhook asks `app_user_owner(app_user_id)`: a user id goes to
  `purchase_record_user`, which binds the purchase to that user (`purchases.bound_user`, set at
  the first grant, never changed, not a foreign key); a household id goes to `purchase_record` as
  before. A purchase has one owner (`purchases_one_owner`). A user-bound transaction reported
  under a household id (an old build, a `TRANSFER`) is `used_elsewhere`; a yearly plan's newer
  period still applies where it is bound. RevenueCat's "Keep with original App User ID" refuses
  the receipt under another account first.
- **What the buyer reads.** `user_entitlements`: one row per unlock, only the buyer's own rows
  (RLS `user_id = auth.uid()`), on Realtime. The app merges them with the household's
  `entitlements` rows under one rule (`Unlocks.premiumAt`, the server's `user_premium()` and
  `household_premium()`), so the buyer has Premium in every household they are in, and other
  members don't see it. Household-level answers stay household-only: the invite preview's
  "unlocked", archiving on the last leave, `leaves_unlocked`. Whether the buyer's Premium should
  also unlock shared views for their households is still open (`shared-views`).
- **Restore on a new device.** `restorePurchases()` under the same user id; RevenueCat sends the
  purchase again and `purchase_record_user` answers `restored`.
- **Lapse.** A yearly plan ends at read time as before (`user_premium()` and the app's rule): the
  row stays with its past end; the integrations pause through the gate while the lock is on. Free
  features (the list, Alexa, and later price entry, trip totals and barcode scanning) never ask
  for Premium: `integration_gate` knows only `siri`, `alexa`, `mcp` and `api`.
- **Integration gate.** `integration_gate(household, integration, user)` opens for the
  household's premium or the caller's own (`user_has_premium`); MCP and the API pass the
  caller (`_shared/premium.ts`, `Integration` is `'mcp' | 'api'`). The two-argument form stays for function deploys that still call
  it.
- **Billing notes follow the subscriber.** `my_yearly_plan()` counts the caller's own yearly plan
  in every household, so the subscriber sees its status and billing problem wherever they are,
  and the "your plan keeps billing" dialog also shows when they leave or join any household or
  delete the account (its text stays true; the copy review in NEEDS_PETER covers whether it
  should show on leaving).
- **Promotional grants to a user customer** sync into `user_entitlements`
  (`promotional_premium_sync_user`). `scripts/iap/promotional.ts` still grants households only:
  the published privacy text describes household grants.
- **Account deletion.** A trigger on `auth.users` marks the user's purchases (`user_deleted_at`;
  purged into tombstones 30 days later like a deleted household's) and queues the RevenueCat
  customer for deletion 30 days later, but only when `revenuecat_customers` says the account id
  ever reached RevenueCat (a tap, a user-bound purchase or a user grant). Every other account id
  is never sent to RevenueCat, unless Ops runs the reconcile route with it, which asks RevenueCat
  about that id and therefore notes it too.
- **Still dark.** All of it is behind `REVENUECAT_PURCHASES` and `premium_offer`, both off. Before
  either goes on, the privacy texts and the Premium page copy must say what this does
  (NEEDS_PETER "Job 185", PAYWALL_RELEASE.md step 4.5).

## How it works

1. A member opens Mehr → Snacklist Premium (`/more/lifetime`). Opening, rebuilding, leaving and
   returning to the page make no RevenueCat call and no network contact to RevenueCat, and
   neither does app start (Legal Review H-67, § 25 Abs. 2 Nr. 2 TDDDG). Opening reads the server
   switch `premium_offer()` and, only when it is on and this build sells, the two prices **from
   the store itself**, once: StoreKit 2 on iOS, Play Billing on Android
   (`app/lib/purchases/store_prices.dart`, channel `familygroceries/store_prices`; A2-5). The page
   shows each price exactly as the store formats it for the store account's country, "inkl.
   MwSt." only in euros, never a repo amount and nothing derived from the device's locale.
2. **What is offered** (`Entitlements.canOffer(Entitlement.premium, plan)`, the one decision
   point): with no premium both cards, **yearly first**; with an active yearly plan only Lifetime
   (the upgrade; never a second yearly plan, H-84); with Lifetime or a promotional grant nothing; while
   the rows load or the phone is offline nothing ("Wir prüfen, ob euer Haushalt Snacklist Premium
   schon hat …"). A plan the store doesn't return (Lifetime in BR, MX, IN) is not offered there,
   silently. No price read at all (offline, store unavailable, timeout): no Buy, "Snacklist Premium
   ist gerade nicht verfügbar." The same, with no price query, when the switch can't be read
   (offline; job 67). Switch off or `REVENUECAT_PURCHASES` off: "Snacklist Premium ist
   bald verfügbar.", no Buy, no Restore, no price query.
3. The yearly card shows the price per year and the disclosures (1 year, renews automatically
   unless cancelled at least 24 hours before the period ends, charged at confirmation and
   renewal, where to cancel); the cards are followed by Restore, the terms (Apple's standard EULA
   on iOS, a placeholder elsewhere) and the privacy policy. All copy is placeholder (K.13 /
   Snacklist PM).
4. **The tap starts the SDK.** Buy configures `purchases_flutter` with the household id as App
   User ID (`logIn(householdId)` instead when this app run configured it for another household),
   loads that plan's product by id (`getProducts`, `ProductCategory.subscription` for yearly,
   `nonSubscription` for Lifetime; Play names the subscription `com.snacklist.app.yearly:yearly`)
   and opens the store's sheet. Restore configures (or logs in) the same way, then calls
   `restorePurchases()`. After a tap the SDK stays configured for the rest of that app run; the
   next app start configures nothing until the next tap. RevenueCat verifies the purchase with the
   store, acknowledges Play purchases and finishes the transaction. The app then **claims** it:
   `POST /functions/v1/purchases/claim` with its own session and `{householdId, store,
   transactionId}`, pinned to `eu-central-1`. The claim records the buyer (H-55) if they were a
   member of that household when buying (job 47); it never unlocks anything. Until Supabase shows
   the unlock (for Lifetime: the Lifetime row, also next to a running yearly plan), the page says
   "Wird freigeschaltet …".
5. **Lifetime while a yearly plan renews** (H-84): Buy Lifetime first shows Legal Review's
   warning, „Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird
   weiter abgerechnet, bis es gekündigt wird; …“ (the subscriber's variant: „Du kannst es unter
   [Abo verwalten] kündigen.“), with „Trotzdem kaufen“ · „Abbrechen“. The SDK starts only on
   „Trotzdem kaufen“. After the purchase the page keeps that text with the store link while the
   plan renews. Snacklist never cancels or refunds the plan.
6. RevenueCat calls our webhook (`POST /functions/v1/purchases/revenuecat/webhook`, the
   `purchases` function): INITIAL_PURCHASE / NON_RENEWING_PURCHASE record the purchase for the
   household `app_user_id` names (`purchase_record`), the yearly plan with its end; RENEWAL and
   the lifecycle events keep the plan's state ("Subscription lifecycle" below).
7. Every member's app reads the household's `entitlements` rows (RLS: members only; who paid or
   granted is not readable, H-55) and hears inserts, updates and deletes over Realtime. Premium is
   active **at read time**: a Lifetime row (no end), a promotional row without end, else
   a yearly or promotional row whose end lies ahead. The page's status line: „Snacklist Premium
   aktiv (jährlich, verlängert sich am …)“, „… läuft am … aus“ (auto-renew off), „Snacklist Premium
   Lifetime“, „Snacklist Premium geschenkt (bis …)“
   (promotional; placeholder copy for K.13). The server's check for the integrations is `household_has_premium()`
   (same rule).
8. While the household has an active yearly plan the page shows „Abo verwalten oder kündigen“
   (StoreKit's manage sheet on iOS, Play's subscription page on Android, a line with both pages on
   the web). Only the subscriber sees a failed renewal: „Apple bzw. Google konnten dein Jahresabo
   nicht abbuchen. Premium läuft noch bis {date}. …“ (`my_yearly_plan()`, H-87).
9. Before deleting the account, joining another household (leave, delete or archive the current
   one) or re-enabling an archived one, the subscriber of a renewing plan reads „Dein Jahresabo
   für Snacklist Premium läuft weiter und wird über dein Apple- bzw. Google-Konto abgerechnet, bis
   du es kündigst. Löschen oder Verlassen kündigt es nicht.“ with „Abo verwalten“ · „Trotzdem
   fortfahren“ (account deletion also for a plan they pay for another household); other members
   of a billed household the placeholder line „Ein Jahresabo für diesen Haushalt läuft weiter,
   bis es gekündigt wird.“ (H-85).
10. Refunds revoke one purchase's unlock (`purchase_revoke`) and send `purchase_refunded` once;
    `REFUND_REVERSED` reinstates it in its own household. A `TRANSFER` never moves anything.
11. Restore (Kauf wiederherstellen) calls `restorePurchases()` under the household's App User ID.
    It counts only what RevenueCat says is active now, by product (`entitlements.active`): a
    lapsed yearly plan or a refunded Lifetime is "nothing to restore", not an unlock to wait for
    (job 67). On Play, Buy takes the yearly base plan's own option, never RevenueCat's default,
    which would pick a trial or intro offer the page doesn't show.
    With the project's restore behavior **Keep with original App User ID** (an Ops setting),
    RevenueCat refuses a purchase that belongs to another household; the app says "Dieser Kauf
    gehört zu einem anderen, früheren Haushalt und bleibt dort." with the refund help. The server
    refuses it too (`purchase_record`: bound household, tombstones).

| Case | What happens |
| --- | --- |
| Double tap on Buy, app killed mid-purchase | RevenueCat owns the transaction and finishes it; its webhook records it. A claim lost with a killed app leaves the buyer unknown: the unlock stands, `purchase_completed` is not sent (analytics undercount) |
| Restore on a new phone or the partner's phone | Household already unlocked: shown at once, no Buy, no Restore (nothing to restore) |
| The same purchase in another household (restore, re-buy, a RevenueCat `TRANSFER`) | Refused by RevenueCat (Keep with original App User ID) and by `purchase_record` (`used_elsewhere`): one household per purchase, for good. "Dieser Kauf gehört zu einem anderen, früheren Haushalt und bleibt dort." and the refund help link |
| Restore after its household was deleted | Refused (`used_elsewhere` with `household_gone`; after the 30-day purge `tombstoned`). Nothing unlocks anywhere else (H-56) |
| A second purchase in an unlocked household (two phones, Ask to Buy, a race) | Its own row; refunding one keeps the other's unlock. Every member's page then shows "Euer Haushalt hat Snacklist Lifetime mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen." with the refund help |
| Buyer switches households between buying and claiming | The claim names the household the purchase was made for (job 47), not the one the buyer is in now. `purchase_claim` records the buyer if they were a member of it at the purchase time: a member now who joined before it, or one who left it in the last hour (`household_departures`, kept one hour) after joining before it. Otherwise (left more than an hour ago, joined after the purchase, never a member, or the household is gone) it answers 403 `no_household` and the buyer stays unknown (no `purchase_completed`); the unlock stands where it was bought |
| Ask to Buy, Play pending payment | "Wartet auf Bestätigung"; RevenueCat's webhook records it when the store completes it, and the note goes once the unlock arrives |
| A purchase or restore ends after the member switched households | The purchase is the user's (job 185): the unlock it waits for follows them into the household they switched to, also after they left their last household and started or joined another (job 211), so Buy stays off there until it arrives. Another account signed in on the device starts with nothing pending. Before job 185 the claim named the household bought for and the new household's page showed nothing of it (job 67) |
| The plan ends while the app is open, also offline | The end-of-plan timer, and every return to the foreground, compute premium again from the last rows: the page offers the plans again, MCP and the API lock at the server (job 67) |
| Products not loadable, offline, store down | Before the tap (no price read): no Buy, "Snacklist Premium ist gerade nicht verfügbar.". After the tap: the same line or the offline note; Buy stays and tries again; no crash |
| Yearly-only storefront (BR, MX, IN) | The store returns no Lifetime: no Lifetime card and no Lifetime entry (warning, upgrade); the yearly card as usual. Lifetime holders and granted households there keep Premium |
| The same Apple ID already pays the yearly plan for household A, and the person tries to buy or restore it in household B (iOS) | Apple allows one subscription per Apple ID per group, and RevenueCat (Keep with original App User ID) keeps the receipt with A: the store or RevenueCat refuses (`receiptAlreadyInUse`), the app says "Dieser Kauf gehört zu einem anderen, früheren Haushalt und bleibt dort." and "Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo für einen anderen Haushalt. Jemand anderes aus diesem Haushalt kann Snacklist Premium abschließen." The restore setting stays |
| Two yearly plans in one household (two members' store accounts, a race) | Both rows kept, never merged; premium runs to the later end; the page says so with the manage link; the function logs `second_yearly` |
| Yearly plan cancelled (auto-renew off) | Premium stays until the period's end, the status says "läuft am … aus"; EXPIRATION ends it |
| Yearly plan lapsed | Premium off at read time; the paywall offers both plans again. Nothing is deleted: household, list, Alexa links, tokens, MCP grants stay (integrations are paused by job 50's gate). The row stays with its past end |
| Billing problem | Premium until the grace period's end (RevenueCat's `grace_period_expiration_at_ms`), else the period's end; only the subscriber is told. Google's account hold: EXPIRATION, premium off until a RENEWAL |
| Lifetime bought while yearly renews | Both rows; Lifetime wins; the yearly plan keeps renewing until its subscriber cancels it; when it expires premium stays |
| Archived household with a yearly plan | Archiving works as for Lifetime; the plan is still billed; at its end premium stops, the archive stays |
| Payer leaves the household, hands it over or deletes the account | The unlock stays with the household. Account deletion removes the buyer link; the purchase keeps its household (`bound_household`) |
| Last member leaves an unlocked household (joins another) | Joining asks first. With `HOUSEHOLD_ARCHIVE` on: "Archivieren und beitreten" keeps the household archived (list and unlock kept, re-enabled under Mehr → Archivierte Haushalte, deleted 24 months after archiving otherwise); "Löschen und beitreten" asks once more ("… Snacklist Lifetime endet mit ihm, denn ein Kauf gehört zu seinem Haushalt …", refund help). With it off (releases, until the legal texts say so): that warning and "Trotzdem beitreten". Never blocked. The server archives only while its switch `household_archive` is on (job 47, H-70); off, an archiving call is refused with `archive_disabled` and changes nothing, and the app says "Archivieren ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist." |
| Joiner into an unlocked household | The join screen says "Dieser Haushalt hat Snacklist Lifetime. Du musst nichts kaufen." With their own purchase from the last 30 days that stands: a link to the refund help |
| Promotional grant (RevenueCat dashboard) | Premium for the whole household until the grant's end (none: for good); nothing to buy, no Buy shown. Revoked or ended at RevenueCat: the row is deleted, premium ends at once. No `purchases` row, no analytics event |
| Tester | Their household gets a RevenueCat promotional grant until 2100 (`scripts/iap/promotional.ts grant`, "Testers"); it stays with that household like a purchase. Internal for analytics |
| Archived household | No members, not readable by anyone, its invites lead nowhere; the archiving user alone sees and re-enables it (`archived_households`, `unarchive_household`), with "Wird am <Datum> gelöscht" per household. Deleted 24 months after archiving unless re-enabled (job 47, H-50), and at once with that user's account. Its purchases restore nowhere else, and in it again after re-enabling; re-enabling and archiving again start a new 24 months. Re-enabling works with the server switch off, unless it would archive the household the user leaves |
| Family Sharing | Off at Apple; a webhook event with `is_family_share` is ignored |
| An App User ID that is no household (anonymous, unknown) | Ignored: nothing recorded, nothing unlocked |
| Web | No buy button and no external purchase link; "Snacklist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet." and the status; with a yearly plan a line with the App Store and Google Play subscription pages |
| `REVENUECAT_PURCHASES` off (every build until Peter's OK) or no SDK key, or `premium_offer` off | "Snacklist Premium ist bald verfügbar.", no Buy, no Restore, no store price query; unlocks (testers) still show |
| Signed out, no household | The page is under More, which `authRedirect` only lets households reach; the claim route answers 401/403 |

## The webhook

`supabase/functions/purchases/handler.ts`. Routes match exactly (after the gateway's
`/functions/v1`; a trailing slash is ignored): `/purchases/revenuecat/webhooks`,
`/x/purchases/revenuecat/webhook` and other near misses are 404 (`handler_test.ts`, `routes`).

| Route | Caller | What it does |
| --- | --- | --- |
| `GET /purchases` | smoke checks | `{configured}` |
| `POST /purchases/revenuecat/webhook` | RevenueCat | The webhook (above). `Authorization` must equal `REVENUECAT_WEBHOOK_AUTH` whole (it includes `Bearer `). 401 without the right `Authorization` (or, with `REVENUECAT_WEBHOOK_HMAC_SECRET`, a bad or stale `X-RevenueCat-Webhook-Signature`: `t=…,v1=…`, HMAC-SHA256 over `"<t>.<raw body>"`, 5 minutes). 200 for everything it processed or ignores, 500 when the database fails and 503 `not_recorded_yet` for a recent lifecycle event that came before its purchase, so RevenueCat retries (5 times over about 80 minutes). The event id is stored in the same transaction as the writes |
| `POST /purchases/revenuecat/deletions` | the daily workflow | Deletes due RevenueCat customers ("Retention"); at most 25 per run, each customer at most once an hour. Needs `x-deletions-secret` equal to `REVENUECAT_DELETIONS_SECRET` (constant-time compare): 401 without or with a wrong one, 503 `not_configured` while the secret is unset (fail closed; job 47) |
| `POST /purchases/revenuecat/reconcile` | Ops (`scripts/iap/promotional.ts reconcile --apply`) | Reads one household's promotional grants at RevenueCat and stores the result, as the webhook does ("Free premium"). Body `{householdId}` (a UUID, else 400). Same `x-deletions-secret` as the deletion route (401 wrong, 503 unset). `{status}`: `granted`, `updated`, `unchanged`, `removed`, `no_household`; 502 `revenuecat_unavailable` when RevenueCat doesn't answer; 503 without `REVENUECAT_SECRET_KEY`/`REVENUECAT_PROJECT_ID` |
| `POST /purchases/claim` | the app, signed in | Records the buyer of a transaction in the household it names (`householdId`, the purchase's App User ID), for a member of it at the purchase time (first member wins); 20 a minute per user |
| `POST /purchases/test/event` | local stack only (404 elsewhere) | Builds a RevenueCat event and processes it like the webhook, without the secret: the debug fake store, fg and e2e use it |

Products (`productOf` in `supabase/functions/purchases/types.ts`, pinned to
`scripts/iap/product.ts`): `com.snacklist.app.yearly` and Play's `com.snacklist.app.yearly:yearly`
(stored as the bare id) are the yearly plan, `com.snacklist.app.lifetime` is Lifetime, all of kind
`premium`. Hummlist's `com.hummlist.app.yearly`, `com.hummlist.app.yearly:yearly` and
`com.hummlist.app.lifetime` count the same way, each stored under its own id (`hummlistProductIds`); any other product id (another base plan included) is acknowledged and ignored. For
store purchases the event's `entitlement_ids` is not read: `premium` and the old `lifetime` both
work. Stores: `APP_STORE` is `apple`, `PLAY_STORE` `google`, `PROMOTIONAL` the promotional grants
("Free premium"); others are ignored. The purchase's key is
`original_transaction_id` (`transaction_id` when absent); the claim may name either.

### Subscription lifecycle

RevenueCat's event types and fields:
https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields (read 2026-11-01).
Every event carries `event_timestamp_ms`; a yearly row keeps the newest one applied (`state_at`),
and an older event changes nothing (`stale`). Lifecycle events for a transaction never recorded
write nothing (`unknown`). Younger than 2 hours, such an event is answered 503
`not_recorded_yet` and its id is not stored, so RevenueCat delivers it again once its
INITIAL_PURCHASE may have arrived; older, 200 `unknown` (job 67). While a billing problem is
open, an event that says nothing about billing (the `CANCELLATION` with `BILLING_ERROR` that
RevenueCat sends next to `BILLING_ISSUE`, in either order) never moves the end earlier, so the
grace period holds (job 67).

| Event | Yearly plan | Lifetime |
| --- | --- | --- |
| `INITIAL_PURCHASE`, `NON_RENEWING_PURCHASE` | Record and bind (H-56); end = `expiration_at_ms`, renews | Record and bind |
| `RENEWAL` | Same transaction: new end, renews, billing problem cleared (also "a lapsed user resubscribed" on Apple). A new transaction (Google resubscribe: new purchase token) is a new row in the same household only. Never a second `purchase_completed` | (as a record) |
| `CANCELLATION`, refund (see below) | Revoke this row (other rows stay), `purchase_refunded` | Revoke, `purchase_refunded` |
| `CANCELLATION`, not a refund | Auto-renew off; premium stays until the end | (every cancellation is a refund) |
| `UNCANCELLATION` | Auto-renew on | nothing |
| `BILLING_ISSUE` | Billing problem open; end = `grace_period_expiration_at_ms`, else `expiration_at_ms` | nothing |
| `EXPIRATION` | End = the reported end, at the latest the event's time; auto-renew off; premium ends at read time; nothing deleted | nothing |
| `SUBSCRIPTION_EXTENDED` | New end | nothing |
| `SUBSCRIPTION_PAUSED` (Google) | Auto-renew off, premium to the end; `EXPIRATION` (reason SUBSCRIPTION_PAUSED) ends it; a resume is a `RENEWAL` | nothing |
| `REFUND_REVERSED` | Reinstate with the stored state | Reinstate |
| `PRODUCT_CHANGE` | Logged by type; the following `RENEWAL` carries the new product, which maps to premium | logged |
| `TRANSFER` | Logged by type, nothing moves (H-56). A later `RENEWAL` under the other App User ID is refused there (`used_elsewhere`) and renews the plan in its own household (job 67) | same |
| `TEMPORARY_ENTITLEMENT_GRANT`, `TEST`, others | 200, no write | same |

Events with `store` `PROMOTIONAL` don't follow this table; see "Free premium".

A `RENEWAL` newer than a refund of the same yearly transaction, in its own household, lifts the
refund (RevenueCat: a subscription refund covers the latest period, and auto-renew may stay on).

### cancel_reason

Read in flight, never stored or logged (H-87). Legal Review K.13 (A2-1, H-81): a cancellation
never ends a paid period; only a refund revokes at once.

| `cancel_reason` | Yearly plan | Lifetime |
| --- | --- | --- |
| `UNSUBSCRIBE` | Auto-renew off; premium until `expires_at`, then `EXPIRATION` ends it | Revoke (refund) |
| `BILLING_ERROR` | Auto-renew off; premium until `expires_at` | Revoke |
| `DEVELOPER_INITIATED` | Auto-renew off; premium until `expires_at` | Revoke |
| `PRICE_INCREASE` | Auto-renew off; premium until `expires_at` | Revoke |
| `UNKNOWN` (App Store only: "Apple did not provide the reason") | Auto-renew off, unless the event carries a negative `price`, which RevenueCat uses for refunds: then revoke | Revoke |
| `CUSTOMER_SUPPORT` (a refund) | Revoke | Revoke |
| missing | Auto-renew off | Revoke |

**Analytics.** `purchase_completed` goes out once per purchase, when both the webhook's record
and the buyer's claim are in (whichever comes second), under the buyer's consent;
`purchase_refunded` on a refund of a purchase with a known buyer. Both carry `product_id` and
`premium_source` (`yearly` | `lifetime`). A renewal sends nothing. Without a claim, or without consent, nothing is sent (the paying
share is a lower bound, docs/ANALYTICS.md). Sandbox purchases and purchases in households with a
promotional grant (testers, reviewers) are `is_internal`. `purchase_restored` is not sent: a RevenueCat
restore produces no event for us, and no production code sends it (the job 25 helper
`recordPurchase` in `_shared/purchases.ts`, which could, has no caller but its test; checked in job
47).

### Free premium: RevenueCat promotional grants

Free Snacklist Premium for a household (App and Play Review, a partner, a support case) is a
RevenueCat **promotional grant** of the entitlement `premium`, made by the Lead in RevenueCat; no
code, no SQL, no fake purchase. RevenueCat documents it at
https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile#granting-promotional-entitlements
(read 2026-11-01).

1. Find the household id (Supabase, `households.id`). It is the RevenueCat App User ID.
2. RevenueCat → Snacklist → Customers → search the household id. No customer yet (nobody in it
   opened Buy or Restore): create it there; the grant then makes it a customer (API v2:
   `POST /v2/projects/{project_id}/customers/{household_id}/actions/grant_entitlement`).
3. Entitlements → **Grant**: entitlement `premium`, a duration or an end date (an end in 2100 for
   "for good"). Revoking it there ends premium again.
4. RevenueCat sends the webhook an event with `store` `PROMOTIONAL` (granting:
   `NON_RENEWING_PURCHASE`; revoking or ending: `CANCELLATION` / `EXPIRATION`). The function
   doesn't trust its fields: for the household (a UUID App User ID; anything else is ignored) and
   only when `entitlement_ids` names `premium` (or is missing), it reads the customer's
   subscriptions from API v2 (`GET …/customers/{household_id}/subscriptions`), keeps the
   promotional ones that give access to `premium` now, and writes the result under the household's
   lock in the event's transaction (`promotional_premium_sync`): one `entitlements` row,
   `source` and `premium_source` `promotional`, `expires_at` the latest end (null: no end). No
   grant left: the row is deleted. RevenueCat unreachable: 502, the event id is not kept and
   RevenueCat retries.
5. Check: Mehr → Snacklist Premium shows „Snacklist Premium geschenkt …“, and
   `select public.household_has_premium('<household id>');` (service role) is true. A grant made
   before this existed, or a webhook that never arrived:
   `deno run --allow-env --allow-net --allow-read scripts/iap/promotional.ts reconcile --household <id> [--apply]`
   (dry run: what RevenueCat grants; `--apply`: the reconcile route stores it).

The row ends at read time too: the app and `household_premium` treat a promotional row with a past
end as no premium, before RevenueCat's `EXPIRATION` deletes it. Apps from before this change read
`premium_source` `promotional` as Lifetime (unlocked, no Buy); RevenueCat ending the grant deletes
the row, so they lose it then.

### Who receives what (Legal Review H-53)

Our server calls neither Apple nor Google. The recipient is **RevenueCat, Inc.** (processor under
its DPA, part of RevenueCat's terms, https://www.revenuecat.com/dpa/; SCCs module 2 for EEA
transfers). The app's `purchases_flutter` SDK talks to RevenueCat (`api.revenuecat.com`), and
RevenueCat talks to Apple (App Store Server API with the In-App Purchase key) and Google (Play
Developer API through a service account; real-time developer notifications).

Data RevenueCat receives (only after a tap on Buy or Restore, job 47): the household UUID as App
User ID (what reaches Apple and Google: "What Apple and Google receive" below), store transaction ids and the Play purchase token,
product id, price, currency, storefront or country code, purchase and refund dates, sandbox or
production, platform, app and SDK version, the device locale, and the requesting IP address
(network level). No e-mail, no name, no Supabase user id, no list or household content; the app
sets no customer attributes and collects no advertising or device identifiers (enforced by the
lint rules `purchases-flutter-only-in-revenuecat-repository` and `no-revenuecat-customer-data`). RevenueCat states customer
data "is sent to AWS data centers located in the United States" (https://www.revenuecat.com/privacy/);
the DPA's subprocessors are all in the USA (AWS, Google, Snowflake, ScyllaDB, ClickHouse, Elastic,
Sentry, Honeycomb, Cloudflare, Fastly, Hex, OpenAI, Anthropic); the docs name no EU hosting
option. RevenueCat AI features stay off (an Ops setting, C4). These are facts with sources; the
legal assessment is Legal Review's.

**Promotional grants** ("Free premium") add: the Lead creates a RevenueCat customer for the
household UUID and grants `premium` with an end date, also for a household nobody in which ever
tapped Buy or Restore; RevenueCat then sends our webhook an event for it (household UUID, event
type and id, `store` `PROMOTIONAL`, the entitlement, dates), and the function asks RevenueCat for
that customer's subscriptions (store, whether it gives access, start and end, entitlements). We
store from it only the household's `entitlements` row (household, kind, source, end, when granted)
and the event id and type (90 days). No user id, e-mail or name goes to RevenueCat for it.

### What Apple and Google receive (Legal Review H-68)

SDK facts checked for purchases_flutter 11.0.0 (the version `app/pubspec.lock` locks), on
2026-10-31, from the source at the exact tags; `scripts/iap/sdk_version_test.ts` fails when the
locked version changes until this section is checked again.

- **Versions.** purchases_flutter 11.0.0 pins purchases-hybrid-common **20.0.0**
  (`ios/purchases_flutter.podspec` and `Package.swift`: `exact: "20.0.0"`; `android/build.gradle`:
  `common_version = '20.0.0'`). That pins **purchases-ios 5.99.0**
  ([PurchasesHybridCommon.podspec](https://github.com/RevenueCat/purchases-hybrid-common/blob/20.0.0/PurchasesHybridCommon.podspec#L18),
  [Package.swift](https://github.com/RevenueCat/purchases-hybrid-common/blob/20.0.0/Package.swift#L25))
  and **purchases-android 11.0.0**
  ([libs.versions.toml](https://github.com/RevenueCat/purchases-hybrid-common/blob/20.0.0/android/gradle/libs.versions.toml#L11)).
- **Apple, StoreKit 2** (the SDK's default, `StoreKitVersion.default = .storeKit2`,
  [StoreKitVersion.swift#L36](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Misc/StoreKitVersion.swift#L36);
  used on iOS 16 and later,
  [#L55](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Misc/StoreKitVersion.swift#L55);
  the app sets no StoreKit version): when the App User ID parses as a UUID, every purchase gets
  `Product.PurchaseOption.appAccountToken(uuid)`
  ([PurchasesOrchestrator.swift#L846-L849](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Purchasing/Purchases/PurchasesOrchestrator.swift#L846-L849)).
  Our App User ID is the household UUID, so **Apple receives the household id as the
  transaction's `appAccountToken`**.
- **Apple, StoreKit 1** (iOS 15 only; since job 97 the app needs iOS 17, so no purchase takes
  this path any more; kept for the record): the SDK
  sets `SKMutablePayment.applicationUsername = appUserID` for every purchase, UUID or not
  ([PurchasesOrchestrator.swift#L661](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Purchasing/Purchases/PurchasesOrchestrator.swift#L661)).
  Apple receives the household id there too. (Apple's documentation says a UUID
  `applicationUsername` also appears as the transaction's `appAccountToken`; that is Apple's
  statement, not read from source.)
- **Google**: a one-time product's `BillingFlowParams` always get
  `setObfuscatedAccountId(appUserID.sha256())`
  ([BillingWrapper.kt#L1031](https://github.com/RevenueCat/purchases-android/blob/11.0.0/purchases/src/main/kotlin/com/revenuecat/purchases/google/BillingWrapper.kt#L1031)),
  where `sha256()` is the Base64 of the unsalted SHA-256 of the id's bytes
  ([utils.kt#L33-L37](https://github.com/RevenueCat/purchases-android/blob/11.0.0/purchases/src/main/kotlin/com/revenuecat/purchases/common/utils.kt#L33-L37)).
  **Google receives a hash of the household id**, not the id. `setObfuscatedProfileId` is never
  called in purchases-android 11.0.0 (no occurrence in the source).
- So draft 5a's sentence ("gibt RevenueCat beim Kauf die Kennung deines Haushalts an Apple
  weiter bzw. einen daraus gebildeten Hashwert an Google") matches the source. Two details for
  Legal Review (NEEDS_LEAD "Job 47"): the hash is unsalted (anyone who knows the household id can
  compute it), and a restore sends neither (it reads existing transactions).

### What the SDK keeps on the device (Legal Review H-73)

Written only after a tap on Buy or Restore (job 47); before, the SDK is never configured. SDK facts
checked for purchases_flutter 11.0.0, as above.

- **iOS** (purchases-ios 5.99.0): the UserDefaults suite `com.revenuecat.user_defaults`
  ([UserDefaults+Extensions.swift#L30](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/FoundationExtensions/UserDefaults+Extensions.swift#L30))
  with the App User ID (`com.revenuecat.userdefaults.appUserID.new`), the household's
  CustomerInfo JSON (`…purchaserInfo.<household id>`: purchased product ids, transaction ids,
  purchase dates, first seen, entitlements) and its timestamp, the product-to-entitlement mapping,
  and, unused by us, subscriber attributes and attribution keys
  ([DeviceCache.swift#L622-L656](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Caching/DeviceCache.swift#L622-L656));
  the offerings response in files under the app's `RevenueCat/device-cache` directory
  ([DeviceCache.swift#L54](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Caching/DeviceCache.swift#L54)).
- **Android** (purchases-android 11.0.0): the SharedPreferences file
  `com_revenuecat_purchases_preferences`
  ([RevenueCatBackupAgent.kt#L33](https://github.com/RevenueCat/purchases-android/blob/11.0.0/purchases/src/main/kotlin/com/revenuecat/purchases/backup/RevenueCatBackupAgent.kt#L33))
  with keys `com.revenuecat.purchases.<api key>…`: the App User ID (`.new`), CustomerInfo per user
  and its timestamp, SHA-1 hashes of sent purchase tokens (`.tokensV2`), the storefront country,
  the product-to-entitlement mapping and the offerings response (a file)
  ([DeviceCache.kt#L75-L147](https://github.com/RevenueCat/purchases-android/blob/11.0.0/purchases/src/main/kotlin/com/revenuecat/purchases/common/caching/DeviceCache.kt#L75-L147)).
  The app declares no `android:allowBackup`, so Android's Auto Backup may copy this file (like
  the app's other SharedPreferences) to the user's Google backup (NEEDS_LEAD "Job 47").
- **How long.** CustomerInfo counts as fresh for 5 minutes in the foreground and 25 hours in the
  background, the entitlement mapping 25 hours
  ([iOS DeviceCache.swift#L976-L986](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Caching/DeviceCache.swift#L976-L986),
  [Android DateExtensions.kt#L15-L16](https://github.com/RevenueCat/purchases-android/blob/11.0.0/purchases/src/main/kotlin/com/revenuecat/purchases/common/caching/DateExtensions.kt#L15-L16)).
  Stale entries are refreshed, not deleted: everything stays until the SDK switches to another
  App User ID (a Buy or Restore for another household, which clears the old household's
  CustomerInfo and offerings,
  [DeviceCache.swift#L129-L149](https://github.com/RevenueCat/purchases-ios/blob/5.99.0/Sources/Caching/DeviceCache.swift#L129-L149)),
  `logOut`, or uninstalling the app.
- **Device identifiers.** The app configures with `automaticDeviceIdentifierCollectionEnabled =
  false` and diagnostics off (`revenuecat_repository_test.dart` checks both) and calls no
  `collectDeviceIdentifiers` or attribute setter (lint `no-revenuecat-customer-data`).
- **Sign-out and account deletion (DECISIONS 47.6).** The app calls nothing at RevenueCat:
  `logOut` would create an anonymous RevenueCat customer and contact RevenueCat (forbidden, C3),
  and the SDK has no other call that clears its storage. The household id and its CustomerInfo
  stay on that device until one of the events above. A deleted household's customer is deleted at
  RevenueCat 30 days later ("Retention"); the copy on the device is not.

The calls our server makes to RevenueCat: `DELETE https://api.revenuecat.com/v2/projects/{project_id}/customers/{household_id}`
and the `GET` that confirms it (404), for deleted households ("Retention"; API v2,
https://www.revenuecat.com/docs/api-v2/customer, read 2026-10-31), and
`GET …/customers/{household_id}/subscriptions` for a household a promotional event or the
reconcile route names ("Free premium").

### Where it runs (Legal Review H-54)

Edge Functions run in the region nearest the caller unless pinned (Supabase "Regional
Invocations", https://supabase.com/docs/guides/functions/regional-invocation, read 2026-10-31).
RevenueCat calls from the US and can't set the `x-region` header, so the webhook URL Ops
registers carries the query parameter:
`https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases/revenuecat/webhook?forceFunctionRegion=eu-central-1`
(`eu-central-1` is Frankfurt, the project's region). The app's claim call passes
`region: 'eu-central-1'` (`x-region` header and the same parameter). The function logs `SB_REGION`
once per request, nothing else from it. A pinned call is not rerouted during a regional outage;
RevenueCat retries, the app retries the claim.

## Data

| Table | Who reads | Who writes | Rows |
| --- | --- | --- | --- |
| `purchases` | service connection | `purchase_record`, `purchase_lifecycle`, `purchase_claim`, `purchase_revoke`, `purchase_reinstate` | store, transaction id (the original), latest transaction id, its HMAC, product, kind (`premium`), plan (`yearly`/`lifetime`), environment, buyer (from the claim; null after their deletion), bound household or, since job 185, bound user (one of them, set at the first record, never changed), when the bound user's account was deleted, purchased/verified/revoked at, price, currency, country, when `purchase_completed` went out, when the household was deleted; yearly: end (`expires_at`), renews (`auto_renew`), billing problem open (`billing_issue`), newest event applied (`state_at`). No cancel or expiry reasons, no per-renewal rows (H-87) |
| `entitlements` | household members (RLS, column grants: `id, purchase_id, household_id, kind, source, product_id, store, environment, granted_at, premium_source, expires_at, auto_renew`), Realtime (insert, update, delete) | `purchase_entitlement_sync` (from `purchase_record`, `purchase_lifecycle`, `purchase_reinstate`), `purchase_revoke` (delete), `promotional_premium_sync` (the webhook and the reconcile route: insert, update, delete) | one row per unlock: a purchase's (`source` purchase) or the household's RevenueCat promotional grant (`source` promotional, at most one per household, no store, product or environment; testers' too); kind; `premium_source` (`yearly`, `lifetime`, `promotional`); yearly and promotional: the end (promotional: null for none); yearly: whether it renews; granted by (not member-readable) |
| `user_entitlements` | the user themselves (RLS `user_id = auth.uid()`, column grants: `id, user_id, kind, source, premium_source, expires_at, auto_renew, granted_at`), Realtime | `purchase_entitlement_sync` for user-bound purchases, `purchase_revoke` (delete), `promotional_premium_sync_user` | job 185: one row per unlock of a user (a user-bound purchase, or the user customer's promotional grant, at most one); the same kinds and sources as `entitlements` |
| `revenuecat_customers` | service connection | `note_revenuecat_customer()` (the app, before Buy or Restore starts the SDK), `purchase_record_user`, `promotional_premium_sync_user` | job 185: account ids that reached RevenueCat; read and deleted by the account-deletion trigger. A note, and `purchase_record_user` and `promotional_premium_sync_user` before they write, take a key share lock on the account (`revenuecat_account_hold`), so they and the account's deletion run one after the other (`delete_account` takes `purchase_user_lock` first, as the webhook does, so the two never wait on each other in a cycle); for an account deleted meanwhile they queue it in `revenuecat_deletions` instead (job 211) |
| `revenuecat_households` | service connection | `purchase_record` and `promotional_premium_sync` (the webhook and the reconcile route), holding the household's row lock | job 211: household ids RevenueCat reported a purchase or a promotional grant for; read and deleted by the household-deletion trigger |
| `purchase_claims` | service connection | `purchase_claim`, `purchase_record` | a claim waiting for its webhook: store, transaction id, claimant, their household, when (30 days at most) |
| `revenuecat_events` | service connection | the webhook | processed event ids and types, 90 days |
| `purchase_tombstones` | service connection | `purge_purchases` | HMAC-SHA256 of purged store transaction ids under `REVENUECAT_TOMBSTONE_HMAC_KEY`, nothing else |
| `revenuecat_deletions` | service connection | trigger on household deletion (only households in `revenuecat_households`, job 211), trigger on account deletion (only accounts in `revenuecat_customers`, job 185), `revenuecat_deletions_take`/`_done` (the deletion route) | deleted households' and accounts' ids (RevenueCat App User IDs), due 30 days later |
| `households.archived_at`, `archived_by` | nobody but `archived_households()` for the archiving user (with `deletes_at`, 24 months later) | `leave_current_household(true)`, `accept_invite(code, true)`, `unarchive_household` (archiving only while `household_archive` is on) | when and by whom the last member archived it |
| `app_switches` | service connection (`app_switch(key)` for the functions); members only through `premium_offer()` | the Lead, with the service role | server switches; `household_archive` (seeded off) allows archiving; `premium_offer` (seeded off, job 49) lets the app offer Snacklist Premium |
| `household_departures` | service connection (`was_member_at`) | trigger on leaving a household | household, user, joined and left at; one hour, for the buyer's claim |
| `purchase_rate` | service connection | `purchase_take_call` | per-user window for claims |

Functions for others to call: `household_premium(household)` (source and end) and
`household_has_premium(household)`, server-only, the check the integrations use (job 50);
`household_internal(household)`, server-only, whether its purchases are internal (a promotional
grant);
`my_yearly_plan()` (members: the caller's own subscriber facts) and `premium_offer()` (members:
the switch).

Migrations `20261030190000_purchases.sql`, `20261031123504_household_bound_lifetime.sql`,
`20261031194500_purchase_legal_fixes.sql`, `20261031214500_premium_yearly.sql`,
`20261101143000_revenuecat_promotional.sql`, `20261101150000_testers_via_revenuecat.sql` and `20261112232617_per_user_premium.sql` (job 185); pgTAP `supabase/tests/purchases.test.sql`,
`household_bound.test.sql`, `purchase_legal_fixes.test.sql`, `premium_yearly.test.sql` and
`revenuecat_promotional.test.sql`, `per_user_premium.test.sql`; the data map
`docs/PRIVACY_DATA_MAP.md`. `export_my_data` has `purchases` (with `belongs_to_household`) and
`archived_households` sections (the `lifetime_tester` section went with the tester list).

### Retention

- **Household deleted** (its last member left without archiving, or deleted their account): its
  unlock rows go at once (cascade). Its purchase rows are kept 30 days (support and refund window),
  then `purge_purchases` (pg_cron, daily 03:41) deletes them and keeps only each transaction's
  HMAC in `purchase_tombstones`, so the purchase never binds to a household again. If RevenueCat
  reported the household (a purchase or a promotional grant under its id, `revenuecat_households`),
  its RevenueCat customer is queued in `revenuecat_deletions` and deleted by the function
  (`purchases/deletions.ts`, started daily by `.github/workflows/revenuecat-delete.yml`): API v2
  `DELETE` then a `GET` that must answer 404, retried at most hourly until it does; logs counts
  only; does nothing while `REVENUECAT_SECRET_KEY` or `REVENUECAT_PROJECT_ID` is unset. A failure opens the issue "RevenueCat customer deletion
  failed"; rerun the workflow once RevenueCat answers.
- **Tombstones** are kept while Snacklist Lifetime is sold or its unlocks are honoured, reviewed
  yearly (NEEDS_LEAD Job 43). One HMAC key for all of them (`REVENUECAT_TOMBSTONE_HMAC_KEY`):
  changing it would make the old tombstones useless.
- **Buyer deletes their account:** the buyer link is nulled (`purchases.user_id`,
  `entitlements.granted_by`); the household keeps its unlock. For a user-bound purchase (job 185)
  the user's `user_entitlements` rows go at once, the purchase rows 30 days later into tombstones,
  and the RevenueCat customer (the user id) is deleted 30 days later if the id ever reached
  RevenueCat (`revenuecat_customers`). An account whose id never reached RevenueCat is never sent
  there.
- **Promotional rows** live while RevenueCat grants premium: deleted when the grant ends or is
  revoked (its event), with the household (cascade), and treated as none at read time once their
  end has passed. A promo-only household's RevenueCat customer is deleted 30 days after the
  household like any other: the grant noted it in `revenuecat_households`, and the deletion
  trigger queues noted households only (`household_deleted_purchases`,
  `20261113155327_revenuecat_known_customers.sql`; pgTAP `revenuecat_promotional.test.sql` checks
  it for a household with only a promotional row, `revenuecat_known_customers.test.sql` that a
  household RevenueCat never reported is not sent there).
- **Webhook event ids:** 90 days. **Claims** that never met their webhook: 30 days.
- **Archived households** keep everything until re-enabled, their archiver's account is deleted
  (`delete_account`), or 24 months have passed since archiving (job 47, H-50): the daily
  `purge_purchases` deletes the household like any deletion, so its purchases start their 30 days
  and its RevenueCat customer is queued. `archived_households()` returns `deletes_at`; the app
  shows "Wird am <Datum> gelöscht". Re-enabling clears `archived_at`; archiving again starts a new
  24 months. There is no reminder e-mail: Snacklist sends no notification e-mails of its own
  (DECISIONS 47.3). One whose archiver vanished another way is deleted by the daily purge.
- RevenueCat's own retention after deletion follows its DPA ("subject to standard data backup and
  archival practices").
- Purchases from before job 43 that unlocked nothing were bound to the nil UUID. All were sandbox
  test data; job 47's migration deletes the nil-bound `Sandbox` rows, and the daily purge deletes
  any nil-bound sandbox row 30 days after it was verified (tombstoning it if it has an HMAC), so
  none can linger (H-69). A nil-bound `Production` row cannot exist (nothing was sold before job
  43); the purge leaves one alone, for a person to look at.
- **Ended memberships** (`household_departures`: household, user, joined, left) are kept one hour
  for the buyer's claim, then deleted (on the next departure and by the daily purge).

### Testers

Testers get Snacklist Premium the same way as App and Play Review: a RevenueCat promotional grant
of the premium entitlement to their **household's** customer (App User ID = household id),
until 2100-01-01 ("Free premium: RevenueCat promotional grants" above; Peter, Nov 1: "use
revenuecat to handle tester's premium grants instead of the custom code"). The household then has
one promotional row like any other grant: it stays when the tester leaves, survives an archive,
never moves to another household, and ends when it is revoked in RevenueCat. RevenueCat knows
households, not people: a tester who starts a second household needs a second grant, and nothing
about the tester (user id, e-mail, name) goes to RevenueCat or into a list of ours.

```
deno run --allow-env --allow-net scripts/iap/promotional.ts grant --household <uuid> [--apply]
```

Dry run unless `--apply`; a household that already has a grant to 2100 or without end is left
alone, so a rerun changes nothing. `--apply` calls API v2 `grant_entitlement` (entitlement
`entl654efcfce4`, `expires_at` 2100-01-01; a customer RevenueCat doesn't know yet is created
first), then asks the purchases function to store the grant (`reconcile`, so the app shows it
without waiting for the webhook). Needs `REVENUECAT_SECRET_KEY` (v2, with
`customer_information:customers:read_write`), `REVENUECAT_PROJECT_ID` and
`REVENUECAT_DELETIONS_SECRET`. The dashboard's Customer → Entitlements → Grant does the same by
hand. To end a tester's premium, revoke the grant in RevenueCat; the webhook deletes the row.

Until 20261101150000_testers_via_revenuecat.sql the server kept its own tester list
(`lifetime_testers`, `tester_grant_apply`, `scripts/iap/testers.ts`, job 43). The migration
removes the list, its triggers and functions, the `tester` column and the `tester`/`tester_grant`
values; it refuses to run while a tester row exists in a household without a promotional row
(production had none on Nov 1, 2026), so no household loses premium by it.

**Analytics.** A household with a promotional row is internal: the purchases function marks every
purchase and refund in it `is_internal` (`household_internal`), and the app marks every event from
it (`HouseholdUnlocks.tester`, `isInternal`'s `testerHousehold`). A tester's purchase in a
household without a grant is no longer internal (we no longer know who is a tester); Sandbox
purchases (TestFlight, App Review, Play license testers) are internal as before (Peter,
2026-10-31).

### A second entitlement (model D, not built)

What a later running-cost subscription (AI meal plans, price feeds) adds, without touching
premium:

1. A product id in `scripts/iap/product.ts` and an entry in `products`
   (`supabase/functions/purchases/types.ts`) with its own kind, e.g. `plus`. Every product check
   (`productOf`) then accepts it.
2. The kind in the `purchases_kind` and `entitlements_kind` checks (a migration) and in
   `Entitlement` (`app/lib/purchases/entitlements.dart`). An unknown kind unlocks nothing in an
   older app (`Entitlement.parse` drops it), so a `plus` row never unlocks Lifetime features.
3. Subscription events work already (the yearly plan's lifecycle, job 49); the effective rule
   (`household_premium`) is per kind and would get its sibling.
4. Paywalls ask `canOffer(Entitlement.plus, plan)`. Apps from before job 43 (TestFlight) read any row as
   unlocked; they gate nothing, but no store build from before job 43 should be live when a
   second kind ships.
5. **RevenueCat's restore behavior is project-wide.** "Keep with original App User ID" would pin a
   subscription bought with the same Apple ID to the first household as well. Revisit when D is
   built (e.g. a separate RevenueCat project or entitlement).

## Integration lock

Job 50 (Spec #4; DECISIONS "Job 50"). MCP / AI assistants and the API (job 73) are part of
Snacklist Premium; the list, sync, categories, the app, the web app, Siri (job 184) and Alexa
(job 72) stay free. One switch, off until Peter says go; it is what job 328's brief calls
`premium-gate-integrations`:

- **Server:** `app_switches.integration_lock` (seeded off). Off, every integration works as it did
  before job 50, for every household. On, the mcp function (tool calls) and the api function
  refuse a caller without premium, as `public.integration_gate(household, integration, user)`
  decides with job 49's `household_has_premium` or job 185's `user_has_premium` of the caller
  (yearly not ended, Lifetime or a running promotional grant, testers' included; read at request
  time). Nothing the app sends counts.
- **App:** follows the server switch (`integration_lock()`, read when Zugänge opens); no define
  and no PostHog flag since job 328 (#577 put a flag `premium-gate-integrations` in front of the
  card, review 0 removed it: with the switch on and the flag off a user was refused without a
  word). While the switch is on, the integration settings (More › Zugänge) show a user without
  premium what Snacklist Premium includes, their connections as paused, and a button to the
  Premium page where this build sells (else "Bald verfügbar", on the web job 49's "buy it in the
  app" note). Builds before job 328 never show it.
- **Not gated:** „Meine Daten exportieren“ (`export_my_data`, Konto). It is the account's GDPR
  copy (Art. 12(5), 15, 20), free by law; Premium's "export" means the API and MCP (job 328).

What a locked user gets: an MCP tool call a tool result with `isError: true` and HTTP 200
(German, or English for a client that prefers it). Nothing is added, queued or kept. OAuth
discovery, initialize and tools/list stay free. Alexa is not locked at all (job 72, Legal Review
N-27): `integration_gate` answers `alexa` open (`20261102120000_alexa_free.sql`), the alexa
function no longer asks, and its Zugänge tile never shows as paused. Siri is free the same way
(job 184, `20261113034530_siri_free.sql`): `integration_gate` answers `siri` open, so a voice
function deployed before it never refuses, the voice function no longer asks, and the Siri
credential's tile never shows as paused. A Shortcut's personal access token still shows as paused,
since the same token also signs in MCP; on the voice function it stays free by design. OAuth
tokens, which MCP and AI-assistant clients hold, get 401 from the voice function (job 213), so a
locked client cannot add through it instead. All copy is a placeholder until Snacklist PM.

What it never does: delete, revoke or disconnect anything. A lapsed yearly plan (or a refund)
locks again at read time; tokens, the Siri credential, the Alexa link, OAuth connections and the
list stay, and buying or renewing opens everything at once for the buyer, in every household they
are in, with no relinking. Another member's plan does not open it (per-user Premium, job 185, PB2).
Connecting while locked is allowed. A failing check answers with the endpoint's normal "try again"
error, never with the premium answer and never by adding.

`integration_blocked` (`integration`: `mcp`, `api`) goes to PostHog at most once an hour
per household and integration (`integration_blocks`), only with the caller's analytics yes;
`paywall_viewed` (`entry_point`: `more`, `integrations`) when the Premium page offers a plan with
its price (docs/ANALYTICS.md).

**Go-live order** (Peter's go; NEEDS_LEAD "Job 50" has the commands):

1. Job 49's premium is live: products in the stores and RevenueCat, the webhook secrets set,
   `premium_offer` on and `REVENUECAT_PURCHASES` in the store builds (otherwise a locked household
   cannot unlock and sees "Bald verfügbar").
2. Promotional grants for the beta households Peter wants to keep (`scripts/iap/promotional.ts
   grant`, "Testers"); check the
   cut-over with `scripts/iap/integration-cutover.sql` (read-only).
3. Legal Review has added `integration_blocked` and `paywall_viewed` to privacy section 9 and the
   texts that call the integrations free are updated (NEEDS_LEAD "Job 50").
4. Most installs run a build from job 328 on (older builds show no card while refusing).
5. The server switch on: `update public.app_switches set enabled = true, changed_at = now() where
   key = 'integration_lock';` (service role, SQL editor). From now on every user without Premium
   is refused, everywhere at once: the switch has no per-user targeting, so a TestFlight trial
   for Peter alone is not possible (use a local stack). Then the changelog hold
   `integration-lock` released in `releases/flags.json`.

Rolling back: the server switch off opens every integration at once and hides the app's card in
every build (the app reads the switch). Testing locally: `update public.app_switches set enabled =
true where key = 'integration_lock'` on the local stack, a household with or without a fake
purchase (`e2e/tests/iap.ts`), then MCP or the API (Siri and Alexa stay open); `e2e/tests/integration-lock.spec.ts`
does all of it.

## Configuration

RevenueCat (set up by the Lead and Ops): the webhook delivers promotional grants too (checked
2026-11-01: the Play Review household's grant at 13:23:31 CET reached the function as
`NON_RENEWING_PURCHASE` two seconds later; the API key can't read the webhook settings
themselves). Entitlement `premium` (`entl654efcfce4`) with the four products (App Store and Play, yearly and Lifetime; the old `lifetime` entitlement stays until every
app is a job 49 build), Hummlist's and Snacklist's alike; one RevenueCat project, with Snacklist's
apps (iOS `app762918886a`, Android `appcec7ffa3d1`) next to Hummlist's (`app508ff9066c`,
`app44e3fb2d11`) until Hummlist retires, offering `default` with `$rc_annual` and `$rc_lifetime`. The app loads
products by id, not the offering (DECISIONS 49.27). Store facts: Snacklist's App Store
subscription group "Snacklist Premium" `22562774`, yearly Apple ID `6832759834`, Lifetime
`6832759640` (job 174); Hummlist's (Ops, 2026-10-31) group "Hummlist Premium" `22532621`, yearly
`6829293557`, Lifetime `6829223747`; Play base plan `yearly`, grace period 14 days, account hold
46 days. Function secrets (set by the Lead on the hosted project; NEEDS_LEAD "Job 43 – RevenueCat
setup"). Without
`REVENUECAT_WEBHOOK_AUTH` and `REVENUECAT_TOMBSTONE_HMAC_KEY` the webhook answers 503
`not_configured`; the claim route works regardless.

| Secret | Meaning |
| --- | --- |
| `REVENUECAT_WEBHOOK_AUTH` | The `Authorization` header value set in RevenueCat's webhook integration |
| `REVENUECAT_WEBHOOK_HMAC_SECRET` | Optional: RevenueCat's webhook signing secret; when set, the signature is required |
| `REVENUECAT_TOMBSTONE_HMAC_KEY` | The one key for the tombstone HMACs; never rotate it while tombstones count |
| `REVENUECAT_SECRET_KEY` | A v2 secret key (`customer_information:customers:read_write`, which includes reading subscriptions) for deleting customers and reading promotional grants; never in the app. Unset: promotional events answer 503 (RevenueCat retries) and the reconcile route 503 |
| `REVENUECAT_PROJECT_ID` | The RevenueCat project (`9cb4a72e`, one for Hummlist and Snacklist) |
| `REVENUECAT_DELETIONS_SECRET` | What the daily deletion workflow and `scripts/iap/promotional.ts reconcile --apply` send as `x-deletions-secret`; also a repository secret of the same name (NEEDS_LEAD "Job 47"). Unset: the deletion and reconcile routes refuse every call |

Expected prices (the drift check's constants, `expectedPrices` in `scripts/iap/product.ts`; never
shown in the app, which shows only what the store returns; `store-prices-ops` in
[`PRODUCT_FEATURE_MAP.md`](PRODUCT_FEATURE_MAP.md)):

| Storefront | Yearly | Lifetime |
| --- | --- | --- |
| Euro storefronts (EUR) | €24.99 | €149.99 |
| United States (USD) | $9.99 | $29.99 |
| United Kingdom (GBP) | £8.99 | £24.99 |
| Switzerland (CHF) | CHF 10 | CHF 30 |
| Brazil, Mexico, India | as the store sets it (recorded on the first run) | not sold |

The euro amounts are the approved ones (Peter, 11 Nov 2026). Ops moves the stores to them; until
then the drift check accepts the superseded €9.99 / €29.99 with a note. The USD, GBP, CHF, BR, MX
and IN figures are what the stores charge today: Ops sets new amounts there and a PR records them
after. €9.99 / €29.99 (and the €39.99 Lifetime once planned) are historical.

App build defines (public SDK keys, from the build environment, never committed):
`REVENUECAT_APPLE_API_KEY` (`appl_…`), `REVENUECAT_GOOGLE_API_KEY` (`goog_…`), and
`REVENUECAT_PURCHASES=true` to show the purchase screen (off by default; turn it on only for
Peter's own builds until he approves the legal texts, then for everyone). `HOUSEHOLD_ARCHIVE=true`
offers archiving in the app; the server archives only while `app_switches.household_archive` is
on (seeded off; NEEDS_LEAD "Job 47" turns both on together).

Gone with job 43 (the Lead deletes them from the hosted secrets and the repository):
`PURCHASES_ENVIRONMENTS`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_PRIVATE_KEY`,
`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `PURCHASES_CRON_SECRET`.

## Testing locally

- `scripts/iap-local-env.sh` (run by `supabase_up`) writes local stand-ins for the function's
  secrets into the gitignored `supabase/functions/.env`. On the local stack the function also
  serves `POST /purchases/test/event`, which plays RevenueCat.
- The app's fake store: build with `--dart-define=FAKE_STORE=ok` (or `pending`, `cancel`,
  `error`, `unavailable`, `offline`) in a debug build on a desktop or phone; its purchases go
  through the local `test/event` route and the real claim route. Recipe:
  `.cursor/skills/verify-family-groceries/features/purchases.md`.
- `e2e/tests/purchases.spec.ts`: the web page, then a purchase reported through the real webhook
  (local secret) unlocks the household live for both members, and a refund locks it again.
- `e2e/tests/premium-yearly.spec.ts`: the yearly plan live for both partners, cancelled and
  expired (list and tokens stay), Lifetime while yearly renews, a TRANSFER, and the
  billing-continues warnings before account deletion and leaving.
- `POST /purchases/test/event` takes `productId` (`com.snacklist.app.yearly`), `type` (every
  lifecycle type), `expiresInDays`, `graceDays`, `cancelReason`, `eventAgoMs`, `transferTo`.
- `e2e/tests/household-bound.spec.ts`: joining an unlocked household (nothing to buy, the refund
  help, the delete warning), restore after the household is gone, archive and bring back (with
  the deletion date), a household bought twice, the web copy. The e2e build has
  `HOUSEHOLD_ARCHIVE` on (`app/config/e2e.json`) and the spec turns the server switch on.
- `app/test/purchases/no_sdk_before_tap_test.dart`: the real `RevenueCatRepository` over a mocked
  platform channel: app start, the More tab, opening, rebuilding, leaving and returning to the
  page make no SDK call and one store price read per opening; Buy (yearly or Lifetime) makes
  `setupPurchases`, `getProductInfo`, `purchaseProduct`, Restore `setupPurchases`,
  `restorePurchases`, in that order (H-67).
- `app/ios/Snacklist.storekit`: both products (the yearly plan in its subscription group) for
  Xcode's StoreKit testing (RevenueCat supports StoreKit configuration files for local UI work on
  a Mac).
- Tests: `supabase/functions/purchases/*_test.ts`, `store_integration_test.ts` (db gate), pgTAP,
  `scripts/iap/*_test.ts`, `app/test/purchases/`.

## Store setup

Scripted where the APIs allow it, never submitted for review:

- `scripts/iap/apple_product.ts`: App Store Connect API, dry run by default, `--apply` to create
  the non-consumable, DE+EN localizations, the EUR 149.99 price in Germany (others equalized),
  availability in all territories; prints the equalized AT and CH prices. Needs the ASC API key,
  which is on the box only.
- `scripts/iap/google_product.ts`: Play Developer API `monetization.onetimeproducts`, dry run by
  default; prints Play's converted AT and CH prices. Needs the payments profile first. On a
  product that exists, `--apply` overwrites its price with `basePrice` (EUR 149.99 since job 184),
  so it changes the live Lifetime price on Play: an Ops step, never run from engineering. It
  therefore refuses `--apply` (exit 2, before any request) unless `--confirm-price <amount>` names
  that base price, e.g. `--apply --confirm-price 149.99` (job 213, `google_product_test.ts`).
- `scripts/iap/product.ts` holds both products (ids, Apple IDs, names, base prices, period,
  subscription group, Play base plan) and the expected prices; `product_test.ts` pins the
  StoreKit file and the function's product map to it. `apple_product.ts` and `google_product.ts`
  create Lifetime only; Ops creates the subscription.
- `scripts/iap/price_drift.ts` (daily `.github/workflows/price-drift.yml`): reads both stores'
  current prices and fails on drift from the expected prices, or Lifetime in BR/MX/IN; "SKIPPED:
  … missing" without its secrets (NEEDS_LEAD "Job 49").
- RevenueCat (account, apps, In-App Purchase key, Play service account, products with the Play
  product NON-CONSUMABLE, the `lifetime` entitlement, restore behavior, the webhook):
  NEEDS_LEAD "Job 43 – RevenueCat setup".

## The refund help

A sheet (`app/lib/purchases/refund_help.dart`) from the Premium page, the join screen and the
delete confirmation. Its texts are Legal Review's R-8 strings word for word (H-76, job 47
ADDENDUM 1 and 2): App Store purchases only Apple refunds; Google Play in the first 48 hours
through Google, after that by e-mail to support@snacklist.app with the order number (`GPA.…`) or
the Google account's e-mail address, looked at case by case; statutory rights unaffected. Links:
Apple's Report a Problem, Google Play's refund page, and the FAQ on snacklist.app (`/support`,
`/en/support`; its refund question has no anchor of its own, and the legal pages are not this
code's to change). Below them a placeholder note for the yearly plan: cancelling only stops the
renewal; the current year is not refunded automatically (NEEDS_LEAD "Job 49").

## Refunds when something is off

RevenueCat retries a failed webhook 5 times over about 80 minutes; after that, resend it from
RevenueCat's dashboard (Integrations → Webhooks → the event). A refund whose `CANCELLATION`
never arrived keeps the household unlocked until it is resent. The deletion workflow opens an
issue when it fails (see "Retention").
