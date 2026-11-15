# Recommendation: FB3, runner-up FB2

**Pick FB3, “Report this, where it happens”.** It asks at the moment something went wrong and sends exactly that: where the user moved an item, or which change the server refused. That gives Peter 5 and 8 of 14 debug points in those cases, against FB1’s 3, at medium exposure (6, and the only option that sends the item name by default, behind a chip the user can remove), with no new processor and no images, in about 5 days on today’s stack. Shake only fires near an error, never when the phone is merely offline.

**Runner-up FB2, “Shake, then mark it on a screenshot”.** It gives Peter the most for a wrong category (7 points) and is the only option that shows layout bugs. It costs about 7 days, though, and adds images and on-device step logs to storage and the privacy policy (exposure 8).

<!-- table -->
| Option | Taps (wrong category · change rejected · idea) | Debug points of 14 | Privacy exposure | Build (estimate) | Existing service | User hears back |
| --- | --- | --- | --- | --- | --- | --- |
| Today | 3 · 3 · 3 | 2 · 2 · 2 | low (4) | live | none | by mail, if ticked |
| FB1 | 2 · 2 · 2 | 3 · 3 · 3 | medium (7) | 3 days | none | by mail, if ticked |
| FB2 | 4 · 4 · 3 | 7 · 7 · 2 | medium (8) | 7 days | none | by mail, if ticked |
| FB3 | 6 · 2 · 3 | 5 · 8 · 1 | medium (6), names the item | 5 days | none | by mail, if ticked |
| FB4 | 4 · 4 · 4 | 2 · 2 · 2 | low (4) | 9 days | none | in the app |
| FB5 | 3 · 3 · 3 | 2 · 7 · 2 | medium (7) | 6 days | PostHog EU + Sentry EU | by mail, if ticked |
<!-- /table -->

Every option is measured in the same three situations. In FB3, 4 of the 6 taps for a wrong category are today’s own fix (long-press, category, Chilled, Done); telling Peter adds 2. FB5’s 7 points for a rejected change need the usage-data yes (only then does Sentry have the error); without it they are 2. Extra entries that fit no single situation are frames on each option’s page, not cells: FB5’s crash prompt and survey (2 taps each), FB4’s +1 on a listed idea (3 taps) and FB3’s paywall question.

## Why FB3 beats the table’s cheaper rows

- **FB1** is cheaper (2 taps, 3 days), but every note it sends is generic: Peter learns the screen and the phone, not what went wrong, so he has to ask back. Its shake is on by default, and accidental shakes in the shop are the cost.
- **FB3’s item chip goes against the research’s “nothing attached unless the user switches it on”.** It is still the right call here: the user just moved that very item and tapped “Tell Peter”, the chip says what goes, and one tap removes it. Legal has to confirm this reading in the §10 redline (FB-Q2) before anything ships.
- **FB2** is the strongest debugging tool and the natural next step on top of FB3, once Legal has the image and step-log text.
- **FB4** gives users answers in the app, but it is the most work and only pays once outside users write regularly. Until then, Peter answers by mail when the contact box is ticked.
- **FB5** adds Sentry, a new processor that keeps account data in the US and lists LLM subprocessors for its AI features. Those can be switched off org-wide, but the processor is still new. Crash linking can come later with its own Legal review.

## What the production build takes from the others

- FB1’s preview: every attached field with its value and a switch (FB3 already shows it).
- #281’s detector and quiet rules for FB3’s short shake window. #281 is then closed or reworked into this build (SH2).
- The daily digest (job 225) as the way Peter reads notes, grouped by context (FB-Q5).

## Open questions

1. **FB-Q1 Shake in the production build.** Default: contextual only, as in FB3 (iOS and Android; for 2 minutes after “Change rejected” or while “Sync failing” shows; never because of offline alone; web no-op). #281’s detector moves into that build, and #281 is closed.
2. **FB-Q2 The item chip.** When the user reports from a moved or rejected item, is its name in the report by default? Default: yes, as a chip the user sees and can remove, because they started from that item. Legal confirms this in the §10 redline before the build ships. Tapping “Tell Peter” counts as consent to send what the sheet then shows: the item name and its old and new category, nothing else from the list, and only after Send. If Legal says no, the chip starts off and the report still sends the categories (“Pantry → Chilled”) without the name. FB3 then keeps its 5 points for a wrong category, because the categories are the case; with the categories removed too it falls to 2. The digest counts a move across households only from reports whose chip was kept, so it never names an item from a household that removed it.
3. **FB-Q3 Which of #281’s context fields ship.** Default: for FB3, only today’s fields (screen, app version, platform and OS, language) and no device model. Theme, text size, orientation, online and Premium status ship only if a later report kind needs them.
4. **FB-Q4 The Shake SDK for screenshots later.** Default: no. Revisit only if Shake confirms in writing that its AI assistant stays off for our organisation, and if the free plan’s one-month retention and report limit fit.
5. **FB-Q5 The daily digest.** Default: switch on job 225’s digest after Legal’s GO, on two conditions. First, Workspace’s Gemini and smart features stay off for the hello@snacklist.app mailbox. Second, the policy says that the digest passes through Resend, which keeps mails 30 days in the US (DPF and SCCs, as for sign-in mails). With FB3, a kept item chip appears in that mail.
6. **FB-Q6 Replies and status (FB4).** Default: not in the first build. Peter replies by mail when the contact box is ticked. Revisit when outside notes reach about 10 a week.
7. **FB-Q7 The paywall entry “Question about the price?”.** Default: yes, behind the same flag as the paywall, sending store and plan and no payment details.
8. **FB-Q8 What a context report sends when the user writes nothing, and what a rejection carries.** Default: allow an empty message for context reports only (`context_kind` set). The database check (1 to 2000 characters) relaxes for that case alone, and a general note still needs text. A rejection report carries the op kind and the server code (`add`, `42501`). Today `ItemRejected` keeps only the item name, so the build adds them.
9. **FB-Q9 Job 259 (menu-opened feedback drops the current screen).** Default: yes. The More form sends no screen, and contextual reports send their own. If 259 lands first, this sandbox’s Today is rebased to match.
10. **FB-Q10 When FB3’s new “Tell Peter” snackbar shows.** Today, Done in the edit sheet shows no snackbar. Default: only when the user changes a category the app picked itself, once per item, and not again for the same item kind (`canonical_key`) in that household for 30 days. A category the user set before never asks.
