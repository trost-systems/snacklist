# hc-add-item-voice: prototype candidates

Job 457 found these while climbing the add sheet and dictation. Each one changes the
interaction or the layout, so the climb did not build it. Each entry is meant for a later
prototype round, and each needs a pick before it is built.

Evidence. A scratch scan typed 37 lines into the real add sheet with the users' flags and
pressed Enter after each (the setup of `app/test/list/add_item_probe_test.dart`). Each section
names the lines it saw.

## 1. Enter on a ticked match drops what was typed

- **Problem.** When only a ticked item matches, Enter puts that item back as it was. With
  „Milch“ ticked, „2x Milch“ and „Weihenstephan Milch 1,5%“ both put back plain „Milch“. The
  amount, brand and details the user typed are lost without a word. This is documented
  (`quick-add.md`, `qa-match-rows`: „A typed amount does not count then“), so it is by design,
  and it is easy to miss. The user typed more than the name, and the `+` row with their text
  sits below the grey row.
- **Idea.** When the typed line carries more than the name (an amount, a brand or details
  that the device parse finds), Enter takes the `+` row, or puts the item back with the
  typed amount, brand and details.
- **Compare.** (a) today's put-back. (b) put back with the typed fields merged in. (c) Enter
  takes the `+` row whenever the parse finds more than the name. Measure taps to get
  „2× Milch“ on the list from a ticked „Milch“, and whether a tester notices the dropped
  amount.

## 2. Offline dictation leaves one sentence that Enter adds as one item

- **Problem.** Offline, the server's splitter can't be reached. The field keeps „Milch und
  Brot“ and the snackbar says to check it. Enter then adds one item named „Milch und Brot“,
  which is the merged item voice users complain about (competitor pain points 2.5). A typed
  „Milch, Brot“ is also one item.
- **Idea.** Split on the device when the server can't be reached, at commas and „und“ / "and",
  the way the voice function's splitter does. Show the parts as rows the user can take one
  by one, or add them all with one tap. A typed line with commas could get the same rows.
- **Compare.** (a) today. (b) a device split that adds every part at once. (c) one sheet row
  per part. Check against the server's split table (`supabase/functions/voice/parse_test.ts`)
  so a device split never disagrees with the online one. Number words and „Drei Glocken
  Nudeln“ are the hard cases.

## 3. A line that is only an amount becomes an item

- **Problem.** Typing „2“ and pressing Enter adds an item named „2“.
- **Idea.** Treat a bare amount as an unfinished line. Enter does nothing and the field keeps
  „2 “ for the name, or the first row reads „2 …“.
- **Compare.** Whether testers ever mean a bare number, and what the sheet shows instead.

## 4. Dictating over typed text replaces it

- **Problem.** A tap on the microphone with „Milch“ already typed replaces „Milch“ with the
  spoken words, and the typed word is never added. This was read from the code, not driven.
  `DictationButton` sets the field to the words heard, and only the dictated sentence is
  split.
- **Idea.** Add the typed line first, or keep it in front of the spoken words.
- **Compare.** (a) today. (b) the typed line becomes the sentence's first part. (c) the
  microphone is greyed out while text is typed.
