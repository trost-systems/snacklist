import 'dart:ui';

import 'package:family_groceries/session/mail_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth.dart';

User _user(Map<String, dynamic> metadata) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: metadata,
  aud: 'authenticated',
  createdAt: '2026-11-10T00:00:00Z',
);

/// Saves metadata the way GoTrue does: merged into the current user.
class _Auth() extends FakeAuth {
  Exception? error;

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    // Yields, as a network call does, so a second sync can start meanwhile.
    await Future<void>.value();
    if (error case final error?) {
      throw error;
    }
    await super.updateUser(attributes);
    user = _user({
      ...?user?.userMetadata,
      ...attributes.data! as Map<String, Object?>,
    });
    return UserResponse.fromJson({});
  }
}

void main() {
  group('mail language of the app language', () {
    test('German and English are kept', () {
      expect(mailLocaleOf(const Locale('de')), 'de');
      expect(mailLocaleOf(const Locale('en', 'US')), 'en');
    });

    test('anything else is English, as the app is', () {
      expect(mailLocaleOf(const Locale('fr')), 'en');
    });

    test('sign-up data carries it under mail_locale', () {
      expect(mailLocaleData(const Locale('en')), {'mail_locale': 'en'});
    });
  });

  group('sync', () {
    late _Auth auth;
    late MailLanguageSync sync;

    setUp(() {
      auth = _Auth();
      sync = MailLanguageSync(auth);
    });

    test('saves the app language for an account without one', () async {
      auth.user = _user({'full_name': 'Lea'});

      await sync.sync(const Locale('de'));

      expect(auth.metadataUpdates, [
        {'mail_locale': 'de'},
      ]);
      expect(auth.user!.userMetadata, {
        'full_name': 'Lea',
        'mail_locale': 'de',
      });
    });

    test('a language change in the app or on the device is saved', () async {
      auth.user = _user({'mail_locale': 'de'});

      await sync.sync(const Locale('en'));

      expect(auth.user!.userMetadata!['mail_locale'], 'en');
    });

    test('asks nothing when the saved language matches', () async {
      auth.user = _user({'mail_locale': 'en'});

      await sync.sync(const Locale('en', 'GB'));

      expect(auth.metadataUpdates, isEmpty);
    });

    test('asks nothing signed out', () async {
      await sync.sync(const Locale('en'));

      expect(auth.metadataUpdates, isEmpty);
    });

    test('a start and a resume at once save once', () async {
      auth.user = _user({});

      await Future.wait([
        sync.sync(const Locale('en')),
        sync.sync(const Locale('en')),
      ]);

      expect(auth.metadataUpdates, hasLength(1));
    });

    test('a failed save is swallowed and retried next time', () async {
      auth
        ..user = _user({})
        ..error = AuthRetryableFetchException();

      await sync.sync(const Locale('en'));
      auth.error = null;
      await sync.sync(const Locale('en'));

      expect(auth.user!.userMetadata!['mail_locale'], 'en');
    });
  });
}
