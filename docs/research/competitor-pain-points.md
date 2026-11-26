# Grocery-list app pain points, mapped to Snacklist's enabled features

Research job 455, 26 November 2026. Every source below was fetched on 26 Nov 2026 unless marked otherwise.
Scope: what users of Bring!, AnyList, OurGroceries, Listonic, Out of Milk and Apple Reminders' grocery list
complain about and praise, and what that means for the parts of Snacklist that are switched on for users today.
History („Verlauf“), the grocery log, trip mode, prices, learned order, push, Home Screen widgets, native Siri and
everything else behind an off flag or an unreleased hold are out of scope (`releases/flags.json` on main at
86b46eb7a). This report recommends nothing for them and does not describe them as available.

## 1. Method and sources

### 1.1 App Store reviews (primary, 5,536 reviews)

Apple's public customer-review feed, one JSON page per storefront, sort order and page:
`https://itunes.apple.com/<cc>/rss/customerreviews/page=<n>/id=<app id>/sortby=<mostrecent|mosthelpful>/json`.
Pages were fetched on 26 Nov 2026 between 10:17 and 10:38 CET for:

| App | App Store id | Reviews in the corpus |
| --- | --- | --- |
| Bring! Einkaufsliste | 580669177 | 1,665 (DE 731, CH 478, AT 456) |
| OurGroceries | 325851015 | 1,350 (US 578, CA 305, AU 233, GB 173, DE 61) |
| AnyList | 522167641 | 1,291 (US 491, CA 349, GB 260, AU 138, DE 53) |
| Out of Milk | 564974992 | 939 (US 736, CA 203) |
| Listonic | 331302745 | 291 (US 200, CH 50, AT 41) |

Every review quoted below names the exact feed page it came from. 1,993 of the reviews are from 2025 or 2026. The
feed got throttled during the run: later requests returned empty pages for most apps, so the corpus is what came
back before that, not every page. The scripts that fetch the pages, dedupe them and search them by theme are in the
job directory (`~/groceries-ops/jobs/455-competitor-pain-points/research/`), so the counts can be rerun. The raw
review text is not committed to this public repo.

Theme volume (reviews rated 1 to 3 stars since 1 Jan 2024, n = 437, matched by German and English keywords). Keyword
matching overcounts: the "disappear" keywords also hit reviews about ads that "disappear" from view. Read this table
as relative volume, not as a measurement. Every claim in section 2 rests on the quoted reviews, not on these counts.

| Theme | Hits | Mostly from |
| --- | --- | --- |
| Ads, offers, clutter | 137 | Bring! 64, Out of Milk 29, OurGroceries 27 |
| Sharing, partner, family | 89 | Bring! 36, Out of Milk 29 |
| Sorting, categories, store order | 62 | Out of Milk 29, Bring! 20 |
| Updates or redesigns that broke habits | 58 | Out of Milk 28, Bring! 13 |
| Items or lists disappearing, sync failures | 42 | Bring! 18, Out of Milk 13 |
| Subscription and price | 41 | Bring! 24 |
| Voice (Siri, Alexa) | 28 | Bring! 14, OurGroceries 8 |
| Account and sign-in | 26 | Bring! 10, Out of Milk 9 |

### 1.2 Store pages, press and forums (fetched pages)

- App Store review pages: `https://apps.apple.com/{de,at,ch,us,gb}/app/bring-einkaufsliste-rezepte/id580669177?see-all=reviews`,
  `https://apps.apple.com/{de,at,us,gb,ca}/app/die-einkaufsliste-listonic/id331302745?see-all=reviews`.
- Review aggregators: https://justuseapp.com/en/app/580669177/bring-shopping-list-recipes/reviews ,
  https://justuseapp.com/en/app/331302745/listonic-grocery-shopping-list/reviews , https://ie.trustpilot.com/review/listonic.com ,
  https://www.trustpilot.com/review/getbring.com
- German press with reader comments: iphone-ticker.de (articles 129909, 134250, 140176, 143130, 153319, 155218,
  214519, 250765, 277882, 289020, 70591; full URLs at each quote), https://www.mobiflip.de/bring-vom-prospekt-direkt-auf-die-einkaufsliste/ ,
  https://www.mobiflip.de/shortnews/bring-einkaufsliste-premium/amp/ , https://www.appgefahren.de/?p=300569 ,
  https://www.giga.de/tech/nie-wieder-was-vergessen-top-einkaufslisten-apps-fuer-android-und-iphone-im-vergleich--01J5QMHF97XJN7GJT2YT8X9Q8B ,
  https://www.heise.de/tipps-tricks/Einkaufslisten-Apps-im-Ueberblick-4883163.html ,
  https://www.inside-digital.de/news/einkaufslisten-app-listonic-ki-funktion-supermarkt ,
  https://www.netzwelt.de/news/258465-einkaufsliste-zwischen-android-iphone-teilen-so-klappt-familie.html ,
  https://www.pctipp.ch/praxis/apple/zickzack-kurs-im-supermarkt-2920767.html ,
  https://www.smarthomeassistent.de/amazon-alexa-einkaufsliste-erhaelt-ein-relativ-nutzloses-update/ ,
  https://t3n.de/news/amazon-alexa-verliert-beliebte-funktion-einkaufsliste-1627716/
