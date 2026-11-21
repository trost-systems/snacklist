# Hex inventory (job 353, redesign without hexagons)

Read-only audit of worktree `job/353-redesign-no-hex-prototypes` at `a1edd966`, 2026-11-21.
Every file:line below was checked by grep. Call-site counts exclude `///` doc comments and,
unless stated otherwise, the definition itself.

Replacement categories:

- **tokens-only**: the motif changes when `HexBorder` / `HlHex` (or a CSS mask, or a generator
  input) changes. Callers stay untouched.
- **widget swap**: the widget has hex geometry beyond the outline (hard-coded 0.866 aspect, a
  nested hex thumb or dot, a pointy-top box, tip-based inset maths). Rewrite the widget body;
  callers mostly stay.
- **structural**: the hex is the artwork itself (icon, ribbon, masks, rendered media). Redraw
  and regenerate.

## Key finding: one choke point in Flutter

Every hex in `app/lib` is drawn by `HexBorder.pathFor` (`app/lib/design/hex_border.dart:30`),
driven by `HlHex.tip`, `HlHex.referenceHeight`, `HlHex.cornerRadius`
(`app/lib/design/tokens.g.dart:401-410`, source `design/tokens/snacklist.tokens.json:1719`
`shape.hex`). No other Dart file builds a six-sided `Path`. The only other `Path`s are the
checkbox tick (`hex_checkbox.dart:113`), the annotator's strokes (`feedback/annotator.dart:547`),
the hint cutout (`tips/hint_views.dart:367`), the QR code (`household/invite_sheet.dart:659`),
the rounded-field path (`field_border.dart:35`) and the tactile focus room
(`tactile.dart:213`).

Reading of the code (not run): with `tip = 0`, `_vertices` (`hex_border.dart:59-81`) degenerates
to a rectangle with two collinear mid-side vertices, and the fillet becomes a rounded rectangle
with radius `8 * h / 48`. All `HlHex.tip * h` insets drop to their `HlSpace` part. So most of
the app could be de-hexed by retargeting `HexBorder` alone, for example to a
`RoundedRectangleBorder` or `StadiumBorder` path that keeps the `outset` maths. Prove this with
goldens before relying on it. The collinear-vertex arc (`acos` = pi, `tan(pi/2)`) is an edge
case that needs a test. Pointy-top boxes would still be 0.866 wide (see the widget-swap rows).

## 1. App widgets (design system, `app/lib/design/`)

