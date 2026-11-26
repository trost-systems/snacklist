import 'package:flutter/widgets.dart';

/// Pops the route [context] belongs to with [result], only while it is the
/// current one.
///
/// A popup closed during an `await` (back, Escape, a barrier tap, a drag)
/// stays mounted for its exit animation but is no longer present: a plain
/// `Navigator.pop()` then removes the page below it, and with the tab shell
/// as the root navigator's only page the app is blank (job 438).
void popIfCurrent<T extends Object?>(BuildContext context, [T? result]) {
  if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
    Navigator.of(context).pop(result);
  }
}

/// Pops [route] with [result], only while it is the current one.
///
/// For a page inside a popup that can go before the popup does (the
/// switcher sheet's pages fade out when the session changes under them):
/// capture `ModalRoute.of(context)` before the `await` and pop that, since
/// the page's own context may be unmounted when the popup still shows.
void popRouteIfCurrent<T extends Object?>(Route<T>? route, [T? result]) {
  if (route != null && route.isCurrent) {
    route.navigator?.pop(result);
  }
}
