import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_credentials.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'fake_siri_channel.dart';

/// `create_siri_credential` and the token table, in memory.
class FakeSiriServer() implements SiriServer {
  @override
  String? sessionId = 'session-1';
  final active = <String>{};
  final creates = <String?>[];

  /// The next create fails as a lost answer would.
  var offline = false;

  @override
  Future<bool> isActive(String id) async {
    if (offline) {
      throw const SocketException('offline');
    }
    return active.contains(id);
  }

  @override
  Future<({String id, String token})> create({String? replace}) async {
    if (offline) {
      throw const SocketException('offline');
    }
    creates.add(replace);
    active.remove(replace);
    final id = 'siri-${creates.length}';
    active.add(id);
    return (id: id, token: 'fgp_token${creates.length}');
  }

  @override
  Future<void> revoke(String id) async {
    if (offline) {
      throw const SocketException('offline');
    }
    active.remove(id);
  }
}

class Sessions() extends Cubit<Session> {
  this : super(const SessionLoading());

  void set(Session session) => emit(session);
}

const household = Household(id: 'h1', name: 'Zuhause');
const voiceUrl = 'https://example.supabase.co/functions/v1/voice';

void main() {
  late FakeSiriServer server;
  late FakeSiriChannel channel;
  late Sessions sessions;
  late SiriCredentials credentials;

  setUp(() {
    server = FakeSiriServer();
    channel = FakeSiriChannel();
    sessions = Sessions();
    credentials = SiriCredentials(server, channel, voiceUrl: voiceUrl)
      ..follow(sessions);
  });

  tearDown(() => sessions.close());

  Future<void> go(Session session) async {
    sessions.set(session);
    await pumpEventQueue();
    await credentials.idle;
  }

  test('signing in to a household creates and stores a credential', () async {
    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, [null]);
    expect(
      channel.entry,
      const SiriKeychainEntry(
        id: 'siri-1',
        userId: 'u1',
        sessionId: 'session-1',
      ),
    );
    expect(channel.token, 'fgp_token1');
    expect(channel.voiceUrl, voiceUrl);
  });

  test('a matching, active keychain item is kept', () async {
    channel.entry = const SiriKeychainEntry(
      id: 'old',
      userId: 'u1',
      sessionId: 'session-1',
    );
    server.active.add('old');

    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, isEmpty);
    expect(channel.stores, isEmpty);
  });

  test('a revoked keychain item is replaced', () async {
    channel.entry = const SiriKeychainEntry(
      id: 'old',
      userId: 'u1',
      sessionId: 'session-1',
    );

    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, ['old']);
    expect(channel.entry?.id, 'siri-1');
  });

  test('another session of the same user replaces its credential', () async {
    channel.entry = const SiriKeychainEntry(
      id: 'old',
      userId: 'u1',
      sessionId: 'session-0',
    );
    server.active.add('old');

    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, ['old']);
    expect(server.active, {'siri-1'});
    expect(channel.entry?.sessionId, 'session-1');
  });

  test("another user's keychain item is overwritten, not revoked", () async {
    channel.entry = const SiriKeychainEntry(
      id: 'theirs',
      userId: 'u2',
      sessionId: 'session-0',
    );
    server.active.add('theirs');

    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, [null]);
    expect(channel.entry?.userId, 'u1');
  });

  test('repeated states in the household mint one credential', () async {
    await go(const InHousehold('u1', household, [household]));
    await go(
      const InHousehold('u1', Household(id: 'h1', name: 'Neu'), [
        Household(id: 'h1', name: 'Neu'),
      ]),
    );
    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, [null]);
    expect(channel.stores, hasLength(1));
  });

  test('a lost answer is retried at the next state', () async {
    server.offline = true;
    await go(const InHousehold('u1', household, [household]));
    expect(channel.entry, isNull);

    server.offline = false;
    await go(
      const InHousehold('u1', Household(id: 'h1', name: 'Neu'), [
        Household(id: 'h1', name: 'Neu'),
      ]),
    );
    expect(server.creates, [null]);
    expect(channel.entry?.id, 'siri-1');
  });

  test('signing out clears the keychain and the names', () async {
    await go(const InHousehold('u1', household, [household]));
    await go(const SignedOut());

    expect(channel.entry, isNull);
    expect(channel.token, isNull);
    expect(channel.sentNames.last, isEmpty);
  });

  test("signing out first revokes this iPhone's row", () async {
    await go(const InHousehold('u1', household, [household]));
    expect(server.active, {'siri-1'});

    await credentials.signingOut();
    await go(const SignedOut());

    expect(server.active, isEmpty);
    expect(channel.entry, isNull);
  });

  test('an offline sign-out still clears the keychain', () async {
    await go(const InHousehold('u1', household, [household]));
    server.offline = true;

    await credentials.signingOut();
    await go(const SignedOut());

    expect(server.active, {'siri-1'});
    expect(channel.entry, isNull);
  });

  test('leaving the household clears the keychain', () async {
    await go(const InHousehold('u1', household, [household]));
    await go(const NeedsHousehold('u1'));

    expect(channel.entry, isNull);
  });

  test('a sign-in after a sign-out mints a new credential', () async {
    await go(const InHousehold('u1', household, [household]));
    await go(const SignedOut());
    server.sessionId = 'session-2';
    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, [null, null]);
    expect(channel.entry?.sessionId, 'session-2');
  });

  test('without a session id nothing is created', () async {
    server.sessionId = null;
    await go(const InHousehold('u1', household, [household]));

    expect(server.creates, isEmpty);
  });

  test('without the Swift side nothing is created', () async {
    channel.missing = true;
    await go(const InHousehold('u1', household, [household]));
    channel.missing = false;
    await go(const NeedsHousehold('u1'));

    expect(server.creates, isEmpty);
    expect(channel.clears, 0);
  });

  test('only iOS apps have the channel', () {
    for (final platform in TargetPlatform.values) {
      expect(
        siriChannelFor(web: false, platform: platform) != null,
        platform == TargetPlatform.iOS,
        reason: '$platform',
      );
    }
    expect(siriChannelFor(web: true, platform: TargetPlatform.iOS), isNull);
  });

  group('SupabaseSiriServer', () {
    String jwt(Map<String, Object?> claims) {
      String part(Map<String, Object?> json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      return '${part({'alg': 'HS256'})}.${part(claims)}.c2ln';
    }

    SiriServer serverWith(String? accessToken) => SupabaseSiriServer(
      _SessionClient(
        _SessionAuth(
          accessToken == null
              ? null
              : supabase.Session(
                  accessToken: accessToken,
                  tokenType: 'bearer',
                  user: const supabase.User(
                    id: 'u1',
                    appMetadata: {},
                    userMetadata: {},
                    aud: 'authenticated',
                    createdAt: '2026-10-31T00:00:00Z',
                  ),
                ),
        ),
      ),
    );

    test('reads the session id from the access token', () {
      expect(
        serverWith(jwt({'sub': 'u1', 'session_id': 'abc'})).sessionId,
        'abc',
      );
      expect(serverWith(jwt({'sub': 'u1'})).sessionId, isNull);
      expect(serverWith('not-a-jwt').sessionId, isNull);
      expect(serverWith(null).sessionId, isNull);
    });
  });
}

class _SessionAuth(final supabase.Session? _session)
    extends Fake
    implements supabase.GoTrueClient {
  @override
  supabase.Session? get currentSession => _session;
}

class _SessionClient(final supabase.GoTrueClient _auth)
    extends Fake
    implements supabase.SupabaseClient {
  @override
  supabase.GoTrueClient get auth => _auth;
}
