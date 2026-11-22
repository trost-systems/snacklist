# Job 369: site copy changes

Round 1 (categories, the old add sheet, comparison page):

Old -> new, from the replacement tables (git diff site/ shows each in place).

+++ b/site/content/comparisons/de/einkaufsliste-vergleich-bring.md
-| Gemeinsame Liste | Eine Haushaltsliste, kostenlos, live auf jedem Gerät | „Gemeinsame Einkaufsliste kostenlos“; „Einkaufsliste kostenlos in Echtzeit teilen“ mit Haushalt, WG, Büro |
+| Gemeinsame Liste | Gemeinsame Listen für den Haushalt, kostenlos, live auf jedem Gerät | „Gemeinsame Einkaufsliste kostenlos“; „Einkaufsliste kostenlos in Echtzeit teilen“ mit Haushalt, WG, Büro |
-| Sortierung | Snacklist sortiert deine Artikel automatisch in Kategorien und lernt aus deinen Korrekturen; die Kategorien ordnest du per Drag in der Reihenfolge deines Ladens, pro Laden und für den ganzen Haushalt gemeinsam | Automatisches Gruppieren und Sortieren; Kategorien lassen sich an die Gänge im eigenen Supermarkt anpassen |
+| Sortierung | Snacklist sortiert deine Artikel automatisch nach Laden und in der Reihenfolge, in der du durch den Laden gehst, und merkt sich, in welchen Laden was gehört; die Läden ordnest du per Drag, für den ganzen Haushalt gemeinsam | Automatisches Gruppieren und Sortieren; Kategorien lassen sich an die Gänge im eigenen Supermarkt anpassen |
-| Mehrere Listen | Eine Haushaltsliste | Mehrere Listen |
+| Mehrere Listen | Mehrere Listen pro Haushalt, zum Beispiel Wocheneinkauf und Baumarkt | Mehrere Listen |
-Snacklist sortiert deine Artikel automatisch in Kategorien und lernt aus deinen Korrekturen. Die Kategorien ordnest du pro Laden in der Reihenfolge, in der du durch den Laden gehst. Bring! gruppiert und sortiert automatisch, und du kannst die Kategorien an die Gänge in deinem Supermarkt anpassen. (Quelle: Bring!-Store-Eintrag, Stand 04.11.2026)
+Snacklist sortiert deine Artikel automatisch nach Laden und in der Reihenfolge, in der du durch den Laden gehst, und merkt sich, in welchen Laden was gehört. Bring! gruppiert und sortiert automatisch, und du kannst die Kategorien an die Gänge in deinem Supermarkt anpassen. (Quelle: Bring!-Store-Eintrag, Stand 04.11.2026)
-Bei Rezepten, saisonalen Vorschlägen, Angeboten und Prospekten, Kundenkarten, mehreren Listen und eigenen Fotos an Artikeln. Außerdem ist Bring! öffentlich verfügbar. (Quelle: Bring!-Store-Eintrag, Stand 04.11.2026)
+Bei Rezepten, saisonalen Vorschlägen, Angeboten und Prospekten, Kundenkarten und eigenen Fotos an Artikeln. Außerdem ist Bring! öffentlich verfügbar. (Quelle: Bring!-Store-Eintrag, Stand 04.11.2026)
+++ b/site/content/guides/de/alexa.md
-Alexa schickt deinen Satz an Snacklist. Snacklist teilt ihn in einzelne Einträge auf, sortiert jeden in seine Kategorie ein, und die Einträge erscheinen sofort auf allen Geräten in eurem Haushalt. Der Skill versteht Deutsch und Englisch, je nachdem, auf welche Sprache dein Alexa-Gerät eingestellt ist.
+Alexa schickt deinen Satz an Snacklist. Snacklist teilt ihn in einzelne Einträge auf, setzt jeden an die passende Stelle der Liste, und die Einträge erscheinen sofort auf allen Geräten in eurem Haushalt. Der Skill versteht Deutsch und Englisch, je nachdem, auf welche Sprache dein Alexa-Gerät eingestellt ist.
-| Ein Eintrag steht in der falschen Kategorie. | Snacklist hat das Wort einer anderen Kategorie zugeordnet. | Halte den Eintrag in der App kurz gedrückt. Tippe im Fenster, das sich öffnet, auf die Kategorie, wähle die richtige und tippe auf **Fertig**. Snacklist merkt sich das für euren ganzen Haushalt, auch für Einzahl und Mehrzahl desselben Worts. |
+| Ein Eintrag steht im falschen Laden. | Snacklist hat den Eintrag einem anderen Laden zugeordnet. | Halte den Eintrag in der App kurz gedrückt. Tippe im Fenster, das sich öffnet, auf den Laden, wähle den richtigen und tippe auf **Fertig**. Snacklist merkt sich das für euren ganzen Haushalt. |
+++ b/site/content/guides/de/claude.md
-Claude kann deine Snacklist lesen, Sachen draufsetzen, ändern, abhaken, wieder draufsetzen, löschen und in eine andere Kategorie, einen anderen Laden oder eine andere Liste verschieben. Du schreibst Claude einfach, was du brauchst:
+Claude kann deine Snacklist lesen, Sachen draufsetzen, ändern, abhaken, wieder draufsetzen, löschen und in einen anderen Laden oder eine andere Liste verschieben. Du schreibst Claude einfach, was du brauchst:
-Die Einträge stehen sofort auf allen Geräten in eurem Haushalt, sortiert in ihre Kategorien. Das Einrichten dauert keine fünf Minuten. Du musst keinen Schlüssel kopieren: Claude meldet sich mit deinem Snacklist-Konto an.
+Die Einträge stehen sofort auf allen Geräten in eurem Haushalt, an der passenden Stelle der Liste. Das Einrichten dauert keine fünf Minuten. Du musst keinen Schlüssel kopieren: Claude meldet sich mit deinem Snacklist-Konto an.
-| Setz Milch, 2 Gurken und Windeln Pampers Größe 3 auf die Snacklist. | Drei Einträge, jeder in seiner Kategorie. Bei den Windeln stehen Marke „Pampers“ und „Größe 3“ dabei. |
+| Setz Milch, 2 Gurken und Windeln Pampers Größe 3 auf die Snacklist. | Drei Einträge, jeder an seiner Stelle. Bei den Windeln stehen Marke „Pampers“ und „Größe 3“ dabei. |
-| Streich den Sekt. | Der Sekt ist gelöscht. Was Snacklist über Sekt gelernt hat (Kategorie, Laden), bleibt. |
+| Streich den Sekt. | Der Sekt ist gelöscht. Was Snacklist über Sekt gelernt hat (zum Beispiel der Laden), bleibt. |
-> - Claude sieht nur eure Einkaufsliste: Einträge, Kategorien und Läden. Dein Passwort bekommt Claude nicht.
+> - Claude sieht nur eure Einkaufsliste: Einträge und Läden. Dein Passwort bekommt Claude nicht.
-| Ein Eintrag steht in der falschen Kategorie. | Snacklist hat das Wort einer anderen Kategorie zugeordnet. | Schreib Claude zum Beispiel „Verschieb Feta nach Kühlregal“. Snacklist merkt sich das für euren Haushalt. |
+| Ein Eintrag steht im falschen Laden. | Snacklist hat den Eintrag einem anderen Laden zugeordnet. | Schreib Claude zum Beispiel „Verschieb Feta zum Wochenmarkt“. Snacklist merkt sich das für euren Haushalt. |
+++ b/site/content/guides/de/siri-kurzbefehl.md
-Siri schickt deinen Satz an Snacklist. Snacklist teilt ihn in einzelne Einträge auf, sortiert jeden in seine Kategorie ein, und die Einträge erscheinen sofort auf allen Geräten in eurem Haushalt. Das Aufteilen funktioniert bisher nur auf Deutsch.
+Siri schickt deinen Satz an Snacklist. Snacklist teilt ihn in einzelne Einträge auf, setzt jeden an die passende Stelle der Liste, und die Einträge erscheinen sofort auf allen Geräten in eurem Haushalt. Das Aufteilen funktioniert bisher nur auf Deutsch.
+++ b/site/content/guides/en/alexa.md
-Alexa sends your sentence to Snacklist. Snacklist splits it into separate items, sorts each into its category, and the items show up on every device in your household right away. The skill understands English and German, depending on the language your Alexa device is set to. If your device is set to German, follow the German guide: [Snacklist per Alexa: Skill einrichten](/de/anleitungen/alexa)
+Alexa sends your sentence to Snacklist. Snacklist splits it into separate items, puts each in the right spot on the list, and the items show up on every device in your household right away. The skill understands English and German, depending on the language your Alexa device is set to. If your device is set to German, follow the German guide: [Snacklist per Alexa: Skill einrichten](/de/anleitungen/alexa)
+++ b/site/content/guides/en/claude.md
-Claude can read your Snacklist, add items, change them, tick them off, put them back, delete them and move them to another category, store or list. Just tell Claude what you need:
+Claude can read your Snacklist, add items, change them, tick them off, put them back, delete them and move them to another store or list. Just tell Claude what you need:
-The items show up right away on every device in your household, sorted into their categories. Setting it up takes less than five minutes. You don't copy any key: Claude signs in with your Snacklist account.
+The items show up right away on every device in your household, in the right spot on the list. Setting it up takes less than five minutes. You don't copy any key: Claude signs in with your Snacklist account.
-| Put milk, 2 cucumbers and Pampers diapers size 3 on the Snacklist. | Three items, each in its category. The diapers keep "Pampers" as the brand. |
+| Put milk, 2 cucumbers and Pampers diapers size 3 on the Snacklist. | Three items, each in its spot. The diapers keep "Pampers" as the brand. |
-| Delete the sparkling wine. | The sparkling wine is gone. What Snacklist learned about it (category, store) stays. |
+| Delete the sparkling wine. | The sparkling wine is gone. What Snacklist learned about it (for example the store) stays. |
-Anything already on the list isn't added twice. Claude tells you it's already there. Snacklist was made for German shopping lists: its categories have German names such as Kühlregal or Obst & Gemüse, and it sorts German item names best. It knows common English words too, and Claude can write items in German for you if you ask.
+Anything already on the list isn't added twice. Claude tells you it's already there. Snacklist was made for German shopping lists: its built-in word list is German, so it sorts German item names best. It knows common English words too, and Claude can write items in German for you if you ask.
-> - Claude sees only your shopping list: items, categories and stores. Claude never gets your password.
+> - Claude sees only your shopping list: items and stores. Claude never gets your password.
-| An item is in the wrong category. | Snacklist matched the word to another category. | Tell Claude, for example, "Move feta to Kühlregal". Snacklist remembers this for your household. |
+| An item is in the wrong store. | Snacklist put the item in a different store. | Tell Claude, for example, "Move feta to the farmers market". Snacklist remembers this for your household. |
+++ b/site/content/landing/copy.yml
-  de: "Das Eingabefeld ist sofort bereit, unten am Daumen. Vorschläge kommen aus dem, was ihr schon gekauft habt. Abgehakt ist mit einem Tipp, und wer sich vertippt, nimmt es gleich zurück."
-  en: "The input field is ready right away, down by your thumb. Suggestions come from what you have bought before. One tap ticks an item off, and a slip of the finger is undone just as fast."
+  de: "Das Eingabefeld ist sofort bereit, unten am Daumen. Vorschläge kommen aus dem, was ihr schon gekauft habt. Abgehakt ist mit einem Tipp, und wer sich beim Abhaken vertippt, nimmt es gleich zurück."
+  en: "The input field is ready right away, down by your thumb. Suggestions come from what you have bought before. One tap ticks an item off, and a slip of the finger when ticking is undone just as fast."
-  de: "Jeder Artikel landet von selbst in seiner Kategorie, von Obst & Gemüse bis Drogerie. Lege deine Läden an, vom Supermarkt bis zum Wochenmarkt, jeder mit eigenem Laufweg. Snacklist merkt sich, wo du was meistens kaufst."
-  en: "Every item lands in its category by itself, from fruit & vegetables to toiletries. Add your stores, from the supermarket to the farmers’ market, each with its own route. Snacklist remembers where you usually buy what."
+  de: "Jeder Artikel landet von selbst im passenden Laden und an der passenden Stelle, vom Obst bis zur Drogerie. Lege deine Läden an, vom Supermarkt bis zum Wochenmarkt, jeder mit eigenem Laufweg. Snacklist merkt sich, wo du was meistens kaufst."
+  en: "Every item lands in the right store and the right spot by itself, from fruit to toiletries. Add your stores, from the supermarket to the farmers’ market, each with its own route. Snacklist remembers where you usually buy what."
-  de: "Eigene Läden legst du dazu, die Reihenfolge der Kategorien stellst du um."
-  en: "Add your own stores and change the order of the categories."
+  de: "Eigene Läden legst du dazu und bringst sie in deine Reihenfolge."
+  en: "Add your own stores and put them in your own order."
-  de: "In der iPhone- und Android-App tippst du auf das Mikrofon im Eingabefeld und sagst, was fehlt. Snacklist hört direkt auf dem Handy zu, in der Sprache der App (Deutsch oder Englisch), und sortiert jedes Teil in seine Kategorie. Unter Android ab Version 13 kann die App Android bitten, die Offline-Spracherkennung dafür herunterzuladen."
-  en: "In the iPhone and Android app, tap the microphone in the input field and say what you need. Snacklist listens right on your phone, in the app's language (German or English), and sorts each item into its category. On Android 13 and later, the app can ask Android to download offline speech recognition for it."
+  de: "In der iPhone- und Android-App tippst du auf das Mikrofon im Eingabefeld und sagst, was fehlt. Snacklist hört direkt auf dem Handy zu, in der Sprache der App (Deutsch oder Englisch), und setzt jedes Teil an die passende Stelle der Liste. Unter Android ab Version 13 kann die App Android bitten, die Offline-Spracherkennung dafür herunterzuladen."
+  en: "In the iPhone and Android app, tap the microphone in the input field and say what you need. Snacklist listens right on your phone, in the app's language (German or English), and puts each item in the right spot on the list. On Android 13 and later, the app can ask Android to download offline speech recognition for it."
-  de: "Video ohne Ton: Im Haushalt „Unser Haushalt“ tippt Anna „Honig“ und „Marmelade“ ins Eingabefeld der Snacklist-App. Beide landen beim Wochenmarkt unter Vorrat & Konserven, oben in der Liste. Danach hakt je ein Tipp sie wieder ab."
-  en: "Silent video: in the household “Our Home”, Anna types “Honey” and “Jam” into the Snacklist app’s input field. Both land at the Farmers market under Pantry, at the top of the list. Then one tap each ticks them off again."
+  de: "Video ohne Ton: Im Haushalt „Unser Haushalt“ tippt Anna „Honig“ und „Marmelade“ ins Eingabefeld der Snacklist-App. Beide landen beim Wochenmarkt, oben in der Liste. Danach hakt je ein Tipp sie wieder ab."
+  en: "Silent video: in the household “Our Home”, Anna types “Honey” and “Jam” into the Snacklist app’s input field. Both land at the Farmers market, at the top of the list. Then one tap each ticks them off again."
-  de: "Video ohne Ton: Mia tippt auf das Mikrofon im Eingabefeld der Snacklist-App und sagt „Pizza, Orangensaft und zwei Packungen Fischstäbchen“. Die Wörter erscheinen im Feld, während sie spricht. Sie tippt auf Stopp, und gleich darauf stehen Orangensaft unter Getränke und Pizza und 2 Packungen Fischstäbchen unter Tiefkühl. Im Laden hakt sie alle drei ab."
-  en: "Silent video: Mia taps the microphone in the Snacklist app’s input field and says, in German, “Pizza, Orangensaft und zwei Packungen Fischstäbchen” (pizza, orange juice and two packs of fish fingers). The words appear in the field as she speaks. She taps stop, and right after, Orangensaft is under Drinks and Pizza and 2 Packungen Fischstäbchen under Frozen. In the store she ticks all three off."
+  de: "Video ohne Ton: Mia tippt auf das Mikrofon im Eingabefeld der Snacklist-App und sagt „Pizza, Orangensaft und zwei Packungen Fischstäbchen“. Die Wörter erscheinen im Feld, während sie spricht. Sie tippt auf Stopp, und gleich darauf stehen Orangensaft, Pizza und 2 Packungen Fischstäbchen auf der Liste. Im Laden hakt sie alle drei ab."
+  en: "Silent video: Mia taps the microphone in the Snacklist app’s input field and says, in German, “Pizza, Orangensaft und zwei Packungen Fischstäbchen” (pizza, orange juice and two packs of fish fingers). The words appear in the field as she speaks. She taps stop, and right after, Orangensaft, Pizza and 2 Packungen Fischstäbchen are on the list. In the store she ticks all three off."
+++ b/site/content/llms.md
-> Snacklist is a shared shopping list for one household: whatever one person adds, everyone else in the household sees right away, sorted into categories and by store.
+> Snacklist is a shared shopping list for one household: whatever one person adds, everyone else in the household sees right away, sorted by store and by your way through the shop.

