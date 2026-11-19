import 'dart:async';

import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/log/model.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether the trips are there yet.
enum LogLoad() {
  loading,
  ready,

  /// The first fetch failed; a later one keeps the trips it had.
  failed,
}

/// The history screen: the trips, how they show, and the calendar's month
/// and picked day.
@immutable
class const LogState({
  /// The local date the screen counts from.
  required final DateTime today,

  /// The calendar's month, its first day.
  required final DateTime month,
  final LogLoad load = LogLoad.loading,

  /// Newest first, all inside [window].
  final List<Trip> trips = const [],

  /// How far back [trips] reach for the signed-in user.
  final HistoryWindow window = const AllHistory(),
  final LogView view = LogView.journal,

  /// The calendar day the journal is narrowed to; null shows every trip.
  final DateTime? day,
}) {
  /// The journal's trips: all of them, or the picked [day]'s.
  List<Trip> get shown => switch (day) {
    final day? => [
      for (final t in trips)
        if (t.day == day) t,
    ],
    null => trips,
  };

  /// Whether the calendar may go on to the next month: not past today's.
  bool get canGoForward => month.isBefore(DateTime(today.year, today.month));

  /// Whether the calendar may go back a month: not before the oldest trip's
  /// month, nor for Free before the window's (whichever is older), so a
  /// Free user sees where the locked days start.
  bool get canGoBack => month.isAfter(_firstMonth);

  /// How many older trips the window hides.
  int get locked => switch (window) {
    RecentHistory(:final locked) => locked,
    AllHistory() => 0,
  };

  DateTime get _firstMonth {
    final oldest = [
      ?trips.lastOrNull?.day,
      if (window case RecentHistory(:final since)) since,
    ].fold(today, (a, b) => b.isBefore(a) ? b : a);
    return DateTime(oldest.year, oldest.month);
  }

  LogState _with({
    DateTime? today,
    DateTime? month,
    LogLoad? load,
    List<Trip>? trips,
    HistoryWindow? window,
    LogView? view,
    DateTime? Function()? day,
  }) => LogState(
    today: today ?? this.today,
    month: month ?? this.month,
    load: load ?? this.load,
    trips: trips ?? this.trips,
    window: window ?? this.window,
    view: view ?? this.view,
    day: day == null ? this.day : day(),
  );
}

class LogCubit(
  final TripRepository _trips,
  final DeviceCache _cache, {

  /// The wall clock; tests fix it.
  final DateTime Function() clock = DateTime.now,

  /// Fires when the user's Premium may have changed: the window is read
  /// again.
  final Stream<Object?>? premiumChanges,
}) extends Cubit<LogState> {
  this
    : super(
        LogState(
          today: dateOnly(clock()),
          month: DateTime(clock().year, clock().month),
        ),
      ) {
    _premium = premiumChanges?.listen((_) => unawaited(refresh()));
  }

  StreamSubscription<Object?>? _premium;

  /// Loads the view saved on this device, then the trips.
  Future<void> start() async {
    final saved = LogView.parse(await _cache.logView());
    if (saved != null && !isClosed) {
      emit(state._with(view: saved));
    }
    await refresh();
  }

  /// After a failed first load.
  Future<void> retry() async {
    emit(state._with(load: LogLoad.loading));
    await refresh();
  }

  /// Fetches the trips again, after a save or delete or a change of
  /// Premium. A failure keeps the trips already shown.
  Future<void> refresh() async {
    final today = dateOnly(clock());
    try {
      final TripHistory(:trips, :window) = await _trips.fetch(today);
      if (!isClosed) {
        final next = state._with(
          today: today,
          load: LogLoad.ready,
          trips: [...trips]..sort(newestFirst),
          window: window,
          day: () => switch (state.day) {
            final day? when !window.locks(day) => day,
            _ => null,
          },
        );
        // A window that shrank (Premium ended) takes the calendar along.
        emit(
          next.month.isBefore(next._firstMonth)
              ? next._with(month: next._firstMonth)
              : next,
        );
      }
    } on Object {
      if (!isClosed && state.load != LogLoad.ready) {
        emit(state._with(load: LogLoad.failed));
      }
    }
  }

  /// G1 to G2 and back; remembered on this device.
  void toggleView() {
    final next = state.view.next;
    emit(state._with(view: next));
    unawaited(_cache.saveLogView(next.name));
  }

  /// The calendar's previous ([delta] -1) or next (1) month, never past
  /// today's nor before [LogState.canGoBack]'s.
  void showMonth(int delta) {
    if (delta < 0 ? state.canGoBack : state.canGoForward) {
      emit(
        state._with(
          month: DateTime(state.month.year, state.month.month + delta),
        ),
      );
    }
  }

  /// Narrows the journal to [day], or widens it again when [day] is the
  /// picked one. A day after today or before the window is not picked.
  void pickDay(DateTime day) {
    if (day.isAfter(state.today) || state.window.locks(day)) {
      return;
    }
    emit(state._with(day: () => day == state.day ? null : day));
  }

  /// Every trip again.
  void clearDay() => emit(state._with(day: () => null));

  @override
  Future<void> close() async {
    await _premium?.cancel();
    await super.close();
  }
}
