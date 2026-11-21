# Categories for non-grocery stores: how other apps do it

Job 346. Web research, 2026-11-21. Every claim carries its URL. "Snippet" means the
claim comes from a search-result excerpt of that URL because the page itself refused
WebFetch (HTTP 403, mostly ikea.com, bauhaus.info, outofmilk). "Unverified" means I
found no source.

Model types used below:

- **Fixed global**: one category set for all lists, app-defined.
- **Per-list set**: each list has its own categories and order.
- **Per-store set**: a category set or order tied to a named store.
- **Learned order**: the app learns the walk order from check-off sequence.
- **User sections**: the user makes sections; no catalog.
- **Retailer location**: the retailer's app knows aisle/shelf/bin from its own data.

## 1. Bring! (DE market leader)

- Model: **fixed global catalog sections, per-list order and visibility**.
- The German catalog has 13 sections in this order: Obst & Gemüse, Brot & Gebäck,
  Milch & Käse, Fleisch & Fisch, Zutaten & Gewürze, Fertig- & Tiefkühlprodukte,
  Getreideprodukte, Snacks & Süsswaren, Getränke, Haushalt, Pflege & Gesundheit,
  Tierbedarf, Baumarkt & Garten (360 items total). Source: Bring's web app catalog
  file https://web.getbring.com/locale/catalog.de-DE.json (a data file the web app
  loads, not a help page).
- Non-grocery coverage is thin. "Baumarkt & Garten" has 15 items (Blumenerde, Grill,
  Sonnenschirm, Dünger, Töpfe, Gartenwerkzeug, Sämereien, Propangas, Holzkohle, Nägel,
  Schrauben, Pinsel, Giesskanne, Pflanzen, Rasenmäher). Kerzen and Glühbirne sit in
  "Haushalt". Möbel, Lampe, Kissen, Bilderrahmen are absent. Same URL.
- Drogerie items live in "Pflege & Gesundheit" (37 items: Deo, Zahnpasta, Windeln,
  Pflaster, Schmerzmittel, Vitamine ...). Same URL.
- Category order is set per list: "profile > settings > List settings > List name >
  Sort your list" and "You can then move the categories to match the layout of your
  store." https://getbring.com/help-center-main-categories/items-lists