| Motif | Where users see it | Definition (file:line) | Call sites in app/lib outside design/ | Category |
| --- | --- | --- | --- | --- |
| `HexBorder` (Hex Soft outline, horizontal and pointy-top) | Every hex below; also used directly | `hex_border.dart:22` (class), `:6` `HexOrientation`, `:30` `pathFor` | 26 direct uses (core 4, feedback 2, list 15, shell 4, trip 1); 42 counting design/ | tokens-only (the choke point) |
| `hexTextInset(h)` = `HlHex.tip*h + s1` | Text padding inside hex buttons, chips, tabs | `hex_border.dart:179` | 6 (core 1, feedback 2, list 3) | tokens-only (tip 0 gives s1) |
| `hexLabelClearance`, `hexLabelInset(style)` | Label start in segmented control and tabs | `hex_border.dart:183`, `:190` | 1 (`list/list_tabs.dart`) | tokens-only |
| `HlHex.tip * …` inline geometry | Badge, chip, switcher, add bar, status pill padding | (token) `tokens.g.dart:403` | 11 (household 1, list 10): `join_approval_section.dart:256`, `household_chip.dart:38`, `list_switcher_button.dart:58-59`, `sync_indicator.dart:575`, `list_screen.dart:798-799,1222`, `store_badge.dart:42`, `price_views.dart:691-692` | tokens-only |
| `PointyHex` (site `.hxp`, 0.866 aspect) | Add bar "+", empty-list cart, Premium hero and benefits, trip summary, hints checklist, join waiting, report sent, More update card | `pointy_hex.dart:7`, aspect `:19` | 12 direct: `more_screen.dart:711`, `trip/summary_view.dart:421`, `trip/premium_card.dart:61`, `household_switcher.dart:116,186`, `report_page.dart:795`, `join_request_waiting.dart:112`, `tips/hint_views.dart:620`, `list_view/explainer.dart:26`, `premium_screen.dart:326,450,521` | widget swap (aspect 0.866 hard-coded) |
| `sheetHex(...)` (PointyHex wrapper) | Household switcher and voice-default sheets, row leading icons | `household/household_switcher.dart:116` | 12 (switcher_household 5, household_switcher 6, voice_default_pages 1) | widget swap (via PointyHex) |
| `HlRowHex` (34 px pointy hex row icon) | More, Settings, store chain rows | `group_card.dart:50` | 4 (`list/store_chain_section.dart:102`, more 1, settings 2) | widget swap (via PointyHex) |
| `HlCountBadge` (honey hex count) | Join requests, unread feedback answers | `count_badge.dart:8` | 2 (household 1, more 1) | tokens-only |
| `HexPill`, `PillTitle`, `PillDragHandle`, `HexPill.lift` | Läden (stores) screen, reorderable store rows | `hex_pill.dart:11`, `:109`, `:130` | HexPill 3, PillTitle 2, PillDragHandle 2, lift 2 (all `list/stores_screen.dart`) | tokens-only |
| `HexCheckbox`, `HexCheckboxListTile` (pointy-top 26 px) | Opt-ins: feedback sheet, edit item, report | `hex_checkbox.dart:16`, `:153`; box `:95` (`height*0.866`) | HexCheckboxListTile 3 (feedback 1, list 1, report 1); HexCheckbox only inside the tile | widget swap (0.866 box, tick placement by fractions) |
| `HexRadio`, `HexRadioTile` (hex outline + hex dot) | Settings (3), access/API scopes, store chain, household, report | `hex_radio.dart:11` (box `Size(24, 20)` `:17`), `:127` | HexRadioTile 6 (household 1, list 1, report 1, settings 3) | widget swap (hex dot, 24x20 box) |
| `HexSegmented`, `HexSegment` (hex track, sliding honey hex) | Settings theme picker, annotator tools, feedback, list | `hex_segmented.dart:27`, `:10`; slide maths `:46`; ring `:286` | HexSegmented 3 (feedback 1, list 1, settings 1), 9 `HexSegment` options | widget swap (tip maths `:46` for the slide) |
| `HexSwitch`, `HexSwitchTile` (hex track, nested hex thumb) | Settings, feedback (2), household, More | `hex_switch.dart:18` (track `Size(56,30)` `:25`), `:215`; thumb width `:177` uses tip | HexSwitchTile 5 (feedback 2, household 1, more 1, settings 1) | widget swap (thumb width formula `:175-177`) |
| `TactileFace`, `tactileButtonStyle` (hex face on its edge) | Every Filled/Outlined button via theme, add-sheet keys, sync indicator, fold-out chips | `tactile.dart:47`, `:243`; painter shape `:134` | TactileFace 2 (`add_sheet.dart:1083`, `sync_indicator.dart:731`); tactileButtonStyle 3 outside theme (`foldout_chips.dart:406`, `add_sheet.dart:900`, `sync_indicator.dart:359`) + 3 in `core/theme.dart:141,157,288` | tokens-only (shape is `HexBorder()`) |
| `ContourInputBorder` / `FieldShape.hex` / `hexFieldInset` | Every single-line text field (theme default) | `field_border.dart:24`, `:9-10`, `:128`; theme `:142`; app theme `core/theme.dart:271` | hexFieldInset 5 (list 4, log 1); all TextField/TextFormField (31) inherit it | tokens-only for the outline; the "no floating label" rule may relax |
| `LabeledField` (label above, because a hex cannot hold a floating label) | Login, onboarding, household, list, log, report, settings | `field_border.dart:239` | 20 (household 3, list 4, log 2, onboarding 3, report 2, session 3, settings 3) | structural decision: keep or drop once fields are rounded |
| `RoundedFields` (opt-out to rounded multiline) | Feedback, report | `field_border.dart:223` | 3 (not hex; the escape hatch) | none |
| `BrandBlock` (hex app mark PNG + wordmark) | Login, welcome, start, onboarding | `brand_block.dart:8`, asset `:22` | 3 (household 1, onboarding 1, session 1) | structural (asset regen) |
| Not hex, listed for completeness: `HlSticker`, `HlGroup` | Cards, groups | `sticker.dart:17` (`HlRadius.m`), `group_card.dart:8` | 16, 9 | none (already rounded) |

