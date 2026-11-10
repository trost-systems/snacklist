# Snacklist features for writers

What Snacklist does today, in plain words, with the exact button and screen labels in German and English. Snacklist Launch and anyone writing emails, site copy or instructions reads this file. The verification recipes behind it are the other files in this folder.

## How to use this

- Describe only what a section says the app does. If it is not here, ask before you write it.
- Copy labels exactly, with their quotes and punctuation: German „…“, English "…". The app shows German or English depending on the phone's language, or on Mehr → Einstellungen → Sprache.
- Check each section's **Never claim** list and the global list below before you send anything.
- **Unverified** means nobody could prove it from the code or a test run. Leave it out, or ask.
- Each section ends with the commit and date it was last checked. If the app changed after that date, the section can be out of date.
- Short clips (GIF for emails, MP4/WebM for the site, PNG fallback) live in `/workspace/hummlist/clips/<feature>/` on the box, for example `quick-add/de.gif`. Each `meta.json` names the commit and the alt text. To make a new one, see `.cursor/skills/snacklist-howto-clips/SKILL.md`. Always give the GIF its alt text and link the PNG as a fallback.

## The name (job 174, 2026-11-10)

The app is called Snacklist (it was Hummlist). The app, its Siri phrases, the site and the help pages say Snacklist; verified on branch job/174b-snacklist-copy, 2026-11-10 (CET), on the release web build (start, sign-in, consent, More, the account deletion page, the site's landing pages), and again on main 1f8e5edb, 2026-11-10 (CET) (start, sign-in, the usage question, More, Premium, the site's /de page, Siri's and the AI assistants' answers). The site is at snacklist.app and the web app at app.snacklist.app; hummlist.com redirects to snacklist.app, and app.hummlist.com still shows the web app for old links. The Alexa skill (its name and „Alexa, sag Snacklist, …“, S4), the mail addresses (support@snacklist.app, hello@snacklist.app) and the MCP server address https://mcp.snacklist.app say Snacklist too (the Hummlist sweep, 2026-11-10, from the docs, not driven). Never write the old addresses in new copy. Never write „Humm“ or „Snack“ alone as the name.

## Never claim (everywhere)

- That Snacklist Premium can be bought, or any price, plan, trial or discount. Premium is not on sale and nothing is locked behind it today.
- That Siri, Alexa or AI assistants need Premium today. They don't: nothing is locked during the beta. After the public launch Siri and AI assistants become part of Snacklist Premium; the Alexa skill stays free for good. Never write that Siri stays free after the launch. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2.
- Siri without setup ("just say Hey Siri", no Shortcut) as available. It is built, but its announcement waits for Snacklist Launch. Today Siri works through a Shortcut the user sets up once, in German.
- That the Alexa skill is launched, certified or in the Alexa Skill Store. It is a beta by invitation, in German and English.
- Store logos or chain colours, official store layouts, prices, offers or opening hours. Store names are plain names; walking orders are researched defaults.
- A code to type from an email for sign-in. Sign-in emails contain a link, and the only code in Snacklist is the 8-character household invite code.
- The Home Screen widget as available. It is built for iPhone and Android, but its announcement waits for a device test (see „Home Screen widget (held)“).
- Apple Watch, Google Assistant, Android voice assistants, push notifications, recipes, meal plans or price tracking. None exist.
- That the microphone (dictation) works in the browser. It is in the iPhone and Android apps only.
- Real people's names or lists. Clips and screenshots use the fictional Brandt family.
- AI products or their makers (ChatGPT, OpenAI, Claude, Anthropic) as examples, claims or praise. Write „KI-Assistenten, die MCP unterstützen“ / "AI assistants that support MCP". Only setup instructions (the Claude guide, the app's MCP help text) and the trademark notice in the imprint name them (Legal N-79 to N-86; `scripts/brand-names.ts` fails the lint gate on the site and the ARB files).
- Alexa as „sie“ / "she". Name the skill „Snacklist-Skill für Amazon Alexa“ / "Snacklist skill for Amazon Alexa" (Legal N-84).
- Anything the sections below mark as held (Premium, native Siri, the Alexa skill's certification, the Home Screen widget, Premium-only connections).

# Getting started

## snacklist.app waitlist

**What it does.** snacklist.app keeps its landing page, but its buttons say „Auf die Warteliste“ (EN: "Join the waitlist") instead of opening the browser version. They lead to a short form: the email (ideally the one of the Apple ID or Google account) and iPhone or Android. Snacklist then sends a confirmation mail; the person is on the list only after tapping „E-Mail bestätigen“ in it and agreeing on the page that opens, where they can also tick that they want one email when the app launches. An AI assistant may fill in the form for someone, but only the person's own click on that page counts. Confirmed people are invited to the beta in weekly groups, by hand. Every mail has a link that deletes the entry at once. The hero badge says „Beta im November“ (EN: "Beta in November"), and above the form a short note „Von Peter“ (EN: "From Peter") says why he builds Snacklist: one list he shares with his wife, which AI assistants can add to, tick off and read through MCP; in the beta people test it with them and say what's missing. Later stages are built but off: „Zur Beta anmelden“ (EN: "Join the beta"), and at launch App Store and Google Play badges with a QR code; the badge and the note leave at launch.

**On the landing page.** Besides the waitlist, the page shows how the app works. The stores card has three buttons under „Tippe auf einen Laden:“ (EN: "Tap a store:"): „Drogerie“, „Getränkemarkt“ and „Supermarkt“ (EN: "Drugstore", "Drinks store", "Supermarket"). A tap re-orders the first five category stops below to that kind of store's route, using the app's own category names. Four short silent videos show the real app: typing two items and ticking them off, three phones of one family staying in sync, adding by voice („Pizza, Orangensaft und zwei Packungen Fischstäbchen“), and an AI chat putting items on the list and ticking them off. Each video has a written description.

**How to get there.**
1. snacklist.app (opens /de or /en by browser language).
2. „Auf die Warteliste“ (EN: "Join the waitlist"), in the header or the hero.
3. In the mail: „E-Mail bestätigen“ (EN: "Confirm email"), then the button on the page.

**Never claim.**
- That signing up works, or that anyone has been invited, until Peter confirms it. The page is on snacklist.app, but sign-ups depend on server settings that are not confirmed here.
- A beta date more exact than the badge's month („Beta im November“), a place in line, a referral reward, a counter, or a date for a particular person's invite.
- That the browser version is open to new users, or that an assistant can sign someone up without their confirmation.
- That launch news can be chosen in the form (only on the confirmation page).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), the site built locally: its waitlist check passes (108 checks); „Beta im November“ on /de. Earlier: main c3636541, 2026-11-09 (CET), the site built locally: its 170 tests pass; „Beta im November“ and „Auf die Warteliste“ on the landing page. The form itself was not re-run. Earlier: main 6c93da99, 2026-11-08 (CET), the site built locally: its 170 tests pass; the landing page has the badge „Beta im November“ and „Auf die Warteliste“; the help page answers both Snacklist Lifetime questions. The form itself was not re-run. Earlier: main c2ce938f, 2026-11-07 (CET), on the locally built site: the badge, the founder note and „Auf die Warteliste“, the stores card's three buttons re-ordering the stops, the four silent videos and their descriptions (DE and EN). The form itself was not re-run. The support and privacy pages built from the 7 Nov texts. Recipe: [waitlist.md](./waitlist.md).

## Sign-up and sign-in

**What it does.** Someone new to Snacklist starts with „Los geht's“ (EN: "Get started") on the first screen and creates the account at the end of the guided start (see „Getting started“). A returning user taps „Schon ein Konto? Anmelden“ (EN: "Already have an account? Log in") and signs in with Google or Apple, or with email: email and password, a new account with „Registrieren“ (EN: "Sign up"), or a sign-in link by email opened on the same device. Google and Apple come first; email is one more button below them, „Weiter mit E-Mail“ (EN: "Continue with email"). The keyboard opens only when the user taps a field. Below the sign-in, „Neu bei Snacklist? Los geht's“ (EN: "New to Snacklist? Get started") leads back to the guided start. Signing out is in the More tab and ends on the login screen. The login screen links the imprint and the privacy policy. Right after deleting the account, the login screen confirms „Dein Konto wurde gelöscht.“ (EN: "Your account was deleted.").

**How to get there.**
1. Open Snacklist while signed out: the first screen shows the Snacklist logo, „Eure Einkaufsliste. Live auf jedem Handy.“ (EN: "Your shopping list. Live on every phone."), „Los geht's“ and „Schon ein Konto? Anmelden“.
2. To sign in, tap „Schon ein Konto? Anmelden“ (EN: "Already have an account? Log in"). The login screen opens on the Snacklist logo and name and has no title. A link to a screen of the app opens the login screen directly. An invite link opens the login screen in the phone apps; in a browser it first shows a short page with „Im Browser beitreten“ (EN: "Join in the browser"), which leads there.
3. Someone who got an invite but has no app open with it can tap „Einladung einfügen“ (EN: "Paste invite") on this screen; with an invite already waiting, the screen says „Einladung gemerkt. Melde dich an, dann trittst du bei.“ (EN: "Invite saved. Sign in to join.").
4. Tap „Mit Google anmelden“ / „Mit Apple anmelden“ (EN: "Sign in with Google" / "Sign in with Apple").
5. Or tap „Weiter mit E-Mail“ (EN: "Continue with email"), enter email and password, then tap „Anmelden“ (EN: "Sign in"), or „Registrieren“ (EN: "Sign up") for a new account.
6. Or, after „Weiter mit E-Mail“, enter only the email and tap „Anmeldelink per E-Mail senden“ (EN: "Email me a sign-in link"), then open the link from the email on the same device.
7. To sign out: tab „Mehr“ (EN: "More"), then „Abmelden“ (EN: "Sign out").

**Never claim.**
- A code that users type in from an email: the app has no such field. Sign-in emails carry a link.
- "8-digit code" for sign-in. Sign-in emails contain a link, not a code. The only 8-character code in Snacklist is the household invite code (letters and digits).
- That the emails are in German or come from a "Snacklist" template: today they are short English emails ("Your sign-in link", "Confirm your email address").
- Passkeys, phone-number sign-in or other providers than Google and Apple.
- That users need an email and password account: Google or Apple is enough.
- A "Forgot password" button or password reset in the app: there is none. Someone who forgot the password uses „Anmeldelink per E-Mail senden“ (EN: "Email me a sign-in link").

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): the first screen, „Schon ein Konto? Anmelden“ to the login screen with Google, Apple, „Weiter mit E-Mail“, „Neu bei Snacklist? Los geht's“ and „Einladung einfügen“; „Einladung gemerkt“ for an invite link; both field errors. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): the first screen, „Schon ein Konto? Anmelden“ to the login screen with Google, Apple, „Weiter mit E-Mail“, „Neu bei Snacklist? Los geht's“ and „Einladung einfügen“; with an invite waiting „Einladung gemerkt …“; signed out, a link to the household page goes to the login screen; sign-in in every journey. Earlier: branch job/168b-onboarding-p2 at 3a2b032d, 2026-11-08 (CET), from code and widget tests (`app/test/onboarding/guided_start_test.dart`): the first screen with „Los geht's“ and „Schon ein Konto? Anmelden“, „Neu bei Snacklist? Los geht's“ on the login screen (not for an invite or a link), the login screen first after a sign-out, an account deletion, an invite link or a link to a screen. Driven on the web build (verify-snacklist `journeys/onboarding.mjs`, German light and English dark, PASS): the first screen, every step, a reload resuming at the stores, no account before the account step, the household made with its kind, stores and three sorted items, two invites, a second browser joining and „… ist beigetreten“ showing without a reload, the list. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): a signed-out link to „Einladungen“ goes to the login screen, „Weiter mit E-Mail“, sign-up. main 8ad168f5, 2026-11-08 (CET): „Abmelden“ from the last row of Mehr ends on the login screen. main c2ce938f, 2026-11-07 (CET): the login screen with Google, Apple and „Weiter mit E-Mail“, the email form's checks, sign-up, sign-out from the last row of Mehr. Recipe: [sign-in.md](./sign-in.md).

## Usage-data question (analytics consent)

**What it does.** Snacklist asks once per device whether it may collect usage data. Someone new meets the question as the first step after „Los geht's“, before any account; someone who signs in without the guided start meets it right after the first sign-in. A no sends nothing to PostHog; Snacklist only notes the no with the account, so voice events stay off too. A yes sends pseudonymous usage data (for example about items, households and setup, and which tips you see) and error reports to PostHog on servers in the EU, from the sign-in on: nothing is sent before there is an account. Both answers are equally prominent, and the user can change the answer any time under More → Nutzungsdaten. Anyone who said yes to an earlier wording of the question is asked again with the current text, and nothing is sent until they answer; that includes people who said yes in the Hummlist app, since the text now names Snacklist, and everyone who said yes before the text named these examples. A no stays a no.

