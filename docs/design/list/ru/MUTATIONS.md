# Mutations (round RU)

`node docs/design/list/tools/mutate.mjs` builds the round into a temporary folder, applies one mutation, runs
`verify.mjs` on it, and lists the checks that failed. Every mutation must fail at least one check.

| Mutation | Checks that fail |
| --- | --- |
| RU3 starts collapsed (its chips hidden) | RU3: the section is expanded by default (short-3 frame); RU3: the live phone starts expanded; RU3: the ticked item is first in the section (no-preference); RU3: one tap on the ticked item in the section (no-preference); RU3: the ticked item is first in the section (reduce); RU3: one tap on the ticked item in the section (reduce); ru/measured.json equals a fresh measure; RECOMMENDATION.md's measured table matches the measure; RECOMMENDATION.de.md's measured table matches the measure |
| A tap-back puts the item at the end of the list | RU1: one tap puts it back at its place (no-preference); RU2: one tap puts it back at its place (no-preference); RU3: one tap puts it back at its place (no-preference); RU4: one tap puts it back at its place (no-preference); RU1: one tap puts it back at its place (reduce); RU2: one tap puts it back at its place (reduce); RU3: one tap puts it back at its place (reduce); RU4: one tap puts it back at its place (reduce) |
| One measured number changed (en ios 100 short-3 RU1 active 5 → 6) | ru/measured.json equals a fresh measure |
| RU2’s peek pill holds the second-newest item | RU2: the peek holds the newest item; RU2: one click on the peek pill returns the newest item; ru/measured.json equals a fresh measure |
| RU3’s chips get a hexagon cell | RU3: no hex element in the recent section or peek; ru/measured.json equals a fresh measure |
| A tick appends to the end of Recently used | RU1: the ticked item is first in the section (no-preference); RU2: the ticked item is first in the section (no-preference); RU3: the ticked item is first in the section (no-preference); RU4: the ticked item is first in the section (no-preference); RU1: the ticked item is first in the section (reduce); RU2: the ticked item is first in the section (reduce); RU3: the ticked item is first in the section (reduce); RU4: the ticked item is first in the section (reduce) |