### Theme-level hex (`app/lib/core/theme.dart`)

| Motif | Line | What inherits it | Uses in app/lib | Category |
| --- | --- | --- | --- | --- |
| Filled/Elevated button (primary tactile hex) | `:141`, `:188-189` | `FilledButton`, `.icon`, `.tonal` | 50 + 14 + 5 | tokens-only |
| Outlined button (secondary tactile hex) | `:157`, `:190` | `OutlinedButton`, `.icon` | 20 + 20 | tokens-only |
| `TextButton` hex ink shape | `:196` | `TextButton`, `.icon` | 66 + 15 | tokens-only |
| `ChipThemeData` hex | `:202` | FilterChip 3, ChoiceChip 1, Chip 1 | 5 | tokens-only |
| `CheckboxThemeData` hex | `:212` | Material `Checkbox` (no direct use left) | 0 | tokens-only |
| `NavigationRail` hex indicator | `:260` | `shell/shell.dart` rail (840 px and up) | 1 | tokens-only |
| `inputDecorationTheme` hex fields | `:271` | every `TextField` / `TextFormField` | 29 + 2 | tokens-only |
| Disabled tactile style | `:288` | disabled buttons | n/a | tokens-only |

Cards, dialogs, sheets and snackbars are already rounded (`HlRadius.m`/`l`, `theme.dart:219-245`).

## 2. App screens using raw `HexBorder` / hex geometry (feature code)

| Surface | Widget | file:line | Call sites | Category |
| --- | --- | --- | --- | --- |
| Bottom tab bar capsule + tabs + focus ring | `_Pill`, `_Tab`, `_Ring` | `shell/shell.dart:521,526` (pill), `:638` (tab), `:709` (ring path) | 1 shell | tokens-only |
| List tabs (multi-list strip) + focus ring | `ListTabs`, `_Tab`, `_Ring` | `list/list_tabs.dart:94,99`, `:290`, `:343` | 1 (`ListTabs` in list screen) | tokens-only |
| Add bar field (thumb zone) | `_AddBar` | `list/list_screen.dart:798-803` | 1 | tokens-only |
| Partner "new adds" status capsule | `_Status` | `list/list_screen.dart:1222`, `:1291,1296` | 1 | tokens-only |
| Store badge (list divider, add sheet) | `StoreBadge` | `list/store_badge.dart:42,54` | 1 (`add_sheet.dart:1077`) | tokens-only |
| Option chips (fold-out, edit sheet, trip sheet) | `OptionChip` | `list/foldout_chips.dart:814` (shape `:840`) | 10 (foldout 4, edit_item 1, trip_sheet 5) | tokens-only |
| Quantity "− Menge +" group | `QuantityGroup` | `list/add_sheet/compact_details.dart:141` (shape `:190`) | 2 (compact_details 1, edit_item 1) | tokens-only |
| Price chip, stepper, unit menu | `PriceChip`, `_Stepper`, `_UnitMenu` | `list/list_view/price_views.dart:87`, `:621`, `:691-696` | PriceChip 1 (`shopping_list_view.dart:1061`) | tokens-only |
| Item icon fallback ("one quiet honeycomb cell") | `ItemIconFallback` / `_CellPainter` | `list/list_view/item_icon_fallback.dart:16`, pointy shape `:41` | 1 (`item_icon.dart:155`), shown on every item without an emoji | widget swap (needs a new non-hex glyph) |
| Sync indicator pill and card/pill morph clip | `_Pill`, `_RenderMorph` | `list/sync_indicator.dart:575`, `:810`, clip `:916-920` | 1 | tokens-only |
| Household chip, list switcher button | `HouseholdChip`, `ListSwitcherButton` | `list/household_chip.dart:38`, `list/list_switcher_button.dart:58` | 1 each | tokens-only |
| Trip strip icon button | `_TripStripState` | `trip/trip_strip.dart:120` | 1 | tokens-only |
| Feedback "Neue Antwort" marker, note status chip | `_NewMarker`, `NoteStatusChip` | `feedback/feedback_hub.dart:229`, `:287` | 1, 2 | tokens-only |
| Join approval row buttons | `_JoinApprovalSectionState` | `household/join_approval_section.dart:256` | 1 | tokens-only |
| Empty list (honey pointy hex + cart) | `EmptyList` | `list/list_view/explainer.dart:9,26` | 2 (`shopping_list_view.dart:727,740`) | widget swap (via PointyHex) |
| Add sheet close and Enter keys | `_CloseButton`, `_hexKey` | `list/add_sheet/add_sheet.dart:52`, `:898-912` | 1 | tokens-only |
| Quantity flag | `hexQuantity` param (name only) | `list/edit_item_sheet.dart:58`, `shopping_list_view.dart:526` | 2 | rename only |

