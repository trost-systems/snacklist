# Hummlist features for writers

What Hummlist does today, in plain words, with the exact button and screen labels in German and English. Hummlist Launch and anyone writing emails, site copy or instructions reads this file. The verification recipes behind it are the other files in this folder.

## How to use this

- Describe only what a section says the app does. If it is not here, ask before you write it.
- Copy labels exactly, with their quotes and punctuation: German „…“, English "…". The app shows German or English depending on the phone's language, or on Mehr → Einstellungen → Sprache.
- Check each section's **Never claim** list and the global list below before you send anything.
- **Unverified** means nobody could prove it from the code or a test run. Leave it out, or ask.
- Each section ends with the commit and date it was last checked. If the app changed after that date, the section can be out of date.
- Short clips (GIF for emails, MP4/WebM for the site, PNG fallback) live in `/workspace/hummlist/clips/<feature>/` on the box, for example `quick-add/de.gif`. Each `meta.json` names the commit and the alt text. To make a new one, see `.cursor/skills/hummlist-howto-clips/SKILL.md`. Always give the GIF its alt text and link the PNG as a fallback.

## Never claim (everywhere)

- That Hummlist Premium can be bought, or any price, plan, trial or discount. Premium is not on sale and nothing is locked behind it today.
- That Siri, Alexa or AI assistants need Premium today. They don't: nothing is locked during the beta. After the public launch Siri and AI assistants become part of Hummlist Premium; the Alexa skill stays free for good. Never write that Siri stays free after the launch. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2.
- Siri without setup ("just say Hey Siri", no Shortcut) as available. It is built, but its announcement waits for Hummlist Launch. Today Siri works through a Shortcut the user sets up once, in German.
- That the Alexa skill is launched, certified or in the Alexa Skill Store. It is a beta by invitation, in German and English.
- Store logos or chain colours, official store layouts, prices, offers or opening hours. Store names are plain names; walking orders are researched defaults.
- A code to type from an email for sign-in. Sign-in emails contain a link, and the only code in Hummlist is the 8-character household invite code.
- The Home Screen widget as available. It is built for iPhone and Android, but its announcement waits for a device test (see „Home Screen widget (held)“).
- Apple Watch, Google Assistant, Android voice assistants, push notifications, recipes, meal plans or price tracking. None exist.
- That the microphone (dictation) works in the browser. It is in the iPhone and Android apps only.
- Real people's names or lists. Clips and screenshots use the fictional Brandt family.
- AI products or their makers (ChatGPT, OpenAI, Claude, Anthropic) as examples, claims or praise. Write „KI-Assistenten, die MCP unterstützen“ / "AI assistants that support MCP". Only setup instructions (the Claude guide, the app's MCP help text) and the trademark notice in the imprint name them (Legal N-79 to N-86; `scripts/brand-names.ts` fails the lint gate on the site and the ARB files).
- Alexa as „sie“ / "she". Name the skill „Hummlist-Skill für Amazon Alexa“ / "Hummlist skill for Amazon Alexa" (Legal N-84).
- Anything the sections below mark as held (Premium, native Siri, the Alexa skill's certification, the Home Screen widget, Premium-only connections).

# Getting started

## hummlist.com waitlist

**What it does.** hummlist.com keeps its landing page, but its buttons say „Auf die Warteliste“ (EN: "Join the waitlist") instead of opening the browser version. They lead to a short form: the email (ideally the one of the Apple ID or Google account) and iPhone or Android. Hummlist then sends a confirmation mail; the person is on the list only after tapping „E-Mail bestätigen“ in it and agreeing on the page that opens, where they can also tick that they want one email when the app launches. An AI assistant may fill in the form for someone, but only the person's own click on that page counts. Confirmed people are invited to the beta in weekly groups, by hand. Every mail has a link that deletes the entry at once. The hero badge says „Beta im November“ (EN: "Beta in November"), and above the form a short note „Von Peter“ (EN: "From Peter") says why he builds Hummlist: one list he shares with his wife, which AI assistants can add to, tick off and read through MCP; in the beta people test it with them and say what's missing. Later stages are built but off: „Zur Beta anmelden“ (EN: "Join the beta"), and at launch App Store and Google Play badges with a QR code; the badge and the note leave at launch.

**On the landing page.** Besides the waitlist, the page shows how the app works. The stores card has three buttons under „Tippe auf einen Laden:“ (EN: "Tap a store:"): „Drogerie“, „Getränkemarkt“ and „Supermarkt“ (EN: "Drugstore", "Drinks store", "Supermarket"). A tap re-orders the first five category stops below to that kind of store's route, using the app's own category names. Four short silent videos show the real app: typing two items and ticking them off, three phones of one family staying in sync, adding by voice („Pizza, Orangensaft und zwei Packungen Fischstäbchen“), and an AI chat putting items on the list and ticking them off. Each video has a written description.

**How to get there.**
1. hummlist.com (opens /de or /en by browser language).
2. „Auf die Warteliste“ (EN: "Join the waitlist"), in the header or the hero.
3. In the mail: „E-Mail bestätigen“ (EN: "Confirm email"), then the button on the page.

**Never claim.**
- That signing up works, or that anyone has been invited, until Peter confirms it. The page is on hummlist.com, but sign-ups depend on server settings that are not confirmed here.
- A beta date more exact than the badge's month („Beta im November“), a place in line, a referral reward, a counter, or a date for a particular person's invite.
- That the browser version is open to new users, or that an assistant can sign someone up without their confirmation.
- That launch news can be chosen in the form (only on the confirmation page).

**Last verified.** main 6c93da99, 2026-11-08 (CET), the site built locally: its 170 tests pass; the landing page has the badge „Beta im November“ and „Auf die Warteliste“; the help page answers both Hummlist Lifetime questions. The form itself was not re-run. Earlier: main c2ce938f, 2026-11-07 (CET), on the locally built site: the badge, the founder note and „Auf die Warteliste“, the stores card's three buttons re-ordering the stops, the four silent videos and their descriptions (DE and EN). The form itself was not re-run. The support and privacy pages built from the 7 Nov texts. Recipe: [waitlist.md](./waitlist.md).

## Sign-up and sign-in

**What it does.** A new or returning user signs in with Google or Apple, or with email: email and password, a new account with „Registrieren“ (EN: "Sign up"), or a sign-in link by email opened on the same device. Google and Apple come first; email is one more button below them, „Weiter mit E-Mail“ (EN: "Continue with email"). The keyboard opens only when the user taps a field. Signing out is in the More tab. The login screen links the imprint and the privacy policy. Right after deleting the account, the login screen confirms „Dein Konto wurde gelöscht.“ (EN: "Your account was deleted.").

**How to get there.**
1. Open Hummlist while signed out: the login screen appears. It opens on the Hummlist logo and name and has no title.
2. Tap „Mit Google anmelden“ / „Mit Apple anmelden“ (EN: "Sign in with Google" / "Sign in with Apple").
3. Or tap „Weiter mit E-Mail“ (EN: "Continue with email"), enter email and password, then tap „Anmelden“ (EN: "Sign in"), or „Registrieren“ (EN: "Sign up") for a new account.
4. Or, after „Weiter mit E-Mail“, enter only the email and tap „Anmeldelink per E-Mail senden“ (EN: "Email me a sign-in link"), then open the link from the email on the same device.
5. To sign out: tab „Mehr“ (EN: "More"), then „Abmelden“ (EN: "Sign out").

**Never claim.**
- A code that users type in from an email: the app has no such field. Sign-in emails carry a link.
- "8-digit code" for sign-in. Sign-in emails contain a link, not a code. The only 8-character code in Hummlist is the household invite code (letters and digits).
- That the emails are in German or come from a "Hummlist" template: today they are short English emails ("Your sign-in link", "Confirm your email address").
- Passkeys, phone-number sign-in or other providers than Google and Apple.
- That users need an email and password account: Google or Apple is enough.
- A "Forgot password" button or password reset in the app: there is none. Someone who forgot the password uses „Anmeldelink per E-Mail senden“ (EN: "Email me a sign-in link").

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): a signed-out link to „Einladungen“ goes to the login screen, „Weiter mit E-Mail“, sign-up. main 8ad168f5, 2026-11-08 (CET): „Abmelden“ from the last row of Mehr ends on the login screen. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): the login screen with Google, Apple and „Weiter mit E-Mail“, the email form's checks, sign-up, sign-out from the last row of Mehr. Recipe: [sign-in.md](./sign-in.md).

