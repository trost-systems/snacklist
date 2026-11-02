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
- That Siri, Alexa or AI assistants need Premium. Today they don't, and the Alexa skill stays free for good.
- Siri without setup ("just say Hey Siri", no Shortcut) as available. It is built, but its announcement waits for Hummlist Launch. Today Siri works through a Shortcut the user sets up once, in German.
- That the Alexa skill is launched, certified or in the Alexa Skill Store. It is a beta by invitation, in German and English.
- Store logos or chain colours, official store layouts, prices, offers or opening hours. Store names are plain names; walking orders are researched defaults.
- A code to type from an email for sign-in. Sign-in emails contain a link, and the only code in Hummlist is the 8-character household invite code.
- The Home Screen widget as available. It is built for iPhone and Android, but its announcement waits for a device test (see „Home Screen widget (held)“).
- Apple Watch, Google Assistant, Android voice assistants, push notifications, recipes, meal plans or price tracking. None exist.
- That the microphone (dictation) works in the browser. It is in the iPhone and Android apps only.
- Real people's names or lists. Clips and screenshots use the fictional Brandt family.
- Anything the sections below mark as held (Premium, native Siri, the Alexa skill's certification, the Home Screen widget, Premium-only connections).

# Getting started

## hummlist.com waitlist (not live yet)

**What it does.** Once Peter turns it on, hummlist.com shows a waitlist instead of links to the browser version: people leave their email (ideally the one of their Apple ID or Google account), say whether they have an iPhone or an Android phone, and can tick that they want one email when the app launches. They confirm by tapping a link in the confirmation mail and pressing the button on the page. Confirmed people are invited to the beta in weekly batches, by hand. Every mail has a link that deletes the entry at once.

**How to get there.**
1. hummlist.com (opens /de or /en by browser language).
2. „Auf die Warteliste“ (EN: "Join the waitlist").
3. In the mail: „E-Mail bestätigen“ (EN: "Confirm email").

**Never claim.**
- That the waitlist is live before Peter turns it on (today hummlist.com still shows the test page).
- A place in line, a referral reward, a counter, or a date for a particular person's invite.
- That the browser version is open to new users.
- Any text marked ⟦LAUNCH COPY⟧ or ⟦LEGAL …⟧ on the preview as final.

**Last verified.** job 82 branch (job/82-waitlist), 2026-11-03 (CET), driven on a local preview against the local stack (sign-up, duplicate, confirm, unsubscribe, one-click unsubscribe) and by pgTAP, Deno and site tests. Recipe: [waitlist.md](./waitlist.md).

## Sign-up and sign-in

**What it does.** A new or returning user signs in with Google or Apple, or with email: email and password, a new account with "Registrieren", or a sign-in link by email opened on the same device. Google and Apple come first; email is one more button below them, „Weiter mit E-Mail“ (EN: "Continue with email"). The keyboard opens only when the user taps a field. Signing out is in the More tab. The login screen links the imprint and the privacy policy.

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

**Last verified.** job/70-login-no-autofocus f48d081 (job 70), 2026-11-02 (CET), from code and driven on the web build (verify-hummlist, DE and EN, light and dark); email subjects from the hosted project's auth settings (2026-11-01). Recipe: [sign-in.md](./sign-in.md).

## Usage-data question (analytics consent)

**What it does.** Right after the first sign-in on a device, Hummlist asks once whether it may collect usage data. A no sends nothing at all. A yes sends pseudonymous usage data and error reports to PostHog on servers in the EU. Both answers are equally prominent, and the user can change the answer any time under More → Nutzungsdaten. Anyone who said yes to an earlier wording of the question is asked again with the current, shorter text, and nothing is sent until they answer. A no stays a no.

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

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist); the switch under Mehr → Nutzungsdaten: job/85-more-menu-mp2 8399b9c, 2026-11-03 (CET), by `e2e/tests/analytics.spec.ts` and `shell-more.spec.ts`. Recipe: [privacy-consent.md](./privacy-consent.md).

## Getting started: first sign-in to the list

**What it does.** After the first sign-in, a new user creates a household or accepts an invite. Creating asks for a household name (prefilled "Unser Haushalt") and which stores you shop at: pick from ten common ones (EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann) and add your own, or skip and add them later. Then Hummlist offers to invite the partner and opens the shopping list. Someone who opens an invite link goes straight to joining.

**How to get there.**
1. Sign up or sign in. If the app asks about usage data, answer it.
2. On „Willkommen bei Hummlist“ (EN: "Welcome to Hummlist") tap „Haushalt erstellen“ (EN: "Create a household") or „Einladung annehmen“ (EN: "Join with an invite").
3. Creating: choose the name, tap the stores you shop at (or „Eigenen Laden hinzufügen“, EN: "Add your own store", and type a name such as „Wochenmarkt“; typing one of the ten, „edeka“ say, ticks it), then „Haushalt erstellen“ (EN: "Create a household"); „Überspringen“ (EN: "Skip") starts without stores.
4. Next screen „Partner einladen“ (EN: "Invite your partner"): make an invite or tap „Später“ (EN: "Later") to go to the list.

**Never claim.**
- A tour, a tutorial or a newsletter or email opt-in in the app: there is none.
- That any store is pre-installed, recommended or a partner: nothing is picked until you pick it, and the shops have nothing to do with Hummlist.

