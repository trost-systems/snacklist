import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/router.dart'
    show historyTripPath, premiumPath;
import 'package:family_groceries/design/group_card.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart' show Store;
import 'package:family_groceries/log/log_cubit.dart';
import 'package:family_groceries/log/model.dart';
import 'package:family_groceries/log/store_dot.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/log/trip_sheet.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart'
    show NoSale;
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The Verlauf tab (job 199): the household's shopping trips, as a journal
/// by date under a month calendar (G1) or by store (G2), one button
/// switching between them. Its trips come from the [TripRepository] and
/// its stores from the list above it.
class const HistoryScreen({
  super.key,

  /// The wall clock; tests fix it.
  final DateTime Function() clock = DateTime.now,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // A household switch keeps the tab's State: a new household, new trips.
    final household = context.select<SessionCubit?, String?>(
      (session) => switch (session?.state) {
        InHousehold(:final household) => household.id,
        _ => null,
      },
    );
    return BlocProvider(
      key: ValueKey(household),
      create: (context) {
        final log = LogCubit(
          context.read<TripRepository>(),
          context.read<DeviceCache>(),
          clock: clock,
          // The server decides the window (the household's Premium or the
          // user's own): any entitlement change reads it again.
          premiumChanges: context.read<Entitlements?>()?.stream,
        );
        unawaited(log.start());
        return log;
      },
      child: _History(clock: clock),
    );
  }
}

class const _History({required final DateTime Function() clock})
    extends StatefulWidget {
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState() extends State<_History> {
  /// The server's `premium_offer`, which has no change signal: read once the
  /// first hint shows and again each time the tab comes back.
  Future<OfferSwitch?>? _offer;
  bool? _shown;

  /// Each time the tab comes back, the trips and the offer are read again:
  /// the shell keeps it alive behind the others, and the list's trip card
  /// saves trips too.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (_shown == false && shown) {
      _offer = null;
      unawaited(context.read<LogCubit>().refresh());
    }
    _shown = shown;
  }

  Future<void> _open(
    BuildContext context, {
    Trip? trip,
    StorePick store = const NotPicked(),
    DateTime? day,
  }) async {
    // A trip-mode trip's entry shows its summary (job 234), at its own
    // address. Back from it, didChangeDependencies reads the trips again
    // (the page can delete the trip).
    final log = context.read<LogCubit>();
    if (trip?.sessionId case final session?
        when context.read<Flags?>()?.isOn(tripModeFlag) ?? false) {
      context.go(historyTripPath(session));
      return;
    }
    await showTripSheet(
      context,
      source: TripSource.manual,
      trip: trip,
      store: store,
      day: day,
      clock: widget.clock,
    );
    // Also after a plain close: a save whose answer was lost may have landed.
    if (!log.isClosed) {
      await log.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<LogCubit>().state;
    final stores = context.select<ListCubit, List<Store>>(
      (list) => list.state.catalog.stores,
    );
    final journal = state.view == LogView.journal;
    void open({
      Trip? trip,
      StorePick store = const NotPicked(),
      DateTime? day,
    }) => unawaited(_open(context, trip: trip, store: store, day: day));
    final hint = state.locked > 0
        ? _LockedHint(
            locked: state.locked,
            offer: _offer ??= Future.value(
              context.read<PremiumServer?>()?.offerSwitch(),
            ),
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabHistory),
        actions: [
          IconButton(
            key: const ValueKey('log-view-toggle'),
            tooltip: journal ? l10n.historyShowByStore : l10n.historyShowByDate,
            onPressed: context.read<LogCubit>().toggleView,
            icon: Icon(
              journal ? Icons.storefront_outlined : Icons.event_note_outlined,
            ),
          ),
          // Large text still leaves the title room at 358 px.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: HlSpace.s2),
              child: Semantics(
                label: l10n.tripAdd,
                button: true,
                onTap: open,
                excludeSemantics: true,
                child: TextButton.icon(
                  key: const ValueKey('log-add'),
                  onPressed: open,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tripAddShort),
                ),
              ),
            ),
          ),
        ],
      ),
      body: switch (state.load) {
        LogLoad.loading => const Center(
          child: CircularProgressIndicator(key: ValueKey('log-loading')),
        ),
        LogLoad.failed => _Failed(onRetry: context.read<LogCubit>().retry),
        LogLoad.ready when state.trips.isEmpty && hint == null => _Empty(
          onAdd: open,
        ),
        LogLoad.ready when journal => _Journal(
          state: state,
          stores: stores,
          hint: hint,
          onOpen: (trip) => open(trip: trip),
          onAddOn: (day) => open(day: day),
        ),
        LogLoad.ready => _StoreTimeline(
          state: state,
          stores: stores,
          hint: hint,
          onOpen: (trip) => open(trip: trip),
          onAddAt: (storeId) => open(store: presetStore(storeId)),
        ),
      },
    );
  }
}

