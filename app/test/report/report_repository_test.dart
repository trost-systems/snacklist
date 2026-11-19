import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:family_groceries/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '20000000-0000-4000-8000-000000000002';

/// An unsigned token for [userId]; nothing here checks it.
final _jwt = [
  base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}')),
  base64Url.encode(
    utf8.encode('{"sub":"$userId","exp":4102444800,"role":"authenticated"}'),
  ),
  'x',
].join('.').replaceAll('=', '');

final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);

final report = ReportSubmission(
  locale: 'en',
  category: ReportCategory.personalRights,
  target: const ItemTarget(
    id: '30000000-0000-4000-8000-000000000003',
    name: 'Hafermilch',
    list: 'Wocheneinkauf',
    household: 'Familie Brandt',
  ),
  reason: 'This item names my neighbour with an insult.',
  name: 'Mia Brandt',
  email: 'mia.brandt@example.com',
  screenshot: png,
);

http.Response json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;

  /// The repository signed in as [userId] with [metadata] from the
  /// provider; the function answers [answer].
  Future<SupabaseReportRepository> signedIn(
    FutureOr<http.Response> Function(http.Request request) answer, {
    Map<String, Object?> metadata = const {},
    String? email = 'mia.brandt@example.com',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requests = [];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return await answer(request);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': _jwt,
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': 4102444800,
        'refresh_token': 'r',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'email': ?email,
          'app_metadata': <String, Object?>{},
          'user_metadata': metadata,
          'created_at': '2026-11-17T12:00:00Z',
        },
      }),
    );
    return SupabaseReportRepository(client, timeout: timeout);
  }

  test('POSTs the report to report/app with the session and answers its '
      'number', () async {
    final repo = await signedIn((_) => json({'ref': 'M-7K2M-4Q9P'}, 201));
    expect(await repo.send(report), 'M-7K2M-4Q9P');
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/functions/v1/report/app');
    expect(request.url.queryParameters, {
      'forceFunctionRegion': 'eu-central-1',
    }, reason: 'handled in Frankfurt (Legal N-285)');
    expect(request.headers['Authorization'], 'Bearer $_jwt');
    expect(jsonDecode(request.body), {
      'locale': 'en',
      'category': 'personal_rights',
      'target': {'kind': 'item', 'id': '30000000-0000-4000-8000-000000000003'},
      'location':
          'item "Hafermilch" in list "Wocheneinkauf", household '
          '"Familie Brandt"',
      'reason': 'This item names my neighbour with an insult.',
      'name': 'Mia Brandt',
      'email': 'mia.brandt@example.com',
      'good_faith': true,
      'screenshot': base64Encode(png),
    });
  });

  test('the household, a list and somewhere else; no name, e-mail or '
      'screenshot sends none', () {
    Map<String, Object> body(ReportTarget target) => ReportSubmission(
      locale: 'de',
      category: ReportCategory.other,
      target: target,
      reason: 'Zwanzig Zeichen und mehr.',
    ).body;
    expect(body(const HouseholdTarget(id: 'h1', name: 'Familie Brandt')), {
      'locale': 'de',
      'category': 'other',
      'target': {'kind': 'household', 'id': 'h1'},
      'location': 'household "Familie Brandt"',
      'reason': 'Zwanzig Zeichen und mehr.',
      'good_faith': true,
    });
    expect(
      body(
        const ListTarget(id: 'l1', name: 'Party', household: 'Familie Brandt'),
      ),
      containsPair('location', 'list "Party", household "Familie Brandt"'),
    );
    expect(body(const ElsewhereTarget('  im Haushalt „WG“  ')), {
      'locale': 'de',
      'category': 'other',
      'target': {'kind': 'elsewhere'},
      'location': 'im Haushalt „WG“',
      'reason': 'Zwanzig Zeichen und mehr.',
      'good_faith': true,
    });
  });

  test('every category goes by its wire name', () {
    expect(ReportCategory.values.map((c) => c.wire), [
      'hate',
      'personal_rights',
      'ip',
      'csam',
      'danger',
      'other',
    ]);
  });

  group('failures', () {
    for (final (status, body, matcher) in [
      (429, {'error': 'rate_limited'}, isA<ReportRateLimited>()),
      (503, {'error': 'unavailable'}, isA<ReportRefused>()),
      (400, {'error': 'invalid_request'}, isA<ReportRefused>()),
      (413, {'error': 'too_large'}, isA<ReportScreenshotTooLarge>()),
      (401, {'error': 'invalid_token'}, isA<ReportRefused>()),
    ]) {
      test('$status is a ${matcher.runtimeType}', () async {
        final repo = await signedIn((_) => json(body, status));
        await expectLater(repo.send(report), throwsA(matcher));
      });
    }

    test('an answer without a number is refused', () async {
      final repo = await signedIn((_) => json({'ok': true}, 201));
      await expectLater(repo.send(report), throwsA(isA<ReportRefused>()));
    });

    test('no connection is offline', () async {
      final repo = await signedIn(
        (_) => throw http.ClientException('Failed host lookup'),
      );
      await expectLater(repo.send(report), throwsA(isA<ReportOffline>()));
    });

    test('no answer in time is offline', () async {
      final never = Completer<http.Response>();
      final repo = await signedIn(
        (_) => never.future,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(repo.send(report), throwsA(isA<ReportOffline>()));
    });
  });

  group('who reports', () {
    test("Google's full name and the address", () async {
      final repo = await signedIn(
        (_) => json({}, 200),
        metadata: {'full_name': 'Mia Brandt', 'name': 'Mia'},
      );
      final who = repo.reporter();
      expect(who.name, 'Mia Brandt');
      expect(who.email, 'mia.brandt@example.com');
    });

    test('else the provider name', () async {
      final repo = await signedIn(
        (_) => json({}, 200),
        metadata: {'name': ' Mia B. '},
      );
      expect(repo.reporter().name, 'Mia B.');
    });

    test('no provider name: none, not the address', () async {
      final repo = await signedIn((_) => json({}, 200));
      expect(repo.reporter().name, isNull);
      expect(repo.reporter().email, 'mia.brandt@example.com');
    });

    test('a guest without an address: neither', () async {
      final repo = await signedIn((_) => json({}, 200), email: null);
      expect(repo.reporter().name, isNull);
      expect(repo.reporter().email, isNull);
    });
  });
}
