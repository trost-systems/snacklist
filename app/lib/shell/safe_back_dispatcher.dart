import 'package:family_groceries/shell/router.dart' show listPath;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// [router] as the app's router config, with system back guarded by
/// [SafeBackDispatcher].
RouterConfig<RouteMatchList> guardedBack(GoRouter router) => RouterConfig(
  routeInformationProvider: router.routeInformationProvider,
  routeInformationParser: router.routeInformationParser,
  routerDelegate: router.routerDelegate,
  backButtonDispatcher: SafeBackDispatcher(router),
);

/// The root back dispatcher. While the router's configuration is empty,
/// back goes to the list and reports a `StateError`
/// ([emptyConfigurationOnBack]).
///
/// The configuration goes empty when a pop removes the tab shell, the root
/// navigator's only page: a popup closed during its save (back, Escape, a
/// barrier tap, a drag) and popped once the save answered (job 438). The
/// app is blank then (go_router's assert is debug-only), and go_router's
/// `popRoute` (18.1.1, `_findCurrentNavigators`) throws `Bad state: No
/// element` on the next back, so the user saw a blank app and then left
/// it. popIfCurrent fixes the pops and the `pop-if-current-after-await`
/// lint keeps new ones out; this catches a pop the lint cannot see (a
/// Timer, a helper) and gives the user the list back. The report keeps it
/// visible in error tracking.
class SafeBackDispatcher(final GoRouter router)
    extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() {
    if (router.routerDelegate.currentConfiguration.matches.isNotEmpty) {
      return super.didPopRoute();
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(emptyConfigurationOnBack),
        stack: StackTrace.current,
        library: 'shell',
        context: ErrorDescription('on system back; going to the list'),
      ),
    );
    router.go(listPath);
    return Future.value(true);
  }
}

/// The message [SafeBackDispatcher] reports.
const emptyConfigurationOnBack = 'System back on an empty router configuration';
