# Changelog

What each Snacklist version brings users. The same notes feed two places: the
stores' "What's new" text and the pages
[snacklist.app/de/changelog](https://snacklist.app/de/changelog) and
[snacklist.app/en/changelog](https://snacklist.app/en/changelog). Each PR
writes its own note, so nobody has to reconstruct a release afterwards.
Decisions and reasons are in [`DECISIONS.md`](DECISIONS.md), "Job 39" and
"Job 40".

## The note in every PR

Every PR description has a `## Changelog` section
([`.github/pull_request_template.md`](../.github/pull_request_template.md)).
It holds one or more items. Each item is a paragraph of three lines: a
category, then one German and one English sentence.

```
## Changelog
new
de: Die Liste sortiert sich nach deinem Einkauf.
en: The list sorts itself after your shopping trip.

fixed
de: Die Liste springt beim Abhaken nicht mehr nach oben.
en: The list no longer jumps to the top when you check off an item.
```

If users see no change, the whole section is the single word `none`.

An item may also have a `flag:` line, a `hold:` line, or both, when users
don't get it yet ("Gated items" below).

| Category | For |
| --- | --- |
| `new` | Something users can do that they couldn't before |
| `improved` | Something that works better, faster or more clearly |
| `fixed` | A bug a user could have noticed |

What to write:

- Write in user words: what the user can now do, or what now works.
- Write one plain sentence per language.
- Don't name jobs, PRs, files, tables or internal tools.

What to leave out: typo and copy fixes, refactors, CI, docs, tests, lints,
deploys and server internals. Add a fix only if a user could have noticed the
bug.

The parser (`scripts/release/changelog.mjs`, `parseNote`) is strict about
structure and lenient about wording. It accepts:

- any case, a trailing colon or full stop (`Fixed:`, `None.`)
- Markdown around the word (`**New:**`, `` `none` ``)
- a remark in brackets (`none (docs only)`)
- list dashes (`- de: …`)
- the German words `neu`, `verbessert`, `behoben` and `keine`

It rejects these, each with a message:

- a heading that is almost the right one (`### Changelog`, `## Changelog:`)

- an unknown category
- an item without a `de:` or an `en:` line
- a line that is not `de:`, `en:`, `flag:` or `hold:`
- two `flag:` or two `hold:` lines in one item, or a key that is not
  `[a-z0-9][a-z0-9._-]*`
- an empty line or a duplicate line
- `none` together with items
- an empty section
- two `## Changelog` sections

The section ends at the next heading or `---` rule. A paragraph that is
neither an item nor `none` also ends it, so the "Generated with" line and the
trailers after it are not part of it. HTML comments (the template's guidance)
are ignored.

## Where it is checked

- **`scripts/push-pr.sh`** checks the PR description before it squashes.
  - **No section, and nothing users could notice changes:** it adds
    `## Changelog` + `none` to the description (`gh pr edit`) and continues.
    Users notice the app build, by the Release run's own rule
    (`scripts/release/plan.sh ships-app`: `app/` or
    `.github/workflows/release.yml`). They also notice the backend, which
    goes live from `main` without an app release: `supabase/` (functions,
    migrations, the classifier) and `alexa/`. Docs, CI, scripts, the site,
    tests and `releases/` need no note. A Dependabot branch (`dependabot/…`)
    gets `none` too.
  - **No section, and the app or backend changes:** it stops and prints the
    format. For a backend change users can't see, write `none`.
  - **An invalid section:** it always stops.
- **CI** checks the structure, never the wording, in the `changelog` gate
  (`scripts/gates/changelog.sh`), a job that `ci-ok` waits for. It runs on
  pull requests only. It skips Dependabot (its bumps change nothing users
  see, and their PRs have no note) and pushes to `main`. It checks the PR
  head's commit message, which is what `main` takes. A head pushed without
  push-pr.sh has no section in its message yet; then the PR description in
  the event counts. The same gate checks every draft in `releases/changelog/`
  (`changelog.mjs drafts`): each must be valid, be named `<version>.json`,
  and have store texts that match its title and items (or its override).
  It also checks `releases/flags.json`, `pending.json` and every
  `<version>.override.md`, and that every flag and hold they name is in
  `flags.json`. A flag can't leave the file while an item still waits for it.

Commits without a section count as `none`. These are everything before job
39, release record commits and Dependabot PRs. Older PRs are not backfilled.

## Gated items (job 40)

Peter's rule: a feature that is behind a feature flag, or not ready for
everyone (an unlaunched feature such as Premium), stays out of the
public changelog until everyone has it. Its item says why it waits:

```
new
de: Listen sortieren sich nach deinem Einkauf.
en: Lists sort themselves after your shopping trip.
flag: smart-sort
```

- `flag: <key>`: the item ships behind the feature flag `<key>`.
- `hold: <key>`: the item waits for something else, such as
  `hold: premium-launch`.

[`releases/flags.json`](../releases/flags.json) says which gates are open:

```json
{
  "flags": { "smart-sort": { "rollout": "partial", "note": "half the households" } },
  "holds": { "premium-launch": { "released": false, "note": "Premium is not on sale yet", "match": ["premium"] } }
}
```

An item is public only when its flag's `rollout` is `full` (not `partial`
or `off`) and its hold is `released: true`. A key that is not in the file is
an error everywhere: in push-pr.sh, in the CI gate and in `draft`. A typo
never makes an item public, and a PR that adds a flagged item adds its flag to
the file. `match` lists words: while the hold is not released, an item that
mentions one of them (at the start of a word, so "Alexas" and "Alexa-Skill"
count, in German or English) must carry that hold. push-pr.sh and the gate
refuse such an item without the line. If one reaches `main` anyway, `draft`
holds it back and warns.
An item with a closed hold of its own may name another hold's word (the
integration lock's item, `hold: integration-lock`, names Premium): it stays
back until both holds are released.

What a draft or an override would publish is checked again, in the
changelog gate and in `record.mjs`: every item's gate must still be open, and
no title or store text may mention a held word. A flag set back to `partial`
after the draft, an item moved out of `held` by hand, or an override that
names Alexa fails with the reason. Redraft with `--force` after fixing
`flags.json`.

Two kinds of flags, two places (job 44). Runtime toggles in the app are
PostHog feature flags, read through `Analytics.flags.isOn(key)`
([`docs/ANALYTICS.md`](ANALYTICS.md), "Feature flags"). A new key in
`app/lib/analytics/flags.dart` becomes a PostHog flag for internal installs
once it is on main (job 332). For the changelog, `flags.json` says whether a
feature's changelog item is public yet. A feature behind a PostHog flag gets
a key of the same name here, and `flags.json` is updated by hand, in a PR,
when the PostHog rollout changes (`full` once everyone has it). Release and
changelog holds (`hold:`) live only here. The changelog tooling never
reads PostHog. A later job may add a read-only check that compares the two.
A flag may also carry `min_version` (`"1.4.0"`, `"1.4.0+1420"` or an object
with `default` and a version per platform): the lowest app version that gets
the flag. The changelog ignores it; it is the one field PostHog reads: the flag sync writes it into the
flag's conditions (docs/ANALYTICS.md, "Flags from main and minimum
versions").

What happens to a gated item:

1. **`draft`** puts an item whose gate is closed under `held` in the draft,
   with its category, flag, hold, PR and commit. `held` is never shown and
   is in no store text. The dry run lists it under "held, not public".
2. **`record.mjs add`** writes the held items into
   `releases/changelog/pending.json` in the release commit. Items merged after
   the draft's commit that carry a gate go there too, so nothing is lost.
3. **The next `draft`** reads `pending.json` first. An item whose gate is open
   now joins the draft in its category, ahead of the new items, and keeps its
   `flag` / `hold` field for tracing. The dry run lists it under "from
   pending.json, gate open now". An item whose gate is still closed stays
   under `held`.
4. **The next `record.mjs add`** drops the published items from
   `pending.json`. It refuses a draft that neither publishes nor holds an item
   of `pending.json`, so a hand edit can't lose one.

`record.mjs` also refuses a draft collected at a commit that is not the
release commit or one before it (another branch, or past the release), since
it would drop or repeat items. A draft without `held` (from before job 40)
is refused while `pending.json` has items.

`draft` never writes `pending.json`. A draft that is thrown away or redrafted
with `--force` costs nothing (DECISIONS, "Job 40").

## Override (job 40)

For a release whose "What's new" should not be the list of items (the 1.0
launch, written for people who don't know Snacklist yet), write
`releases/changelog/<version>.override.md`:

```markdown
status: draft — pending Peter's review

# Snacklist 1.0.0

## de
title: Willkommen bei Snacklist

### play
Kurzer Text für Google Play.

### app_store
Längerer Text für den App Store.

## en
title: Welcome to Snacklist

One text for both stores.
```

- `## de` and `## en` are both required. Each starts with a `title:` line,
  the headline on snacklist.app and in the draft.
- Then comes one text for both stores, or a `### play` and an
  `### app_store` block (both, not just one). One text must fit Play's 500.
- The text is the whole "What's new", as written. The title is not added to
  it, so start the text with the headline if the store should show one.
  Emoji and `<` are removed, as for generated texts. A text over its limit
  fails, with its length.
- A `# ` heading and HTML comments are allowed. A `status: draft` line
  before `## de` marks the text as not approved.

`draft` and `store` take the title and both store texts from the override.
The items stay as collected, and snacklist.app lists them under the title.
To leave an item off the page, delete it from the draft during the review.
The changelog gate and `record.mjs` refuse a draft whose title or store texts
differ from its override; run `store` after editing the override.

**Approval.** While the override has `status: draft`, `record.mjs add`
refuses to record the version as a public release (a dry run only warns).
Peter approves the text by deleting that line in a PR. `record.mjs` deletes
the override together with the draft, since the record holds the texts
from then on. An override without its draft can't be recorded: run `draft`
first.

The 1.0.0 launch text is
[`releases/changelog/1.0.0.override.md`](../releases/changelog/1.0.0.override.md),
waiting for Peter's review.

## Rewording an item on main (job 213)

An item's text lives in its commit message on `main`, which can't change. When
a merged item turns out wrong before it is published (the integration lock's
held item named Siri, which stays free since job 184), give it new wording in
[`releases/changelog/rewords.json`](../releases/changelog/rewords.json):

```json
{
  "items": [
    {
      "sha": "<the commit on main, 40 hex>",
      "item": 2,
      "why": "what was wrong, for the reviewer",
      "de": "Der neue deutsche Satz.",
      "en": "The new English sentence."
    }
  ]
}
```

- `item` counts the items of that commit's note from 1, in the order written.
- An item users never saw (a fix that changed nothing) is taken out with
  `"drop": true` instead of `de` and `en`; `why` says what was wrong.
- Only `de` and `en` change. The category, the flag or hold, the PR and the
  commit stay the note's, so a held item stays held.
- `draft` and `record.mjs` (for items merged after a draft) read the new
  wording when they collect the commit, so a draft, its store texts and
  `pending.json` only ever hold the new text. A reword of an item the note
  doesn't have refuses the draft; the `drafts` check validates the file.
- TestFlight's "What to Test" (`notes`) keeps the commit's text: it reads
  only the newest commits, never one old enough to need a reword.
- A reword whose commit is already in a public release changes nothing:
  the record holds that text. Delete the entry when its item is published.

## Collecting a release

```bash
node scripts/release/changelog.mjs draft --version 1.0.0 --sha <main commit> --dry-run
node scripts/release/changelog.mjs draft --version 1.0.0 --sha <main commit>
```

`draft` reads main's first-parent commits from the previous public release up
to `--sha`. The previous release is the newest one in
`releases/releases.json`. Without one, it reads from the root commit.
`--previous-sha` sets the start by hand. The script reads git only: no
GitHub API, no network, no LLM.

What `draft` does with the notes:

- It drops `none` and commits without a section.
- It drops the items of internal commits: no changed path that reaches users,
  or a `Changelog: skip` line (`docs/RELEASE.md`, "Internal work stays out").
  It prints a warning for each, so a wrongly dropped item can go back in by
  hand.
- It holds back an item whose flag or hold is closed (above) and adds the
  items of `pending.json` whose gate is open now.
- It groups the items as new, improved, fixed, in merge order (oldest first)
  within each group.
- It drops an item whose German and English sentences are identical to an
  earlier one.
- It keeps each item's PR number and commit for tracing. The site never shows
  them.

It writes `releases/changelog/<version>.json`. `--out` writes the file
somewhere else instead. `--dry-run` prints the JSON and both store texts with
their lengths, and writes nothing. A release with no item prints a warning,
because a release with nothing users notice is suspicious.

An invalid section on `main` (only possible past CI) stops `draft` and names
the commit. Write that item into the draft by hand, then rerun with
`--skip <sha>`.

`draft` never overwrites an existing draft, because it may hold reviewed
wording. Edit the draft by hand, or pass `--force` to replace it.

The draft's `title` (`de`, `en`) starts empty. During the review, give it a
headline that names the 2-3 biggest things. After editing the title or the
items, run

```bash
node scripts/release/changelog.mjs store --version 1.0.0
```

It rewrites the draft's store texts from the edited wording. The changelog
gate and `record.mjs` refuse a draft whose store texts don't match its title
and items, so an edit can't reach the stores half-applied. An item added by
hand needs `pr` (a number, or `null`) and `sha` (the release commit will do).

## Store texts

Each draft holds four texts: `store.app_store` and `store.play`, each in
`de` and `en`. Each text has the title (if any), then `Neu:` / `New:`,
`Verbessert:` / `Improved:` and `Behoben:` / `Fixed:` with one `•` line per
item. An item that is empty after stripping (only emoji) gets no line. With
no items it is "Fehlerbehebungen und Verbesserungen." / "Bug fixes and
improvements."

| Store | Limit | Counted as | Source |
| --- | --- | --- | --- |
| App Store | 4000 | UTF-8 bytes. Apple says "characters"; fastlane's pilot cuts at 4000 bytes, the strictest reading, so "ä" counts 2 | App Store Connect Help, "Platform version information": "Limited to 4000 characters." |
| Google Play | 500 | Unicode characters (code points, after NFC) | Play Console Help, answer 9859348: "up to 500 Unicode characters per language" |

When a text is too long, whole items go from the end: fixed first, then
improved, then new. A last line then points to the full list: "Alle
Änderungen: snacklist.app/de/changelog#v1-0-0" / "All changes:
snacklist.app/en/changelog#v1-0-0". A sentence is never cut. Emoji and `<` are
removed from both stores' texts, as fastlane's `sanitize_changelog` does,
because Apple rejects them. Emoji means what shows as emoji: emoji
presentation, or a symbol with the emoji selector. Text symbols such as ©, ™,
arrows or a plain ✔ stay. The site shows the items unchanged.

`parseRecord` and `parseDraft` (`site/releases.mjs`) reject a store text over
its limit. A text edited by hand can't slip past them.

## Publishing

The order of steps is in [`RELEASE.md`](RELEASE.md), "Public releases":

1. A PR commits the draft.
2. Peter reviews it and approves the release.
3. After the stores accept the build, the Public release record workflow moves
   the draft into `releases/releases.json` and deletes the draft file.
4. That push redeploys snacklist.app, which shows the version from then on.

Preview builds of the site also show drafts whose version is not in the
record yet, with a banner. Production shows only recorded releases ([`site/README.md`](../site/README.md),
"Changelog").
