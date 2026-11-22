---
name: snacklist-ui-craft
description: How to make Snacklist UI look finished in a marketing still, a demo loop or a real screen. Use whenever you build or refine a product illustration, hero or feature-card shot, demo video, golden screenshot, Widgetbook story or app screen meant to be shown (homepage scenes in site/, Flutter goldens and filmed Flutter screens, the generic AI chat surface), or when you review one. Covers the 6b Hex Frische look, restraint, framing and bleed, spacing, devices, motion with a cause, loops, poster frames, reduced motion, the 358 px compact design, and the film, contact sheet and fresh-eye review loop.
---

# Snacklist UI craft

A shown screen is a real Snacklist screen, simplified to what the viewer needs, framed with
intent, and every motion in it has a cause. This applies to two kinds of surface:

- **Flutter:** app screens, Widgetbook stories, golden screenshots (`app/test/design/`) and
  real screens filmed for demos (Linux build under `xvfb-run`, `integration_test`).
- **Site:** illustration scenes for the static site, authored in plain HTML/CSS (no React,
  not part of `site/build.mjs`), filmed with Playwright to PNG, WebP, WebM and MP4 by
  [`film.mjs`](film.mjs).

Read [`references/framing.md`](references/framing.md) before you compose a shot,
[`references/motion.md`](references/motion.md) before anything moves, and
[`references/review.md`](references/review.md) before you hand over.

## How it goes wrong

- **Too much:** real words in every row, numbers everywhere. Detail everywhere reads as generated.
- **Wireframe:** two gray bars and a button. Too small, or stripped of what makes it Snacklist.
- **Boxed:** a whole phone shrunk onto a tinted plate with even margins. A pasted screenshot.
- **Flat:** every object the same weight in the same bordered card. The eye has nowhere to land.
- **Bland:** a gray mock with none of the 6b look. The hex controls, navy contour, sticker
  shadow and colour blocks are the point; build them in full.

## The Snacklist look (6b Hex Frische, design 6's yellow)

Take values from the shared tokens, never by eye: `design/tokens/snacklist.tokens.json`,
generated into `site/public/tokens.css` (`--hl-*`) and `app/lib/design/tokens.g.dart`
(`SnacklistColors`, `HlSpace`, `HlRadius`, `HlDuration`, `HlEasing`). Never hand-edit either.

| Role | Light | Dark |
| --- | --- | --- |
| Cobalt (brand, accent) | `#1b3fae` | `#9fb6ff` (field `#2448c0`) |
| Lemon yellow (honey) | `#ffe24a`, edge `#d4b20f` | `#ffe24a`, edge `#b39b1a` |
| Mint | `#7fe3b8`, edge `#3fbf8a` | `#62c99d`, edge `#3a9e78` |
| Tomato | `#ff5b3a`, edge `#c8402a` | `#f0603f`, edge `#b04530` |
| Navy text and contour | `#0f1530` | text `#eff3ff`; on yellow `#0b1024` |
| Surface / raised | `#f7f7f2` / `#ffffff` | `#0b1024` / `#151c3a` |

- **Type:** Bricolage Grotesque for display and titles, Inter for UI. Self-hosted woff2
  only (CSP `default-src 'self'`); never a font from a CDN.
- **Shape:** hex controls, 2 px navy contour (`--hl-border-width`), hard navy sticker shadow
  in light (`--hl-shadow-sticker*`), lighter raised surfaces plus night shadows in dark.
- **Contrast rules:** yellow controls on light surfaces and tomato buttons on yellow need
  the 2 px navy contour; never white text on yellow; never tomato text.
- **Logo:** the app icon AI1 Soft tile (cobalt ground, yellow rounded-square ring, white inner
  tile, cobalt check; dark: `#0b1024`, `#ffe24a`, `#9fb6ff`). Never redraw it; use the generated asset.
- **Name:** always "Snacklist" in full, never shortened. German du-form on DE screens.
- **Never:** a bee mascot; other brands' logos; stock-AI sparkles, wands, gradients or
  purple; a look-alike of Claude's, ChatGPT's or any vendor's chat UI; Apple Liquid Glass or
  SF Pro imitation; emoji standing in for icons.
- **Icons:** the app's own Material icons, one style (outlined), one size per scene; on the
  site the same glyphs as self-hosted SVG. Never draw an icon by hand.

## Workflow

Most of the quality is decided before code. Write the plan first, in five lines: where it
sits, the focal object, the action, the payoff, what is left out.