**How to get there.**
1. On a new device, tap „Los geht's“ (EN: "Get started") on the first screen, or sign in for the first time: the question „Darf Snacklist Nutzungsdaten erfassen?“ (EN: "May Snacklist collect usage data?") appears.
2. Answer „Erlauben“ (EN: "Allow") or „Nicht erlauben“ (EN: "Don't allow").
3. To change it later: tab „Mehr“ (EN: "More"), „Nutzungsdaten“ (EN: "Usage data"), the switch „Nutzungsdaten und Fehlerberichte senden“ (EN: "Send usage data and error reports").

**Never claim.**
- That list contents, names or email addresses are collected: the text says they are never sent.
- That a no limits any feature: the app works the same.
- That Snacklist uses advertising or sells data: nothing in the app says so.
- Quote the legal text exactly; do not paraphrase it. Point to the privacy policy for details.

**Note.** Every released app and the web app (app.snacklist.app, app.hummlist.com) ask this question (checked 2026-11-01; app.snacklist.app since 2026-11-10).

**Last verified.** Branch job/178-app, 2026-11-10 (CET), from code and widget tests only, not driven: the question's text names examples of the usage data (entries, households, setup, which tips you see), version 2026-11-11, so everyone who said yes before is asked again (`consent_version_test.dart`). Earlier: main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): „Los geht's“ opens the question „Darf Snacklist Nutzungsdaten erfassen?“ as step 1 („Schritt 1 von 7“); from code, a yes given under the Hummlist text counts as no answer, so the question comes again. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): „Los geht's“ opens the question as step 1 (the bar says „Schritt 1 von 7“), „Nicht erlauben“ goes on; the question after a plain sign-in in every journey. Earlier: branch job/168b-onboarding-p2 at 3a2b032d, 2026-11-08 (CET), from code and widget tests (`app/test/onboarding/guided_start_test.dart`): the question as the guided start's first step, skipped on a device that answered, no second question after the sign-up. Driven on the web build (`journeys/onboarding.mjs`, PASS): „Los geht's“ opens the question as „Schritt 1 von 7“ and „Nicht erlauben“ goes on to „Mit wem kaufst du ein?“. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): the question after sign-up, „Nicht erlauben“, the switch under Mehr → Nutzungsdaten (off). main c2ce938f, 2026-11-07 (CET): the question after sign-up with its privacy link. Recipe: [privacy-consent.md](./privacy-consent.md).

## Getting started: the guided start

