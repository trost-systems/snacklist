# Round SS: recommendation

<!-- pick: SS2 -->
<!-- runner-up: SS5 -->

## Recommendation

**Pick: SS2, type as today, with matches offered and one "Is this Lidl?".** The add-store field stays as it is. The matches under it search the phone's country first, then every country. So "Hofer" finds Austria's Hofer and "Carre" finds Carrefour without any country setting. A typed name that matches asks once. A name that matches nothing is saved as today, with no question. The store's own name never changes: "Aldi am Bahnhof" stays the label, and the link sits beside it.

Take two rules from SS5 into the pick:
- **Existing stores:** ask only where the link changes something you can see, which today means a store whose chain has an app. Ask once per store, as a card on the list.
- **Country:** use the phone's region at the moment you add the store, not a household setting. That drops SS2's "Changing country" walk from 8 taps to SS5's 5.

**Runner-up: SS5, lazy.** It asks the least, and stores without an app are never touched. The cost is that it recognises only chains with an app, so brochures (OF1) or walking orders for other chains would need a second pass later.

Not recommended:
- **SS1, a picker.** It is explicit and predictable, but linking existing stores costs 9 taps, and a country is something the user has to understand.
- **SS3, nearby.** It is the only option that gives a real branch, and the branch sets the country. But it sends the location to a map service, and Google Places is a paid API. OpenStreetMap's public Nominatim doesn't allow app-scale use. It is worth revisiting only if branch-level features come.
- **SS4, a directory.** It does not scale past a few dozen chains per country, and the household needs a country setting.

## Measured

These are the taps from the list to the end of each scenario (`verify.mjs` reads them from the walks). "Changing country" for SS2 and SS4 goes through More › Settings › Shopping country.

| Option | Existing stores | A new store | Not in the list | One chain, two countries | Changing country | Typing | Location | Country |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **SS1** Chain picker | 9 | 3 | 3 | 5 | 5 | search | no | per store, from the phone's region, "Change" |
| **SS2** Type-ahead, "Is this Lidl?" | 3 | 4 | 3 | 3 | 8 | as today | no | household setting; matches in any country |
| **SS3** Nearby | 6 | 5 | 5 | 5 | 5 | none (or a town) | yes, once per search, to a map service | from the branch |
| **SS4** Directory by country | 4 | 3 | 4 | 4 | 8 | only "Other" | no | household setting |
| **SS5** Lazy | 3 | 4 | 3 | 5 | 5 | as today | no | phone region, then any country |

- "Existing stores" links dm, Lidl and "Aldi" (two chains in Germany, so one extra choice) and leaves the market as it is.
- "A new store" for SS2 is 4 taps when the user saves the plain name and answers the question, and 3 when they tap the suggestion.
- SS2 and SS5 put a card on the list while they ask: one card, about 120 px at 100 %, gone after the answer.

## Data model proposal

A retailer registry keyed by chain and country (ISO 3166-1 alpha-2), with the app ids per country. It is versioned in the repo and served from Supabase, so a country can be added without an app release.

```
registry/retailers.json (source of truth, reviewed in PRs)
  { chain: "aldi-sued", country: "AT", name: "Hofer", aliases: ["hofer", "aldi"],
    app: { name: "HOFER", android: "de.apptiv.business.android.aldi_at", ios: "395677652",
           universalLink: "https://www.hofer.at/homescreen",
           storeFallback: { android: "market://details?id=…", ios: "itms-apps://apps.apple.com/app/id395677652" } },
    status: "verified", verified: "2026-11-18", sources: [ … ] }

public.retailers (chain text, country char(2), name text, aliases text[], app jsonb, status text, verified date,
                  primary key (chain, country))       -- public data: RLS on, select for anon and authenticated
public.stores    + retailer_chain text null, + retailer_country char(2) null, + branch text null
                  foreign key (retailer_chain, retailer_country) references retailers on delete set null
public.match_retailer(household uuid, name text, country char(2)) -> (chain, country)[]
                  -- server-side, beside classify_item, sharing store_name_key; the app, MCP and Siri all call it
```

