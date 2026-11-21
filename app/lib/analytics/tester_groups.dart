import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// The signed-in user's tester groups, as the server keeps them
/// (`public.tester_groups`, written only by the service role; job 337).
abstract interface class TesterGroupsSource() {
  Future<Set<String>> mine();
}

class SupabaseTesterGroupsSource(final SupabaseClient _client)
    implements TesterGroupsSource {
  @override
  Future<Set<String>> mine() async =>
      switch (await _client.rpc<Object?>('my_tester_groups')) {
        final List<Object?> groups => {...groups.whereType<String>()},
        _ => const {},
      };
}

/// Hands the signed-in user's tester groups to [Analytics]: the kept ones
/// at once, then the server's, read again at every sign-in and whenever
/// the app comes back from the background (not after a mere focus loss).
/// Offline the kept ones stand; a sign-out deletes them.
class TesterGroupsSync(
  final TesterGroupsSource _source,
  final AnalyticsStore _store,
  final Analytics _analytics,
) {
  String? _user;

  /// Counts the reads started; only the newest one's answer counts.
  var _reads = 0;

  StreamSubscription<Session>? _sessions;
  AppLifecycleListener? _lifecycle;

  /// Follows [session]'s user from now on.
  void follow(SessionCubit session) {
    _signedIn(session.state);
    _sessions = session.stream.listen(_signedIn);
    _lifecycle = AppLifecycleListener(onShow: () => unawaited(refresh()));
  }

  void _signedIn(Session session) {
    final user = switch (session) {
      NeedsHousehold(:final userId) || InHousehold(:final userId) => userId,
      SignedOut() => null,
      SessionLoading() => _user,
    };
    if (user == _user) {
      return;
    }
    _user = user;
    final read = ++_reads;
    if (user == null) {
      _analytics.setTesterGroups(const {});
      unawaited(_store.forgetTesterGroups());
      return;
    }
    unawaited(() async {
      final kept = await _store.testerGroups(user);
      if (read == _reads && kept != null) {
        _analytics.setTesterGroups(kept);
      }
      await refresh();
    }());
  }

  /// Reads the signed-in user's groups again.
  Future<void> refresh() async {
    final user = _user;
    if (user == null) {
      return;
    }
    final read = ++_reads;
    final Set<String> groups;
    try {
      groups = await _source.mine();
    } on Object catch (e) {
      debugPrint('analytics: tester groups not read: ${e.runtimeType}');
      return;
    }
    if (read != _reads || _user != user) {
      return;
    }
    _analytics.setTesterGroups(groups);
    await _store.saveTesterGroups(user, groups);
  }

  Future<void> close() async {
    _lifecycle?.dispose();
    await _sessions?.cancel();
  }
}