**What it does.** A new user sets up the shared list before making an account. After „Los geht's“ (EN: "Get started") Snacklist asks, one screen at a time: who you shop with, the household's name, the stores, and what you need right now. Only then does it ask for the account. Everything typed so far stays on the device, also when the app is closed in between. Once signed in, Snacklist makes the household from the answers, puts the things you need on the list, and offers to invite the people you shop with. A counter shows how far along you are („Schritt 3 von 7“, EN: "Step 3 of 7"). „Überspringen“ (EN: "Skip") skips „Mit wem“ and the stores. The X on each screen leaves the setup: log in instead (the answers stay on the device), or discard them. Someone who signs in to an account that already has a household gets the typed items on that list. Someone who opens an invite link goes straight to joining (in a browser after the link's short page and „Im Browser beitreten“). „Einladung einfügen“ (EN: "Paste invite") below the buttons of the first screen takes an invite copied before the app was installed. A signed-in user without a household sees „Willkommen bei Snacklist“ (EN: "Welcome to Snacklist") with „Haushalt erstellen“ (EN: "Create a household"), which runs the same questions, „Einladung annehmen“ (EN: "Join with an invite") and „Einladung einfügen“. Someone waiting for a household's admin to let them in can tap „Eigenen Haushalt anlegen“ (EN: "Create your own household") to run the same questions; if the admin lets them in meanwhile, they finish anyway and end up in both households, the joined one and their own with what they typed.

**How to get there.**
1. Open Snacklist signed out and tap „Los geht's“ (EN: "Get started"). If the app asks about usage data, answer it.
2. „Mit wem kaufst du ein?“ (EN: "Who do you shop with?"): tap all that fit: „Partner·in“, „Familie“, „WG“, „Verein oder Team“, „Nur ich“, „Andere“ (EN: "Partner", "Family", "Flatmates", "Club or team", "Just me", "Other"). The first one picked sets up the household; Snacklist keeps the others for later.
3. „Wie soll euer Haushalt heißen?“ (EN: "What should your household be called?"): the name is suggested from the answer, „Unsere Familie“ for example (EN: "Our family"). Everyone you invite sees it.
4. „Wo kauft ihr ein?“ (EN: "Where do you shop?"): tap the stores you shop at, from eleven common ones (EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann and a „Baumarkt“), or „Eigenen Laden hinzufügen“ (EN: "Add your own store") and type a name such as „Wochenmarkt“; typing one of the eleven, „edeka“ say, ticks it.
5. „Was fehlt gerade?“ (EN: "What do you need right now?"): tap things like „Milch“ or „Brot“ (EN: "Milk", "Bread"), or type anything else, „2 Gurken“ for example. Then „Weiter mit 2 Artikeln“ (EN: "Continue with 2 items").
6. „Konto erstellen“ (EN: "Create your account"): sign up or sign in with Google, Apple or email.
7. The invite screen, for example „Familie einladen“ (EN: "Invite your family"): see „Household and invites“. „Später“ (EN: "Later") or „Weiter zur Liste“ (EN: "Go to the list") opens the list with the items on it. With „Nur ich“ (EN: "Just me") as the only answer, the list opens right away.

**Never claim.**
- A tour, a tutorial or a newsletter or email opt-in in the app: there is none.
- That any store is pre-installed, recommended or a partner: nothing is picked until you pick it, and the shops have nothing to do with Snacklist.
- Importing a list from another app: not built.
- That the extra „Mit wem“ answers do anything yet: the guided start makes one household from the first answer and only keeps the others on the device for later.
- A referral or "how did you hear about us" question: there is none.
- That the answers sync before the account exists: they stay on this one device until the sign-in.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/onboarding.mjs` in German light and English dark; a start with only „Verein oder Team“ makes a club with „Beitritte bestätigen“ on, and the joiner sees „Anfrage gesendet: Ein Admin von „Unser Verein“ bestätigt deinen Beitritt.“ Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/onboarding.mjs` in German light and English dark (every step, a reload resuming at the stores, the household from the answers, two invites, a second browser joining through the invite page's „Im Browser beitreten“ and „… ist beigetreten“ live, the list). Earlier: Branch job/168c-club-approval (job 168c), 2026-11-09 (CET): from code, widget tests (`join_approval_test.dart`: „Eigenen Haushalt anlegen“ while a request waits, the approval arriving mid-way) and e2e `guided-start.spec.ts` (a „Verein oder Team“ start creates a club with „Beitritte bestätigen“ on). Earlier: Branch job/169b-w3 at 955ba83c (job 169b W3), 2026-11-08 (CET), join approval driven on the web build by e2e (`club.spec.ts`): the switch „Beitritte bestätigen“, a new user's request from a group link with „Anfrage gesendet …“, the request appearing live on the owner's household page, „Aufnehmen“ switching the requester's open app into the household with „Du bist jetzt in „Verein Grün“.“, a person-link request declined with „Deine Anfrage für „Verein Grün“ wurde nicht angenommen.“, a club household created with approval on. Not driven: withdrawing a request, „Anfrage offen“ in the switcher. Earlier: Branch job/169b-w2 at c57618d3, 2026-11-08 (CET), e2e `onboarding.spec.ts` and `invite-loop.spec.ts` on the web build: an invite link's page, „Im Browser beitreten“, sign-up, then the join screen with the household's name. branch job/168b-onboarding-p2 at 3a2b032d, 2026-11-08 (CET), from code and widget tests (`app/test/onboarding/guided_start_test.dart`, `draft_test.dart`): the first screen, every step with its German labels (the first screen and a step in English too), the answers kept across a restart, the household made from the answers at the sign-in, an existing household getting the items, „Nur ich“ without the invite step, the X with „Stattdessen anmelden“ and „Fortschritt verwerfen“. Driven on the web build (verify-snacklist `journeys/onboarding.mjs`, German light and English dark, PASS): the first screen, every step, a reload resuming at the stores, no account before the account step, the household made with its kind, stores and three sorted items, two invites, a second browser joining and „… ist beigetreten“ showing without a reload, the list. Earlier (the create screen before the guided start): main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): a new account offered eleven store chips with „Baumarkt“ last; REWE plus typed „edeka“ ticked the one EDEKA; the invite step, „Später“ to the list; with a link waiting, the link's screen instead of the invite step. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): a new account offered eleven store chips with „Baumarkt“ last, creating a household with REWE and typed „edeka“ (one EDEKA), the invite step, „Später“ to the list. Recipe: [onboarding.md](./onboarding.md).

## Household and invites

**What it does.** One household shares one shopping list, and one person can be in several households, for example at home and with their parents (up to 10; the app says so when someone in 10 tries to create or join another). The household's name sits top left of the list; a tap shows all your households and switches between them. Right after the guided start sets up a household, it offers invites: one link per person, as many as you like, and each invite shows „Mia ist beigetreten“ (EN: "Mia joined") as soon as that person joins, while the screen is open. For a club, where new members wait for approval, the invite screen shows no „beigetreten“; the request appears on the household page until an admin lets the person in. Later, any member invites one person with an 8-character code and a link; such an invite is valid for 7 days and works once. The household's creator and its admins can also make a group link with a QR code for up to 50 people, valid for 30 days, see who joined with it, revoke it and make a new one; when 50 have joined, the sheet says the link is full and offers a new one. The share text fits who shops together (partner, family, flat share, club) and always carries the link and the code; the person shares it, Snacklist sends nothing. Whoever gets it types the code, opens the link, or pastes it with „Einladung einfügen“ after installing; their other households stay. In a browser the link first shows a short page: who invites to which household („Peter lädt dich zu „Familie Brandt“ ein“), how many members and open items, the code, and „Im Browser beitreten“ (EN: "Join in the browser"); it shows no items and no email addresses. Every screen that makes or shares an invite says, above its button, what that short page shows (your first name from your display name, the household's name and kind, the number of members) and to share the link only with people you want to invite. A household with Premium says that Premium covers everyone in it. Each household has a page to rename it, see its members and their roles, remove members (creator and admins), name admins (creator), make it the default for Siri, Alexa & AI, and leave it. Someone who was removed sees a notice in their app the next time it loads their households, naming the household and the 30-day rule; a phone or browser they sign in on later during those 30 days tells them once too. Someone who left a household on another device gets only „Du bist nicht mehr Mitglied von „{name}“.“ (EN: "You're no longer a member of “{name}”.") there, without the 30 days, which don't apply to them. They can't come back through an invite made before the removal, not even the group link still in the group chat; for the next 30 days only a new invite or a new group link from the household's creator or an admin lets them in again. A code or link of a household you are already in simply opens that household. The creator and admins can switch on „Beitritte bestätigen“ (EN: "Confirm new members"): then whoever uses an invite first sees „Anfrage gesendet: Ein Admin von „Verein Grün“ bestätigt deinen Beitritt.“ (EN: "Request sent: an admin of “Verein Grün” will let you in."), and an admin lets them in („Aufnehmen“, EN: "Let in") or declines („Ablehnen“, EN: "Decline") on the household page. If the link they used is full by then, the request waits and the page says to send a new link. After a decline the same person can ask that household again only after 24 hours; until then the app says so plainly. Once let in, the person's app switches to the household and says „Du bist jetzt in „Verein Grün“.“ (EN: "You're now in “Verein Grün”."). It is on from the start for households created as a club, off for all others.

**How to get there.**
1. Right after the setup: the invite screen of the guided start. Its button names whom to invite, for example „Partner·in einladen“ or „Familie einladen“ (EN: "Invite your partner", "Invite your family"); „Weitere Einladung“ (EN: "Another invite") makes one more.
2. Switch: tap the household's name top left of the list. „Deine Haushalte“ (EN: "Your households") lists them with members and open items; tap one. „Neuer Haushalt“ (EN: "New household") creates one more, „Mit Code beitreten“ (EN: "Join with a code") joins one.
3. Invite later: in „Deine Haushalte“ the person-plus button on a household's row, or „Leute einladen“ (EN: "Invite people") on the household page, or tab „Mehr“ (EN: "More"), row „Partner einladen“ (EN: "Invite your partner"); then „Neue Einladung“ (EN: "New invite") for one person or „Gruppenlink erstellen“ (EN: "Create group link") for a group. In the iPhone and Android apps the share sheet opens right away. Otherwise share it with „Teilen“ (EN: "Share") where the browser offers it, or copy it with „Link kopieren“ / „Code kopieren“ (EN: "Copy link" / "Copy code").
4. To join: „Anderem Haushalt beitreten“ (EN: "Join another household") in „Mehr“, enter the code, „Weiter“ (EN: "Continue"), then „Haushalt beitreten“ (EN: "Join household"). Or open the invite link. Back or „Abbrechen“ (EN: "Cancel") returns to „Mehr“.
5. The household page: tab „Mehr“, the row with the household's name. „Umbenennen“ (EN: "Rename"), „Mitglieder“ (EN: "Members"), „Als Standard nutzen“ (EN: "Make default"), „Haushalt verlassen“ (EN: "Leave household").
6. To revoke: tap „Widerrufen“ (EN: "Revoke") on an invite, on the invites page under „Mehr“ or in the „Leute einladen“ sheet.
7. Confirm new members: the household page, „Beitritte bestätigen“ under „Beitrittsanfragen“ (EN: "Join requests"); open requests are listed there with „Aufnehmen“ and „Ablehnen“. Whoever waits can take the request back with „Anfrage zurückziehen“ (EN: "Withdraw request").

**Never claim.**
- That Snacklist sends invites by e-mail or message: the user shares them.
- That a group link works for more than 50 people or longer than 30 days, or that members (not admins) can make or revoke one.
- That a removed person can never come back: a new invite from the owner or an admin lets them in. Nor that any member can bring them back: in the first 30 days a plain member's invite doesn't.
- That Siri, Alexa or an AI assistant follows the household shown in the app: they use the default household („Siri, Alexa & KI nutzen: …“).
- An archive for households: it is off in the released apps.
- Person invites that stay valid longer than 7 days or work for several people.
- Purchases or Premium tied to joining: Premium is not on sale yet. Premium belongs to one household, not to the person.
- That members can approve joins: only the owner and admins can. Or that older app versions handle a request: they show an error until updated.

**Last verified.** Branch job/178-app, 2026-11-10 (CET), from code, pgTAP (`my_household_removals.test.sql`) and widget and unit tests only, not driven: the removed person's notice in Legal's wording, 15 s, at 358 and 390 px (`switcher_test.dart`), once per device and removal, also at a sign-in on a new device, and the neutral notice for a household left elsewhere (`session_cubit_test.dart`); the join page hint on the sheet „Leute einladen“, „Einladungen“, the guided start's invite step and Step 3 after „Neuer Haushalt“ (`invite_sheet_test.dart`, `onboarding_test.dart`, `guided_start_test.dart`, goldens `invite-sheet-*`). Earlier: main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): the „Leute einladen“ sheet with a group link (QR code, „0 von 50 beigetreten“, valid 30 days, „Link widerrufen“), the household page, the switcher; with „Beitritte bestätigen“ on, „Aufnehmen“ for someone who has reached 10 households lets nobody in. Earlier: main 1c8e8134, 2026-11-09 (CET), on the local stack: someone in 10 households is refused an 11th by creating and by joining with an invite, and stays in 10. Earlier: branch job/173-fix-phone-news-join-cap at 161a8496, 2026-11-09 (CET), from pgTAP (`households_join_cap.test.sql`) and driven on the web build (verify-snacklist): Ida in 10 households joins with a code through Mehr → join screen and reads „Du bist schon in 10 Haushalten. Verlasse einen, bevor du einen neuen anlegst oder beitrittst.“, still 10; after leaving one the same invite joins. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): the household chip and „Deine Haushalte“ (row with members and open items, „Neuer Haushalt“, „Mit Code beitreten“, „Siri, Alexa & KI nutzen: Familie Brandt“); the household page in order (name, members with „Hauptadmin“, „Leute einladen“, „Listen“, „Beitritte bestätigen“, the default, „Haushalt verlassen“); „Leute einladen“ with a person invite and a group link (QR code, „0 von 50 beigetreten“, valid 30 days); a second browser joining from the invite page. Earlier: Branch job/169b-w2, review W2.2 fixes, 2026-11-08 (CET): from pgTAP and widget tests only, not driven: a removed person is refused a plain member's newer invite and let in by the creator's or an admin's (e2e `invite-loop.spec.ts` drives the owner's); removal records are no longer readable by members and are deleted 30 days after the removal; who joined polls only while the sheet or Einladungen is on screen and the app is in the front. Before: branch job/169b-w2, review W2.1 fixes, 2026-11-08 (CET), e2e on the web build (`invite-loop.spec.ts`): a member can't revoke the group link and doesn't get it from the old builds' invites read; who joined follows within seconds (polled); a removed person opening the old group link gets „Dieser Code ist ungültig oder abgelaufen.“ and a new person invite from the owner brings them back; the full-link state („50 von 50 beigetreten“, „Der Link ist voll: Niemand kann mehr damit beitreten.“, „Neuen Link erstellen“ on Einladungen) driven on the web build by review W2.2. Before: branch job/169b-w2 at c57618d3 (job 169b W2), 2026-11-08 (CET), driven on the web build by e2e (`invite-loop.spec.ts`, `households.spec.ts`, `onboarding.spec.ts`): the join page with the inviter's first name, members and open items and no item names; joining from it through sign-up; a group link made in „Leute einladen“, two people joining with it, „2 von 50 beigetreten“ and both names under „Wer ist beigetreten“ live; no group link for members; revoking and a new link (the old one's page says „Diese Einladung gilt nicht mehr“); „Zum Admin machen“, an admin removing a member, the removed person's app saying „Du bist nicht mehr Mitglied von „Verein Grün“.“ when it comes back to the front and showing their other household; members have no remove menu; the sheet in English and dark. Not driven: paste, install referrer. Branch job/168b-onboarding-p2 rebased onto main 6d2a193e (job 168c), 2026-11-08 (CET): from code and widget tests, the guided start's invites and the switcher's new household with its invite step side by side. branch job/168b-onboarding-p2 at 3a2b032d, 2026-11-08 (CET), from code and widget tests (`app/test/onboarding/guided_start_test.dart`): several invites on the guided start's invite screen, each with its own code, „<Name> ist beigetreten“ live and for an invite accepted earlier. Driven on the web build (verify-snacklist `journeys/onboarding.mjs`, German light and English dark, PASS): the first screen, every step, a reload resuming at the stores, no account before the account step, the household made with its kind, stores and three sorted items, two invites, a second browser joining and „… ist beigetreten“ showing without a reload, the list. Earlier: branch job/169b-w2-app, 2026-11-08 (CET): from code and widget tests only. Branch job/169b-app (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven** (switcher, household page, joining without leaving). Unverified until driven on the web build. Before: main 8ad168f5, 2026-11-08 (CET), driven on the web build (verify-snacklist): a new invite with its code, revoking it. Recipe: [household-invites.md](./household-invites.md). Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven** (a link of an own household opens it; the leave dialog reads the members when it opens).

## Several lists and „Ich bringe“

**What it does.** A household can keep more than one list, for example „Wocheneinkauf“ and „Baumarkt“, or a club's „Vereinsheim“ and „Sommerfest“. The first one is „Einkaufsliste“ (EN: "Shopping list") until it is renamed. Each item is on one list; stores, categories and their order are shared by all of a household's lists. With two or more lists, tabs under the household's name switch between them, and new items go to the list shown. For a party or a family gathering, members say what they bring: „Ich bringe das“ (EN: "I'll bring it"), with an amount if they like, and the list shows „Mia bringt 2 · Tom bringt 1“ under the item, „Du bringst“ (EN: "You bring") for your own. Ticking an item off ends what was promised for it.

**How to get there.**
1. New list: tab „Mehr“ (EN: "More"), the household's row, „Neue Liste“ (EN: "New list") under „Listen“ (EN: "Lists"); with two or more lists also the „+“ at the end of the tabs.
2. Switch lists: tap a tab under the household's name. The phone remembers which list it showed.
3. Move an item to another list: press and hold it, pick the list under „Liste“ (EN: "List") in the sheet, „Fertig“ (EN: "Done").
4. Say you bring it: press and hold the item, tick „Ich bringe das“, optionally enter „Wie viel?“ (EN: "How much?"), „Fertig“. Untick it the same way to take it back.
5. Rename, reorder or delete a list (any member can; up to 50 lists): „Listen“ on the household page, the menu next to a list: „Umbenennen“, „Nach oben“, „Nach unten“, „Löschen“ (EN: "Rename", "Move up", "Move down", "Delete").

**Never claim.**
- That stores, categories or their order can differ between lists of one household.
- That deleting a list keeps its items: its items are deleted with it (the dialog says how many open ones). The last list cannot be deleted.
- That Siri or Alexa add to a chosen list: they add to a household's first list (Alexa in the default household, the Siri Shortcut in the household it was set up in). The microphone in the app adds to the list on screen.
- That a promise outlives the person: when a member leaves or is removed, what they said they would bring is cleared.
- That an AI assistant can say „Ich bringe das“ for someone: claims are a person's promise, made in the app.
- That lists can be changed offline: adding, renaming, reordering and deleting lists needs a connection (moving items and „Ich bringe das“ work offline).
- That older app versions show the lists: they show every list's items as one list until updated.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): a second list from the household page shown at once with tabs; „Butter“ open on two lists; „Ich bringe das“ with 2 shows „Butter Du bringst 2“, and Noah sees „Butter Mia Brandt bringt 2“. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): a second list from the household page shown at once with tabs; „Butter“ open on two lists; the edit sheet's „Liste“ and „Ich bringe das“ with „2“ giving „Du bringst 2“ and „Mia Brandt bringt 2“ live on another member's screen. Earlier: Branch job/169b-w3 at 955ba83c (job 169b W3), 2026-11-08 (CET), driven on the web build against the W3 server by e2e (`club.spec.ts`): a second list from the household page and a third from the tabs' „+“, adds staying on the shown list, switching tabs, the shown list kept after a reload, „Kuchen“ open on two lists, moving an item with „Liste“ in the edit sheet, deleting a list from the household page with „Die 2 offenen Artikel darauf werden mit gelöscht.“; „Ich bringe das“ with „2“ showing „Du bringst 2“ on the claimant's phone and „Lea Berg bringt 2“ live on another member's, taking it back, ticking ending a claim; tabs in English and dark. Not driven: rename and reorder lists, offline refusal. Earlier: branch job/169b-w3-app, 2026-11-08 (CET): from code, widget tests and goldens only. Recipe: [lists-and-claims.md](./lists-and-claims.md).

## Links into the app

**What it does.** In the web app at app.snacklist.app (app.hummlist.com shows the same app) and in the test apps from 6 Nov on (see the Never-claims below), a link opens that screen of Snacklist: in the iPhone or Android app when it is installed, otherwise in the browser. A link can open the list, the add field, one store's part of the list, the More tab and its pages (for example „Einladungen“ / "Invites" or „Einstellungen“ / "Settings"), or an invite. In a browser an invite link (`app.snacklist.app/join/<code>`) shows a short page about the invite with „Im Browser beitreten“ (EN: "Join in the browser"), which opens the web app's join screen. Someone who is signed out signs in first and then lands on the linked screen; a new account sets up its household first.

**Links to use.**
- The list: `https://app.snacklist.app/list`
- Add something: `https://app.snacklist.app/add` (opens the add field, ready to type)
- Invite your partner: `https://app.snacklist.app/more/invites`
- Settings (theme, language): `https://app.snacklist.app/more/settings`
- The More tab: `https://app.snacklist.app/more`
- Your household's page (members, lists, invites): `https://app.snacklist.app/more/household`
- All tips: `https://app.snacklist.app/more/tips`
- A store's part of the list: `https://app.snacklist.app/stores/<id>`. The id belongs to one household, so this link only works for its members; don't put it in emails to everyone.

**Never claim.**
- That these links (other than invite links) open the phone apps for everyone. Only the test apps from 6 Nov on (TestFlight, Google Play internal testing) have them, and that they open the app is not yet checked on a phone. The store apps get them with the first public release. Invite links already work everywhere and open the apps.
- That app.snacklist.app links open an installed app today. The Hummlist test apps open only app.hummlist.com links. The Snacklist apps open both after the next test release. Until then an app.snacklist.app link opens the browser.
- Links that fill in an item ("add Milch") or tick something off: a link only opens a screen.
- That a link keeps working after the app was closed during sign-in on the phone: it then opens the list.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `/add` opens the list with the add field focused; `/more/invites`; `/more/legal` goes to More; signed out, `/more/household` waits through the login. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `/more/tips` and `/more/household` open their pages; signed out, `/more/household` waits through the login screen. Earlier: Branch job/169b-w2 at c57618d3, 2026-11-08 (CET), e2e on the web build: `/join/<code>` shows the invite page, its button opens the app's join flow; signed out, sign-in keeps the invite. main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): /add opens the add sheet, /more/invites opens „Einladungen“, unknown paths land on the list, a store link shows that store's section on top; signed out, the link waits through sign-up. Earlier: the change that made store links wait, 2026-11-07 (CET), driven on the web build: a store link opens the list at that store also when this device's saved list is older than the store's items (it waits for the server's first answer; offline it opens the list as it is). Recipe: [app-links.md](./app-links.md).

# The list

## Quick add

**What it does.** The field floating at the bottom of the list, „Was brauchst du?“ (EN: "What do you need?"), is how items get onto the list. As soon as you type or tap it, a sheet opens with suggestions: what you typed, things you bought before, other packs, kinds, sizes and brands, and words from a built-in catalogue; they also find what you meant despite a small typo ("Hafermlch" offers Hafermilch). Enter takes the first suggestion, a tap takes any. Snacklist reads amounts out of what you type, in front or behind, as digits or words, German or English, also without a connection ("2 l Milch", "6x Eier", "zwei Gurken", "Gurken zwei", "two apples", "Karotten 2", "Karotten x2"), and a number that belongs to the item is not taken as an amount ("Windeln Größe 4", "Vitamin D3", "7up", "Drei Glocken Spaghetti"); and picks the category and, where it knows one, the store. After an add the field is empty and ready for the next item, and „Rückgängig“ (EN: "Undo") takes the last add back. On a computer the mouse wheel or trackpad scrolls the list also with the pointer on the field or the tab bar.

**How to get there.**
1. Open Snacklist and stay on the „Liste“ (EN: "List") tab.
2. Type into „Was brauchst du?“ (EN: "What do you need?") or tap anywhere on it.
3. Press Enter for the first suggestion, or tap another row. Before you take a row you can choose a store and a category with the two chips at the top of the sheet. Until you do, they show what Snacklist picked, in grey with a small "A" for automatic (just „Laden“ / "Store" while it knows no store). The store chip also offers „Neuer Laden“ (EN: "New store") to add a store on the spot.
4. Close with the ✕ at the top right („Schließen“, EN: "Close"), Escape, or a tap on the list behind. The sheet stays closed until you tap the field or type again, also when you close it right after an add. Closing while Enter still waits for its suggestions adds nothing.

**Never claim.**
- That suggestions forgive any spelling. They forgive one wrong letter in short words and two in longer ones ("Hafermlch" finds Hafermilch) and find a word from 4 letters inside it ("milch" finds Hafermilch), online and offline alike.
- That the microphone works in the browser (it is on iOS and Android only).
- That the cursor jumps into the field on phones when the app opens (only on desktop and web).
- That an item already on the list can be added twice to that list; Snacklist says „<name> steht schon auf der Liste“ (EN: "<name> is already on the list"). A household with several lists can have the same item open on two of them. Two people adding the same item at the same moment also end up with one.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/quick-add.mjs` (DE and EN); the store chip folds out „Ohne Laden“, the stores, „Neuer Laden“. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/quick-add.mjs` (DE and EN): a catalogue suggestion filed under its category. Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `journeys/quick-add.mjs`: a catalogue suggestion tapped and filed under its category. main 6c93da99, 2026-11-08 (CET): the same in English. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): a catalogue suggestion tapped and filed under its category (DE and EN), the field floating over the list with the tab pill below it; the mouse wheel over the field and over the tab pill scrolls the list. Recipe: [quick-add.md](./quick-add.md).

## Due again

**What it does.** Snacklist notices what a household buys regularly. When you open the add bar with nothing typed, items that are probably running out show up as „Wieder fällig“ (EN: "Due again"); one tap puts them on the list with the quantity from last time. An item shows up once it was bought on at least two different days and about its usual time between purchases has passed. Below them come the items used in the last 30 days, marked „Zuletzt verwendet“ (EN: "Recently used"), up to 10 rows in all. The sheet opens small, with three of them; the others scroll.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Tap the bar „Was brauchst du?“ (EN: "What do you need?") without typing.
3. Tap a row marked „Wieder fällig“ (EN: "Due again").

**Never claim.**
- That Snacklist sends reminders or notifications about due items; it only shows them in the add sheet.
- That it works from a single purchase; it needs at least two purchase days.
- That it predicts quantities by season or guesses new items; it only repeats what the household bought.
- That an item stays due until it is bought: it drops out after about four times its usual time between purchases.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): a household with eight weeks of shopping sees eight items „Wieder fällig“. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): a household with eight weeks of shopping sees eight items „Wieder fällig“. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): a household with eight weeks of shopping sees eight items „Wieder fällig“; an open „Aepfel“ (another spelling) takes „Äpfel“ off them. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): a household with eight weeks of shopping sees eight items „Wieder fällig“ with the field empty; a tap adds one with „✓ Hinzugefügt“. Recipe: [usuals.md](./usuals.md).