/// Clear of the floating tab pill.
EdgeInsets _listPadding(BuildContext context) =>
    EdgeInsets.only(bottom: HlSpace.s5 + MediaQuery.paddingOf(context).bottom);

class const _Failed({required final VoidCallback onRetry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HlSpace.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s4,
          children: [
            Text(l10n.historyLoadFailed, textAlign: TextAlign.center),
            FilledButton(
              key: const ValueKey('log-retry'),
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class const _Empty({required final VoidCallback onAdd})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('log-empty'),
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s6,
          HlSpace.s5,
          HlSpace.s6,
          HlSpace.s8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: HlSpace.s3,
          children: [
            Icon(Icons.shopping_basket_outlined, size: 40, color: t.textMuted),
            Text(
              l10n.historyEmptyTitle,
              textAlign: TextAlign.center,
              style: HlType.title.copyWith(color: t.text),
            ),
            Text(
              l10n.historyEmptyBody,
              textAlign: TextAlign.center,
              style: HlType.body.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: HlSpace.s2),
            FilledButton.icon(
              key: const ValueKey('log-empty-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.tripAdd),
            ),
          ],
        ),
      ),
    );
  }
}

/// A trip's store as shown: the household's store by its name now, a gone
/// one by the name it was saved with, or "Ohne Laden".
String _storeLabel(Trip trip, List<Store> stores, AppLocalizations l10n) =>
    stores.where((s) => s.id == trip.storeId).firstOrNull?.name ??
    trip.storeName ??
    l10n.noStore;

Color _tripColour(BuildContext context, Trip trip, List<Store> stores) {
  final brightness = Theme.of(context).brightness;
  return storeColour(
    SnacklistColors.of(brightness),
    brightness,
    storeColourIndex(trip.storeId, stores),
  );
}

/// Heute, Gestern, or the short date ("Mo., 10. Nov.").
String _dayLabel(BuildContext context, DateTime day, DateTime today) {
  final l10n = AppLocalizations.of(context);
  return switch (daysBetween(day, today)) {
    0 => l10n.dayToday,
    1 => l10n.dayYesterday,
    _ => DateFormat.MMMEd(_locale(context)).format(day),
  };
}

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

/// "Milch, Eier, Äpfel und 1 mehr".
String _summary(AppLocalizations l10n, List<TripItem> items) {
  final names = [for (final item in items) item.name];
  return names.length > 3
      ? l10n.tripSummaryMore(names.take(3).join(', '), names.length - 3)
      : names.join(', ');
}

