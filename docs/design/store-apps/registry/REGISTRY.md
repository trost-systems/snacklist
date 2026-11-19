# Retailer app registry

`retailers.json` maps a grocery or drugstore chain in one country to its app. Snacklist can then open the retailer's app, or its store page when the app is missing. Job 314 built it on 2026-11-18.

## How it was verified

`node verify-registry.mjs` rechecks every entry against primary sources. `--offline` only checks the schema. `--only DE,AT` limits the run to some countries.

- iOS. `itunes.apple.com/lookup?id=<id>&country=<cc>` must return the app. The lookup filters by storefront: Biedronka returns 0 results for `us`. The run records the store name and the bundle id.
- Android. The Play details page must answer 200, and its title must contain `app.name`. Play shows anonymous clients the same page for every `gl`, so country availability on Android is not verified. The script reports it as "listed (country availability unverified)".
- Links. The script reads Apple's CDN copy of the AASA (`app-site-association.cdn-apple.com/a/v1/<host>`) and Google's Digital Asset Links API for the entry's `web` host. A `universalLink` passes only if the AASA claims that exact URL for the app's bundle id. Components are matched in order and exclusions count.
- The candidates came from the iTunes Search API filtered by seller, Play search, the retailers' AASA and asset links files, and their home pages. No id was guessed.

A mutated copy proved the checks bite. A wrong iOS id, an unknown package, a renamed app, an excluded link path (`/angebote` on aldi-sued.de) and a wrong store fallback each failed.

## Counts (2026-11-18)

All 59 entries pass. 58 are verified with both store ids and one has no app.

| Country | Verified | No app |
| --- | --- | --- |
| DE | 10 | 0 |
| AT | 7 | 0 |
| CH | 5 | 0 |
| FR | 8 | 0 |
| NL | 7 | 0 |
| PL | 7 | 1 (Dino) |
| IT | 7 | 0 |
| ES | 7 | 0 |

All ten German starting ids from earlier research were correct.

## Same chain, different country

- Lidl Plus is one app everywhere (iOS 1238611143, `com.lidl.eci.lidlplus`). Every Lidl domain's AASA lists the same appID. Asset links list the package on lidl.de, .fr, .nl, .pl and .es, but not on lidl.at, .ch or .it. Those three domains also claim only `/prm/*`.
- ALDI SÜD runs a separate app per country. ALDI SÜD DE, Hofer AT (`com.aldisued.HoferAT`), ALDI SUISSE and ALDI Italia each have their own iOS id and `de.apptiv.business.android.aldi_<cc>` package.
- ALDI France, Nederland and Spain belong to ALDI Nord, not ALDI SÜD. Their seller is ALDI Einkauf and their packages are `<cc>.aldi.android`. ALDI Nord's asset links file covers every country's package.
- Carrefour FR, PL, IT and ES are four different apps from four companies: Carrefour Groupe, Carrefour Polska, GS SpA and Centros Comerciales Carrefour.
- Coop CH (Coop Genossenschaft, `ch.coop.coopapp`) and Coop IT (Coop Italia, `com.coopitalia.iCoopNew`) are unrelated chains that share a name.
- SPAR Österreich has its own app (`at.spar.app`). SPAR Croatia and Slovenia have separate apps.
- PENNY DE and PENNY AT are different apps. So are Rossmann DE and Rossmann PL.
- Mein dm (DE, AT) and Kaufland (DE, PL) are one app across countries, and each country's domain serves the same association files.
- Auchan: France, Poland and Alcampo ES each have their own app. One iOS app (1450287430) is named "Club Alcampo" in ES and "Auchan Retail Shopping" in PL.

## Universal links

Universal links are set on 21 entries. Each URL is claimed in the AASA, and that domain's asset links list the Android package. Android path filters live in the app manifest, so the Android path itself is not checked.

- These open the app home: aldi-sued.de, hofer.at and aldi.it at `/homescreen`, and aldi-suisse.ch at `/de/homescreen`. ALDI Nord's DE, FR, NL and ES domains use `/app-only/dashboard.html`. Conad uses `/app-internal/home_page`, Intermarché `/accueil`, and Migros `/?universal_link=true`.
- These claim the site root: carrefour.fr, auchan.fr, coursesu.com, plus.nl, rossmann.pl and tienda.mercadona.es.
- These open a section: REWE `/shop` and Jumbo `/lijstjes` (lists). Kruidvat `/kruidvatapp` and Carrefour IT `/app-carrefour.html` are app landing pages, and which screen they open is unverified.
- The other 37 entries have no universal link, and each note gives the reason. Some domains have no AASA. Others claim only deep paths, or declare only webcredentials (Monoprix) or an App Clip (Dirk). Eurospin's AASA on Apple's CDN is invalid JSON, with a trailing comma.

## TODO

- Android country availability cannot be checked without a signed-in Play client in each country.
- Pick between alternative apps where the chain promotes two. The notes list them: BILLA vs jö, Super U, Esselunga, Auchan PL, Alcampo, Leclerc and ALDI ES.
- Dino PL has no app on 2026-11-18. Recheck it now and then.
- Test the 21 universal links on a device. Only the claim is verified, not the screen the app opens.
- Coop CH's AASA starts with a bare `#*` component. Test `https://www.coop.ch/` on a device before using it.
