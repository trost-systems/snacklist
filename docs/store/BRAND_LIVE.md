# Brands named in Snacklist texts (BN-1)

One row per brand that Legal's rule BN-1 covers (`docs/store/LISTING.md`, "Brand rule BN-1"). The
columns are BN-1 point 2's, plus "Live" and "Wording until then".

- **Live** is `yes` only when the BN-1 point 1 trigger holds for an ordinary user on the day: Ops ran the
  end-to-end check and saved dated proof, Engineering Lead confirmed in writing, and Legal Review recorded
  a hash-bound brand check for the exact text. For Claude, a marketing surface (store texts, release
  notes, landing page, social, email) also needs Anthropic's written OK for the exact wording first.
- **Last verified** is the date of that check (`YYYY-MM-DD`, Europe/Berlin). Verify again on each store
  release and every week while a brand is named. A failed check sets Live to `no` the same day, and the
  brand leaves every text listed in its row within one working day (BN-1 point 7).
- **Texts that depend on it** lists every store listing file that names the brand.

`scripts/store-brands.ts` reads this table. In CI, a store description may name a brand only while its
row says Live `yes` and lists the file. On the day a text goes public, run
`deno run --allow-read scripts/store-brands.ts --publish`: every brand named must then be verified
that same day. The 2026-11-27 copy that names Siri and Alexa before either is marked live is in
`scripts/store-brands.baseline.json`, with the reason for each entry. `--publish` ignores that file.

| Brand | Live | URL | Last verified | Proof | Texts that depend on it | Wording until then |
| --- | --- | --- | --- | --- | --- | --- |
| Siri | no | - | never | - | `app/fastlane/metadata/de-DE/description.txt`, `app/fastlane/metadata/en-US/description.txt` | Kurzbefehl wording only („per Siri-Kurzbefehl“) until the native-Siri device test passes (hold `native-siri` in `releases/flags.json`), then „mit Siri“. |
| Alexa | no | - | never | - | `app/fastlane/metadata/de-DE/description.txt`, `app/fastlane/metadata/en-US/description.txt`, `app/fastlane/metadata/android/de-DE/full_description.txt`, `app/fastlane/metadata/android/en-US/full_description.txt` | Only ever „Snacklist-Skill für Amazon Alexa“ / "Snacklist skill for Amazon Alexa". |
| Claude | no | - | never | - | - | Off every marketing surface until Anthropic's written OK for the exact wording. Guides, support and in-app setup need no OK. |
| ChatGPT | no | - | never | - | - | Out until the app is approved and live, then always with the plan and country qualifier („je nach ChatGPT-Tarif und Land“). |