/// G1: the month calendar, then the trips by week and month, or the picked
/// day's.
class const _Journal({
  required final LogState state,
  required final List<Store> stores,

  /// Free with older trips: under the calendar when its month has locked
  /// days, and at the end.
  required final Widget? hint,
  required final ValueChanged<Trip> onOpen,
  required final ValueChanged<DateTime> onAddOn,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final log = context.read<LogCubit>();
    final day = state.day;
    final locale = _locale(context);
    Widget card(Trip trip) => _TripTile(
      trip: trip,
      title: _storeLabel(trip, stores, l10n),
      dot: _tripColour(context, trip, stores),
      date: _dayLabel(context, trip.day, state.today),
      onTap: () => onOpen(trip),
    );
    return ListView(
      key: const ValueKey('log-journal'),
      padding: _listPadding(context),
      children: [
        _Calendar(state: state, stores: stores),
        if (hint != null &&
            state.window.locks(DateTime(state.month.year, state.month.month)))
          Padding(
            key: const ValueKey('log-calendar-locked'),
            padding: const EdgeInsets.only(top: HlSpace.s2),
            child: hint,
          ),
        if (day != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, HlSpace.s4, HlSpace.s2, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.historyDayFilter(day),
                    key: const ValueKey('log-day-filter'),
                    style: HlType.label.copyWith(color: t.text),
                  ),
                ),
                IconButton(
                  key: const ValueKey('log-day-clear'),
                  tooltip: l10n.historyDayClear,
                  onPressed: log.clearDay,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (state.shown.isEmpty)
            Padding(
              key: const ValueKey('log-day-empty'),
              padding: const EdgeInsets.fromLTRB(20, HlSpace.s2, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s2,
                children: [
                  Text(
                    l10n.historyDayEmpty,
                    style: HlType.body.copyWith(color: t.textMuted),
                  ),
                  TextButton.icon(
                    key: const ValueKey('log-day-add'),
                    onPressed: () => onAddOn(day),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.tripAdd),
                  ),
                ],
              ),
            )
          else
            HlGroup(
              top: HlSpace.s2,
              children: [for (final trip in state.shown) card(trip)],
            ),
        ] else
          for (final (:period, :trips) in journalSections(
            state.trips,
            state.today,
          )) ...[
            HlSectionLabel(switch (period) {
              ThisWeek() => l10n.historyThisWeek,
              LastWeek() => l10n.historyLastWeek,
              InMonth(:final year, :final month) => DateFormat.yMMMM(
                locale,
              ).format(DateTime(year, month)),
            }, padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, 20, 0)),
            HlGroup(
              top: HlSpace.s2,
              children: [for (final trip in trips) card(trip)],
            ),
          ],
        if (day == null && hint != null)
          Padding(
            key: const ValueKey('log-journal-locked'),
            padding: const EdgeInsets.only(top: HlSpace.s4),
            child: hint,
          ),
      ],
    );
  }
}

/// G2: one block per store, its trips newest first.
class const _StoreTimeline({
  required final LogState state,
  required final List<Store> stores,

  /// Free with older trips: at the end.
  required final Widget? hint,
  required final ValueChanged<Trip> onOpen,
  required final ValueChanged<String?> onAddAt,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final t = SnacklistColors.of(brightness);
    return ListView(
      key: const ValueKey('log-stores'),
      padding: _listPadding(context),
      children: [
        for (final (:storeId, :name, :trips) in storeBlocks(
          state.trips,
          stores,
        )) ...[
          Padding(
            key: ValueKey('log-store-${storeId ?? name ?? 'none'}'),
            padding: const EdgeInsets.fromLTRB(20, HlSpace.s5, HlSpace.s2, 0),
            // As tall as its + button, also for a gone store without one.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: HlSize.target),
              child: Row(
                spacing: HlSpace.s3,
                children: [
                  StoreDot(
                    storeColour(
                      t,
                      brightness,
                      storeColourIndex(storeId, stores),
                    ),
                    size: 12,
                  ),
                  Expanded(
                    child: Semantics(
                      // Its own node, apart from the + next to it.
                      container: true,
                      header: true,
                      child: Text(
                        name ?? l10n.noStore,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HlType.title.copyWith(color: t.text),
                      ),
                    ),
                  ),
                  // A gone store can't be picked any more.
                  if (storeId != null || name == null)
                    IconButton(
                      key: ValueKey('log-store-add-${storeId ?? 'none'}'),
                      tooltip: l10n.tripAddAt(name ?? l10n.noStore),
                      onPressed: () => onAddAt(storeId),
                      icon: const Icon(Icons.add),
                    ),
                ],
              ),
            ),
          ),
          if (trips.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, HlSpace.s1, 20, 0),
              child: Text(
                l10n.historyStoreEmpty,
                style: HlType.body.copyWith(color: t.textMuted),
              ),
            )
          else
            HlGroup(
              top: HlSpace.s2,
              children: [
                for (final trip in trips)
                  _TripTile(
                    trip: trip,
                    title: _dayLabel(context, trip.day, state.today),
                    date: null,
                    dot: null,
                    onTap: () => onOpen(trip),
                  ),
              ],
            ),
        ],
        if (hint != null)
          Padding(
            key: const ValueKey('log-stores-locked'),
            padding: const EdgeInsets.only(top: HlSpace.s4),
            child: hint,
          ),
      ],
    );
  }
}