**Last verified.** job 88 branch, 2026-11-03 (CET), typed chain names driven on the web build (verify-hummlist) and by app/test/household/onboarding_test.dart; main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build. Recipe: [onboarding.md](./onboarding.md).
**Last verified.** job 68 branch, 2026-11-02 (CET), skip hint by app/test/household/onboarding_test.dart; job 58 branch (PR #176), 2026-11-01 (CET), by e2e/tests/onboarding.spec.ts and stores-add.spec.ts. Recipe: [onboarding.md](./onboarding.md).

## Household and invites

**What it does.** One household shares one shopping list. A member invites a partner with an 8-character code and a link; each invite is valid for 7 days and works for one person. The partner types the code or opens the link and joins. A member can revoke open invites at any time.

**How to get there.**
1. Tab „Mehr“ (EN: "More"), row „Partner einladen“ (EN: "Invite your partner").
2. Tap „Neue Einladung“ (EN: "New invite"), then share it with „Teilen“ (EN: "Share") or copy it with „Link kopieren“ / „Code kopieren“ (EN: "Copy link" / "Copy code").
3. To join: „Anderem Haushalt beitreten“ (EN: "Join another household") right below it, enter the code, „Weiter“ (EN: "Continue"), then „Haushalt beitreten“ (EN: "Join household"). Or open the invite link. Back or „Abbrechen“ (EN: "Cancel") returns to „Mehr“ (job 78, 2026-11-02).
4. To revoke: on the invites page tap „Widerrufen“ (EN: "Revoke") on an invite.

**Never claim.**
- A members list, renaming a household, removing a member or a "leave household" button: none exist. Joining another household moves the person; if they were the last member, the old household is deleted with its list.
- An archive for households: it is off in the released apps.
- Invites that stay valid longer than 7 days or work for several people.
- Purchases or Premium tied to joining: Premium is not on sale yet.

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist); the More rows without hints: job/85-more-menu-mp2 8399b9c, 2026-11-03 (CET), `shell-more.spec.ts`. Recipe: [household-invites.md](./household-invites.md).

## Links into the app

**What it does.** A link to app.hummlist.com opens that screen of Hummlist: in the iPhone or Android app when it is installed, otherwise in the browser. A link can open the list, the add field, one store's part of the list, the More tab and its pages (for example „Einladungen“ / "Invites" or „Einstellungen“ / "Settings"), or an invite. Someone who is signed out signs in first and then lands on the linked screen; a new account sets up its household first.

**Links to use.**
- The list: `https://app.hummlist.com/list`
- Add something: `https://app.hummlist.com/add` (opens the add field, ready to type)
- Invite your partner: `https://app.hummlist.com/more/invites`
- Settings (theme, language): `https://app.hummlist.com/more/settings`
- The More tab: `https://app.hummlist.com/more`
- A store's part of the list: `https://app.hummlist.com/stores/<id>`. The id belongs to one household, so this link only works for its members; don't put it in emails to everyone.

**Never claim.**
- That the iPhone app opens these links before the next app release. Until then the iPhone opens them in the browser (invite links already open the app).
- Links that fill in an item ("add Milch") or tick something off: a link only opens a screen.
- That a link keeps working after the app was closed during sign-in on the phone: it then opens the list.

**Last verified.** job/66-deep-links, 2026-11-02 (CET), web build with e2e/tests/deep-links.spec.ts. Phone apps: unverified on a device. Recipe: [app-links.md](./app-links.md).

# The list

## Quick add

**What it does.** The bar at the bottom of the list, „Was brauchst du?“ (EN: "What do you need?"), is how items get onto the list. As soon as you type or tap it, a sheet opens with suggestions: what you typed, things you bought before, other packs, sizes and brands, and words from a built-in catalogue; they also find what you meant despite a small typo ("Hafermlch" offers Hafermilch). Enter takes the first suggestion, a tap takes any. Hummlist reads amounts out of what you type, in front or behind ("2 l Milch", "6x Eier", "zwei Gurken", "Karotten 2", "Karotten x2"), and a number that belongs to the item is not taken as an amount ("Windeln Größe 4", "Vitamin D3", "7up"); and picks the category and, where it knows one, the store. After an add the field is empty and ready for the next item, and „Rückgängig“ (EN: "Undo") takes the last add back.

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

**Last verified.** job 61 branch (quantities), 2026-11-01 (CET), driven on the Linux app with fg; main 3d66cee, 2026-11-01 (CET), from code on main; typo rows driven on the web build at 113e756 (verify-hummlist journey, typo probe, how-to clip DE and EN), offline and recent rows from job 59's own drives (#179). Recipe: [quick-add.md](./quick-add.md).
**Last verified.** job 78, 2026-11-02 (CET), the bar and sheet driven on the web build (verify-hummlist journey `list-manage`, e2e `add-sheet.spec.ts`) and by widget tests and goldens at 358 and 390 px; closing right after an add: job 76 branch, 2026-11-02 (CET), `add-sheet.spec.ts`, 20 repeats. Recipe: [quick-add.md](./quick-add.md).

## Due again

**What it does.** Hummlist notices what a household buys regularly. When you open the add bar with nothing typed, items that are probably running out show up as „Wieder fällig“ (EN: "Due again"); one tap puts them on the list with the usual quantity. An item shows up once it was bought on at least two different days and about its usual time between purchases has passed. Below them come the items used in the last 30 days, marked „Zuletzt verwendet“ (EN: "Recently used"), up to 10 rows in all. The sheet opens small, with three of them; the others scroll.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Tap the bar „Was brauchst du?“ (EN: "What do you need?") without typing.
3. Tap a row marked „Wieder fällig“ (EN: "Due again").

