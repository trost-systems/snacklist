import 'dart:async';

import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/review/trip_signals.dart';

/// The device's review counters for one test.
class MemoryReviewStore() implements ReviewStore {
  String? json;

  @override
  Future<String?> reviewState() async => json;

  @override
  Future<void> saveReviewState(String json) async => this.json = json;
}

/// The store's prompt and listing, counted.
class FakeStoreReview() implements StoreReview {
  var available = true;
  var requests = 0;
  var listings = 0;

  /// Thrown by [openStoreListing] when set (no store app, no connection).
  Exception? listingError;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  Future<void> openStoreListing() async {
    listings++;
    if (listingError case final error?) {
      throw error;
    }
  }
}

/// Trip mode as the shell shows it to the prompt, set by hand.
class FakeTripSignals() implements TripSignals {
  @override
  var running = false;

  @override
  var asking = false;

  final _signals = StreamController<TripSignal>.broadcast();

  @override
  Stream<TripSignal> get signals => _signals.stream;

  void tell(TripSignal signal) => _signals.add(signal);

  Future<void> close() => _signals.close();
}
