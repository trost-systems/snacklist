# Job 356: invite joiners land on the shared list

**Built.** Behind the new PostHog flag `joiner-direct-list` (internal installs: Peter and the
testers, via the flag sync's `is_internal` condition; rollout `partial` in `releases/flags.json`):

- An invite link or code goes: sign-in (with the new line on why an account is needed), the
  usage-data question if the install has not answered it, „Wie sollen wir dich nennen?“, then the
  invited household's list. No „Haushalt beitreten“ tap, also with JH2 off. A household that
  confirms new members still shows the request wait.
- The sign-in for an invite shows under the logo: „Ein Konto brauchst du, damit die gemeinsame
  Liste mit dem Haushalt synchron bleibt, zu dem du eingeladen wurdest.“ / "You need an account so the
  shared list stays in sync with the household you were invited to." (`joinerAccountWhy`, new, needs Legal).
- Flag off: unchanged, with JH2 on and off.

Decisions: `docs/DECISIONS.md`, "Job 356".

**Where.** `app/lib/onboarding/start_screen.dart`, `onboarding_cubit.dart` 
`join_cubit.dart` (auto-join), `app/lib/session/login_screen.dart`, `app/lib/analytics/flags.dart`,
ARB files, `releases/flags.json`.

**Verify.**
- Widget tests: `app/test/onboarding/joiner_direct_list_test.dart` (start screen has no code button, code to list,
  link; iOS and Android variants; flag-off counterparts), `app/test/session/login_screen_test.dart`
  (the line in DE and EN, not without invite, not flag off).
  (The first version's tests were each broken once to see them fail; not repeated for the rebase.)
- Web: the first version's spec `joiner-direct-list.spec.ts` was dropped in job 373: the e2e budget (`e2e/budget.json`, 300 tests) was full, and the behaviour is widget-tested; the link join with JH2 on stays in `join-jh2.spec.ts`. The screenshots come from that earlier web run.
- Screenshots: `docs/screenshots/356/`.

**Not merged here.** The new sign-in line is new sign-up copy: the PR waits for Legal (NEEDS_LEAD).
On TestFlight: the next green main build after the merge, flag `joiner-direct-list` (on for
internal installs only once the flag sync has run on main).

**Changed Nov 22 (job 373, rebase).** Peter removed the start screen's „Mit Code beitreten“ button and the draft's `code_first` path; the start screen keeps „Los geht's“ and the login. `joinerAccountWhy` is now DE „… mit dem Haushalt synchron bleibt, zu dem du eingeladen wurdest.“ (N-331), and the start login label is „Ich habe schon ein Konto“ (`startLogIn`, `jh2StartHaveAccount`, G1).