### Per folder (direct hex call sites outside `lib/design/`, theme inheritance not counted)

Counts are of the identifiers in section 1 (HexBorder, HlHex.*, hex insets, PointyHex, sheetHex,
HlRowHex, HlCountBadge, HexPill family, Hex*Tile, HexSegmented, TactileFace, tactileButtonStyle,
LabeledField, BrandBlock), counted as source lines (a line with two matches counts once; the
`sheetHex` definition line is excluded).

| Folder | Sites | Main widgets |
| --- | --- | --- |
| list | 56 | HexBorder 15, HlHex 10, HexPill family 9, LabeledField 4, hexFieldInset 4, hexTextInset 3, tactile 4 |
| household | 22 | sheetHex 12, PointyHex 2, LabeledField 3, HexRadioTile 1, HexSwitchTile 1, HlCountBadge 1, BrandBlock 1, HlHex 1 |
| settings | 10 | HexRadioTile 3, LabeledField 3, HlRowHex 2, HexSegmented 1, HexSwitchTile 1 |
| feedback | 8 | HexSwitchTile 2, hexTextInset 2, HexBorder 2, HexCheckboxListTile 1, HexSegmented 1 (+4 segments) |
| core | 8 | HexBorder 4 (theme), tactileButtonStyle 3, hexTextInset 1 |
| report | 5 | LabeledField 2, PointyHex 1, HexRadioTile 1, HexCheckboxListTile 1 |
| purchases | 3 | PointyHex 3 |
| trip | 3 | PointyHex 2, HexBorder 1 |
| shell | 4 | HexBorder 4 |
| onboarding | 4 | LabeledField 3, BrandBlock 1 |
| session | 4 | LabeledField 3, BrandBlock 1 |
| more | 4 | PointyHex 1, HlRowHex 1, HlCountBadge 1, HexSwitchTile 1 |
| log | 3 | LabeledField 2, hexFieldInset 1 |
| tips | 1 | PointyHex 1 |

Total: 135 lines with a direct hex call site in 46 files outside `lib/design/`, plus about 227 widgets
that inherit hex from the theme (buttons 190, fields 31, chips 5, rail 1).
Tests: 11 files in `app/test` name a hex widget; `app/test` holds 161 PNG goldens that show the
hex look and all need regenerating.

### Native widgets (Home Screen)

| Motif | Where | file:line | Category |
| --- | --- | --- | --- |
| SwiftUI `Hex` shape (copies `HlHex`: tip 0.2887, corner 8, ref 48, hard-coded) | iOS widget "done" badge | `app/ios/HomeWidget/Hex.swift:5,13-15`; use `HomeWidgetView.swift:170-171` | widget swap (constants are not generated) |
| Android widget hex nine-patches and done hex | Android widget pill, add button, empty-list badge | generator `design/widget/build.mjs:33,85,107-110` -> `res/drawable/widget_done_hex.xml`, `widget_pill.9.png`, `widget_add_button.9.png`; used `SnacklistWidget.kt:162,248,299` | structural (regenerate; generator reads `shape.hex` tokens `:22-24`) |