## Dictation

**What it does.** In the iPhone and Android apps, a microphone next to the add bar lets people speak what they need. Snacklist listens in German, on the phone only, so the voice never goes to a server. The words appear as they are spoken, the latest always in view, and, when the person pauses, Snacklist splits the sentence into separate items ("Milch, zwei Gurken und Klopapier") and adds them. An amount said after the item counts too: „Gurken zwei“ adds 2 Gurken. Brand and details are read out as when typing: „Windeln Pampers Größe 3“ adds Windeln with the brand Pampers and the detail Größe 3. A product name that starts with a number stays whole, as when typing: „Drei Glocken Nudeln“ is one item, while „drei Äpfel“ adds 3 Äpfel. It then shows a short message with what it added. One sentence takes up to 30 items; with more, the first 30 are added and the message asks to say the rest again.

**How to get there.**
1. Open the Snacklist app on an iPhone or Android phone, on the „Liste“ (EN: "List") tab.
2. Tap the microphone at the right of „Was brauchst du?“ (EN: "What do you need?") („Diktieren“, EN: "Dictate").
3. Say what you need. Tap the red button („Diktat beenden“, EN: "Stop dictation") to stop early.
4. The first time, allow microphone and speech recognition when the phone asks.

**Never claim.**
- That dictation works in the web app or on a computer; there is no microphone button there.
- That the voice is sent to a server or stored; recognition happens on the device.
- That it understands languages other than German.
- That it works on phones without German offline speech data; the app then asks to download it or to type instead.

**Unverified.** Behaviour on real devices (permission prompts, recognizer) was read from code, not run.

**Shown on snacklist.app.** The landing page's "In der App" / "In the app" card has a video of it: the real app with a scripted recognizer, „Pizza, Orangensaft und zwei Packungen Fischstäbchen“ landing under Getränke and Tiefkühl. The English video shows the same German sentence, because the app listens in German.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), the splitter on the local stack: „Gurken zwei und Windeln Pampers Größe 3 und Drei Glocken Nudeln und drei Äpfel“ gives 2 Gurken, Windeln / Pampers / Größe 3, Drei Glocken Nudeln, 3 Äpfel. Earlier: main c3636541, 2026-11-09 (CET), the splitter on the local stack: „Gurken zwei und Windeln Pampers Größe 3 und Drei Glocken Nudeln und drei Äpfel“ gives 2 Gurken, Windeln / Pampers / Größe 3, Drei Glocken Nudeln and 3 Äpfel. No microphone on the web build; the microphone itself needs a phone. Earlier: Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and tests only, **not driven**: dictation splits in the household shown. main 6c93da99, 2026-11-08 (CET), the splitter on the local stack: „Drei Glocken Nudeln und drei Äpfel“ gives Drei Glocken Nudeln and 3 Äpfel; „Gurken zwei und Windeln Pampers Größe 3“ gives 2 Gurken and Windeln / Pampers / Größe 3. No microphone on the web build. The microphone itself needs a phone. Earlier: main c2ce938f, 2026-11-07 (CET), the splitter on the local stack: „Drei Glocken Nudeln und drei Äpfel“ gives Drei Glocken Nudeln and 3 Äpfel; „Gurken zwei“ and „Windeln Pampers Größe 3“ split right. The microphone itself needs a phone. Recipe: [dictation.md](./dictation.md).

## Ticking items, "Zuletzt verwendet" and undo

**What it does.** Tapping an item on the list ticks it off: a line strikes through it, the row turns mint and slides away in under half a second, without a message. There is no check box to tap; the whole row is the target. At the bottom of the list, „Zuletzt verwendet“ keeps up to 20 recently ticked items of that list, each one only once, and leaves out anything that is back on the list; tapping one puts it back where it was. With nothing typed, the add bar also suggests recently used items under the same name, „Zuletzt verwendet“ (EN: "Recently used"). Ticking an item off is how it leaves the list. An item added by mistake can be undone with „Rückgängig“.

**How to get there.**
1. Open the list and tap an item to tick it.
2. Scroll to the bottom and tap „Zuletzt verwendet“ (EN: "Recently used") to unfold it.
3. Tap the item to put it back; it reappears in its old place, without a message.
4. To remove an item, tick it off. Screen reader users also find „Löschen“ (EN: "Delete") among an item's actions, with „Rückgängig“ (EN: "Undo") right after.

**Never claim.**
- That ticking shows an undo message; it does not. Undo for a tick is the „Zuletzt verwendet“ section.
- A check box next to each item: there is none.
- That swiping does anything on a row: it neither deletes nor edits; holding opens editing.
- That the edit sheet deletes an item; it has no delete button. Tick the item off instead.
- That ticked items vanish after a fixed time or can be counted past 20 there.

**Unverified.** Whether ticked items are ever removed from the section by age: no cleanup job was found in the code, but it was not run.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/tick-and-undo.mjs` (DE and EN). Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/tick-and-undo.mjs` (DE and EN). Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `journeys/tick-and-undo.mjs`: tick without a message, putting back from „Zuletzt verwendet“. main 6c93da99, 2026-11-08 (CET): the same in English. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist), `journeys/tick-and-undo.mjs`: tick without a message, putting back from „Zuletzt verwendet“ (DE and EN). Recipe: [tick-and-undo.md](./tick-and-undo.md).

## Edit an item

