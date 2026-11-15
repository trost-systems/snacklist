# Joining a household: recommendation (JH1–JH5)

**Pick: JH5, name first, account later.** It is the fewest taps to the shared list in the app in every one of the 12 scenarios: 2 with the app installed (tap the link, type a first name, Join), 6 without it, 4 to 7 with a typed code. From a link or QR without the app, two options reach a first list sooner, in a smaller place: JH2 in the browser and JH4 in an App Clip (4 taps each). JH5 wins mostly by moving the sign-in to a “Keep your access” card after the join. It needs no new service (Supabase anonymous sign-ins are part of our stack), nothing is read from the device except the clipboard on her own Paste tap (as “Paste invite” does today), and the wait tells Ida what Mia sees. The cost is a new kind of account: about 10 days for guest accounts, the invite check at sign-up, closing the signed-in functions to guests, saving them later, deletion and export (JH-Q10).

**Runner-up: JH3, two doors.** If Peter doesn't want guest accounts: an equal “Join a household” door replaces “Paste invite”, the landing names Mia and the household before any account, and nothing is read from the device or sent to a new service, in about 4 days. It costs taps: 5 with the app and 9 without (going back to the chat after installing is 1, answering the usage-data sheet over the list is 1), against JH5's 2 and 6; with usage data as a card, like the other options, it would be 4 and 8.

## Why

- A referred user often does not have the app yet (an assumption; nothing measures it today). Today such a user reaches a list only in the browser (6 taps), and the list in the app only after 14. Every option shows Mia and the household before the account; today's app does not.
- Taps to the shared list in the app, link without the app: JH5 6, JH1 7, JH4 7, JH3 9, JH2 10 (4 to the list in the browser), Today 14. With the app: JH5 2, JH1, JH2 and JH4 4, JH3 and Today 5.
- JH1's deep-link service saves JH3 2 taps without the app but adds a new US-parented processor and device matching that Legal N-111 rules out without a tap first; its numbers already include that tap. JH5 is 1 tap better without it.
- JH4 (App Clip) matches JH1 on taps but is iOS only, needs a second iOS target with Flutter in the clip, and about 15 days.
- JH2 is the only path to a shared list without installing anything. Its weak spot is the typed code (11 taps, through sign-in and Welcome).
- Every new option asks usage data after the join, not before it, and no wait offers “Create your own household” as its main button.

## Comparison

<!-- table -->
| Option | Taps / screens to the first shared list | Taps / screens to the shared list in the app | “Paste invite” | Manual “I have an invite” | Not installed (deferred link) | First list in | Approval wait | Consent | Privacy exposure | Build effort | Existing service |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Today** Today (main) | **6 / 5** (5–11 / 4–8) | **14 / 11** (5–14 / 4–12) | kept, on start and sign-in | “Paste invite” on start and sign-in; “Join with an invite” after sign-in | none: web join stays in the browser; Paste invite if the code was copied | app (installed) or browser | “Request sent”; first button “Create your own household” | full screen before the join, again per install | low: nothing new | 0 (live) | none |
| **JH1** The store remembers the invite (deep-link service) | **7 / 5** (4–9 / 3–8) | **7 / 5** (4–9 / 3–8) | gone | “I have a code” in the start screen’s invite card | the service matches the install to the tap, after “I was invited” (iOS by IP and device type; Android by store referrer) | app | “Mia will let you in”, list opens by itself, no “create your own” | card on the first list | high: new US-parented processor gets IP, user agent, device data at click and first start | 7 days + DPA, Legal | Branch or AppsFlyer OneLink |
| **JH2** Join in the browser, then get the app | **4 / 3** (4–11 / 3–10) | **10 / 7** (4–11 / 3–10) | gone | “Join with an invite” on Welcome, after sign-in only | not needed: she joins on the web; the membership is on her account | browser (app installed: app) | kind wait; “Get the app” offered while waiting | card on the list; asked again in the app (per install) | low: nothing new | 4 days | none (today’s web app) |
| **JH3** Two doors: tap the link again, or type the code | **9 / 7** (5–10 / 4–9) | **9 / 7** (5–10 / 4–9) | gone | “Join a household”, an equal second door on the start screen (code or QR) | the join page says “get the app, then tap the link again”; the code is the fallback | app | kind wait, says what Mia sees | sheet over the first list (1 tap) | low: nothing read from the device | 4 days (scanner later, JH-Q8) | none |
| **JH4** App Clip: join before installing | **4 / 4** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | gone | “I have an invite code” under the start buttons | iOS: the App Clip joins and hands the session to the app; Android: web join | App Clip, then app | kind wait inside the clip | none in the clip; card in the app | low: Apple only (already the store) | 15 days (second iOS target, Flutter in a clip) | Apple App Clips |
| **JH5** Name first, account later; a clear wait | **6 / 5** (2–7 / 2–7) | **6 / 5** (2–7 / 2–7) | gone; a system Paste button on the first start | “Type a code” in the first start’s invite card | the join page’s store button copies the invite; the app’s Paste button reads it on her tap | app | wait shows what Mia sees, offers a notification | card on the list, after “Keep your access” | medium: a guest account without email; clipboard read on her tap | 10 days (guest accounts, invite check, upgrade; JH-Q10) | Supabase anonymous sign-ins |

