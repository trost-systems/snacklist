import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

const note = FeedbackSubmission(
  id: '10000000-0000-4000-8000-000000000001',
  message: 'Der Haken reagiert spät.',
  category: FeedbackCategory.bug,
  contactOk: true,
  context: sampleContext,
);

http.Response _error(String code, int status) => http.Response(
  jsonEncode({'code': code, 'message': code, 'details': null, 'hint': null}),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;

  SupabaseFeedbackRepository repository(
    FutureOr<http.Response> Function(int attempt) answer, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    requests = [];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await answer(requests.length);
        // postgrest reads the request back from its response.
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    return SupabaseFeedbackRepository(client, timeout: timeout);
  }

  test('one insert into feedback with the note and its context only', () async {
    await repository((_) => http.Response('', 201)).submit(note);
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/feedback');
    expect(request.headers['Prefer'] ?? '', isNot(contains('representation')));
    expect(jsonDecode(request.body), {
      'id': note.id,
      'message': 'Der Haken reagiert spät.',
      'category': 'bug',
      'contact_ok': true,
      'app_version': '1.2.3',
      'build': '45',
      'platform': 'android',
      'os_version': 'Android 14 (SDK 34)',
      'locale': 'de',
      'screen': 'list',
      'is_internal': false,
    });
  });

  test('the shown household goes along when there is one (job 169b)', () async {
    await repository((_) => http.Response('', 201)).submit(
      FeedbackSubmission(
        id: note.id,
        message: 'x',
        category: null,
        contactOk: false,
        context: const FeedbackContext(
          appVersion: '1.2.3',
          build: '45',
          platform: 'android',
          osVersion: 'Android 14 (SDK 34)',
          locale: 'de',
          screen: 'list',
          isInternal: false,
          householdId: 'club',
        ),
      ),
    );
    expect(
      jsonDecode(requests.single.body),
      containsPair('household_id', 'club'),
    );
  });

  test('no category is null', () async {
    await repository((_) => http.Response('', 201)).submit(
      FeedbackSubmission(
        id: note.id,
        message: 'x',
        category: null,
        contactOk: false,
        context: sampleContext,
      ),
    );
    expect(jsonDecode(requests.single.body), containsPair('category', null));
  });

  test('a duplicate (a send still being written) is tried once more', () async {
    await repository(
      (attempt) => attempt == 1 ? _error('23505', 409) : http.Response('', 201),
    ).submit(note);
    expect(requests, hasLength(2));
    expect(
      (jsonDecode(requests.last.body) as Map<String, Object?>)['id'],
      note.id,
      reason: 'same id',
    );
  });

  test("a duplicate twice is someone else's id", () async {
    final repo = repository((_) => _error('23505', 409));
    await expectLater(repo.submit(note), throwsA(isA<FeedbackIdTaken>()));
    expect(requests, hasLength(2));
  });

  test('a refusal names the code', () async {
    final repo = repository((_) => _error('23514', 400));
    await expectLater(
      repo.submit(note),
      throwsA(isA<FeedbackRefused>().having((e) => e.code, 'code', '23514')),
    );
  });

  test('no connection is offline', () async {
    final repo = repository(
      (_) => throw http.ClientException('Failed to fetch'),
    );
    await expectLater(repo.submit(note), throwsA(isA<FeedbackOffline>()));
  });

  test('no answer in time is offline', () async {
    final never = Completer<http.Response>();
    final repo = repository(
      (_) => never.future,
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(repo.submit(note), throwsA(isA<FeedbackOffline>()));
  });
}