## Usage-data question (analytics consent)

**What it does.** Right after the first sign-in on a device, Hummlist asks once whether it may collect usage data. A no sends nothing to PostHog; Hummlist only notes the no with the account, so voice events stay off too. A yes sends pseudonymous usage data and error reports to PostHog on servers in the EU. Both answers are equally prominent, and the user can change the answer any time under More → Nutzungsdaten. Anyone who said yes to an earlier wording of the question is asked again with the current, shorter text, and nothing is sent until they answer. A no stays a no.

**How to get there.**
1. Sign in for the first time on a device: the question „Darf Hummlist Nutzungsdaten erfassen?“ (EN: "May Hummlist collect usage data?") appears.
2. Answer „Erlauben“ (EN: "Allow") or „Nicht erlauben“ (EN: "Don't allow").
3. To change it later: tab „Mehr“ (EN: "More"), „Nutzungsdaten“ (EN: "Usage data"), the switch „Nutzungsdaten und Fehlerberichte senden“ (EN: "Send usage data and error reports").

**Never claim.**
- That list contents, names or email addresses are collected: the text says they are never sent.
- That a no limits any feature: the app works the same.
- That Hummlist uses advertising or sells data: nothing in the app says so.
- Quote the legal text exactly; do not paraphrase it. Point to the privacy policy for details.

**Note.** Every released app and app.hummlist.com ask this question (checked 2026-11-01).

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): the question after sign-up, „Nicht erlauben“, the switch under Mehr → Nutzungsdaten (off). Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): the question after sign-up with its privacy link, „Nicht erlauben“, the switch under Mehr → Nutzungsdaten. Recipe: [privacy-consent.md](./privacy-consent.md).

## Getting started: first sign-in to the list

**What it does.** After the first sign-in, a new user creates a household or accepts an invite. Creating asks for a household name (prefilled „Unser Haushalt“, EN: "Our household") and which stores you shop at: pick from eleven common ones (EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann and a „Baumarkt“) and add your own, or skip and add them later. Then Hummlist offers to invite the partner and opens the shopping list. Someone who opens an invite link goes straight to joining.

**How to get there.**
1. Sign up or sign in. If the app asks about usage data, answer it.
2. On „Willkommen bei Hummlist“ (EN: "Welcome to Hummlist") tap „Haushalt erstellen“ (EN: "Create a household") or „Einladung annehmen“ (EN: "Join with an invite").
3. Creating: choose the name, tap the stores you shop at (or „Eigenen Laden hinzufügen“, EN: "Add your own store", and type a name such as „Wochenmarkt“; typing one of the eleven, „edeka“ say, ticks it), then „Haushalt erstellen“ (EN: "Create a household"); „Überspringen“ (EN: "Skip") starts without stores.
4. Next screen „Partner einladen“ (EN: "Invite your partner"): make an invite or tap „Später“ (EN: "Later") to go to the list.

**Never claim.**
- A tour, a tutorial or a newsletter or email opt-in in the app: there is none.
- That any store is pre-installed, recommended or a partner: nothing is picked until you pick it, and the shops have nothing to do with Hummlist.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): a new account offered eleven store chips with „Baumarkt“ last; REWE plus typed „edeka“ ticked the one EDEKA; the invite step, „Später“ to the list; with a link waiting, the link's screen instead of the invite step. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): a new account offered eleven store chips with „Baumarkt“ last, creating a household with REWE and typed „edeka“ (one EDEKA), the invite step, „Später“ to the list. Recipe: [onboarding.md](./onboarding.md).

## Household and invites

**What it does.** One household shares one shopping list, and one person can be in several households, for example at home and with their parents (up to 10). The household's name sits top left of the list; a tap shows all your households and switches between them. A member invites a partner with an 8-character code and a link; each invite is valid for 7 days and works for one person. The partner types the code or opens the link and joins; their other households stay. A code or link of a household you are already in simply opens that household. A member can revoke open invites at any time. Each household has a page to rename it, see its members, make it the default for Siri, Alexa & AI, and leave it.

**How to get there.**
1. Switch: tap the household's name top left of the list. „Deine Haushalte“ (EN: "Your households") lists them with members and open items; tap one. „Neuer Haushalt“ (EN: "New household") creates one more, „Mit Code beitreten“ (EN: "Join with a code") joins one.
2. Invite: tab „Mehr“ (EN: "More"), row „Partner einladen“ (EN: "Invite your partner"), then „Neue Einladung“ (EN: "New invite"). In the iPhone and Android apps the share sheet opens right away. Otherwise share it with „Teilen“ (EN: "Share") where the browser offers it, or copy it with „Link kopieren“ / „Code kopieren“ (EN: "Copy link" / "Copy code").
3. To join: „Anderem Haushalt beitreten“ (EN: "Join another household") in „Mehr“, enter the code, „Weiter“ (EN: "Continue"), then „Haushalt beitreten“ (EN: "Join household"). Or open the invite link.
4. The household page: tab „Mehr“, the row with the household's name. „Umbenennen“ (EN: "Rename"), „Mitglieder“ (EN: "Members"), „Als Standard nutzen“ (EN: "Make default"), „Haushalt verlassen“ (EN: "Leave household").
5. To revoke: on the invites page tap „Widerrufen“ (EN: "Revoke") on an invite.

**Never claim.**
- Removing a member or member roles: they don't exist yet.
- That Siri, Alexa or an AI assistant follows the household shown in the app: they use the default household („Siri, Alexa & KI nutzen: …“).
- An archive for households: it is off in the released apps.
- Invites that stay valid longer than 7 days or work for several people.
- Purchases or Premium tied to joining: Premium is not on sale yet. Premium belongs to one household, not to the person.

**Last verified.** Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven** (a link of an own household opens it; the leave dialog reads the members when it opens). Branch job/169b-app (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven** (switcher, household page, joining without leaving). Unverified until driven on the web build. Before: main 8ad168f5, 2026-11-08 (CET), driven on the web build (verify-hummlist): a new invite with its code, revoking it. Recipe: [household-invites.md](./household-invites.md).

## Links into the app

**What it does.** In the web app at app.hummlist.com and in the test apps from 6 Nov on (see the first Never-claim below), a link to app.hummlist.com opens that screen of Hummlist: in the iPhone or Android app when it is installed, otherwise in the browser. A link can open the list, the add field, one store's part of the list, the More tab and its pages (for example „Einladungen“ / "Invites" or „Einstellungen“ / "Settings"), or an invite. Someone who is signed out signs in first and then lands on the linked screen; a new account sets up its household first.

**Links to use.**
- The list: `https://app.hummlist.com/list`
- Add something: `https://app.hummlist.com/add` (opens the add field, ready to type)
- Invite your partner: `https://app.hummlist.com/more/invites`
- Settings (theme, language): `https://app.hummlist.com/more/settings`
- The More tab: `https://app.hummlist.com/more`
- A store's part of the list: `https://app.hummlist.com/stores/<id>`. The id belongs to one household, so this link only works for its members; don't put it in emails to everyone.

**Never claim.**
- That these links (other than invite links) open the phone apps for everyone. Only the test apps from 6 Nov on (TestFlight, Google Play internal testing) have them, and that they open the app is not yet checked on a phone. The store apps get them with the first public release. Invite links already work everywhere and open the apps.
- Links that fill in an item ("add Milch") or tick something off: a link only opens a screen.
- That a link keeps working after the app was closed during sign-in on the phone: it then opens the list.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): /add opens the add sheet, /more/invites opens „Einladungen“, unknown paths land on the list, a store link shows that store's section on top; signed out, the link waits through sign-up. Earlier: the change that made store links wait, 2026-11-07 (CET), driven on the web build: a store link opens the list at that store also when this device's saved list is older than the store's items (it waits for the server's first answer; offline it opens the list as it is). Recipe: [app-links.md](./app-links.md).