- **Where the data lives.**
  - *Local JSON in the app* needs a release for every new id. It is used only as a bundled snapshot for the first start offline.
  - *A Supabase table* is the pick. The deploy loads it from `retailers.json` with an idempotent upsert, the app reads it once a day and caches it in `DeviceCache`, and MCP and Siri share it.
  - *PostHog flags* only switch features: `open-store-app` and its per-country targeting. Payloads are not a database.
- **Adding a country.**
  1. Add entries to `retailers.json`.
  2. Run `node registry/verify-registry.mjs --only <CC>`. It checks every id against Apple and Google, and every link against the AASA and asset links.
  3. Open a PR. The lint gate runs the offline schema check.
  4. Merge. The deploy upserts the rows, and the app picks them up within a day.

  No app release is needed. Android starts an app by package with `startActivity` and catches `ActivityNotFoundException`, which needs no `<queries>` entry (Android docs, "Package visibility use cases"). iOS opens https links and `itms-apps://`, which need no declaration.
- **Today's seeds.** `seed_key` dm, lidl and edeka become `dm:DE`, `lidl:DE` and `edeka:DE` links. The layouts stay keyed by chain.
- **The registry so far.** It has 58 verified entries (chain and country) in DE, AT, CH, FR, NL, PL, IT and ES, plus Dino PL with no app. No id is guessed; the table above lists them, and `registry/REGISTRY.md` explains how they were checked. DeutschlandCard and PAYBACK are left out.

## Privacy

None of the options needs location by default. Only SS3 uses it. There, the location is asked for on a tap, once ("Allow Once"), and sent to the map service to find shops nearby. Snacklist doesn't store it. **Note for Legal:** SS3 would add a map data processor, which neither Google Places (paid) nor OSM's public Nominatim (usage policy) fits without a contract. The store name a user types stays in the household, as today; matching runs on our server against public registry data.

## Open questions

1. **SS-Q1 Where does the registry live?** Default: `retailers.json` in the repo as the source, loaded by the deploy into a public, read-only `retailers` table. The app caches it and ships a snapshot for the first start. Flags only gate.
2. **SS-Q2 Where does a store's country come from?** Default: the phone's region when the store is added, stored per store. Matching tries that country first, then every country. There is no household setting in the first version. A store in another country gets its country from the match ("Hofer · Austria").
3. **SS-Q3 Which existing stores get asked?** Default: only those whose match has an app, once per store, as a card on the list. "No" is remembered per store, and the store keeps its free text.
4. **SS-Q4 Should a store have a branch?** Default: not in the first version. The nullable column is there, so a free-text branch on the store's screen, or SS3's nearby pick, can come later.
5. **SS-Q5 Should Android get `<queries>` per package, as the DL1 brief said?** Default: no. Use `startActivity` with the package's launcher intent and catch `ActivityNotFoundException`, then open the Play page. New countries then need no release. Confirm on a real Android 14 device before DL1 lands.
6. **SS-Q6 Who keeps the ids fresh?** Default: a weekly scheduled run of `verify-registry.mjs` that opens an issue when an id or link stops resolving. Changes go through PRs only.
7. **SS-Q7 Where does matching run?** Default: Postgres `match_retailer`, next to `classify_item` and sharing `store_name_key`, so the app, MCP and Siri agree. Aliases live in the registry.
8. **SS-Q8 Which app does a chain with two apps get (BILLA or jö, Super U or Courses U, and others)?** Default: one app per chain and country, the one that holds the loyalty card or coupons. The alternatives are listed in each entry's note.
9. **SS-Q9 Should the store-name disclaimer stand under every chain suggestion and picker?** Default: yes, word for word. Legal confirms that L-7 covers the new places.
10. **SS-Q10 Should location-based search (SS3) come back later?** Default: no, not without a branch-level feature that needs it, plus Legal's review of a map provider.
