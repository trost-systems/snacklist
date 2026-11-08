import 'dart:async';

import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/fake_auth.dart';
import '../session/fake_households.dart';

/// Records what the app sends to an edge function and answers with
/// [answer].
class FakeFunctions() extends Fake implements FunctionsClient {
  final functionNames = <String>[];
  final bodies = <Object?>[];
  FutureOr<Object?> Function() answer = () => const {
    'deleted': true,
    'household': 'kept',
    'apple': 'revoked',
  };

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) async {
    functionNames.add(functionName);
    bodies.add(body);
    return FunctionResponse(data: await answer(), status: 200);
  }
}

class FakeFunctionsClient(final FakeAuth fakeAuth, final FakeFunctions fake)
    extends Fake
    implements SupabaseClient {
  @override
  GoTrueClient get auth => fakeAuth;

  @override
  FunctionsClient get functions => fake;
}

User userWith(List<String> providers) => User(
  id: 'peter',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-22T12:00:00Z',
  identities: [
    for (final provider in providers)
      UserIdentity(
        id: provider,
        userId: 'peter',
        identityData: const {},
        identityId: provider,
        provider: provider,
        createdAt: null,
        lastSignInAt: null,
      ),
  ],
);

void main() {
  group('accountErrorOf', () {
    for (final (error, expected) in <(Object, String)>[
      (
        const FunctionsFetchException(details: 'XMLHttpRequest error'),
        'offline',
      ),
      (ClientException('Failed host lookup'), 'offline'),
      (TimeoutException('slow'), 'offline'),
      (
        const FunctionsHttpException(
          status: 403,
          details: {'error': 'forbidden', 'message': 'no'},
        ),
        'forbidden',
      ),
      (const FunctionsHttpException(status: 502, details: 'Bad'), '502'),
      (const PostgrestException(message: 'denied', code: '42501'), '42501'),
      (StateError('bug'), 'StateError'),
    ]) {
      test('$error is $expected', () {
        expect(switch (accountErrorOf(error)) {
          AccountOffline() => 'offline',
          AccountFailed(:final code) => code,
          AppleReauthCanceled() => 'canceled',
        }, expected);
      });
    }
  });

  test('the fate names each household: kept for others, or deleted '
      '(job 169b)', () async {
    final auth = FakeAuth()..user = userWith(const []);
    addTearDown(auth.close);
    final server = FakeHouseholds(auth)
      ..member('peter', 'home', 'Zuhause')
      ..member('lea', 'home', 'Zuhause')
      ..member('peter', 'club', 'Sommerfest')
      ..unlocked.add('club');
    final fate = await SupabaseAccountRepository(server).fate();
    expect(fate.households, hasLength(2));
    expect(
      fate.households.first,
      isA<FateKept>().having((f) => f.householdName, 'name', 'Zuhause').having(
        (f) => f.otherMemberNames,
        'others',
        ['Lea'],
      ),
    );
    expect(
      fate.households.last,
      isA<FateDeleted>()
          .having((f) => f.householdName, 'name', 'Sommerfest')
          .having((f) => f.unlocked, 'unlocked', isTrue),
    );
    expect(fate.endsPremium, isTrue);
    expect(
      server.calls.where((c) => c.startsWith('household_members')),
      isEmpty,
      reason: 'no direct household_members read',
    );
  });

  test('unknown Apple answers fall back to the manual hint', () {
    expect(AppleUnlink.parse('revoked'), AppleUnlink.revoked);
    expect(AppleUnlink.parse('not_linked'), AppleUnlink.notLinked);
    expect(AppleUnlink.parse('manual'), AppleUnlink.manual);
    expect(AppleUnlink.parse(null), AppleUnlink.manual);
  });

  group('delete', () {
    late FakeAuth auth;
    late FakeFunctions functions;
    var appleCalls = 0;

    setUp(() {
      auth = FakeAuth();
      functions = FakeFunctions();
      appleCalls = 0;
    });
    tearDown(() => auth.close());

    SupabaseAccountRepository repository(
      List<String> providers, {
      AppleAuthorizationCode? apple,
    }) {
      auth.user = userWith(providers);
      return SupabaseAccountRepository(
        FakeFunctionsClient(auth, functions),
        retryDelay: Duration.zero,
        appleCode: apple == null
            ? null
            : () {
                appleCalls++;
                return apple();
              },
      );
    }

    test('an Apple user on iOS sends a fresh authorization code', () async {
      final deleted = await repository([
        'apple',
      ], apple: () async => 'code-1').delete();
      expect(functions.functionNames, ['account/delete']);
      expect(functions.bodies, [
        {'apple_authorization_code': 'code-1'},
      ]);
      expect(deleted.apple, AppleUnlink.revoked);
    });

    test('without an Apple identity Apple is not asked', () async {
      await repository(['google'], apple: () async => 'code-1').delete();
      expect(appleCalls, 0);
      expect(functions.functionNames, ['account/delete']);
      expect(functions.bodies, [<String, Object?>{}]);
    });

    test('without the native dialog no code is sent', () async {
      functions.answer = () => const {
        'deleted': true,
        'household': 'none',
        'apple': 'manual',
      };
      final deleted = await repository(['apple']).delete();
      expect(functions.functionNames, ['account/delete']);
      expect(functions.bodies, [<String, Object?>{}]);
      expect(deleted.apple, AppleUnlink.manual);
    });

    test('a failed re-authorization deletes without a code', () async {
      await repository(['apple'], apple: () async => null).delete();
      expect(functions.functionNames, ['account/delete']);
      expect(functions.bodies, [<String, Object?>{}]);
    });

    test('closing Apple’s sheet deletes nothing', () async {
      final repo = repository([
        'apple',
      ], apple: () async => throw const SocialSignInCanceled());
      await expectLater(repo.delete(), throwsA(isA<AppleReauthCanceled>()));
      expect(functions.functionNames, isEmpty);
    });

    test('an unreachable server is offline', () async {
      functions.answer = () => throw FunctionsFetchException(
        details: ClientException('Connection refused'),
      );
      await expectLater(
        repository(['google']).delete(),
        throwsA(isA<AccountOffline>()),
      );
    });

    test(
      'a call the edge gateway dropped is retried once, then succeeds',
      () async {
        var calls = 0;
        functions.answer = () => calls++ == 0
            ? throw const FunctionsHttpException(status: 503, details: '')
            : const {
                'deleted': true,
                'household': 'kept',
                'apple': 'not_linked',
              };
        final deleted = await repository(['google']).delete();
        expect(functions.functionNames, ['account/delete', 'account/delete']);
        expect(deleted.apple, AppleUnlink.notLinked);
      },
    );

    test('a second dropped call fails without a third try', () async {
      functions.answer = () =>
          throw const FunctionsHttpException(status: 503, details: '');
      await expectLater(
        repository(['google']).delete(),
        throwsA(isA<AccountFailed>().having((e) => e.code, 'code', '503')),
      );
      expect(functions.functionNames, hasLength(2));
    });

    test('an error the handler answered is not retried', () async {
      functions.answer = () => throw const FunctionsHttpException(
        status: 500,
        details: {'error': 'server', 'message': 'x'},
      );
      await expectLater(
        repository(['google']).delete(),
        throwsA(isA<AccountFailed>().having((e) => e.code, 'code', 'server')),
      );
      expect(functions.functionNames, hasLength(1));
    });

    test('an answer without deleted: true is a failure', () async {
      functions.answer = () => const {'error': 'what'};
      await expectLater(
        repository(['google']).delete(),
        throwsA(
          isA<AccountFailed>().having((e) => e.code, 'code', 'bad_response'),
        ),
      );
    });
  });
}
