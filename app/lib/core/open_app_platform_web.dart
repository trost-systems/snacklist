import 'dart:async';

import 'package:web/web.dart' as web;

String? browserUserAgent() => web.window.navigator.userAgent;

/// Leaves for [app] in this tab, within the tap: a browser opens another
/// app only from a user's gesture. Safari stays on the page when no app
/// takes the link, so [store] follows if the page still shows after a
/// moment.
void navigateToApp(String app, {String? store}) {
  web.window.location.href = app;
  if (store != null) {
    Timer(const Duration(milliseconds: 1500), () {
      if (web.document.visibilityState == 'visible') {
        web.window.location.href = store;
      }
    });
  }
}
