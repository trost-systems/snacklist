# Job 346: categories deep dive

Research only, draft PR, never merged. The report is `docs/research/346-categories/README.md`,
and the lead's copy is `~/groceries-ops/jobs/346-categories-deep-dive/out/REPORT.md`.

- **Today:** `today.md` has file:line for the category sets, the classifier, the walk order, the UI
  and the API/MCP.
- **Repro:** 82 mock items at IKEA, dm, Baumarkt and Apotheke ran through the real classifier on a
  local stack (`repro/`).
  - 15 of 32 IKEA items land in Sonstiges.
  - 0 of 32 IKEA items and 0 of 13 Apotheke items default to their own store.
  - The Baumarkt items are 16 of 16 right.
- **Research:** `research.md` covers Bring!, AnyList, OurGroceries, Listonic, Apple Reminders,
  Todoist, learned-order apps and the retailer apps, with a URL for every claim.
- **Approaches:** CAT1 to CAT5. Recommendation CAT1 (store kinds with their own sets), runner-up
  CAT4 (plain stores without dividers). Open questions CAT-Q1 to CAT-Q11.
- **Not done:** the classifier misfires B1 to B7 are bugs. They are left for their own job,
  because this brief forbids production changes.