**Never claim.**
- That Hummlist sends reminders or notifications about due items; it only shows them in the add sheet.
- That it works from a single purchase; it needs at least two purchase days.
- That it predicts quantities by season or guesses new items; it only repeats what the household bought.

**Last verified.** job 64 branch (job/64-polish-seed), 2026-11-02 (CET), from code on the branch, driven on the web build (360×640, 390×844) and by widget, pgTAP and Deno tests. Recipe: [usuals.md](./usuals.md).

## Dictation

**What it does.** In the iPhone and Android apps, a microphone next to the add bar lets people speak what they need. Hummlist listens in German, on the phone only, so the voice never goes to a server. The words appear as they are spoken and, when the person pauses, Hummlist splits the sentence into separate items ("Milch, zwei Gurken und Klopapier") and adds them. An amount said after the item counts too: „Gurken zwei“ adds 2 Gurken. It then says what it added.

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

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main; on the web build only the missing microphone and the sentence splitting were driven (verify-hummlist), the microphone needs a phone. Recipe: [dictation.md](./dictation.md).
**Last verified.** job/89-fix-voice-quantity-words, 2026-11-03 (CET), from the voice function on a local stack (split-only and add, German and English) and the splitter, handler, Alexa handler and add-path tests; dictation itself needs a phone, Alexa a device. Recipe: [dictation.md](./dictation.md).

## Ticking items, "Zuletzt verwendet" and undo

**What it does.** Tapping an item on the list ticks it off: a line strikes through it, the row turns mint and slides away in under half a second, without a message. There is no check box to tap; the whole row is the target. At the bottom of the list, „Zuletzt verwendet“ keeps the last 20 ticked items, each one only once, and leaves out anything that is back on the list; tapping one puts it back where it was. With nothing typed, the add bar also suggests recently used items under the same name, „Zuletzt verwendet“ (EN: "Recently used"). Deleting an item or adding one by mistake can be undone with „Rückgängig“.

**How to get there.**
1. Open the list and tap an item to tick it.
2. Scroll to the bottom and tap „Zuletzt verwendet“ (EN: "Recently used") to unfold it.
3. Tap the item to put it back; a note says „<Name> steht wieder auf der Liste“ (EN: "<Name> is back on the list").
4. To delete: hold the item (or right-click it on a computer), tap „Löschen“ (EN: "Delete"), then „Rückgängig“ (EN: "Undo") if it was a slip.

**Never claim.**
- That ticking shows an undo message; it does not. Undo for a tick is the „Zuletzt verwendet“ section.
- A check box next to each item: there is none.
- That swiping does anything on a row: it neither deletes nor edits (since job 78); holding opens editing.
- That ticked items vanish after a fixed time or can be counted past 20 there.

**Unverified.** Whether ticked items are ever removed from the section by age: no cleanup job was found in the code, but it was not run.

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist).
**Last verified.** job 78, 2026-11-02 (CET), the swipe's removal by the app's widget tests (`app/test/list/list_screen_test.dart`); the e2e specs were rewritten but not run. Recipe: [tick-and-undo.md](./tick-and-undo.md).

## Edit an item

**What it does.** Every item can be changed after it is on the list: its name, brand, details (like "Größe 3" or "1,5 %"), quantity, store and category. The list row shows the brand and details in small text under the name. Items can also be deleted from the same sheet, with an undo.

**How to get there.**
1. Open the „Liste“ (EN: "List") tab.
2. Press and hold an item, or right-click it on a computer. (A plain tap ticks the item off instead.)
3. In the sheet „Bearbeiten“ (EN: "Edit") change „Bezeichnung“ (EN: "Name"), „Marke“ (EN: "Brand"), „Menge“ (EN: "Qty") with the buttons „Eins weniger“ / „Eins mehr“ (EN: "One less" / "One more"), or „Eigenschaften“ (EN: "Details"), or pick another store or category with the chips. The store chip also offers „Neuer Laden“ (EN: "New store", the row with a plus) to add a store and pick it. Hummlist remembers the new store or category the next time the item is added.
4. Tap „Fertig“ (EN: "Done") to save, „Abbrechen“ (EN: "Cancel") to discard, or „Löschen“ (EN: "Delete") to remove the item; „Rückgängig“ (EN: "Undo") in the message that shows for a few seconds brings it back. If someone put the same item on the list in the meantime, Undo shows theirs, as they wrote it, instead of a second one.

**Never claim.**
- That a swipe deletes or edits an item; a swipe does nothing, a hold opens the edit sheet.
- That Undo after a delete always brings back your own quantity: when the item is on the list again by then, the one there stays as it is.
- That items in „Zuletzt verwendet“ (EN: "Recently used") can be edited.
- That the quantity buttons work on free text like "eine Packung"; they only step numbers.
- That holding and dragging moves an item on the list; nothing on the list drags since job 78. Holding opens this sheet.

**Last verified.** job 78, 2026-11-02 (CET), by the app's widget tests (`app/test/list/list_screen_test.dart`); the e2e specs were rewritten but not run. Recipe: [edit-item.md](./edit-item.md).
**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist); undo onto an open item: job 64b branch (job/64b-dup-skip-undo), 2026-11-02 (CET), driven on the web build (`already-on-list.spec.ts`). Recipe: [edit-item.md](./edit-item.md).

## Tips on the list

**What it does.** Once there is something on the list, a small card at the top shows one tip at a time, for example how to edit an item or that the amount can be typed with the item. The X hides a tip for good on that device; the next one shows from the next app start on. A new, empty list shows no tip.

