import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/shell/router.dart' show tripSummaryPath;
import 'package:family_groceries/trip/ask_sheet.dart';
import 'package:family_groceries/trip/detection.dart';
import 'package:family_groceries/trip/ended_card.dart';
import 'package:family_groceries/trip/model.dart' show AskAnswer, RunningTrip;
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_strip.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Trip mode's part of the list (job 234): the question after an own tick,
/// the summary after Beenden. Without a [TripCubit] above it, [child] alone.
class const TripOnList({required final Widget child, super.key})
    extends StatefulWidget {
  @override
  State<TripOnList> createState() => _TripOnListState();
}

class _TripOnListState() extends State<TripOnList> {
  StreamSubscription<TripState>? _states;

  @override
  void initState() {
    super.initState();
    final trips = context.read<TripCubit?>();
    var last = trips?.state;
    _states = trips?.stream.listen((next) {
      final was = last;
      last = next;
      if (mounted) {
        _changed(trips, was, next);
      }
    });
  }

  void _changed(TripCubit trips, TripState? was, TripState next) {
    switch (next) {
      case Asking(:final item, :final at)
          when switch (was) {
            Asking(item: final i, at: final a) => i.id != item.id || a != at,
            _ => true,
          }:
        unawaited(_ask(trips, next));
      case Ended(:final trip, :final auto) when was is! Ended:
        if (!auto) {
          context.go(tripSummaryPath(trip.id));
        }
      case _:
        break;
    }
  }

  Future<void> _ask(TripCubit trips, Asking asking) async {
    final answer = await showTripAsk(
      context,
      itemName: asking.item.name,
      quiet: trips.quietsAfterNo,
    );
    if (!identical(trips.state, asking)) {
      return;
    }
    switch (answer) {
      case AskAnswer.yes:
        trips.yes();
      case AskAnswer.no:
        trips.no();
      case AskAnswer.takeBack:
        trips.takeBack();
    }
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Whether the flag `trip-mode` is on.
bool _tripMode(BuildContext context) =>
    context.select<Flags?, bool>((flags) => flags?.isOn(tripModeFlag) ?? false);

/// The running trip's strip above the add bar; nothing while [hidden] (the
/// field has focus, the price panel is open) or no trip runs.
class const TripStripSlot({required final bool hidden, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = _tripMode(context);
    final running = context.select<TripCubit?, Running?>(
      (trips) => switch (trips?.state) {
        final Running running => running,
        _ => null,
      },
    );
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!on || running == null || hidden || keyboard) {
      return const SizedBox.shrink();
    }
    final trips = context.read<TripCubit>();
    final strip = TripStrip(
      trip: running.trip,
      lastTick: running.lastTick,
      elapsed: trips.elapsed,
      clock: trips.clock,
      onPause: trips.pause,
      onResume: trips.resume,
      onEnd: () => unawaited(trips.finish()),
    );
    // Over the list's first column, as the add bar below it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = context.select<ListCubit, ListFrame>(
          (list) => ShoppingListView.frameFor(constraints.maxWidth, list.state),
        );
        return Padding(
          padding: EdgeInsetsDirectional.only(start: frame.side),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: 1,
            child: SizedBox(width: frame.columnWidth, child: strip),
          ),
        );
      },
    );
  }
}

/// The user's trip running on [listId] (one without a list on any), with
/// `trip-mode` on: the summary block splits bought and open (job 237).
RunningTrip? runningOn(BuildContext context, String? listId) {
  final on = _tripMode(context);
  final trip = context.select<TripCubit?, RunningTrip?>(
    (trips) => switch (trips?.state) {
      Running(:final trip) => trip,
      _ => null,
    },
  );
  return on && trip != null && (trip.listId == null || trip.listId == listId)
      ? trip
      : null;
}

/// The list's card after the long-running rule ended the trip.
class const TripEndedSlot({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final on = _tripMode(context);
    final ended = context.select<TripCubit?, Ended?>(
      (trips) => switch (trips?.state) {
        final Ended ended when ended.auto => ended,
        _ => null,
      },
    );
    final endedAt = ended?.trip.endedAt;
    if (!on || ended == null || endedAt == null) {
      return const SizedBox.shrink();
    }
    final trips = context.read<TripCubit>();
    return TripEndedCard(
      endedAt: endedAt,
      onKeepGoing: trips.keepShopping,
      onShowSummary: () => context.go(tripSummaryPath(ended.trip.id)),
      onDismiss: trips.dismissEnded,
    );
  }
}

/// The list's card after the person's first detected trip (job 352): with
/// the flags `learned-order`, `grocery-log` and `trip-mode` (its words point
/// to the trip in Verlauf, job 401), while it is unseen and the trip is in
/// this household. Either button sees it for good; „Ansehen“ opens the trip.
class const DetectedTripSlot({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final flag = context.select<Flags?, bool>(
      (flags) =>
          flags != null &&
          flags.isOn(learnedOrderFlag) &&
          flags.isOn(groceryLogFlag) &&
          flags.isOn(tripModeFlag),
    );
    final detection = context.watch<TripDetectionCubit?>();
    final card = detection?.state?.card;
    if (!flag ||
        detection == null ||
        card == null ||
        card.householdId != context.read<TripCubit?>()?.householdId) {
      return const SizedBox.shrink();
    }
    return DetectedTripCard(
      storeName: card.storeName,
      onView: () {
        unawaited(detection.seenCard());
        context.go(tripSummaryPath(card.id));
      },
      onDone: () => unawaited(detection.seenCard()),
    );
  }
}