- Apple Community (German): https://communities.apple.com/de/thread/255570466 , https://communities.apple.com/de/thread/255369917 ,
  https://communities.apple.com/de/thread/255151392 , https://communities.apple.com/de/thread/256298512
- Forums: https://talk.macpowerusers.com/t/grocery-list-not-working-in-ios17/34830 ,
  https://talk.macpowerusers.com/t/reminders-turn-off-sections/38160 ,
  https://community.home-assistant.io/t/i-asked-my-hermes-to-made-alexa-a-shopping-list-inbox-because-amazon-improved-alexa-again/1025523
- Official help: https://support.apple.com/en-us/105086 (Reminders groceries list), https://help.anylist.com/articles/siri/ ,
  https://help.anylist.com/articles/alexa-issue-early-2026/
- Press (English): https://www.idownloadblog.com/2022/10/17/siri-grocery-list/ ,
  https://9to5google.com/2026/08/25/google-home-keep-integration-broken-due-to-bug/

Five quotes from these pages were checked a second time with a plain HTTP fetch on 26 Nov 2026 (iphone-ticker 214519 and
155218, mobiflip, Apple Community 255570466, App Store CH Bring!). All five are on the live pages.

### 1.3 What could not be fetched (no claims taken from them)

- **Reddit.** reddit.com and old.reddit.com, including the `.json` endpoints, answer this runner with HTTP 403
  "blocked due to a network policy". The page-fetch tool refuses the domain too. So the report has **no Reddit
  evidence**. Claims seen only in search-result snippets are left out.
- **Google Play reviews.** They load by JavaScript, and the fetched HTML held no review text.
- MacRumors forums (403). English discussions.apple.com threads redirect to support.apple.com. ask.metafilter.com
  serves a Cloudflare challenge. Apple support page 120616 served a generic table of contents.
- No respected UX write-up (for example Nielsen Norman Group) on grocery-list apps specifically turned up. So the
  report rests on user reviews, forums and press, and has no UX-authority sources.

### 1.4 Snacklist's side

What Snacklist does today comes from `.cursor/skills/verify-snacklist/features/FEATURES-FOR-WRITERS.md` (sections last
verified 23 to 26 Nov 2026), the per-feature files in that folder, `releases/flags.json` and `docs/DECISIONS.md`, all
on main at 86b46eb7a. Nothing in the app was driven for this report. No claim here depends on new app behaviour.

## 2. Recurring pain points, by theme

Quotes are verbatim and cut with "…". Reviewer names are left out. "Feed" means the App Store review feed page given.

### 2.1 Ticking: an accidental tap takes an item off the list

This is the most consistent complaint across apps that tick with a single tap, and it shows up in German and
English reviews. People don't mind ticking with a tap. They mind losing track of what they ticked by mistake.