### Strings

`app/l10n/app_de.arb` and `app_en.arb`: no string mentions Wabe, Hex or honeycomb (grep, case
insensitive). Nothing to change.

## 3. App icon and brand assets

The icon "5 Wabenstapel" is hex: a cobalt rounded square (`rx 184`), a honey outer hex ring, a
white inner hex (dark mode `#9fb6ff`) and a cobalt check. The in-app and splash mark is a cobalt
rounded hex body with a small honey hex cell and a tick.

| Asset | Generator | Output (all regenerated by `node design/app-icon/build.mjs`) | Category |
| --- | --- | --- | --- |
| App icon geometry | `design/app-icon/build.mjs:29-35` (`outer`, `hole`, `inner` hexes; groups "Wabe außen", "Wabe innen"), `geom.mjs` (`hex`, `hexPoints`, `roundedPolygon`) | iOS `app/ios/Runner/AppIcon.icon/*` (layer names say Wabe), `Assets.xcassets/AppIcon.appiconset/AppIcon-1024{,-dark,-tinted}.png`; Android `res/mipmap-*/ic_launcher{,_round}.png`, `drawable/ic_launcher_{background,foreground,monochrome}.xml`, `mipmap-anydpi-v26/*`; web `app/web/favicon.{svg,png}`, `app/web/icons/Icon-{192,512}.png`, `Icon-maskable-*.png`, `apple-touch-icon.png`; Alexa `alexa/skill-package/assets/images/de-DE_{large,small}IconUri.png`; email `site/public/email/snacklist-icon-96.png` | structural |
| Brand mark (body hex + honey cell) | `design/app-icon/build.mjs:47-53` | `app/assets/brand/{,2.0x/,3.0x/}mark-{light,dark}.png` (`BrandBlock`), `app/web/splash/mark-{light,dark}.svg`, `app/web/splash.css`, Android `drawable{,-night}/splash_mark.xml`, iOS `LaunchImage.imageset` | structural |
| Copies of the icon SVG | (same art) | `site/public/favicon.svg`, `site/public/favicon.png`, `site/public/apple-touch-icon.png`, `mcp-proxy/public/static/logo.svg` | structural |
| Not hex | | `app/assets/google_g.png`, fonts | none |

## 4. Store frames (`marketing/store-screenshots/`)

| Motif | file:line | Use | Category |
| --- | --- | --- | --- |
| `hexPath` (pointy-top rounded hex) | `kit.mjs:162` | base of all below | structural |
| Wabenband (cobalt ribbon with a honeycomb inside) | `kit.mjs:180-205` (`band`) | behind every screenshot set `compose.mjs:131`, feature graphic `compose.mjs:156` | structural |
| Member hex avatar with initial | `kit.mjs:207-209` (`avatar`) | `compose.mjs:83` (voice sticker) | structural |
| Hex icon chip (`.hexicon`) | `kit.mjs:212-214`, CSS `compose.mjs:122-124` | mic `compose.mjs:83`, check list `compose.mjs:89` | structural |
| The app captures themselves | `capture.mjs` (real web build) | every frame | follows the app |
| Captions | `captions.yaml` | no hex words | none |

Docs describing it: `docs/STORE_SCREENSHOTS.md:7`.

## 5. Site (`site/`), web join page, MCP page, videos

### Site CSS system (`site/public/styles.css`)

