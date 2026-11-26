import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/shell/router.dart' show listPath;
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/summary_view.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A trip's summary page (job 234), in the List tab and in Verlauf. The
/// trip that just ended on this device comes from the [TripCubit] (with
/// „Weiter einkaufen“ and „Fertig“); any other from the server.
class const TripSummaryPage({required final String id, super.key})
    extends StatefulWidget {
  @override
  State<TripSummaryPage> createState() => _TripSummaryPageState();
}

class _TripSummaryPageState() extends State<TripSummaryPage> {
  TripCubit? _trips;
  Future<FinishedTrip>? _fetch;

  /// This page's „War geplant“ changes to the server's trip.
  final _marks = <String, bool>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _trips = context.read<TripCubit?>();
  }

  /// Leaving the fresh page lets the ended trip go: no „Weiter einkaufen“
  /// after it.
  @override
  void dispose() {
    if (_trips?.state case Ended(:final trip) when trip.id == widget.id) {
      _trips?.dismissEnded();
    }
    super.dispose();
  }

  /// Leaves the page, unless it was left already or covered during an await
  /// (a pop would then close what lies above or below it, job 438).
  void _leave() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(listPath);
    }
  }

  /// „Einkauf löschen“: after a yes, the trip goes for everyone (with its
  /// Verlauf entries) and the page leaves.
  Future<void> _delete({required bool fresh}) async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final trips = context.read<TripCubit?>();
    final repo = context.read<TripSessionRepository>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tripDeleteTitle),
        content: Text(l10n.tripDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('trip-summary-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    try {
      await (fresh && trips != null ? trips.delete() : repo.delete(widget.id));
    } on Object {
      notices.showSnackBar(SnackBar(content: Text(l10n.tripDeleteFailed)));
      return;
    }
    _leave();
  }

  /// „Kein Einkauf“ on a detected trip (job 352): after a yes it leaves
  /// Verlauf for everyone, its ticks stay, and the page leaves.
  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final notices = Notices.of(context);
    final repo = context.read<TripSessionRepository>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.tripNotShoppingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('trip-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.tripNotShoppingConfirm),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    try {
      await repo.removeDetected(widget.id);
    } on Object {
      notices.showSnackBar(SnackBar(content: Text(l10n.tripRemoveFailed)));
      return;
    }
    notices.showSnackBar(SnackBar(content: Text(l10n.tripRemoved)));
    _leave();
  }

  Future<FinishedTrip> _load() => _fetch ??= context
      .read<TripSessionRepository>()
      .fetch(widget.id)
      .then((trip) {
        if (mounted && trip.detected) {
          setState(() => _loaded = trip);
        }
        return trip;
      });

  /// The server's trip once loaded, when it is a detected one.
  FinishedTrip? _loaded;

  Future<void> _markFetched(String id, TripLine line, bool planned) async {
    final notices = Notices.of(context);
    final failed = AppLocalizations.of(context).shopMarkFailed;
    setState(() => _marks[line.key] = planned);
    try {
      await context.read<TripSessionRepository>().markPlanned(
        id,
        line.key,
        planned: planned,
      );
    } on Object {
      if (mounted) {
        setState(() => _marks[line.key] = !planned);
        notices.showSnackBar(SnackBar(content: Text(failed)));
      }
    }
  }

  Future<void> _markFresh(TripLine line, bool planned) async {
    final notices = Notices.of(context);
    final failed = AppLocalizations.of(context).shopMarkFailed;
    final ok = await context.read<TripCubit>().markPlanned(
      line.key,
      planned: planned,
    );
    if (!ok && mounted) {
      notices.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.select<ListCubit, Catalog>(
      (list) => list.state.catalog,
    );
    final prices = context.select<Flags?, bool>(
      (flags) => flags?.isOn(pricesFlag) ?? false,
    );
    final held = context.select<Entitlements?, bool>(
      (e) => e?.has(Entitlement.premium) ?? false,
    );
    final fresh = context.select<TripCubit?, Ended?>(
      (trips) => switch (trips?.state) {
        final Ended ended when ended.trip.id == widget.id => ended,
        _ => null,
      },
    );
    final Widget body;
    // Known once loaded: a detected trip is removed, not deleted.
    var detected = false;
    if (fresh != null) {
      final trips = context.read<TripCubit>();
      body = TripSummaryView(
        trip: fresh.trip,
        catalog: catalog,
        prices: prices,
        // Computed here, the lines are there before the server's answer
        // withholds them.
        locked: !held,
        onMark: held ? (line, on) => unawaited(_markFresh(line, on)) : null,
        onKeepShopping: () {
          trips.keepShopping();
          _leave();
        },
        onDone: () {
          trips.dismissEnded();
          _leave();
        },
        onRetrySave: fresh.save == TripSave.failed
            ? () => unawaited(trips.retry())
            : null,
        refused: fresh.save == TripSave.refused,
      );
    } else {
      detected = _loaded?.detected ?? false;
      body = FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Failed(
              onRetry: () => setState(() {
                _fetch = null;
              }),
            );
          }
          final trip = snapshot.data;
          if (trip == null) {
            return const Center(
              child: CircularProgressIndicator(key: ValueKey('trip-loading')),
            );
          }
          return TripSummaryView(
            trip: trip,
            catalog: catalog,
            prices: prices,
            marks: _marks,
            onMark: trip.lines == null
                ? null
                : (line, on) => unawaited(_markFetched(trip.id, line, on)),
            onRemove: trip.detected ? () => unawaited(_remove()) : null,
          );
        },
      );
    }
    // While the end is on its way, a delete could land before it. A
    // detected trip is removed from its head instead.
    final deletable = !detected && fresh?.save != TripSave.saving;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _barHeight(
          context,
          l10n.shopSummaryTitle,
          action: deletable,
        ),
        title: Text(l10n.shopSummaryTitle, softWrap: true, maxLines: 3),
        actions: [
          if (deletable)
            IconButton(
              key: const ValueKey('trip-summary-delete'),
              tooltip: l10n.tripDelete,
              onPressed: () => unawaited(_delete(fresh: fresh != null)),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      // One readable column on a wide window, as the list's.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ShoppingListView.columnWidth,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// The bar's height for [title]: one line's bar, or as tall as the lines
/// large text wraps it to (200 % on a 358 px phone), so it is never cut.
double _barHeight(BuildContext context, String title, {required bool action}) {
  // The title's width in the bar, a little less if anything: the back
  // button, the spacing around the title and the delete button.
  final width =
      MediaQuery.sizeOf(context).width -
      kToolbarHeight -
      2 * NavigationToolbar.kMiddleSpacing -
      (action ? kMinInteractiveDimension : 0);
  final painter = TextPainter(
    text: TextSpan(
      text: title,
      style: Theme.of(context).appBarTheme.titleTextStyle,
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 3,
  )..layout(maxWidth: width);
  final lines = painter.computeLineMetrics().length;
  final height = painter.height;
  painter.dispose();
  return lines < 2
      ? kToolbarHeight
      : math.max(kToolbarHeight, height + 2 * HlSpace.s2);
}

class const _Failed({required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HlSpace.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s3,
          children: [
            Text(
              l10n.shopLoadFailed,
              textAlign: TextAlign.center,
              style: HlType.body.copyWith(color: t.text),
            ),
            OutlinedButton(
              key: const ValueKey('trip-load-retry'),
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