- Bring! (CH, 3★, 22 Nov 2025): „…dass ich versehentlich einen Artikel angeklickt habe und er dadurch im Ordner ‚Zuletzt verwendet‘ gelandet ist. Das ist ärgerlich, wenn man es erst zu Hause bemerkt.“ Feed: https://itunes.apple.com/ch/rss/customerreviews/page=3/id=580669177/sortby=mosthelpful/json
- Bring! (AT, 5★, 9 Jul 2026): „ein Rückgängig-button wäre hilfreich wenn man versehentlich was als ‘gekauft’ listet, weiß man nicht mehr was es ursprünglich war“ Feed: https://itunes.apple.com/at/rss/customerreviews/page=1/id=580669177/sortby=mosthelpful/json
- Bring! (DE, 5★, 24 May 2026), title „Artikel aus Versehen gelöscht“: „Wenn man viele Artikel in der Liste hat, kann es leicht passieren, dass man aus Versehen auf einen anderen Artikel kommt…“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=4/id=580669177/sortby=mosthelpful/json
- Bring! (CH, 4★, 25 Jul 2025): „…dass es so leicht geschieht etwas versehentlich zu löschen. Wir fänden eine Lösung mit swipen zum Löschen besser.“ Feed: https://itunes.apple.com/ch/rss/customerreviews/page=4/id=580669177/sortby=mosthelpful/json
- OurGroceries (GB, 4★, 30 Apr 2026): "I often get home and find I’ve accidentally ticked off items I haven’t actually purchased which is frustrating." Feed: https://itunes.apple.com/gb/rss/customerreviews/page=1/id=325851015/sortby=mosthelpful/json
- OurGroceries (US, 3★, 10 Jun 2026): "it’s too easy to accidentally cross off an item… Would be nice to be able to undo last action" Feed: https://itunes.apple.com/us/rss/customerreviews/page=2/id=325851015/sortby=mosthelpful/json
- OurGroceries (US, 4★, 20 Oct 2025): "putting the phone in a pocket and taking it out again, it can be too easy to accidentally take things off… Fortunately, the items most recently removed are at the top of the “removed” list" Feed: https://itunes.apple.com/us/rss/customerreviews/page=6/id=325851015/sortby=mostrecent/json
- Out of Milk (US, 3★, 29 Dec 2024): "Sometimes I inadvertently check off an item, and it disappears from my list. I see it happen, but it’s so fast I can’t see which item." Feed: https://itunes.apple.com/us/rss/customerreviews/page=10/id=564974992/sortby=mostrecent/json
- AnyList (CA, 5★, 23 Nov 2026): "Only wish it had an undone feature as I’ve accidentally deleted items on my list." Feed: https://itunes.apple.com/ca/rss/customerreviews/page=1/id=522167641/sortby=mostrecent/json
- Praise for the opposite, OurGroceries (US, 5★, 3 Feb 2026): "The optional swipe feature prevents me from inadvertently crossing off items on my list just by touching them." Feed: https://itunes.apple.com/us/rss/customerreviews/page=1/id=325851015/sortby=mosthelpful/json
- Praise for ticked items vanishing at once, Listonic (DE, 1 Jun 2025): „Beim Einkauf ist es super, dass die Produkte die man ankreuzt gleich verschwinden“ https://apps.apple.com/de/app/die-einkaufsliste-listonic/id331302745?see-all=reviews

### 2.2 Sorting: the list doesn't follow my store, and I can't fix it

- Bring! (appgefahren reader, 11 May 2021): „die reihenfolge meines einkaufs kann ich immer noch nicht bestimmen“ https://www.appgefahren.de/?p=300569
- Bring! (mobiflip readers, 27 May 2026): „Ich warte viel mehr darauf, dass man endlich eigene Kategorien hinzufügen kann“, and a workaround: „So habe ich jetzt Tiefkühlprodukte aus den letzten beiden Reihen unter Tierprodukte eingepflegt“ https://www.mobiflip.de/bring-vom-prospekt-direkt-auf-die-einkaufsliste/
- Bring! (US, 15 Jan 2023): "My biggest pet peeve is having to change the category of an item on the list" https://apps.apple.com/us/app/bring-shopping-list-recipes/id580669177?see-all=reviews
- Listonic (GB, 22 Oct 2023): "Latest update seems to keep the custom sort order in place, this hasn't worked for me for years." https://apps.apple.com/gb/app/id331302745?see-all=reviews
- Apple Reminders: "Apples went to Snacks instead of “fruit/vegetables”" (19 Sep 2023), and in German: "Doesn’t seem to be working for me in german, despite setting the correct list type" (19 Sep 2023). https://talk.macpowerusers.com/t/grocery-list-not-working-in-ios17/34830
- Apple Reminders, sections in the way: "The sections in the Groceries reminders take up room…" (18 Aug 2024) https://talk.macpowerusers.com/t/reminders-turn-off-sections/38160
- Picking shop and category for every item is too much work (iphone-ticker reader, 12 May 2026): „musste jedesmal das Geschäft und die Kategorie auswählen. Viel zu umständlich.“ https://www.iphone-ticker.de/meinkaufen-app-will-einkaufslisten-einfacher-verwalten-277882/
- The same thread on store order as the most useful feature: „Mir hilft diese Funktion am allermeisten, da ich so nicht ziellos durch den Markt rennen muss“ (12 May 2026).
- OurGroceries (AU, 2★, 14 May 2026): "recent updates seem to have made it impossible to leave my list uncategorised." Feed: https://itunes.apple.com/au/rss/customerreviews/page=1/id=325851015/sortby=mostrecent/json

### 2.3 Sharing: sync that lags or fails means buying twice