| Motif | Lines | Used by | Category |
| --- | --- | --- | --- |
| Mask variables `--hex-img`, `--sweep-img`, `--pointy-img` | `:32-34` | all below | tokens-only (swap masks) |
| `.hx` static horizontal hex (tags, chips) | `:160-180` (comment `:128-158`) | `landing.mjs:162,290`; scenes (`.compose hx`) | tokens-only |
| `.hxp` pointy hex (ticks, play button) | `:182-213` | `landing.mjs:162,264,290`, `report.mjs:119`, `waitlist.mjs:77`, scenes, `demo.js:3` (play button) | structural (0.866 box) |
| `.hex` tactile control (face, side wall, edge, focus ring from stacked shadows) | `:215-330`, focus `:306-318`, `.hex--small` `:320-326` | header CTA on every page `build.mjs:408`; `landing.mjs:160,270`; `report.mjs:112`; `waitlist.mjs:72,96`; excluded from the cards' link style by `a:not(.hex)` in `waitlist.css:20` and `report.css:16` | widget swap (focus ring is hex-shaped shadows) |
| Forced-colours fallbacks | `:762-795` | same | tokens-only |
| Masks | `site/public/hex/hex-cap-l.svg`, `hex-cap-r.svg`, `hex-pointy.svg` | all of the above | structural |
| Honeycomb block art | `site/public/hex/block-hex.svg`, `block-hex-dark.svg`; `landing.css:742-745,790` (voice, privacy, cta blocks) | landing page | structural |
| `.hex--tomato` | `landing.css:679` | landing | tokens-only |
| Tokens | `site/public/tokens.css:120-122` `--hl-shape-hex-*` | `.hex` paddings | tokens-only |

### Scenes and rendered media

| Item | file:line / count | Category |
| --- | --- | --- |
| Scene CSS `.hx`, `.hx--honey`, `.hx--edge`, `.hxp` | `site/scenes/scenes.css:29,94-170` | structural |
| Scene HTML hex elements | `hero.html` 7, `add-tick.html` 9, `household-sync.html` 12, `mcp-chat.html` 3 (compose bar `hero.html:51`, `add-tick.html:45`) | structural |
| Rendered loops | `site/public/media/*.mp4`, `*.webm` (add-tick, household-sync, mcp-chat, voice-add) | re-film |
| Email demo screenshot | `site/public/email/demo-list-de.png` | re-capture |

### Videos (`marketing/videos/`)

| Motif | file:line | Category |
| --- | --- | --- |
| Caption hex led by a glyph, member hexes | `video.css:124-164`, `:190`, `:290` (mask `hex-pointy.svg`) | structural |
| Copies the mask in | `build.mjs:48` | structural |
| `.hxp` in markup | `lib.mjs:104`, `household-sync/scene.mjs:71,75`, `mcp-chat/scene.mjs:106,146-147`, 0.866 layout `:154-155` | structural |

### App web join page (`app/web/join/`, served by the app build)

| Motif | file:line | Category |
| --- | --- | --- |
| `.hex` tactile buttons | `index.html:24,29`; `join.css:27-28,236-` | tokens-only (mask swap) |
| Honey pointy hex on the Premium line | `join.css:148-167` | structural |
| Masks | `app/web/join/hex/` | structural |

### MCP page (`mcp-proxy/public/`)

| Motif | file:line | Category |
| --- | --- | --- |
| `.hex` buttons | `de.html:28,32`, `en.html:28,32`; `static/page.css:88-90,280,363-410` | tokens-only (mask swap) |
| Honeycomb block art | `static/page.css:763,793`; `static/hex/block-hex{,-dark}.svg` | structural |
| Masks | `static/hex/hex-cap-{l,r}.svg`, `hex-pointy.svg` | structural |
| Logo | `static/logo.svg` (app icon copy) | structural |

## 6. Emails and other

