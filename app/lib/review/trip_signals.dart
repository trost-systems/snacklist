import 'package:flutter/foundation.dart' show immutable;

/// Trip mode as the rating prompt sees it (job 326), from the shell: review
/// may not import trip.
abstract interface class TripSignals() {
  /// A trip runs here.
  bool get running;

  /// „Kaufst du gerade ein?“ is up.
  bool get asking;

  /// Broadcast.
  Stream<TripSignal> get signals;
}

@immutable
sealed class const TripSignal();

/// „Kaufst du gerade ein?“ closed; [declined]: „Nein, nur abgehakt“ or
/// dismissed, not „Ja“ or „Zurücknehmen“.
final class const TripQuestionClosed({required final bool declined})
    extends TripSignal;

/// A trip's summary was left; [bought] items were ticked on it. [complete]:
/// ended by the user, saved at the first go, every planned item bought.
final class const TripSummaryLeft({
  required final int bought,
  required final bool complete,
}) extends TripSignal;

/// The save of a shown trip end failed or was refused.
final class const TripSaveFailed() extends TripSignal;
