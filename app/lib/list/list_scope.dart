import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_suggestions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The household's list above both tabs: the List tab shows it and its
/// Anpassen pages manage its categories and stores; it keeps syncing while
/// More is open. A new household gets a new list.
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
}) extends StatefulWidget {
  @override
  State<ListScope> createState() => _ListScopeState();
}

class _ListScopeState() extends State<ListScope> {
  /// The open lists by household: the shown one and hidden ones whose
  /// queue is not sent yet.
  final _lists = <String, ListCubit>{};

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
        _userId = userId;
        unawaited(_sendLeftQueues(userId, households));
      }
      unawaited(_sending.remove(shown)?.cancel());
      _lists.putIfAbsent(shown, () => _open(userId, shown));
      for (final id in [..._lists.keys]) {
        if (id == shown) {
          continue;
        }
        if (households.any((h) => h.id == id)) {
          _closeOnceSent(id);
        } else {
          _close(id);
        }
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
    return BlocProvider.value(
      key: ValueKey(household.id),
      value: _lists[household.id]!,
      child: _Scope(householdId: household.id, child: widget.child),
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
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(cubit.resync()),
    );
    _rejections = cubit.rejections.listen((rejection) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      final text = switch (rejection) {
        ItemRejected(:final itemName) => l10n.syncFailed(itemName),
        NameTaken(:final name) => l10n.categoryNameTaken(name),
        CatalogRejected() => l10n.catalogSaveFailed,
        NeedsConnection() => l10n.reorderNeedsConnection,
        StoreNameTaken(:final name) => l10n.storeNameTaken(name),
        StoreNeedsConnection() => l10n.storesNeedConnection,
        MergeRefused(:final name) => l10n.mergeRefused(name),
        RenameTaken(:final name) => l10n.alreadyOnList(name),
      };
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider.value(value: _notices, child: widget.child);
}
