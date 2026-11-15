# PR #464 delta: Legal GO corrections C-1, C-2 and addendum 1

Reviewed head (GO, review section 15): 8b44d0b130b5fdb088a7efe8eac6b281892fb2c4.
Corrected code head: a347064a48956a39fcc4ec6aba45ec9b13eeaf03, ci-ok green, run 43685313627. The PR head after this folder is added is a later commit that changes only research/legal-review/pr-464/ (a commit cannot name its own SHA); its ci-ok run is in the NEEDS_LEAD entry.

Diff of the two legal files, 8b44d0b1 to a347064a48956a39fcc4ec6aba45ec9b13eeaf03 (see DELTA.diff), is exactly:
- C-1: datenschutz.md "siehe oben" -> "siehe unten"; privacy.md "see above" -> "see below".
- C-2: "Stand: 14. November 2026" -> "15. November 2026"; "Last updated: 14 November 2026" -> "15 November 2026".
- Addendum 1: frontmatter `updated: 2026-11-14` -> `updated: 2026-11-15` in both files.

| File | sha256 at a347064a48956a39fcc4ec6aba45ec9b13eeaf03 |
| --- | --- |
| site/content/legal/datenschutz.md | 8765759c72895b3326c915072a552822081bfbf2dda14309b4fc783924cef4fd |
| site/content/legal/privacy.md | 90820004ce623013cf9844c15a442c4095cfd30e8ab3aa46deccfa983f021dd7 |