**How to get there.**
1. Open Hummlist with at least one item on the list („Liste“, EN: "List").
2. Read the card at the top; tap the X („Tipp ausblenden“, EN: "Hide tip") to hide it.

**Never claim.**
- That tips sync between devices or members (they are per device and user).
- That tips show news or offers today (the two tips are how-tos).

**Last verified.** job/80-polish-access-tips-account, 2026-11-02 (CET), by the widget tests and goldens (`app/test/tips/`) and driven on the web build (verify-hummlist). Recipe: [tips.md](./tips.md).

## Automatic category (the classifier)

**What it does.** When an item is added, Hummlist sorts it into a category on its own, such as Kühlregal for Hafermilch, using a built-in German word list of about 1,200 terms plus common spelling variants, regional words, some English words and small typos. While you type, the add sheet already shows the category it will use. Anything unknown goes to „Sonstiges“. If you move an item to another category, or pick another one before adding, the household remembers it and the same item lands there next time, also under another spelling of the same word (Karotten, Möhren). This works the same for items added in the app, by voice, through the AI-assistant connection, Siri and Alexa.

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

**Last verified.** job 78, 2026-11-02 (CET), by the app's widget tests (`app/test/list/list_screen_test.dart`, `app/test/list/add_sheet_test.dart`) and driven on the web build (verify-hummlist). Recipe: [classifier.md](./classifier.md).

## Categories

**What it does.** Items on the list sit under categories such as Obst & Gemüse or Getränke. Every household starts with 11 and can add its own, rename any, reorder them, and delete any except „Sonstiges“. A new category goes just before „Sonstiges“. When a category is deleted, its items move to a category the user picks („Sonstiges“ unless changed).

**How to get there.**
1. On the list, tap „Anpassen“ (EN: "Edit") top right.
2. Tap „Ohne Laden“ (EN: "No store"), the last row, for the household's own order; or tap a store for that store's order of the same categories.
3. Tap a category to rename it, the trash icon to delete it (it disappears from every store), the handle to drag it; „Kategorie hinzufügen“ (EN: "Add category") adds one.

The starting categories, in order: Obst & Gemüse, Brot & Backwaren, Kühlregal, Fleisch/Wurst/Fisch, Vorrat & Konserven, Süßes & Snacks, Getränke, Tiefkühl, Haushalt, 👶 Drogerie, Sonstiges (EN: Fruit & veg, Bread & bakery, Chilled, Meat & fish, Pantry, Sweets & snacks, Drinks, Frozen, Household, 👶 Drugstore, Other).

**Never claim.**
- That "Sonstiges" can be deleted; it is the fallback for anything unrecognised.
- That categories are per store; stores only have their own order of the same categories.
- A fixed number of categories or any limit on how many you add (none found).
- Category names longer than 60 characters; the name field stops at 60.

**Unverified.** Whether there is a limit on the number of categories: none found in the app.

**Last verified.** job 78, 2026-11-02 (CET), from code and widget tests; e2e specs updated, not yet run. Recipe: [categories.md](./categories.md).

## Stores, walk order and the sections of the list

**What it does.** The list is split into one section per store (only stores that have something on the list), then „Ohne Laden“. Inside a store, items are grouped by category in that store's own walking order, so the list follows the way you walk through the shop. An item moves to another store or category in its edit sheet, and the household remembers which store an item belongs to. The list itself never drags: the order of stores and categories is changed in „Anpassen“. A new household has the stores it picked at the start; you can change their order and add your own stores (Rewe, the market, the bakery), each with its own walking order, rename them or delete them.

**How to get there.**
1. Open the „Liste“ tab (EN: "List"): each store is a section; tap a store's name to fold it.
2. Hold a store's name (or right click it) to open that store in „Anpassen“, where its category order is changed. Holding a category heading opens the store it sits in.
3. Hold an item (or right-click it), tap the store chip and pick a store to put it in that store.
4. On the list, tap „Anpassen“ (EN: "Edit") top right: the stores in list order, „Ohne Laden“ (EN: "No store") last. Drag the handle to reorder, the trash icon deletes a store, „Laden hinzufügen“ (EN: "Add store") adds one. Tap a store to rename it (its name on top) and to order its categories.
5. While adding or editing an item, open the store chip and tap „Neuer Laden“ (EN: "New store", the row with a plus), type the name and press Enter: the store is created and chosen for the item.

**Never claim.**
- Store logos, chain colours or official store maps. Store names appear as plain names in a small hexagonal label. The walking orders are researched defaults that can differ from a real shop.
- That items, stores or categories can be dragged around on the list; moving an item is the edit sheet's store or category choice, and ordering lives in „Anpassen“ (job 78).
- That the app knows prices, opening hours or store locations.
- That stores can be added, renamed or deleted without a connection; the app asks for one.

**Note.** The onboarding skip hint says „Du kannst sie später unter Liste → Anpassen anlegen.“ / "You can add them later under List → Edit." (jobs 68, 78).

**Last verified.** job 78, 2026-11-02 (CET), from code and widget tests; e2e specs updated, not yet run. Recipe: [stores-walk-order.md](./stores-walk-order.md).

## Live sync between household members

**What it does.** Everyone in a household sees the same list, live. When a partner adds, ticks, edits, moves or deletes an item, it shows on the other phone within a couple of seconds, with no reload. New items from a partner are highlighted, and the strip above the list says how many are new and from whom, until they have been on screen for a moment.

