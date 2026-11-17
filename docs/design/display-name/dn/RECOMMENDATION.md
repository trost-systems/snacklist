# Round DN: asking for the name in onboarding
<!-- pick: DN3 -->
<!-- runner-up: DN4 -->

## Recommendation

**Pick: DN3 Confirm after sign-in.** Every path to a shared list passes the sign-in: people who create a household and people who join by invite. Right after it, one screen asks once. With a Google or Apple name it shows that name with “Yes, that’s me”: one tap, no typing. Without one (an e-mail sign-up, or Apple with the name not shared) the field is empty and required. This is Peter’s “How should we call you?” in onboarding, for everyone, and nobody reaches the list as “lea.brandt87”. It costs every new user one screen and one tap, solo users included.

**Runner-up: DN4 Asked when it first matters.** It is the cheapest option: 0 taps and 0 screens when Google or Apple hands over a name, and the sheet says why it asks (“Your partner sees who the invite is from”). But “Not now” keeps the e-mail prefix in the member list. The question also comes at the moment of sharing, and solo users who invite weeks later meet it then. Pick it instead if one more screen in onboarding matters more than a name for everyone.

Not picked:
- **DN1 A step of its own** asks before the account, when the Google or Apple name is not known yet. So everyone types, Google users too, and a joiner gets a second version of the screen after sign-in.
- **DN2 A field on the household-name step** adds no screen but an optional second field. Left empty (the walk’s skip path), today’s “lea.brandt87” stays, and joiners need the field again on the join screen.
- **DN5 The first question, skippable** feels personal (“Lea, who do you shop with?”). But it asks before Google or Apple can fill it, and Skip leaves the e-mail prefix.

## Measured

The verify script walks each option with real clicks, from “Who do you shop with?” (or the join page) to the list. It counts every tap, the tap into a field that does not get the focus by itself included. The table gives the difference to today for the same person. A Google or Apple sheet counts one tap, and typing counts no taps. “If skipped” is the path that never types a name where that can be left out. Overflow is text cut, spilling past the phone, overlapping, or a target under 44 px. It was checked on every screen of every walk and frame, in English and German, at 100 %, 200 % (Android's largest, and WCAG's figure) and 310 % (iOS's largest accessibility size; the app has no global cap), for five people (e-mail, Google, Apple without a name, a 49-character name, a name with an emoji).

<!-- table:start -->
| Option | Screens added, create (e-mail / Google) | Taps added, create (e-mail / Google / Apple hidden) | Taps added, join (e-mail / Google) | Typing, create (e-mail / Google / Apple hidden) | Peter sees (e-mail) | If skipped (create / join) | Overflow at 100 % and 200 % | Overflow at 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| today | 0 / 0 | 0 / 0 / 0 | 0 / 0 | no / no / no | lea.brandt87 | lea.brandt87 / lea.brandt87 | none | none |
| DN1 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | yes / yes / yes | Lea | required / required | none | none |
| DN2 | 0 / 0 | +1 / +1 / +1 | +1 / 0 | yes / yes / yes | Lea | lea.brandt87 / lea.brandt87 | none | none |
| DN3 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | yes / no / yes | Lea | required / required | none | none |
| DN4 | +1 / 0 | +1 / 0 / +1 | +1 / 0 | yes / no / yes | Lea | lea.brandt87 / lea.brandt87 | none | none |
| DN5 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | yes / yes / yes | Lea | lea.brandt87 / lea.brandt87 | none | none |
<!-- table:end -->

Read the table this way. Every option costs an e-mail user one tap. They differ for Google and Apple users, and in what is left when someone skips. Only DN1 and DN3 can’t be skipped, and of those two only DN3 needs no typing from Google users. At 310 % no screen of any option overflows. Long words break as Flutter breaks them, and the steps scroll.

## Open questions

- **DN-Q1** Required or optional? Default: required. DN3’s “Continue” stays off until the field has 1 character, and there is no Skip.
- **DN-Q2** How long? Default: 1 to 80 characters (the database limit, the same as the household name), with Flutter's counter “n/80” under the field, as on the household-name step (screen readers hear “67 characters remaining”).
- **DN-Q3** First name or full name? Default: free text labelled “Your name”, prefilled with the full Google or Apple name. The join page keeps showing only the first word, as today.
- **DN-Q4** Does a later Google or Apple name overwrite one the user set? Default: no, and today's code does not guarantee that. `handle_user_metadata_update` replaces the profile name whenever it equals the name derived from the old metadata. That covers the e-mail prefix, and also the old Google or Apple name. So a “Yes, that's me” written straight to `profiles` would be overwritten by Apple's first sign-in or a linked Google identity. Default: every name write (DN3's confirm or field, DE1's sheet) goes through `updateUser(data: {display_name})`, which `default_display_name` ranks first. The trigger then copies it into `profiles` and keeps it against later provider names. This was checked in a scratch Postgres with the two real functions. Written straight to `profiles`, a confirmed “Lea Brandt” became “Lea M. Brandt” after a metadata change. Written as `display_name` metadata it stayed “Lea Brandt”, and a later change to “Lea” went through. The prototype's `source: chosen` is this target, not today's behaviour.
- **DN-Q5** Existing users with an e-mail-prefix name, like the household member who asked? Default: they get DN3’s screen once at the next app start, with “Not now” for them only, and from then on the Account row (DE1).
- **DN-Q6** Where exactly? Default: creators see it after the account and before the household is set up, as a counted step of its own (“Step 7 of 8”, so the bar moves). Joiners see it before the join screen, so a join request (“Confirm new members”) already carries the name.
- **DN-Q7** Which characters? Default: anything printable, emoji included. Trim and collapse spaces, with no word filter. The 49-character name and “Lea 🌻” fit at 200 % in every option.
- **DN-Q8** Analytics? Default: no new event and never the name. If wanted, `display_name_set` with only `prefilled: true|false`, added to the allow-list.
