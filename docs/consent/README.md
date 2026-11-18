# Analytics consent texts

One file per version of the analytics consent screen, DE and EN, word for word as the app showed
it, so we can show which text a decision was given under (Art. 7(1) DSGVO; EDPB Guidelines 05/2020
Rn. 108). The app stores the version with every decision (`consentTextVersion` in
`app/lib/analytics/consent_version.dart`), on the device and in `analytics_consents`.

| Version | File | Stored as | Shown by |
| --- | --- | --- | --- |
| 2026-11-18 | [2026-11-18.md](2026-11-18.md) | `2026-11-18` | Snacklist (job 270): 2026-11-14 with connected apps, MCP and API keys among the examples (Legal N-251) (current) |
| 2026-11-14 | [2026-11-14.md](2026-11-14.md) | `2026-11-14` | Snacklist (job 216): 2026-11-11 with Siri among the examples (Legal N-146); the server stopped counting its yes with 2026-11-18 (N-251) |
| 2026-11-11 | [2026-11-11.md](2026-11-11.md) | `2026-11-11` | Snacklist (job 178): 2026-11-10 with examples of the usage data; the server stopped counting its yes with 2026-11-14 (N-146) |
| 2026-11-10 | [2026-11-10.md](2026-11-10.md) | `2026-11-10` | Snacklist (job 174): 2026-11-01 with the new name; the server stopped counting its yes with 2026-11-11 (N-125) |
| 2026-11-01 | [2026-11-01.md](2026-11-01.md) | `2026-11-01` | Hummlist, from the release after PR "Consent text version and re-ask" on; the server stopped counting its yes with 2026-11-11 (N-125) |
| PR #165 text | [2026-11-01-pr165.md](2026-11-01-pr165.md) | nothing (no version field yet) | builds with #165, before this version field |
| 2026-10-30 | [2026-10-30.md](2026-10-30.md) | nothing (no version field yet) | builds up to b5d0fee |

A yes without a version, or with any version but the current one, counts as no decision: the app
sends nothing (no events, no `/flags`), deletes the install id and the SDK's data on the device, as
on a no, and asks again. The server sends no event for it either (`analyticsSubject`).

Changing the text: add a file here, set the new date in `consent_version.dart` and
`supabase/functions/_shared/consent_version.ts`, keep the old file.
