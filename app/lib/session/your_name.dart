import 'dart:async';

import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The longest display name, in characters (code points, as Postgres'
/// char_length counts them).
const maxDisplayName = 80;

final _blankRuns = RegExp(r'[\s\p{Cc}]+', unicode: true);

/// [raw] as `set_display_name` stores it: runs of spaces and control
/// characters become one space, then trimmed.
String normalizeDisplayName(String raw) =>
    raw.replaceAll(_blankRuns, ' ').trim();

/// Whether the server takes [raw] as a display name: 1 to 80 characters
/// once normalized, emoji and all, and not only invisible ones.
bool validDisplayName(String raw) {
  final name = normalizeDisplayName(raw);
  final length = name.runes.length;
  return length >= 1 &&
      length <= maxDisplayName &&
      name.replaceAll(_invisible, '').isNotEmpty;
}

/// Format characters (zero-width spaces and joiners, soft hyphens): a name
/// of only these shows as blank.
final _invisible = RegExp(r'\p{Cf}', unicode: true);

/// The signed-in user's own display name (job 297).
sealed class const YourName();

/// Nobody is signed in, the name is not read yet, or the read [failed].
final class const NameUnread({final bool failed = false}) extends YourName;

final class const NameRead(
  final String userId,
  final String name, {

  /// The user saved or confirmed it; no Google or Apple name replaces it.
  required final bool chosen,

  /// Not chosen, and empty or the e-mail address' local part: an e-mail
  /// sign-up, or Apple with the name not shared.
  required final bool fromEmail,

  /// „Jetzt nicht“ was tapped for this user on this device.
  required final bool postponed,
}) extends YourName;

/// Whether the router sends [session] to the name step; the caller checks
/// the flag `display-name`. Someone without a household (a new user, about
/// to create or join one) must have chosen a name, and waits while it is
/// read. Someone in a household is asked once, only for a name from their
/// e-mail address, and may postpone it.
bool asksName(Session session, YourName name) => switch (session) {
  NeedsHousehold(:final userId) =>
    !(name is NameRead && name.userId == userId && name.chosen),
  InHousehold(:final userId) =>
    name is NameRead &&
        name.userId == userId &&
        !name.chosen &&
        name.fromEmail &&
        !name.postponed,
  _ => false,
};

/// The name as `my_display_name()` answers it.
typedef NameRow = ({String name, bool chosen, bool fromEmail});

/// Saving the name failed; nothing changed.
sealed class const NameError() implements Exception;

final class const NameOffline() extends NameError;

/// The server refused the name: not 1 to 80 characters.
final class const NameInvalid() extends NameError;

/// The server refused or failed; [code] is its error code.
final class const NameFailed(final String code) extends NameError;

/// The name's only door to the backend.
abstract interface class NameRepository() {
  /// The signed-in user's name, or null when they have no profile.
  Future<NameRow?> read();

  /// Saves [name] as chosen and returns it as stored. Throws [NameError].
  Future<String> save(String name);
}

class SupabaseNameRepository(final SupabaseClient _client)
    implements NameRepository {
  @override
  Future<NameRow?> read() async {
    final rows = await _client.rpc<List<dynamic>>('my_display_name');
    return switch (rows.firstOrNull) {
      {'chosen': final bool chosen, 'from_email': final bool fromEmail} &&
          final Map<String, dynamic> row =>
        (
          name: switch (row['display_name']) {
            final String name => name,
            _ => '',
          },
          chosen: chosen,
          fromEmail: fromEmail,
        ),
      _ => null,
    };
  }

  @override
  Future<String> save(String name) async {
    try {
      return await _client.rpc<String>(
        'set_display_name',
        params: {'p_name': name},
      );
    } on PostgrestException catch (e) {
      throw e.code == '22023'
          ? const NameInvalid()
          : NameFailed(e.code ?? e.message);
    } on ClientException {
      throw const NameOffline();
    } on TimeoutException {
      throw const NameOffline();
    }
  }
}

/// Which users postponed the name step on this device.
abstract interface class NamePostponements() {
  Future<bool> postponedNameFor(String userId);

  Future<void> savePostponedName(String userId);
}

/// The signed-in user's [YourName]: read on each new sign-in and again when
/// the account changes (Apple stores the name right after the sign-in, so
/// the first read may still have the e-mail's), and after a failed read on
/// the next auth event.
class YourNameCubit(
  final NameRepository _repository,
  final NamePostponements _postponements,
  Stream<AuthState> auth,
) extends Cubit<YourName> {
  this : super(const NameUnread()) {
    _auth = auth.listen(
      (state) => _follow(state.event, state.session?.user.id),
      // The session cubit tells the user about auth errors; the name stays.
      onError: (Object _) {},
    );
  }

  late final StreamSubscription<AuthState> _auth;

  /// The user whose name is shown or being read.
  String? _userId;

  /// Counts reads and saves: only the newest one's answer is shown.
  var _reads = 0;

  void _follow(AuthChangeEvent event, String? userId) {
    if (userId == null) {
      _userId = null;
      _reads++;
      emit(const NameUnread());
    } else if (userId != _userId ||
        event == AuthChangeEvent.userUpdated ||
        state is NameUnread) {
      _userId = userId;
      unawaited(_read(userId));
    }
  }

  /// Reads the name again after a failed read.
  Future<void> retry() async {
    if (_userId case final userId?) {
      await _read(userId);
    }
  }

  Future<void> _read(String userId) async {
    final read = ++_reads;
    if (state case NameRead(userId: final shown) when shown == userId) {
      // The name stays while it is read again.
    } else {
      emit(const NameUnread());
    }
    YourName next;
    try {
      final (row, postponed) = await (
        _repository.read(),
        _postponements.postponedNameFor(userId),
      ).wait;
      next = row == null
          ? const NameUnread(failed: true)
          : NameRead(
              userId,
              row.name,
              chosen: row.chosen,
              fromEmail: row.fromEmail,
              postponed: postponed,
            );
    } on Object {
      next = const NameUnread(failed: true);
    }
    if (read == _reads && !isClosed) {
      emit(next);
    }
  }

  /// Saves [name] as the user's chosen name. Throws [NameError].
  Future<void> save(String name) async {
    final userId = _userId;
    if (userId == null) {
      throw const NameFailed('signed_out');
    }
    final stored = await _repository.save(normalizeDisplayName(name));
    if (userId != _userId || isClosed) {
      return;
    }
    // A read that started before the save must not undo it.
    _reads++;
    emit(
      NameRead(
        userId,
        stored,
        chosen: true,
        fromEmail: false,
        postponed: switch (state) {
          NameRead(:final postponed) => postponed,
          NameUnread() => false,
        },
      ),
    );
  }

  /// „Jetzt nicht“: this device asks this user no more.
  Future<void> postpone() async {
    if (state case final NameRead read) {
      emit(
        NameRead(
          read.userId,
          read.name,
          chosen: read.chosen,
          fromEmail: read.fromEmail,
          postponed: true,
        ),
      );
      await _postponements.savePostponedName(read.userId);
    }
  }

  @override
  Future<void> close() {
    unawaited(_auth.cancel());
    return super.close();
  }
}