# The list

## Quick add

**What it does.** The field floating at the bottom of the list, „Was brauchst du?“ (EN: "What do you need?"), is how items get onto the list. As soon as you type or tap it, a sheet opens with suggestions: what you typed, things you bought before, other packs, kinds, sizes and brands, and words from a built-in catalogue; they also find what you meant despite a small typo ("Hafermlch" offers Hafermilch). Enter takes the first suggestion, a tap takes any. Hummlist reads amounts out of what you type, in front or behind, as digits or words, German or English, also without a connection ("2 l Milch", "6x Eier", "zwei Gurken", "Gurken zwei", "two apples", "Karotten 2", "Karotten x2"), and a number that belongs to the item is not taken as an amount ("Windeln Größe 4", "Vitamin D3", "7up", "Drei Glocken Spaghetti"); and picks the category and, where it knows one, the store. After an add the field is empty and ready for the next item, and „Rückgängig“ (EN: "Undo") takes the last add back. On a computer the mouse wheel or trackpad scrolls the list also with the pointer on the field or the tab bar.

**How to get there.**
1. Open Hummlist and stay on the „Liste“ (EN: "List") tab.
2. Type into „Was brauchst du?“ (EN: "What do you need?") or tap anywhere on it.
3. Press Enter for the first suggestion, or tap another row. Before you take a row you can choose a store and a category with the two chips at the top of the sheet. Until you do, they show what Hummlist picked, in grey with a small "A" for automatic (just „Laden“ / "Store" while it knows no store). The store chip also offers „Neuer Laden“ (EN: "New store") to add a store on the spot.
4. Close with the ✕ at the top right („Schließen“, EN: "Close"), Escape, or a tap on the list behind. The sheet stays closed until you tap the field or type again, also when you close it right after an add. Closing while Enter still waits for its suggestions adds nothing.

**Never claim.**
- That suggestions forgive any spelling. They forgive one wrong letter in short words and two in longer ones ("Hafermlch" finds Hafermilch) and find a word from 4 letters inside it ("milch" finds Hafermilch), online and offline alike.
- That the microphone works in the browser (it is on iOS and Android only).
- That the cursor jumps into the field on phones when the app opens (only on desktop and web).
- That an item already on the list can be added twice; Hummlist says „<name> steht schon auf der Liste“ (EN: "<name> is already on the list"). Two people adding the same item at the same moment also end up with one.

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/quick-add.mjs`: a catalogue suggestion tapped and filed under its category. main 6c93da99, 2026-11-08 (CET): the same in English. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): a catalogue suggestion tapped and filed under its category (DE and EN), the field floating over the list with the tab pill below it; the mouse wheel over the field and over the tab pill scrolls the list. Recipe: [quick-add.md](./quick-add.md).

## Due again

**What it does.** Hummlist notices what a household buys regularly. When you open the add bar with nothing typed, items that are probably running out show up as „Wieder fällig“ (EN: "Due again"); one tap puts them on the list with the quantity from last time. An item shows up once it was bought on at least two different days and about its usual time between purchases has passed. Below them come the items used in the last 30 days, marked „Zuletzt verwendet“ (EN: "Recently used"), up to 10 rows in all. The sheet opens small, with three of them; the others scroll.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Tap the bar „Was brauchst du?“ (EN: "What do you need?") without typing.
3. Tap a row marked „Wieder fällig“ (EN: "Due again").

**Never claim.**
- That Hummlist sends reminders or notifications about due items; it only shows them in the add sheet.
- That it works from a single purchase; it needs at least two purchase days.
- That it predicts quantities by season or guesses new items; it only repeats what the household bought.
- That an item stays due until it is bought: it drops out after about four times its usual time between purchases.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): a household with eight weeks of shopping sees eight items „Wieder fällig“; an open „Aepfel“ (another spelling) takes „Äpfel“ off them. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): a household with eight weeks of shopping sees eight items „Wieder fällig“ with the field empty; a tap adds one with „✓ Hinzugefügt“. Recipe: [usuals.md](./usuals.md).

## Dictation

**What it does.** In the iPhone and Android apps, a microphone next to the add bar lets people speak what they need. Hummlist listens in German, on the phone only, so the voice never goes to a server. The words appear as they are spoken, the latest always in view, and, when the person pauses, Hummlist splits the sentence into separate items ("Milch, zwei Gurken und Klopapier") and adds them. An amount said after the item counts too: „Gurken zwei“ adds 2 Gurken. Brand and details are read out as when typing: „Windeln Pampers Größe 3“ adds Windeln with the brand Pampers and the detail Größe 3. A product name that starts with a number stays whole, as when typing: „Drei Glocken Nudeln“ is one item, while „drei Äpfel“ adds 3 Äpfel. It then shows a short message with what it added. One sentence takes up to 30 items; with more, the first 30 are added and the message asks to say the rest again.

**How to get there.**
1. Open the Hummlist app on an iPhone or Android phone, on the „Liste“ (EN: "List") tab.
2. Tap the microphone at the right of „Was brauchst du?“ (EN: "What do you need?") („Diktieren“, EN: "Dictate").
3. Say what you need. Tap the red button („Diktat beenden“, EN: "Stop dictation") to stop early.
4. The first time, allow microphone and speech recognition when the phone asks.

**Never claim.**
- That dictation works in the web app or on a computer; there is no microphone button there.
- That the voice is sent to a server or stored; recognition happens on the device.
- That it understands languages other than German.
- That it works on phones without German offline speech data; the app then asks to download it or to type instead.

**Unverified.** Behaviour on real devices (permission prompts, recognizer) was read from code, not run.

**Shown on hummlist.com.** The landing page's "In der App" / "In the app" card has a video of it: the real app with a scripted recognizer, „Pizza, Orangensaft und zwei Packungen Fischstäbchen“ landing under Getränke and Tiefkühl. The English video shows the same German sentence, because the app listens in German.

**Last verified.** Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and tests only, **not driven**: dictation splits in the household shown. main 6c93da99, 2026-11-08 (CET), the splitter on the local stack: „Drei Glocken Nudeln und drei Äpfel“ gives Drei Glocken Nudeln and 3 Äpfel; „Gurken zwei und Windeln Pampers Größe 3“ gives 2 Gurken and Windeln / Pampers / Größe 3. No microphone on the web build. The microphone itself needs a phone. Earlier: main c2ce938f, 2026-11-07 (CET), the splitter on the local stack: „Drei Glocken Nudeln und drei Äpfel“ gives Drei Glocken Nudeln and 3 Äpfel; „Gurken zwei“ and „Windeln Pampers Größe 3“ split right. The microphone itself needs a phone. Recipe: [dictation.md](./dictation.md).

## Ticking items, "Zuletzt verwendet" and undo

**What it does.** Tapping an item on the list ticks it off: a line strikes through it, the row turns mint and slides away in under half a second, without a message. There is no check box to tap; the whole row is the target. At the bottom of the list, „Zuletzt verwendet“ keeps the last 20 ticked items, each one only once, and leaves out anything that is back on the list; tapping one puts it back where it was. With nothing typed, the add bar also suggests recently used items under the same name, „Zuletzt verwendet“ (EN: "Recently used"). Ticking an item off is how it leaves the list. An item added by mistake can be undone with „Rückgängig“.

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

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/tick-and-undo.mjs`: tick without a message, putting back from „Zuletzt verwendet“. main 6c93da99, 2026-11-08 (CET): the same in English. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist), `journeys/tick-and-undo.mjs`: tick without a message, putting back from „Zuletzt verwendet“ (DE and EN). Recipe: [tick-and-undo.md](./tick-and-undo.md).