**What it does.** Every item can be changed after it is on the list: its name, brand, details (like "Größe 3" or "1,5 %"), quantity, store and category, and, in a household with several lists, the list it is on. The same sheet is where someone says „Ich bringe das“ (see "Several lists and „Ich bringe“"). The list row shows the quantity in bold in front of the name („6× Bananen“) and the brand and details in small text under the name. The sheet does not delete; to remove an item, tick it off.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Press and hold an item, or right-click it on a computer. (A plain tap ticks the item off instead.)
3. In the sheet „Bearbeiten“ (EN: "Edit") change „Bezeichnung“ (EN: "Name"), „Marke“ (EN: "Brand"), „Menge“ (EN: "Qty") with the buttons „Eins weniger“ / „Eins mehr“ (EN: "One less" / "One more"), or „Eigenschaften“ (EN: "Details"), or pick another store or category with the chips. The store chip also offers „Neuer Laden“ (EN: "New store", the row with a plus) to add a store and pick it. Snacklist remembers the new store or category the next time the item is added. With several lists, „Liste“ (EN: "List") moves the item to another list.
4. Tap „Fertig“ (EN: "Done") to save, or „Abbrechen“ (EN: "Cancel") next to it to drop every change and close the sheet.
5. Renaming an item to exactly the name of something already open on the same list (capital letters, spaces, and ae/oe/ue for ä/ö/ü don't matter) does not make a second entry: the two become one. The item already there keeps its name, store and category, the amounts add up, and „Zusammengeführt: <amount> <name>“ (EN: "Merged: …") shows with „Rückgängig“ (EN: "Undo"). This also holds when the rename was made offline or on two phones at the same moment: once the phone is back online, the two become one. If they cannot be combined (the amount would get too long), Snacklist says „<name> steht schon auf der Liste“ (EN: "<name> is already on the list"), keeps the old name and does not save the change.

Each field's name sits above its field; what is typed sits in the middle of the field, left-aligned.

**Never claim.**
- That a swipe deletes or edits an item; a swipe does nothing, a hold opens the edit sheet.
- That the sheet has a delete button; its buttons at the bottom are „Abbrechen“ and „Fertig“. Tick an item off to remove it.
- That Undo after a screen reader's delete always brings back your own quantity: when the item is on the list again by then, the one there stays as it is.
- That items in „Zuletzt verwendet“ (EN: "Recently used") can be edited.
- That the quantity buttons work on free text like "eine Packung"; they only step numbers.
- That holding and dragging moves an item on the list; nothing on the list drags. Holding opens this sheet.
- That renaming to another word for the same thing („Semmeln“ while „Brötchen“ is on the list) or to an item with a brand merges them; Snacklist only points it out („Brötchen steht schon auf der Liste“ with „Zusammenführen“), as when adding.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/edit-item.mjs` (a rename onto an open item merges, „Rückgängig“); the sheet's „Liste“ and „Ich bringe das“. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/edit-item.mjs` (a rename onto an open item merges, „Rückgängig“); the sheet's „Liste“ and „Ich bringe das“ with two lists. Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `journeys/edit-item.mjs`: the sheet with „Abbrechen“ and „Fertig“, a rename onto an open item merging with „Rückgängig“. main 6c93da99, 2026-11-08 (CET): the same in English, and `journeys/hex-surfaces.mjs`. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist), `journeys/edit-item.mjs` and `journeys/hex-surfaces.mjs`: the sheet with „Abbrechen“ and „Fertig“ and no delete, a rename onto an open item merging with „Rückgängig“. Recipe: [edit-item.md](./edit-item.md).

## Tips on the list

**What it does.** In a new household, once the first item is on the list, a small card „Erste Schritte“ (EN: "First steps") shows at the top (an empty list shows nothing): list started, invite someone (for households that shop together), do one shop, and for a club „KI-Assistenten verbinden“ (EN: "Connect an AI assistant"). Each item ticks itself off when it happens; „Einladen“ (EN: "Invite") and „Öffnen“ (EN: "Open") lead there. The card goes once everything is done, or with its X. After that, Snacklist shows a short tip only once it is useful: after five typed items without an amount, how to type the amount; after a first finished shop, that the categories can be sorted in the order you walk through the shop; after a day alone on the list, an invite; and so on. At most one tip per app start, a new one at most once a day, never while you are typing or a window is open, and a tip goes for good once you use what it is about, tap its X, or have seen it three times. After the X, a note says where all tips are: Mehr → „Tipps“ (EN: More → "Tips"), which lists every tip to read again.

**How to get there.**
1. Create a household and add the first item: „Erste Schritte“ is at the top of „Liste“ (EN: "List").
2. Tips come by themselves later. To read them all: „Mehr“ (EN: "More") → „Tipps“ (EN: "Tips").

**Never claim.**
- That tips or the checklist sync between devices or members (they are per device and user; the checklist per household).
- That tips show news, offers or Snacklist Premium (they are how-tos and invitations).
- That a tip can be snoozed: the X hides it for good, and the „Tipps“ page shows it again.
- A Siri tip: none shows today, on any device, until Siri without the Shortcut is announced.
- That Snacklist sees a placed widget everywhere.
- A tip that offers a second household: those tips are built but switched off; a second household is made from the household switcher („Neuer Haushalt“).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/tips.mjs`; a new, empty list shows no „Erste Schritte“, and the first item brings it. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/tips.mjs` („Artikel bearbeiten“ after 10 s, X with „Alle Tipps unter Mehr → Tipps.“, none after a reload); Mehr → „Tipps“ lists six tips in the browser. Earlier: branch job/168b-hints, 2026-11-08 (CET), from code and widget tests (`app/test/tips/`); driven on the web build at 3a2b032d (verify-snacklist `journeys/tips.mjs`, PASS): More → Tipps lists the hints, „Artikel bearbeiten“ shows as a flat card 10 s after the start, X shows „Alle Tipps unter Mehr → Tipps.“ and hides it, no new hint after a reload. Earlier (job 80's fixed tips): main 8ad168f5, 2026-11-08 (CET), `journeys/tips.mjs`. Recipe: [tips.md](./tips.md).

## Automatic category (the classifier)

**What it does.** When an item is added, Snacklist sorts it into a category on its own, such as Kühlregal for Hafermilch, using a built-in German word list of about 1,350 terms plus common spelling variants, regional words, some English words and small typos. While you type, the add sheet already shows the category it will use. It also knows about 270 DIY words (Schrauben, Dübel, Glühbirne, Wandfarbe, Blumenerde …): with a Baumarkt they go to its categories and to that store, without one to „Haushalt“. Anything unknown goes to „Sonstiges“. If you move an item to another category, or pick another one before adding, the household remembers it and the same item lands there next time, also under another spelling of the same word (Karotten, Möhren), and also when you add it again right away on a slow connection. This works the same for items added in the app, by voice, through the AI-assistant connection, Siri and Alexa.

**How to get there.**
1. Type an item in the add bar on the „Liste“ tab and add it; it appears under its category.
2. To correct it, hold the item and tap the category chip (it shows the current category, such as „Kühlregal“), pick another one, tap „Fertig“ (EN: "Done").
3. To choose before adding, tap the category chip in the add sheet (it shows the guess in grey with a small "A" for automatic, or „Kategorie“ / "Category" before you type).

**Never claim.**
- That it understands every word, or any typo; very short words and unusual typos stay in „Sonstiges“ on purpose.
- That it uses AI or learns across households; each household's corrections stay in that household.
- That it works for every language; the word list is German, with a few English synonyms.
- That Siri and Alexa are generally available: Siri's native integration is held and Alexa is in beta, not certified.

**Offline.** An item added without a connection shows under „Wird einsortiert …“ (EN: "Sorting …") until the connection is back, then moves under its category. Online, items arrive already sorted.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): Hafermilch under Kühlregal, Quietscheentchen under Sonstiges; DIY words in the Baumarkt categories (`journeys/baumarkt.mjs`). Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): Hafermilch under Kühlregal, Quietscheentchen under Sonstiges; DIY words in the Baumarkt categories (`journeys/baumarkt.mjs`). Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): Hafermilch and „Mlich“ under Kühlregal, „Quietscheentchen“ in Sonstiges; DIY words in the Baumarkt categories of a household with a Baumarkt (`journeys/baumarkt.mjs`, DE and EN). Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): new items under their category; „Mlich“ under Kühlregal, „Kaffe“ and „Mehk“ in Sonstiges; DIY words in the Baumarkt categories of a household with a Baumarkt (`journeys/baumarkt.mjs`). Recipe: [classifier.md](./classifier.md).

## Categories

**What it does.** Items on the list sit under categories such as Obst & Gemüse or Getränke. Every household starts with 11 and can add its own, rename any, reorder them, and delete any except „Sonstiges“. A new category goes just before „Sonstiges“. Names are unique in a household regardless of upper and lower case: adding „baby“ when „Baby“ exists, or renaming another category to it, adds nothing and says „Eine Kategorie „Baby“ gibt es schon.“ in the dialog, so the user can pick another name. When a category is deleted, its items move to a category the user picks („Sonstiges“ unless changed).

**How to get there.**
1. On the list, tap „Anpassen“ (EN: "Edit") top right.
2. Tap „Ohne Laden“ (EN: "No store"), the last row, for the household's own order; or tap a store for that store's order of the same categories.
3. Tap a category to rename it, the trash icon to delete it (it disappears from every store), the handle to drag it; „Kategorie hinzufügen“ (EN: "Add category") adds one. The rows carry no numbers: their order on screen is the order.

A household that adds a store called „Baumarkt“ (EN: also "Hardware store") gets seven more, just before „Sonstiges“: Farben & Lacke, Sanitär, Elektro & Leuchtmittel, Werkzeug, Schrauben & Befestigung, Holz & Baustoffe, Garten & Pflanzen (EN: Paint & varnish, Plumbing, Electrical & lighting, Tools, Screws & fixings, Wood & building, Garden & plants). Its own categories keep their names and order. Households without a Baumarkt never see them. Deleting the Baumarkt store later keeps the seven categories; the household deletes them one by one if it wants them gone.

The starting categories, in order: Obst & Gemüse, Brot & Backwaren, Kühlregal, Fleisch/Wurst/Fisch, Vorrat & Konserven, Süßes & Snacks, Getränke, Tiefkühl, Haushalt, 👶 Drogerie, Sonstiges (EN: Fruit & veg, Bread & bakery, Chilled, Meat & fish, Pantry, Sweets & snacks, Drinks, Frozen, Household, 👶 Drugstore, Other).

**Never claim.**
- Numbered categories or steps; the rows show no numbers (a screen reader still hears „2 von 11“).
- That "Sonstiges" can be deleted; it is the fallback for anything unrecognised.
- That categories are per store; stores only have their own order of the same categories.
- That deleting the Baumarkt store removes its categories; they stay until deleted one by one.
- That every household has Baumarkt categories; they come with a store called „Baumarkt“ (or "Hardware store", „Heimwerkermarkt“, "DIY store").
- That Snacklist knows a particular DIY chain; it recognizes only the generic word.
- A fixed number of categories or any limit on how many you add (none found).
- Category names longer than 60 characters; the name field stops at 60.
- Two categories whose names differ only in case or spacing ("Baby" and "baby"); they cannot exist any more, and households that had them now have one.

**Unverified.** Whether there is a limit on the number of categories: none found in the app.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): „Anpassen“ → „Ohne Laden“ with its 11 categories, every one deletable but Sonstiges; `journeys/baumarkt.mjs`. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): „Anpassen“ → „Ohne Laden“ with its 11 categories, every one deletable but Sonstiges; `journeys/baumarkt.mjs`, `list-manage.mjs`. Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): „Anpassen“ → „Ohne Laden“, adding „Baby“, the duplicate message for „ BABY“, deleting it. main 6c93da99, 2026-11-08 (CET): `journeys/baumarkt.mjs` (DE and EN); after the journey deletes its Baumarkt store, the seven categories stay under „Ohne Laden“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): „Anpassen“ → „Ohne Laden“ with the 11 categories, adding „Baby“, the duplicate message for „ BABY“, deleting it with the move-to choice; `journeys/baumarkt.mjs` (DE and EN): a store „Baumarkt“ brings its seven categories. Recipe: [categories.md](./categories.md).

## Stores, walk order and the sections of the list

**What it does.** The list is split into one section per store (only stores that have something on the list), then „Ohne Laden“. Inside a store, items are grouped by category in that store's own walking order, so the list follows the way you walk through the shop. An item moves to another store or category in its edit sheet, and the household remembers which store an item belongs to. The list itself never drags: the order of stores and categories is changed in „Anpassen“. A new household has the stores it picked at the start; you can change their order and add your own stores (Rewe, the market, the bakery), each with its own walking order, rename them or delete them. A store called „Baumarkt“ (onboarding offers it too) brings Baumarkt categories and a Baumarkt walking order (paint first, garden by the tills), and DIY items such as screws, paint or potting soil go to it on their own. Each item shows a small picture when its name says what it is (about 1,400 everyday items in German and English, from bananas to gift cards and screws); anything else shows a plain hexagon instead of a guess. New item pictures can arrive without an app update; the list's contents are never sent for that.

**How to get there.**
1. Open the „Liste“ tab (EN: "List"): each store is a section; tap a store's name to fold it, tap again to unfold it.
2. To change a store's category order, open „Anpassen“ (step 4) and tap the store. Holding or right clicking a store's name or a category heading on the list does nothing.
3. Hold an item (or right-click it), tap the store chip and pick a store to put it in that store.
4. On the list, tap „Anpassen“ (EN: "Edit") top right: the stores in list order, „Ohne Laden“ (EN: "No store") last. Drag the handle to reorder, the trash icon deletes a store, „Laden hinzufügen“ (EN: "Add store") adds one; a name you have already, in any spelling of upper and lower case, keeps the window open with „Einen Laden „Lidl“ gibt es schon.“ (EN: "A store named “Lidl” already exists."). Tap a store to rename it (its name on top) and to order its categories.
5. While adding or editing an item, open the store chip and tap „Neuer Laden“ (EN: "New store", the row with a plus), type the name and press Enter: the store is created and chosen for the item.

**Never claim.**
- Store logos, chain colours or official store maps. Store names appear as plain names in a small hexagonal label. The walking orders are researched defaults that can differ from a real shop.
- That items, stores or categories can be dragged around on the list; moving an item is the edit sheet's store or category choice, and ordering lives in „Anpassen“.
- That holding a store's name or a category heading opens the store; only „Anpassen“ does (since job 171).
- That the app knows prices, opening hours or store locations.
- That every item gets a picture, or that the pictures come from AI or from the household's own lists. They come from a fixed table of item names that comes with the app and that Snacklist can extend from snacklist.app.
- That stores can be added, renamed or deleted without a connection; the app asks for one.