## sha256
9e644278da328e7aa321517c829e47e9cb404f22792484864c2e0f922d9dad01  COPY_NEEDED.md
d155ce2f07f1604cb5968d5c4f33c11b1e12df2c67ffd236d4805b0e88742dc3  content/comparisons/de/einkaufsliste-vergleich-bring.md
d9fbcad67e3e43182222a4d22f1184d1aa1f2f4715155101c165a28fc414f4f9  content/guides/de/alexa.md
029c6c3912c2ece339e1fa0e25ed805a9d4db56b36747f6ab323c6a90b4d886d  content/guides/de/claude.md
6d32b10ff70e412e6c2db0f25b043e6ef52b36a4a8568b424580faba22437d28  content/guides/de/siri-kurzbefehl.md
6d52451ed7fc5f975d03e10f626ad6b1fc8766ad38ac594e60493da1ca643dce  content/guides/en/alexa.md
2da2712d6af0a6a7376e13078e9806971f1857c0c31f325c73c95ee2dfd5a115  content/guides/en/claude.md
74c02782afe9221d537d5c31ada15f1ecc3d07028acb8147f22ac56f076155a0  content/landing/copy.yml
181b420a9c828c17f5a0dca9fe2c84bc7ef06e825fe9177feac338e093e876ef  content/llms.md

