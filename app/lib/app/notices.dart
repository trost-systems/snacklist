import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Follows the root navigator's top route: dialogs and sheets go there
/// (`showModalBottomSheet` with `useRootNavigator: true`, the
/// `popups-on-root-navigator` lint). A popup on a nested navigator (a
/// dropdown's menu inside a tab) goes unseen. Notifies when [open] changes.
class Popups() extends NavigatorObserver with ChangeNotifier {
  Route<dynamic>? _top;

  /// The app's, from its [NoticesHost].
  static Popups? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Host>()?.popups;

  /// A dialog or sheet is on top, and its barrier covers every page.
  bool get open => _top is PopupRoute;

  /// Whether a dialog or sheet covers [context]'s page; false outside a
  /// [NoticesHost].
  static bool openAbove(BuildContext context) =>
      maybeOf(context)?.open ?? false;

  void _setTop(Route<dynamic>? route) {
    final was = open;
    _top = route;
    if (open != was) {
      notifyListeners();
    }
  }

  /// Once per change of the history, with the route that is really on top:
  /// a page the router adds below an open dialog (didPush) leaves it there.
  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) => _setTop(topRoute);
}

/// A messenger whose snackbars the user sees: [ScaffoldMessenger.of]
/// shows them in the page's Scaffold, which an open dialog's or sheet's
/// barrier covers, dimmed, out of reach and out of the semantics tree.
/// While one is open they show above it instead (job 116).
final class Notices._(final ScaffoldMessengerState _page, final _Host? _host) {
  /// Notices for [context]'s messenger.
  factory of(BuildContext context) => Notices._(
    ScaffoldMessenger.of(context),
    context.getInheritedWidgetOfExactType<_Host>(),
  );

  /// Like `Notices.of`, or null without a messenger.
  static Notices? maybeOf(BuildContext context) =>
      ScaffoldMessenger.maybeOf(context) == null ? null : Notices.of(context);

  /// Decided when shown: a notice taken before an await may show while a
  /// dialog opened meanwhile.
  ScaffoldMessengerState get _messenger => switch (_host) {
    _Host(:final popups, :final above) when popups.open =>
      above.currentState ?? _page,
    _ => _page,
  };

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar,
  ) => _messenger.showSnackBar(snackBar);

  void hideCurrentSnackBar() => _messenger.hideCurrentSnackBar();
}

/// Goes around the app's navigator (`MaterialApp.builder`): above it, a
/// messenger for [Notices] while one of [popups] is open.
class const NoticesHost({
  required final Popups popups,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  @override
  State<NoticesHost> createState() => _NoticesHostState();
}

class _NoticesHostState() extends State<NoticesHost> {
  final _above = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    widget.popups.addListener(_onPopups);
  }

  @override
  void didUpdateWidget(NoticesHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.popups != widget.popups) {
      oldWidget.popups.removeListener(_onPopups);
      widget.popups.addListener(_onPopups);
    }
  }

  @override
  void dispose() {
    widget.popups.removeListener(_onPopups);
    super.dispose();
  }

  /// Once the last dialog or sheet has closed, what was said above it goes:
  /// left there it would cover the tabs and take their taps (review 0).
  /// After the build, since a route can leave while the router rebuilds
  /// the navigator.
  void _onPopups() {
    if (widget.popups.open) {
      return;
    }
    scheduleMicrotask(() {
      if (!widget.popups.open) {
        _above.currentState
          ?..clearSnackBars()
          ..removeCurrentSnackBar();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _Host(
    popups: widget.popups,
    above: _above,
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Its own Scaffold, in the app's MediaQuery: the snackbar sits above
        // the keyboard the dialog's field opened.
        _SnackBarsOnly(
          child: ScaffoldMessenger(
            key: _above,
            child: const Scaffold(
              primary: false,
              backgroundColor: Colors.transparent,
              body: _Background(),
            ),
          ),
        ),
      ],
    ),
  );
}

class const _Host({
  required final Popups popups,
  required final GlobalKey<ScaffoldMessengerState> above,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_Host oldWidget) => false;
}

/// The layer's Scaffold takes every hit with its Material; a hit that lands
/// on [_Background], under the snackbar, goes on to the routes below. An
/// IgnorePointer would not do: while a dialog is open the snackbar takes
/// taps and the dialog around it too.
class const _SnackBarsOnly({required super.child})
    extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSnackBarsOnly();
}

class _RenderSnackBarsOnly() extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final probe = BoxHitTestResult();
    if (!super.hitTest(probe, position: position) ||
        probe.path.first.target is _RenderBackground) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class const _Background() extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBackground();
}

class _RenderBackground() extends RenderBox {
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;
}