**How to get there.**
1. Both people join the same household: one uses „Mehr“ (EN: "More") → „Partner einladen“ (EN: "Invite your partner"), the other opens the link or enters the code.
2. Open „Liste“ (EN: "List"). Changes appear on its own.
3. Strip above the list: „1 neu von Noah Brandt“ (EN: "1 new from Noah Brandt"). A small cloud icon on its right appears while changes are being sent or the phone is offline.

**Never claim.**
- Sync with people outside the household, or with a read-only guest view.
- Push notifications for a partner's changes.
- That the list updates with the app fully closed in the background.

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist). Recipe: [live-sync.md](./live-sync.md).

## Working offline

**What it does.** The shopping list keeps working without a connection: adding, ticking, editing and deleting items all show up immediately and are sent automatically once the phone is back online. The app also opens offline and shows the last list it had. A cloud icon above the list says "Offline" while there is no connection. Suggestions while typing still work offline, from items the household used before, even with a typo or part of a word, and the empty field still shows what is due again. A few settings-type actions (reordering stores or categories, adding, renaming or deleting a store, creating or joining a household, exporting data, deleting the account, sending feedback) need a connection and say so. Changes to categories made offline are not saved: the app says so and puts them back. If someone else added the same item while you were offline, your add becomes theirs when it syncs (no second row), and what you did to it offline, like ticking it off, goes to theirs.

**How to get there.**
1. Open „Liste“ (EN: "List") and use it as usual with the connection off.
2. Look for the crossed-out cloud on the right of the strip above the list: „Offline: Änderungen werden synchronisiert, sobald die Verbindung zurück ist“ (EN: "Offline: changes will sync once the connection is back").
3. When the connection returns, the cloud goes away on its own.

**Never claim.**
- That a partner sees offline changes before they sync.
- That reordering stores or categories, adding or changing stores or categories, feedback or account actions work offline.
- Offline voice dictation to a server: dictation stays on the device, but splitting text into items needs a connection.

**Unverified.** Offline sign-in, and a first start offline before the list was ever synced (not covered by specs or read in detail).

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist); an offline add someone else made meanwhile: job 64b branch (job/64b-dup-skip-undo), 2026-11-02 (CET), driven on the web build (`already-on-list.spec.ts`). Recipe: [offline.md](./offline.md).

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

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist). Recipe: [theme.md](./theme.md).

## App language

**What it does.** The app is available in German and English. It follows the device language by default (German if the device uses neither); the user can override that. The switch is instant, covers the whole app and is remembered on that device.

**How to get there.**
1. „Mehr“ (EN: "More") → „Einstellungen“ (EN: "Settings") → „Sprache“ (EN: "Language").
2. Pick „Wie Gerät“ (EN: "Device"), „Deutsch“ or „English“.

**Never claim.**
- Any language besides German and English.
- That the language is stored in the account or follows the user to other devices.
- That everything is English once the app is set to English: suggestions from the catalogue („Aus dem Katalog“) stay German words, the Siri Shortcut answers in German and the sign-in emails are short English emails whatever the app language.

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist). Recipe: [language.md](./language.md).

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

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist). Recipe: [feedback.md](./feedback.md).

## The More tab, help and legal pages

**What it does.** The app has two tabs, List and More. More is a short list of grouped rows, each one line with an icon, in this order: „Konto“ (EN: "Account") and, once it is on sale, „Hummlist Premium“; „Partner einladen“ (EN: "Invite your partner") and „Anderem Haushalt beitreten“ (EN: "Join another household"); „Zugänge“ (EN: "Access"); „Einstellungen“ (EN: "Settings") and „Nutzungsdaten“ (EN: "Usage data"); „Feedback senden“ (EN: "Send feedback") and „Hilfe & Kontakt“ (EN: "Help & contact"); under the small heading „Rechtliches“ (EN: "Legal") the rows „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") and „Lizenzen“ (EN: "Licenses"); then „Abmelden“ (EN: "Sign out") on its own, and the app version at the bottom. Categories and stores are under the list's „Anpassen“ since job 78. „Nutzungsdaten“ opens a page with just the usage-data switch. Help, imprint and privacy policy open pages on hummlist.com in the browser; the terms open Apple's standard terms on iPhone and, until Hummlist has its own, the help page elsewhere. The imprint is two taps from the list: „Mehr“, then „Impressum“.

**How to get there.**
1. Tap „Mehr“ (EN: "More") in the bottom bar (on wide screens: the rail on the left).
2. Pick an entry, e.g. „Hilfe & Kontakt“ (EN: "Help & contact"), „Nutzungsdaten“ (EN: "Usage data"), „Abmelden“ (EN: "Sign out").
3. Imprint, privacy policy, terms and licenses: scroll to „Rechtliches“ (EN: "Legal") and tap „Impressum“ (EN: "Imprint"), „Datenschutzerklärung“ (EN: "Privacy policy"), „Nutzungsbedingungen (EULA)“ (EN: "Terms of Use (EULA)") or „Lizenzen“ (EN: "Licenses").
4. Help page on the web: hummlist.com/support (EN: hummlist.com/en/support), with support@hummlist.com and answers to common questions.
5. Guides on hummlist.com: Siri Shortcut in German (the English page says it is German-only for now), Alexa skill in German and English („Hummlist per Alexa: Skill einrichten“, EN "Hummlist with Alexa: set up the skill"), and „Hummlist mit Claude verbinden“ (EN "Connect Hummlist to Claude"), in German and English. The app itself links no guide.

