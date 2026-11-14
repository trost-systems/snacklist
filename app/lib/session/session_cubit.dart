import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// What a member may do in a household (docs/households/W2.md): the
/// [owner] created it and names [admin]s; both remove members and make
/// group links.
enum HouseholdRole() {
  owner,
  admin,
  member;

  /// The server's `role`; anything unknown counts as [member].
  static HouseholdRole parse(Object? role) =>
      values.where((r) => r.name == role).firstOrNull ?? member;

  /// Removes members, makes and revokes group links.
  bool get manages => this != member;
}

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

  /// Who it shops with (job 168b); null when never answered. Invites say
  /// it in their text.
  final HouseholdKind? kind,

  /// The user's own role in it.
  final HouseholdRole role = HouseholdRole.member,

  /// It has Snacklist Premium, which covers every member.
  final bool premium = false,

  /// An invite makes a join request an owner or admin decides on instead
  /// of a membership (job 169b W3 M).
  final bool joinApproval = false,
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
      kind: HouseholdKind.parse(json['kind']),
      role: HouseholdRole.parse(json['role']),
      premium: json['premium'] == true,
      joinApproval: json['join_approval'] == true,
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'is_default': isDefault,
    'member_count': memberCount,
    'open_count': openCount,
    'kind': kind?.name,
    'role': role.name,
    'premium': premium,
    'join_approval': joinApproval,
  };

  Household copyWith({String? name, bool? isDefault}) => Household(
    id: id,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    memberCount: memberCount,
    openCount: openCount,
    kind: kind,
    role: role,
    premium: premium,
    joinApproval: joinApproval,
  );
}

/// The user's own join request, waiting for an owner or admin of the
/// household (job 169b W3 M), as `my_join_requests()` answers it.
@immutable
class const JoinRequest({
  required final String id,
  required final String householdId,
  required final String householdName,
}) {
  /// A pending row, or null: no id or household, or decided already.
  static JoinRequest? fromJson(Map<String, Object?> json) => switch (json) {
    {'id': final String id, 'household_id': final String householdId}
        when json['decision'] == null && json['decided_at'] == null =>
      JoinRequest(
        id: id,
        householdId: householdId,
        householdName: switch (json['household_name'] ?? json['name']) {
          final String name => name,
          _ => '',
        },
      ),
    _ => null,
  };
}

/// An owner or admin decided on one of the user's [JoinRequest]s. Approved,
/// the session shows the household already.
typedef JoinDecision = ({String household, bool approved});

/// A household `userId` is no longer in. `removal`: an owner or admin
/// removed them in the last 30 days, while old invites can't bring them
/// back (Legal N-114), by `_Removal.key`, which [SessionCubit.removalsTold]
/// takes once the user saw it; null: it went another way, such as leaving
/// on another device.
typedef LostHousehold = ({String userId, String name, String? removal});

/// One of the user's removals as `my_household_removals()` answers it;
/// `key` tells this removal from an earlier one of the same household.
typedef _Removal = ({String householdId, String name, String key});

/// What `accept_invite` did with a join.
sealed class const JoinAnswer();

/// A member now (or already was); the session shows the household.
final class const Joined(final String householdId) extends JoinAnswer;

/// The household confirms joins: an owner or admin decides, the session
/// lists it in its requests meanwhile.
final class const JoinRequested(final String householdId) extends JoinAnswer;

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

final class const NeedsHousehold(
  final String userId, {

  /// Joins waiting for an owner or admin: the user waits instead of
  /// creating a household, or creates one anyway.
  final List<JoinRequest> requests = const [],
}) extends Session;

final class const InHousehold(
  final String userId,

  /// The household this device shows: the one opened last here while the
  /// user is still in it, else [defaultHousehold].
  final Household household,

  /// Every household of the user, in their own order (job 229), else oldest
  /// membership first; [household] is one of them.
  final List<Household> households, {

  /// Joins waiting for an owner or admin, in households not among
  /// [households].
  final List<JoinRequest> requests = const [],
}) extends Session {
  /// The one Siri, Alexa and AI assistants act in.
  Household get defaultHousehold =>
      households.where((h) => h.isDefault).firstOrNull ?? households.first;
}

/// The household of [households] with id [shown], else the default one.
Household _pick(List<Household> households, String? shown) =>
    households.where((h) => h.id == shown).firstOrNull ??
    households.where((h) => h.isDefault).firstOrNull ??
    households.first;