**Note.** The onboarding skip hint says „Du kannst sie später unter Liste → Anpassen anlegen.“ / "You can add them later under List → Edit." (jobs 68, 78).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/baumarkt.mjs`, `list-manage.mjs`, `hex-surfaces.mjs`, `top-bar-and-name-dialog.mjs`, `item-icons.mjs`. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/baumarkt.mjs`, `list-manage.mjs`, `hex-surfaces.mjs`, `top-bar-and-name-dialog.mjs`, `item-icons.mjs` (with a newer picture table from hummlist.com). Earlier: Branch job/171-store-header-tap (PR #329), 2026-11-08 (CET), from code, widget tests and the e2e spec list-walk-order: a hold or right click on a store's name or a category heading opens nothing, a tap folds. main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): adding „Supermarkt“, then „supermarkt“ keeps the window open with „Einen Laden „Supermarkt“ gibt es schon.“. main 6c93da99, 2026-11-08 (CET): `journeys/baumarkt.mjs` (DE and EN), `item-icons.mjs` (with a newer picture table from hummlist.com), `hex-surfaces.mjs`, `list-manage.mjs`, `top-bar-and-name-dialog.mjs`. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): „Anpassen“ as a raised hex top right, „Läden“, adding a store, adding „supermarkt“ while Supermarkt exists (the window stays open with „Einen Laden „Supermarkt“ gibt es schon.“, no second store), item pictures and the plain hexagon on a mixed list, a newer picture table from hummlist.com, the rename dialog fitting its content; `journeys/baumarkt.mjs` (DE and EN): Schrauben, Dübel, Glühbirne, Wandfarbe, Silikon and Blumenerde in the Baumarkt section in its walking order, Milch outside it. Recipe: [stores-walk-order.md](./stores-walk-order.md).

## Live sync between household members

**What it does.** Everyone in a household sees the same list, live. When a partner adds, ticks off, edits or moves an item, it shows on the other phone within a couple of seconds, with no reload. New items from a partner are highlighted, and the floating bar at the top of the list says how many are new and from whom, until they have been on screen for a moment.

**How to get there.**
1. Both people join the same household: one uses „Mehr“ (EN: "More") → „Partner einladen“ (EN: "Invite your partner"), the other opens the link or enters the code.
2. Open „Liste“ (EN: "List"). Changes appear on its own.
3. In the floating bar at the top of the list: „1 neu von Noah Brandt“ (EN: "1 new from Noah Brandt"); on a phone it shows right below the household's name, or below the list tabs when the household has several lists. While the phone is offline or syncing has trouble, a card under the bar says so and then folds into a small pill next to the household's name (see "Working offline"); nothing shows while changes are simply being sent.

**Never claim.**
- Sync with people outside the household, or with a read-only guest view.
- Push notifications for a partner's changes.
- That the list updates with the app fully closed in the background.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), driven on the web build (verify-snacklist) at 390 px: Noah's add shows „1 neu von Noah Brandt“ on Mia's phone within a second, below the list tabs when the household has two lists, and goes after about 3 s on screen. Earlier: main 1c8e8134, 2026-11-09 (CET), driven on the web build (verify-snacklist) at 390 px: Noah's add shows „1 neu von Noah Brandt“ on Mia's phone after under 2 s, read first by a screen reader. Earlier: branch job/173-fix-phone-news-join-cap at 161a8496, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): Noah's add shows „1 neu von Noah Brandt“ on Mia's phone right below „Familie Brandt“ at 390 and 360 px, whole and in the accessibility tree, cleared once seen; at 1366 px in the bar. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): two members side by side on a 1366 px wide window: a partner's add shows „1 neu von Noah Brandt“ within 2 s; a partner's „Ich bringe das“ shows live; the household's name and the sync pill side by side in the bar. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), two members side by side: a partner's add shows „1 neu von Noah Brandt“ within a second; a tick on one phone removes the row on the other. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist), two members side by side: a partner's add shows „1 neu von Noah Brandt“ within a second, a tick on one phone removes the row on the other; the offline cloud beside „Anpassen“. Recipe: [live-sync.md](./live-sync.md).

## Working offline

**What it does.** The shopping list keeps working without a connection: adding, ticking off, putting back and editing items all show up immediately and are sent automatically once the phone is back online. The app also opens offline and shows the last list it had. A dark card at the top of the list says "Offline" as soon as the phone loses its connection (flight mode, Wi-Fi off), with no tap needed, and goes away on its own a moment after the connection is back, when changes from others in the household arrive again right away; it folds into a small "Offline" pill after about 3 s or as soon as the user scrolls. When the server has trouble instead, and the app's own retry a few seconds later fails too, a yellow "Sync gestört" (EN "Sync failing") card says the changes are saved on the phone; a tap tries again, and once it works the card simply goes away. A single hiccup that the retry gets past shows nothing. Nothing shows while everything is in sync. Suggestions while typing still work offline, from items the household used before, even with a typo or part of a word, and the empty field still shows what is due again. A few settings-type actions (reordering stores or categories, adding, renaming or deleting a store, creating or joining a household, exporting data, deleting the account, sending feedback) need a connection and say so, also while the dialog or sheet they were started from is still open. Changes to categories made offline are not saved: the app says so and puts them back. If someone else added the same item while you were offline, your add becomes theirs when it syncs (no second row), and what you did to it offline, like ticking it off, goes to theirs. Amounts typed offline are read the same way as online, also as words („zwei Gurken“, "two apples"). Brand and details typed offline („Windeln Pampers Größe 3“) are sorted out when the add syncs, as for an online add. Someone in several households can switch to another one while offline: what they changed in the first is still sent once the phone is back online, without opening it again.

**How to get there.**
1. Open „Liste“ (EN: "List") and use it as usual with the connection off.
2. The card „Offline“ shows under the bar at the top of the list: „Änderungen werden synchronisiert, sobald du wieder online bist.“ (EN: "Your changes will sync once you're back online."). After about 3 s, or when you scroll or swipe it up, the card shrinks into the small „Offline“ pill next to the household's name, left of „Anpassen“ (EN: "Edit"); tap the pill to read the card again.
3. When the connection returns, the card or pill goes away on its own within a few seconds, with no tap and no message. If it says „Sync gestört“ (EN: "Sync failing") instead, tap it to try again.

**Never claim.**
- That a partner sees offline changes before they sync.
- A "back online" or "synced" message: the indicator just goes away (screen readers hear „Synchronisiert“ after a tapped retry only).
- That reordering stores or categories, adding or changing stores or categories, feedback or account actions work offline.
- Offline voice dictation to a server: dictation stays on the device, but splitting text into items needs a connection.

**Unverified.** Offline sign-in, and a first start offline before the list was ever synced (not covered by specs or read in detail).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/offline.mjs` (amounts typed offline match online); offline, the card folds into the pill next to the household's name. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/offline.mjs` (amounts typed offline match online); offline, the pill next to the household's name. Earlier: Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven**: changes queued in one household are sent after a switch to another and after a restart. main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): offline, the „Offline“ card at once, folded into the pill after about 3 s, open again on a tap, gone under a second after the connection came back with no tap. main 8ad168f5, 2026-11-08 (CET): a server answering 503 shows nothing at first and „Sync gestört“ once the retry fails too; a tap names it „Wird erneut versucht“ until it goes through, then it leaves; `journeys/offline.mjs`: amounts typed offline match the ones typed online. Earlier: the connection-recovery change before it landed, 2026-11-07 (CET), driven on the web build (verify-snacklist and e2e `connectivity.spec.ts`) with the live socket left dead and open across a network drop: back online, „Offline“ goes about 3 s later and a partner's add shows within a second (before: 39.5 s, after the heartbeat). Recipe: [offline.md](./offline.md).

# Settings, help and account

## Theme: System, light, dark

**What it does.** The user chooses between „System“ (follow the device), light and dark in one three-part switch. The choice applies immediately across the whole app and is remembered on that device, also after signing out. By default the app follows the phone's or browser's own light/dark setting.

**How to get there.**
1. „Mehr“ (EN: "More") → „Einstellungen“ (EN: "Settings").
2. Under „Darstellung“ (EN: "Appearance") tap „System“ (EN: "System"), „Hell“ (EN: "Light") or „Dunkel“ (EN: "Dark").

**Never claim.**
- That the choice follows the account to other devices.
- A scheduled or automatic day/night switch beyond „System“.
- The old label „Wie Gerät“ for the theme (it is „System“ since 2026-11-01).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): „Dunkel“ kept after a reload. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): „Dunkel“ kept after a reload, back to System. Earlier: job 154b (PR #320, ba198151), 2026-11-08 (CET), driven on the web build in its review: „Darstellung“ and „Sprache“ sit in cards like the rows on „Mehr“; System, „Dunkel“ and back still switch. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): „Darstellung“, „Dunkel“ kept after a reload, back to System. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): „Darstellung“ with System, „Dunkel“ kept after a reload, and back. Recipe: [theme.md](./theme.md).

## App language

**What it does.** The app is available in German and English. It follows the device language by default (German if the device uses neither); the user can override that. The switch is instant, covers the whole app and is remembered on that device.

**How to get there.**
1. „Mehr“ (EN: "More") → „Einstellungen“ (EN: "Settings") → „Sprache“ (EN: "Language").
2. Pick „Wie Gerät“ (EN: "Device"), „Deutsch“ or „English“.

**Never claim.**
- Any language besides German and English.
- That the language is stored in the account or follows the user to other devices.
- That Alexa or AI assistants answer in the app's language: Alexa answers in the language of the Alexa device (German or English), AI assistants get German answers.
- That everything is English once the app is set to English: suggestions from the catalogue („Aus dem Katalog“, EN: "From the catalogue") stay German words, the Siri Shortcut answers in German and the sign-in emails are short English emails whatever the app language.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): English live, back to German. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): English live, back to „Wie Gerät“. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): English live, back to „Wie Gerät“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): English live, the list in English, back to „Wie Gerät“. Recipe: [language.md](./language.md).

## Feedback

**What it does.** Users can send Peter a short note from inside the app: a bug, an idea or anything else, up to 2000 characters. They can optionally say Peter may contact them. The app attaches its version, device type, language and the screen the user came from, but never anything from the shopping list. If there is no connection the note stays in the form and can be sent again.

**How to get there.**
1. „Mehr“ (EN: "More") → „Feedback senden“ (EN: "Send feedback").
2. Write in „Deine Nachricht“ (EN: "Your message"), optionally pick „Bug“, „Idee“ or „Sonstiges“ (EN: "Bug", "Idea", "Other") and tick „Peter darf mich dazu kontaktieren“ (EN: "Peter may contact me about this").
3. Tap „Senden“ (EN: "Send"); the app answers „Danke!“ (EN: "Thanks!").

**Never claim.**
- Shake-to-report, feedback from the list screen, or screenshots/attachments.
- A reply is guaranteed; contact only happens if the box is ticked and Peter chooses to.
- That list contents are sent.
- That users can read their sent notes back in the app (they come back only in their own data export, Konto → „Meine Daten exportieren“, EN "Export my data").

**Unverified.** How quickly or by what channel Peter sees notes (not in the app).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): a note sent, „Danke!“. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): a note sent, „Danke!“; the row after „Tipps“. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): a note sent from a new account, „Danke!“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): the sheet with its kinds, contact box and the „Wird mitgeschickt“ line, a note sent, „Danke!“. Recipe: [feedback.md](./feedback.md).

## The More tab, help and legal pages

**What it does.** The app has two tabs, List and More. On phones they sit in a small pill that floats at the bottom of the screen; the list scrolls on behind it. More is a short list of grouped rows, each one line with an icon, in this order: „Konto“ (EN: "Account") and, for a household that has Premium (a free unlock in the beta or for testers) or once Premium is on sale, „Snacklist Premium“; the household's name (it opens the household's page), „Partner einladen“ (EN: "Invite your partner") and „Anderem Haushalt beitreten“ (EN: "Join another household"); „Zugänge“ (EN: "Access"); „Einstellungen“ (EN: "Settings") and „Nutzungsdaten“ (EN: "Usage data"); „Tipps“ (EN: "Tips"), „Feedback senden“ (EN: "Send feedback"), in the iPhone and Android apps „Snacklist bewerten“ (EN: "Rate Snacklist"), and „Hilfe & Kontakt“ (EN: "Help & contact"); under the small heading „Rechtliches“ (EN: "Legal") the rows „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") and „Lizenzen“ (EN: "Licenses"); then „Abmelden“ (EN: "Sign out") on its own, looking like any other row, and the app version at the bottom. Categories and stores are under the list's „Anpassen“. „Nutzungsdaten“ opens a page with just the usage-data switch. Help, imprint and privacy policy open pages on snacklist.app in the browser; the terms open Apple's standard terms on iPhone and, until Snacklist has its own, the help page elsewhere. The imprint is two taps from the list: „Mehr“, then „Impressum“.

**How to get there.**
1. Tap „Mehr“ (EN: "More") in the pill at the bottom (on wide screens: the rail on the left).
2. Pick an entry, e.g. „Hilfe & Kontakt“ (EN: "Help & contact"), „Nutzungsdaten“ (EN: "Usage data"), „Abmelden“ (EN: "Sign out").
3. Imprint, privacy policy, terms and licenses: scroll to „Rechtliches“ (EN: "Legal") and tap „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") or „Lizenzen“ (EN: "Licenses").
4. Help page on the web: snacklist.app/support (EN: snacklist.app/en/support), with support@snacklist.app and answers to common questions.
5. Guides on snacklist.app: Siri Shortcut in German (the English page says it is German-only for now), Alexa skill in German and English („Snacklist per Alexa: Skill einrichten“, EN "Snacklist with Alexa: set up the skill"), and „Snacklist mit Claude verbinden“ (EN "Connect Snacklist to Claude"), in German and English. The app itself links no guide.