## Edit an item

**What it does.** Every item can be changed after it is on the list: its name, brand, details (like "Größe 3" or "1,5 %"), quantity, store and category. The list row shows the quantity in bold in front of the name („6× Bananen“) and the brand and details in small text under the name. The sheet does not delete; to remove an item, tick it off.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Press and hold an item, or right-click it on a computer. (A plain tap ticks the item off instead.)
3. In the sheet „Bearbeiten“ (EN: "Edit") change „Bezeichnung“ (EN: "Name"), „Marke“ (EN: "Brand"), „Menge“ (EN: "Qty") with the buttons „Eins weniger“ / „Eins mehr“ (EN: "One less" / "One more"), or „Eigenschaften“ (EN: "Details"), or pick another store or category with the chips. The store chip also offers „Neuer Laden“ (EN: "New store", the row with a plus) to add a store and pick it. Hummlist remembers the new store or category the next time the item is added.
4. Tap „Fertig“ (EN: "Done") to save, or „Abbrechen“ (EN: "Cancel") next to it to drop every change and close the sheet.
5. Renaming an item to exactly the name of something already on the list (capital letters, spaces, and ae/oe/ue for ä/ö/ü don't matter) does not make a second entry: the two become one. The item already there keeps its name, store and category, the amounts add up, and „Zusammengeführt: <amount> <name>“ (EN: "Merged: …") shows with „Rückgängig“ (EN: "Undo"). This also holds when the rename was made offline or on two phones at the same moment: once the phone is back online, the two become one. If they cannot be combined (the amount would get too long), Hummlist says „<name> steht schon auf der Liste“ (EN: "<name> is already on the list"), keeps the old name and does not save the change.

Each field's name sits above its field; what is typed sits in the middle of the field, left-aligned.

**Never claim.**
- That a swipe deletes or edits an item; a swipe does nothing, a hold opens the edit sheet.
- That the sheet has a delete button; its buttons at the bottom are „Abbrechen“ and „Fertig“. Tick an item off to remove it.
- That Undo after a screen reader's delete always brings back your own quantity: when the item is on the list again by then, the one there stays as it is.
- That items in „Zuletzt verwendet“ (EN: "Recently used") can be edited.
- That the quantity buttons work on free text like "eine Packung"; they only step numbers.
- That holding and dragging moves an item on the list; nothing on the list drags. Holding opens this sheet.
- That renaming to another word for the same thing („Semmeln“ while „Brötchen“ is on the list) or to an item with a brand merges them; Hummlist only points it out („Brötchen steht schon auf der Liste“ with „Zusammenführen“), as when adding.

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/edit-item.mjs`: the sheet with „Abbrechen“ and „Fertig“, a rename onto an open item merging with „Rückgängig“. main 6c93da99, 2026-11-08 (CET): the same in English, and `journeys/hex-surfaces.mjs`. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist), `journeys/edit-item.mjs` and `journeys/hex-surfaces.mjs`: the sheet with „Abbrechen“ and „Fertig“ and no delete, a rename onto an open item merging with „Rückgängig“. Recipe: [edit-item.md](./edit-item.md).

## Tips on the list

**What it does.** Once there is something on the list, a small card at the top shows one tip at a time, for example how to edit an item or that the amount can be typed with the item. The X hides a tip for good on that device; the next one shows from the next app start on. A new, empty list shows no tip, and the first tip waits until the user has tapped „Verstanden“ (EN: "Got it") on the card „Tippen hakt ab · Halten bearbeitet“ (EN: "Tap ticks off · Hold to edit").

**How to get there.**
1. Open Hummlist with at least one item on the list („Liste“, EN: "List").
2. Read the card at the top; tap the X („Tipp ausblenden“, EN: "Hide tip") to hide it.

**Never claim.**
- That tips sync between devices or members (they are per device and user).
- That tips show news or offers today (the two tips are how-tos).

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/tips.mjs`: the first tip, hiding it, the next tip after a reload. main 6c93da99, 2026-11-08 (CET): the same in English. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist), `journeys/tips.mjs`: the first tip, hiding it, the next tip after a reload (DE, EN, dark). Recipe: [tips.md](./tips.md).

## Automatic category (the classifier)

**What it does.** When an item is added, Hummlist sorts it into a category on its own, such as Kühlregal for Hafermilch, using a built-in German word list of about 1,350 terms plus common spelling variants, regional words, some English words and small typos. While you type, the add sheet already shows the category it will use. It also knows about 270 DIY words (Schrauben, Dübel, Glühbirne, Wandfarbe, Blumenerde …): with a Baumarkt they go to its categories and to that store, without one to „Haushalt“. Anything unknown goes to „Sonstiges“. If you move an item to another category, or pick another one before adding, the household remembers it and the same item lands there next time, also under another spelling of the same word (Karotten, Möhren), and also when you add it again right away on a slow connection. This works the same for items added in the app, by voice, through the AI-assistant connection, Siri and Alexa.

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

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): Hafermilch and „Mlich“ under Kühlregal, „Quietscheentchen“ in Sonstiges; DIY words in the Baumarkt categories of a household with a Baumarkt (`journeys/baumarkt.mjs`, DE and EN). Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): new items under their category; „Mlich“ under Kühlregal, „Kaffe“ and „Mehk“ in Sonstiges; DIY words in the Baumarkt categories of a household with a Baumarkt (`journeys/baumarkt.mjs`). Recipe: [classifier.md](./classifier.md).

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
- That Hummlist knows a particular DIY chain; it recognizes only the generic word.
- A fixed number of categories or any limit on how many you add (none found).
- Category names longer than 60 characters; the name field stops at 60.
- Two categories whose names differ only in case or spacing ("Baby" and "baby"); they cannot exist any more, and households that had them now have one.

**Unverified.** Whether there is a limit on the number of categories: none found in the app.

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): „Anpassen“ → „Ohne Laden“, adding „Baby“, the duplicate message for „ BABY“, deleting it. main 6c93da99, 2026-11-08 (CET): `journeys/baumarkt.mjs` (DE and EN); after the journey deletes its Baumarkt store, the seven categories stay under „Ohne Laden“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): „Anpassen“ → „Ohne Laden“ with the 11 categories, adding „Baby“, the duplicate message for „ BABY“, deleting it with the move-to choice; `journeys/baumarkt.mjs` (DE and EN): a store „Baumarkt“ brings its seven categories. Recipe: [categories.md](./categories.md).

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
- That every item gets a picture, or that the pictures come from AI or from the household's own lists. They come from a fixed table of item names that comes with the app and that Hummlist can extend from hummlist.com.
- That stores can be added, renamed or deleted without a connection; the app asks for one.

**Note.** The onboarding skip hint says „Du kannst sie später unter Liste → Anpassen anlegen.“ / "You can add them later under List → Edit." (jobs 68, 78).

