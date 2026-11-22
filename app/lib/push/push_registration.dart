import 'dart:async';

import 'package:family_groceries/push/push_plugin.dart';
import 'package:family_groceries/push/push_target.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// Push on this device (docs/PUSH.md, "The app").
sealed class const PushState();

/// Not opted in here, or the opt-in went with a sign-out.
final class const PushOff() extends PushState;

/// The user wants push, but the OS refuses notifications: at the prompt,
/// or switched off in the system settings since. Opted in from before, a
/// later start registers again once they are allowed.
final class const PushBlocked() extends PushState;

/// Opted in and allowed: the device's token is registered, or is with the
/// next start or token refresh if this try failed (offline).
final class const PushOn() extends PushState;

/// What this device keeps about push between starts.
enum PushDevice() {
  /// No opt-in here, and no token left to delete.
  off,

  /// The user opted in on this device.
  optedIn,

  /// A sign-out could not delete the token at the messaging service
  /// (offline): the next start, sign-in, sign-out or opt-in deletes it
  /// first, so the account that left gets nothing more on this device.
  tokenLeft,
}

/// The [PushDevice] of this device.
abstract interface class PushStore() {
  Future<PushDevice> pushDevice();

  Future<void> savePushDevice(PushDevice device);
}

/// The signed-in user's devices on the server (`public.push_tokens`).
abstract interface class PushTokens() {
  Future<void> register(String token, PushPlatform platform);

  Future<void> unregister(String token);
}

class const SupabasePushTokens(final SupabaseClient _client)
    implements PushTokens {
  @override
  Future<void> register(String token, PushPlatform platform) =>
      _client.rpc<void>(
        'register_push_token',
        params: {'p_token': token, 'p_platform': platform.name},
      );

  @override
  Future<void> unregister(String token) =>
      _client.rpc<void>('unregister_push_token', params: {'p_token': token});
}

/// Keeps this device's token registered for the signed-in user while they
/// opted in, and hands on the targets of tapped notifications. Its work
/// runs one step after the other, so a sign-out right after a sign-in ends
/// unregistered.
class PushRegistration(
  final PushPlugin _plugin,
  final PushStore _store,
  final PushTokens _tokens,
) extends Cubit<PushState> {
  this : super(const PushOff());

  Future<void> _work = Future.value();

  /// The user the last start or sign-in resumed for.
  String? _userId;
  StreamSubscription<String>? _refreshes;
  StreamSubscription<Map<String, Object?>>? _opened;

  /// Buffers until the app listens: a cold start's tap may come first.
  final _taps = StreamController<PushTarget>();

  /// The target of each tapped notification this app knows how to open:
  /// the one that started the app, then those that brought it back. Taps
  /// are followed once the user opted in on this device.
  Stream<PushTarget> get taps => _taps.stream;

  /// Resumes for each user who signs in (or starts signed in), and forgets
  /// on this device at any sign-out: one this device started has
  /// [forget]ed before; others (an account deletion, a session that ended
  /// elsewhere) leave the server rows to the cascade or to the send, which
  /// drops a deleted token.
  StreamSubscription<Session> follow(StateStreamable<Session> session) {
    _follow(session.state);
    return session.stream.listen(_follow);
  }

  void _follow(Session session) {
    switch (session) {
      case InHousehold(:final userId) || NeedsHousehold(:final userId):
        if (userId == _userId) {
          return;
        }
        final before = _userId;
        _userId = userId;
        if (before != null) {
          // Another account signed in over this one starts without push.
          unawaited(_run(_dropHere));
        }
        unawaited(resume());
      case SignedOut():
        _userId = null;
        unawaited(_run(_dropHere));
      case SessionLoading():
        break;
    }
  }

  /// Asks the OS for permission (the only place that prompts) and, given,
  /// registers this device and remembers the opt-in. True when push is on.
  Future<bool> optIn() => _run(() async {
    await _deleteLeftToken();
    final PushPermission permission;
    try {
      permission = await _plugin.requestPermission();
    } on Object {
      return false;
    }
    if (permission != PushPermission.granted) {
      emit(const PushBlocked());
      return false;
    }
    await _store.savePushDevice(PushDevice.optedIn);
    emit(const PushOn());
    _followTaps();
    await _register();
    return true;
  });

  /// With the opt-in remembered and notifications still allowed, registers
  /// the current token again; never prompts.
  Future<void> resume() => _run(() async {
    await _deleteLeftToken();
    if (await _store.pushDevice() != PushDevice.optedIn) {
      emit(const PushOff());
      return;
    }
    _followTaps();
    try {
      if (await _plugin.permission() != PushPermission.granted) {
        emit(const PushBlocked());
        return;
      }
    } on Object {
      return;
    }
    emit(const PushOn());
    await _register();
  });

  /// Before a sign-out, while the session still exists: unregisters this
  /// device (briefly; offline the send drops the deleted token later),
  /// deletes the token and forgets the opt-in. Offline, the token is
  /// deleted at the next chance ([PushDevice.tokenLeft]).
  Future<void> forget() => _run(() async {
    if (await _store.pushDevice() != PushDevice.optedIn) {
      await _deleteLeftToken();
      return;
    }
    try {
      await () async {
        if (await _plugin.token() case final token?) {
          await _tokens.unregister(token);
        }
      }().timeout(const Duration(seconds: 2));
    } on Object {
      // Offline or refused: the token is deleted below either way.
    }
    await _dropHere();
  });

  /// Deletes the token and forgets the opt-in on this device only; a
  /// token that could not be deleted is remembered for the next chance.
  Future<void> _dropHere() async {
    if (await _store.pushDevice() == PushDevice.optedIn) {
      await _store.savePushDevice(PushDevice.tokenLeft);
    }
    await _deleteLeftToken();
    emit(const PushOff());
  }

  /// Deletes a token a sign-out left behind. FCM needs the network for it;
  /// until it answers, the token stays [PushDevice.tokenLeft].
  Future<void> _deleteLeftToken() async {
    if (await _store.pushDevice() != PushDevice.tokenLeft) {
      return;
    }
    try {
      await _plugin.deleteToken().timeout(const Duration(seconds: 3));
    } on Object {
      return;
    }
    await _store.savePushDevice(PushDevice.off);
  }

  Future<void> _register() async {
    _refreshes ??= _plugin.tokenRefreshes.listen(
      (token) => unawaited(
        _run(() async {
          if (state is PushOn) {
            await _send(token);
          }
        }),
      ),
      onError: (Object _) {},
    );
    try {
      if (await _plugin.token() case final token?) {
        await _send(token);
      }
    } on Object {
      // No token yet: the refresh brings it.
    }
  }

  Future<void> _send(String token) async {
    try {
      await _tokens.register(token, _plugin.platform);
    } on Object {
      // Offline or refused: the next start or refresh tries again.
    }
  }

  void _followTaps() {
    if (_opened != null) {
      return;
    }
    _opened = _plugin.openedMessages.listen(_tapped, onError: (Object _) {});
    unawaited(
      _plugin.initialMessage().then((data) {
        if (data != null) {
          _tapped(data);
        }
      }, onError: (Object _) {}),
    );
  }

  void _tapped(Map<String, Object?> data) {
    if (pushTargetOf(data) case final target? when !_taps.isClosed) {
      _taps.add(target);
    }
  }

  Future<T> _run<T>(Future<T> Function() step) {
    final done = _work.then((_) => step());
    _work = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  @override
  Future<void> close() async {
    await _refreshes?.cancel();
    await _opened?.cancel();
    // Not awaited: without a listener it never completes.
    unawaited(_taps.close());
    await super.close();
  }
}
