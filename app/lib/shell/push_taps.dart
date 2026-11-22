import 'dart:async';

import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/push/push_target.dart';
import 'package:family_groceries/session/session_cubit.dart';

/// Opens the list a tapped notification names (docs/PUSH.md, "Tap"), once
/// the session is known: a cold start's tap comes while it still loads.
/// In one of the user's households the app switches to it first, and the
/// list takes the [ShowListLink]; a household the user left gets the link
/// too, which the shown household's list does not know, so it stays as it
/// is. Signed out or without a household the tap is dropped. Each tap then
/// calls [_openList], which goes to the list (or `authRedirect`'s gate).
class PushTaps(
  final SessionCubit _session,
  final ListLinks _links,
  final void Function() _openList,
) {
  StreamSubscription<PushTarget>? _taps;
  StreamSubscription<Session>? _sessions;

  /// The tapped notification's list while the session is still loading.
  PushTarget? _waiting;

  void follow(Stream<PushTarget> taps) {
    _taps = taps.listen((target) {
      _waiting = target;
      _open();
    });
    _sessions = _session.stream.listen((_) => _open());
  }

  void _open() {
    final target = _waiting;
    if (target == null) {
      return;
    }
    switch (_session.state) {
      case SessionLoading():
        return;
      case SignedOut() || NeedsHousehold():
        _waiting = null;
      case InHousehold(:final household, :final households):
        _waiting = null;
        if (household.id != target.householdId &&
            households.any((h) => h.id == target.householdId)) {
          // Emits at once: the list gets the link in the new household.
          unawaited(_session.switchTo(target.householdId));
        }
        _links.pending = ShowListLink(target.listId);
    }
    _openList();
  }

  Future<void> cancel() async {
    await _taps?.cancel();
    await _sessions?.cancel();
  }
}
