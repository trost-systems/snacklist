# Your name

The app asks for the name the household sees. Right after sign-in and the usage-data question, „Wie sollen wir dich nennen?“ / "What should we call you?" comes before anything else: before a new household is set up (also after the guided start's account step), and before an invite link joins. A Google or Apple name is prefilled and „Ja, das bin ich“ / "Yes, that's me" saves it with one tap. Without one (an e-mail sign-up, Apple with the name hidden) the field is empty and the step cannot be skipped. A member whose name is still the e-mail prefix gets the step once, with „Jetzt nicht“ / "Not now". Under Mehr › Konto the first row „Dein Name“ / "Your name" shows the name, or „Namen eintragen“ / "Add your name" for an e-mail-prefix name, and opens a sheet to change it. One name for all households. A saved name is never replaced by a later Google or Apple name. Others see a change the next time their screens load the members (no live update, no notice).

## Sub-features

- `dn-step` the step `/your-name` (screen name `your_name`): the title bar „Dein Name“, the heading „Wie sollen wir dich nennen?“ / "What should we call you?", „Alle in deinem Haushalt sehen diesen Namen. Wen du einlädst, sieht deinen Vornamen. Du kannst ihn später ändern.“ / "Everyone in your household sees this name. The people you invite see your first name. You can change it later.", the field „Dein Name“ (hint „z. B. Lea“ / "e.g. Lea" while empty, „n/80“ under it, read out as „Noch N Zeichen“, „Noch 80 Zeichen“ while empty), the button „Weiter“ / "Continue" (off while the field is empty or only spaces), „Ja, das bin ich“ / "Yes, that's me" while the field holds the prefilled name. Saved: spaces and line breaks collapse to one space and are trimmed; 1 to 80 characters, emoji count as one. Too long or empty after that: „Gib einen Namen mit 1 bis 80 Zeichen ein.“. Offline: „Keine Internetverbindung. Dein Name wurde nicht gespeichert.“. A failed read: „Dein Name konnte nicht geladen werden.“ with „Erneut versuchen“. The app bar has „Abmelden“ (icon button, as on the analytics question): it signs out to the start screen (job 486) without saving a name, and an invite on the step's location rides along. The field refuses an edit past 80 code points (a family emoji counts 5, though the counter shows 1); a name of only zero-width characters stays off.
- `dn-required` without a household (a new account, someone about to join) the step comes until a name is saved: after the analytics question, before the household setup of the guided start, before an invite link joins (`/your-name?invite=<code>`; after „Weiter“ the app joins with no further tap, household-invites `link-join`). No „Jetzt nicht“, no back.
- `dn-prefill` a Google or Apple name (the profile's name, not the e-mail prefix) is in the field; one tap on „Ja, das bin ich“ saves it as chosen. Apple's name arrives right after the sign-in; the field takes it while untouched.
- `dn-once` in a household, an unchosen name that is the e-mail's local part (or empty) asks once per device, with „Jetzt nicht“ / "Not now". Members with a Google or Apple name are not asked.
- `dn-row` Mehr › Konto: the first row „Dein Name“ with the name under it, or „Namen eintragen“ / "Add your name", and a pencil. A tap opens a sheet: „Dein Name“, „Alle in deinem Haushalt sehen diesen Namen. Wen du einlädst, sieht deinen Vornamen.“, the field (prefilled; empty with the hint for an e-mail-prefix name), „Speichern“ (off while empty, only spaces, or unchanged) and „Abbrechen“. Saved: the notice „Name gespeichert“ / "Name saved" and the row shows it. After a failed read the row reads „Dein Name konnte nicht geladen werden.“ and a tap reads again.
- `dn-kept` a chosen name (typed or confirmed) is never replaced by a later Google or Apple name; an unchosen e-mail prefix still is (server trigger, `supabase/tests/display_name_chosen.test.sql`).

## How to get to it (user POV)

- A new account: „Registrieren“ on the sign-in (or the guided start's account step), the usage-data question, then the step.
- An invite link: „Im Browser beitreten“, „Konto erstellen“ in the sheet, sign up, the usage-data question, the step, then the household's list.
- An existing member with an e-mail-prefix name: the next sign-in or app start.
- Tab „Mehr“ › „Konto“ › „Dein Name“.

## Driving it with Playwright

Preconditions: a plain `launch.sh` (on the Hetzner runner also `FLUTTER_DIR=~/flutter-3.50.0`), `demo-familie`. `drive.sh display-name [--lang en] [--dark]` runs `journeys/display-name.mjs`:

- **E-mail sign-up.** `/login`, „Registrieren“, decline the question → `/your-name`; the field (`getByRole('textbox', { name: /^Dein Name/ })`) is empty, „Weiter“ is disabled, no „Jetzt nicht“. Type „  Lea   🌻 “, „Weiter“ → `/welcome`; the profile holds „Lea 🌻“ with `display_name_chosen_at` set.
- **Wrong account.** Another new sign-up taps „Abmelden“ on the step → `/start`; its profile is still its e-mail prefix, not chosen.
- **Prefilled.** A user signed up through supabase-js with `options.data.full_name` (what Google puts there) signs in → the field holds the name, „Ja, das bin ich“ → `/welcome`, chosen. Then `raw_user_meta_data` gets another `full_name` in SQL: the name stays.
- **Joiner.** Mia's `create_invite` (`p_kind: 'person'`), `/join/<code>`, „Im Browser beitreten“, the sheet „Du bist in einen Haushalt eingeladen“, sign up → `/your-name?invite=<code>`; type „Jo Brandt“, „Weiter“ → the household's list with no „Haushalt beitreten“ tap; Mia's `household_members_of` lists „Jo Brandt“ (driven 2026-11-19 on af0287cf).
- **Member, once.** Noah's profile set to his e-mail prefix in SQL (`display_name_chosen_at = null`); sign in → the step, empty, with „Jetzt nicht“; tap it → the list; reload → still the list. Mehr › Konto: the row reads „Namen eintragen“; the sheet's „Speichern“ is off until „Noah“ is typed; saved → the row shows „Noah“, chosen in the database. Then the root font size 200 %: the row and the sheet with „Speichern“ visible.
- Second view: `select display_name, display_name_chosen_at from public.profiles` (`psql` on port `<prefix>22`), or `rpc('my_display_name')` as the user (`display_name`, `chosen`, `from_email`).

## Gotchas

- `VH_FLAGS_FULL=0` (or `VH_FLAGS_OFF=display-name`) builds the flag-off screens the e2e specs see: no name step and no „Dein Name“ row under Konto.
- `signIn` in `helpers/lib.mjs` waits for the add field: a seeded member whose name is the e-mail prefix stops at the step first. The seeded members have real names, so they are not asked.
- „Jetzt nicht“ is kept per browser profile (DeviceCache): a fresh `openApp` context asks again.
- The real Google and Apple sheets cannot be driven locally; `full_name` in the sign-up metadata stands in for them (the profile trigger reads it the same way).
- Without the migration (`my_display_name`) the step cannot read the name and shows the retry.
- The public join page (`/join/<code>`, static) still hides a name equal to the e-mail prefix, chosen or not (Legal N-151).
- Covered by widget tests too: `app/test/session/your_name_screen_test.dart`, `your_name_gate_test.dart`, `your_name_test.dart`, `app/test/settings/account_name_test.dart` (200 % and dark included), router cases in `app/test/shell/router_test.dart`.
