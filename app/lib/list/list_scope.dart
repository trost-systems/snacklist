import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_names.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_suggestions.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The household's list above the tabs: the List tab shows it and its
/// Anpassen pages manage its categories and stores; it keeps syncing while
/// More is open. A new household gets a new list. Next to it, the
/// household's logged trips ([TripRepository], job 199) and its trip-mode
/// trips ([TripSessionRepository], job 234).
///
/// Job 169b: a household switched away from keeps its list open until the
/// changes queued in it reached the server, and a start opens the list of
/// every other household that left changes queued on this device, until
/// they are sent. One list per household owns its queue (DECISIONS 169b).
class const ListScope({
  required final Widget child,
  super.key,

  /// Overrides the Supabase repository per household, for tests.
  final ListRepository Function(String householdId)? repositories,

  /// Overrides the Supabase trips per household, for tests.
  final TripRepository Function(String householdId)? trips,

  /// Overrides the Supabase trip-mode trips per household, for tests.
  final TripSessionRepository Function(String householdId)? tripSessions,
}) extends StatefulWidget {
  @override
  State<ListScope> createState() => _ListScopeState();
}

/// Opens the list of a household that is not shown, for as long as it is
/// held: the switcher sheet shows any household's lists (job 229). Each
/// [hold] needs its [release].
abstract interface class ListHolds() {
  /// The list of [householdId], opened if it is not open.
  ListCubit hold(String householdId);

  /// Lets go of one [hold] of [householdId]: once none is left and it is
  /// not shown, it closes as a list switched away from does, once its
  /// queue reached the server.
  void release(String householdId);
}

class _ListScopeState() extends State<ListScope> implements ListHolds {
  /// The open lists by household: the shown one, hidden ones whose queue is
  /// not sent yet and held ones.
  final _lists = <String, ListCubit>{};

  /// How often each household's list is held.
  final _holds = <String, int>{};

  /// A hidden list's wait for its queue to empty.
  final _sending = <String, StreamSubscription<ListState>>{};
  late final StreamSubscription<Session> _sessions;
  late Session _session;
  String? _userId;

  @override
  void initState() {
    super.initState();
    final sessions = context.read<SessionCubit>();
    _follow(sessions.state);
    _sessions = sessions.stream.listen((session) {
      if (mounted) {
        setState(() => _follow(session));
      }
    });
  }

  void _follow(Session session) {
    _session = session;
    if (session case InHousehold(
      :final userId,
      household: Household(id: final shown),
      :final households,
    )) {
      if (userId != _userId) {
        [..._lists.keys].forEach(_close);
        _holds.clear();
        _userId = userId;
        unawaited(_sendLeftQueues(userId, households));
      }
      unawaited(_sending.remove(shown)?.cancel());
      _lists.putIfAbsent(shown, () => _open(userId, shown));
      for (final id in [..._lists.keys]) {
        if (id == shown) {
          continue;
        }
        if (!households.any((h) => h.id == id)) {
          _close(id);
        } else if (!_holds.containsKey(id)) {
          _closeOnceSent(id);
        }
      }
    }
  }

  @override
  ListCubit hold(String householdId) {
    _holds.update(householdId, (n) => n + 1, ifAbsent: () => 1);
    unawaited(_sending.remove(householdId)?.cancel());
    return _lists.putIfAbsent(householdId, () => _open(_userId!, householdId));
  }

  @override
  void release(String householdId) {
    final left = (_holds[householdId] ?? 0) - 1;
    if (left > 0) {
      _holds[householdId] = left;
      return;
    }
    _holds.remove(householdId);
    if (!mounted) {
      return;
    }
    if (_session
        case InHousehold(
          household: Household(id: final shown),
          :final households,
        )
        when shown != householdId) {
      if (households.any((h) => h.id == householdId)) {
        _closeOnceSent(householdId);
      } else {
        _close(householdId);
      }
    }
  }

  ListCubit _open(String userId, String householdId) => ListCubit(
    widget.repositories?.call(householdId) ??
        SupabaseListRepository(Supabase.instance.client, householdId),
    context.read<DeviceCache>().list(userId, householdId),
    userId: userId,
    analytics: context.read<Analytics>(),
    network: context.read<NetworkWatch?>()?.watch(),
  )..start();

  /// Closes the hidden list of [id] once its queue reached the server. Until
  /// then it retries like the shown one: offline, or with the server failing.
  void _closeOnceSent(String id) {
    final list = _lists[id];
    if (list == null || _sending.containsKey(id)) {
      return;
    }
    // Resynced: the cached queue is loaded and was tried once.
    bool sent(ListState state) => state.resynced && state.pending.isEmpty;
    if (sent(list.state)) {
      _close(id);
      return;
    }
    _sending[id] = list.stream.listen((state) {
      if (sent(state)) {
        _close(id);
      }
    });
  }

  void _close(String id) {
    unawaited(_sending.remove(id)?.cancel());
    unawaited(_lists.remove(id)?.close());
  }

  /// A start, or another user: opens the list of each other household that
  /// has changes queued on this device, so they are sent without the user
  /// opening it.
  Future<void> _sendLeftQueues(
    String userId,
    List<Household> households,
  ) async {
    final cache = context.read<DeviceCache>();
    for (final Household(:id) in households) {
      final queued = (await cache.list(userId, id).load())?.pending ?? const [];
      final still = switch (_session) {
        InHousehold(:final households) => households.any((h) => h.id == id),
        _ => false,
      };
      if (queued.isEmpty ||
          !mounted ||
          !still ||
          _userId != userId ||
          _lists.containsKey(id)) {
        continue;
      }
      _lists[id] = _open(userId, id);
      _closeOnceSent(id);
    }
  }