/// Calls `onChange` when one of [userId]'s join requests changes (an owner
/// or admin decided), as far as realtime tells; returns the call that stops
/// it.
typedef WatchJoinRequests = Future<void> Function() Function(
  String userId,
  void Function() onChange,
);

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

  /// The removals of [userId] this device told them about, by
  /// `_Removal.key`. Kept across sign-outs: each is told once per device.
  Future<Set<String>> toldRemovals(String userId);

  /// Keeps [keys] as [userId]'s told removals, in place of the ones before.
  Future<void> rememberToldRemovals(String userId, Set<String> keys);
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

  /// Realtime on the user's join requests; the client's channel when null.
  final WatchJoinRequests? _watchJoinRequests,
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

  /// The last household order sent: the next waits for it, so the server
  /// ends with the order shown.
  Future<void> _reorderSent = Future.value();
  var _reorders = 0;

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

  /// Households this device is leaving: gone after the next refresh, but
  /// not lost.
  final _leaving = <String>{};
  final _lost = StreamController<LostHousehold>.broadcast();

  /// Removals told on this device since the start, so two refreshes at once
  /// tell one once.
  final _toldRemovals = <String>{};

  /// The last write of the told removals, see [_editTold].
  Future<void> _toldWrites = Future.value();

  /// Each household the user is no longer in that a refresh finds (job
  /// 169b W2): gone since the last one without this device leaving it, or
  /// a removal of the last 30 days not told on this device yet, also right
  /// after signing in. The session already shows another one. A removal
  /// counts as told once [removalsTold] says so.
  Stream<LostHousehold> get lostHouseholds => _lost.stream;

  /// Join requests this device withdrew: gone after the next refresh, but
  /// not declined.
  final _withdrawing = <String>{};
  final _decisions = StreamController<JoinDecision>.broadcast();
  final _decided = <String>{};

  /// Each of the user's join requests an owner or admin decided on, as a
  /// refresh finds it gone (job 169b W3 M): approved, the session shows the
  /// household already. A request decided while the app was closed finds
  /// the household in the list without a word.
  Stream<JoinDecision> get joinDecisions => _decisions.stream;

  /// The user whose join requests realtime watches, and how to stop it.
  ({String userId, Future<void> Function() stop})? _requestWatch;

  /// A join whose answer never came (offline, a timeout): the server may
  /// have done it. The retry then answers `member`, and the event goes out
  /// once, then.
  ({String code, JoinMethod method})? _unansweredJoin;

  Future<void> _load(String? userId) async {
    if (userId == null) {
      // A reload still out for the old user must not show their household.
      _reloads++;
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
    } on Object {
      // Offline: asked again below.
    }
    // Asks until the server's answer shows: this read failed, or a newer
    // one passed it (its answer was dropped) and failed itself. Not after a
    // sign-out meanwhile.
    if (_loadedFor != userId &&
        !isClosed &&
        _client.auth.currentUser?.id == userId) {
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
    final told = await _cache.toldRemovals(userId);
    final householdRows = _client.rpc<List<dynamic>>('my_households');
    final ownRequests = _ownRequests();
    final ownRemovals = _ownRemovals();
    final rows = await householdRows;
    final own = await ownRequests;
    final removals = await ownRemovals;
    if (reload != _reloads) {
      return;
    }
    final households = [
      for (final row in rows.whereType<Map<String, dynamic>>())
        ?Household.fromJson(row),
    ];
    final waiting = switch (state) {
      NeedsHousehold(userId: final user, :final requests) ||
      InHousehold(
        userId: final user,
        :final requests,
      ) when user == userId => requests,
      _ => const <JoinRequest>[],
    };
    // Unknown (an older server, offline): the ones known stay.
    final requests = [
      for (final r in own ?? waiting)
        if (!households.any((h) => h.id == r.householdId)) r,
    ];
    final decided = [
      for (final r in waiting)
        if (!requests.any((now) => now.id == r.id) &&
            !_withdrawing.remove(r.id) &&
            // Two refreshes at once both find it gone.
            _decided.add(r.id))
          (
            household:
                households
                    .where((h) => h.id == r.householdId)
                    .firstOrNull
                    ?.name ??
                r.householdName,
            approved: households.any((h) => h.id == r.householdId),
            id: r.householdId,
          ),
    ];
    // Read after the answer: a switch while it was out wins.
    final shown =
        _toShow ??
        // Approved just now: the user waited for it, so it shows.
        decided.where((d) => d.approved).lastOrNull?.id ??
        switch (state) {
          InHousehold(userId: final user, :final household)
              when user == userId =>
            household.id,
          _ => cached?.shown,
        };
    final next = households.isEmpty
        ? NeedsHousehold(userId, requests: requests)
        : InHousehold(
            userId,
            _pick(households, shown),
            households,
            requests: requests,
          );
    _toShow = null;
    final gone = switch (state) {
      InHousehold(userId: final user, households: final before)
          when user == userId =>
        [
          for (final h in before)
            if (!households.any((now) => now.id == h.id) &&
                !_leaving.remove(h.id))
              h,
        ],
      _ => const <Household>[],
    };
    // Unknown removals (an older server, offline): every one gone is told
    // without the 30 days.
    final lost = <LostHousehold>[
      for (final h in gone)
        if (!(removals?.any((r) => r.householdId == h.id) ?? false))
          (userId: userId, name: h.name, removal: null),
      for (final r in removals ?? const <_Removal>[])
        if (!told.contains(r.key) && _toldRemovals.add(r.key))
          (userId: userId, name: r.name, removal: r.key),
    ];
    // Shown before the write: a switch during it must not be undone.
    emit(next);
    _loadedFor = userId;
    lost.forEach(_lost.add);
    if (removals != null) {
      final current = {for (final r in removals) r.key};
      // The server forgets a removal after 30 days, and so does the device.
      await _editTold(userId, (told) => told.intersection(current));
    }
    await _cache.remember(
      userId,
      households: households,
      shown: switch (next) {
        InHousehold(:final household) => household.id,
        _ => null,
      },
    );
    for (final d in decided) {
      _decisions.add((household: d.household, approved: d.approved));
    }
  }

  /// [userId] saw the notices of the removals [keys] (told by
  /// [lostHouseholds]): this device does not tell them again, also after a
  /// restart. Not before: a notice held behind the analytics consent and
  /// lost to an app kill shows on the next start.
  Future<void> removalsTold(String userId, Iterable<String> keys) =>
      _editTold(userId, (told) => {...told, ...keys});

  /// One edit of the told removals after the other: a prune by [refresh]
  /// and [removalsTold] both read and write the whole set.
  Future<void> _editTold(
    String userId,
    Set<String> Function(Set<String> told) edit,
  ) => _toldWrites = _toldWrites.then((_) async {
    final told = await _cache.toldRemovals(userId);
    final next = edit(told);
    if (!setEquals(next, told)) {
      await _cache.rememberToldRemovals(userId, next);
    }
  });

  /// The user's pending join requests, or null when the server did not
  /// say.
  Future<List<JoinRequest>?> _ownRequests() async {
    try {
      final rows = await _client.rpc<List<dynamic>>('my_join_requests');
      return [
        for (final row in rows.whereType<Map<String, dynamic>>())
          ?JoinRequest.fromJson(row),
      ];
    } on Object {
      return null;
    }
  }

  /// The user's removals of the last 30 days, or null when the server did
  /// not say.
  Future<List<_Removal>?> _ownRemovals() async {
    try {
      final rows = await _client.rpc<List<dynamic>>('my_household_removals');
      return [
        for (final row in rows.whereType<Map<String, dynamic>>())
          if (row case {
            'household_id': final String id,
            'household_name': final String name,
            'removed_at': final String at,
          })
            (
              householdId: id,
              name: name,
              key: '$id ${DateTime.parse(at).toUtc().toIso8601String()}',
            ),
      ];
    } on Object {
      return null;
    }
  }

  /// Shows [householdId], one of the user's households, on this device: the
  /// list switches at once, also offline, and the next start opens it.
  Future<void> switchTo(String householdId) async {
    if (state
        case InHousehold(
          :final userId,
          :final household,
          :final households,
          :final requests,
        )
        when household.id != householdId) {
      final next = households.where((h) => h.id == householdId).firstOrNull;
      if (next == null) {
        return;
      }
      _toShow = null;
      emit(InHousehold(userId, next, households, requests: requests));
      analytics?.track('household_switched');
      await _cache.remember(userId, households: households, shown: next.id);
    }
  }

  /// Puts the user's households in the order of [ids] (job 229): here at
  /// once, and on the server for the user's other devices. Households [ids]
  /// leaves out stay after the named ones. A refusal puts the order back
  /// and throws [HouseholdError].
  Future<void> reorderHouseholds(List<String> ids) async {
    if (state case InHousehold(
      :final userId,
      :final household,
      :final households,
      :final requests,
    )) {
      final ordered = _inOrder(households, ids);
      if (listEquals(_ids(ordered), _ids(households))) {
        return;
      }
      // A reload out now answers the old order.
      _reloads++;
      final reorder = ++_reorders;
      emit(InHousehold(userId, household, ordered, requests: requests));
      await _cache.remember(userId, households: ordered, shown: household.id);
      final sent = _reorderSent.then(
        (_) => householdCall(
          () => _client.rpc<void>(
            'reorder_households',
            params: {'p_households': _ids(ordered)},
          ),
        ),
      );
      _reorderSent = sent.then((_) {}, onError: (Object _) {});
      try {
        await sent;
        // The reload the order discarded: counts and names stay fresh.
        if (reorder == _reorders) {
          unawaited(refresh().catchError((Object _) {}));
        }
      } on HouseholdError {
        if (state
            case InHousehold(
              userId: final user,
              household: final shown,
              households: final now,
              requests: final waiting,
            )
            when user == userId) {
          final back = _inOrder(now, _ids(households));
          emit(InHousehold(userId, shown, back, requests: waiting));
          await _cache.remember(userId, households: back, shown: shown.id);
        }
        rethrow;
      }
    }
  }

  static List<String> _ids(List<Household> households) => [
    for (final h in households) h.id,
  ];

  /// [households] in the order of [ids], the ones not named after them.
  static List<Household> _inOrder(
    List<Household> households,
    List<String> ids,
  ) => [
    for (final id in ids) ?households.where((h) => h.id == id).firstOrNull,
    for (final h in households)
      if (!ids.contains(h.id)) h,
  ];

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

  /// The list Siri, Alexa and AI assistants add to in [householdId] when
  /// no list is named (job 207): the user's pick, else its first list.
  /// Null when the user is not in it. Throws [HouseholdError].
  Future<String?> defaultList(String householdId) => householdCall(
    () => _client.rpc<String?>(
      'default_list',
      params: {'p_household': householdId},
    ),
  );

  /// [householdId]'s lists in their order. Throws [HouseholdError].
  Future<List<HouseholdList>> lists(String householdId) => householdCall(
    () async => [
      for (final row
          in await _client.rest
              .from('lists')
              .select('id, name, position, seed_key')
              .eq('household_id', householdId)
              .order('position', ascending: true)
              .order('created_at', ascending: true)
              .order('id', ascending: true))
        HouseholdList.fromJson(row),
    ],
  );

  /// Makes [listId] the user's [defaultList] in its household; showing
  /// another list does not. Throws [HouseholdError].
  Future<void> setDefaultList(String listId) => householdCall(
    () => _client.rpc<void>('set_default_list', params: {'p_list': listId}),
  );

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
  /// Snacklist Lifetime (job 43). Leaving the shown household shows the
  /// default one; leaving the last one, onboarding. Throws
  /// [HouseholdError].
  Future<void> leave(String householdId, {bool archive = false}) async {
    _leaving.add(householdId);
    final Map<String, dynamic> result;
    try {
      result = await householdCall(
        () => _client.rpc<Map<String, dynamic>>(
          'leave_household',
          params: {'p_household': householdId, 'p_archive': archive},
        ),
      );
    } on HouseholdError catch (e) {
      // Offline, the server may have done it: then it is gone by our hand.
      if (e.problem != HouseholdProblem.offline) {
        _leaving.remove(householdId);
      }
      rethrow;
    }
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
      :final requests,
    )) {
      _reloads++;
      final rest = [
        for (final h in households)
          if (h.id != householdId) h,
      ];
      final kept = switch (rest) {
        [final first, ...final others] when !rest.any((h) => h.isDefault) => [
          // Keeps its role, kind and Premium: a failed reload after this must
          // not hide an admin's controls.
          first.copyWith(isDefault: true),
          ...others,
        ],
        _ => rest,
      };
      final next = kept.isEmpty
          ? NeedsHousehold(userId, requests: requests)
          : InHousehold(
              userId,
              _pick(kept, household.id == householdId ? null : household.id),
              kept,
              requests: requests,
            );
      emit(next);
      await _cache.remember(
        userId,
        households: kept,
        shown: switch (next) {
          InHousehold(:final household) => household.id,
          _ => null,
        },
      );
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
  /// A caller that must survive an app kill passes its own kept
  /// [requestId] (the guided start's draft, job 168c).
  /// Throws [HouseholdError]: [HouseholdProblem.tooManyHouseholds] at 20
  /// households, [HouseholdProblem.offline] without an answer.
  Future<String> createHousehold(
    String name, {
    List<String> stores = const [],
    String? kind,
    HouseholdOrigin from = HouseholdOrigin.onboarding,
    String? requestId,
  }) async {
    final key = jsonEncode([name, stores, kind]);
    requestId ??= switch (_create) {
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
  /// households stay. A household that confirms joins answers
  /// [JoinRequested] instead: nothing switches, the session lists the
  /// request until an owner or admin decides ([joinDecisions]). [method]
  /// says whether the code came from a link or was typed.
  /// `invite_accepted` goes out only for a new membership (status
  /// `joined`), not when the server answers that the user is a member
  /// already, unless that answers an earlier try whose answer was lost.
  /// Throws [HouseholdError] for a bad code, the rate limit or no
  /// connection.
  Future<JoinAnswer> join(
    String code, {
    JoinMethod method = JoinMethod.code,
  }) async {
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
      case {'status': 'requested', 'household_id': final String id}:
        // Not the household's member: the event keeps the user's own.
        analytics?.track('join_requested');
        pendingInvite?.clear();
        await householdCall(refresh);
        return JoinRequested(id);
      case {'status': final String status}:
        throw HouseholdError.fromStatus(status);
      default:
        throw const HouseholdError(HouseholdProblem.other);
    }
    pendingInvite?.clear();
    await householdCall(() => refresh(show: joined));
    return Joined(joined);
  }

  /// Withdraws the user's join request for [householdId]. Throws
  /// [HouseholdError].
  Future<void> withdrawJoinRequest(String householdId) async {
    JoinRequest? find() => switch (state) {
      NeedsHousehold(:final requests) || InHousehold(:final requests) =>
        requests.where((r) => r.householdId == householdId).firstOrNull,
      _ => null,
    };
    // The answer to the join came before the server listed the request.
    if (find() == null) {
      await householdCall(refresh);
    }
    final request = find();
    if (request == null) {
      return;
    }
    _withdrawing.add(request.id);
    try {
      await householdCall(
        () => _client.rpc<void>(
          'cancel_join_request',
          params: {'p_request': request.id},
        ),
      );
    } on HouseholdError catch (e) {
      // Offline, the server may have done it: then it is gone by our hand.
      if (e.problem != HouseholdProblem.offline) {
        _withdrawing.remove(request.id);
      }
      rethrow;
    }
    await householdCall(refresh);
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
    _reloads++;
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
    _followRequests(change.nextState);
  }

  /// Realtime on the user's join requests while there are any: a decision
  /// shows at once, not only on the next refresh.
  void _followRequests(Session session) {
    final userId = switch (session) {
      NeedsHousehold(:final userId, :final requests) ||
      InHousehold(
        :final userId,
        :final requests,
      ) when requests.isNotEmpty => userId,
      _ => null,
    };
    if (_requestWatch?.userId == userId) {
      return;
    }
    if (_requestWatch case (:final stop, userId: _)) {
      unawaited(stop());
    }
    _requestWatch = userId == null
        ? null
        : (
            userId: userId,
            stop: (_watchJoinRequests ?? _watchOwnRequests)(
              userId,
              () => unawaited(refresh().catchError((Object _) {})),
            ),
          );
  }

  Future<void> Function() _watchOwnRequests(
    String userId,
    void Function() onChange,
  ) {
    final channel = _client.channel('join_requests:$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'join_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => onChange(),
      )
      ..subscribe();
    return () async {
      await _client.removeChannel(channel);
    };
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    await _auth.cancel();
    await _requestWatch?.stop();
    _requestWatch = null;
    await _lost.close();
    await _decisions.close();
    await super.close();
  }
}
