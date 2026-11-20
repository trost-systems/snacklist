# Job 329: subscription legal texts for per-user Premium (2026-11-20)

Redo of draft PR #153 on main as #580. Not merged: Legal's GO first (brief). Decisions: docs/DECISIONS.md "Job 329".
Legal sources, by file in `/workspace/legal/reviews/`: `2026-10-30-hummlist.md` (K.13.4 S-1..S-5, K.13.R R.1/R.2/R.4/R.6,
K.13.S terms, K.13.T), `2026-11-10-snacklist-premium.md` (N-128, N-129), `2026-11-19-snacklist-inapp-legal.md` (Q25,
N-302).

## What changed

| Where | What | Live when |
| --- | --- | --- |
| `site/content/legal/datenschutz.md`, `privacy.md` | New section 5a (yearly plan and Lifetime, per-user: RevenueCat gets the account id after a tap, Apple the id, Google a hash; only the buyer sees the unlock; account deletion ends Premium, purchases purged after 30 days, RevenueCat customer deleted after 30 days; a lapse deletes nothing, history back to 4 weeks). §8 and §14 per-user versions | Only once the hold `premium-launch` is released |
| same | §12 RevenueCat line (subscriptions, renewals, cancellations) and §13 (the account id goes to Apple and Google) | Next site deploy after merge (true before and after the sale) |
| `site/content/legal/support.md`, `support-en.md` | Per-user answers: deleting the account, leaving a household (at most 20), cancelling the yearly plan, when Premium ends, refunds. R.4's MCP line behind `integration-lock` | Once `premium-launch` (and `integration-lock` for the MCP line) is released; today's answers until then |
| `site/content/legal/nutzungsbedingungen.md`, `terms.md` | K.13.S rewritten for the CS1 split and per-user Premium (cap of 20 households, personal use), yearly plan at the store's price, lapse, Lifetime, API limits as numbers, costly features only with numbered limits, refunds, changes, shutdown | `draft: true` until Legal's GO; must be published before 5.4 (N-129) |
| `app/l10n/app_de.arb`, `app_en.arb` | `premiumYearlyTerms` (store price, lapse), `premiumOwner` (per-user, replaces `premiumHousehold`), `premiumWeb` (per-user); as Legal GO'd them at 2abc7521 | Only with `REVENUECAT_PURCHASES` and `premium_offer` on |
| `app/web/konto-loeschen.html`, `delete-account.html` | Premium ends with the account; a yearly plan keeps billing until cancelled | Next web release (true before and after the sale) |
| `site/content/legal/datenschutz-kaeufe.md`, `privacy-purchases.md` | Deleted (draft pages, now section 5a) | (were 404 in production) |
| `site/test/gates.test.mjs` | All 24 `premium-launch` gates listed with a phrase per side; held and released builds checked; gate count per page pinned | CI |

## How to verify

- `cd site && node --test test/gates.test.mjs test/waitlist.test.mjs`; `/tmp`-style mutation: removing any one of the 24 gates fails the render test.
- `cd app && flutter test test/purchases/ test/design/premium_golden_test.dart`
- Production render today equals main's for the help page; the privacy policy differs only in the §12 and §13
  RevenueCat lines (built both with the site's test helpers and diffed the Markdown twins).
- Screenshots: `docs/screenshots/329/`.

## Open

- Legal's GO on every changed text (NEEDS_LEAD "Job 329" in the ops file has the head sha and sha256 prefixes).
- Before 5.4: the Premium hero (#579's) stops promising the household, the page says the free list needs no Premium
  (N-129) and names the 20-household cap (N-128); the terms published and linked (N-129); numbered limits for any costly feature offered; Lifetime allowances (Peter).
- Peter: whether CS1's Premium "export" means anything beyond the free GDPR download.
- #153 can be closed once this PR has Legal's GO.
