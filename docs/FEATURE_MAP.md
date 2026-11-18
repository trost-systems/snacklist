# Feature map

This file points at the code-backed inventory: what Snacklist does today. The product candidate map
(built, planned, considering, dropped, and the product decisions behind them) is
[`PRODUCT_FEATURE_MAP.md`](PRODUCT_FEATURE_MAP.md).

`.cursor/skills/verify-snacklist/features/` describes what Snacklist does today, one file per
user-facing feature (index: its `README.md`). `FEATURES-FOR-WRITERS.md` in the same folder is
the plain-language version with the exact German and English labels, a "never claim" list per
feature and the commit each section was last verified on. Snacklist PM and anyone writing
emails, site copy or instructions works from it.

**Whenever user-facing behaviour changes, update the feature file and its section in
FEATURES-FOR-WRITERS.md (including "Last verified") in the same PR.** The PR template has a
checkbox for it.

- Prove a feature on the real web build: the verify-snacklist skill
  (`.cursor/skills/verify-snacklist/SKILL.md`): `helpers/launch.sh`, `helpers/doctor.sh`,
  `helpers/drive.sh <feature-id>`, `helpers/cleanup.sh`.
- Film a how-to clip (email GIF, MP4/WebM, PNG) of a feature: the snacklist-howto-clips skill
  (`.cursor/skills/snacklist-howto-clips/SKILL.md`).
- The older verify-family-groceries skill (`scripts/fg`, the Linux desktop app, `fg sync`,
  scenarios) stays; its `features/` folder is no longer the current map.
- Copies for writers outside the repo: the box's `/workspace/hummlist/feature-map/` (this folder)
  and `/workspace/hummlist/clips/<feature-id>/` (clips), refreshed by the lead.