  @override
  void dispose() {
    unawaited(_sessions.cancel());
    [..._lists.keys].forEach(_close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final household = session.household;
    return RepositoryProvider<ListHolds>.value(
      value: this,
      child: BlocProvider.value(
        key: ValueKey(household.id),
        value: _lists[household.id]!,
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<TripRepository>(
              create: (_) =>
                  widget.trips?.call(household.id) ??
                  SupabaseTripRepository(
                    Supabase.instance.client,
                    household.id,
                  ),
            ),
            RepositoryProvider<TripSessionRepository>(
              create: (_) =>
                  widget.tripSessions?.call(household.id) ??
                  SupabaseTripSessionRepository(
                    Supabase.instance.client,
                    household.id,
                  ),
            ),
          ],
          child: _Scope(householdId: household.id, child: widget.child),
        ),
      ),
    );
  }
}

/// Whether the list of [householdId] gives Siri its item names: only the
/// default household's, since Siri adds there (job 169b). Another
/// household's list leaves Siri the names it learnt from the default.
bool teachesSiri(Session session, String householdId) => switch (session) {
  InHousehold(:final households) => households.any(
    (h) => h.id == householdId && h.isDefault,
  ),
  _ => false,
};

/// What a refused write tells the user.
String rejectionText(AppLocalizations l10n, Rejected rejection) =>
    switch (rejection) {
      ItemRejected(:final itemName) => l10n.syncFailed(itemName),
      NameTaken(:final name) => l10n.categoryNameTaken(name),
      CatalogRejected() => l10n.catalogSaveFailed,
      NeedsConnection() => l10n.reorderNeedsConnection,
      StoreNameTaken(:final name) => l10n.storeNameTaken(name),
      StoreNeedsConnection() => l10n.storesNeedConnection,
      ListsNeedConnection() => l10n.listsNeedConnection,
      OnListAlready(:final name, :final list) => l10n.onListAlready(
        name,
        listName(list, l10n),
      ),
      MergeRefused(:final name) => l10n.mergeRefused(name),
      RenameTaken(:final name) => l10n.alreadyOnList(name),
    };

/// Where the List tab tells refused writes while it shows; elsewhere
/// [ListScope] tells them in the app's messenger, above the tabs.
class RejectionNotices() {
  /// Shows `text` in the List tab and returns true, or returns false when
  /// the tab is not on screen.
  bool Function(String text)? listTab;
}

/// Coming back to the app catches up on what changed meanwhile, a refused
/// write is told wherever the user is, on iOS Siri learns the household's
/// item names, and the Home Screen widgets show the list.
class const _Scope({
  required final String householdId,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<_Scope> createState() => _ScopeState();
}

class _ScopeState() extends State<_Scope> {
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<Rejected> _rejections;
  final _notices = RejectionNotices();
  SiriSuggestions? _siri;
  StreamSubscription<ListState>? _homeWidgets;

  /// Trip mode (job 234): asks after own ticks, runs the user's trip.
  late final TripCubit _trips;
  StreamSubscription<Map<String, bool>>? _flags;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ListCubit>();
    if (siriChannelFor(web: kIsWeb, platform: defaultTargetPlatform)
        case final siri?
        when teachesSiri(
          context.read<SessionCubit>().state,
          widget.householdId,
        )) {
      _siri = SiriSuggestions(siri, cubit);
    }
    _homeWidgets = context.read<HomeWidgetSync?>()?.followList(
      widget.householdId,
      cubit,
    );
    final flags = context.read<Flags?>();
    bool flag(String key) => flags?.isOn(key) ?? false;
    _trips = TripCubit(
      cubit,
      _LazyTripSessions(() => context.read<TripSessionRepository>()),
      context.read<DeviceCache>(),
      userId: cubit.userId,
      householdId: widget.householdId,
      enabled: () => flag(tripModeFlag),
      logs: () => flag(groceryLogFlag),
      analytics: context.read<Analytics>(),
    );
    unawaited(_trips.start());
    var tripMode = flag(tripModeFlag);
    _flags = flags?.stream.listen((_) {
      if (!tripMode && flag(tripModeFlag)) {
        unawaited(_trips.check());
      }
      tripMode = flag(tripModeFlag);
    });
    _lifecycle = AppLifecycleListener(
      onHide: cubit.hidden,
      onResume: () async {
        await cubit.resumed();
        await _trips.check();
      },
    );
    _rejections = cubit.rejections.listen((rejection) {
      if (!mounted) {
        return;
      }
      final text = rejectionText(AppLocalizations.of(context), rejection);
      if (!(_notices.listTab?.call(text) ?? false)) {
        Notices.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text), persist: false));
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_rejections.cancel());
    unawaited(_siri?.close());
    unawaited(_homeWidgets?.cancel());
    unawaited(_flags?.cancel());
    unawaited(_trips.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepositoryProvider.value(
    value: _notices,
    child: BlocProvider.value(value: _trips, child: widget.child),
  );
}

/// The household's [TripSessionRepository], looked up at its first call:
/// with the flag `trip-mode` off the trip cubit never makes one.
class _LazyTripSessions(final TripSessionRepository Function() _find)
    implements TripSessionRepository {
  late final _repo = _find();

  @override
  Future<FinishedTrip> save(FinishedTrip trip, {required bool log}) =>
      _repo.save(trip, log: log);

  @override
  Future<FinishedTrip> fetch(String id) => _repo.fetch(id);

  @override
  Future<void> markPlanned(String id, String key, {required bool planned}) =>
      _repo.markPlanned(id, key, planned: planned);

  @override
  Future<void> delete(String id) => _repo.delete(id);
}