Test: scripts/gates/site.sh exit 0, 243 tests pass, build 34 pages (Node 24 locally).

Round 2 (stores card):

Changed ids in site/content/landing/copy.yml (old -> new):

- feature.stores.title
  - de: "Sortiert, wie du durch den Laden gehst" -> "Sortiert nach deinen Läden"
  - en: "Sorted the way you walk through the store" -> "Sorted by your stores"
- feature.stores.body
  - de: "Jeder Artikel landet von selbst im passenden Laden und an der passenden Stelle, vom Obst bis zur Drogerie. Lege deine Läden an, vom Supermarkt bis zum Wochenmarkt, jeder mit eigenem Laufweg. Snacklist merkt sich, wo du was meistens kaufst." -> "Jeder Artikel landet von selbst im passenden Laden, vom Wochenmarkt bis zur Drogerie. Lege deine Läden an und bring sie in deine Reihenfolge, so geht die Liste mit dir von Laden zu Laden. Snacklist merkt sich, wo du was meistens kaufst."
  - en: "Every item lands in the right store and the right spot by itself, from fruit to toiletries. Add your stores, from the supermarket to the farmers’ market, each with its own route. Snacklist remembers where you usually buy what." -> "Every item lands in the right store by itself, from the farmers’ market to the drugstore. Add your stores and put them in your order, so the list follows you from store to store. Snacklist remembers where you usually buy what."
