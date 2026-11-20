import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// One store review request this install made, and the app version then.
@immutable
final class const ReviewRequest(final DateTime at, final String version) {
  @override
  bool operator ==(Object other) =>
      other is ReviewRequest && other.at == at && other.version == version;

  @override
  int get hashCode => Object.hash(at, version);
}

/// What the store review prompt knows about this install (job 155): how
/// long and how much it has been used, its review requests, and when it last
/// saw an error. Counts only: no ids, no item names, no household or user,
/// and kept across sign-outs.
@immutable
class const ReviewCounters({
  final DateTime? firstLaunch,

  /// The last day the app was in front, `yyyy-mm-dd` in local time.
  final String? lastActiveDay,
  final int activeDays = 0,
  final int completedTrips = 0,
  final int itemsAdded = 0,

  /// Oldest first, only those of the last 365 days.
  final List<ReviewRequest> requests = const [],
  final DateTime? lastErrorAt,
  final DateTime? sessionStart,
  final DateTime? previousSessionStart,

  /// A trip save that failed or was refused, a join or a household switch
  /// (job 326, SA3).
  final DateTime? lastSetbackAt,

  /// A sent feedback note of the kind bug.
  final DateTime? lastBugNoteAt,

  /// A re-add put an item back right after the tick that emptied the list
  /// (SA2).
  final DateTime? lastReopenedAt,
}) {
  /// Anything unreadable is a fresh install's counters: the prompt only
  /// waits longer.
  factory parse(String? json) {
    if (json == null) {
      return const ReviewCounters();
    }
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded case final Map<String, Object?> map) {
        return ReviewCounters(
          firstLaunch: _time(map['first_launch']),
          lastActiveDay: switch (map['last_active_day']) {
            final String day => day,
            _ => null,
          },
          activeDays: _count(map['active_days']),
          completedTrips: _count(map['completed_trips']),
          itemsAdded: _count(map['items_added']),
          requests: [
            if (map['requests'] case final List<Object?> requests)
              for (final request in requests)
                if (request
                    case {
                      'at': final String at,
                      'version': final String version,
                    }
                    when DateTime.tryParse(at) != null)
                  ReviewRequest(DateTime.parse(at), version),
          ],
          lastErrorAt: _time(map['last_error_at']),
          sessionStart: _time(map['session_start']),
          previousSessionStart: _time(map['previous_session_start']),
          lastSetbackAt: _time(map['last_setback_at']),
          lastBugNoteAt: _time(map['last_bug_note_at']),
          lastReopenedAt: _time(map['last_reopened_at']),
        );
      }
    } on FormatException {
      // Falls through to fresh counters.
    }
    return const ReviewCounters();
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static int _count(Object? value) => value is int && value > 0 ? value : 0;

  String toJson() => jsonEncode({
    'first_launch': ?firstLaunch?.toUtc().toIso8601String(),
    'last_active_day': ?lastActiveDay,
    'active_days': activeDays,
    'completed_trips': completedTrips,
    'items_added': itemsAdded,
    'requests': [
      for (final r in requests)
        {'at': r.at.toUtc().toIso8601String(), 'version': r.version},
    ],
    'last_error_at': ?lastErrorAt?.toUtc().toIso8601String(),
    'session_start': ?sessionStart?.toUtc().toIso8601String(),
    'previous_session_start': ?previousSessionStart?.toUtc().toIso8601String(),
    'last_setback_at': ?lastSetbackAt?.toUtc().toIso8601String(),
    'last_bug_note_at': ?lastBugNoteAt?.toUtc().toIso8601String(),
    'last_reopened_at': ?lastReopenedAt?.toUtc().toIso8601String(),
  });

  ReviewCounters copyWith({
    DateTime? firstLaunch,
    String? lastActiveDay,
    int? activeDays,
    int? completedTrips,
    int? itemsAdded,
    List<ReviewRequest>? requests,
    DateTime? lastErrorAt,
    DateTime? sessionStart,
    DateTime? previousSessionStart,
    DateTime? lastSetbackAt,
    DateTime? lastBugNoteAt,
    DateTime? lastReopenedAt,
  }) => ReviewCounters(
    firstLaunch: firstLaunch ?? this.firstLaunch,
    lastActiveDay: lastActiveDay ?? this.lastActiveDay,
    activeDays: activeDays ?? this.activeDays,
    completedTrips: completedTrips ?? this.completedTrips,
    itemsAdded: itemsAdded ?? this.itemsAdded,
    requests: requests ?? this.requests,
    lastErrorAt: lastErrorAt ?? this.lastErrorAt,
    sessionStart: sessionStart ?? this.sessionStart,
    previousSessionStart: previousSessionStart ?? this.previousSessionStart,
    lastSetbackAt: lastSetbackAt ?? this.lastSetbackAt,
    lastBugNoteAt: lastBugNoteAt ?? this.lastBugNoteAt,
    lastReopenedAt: lastReopenedAt ?? this.lastReopenedAt,
  );
}

/// Where [ReviewCounters] live on the device: `DeviceCache` in the app, one
/// JSON value.
abstract interface class ReviewStore() {
  Future<String?> reviewState();

  Future<void> saveReviewState(String json);
}
