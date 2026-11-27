# hc-tick-untick: prototype candidates (job 458, not built)

Design changes the climb found but must not build (`hc-tick-untick.md`). Each one is for a later
prototype round with Peter's pick. CP1 (Peter, 26 Nov 2026): a snackbar with an Undo button
after a tick is the decision, so job 29b's rule (no undo snackbar on a tick) no longer holds.
Job 471 (PR 765) implements it. Job 469 owns the hint copy about „Zuletzt verwendet“.

## TU1: name what a tap just ticked (superseded by CP1, option (a): the snackbar with Undo)

- **Problem.** The most frequent complaint in job 455's review corpus (section 2.1, recommendation 1).
  A mistaken tap strikes the row through and slides it away in under 0.5 s, and nothing says
  which item went. The undo exists (a tap on the row in „Zuletzt verwendet“ within 10 minutes
  puts the item back and counts as no add), but it sits at the end of the list.
- **Idea (superseded).** No snackbar. For about 4 s after a tick, one line next to the add field reads
  „Abgehakt: Milch · Zurück“. „Zurück“ calls the same `readd` the „Zuletzt verwendet“ row
  calls, so analytics and the server's purchase counting stay as they are. A second tick
  replaces the name. The line takes no list height.
- **Compare.** (a) today; (b) the inline line; (c) a short undo snackbar for the last tick only,
  which job 29b removed and CP1 brought back. Measure on a 358 px screen in German. Count the taps to recover a
  mistaken tick on a 40-item list (today: scroll to the end, find the row, tap). Check how
  often the line covers what the user wants to tap next while ticking fast in a shop.

## TU2: the just-ticked rows stand out in „Zuletzt verwendet“

- **Problem.** The same as TU1, without new chrome. „Zuletzt verwendet“ lists the newest first,
  but a row ticked seconds ago looks like one bought last week.
- **Idea.** Rows still inside the undo window (10 minutes) carry a small trailing time
  („gerade eben“, „vor 3 Min.“); they come first already. After the window they look as they do
  today.
- **Compare.** Today against TU2 on a list with 30 recently used items. Measure the time to find
  and put back an item ticked by mistake (finger on the list, eyes on the section). TU2 can
  ship with TU1 or instead of it.