- feature.stores.pick
  - de: "Tippe auf einen Laden:" -> "Wohin zuerst? Tippe auf einen Laden:"
  - en: "Tap a store:" -> "Where first? Tap a store:"
- feature.stores.store.market (new): de "Wochenmarkt", en "Farmers’ market"
- feature.stores.store.bakery (new): de "Bäckerei", en "Bakery"
- feature.stores.store.drinks-market (removed): de "Getränkemarkt", en "Drinks store"
- feature.stores.category.{produce,bakery,chilled,meat,pantry,sweets,drinks,frozen,household,drugstore} (all 10 removed; categories are not visible in the app)
- feature.stores.store.drugstore / supermarket: copy unchanged, source note extended.

Unchanged: feature.stores.more.

sha256 of changed content files after this round (copy.yml also holds edits of other agents):
3923618145e8f4e3ce8a735e387ee78a621a7bd5cb9ff0d6049ec5445d3d19a3  content/landing/copy.yml
c38a8b85a24cec9e6e3e901bb653b3f225f8e1a1d76fe266b9dba5ec1aad711f  COPY_NEEDED.md

Round 3 (review 0, Legal addendum 3 and alt texts):

N-341 (comparison page DE only; no EN comparison exists):
 - L19: "Snacklist startet am 15. November 2026 als Beta für Freunde und Familie." -> "Snacklist gibt es für iPhone und Android."
 - table Verfügbarkeit: "Beta ab 15.11.2026 für Freunde und Familie, Warteliste" -> "Für iPhone und Android"
 - MCP section + FAQ KI: "In der Beta ist das für alle kostenlos. Nach dem öffentlichen Start sollen Extras wie die KI-Anbindung zu Snacklist Premium gehören, das dann kostenpflichtig ist." -> "Die Anbindung an KI-Assistenten soll Teil von Snacklist Premium werden."
 - Preis bullet: "Extras wie die KI-Anbindung sollen nach dem öffentlichen Start zu Snacklist Premium gehören." -> "Die Anbindung an KI-Assistenten soll Teil von Snacklist Premium werden."
 - "Wann gibt es Snacklist?": "Snacklist kommt für iPhone und Android. Die Beta startet am 15. November 2026 ... Warteliste setzen." -> "Snacklist gibt es für iPhone und Android, im App Store und in Google Play."
 - FAQ "Kann ich Snacklist schon nutzen?": answer -> "Ja. Snacklist gibt es für iPhone und Android, im App Store und in Google Play."
 - Stand 05.11.2026 -> 22.11.2026 (title, description, headline, intro, table lead-in, Stand section, last FAQ, updated: 2026-11-22). Source dates 04.11.2026 unchanged.