**Never claim.**
- A guides section inside the app, a help chat or an in-app browser.
- That the Siri guide exists in English beyond the German-only notice.
- A sign-out from anywhere but More.
- An update notice in More: the app does not check for updates yet.
- That More shows the household's name: it no longer does (job 85).
- That „Rechtliches“ is a page of its own: its entries are rows on More.
- Terms of use of Hummlist's own: the terms row shows Apple's standard terms on iPhone and the help page elsewhere.

**Last verified.** job/85-more-menu-mp2 8399b9c, 2026-11-03 (CET), the M-P2 menu with the Nutzungsdaten page and the Rechtliches rows on More, from code and driven on the web build (e2e `shell-more.spec.ts`, `help.spec.ts`, `analytics.spec.ts`; screenshots `docs/screenshots/85/`). Recipe: [more-help.md](./more-help.md).

## Account: data export and deletion

**What it does.** The Konto page shows the signed-in email address with a copy button („Kopiert“, EN "Copied"). Every user can download a copy of their data as a JSON file and delete their account for good. Before deleting, the app says what happens to the shared household: it stays for the others (the user's items remain, without their name) or, for the last member, it is deleted with its list, history, categories and stores. The user confirms by typing a word. Single data can also be removed without deleting the account: an item from the list, an access key or connected app on Zugänge, and usage data by switching it off.

**How to get there.**
1. Open „Mehr“ (EN: "More").
2. Tap „Konto“ (EN: "Account"), the first row.
3. Tap „Meine Daten exportieren“ (EN: "Export my data") for the copy, or „Konto löschen“ (EN: "Delete account"), type LÖSCHEN (EN: DELETE) and tap „Endgültig löschen“ (EN: "Delete for good").
4. Without the app: app.hummlist.com/konto-loeschen.html explains all steps; single data is at app.hummlist.com/konto-loeschen.html#einzelne-daten under „Einzelne Daten löschen, ohne das Konto zu löschen“.

**Never claim.**
- History entries or „Zuletzt verwendet“ entries can be deleted one by one in the app (they cannot; history goes with the household, single entries on request by email to support@hummlist.com).
- Deletion can be undone, or happens later (it is immediate and final).
- Backups or logs vanish at once (backups are kept up to 90 days, logs 1 day, per the deletion page).
- That the delete dialog mentions Hummlist Premium, or that a household's Premium stays when its last member deletes their account (the household goes, and its Premium with it).

**Unverified.** Apple sign-in revocation on iPhone (no iOS surface to test).

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build (verify-hummlist); the email copy button: job/80-polish-access-tips-account, 2026-11-02 (CET), by app/test/settings/account_test.dart; the Konto row: job/85-more-menu-mp2, 2026-11-02 (CET), `shell-more.spec.ts`. Recipe: [account-deletion.md](./account-deletion.md).
- That deleting the account archives the household or keeps Hummlist Premium: the last member's household goes with its Premium, and households the user archived go too. Premium is not refunded automatically. The app's warning about this is held (it appears with the archive UI or the Premium sale).

**Unverified.** Apple sign-in revocation on iPhone (no iOS surface to test).

**Last verified.** job 68 branch, 2026-11-02 (CET), Premium warning by the widget tests (`app/test/settings/account_test.dart`) and e2e/tests/household-bound.spec.ts; main 1b6d204, 2026-11-01 (CET), from code on main. Recipe: [account-deletion.md](./account-deletion.md).

# Connections and Premium

## AI assistants (MCP) and access keys

**What it does.** An AI assistant such as Claude can read the shopping list, add items, tick them off and move them to another category or store. The user connects it by signing in when the assistant asks (a page „Zugriff erlauben?“ with „Erlauben“ and „Ablehnen“) or with an access key made in the app, which is shown once. After „Erlauben“ the page shows „Verbunden“ and „Fertig, du kannst zu Claude zurückkehren.“ (EN: "Connected", "Done, you can return to Claude.") while the assistant finishes connecting (Claude takes up to about 10 seconds). Asked what's on the list, the assistant also gets how many items are open on the whole list and how many were ticked in the last 24 hours. An amount written before or after the item, like „2 Gurken“ or „Gurken 3“, becomes the amount; numbers that belong to the name stay in it („Windeln Größe 4“, „Büroklammern 100“). In the app the user sees the address, the keys and the connected assistants, and can revoke or disconnect any of them at once. Each connected assistant shows where it was approved, like „Chrome · macOS“, when it was connected and when it was last active; a tap on it explains in plain words what it may do, with the button to disconnect it. A short text under „Zugriffstoken“ says that a token lets you build your own automations that manage the list. Nothing needs Premium today. Setup guide: hummlist.com/de/anleitungen/claude (EN /en/guides/claude).

**How to get there.**
1. Open „Mehr“ (EN: "More") and tap „Zugänge“ (EN: "Access").
2. Copy the server address under „MCP-Server“ (EN: "MCP server"): https://mcp.hummlist.com.
3. In the assistant, add a connector with that address and sign in, or tap „Token erstellen“ (EN: "Create token"), name it and copy the key once.
4. To end access: the bin icon „<Name> widerrufen“ (EN: "Revoke <name>") then „Widerrufen“, or „<App> trennen“ (EN: "Disconnect <app>") then „Trennen“.

**Never claim.**
- That it needs Premium (it is free, also after Premium launches).
- That the assistant sees more than the list (it reads and changes shopping items, categories and stores only).
- That a key can be viewed again after creation (shown once).
- That Hummlist knows where an assistant is used or tracks its location: it only keeps the browser and system name of the page where the user approved it (gone once disconnected); „Zuletzt aktiv“ is the day of the assistant's last sign-in refresh, not of every request.
- That ended keys are deleted at once (the record stays 30 days, then a daily clean-up deletes it; the key itself stops working immediately).
- Any specific assistant as officially supported or tested (Claude and ChatGPT are named in the app text; ChatGPT needs a Business or Enterprise workspace).

**Unverified.** The third-party connector screens of Claude and ChatGPT.

**Held: the Hummlist API.** Built but switched off for everyone: the app hides it (job 73, PostHog flag `public-api`) and the server refuses keys and requests (job 75, server switch `public_api`). When it is on, Zugänge gets a section „API“ with an address, a link „API-Dokumentation“ and the button „API-Schlüssel erstellen“ (EN "Create API key"): the user names the key, picks „Nur lesen“ or „Lesen und schreiben“ (EN "Read only", "Read and write") and copies it once. Scripts and automations then read and change the list over HTTP. Do not announce it until Hummlist Launch says so. Never claim it today, nor a short address like api.hummlist.com (none exists).

**Last verified.** job/80-polish-access-tips-account, 2026-11-02 (CET), the connected-app row, details sheet and token hint by the widget tests and e2e/tests/mcp.spec.ts on the web build. job/73-public-api, 2026-11-02 (CET), the API section driven on the web build with the flag forced on (verify-hummlist); the rest main aa339cc, 2026-11-02 (CET), from code on main and driven on the web build; the page after „Erlauben“ by the e2e specs. Recipe: [ai-assistants.md](./ai-assistants.md).

## Siri

**What it does.** On an iPhone the user can add things to the Hummlist by voice: they say a sentence like „Milch, zwei Gurken und Klopapier“, Hummlist splits it into items, files each under a category and Siri reads back „Hinzugefügt: Milch, 2 Gurken, Klopapier.“ An amount said after the item counts too, as a word or digits: „Möhren zwei“ adds 2 Möhren, „Eier dreißig“ 30 Eier. Today this works with a Shortcut the user sets up once (about five minutes, German only). Siri without any setup (iOS 17 and newer, German and English, also reads the list aloud) is built but its announcement is held until Hummlist Launch.

**How to get there.**
1. Open „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Token erstellen“ (EN: "Create token"), name it Siri, copy the key once.
2. In Apple's Shortcuts app build a shortcut called „Einkaufsliste“ (dictate text, send to Hummlist, speak the answer). The step-by-step guide is on hummlist.com: „Hummlist per Siri: Kurzbefehl einrichten“ (EN: "Hummlist with Siri (German only for now)").
3. Say „Hey Siri, Einkaufsliste“, then the items.

**Never claim.**
- That Siri works without setup as a released feature (held until Hummlist Launch).
- That it works on Apple Watch, AirPods or CarPlay (untested), or Android, or in the browser.
- That English sentences are split correctly through the Shortcut (German only).
- That it needs Premium (it is free, also after Premium launches).
- That the voice microphone in the app works on the web (iOS and Android apps only).

**Unverified.** Real Siri voice on a device; the Shortcut on current iOS versions. Siri without setup in German: the first device test (2 Nov 2026) only opened the app; the fix (Siri now also takes the name as „Hummliste“, and sentences like „Füge etwas zur Hummlist hinzu“) waits for the next device test.

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and the Shortcut's server answers driven against the web build's local stack (verify-hummlist); Siri itself needs an iPhone. Recipe: [siri.md](./siri.md).
**Last verified.** job 68 branch, 2026-11-02 (CET), from code and unit tests (`supabase/functions/alexa`, `supabase/functions/voice`); main 1b6d204, 2026-11-01 (CET), from code on main. Recipe: [siri.md](./siri.md).
**Last verified.** PR #194 (job 71), 2026-11-02 (CET): the German native-Siri request driven against the web build's local stack (e2e `voice.spec.ts`) and the iOS build's Siri training read from CI; Siri itself needs an iPhone. Recipe: [siri.md](./siri.md).
**Last verified.** job/89-fix-voice-quantity-words, 2026-11-03 (CET), from the voice function on a local stack (split-only and add, German and English) and the splitter, handler, Alexa handler and add-path tests; dictation itself needs a phone, Alexa a device. Recipe: [siri.md](./siri.md).

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

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and by the app's widget tests (native widgets need a device). Recipe: [home-widgets.md](./home-widgets.md).

## Alexa skill (beta)

**What it does.** With the Hummlist skill a household member can say „Alexa, sag Hummlist, füg Milch und Eier hinzu“; the items land on the shared list, sorted by category, and Alexa says „Ich habe Milch und Eier auf die Hummlist gesetzt.“ What is open already it names in one sentence: „Schon auf der Hummlist: Milch.“ „Alexa, frag Hummlist, was auf der Liste steht“ reads the open items (up to ten, then „und N weitere“). The skill is in beta, German only, and not yet certified by Amazon, so it is not for everyone.
**What it does.** With the Hummlist skill a household member can say „Alexa, sag Hummlist, füg Milch und Eier hinzu“; the items land on the shared list, sorted by category, and Alexa says „Milch und Eier sind auf der Hummlist.“ „Alexa, frag Hummlist, was auf der Liste steht“ reads the open items (up to ten, then „und N weitere“). On an Alexa device set to English it understands „Alexa, ask Hummlist to add milk and eggs“ and „Alexa, ask Hummlist what's on the list“ and answers in English ("I put milk and eggs on Hummlist."). The skill is in beta and not yet certified by Amazon, so it is not for everyone.

**How to get there.**
1. Ask for a beta invitation (the link comes from Peter, who needs the email address of your Amazon account); accept it.
2. In the Alexa app open the skill „Hummlist“ and tap „Zur Verwendung aktivieren“.
3. Sign in to Hummlist and tap „Erlauben“ on the page „Zugriff erlauben?“ (it names „Amazon Alexa“). The page then says „Verbunden“ (EN "Connected") until the Alexa app takes over.
4. Say „Alexa, sag Hummlist, …“ (EN: "Alexa, ask Hummlist to …", "Alexa, tell Hummlist …", "Alexa, open Hummlist") (for example „… ich brauche Milch“, „… füge Milch hinzu“, „… setz Milch drauf“), „Alexa, frag Hummlist, …“ or „Alexa, öffne Hummlist“. The name works best said clearly in two syllables, „Humm-list“. To end it: Hummlist → „Mehr“ (EN: "More") → „Zugänge“ (EN: "Access") → „Amazon Alexa trennen“ (EN: "Disconnect Amazon Alexa") → „Trennen“, or disable the skill in the Alexa app. Disabling the skill also removes „Amazon Alexa“ from Zugänge. A connection nobody used for 12 months is removed, Zugänge entry included.

**Never claim.**
- That the skill is certified, in the public Alexa Skill Store, or available to everyone.
- That it speaks any language besides German and English, or that everyone can find it in the Skill Store (it is listed for every country only once certified).
- That it needs Premium (it is free, also after Premium launches).
- That it works for ticking items off or moving them (add and read only).
- That „Alexa, setz Milch auf die Hummlist“ (EN "Alexa, add milk to Hummlist") works: without „sag/frag/öffne Hummlist“ ("ask/tell/open Hummlist") Alexa's own lists take the sentence.
- Exact deletion periods beyond what the privacy policy says (its wording waits for Peter's approval).

**Unverified.** Real Alexa voice, the Alexa app screens and the beta invitation flow (no device or Amazon account here).

**Last verified.** main aa339cc, 2026-11-02 (CET), from code on main and by the e2e specs on the web build (a real Alexa device is needed for the voice). Recipe: [alexa.md](./alexa.md).
**Last verified.** job 68 branch, 2026-11-02 (CET), from code and unit tests (`supabase/functions/alexa`, `supabase/functions/voice`); main 1b6d204, 2026-11-01 (CET), from code on main. Recipe: [alexa.md](./alexa.md).
**Last verified.** job/69-alexa-icon-invocation, 2026-11-02 (CET), from the code and the skill package tests (sample utterances, guide phrasings), and the shared splitter live on the local stack (a real Alexa device is needed for the voice and the icon in the Alexa app). Recipe: [alexa.md](./alexa.md).
**Last verified.** job/72-alexa-data-cleanup 29e1784, 2026-11-02 (CET), from code and by the e2e specs on the web build (a real Alexa device is needed for the voice). Recipe: [alexa.md](./alexa.md).
**Last verified.** job/89-fix-voice-quantity-words, 2026-11-03 (CET), from the voice function on a local stack (split-only and add, German and English) and the splitter, handler, Alexa handler and add-path tests; dictation itself needs a phone, Alexa a device. Recipe: [alexa.md](./alexa.md).

## Hummlist Premium (held)

**What it does.** Premium is not on sale yet and nothing in the app is gated by it: Siri, Alexa and AI assistants work for everyone. The app has a „Hummlist Premium“ page that explains Premium will unlock these connections for the whole household, with two lines: „Siri auf dem iPhone“ (EN: "Siri on iPhone") and „KI-Assistenten wie ChatGPT oder Claude (MCP)“ (EN: "AI assistants like ChatGPT or Claude (MCP)"). Today it says Premium is bought in the iPhone or Android app (web) or „bald verfügbar“ (phone apps); there are no prices or buy buttons. Households the team has gifted Premium (for example testers) see „Hummlist Premium geschenkt“ (EN: "Hummlist Premium, a gift"), or with an end date „Hummlist Premium geschenkt bis …“ (EN: "Hummlist Premium, a gift until …"; for testers the date is 1 January 2100), and they see the row „Hummlist Premium“ in Mehr.

**How to get there.** Not from Mehr before the launch: the row „Hummlist Premium“ shows only for households that have Premium (testers). The page opens from its link.

**Never claim.**
- That Premium can be bought, or any price, plan or discount (yearly and Lifetime are planned, not for sale).
- That Siri, Alexa or AI assistants need Premium today (they do not), or that Alexa ever will (the skill stays free).
- That Google Assistant or Apple Watch exist (the page says only "later").
- That there is a free trial.
- That Mehr shows Hummlist Premium to everyone (it does once Premium is on sale).

**When it goes on sale.** Nothing changes for users until Peter's go; the switches and their order are in `docs/PAYWALL_RELEASE.md`. Write launch copy from `docs/PURCHASES.md`, not from this section.

**Unverified.** Real store purchases (no store sandbox here); whether the analytics event for the paywall ever fires in production (it should not).

**Last verified.** job/72-alexa-data-cleanup, 2026-11-02 (CET), from code and the app tests (Alexa removed from the card and the hint); the Mehr row without hint: job/85-more-menu-mp2, 2026-11-02 (CET), `purchases.spec.ts`. Recipe: [premium.md](./premium.md).
