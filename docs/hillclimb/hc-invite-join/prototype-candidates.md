# Prototype candidates: household invite and join (job 460)

Found while climbing `hc-invite-join.md`. Each one changes the design (steps, chrome or the
interaction model), so none is built. Each entry names the problem, the idea and what a prototype
round should compare.

## 1. The switcher's „Mit Code beitreten“ takes one action more than the guided start

- **Problem.** Signed in, a code typed at `/join` (`JoinScreen`) takes three actions: type the code,
  tap „Weiter“, tap „Haushalt beitreten“. The guided start's code step (`JoinCodeScreen`) takes two:
  it looks the code up at the 8th character, shows who invites to which household, then
  „Beitreten“. A person who joins from the switcher meets the older form.
- **Idea.** Give the switcher the guided start's step: lookup at the 8th character, the preview card
  (inviter, household, members, open items), one button.
- **Compare.** Today's `JoinScreen` against the `JoinCodeScreen` layout in the switcher, at 358 px
  and with a pasted link. Count the actions and the time to the list. Check that
  „Haushalt beitreten“ stays a deliberate tap for a typed code (JH-Q6 asked for no tap only for a
  link).

## 2. Rate limited on the code step has no way forward

- **Problem.** After „Gerade zu viele Versuche“ on the guided start's code step there is no button.
  The same code in the field is not looked up again (`JoinCodeCubit.changed` ignores an unchanged
  code), so the user has to delete a character and type it again. `JoinScreen` keeps „Weiter“ for
  this case.
- **Idea.** Either a retry like the offline case, or a line that says when to try again.
- **Compare.** A retry button, a timed hint, and today. The server limit is per hour, so measure
  how often a retry within the hour still fails.

## 3. Cancel while a link joins

- **Problem.** While a link joins without asking (JH2), „Abbrechen“ stays on. A tap forgets the link
  and leaves, but `accept_invite` is already out, so the user can still be in the household
  afterwards.
- **Idea.** Hide or disable „Abbrechen“ while it joins, or say „Beigetreten“ afterwards when a
  cancel came too late.
- **Compare.** The three variants on a slow network (the join takes 1 to 15 s).

## 4. A guided-start code refused at the join loses the guided start

- **Problem.** „Beitreten“ on the code step drops the guided start (its name) before the join at
  `/join/<code>` runs, so the router cannot set it up in the joined household. If the server then
  refuses (the code was used in between, 20 households), „Abbrechen“ leads back to the start
  screen. The name the user typed is gone.
- **Idea.** Keep the draft until the join answers, and make the router skip its setup while a join
  is pending. Or offer „Eigene Liste anlegen“ on that refusal, like the approval wait does.
- **Compare.** Both against today, signed in and signed out, including the race test in
  `onboarding.spec.ts` (two people, one code).

## 5. Offline at a link's join: no retry when the connection is back

- **Problem.** A link that was joined without asking but failed offline shows the offline line and
  „Haushalt beitreten“. Nothing retries on its own when the device is back online.
- **Idea.** Retry the join once when connectivity comes back, while the screen is open.
- **Compare.** Today and an automatic retry. Watch for a second join on flaky connectivity and for
  the iOS connectivity quirk (a fresh monitor reports none).