- AnyList (US, 2★, 25 Jul 2026): "This results in duplicate purchases and wasted money: Purchased items are crossed off the list on one phone but still appear as unpurchased on the other." Feed: https://itunes.apple.com/us/rss/customerreviews/page=5/id=522167641/sortby=mostrecent/json
- Out of Milk (US, 2★, 23 May 2026): "the failure to sync reliably is not acceptable anymore. It’s literally the only thing this list needs to be able to do well." Feed: https://itunes.apple.com/us/rss/customerreviews/page=9/id=564974992/sortby=mosthelpful/json
- Out of Milk (US, 2★, 17 Aug 2026): "my partner has an android… It’s gotten to the point we have to screenshot our list to see if they’re matching up." Feed: https://itunes.apple.com/us/rss/customerreviews/page=2/id=564974992/sortby=mostrecent/json
- Apple Reminders (Apple Community DE, 10 Apr 2024): „Leider wird alles was sie der Liste hinzufügt bei mir erst wenn überhaupt Tage oder Wochen später angezeigt.“ https://communities.apple.com/de/thread/255570466
- Apple Reminders (Apple Community DE, 26 Dec 2023): „In einer geteilten Erinnerung Einkaufsliste sind nur meine eigenen Einträge sichtbar…“ https://communities.apple.com/de/thread/255369917
- Mixed iPhone and Android households: „Denn Apples Erinnerungen-App hilft euch in diesem Fall nicht weiter.“ (netzwelt, 13 Sep 2026) https://www.netzwelt.de/news/258465-einkaufsliste-zwischen-android-iphone-teilen-so-klappt-familie.html
- Generic shared list (iphone-ticker reader, 14 May 2026): „Leider hängt die Synchronisierung ziemlich hinterher und dann ist immer alles doppelt im Einkaufswagen.“ https://www.iphone-ticker.de/meinkaufen-app-will-einkaufslisten-einfacher-verwalten-277882/
- Inviting is too hard. Listonic (CH, 1★, 8 Oct 2024), title: „Viel zu kompliziert um die Familie einzuladen“ Feed: https://itunes.apple.com/ch/rss/customerreviews/page=1/id=331302745/sortby=mostrecent/json
- Email invites failing (iphone-ticker reader, 25 Oct 2026): „Bei mir funktionierte nur leider das Einladen von Familienmitgliedern per Email nicht“ https://www.iphone-ticker.de/von-uns-fuer-euch-kaufo-bringt-einkaufszettel-aufs-iphone-289020/
- Who added it? OurGroceries (US, 4★, 23 Jul 2023): "I always have to group text questions about the list because I don’t know who added it." Feed: https://itunes.apple.com/us/rss/customerreviews/page=1/id=325851015/sortby=mosthelpful/json . Also OurGroceries (US, 5★, 25 Apr 2024): "add a field to identify who added things to the list" Feed: https://itunes.apple.com/us/rss/customerreviews/page=2/id=325851015/sortby=mosthelpful/json
- Praise: Bring!'s fast household sync is the main thing people like. „Insbesondere die gemeinsame Nutzung der App funzt perfekt, innerhalb von Sekunden..“ (15 Aug 2018) https://www.iphone-ticker.de/einkaufsliste-bring-akzeptiert-jetzt-siri-befehle-129909/

### 2.4 Clutter: offers, recipes, badges and nags around the list

This is the biggest theme for Bring! in German-speaking stores, and a recurring reason for switching apps.

- „durch die ganze Werbung (Prospekte, Einkaufstipps usw.) ist es leider nicht mehr benutzbar geworden“ (16 Apr 2019) https://www.iphone-ticker.de/einkaufsliste-bring-die-industrie-zahlt-mehr-als-der-nutzer-140176/
- „die Werbung war allerdings so nervig das ich zu SmartList gewechselt bin.“ (24 Mar 2020) https://www.iphone-ticker.de/einkaufsliste-bring-jetzt-mit-premium-abo-155218/
- Bring! (DE, 1★, 1 Sep 2026): „Dennoch ist eine Werbekachel "aus Versehen" in die Liste gerutscht und wurde dann eingekauft.“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=2/id=580669177/sortby=mostrecent/json
- Bring! (CH, 4★, 30 Mar 2024): „…die penetranten Migros Aktionsvorschläge, die immer dann dazwischengrätschen, wenn wir einen Artikel präzisieren wollen.“ Feed: https://itunes.apple.com/ch/rss/customerreviews/page=6/id=580669177/sortby=mosthelpful/json
- Bring! (DE, 3★, 27 Apr 2024): „Ich benötige nur die gemeinsame Einkaufsliste mit meiner Partnerin… Rezepte und Prospekte in der App brauchen wir nicht“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=4/id=580669177/sortby=mosthelpful/json
- Bring! (DE, 2★, 19 Sep 2026), on rating prompts: „die App nervt mich fast jede Woche und bietet um einen Bewertung im App Store.“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=2/id=580669177/sortby=mostrecent/json
- Badges: „vollgekleistert mit hinweisen und badges“ (11 May 2021) https://www.appgefahren.de/?p=300569
- Listonic (GB): "Full screen annoying ads with invisible closing it’s not what you want when entering the supermarket." https://apps.apple.com/gb/app/id331302745?see-all=reviews
- Paying with data (iphone-ticker reader, 23 Oct 2026): „Mich stört an bring schon lange, dass man ja quasi mit seinen Daten bezahlt und die ganze Werbung darin.“ https://www.iphone-ticker.de/von-uns-fuer-euch-kaufo-bringt-einkaufszettel-aufs-iphone-289020/

