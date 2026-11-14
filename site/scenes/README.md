# Homepage scenes

Source for the product illustrations on the snacklist.app landing pages (job 53). Each scene is
a standalone HTML page at design size, built with the snacklist-ui-craft skill
(`.claude/skills/snacklist-ui-craft/`). Nothing in this folder ships: the site build reads only
the WebP stills that `film-all.mjs` writes to `site/public/media/`.

## Re-film

```sh
node site/scenes/film-all.mjs            # hero and mcp-chat (16 stills), then one contact sheet per scene
node site/scenes/film-all.mjs hero       # one scene
node site/scenes/film-all.mjs --serve    # only serve, to look at http://127.0.0.1:57610/scenes/hero.html?lang=en
```

`film-all.mjs` serves `site/` on 127.0.0.1:57610 (the hex masks do not load over `file://`) and
calls `film.mjs --still --scale 2` for each scene, locale (`?lang=de|en`), size (wide, compact)
and theme (light, `--dark`). It writes PNGs and sheets to `/tmp/s53/scenes/`, and
`site/public/media/<scene>-<locale>-<wide|compact>[-dark].webp`, re-encoding a WebP at lower
quality until it is under 120 KB. Needs `npm ci` in `e2e/` once, ffmpeg, and Flutter on PATH:
the icons are the app's own Material Icons font from the Flutter SDK, served as
`/scenes/material-icons.otf`, never redrawn and not copied into the repo.

Files:

- `scenes.css`: fonts, the 6b hex system, phone, list rows, stickers, chips, bubbles.
- `scene.js`: reads `?lang=` and fills every `data-t` element from the page's string table.
- `<scene>.html`: one per scene, with its markup and its `de` and `en` strings.

The compact design switches at `max-width: 400px` inside each scene. Dark comes from
`prefers-color-scheme: dark` through `site/public/tokens.css`.

All four are stills. `hero` stays a still on the page. The three video slots (`add-tick`,
`household-sync`, `mcp-chat`) get job 54's real app footage; these are their placeholder
posters, so nothing here loops. `add-tick` and `household-sync` take their posters from their
videos since job 215 (`marketing/videos/remake.sh`), so `film-all.mjs` no longer films them;
`emails/scripts/demo-screen.tsx` still shoots `add-tick.html`.

## Plan per scene

### hero (wide 500 x 540, compact 358 x 400)
- Where: the bottom of the cobalt hero block, painted cobalt so it merges with the block.
- Focal object: the list screen on one phone, run off the bottom edge.
- Action: Anna (household „Unser Haushalt“, with Jonas) added Hafermilch on her phone; it sits in the list, freshly tinted.
- Payoff: the sync sticker "Anna hat „Hafermilch“ hinzugefügt" with Anna's avatar, straddling the phone.
- Left out: tabs, status bar, settings, other satellites (no voice sticker, no logo cluster).

### add-tick (wide 576 x 324, compact 358 x 448)
- Where: the "add and tick off" video slot, as its poster, inside the page's 28 px frame.
- Focal object: the Supermarkt part of the list with the add field under it.
- Action: Bananen ticked off, Avocados just added through the add field.
- Payoff: one mint ticked row and one fresh row in place, the field ready for the next item.
- Left out: the app bar (cropped above), the add sheet, keyboard, other stores.

### household-sync (wide 576 x 324, compact 358 x 448)
- Where: the "one household, live sync" video slot, as its poster.
- Focal object: Jonas's phone, where he just added Eier.
- Action: the same row lands on Anna's phone, which straddles Jonas's.
- Payoff: the row in mint on Anna's phone under "1 neu von Jonas", the members Anna and Jonas of „Unser Haushalt“ in their colours.
- Left out: a third phone, arrows or dotted flight lines, store sections beyond one.

Members keep one colour everywhere: Anna tomato, Jonas honey (navy letters). Item emoji are the ones `app/lib/list/list_view/item_icon.dart`
picks; store names are text in Snacklist colours only.

### mcp-chat (wide 576 x 324, compact 358 x 448)
- Where: the "any AI assistant with MCP" video slot, as its poster.
- Focal object: the Snacklist result card in a Snacklist-styled chat thread.
- Action: the request "Setz Milch, Eier und Äpfel auf unsere Einkaufsliste".
- Payoff: the card listing the three added items with their categories and mint ticks.
- Left out: any vendor name, logo, avatar, model picker, sparkle; the composer.

### stores (no longer a scene)
Job 145 replaced the stores still with live HTML: `site/landing.mjs` renders the store buttons and
the route, `site/public/stores.js` switches it, `site/checks/stores.mjs` drives it.