1. **Place and medium.** Still, loop (10 to 16 s) or play-once. Design at the size it is
   shown at 1:1: about 720 × 340 beside hero copy, 900 to 1100 wide full-width, 400 × 300
   for a card. Nothing under about 320 wide except a small tile. Plan the 358 px compact
   design now (below), not at the end.
2. **Look.** Tokens from the table above, light and dark. Real Snacklist content: German
   grocery items, quantities, store sections, household members.
3. **Story.** Three to five beats and a payoff. Every cursor or finger move has a reason.
4. **Frame** with `references/framing.md`: choose a layout, crop to where the story happens.
   Film one still at the wide and the compact width; fix the frame before any motion.
5. **The screen.** Count the real strings (below), fill the rest with quiet structure.
6. **Choreograph** with `references/motion.md`.
7. **Rehearse:** poster first, then film the loop, read the contact sheet, fix the largest
   fault, re-film. Then a fresh-eye review and the hand-over notes (`references/review.md`).

## Restraint and the word budget

- Count the real strings: the title, the thing acted on, what is typed, the result. Usually
  3 to 7. Everything else is placeholder bars in the quiet ink, widths varying (60, 45, 70, 52 %).
- A word budget is not an element budget: a list still needs enough rows to read as a list,
  a household enough members, a store enough sections.
- Real words where the eye lands, bars at the edges and where the crop cuts. Gray bars on
  the focal object read as unfinished.
- In a small surface (popover, chip, card) a row is one line: icon or avatar, name, value.
- Label and value match: both words or both bars.
- Keep the signature content: item names with quantities, store chips, the hex tick,
  member avatars in their own colours. Swap them for generic rows and it is any list app.
- One number gets to be big. Say each thing once: no feature named in the header, a card and
  every row.
- Choose copy that fits: names and items whose length suits the slot, nothing truncated.
- Simplify before polishing: fewest surfaces and strings that explain it, then borders and
  badges only where earned. Simplify the words, not the context.

## Hierarchy and the focal object

- One hero object, at most one or two satellites (a member's phone, a store chip, a
  confirmation) that carry the point. Different sizes and kinds, never a pile of equal cards.
- The heaviest marks (yellow block, sticker shadow, display type) sit on what the story is
  about. Lift the focal object the way the app does (raised surface, contour, colour block),
  never with a glow ring or a halo.
- Judge the silhouette first: at thumbnail size subject, support and empty space make one picture.
- Space follows the story: the payoff gets the room; no empty band mid-screen while the result
  is pushed into the crop.
- Ask of every still: what does the eye land on first, and is it the result?

## Framing, cropping and bleed

- The page is the ground. No plate (tinted field or card behind the phone) on a white or navy
  page, and no phone or window floating whole with even air on four sides.
- The hero fills at least two thirds of the stage width and runs 10 to 40 % off at least one
  edge. Crop only filler: the action, the payoff, what the finger touches and every real word
  stay whole. A button sliced by the edge is removed, not sliced.
- One gutter, measured in the final crop: every edge distance matches it, or is well past it.
  Missing a gutter by a few pixels is a mistake, not a style.
- No dead corners at rest or anywhere in the loop. What the story opens (a sheet, a menu)
  stays a gutter inside every edge on every frame.
- A device keeps its shape; fix by crop or layout, never by squashing. Flat and frontal by
  default; earn a tilt by comparing with the straight version.
- The stage clips everything (`overflow: hidden`). Fades only for moving tracks, stacks, or a
  window dissolving at its foot over filler, with a mask, never a colour overlay.

## Spacing and alignment

- Words keep 12 px from any card, sheet, row or chip edge; never under 8. Row padding 12 px,
  8 in a dense list. A one-line row three times taller than its words is a fat row.
- A title over its subtitle reads as one item: 4 to 6 px of ink between, line height 1.3.
  Whitespace groups: a title sits closer to its meta than to the next row.
- A button keeps 8 px or more from the field or edge above it. A control hugs its content.
- Nested shapes pad evenly; outer radius = inner radius + padding (`--hl-radius-*`).
- No near-tangents: edges 1 to 3 px apart read as an accident. Align exactly or part by a gutter.
- Center labels on their letters, not the line box (`text-box: trim-both cap alphabetic`; in
  Flutter check the visible glyph, not the widget box). A dot or badge is not a column: 6 px clear.
