# Onboarding

After sign-in (and the analytics question, in builds with a key), a user without a household goes
through onboarding (job 22, Spec #3). Step 1, "Willkommen bei Hummlist", offers "Haushalt
erstellen" and "Einladung annehmen". Step 2a creates the household (name, picked or typed stores,
or "Überspringen"). Step 2b joins one with a code, after showing the household's name. Step 3,
"Partner einladen", makes an invite and shares it ("Später" goes to the list). An invite link
skips Step 1. A user who already has a household goes straight to the list.

## Sub-features

- `ob-order` follows sign-in, then analytics consent (once per install), then Step 1 or the list. Routes: `/welcome`, `/welcome/create`, `/join`, `/join/<code>`, `/welcome/invite`. The only gate is `authRedirect` in `app/lib/app/router.dart`.
- `ob-create` (Step 2a, key `create-household-screen`): `household-name` is prefilled "Unser Haushalt" ("Our household" in English). The stores (`onboarding-stores`) are filter chips `onboarding-store-<name>` for EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm and Rossmann, none picked; `onboarding-store-own` opens `store-new-field` for an own store (up to 40 characters; `store-new-confirm` or Enter adds, `store-new-cancel` or Escape closes); a new name such as "Wochenmarkt" joins the chips picked (`onboarding-store-Wochenmarkt`); a typed name of an offered chain in any case or spacing ("edeka", " EDEKA ") ticks that chip (`onboarding-store-EDEKA`) instead, and a name already picked stays picked once; `stores-disclaimer` is the store-name note. `create-household` creates with the picked stores in the order picked (EDEKA, Lidl and dm become those chains with their layouts); `skip-stores` creates without stores (below it "Ohne Läden starten. Du kannst sie später unter Liste → Anpassen anlegen."). Offline it says "Keine Internetverbindung …" and keeps the name and the choice; a retry after a lost answer finds the household instead of making a second one.
- `ob-invite` (Step 3, `invite-partner-screen`): `invite-partner` makes one invite. iOS and Android open the share sheet with "Komm in unseren Hummlist-Haushalt: <link> · Code: <code>". The web and the Linux app show the card: the code, the link, `invite-copy-link`, `invite-copy-code`, and `invite-share` where a share sheet exists. `invite-later` ("Später", then "Weiter zur Liste") goes to the list.
- `ob-join` (Step 2b, `join-screen`): `invite-code`, then `invite-check` ("Weiter") shows `invite-household` with the name, then `join-confirm` ("Haushalt beitreten"). `join-cancel` goes back to Step 1 and drops the pending link. In a household it is the same screen (job 169b): joining adds the household beside the others and shows it; nothing is left.
- `ob-pending` keeps a link's code on the device (`DeviceCache` key `invite.pending`, 7 days) from the moment `/join/<code>` or `?invite=` arrives. It survives sign-in (also the apps' `com.hummlist.app://login-callback` return), an app kill, the consent and the steps. It goes after a join, Cancel, an invalid code or a sign-out.
- `ob-errors`: one "Dieser Code ist ungültig oder abgelaufen." for made-up, expired, revoked and used codes; "Zu viele Versuche. Bitte später noch einmal." after 10 failures in an hour; the offline line. The field always keeps the code.
- `ob-events` (builds with a key, after a yes): `household_created` (`store_count`, 0 to 50; builds before job 58 sent `default_stores`), `invite_sent` (`channel` share_sheet/copy_link/copy_code, `context` onboarding/settings), `invite_accepted` (`method` link/code). Each once per action; never the code, the link or a name.

## How to get to it (user POV)

- Sign up with a new email. Answer the analytics question if it comes. Step 1 shows.
- Or open `/join/<code>` signed out: sign in by any method; after the question, the join screen for that code shows.

## Driving it with fg

Preconditions: the baseline from `features/README.md`; a fresh user on lea's client (`features/household.md`, Preconditions; it now waits for `--key welcome`).

- **Create with stores.** `fg tap --key onboarding-create --client lea`, `fg wait --key household-name --client lea`, `fg type --key household-name --input "WG $(date +%s)" --client lea`, `fg tap --key onboarding-store-REWE --client lea`, `fg tap --key onboarding-store-dm --client lea`, `fg tap --key create-household --client lea`, `fg wait --key invite-partner --client lea`. `fg db query "select s.name, s.seed_key from stores s join households h on h.id = s.household_id where h.name = '<name>' order by s.sort_order"` returns REWE (null) and dm (dm).
- **Create without stores.** The same, but `fg tap --key skip-stores --client lea` instead of `create-household`; the stores query returns nothing, categories 11.
- **Invite (Linux: no share sheet).** On Step 3, `fg tap --key invite-partner --client lea`, `fg wait --key invite-copy-code --client lea`. Read the code as in `features/household.md`. `fg tap --key invite-copy-code --client lea` shows "Code kopiert". `fg tap --key invite-later --client lea`, `fg wait --key add-item-field --client lea`.
- **Second client joins by code, then live.** Use `fg sync` (two clients, `docs/TEST_FIXTURES.md`) or peter's client after `fg logout --client peter` and a fresh sign-up there: `fg tap --key onboarding-join`, type the code into `invite-code`, `fg tap --key invite-check`, `fg wait --text "<household name>"`, `fg tap --key join-confirm`, `fg wait --key add-item-field`. Then add an item on one client and `fg wait --text <item>` on the other (as in `features/live-sync.md`).
- **Proof.** Screenshots of Step 1, Step 2a (both store options), Step 3 with the card, the join preview and the list on both clients; the `household_members` and `stores` query output.

## Gotchas

- fg builds have no PostHog key, so the analytics question never comes and nothing is sent.
- The fg debug build has no `APP_URL`: the invite card shows the code without a link, and the share text names the code only.
- Invites are single use and expire after 7 days; seed a fresh one per join (`fg seed pending-invite` prints an open code).
- After 10 wrong codes in an hour, the user is rate-limited for an hour: `fg db query "delete from invite_attempts" --write` resets it.
- The Mac runner has no Docker, so no local stack and no fg there. Run fg on the box, or prove the web flows with `scripts/ci-e2e.sh --spec tests/onboarding.spec.ts`.