support.md / support-en.md:
 - email answer -> DE "Wenn du dich per E-Mail anmeldest, schicken wir dir einen Link an diese Adresse, und wenn du dich für eine E-Mail zum Start der App eingetragen und das angekreuzt hast, schicken wir dir diese eine Mail." / EN "If you sign in with email, we send a link to that address, and if you signed up for an email when the app launches and ticked the box, we send you that one email."
 - removed 4 Q&As (install beta iPhone/Android, wrong email, invite not arrived); added "Wie installiere ich Snacklist?" / "How do I install Snacklist?": DE "Suche auf dem iPhone im App Store nach „Snacklist“, auf Android in Google Play, und lade die App. Updates kommen danach wie bei jeder App über den Store." EN "On iPhone, search for "Snacklist" in the App Store; on Android, in Google Play, and download the app. Updates then arrive through the store like for any app."
 - "Ich teste Snacklist über TestFlight..." Q&A -> DE "Ich habe einen Fehler gefunden oder eine Idee. Was tun?" / EN "I found a bug or have an idea. What do I do?" (feedback via Mehr > Feedback senden)
N-342: grep -ri hummlist site/content: only waitlist consent v1/v2 texts (allowlisted, scripts/checks/hummlist-allow.txt); imprint/trademarks already Snacklist; no change.
N-339: no country-limit evidence in repo; no launch.countries added.
Tests: site npm test 245/245 (Node 24), scripts/gates/site.sh and lint.sh run.
e735bb4d807ec075a66715752384316fb0cbd266f98b198e465a2cbd2e2164d9  site/COPY_NEEDED.md
fe97ae839d0c05f52376dbbc5ac93e7dfb87d31df69c2bd02d516aae11ba18e8  site/content/landing/copy.yml
e5552bb53d754a81a5e07ba07aea20f21a9190b8c1020186831efd6e4a0c8252  site/content/comparisons/de/einkaufsliste-vergleich-bring.md
9b12096746f28b19764b985257794214dd16ed2dce6a7ab25d1bd3a3d2c4ed0e  site/content/legal/support.md
ec43c2c5431b546f2e679fd45593d4271cbfbdd6e9b198cd34455a6822fb884b  site/content/legal/support-en.md