| Item | file:line | Category |
| --- | --- | --- |
| Email header logo = hex app icon PNG | `emails/src/components/Header.tsx:5,18-19`; referenced by all 13 `supabase/templates/*.html` | structural (icon regen only) |
| Email buttons, steps, tip box | `PrimaryButton.tsx:30,37`, `Steps.tsx:27`, `TipBox.tsx:11,29` | none (already `radius.s` / `full`) |
| Design doc | `docs/DESIGN.md` (55 hex mentions; component table `:150-157`, design files `:162-220`) | docs rewrite |
| UI craft skill mandates hex | `.claude/skills/snacklist-ui-craft/SKILL.md:27-28` ("The hex controls … are the point"), `:30` (6b Hex Frische), `:47` (Shape: hex controls), `:51` (Logo Wabenstapel), `:89` (hex tick); `references/motion.md:54`, `references/framing.md:11,44` (`.cursor/skills/snacklist-ui-craft` is the same directory) | docs rewrite |
| Lint `no-label-in-hex-field` | `ast-grep/rules/no-label-in-hex-field.yml` (id line 5), test `ast-grep/tests/no-label-in-hex-field-test.yml`, row in `CLAUDE.md` lint table | delete or rename with the field decision |
| History mentioning the Wabenband | `docs/STORE_SCREENSHOTS.md:7`, `DONE_SUMMARY.md:1201`, `docs/done/215-*.md:9` | leave (history) |

## Palette and shape tokens today

Source: `design/tokens/snacklist.tokens.json` (W3C design tokens, `color.light` / `color.dark`
semantic names in kebab case, `radius`, `shape.hex`, `border`, `shadow`, `depth`, `focus`, `size`).
`node design/tokens/build.mjs` writes `app/lib/design/tokens.g.dart`, `site/public/tokens.css`,
`app/web/join/tokens.css`, `app/ios/HomeWidget/SnacklistColors.swift` and the Android
`values{,-night}/snacklist_tokens.xml`; `emails/src/tokens.ts` reads the JSON directly.

### Colours (`SnacklistColors`, `tokens.g.dart:127-208`)

| Token | Light | Dark |
| --- | --- | --- |
| brand | #1B3FAE | #9FB6FF |
| onBrand | #FFFFFF | #0B1024 |
| honey | #FFE24A | #FFE24A |
| onHoney | #0F1530 | #0B1024 |
| honeySoft | #FFF2A8 | #35310F |
| honeyEdge | #D4B20F | #B39B1A |
| accent | #1B3FAE | #9FB6FF |
| onAccent | #FFFFFF | #0B1024 |
| accentSoft | #E1E8FF | #1D2B66 |
| onAccentSoft | #132F86 | #E1E8FF |
| cobalt | #1B3FAE | #2448C0 |
| onCobalt | #FFFFFF | #FFFFFF |
| surface | #F7F7F2 | #0B1024 |
| surfaceRaised | #FFFFFF | #151C3A |
| surfaceSunken | #ECEFF6 | #111735 |
| surfaceEdge | #C3CAE0 | #2A3463 |
| text | #0F1530 | #EFF3FF |
| textMuted | #4B536C | #B0B9D8 |
| border | #0F1530 | #7F8CC4 |
| divider | #D3D8E6 | #2F3A66 |
| ink | #0F1530 | #03050F |
| edge | #0F1530 | #03050F |
| success | #0D7A4E | #62C99D |
| onSuccess | #FFFFFF | #0B1024 |
| successSoft | #D6F5E7 | #123A31 |
| warning | #8A5300 | #FFD25A |
| onWarning | #FFFFFF | #0B1024 |
| error | #C4280F | #FF8A73 |
| onError | #FFFFFF | #0B1024 |
| mint | #7FE3B8 | #62C99D |
| onMint | #0F1530 | #0B1024 |
| mintSoft | #D6F5E7 | #123A31 |
| mintEdge | #3FBF8A | #3A9E78 |
| tomato | #FF5B3A | #F0603F |
| onTomato | #0F1530 | #0B1024 |
| tomatoEdge | #C8402A | #B04530 |
| inverse | #0F1530 | #111735 |
| onInverse | #F3F6FF | #EFF3FF |

### Shape and depth