### 2.5 Voice: exact phrases, merged or split items, the wrong list

- Bring! with Siri, mishearing: „Mehl wird immer als „Mail“ erkannt“, and with several lists „leider sinnfrei, wenn man mehrere Einkaufslisten hat…“ (14 and 15 Aug 2018) https://www.iphone-ticker.de/einkaufsliste-bring-akzeptiert-jetzt-siri-befehle-129909/
- Bring! with Alexa: „die Integration in Alexa inzwischen leider eine Zumutung ist.“ (blog author, 27 May 2026) https://www.mobiflip.de/bring-vom-prospekt-direkt-auf-die-einkaufsliste/
- Siri merges items: "it often adds them as one entry (cheese bread) instead of two separate entries." https://www.idownloadblog.com/2022/10/17/siri-grocery-list/
- Siri splits one item: "I say “mushroom soup” and Siri adds 2 items" https://help.anylist.com/articles/siri/
- Alexa doesn't split at „und“: „…einfach beim Wörtchen „UND“ zu trennen.“ https://www.smarthomeassistent.de/amazon-alexa-einkaufsliste-erhaelt-ein-relativ-nutzloses-update/
- Siri with two shopping lists asks every time (Apple Community DE, 16 May 2026): „Siri gibt mir dann als Auswahl immer beide.“ https://communities.apple.com/de/thread/256298512
- AnyList has no German Siri (DE, 1★, 12 Jul 2024): „Leider funktioniert die App nicht mit Siri auf Deutsch.“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=1/id=522167641/sortby=mostrecent/json
- Third-party Alexa lists got harder after Amazon ended the list API on 1 Jul 2024: „Beide sind aber mit Unannehmlichkeiten verbunden.“ https://t3n.de/news/amazon-alexa-verliert-beliebte-funktion-einkaufsliste-1627716/
- Praise: „Bring lässt sich per Alexa befüllen, der große Vorteil in der Küche!“ (11 Feb 2020) https://www.iphone-ticker.de/einkaufslisten-hngry-update-und-leser-geheimtipp-pon-153319

### 2.6 Notifications: too many, or the wrong kind

- Apple Reminders, a push for every addition (iphone-ticker readers, 10 Jun 2023): „Ständig wird man benachrichtigt, fügt wer etwas hinzu und das brauchen wir wirklich mal gar nicht.“ and „seit dem ist die Erinnerungen-App als Einkaufsliste unbrauchbar.“ https://www.iphone-ticker.de/neu-in-ios-17-intelligente-einkaufslisten-automatisch-sortiert-214519/
- Bring! marketing pushes: „Bei mir kam ab und zu „Zeit mal wieder was einzukaufen“ und ähnliches.“ (16 Apr 2019) https://www.iphone-ticker.de/einkaufsliste-bring-die-industrie-zahlt-mehr-als-der-nutzer-140176/
- The other side, Listonic (US, 25 Oct 2019): "We love the fact that if one of us adds or checks off an item we’re all notified." https://apps.apple.com/us/app/-/id331302745?see-all=reviews

### 2.7 Adding items: catalog language and quick re-adding

- Catalog in the wrong language or dialect. AnyList (GB, 4★, 24 Jan 2016): "A British English dictionary for the autocompletion would be a welcome future update though , e.g. 'Coriander' is missing" Feed: https://itunes.apple.com/gb/rss/customerreviews/page=8/id=522167641/sortby=mosthelpful/json . AnyList (DE, 4★, 20 Mar 2019): "Anything on my list is in the category „other“ because it is in german." Feed: https://itunes.apple.com/de/rss/customerreviews/page=1/id=522167641/sortby=mostrecent/json
- Quick re-adding is praised. Bring! readers: „In Bring tippe ich weniger und kann einfach aus der Liste meiner Letzten Artikel per Tipp…“ (11 Feb 2020) https://www.iphone-ticker.de/einkaufslisten-hngry-update-und-leser-geheimtipp-pon-153319
- Re-finding a ticked item: several OurGroceries and Out of Milk reviewers want the crossed-off list alphabetical "Otherwise it’s hard to find them to add back to the list" (OurGroceries US, 5★, 8 Apr 2025). Feed: https://itunes.apple.com/us/rss/customerreviews/page=9/id=325851015/sortby=mostrecent/json
- Quantities and pack sizes. OurGroceries (US, 3★, 10 Jun 2026): "I wish this app had fields for volume/weight for items" Feed: https://itunes.apple.com/us/rss/customerreviews/page=2/id=325851015/sortby=mosthelpful/json . iphone-ticker reader (13 May 2026): „Was mir aber fehlt, sind Mengenangaben und Verpackungsmaterial.“ https://www.iphone-ticker.de/meinkaufen-app-will-einkaufslisten-einfacher-verwalten-277882/
- Someone else already added it. Listonic (DE, 29 Apr 2023): „fehlt der Hinweis, dass eine andere Person das entsprechende Produkt schon hinzugefügt hat“ https://apps.apple.com/de/app/die-einkaufsliste-listonic/id331302745?see-all=reviews

