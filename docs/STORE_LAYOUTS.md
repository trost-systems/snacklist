# Store layouts

Each store has its own walking order of the categories, from the entrance to
the checkout. A household can change it by drag in the app (store picker,
then "Reihenfolge bearbeiten"). The defaults are seeded by
`public.apply_default_store_layouts` in
`supabase/migrations/20261022233800_classifier_stores.sql`.

A store the household adds itself (job 58, `public.add_store`) has no researched
layout: it starts from the household's route order (the "Ohne Laden" order),
every category shown, and is edited the same way.

None of the three chains publishes a floor plan, and Edeka stores are run by
independent retailers, so layouts vary from store to store. The defaults below
come from store reports in the German retail trade press. Where those reports
say nothing, the order follows the usual pattern: fresh goods at the entrance,
staples and heavy goods further in, non-food last. Each line says which parts
come from a source and which are inferred.

## Lidl

Brot & Backwaren, Obst & Gemüse, Kühlregal, Fleisch/Wurst/Fisch, Vorrat &
Konserven, Süßes & Snacks, Getränke, Tiefkühl, Haushalt, 👶 Drogerie,
Sonstiges.

- Sourced: the self-service bake station comes first, then produce, then the
  chilled wall and self-service meat. A non-food aisle sits toward the rear.
  ([Lidl Metropol store, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/galerien/So-sieht-die-Metropolfilale-von-Lidl-aus-1433),
  [Lidl Schweich store, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/galerien/Neue-Filiale-in-Schweich-900),
  [Lidl press release, Berlin opening](https://unternehmen.lidl.de/content/download/127077/file/250403_PI_Lidl%20Berlin%20Neuer%C3%B6ffnung.pdf))
- Inferred: the order of pantry, sweets, drinks and frozen.

## Edeka

Obst & Gemüse, Brot & Backwaren, Fleisch/Wurst/Fisch, Kühlregal, Vorrat &
Konserven, Süßes & Snacks, Tiefkühl, Getränke, Haushalt, 👶 Drogerie,
Sonstiges.

- Sourced: produce opens the store as a "market square". The bakery and the
  cheese, meat and sausage counters sit in the first third of the store.
  Staples like milk sit further back.
  ([Edeka Otto, Lebensmittel Praxis](https://lebensmittelpraxis.de/ladenreportagen/10-ladenreportagen/49075-marktrundgang-die-kaesetheke-als-stopper-wie-edeka-otto-den-kundenlauf-neu-denkt.html),
  [Edeka Prechtl, Lebensmittel Praxis](https://lebensmittelpraxis.de/ladenreportagen/49463-marktrundgang-klasse-statt-masse-wie-edeka-prechtl-lebensmittel-neu-inszeniert.html),
  [Verbraucherzentrale on supermarket layouts](https://www.verbraucherzentrale.de/wissen/lebensmittel/einkaufsfallen-im-supermarkt-diese-tricks-sollen-zum-kauf-verfuehren-48915))
- Inferred: the order after the chilled section.

## dm

👶 Drogerie, Vorrat & Konserven, Süßes & Snacks, Haushalt, Getränke,
Sonstiges. Obst & Gemüse, Brot & Backwaren, Kühlregal,
Fleisch/Wurst/Fisch and Tiefkühl are hidden.

- Sourced: beauty and baby come first. The food shelves (muesli, spreads,
  coffee, tea, plant milks, pasta, snacks, sweets) sit further in. Drinks and
  the impulse fridges are at the tills. dm also sells cleaning products and
  hygiene paper.
  ([dm Frankfurt store check, Lebensmittel Zeitung](https://www.lebensmittelzeitung.net/storechecks/dm-Drogeriemarkt-in-Frankfurt-1033),
  [dm's food range, Lebensmittel Praxis](https://lebensmittelpraxis.de/zentrale-management/21756-lebensmittel-in-drogeriemaerkten-neue-nahversorger.html?showall=1))
- Inferred: where household goods sit. Also inferred: that dm sells no fresh
  produce, bakery, chilled, meat or frozen goods, which is why those
  categories are hidden.

## How hidden categories work

A store's layout lists every category. Each one is either shown or hidden;
"gibt es hier" is the switch in the layout editor.

- **Store view.** It shows the items tagged to that store plus the untagged
  items, grouped in the store's order.
- **Hidden categories.** An untagged item in a category the store hides is
  left out of the view. A footer counts these items and can show them, so
  nothing is lost. An item tagged to the store always shows, even in a hidden
  category.
- **Klopapier.** It is in Haushalt (DECISIONS, job 1, #7). dm shows Haushalt,
  so untagged toilet paper appears in the dm view, where Peter and Lea would
  likely buy it.
