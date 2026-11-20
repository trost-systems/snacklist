# Retailer registry

`retailers.json` lists grocery and drugstore chains per country with their apps. Snacklist links a
store to one entry and opens its app, or the app's store page when the app is missing. Job 314
researched the entries on 2026-11-18; job 313 turned them into this file and `public.retailers`.

## An entry

- `chain` and `country` (ISO alpha-2) are the key. One chain can have a different app per country
  (ALDI SÜD, PENNY, Carrefour) or the same one everywhere (Lidl Plus).
- `name` is what the household sees. `aliases` are further lower-case names people type for it
  ("aldi", "netto", "eurospar"), three characters or more. Matching folds case, accents and
  punctuation (`public.retailer_key`).
- `apps` lists every app with both store ids. The first one is the default, the chain's loyalty or
  coupon app where it has one; a household can pick another one per store. `universalLink` is a
  URL the retailer's AASA claims for the app, or null with the reason in `note`.
- `status` is `verified`, or `no-app` with the evidence in `note` (Dino PL).

## Changing it

1. Edit `retailers.json` and run `deno run --allow-read --allow-net scripts/retailers.ts --verify --only DE`
   for the countries you touched.
2. Run `deno run --allow-read --allow-write scripts/retailers.ts --migration`. It writes a new
   migration that upserts every entry and deletes the others; stores of a deleted entry lose their
   link. The lint gate (`--check`) fails while the newest migration's rows differ from the file.

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
- Dino PL had no app on 2026-11-18.
