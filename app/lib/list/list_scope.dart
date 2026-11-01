import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_suggestions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The household's list for both tabs: the List tab shows it, More manages
/// its categories and stores. A new household gets a new list.
class const ListScope({
  required final Widget child,
  super.key,

  /// Overrides the Supabase repository, for tests.
  final ListRepository? repository,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final household = session.household;
    return BlocProvider(
      key: ValueKey(household.id),
      create: (context) => ListCubit(
        repository ??
            SupabaseListRepository(Supabase.instance.client, household.id),
        context.read<DeviceCache>().list(session.userId, household.id),
        userId: session.userId,
        analytics: context.read<Analytics>(),
      )..start(),
      child: _Scope(child: child),
    );
  }
}

/// Where the List tab tells refused writes while it shows; elsewhere
/// [ListScope] tells them in the app's messenger, above the tabs.
class RejectionNotices() {
  /// Shows `text` in the List tab and returns true, or returns false when
  /// the tab is not on screen.
  bool Function(String text)? listTab;
}

/// Coming back to the app catches up on what changed meanwhile, a refused
/// write is told wherever the user is, and on iOS Siri learns the
/// household's item names.
class const _Scope({required final Widget child}) extends StatefulWidget {
  @override
  State<_Scope> createState() => _ScopeState();
}

class _ScopeState() extends State<_Scope> {
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<Rejected> _rejections;
  final _notices = RejectionNotices();
  SiriSuggestions? _siri;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ListCubit>();
    if (siriChannelFor(web: kIsWeb, platform: defaultTargetPlatform)
        case final siri?) {
      _siri = SiriSuggestions(siri, cubit);
    }
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
      };
      if (!(_notices.listTab?.call(text) ?? false)) {
        ScaffoldMessenger.maybeOf(context)
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider.value(value: _notices, child: widget.child);
}
