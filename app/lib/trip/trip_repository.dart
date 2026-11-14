import 'package:family_groceries/trip/model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server refused a trip for good (`22023`: too many lines, a line it
/// does not take): saving it again cannot work.
class const TripRefused(final String message) implements Exception {
  @override
  String toString() => 'TripRefused: $message';
}

/// Trip mode's only door to the backend (`public.trip_sessions`, job 234).
/// A failure throws; the caller keeps the trip on the device and retries.
abstract interface class TripSessionRepository() {
  /// Saves [trip] by its id (`save_trip_session`): a retried or repeated
  /// end is the same trip. With [log], also writes its grocery-log entries,
  /// one per store. Answers as [fetch] does: without Premium, no lines.
  /// Throws [TripRefused] when no later save of it can work.
  Future<FinishedTrip> save(FinishedTrip trip, {required bool log});

  /// The household's trip [id] (`trip_session`).
  Future<FinishedTrip> fetch(String id);

  /// "War geplant" on line [key] of trip [id]; Premium only.
  Future<void> markPlanned(String id, String key, {required bool planned});

  /// Deletes the trip and its log entries; a missing one is no error.
  Future<void> delete(String id);
}

class SupabaseTripSessionRepository(
  final SupabaseClient _client,
  final String householdId,
) implements TripSessionRepository {
  @override
  Future<FinishedTrip> save(FinishedTrip trip, {required bool log}) async {
    try {
      return FinishedTrip.fromJson(
        await _client.rpc<Map<String, Object?>>(
          'save_trip_session',
          params: {
            'p_household': householdId,
            'p_trip': trip.toJson(),
            'p_log': log,
          },
        ),
      );
    } on PostgrestException catch (e) {
      if (e.code == '22023') {
        throw TripRefused(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<FinishedTrip> fetch(String id) async => FinishedTrip.fromJson(
    await _client.rpc<Map<String, Object?>>(
      'trip_session',
      params: {'p_household': householdId, 'p_id': id},
    ),
  );

  @override
  Future<void> markPlanned(
    String id,
    String key, {
    required bool planned,
  }) async {
    await _client.rpc<void>(
      'mark_trip_line_planned',
      params: {'p_id': id, 'p_key': key, 'p_planned': planned},
    );
  }

  @override
  Future<void> delete(String id) async {
    await _client.rpc<void>('delete_trip_session', params: {'p_id': id});
  }
}
