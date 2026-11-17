# Round DE: changing the name later
<!-- pick: DE1 -->
<!-- runner-up: DE2 -->

## Recommendation

**Pick: DE1 Account › Your name.** The name belongs to the person, not to a household, and Account is where people look for “my details”. It is already the first row on More. The row shows the current name, or “Add your name” instead of an e-mail prefix. A tap opens a sheet with the field, prefilled, and Save stays off while it is empty or unchanged. It costs 4 taps from the list. The row is visible without scrolling at 100 %, 200 % and 310 %, it moves nothing on More, and it is the same in every household. The household member who asked would find it under More › Account.

**Runner-up: DE2 Your own member tile.** It costs the same 4 taps, and you change the name where you see it next to the others. But it is a pencil on one row of a list, people go to the household page to see who is in, not to edit themselves, and with the list-declutter flag that page moves into the list’s switcher sheet. Good as a second way into the same sheet (DE-Q1), not as the only one.

Not picked:
- **DE3 A profile header on More** is the fastest (3 taps, editing in place), but it puts a card above every row of More and pushes all of them down for one rare action.
- **DE4 Where your invite shows it** fixes the name at the moment someone will see it, but nobody finds it unless they are inviting, and at 200 % the entry is below the fold.
- **DE5 A name per household** answers a question nobody asked yet (“Mama” here, “Peter” there). It needs a column on household_members, a choice per new household, and a rule for which name the join page shows.

## Where the change shows

The strip “What others see” on this page updates when any phone saves. In the app every place reads the current profile name, and nothing keeps a copy: Peter’s member list, join requests (`join_requests_of`), “2 new from Lea” and who took an item (the household’s member catalog), the trip summary, and the join page of Lea’s invite (`preview_invite_public`, first word, never the e-mail prefix). The report form's prefill (job 281, not on main yet) has to read the current name too; check that once it lands. Profiles are not published to realtime. So others see the new name the next time those screens load the members, not live (DE-Q4).

## Measured

The verify script walks each option from the list with real clicks, types a new name and saves. It then checks that the member list, the list and the join page in the strip show it. “Entry visible” means the edit control is whole above the floating tab bar on the screen where it lives, without scrolling. Overflow was checked on every screen of every walk and frame, in English and German, at 100 %, 200 % (Android's largest) and 310 % (iOS's largest), starting from five names (an e-mail prefix, Google’s “Lea Brandt”, an Apple relay prefix, a 49-character name, “Lea 🌻”) and saving “Lea Maria Brandt-Sommerfeld”.

<!-- table:start -->
| Option | Taps from the list to saved | Screens and sheets | Entry visible without scrolling (100 % / 200 % / 310 %) | More’s rows pushed down (100 % / 200 % / 310 %) | Overflow at 100 % and 200 % | Overflow at 310 % |
| --- | --- | --- | --- | --- | --- | --- |
| DE1 | 4 | 4 | yes / yes / yes | 0 | none | none |
| DE2 | 4 | 4 | yes / yes / no | 0 | none | none |
| DE3 | 3 | 2 | yes / yes / yes | 108 px / 217 px / 444 px | none | none |
| DE4 | 4 | 4 | yes / no / no | 0 | none | none |
| DE5 | 4 | 4 | yes / yes / no | 0 | none | none |
<!-- table:end -->

A row title with one word longer than the row, like the e-mail at 200 %, breaks inside the word, as Flutter's Text does. At 310 % DE2 and DE5 also lose their entry below the fold (DE4 already at 200 %), and DE3's card pushes More's rows down by almost a whole screen.

## Open questions

- **DE-Q1** One entry or two? Default: DE1 only. DE2’s pencil on your own member tile can open the same sheet later, if testers look for it there.
- **DE-Q2** Can the name be emptied? Default: no. Save stays off for an empty field (1 to 80 characters, as in DN-Q2), so nobody goes back to “Unnamed” or an e-mail prefix.
- **DE-Q3** One name or one per household? Default: one name for all households (`profiles.display_name`, as today). DE5 is not built.
- **DE-Q4** Do household members see the change at once? Default: the next time their member list, list or join page loads, with no new realtime channel. If it should be live, publish `profiles` to realtime with a household-scoped filter. That is a separate job with its own RLS case.
- **DE-Q5** Does the new name replace the old one in older places (claims, trip summaries, join requests)? Default: yes. They all read the current name, so nothing needs migrating.
- **DE-Q6** Tell the others? Default: no notice, no history and no limit on how often it changes.
- **DE-Q7** What does the row show for an e-mail-prefix name? Default: “Add your name”, and the sheet opens empty with the hint “e.g. Lea”, not prefilled with “lea.brandt87”.
- **DE-Q8** How is it saved? Default: through `updateUser(data: {display_name})`, not a direct `profiles` update, so a later Google or Apple name can't overwrite it (DN-Q4).
