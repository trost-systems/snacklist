# Retailer registry

`retailers.json` lists grocery and drugstore chains per country with their apps. Snacklist links a
store to one entry and opens its app, or the app's store page when the app is missing. Job 314
researched the entries on 2026-11-18; job 313 turned them into this file and `public.retailers`.

## An entry

- `chain` and `country` (ISO alpha-2) are the key. One chain can have a different app per country
  (ALDI SÜD, PENNY, Carrefour) or the same one everywhere (Lidl Plus).
- Entries of one country stand in the order the onboarding offers them as chips, most stores first
  (job 321).
- `name` is what the household sees. `short`, when set, is a shorter name for the chip and the store
  made from it ("Netto" for Netto Marken-Discount); the database does not keep it. `aliases` are further lower-case names people type for it
  ("aldi", "netto", "eurospar"), three characters or more. Matching folds case, accents and
  punctuation (`public.retailer_key`).
- `apps` lists every app with both store ids. The first one is the default, the chain's loyalty or
  coupon app where it has one; a household can pick another one per store. `universalLink` is a
  URL the retailer's AASA claims for the app, or null with the reason in `note`. Only the chain's own
  domains count: Adjust (`go.link`), AppsFlyer (`onelink.me`) and Firebase (`page.link`) hosts also
  claim some apps, but a bare link there hands the app's attribution SDK a click and may land on an
  error screen (job 335). `scheme` is the URL scheme the app registers (`lidlplus`), or null; the
  iPhone app opens its bare root when no universal link opened the app, and sends nothing with it.
  Its source goes in `note`: the iOS app's Info.plist or the chain's own pages where public, else
  the Android app's manifest (`tool/retailers/app_schemes.py`). A scheme several apps declare stays
  out where the app has another way in (`aldinord`, four ALDI Nord countries with universal links):
  iOS could open another one. Carrefour PL keeps `carrefour`, which Carrefour Italia declares too,
  because it has no other way in; only someone with both apps could land in the wrong one.
- `status` is `verified`, or `no-app` with the evidence in `note` (Dino PL).

## Changing it

1. Edit `retailers.json` and run `deno run --allow-read --allow-net scripts/retailers.ts --verify --only DE`
   for the countries you touched.
2. Run `deno run --allow-read --allow-write scripts/retailers.ts --migration`. It writes a new
   migration that upserts every entry and deletes the others; stores of a deleted entry lose their
   link. The lint gate (`--check`) fails while the newest migration's rows differ from the file.
3. Run `deno run --allow-read --allow-write scripts/retailers.ts --dart`. It writes the app's copy,
   `app/lib/list/retailer_registry.g.dart`: the onboarding's store step runs before sign-in, when
   the app can't read `public.retailers`. `--check` fails while the copy differs.
4. Run `deno run --allow-read --allow-write scripts/retailers.ts --coverage`. It writes `coverage.md`:
   per app how the iPhone opens it (universal link, scheme, or only the App Store) and the source.
   `--check` fails while it is stale.

A new country needs nothing else: matching tries the phone's country first and then every country.

## How it is verified

`--verify` checks each app against primary sources. It is online and not part of CI.

- iOS. `itunes.apple.com/lookup?id=<id>&country=<cc>` must return the app in that storefront.
- Android. The Play details page must answer 200, and its title must contain the app's `name`.
  Play shows anonymous clients one page for every country, so Android availability per country
  is not verified.
- Links. Apple's CDN copy of the AASA (`app-site-association.cdn-apple.com/a/v1/<host>`) must
  claim the `universalLink` for the app's bundle id, components in order, exclusions counted.
  Google's Digital Asset Links for the `web` host are reported.

Schemes have no online check: `python3 -I tool/retailers/app_schemes.py [--only <pkg>...]` downloads
each app's current APK (apkpure, else Aptoide) into a temp dir, reads its manifest with aapt2 (nothing
from the APK runs) and prints the schemes per activity with the APK's version and signer.

Candidates came from the iTunes Search API, Play search, the retailers' AASA and asset links files
and their home pages. No id was guessed. A second app is listed only when both its ids passed;
the others stay in `note` (Mein BILLA has no iOS app; Auchan PL's and Alcampo's alternative pairs
an iOS and an Android app from different Auchan companies).

## Weekly check

`.github/workflows/retailers-verify.yml` runs `--verify` every Monday (and by hand). When an app id or link stops
resolving it opens or updates the issue "Retailer registry: an app id or link stopped resolving"; the next green run
closes it. Fix the entry in a PR.

## Open

- Android country availability needs a signed-in Play client in each country.
- The universal links are claims; which screen each one opens is untested on a device.
- Short schemes (`dm`, `penny`, `rewe`, `edeka`, `ross`, `migros`, `eroski`) can be claimed by an
  unrelated app; iOS then opens whichever it picked and `store_app_opened` still says `app`. A
  universal link goes first where the chain has one.
- The signer in a note is the APK certificate's subject as `app_schemes.py` reads it, without
  verifying the signature; a repackaged mirror APK could show any subject.
- 20 of the 68 apps open on an iPhone through a scheme read from the Android app; whether the iOS app
  registers the same one is untested on a device. A wrong one only falls through to the App Store.
- E.Leclerc, Dirk, Biedronka, Żabka Jush and Esselunga have neither a first-party universal link nor
  a scheme of their own (2026-11-21).
- Dino PL had no app on 2026-11-18.
