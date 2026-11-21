# Round RD: Snacklist without hexagons (job 353)

Peter asked for 10 mocks of different designs away from the hexagons, with other corner radii and a new look at the
menu, keeping today's colours. This round is a throwaway prototype. Nothing in the app changed.

- Page: `docs/design/redesign/rd/` (English; `?lang=de` for German, `?theme=dark`, `?ts=200` or `?ts=310`).
- Every option is drawn on the same list: job 350's list with the categories hidden and job 348's TE1 total. The
  household is the fictional Brandt family. All data is mock data.
- Each option has six frames: the list, a tick, the menu open, the add sheet with the keyboard, More (or, where the
  menu holds every place, that menu scrolled to its end) and the empty list.
- Every place today's More tab leads to is in every option: Start a trip, Account (Premium sits inside it), Access,
  Settings, Usage data, Tips, Feedback & ideas, Rate Snacklist, Help & contact, Imprint, Privacy policy, Terms of Use
  and Licenses, and Sign out (`more_screen.dart`, as an iPhone shows it). So are History, Edit (today's „Anpassen“,
  where the stores are) and switching lists. `places.js` says where each one goes in each option.
- The colours are exactly today's tokens. `palette.css` is generated from `app/lib/design/tokens.g.dart`, and
  `verify.mjs` fails if any phone paints a colour outside it. Shapes, menus, rows, ticks and type are open.
- Where the hexagons are today: `HEX-INVENTORY.md` (135 direct call sites in 46 files, about 227 more through the
  theme, plus the icon, the store frames and the site).

## The ten options

| Option | Corners | Menu | Cost |
| --- | --- | --- | --- |
| RD1 Soft swap | soft: 8 chip, 12 button and field, 20 bar, 24 sheet | today's floating tab bar | cheap: tokens only |
| RD2 Pill dock | pill on every control, 28 sheet | no tab bar; a menu button beside the add field opens one sheet with the lists, History and every More row; Edit stays top right | structural |
| RD3 Docked tabs | 6 box, 8 button and field, 16 sheet | full-width tab bar with four tabs (Stores gets one), large title | structural |
| RD4 One screen | nested by size: 4 small, 12 medium, 20 large | no tabs; the title drops a panel with households, lists, History and every More row | structural |
| RD5 Store cards | 12 chip, 16 button, 24 card and sheet, round add button | bottom bar with four tabs around a round add button | structural |
| RD6 Side drawer | squircle (continuous corners) 10 / 18 / 28 | menu button top left opens a drawer with the lists, History and every More row | structural |
| RD7 People first | circles for people and ticks, 10 for the rest | List and History as segments on top; the household's avatars open a sheet with Edit and every More row | structural |
| RD8 Store tabs | tight: 4 and 6, 12 sheet | tabs per store under the title; a ••• menu with History, Edit, Start a trip, Settings, the legal links and More (Account and the rest) | structural |
| RD9 Receipt | sharp 2 everywhere; a torn edge is the motif | today's three tabs as a docked text bar | medium: widgets redrawn |
| RD10 Bite | round 20, with a round bite out of one corner of the hero controls | floating tab capsule plus a separate round add button | structural |

What each option also changes, and why, is on the page under its name. In short:

- **RD1** keeps every screen. Only the shape changes (inventory: setting `HlHex.tip` to 0 turns `HexBorder` into a
  rounded rectangle; `PointyHex`, the radio, switch, segmented control and checkbox still need their own rewrite).
- **RD2** makes the list the app. The bottom holds a round menu button and the add field. Rows lose their dividers
  and get a round check at the start. The contour stays, and the hard sticker shadow goes.
- **RD3** is what iOS and Android users already know: flat surfaces, hairlines, and a check box at the end of a row.
- **RD4** is the densest: 44 px rows and a docked add field. Radii follow the size of the part.
- **RD5** puts each store in a card with its sum, and the add field becomes a round button. Tapping it opens the sheet
  in one tap, as tapping today's field does, but the "What do you need?" prompt leaves the list.
- **RD6** uses continuous corners (Flutter: `RoundedSuperellipseBorder`; the page shows them in Chrome, and Safari
  draws plain rounded corners). A swipe to the right ticks.
- **RD7** puts the household's people in the corner and shows quantities as small badges.
- **RD8** filters the list to one store, for use in the shop.
- **RD9** draws the list as the receipt it becomes: dotted leaders to the prices and a torn edge under the total.
- **RD10** replaces the honeycomb with a bite as the brand motif. It also works for the app icon (RD-Q4).

## Measurements

