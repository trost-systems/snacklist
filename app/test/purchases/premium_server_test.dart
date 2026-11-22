import 'dart:convert';

import 'package:family_groceries/purchases/premium_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/fake_auth.dart';
import 'fakes.dart';

/// Signed in as peter; `user_entitlements` answers [rows] to a read of
/// peter's own rows and nothing to anyone else's.
class _Server(final FakeAuth fakeAuth, final List<Map<String, dynamic>> rows)
    extends Fake
    implements SupabaseClient {
  @override
  GoTrueClient get auth => fakeAuth;

  @override
  late final rest = PostgrestClient(
    'http://db.invalid/rest/v1',
    httpClient: MockClient(
      (request) async => Response(
        jsonEncode(
          request.url.path.endsWith('/user_entitlements') &&
                  request.url.queryParameters['user_id'] == 'eq.peter'
              ? rows
              : const <Object?>[],
        ),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    ),
  );
}

void main() {
  late FakeAuth auth;

  setUp(() {
    auth = FakeAuth()
      ..user = const User(
        id: 'peter',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-10-22T12:00:00Z',
      );
    addTearDown(auth.close);
  });

  final now = DateTime.now();
  for (final (name, rows, expected)
      in <(String, List<Map<String, dynamic>>, MyPremium)>[
        ('no rows', const [], MyPremium.none),
        (
          'Lifetime',
          const [
            {
              'kind': 'premium',
              'source': 'purchase',
              'premium_source': 'lifetime',
              'expires_at': null,
              'auto_renew': null,
            },
          ],
          MyPremium.active,
        ),
        ('a beta grant for good', const [lifetimeGrantRow], MyPremium.active),
        ('a renewing yearly plan', [yearlyRow(from: now)], MyPremium.billed),
        (
          'a cancelled yearly plan still running',
          [yearlyRow(from: now, renews: false)],
          MyPremium.active,
        ),
        (
          'an expired yearly plan',
          [yearlyRow(from: now, days: -1)],
          MyPremium.none,
        ),
      ]) {
    test("the account's own premium with $name is ${expected.name}", () async {
      expect(
        await SupabasePremiumServer(_Server(auth, rows)).myPremium(),
        expected,
      );
    });
  }

  test('signed out it cannot be read', () async {
    auth.user = null;
    await expectLater(
      SupabasePremiumServer(_Server(auth, const [])).myPremium(),
      throwsA(anything),
    );
  });
}
