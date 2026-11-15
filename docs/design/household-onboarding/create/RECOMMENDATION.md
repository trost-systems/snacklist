# Creating a household: recommendation (CH1–CH5)

**Pick: CH1, today three steps shorter.** Keep who and the name, drop the usage step, stores and “What do you need right now?” (they move to First steps and a card on the list), and let the invite step show a ready invite with Share, Copy code and “Show QR code”. It is lighter than today everywhere (6 taps to the list instead of 9, 8 to a shared link instead of 11, 6 to a QR instead of 12) and costs about 3 days.

**Runner-up: CH2, the account and then the list.** No questions at all: 3 taps to the list and 7 to a shared link, with the invite on First steps opening the job 242 invite page. It loses the kind, so the invite text and first tips stay generic, and inviting waits until Mia taps the card.

## Why

- Peter asked for a create flow no heavier than today with an easy hand-off to inviting. CH1, CH2 and CH4 are all lighter; CH1 keeps the invite step that the earlier onboarding research calls the commitment step (`docs/onboarding/research/best-practice.md`), and makes it one tap to share.
- The QR is where today is heaviest: a person invite has none, so showing one means Later, the switcher, Invite and a group link (12 taps). CH1 and CH4 put a QR on the invite step.
- CH3 (1 tap to a list) needs guest accounts, the same new account type as JH5, about 8 days. Not worth it for the create path alone.
- CH5 keeps most of today’s weight (7 taps); its two doors are worth taking into CH1 anyway (JH3’s door).

## Comparison

<!-- table -->
| Option | Taps / screens to the first list | Taps / screens to an invite shared | Questions before the list | Where the invite lives | QR | Consent | For someone invited | Build effort | Existing service |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Today** Today (main): the guided start | **9 / 9** (9 / 9) | **11 / 11** (11–12 / 11–12) | 5 (usage, who, name, stores, need) | invite step before the list; later the switcher sheet’s invite page | group link only, from the switcher | step 1, before the account | “Paste invite” under “Sign in” | 0 (live) | none |
| **CH1** Today, three steps shorter | **6 / 6** (6 / 6) | **8 / 8** (6–8 / 6–8) | 2 (who, name) | invite step before the list, invite made already | “Show QR code” on the invite step (person invite) | card on the list | “I have an invite” text button | 3 days | none |
| **CH2** The account, then the list | **3 / 3** (3 / 3) | **7 / 7** (5–7 / 5–7) | 0 | First steps card on the list → switcher invite page | group link on the invite page | card on the list | “I have an invite” text button | 3 days | none |
| **CH3** The list first, the account when you share | **1 / 1** (1 / 1) | **7 / 6** (5–7 / 4–6) | 0 | “Invite” in the list header → account → invite page | group link on the invite page | card on the list | “Join a household” door | 8 days (guest accounts, upgrade) | Supabase anonymous sign-ins |
| **CH4** Invite first, by QR or link | **6 / 5** (6 / 5) | **8 / 7** (6–8 / 5–7) | 1 (who, a pick needed) | full invite screen before the list, QR shown | on screen at once (person invite) | card on the list | “I have an invite” text button | 3 days | none |
| **CH5** Today’s steps with two doors | **7 / 7** (7 / 7) | **9 / 9** (9–10 / 9–10) | 3 (who, name, stores and items) | invite step before the list; later the switcher sheet | group link only, from the switcher | card on the list | two equal doors, and “Join their household” on step 1 | 3 days | none |

Bold: Share link; in brackets the range over link · QR · code.
<!-- /table -->

## Together with the join round

CH1 and JH3 share one start screen: “Get started” (CH1’s three steps) and “Join a household” (JH3’s code door), with “Sign in” under them. “Paste invite” goes.

## Open questions

1. **CH-Q1** Drop the usage step, the stores step and “What do you need right now?” from the guided start? Default: yes. Stores and first items become First steps rows; usage data is a card on the list with two equal buttons.
2. **CH-Q2** Make the invite as soon as the invite step opens (CH1), instead of on a tap? Default: yes. An unused invite expires after 7 days like today; the step’s “Later” leaves it unused.
3. **CH-Q3** Put the two doors (“Get started”, “Join a household”) on the start screen with CH1? Default: yes, the same door as JH3.
4. **CH-Q4** Keep “Skip” on the who step? Default: yes; the invite text falls back to today’s generic one.
5. **CH-Q5** Show a QR code on a one-person invite card? Default: yes (same as JH-Q7). It works once; a second scanner sees “This invite no longer works”.
6. **CH-Q6** Guest accounts for a list before any account (CH3)? Default: no; revisit together with JH5 if the account step shows as the main drop-off.