| Token | Value | Source / output |
| --- | --- | --- |
| `HlRadius.s` / `--hl-radius-s` | 12 | `tokens.g.dart:342`, `tokens.css:98` |
| `HlRadius.m` | 18 | `:343` (stickers, cards, groups, snackbars) |
| `HlRadius.l` | 28 | `:344` (dialogs, sheets) |
| `HlRadius.xl` | 40 | `:345` (site blocks) |
| `HlRadius.full` | 999 | `:346` |
| `HlHex.tip` / `--hl-shape-hex-tip` | 0.2887 (1/(2 tan 60°)) | `tokens.g.dart:403`, `tokens.css:120`, JSON `shape.hex.tip` |
| `HlHex.referenceHeight` | 48 | `:406`, `tokens.css:121` |
| `HlHex.cornerRadius` | 8 (at 48 px, scales with height) | `:409`, `tokens.css:122` |
| `HlBorder.width` / `widthThin` | 2 / 1 | `:351-352` |
| `HlShadow.stickerS` / `sticker` / `stickerL` | #0F1530 offset 0,2 / 0,4 / 0,8 | `:356-363` |
| `HlShadow.nightS` / `night` / `nightL` | #03050F offset 0,2/4/8 plus #9FB6FF glow 12/24/48 at 12/14/18 % | `:365-376` |
| `HlDepth.edge` / `edgeL` / `lift` / `press` | 4 / 6 / 2 / 4 | `:380-385` |
| `HlFocus.ringWidth` / `ringGap` | 3 / 2 | `:390-393` |
| `HlSize.target` | 48 | `:398` |

Hard-coded copies of hex geometry outside the token pipeline: `Hex.swift:13-15` (tip, corner,
reference height), `PointyHex.aspect` 0.866 (`pointy_hex.dart:19`), `HexCheckbox` 0.866
(`hex_checkbox.dart:95`), `HexRadio.hex` 24x20 (`hex_radio.dart:17`), `mcp-chat/scene.mjs:154`.

## Summary

| Widget / motif | Call sites | Difficulty |
| --- | --- | --- |
| Theme buttons (Filled, Outlined, Text) via `tactileButtonStyle` / `HexBorder` | 190 | tokens-only |
| Theme text fields (`ContourInputBorder`) | 31 | tokens-only |
| `HexBorder` direct in feature code | 26 | tokens-only |
| `LabeledField` | 20 | structural decision (keep labels above or move them into the field) |
| `PointyHex` | 12 | widget swap |
| `sheetHex` | 12 | widget swap (follows PointyHex) |
| `HlHex.tip` inline maths | 11 | tokens-only |
| `OptionChip` | 10 | tokens-only |
| `HexSegment` options / `HexSegmented` | 9 / 3 | widget swap |
| `HexRadioTile` | 6 | widget swap |
| `hexTextInset` / `hexFieldInset` / `hexLabelInset` | 6 / 5 / 1 | tokens-only |
| `tactileButtonStyle` outside theme / `TactileFace` | 3 / 2 | tokens-only |
| Material chips (theme) | 5 | tokens-only |
| `HexSwitchTile` | 5 | widget swap |
| `HlRowHex` | 4 | widget swap |
| `HexPill` family (`HexPill`, `PillTitle`, `PillDragHandle`, `lift`) | 3 / 2 / 2 / 2 | tokens-only |
| `HexCheckboxListTile` | 3 | widget swap |
| `BrandBlock` | 3 | structural (asset) |
| `HlCountBadge` | 2 | tokens-only |
| `ItemIconFallback` (honeycomb cell on every emoji-less item) | 1 widget, many rows | widget swap |
| `EmptyList` hex cart | 2 | widget swap |
| `NavigationRail` indicator | 1 | tokens-only |
| iOS widget `Hex` / Android widget drawables | 1 / 3 files | widget swap / structural |
| App icon, mark, splash, favicons, Alexa and email icons | about 40 generated files from 1 generator | structural |
| Store frames: Wabenband, hex avatars, hex icons | 4 kit functions, 5 uses | structural |
| Site `.hex` / `.hx` / `.hxp` + 5 masks + block art | about 40 markup uses across site, scenes, join page, MCP page | tokens-only for `.hex`/`.hx` (mask swap), structural for `.hxp` and block art |
| Videos and rendered media | 3 scenes, about 12 media files | structural (re-film) |
| Docs, skill, lint rule | `DESIGN.md`, ui-craft skill (6 places), 1 ast-grep rule + test | docs rewrite |