**Last verified.** Branch job/171-store-header-tap (PR #329), 2026-11-08 (CET), from code, widget tests and the e2e spec list-walk-order: a hold or right click on a store's name or a category heading opens nothing, a tap folds. main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): adding „Supermarkt“, then „supermarkt“ keeps the window open with „Einen Laden „Supermarkt“ gibt es schon.“. main 6c93da99, 2026-11-08 (CET): `journeys/baumarkt.mjs` (DE and EN), `item-icons.mjs` (with a newer picture table from hummlist.com), `hex-surfaces.mjs`, `list-manage.mjs`, `top-bar-and-name-dialog.mjs`. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): „Anpassen“ as a raised hex top right, „Läden“, adding a store, adding „supermarkt“ while Supermarkt exists (the window stays open with „Einen Laden „Supermarkt“ gibt es schon.“, no second store), item pictures and the plain hexagon on a mixed list, a newer picture table from hummlist.com, the rename dialog fitting its content; `journeys/baumarkt.mjs` (DE and EN): Schrauben, Dübel, Glühbirne, Wandfarbe, Silikon and Blumenerde in the Baumarkt section in its walking order, Milch outside it. Recipe: [stores-walk-order.md](./stores-walk-order.md).

## Live sync between household members

**What it does.** Everyone in a household sees the same list, live. When a partner adds, ticks, edits, moves or deletes an item, it shows on the other phone within a couple of seconds, with no reload. New items from a partner are highlighted, and the floating bar at the top of the list says how many are new and from whom, until they have been on screen for a moment.

**How to get there.**
1. Both people join the same household: one uses „Mehr“ (EN: "More") → „Partner einladen“ (EN: "Invite your partner"), the other opens the link or enters the code.
2. Open „Liste“ (EN: "List"). Changes appear on its own.
3. In the floating bar at the top of the list: „1 neu von Noah Brandt“ (EN: "1 new from Noah Brandt"). While the phone is offline or syncing has trouble, a card under the bar says so and then folds into a small pill at the top left (see "Working offline"); nothing shows while changes are simply being sent.

**Never claim.**
- Sync with people outside the household, or with a read-only guest view.
- Push notifications for a partner's changes.
- That the list updates with the app fully closed in the background.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), two members side by side: a partner's add shows „1 neu von Noah Brandt“ within a second; a tick on one phone removes the row on the other. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist), two members side by side: a partner's add shows „1 neu von Noah Brandt“ within a second, a tick on one phone removes the row on the other; the offline cloud beside „Anpassen“. Recipe: [live-sync.md](./live-sync.md).

## Working offline

**What it does.** The shopping list keeps working without a connection: adding, ticking, editing and deleting items all show up immediately and are sent automatically once the phone is back online. The app also opens offline and shows the last list it had. A dark card at the top of the list says "Offline" as soon as the phone loses its connection (flight mode, Wi-Fi off), with no tap needed, and goes away on its own a moment after the connection is back, when changes from others in the household arrive again right away; it folds into a small "Offline" pill after about 3 s or as soon as the user scrolls. When the server has trouble instead, and the app's own retry a few seconds later fails too, a yellow "Sync gestört" (EN "Sync failing") card says the changes are saved on the phone; a tap tries again, and once it works the card simply goes away. A single hiccup that the retry gets past shows nothing. Nothing shows while everything is in sync. Suggestions while typing still work offline, from items the household used before, even with a typo or part of a word, and the empty field still shows what is due again. A few settings-type actions (reordering stores or categories, adding, renaming or deleting a store, creating or joining a household, exporting data, deleting the account, sending feedback) need a connection and say so, also while the dialog or sheet they were started from is still open. Changes to categories made offline are not saved: the app says so and puts them back. If someone else added the same item while you were offline, your add becomes theirs when it syncs (no second row), and what you did to it offline, like ticking it off, goes to theirs. Amounts typed offline are read the same way as online, also as words („zwei Gurken“, "two apples"). Brand and details typed offline („Windeln Pampers Größe 3“) are sorted out when the add syncs, as for an online add. Someone in several households can switch to another one while offline: what they changed in the first is still sent once the phone is back online, without opening it again.

**How to get there.**
1. Open „Liste“ (EN: "List") and use it as usual with the connection off.
2. The card „Offline“ shows under the bar at the top of the list: „Änderungen werden synchronisiert, sobald du wieder online bist.“ (EN: "Your changes will sync once you're back online."). After about 3 s, or when you scroll or swipe it up, the card shrinks into the small „Offline“ pill at the top left, left of „Anpassen“ (EN: "Edit"); tap the pill to read the card again.
3. When the connection returns, the card or pill goes away on its own within a few seconds, with no tap and no message. If it says „Sync gestört“ (EN: "Sync failing") instead, tap it to try again.

**Never claim.**
- That a partner sees offline changes before they sync.
- A "back online" or "synced" message: the indicator just goes away (screen readers hear „Synchronisiert“ after a tapped retry only).
- That reordering stores or categories, adding or changing stores or categories, feedback or account actions work offline.
- Offline voice dictation to a server: dictation stays on the device, but splitting text into items needs a connection.

**Unverified.** Offline sign-in, and a first start offline before the list was ever synced (not covered by specs or read in detail).

**Last verified.** Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and widget tests only, **not driven**: changes queued in one household are sent after a switch to another and after a restart. main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): offline, the „Offline“ card at once, folded into the pill after about 3 s, open again on a tap, gone under a second after the connection came back with no tap. main 8ad168f5, 2026-11-08 (CET): a server answering 503 shows nothing at first and „Sync gestört“ once the retry fails too; a tap names it „Wird erneut versucht“ until it goes through, then it leaves; `journeys/offline.mjs`: amounts typed offline match the ones typed online. Earlier: the connection-recovery change before it landed, 2026-11-07 (CET), driven on the web build (verify-hummlist and e2e `connectivity.spec.ts`) with the live socket left dead and open across a network drop: back online, „Offline“ goes about 3 s later and a partner's add shows within a second (before: 39.5 s, after the heartbeat). Recipe: [offline.md](./offline.md).

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

**Last verified.** job 154b (PR #320, ba198151), 2026-11-08 (CET), driven on the web build in its review: „Darstellung“ and „Sprache“ sit in cards like the rows on „Mehr“; System, „Dunkel“ and back still switch. Earlier: main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): „Darstellung“, „Dunkel“ kept after a reload, back to System. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): „Darstellung“ with System, „Dunkel“ kept after a reload, and back. Recipe: [theme.md](./theme.md).

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

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): English live, back to „Wie Gerät“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): English live, the list in English, back to „Wie Gerät“. Recipe: [language.md](./language.md).

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

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): a note sent from a new account, „Danke!“. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): the sheet with its kinds, contact box and the „Wird mitgeschickt“ line, a note sent, „Danke!“. Recipe: [feedback.md](./feedback.md).

## The More tab, help and legal pages

**What it does.** The app has two tabs, List and More. On phones they sit in a small pill that floats at the bottom of the screen; the list scrolls on behind it. More is a short list of grouped rows, each one line with an icon, in this order: „Konto“ (EN: "Account") and, for a household that has Premium (a free unlock in the beta or for testers) or once Premium is on sale, „Hummlist Premium“; „Partner einladen“ (EN: "Invite your partner") and „Anderem Haushalt beitreten“ (EN: "Join another household"); „Zugänge“ (EN: "Access"); „Einstellungen“ (EN: "Settings") and „Nutzungsdaten“ (EN: "Usage data"); „Feedback senden“ (EN: "Send feedback"), in the iPhone and Android apps „Hummlist bewerten“ (EN: "Rate Hummlist"), and „Hilfe & Kontakt“ (EN: "Help & contact"); under the small heading „Rechtliches“ (EN: "Legal") the rows „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") and „Lizenzen“ (EN: "Licenses"); then „Abmelden“ (EN: "Sign out") on its own, looking like any other row, and the app version at the bottom. Categories and stores are under the list's „Anpassen“. „Nutzungsdaten“ opens a page with just the usage-data switch. Help, imprint and privacy policy open pages on hummlist.com in the browser; the terms open Apple's standard terms on iPhone and, until Hummlist has its own, the help page elsewhere. The imprint is two taps from the list: „Mehr“, then „Impressum“.

**How to get there.**
1. Tap „Mehr“ (EN: "More") in the pill at the bottom (on wide screens: the rail on the left).
2. Pick an entry, e.g. „Hilfe & Kontakt“ (EN: "Help & contact"), „Nutzungsdaten“ (EN: "Usage data"), „Abmelden“ (EN: "Sign out").
3. Imprint, privacy policy, terms and licenses: scroll to „Rechtliches“ (EN: "Legal") and tap „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") or „Lizenzen“ (EN: "Licenses").
4. Help page on the web: hummlist.com/support (EN: hummlist.com/en/support), with support@hummlist.com and answers to common questions.
5. Guides on hummlist.com: Siri Shortcut in German (the English page says it is German-only for now), Alexa skill in German and English („Hummlist per Alexa: Skill einrichten“, EN "Hummlist with Alexa: set up the skill"), and „Hummlist mit Claude verbinden“ (EN "Connect Hummlist to Claude"), in German and English. The app itself links no guide.