- Columns line up on one grid; optional content keeps its track empty.
- Type: 11 to 15 px UI text at the shown size, never under 10 px on the phone. Sentence case.
  No real `h1`–`h6` inside a scene; it lives in someone's page outline.

## Chrome and devices

- Chrome for the task. A phone shot gets the real Flutter screen; no browser bar unless the web
  app at app.snacklist.app is the story.
- Never draw platform chrome from memory: status bar, home indicator, keyboard come from a real
  capture or a faithful frame. Nothing sits under the island; a sheet starts below the status bar.
- A phone is lit from its first frame: never dimmed or faded up.
- Several phones (household sync): one is active and leads; the others step back with quieter
  contrast and shadow, never three equal hero phones.
- A satellite phone straddles the hero's edge about half outside, over margin or chrome, never
  over the item or amount it explains.

## Motion, loops and the poster (details in `references/motion.md`)

- Every motion has a cause: a tap, a typed item, a sync arriving. No cursor or finger move you
  cannot explain. Feedback stays as quick as the app (`--hl-motion-duration-press`, 70 ms);
  only story travel slows down.
- Animate the relationship, not just the object: a new item carries the rows below it, a ticked
  item leaves and its gap closes in one motion, a sheet resizes without stretching its text.
- Nothing pops: every element has an entrance and stays until its exit finishes.
- **Loop seam:** the last frame equals the first. A reset has a visible cause (untick, clear,
  undo) or happens while hidden; data never rewinds in view; no dead air at the seam.
- **Poster:** set it first. It is the beat that tells the story alone (the item just ticked in
  mint, the new row in place on the second phone), never mid-change, result left on screen.
- **Reduced motion:** show the poster, complete and still. Site: `prefers-reduced-motion:
  reduce` gets the poster image and a play button, no autoplay. Flutter: every design-system
  animation goes through `hlMotion(context, …)`, which returns zero duration.

## Compact 358 px

Every scene that can sit in a phone column ships a second design at 358 px wide (a 390
viewport minus gutters), switched where the wide one stops fitting. It is a redesign, not a
squeeze: crop closer, drop or stack the satellite, keep the action and payoff whole, type at
its native size. Shrinking the wide scene (type drawn at 0.7×) is the fault this rule fixes.

## Generic AI chat (MCP demo)

Build it ourselves in 6b style: a Snacklist-styled thread (raised navy-contoured bubbles, Inter,
cobalt for the user's side, the result as a Snacklist card with the added items). The real MCP
tool results from the local stack are the content. No vendor's layout, avatar, logo, name,
model picker, sparkle or purple; caption it generically ("any AI assistant with MCP", draft
copy). Story: the request typed (or a mic state as UI only), a short working state, the
result card arriving whole, then the items appearing in the real app footage.

## Rehearse and review (details in `references/review.md`)

1. Film it: `node .claude/skills/snacklist-ui-craft/film.mjs <scene.html> --out shots/x --still`
   for the poster, `--every 500 --count 24` for a contact sheet, `--width 358` for compact,
   `--dark`, `--reduced`, `--seam <loop ms>` for the seam, `--video <s>` for WebM/MP4.
   For Flutter, put goldens or `x11grab` frames on one sheet with `film.mjs sheet`.
2. Read every frame of the sheet at the shown size. Fix the largest fault first: framing,
   then hierarchy, then motion, then polish. Re-film after every change.
3. Hold the still beside the best existing Snacklist shot and name the one difference.
4. Fresh-eye review: a reviewer (another agent) gets only the frames, the brief's one line and
   `references/review.md`, not your plan. Ranked findings, each tied to a frame.
5. Hand-over notes in the PR or DONE_SUMMARY (template in `references/review.md`).

## Recurring faults (check before handing over)

- Content that swaps in one frame instead of moving.
- Gray bars where the eye lands; real words where only filler belongs.
- A plate behind the phone, or a phone floating whole with even air.
- Empty bands, a void under a list, rows spread to fill a pane, dead corners.
- A cut button, chip or shadow at the stage edge.
- Stock AI (sparkles, purple), invented logos, emoji as icons, the bee.
- Busy rows, uneven insets, near-tangent edges.
- Long holds (nothing still for more than 3 s, payoff held about 2 s) and a reset with no cause.
- Hand-drawn status bar, island or keyboard.
- Text shrunk instead of a compact design; white text on yellow; tomato text.
The full you-see / you-do table is in `references/review.md`.

## Credits

Inspired by the MIT-licensed `stageshow` skill; see [`NOTICE.md`](NOTICE.md). No code from it
is used here.
