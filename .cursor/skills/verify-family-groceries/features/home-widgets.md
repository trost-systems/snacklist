# Home Screen widgets

The iOS and Android apps put the list last shown in the app (its household and list) on the Home Screen: the open count, the next items with their quantity, and (medium size) the store's name in a hex pill and an Add button. A tap on the widget opens the list; Add opens the list with the add sheet ready for typing. Signed out or without a household the widget asks the user to open Snacklist. The widget reads only what the app last wrote (docs/HOME_WIDGETS.md): nothing native talks to the server, and nothing is ticked from the widget.

## Sub-features

- `widget-payload` the app writes one JSON string, key `snacklist_widget`, version 1: `state` (`ready`, `signedOut`, `noHousehold`), `open`, the first six open `items` (name, quantity, the store's full name or null) in the List tab's order, `updatedAt`.
- `widget-sync` `HomeWidgetSync` (`app/lib/home_widget/`) follows the session and the list cubit of the shown list, writes at most once a second and only when the payload changed, never a list of another household than the session's. Offline, the cached list goes out at start.
- `widget-small` iOS systemSmall / Android 2x2: count, up to three rows without store pills (fewer when the height is short), „+N weitere“/"+N more"; the whole widget opens the list.
- `widget-medium` iOS systemMedium / Android 4x2 (from 250 dp wide): count, up to five rows, a store pill on the first row of each store run (`ListRow.rows`, `widgetRows`), „Hinzufügen“/"Add", „+N weitere“/"+N more".
- `widget-empty` an empty list: „Alles erledigt“ / "All done"; medium keeps the Add button.
- `widget-prompts` „Melde dich in Snacklist an“ / "Sign in to Snacklist", „Richte deinen Haushalt in Snacklist ein“ / "Set up your household in Snacklist", and before the app ever wrote: „Öffne Snacklist, um deine Liste zu sehen“ / "Open Snacklist to see your list".
- `widget-launch` `snacklist-widget://open/?homeWidget` opens the list, `snacklist-widget://add/?homeWidget` the list with the add sheet open (`widget_launch.dart`, App's `_onWidgetLaunch`, the List tab's `AddSheetRequest`). Signed out, the router sends both to the start screen; an Add request stays pending until the List tab is built.

## How to get to it (user POV)

- iPhone: hold the Home Screen, Bearbeiten → Widget hinzufügen → Snacklist, small or medium. Android: hold the Home Screen → Widgets → Snacklist, drag it out; four columns wide shows the medium layout.
- Guide (draft until the `home-widgets` hold ends): `/de/anleitungen/widget`, `/en/guides/widget`.

## Driving it with fg

Preconditions:

- None of it is drivable with fg: the linux surface has no Home Screen and `homeWidgetSyncFor` returns null there (also on the web), and the build boxes run no simulator or emulator.

- **Payload and sync.** `cd app && flutter test test/home_widget` (22 tests, all passed on 2026-11-23 on d023441d; the Android side's `WidgetPayloadTest` runs in the `android` gate) runs the serializer (states, order across stores and walk order, six items, the count, full store names, deleted stores), the sync against a fake publisher (signed out, no household, debounce, unchanged payloads, another household, a failed write retried) and against the real `ListCubit` (add, tick, a partner's row, sign-out, an offline start from the cache).
- **Taps.** The same run covers the link mapping (open, add; the auth callback and invite links are not the widget's), the starting tap and later ones, and the List tab opening the add sheet for a request made before it was built (cold start) and while it shows.
- **Native builds.** CI's `ios` job builds the app with the extension for the simulator and checks `Runner.app/PlugIns/HomeWidget.appex` and its version; the `android` job builds the debug APK with the Glance widget.
- **Proof.** The test output and the green CI jobs. Screenshots need a device (Peter's device test, docs/NEEDS_PETER.md job 63).

## Gotchas

- iOS release signing needs the App ID `com.snacklist.app.HomeWidget`, the App Group on both App IDs and a renewed match profile first (docs/NEEDS_PETER.md, job 63; docs/RELEASE.md).
- The widget follows the phone's light or dark setting, not the app's own theme choice.
- A partner's change reaches the widget only after the app on this phone saw it (open, or still running with realtime). There is no background refresh in v1.
