# Job 456: copy findings for Legal (no edits made)

Copy audit of the enabled feature set, 26 November 2026, at b56693e2c. These texts are Legal's, so
this job changed none of them. Each item gives the place, the current text, a suggestion and the
reason. Truth source: `.cursor/skills/verify-snacklist/features/FEATURES-FOR-WRITERS.md` (FFW) and
`releases/flags.json`.

## Support pages (`site/content/legal/support.md`, `support-en.md`)

- **support.md:35 / support-en.md:35, invite path.** Current: „Tippe auf **Mehr** und dann auf
  **Leute einladen**. … Offene Einladungen kannst du dort auch widerrufen.“ / "Tap **More**, then
  **Invite people**. … You can revoke open invites there too." Suggested: „Tippe oben links in der
  Liste auf den Namen deines Haushalts und dann auf **Einladen**. Teile den Link oder den Code.
  Offene Einladungen widerrufst du auf der Mitgliederseite unter **Offene Einladungen**.“ / "Tap your
  household's name at the top left of the list, then **Invite**. Share the link or the code. Revoke
  open invites on the members page under **Open invites**." Why: with list-declutter on for
  everyone, More has no invite row (FFW "Household and invites"; ARB `switcherInvite`). Peter
  already knows. `site/test/agent.test.mjs:135` pins the EN FAQ answer, so update it with the text.
- **support.md:39 / support-en.md:39, join path.** Current: „…tippe oben in der Liste auf den
  Namen deines Haushalts, dann auf **Mit Code beitreten**…“. Suggested: „…tippe oben links auf den
  Namen deines Haushalts, dann auf **← Haushalte** und auf **Mit Code beitreten**…“ / "…then
  **← Households** and **Join with a code**…". Why: „Mit Code beitreten“ sits on „Deine
  Haushalte“, one step behind the household page (FFW "Household and invites", steps 3 and 5).
- **support.md:39 / support-en.md:39, first join.** Current: „Bist du noch ganz neu, wählst du
  gleich nach der Anmeldung **Haushalt beitreten**.“ Suggested: „Bist du noch ganz neu, tippst du
  beim Namen des Haushalts auf **Bestehendem Haushalt beitreten** und gibst den Code ein.“ / "…tap
  **Join existing household** on the household-name step and enter the code." Why: the guided
  start comes before the account, and the entry is „Bestehendem Haushalt beitreten“
  (join-household-jh2 full; FFW "Getting started").
- **support.md:13 / support-en.md:13, categories.** Current: „Snacklist sortiert jeden Eintrag in
  seine Kategorie.“ / "Snacklist sorts each item into its category." Suggested: „Snacklist sortiert
  jeden Eintrag nach Laden, in der Reihenfolge deines Wegs durch den Laden.“ / "Snacklist sorts each
  item by store, in the order you walk through it." Why: the app shows no categories since
  22 November (hide-categories full; FFW "Categories").
- **support.md:68, grammar.** Current: „Du kannst ihn jederzeit wieder einschalten.“ Suggested:
  „…sie…“. Why: the antecedent is „Nutzungsdaten“ (plural). The EN text is fine.
- **support.md:47, :51-64 / support-en.md:47, :51-64, Premium purchase and refunds.** Current:
  yearly billing, refunds, „Snacklist Premium kaufst du bei Apple oder Google“, live in production
  today. Suggested: gate them with `::: once premium-launch`, or confirm they must be public now.
  Why: FFW "Never claim": Premium is not on sale until the 1 December publish; the `premium-launch`
  hold is unreleased.
- **support.md:47 / support-en.md:47, archived households.** Current: „Auch Haushalte, die du
  archiviert hast, werden gelöscht.“ Suggested: drop it, unless it should stay for older builds.
  Why: archiving is off in the released apps (FFW "Household and invites"). Low.

## Privacy policy and report page

- **datenschutz.md:81, :85 / privacy.md:62, :66.** Prices, totals, „Im Reiter „Verlauf“ kannst du
  Einkäufe eintragen“ and trip detection, all in the present tense. Suggested: frame them as
  conditional („Ist diese Funktion eingeschaltet, …“) or gate them. Why: prices-and-trip-total,
  grocery-log, trip-mode and learned-order are off for everyone. Disclosing them anyway may be
  Legal's choice.
- **inhalte-melden.md:22 / report.md:22.** Current: „In der App wählen wir den Eintrag, die Liste
  oder das Foto für dich aus – bitte prüfe die Auswahl.“ Suggested: gate it until
  report-content-entry is on, or drop it. Also drop „Foto“: items have no photos. Why:
  report-content-entry is off (FFW "Reporting illegal content").

## Store listings (`app/fastlane/metadata/`)

- **{de-DE,en-US}/description.txt:21-22, android/{de-DE,en-US}/full_description.txt:20-21, the AI
  paragraph.** It names AI assistants with no Premium note. Since 24 November, AI access needs the
  account's own Premium, which is not on sale until 1 December. Decide whether the paragraph must say
  so now (Apple 2.3.2), or whether the listing waits for the 1 December block (`docs/store/LISTING.md`).
- **Same files, the SNACKLIST PREMIUM paragraph.** Confirm it goes live only together with the
  purchase screen (LISTING.md open item 4).
- **android/*/full_description.txt:29.** Only the privacy link; the App Store text also has the
  terms link. Optional: add the terms link so both stores match.
- **Outside the repo:** the App Store Connect de-DE Lifetime text "Unlocks premium for your
  household, once." contradicts per-account Premium. Replace it with `iap/de-DE/lifetime.txt` at
  the next console edit.

## Emails (`emails/src/emails/auth.tsx`, built into `supabase/templates/`)

- **EN reason lines (auth.tsx:51, 74, 97, 120, 142, 157) and `emails/src/components/Footer.tsx:93-96`.**
  "e-mail" next to the body's "email" in the same mail. Suggested: "email" everywhere. Legal confirmed
  these lines (N-15a).
- **confirmation and magic_link.** The body says „…kannst du diese E-Mail einfach ignorieren.“ and
  the reason line then says „Warst du das nicht, ignoriere sie einfach.“ Suggested: drop one of them.
- **invite template wired (`supabase/config.toml` auth.email.template.invite).** Hard rule N-18:
  Snacklist never emails an invitee. The app never calls `inviteUserByEmail`, so it cannot fire
  today. No change is needed unless Legal wants it removed.

## App (ARB)

- **`analyticsConsentBody`** still says „API-Schlüssel“, while the app's keys are
  „Zugriffsschlüssel“ since unified-keys. FFW says to quote this consent text exactly, so only
  Legal changes it.
