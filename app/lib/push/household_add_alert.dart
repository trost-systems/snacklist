import 'dart:async';

import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The signed-in user's household-add alert on the server
/// (`public.push_preferences`, docs/PUSH.md, "Household add").
abstract interface class HouseholdAddPrefs() {
  /// Whether the alert is on and the language its text is written in; null
  /// when the user never switched it.
  Future<({bool on, String language, bool nameHidden})?> load();

  Future<void> save({required bool on, required String language});

  Future<void> saveNameHidden({required bool hidden});
}

class const SupabaseHouseholdAddPrefs(final SupabaseClient _client)
    implements HouseholdAddPrefs {
  @override
  Future<({bool on, String language, bool nameHidden})?> load() async {
    final row = await _client
        .from('push_preferences')
        .select('household_add, language, name_hidden')
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return (
      on: row['household_add'] == true,
      language: row['language'] as String? ?? 'de',
      nameHidden: row['name_hidden'] == true,
    );
  }

  @override
  Future<void> saveNameHidden({required bool hidden}) =>
      _client.rpc<void>('set_push_name_hidden', params: {'p_hidden': hidden});

  @override
  Future<void> save({required bool on, required String language}) =>
      _client.rpc<void>(
        'set_push_household_add',
        params: {'p_on': on, 'p_language': language},
      );
}

/// What a switch of the alert came to.
enum HouseholdAddResult() {
  done,

  /// The OS refuses notifications; nothing was switched on.
  blocked,

  /// The server did not take it (offline); the switch stays as it was.
  failed,
}

/// The in-app push types other than the household-add alert that are on for
/// the signed-in user, as each type reports it (the shopping-day reminder
/// reads its days from the server; one that cannot be read reports off, so a
/// phone that cannot be asked is taken off push). The household-add off keeps
/// the device registered while any is on (Legal N-427, N-436).
class PushAlertRegistry() {
  final _sources = <FutureOr<bool> Function()>[];

  void register(FutureOr<bool> Function() isOn) => _sources.add(isOn);

  Future<bool> get anyOn async {
    for (final isOn in _sources) {
      if (await isOn()) {
        return true;
      }
    }
    return false;
  }
}

/// What the signed-in user chose about the household-add alert.
class const HouseholdAddChoice({
  required final bool on,
  required final bool nameHidden,
});

/// Whether the signed-in user gets a push when another member adds an item
/// (job 377), and whether their own name is left out of other members'
/// pushes (Art. 21). Null until the server has answered for the user who is
/// signed in: another account signing in on the device resets it. It reads
/// "on" only while this device is opted in too ([PushRegistration]): the
/// server's row belongs to the account, and a signed-out-and-in or a second
/// phone gets no push until its own yes. Without push (the web) only the
/// name switch exists ([canNotify]). Off by default: the first yes is also
/// what asks the OS for permission
/// ([PushRegistration]), and an off is what [PushRegistration.forget]s the
/// device, the same path as a sign-out (Legal N-401), unless [alerts]
/// says another alert (the shopping-day reminder) still needs it (N-427). An
/// off the server did not take is kept in [pending] and sent again at the
/// next start or sign-in of that account until it is taken (N-439).
class HouseholdAddAlert(
  final PushRegistration? _push,
  final HouseholdAddPrefs _prefs, {
  final PushAlertRegistry? alerts,
  final PendingOffStore? pending,
}) extends Cubit<HouseholdAddChoice?> {
  this : super(null);

  String? _userId;
  StreamSubscription<Session>? _sessions;

  /// Whether this build can show notifications at all (iOS and Android).
  bool get canNotify => _push != null;

  bool get _deviceOptedIn => switch (_push?.state) {
    PushOn() || PushBlocked() => true,
    PushOff() || null => false,
  };

  /// Whether the alert is on for this user on this device, read from the
  /// server. False when it cannot be read: the shopping-day reminder's last
  /// day off then takes the device off push (N-436) rather than leave the
  /// token of a phone that cannot be asked.
  Future<bool> isOn() async {
    try {
      final saved = await _prefs.load();
      return (saved?.on ?? false) && _deviceOptedIn;
    } on Object {
      return false;
    }
  }

  /// Forgets the choice of whoever was signed in before when the user
  /// changes; the settings read it again each time they open.
  void follow(StateStreamable<Session> session) {
    _follow(session.state);
    _sessions = session.stream.listen(_follow);
  }

  void _follow(Session session) {
    final user = switch (session) {
      InHousehold(:final userId) || NeedsHousehold(:final userId) => userId,
      SignedOut() => null,
      SessionLoading() => _userId,
    };
    if (user != _userId) {
      _userId = user;
      emit(null);
      if (user != null) {
        unawaited(_sendPendingOff(user));
      }
    }
  }

  /// Sends an off this account switched while the server could not be
  /// reached, and forgets it once the server took it. Another account's
  /// pending off waits for that account.
  Future<void> _sendPendingOff(String user) async {
    final store = pending;
    final off = await store?.pendingOff();
    if (store == null || off == null || off.userId != user) {
      return;
    }
    try {
      await _prefs.save(on: false, language: off.language);
    } on Object {
      return;
    }
    await store.savePendingOff(null);
  }

  /// Reads the setting, and writes [language] again when the app's language
  /// changed since the alert was switched on, so the text follows it. False
  /// when the setting could not be read.
  Future<bool> refresh(String language) async {
    final user = _userId;
    var read = false;
    try {
      if (user != null) {
        await _sendPendingOff(user);
      }
      await _push?.resume();
      final saved = await _prefs.load();
      read = true;
      if (user != _userId) {
        return true;
      }
      final on = (saved?.on ?? false) && _deviceOptedIn;
      emit(HouseholdAddChoice(on: on, nameHidden: saved?.nameHidden ?? false));
      if (saved != null && on && saved.language != language) {
        await _prefs.save(on: true, language: language);
      }
    } on Object {
      // Offline: the settings offer to try again.
    }
    return read;
  }

  Future<HouseholdAddResult> set({
    required bool on,
    required String language,
  }) async {
    final push = _push;
    if (push == null) {
      return HouseholdAddResult.failed;
    }
    if (on && !await push.optIn()) {
      return HouseholdAddResult.blocked;
    }
    final user = _userId;
    if (!on && !(await alerts?.anyOn ?? false)) {
      // Before the save: an off that cannot reach the server still takes
      // this device off push, as a sign-out does. The server's row stays
      // on, which this device shows as off.
      await push.forget();
    }
    try {
      await _prefs.save(on: on, language: language);
      await pending?.savePendingOff(null);
    } on Object {
      if (!on && user != null) {
        await pending?.savePendingOff((userId: user, language: language));
      }
      if (!on && user == _userId) {
        emit(
          HouseholdAddChoice(on: false, nameHidden: state?.nameHidden ?? false),
        );
      }
      return HouseholdAddResult.failed;
    }
    if (user == _userId) {
      emit(HouseholdAddChoice(on: on, nameHidden: state?.nameHidden ?? false));
    }
    return HouseholdAddResult.done;
  }

  Future<HouseholdAddResult> setNameHidden({required bool hidden}) async {
    final user = _userId;
    try {
      await _prefs.saveNameHidden(hidden: hidden);
    } on Object {
      return HouseholdAddResult.failed;
    }
    if (user == _userId) {
      emit(HouseholdAddChoice(on: state?.on ?? false, nameHidden: hidden));
    }
    return HouseholdAddResult.done;
  }

  @override
  Future<void> close() async {
    unawaited(_sessions?.cancel());
    await super.close();
  }
}