- `demo.voice-add` EN: now the English take ("Pizza, Orange juice and two packs of Cereal"; Orange juice, Pizza and 2 packs Cereal on the list). DE unchanged.
- `demo.mcp-chat`: DE "unter Vorrat & Konserven" -> "zurück"; EN "under Pantry" -> "back" (the chat no longer shows a category).

Round 4 (Legal partial GO on #637, addendum 4; redlines from the Legal report):

- N-351, all four long descriptions (App Store DE/EN, Play DE/EN): „• Verlauf: alle Einkäufe auf einen Blick, auch von Hand eintragbar" -> „• Verlauf: Einkäufe auf einen Blick, auch von Hand eintragbar"; "• History: all your trips at a glance, and you can log one by hand" -> "• History: your trips at a glance, and you can log one by hand".
- N-354 (delete-redline, `integration-lock` unreleased), same four files: the sentence „Der Zugang für KI-Assistenten gehört zu Snacklist Premium." / "Access for AI assistants is part of Snacklist Premium." and the Premium bullet „• Den Zugang für KI-Assistenten, die MCP unterstützen" / "• Access for AI assistants that support MCP" are deleted.
- N-352 comparison page, Legal's pre-launch column verbatim: intro bullet -> „Bring! ist öffentlich verfügbar. Snacklist ist als Beta für Freunde und Familie gestartet; der öffentliche Start in App Store und Google Play steht bevor."; „Verfügbarkeit" row -> „Beta für Freunde und Familie; öffentlicher Start steht bevor"; „Wann gibt es Snacklist?" -> „Snacklist kommt für iPhone und Android. Die Beta für Freunde und Familie läuft; der öffentliche Start in den Stores steht bevor."; FAQ „Kann ich Snacklist schon nutzen?" -> „Die Beta für Freunde und Familie läuft. Der öffentliche Start in App Store und Google Play steht bevor." Round 1's launch-flip wording is gone.
- The builder's own MCP sentence „Die Anbindung an KI-Assistenten soll Teil von Snacklist Premium werden." is DELETED in all three places (Preis bullet, MCP section, FAQ), not kept: it is not a Legal redline and the lock is off.
- N-356: the row „Mehrere Listen" moved from „Was Bring! heute mehr bietet" to „Die gemeinsame Liste".
- N-357: Bring! source re-dated: „abgerufen am", „Stand", „vom" 04.11.2026 -> 22.11.2026; „Nächste Prüfung" 04.05.2027 -> 22.05.2027 (Legal re-fetched the Bring! listing on 22.11.2026).
- `/support`, `/en/support` (also `updated:` -> 2026-11-22): the Alexa sentence „Der Skill ist noch im Beta-Test und noch nicht für alle verfügbar; den Einladungslink bekommst du von Peter." / "The skill is still in a beta test ... Peter sends you the invitation link." -> „Den Skill findest du im Alexa Skill Store." / "You find the skill in the Alexa Skill Store." (the skill has been live since 2026-11-16). „Wie installiere ich Snacklist?" is now pre-launch: „Snacklist erscheint für das iPhone im App Store und für Android in Google Play. Sobald die App dort verfügbar ist, suchst du nach „Snacklist" und lädst sie wie jede andere App. Updates kommen danach über den Store." / EN equivalent.
- N-358: `marketing/store-assets/collect.sh` leaves out `*.BLOCKED.*` and `*.ON-HOLD.*`; the two Play voice frames are gone from the folder and SHA256SUMS.
- N-359: the English voice-add video, its vtt and alt already use an English sentence (round 3).
