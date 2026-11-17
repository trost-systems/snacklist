# Report content entry: recommendation

<!-- pick: RC2 -->
<!-- runner-up: RC3 -->

## Round RC: the in-app “Report content” entry

Peter picked NR1 on 16 Nov: a public report form on snacklist.app plus an in-app entry merged with feedback. Legal (Addendum B, N-226) allows the shared entry only if “Report content” is its own first-level choice with its own form, and the More row says reporting is there. The three options differ only in the way in. The form (N-228) and the confirmation with a reference number (N-229) are the same in all of them, in Legal’s B.4 words.

- **RC1 Chooser sheet**: the More row becomes “Feedback & reports”. A tap opens a small sheet with “Feedback & ideas” and “Report content”.
- **RC2 Two buttons in the hub**: the row stays “Feedback & ideas” with the subtitle “Also: report content”. The hub has “Report content” right under “Write to Snacklist Support”. Without FB4 the button sits at the top of the feedback sheet.
- **RC3 Its own More row**: “Report content” is also a row of its own, right under the feedback row. The hub keeps RC2’s button.

## Measured

Measured by `verify.mjs` in Chromium on the 390 × 844 phone, in English and German, at 100 % and 200 % text, with FB4’s hub on and off (it is off for every user today).

<!-- table -->
| Option | More names reporting (FB4 on / off) | Taps from More to the report form, FB4 on / off | Report choice in view where it is offered (100 % and 200 %, both FB4 states) | Taps to write feedback, FB4 on / off (today 2 / 1) | Taps to notes and ideas, FB4 on (today 1) | Report offered on the feedback screen (hub or sheet), FB4 on / off | Feedback group on More vs today, 100 % / 200 % (more of FB4 on and off) | Text cut, outside or overlapping at 200 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Today | no / no | none (e-mail only) / none (e-mail only) | — | 2 / 1 | 1 | no / no | 0 px / 0 px | 0 |
| **RC1 Chooser sheet** | “Feedback & reports” / “Feedback & reports” | 2 / 2 | yes | 3 / 2 | 2 | no / no | 0 px / +46 px | 0 |
| **RC2 Two buttons in the hub** | “Also: report content” / “Also: report content” | 2 / 2 | yes | 2 / 1 | 1 | yes / yes | +2 px / +76 px | 0 |
| **RC3 Its own More row** | “Report content” / “Report content” | 1 / 1 | — (the More row itself) | 2 / 1 | 1 | yes / yes | +56 px / +63 px | 0 |
<!-- /table -->

All three pass the same Legal checks, run on a form reached from More in every option, with FB4 on and off, in both languages and sizes: six kinds including child sexual abuse material, no report kind in the feedback form, the picked item shown for the user to confirm, 20 to 5,000 characters, good faith required, name and e-mail prefilled but not required (hidden by default for child abuse material, with a way to add them), a reference number on screen in Legal’s confirmation text word for word, Done back to where the report started, the report never under Your notes, and the feedback form’s kinds only Bug, Idea and Other. Every B.4 string in `copy.js` is checked word for word against Legal’s addendum. Two cuts are disclosed: the screenshot label drops “in the app”, and the help under “Where is the content?” keeps only the app’s sentence, shown once something is picked.

### Pick: RC2 Two buttons in the hub

RC2 is NR1 as Peter described it and N-226 as Legal worded it: the report entry sits next to “Write to Snacklist Support”, where someone who opens feedback looks. It costs feedback nothing: writing stays 2 taps with the hub (1 without), the hub 1 tap, and the report form is 2 taps away. It keeps FB4’s row label and adds Legal’s subtitle “Also: report content”, so More names reporting without renaming the row FB4 just introduced. Its cost is height: the subtitle adds 2 px at 100 % and up to 76 px at 200 %, where it wraps.

### Runner-up: RC3 Its own More row

RC3 is RC2 plus a More row named “Report content”: the most findable, and the form is 1 tap from More. The row costs everyone a line in More (+56 px at 100 %) for something few people will ever need, and it splits reporting from feedback again, where Peter asked for one entry. Take it over RC2 if Legal or Peter wants a separate menu item rather than a subtitle.

RC1 puts a sheet in front of feedback: every visit to the hub costs a tap more (2 instead of 1, writing 3 instead of 2), to make room for an entry most people never use. Its report choice sits next to “Feedback & ideas” in the chooser, not next to “Write to Snacklist Support” in the hub, which Legal would have to confirm as meeting N-226’s first bullet.

### Open questions

1. RC-Q1: Row label in RC2. Default: keep “Feedback & ideas” with the subtitle “Also: report content” (Legal’s second route). Without FB4 the row is “Send feedback” with the same subtitle, which Legal has not seen. The other route renames the row and the hub title to “Feedback & reports”. The Impressum text (B.3) names the path, so it must use the label picked here.
2. RC-Q2: An entry in an item’s menu (N-240, optional, once photos ship). Default: not in this round; with photos, “Report content” in the item’s and the photo’s menu opens the same form with that item preselected.
3. RC-Q3: Where does the reporter see their report’s status (N-227 allows their own)? Default: by e-mail only, the confirmation and the decision. No in-app list, so reports never come near Your notes.
4. RC-Q4: The screenshot row. The prototype always shows it. Default for the build: only where FB2’s capture and annotator exist (flag feedback-fb2), never taken automatically, with the annotator’s cover tool; without FB2 the row is hidden.
5. RC-Q5: Name and e-mail for a guest account without an e-mail. Default: the fields are empty, the same “recommended” label and help text apply.
6. RC-Q6: Flag. Default: its own flag (N-226: until the B.3–B.8 texts have a hash-bound GO), independent of feedback-fb2 and feedback-fb4, and the web form ships first (N-239).
7. RC-Q7: At 200 % text B.4’s intro fills the form’s first screen, and only “What is it about?” shows below it. Default: keep Legal’s intro first, as built.
