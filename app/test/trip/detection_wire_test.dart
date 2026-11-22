import 'dart:convert';

import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/trip/detection.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Job 352's calls as the server sees them, and its answers as read.
void main() {
  final sent = <http.Request>[];
  late Object? answer;

  SupabaseClient client() => SupabaseClient(
    'http://127.0.0.1:1',
    'sb_publishable_test',
    httpClient: MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(answer),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );

  String rpc(http.Request r) => r.url.pathSegments.last;
  Object? params(http.Request r) => jsonDecode(r.body);

  setUp(sent.clear);

  Map<String, Object?> row(
    String id, {
    Map<String, Object?> extra = const {},
  }) => {
    'id': id,
    'store_id': 'lidl',
    'store_name': 'Lidl',
    'shopped_on': '2026-11-14',
    'items': [
      {'name': 'Milch', 'quantity': null},
    ],
    'logged_by': null,
    'session_id': 's-$id',
    'created_at': '2026-11-14T00:00:00Z',
    ...extra,
  };

  test('Verlauf with learned-order reads trip_history_v2 and its detected '
      'trips; without, trip_history', () async {
    answer = {
      'trips': [
        row(
          'd',
          extra: {
            'session_source': 'detected',
            'detected_by': ['lea', 'peter'],
            'walked': false,
          },
        ),
        row('a', extra: {'session_source': 'ask'}),
        row('m'),
      ],
      'premium': true,
      'since': null,
      'locked': 0,
    };
    var on = true;
    final repo = SupabaseTripRepository(client(), 'home', detected: () => on);
    final history = await repo.fetch(DateTime(2026, 11, 22));
    expect(rpc(sent.single), 'trip_history_v2');
    expect(params(sent.single), {
      'p_household': 'home',
      'p_today': '2026-11-22',
    });
    expect(
      [for (final t in history.trips) t.detectedBy],
      [
        ['lea', 'peter'],
        null,
        null,
      ],
    );
    on = false;
    await repo.fetch(DateTime(2026, 11, 22));
    expect(rpc(sent.last), 'trip_history');
  });

  test('„Kein Einkauf“ is remove_detected_trip with the id', () async {
    answer = null;
    await SupabaseTripSessionRepository(
      client(),
      'home',
    ).removeDetected('trip-d');
    expect(rpc(sent.single), 'remove_detected_trip');
    expect(params(sent.single), {'p_id': 'trip-d'});
  });

  group('my_trip_detection', () {
    test('reads on, the card and its trip', () async {
      answer = {
        'on': true,
        'card_seen': false,
        'first_trip': {
          'id': 'trip-d',
          'household_id': 'home',
          'store_name': 'Lidl',
        },
      };
      final detection = await SupabaseTripDetection(client()).fetch();
      expect(rpc(sent.single), 'my_trip_detection');
      expect(detection.on, isTrue);
      expect(
        (
          detection.card?.id,
          detection.card?.householdId,
          detection.card?.storeName,
        ),
        ('trip-d', 'home', 'Lidl'),
      );
    });

    test('no first trip, or the card seen: no card', () async {
      answer = {'on': false, 'card_seen': false, 'first_trip': null};
      expect((await SupabaseTripDetection(client()).fetch()).card, isNull);
      answer = {
        'on': true,
        'card_seen': true,
        'first_trip': {'id': 't', 'household_id': 'h', 'store_name': null},
      };
      expect((await SupabaseTripDetection(client()).fetch()).card, isNull);
    });

    test('an answer of another shape is a FormatException', () async {
      answer = {'on': 'yes'};
      await expectLater(
        SupabaseTripDetection(client()).fetch(),
        throwsFormatException,
      );
    });

    test('the switch and the card call their functions', () async {
      answer = null;
      final repo = SupabaseTripDetection(client());
      await repo.setOn(on: false);
      await repo.seenCard();
      expect(
        [for (final r in sent) rpc(r)],
        ['set_trip_detection', 'seen_detected_trip_card'],
      );
      expect(params(sent.first), {'p_on': false});
    });
  });
}