**Never claim.**
- A guides section inside the app, a help chat or an in-app browser.
- That the Siri guide exists in English beyond the German-only notice.
- A sign-out from anywhere but More.
- That signing out is marked as a warning or a dangerous step: it looks like any other row.
- An update notice in More: the app does not check for updates yet.
- That More shows the household's name: it no longer does.
- That archived households can be seen or reopened under More: the app does not show that row.
- That „Rechtliches“ is a page of its own: its entries are rows on More.
- Terms of use of Hummlist's own: the terms row shows Apple's standard terms on iPhone and the help page elsewhere.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): every row in order with „Abmelden“ last and the version; „Hilfe & Kontakt“ opens hummlist.com/support; Nutzungsdaten. The help page's questions from the locally built site. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): every row in order, „Abmelden“ last in the plain row style, the version, Nutzungsdaten, the tab pill. Recipe: [more-help.md](./more-help.md).

## Rating Hummlist in the store

**What it does.** In the iPhone and Android apps, More has the row „Hummlist bewerten“ (EN: "Rate Hummlist"). It opens Hummlist's page in the App Store or on Google Play, where people can leave a rating. Once Hummlist is in the public stores, the app may also ask for a rating with the phone's own rating window: only right after a shopping trip is finished (every item of a list with at least three items ticked off), after a few quiet seconds, and only for people who have used Hummlist for at least a week, on several days, without trouble (no failed sync, no error) lately. It asks at most a few times a year, never twice in four months. Hummlist asks no question of its own first and shows no extra text.

**How to get there.**
1. Tap „Mehr“ (EN: "More").
2. Tap „Hummlist bewerten“ (EN: "Rate Hummlist").

**Never claim.**
- That Hummlist asks "Do you like Hummlist?" or offers anything for a rating.
- That the rating window appears at a set time or for everyone: the phone decides whether to show it.
- The rating window in the beta (TestFlight, Google Play testing) or in the browser: it does not appear there.
- The rate row in the browser version: it is in the iPhone and Android apps only.

**Unverified.** The rating window on a real phone (no device on the runner); the store page opening on a real phone.

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `drive.sh rate-hummlist`: no rate row in the browser, a whole list ticked off counts one trip and asks nothing, putting one back and ticking it again stays one trip, 10 s offline is no failure and 70 s is. The row and the system dialog in the phone apps: unverified on a device. Earlier: the rating change before it landed, 2026-11-06 (CET): driven on the web build (verify-hummlist, `drive.sh rate-hummlist`): no rate row in the browser, a whole list ticked off counts one trip on the device and asks nothing, an undo and re-tick stays one trip, 10 s offline is no failure and 70 s is; the row in the iPhone/Android layout, DE and EN, from widget tests and goldens; the rules from unit tests. Recipe: [rate-hummlist.md](./rate-hummlist.md).

## Account: data export and deletion

**What it does.** The Konto page shows the signed-in email address with a copy button („Kopiert“, EN "Copied"). Every user can download a copy of their data as a JSON file and delete their account for good. Before deleting, the app says what happens to the shared household: it stays for the others (the user's items remain, without their name) or, for the last member, it is deleted with its list, history, categories and stores. The last member of a household with Hummlist Premium (bought for life, yearly, or a free unlock in the beta or for testers) is told first that Premium ends with the household and is not refunded automatically, with a link to ask Apple or Google for a refund, and ticks a box before deleting. The user confirms by typing a word. Single data can also be removed without deleting the account: an item from the list, an access token or connected app on Zugänge, and usage data by switching it off.

**How to get there.**
1. Open „Mehr“ (EN: "More").
2. Tap „Konto“ (EN: "Account"), the first row.
3. Tap „Meine Daten exportieren“ (EN: "Export my data") for the copy, or „Konto löschen“ (EN: "Delete account"), type LÖSCHEN (EN: DELETE) and tap „Endgültig löschen“ (EN: "Delete for good").
4. Without the app: app.hummlist.com/konto-loeschen.html explains all steps; single data is at app.hummlist.com/konto-loeschen.html#einzelne-daten under „Einzelne Daten löschen, ohne das Konto zu löschen“.

**Never claim.**
- History entries or „Zuletzt verwendet“ entries can be deleted one by one in the app (they cannot; history goes with the household, single entries on request by email to support@hummlist.com).
- Deletion can be undone, or happens later (it is immediate and final).
- Backups or logs vanish at once (backups are kept up to 90 days, logs 1 day, per the deletion page).
- That deleting the account archives the household or keeps Hummlist Premium: the last member's household goes with its Premium (also a tester's gift), and households the user archived go too. Premium is not refunded automatically; the app warns about this. That Premium can be kept by archiving the household: it cannot.

**Unverified.** Apple sign-in revocation on iPhone (no iOS surface to test).

