import 'package:family_groceries/log/model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The grocery log's only door to the backend (`public.trips`, job 199).
/// A failure throws; the caller tells it and keeps what the user typed.
abstract interface class TripRepository() {
  /// The household's trips the user may see on [today] (a local date),
  /// newest first, and how far back they reach (`trip_history`).
  Future<TripHistory> fetch(DateTime today);

  /// Saves [trip] by its id (`save_trip`): a retried save is the same trip.
  /// The server snapshots the store's name and each item's canonical key.
  Future<void> save(Trip trip);

  /// Deletes the trip; a missing one is no error (`delete_trip`).
  Future<void> delete(String id);
}

class SupabaseTripRepository(
  final SupabaseClient _client,
  final String householdId, {

  /// The flag `learned-order` (job 352): `trip_history_v2`, which also
  /// answers detected trips.
  final bool Function() detected = _off,
}) implements TripRepository {
  static bool _off() => false;

  @override
  Future<TripHistory> fetch(DateTime today) async => TripHistory.fromJson(
    await _client.rpc<Object?>(
      detected() ? 'trip_history_v2' : 'trip_history',
      params: {'p_household': householdId, 'p_today': wireDay(today)},
    ),
  );

  @override
  Future<void> save(Trip trip) async {
    await _client.rpc<void>(
      'save_trip',
      params: {
        'p_household': householdId,
        'p_id': trip.id,
        'p_store': trip.storeId,
        'p_day': wireDay(trip.day),
        'p_items': [for (final item in trip.items) item.toJson()],
      },
    );
  }

  @override
  Future<void> delete(String id) async {
    await _client.rpc<void>('delete_trip', params: {'p_id': id});
  }
}
