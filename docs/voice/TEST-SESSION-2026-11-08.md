# Voice test session, Sunday 2026-11-08, 16:00 CET

For Peter: 60 to 90 minutes, iPhone first, then the Echo. Each step lists what to say or tap,
what you should hear, and the log line the lead should see. If a step fails, follow its decision
tree, fix it live, and move on. Write down the time (hh:mm) of every failure: the lead finds the
request by its time.

Everything that needs no phone or Echo was checked on Sunday before 15:00
(`scripts/voice/health.sh`, results in [Pre-checks](#pre-checks-done-before-1500)).

**The lead watches:** `scripts/voice/tail.sh --since 30m`. The command prints every Siri and
Alexa request the server gets, about 10 to 60 s after you speak. No line at all means the request
never reached Hummlist: Siri or Alexa routed it elsewhere. During Part 2 the lead keeps a second
window for linking: `scripts/alexa/diagnose.sh --last 30m` joins the OAuth steps with the Alexa
requests and the stored links.

How to read a line:

```
16:05:12  voice: siri add de client=ios-1210.AddItems -> added status=200 count=2 ms=640
          |     |    |   |  |                          |      the HTTP status, the item count, the time
          |     |    |   |  |                          outcome: added, nothing_added (all already on the list), read, unauthorized, ...
          |     |    |   |  the app build and the Siri path: AddItems, AddItems.item, ReadList,
          |     |    |   |  Lists.add or Lists.read (Siri's own list grammar)
          |     |    |   language the iPhone sent
          |     |    add or read
          |     siri = the Siri sign-in of the app; pat = the old Shortcut recipe; none = no valid sign-in
16:21:40  alexa: IntentRequest AddItemIntent de-DE linked=true -> added rid=3f2a9c1d0b7e slot=3 confirm=NONE ended=- error=- ms=812
                 |             |             |     |              |     |                 slot = words heard for the items (never the words)
                 |             |             |     |              |     the end of Alexa's request id
                 |             |             |     |              what Hummlist answered: added, read, launch, link, ask, ...
                 |             |             |     |              (`link invalid_token:<why>`: the token was rejected, see X5)
                 |             |             |     the account link token came with the request
                 |             |             the Echo's language
                 |             the intent the model picked
                 LaunchRequest, IntentRequest, SessionEndedRequest (ended=ERROR error=<type> is Alexa's complaint)
16:22:01  auth  GET /oauth/authorize 302                           (account linking: the login starts)
16:22:03  auth  POST /oauth/token 200 grant=authorization_code     (Amazon got the token; a failure shows error=<code>)
16:40:10  auth  POST /oauth/token 200 grant=refresh_token          (a token refresh, no consent lines before it: Alexa's or another connected app's, e.g. an AI assistant)
```

## Pre-checks (done before 15:00)

The lead fills this in from `scripts/voice/health.sh` (hz) and `scripts/voice/health.sh --amazon`
(box) on Sunday. Peter does nothing here.

| Check | Result |
| --- | --- |
| `voice` and `alexa` deployed from main, both log a request line | _fill in_ |
| TestFlight build with the request lines (`client=ios-<build>…`) | _build number_ |
| Alexa development stage = repo: invocation `humm list` in de-DE and en-*, endpoint, account linking | _fill in_ (still „fill in“: `--amazon` could not run, so start Part 2 with the name probe in 2B) |
| Supabase OAuth client "Amazon Alexa" with the EU (layla) redirect | PASS (Sat 22:20) |
| `integration_lock` off: Siri needs no Premium | PASS (Sat 22:20) |

## Part 0: setup checks on the iPhone (10 min)

1. **TestFlight:** install the build named above (TestFlight › Hummlist › Installieren). At the
   bottom of Hummlist › Mehr, „Version 1.x (<build>)“ shows the build number.
2. **Open Hummlist**, signed in, in your household, and let the list load. This registers the
   item names Siri may hear and stores the Siri sign-in. If iOS asks whether Hummlist may
   use Siri (the message reads „Mit Siri setzt du Einträge auf deine Hummlist und lässt sie dir
   vorlesen.“), tap **OK** or **Erlauben**. Without it, Siri's own list grammar never reaches Hummlist.
3. Note the **iOS version** (Einstellungen › Allgemein › Info). Apple Intelligence on or off
   (Einstellungen › Apple Intelligence & Siri).
4. **Siri language:** Einstellungen › Apple Intelligence & Siri › Sprache = **Deutsch
   (Deutschland)**. Antworten › **Transkription immer anzeigen**: on. With the transcript on
   screen, every failure shows what Siri heard. Take a screenshot each time.
5. **Siri for Hummlist:** Einstellungen › Apps › Hummlist › Siri (on some iOS versions:
   Einstellungen › Apple Intelligence & Siri › Apps › Hummlist): **Mit Siri verwenden** on.
6. **Kurzbefehle app** › Kurzbefehle › App-Kurzbefehle › **Hummlist**: three tiles, „Zu Hummlist
   hinzufügen“, „Meine Hummlist vorlesen“ and „Hummlist öffnen“. If the tile has a Siri switch,
   it is on.

If 6 shows no Hummlist tile: delete the app, install it again from TestFlight, open it once
(step 2), wait a minute, check again. Still nothing: stop Siri here and go to Part 2. The lead
reads the build's App Shortcuts training log (CI `ios` job) for that build.

## Part 1: Siri (30 to 35 min)

Use these items: **Milch** (on the list before? Tick it off first so it can be added), **Brot**,
**Zahnpasta** (an item Hummlist has never seen in your household; on the list already? Tick it
off first).

### 1A. Tap test, no voice (2 min)

In the Kurzbefehle app, tap **Zu Hummlist hinzufügen**. Siri asks „Was soll auf die Liste?“. Type
„Milch und Brot“.

- Expected: „Hinzugefügt: Milch, Brot.“ Both are in the app's list within a few seconds.
- Log: `voice: siri add de client=ios-<build>.AddItems -> added status=200 count=2`.

This proves the intent, the Siri sign-in and the server without speech recognition. If it
fails, see [Siri decision tree](#siri-decision-tree), rows S1 to S4, before you speak a phrase.

### 1B. German phrases, typed (5 min)

Type to Siri (Einstellungen › Bedienungshilfen › Siri › **Eingabe für Siri**, or hold the side
button and type when the keyboard shows). Typing takes speech recognition out: a phrase that
works typed and fails spoken is a name problem, not a Hummlist problem.

| # | Type | Expected answer | Log line |
| --- | --- | --- | --- |
| T1 | `Hummlist, füge etwas hinzu` → `Zahnpasta` | „Was soll auf die Liste?“, then „Hinzugefügt: Zahnpasta.“ | `siri add de client=…AddItems -> added count=1` |
| T2 | `Was steht auf meiner Hummlist` | „Auf der Hummlist stehen 3 Sachen: …“ | `siri read de client=…ReadList -> read` |
| T3 | `Zeig meine Hummlist` | Hummlist opens on the list | none (opens the app, no server call) |

### 1C. German phrases, spoken (15 min)

Say each one at normal speed. After each, look at the transcript: does it say „Hummlist“?

| # | Say | Expected answer | Log line |
| --- | --- | --- | --- |
| V1 | „Hey Siri, Hummlist, füge etwas hinzu“ → „Milch“ | „Was soll auf die Liste?“, then „Hinzugefügt: Milch.“ | `-> added count=1`, `client=…AddItems` |
| V2 | „Hey Siri, füge etwas zu meiner Hummlist hinzu“ → „Brot und zwei Gurken“ | „Hinzugefügt: Brot, 2 Gurken.“ (or „Schon auf der Liste: Brot.“) | `-> added count=2`, or `-> nothing_added` when everything was already on the list |
| V3 | „Hey Siri, füge Milch zu Hummlist hinzu“ (tick Milch off first) | „Hinzugefügt: Milch.“ with no question | `client=…AddItems.item` (a known item) |
| V4 | „Hey Siri, füge Zahnpasta zu Hummlist hinzu“ (tick it off first) | Zahnpasta in the app; Siri speaks its own short confirmation | `client=…Lists.add` (Siri's list grammar) |
| V5 | „Hey Siri, was steht auf meiner Hummlist?“ | Siri reads the open items | `-> read`, `client=…ReadList` or `Lists.read` |
| V6 | „Hey Siri, Hummlist, was brauchen wir?“ | as V5 | as V5 |
| V7 | „Hey Siri, zeig meine Hummlist“ | the app opens on the list | none |
| V8 | „Hey Siri, füge Milch zur Einkaufsliste hinzu“ | goes to Erinnerungen, not Hummlist (on purpose) | none |

A failure: write the time, take a screenshot of the transcript, then use the decision tree.

### 1D. English (optional, 8 min, only if Part 2 time is safe)

Switching Siri's language downloads a voice and can take a few minutes. Einstellungen › Apple
Intelligence & Siri › Sprache = **English (United States)**, then:

| # | Say | Expected | Log line |
| --- | --- | --- | --- |
| E1 | "Hey Siri, add to Hummlist" → "eggs" | "What should I add?", then "Added eggs to Hummlist." | `siri add en client=…AddItems -> added` |
| E2 | "Hey Siri, what's on my Hummlist?" | reads the open items in English | `siri read en … -> read` |
| E3 | "Hey Siri, show my Hummlist" | the app opens | none |

Set Siri back to Deutsch afterwards.

### Siri decision tree

| # | What happens | Log | Likely cause | Fix now |
| --- | --- | --- | --- | --- |
| S1 | 1A: „Öffne Hummlist und melde dich an.“ | no line | The Siri sign-in isn't stored (app not opened since install, or opened signed out) | Open Hummlist, make sure the list loads, wait 5 s, retry 1A. Still: sign out and in again (Mehr › Abmelden), retry |
| S2 | 1A: „Öffne Hummlist und melde dich erneut an.“ | `none … -> unauthorized status=401` | The stored Siri sign-in was revoked (sign-out on another device, account deletion test) | Sign out and in again in the app, retry |
| S3 | 1A: „Hummlist hat nicht rechtzeitig geantwortet.“ or „…keine Internetverbindung“ | none, or `ms=` above 7000 | No network, or a slow server start | Retry once (the second call is warm). Twice slow: the lead checks the line's `ms` |
| S4 | 1A: „Bei Hummlist ist etwas schiefgelaufen.“ | `-> server status=500` | A server error | The lead reads the error line next to it (`voice: adding items failed …`); go on with Part 2 meanwhile |
| S5 | Typed works, spoken fails; the transcript shows another name („Hummel ist“, „Ham List“, „Home-Liste“) | no line | Siri didn't hear the app's name | Say „Humm-list“ with a short stop, or one of the trained names „Homlist“, „Hamlist“. Write down every spelling the transcript shows: the alternative names get chosen from them |
| S6 | Siri says Hummlist doesn't support that with Siri (wording varies), or offers to turn on Hummlist's shortcuts with Siri | no line | The app's Siri switch is off | Accept the offer, or Part 0 steps 5 and 6, retry |
| S7 | The item lands in Erinnerungen (Reminders) | no line | Siri took the sentence as its own list grammar | Use the „Hummlist, …“ order (V1). Note the exact sentence |
| S8 | V4 (unknown item): „Hummlist unterstützt das nicht“ or Siri can't do it | no line | Siri wasn't allowed for Hummlist (the one-time prompt was declined), so its list grammar never reaches the app | Einstellungen › Apps › Hummlist › Siri: allow; or delete and reinstall the app and tap Erlauben at the prompt (Part 0 step 2) |
| S9 | V3 asks „Was soll auf die Liste?“ instead of adding Milch | `client=…AddItems` | Milch isn't one of the item names the app registered | Fine: answer „Milch“. The item phrase only knows items the household had before |
| S10 | Siri opens the Hummlist app instead of answering | none | Siri matched no phrase and fell back to the app | Same as S5: check the transcript |
| S11 | Phrase fails by voice and typed, but 1A works | none | The phrases aren't registered on this iPhone (an iOS bug reported on the iOS 27.2 beta) | Kurzbefehle: switch the Hummlist Siri toggle off and on, open the app once, retry. Note the iOS build |
| S12 | „Sprachbefehle sind Teil von Hummlist Premium“ | `-> premium_required` | The integration lock was switched on | The lead switches `integration_lock` off (`docs/PAYWALL_RELEASE.md`) |

## Part 2: Alexa (30 to 35 min)

### 2A. Setup checks (8 min)

1. **Which account:** say „Alexa, welches Konto ist das?“ (wording unconfirmed). If Alexa
   doesn't answer that, look in the Alexa app › Geräte › your Echo › „Registriert für“. A
   development skill works only on an Echo registered to **the Amazon account of the Alexa
   developer console** (same e-mail), or to an account that accepted the skill's beta invitation.
   The other account sees no Hummlist skill at all.
2. **Echo language:** Alexa app › Geräte › your Echo › Sprache = **Deutsch**.
3. **Alexa+:** if this Echo or account uses Alexa+ (early access in Germany since May 2026),
   note it. How Alexa+ routes to development skills is not documented, and in 2026 Alexa+ sends
   more „füge … hinzu“ sentences to Amazon's own shopping list.
4. **Skill enabled and linked:** Alexa app › Mehr › Skills und Spiele › Ihre Skills › scroll the
   tabs to **Entwicklung** (Alexa+: Alexa+ Store › Skills und Spiele durchsuchen › Ihre Skills) ›
   **Hummlist**. If it says „Aktivieren“: tap it, sign in with your Hummlist account, tap
   „Erlauben“. If it is already enabled, check that it says „Konto verknüpft“.
   - Log during linking: `auth  GET /oauth/authorize …`, the consent steps (`auth  …
     /oauth/authorizations/<id>/consent …`), `auth  POST /oauth/token 200
     grant=authorization_code`, then `alexa: AlexaSkillEvent.SkillAccountLinked … -> empty`. A
     word after `empty` (`invalid_token:<why>`) means Hummlist rejected the new token: X5a to X5d.

### 2B. Typed in the Alexa app (5 min)

Alexa app › Alexa (the chat) › keyboard. Typing takes speech recognition out.

**Name probe first, if the pre-check row for the development stage isn't PASS.** The stage may
still serve the old invocation name `hummlist` (the repo moved to `humm list` on Nov 5; the
deploy needs the box). Type `öffne humm list`, then `öffne hummlist`:

- Only `öffne hummlist` answers „Was soll auf die Liste?“: the stage has the old name. Either
  test with „Hummlist“ everywhere below (A1, A4, A7, A8: say „Hummlist“ instead of „Humm List“),
  or set the new name live: developer console › Hummlist › Build › Invocation › Skill Invocation
  Name `humm list` › Save Model › Build Model (2 min), and repeat the probe.
- Only `öffne humm list` answers: the stage is current; go on with A1.
- Neither answers: decision tree X3.

| # | Type | Expected answer | Log line |
| --- | --- | --- | --- |
| A1 | `öffne humm list` | „Was soll auf die Liste?“ | `LaunchRequest - de-DE linked=true -> launch` |
| A2 | then `Milch und Eier` | „Ich habe Milch und Eier auf die Hummlist gesetzt.“ | `IntentRequest AddItemIntent de-DE linked=true -> added … slot=3` |
| A3 | `frag humm list was auf der liste steht` | „Auf der Hummlist stehen 3 Sachen: …“ | `IntentRequest ReadListIntent … -> read` |

### 2C. Spoken on the Echo (15 min)

| # | Say | Expected answer | Log line |
| --- | --- | --- | --- |
| A4 | „Alexa, öffne Humm List“ (short stop between Humm and List) | „Was soll auf die Liste?“ | `LaunchRequest … -> launch` |
| A5 | then „Brot und zwei Gurken“ | „Ich habe Brot und 2 Gurken auf die Hummlist gesetzt.“ | `AddItemIntent … -> added slot=4` |
| A6 | „Alexa, öffne Hummlist“ (one word) | as A4 | as A4 |
| A7 | „Alexa, sag Humm List, füg Zahnpasta hinzu“ | Zahnpasta added in one go | `AddItemIntent … -> added slot=…` |
| A8 | „Alexa, frag Humm List, was auf der Liste steht“ | Alexa reads the open items | `ReadListIntent … -> read` |
| A9 | „Alexa, öffne Humm List“ → „Hilfe“ → „Stopp“ | the help text, then „Bis bald.“ | `-> help`, then `-> goodbye` |

### 2D. English (optional, 5 min)

Only with time left: Alexa app › Geräte › Echo › Sprache = **English (United Kingdom)**, then
"Alexa, open humm list" → "milk". Expected: "What should I add?" and "Added milk to Hummlist."
Log: `LaunchRequest - en-GB … -> launch`. Set the Echo back to Deutsch.

### Alexa decision tree

| # | What happens | Log | Likely cause | Fix now |
| --- | --- | --- | --- | --- |
| X1 | No Hummlist under Ihre Skills › Entwicklung | none | The Echo's account isn't the developer account and hasn't accepted the beta invitation | Use the developer account's Echo, or the lead resends the beta invitation link to this account (console › Zertifizierung › Beta-Test) and you accept it in the Alexa app |
| X2 | Typed A1 works, spoken A4 doesn't („Ich weiß nicht…“ or another skill opens) | no line for the spoken one | Alexa didn't hear „humm list“ | Alexa app › Mehr › Einstellungen › Alexa-Datenschutz › Sprachverlauf überprüfen (menu names vary by app version): read what Alexa heard and write it down. Try A6 and „Alexa, starte Humm List“. If it heard a stable other word, Peter can change the invocation name in the console (Build › Invocation, „Save“ and „Build Model“, 2 min) to that spelling for the test |
| X3 | Typed A1 also fails: „Ich weiß nicht…“ | no line | No request reaches Hummlist: wrong account (X1), the skill not enabled, or the dev stage not serving `humm list` | Check 2A 1 and 4. The lead checks the dev stage (`health.sh --amazon` on the box). Console › Test tab: set to „Entwicklung“, type „öffne humm list“ and „öffne hummlist“. If the old name `hummlist` answers, the stage has the old name: use „Hummlist“ for the session or set Build › Invocation to `humm list`, Save Model, Build Model, retry. If either reaches the log, the console works and the device or account is the problem |
| X4 | „Bitte verknüpfe zuerst dein Hummlist-Konto…“ | `linked=false -> link` | The skill is enabled on this account but not linked | 2A step 4: Konto verknüpfen |
| X5 | Same sentence | `linked=true -> link invalid_token:session_ended` | The link's session is gone: removed under Zugänge, signed out everywhere, or a reused refresh token revoked it | Alexa app › Hummlist › Skill deaktivieren, then Aktivieren and link again. Still `session_ended` right after a fresh link: X5c |
| X5a | Same sentence | `linked=true -> link invalid_token:expired` | Alexa sent an expired token: its refresh failed | The lead runs `scripts/alexa/diagnose.sh --last 30m` and looks for a failed `token refresh_token` row (`refresh_token_already_used`). Then relink as in X5 |
| X5b | Same sentence, or linking succeeds but every request asks to link | `linked=true -> link invalid_token:not_oauth` or `:unknown_key`, also on `SkillAccountLinked … -> empty <reason>` | The token is a Hummlist app session or key, not the Amazon Alexa client's OAuth token | The lead checks the console's Account Linking: Client ID = the „Amazon Alexa“ client (`health.sh` names it), Authorization and Access Token URI as in docs/ALEXA.md. Fix, save, relink |
| X5c | Same as X5b | `linked=true -> link invalid_token:issuer`, `:audience`, `:signature`, `:claims` or `:malformed` | The token isn't from this project's auth server: the Access Token URI points at another host or project | Same check as X5b, the Access Token URI first. Fix, save, relink. No fix in the session: note the time and the reason, end Part 2 |
| X5d | Same sentence, once | `linked=true -> link invalid_token:unverified` | Hummlist couldn't check the token (its key set didn't load) | Say it again. Repeats: the lead reads the function logs for an auth outage. Don't relink |
| X6 | Linking ends with „Verknüpfung derzeit nicht möglich“ | `auth  POST /oauth/token 4xx error=<code>`, or no token line after the consent lines | The token exchange failed | Note the time. The lead reads the auth line (status and grant) and `scripts/alexa/diagnose.sh --last 30m`. Retry once in the Alexa app (not the browser) |
| X7 | „Bei der Antwort des angeforderten Skills ist ein Problem aufgetreten“ | `SessionEndedRequest … ended=ERROR error=INVALID_RESPONSE` | Hummlist's answer was malformed for Alexa | Note the time; the lead reads the line before it (the intent and kind) and fixes it on Monday. Move on |
| X8 | Same, or a long pause and then an error | `ms=` above 7000, or `error=ENDPOINT_TIMEOUT` | Slow start of the function (Alexa waits 8 s) | Retry once right away (warm now) |
| X9 | A7 lands in Amazon's own Einkaufsliste | no line | Alexa's built-in lists took the sentence (worse with Alexa+) | Use A4/A5 (open first). With Alexa+: note it |
| X9a | A8 answers „Du hast N Artikel auf deiner Einkaufsliste“ | no `ReadListIntent` line | Alexa's own Einkaufsliste answered (Hummlist says „Auf der Hummlist stehen N Sachen“ and counts open items only; job 172) | Use A4, then „Was steht auf der Liste?“. Alexa app › Listen › Einkaufsliste holds the items she counted |
| X10 | „Das habe ich nicht verstanden…“ | `AddItemIntent … -> reprompt slot=0` or `FallbackIntent` | Alexa opened Hummlist but didn't catch the items | Say the items with a verb: „füg Milch hinzu“ |
| X11 | „Du bist noch in keinem Haushalt…“ | `-> no-household` | The linked Hummlist account has no household | Link the account that has your household (as in X5) |

## After the session

Send the lead: the times and table numbers that failed, the transcript screenshots, iOS version,
Alexa+ yes or no, the account Alexa named. The lead copies the tail output into
`~/groceries-ops/jobs/170-voice-test-prep/session-log.txt` and files the follow-ups.