### 2.8 Onboarding and accounts

- Bring! needs an account to sync: „ein Online-Konto anlegen oder euch mit eurem Google- beziehungsweise Facebook-Konto anmelden“ (giga, 2 Apr 2026). The same article on Listonic: it „etwas aufdringlich zu einer Registrierung für 10,99 Euro drängt“. https://www.giga.de/tech/nie-wieder-was-vergessen-top-einkaufslisten-apps-fuer-android-und-iphone-im-vergleich--01J5QMHF97XJN7GJT2YT8X9Q8B
- Bring! (DE, 1★, 24 Apr 2025): after reinstalling, registering again failed: „…muss man sich noch mal registrieren… und das hat bei mir nicht geklappt.“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=10/id=580669177/sortby=mostrecent/json

### 2.9 Accessibility

- Bring! (DE, 1★, 8 Dec 2025): „Die Bedienung mit dem Screen Reader VoiceOver auf dem iPhone ist nur eingeschränkt möglich. Selbst grundlegende Schaltflächen sind unzureichend besch[riftet]…“ Feed: https://itunes.apple.com/de/rss/customerreviews/page=3/id=580669177/sortby=mosthelpful/json

### 2.10 Pricing (context only, no recommendation)

- Bring! Premium can't be shared with the household: „Die InApp Käufe können nicht geteilt werden. Das ist dämlich“ (24 Mar 2020) https://www.iphone-ticker.de/einkaufsliste-bring-jetzt-mit-premium-abo-155218/
- Ads come back after paying. Listonic (DE, 14 Dec 2022) „habe ich jetzt wieder Werbung“ https://apps.apple.com/de/app/die-einkaufsliste-listonic/id331302745?see-all=reviews ; Listonic (CH, 1★, 6 Aug 2026): „obwohl ich ein premium abo habe, wird jedesmal Werbung eingeblendet“ Feed: https://itunes.apple.com/ch/rss/customerreviews/page=1/id=331302745/sortby=mostrecent/json

## 3. Themes mapped onto Snacklist's enabled features

"Today" means what FEATURES-FOR-WRITERS.md and the feature files describe for users (flags at `full` or without a flag).