## Hand-over notes

Sheets: `/tmp/s53/scenes/<scene>-sheet.png` (8 frames each: wide, then compact; de, en; light,
dark), frames `/tmp/s53/scenes/<scene>-<locale>-<size>[-dark].png` at 2x. Every WebP is
29 to 50 KB at quality 90.

### hero
Plan: the list screen on one phone; Anna added Hafermilch; it sits honey-tinted in the list with the sync sticker; no tabs, status bar or second satellite.
Layout: Block with gutters on the cobalt ground, gutter 72 (sides and top), phone off the bottom with the add field whole and 44 px of list under it (19 px at compact); sticker straddles the top-left corner, rotated -3°. Compact 358: phone 24 px from the sides, the Wochenmarkt, Bäckerei and Drogerie stores dropped, sticker stacked centred over the phone's top edge.
Beats: still, stays a still on the page.
Captured: 500 and 358, light and dark, de and en. No reduced-motion or seam film (nothing moves).
Review: add field touched the bottom crop → Gurken dropped in wide, field now clear. "Emptiest of the five, no bleed off the right" → stands: the brief places it at the block's bottom, so it bleeds off the bottom only, and more rows would push the field out of the crop. Night-shadow halo in dark → stands, it is the `--hl-shadow-night-l` token.
Not checked: the image inside the real page at 390 and 1440 (the page is being built in parallel).

### add-tick
Plan: the Supermarkt part of the list and the add field; Bananen ticked in mint, 2× Avocados just added at the end of its category above the field; no app bar, sheet or keyboard.
Layout: Pinned bottom, cropped at the top inside the content (category label first) and off the bottom; gutter 48; the sticker "Hinzugefügt: Avocados" (the app's `addedItem`) straddles the right edge at the Avocados row, 12 px clear of its check box. Compact 358: app bar shown, sticker stacked over the phone's top edge.
Beats: poster only; job 54's footage replaces it.
Captured: 576 and 358, light and dark, de and en.
Review: half a row on the top crop → removed, the crop starts at the category label. Sticker nearly touching the check box → rotation removed, 12 px clear. Empty right third → stands: a portrait phone in a 16:9 slot, the phone holds two thirds and the sticker sits where the story lands; a wider phone would read as a tablet. New item not tinted → stands: the app tints only items a partner added, so the sticker carries "just added".
Not checked: how job 54's video frames line up with this poster.

### household-sync
Plan: Jonas's phone leads, the same Eier row arrives on Anna's phone in mint under "1 neu von Jonas" (the app's `newItemsFrom`); no third phone, no flight lines.
Layout: Phone pair; gutter 48; Anna's phone is narrower with the smaller sticker shadow, overlaps Jonas's bezel only, and its arriving row sits on the exact line of Jonas's row (measured 146 / 146). Compact 358: Anna's phone stacked over the lower half of Jonas's, its top edge between two of his rows.
Beats: poster only.
Captured: 576 and 358, light and dark, de and en.
Review: phone corners tangent → Jonas's phone moved up 16 px so the corners part clearly. A check box cut by the front phone in compact → front phone now covers that row's check box whole. Anna's avatar beside "von Jonas" → the avatar is now Jonas's J. Nothing shows Jonas adding → stands, the poster's point is the arrival; the video shows the add.
Not checked: real sync latency (a still has none).

### mcp-chat
Plan: a Snacklist-styled thread; the cobalt request bubble, then the Snacklist result card with the three items, their categories and mint ticks; no vendor name, logo, avatar, model picker or composer.
Layout: the thread on the scene ground, gutter 32; the card runs the full width under the right-aligned request. Compact 358: the card rows get a second line for the category, an assistant reply of bars bleeds off the bottom.
Beats: poster only.
Captured: 576 and 358, light and dark, de and en.
Review: grey bubble above the request → removed. Carrot for Spinat (the app's produce fallback) → the request now names Äpfel, which has its own emoji in the app. Ground differed from the other posters → all posters on `--hl-color-surface-raised`. Nothing says "AI assistant" → stands: an assistant avatar or label is exactly the vendor look the brief rules out; the page caption says "any AI assistant with MCP".
Not checked: whether real MCP tool results classify Äpfel as Obst & Gemüse and Eier as Kühlregal on the demo household (assumed from the seeded categories).

Not watched by anyone: the WebPs in the built page at 390 and 1440 wide, and the page's frame
(28 px radius, 2 px navy contour) clipping them.
