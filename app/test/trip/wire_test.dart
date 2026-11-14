import 'dart:convert';

import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Premium answer of `trip_session` as Postgres writes it (job 234's
/// trip_mode.test.sql shows the same shape).
const _answer = <String, Object?>{
  'id': '00000000-0000-0000-0000-000000234c01',
  'household_id': '00000000-0000-0000-0000-000000234b01',
  'list_id': null,
  'started_by': '00000000-0000-0000-0000-000000234a01',
  'started_at': '2026-11-14T09:00:00+00:00',
  'ended_at': '2026-11-14T09:25:00.5+00:00',
  'active_seconds': 1200,
  'end_reason': 'auto',
  'source': 'ask',
  'currency': 'EUR',
  'shopped_on': '2026-11-14',
  'pauses': [
    {
      'from': '2026-11-14T09:10:00+00:00',
      'to': '2026-11-14T09:15:00+00:00',
      'auto': true,
    },
  ],
  'lines': [
    {
      'key': 'k1',
      'name': 'Milch',
      'planned': true,
      'bought': true,
      'quantity': '2',
      'store_id': '00000000-0000-0000-0000-000000234d01',
      'store_name': 'Lidl',
      'marked_planned': false,
      'by_other': false,
      'added_by': null,
      'planned_cents': 258,
      'paid_cents': 278,
    },
    {
      'key': 'k3',
      'name': 'Käse',
      'planned': false,
      'bought': true,
      'quantity': null,
      'store_id': null,
      'store_name': null,
      'marked_planned': true,
      'by_other': true,
      'added_by': '00000000-0000-0000-0000-000000234a02',
      'planned_cents': null,
      'paid_cents': -25,
    },
  ],
  'bought': 2,
  'stores': ['Lidl', null],
  'premium': true,
};

void main() {
  final trip = FinishedTrip.fromJson(_answer);

  test('trip_session parses into a FinishedTrip', () {
    expect(
      trip,
      FinishedTrip(
        id: '00000000-0000-0000-0000-000000234c01',
        householdId: '00000000-0000-0000-0000-000000234b01',
        startedBy: '00000000-0000-0000-0000-000000234a01',
        startedAt: DateTime.utc(2026, 11, 14, 9),
        endedAt: DateTime.utc(2026, 11, 14, 9, 25, 0, 500),
        active: const Duration(minutes: 20),
        end: TripEnd.auto,
        source: TripSource.ask,
        currency: 'EUR',
        day: DateTime(2026, 11, 14),
        pauses: [
          TripPause(
            from: DateTime.utc(2026, 11, 14, 9, 10),
            to: DateTime.utc(2026, 11, 14, 9, 15),
            auto: true,
          ),
        ],
        lines: const [
          TripLine(
            key: 'k1',
            name: 'Milch',
            planned: true,
            bought: true,
            quantity: '2',
            storeId: '00000000-0000-0000-0000-000000234d01',
            storeName: 'Lidl',
            plannedCents: 258,
            paidCents: 278,
          ),
          TripLine(
            key: 'k3',
            name: 'Käse',
            planned: false,
            bought: true,
            markedPlanned: true,
            byOther: true,
            addedBy: '00000000-0000-0000-0000-000000234a02',
            paidCents: -25,
          ),
        ],
        bought: 2,
        stores: const ['Lidl', null],
      ),
    );
  });

  test('toJson is what save_trip_session takes and parses back', () {
    final json = trip.toJson();
    expect(json['started_at'], '2026-11-14T09:00:00.000Z');
    expect(json['shopped_on'], '2026-11-14');
    expect(json['active_seconds'], 1200);
    expect(json['end_reason'], 'auto');
    expect(FinishedTrip.fromJson(json), trip);
  });

  test('without Premium the lines are null and the counts stay', () {
    final free = FinishedTrip.fromJson(
      Map.of(_answer)
        ..['lines'] = null
        ..['premium'] = false,
    );
    expect(free.lines, isNull);
    expect(free.bought, 2);
    expect(free.stores, ['Lidl', null]);
    expect(free.toJson()['lines'], isNull);
  });

  group('save_trip_session refusing', () {
    Future<void> save(String code) => SupabaseTripSessionRepository(
      SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_test',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': code, 'message': 'too_many_lines'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      ),
      'household',
    ).save(FinishedTrip.fromJson(_answer), log: false);

    test('invalid input (22023) is for good', () async {
      await expectLater(save('22023'), throwsA(isA<TripRefused>()));
    });

    test('anything else may pass on a retry', () async {
      await expectLater(save('57014'), throwsA(isA<PostgrestException>()));
    });
  });
}