**Never claim.**
- A guides section inside the app, a help chat or an in-app browser.
- That the Siri guide exists in English beyond the German-only notice.
- A sign-out from anywhere but More.
- That signing out is marked as a warning or a dangerous step: it looks like any other row.
- An update notice in More: the app does not check for updates yet.
- That archived households can be seen or reopened under More: the app does not show that row.
- That „Rechtliches“ is a page of its own: its entries are rows on More.
- Terms of use of Snacklist's own: the terms row shows Apple's standard terms on iPhone and the help page elsewhere.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): every row in order: Konto, the household's name, Partner einladen, Anderem Haushalt beitreten, Zugänge, Einstellungen, Nutzungsdaten, Tipps, Feedback senden, Hilfe & Kontakt, Rechtliches (Impressum, Datenschutzerklärung, Nutzungsbedingungen (EULA), Lizenzen), Abmelden. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): every row in order: Konto, the household's name, Partner einladen, Anderem Haushalt beitreten, Zugänge, Einstellungen, Nutzungsdaten, Tipps, Feedback senden, Hilfe & Kontakt, Rechtliches with its four rows, Abmelden. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): every row in order with „Abmelden“ last and the version; „Hilfe & Kontakt“ opens snacklist.app/support; Nutzungsdaten. The help page's questions from the locally built site. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): every row in order, „Abmelden“ last in the plain row style, the version, Nutzungsdaten, the tab pill. Recipe: [more-help.md](./more-help.md).

## Rating Snacklist in the store

**What it does.** In the iPhone and Android apps, More has the row „Snacklist bewerten“ (EN: "Rate Snacklist"). It opens Snacklist's page in the App Store or on Google Play, where people can leave a rating. Once Snacklist is in the public stores, the app may also ask for a rating with the phone's own rating window: only right after a shopping trip is finished (every item of a list with at least three items ticked off), after a few quiet seconds, and only for people who have used Snacklist for at least a week, on several days, without trouble (no failed sync, no error) lately. It asks at most a few times a year, never twice in four months. Snacklist asks no question of its own first and shows no extra text.

**How to get there.**
1. Tap „Mehr“ (EN: "More").
2. Tap „Snacklist bewerten“ (EN: "Rate Snacklist").

**Never claim.**
- That Snacklist asks "Do you like Snacklist?" or offers anything for a rating.
- That the rating window appears at a set time or for everyone: the phone decides whether to show it.
- The rating window in the beta (TestFlight, Google Play testing) or in the browser: it does not appear there.
- The rate row in the browser version: it is in the iPhone and Android apps only.

**Unverified.** The rating window on a real phone (no device on the runner); the store page opening on a real phone.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `drive.sh rate-snacklist`: no rate row in the browser, one trip counted, offline rules. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `drive.sh rate-snacklist`: no rate row in the browser, one trip counted, offline rules. Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `drive.sh rate-snacklist`: no rate row in the browser, a whole list ticked off counts one trip and asks nothing, putting one back and ticking it again stays one trip, 10 s offline is no failure and 70 s is. The row and the system dialog in the phone apps: unverified on a device. Earlier: the rating change before it landed, 2026-11-06 (CET): driven on the web build (verify-snacklist, `drive.sh rate-snacklist`): no rate row in the browser, a whole list ticked off counts one trip on the device and asks nothing, an undo and re-tick stays one trip, 10 s offline is no failure and 70 s is; the row in the iPhone/Android layout, DE and EN, from widget tests and goldens; the rules from unit tests. Recipe: [rate-snacklist.md](./rate-snacklist.md).

## Account: data export and deletion

**What it does.** The Konto page shows the signed-in email address with a copy button („Kopiert“, EN "Copied"). Every user can download a copy of their data as a JSON file and delete their account for good. Before deleting, the app says what happens to each of the user's households: one stays for the others (the user's items remain, without their name), or, where the user is the last member, it is deleted with its list, history, categories and stores. The last member of a household with Snacklist Premium (bought for life, yearly, or a free unlock in the beta or for testers) is told first that Premium ends with the household and is not refunded automatically, with a link to ask Apple or Google for a refund, and ticks a box before deleting. If the user owned a household that stays, ownership passes to another member (the app does not say so). The user confirms by typing a word. Single data can also be removed without deleting the account: an item from the list (with a screen reader's „Löschen“ action; a tap only ticks it off into „Zuletzt verwendet“), an access token or connected app on Zugänge, and usage data by switching it off.

**How to get there.**
1. Open „Mehr“ (EN: "More").
2. Tap „Konto“ (EN: "Account"), the first row.
3. Tap „Meine Daten exportieren“ (EN: "Export my data") for the copy, or „Konto löschen“ (EN: "Delete account"), type LÖSCHEN (EN: DELETE) and tap „Endgültig löschen“ (EN: "Delete for good").
4. Without the app: app.snacklist.app/konto-loeschen.html explains all steps; single data is at app.snacklist.app/konto-loeschen.html#einzelne-daten under „Einzelne Daten löschen, ohne das Konto zu löschen“.

**Never claim.**
- History entries or „Zuletzt verwendet“ entries can be deleted one by one in the app (they cannot; history goes with the household, single entries on request by email to support@snacklist.app).
- Deletion can be undone, or happens later (it is immediate and final).
- Backups or logs vanish at once (backups are kept up to 90 days, logs 1 day, per the deletion page).
- That deleting the account archives the household or keeps Snacklist Premium: the last member's household goes with its Premium (also a tester's gift), and households the user archived go too. Premium is not refunded automatically; the app warns about this. That Premium can be kept by archiving the household: it cannot.

**Unverified.** Apple sign-in revocation on iPhone (no iOS surface to test).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/account-deletion.mjs`: no Premium warning in a shared household; the warning with its tick box for the last member of a household with a free unlock. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/account-deletion.mjs`: the email copy button; no Premium warning in a shared household; the warning and tick box for the last member with a free unlock (nothing deleted). Earlier: main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `journeys/account-deletion.mjs`: the email copy button. main 6c93da99, 2026-11-08 (CET): no Premium warning in a shared household; the Premium warning and tick box for the last member with a free unlock (nothing deleted). Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist), `journeys/account-deletion.mjs`: the email copy button; the Premium warning for the last member with a free unlock, none in a shared household (nothing deleted). Recipe: [account-deletion.md](./account-deletion.md).

# Connections and Premium

## AI assistants (MCP) and access tokens

**What it does.** An AI assistant that supports MCP can read the shopping list, add items, tick them off and move them to another category or store. The user connects it by signing in when the assistant asks (a page „Zugriff erlauben?“ with „Erlauben“ and „Ablehnen“) or with an access token („Zugriffstoken“, EN: "Access tokens") made in the app, which is shown once. After „Erlauben“ the page shows „Verbunden“ and „Fertig, du kannst zu <Assistent> zurückkehren.“ with the assistant's own name (EN: "Connected", "Done, you can return to <assistant>.") while the assistant finishes connecting (this can take about 10 seconds). Asked what's on the list, the assistant also gets how many items are open on the whole list and how many were ticked in the last 24 hours. An amount written before or after the item, like „2 Gurken“ or „Gurken 3“, becomes the amount; numbers that belong to the name stay in it („Windeln Größe 4“, „Büroklammern 100“). In the app the user sees the address, the tokens and the connected assistants, and can revoke or disconnect any of them at once. Each connected assistant shows where it was approved, like „Chrome · macOS“, when it was connected and when it was last active; a tap on it explains in plain words what it may do, with the button to disconnect it. A short text under „Zugriffstoken“ says that a token lets you build your own automations that manage the list. Someone in several households sees one more line naming the household a new token works in: the one open in the app („Ein neuer Token gilt für „Zuhause“, den Haushalt, der gerade offen ist.“, EN "A new token works in “Zuhause”, the household open now."). An assistant signed in with the user's account can list all their households and work in any of them by name. Assistants on the newest version of the assistant protocol (MCP 2026-07-28) connect the same way and need no setup either: the consent page shows the name the assistant publishes for itself. Nothing needs Premium today. Setup guide: snacklist.app/de/anleitungen/claude (EN /en/guides/claude).

**How to get there.**
1. Open „Mehr“ (EN: "More") and tap „Zugänge“ (EN: "Access").
2. Copy the server address under „MCP-Server“ (EN: "MCP server"): https://mcp.snacklist.app.
3. In the assistant, add a connector with that address and sign in, or tap „Token erstellen“ (EN: "Create token"), name it and copy the token once („Kopieren“).
4. To end access: the bin icon „<Name> widerrufen“ (EN: "Revoke <name>") then „Widerrufen“, or „<App> trennen“ (EN: "Disconnect <app>") then „Trennen“.

**Never claim.**
- That it needs Premium today. It doesn't. Once Peter turns the integration lock on (hold `integration-lock` in releases/flags.json), every tool tells a household without Premium „Dieser Haushalt braucht Snacklist Premium für den Zugang über KI-Assistenten …“; the Claude guides say so only from then (`::: once integration-lock`).
- That the assistant sees more than the list (it reads and changes shopping items, categories and stores only).
- That a key can be viewed again after creation (shown once).
- That Snacklist knows where an assistant is used or tracks its location: it only keeps the browser and system name of the page where the user approved it (gone once disconnected); „Zuletzt aktiv“ is the day the assistant last signed in or refreshed its sign-in, not of every request.
- That ended keys are deleted at once (the record stays 30 days, then a daily clean-up deletes it; the key itself stops working immediately).
- Any specific assistant as officially supported or tested. The app's MCP help text on Zugänge names two assistants as examples; copy names none (see "Never claim (everywhere)").
- That the well-known assistants already use the newest protocol version with Snacklist (today they connect the established way; both ways lead to the same consent page).

**Unverified.** The assistants' own connector screens.

**For assistants finding Snacklist on the web.** snacklist.app has https://snacklist.app/llms.txt, a list for AI assistants of every guide, help and legal page with the MCP server's address, and every page also as plain Markdown at its address plus `.md` (for example https://snacklist.app/en/guides/claude.md). Never claim the site is in search engines yet: it is hidden from them until launch.

**The address in a browser.** Someone who opens https://mcp.snacklist.app in a browser gets a short page in German or English (by the browser's language): „Hier sprechen KI-Assistenten mit deiner Snacklist.“ (EN "This is where AI assistants talk to your Snacklist."), a note that the address is for AI assistants that support MCP, not for the browser, the address with a copy button, and links to the guides and snacklist.app. It names no assistant. Never claim it does anything itself: it only explains the address. Live on mcp.snacklist.app (checked 2026-11-07); assistants still connect at the same address.

**Held: the Snacklist API.** Built but switched off for everyone: the app hides it and the server refuses its keys and requests. When it is on, Zugänge gets a section „API“ with an address, a link „API-Dokumentation“ and the button „API-Schlüssel erstellen“ (EN "Create API key"): the user names the key, picks „Nur lesen“ or „Lesen und schreiben“ (EN "Read only", "Read and write") and copies it once. Scripts and automations then read and change the list over HTTP. Do not announce it until Snacklist Launch says so. Never claim it today, nor a short address like api.snacklist.app (none exists).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): `journeys/ai-assistants.mjs`; on the local stack the MCP server introduces itself as „Snacklist“ and offers eight tools. Job 94 branch, 2026-11-04 (CET), driven on the web build: an assistant on MCP 2026-07-28 signing in with a published client document (Claude's), through the consent page (its name and https://claude.ai) to the connected-app row (`journeys/ai-consent-cimd.mjs`). Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): `journeys/ai-assistants.mjs`: the connected app's row and details. Earlier: Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and tests only, **not driven**: the line naming the household of a new token, households by name in any case, the list of households with a locked default. main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist), `journeys/ai-assistants.mjs`: the connected-app row and its details; a token reading the tools over MCP on the local stack. main 6c93da99, 2026-11-08 (CET): a token adding an item over MCP, and refused when unknown. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): the connected-app row and its details; a token adding an item over MCP on the local stack; https://mcp.snacklist.app in a browser shows the German page, and an assistant's request still reaches the server. Recipe: [ai-assistants.md](./ai-assistants.md).

## Siri

**What it does.** On an iPhone the user can add things to the Snacklist by voice: they say a sentence like „Milch, zwei Gurken und Klopapier“, Snacklist splits it into items, files each under a category and Siri reads back „Hinzugefügt: Milch, 2 Gurken, Klopapier.“ What is open already Siri names instead („Schon auf der Liste: Milch.“). When the user says just „Butter“ and „Butter Weihenstephan“ (a brand) or „Bio Butter“ is open, Siri without setup asks whether to add another Butter; the Shortcut adds nothing and says Butter Weihenstephan is already on the list. Another kind of the item, like „Butter gesalzen“ or „Milch laktosefrei“, is a different product: plain „Butter“ is added. Snacklist never changes or merges the open item. An amount said after the item counts too, as a word or digits: „Möhren zwei“ adds 2 Möhren, „Eier dreißig“ 30 Eier. A product name that starts with a number stays whole: „Drei Glocken Nudeln“ is one item. Today this works with a Shortcut the user sets up once (about five minutes, German only). Siri without any setup (iOS 17 and newer, German and English, also reads the list aloud) is built but its announcement is held until Snacklist Launch.

