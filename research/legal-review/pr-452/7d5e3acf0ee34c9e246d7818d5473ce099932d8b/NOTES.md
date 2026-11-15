# PR #452 rebased on merged #464 (job 250, 15 Nov 2026)

- Head: 7d5e3acf0ee34c9e246d7818d5473ce099932d8b (PR #452, branch job/233-policy-followups-n156-n177), base e8e45493 (#464).
- ci-ok: pass, run https://github.com/trost-systems/snacklist/actions/runs/43706058678
- sha256 datenschutz.md 42740a7a749bc2034cef0ac1113e2cdc5e15fdda10409b560a4374057bd2c2a4
- sha256 privacy.md 1f0c8ad1c9344c6eca6088e130ca0a5d74a8a7f55b759f90875f0077a4f3bb35
- Both equal Legal's *.updated-15.md reference (§16 "Reference result") byte for byte.
- check-expected.sh compares with the non-updated files and reports MISMATCH on line 7 only (`updated: 2026-11-15` vs `2026-11-14`). Main already carries 2026-11-15 from #464 (C-2), so the updated-15 pair is the one that applies; no other difference.
- Diff vs e8e45493: only the two legal files, 3 lines each (six #452 texts N-156, N-177 to N-182 plus N-185 export sentence with trips and price). N-178 sits in #464's Änderungsverlauf sentence (N-184). N-186: Stand 15 November 2026 inherited.
- Method: cherry-pick of 9f513126 conflicted (2 per file, as Legal predicted); resolved with Legal's reference files, then verified the diff is limited as above. Not merged, no flags.
