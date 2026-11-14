import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/router.dart' show tripSummaryPath;
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/log/trip_prompts.dart';
import 'package:family_groceries/trip/ask_sheet.dart';
import 'package:family_groceries/trip/ended_card.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_strip.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Trip mode's part of the list (job 234): the question after an own tick,
/// the summary after Beenden, and the end of job 199's trip prompts, which
/// the trip logged. Without a [TripCubit] above it, [child] alone.
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
      case Ended(:final trip, :final from, :final auto) when was is! Ended:
        // The trip logged what it bought: job 199's cards must not offer it
        // again, also in a store whose section still had open items.
        final items = context.read<ListCubit>().state.allItems.values;
        context.read<TripPrompts?>()?.forget({
          for (final item in items)
            if (boughtOnTrip(from, item, end: trip.endedAt)) item.id,
        });
        if (!auto) {
          context.go(tripSummaryPath(trip.id));
        }
      case _:
        break;
    }
  }

  Future<void> _ask(TripCubit trips, Asking asking) async {
    final answer = await showTripAsk(context, itemName: asking.item.name);
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

/// Whether a trip runs here: job 199's prompts wait for its end.
bool tripRunning(BuildContext context) {
  final on = _tripMode(context);
  final running = context.select<TripCubit?, bool>(
    (trips) => trips?.state is Running,
  );
  return on && running;
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
    if (!on || ended == null) {
      return const SizedBox.shrink();
    }
    final trips = context.read<TripCubit>();
    return TripEndedCard(
      endedAt: ended.trip.endedAt,
      onKeepGoing: trips.keepShopping,
      onShowSummary: () => context.go(tripSummaryPath(ended.trip.id)),
      onDismiss: trips.dismissEnded,
    );
  }
}