<!-- table -->
| Option | Cost | Whole rows, 100 % | Whole rows, 310 % | Smallest tap target | Lowest text contrast, light / dark | Lowest border contrast, light / dark | Overflows at 310 % | Words broken at 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Today | today | 7 | 1 | 44 px | 7.1 / 8.43 | – / – | 0 | 29 |
| RD1 Soft swap | cheap (tokens only) | 7 | 2 | 44 px | 7.1 / 8.43 | 7.1 / 5.12 | 0 | 7 |
| **RD2 Pill dock** | structural | 8 | 2 | 44 px | 6.63 / 8.43 | 7.1 / 5.12 | 0 | 16 |
| RD3 Docked tabs | structural | 7 | 2 | 44 px | 7.1 / 8.43 | 7.1 / 8.43 | 0 | 7 |
| RD4 One screen (runner-up) | structural | 10 | 2 | 44 px | 7.1 / 8.43 | 7.1 / 5.12 | 0 | 16 |
| RD5 Store cards | structural | 8 | 2 | 44 px | 7.1 / 8.43 | 8.87 / 8.43 | 0 | 9 |
| RD6 Side drawer | structural | 9 | 2 | 44 px | 6.63 / 8.56 | 7.1 / 9.68 | 0 | 17 |
| RD7 People first | structural | 7 | 2 | 44 px | 6.63 / 8.43 | 7.1 / 5.12 | 0 | 10 |
| RD8 Store tabs | structural | 8 | 2 | 44 px | 7.1 / 8.43 | 8.87 / 5.12 | 0 | 5 |
| RD9 Receipt | medium (widgets) | 7 | 2 | 44 px | 7.1 / 8.43 | 8.87 / 8.43 | 0 | 7 |
| RD10 Bite | structural | 8 | 2 | 44 px | 7.1 / 8.43 | 7.1 / 5.12 | 0 | 8 |
<!-- /table -->

How it was measured. `verify.mjs` renders every option × frame × light and dark × 100, 200 and 310 % text ×
English and German (792 phones) in Chromium and measures each one with `measure.js`. It measures what the phone shows
at rest, then scrolls every scrolling area (the list down to its total, a long menu) page by page and measures again, so
nothing below the first screen escapes:

- **Whole rows.** Item rows wholly between the top bar and the bottom bar on the list frame (English, light). The phone
  is a 390 × 844 iPhone screen with its 47 px status bar and 34 px home indicator. Job 347's counts (9 today) were
  taken in the web build's window, which has no status bar or home indicator, so they are about 80 px taller.
- **Smallest tap target.** The smaller side of anything tappable and not covered: rows, chips, tabs, menu rows,
  buttons. The check fails under 44 px.
- **Text contrast.** WCAG ratio of every text against the colour painted under it. The check fails under 4.5, or
  under 3 for large text.
- **Border contrast.** For each control, the larger of its border or its fill against the ground. The check fails
  under 3 (WCAG 1.4.11). Today draws its outlines as hex shadows, which this check cannot read, hence "–".
- **Overflows.** Text that is cut, leaves the screen, or overlaps other text, at 310 %, over all frames, both themes
  and both languages. The check fails on any.
- **Words broken.** Words split across two lines at 310 % (light, both languages). This is reported, not failed:
  long German words such as „Einkaufsliste“ must break at the largest size.
- The table's numbers come from `rd/measured.json` (`tools/table.mjs`), and `verify.mjs` checks every cell against a
  fresh run.

Taps from the list to each place, from each menu's design (`places.js`, not measured; `verify.mjs` checks this table
against it and that every option draws a way to all 16 places). The other More rows (Access, Usage data, Tips,
Feedback, Rate, Help, the other legal pages) take as many taps as Account, except in RD8, where Settings and the legal
pages sit in the ••• menu (2) and the rest behind its More row (3):

<!-- taps -->
| Option | History | Edit (stores) | Start a trip | Account | Settings | Imprint | Sign out | Another list | Account and the rest open from |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Today | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
| RD1 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
| RD2 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | menu button, bottom |
| RD3 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
| RD4 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | title, top |
| RD5 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
| RD6 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | menu button, top |
| RD7 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | avatars, top |
| RD8 | 2 | 2 | 2 | 3 | 2 | 2 | 3 | 2 | ••• button, top |
| RD9 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
| RD10 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | tab bar |
<!-- /taps -->

The imprint stays 2 taps from the list in every option. `more_screen.dart` keeps the legal pages one tap from the More
tab for the German Digital Services Act (DDG §5); RD8 keeps them in its ••• menu for the same reason.

What the numbers say:

- No option fails a check. Every one keeps 44 px targets, WCAG contrast in both themes and no overflow, so the
  palette survives every shape.
- Rows separate them. RD4 shows 3 more rows than Today, RD6 2 more, and RD2, RD5, RD8 and RD10 one more. RD1, RD3,
  RD7 and RD9 show as many as Today.