Bold: Invite link, Not installed, Off; in brackets the range over all 12 scenarios.
<!-- /table -->

## What JH5 should take from the others

- From JH3: “Join a household” as a visible second door on the start screen, for someone who has a code and no link.
- From JH2: the join page keeps “Join in the browser” as a text button for people who don't want the app.
- One code entry, not two: the door opens the same code screen as JH5's “Type a code”, so the start screen keeps the door and the first-start Paste card and drops “Type a code”.
- Without the app, JH5's 6 taps need the join page's App Store button, which shows once the store listings are public (JH-Q2). Until then the path goes through “Join in the browser” or a typed code.

## Open questions

1. **JH-Q1** Remove “Paste invite” from the start and sign-in screens? Default: yes. The “Join a household” door (a code field) and, on a first start, JH5's “Coming from an invite?” card with the system Paste button replace it; “Join with an invite” stays on Welcome.
2. **JH-Q2** Which button leads on the join page when the app is missing? Default: “Get the app” once the store listings are public (`storeListings` in `app/web/join/join.js`); until then “Join in the browser” stays the main button.
3. **JH-Q3** Add a deep-link service (JH1) for installs that lose the link? Default: no. Revisit if, on iOS, more than 30 % of join-page opens are not followed by a join within 24 hours, counted from our own join records with no new event.
4. **JH-Q4** Bring back the Android install referrer, read only after a tap on “I was invited”? Default: no. Ask Legal only if Android shows the same loss.
5. **JH-Q5** Ask usage data after the join instead of before it? Default: yes, with today’s wording and two equal buttons. Legal confirms that the order change needs no new text.
6. **JH-Q6** On the approval wait, drop “Create your own household” as the main button? Default: yes. The wait says what Mia sees and that the list opens by itself; “Start my own list instead” moves to a text button on the landing.
7. **JH-Q7** Show a QR code for one-person invites too (today only group links have one)? Default: yes, on the invite card.
8. **JH-Q8** Build a QR scanner into the “Join a household” screen? Default: not in the first version. The phone’s camera opens the link already; the button in the prototype shows where it would go.
9. **JH-Q9** May the app’s own landing show the join page’s facts (first name, household, counts, Premium) before sign-in? Default: yes, the same `preview_invite_public` answer and nothing more. Legal confirms that N-112 / N-151b cover the in-app copy.
10. **JH-Q10** Build guest accounts (Supabase anonymous sign-ins) for JH5? Default: yes, only for joining by invite, and no captcha (Supabase's captcha providers would be a new processor). A guest gets the `authenticated` role, so today every function open to signed-in users would be open to it; the build adds three things. A `before-user-created` auth hook refuses an anonymous sign-up whose metadata carries no valid invite code, and the app joins right after. The functions that create households, lists, API tokens, Siri credentials, OAuth devices or purchases refuse a session with `is_anonymous` until the account is saved. Failed codes are limited per network (the salted `X-Real-IP` hash the join page uses), not only per user, since each guest is a new user. A “Keep your access” card links Apple, Google or email; a guest who never saves is deleted with the household's normal rules. About 10 days. If no, JH3.
11. **JH-Q11** May the join page's “Get the app” copy the invite to the clipboard (JH5)? Default: yes, on that tap only, with the line “The button copies your invite” under it; the app reads it only on the user's Paste tap.
