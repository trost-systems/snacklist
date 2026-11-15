# Reload indicator: recommendation (job 273, round RI)

Question: how should the add sheet show that the server’s suggestions are still on the way, without rows jumping under the finger? Today shows nothing (`AddSheetState.fresh` is unused in the UI, EVIDENCE gap 3). The debounce stays at today’s 120 ms.

## Measured

<!-- table -->
| Option | Indicator during the whole load (ms to visible) | Gone in the first frame with the reply’s rows | Sheet height while loading / at the reply | Row moved while loading | Row under the finger swaps at the reply | Typed row shows the text | Tap while loading takes the row shown | Obviousness, the least: pixels the indicator changes by ≥ 3:1 (median), + pixels changed less | Text cut, spilling or overlapping at 200 % (main’s chrome included) | Reduced motion: stands still |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Today** | no | — | 0 px / +307 px (DE 200 %) | 0 px | yes (EN 100 %, EN 200 %) | no | yes in EN 100 %, EN 200 %; no second row in DE 100 %, DE 200 % | no indicator | 2 | — |
| **272 base, no indicator** | no | — | 0 px / +34 px (DE 200 %) | 0 px | no | yes | yes in EN 100 %, EN 200 %; no second row in DE 100 %, DE 200 % | no indicator | 2 | — |
| **RI1 Dim stale rows** | no in DE 100 %, DE 200 %, else yes (≤ 1 frame) | yes | 0 px / +34 px (DE 200 %) | 0 px | no | yes | yes in EN 100 %, EN 200 %; no second row in DE 100 %, DE 200 % | 0 px² + 0 px² (DE 100 %, DE 200 %) | 2 | yes |
| **RI2 Progress line** | yes (≤ 1 frame) | yes | 0 px / +34 px (DE 200 %) | 0 px | no | yes | yes in EN 100 %, EN 200 %; no second row in DE 100 %, DE 200 % | 312 px² (8.9:1) + 468 px² | 2 | yes |
| **RI3 Spinner in the field** | yes (≤ 1 frame) | yes | 0 px / +34 px (DE 200 %) | 0 px | no | yes | yes in EN 100 %, EN 200 %; no second row in DE 100 %, DE 200 % | 68 px² (5.8:1) + 76 px² (EN 200 %, DE 100 %) | 2 | yes |
<!-- /table -->

Measured by `verify.mjs` in Chromium, in English and German at 100 % and 200 % text: the fast typist types “Milk” (“Milch”) at 70 ms per key with a 450 ms reply, sampled on every animation frame; the tap test types at 220 ms per key with an 1800 ms reply and taps the second row while it loads. Every cell but the 200 % column is the worst of the four settings; where it differs between them, the cell names the settings it holds for.

- German “Milch” starts with no row to keep: the device has nothing for “M”, so while it loads every phone shows only the typed row. RI1 then dims nothing (0 px²), and the tap test has no second row to tap.
- In German at 200 % the reply’s “Buttermilch · Schon mal gekauft · Rewe” wraps to two lines, so the sheet grows 34 px at the reply in the control and in every option: the four kept slots are one line high. In the other three settings it stays at 0 px.
- “272 base, no indicator” is the control: job 272’s live typed row and four kept row slots, with nothing else. RI1–RI3 are that phone plus their indicator. The columns about heights, moving rows, the swap and the typed row come from the base: compare RI1–RI3 with the control row there, not with Today.
- “Gone in the first frame with the reply’s rows” checks the frame in which the reply’s rows are painted.
- “Obviousness” compares the loading phone with and without its indicator, pixel by pixel, the same way for every option, and reports the least of the four settings. The first number counts the pixels the indicator changes by at least 3:1 (the visible mark: RI2’s moving segment, RI3’s ring, RI1’s dimmed glyphs), with their median contrast. The second counts the pixels it changes less (RI2’s faint track, the soft edges of RI1’s glyphs). RI2’s line and RI3’s ring keep their size at 200 % (312 px² and 68 px² in all four settings); RI1 changes 599 px² in English at 100 % and 3005 px² at 200 %, and nothing in German.
- “Text cut, spilling or overlapping at 200 %” includes main’s chrome: the 2 in every phone are the German household name, “Zuhause”, ending in an ellipsis.

## Pick: RI2 Progress line

In all four settings RI2 shows for the whole load within one frame of the keystroke, is gone in the frame that paints the reply, takes no height while loading and stands still with reduced motion. At the reply it adds nothing to the control: 0 px, and the control’s 34 px in German at 200 %. Its moving segment is a 312 px² mark at 8.9:1 in every setting, 4.6 times RI3’s ring, and it leaves the rows as they are, so a row that takes a tap does not look disabled. It also shows when no row is stale, as for German “Milch”.

## Runner-up: RI1 Dim stale rows

In English RI1 is the most visible change (599 px² change by at least 3:1 at 100 %, 3005 px² at 200 %, median 4.4:1) and the only one that says which rows may still change, also to screen readers. It can only dim rows that exist: in German “Milch” loads with nothing but the typed row, and RI1 shows nothing for the whole load (RI-Q6). The same dimming makes rows look disabled while they still take a tap. Both are why it is second.

## What else the table shows

- RI3’s spinner is the smallest mark that always shows (68 px² at 5.8:1 in every setting) and sits in the field where the eyes are while typing; it is easy to miss next to the clear ✕.
- The jump at the reply is fixed by job 272’s base, not by any indicator. Today grows 60 px in English at 100 % and up to 307 px in German at 200 % (a German sheet starts with one row), and in English the row under the finger swaps. The control without an indicator shows no swap and 0 px, except the 34 px of a wrapped row in German at 200 %. That part belongs to job 272.

## Open questions

1. RI-Q1: How many row slots does the sheet keep while typing? Default: 4 (the typed row and three more), which kept the height at the reply at 0 px for “Milk” and “Milch” at 100 % and for “Milk” at 200 %. The slots are one line high: in German at 200 % a reply row wraps to two lines and the sheet still grows 34 px, and a reply with more rows than slots grows it too.
2. RI-Q2: Where does the line run: the sheet’s bottom edge above the field, or its top edge under the chips? Default: the bottom edge, right above the field the user is typing in.
3. RI-Q3: Does the line also show for the first letter, when the rows were made on the device? Default: yes, whenever `fresh` is false, as built.
4. RI-Q4: A fast reply (150 ms) makes the line flash. Default: show it at once anyway; a delay would hide slow first replies, and the flash is 2 px high.
5. RI-Q5: Do screen readers also get RI1’s “older suggestion, still loading” on provisional rows? Default: yes, the label without the dimming, plus the line’s progressbar role.
6. RI-Q6: RI1 shows nothing while no row is stale, as when the device has nothing for the first letter (German “M”). If RI1 is picked, what shows then? Default: RI2’s line whenever no row is stale; as built, RI1 shows nothing.
