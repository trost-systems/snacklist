# Store layouts

Each store has its own walking order of the categories, from the entrance to
the checkout. A household can change it in the app: the drag handles on a
store's details (Liste → "Anpassen" → the store). The defaults are
`public.apply_store_layout`, latest in
`supabase/migrations/20261106163919_hardware_categories.sql`.

A store the household adds itself (job 58, `public.add_store`) has no researched
layout: it starts from the household's route order (the "Ohne Laden" order),
every category shown, and is edited the same way.

A store named Baumarkt, Heimwerkermarkt, Hardware Store or DIY Store (job 151) is a
hardware store, a type rather than a chain: it gets the Baumarkt layout below and gives the
household seven DIY categories (Farben & Lacke, Sanitär, Elektro & Leuchtmittel, Werkzeug,
Schrauben & Befestigung, Holz & Baustoffe, Garten & Pflanzen). Households without one have none
of them.

None of the three chains publishes a floor plan, and Edeka stores are run by
independent retailers, so layouts vary from store to store. The defaults below
come from store reports in the German retail trade press. Where those reports
say nothing, the order follows the usual pattern: fresh goods at the entrance,
staples and heavy goods further in, non-food last. Each line says which parts
come from a source and which are inferred.

## Lidl

Brot & Backwaren, Obst & Gemüse, Kühlregal, Fleisch/Wurst/Fisch, Vorrat &
Konserven, Süßes & Snacks, Getränke, Tiefkühl, Haushalt, 👶 Drogerie,
the DIY categories of a household with a Baumarkt in the Baumarkt's order (Farben & Lacke,
Sanitär, Elektro & Leuchtmittel, Werkzeug, Schrauben & Befestigung, Holz & Baustoffe, Garten &
Pflanzen), Sonstiges.

- Sourced: the self-service bake station comes first, then produce, then the
  chilled wall and self-service meat. A non-food aisle sits toward the rear.
  ([Lidl Metropol store, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/galerien/So-sieht-die-Metropolfilale-von-Lidl-aus-1433),
  [Lidl Schweich store, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/galerien/Neue-Filiale-in-Schweich-900),
  [Lidl press release, Berlin opening](https://unternehmen.lidl.de/content/download/127077/file/250403_PI_Lidl%20Berlin%20Neuer%C3%B6ffnung.pdf))
- Inferred: the order of pantry, sweets, drinks and frozen. The DIY categories go just before
  Sonstiges in the Baumarkt's order, which is where adding a category puts them in a store
  that existed before the Baumarkt: so the order does not depend on which store came first.

## Edeka

Obst & Gemüse, Brot & Backwaren, Fleisch/Wurst/Fisch, Kühlregal, Vorrat &
Konserven, Süßes & Snacks, Tiefkühl, Getränke, Haushalt, 👶 Drogerie,
the DIY categories of a household with a Baumarkt in the Baumarkt's order (Farben & Lacke,
Sanitär, Elektro & Leuchtmittel, Werkzeug, Schrauben & Befestigung, Holz & Baustoffe, Garten &
Pflanzen), Sonstiges.

- Sourced: produce opens the store as a "market square". The bakery and the
  cheese, meat and sausage counters sit in the first third of the store.
  Staples like milk sit further back.
  ([Edeka Otto, Lebensmittel Praxis](https://lebensmittelpraxis.de/ladenreportagen/10-ladenreportagen/49075-marktrundgang-die-kaesetheke-als-stopper-wie-edeka-otto-den-kundenlauf-neu-denkt.html),
  [Edeka Prechtl, Lebensmittel Praxis](https://lebensmittelpraxis.de/ladenreportagen/49463-marktrundgang-klasse-statt-masse-wie-edeka-prechtl-lebensmittel-neu-inszeniert.html),
  [Verbraucherzentrale on supermarket layouts](https://www.verbraucherzentrale.de/wissen/lebensmittel/einkaufsfallen-im-supermarkt-diese-tricks-sollen-zum-kauf-verfuehren-48915))
- Inferred: the order after the chilled section, and the DIY categories as at Lidl.

## dm

👶 Drogerie, Vorrat & Konserven, Süßes & Snacks, Haushalt, Getränke, the DIY
categories of a household with a Baumarkt (as at Lidl), Sonstiges. Obst & Gemüse,
Brot & Backwaren, Kühlregal, Fleisch/Wurst/Fisch and Tiefkühl are hidden.

- Sourced: beauty and baby come first. The food shelves (muesli, spreads,
  coffee, tea, plant milks, pasta, snacks, sweets) sit further in. Drinks and
  the impulse fridges are at the tills. dm also sells cleaning products and
  hygiene paper.
  ([dm Frankfurt store check, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/storechecks/dm-Drogeriemarkt-in-Frankfurt-1033),
  [dm's food range, Lebensmittel Praxis](https://lebensmittelpraxis.de/zentrale-management/21756-lebensmittel-in-drogeriemaerkten-neue-nahversorger.html?showall=1))
- Inferred: where household goods sit. Also inferred: that dm sells no fresh
  produce, bakery, chilled, meat or frozen goods, which is why those
  categories are hidden. The DIY categories are shown before Sonstiges, as at Lidl, so the
  order does not depend on whether dm or the Baumarkt came first.

## Baumarkt

Farben & Lacke, Sanitär, Elektro & Leuchtmittel, Werkzeug, Schrauben &
Befestigung, Holz & Baustoffe, Garten & Pflanzen, Haushalt, Getränke, Süßes &
Snacks, Sonstiges. Obst & Gemüse, Brot & Backwaren, Kühlregal,
Fleisch/Wurst/Fisch, Vorrat & Konserven, Tiefkühl and 👶 Drogerie are hidden.

- Sourced: paint and wallpaper sit right at the entrance, described as the
  classic arrangement of a DIY store.
  ([a DIY chain's reopened store, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/galerien/Wie-Toom-Baumarkt-mit-mehr-Beratung-punkten-will-1407))
- Inferred: the rest. Sanitär, Elektro and Werkzeug follow in the main hall,
  then screws and fixings, timber and building materials at the back by the
  cutting service, and the garden centre by the tills. Household goods,
  drinks and sweets stand near the tills. The food and Drogerie categories
  are hidden because a DIY store sells hardly any of it.

## How hidden categories work

A store's layout lists every category, each one shown or hidden. The list
ignores the flag since job 16: a store's section shows every item tagged to it,
in the store's order, and an untagged item sits under "Ohne Laden"
(DECISIONS, job 16, item 2, and job 78, item 3). The flag is only stored, and
the store details screen has no switch for it. The researched layouts still
set it (dm hides the fresh food, the Baumarkt the food and Drogerie), so the
data keeps which categories a store does not carry.
