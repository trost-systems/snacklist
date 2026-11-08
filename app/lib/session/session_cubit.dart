import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// One of the user's households, as `my_households()` answers it.
@immutable
class const Household({
  required final String id,
  required final String name,

  /// Siri, Alexa and AI assistants act in this one (job 169b); every user
  /// with a household has exactly one.
  final bool isDefault = false,
  final int memberCount = 1,

  /// Items not ticked yet.
  final int openCount = 0,
}) {
  /// A row of `my_households()` or of the device cache; null when it has no
  /// id or name.
  static Household? fromJson(Map<String, Object?> json) => switch (json) {
    {'id': final String id, 'name': final String name} => Household(
      id: id,
      name: name,
      isDefault: json['is_default'] == true,
      memberCount: switch (json['member_count']) {
        final int n => n,
        _ => 1,
      },
      openCount: switch (json['open_count']) {
        final int n => n,
        _ => 0,
      },
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'is_default': isDefault,
    'member_count': memberCount,
    'open_count': openCount,
  };
}

/// Where a household was created, for `household_created`'s `context`.
enum HouseholdOrigin() {
  /// Onboarding, before the user had a household (job 22, job 168).
  onboarding,

  /// The switcher's "Neuer Haushalt" (job 169b).
  switcher,
}

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

final class const InHousehold(
  final String userId,

  /// The household this device shows: the one opened last here while the
  /// user is still in it, else [defaultHousehold].
  final Household household,

  /// Every household of the user, oldest membership first; [household] is
  /// one of them.
  final List<Household> households,
) extends Session {
  /// The one Siri, Alexa and AI assistants act in.
  Household get defaultHousehold =>
      households.where((h) => h.isDefault).firstOrNull ?? households.first;
}

/// The household of [households] with id [shown], else the default one.
Household _pick(List<Household> households, String? shown) =>
    households.where((h) => h.id == shown).firstOrNull ??
    households.where((h) => h.isDefault).firstOrNull ??
    households.first;

/// Each user's households and the one shown last, kept on the device so an
/// offline start can open the list.
abstract interface class SessionCache() {
  Future<({List<Household> households, String? shown})?> householdsOf(
    String userId,
  );

  /// Keeps [households] (none: the user has no household) and the one
  /// [shown]. Also drops the user's cached lists of any household not in
  /// [households].
  Future<void> remember(
    String userId, {
    required List<Household> households,
    String? shown,
  });

  /// Drops everything cached for every user.
  Future<void> forget();
}

class SessionCubit(
  final SupabaseClient _client,
  final SessionCache _cache, {

  /// Follows who is signed in and in which household, and hears about
  /// households created, switched to and invites accepted.
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

  /// Counts [refresh]es: only the newest one's answer is shown, so a reload
  /// that started before a change can't undo it.
  var _reloads = 0;

  /// A household a change asked to show (a create, a join, an unarchive)
  /// until a reload shows it: a reload that failed leaves it to the next.
  String? _toShow;

  /// The create that failed or is out, by its arguments: calling again with
  /// the same ones sends the same request id, so the server makes no second
  /// household.
  ({String key, String requestId})? _create;

  /// Households whose `household_created` went out, so a double tap's
  /// second answer (the same household) is not counted again.
  final _created = <String>{};

  /// A join whose answer never came (offline, a timeout): the server may
  /// have done it. The retry then answers `member`, and the event goes out
  /// once, then.
  ({String code, JoinMethod method})? _unansweredJoin;

  Future<void> _load(String? userId) async {
    if (userId == null) {
      _loadedFor = null;
      _toShow = null;
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
    // The device's households open the list at once and the server's answer
    // corrects them, so an offline start never waits for a request to fail.
    if (state is SessionLoading) {
      if (await _cache.householdsOf(userId)
          case (:final households, :final shown) when households.isNotEmpty) {
        // A household asked to show that the device doesn't know yet (an
        // unarchive or join whose reload never answered) waits for the
        // server's list.
        if (shown != null && !households.any((h) => h.id == shown)) {
          _toShow ??= shown;
        }
        if (state is SessionLoading && _client.auth.currentUser?.id == userId) {
          emit(InHousehold(userId, _pick(households, shown), households));
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

  /// Reads the user's households (`my_households()`) and shows [show], or
  /// the one shown now, or the one shown last on this device, while the
  /// user is in it; else the default one.
  Future<void> refresh({String? show}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      emit(const SignedOut());
      return;
    }
    // Counted first: a reload that answers while this one is still keeping
    // [show] on the device is older and must not undo it.
    final reload = ++_reloads;
    if (show != null) {
      _toShow = show;
      // Kept on the device before the server answers: a reload of the page
      // or a restart while the answer is out still shows it (see _load).
      if (state case InHousehold(userId: final user, :final households)
          when user == userId) {
        await _cache.remember(userId, households: households, shown: show);
      }
    }
    final cached = await _cache.householdsOf(userId);
    final rows = await _client.rpc<List<dynamic>>('my_households');
    if (reload != _reloads) {
      return;
    }
    final households = [
      for (final row in rows.whereType<Map<String, dynamic>>())
        ?Household.fromJson(row),
    ];
    // Read after the answer: a switch while it was out wins.
    final shown =
        _toShow ??
        switch (state) {
          InHousehold(userId: final user, :final household)
              when user == userId =>
            household.id,
          _ => cached?.shown,
        };
    final next = households.isEmpty
        ? NeedsHousehold(userId)
        : InHousehold(userId, _pick(households, shown), households);
    _toShow = null;
    await _cache.remember(
      userId,
      households: households,
      shown: switch (next) {
        InHousehold(:final household) => household.id,
        _ => null,
      },
    );
    emit(next);
  }

  /// Shows [householdId], one of the user's households, on this device: the
  /// list switches at once, also offline, and the next start opens it.
  Future<void> switchTo(String householdId) async {
    if (state
        case InHousehold(:final userId, :final household, :final households)
        when household.id != householdId) {
      final next = households.where((h) => h.id == householdId).firstOrNull;
      if (next == null) {
        return;
      }
      _toShow = null;
      emit(InHousehold(userId, next, households));
      analytics?.track('household_switched');
      await _cache.remember(userId, households: households, shown: next.id);
    }
  }

  /// Makes [householdId] the one Siri, Alexa and AI assistants act in.
  /// Throws [HouseholdError].
  Future<void> setDefault(String householdId) async {
    await householdCall(
      () => _client.rpc<void>(
        'set_default_household',
        params: {'p_household': householdId},
      ),
    );
    await householdCall(refresh);
  }

  /// Renames [householdId] for everyone in it. Throws [HouseholdError].
  Future<void> rename(String householdId, String name) async {
    await householdCall(
      () => _client.rest
          .from('households')
          .update({'name': name.trim()})
          .eq('id', householdId),
    );
    await householdCall(refresh);
  }

  /// Leaves [householdId]; the user's other households stay. As its last
  /// member, the household is deleted, or with [archive] archived if it has
  /// Hummlist Lifetime (job 43). Leaving the shown household shows the
  /// default one; leaving the last one, onboarding. Throws
  /// [HouseholdError].
  Future<void> leave(String householdId, {bool archive = false}) async {
    final result = await householdCall(
      () => _client.rpc<Map<String, dynamic>>(
        'leave_household',
        params: {'p_household': householdId, 'p_archive': archive},
      ),
    );
    switch (result) {
      case {'status': 'left'}:
        await _left(householdId);
        try {
          await refresh();
        } on Object {
          // The household is gone here already; the next reload brings
          // what else changed.
        }
      case {'status': final String status}:
        throw HouseholdError.fromStatus(status);
      default:
        throw const HouseholdError(HouseholdProblem.other);
    }
  }

  /// Drops [householdId], which the server says the user left, at once: a
  /// reload that fails or started before must not show it again. Its
  /// default passes to the oldest membership left, as on the server.
  Future<void> _left(String householdId) async {
    if (state case InHousehold(
      :final userId,
      :final household,
      :final households,
    )) {
      _reloads++;
      final rest = [
        for (final h in households)
          if (h.id != householdId) h,
      ];
      final kept = switch (rest) {
        [final first, ...final others] when !rest.any((h) => h.isDefault) => [
          Household(
            id: first.id,
            name: first.name,
            isDefault: true,
            memberCount: first.memberCount,
            openCount: first.openCount,
          ),
          ...others,
        ],
        _ => rest,
      };
      final next = kept.isEmpty
          ? NeedsHousehold(userId)
          : InHousehold(
              userId,
              _pick(kept, household.id == householdId ? null : household.id),
              kept,
            );
      await _cache.remember(
        userId,
        households: kept,
        shown: switch (next) {
          InHousehold(:final household) => household.id,
          _ => null,
        },
      );
      emit(next);
    }
  }

  /// Creates a household named [name] with [stores] in that order (no
  /// store without a pick) and shows it; returns its id. [kind] is who the
  /// user shops with there (`partner`, `family`, `flat`, `club`, `solo`),
  /// null when not asked; [from] where it was created, for analytics.
  ///
  /// Each call is one household: onboarding may call it once per household
  /// it creates, one after the other, and the last one created is shown.
  /// Calling again with the same arguments after a failure (a lost answer,
  /// a double tap while one is out) sends the same request id, so the
  /// server answers with the household it made and creates no second one.
  /// Throws [HouseholdError]: [HouseholdProblem.tooManyHouseholds] over 10
  /// households, [HouseholdProblem.offline] without an answer.
  Future<String> createHousehold(
    String name, {
    List<String> stores = const [],
    String? kind,
    HouseholdOrigin from = HouseholdOrigin.onboarding,
  }) async {
    final key = jsonEncode([name, stores, kind]);
    final requestId = switch (_create) {
      (key: final k, :final requestId) when k == key => requestId,
      _ => const Uuid().v4(),
    };
    _create = (key: key, requestId: requestId);
    final created = await householdCall(
      () => _client.rpc<Object?>(
        'create_household',
        params: {
          'p_name': name,
          'p_default_stores': false,
          'p_stores': stores,
          'p_request_id': requestId,
          'p_kind': kind,
        },
      ),
    );
    if (created case {'id': final String id}) {
      if (_created.add(id)) {
        _trackIn(id, 'household_created', {
          'store_count': stores.length,
          'context': from.name,
        });
      }
      // Kept until the household shows: a retry after a failed reload must
      // not make a second one.
      await householdCall(() => refresh(show: id));
      if (_create?.requestId == requestId) {
        _create = null;
      }
      return id;
    }
    throw const HouseholdError(HouseholdProblem.other);
  }

  /// Joins the household of invite [code] and shows it; the user's other
  /// households stay. [method] says whether the code came from a link or
  /// was typed. `invite_accepted` goes out only for a new membership
  /// (status `joined`), not when the server answers that the user is a
  /// member already, unless that answers an earlier try whose answer was
  /// lost. Throws [HouseholdError] for a bad code, the rate limit or no
  /// connection.
  Future<void> join(String code, {JoinMethod method = JoinMethod.code}) async {
    final normalized = normalizeInviteCode(code);
    final Map<String, dynamic> result;
    try {
      result = await householdCall(
        () => _client.rpc<Map<String, dynamic>>(
          'accept_invite',
          params: {'p_code': normalized, 'p_mode': 'add'},
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
    final String joined;
    switch (result) {
      case {'status': 'joined', 'household_id': final String id}:
        joined = id;
        _trackIn(id, 'invite_accepted', {'method': method.name});
      case {'status': 'member', 'household_id': final String id}:
        joined = id;
        if (unanswered case (:final code, :final method)
            when code == normalized) {
          _trackIn(id, 'invite_accepted', {'method': method.name});
        }
      case {'status': final String status}:
        throw HouseholdError.fromStatus(status);
      default:
        throw const HouseholdError(HouseholdProblem.other);
    }
    pendingInvite?.clear();
    await householdCall(() => refresh(show: joined));
  }

  /// Brings back the archived household [householdId] (job 43) beside the
  /// user's other households, and shows it.
  Future<void> unarchive(String householdId) async {
    final result = await householdCall(
      () => _client.rpc<Map<String, dynamic>>(
        'unarchive_household',
        params: {
          'p_household': householdId,
          'p_archive': false,
          'p_mode': 'add',
        },
      ),
    );
    if (result case {'status': 'unarchived'}) {
      await householdCall(() => refresh(show: householdId));
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
    _toShow = null;
    _create = null;
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
    _toShow = null;
    _create = null;
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
