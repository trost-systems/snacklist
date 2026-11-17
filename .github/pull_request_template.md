## What

<!-- What changed, for whom. -->

## Why

## How verified

- [ ] User-facing behaviour changed? The feature file in `.cursor/skills/verify-snacklist/features/` and its section in `FEATURES-FOR-WRITERS.md` (last verified: commit and date) are updated in this PR (`docs/FEATURE_MAP.md`).

<!-- Commands and results, the green CI run, screenshots where the UI changed. -->

## Changelog

<!--
What users of the app notice, for the stores' "What's new" and snacklist.app/changelog
(docs/CHANGELOG.md). scripts/push-pr.sh lands this section in the commit main takes; CI checks
its structure.

One paragraph per item: a category line (new, improved or fixed), then one sentence in German
(de:) and one in English (en:). Write in user words what the user can now do or what now works.
No job or PR numbers, file, table or tool names.

Leave out what users don't see: typo and copy fixes, refactors, CI, docs, tests, lints, deploys,
server internals. Add a fix only if a user could have noticed the bug. If nothing here is
visible to users, write only: none

Not everyone has it yet? Add "flag: <key>" when the item ships behind a feature flag, or
"hold: <key>" when it waits for something else (a feature not launched yet: hold: premium-launch).
The key must be in releases/flags.json; the item stays out of the public changelog until that
file opens its gate.

These items are also the testers' TestFlight notes. A PR that changes nothing users run (Nexus,
CI, scripts, docs, tests, the site) never shows up there or in the changelog. For an internal
change in the app's own code, add a paragraph "Changelog: skip" above this section
(docs/RELEASE.md, "Internal work stays out").

Example:

new
de: Mit Alexa fügst du Artikel per Sprache hinzu: „Alexa, sag Snacklist, füg Milch hinzu“.
en: Add items with Alexa: "Alexa, tell Snacklist to add milk".

fixed
de: Die Liste springt beim Abhaken nicht mehr nach oben.
en: The list no longer jumps to the top when you check off an item.
-->
