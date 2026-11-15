import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

const userId = '20000000-0000-4000-8000-000000000002';

/// An unsigned token for [userId]; nothing here checks it.
final _jwt = [
  base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}')),
  base64Url.encode(
    utf8.encode('{"sub":"$userId","exp":4102444800,"role":"authenticated"}'),
  ),
  'x',
].join('.').replaceAll('=', '');

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

  /// [repository] signed in as [userId], as the app only sends then.
  Future<SupabaseFeedbackRepository> signedIn(
    FutureOr<http.Response> Function(http.Request request) answer, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    requests = [];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await answer(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
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
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'created_at': '2026-11-15T12:00:00Z',
        },
      }),
    );
    return SupabaseFeedbackRepository(client, timeout: timeout);
  }

  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
  FeedbackSubmission withShot(Uint8List shot) => FeedbackSubmission(
    id: note.id,
    message: note.message,
    category: note.category,
    contactOk: note.contactOk,
    context: note.context,
    screenshot: shot,
  );
  bool isUpload(http.Request r) => r.url.path.startsWith('/functions/');
  http.Response json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  final stored = '$userId/${note.id}.png';

  test('the function stores the screenshot with the session, then the row '
      'names what it stored', () async {
    final repo = await signedIn(
      (r) => isUpload(r) ? json({'name': stored}, 200) : http.Response('', 201),
    );
    await repo.submit(withShot(png));
    expect(requests, hasLength(2));
    final (upload, insert) = (requests.first, requests.last);
    expect(upload.method, 'POST');
    expect(
      upload.url.path,
      '/functions/v1/feedback-screenshots/upload/${note.id}',
    );
    expect(upload.headers['Authorization'], 'Bearer $_jwt');
    expect(upload.headers['Content-Type'], 'image/png');
    expect(upload.bodyBytes, png);
    expect(insert.url.path, '/rest/v1/feedback');
    expect(jsonDecode(insert.body), containsPair('screenshot', stored));
  });

  test('without a screenshot nothing is uploaded and no column sent', () async {
    final repo = await signedIn((_) => http.Response('', 201));
    await repo.submit(note);
    expect(requests.where(isUpload), isEmpty);
    expect(
      (jsonDecode(requests.single.body) as Map<String, Object?>).keys,
      isNot(contains('screenshot')),
    );
  });

  for (final (status, error) in [
    (403, 'quota'),
    (413, 'too_large'),
    (415, 'not_png'),
  ]) {
    test(
      'a $status ($error) refuses the screenshot and sends no row',
      () async {
        final repo = await signedIn(
          (r) => isUpload(r)
              ? json({'error': error}, status)
              : http.Response('', 201),
        );
        await expectLater(
          repo.submit(withShot(png)),
          throwsA(
            isA<FeedbackScreenshotRefused>().having(
              (e) => e.code,
              'code',
              'upload_$status',
            ),
          ),
        );
        expect(requests.where((r) => !isUpload(r)), isEmpty);
      },
    );
  }

  for (final (status, body) in [
    (500, {'error': 'internal'}),
    (503, {'error': 'storage_failed'}),
    (401, {'msg': 'Invalid JWT'}),
    (403, {'error': 'session_required'}),
  ]) {
    test("a $status is a plain refusal, not the screenshot's, and sends no "
        'row', () async {
      final repo = await signedIn(
        (r) => isUpload(r) ? json(body, status) : http.Response('', 201),
      );
      await expectLater(
        repo.submit(withShot(png)),
        throwsA(
          isA<FeedbackRefused>().having(
            (e) => e.code,
            'code',
            'upload_$status',
          ),
        ),
      );
      expect(requests.where((r) => !isUpload(r)), isEmpty);
    });
  }

  test('a 200 without the name is a refusal and sends no row', () async {
    final repo = await signedIn(
      (r) => isUpload(r) ? json({'ok': true}, 200) : http.Response('', 201),
    );
    await expectLater(
      repo.submit(withShot(png)),
      throwsA(
        isA<FeedbackRefused>().having(
          (e) => e.code,
          'code',
          'upload_bad_response',
        ),
      ),
    );
    expect(requests.where((r) => !isUpload(r)), isEmpty);
  });

  test('an upload without a connection is offline, and sends no row', () async {
    final repo = await signedIn((r) {
      if (isUpload(r)) {
        throw http.ClientException('Failed to fetch');
      }
      return http.Response('', 201);
    });
    await expectLater(
      repo.submit(withShot(png)),
      throwsA(isA<FeedbackOffline>()),
    );
    expect(requests.where((r) => !isUpload(r)), isEmpty);
  });

  test(
    'an upload without an answer in time is offline, and sends no row',
    () async {
      final never = Completer<http.Response>();
      final repo = await signedIn(
        (r) => isUpload(r) ? never.future : http.Response('', 201),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        repo.submit(withShot(png)),
        throwsA(isA<FeedbackOffline>()),
      );
      expect(requests.where((r) => !isUpload(r)), isEmpty);
    },
  );

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
          entryPoint: FeedbackEntryPoint.settings,
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