**How to get there.**
1. Open „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Token erstellen“ (EN: "Create token"), name it Siri, copy the token once.
2. In Apple's Shortcuts app build a shortcut called „Einkaufsliste“ (dictate text, send to Snacklist, speak the answer). The step-by-step guide is on snacklist.app: „Snacklist per Siri: Kurzbefehl einrichten“ (EN: "Snacklist with Siri (German only for now)").
3. Say „Hey Siri, Einkaufsliste“, then the items.

**Never claim.**
- That Siri works without setup as a released feature (held until Snacklist Launch).
- That it works on Apple Watch, AirPods or CarPlay (untested), or Android, or in the browser.
- That English sentences are split correctly through the Shortcut (German only).
- That it needs Premium today, or that it stays free after the public launch. Siri is free for everyone during the beta (testers keep a free unlock) and becomes part of Snacklist Premium after the public launch. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; testers' free unlock: P1, Nov 2.
- That the voice microphone in the app works on the web (iOS and Android apps only).

**Unverified.** Real Siri voice on a device; the Shortcut on current iOS versions. Siri without setup in German: the device tests on build 1119 (3 Nov 2026) sent „Füge … zur Hummliste hinzu“ to Reminders or answered „Hummlist unterstützt das nicht“ (the app was still called Hummlist then). The fix (sentences that name Snacklist first or as the object, like „Etwas auf Snacklist setzen“ and „Snacklist, was steht drauf?“; any item in „Füge Zahnpasta zu Snacklist hinzu“; Siri asks once to be allowed for Snacklist) waits for the next German device test. Never write „Einkaufsliste“ as a Snacklist Siri sentence: Siri gives it to Reminders. Built since, not yet tried on a device: Siri says the name „Snacklist“ and no longer takes a name ending in „Liste“ for it, more German sentences („Füge etwas zu meiner Snacklist hinzu“, „Zeig meine Snacklist“), the household's own words for an item („Möhren“ for „Karotten“), and on an error Siri answers instead of opening the app. The iPhone app needs iOS 17 or newer.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), on the local stack: the Shortcut's requests (an add sentence, „Butter“ with Butter Weihenstephan open, the list read aloud as „Auf der Snacklist stehen …“); Siri without setup: „Füge Milch zur Snackliste hinzu“ is read as Milch, and the English read starts "There are … things on your Snacklist". Earlier: main c3636541, 2026-11-09 (CET), the Shortcut's requests on the local stack: an add sentence, „Butter“ with Butter Weihenstephan open („Schon auf der Liste: Butter Weihenstephan.“, EN too), the not-understood sentence, reading the list. Siri itself needs an iPhone. Earlier: main 8ad168f5, 2026-11-08 (CET), the Shortcut's requests on the local stack: „Butter“ with Butter Weihenstephan open (the reply and the question, DE and EN), reading eleven items. main 6c93da99, 2026-11-08 (CET): an add sentence with „Schon auf der Liste“, the not-understood sentence. Siri itself needs an iPhone. Earlier: main c2ce938f, 2026-11-07 (CET), the Shortcut's requests against the web build's local stack: an add sentence, „Schon auf der Liste“, „Butter“ with Butter Weihenstephan open (the reply and the question, DE and EN), the not-understood sentence. Siri itself needs an iPhone. Recipe: [siri.md](./siri.md).

## Home Screen widget (held)

**What it does.** On iPhone and Android the user can put Snacklist on the Home Screen as a widget. It shows how many items are still open („3 offen“, EN "3 open") and the next ones with their quantity, then „+2 weitere“ (EN "+2 more") if more are open. The medium size adds the store's name and a „Hinzufügen“ (EN "Add") button, also when everything is done („Alles erledigt“, EN "All done"). A tap on the widget opens the list; Add opens the list with the input ready. Without internet it shows the last list the app saw. Built, but its announcement is held until it has been tested on an iPhone and an Android phone.

**How to get there.**
1. iPhone: touch and hold an empty spot on the Home Screen, „Bearbeiten“ (EN "Edit") → „Widget hinzufügen“ (EN "Add Widget") → Snacklist, pick small or medium.
2. Android: touch and hold an empty spot → „Widgets“ → Snacklist, drag it out; four columns wide shows the Add button.
3. Guides (drafts until the hold ends): „Snacklist auf dem Home-Bildschirm: das Widget“ (EN "Snacklist on your Home Screen: the widget").

**Never claim.**
- That it is released (held until a device test).
- That you can tick items off in the widget (you open the app for that).
- That a partner's adds show in the widget the moment they happen (they show once Snacklist was open on your phone again).
- That it follows the app's own light/dark choice (it follows the phone's).
- That it works on the web, Apple Watch, the Lock Screen or StandBy.
- That it needs Premium (it does not).

**Unverified.** Everything on a real device: the look in light and dark, both sizes, the taps.

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and the app's 22 widget tests (passed). Earlier: main c3636541, 2026-11-09 (CET), from code and the app's 22 widget tests (passed). The widget on a phone: unverified. Earlier: main 6c93da99, 2026-11-08 (CET), from code and the app's 22 widget tests (passed). The widget on a phone: unverified. Earlier: main c2ce938f, 2026-11-07 (CET), from code and the app's 22 widget tests (passed). The widget on a phone: unverified. Recipe: [home-widgets.md](./home-widgets.md).

## Alexa skill (beta)

**What it does.** With the Snacklist skill a household member can say „Alexa, sag Snacklist, füg Milch und Eier hinzu“; the items land on the shared list, sorted by category, and Alexa says „Ich habe Milch und Eier auf die Snacklist gesetzt.“ What is open already it names in one sentence: „Schon auf der Snacklist: Milch.“ Saying just „Butter“ while „Butter Weihenstephan“ (a brand) or „Bio Butter“ is open, Alexa asks whether to add another Butter; yes adds it, no adds nothing. With „Butter gesalzen“ open, plain „Butter“ is simply added. An amount said after the item counts too: „Zwiebeln drei“ adds 3 Zwiebeln. A product name that starts with a number stays whole: „Drei Glocken Nudeln“ is one item. „Alexa, frag Snacklist, was auf der Liste steht“ reads the open items (up to ten, then „und N weitere“; with eleven it reads all eleven). On an Alexa device set to English it understands "Alexa, ask Snacklist to add milk and eggs" and "Alexa, ask Snacklist what's on the list" and answers in English ("I put milk and eggs on Snacklist."). The skill is in beta and not yet certified by Amazon, so it is not for everyone.

Since S4 (2026-11-10) the skill is called Snacklist, with the invocation „snacklist“; the old Hummlist skill (invocation „humm list“) keeps answering for its testers until R1.

**How to get there.**
1. Ask for a beta invitation (the link comes from Peter, who needs the email address of your Amazon account); accept it.
2. In the Alexa app open the skill „Snacklist“ and tap „Zur Verwendung aktivieren“.
3. Sign in to Snacklist and tap „Erlauben“ on the page „Zugriff erlauben?“ (it names „Amazon Alexa“). The page then says „Verbunden“ (EN "Connected") until the Alexa app takes over.
4. Say „Alexa, sag Snacklist, …“ (EN: "Alexa, ask Snacklist to …", "Alexa, tell Snacklist …", "Alexa, open Snacklist") (for example „… ich brauche Milch“, „… füge Milch hinzu“, „… setz Milch drauf“), „Alexa, frag Snacklist, …“ or „Alexa, öffne Snacklist“. If Alexa mishears the name, say „Alexa, öffne Snacklist“ first, then the items. To end it: Snacklist → „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Amazon Alexa trennen“ (EN: "Disconnect Amazon Alexa") → „Trennen“, or disable the skill in the Alexa app. Disabling the skill also removes „Amazon Alexa“ from Zugänge. A connection nobody used for 12 months is removed, Zugänge entry included.

**Never claim.**
- That the skill is certified, in the public Alexa Skill Store, or available to everyone.
- That it speaks any language besides German and English, or that everyone can find it in the Skill Store (it is listed for every country only once certified).
- That it needs Premium (it is free, also after Premium launches). Source: Peter Q39 AP1, Nov 2; docs/PAYWALL_RELEASE.md.
- That it works for ticking items off or moving them (add and read only).
- That „Alexa, setz Milch auf die Snacklist“ (EN "Alexa, add milk to Snacklist") works: without „sag/frag/öffne Snacklist“ ("ask/tell/open Snacklist") Alexa's own lists take the sentence.
- Exact deletion periods beyond what the privacy policy says (its wording waits for Peter's approval).

**Unverified.** Real Alexa voice, the Alexa app screens and the beta invitation flow (no device or Amazon account here).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), the skill's server side on the local stack: opening it without a linked account (DE and EN), unsigned and stale requests refused. Earlier: main c3636541, 2026-11-09 (CET), the skill's server side on the local stack: opening it without a linked account (DE and EN), unsigned and stale requests refused; the Alexa and voice unit tests pass (449). Earlier: main 8ad168f5, 2026-11-08 (CET), the skill's server side on the local stack: opening it without a linked account, requests not signed by Amazon refused. main 6c93da99, 2026-11-08 (CET): the same in English and a stale request refused; the skill's 440 unit tests with the voice ones pass (a mixed add says „Ich habe … auf die Snacklist gesetzt. Schon auf der Snacklist: …“). Earlier: main c2ce938f, 2026-11-07 (CET), the skill's server side on a local test setup: opening the skill without a linked account (DE and EN), requests not from Amazon refused. Recipe: [alexa.md](./alexa.md).

## Snacklist Premium (held)

**What it does.** Premium is not on sale yet and nothing in the app is gated by it: Siri, Alexa and AI assistants work for everyone. After the public launch Siri and AI assistants become part of Premium; the Alexa skill stays free. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2. The app has a „Snacklist Premium“ page about the household: „Snacklist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.“ (EN: "Snacklist Premium covers your whole household, including everyone who joins later."), „KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden“ (EN: "Connect AI assistants that support MCP to your list"). Once native Siri is released, the iPhone app lists „Per Siri auf die Liste, ohne die App zu öffnen“ (EN: "Add to the list with Siri, without opening the app") above that line, and once the Snacklist API is released, „Eigene Automationen mit der Snacklist API“ (EN: "Your own automations with the Snacklist API") below it; both are hidden today. Today it shows nothing else: no slogan, no prices, no buy buttons, no „bald verfügbar“, no note about buying in the apps, no refund link. Never name an assistant brand for Premium (Legal Review N-67). Beta households with a free unlock see „In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet“ (EN: "Free in the beta, until Snacklist Premium launches") with „Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid.“ (EN: "You pay nothing, and nothing renews automatically. We'll let you know at least 4 weeks before the free unlock ends.") and a link „Mehr dazu in der Datenschutzerklärung“ (EN: "More in the privacy policy"); these are Legal Review's approved texts. Testers and app review see „Kostenlos freigeschaltet (Test und App-Prüfung)“ (EN: "Unlocked free of charge (testing and app review)") instead. They also see the row „Snacklist Premium“ in Mehr.

**How to get there.** Not from Mehr before the launch: the row „Snacklist Premium“ shows only for households that have Premium (a free unlock in the beta or for testers). The page opens from its link.

**Note.** The privacy policy explains the free unlock in the section „Snacklist Premium in der Beta“ (snacklist.app/datenschutz#premium-beta): testers and Apple's and Google's app review get Premium for free until the team ends it, and it never turns into a paid purchase.

**Never claim.**
- That Premium can be bought, or any price, plan or discount (yearly and Lifetime are planned, not for sale).
- That Siri, Alexa or AI assistants need Premium today (they do not), that Siri or AI assistants stay free after the public launch (they become part of Premium), or that Alexa ever needs it (the skill stays free). Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2.
- That Google Assistant or Apple Watch exist or are coming.
- That there is a free trial.
- That Mehr shows Snacklist Premium to everyone (it does once Premium is on sale).

**When it goes on sale.** Nothing changes for users until Peter's go; the switches and their order are in `docs/PAYWALL_RELEASE.md`. Write launch copy from `docs/PURCHASES.md`, not from this section.

**Unverified.** Real store purchases (no store sandbox here); whether the analytics event for the paywall ever fires in production (it should not).

**Last verified.** main 1f8e5edb, 2026-11-10 (CET), from code and driven on the web build (verify-snacklist): no row without Premium; a beta unlock shows „In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet“ and the link „Mehr dazu in der Datenschutzerklärung“ to snacklist.app/datenschutz#premium-beta. Earlier: main c3636541, 2026-11-09 (CET), from code and driven on the web build (verify-snacklist): no row without Premium; a gifted household's row and „Kostenlos freigeschaltet (Test und App-Prüfung)“ for an unlock to 2100. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-snacklist): no row without Premium; a gifted household's row with „Kostenlos freigeschaltet (Test und App-Prüfung)“ for an unlock to 2100 and „In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet“ for a 60-day unlock; the row gone once it ended. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-snacklist): no row without Premium; a gifted household's row, „Kostenlos freigeschaltet (Test und App-Prüfung)“ for an unlock without end and „In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet“ for a beta unlock, with no buy note. Recipe: [premium.md](./premium.md).
