# Joining a household: recommendation (JH1–JH5)

**Pick: JH3, two doors.** The start screen gets “Join a household” as an equal second door in place of “Paste invite”, an installed app opens a landing that names Mia and the household before any account, and nothing is read from the device or sent to a new service. It costs about 4 days, keeps the join to 4 taps when the app is installed, and the code door catches everyone the store loses.

**Runner-up: JH2, join in the browser first.** It is the only flow that puts a referred user into the shared list without installing anything (4 taps), on the stack we run today. The cost is a second sign-in and a second consent answer once she gets the app (10 taps to the list in the app).

## Why

- Referred users mostly arrive without the app. With today’s link they reach a list only in the browser, and in the app only after 14 taps. JH3 gets them into the app’s list in 7, JH5 in 6, JH4 in 7.
- Legal N-111 rules out any automatic read on first start. JH1’s deep-link service needs one (device data at first start, fingerprinting on iOS) or a tap first, plus a new US-parented processor. It saves nothing over JH3 when the app is missing (7 taps each).
- JH4 (App Clip) is the smoothest on paper, but it is iOS only, needs a second iOS target with Flutter inside the clip’s size limit, and about 15 days. Keep it for later.
- JH5 has the fewest taps (2 with the app), but it adds guest accounts: a new account type for deletion, export and abuse limits, and lost access if a guest never saves.
- Every new option asks usage data after the join, not before it, and the approval wait no longer offers “Create your own household” as its main button.

## Comparison

<!-- table -->
| Option | Taps / screens to the first shared list | Taps / screens to the shared list in the app | “Paste invite” | Manual “I have an invite” | Not installed (deferred link) | First list in | Approval wait | Consent | Privacy exposure | Build effort | Existing service |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Today** Today (main) | **6 / 5** (5–11 / 4–8) | **14 / 11** (5–14 / 4–12) | kept, on start and sign-in | “Paste invite” on start and sign-in; “Join with an invite” after sign-in | none: web join stays in the browser; Paste invite if the code was copied | app (installed) or browser | “Request sent”; first button “Create your own household” | full screen before the join, again per install | low: nothing new | 0 (live) | none |
| **JH1** The store remembers the invite (deep-link service) | **7 / 5** (4–9 / 3–8) | **7 / 5** (4–9 / 3–8) | gone | “I have a code” in the start screen’s invite card | the service matches the install to the tap, after “I was invited” (iOS by IP and device type; Android by store referrer) | app | “Mia will let you in”, list opens by itself, no “create your own” | card on the first list | high: new US-parented processor gets IP, user agent, device data at click and first start | 7 days + DPA, Legal | Branch or AppsFlyer OneLink |
| **JH2** Join in the browser, then get the app | **4 / 3** (4–11 / 3–10) | **10 / 7** (4–11 / 3–10) | gone | “Join with an invite” on Welcome, after sign-in only | not needed: she joins on the web; the membership is on her account | browser (app installed: app) | kind wait; “Get the app” offered while waiting | card on the list; asked again in the app (per install) | low: nothing new | 4 days | none (today’s web app) |
| **JH3** Two doors: tap the link again, or type the code | **7 / 6** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | gone | “Join a household”, an equal second door on the start screen (code or QR) | the join page says “get the app, then tap the link again”; the code is the fallback | app | kind wait, says what Mia sees | sheet over the first list | low: nothing read from the device | 4 days | none |
| **JH4** App Clip: join before installing | **4 / 4** (4–9 / 3–8) | **7 / 6** (4–9 / 3–8) | gone | “I have an invite code” under the start buttons | iOS: the App Clip joins and hands the session to the app; Android: web join | App Clip, then app | kind wait inside the clip | none in the clip; card in the app | low: Apple only (already the store) | 15 days (second iOS target, Flutter in a clip) | Apple App Clips |
| **JH5** Name first, account later; a clear wait | **6 / 5** (2–7 / 2–7) | **6 / 5** (2–7 / 2–7) | gone; a system Paste button on the first start | “Type a code” in the first start’s invite card | the join page’s store button copies the invite; the app’s Paste button reads it on her tap | app | wait shows what Mia sees, offers a notification | card on the list, after “Keep your access” | medium: a guest account without email; clipboard read on her tap | 8 days (anonymous sign-in, upgrade, abuse limits) | Supabase anonymous sign-ins |

Bold: Invite link, Not installed, Off; in brackets the range over all 12 scenarios.
<!-- /table -->

## What JH3 takes from the others

- From JH5: the join page’s “Get the app” also copies the code, and the code screen has the system Paste button (it reads the clipboard only on that tap, without the iOS prompt). This is today’s “Paste invite” read, moved to where it is expected.
- From JH2: the join page keeps “Join in the browser” as a text button for people who don’t want the app.

## Open questions

1. **JH-Q1** Remove “Paste invite” from the start and sign-in screens? Default: yes. “Join a household” on the start screen and “Join with an invite” on Welcome replace it; the code screen gets the Paste button.
2. **JH-Q2** Which button leads on the join page when the app is missing? Default: “Get the app” once the store listings are public (`storeListings` in `app/web/join/join.js`); until then “Join in the browser” stays the main button.
3. **JH-Q3** Add a deep-link service (JH1) for installs that lose the link? Default: no. Revisit if, on iOS, more than 30 % of join-page opens are not followed by a join within 24 hours, counted from our own join records with no new event.
4. **JH-Q4** Bring back the Android install referrer, read only after a tap on “I was invited”? Default: no. Ask Legal only if Android shows the same loss.
5. **JH-Q5** Ask usage data after the join (a sheet over the first list) instead of before it? Default: yes, with today’s wording and two equal buttons. Legal confirms that the order change needs no new text.
6. **JH-Q6** On the approval wait, drop “Create your own household” as the main button? Default: yes. The wait says what Mia sees and that the list opens by itself; “Start my own list instead” moves to a text button.
7. **JH-Q7** Show a QR code for one-person invites too (today only group links have one)? Default: yes, on the invite card.
8. **JH-Q8** Build a QR scanner into the “Join a household” screen? Default: not in the first version. The phone’s camera opens the link already; the button in the prototype shows where it would go.
9. **JH-Q9** May the app’s own landing show the join page’s facts (first name, household, counts, Premium) before sign-in? Default: yes, the same `preview_invite_public` answer and nothing more. Legal confirms that N-112 / N-151b cover the in-app copy.