/// The quiet row for a Free user's [locked] older trips: they are kept and
/// show with Snacklist Premium. Opens the Premium page where it is sold;
/// otherwise says, as the integration settings' card does, why not.
class const _LockedHint({
  required final int locked,
  required final Future<OfferSwitch?> offer,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final held = context.select<Entitlements?, bool>(
      (e) => e?.has(Entitlement.premium) ?? false,
    );
    final noSale = context.select<PurchaseCubit?, NoSale?>(
      (c) => c?.state.noSale,
    );
    return FutureBuilder(
      future: offer,
      builder: (context, snapshot) {
        // Exactly when More lists Premium; before sales start the row says
        // nothing about buying (job 87).
        final opens = premiumListed(
          held: held,
          offer: snapshot.data,
          noSale: noSale,
        );
        final row = Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: HlSpace.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HlSpace.s3,
            children: [
              Icon(Icons.lock_outline, size: 20, color: t.textMuted),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      l10n.historyLockedTitle,
                      style: HlType.label.copyWith(color: t.text),
                    ),
                    Text(
                      l10n.historyLockedCount(locked),
                      style: HlType.body.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              if (opens) Icon(Icons.chevron_right, color: t.textMuted),
            ],
          ),
        );
        if (!opens) {
          return MergeSemantics(child: row);
        }
        return MergeSemantics(
          child: Semantics(
            button: true,
            child: InkWell(
              key: const ValueKey('log-locked-premium'),
              onTap: () => context.go(
                Uri(
                  path: premiumPath,
                  queryParameters: {'from': PaywallEntry.history.name},
                ).toString(),
              ),
              child: row,
            ),
          ),
        );
      },
    );
  }
}