- At 310 % every RD option shows 2 whole rows against Today's 1. They use the same large-text rule: the price moves
  under the name, and headings stop growing at 200 % (RD-Q6).
- The total follows job 348's rule at large text: an amount too wide beside its name goes under it, whole.
- Broken words: Today breaks 29 at 310 %, the RD options 5 to 17. The options whose one menu holds every place (RD2,
  RD4, RD6) break the most, because a long menu shows more long German words.

## Recommendation

**Pick: RD2 Pill dock.** It answers both of Peter's asks with the smallest change to how people use the list:

- The hexagons become pills, a friendly shape that suits a snack app.
- The tab bar goes. History and every row of today's More tab live in one menu sheet that also switches lists, each
  2 taps away as today. Edit stays top right, 1 tap, as today.
- The menu button sits next to the add field in thumb reach, so the bottom of the screen is one line.
- The list gains a row (8 against 7).
- Adding is unchanged: the field is always there.
- The cost is one more tap to History (2 instead of 1). That History is opened less than the list is an assumption,
  not a measurement. RD-Q2 has the analytics check.
- The menu sheet is long (16 rows and the lists). It opens with the lists and History on top; Account and the rest
  need a scroll, as on today's More tab.

**Runner-up: RD4 One screen.** It is the densest list: 10 rows against 7. Its radii follow the size of each part,
which is the most principled radius system of the ten. Its menu sits under the title at the top, out of thumb reach
on a large phone. That is why it comes second.

**Ship in two steps (RD-Q1).**

1. **RD1 first.** It is tokens only, so the hexagons leave every screen within days: `HlHex.tip` → 0 (prove it with
   goldens first), plus rewrites of `PointyHex`, `HexRadio`, `HexSwitch`, `HexSegmented` and `HexCheckbox`.
2. **Then RD2's dock and menu sheet**, behind a flag.

RD1 alone already answers the users who dislike the hexagons. RD2 is then a smaller, separate change.

Not picked, and why:

- **RD3:** standard, but it adds a tab where Peter asked to rethink the menu.
- **RD5 and RD10:** the add field becomes a button, and the "What do you need?" prompt leaves the list.
- **RD6 and RD8:** the menu sits top right or top left.
- **RD7:** it gains no rows.
- **RD9:** a strong look for the totals, but the dotted leaders pull every row toward money, and a row without a price
  leads to „+ Price“.

## Open questions (defaults apply unless Peter says otherwise)

- **RD-Q1: two steps?** Default: yes. RD1's token swap first, then RD2's dock behind a new flag (`pill-dock`).
- **RD-Q2: History without a tab.** Default: History is the menu sheet's first place, under the lists. Check the PostHog screen views of
  History against List before building. If History is opened often,
  RD3's or RD9's tab bar keeps it at 1 tap.
- **RD-Q3: a row without a price.** RD2 keeps a small „+“ at the row's end, which sets the price as today's „+ Preis“
  chip does. RD3, RD4 and RD8 show nothing, and the price is set in the item's sheet. Default: RD2's small „+“.
- **RD-Q4: the app icon, store frames and site.** The icon (#5 Wabenstapel), the store frames' „Wabenband“, the site's
  hex masks and the email logo are hexagons too (inventory). Default: a follow-up round for the icon and brand mark,
  with RD10's bite as one candidate. The store frames and site follow the app in the same release.
- **RD-Q5: the sticker shadow.** RD2 drops the hard navy shadow and keeps the 2 px contour. RD1 and RD10 keep both.
  Default: drop it with RD2.
- **RD-Q6: large text.** In every RD option the price moves under the name at 200 % and up, and headings stop growing
  at 200 %. Default: yes, for all list rows and headings.
- **RD-Q7: ticking.** RD2 draws a round check at the row's start. The whole row still ticks, as today, and the circle
  shows the state. Default: as drawn.
- **RD-Q8: Edit (Anpassen).** RD2 keeps it top right as a quiet pill, 1 tap as today, and the menu does not repeat it.
  Default: as drawn.
- **RD-Q9: fields and labels.** Today's labels sit above fields because a hex outline cannot hold a floating label
  (`LabeledField`, lint `no-label-in-hex-field`). Default: keep labels above the field, and rename the lint rule when
  the hexagons go.
- **RD-Q10: the empty state.** Each option's empty list draws its own motif in place of the hex. Default: RD2's yellow
  circle, until RD-Q4 settles the brand mark.

## How to check

- `node docs/design/redesign/verify.mjs` checks:
  - `strings.js` and `palette.css` against the app;
  - every phone's measurements;
  - both tables in `RECOMMENDATION.md` and `.de.md`, cell by cell, against a fresh run.
- `--write` rewrites `rd/measured.json`, and `--shots <dir>` writes screenshots.
- `node docs/design/redesign/tools/table.mjs` rewrites the tables from `measured.json`.