| Theme | What Snacklist does today | Verdict |
| --- | --- | --- |
| Accidental tick (2.1) | A tap anywhere on a row ticks it. The row strikes through and slides away in under 0.5 s, then the snackbar „Abgehakt: <Name>“ with „Rückgängig“ names the item and takes the last tick back (Peter's CP1, 26 Nov 2026, job 471; from 29 Oct, DECISIONS job 29b, until then a tick showed nothing). The item goes to „Zuletzt verwendet“ at the bottom of the list, newest first; a tap there puts it back without a message, the fallback once the snackbar is gone. (`tick-and-undo.md`) | **Closed by CP1.** The Bring! review from 22 Nov 2025 describes the old pattern, including the section name. The snackbar now names the item and offers Undo for a few seconds; later, recovery still sits at the end of the list. |
| Store order (2.2) | One section per store in the household's order, with items in a researched walk order and no headings (categories hidden for everyone since 22 Nov). Users can reorder, add and rename stores in „Anpassen“ and move an item to another store. Within a store nothing moves: no drag on the list, no category picker in the edit sheet. (`stores-walk-order.md`, `categories.md`) | **Strength with one gap.** Store-first sorting answers the top German wish, and hiding categories removes the Reminders-style "wrong section" noise. A misplaced item can't be moved within its store, which is Bring!'s „Reihenfolge kann ich nicht bestimmen“. |
| Sync and double buying (2.3) | Changes show on other phones within a couple of seconds. New items from others are highlighted with „1 neu von Noah Brandt“. Offline edits sync later, and „Sync gestört“ shows server trouble. iPhone, Android and web. (`live-sync.md`, `offline.md`) | **Strength.** Keep it the thing that never breaks. |
| Inviting (2.3) | Link, 8-character code or QR code, shared by the user. Group links for clubs. Joining from a link lands on the shared list. (`household-invites.md`) | **Strength.** No email invites to fail. |
| Who added it (2.3) | The news bar names who added new items while the list is open. The feature map shows no "added by" on a row after that. | **Small gap**, thin evidence (two OurGroceries reviews). |
| Clutter, ads, nags (2.4) | No ads, no offers, no recipes. One tip at most per start and day. The rating prompt at most twice a year. The store-app key and the „… ist erledigt“ card open the matched chain's own app, with no logos (`store-apps.md`). | **Strength**, and already the site's and store listing's message („Gemeinsam einkaufen, ohne Werbung“, `site/content/landing/copy.yml`, `captions.yaml`). The chain-app card is the one surface that resembles Bring!'s retailer tiles. See section 5. |
| Voice (2.5) | Dictation in the phone apps splits „Milch, zwei Gurken und Klopapier“ into three items. Alexa skill (add and read, DE and EN). Siri through a Shortcut, German only, set up once. Each member picks the list voice adds to. (`dictation.md`, `alexa.md`, `siri.md`) | **Strength**: splitting at „und“ and a fixed voice list answer 2.5 directly. The Siri Shortcut's setup is the weak spot, but its successor (native Siri) is held, so it's out of scope here. |
| Notifications (2.6) | None. Push is built but off. | Out of scope. See section 5. |
| Catalog language (2.7) | The catalog is German, and in the English UI „Aus dem Katalog“ rows still show German words (`quick-add.md`). | **Gap for English users only.** The evidence is old (AnyList 2016 to 2020). |
| Quick re-add, quantities, "already on the list" (2.7) | „Wieder fällig“ and „Zuletzt verwendet“ in the empty add sheet, amounts parsed from text, „Eigenschaften“ for details, match rows for items already on the list, „<name> steht schon auf der Liste“. | **Strength.** It answers the quantity wish and Listonic's "someone already added it" complaint. |
| Accounts (2.8) | The guided start runs before the account; answers stay on the device until sign-in. Google, Apple, email and password, or a magic link. | **Neutral.** An account is required, as with Bring!. Setup comes first, so it doesn't feel like a toll. |
| Accessibility (2.9) | Web semantics are tested with Playwright by role and label. Real VoiceOver and TalkBack on phones are not covered in the feature map. | **Unknown** on phones. |

## 4. Ranked UX improvements

Ranked by evidence strength and user impact for the enabled feature set, best first.

### 1. Tell the user what a mistaken tap just ticked

- **Surface.** List (tick), „Zuletzt verwendet“.
- **Why.** The most consistent complaint across five apps (2.1). The Bring! CH review from 22 Nov 2025 describes Snacklist's pattern word for word: a mistaken tap moves the item into „Zuletzt verwendet“, and the user notices at home. Out of Milk: "it’s so fast I can’t see which item." Until 26 Nov 2026 Snacklist showed nothing after a tick, and the only recovery was at the end of the list.
- **Tag.** **decided** (Peter's CP1, 26 Nov 2026: "CP1 yes I guess we can show a snackbar for that with an undo button."). He had removed the tick's undo snackbar on 29 Oct 2026 (DECISIONS job 29b); CP1 picked option (a), a short undo for the last tick only, over (b) naming the item in place and (c) only teaching it.
- **Next step.** Done in job 471: the snackbar „Abgehakt: <Name>“ / "Ticked: <Name>" with „Rückgängig“ / "Undo" after every tick, for the last tick only. „Zuletzt verwendet“ and the hint about it (item 2) remain the fallback once the snackbar is gone.

### 2. Teach where ticked items go

- **Surface.** „Erste Schritte“ card and tips (`listHint` „Tippen hakt ab · Halten bearbeitet“ in `app/l10n/app_de.arb`), and the Hilfe page.
- **Why.** Same evidence as item 1. The recovery path exists, but none of the shown copy says where a ticked item went. OurGroceries users who know about their "removed" list report the mistake as minor (2.1, OurGroceries 20 Oct 2025).
- **Tag.** **simple fix** (copy only). For example, extend the hint with „Vertippt? Unten unter „Zuletzt verwendet“ zurückholen.“ / "Tapped by mistake? Get it back under "Recently used"." Copy follows the hint-outside-controls rule.
- **Next step.** Auto-merge job: ARB strings DE and EN, the tips test, `tips.md` and the FEATURES-FOR-WRITERS "Tips" section in the same PR. It works with any outcome of item 1.

### 3. Let users fix an item's place within a store

- **Surface.** List (walk order inside a store section), edit sheet.
- **Why.** Store order is the most praised organising feature (2.2: „nicht ziellos durch den Markt rennen“), and not being able to set it is a standing Bring! complaint („die reihenfolge meines einkaufs kann ich immer noch nicht bestimmen“, 2021; own categories still wanted in May 2026). Snacklist's researched walk order is a head start. But since categories were hidden on 22 Nov, a misplaced item can't be moved at all: no drag, no category chip, and the only built placement tool sits behind a flag that is off.
- **Tag.** **needs Peter.** Choosing how users correct the order (a small „Platz im Laden“ control in the edit sheet, drag within a store section, or accepting the researched order for now) is a product call that touches his hide-categories pick.
- **Next step.** Question for Peter: accept as is for launch, or which correction model? Then a prototype round. Until then, track feedback notes that mention „Reihenfolge“ or "order" (Feedback & Ideen) to size it.

### 4. Check the screen reader on a real phone

- **Surface.** List, add sheet, edit sheet in the iPhone and Android apps.
- **Why.** A 1★ Bring! review (8 Dec 2025) is about VoiceOver labels (2.9). Snacklist's accessibility is tested on the web build only. The feature map has no VoiceOver or TalkBack pass on a phone.
- **Tag.** **needs Peter** (a real iPhone or Android phone; the runners have no device).
- **Next step.** A 10-minute VoiceOver walk on Peter's phone (add, tick, put back, edit), with findings sent through Feedback & Ideen. Or a TalkBack pass on an emulator job (the Hetzner runner has no KVM, so an emulator pass would run on GitHub Actions).

### 5. Show who added an item, on demand

- **Surface.** Edit sheet („Bearbeiten“).
- **Why.** Two OurGroceries reviews (2023, 2024) ask who added an item, because members have their own brands (2.3). Snacklist names the person only in the live news bar while the list is open.
- **Tag.** **needs design pick** (a muted „Hinzugefügt von Mia“ line in the edit sheet is the least intrusive option, and the row stays as it is).
- **Next step.** Prototype round with the edit sheet only. Confirm first that the item's author is already readable under RLS for the household (it is household data, not a new field).

### 6. English catalog words in the English app

- **Surface.** Add sheet suggestions („Aus dem Katalog“ / "From the catalog") in English.
- **Why.** Catalog words in another language or dialect are a recurring AnyList complaint (UK 2016 and 2020, a German user in 2019; 2.7). Snacklist's English UI suggests German catalog words.
- **Tag.** **needs Peter** (scope: an English catalog is a content project, and the home market is German).
- **Next step.** Question for Peter: is English a launch market for the catalog? If not, leave it and keep the English copy from promising English suggestions.

## 5. What we should not do

- **No offers, flyers, sponsored suggestions or recipe tabs.** This is the loudest German complaint (2.4), and it is Snacklist's stated difference („Gemeinsam einkaufen, ohne Werbung“). The store-app key and the „… ist erledigt“ card with „<App> öffnen“ are the nearest thing Snacklist has to a retailer tile. They stay utility (opening the chain's own app the household matched, no logos, closable, shown only right after the last item of that store is ticked). Never add deals, product promotions or chain-suggested items to them.
- **No push for every addition, and no "time to shop" nudges.** Reminders users called the per-add pushes „unbrauchbar“, and Bring! users turned pushes off because of marketing pushes and lost the useful ones too (2.6). Push is off today and out of scope. On main since #710 (26 Nov) the privacy text for push is live, but both push flags stay off until Legal's enable GO, after which `push-household-add` goes straight to full. The evidence supports keeping it as built, off for each person until they switch it on, with no reminder-style pushes added. This report recommends nothing else for push.
- **No swipe or double tap to tick as a fix for accidental ticks without a Peter pick.** One OurGroceries reviewer praised optional swipe, and others praise one-tap speed (Listonic: „gleich verschwinden“). Snacklist's tap-anywhere tick is a deliberate design (`tick-and-undo.md`: "Swipe does nothing"). Changing the tick gesture would fight it. Item 1 addresses the pain without changing the gesture.
- **Don't bring categories back on the list** to answer the sorting theme. Reminders users complain about sections taking room and wrong sections (2.2), and Peter hid them on 22 Nov. Item 3 asks for a correction tool, not headings.
- **Don't surface off features to answer these themes.** History, trips, prices and totals, learned order, widgets, push and native Siri all touch themes above (re-finding items, store order, notifications, voice). They stay off and unmentioned in copy until their flags or holds change.
- **No AI assistant in place of search.** Listonic users complained when an "AI assistant" replaced the search bar (App Store CA, 9 Aug) https://apps.apple.com/ca/app/shared-grocery-list-listonic/id331302745?see-all=reviews . Snacklist's AI connection lives under Zugänge, away from the add field. Keep it there.
- **No more rating asks.** Bring! asks „fast jede Woche“ and gets 2-star reviews for it (2.4). Snacklist's two asks a year at most is right.
