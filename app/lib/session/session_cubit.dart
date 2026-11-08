import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class const Household({
  required final String id,
  required final String name,

  /// Who it shops with (job 168b); null when never answered.
  final HouseholdKind? kind,
});

sealed class const Session();

final class const SessionLoading() extends Session;

final class const SignedOut({
  /// Why the last sign-in failed, e.g. an error on a provider's return URL.
  final Exception? error,

  /// Set when the user just deleted their account, for the start screen's
  /// confirmation.
  final AccountDeletedNotice? deleted,
}) extends Session;

/// The confirmation after an account deletion.
@immutable
class const AccountDeletedNotice({
  /// Apple's grant was not revoked, so the user removes the app from their
  /// Apple account themselves.
  required final bool removeAppleManually,
});

final class const NeedsHousehold(final String userId) extends Session;

final class const InHousehold(final String userId, final Household household)
    extends Session;

/// The household each user was last in, kept on the device so an offline
/// start can open the list.
abstract interface class SessionCache() {
  Future<Household?> household(String userId);

  /// Also drops the user's cached lists of any other household.
  Future<void> remember(String userId, Household? household);

  /// Drops everything cached for every user.
  Future<void> forget();
}

class SessionCubit(
  final SupabaseClient _client,
  final SessionCache _cache, {

  /// Follows who is signed in and in which household, and hears about
  /// households created and invites accepted.
  final Analytics? analytics,

  /// The invite link waiting for an answer; dropped after a join and on
  /// sign-out.
  final PendingInvite? pendingInvite,

  /// Runs while the session still exists, before [signOut] ends it.
  final Future<void> Function()? _beforeSignOut,
}) extends Cubit<Session> {
  this : super(const SessionLoading()) {
    // Job 31: the server learns each install's analytics answer, so an add
    // over Alexa is counted only after a yes (docs/ANALYTICS.md).
    analytics?.recordConsent =
        ({
          required installId,
          required consent,
          required internal,
          required answered,
          required textVersion,
        }) => _client.rpc<void>(
          'record_analytics_consent',
          params: {
            'p_install': installId,
            'p_consent': consent,
            'p_internal': internal,
            'p_answered': answered,
            'p_text_version': textVersion,
          },
        );
    // Also replays a failed browser sign-in that supabase_flutter read from
    // the return URL before this cubit existed.
    _auth = _client.auth.onAuthStateChange.listen(
      (event) => unawaited(_load(event.session?.user.id)),
      onError: (Object e) => switch (e) {
        // An offline token refresh: the session stays and is retried.
        AuthRetryableFetchException() => unawaited(
          _load(_client.auth.currentUser?.id),
        ),
        _ => emit(SignedOut(error: e is Exception ? e : null)),
      },
    );
  }

  late final StreamSubscription<AuthState> _auth;

  /// The user whose household the server last confirmed.
  String? _loadedFor;
  Timer? _retry;

  /// A create or join whose answer never came (offline, a timeout): the
  /// server may have done it. The retry then answers
  /// `already_in_household` or `member`, and the event goes out once, then.
  ({int storeCount})? _unansweredCreate;
  ({String code, JoinMethod method})? _unansweredJoin;

  Future<void> _load(String? userId) async {
    if (userId == null) {
      _loadedFor = null;
      _retry?.cancel();
      // The sign-out that [accountDeleted] causes keeps its notice.
      emit(
        SignedOut(
          deleted: switch (state) {
            SignedOut(:final deleted) => deleted,
            _ => null,
          },
        ),
      );
      await _cache.forget();
      return;
    }
    if (_loadedFor == userId) {
      return;
    }
    // The device's household opens the list at once and the server's answer
    // corrects it, so an offline start never waits for a request to fail.
    if (state is SessionLoading) {
      if (await _cache.household(userId) case final household?) {
        if (state is SessionLoading && _client.auth.currentUser?.id == userId) {
          emit(InHousehold(userId, household));
        }
      }
    }
    try {
      await refresh();
      _loadedFor = userId;
    } on Object {
      // Offline: ask until the server answers.
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 3), () {
        if (!isClosed && _client.auth.currentUser?.id == userId) {
          unawaited(_load(userId));
        }
      });
    }
  }

  Future<void> refresh() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      emit(const SignedOut());
      return;
    }
    final row = await _client.rest
        .from('household_members')
        .select('households(id, name, kind)')
        .eq('user_id', userId)
        .maybeSingle();
    final next = switch (row?['households']) {
      final Map<String, Object?> h &&
          {'id': final String id, 'name': final String name} =>
        InHousehold(
          userId,
          Household(id: id, name: name, kind: HouseholdKind.parse(h['kind'])),
        ),
      _ => NeedsHousehold(userId),
    };
    await _cache.remember(userId, switch (next) {
      InHousehold(:final household) => household,
      _ => null,
    });
    emit(next);
  }

  /// Creates the user's household with [stores], the ones picked in
  /// onboarding, in that order; no store without a pick. Creating again (a
  /// double tap, a retry after a lost answer) makes no second household: the
  /// server answers `already_in_household`, which loads the one there is.
  Future<void> createHousehold(
    String name, {
    List<String> stores = const [],
  }) async {
    final Object? created;
    try {
      created = await householdCall(
        () => _client.rpc<Object?>(
          'create_household',
          params: {
            'p_name': name,
            'p_default_stores': false,
            'p_stores': stores,
          },
        ),
      );
    } on HouseholdError catch (e) {
      if (e.problem == HouseholdProblem.offline) {
        _unansweredCreate ??= (storeCount: stores.length);
        rethrow;
      }
      // The household is there already; show it.
      if (e.problem != HouseholdProblem.alreadyInHousehold) {
        rethrow;
      }
      await householdCall(refresh);
      if (state case InHousehold(:final household)) {
        if (_unansweredCreate case (:final storeCount)) {
          _trackIn(household.id, 'household_created', {
            'store_count': storeCount,
          });
        }
        _unansweredCreate = null;
        return;
      }
      rethrow;
    }
    _unansweredCreate = null;
    if (created case {'id': final String id}) {
      _trackIn(id, 'household_created', {'store_count': stores.length});
    }
    await householdCall(refresh);
  }

  /// Joins the household of invite [code]. [method] says whether the code
  /// came from a link or was typed. `invite_accepted` goes out only for a
  /// new membership (status `joined`), not when the server answers that the
  /// user is a member already, unless that answers an earlier try whose
  /// answer was lost. Throws [HouseholdError] for a bad code, the rate
  /// limit or no connection. With [archive], the household the user leaves
  /// as its last member is archived instead of deleted if it has Hummlist
  /// Lifetime (job 43).
  Future<void> join(
    String code, {
    JoinMethod method = JoinMethod.code,
    bool archive = false,
  }) async {
    final normalized = normalizeInviteCode(code);
    final Map<String, dynamic> result;
    try {
      result = await householdCall(
        () => _client.rpc<Map<String, dynamic>>(
          'accept_invite',
          params: {'p_code': normalized, 'p_archive': archive},
        ),
      );
    } on HouseholdError catch (e) {
      if (e.problem == HouseholdProblem.offline) {
        _unansweredJoin = (code: normalized, method: method);
      }
      rethrow;
    }
    final unanswered = _unansweredJoin;
    _unansweredJoin = null;
    switch (result) {
      case {'status': 'joined', 'household_id': final String id}:
        _trackIn(id, 'invite_accepted', {'method': method.name});
      case {'status': 'member', 'household_id': final String id}:
        if (unanswered?.code == normalized) {
          _trackIn(id, 'invite_accepted', {'method': unanswered!.method.name});
        }
      case {'status': final String status}:
        throw HouseholdError.fromStatus(status);
      default:
        throw const HouseholdError(HouseholdProblem.other);
    }
    pendingInvite?.clear();
    await householdCall(refresh);
  }

  /// Moves the user back into their archived household [householdId] (job
  /// 43). The household they are in now is left like on a join, archived if
  /// they are its last member and it has Hummlist Lifetime.
  Future<void> unarchive(String householdId) async {
    final result = await householdCall(
      () => _client.rpc<Map<String, dynamic>>(
        'unarchive_household',
        params: {'p_household': householdId, 'p_archive': true},
      ),
    );
    if (result case {'status': 'unarchived'}) {
      await householdCall(refresh);
      return;
    }
    throw const HouseholdError(HouseholdProblem.other);
  }

  /// Tracks [event] in [householdId], which the server just confirmed:
  /// before the reload, so it counts even when the reload fails.
  void _trackIn(
    String householdId,
    String event, [
    Map<String, Object> properties = const {},
  ]) {
    analytics
      ?..setUser(
        AnalyticsUser(
          email: _client.auth.currentUser?.email,
          householdId: householdId,
        ),
      )
      ..track(event, properties);
  }

  /// Sends what analytics still holds for this user first (briefly):
  /// nothing is sent once signed out.
  Future<void> signOut() async {
    pendingInvite?.signedOut();
    _unansweredCreate = null;
    _unansweredJoin = null;
    await analytics?.flush().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await _beforeSignOut?.call();
    await _client.auth.signOut();
  }

  /// The server already deleted the account and its sessions: signs out on
  /// this device only and drops everything cached.
  Future<void> accountDeleted(AccountDeletedNotice notice) async {
    _loadedFor = null;
    _retry?.cancel();
    pendingInvite?.signedOut();
    _unansweredCreate = null;
    _unansweredJoin = null;
    emit(SignedOut(deleted: notice));
    await _cache.forget();
    try {
      // GoTrue's default scope is this device only.
      await _client.auth.signOut();
    } on Object {
      // Local sign-out only clears storage; the account is gone regardless.
    }
  }

  /// Analytics learns of each change at once, so an event right after a
  /// change (a new household) carries the new household.
  @override
  void onChange(Change<Session> change) {
    super.onChange(change);
    analytics?.setUser(switch (change.nextState) {
      NeedsHousehold() => AnalyticsUser(email: _client.auth.currentUser?.email),
      InHousehold(:final household) => AnalyticsUser(
        email: _client.auth.currentUser?.email,
        householdId: household.id,
      ),
      SignedOut() || SessionLoading() => null,
    });
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    await _auth.cancel();
    await super.close();
  }
}