- Categories can be hidden per list ("tapping the eye symbol next to the category
  name"). Items themselves cannot be reordered ("It is not possible to change the
  order of the individual items."). Same URL.
- Unknown item: "If the searched item does not exist, Bring! will assign a suitable
  icon and the correct category." Unusual items become "own items": "You must add
  extraordinary items as your own." Same URL.
- An item can be moved to "one of the predetermined categories" only; users cannot
  create categories. Same URL. A German App Store review asks for custom categories
  and the developer answers it was passed to the team (snippet,
  https://apps.apple.com/de/app/bring-einkaufsliste-rezepte/id580669177).
- Store guidance is "Erstelle gemeinsame Einkaufslisten für verschiedene Geschäfte"
  plus "passe die Anzeige der Produktkategorien an die Gänge in deinem Supermarkt an"
  (same App Store URL). So Bring's answer to "Baumarkt" or "Drogerie" is a separate
  list with the same 13 sections, reordered or hidden. No Baumarkt-specific section
  set: I found none (unverified that none exists in-app).
- New-list "suggestions" and "Inspiration" templates exist (help center URL above);
  whether any template is store-typed (Baumarkt, Drogerie) is unverified.

## 2. AnyList

- Model: **per-list categories, plus optional per-store category sets**.
- Since v5.9 "categories are maintained on a per-list basis"; renaming in one list
  does not touch others. https://help.anylist.com/articles/release-notes-anylist-v5-9
- Users add, rename, re-icon, reorder and delete categories.
  https://help.anylist.com/articles/category-group
- Category sets: "multiple distinct sets of categories for a single list", and an item
  can sit in a different category in each set. You create one set per store "with
  each set containing categories that match the aisle layout at that store".
  https://help.anylist.com/articles/category-sets/
- A store's filter can name its "Active Category Set"; filtering by that store then
  rearranges the list. Same URL. Stores and filters need AnyList Complete (paid).
  https://help.anylist.com/articles/assign-items-to-stores/
- Unknown item: goes to the list's "default category" (configurable, "Other" by
  default and removable). https://help.anylist.com/articles/default-category
- Learning: after a reassignment "the next time anyone adds that item to the list,
  it will be automatically assigned to that category." Per list. v5.9 notes URL.
- Non-grocery lists: the packing-list example starts empty and the user adds
  categories by hand. https://help.anylist.com/articles/custom-list/
- Notable: this is the most complete model (list -> category sets -> store picks set)
  and it is a paid power feature.

## 3. OurGroceries

- Model: **fixed global user-editable set**. "categories are the same across all
  shopping lists". https://ourgroceries.com/user-guide
- Ships a few starter categories (Dairy, Produce, Bakery); users add, rename, delete
  and reorder in Settings > Item Categories, and the order is the section order on
  every list. Some users name categories by aisle number. Same URL.
- Unknown item: "By default, OurGroceries guesses what category each new item should
  be in." A setting "When adding an item with no category" picks between guess and
  ask, always ask, or leave "Uncategorized". Same URL.
- Learning from user corrections: not stated in the guide (unverified).
- Notable: one global order means a second store type (Baumarkt) shares the grocery
  order. No per-store order.

## 4. Listonic

- Model: **auto categories plus custom categories; order per list** (one list per
  store is the suggested pattern).
- "Listonic adds a category to every item automatically." "Listonic's default
  categories match most supermarket aisles, but they don't cover everything."
  https://listonic.com/custom-grocery-list-categories
- Per store: "create separate lists for your favorite stores and set a custom
  category order." Same URL.
- Custom categories with own names and icons "sit alongside the automatic grouping
  rather than replacing it". https://listonic.com/features/custom-categories
- Reorder by drag handle. Snippet,
  https://help.listonic.com/en/31035968-How-to-change-the-categories-order-
  (page failed TLS on fetch).
- Shared lists: only the owner can create a custom category (snippet from a Listonic
  page, via the same search; exact URL not fetched, so unverified).
- Unknown-item fallback category name: unverified.

## 5. Apple Reminders (Groceries list type)

- Model: **fixed global grocery section set, user-editable per list, learned
  corrections**.
- iOS 17 sections: Produce; Breads & Cereals; Frozen Foods; Snacks & Candy; Meat;
  Dairy, Eggs & Cheese; Bakery; Baking Items; Household Items; Personal Care &
  Health; Wine, Beer & Spirits.
  https://www.macrumors.com/2023/06/07/ios-17-reminders-grocery-sorting/
- Non-food has two buckets only: "Household Items" and "Personal Care & Health".
  Same URL. Nothing for hardware or furniture.
- Unknown item: "If the iPhone doesn't recognize where an item should go, it remains
  uncategorized." Same URL.
- Correction is remembered: "your Groceries list remembers your preference next time
  you add that item". Users can add sections ("New Section with Selection") and
  rename them. https://support.apple.com/en-ae/105086
- Order: "change the order of the shopping categories to match the arrangement of
  your favourite supermarket"; "Hide Empty Sections".
  https://support.apple.com/bn-in/guide/reminders/remnbb50db03/7.0/mac/27
- German grocery categorization arrived with iOS 18 (snippet from
  https://www.idropnews.com/gallery/everything-new-with-reminders-in-ios-18/223553/4
  and https://support.apple.com/120616; the Apple page itself did not render the
  language list for me).
- Newer: Apple Intelligence "Auto-Categorise" sorts reminders in any list into
  sections it invents. Same Mac guide URL. This is the only example of category
  names generated per list rather than picked from a fixed set.

## 6. Todoist and Microsoft To Do

- Model: **user sections, no catalog, no auto categorization**.
- Todoist's grocery template tells users "If you think a category is missing, add a
  new section like "Desserts" or "Costco"" (store as a section).
  https://www.todoist.com/templates/grocery-list
- Microsoft To Do: no category grouping; users ask for a dedicated grocery list.
  https://techcommunity.microsoft.com/discussions/to-do/dedicated-grocery-list/4257009
  No official statement of automatic grocery categories found.

## 7. Out of Milk, Paprika, Mealime

- Out of Milk: user categories (name and colour) via Manage Categories; an
  "Auto-categorize" setting; reordering categories per list has its own help article.
  Snippets from https://support.outofmilk.com/hc/en-us/articles/207913066 and
  https://support.outofmilk.com/hc/en-us/articles/207913046 (403 on fetch).
- Paprika: custom grocery "aisles" in your own order; an ingredient's aisle
  assignment is remembered. Snippet from https://www.paprikaapp.com/blog/page3 and
  https://apps.apple.com/us/app/-/id1303222868.
- Mealime: not researched (unverified).

## 8. Learned order (check-off sequence)

- Grocery - Smart Shopping List: "Keeps track of the order you mark off items to sort
  your list next time"; "Add a Store for every place that you shop".
  https://apps.apple.com/au/app/id1195676848?l=en-au
- Others advertise the same: Grocery Flow ("learns the geographical sequence of your
  specific route"), Easy Shopping List, Cart Companion (one layout profile per
  store). Snippets: https://apps.apple.com/app/id6759967985,
  https://apps.apple.com/app/id463855587, https://apps.apple.com/app/id6741090855.
  Mechanisms are vendor claims only.
- Notable: learned order needs no category vocabulary at all, so it works for IKEA or
  a Baumarkt as well as for a supermarket, but only from the second visit and only
  per store.

## 9. Retailers' own apps

- **IKEA app**: adding a product to the shopping list "will show its location within
  the store" (Canada, snippet,
  https://www.retaildive.com/ex/mobilecommercedaily/ikea-canada-builds-in-store-shopping-companion-with-redesigned-app);
  the IKEA Shopping app "shows where products on your shopping list are located in
  store" (snippet, https://apps.apple.com/mx/app/ikea-shopping/id1525177145?l=en).
  On ikea.com larger furniture shows aisle and bin in the self-serve warehouse
  (snippet, https://www.ikea.com/us/en/customer-service/knowledge/articles/56835821-8dgd-4fb1-b7e3-0015g7f5g990.html).
  German app behaviour: unverified.
- **dm (Mein dm)**: "Merkliste" usable as Einkaufsliste and store stock per preferred
  store; no shelf location found (snippet,
  https://www.dm.de/services/services-in-der-dm-app/deine-produkte-3621032). An
  assistant "dm-mitgedacht" with "intelligente" Einkaufslisten is planned for early
  2027 (https://www.giga.de/tech/beim-naechsten-dm-einkauf-neuer-service-spart-euch-zeit--01M5HMJWY7JX1GMC7BZEV12ZRT,
  dated 2026-10-22).
- **Rossmann**: Einkaufsliste with coupon suggestions; no shelf sorting found
  (snippet, https://www.rossmann.de/de/service-und-hilfe/rossmann-app).
- **OBI (heyOBI)**: "Im OBI Markt angekommen, kannst du dir im Markt-Navi den Standort
  von Artikeln aus deiner Einkaufsliste anzeigen lassen", only in participating stores
  (https://apps.apple.com/DE/app/id1331431911, and snippet from
  https://www.obi.de/info/heyobi).
- **Hornbach**: the app shows "die Gangnummer sowie die Artikelverfügbarkeit"; the
  Merkliste ticks items into "Erledigt"; Marktnavigation routes after scanning any
  barcode (snippet, https://www.hornbach.ch/services/hornbach-app/). Netherlands:
  aisle, display and shelf (snippet, https://www.retaildetail.eu/?p=45538).
- **Bauhaus**: "Artikelstandorte im BAUHAUS Fachcentrum automatisch im Produktfinder";
  a store map highlights the item; a review reports "Regal- und sogar Fachnummer"
  (https://apps.apple.com/DE/app/id1615566534). The list "can be sorted by shelves"
  per a 2023 press release (snippet,
  https://www.presseportal.de/download/document/64f580b3270000fd2c86098b-23-09-04-pi-bauhaus-app.pdf).
- **REWE**: Einkaufsliste renamed "Favoriten", no layout sorting found (snippet,
  https://www.rewe.de/service/online-einkaufen/favoriten/). Edeka: not researched.
- **Walmart**: list items show aisle (2018,
  https://corporate.walmart.com/news/2018/02/08/your-shopping-trip-just-got-easier-with-this-new-store-assistant);
  a newer "Sort by aisle" on lists (snippet,
  https://www.consumeraffairs.com/news/walmarts-app-just-grew-up-for-the-holidays-and-its-a-money-saver-110325.html).
  Target: unverified.

## 10. IKEA store layout

- Route: showroom first, then Market Hall, then the self-serve area, then checkouts.
  India's guide: "Proceed to the market hall, explore our product range and pick
  items as you move" before self-serve (snippet,
  https://www.ikea.com/in/en/customer-service/knowledge/articles/dgc55b05-8789-468b-b611-37b8744cg980.html).
  A German Erfahrungsbericht describes Ausstellung, essen, Markthalle, then SB-Regal
  (snippet, https://ohn.haendlerbund.de/themen/panorama/30178-erfahrungsbericht-ikea-click-collect).
- Market Hall: "lighting, textiles, cooking & tableware, daily storage and
  decorations" you pick yourself (snippet,
  https://www.ikea.com/kr/en/customer-service/knowledge/articles/d3eb2256-f316-4c85-8cd2-6b48g05683c6.html).
  A numbered Hyderabad route: Cookware & tableware, Textiles, Bed & Bath textiles,
  Rugs, Lighting, Home organisation, Wall decoration & mirrors (snippet,
  https://manuals.plus/m/01b21a9787d4d356c1be2b6fbb9466568c3adbd5a6e6ef3ebbef27e66d92aae1).
  Singapore Alexandra: Wall decoration (incl. mirrors), Textile, Cookshop, Rugs,
  Lighting, Home (snippet,
  https://www.ikea.com/sg/en/files/pdf/1a/35/1a35a648/ikea-alexandra-store-layout.pdf).
- Self-serve: the price tag gives aisle and bin (location or shelf); shoppers note the
  item number, aisle and location; yellow tags mean staff pick it (Full Serve,
  collected after checkout) (snippets,
  https://www.ikea.com/in/en/customer-service/knowledge/articles/8293f091-b74b-44d9-b4dg-493f5200c8d9.html,
  https://www.ikea.com/cz/en/customer-service/shopping-at-ikea/shopping-at-ikea-store-pubd3a795f2).
- Food: Bistro and Schwedenshop by the checkouts in German stores (snippet, a review,
  https://www.happycow.net/reviews/ikea-dortmund-374270); the Swedish food shop sells
  meatballs, cinnamon buns, smoked salmon (snippet,
  https://www.ikea.com/de/en/customer-service/knowledge/articles/7d3c56cc-e96g-4dfd-9c89-f3419bd9621c.html).
- German department labels (Kochen & Essen, Textilien, Beleuchtung, Dekoration,
  Bilderrahmen, Aufbewahrung, Pflanzen): **unverified**. The general area names
  Markthalle, SB-Halle, Kassenzone appear in Karlsruhe planning documents (snippet,
  https://web1.karlsruhe.de/ris/oparl/bodies/0001/downloadfiles/00592696.pdf). Plants'
  position in the route: unverified. Department order varies by store per IKEA's own
  pages (snippets above).

## Comparison

| App | Model | Non-grocery support | Unknown item | Order per store | Learns |
| --- | --- | --- | --- | --- | --- |
| Bring! | Fixed 13 catalog sections; order and visibility per list | Haushalt, Pflege & Gesundheit, Tierbedarf, Baumarkt & Garten (15 items); no furniture/IKEA | Auto-assigned a "suitable" category as own item | Yes, via one list per store | Unverified |
| AnyList | Per-list user categories; per-store category sets (paid) | User builds categories (e.g. packing) | List's default category ("Other") | Yes, category set per store filter | Yes, per list |
| OurGroceries | One global user-editable set | Only if user adds categories | Guess, ask, or "Uncategorized" (setting) | No, one global order | Unverified |
| Listonic | Auto categories + custom categories | Custom categories | Unverified | Yes, one list per store | Unverified |
| Apple Reminders | Fixed grocery sections per Groceries list, editable; AI auto-sections on newer OS | Household Items, Personal Care & Health only | Stays uncategorized | Per list order | Yes, corrections |
| Todoist / To Do | User sections only | Anything, manual | No grouping | Store as a section | No |
| Out of Milk / Paprika | User categories / aisles | Manual | Auto-categorize setting / remembered aisle | Unverified | Paprika: yes |
| Grocery (Stoll) et al. | Learned walk order per store | Any store | Placed by learned position (mechanism unverified) | Yes | Yes, from check-offs |
| IKEA, OBI, Hornbach, Bauhaus | Retailer location (aisle/shelf/bin) | Native | Not applicable (catalog = assortment) | Their own store | No |
| dm, Rossmann, REWE | Plain list, no location found | Native assortment | Not applicable | No | No |

## Takeaways for Snacklist

1. No consumer list app I found ships a category set for IKEA, furniture or
   Baumarkt departments. The market leader's answer is one fixed grocery-shaped set
   with three thin non-food buckets (Bring's Baumarkt & Garten has 15 items, no
   furniture). Snacklist's hardware-store set already goes further than Bring.
2. The common pattern is "one list per store, reorder and hide the sections" (Bring,
   Listonic, Apple). It fixes order, not vocabulary: an IKEA list still shows grocery
   names, which is exactly the user's complaint.
3. AnyList's category sets are the only general model where a store brings its own
   vocabulary and order, with an item mapped separately per set. It is a paid power
   feature, a sign that it is heavy UI for most households.
4. Every auto-categorizing app has an explicit fallback (Bring "own item", AnyList
   default "Other", OurGroceries "Uncategorized", Apple "uncategorized"). For a store
   the classifier does not know, a clean "no sections" list beats a wrong grocery
   section.
5. Remembering a user's correction is table stakes (AnyList, Apple, Paprika), scoped
   per list in AnyList. Snacklist's category memory should be scoped to the store
   type when non-grocery sets exist, or an IKEA "Kerzen" fix leaks into grocery
   lists.
6. Learned walk order (check-off sequence per store) is the one approach that is
   store-type-agnostic. It suits IKEA, where the route is fixed (showroom, Market Hall,
   self-serve aisle/bin, checkout, Schwedenshop), and needs no German department
   vocabulary we could not verify.
7. Retailers with real location data (IKEA, OBI, Hornbach, Bauhaus) give aisle, shelf
   or bin per product, but only in their own apps and with no public API found
   (unverified). Drugstores (dm, Rossmann) show stock, not shelf. Do not plan on
   importing locations.
8. Drogerie and Apotheke items fit a small fixed set well (Bring's 37-item Pflege &
   Gesundheit, Apple's Personal Care & Health). IKEA does not: its sections are store
   areas, and the self-serve part is addressed by aisle and bin numbers, not
   categories.
