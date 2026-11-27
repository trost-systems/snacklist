# Accessibility: screen readers

Rules for VoiceOver (iOS) and TalkBack (Android) in the Flutter app, from Peter's device walk
(job 474). Each rule names where it lives and the test that holds it.

## Announce what the user just did

Say the result of an action that changes the list, on the optimistic update, through
`ScreenReader.of(context).announce(...)` (`app/lib/core/screen_reader.dart`). Never call
`SemanticsService` directly: the lint `announce-through-screen-reader` stops it. `ScreenReader`
speaks after the frame that shows the change (300 ms later while VoiceOver or TalkBack runs), so a
focus move does not read over it, and joins what one moment says into one announcement.

| Action | DE | EN |
| --- | --- | --- |
| Add | „Milch hinzugefügt“ | "Milch added" |
| Tick | „Milch abgehakt“ | "Milch ticked off" |
| Undo of a tick (snackbar „Rückgängig“, trip mode's „Zurücknehmen“) | „Milch wieder auf der Liste“ | "Milch back on the list" |
| Put back from „Zuletzt verwendet“ | „Milch wieder auf der Liste“ | "Milch back on the list" |
| Edit saved | „Name auf Kosmetiktücher, Menge auf 2 und Laden auf Edeka geändert“ | "Changed name to Kosmetiktücher, quantity to 2 and store to Edeka" |
| Edit emptied a field | „Menge entfernt“ | "Removed quantity" |
| Store done card appears | „Lidl ist erledigt. Lidl Plus öffnen.“ | "Lidl is done. Open Lidl Plus." |
| List tab shown | „Auf Liste Einkaufsliste im Haushalt Zuhause, 3 offen“ | "On list Shopping list in household Zuhause, 3 open items" |

An edit that changed nothing says nothing, and neither does a rename that merges into an open
item: its snackbar („Zusammengeführt: …“) says what happened. A failed call that reverts the UI
is said by its snackbar.

Say each thing once. When a snackbar shows what was already announced (the tick's „Abgehakt:
<Name>“ with „Rückgängig“), make its text a node of its own (`_snack(said: true)`): iOS and Android
announce a live region's own label, which is then empty, while the text and the action stay
reachable. The web's live region reads its whole content, so it repeats there.

## Keep the focus where the user was

When the node holding the focus leaves the tree, VoiceOver jumps to the screen's first element (the
household chip). Before it goes, pick where the focus belongs and send it there with
`ScreenReader.moveFocus([...])`, by `Semantics.identifier`: the next row after a tick, the store
card when it appears, the top row of „Zuletzt verwendet“ after a put-back.

## One stop per control

- Steppers are one adjustable node (`QuantitySemantics`): label „Menge“ / "Quantity", the value
  first, swipe up or down to step. − and + are no stops of their own. iOS and Android only: on the
  web an adjustable node is a range input that a pointer click moves too, so there − and + stay
  labelled buttons.
- A switch carries its explainer as its subtitle, so both are read as one stop
  („Beitritte bestätigen“).
- Write labels out: „Menge“ / "Quantity", never "Qty".

## No unlabeled or decorative containers

A container gets a label only when the label says what the user can do there. The add sheet's
container had „Hinzufügen“ and was a stop in front of its buttons; it now has none. A container
without a label that tests or e2e need to find gets a `Semantics.identifier` (web:
`[flt-semantics-identifier="add-sheet"]`).

## A screen without a visible title still names itself

More has no visible title; a heading node „Mehr“ / "More" above its rows is what a screen reader
reads on arrival.

## Tests

Semantics in widget tests: `tester.ensureSemantics()`, `isSemantics(...)`,
`tester.semantics.simulatedAccessibilityTraversal()` for order, `tester.semantics.increase(...)` for
adjustable nodes. Announcements: `tester.takeAnnouncements()`; for focus and announcements in order,
`screenReaderLog(tester)` (`app/test/core/screen_reader_harness.dart`). Emulate VoiceOver's timing
with `tester.platformDispatcher.accessibilityFeaturesTestValue = const
FakeAccessibilityFeatures(accessibleNavigation: true)` and pump `announceSettle`.