/// A trip in a group: [title] (the store, or in G2 the day) with [date]
/// after it, the items it held and how many.
class const _TripTile({
  required final Trip trip,
  required final String title,
  required final String? date,
  required final Color? dot,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final count = l10n.tripItemCount(trip.items.length);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          key: ValueKey('log-trip-${trip.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HlSpace.s4,
              vertical: HlSpace.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: HlSpace.s3,
              children: [
                if (dot case final dot?)
                  SizedBox(
                    width: 20,
                    height: 22,
                    child: Center(
                      child: StoreDot(dot, size: 12, ring: t.surfaceRaised),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: title,
                          style: HlType.label.copyWith(color: t.text),
                          children: [
                            if (date != null)
                              TextSpan(
                                text: ' · $date',
                                style: HlType.label.copyWith(
                                  color: t.textMuted,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _summary(l10n, trip.items),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HlType.body.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
                Text(count, style: HlType.caption.copyWith(color: t.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The journal's month: a row per week from Monday, each day with up to
/// [maxDayDots] overlapping dots, one per trip in its store's colour. A day
/// up to today narrows the journal to it; later days are not buttons.
class const _Calendar({
  required final LogState state,
  required final List<Store> stores,
}) extends StatelessWidget {
  static const _cellHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final t = SnacklistColors.of(brightness);
    final log = context.read<LogCubit>();
    final locale = _locale(context);
    final month = state.month;
    final marks = dayMarks(
      state.trips,
      month,
      (trip) =>
          storeColour(t, brightness, storeColourIndex(trip.storeId, stores)),
    );
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - DateTime.monday;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((lead + days) / 7).ceil();
    final monday = mondayOf(state.today);
    return Padding(
      key: const ValueKey('log-calendar'),
      padding: const EdgeInsets.fromLTRB(HlSpace.s3, HlSpace.s2, HlSpace.s3, 0),
      // Large text still fits the day cells; screen readers get the full
      // label anyway.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('log-month-previous'),
                  tooltip: l10n.previousMonth,
                  onPressed: state.canGoBack ? () => log.showMonth(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Semantics(
                    // Its own node: otherwise the whole calendar under it
                    // becomes the header.
                    container: true,
                    header: true,
                    child: Text(
                      DateFormat.yMMMM(locale).format(month),
                      key: const ValueKey('log-month'),
                      textAlign: TextAlign.center,
                      style: HlType.title.copyWith(color: t.text),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('log-month-next'),
                  tooltip: l10n.nextMonth,
                  onPressed: state.canGoForward ? () => log.showMonth(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Text(
                        DateFormat.E(locale)
                            .format(
                              DateTime(
                                monday.year,
                                monday.month,
                                monday.day + i,
                              ),
                            )
                            .replaceAll('.', ''),
                        textAlign: TextAlign.center,
                        style: HlType.caption.copyWith(color: t.textMuted),
                      ),
                    ),
                ],
              ),
            ),
            for (var week = 0; week < weeks; week++)
              Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: switch (week * 7 + weekday - lead + 1) {
                        final n when n < 1 || n > days => const SizedBox(
                          height: _cellHeight,
                        ),
                        final n => _Day(
                          day: DateTime(month.year, month.month, n),
                          today: state.today,
                          picked: state.day,
                          locked: state.window.locks(
                            DateTime(month.year, month.month, n),
                          ),
                          mark: marks[n],
                          onTap: log.pickDay,
                        ),
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class const _Day({
  required final DateTime day,
  required final DateTime today,
  required final DateTime? picked,

  /// Before the Free window: muted, no dots, not a button.
  required final bool locked,
  required final DayMark<Color>? mark,
  required final ValueChanged<DateTime> onTap,
}) extends StatelessWidget {
  /// Each dot's step right of the one before: they overlap by half.
  static const _dotStep = 6.0;
  static const _dotSize = 9.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final future = day.isAfter(today);
    final muted = future || locked;
    final isToday = day == today;
    final isPicked = day == picked;
    final wire = wireDay(day);
    final colours = locked ? const <Color>[] : mark?.colours ?? const <Color>[];
    const dot = _dotSize + 2 * StoreDot.ringWidth;
    final dots = SizedBox(
      height: dot,
      width: colours.isEmpty ? dot : dot + (colours.length - 1) * _dotStep,
      child: Stack(
        children: [
          if (locked)
            Icon(
              Icons.lock_outline,
              size: dot,
              color: t.textMuted.withValues(alpha: 0.5),
            ),
          // Painted last, the newest (left) dot lies on top.
          for (final (i, colour) in colours.indexed.toList().reversed)
            Positioned(
              left: i * _dotStep,
              child: StoreDot(
                colour,
                key: ValueKey('log-dot-$wire-$i'),
                size: _dotSize,
                ring: isPicked ? t.honey : t.surface,
              ),
            ),
        ],
      ),
    );
    final number = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: t.border, width: HlBorder.width)
            : null,
      ),
      child: Text(
        '${day.day}',
        style: HlType.label.copyWith(
          color: muted
              ? t.textMuted.withValues(alpha: 0.5)
              : isPicked
              ? t.onHoney
              : t.text,
          fontWeight: isToday || isPicked ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
    final cell = Container(
      height: _Calendar._cellHeight,
      margin: const EdgeInsets.all(1),
      decoration: isPicked
          ? BoxDecoration(
              color: t.honey,
              borderRadius: BorderRadius.circular(HlRadius.s),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [number, dots],
      ),
    );
    final date = DateFormat.MMMMEEEEd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(day);
    final count = locked ? 0 : mark?.count ?? 0;
    final label = locked
        ? l10n.historyDayLocked(date)
        : count == 0
        ? date
        : l10n.historyDayLabel(date, count);
    if (muted) {
      return Semantics(
        key: ValueKey('log-day-$wire'),
        container: true,
        label: label,
        excludeSemantics: true,
        child: cell,
      );
    }
    return Semantics(
      key: ValueKey('log-day-$wire'),
      button: true,
      selected: isPicked,
      label: label,
      excludeSemantics: true,
      onTap: () => onTap(day),
      child: InkWell(
        borderRadius: BorderRadius.circular(HlRadius.s),
        onTap: () => onTap(day),
        child: cell,
      ),
    );
  }
}