**Last verified.** main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/account-deletion.mjs`: the email copy button. main 6c93da99, 2026-11-08 (CET): no Premium warning in a shared household; the Premium warning and tick box for the last member with a free unlock (nothing deleted). Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist), `journeys/account-deletion.mjs`: the email copy button; the Premium warning for the last member with a free unlock, none in a shared household (nothing deleted). Recipe: [account-deletion.md](./account-deletion.md).

# Connections and Premium

## AI assistants (MCP) and access tokens

**What it does.** An AI assistant that supports MCP can read the shopping list, add items, tick them off and move them to another category or store. The user connects it by signing in when the assistant asks (a page „Zugriff erlauben?“ with „Erlauben“ and „Ablehnen“) or with an access token („Zugriffstoken“, EN: "Access tokens") made in the app, which is shown once. After „Erlauben“ the page shows „Verbunden“ and „Fertig, du kannst zu <Assistent> zurückkehren.“ with the assistant's own name (EN: "Connected", "Done, you can return to <assistant>.") while the assistant finishes connecting (this can take about 10 seconds). Asked what's on the list, the assistant also gets how many items are open on the whole list and how many were ticked in the last 24 hours. An amount written before or after the item, like „2 Gurken“ or „Gurken 3“, becomes the amount; numbers that belong to the name stay in it („Windeln Größe 4“, „Büroklammern 100“). In the app the user sees the address, the tokens and the connected assistants, and can revoke or disconnect any of them at once. Each connected assistant shows where it was approved, like „Chrome · macOS“, when it was connected and when it was last active; a tap on it explains in plain words what it may do, with the button to disconnect it. A short text under „Zugriffstoken“ says that a token lets you build your own automations that manage the list. Someone in several households sees one more line naming the household a new token works in: the one open in the app („Ein neuer Token gilt für „Zuhause“, den Haushalt, der gerade offen ist.“, EN "A new token works in “Zuhause”, the household open now."). An assistant signed in with the user's account can list all their households and work in any of them by name. Nothing needs Premium today. Setup guide: hummlist.com/de/anleitungen/claude (EN /en/guides/claude).

**How to get there.**
1. Open „Mehr“ (EN: "More") and tap „Zugänge“ (EN: "Access").
2. Copy the server address under „MCP-Server“ (EN: "MCP server"): https://mcp.hummlist.com.
3. In the assistant, add a connector with that address and sign in, or tap „Token erstellen“ (EN: "Create token"), name it and copy the token once („Kopieren“).
4. To end access: the bin icon „<Name> widerrufen“ (EN: "Revoke <name>") then „Widerrufen“, or „<App> trennen“ (EN: "Disconnect <app>") then „Trennen“.

**Never claim.**
- That it needs Premium today. It doesn't. Once Peter turns the integration lock on (hold `integration-lock` in releases/flags.json), every tool tells a household without Premium „Dieser Haushalt braucht Hummlist Premium für den Zugang über KI-Assistenten …“; the Claude guides say so only from then (`::: once integration-lock`).
- That the assistant sees more than the list (it reads and changes shopping items, categories and stores only).
- That a key can be viewed again after creation (shown once).
- That Hummlist knows where an assistant is used or tracks its location: it only keeps the browser and system name of the page where the user approved it (gone once disconnected); „Zuletzt aktiv“ is the day the assistant last signed in or refreshed its sign-in, not of every request.
- That ended keys are deleted at once (the record stays 30 days, then a daily clean-up deletes it; the key itself stops working immediately).
- Any specific assistant as officially supported or tested. The app's MCP help text on Zugänge names two assistants as examples; copy names none (see "Never claim (everywhere)").

**Unverified.** The assistants' own connector screens.

**For assistants finding Hummlist on the web.** hummlist.com has https://hummlist.com/llms.txt, a list for AI assistants of every guide, help and legal page with the MCP server's address, and every page also as plain Markdown at its address plus `.md` (for example https://hummlist.com/en/guides/claude.md). Never claim the site is in search engines yet: it is hidden from them until launch.

**The address in a browser.** Someone who opens https://mcp.hummlist.com in a browser gets a short page in German or English (by the browser's language): „Hier sprechen KI-Assistenten mit deiner Hummlist.“ (EN "This is where AI assistants talk to your Hummlist."), a note that the address is for AI assistants that support MCP, not for the browser, the address with a copy button, and links to the guides and hummlist.com. It names no assistant. Never claim it does anything itself: it only explains the address. Live on mcp.hummlist.com (checked 2026-11-07); assistants still connect at the same address.

**Held: the Hummlist API.** Built but switched off for everyone: the app hides it and the server refuses its keys and requests. When it is on, Zugänge gets a section „API“ with an address, a link „API-Dokumentation“ and the button „API-Schlüssel erstellen“ (EN "Create API key"): the user names the key, picks „Nur lesen“ or „Lesen und schreiben“ (EN "Read only", "Read and write") and copies it once. Scripts and automations then read and change the list over HTTP. Do not announce it until Hummlist Launch says so. Never claim it today, nor a short address like api.hummlist.com (none exists).

**Last verified.** Branch job/169b-households-p2 (job 169b), 2026-11-08 (CET): from code and tests only, **not driven**: the line naming the household of a new token, households by name in any case, the list of households with a locked default. main 8ad168f5, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist), `journeys/ai-assistants.mjs`: the connected-app row and its details; a token reading the tools over MCP on the local stack. main 6c93da99, 2026-11-08 (CET): a token adding an item over MCP, and refused when unknown. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): the connected-app row and its details; a token adding an item over MCP on the local stack; https://mcp.hummlist.com in a browser shows the German page, and an assistant's request still reaches the server. Recipe: [ai-assistants.md](./ai-assistants.md).

## Siri

**What it does.** On an iPhone the user can add things to the Hummlist by voice: they say a sentence like „Milch, zwei Gurken und Klopapier“, Hummlist splits it into items, files each under a category and Siri reads back „Hinzugefügt: Milch, 2 Gurken, Klopapier.“ What is open already Siri names instead („Schon auf der Liste: Milch.“). When the user says just „Butter“ and „Butter Weihenstephan“ (a brand) or „Bio Butter“ is open, Siri without setup asks whether to add another Butter; the Shortcut adds nothing and says Butter Weihenstephan is already on the list. Another kind of the item, like „Butter gesalzen“ or „Milch laktosefrei“, is a different product: plain „Butter“ is added. Hummlist never changes or merges the open item. An amount said after the item counts too, as a word or digits: „Möhren zwei“ adds 2 Möhren, „Eier dreißig“ 30 Eier. A product name that starts with a number stays whole: „Drei Glocken Nudeln“ is one item. Today this works with a Shortcut the user sets up once (about five minutes, German only). Siri without any setup (iOS 17 and newer, German and English, also reads the list aloud) is built but its announcement is held until Hummlist Launch.

**How to get there.**
1. Open „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Token erstellen“ (EN: "Create token"), name it Siri, copy the token once.
2. In Apple's Shortcuts app build a shortcut called „Einkaufsliste“ (dictate text, send to Hummlist, speak the answer). The step-by-step guide is on hummlist.com: „Hummlist per Siri: Kurzbefehl einrichten“ (EN: "Hummlist with Siri (German only for now)").
3. Say „Hey Siri, Einkaufsliste“, then the items.

**Never claim.**
- That Siri works without setup as a released feature (held until Hummlist Launch).
- That it works on Apple Watch, AirPods or CarPlay (untested), or Android, or in the browser.
- That English sentences are split correctly through the Shortcut (German only).
- That it needs Premium today, or that it stays free after the public launch. Siri is free for everyone during the beta (testers keep a free unlock) and becomes part of Hummlist Premium after the public launch. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; testers' free unlock: P1, Nov 2.
- That the voice microphone in the app works on the web (iOS and Android apps only).

**Unverified.** Real Siri voice on a device; the Shortcut on current iOS versions. Siri without setup in German: the device tests on build 1119 (3 Nov 2026) sent „Füge … zur Hummliste hinzu“ to Reminders or answered „Hummlist unterstützt das nicht“. The fix (sentences that name Hummlist first or as the object, like „Etwas auf Hummlist setzen“ and „Hummlist, was steht drauf?“; any item in „Füge Zahnpasta zu Hummlist hinzu“; Siri asks once to be allowed for Hummlist) waits for the next German device test. Never write „Einkaufsliste“ as a Hummlist Siri sentence: Siri gives it to Reminders. Built since, not yet tried on a device: Siri says the name „Hummlist“ and no longer takes „Hummliste“ or „Humm Liste“ for it, more German sentences („Füge etwas zu meiner Hummlist hinzu“, „Zeig meine Hummlist“), the household's own words for an item („Möhren“ for „Karotten“), and on an error Siri answers instead of opening the app. The iPhone app needs iOS 17 or newer.

**Last verified.** main 8ad168f5, 2026-11-08 (CET), the Shortcut's requests on the local stack: „Butter“ with Butter Weihenstephan open (the reply and the question, DE and EN), reading eleven items. main 6c93da99, 2026-11-08 (CET): an add sentence with „Schon auf der Liste“, the not-understood sentence. Siri itself needs an iPhone. Earlier: main c2ce938f, 2026-11-07 (CET), the Shortcut's requests against the web build's local stack: an add sentence, „Schon auf der Liste“, „Butter“ with Butter Weihenstephan open (the reply and the question, DE and EN), the not-understood sentence. Siri itself needs an iPhone. Recipe: [siri.md](./siri.md).

## Home Screen widget (held)

**What it does.** On iPhone and Android the user can put Hummlist on the Home Screen as a widget. It shows how many items are still open („3 offen“, EN "3 open") and the next ones with their quantity, then „+2 weitere“ (EN "+2 more") if more are open. The medium size adds the store's name and a „Hinzufügen“ (EN "Add") button, also when everything is done („Alles erledigt“, EN "All done"). A tap on the widget opens the list; Add opens the list with the input ready. Without internet it shows the last list the app saw. Built, but its announcement is held until it has been tested on an iPhone and an Android phone.

**How to get there.**
1. iPhone: touch and hold an empty spot on the Home Screen, „Bearbeiten“ (EN "Edit") → „Widget hinzufügen“ (EN "Add Widget") → Hummlist, pick small or medium.
2. Android: touch and hold an empty spot → „Widgets“ → Hummlist, drag it out; four columns wide shows the Add button.
3. Guides (drafts until the hold ends): „Hummlist auf dem Home-Bildschirm: das Widget“ (EN "Hummlist on your Home Screen: the widget").

**Never claim.**
- That it is released (held until a device test).
- That you can tick items off in the widget (you open the app for that).
- That a partner's adds show in the widget the moment they happen (they show once Hummlist was open on your phone again).
- That it follows the app's own light/dark choice (it follows the phone's).
- That it works on the web, Apple Watch, the Lock Screen or StandBy.
- That it needs Premium (it does not).

**Unverified.** Everything on a real device: the look in light and dark, both sizes, the taps.

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and the app's 22 widget tests (passed). The widget on a phone: unverified. Earlier: main c2ce938f, 2026-11-07 (CET), from code and the app's 22 widget tests (passed). The widget on a phone: unverified. Recipe: [home-widgets.md](./home-widgets.md).

## Alexa skill (beta)

**What it does.** With the Hummlist skill a household member can say „Alexa, sag Hummlist, füg Milch und Eier hinzu“; the items land on the shared list, sorted by category, and Alexa says „Ich habe Milch und Eier auf die Hummlist gesetzt.“ What is open already it names in one sentence: „Schon auf der Hummlist: Milch.“ Saying just „Butter“ while „Butter Weihenstephan“ (a brand) or „Bio Butter“ is open, Alexa asks whether to add another Butter; yes adds it, no adds nothing. With „Butter gesalzen“ open, plain „Butter“ is simply added. An amount said after the item counts too: „Zwiebeln drei“ adds 3 Zwiebeln. A product name that starts with a number stays whole: „Drei Glocken Nudeln“ is one item. „Alexa, frag Hummlist, was auf der Liste steht“ reads the open items (up to ten, then „und N weitere“; with eleven it reads all eleven). On an Alexa device set to English it understands "Alexa, ask Hummlist to add milk and eggs" and "Alexa, ask Hummlist what's on the list" and answers in English ("I put milk and eggs on Hummlist."). The skill is in beta and not yet certified by Amazon, so it is not for everyone.

**How to get there.**
1. Ask for a beta invitation (the link comes from Peter, who needs the email address of your Amazon account); accept it.
2. In the Alexa app open the skill „Hummlist“ and tap „Zur Verwendung aktivieren“.
3. Sign in to Hummlist and tap „Erlauben“ on the page „Zugriff erlauben?“ (it names „Amazon Alexa“). The page then says „Verbunden“ (EN "Connected") until the Alexa app takes over.
4. Say „Alexa, sag Hummlist, …“ (EN: "Alexa, ask Hummlist to …", "Alexa, tell Hummlist …", "Alexa, open Hummlist") (for example „… ich brauche Milch“, „… füge Milch hinzu“, „… setz Milch drauf“), „Alexa, frag Hummlist, …“ or „Alexa, öffne Hummlist“. The name works best said clearly in two syllables, „Humm-list“. To end it: Hummlist → „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Amazon Alexa trennen“ (EN: "Disconnect Amazon Alexa") → „Trennen“, or disable the skill in the Alexa app. Disabling the skill also removes „Amazon Alexa“ from Zugänge. A connection nobody used for 12 months is removed, Zugänge entry included.

**Never claim.**
- That the skill is certified, in the public Alexa Skill Store, or available to everyone.
- That it speaks any language besides German and English, or that everyone can find it in the Skill Store (it is listed for every country only once certified).
- That it needs Premium (it is free, also after Premium launches). Source: Peter Q39 AP1, Nov 2; docs/PAYWALL_RELEASE.md.
- That it works for ticking items off or moving them (add and read only).
- That „Alexa, setz Milch auf die Hummlist“ (EN "Alexa, add milk to Hummlist") works: without „sag/frag/öffne Hummlist“ ("ask/tell/open Hummlist") Alexa's own lists take the sentence.
- Exact deletion periods beyond what the privacy policy says (its wording waits for Peter's approval).

**Unverified.** Real Alexa voice, the Alexa app screens and the beta invitation flow (no device or Amazon account here).

**Last verified.** main 8ad168f5, 2026-11-08 (CET), the skill's server side on the local stack: opening it without a linked account, requests not signed by Amazon refused. main 6c93da99, 2026-11-08 (CET): the same in English and a stale request refused; the skill's 440 unit tests with the voice ones pass (a mixed add says „Ich habe … auf die Hummlist gesetzt. Schon auf der Hummlist: …“). Earlier: main c2ce938f, 2026-11-07 (CET), the skill's server side on a local test setup: opening the skill without a linked account (DE and EN), requests not from Amazon refused. Recipe: [alexa.md](./alexa.md).

## Hummlist Premium (held)

**What it does.** Premium is not on sale yet and nothing in the app is gated by it: Siri, Alexa and AI assistants work for everyone. After the public launch Siri and AI assistants become part of Premium; the Alexa skill stays free. Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2. The app has a „Hummlist Premium“ page about the household: „Hummlist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen.“ (EN: "Hummlist Premium covers your whole household, including everyone who joins later."), „KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden“ (EN: "Connect AI assistants that support MCP to your list"). Once native Siri is released, the iPhone app lists „Per Siri auf die Liste, ohne die App zu öffnen“ (EN: "Add to the list with Siri, without opening the app") above that line, and once the Hummlist API is released, „Eigene Automationen mit der Hummlist API“ (EN: "Your own automations with the Hummlist API") below it; both are hidden today. Today it shows nothing else: no slogan, no prices, no buy buttons, no „bald verfügbar“, no note about buying in the apps, no refund link. Never name an assistant brand for Premium (Legal Review N-67). Beta households with a free unlock see „In der Beta kostenlos freigeschaltet, bis Hummlist Premium startet“ (EN: "Free in the beta, until Hummlist Premium launches") with „Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid.“ (EN: "You pay nothing, and nothing renews automatically. We'll let you know at least 4 weeks before the free unlock ends.") and a link „Mehr dazu in der Datenschutzerklärung“ (EN: "More in the privacy policy"); these are Legal Review's approved texts. Testers and app review see „Kostenlos freigeschaltet (Test und App-Prüfung)“ (EN: "Unlocked free of charge (testing and app review)") instead. They also see the row „Hummlist Premium“ in Mehr.

**How to get there.** Not from Mehr before the launch: the row „Hummlist Premium“ shows only for households that have Premium (a free unlock in the beta or for testers). The page opens from its link.

**Note.** The privacy policy explains the free unlock in the section „Hummlist Premium in der Beta“ (hummlist.com/datenschutz#premium-beta): testers and Apple's and Google's app review get Premium for free until the team ends it, and it never turns into a paid purchase.

**Never claim.**
- That Premium can be bought, or any price, plan or discount (yearly and Lifetime are planned, not for sale).
- That Siri, Alexa or AI assistants need Premium today (they do not), that Siri or AI assistants stay free after the public launch (they become part of Premium), or that Alexa ever needs it (the skill stays free). Source: Spec #4, Oct 31; docs/PAYWALL_RELEASE.md; Alexa: Peter Q39 AP1, Nov 2.
- That Google Assistant or Apple Watch exist or are coming.
- That there is a free trial.
- That Mehr shows Hummlist Premium to everyone (it does once Premium is on sale).

**When it goes on sale.** Nothing changes for users until Peter's go; the switches and their order are in `docs/PAYWALL_RELEASE.md`. Write launch copy from `docs/PURCHASES.md`, not from this section.

**Unverified.** Real store purchases (no store sandbox here); whether the analytics event for the paywall ever fires in production (it should not).

**Last verified.** main 6c93da99, 2026-11-08 (CET), from code and driven on the web build (verify-hummlist): no row without Premium; a gifted household's row with „Kostenlos freigeschaltet (Test und App-Prüfung)“ for an unlock to 2100 and „In der Beta kostenlos freigeschaltet, bis Hummlist Premium startet“ for a 60-day unlock; the row gone once it ended. Earlier: main c2ce938f, 2026-11-07 (CET), from code and driven on the web build (verify-hummlist): no row without Premium; a gifted household's row, „Kostenlos freigeschaltet (Test und App-Prüfung)“ for an unlock without end and „In der Beta kostenlos freigeschaltet, bis Hummlist Premium startet“ for a beta unlock, with no buy note. Recipe: [premium.md](./premium.md).
