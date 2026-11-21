# Job 355: Recently used, expanded (round RU, 2026-11-21)

A prototype round. The draft PR is never merged, and nothing in the app changed (Changelog: none).

## Preview

- Deployment `dpl_3A58vwdK5SrEAPKTuBi9TnoSVfid` on `family-groceries-design`. It is a preview, READY, with SSO on, no bypass and no domain. The bare URL answers 302.
- Round page: https://family-groceries-design-nipo5duub-peter-trost.vercel.app/list/ru/. The root overview's newest card links it. Add `?lang=de`, `?theme=dark`, `?ts=200` or `?ts=310`, or `?device=android`.
- It is built on `dpl_32tyoG68T6bmjtNExzpyrBHkADfE` (job 353's RD round). Those 286 files were fetched byte for byte, so older links keep working. All 329 deployed files match the build by SHA-1.
- The share link is not minted. hz has no Vercel connector, so the lead mints it.

## Round RU

- RU1 is "Faded, as today, open".
- RU2 is "Tinted tray with a peek".
- RU3 is "Chips".
- RU4 is "Ticked with checkmarks".

Every option starts open, animates the tick into the section and returns an item with one tap.

**Pick: RU2. Runner-up: RU4.** The measurement drove the pick. At scroll top no option shows one whole recent row, on any phone, at any text size, in either language, with 3 or 15 recent items. The TE1 total sits between the list and the section. So opening the section alone does not make a tick visibly land. RU2's peek on the add field is the only element that does. It costs 1 open row on a long list on the iPhone (9 instead of 10) and 2 on Android (6 instead of 8). With 0 recent items every option looks like today. The open questions RU-Q1 to RU-Q12, each with a default, are in `docs/design/list/ru/RECOMMENDATION.md` (German: `.de.md`, where they are numbered RU-F1 to RU-F12).

## How to verify

- `node docs/design/list/verify.mjs` ends `all checks passed (167)`. It also passes on the deployed folder (`--dir /tmp/p355/dist --path /list/`).
- `node docs/design/list/tools/mutate.mjs` runs six mutations, and each fails named checks (`docs/design/list/ru/MUTATIONS.md`). A seventh mutation changed a prose number, and the new prose check caught it.
- Today's tile and rows were checked against the release web build within 1 px (`ru/real/`, port block 641, stack stopped).
- Screenshots are in `docs/screenshots/355/`.

## Not done

- The share link, which the lead mints.
- The replica's 310 % open rows are shorter than the real build's (141 px against 189 px). That comes from job 347's replica. It does not change "no recent row at scroll top", because the real rows are taller still.
- The trip strip is not drawn (RU-Q10).
