import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/your_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'fake_your_name.dart';

void main() {
  group('normalizeDisplayName', () {
    const cases = {
      'Lea': 'Lea',
      '  Lea   🌻 ': 'Lea 🌻',
      'Lea\tMaria\n\nBrandt': 'Lea Maria Brandt',
      'Lea\u0000Brandt': 'Lea Brandt',
      '   ': '',
      '': '',
    };
    for (final MapEntry(key: raw, value: stored) in cases.entries) {
      test('${Uri.encodeComponent(raw)} is stored as "$stored"', () {
        expect(normalizeDisplayName(raw), stored);
      });
    }
  });

  group('validDisplayName', () {
    test('1 to 80 characters once normalized', () {
      expect(validDisplayName('L'), isTrue);
      expect(validDisplayName('x' * 80), isTrue);
      expect(validDisplayName('x' * 81), isFalse);
      expect(validDisplayName(''), isFalse);
      expect(validDisplayName(' \t\n '), isFalse);
      // Spaces around the name do not count.
      expect(validDisplayName('  ${'x' * 80}  '), isTrue);
    });

    test('an emoji counts as one character, as Postgres counts it', () {
      // 🌻 is two UTF-16 units: 80 sunflowers are 160 of them.
      expect(validDisplayName('🌻' * 80), isTrue);
      expect(validDisplayName('🌻' * 81), isFalse);
    });
  });

  group('asksName', () {
    const home = Household(id: 'h', name: 'Zuhause');
    const member = InHousehold('lea', home, [home]);
    const newcomer = NeedsHousehold('lea');
    NameRead read({
      String userId = 'lea',
      bool chosen = false,
      bool fromEmail = false,
      bool postponed = false,
    }) => NameRead(
      userId,
      'Lea',
      chosen: chosen,
      fromEmail: fromEmail,
      postponed: postponed,
    );
    final cases = <(String, Session, YourName, bool)>[
      ('a newcomer while unread', newcomer, const NameUnread(), true),
      (
        'a newcomer after a failed read',
        newcomer,
        const NameUnread(failed: true),
        true,
      ),
      ('a newcomer with a Google name', newcomer, read(), true),
      ('a newcomer from e-mail', newcomer, read(fromEmail: true), true),
      ('a newcomer who postponed', newcomer, read(postponed: true), true),
      ('a newcomer who chose', newcomer, read(chosen: true), false),
      ('a newcomer, another user read', newcomer, read(userId: 'x'), true),
      (
        'a newcomer, another user chose',
        newcomer,
        read(userId: 'x', chosen: true),
        true,
      ),
      ('a member while unread', member, const NameUnread(), false),
      ('a member with a Google name', member, read(), false),
      ('a member from e-mail', member, read(fromEmail: true), true),
      (
        'a member from e-mail who postponed',
        member,
        read(fromEmail: true, postponed: true),
        false,
      ),
      (
        'a member from e-mail, another user read',
        member,
        read(userId: 'x', fromEmail: true),
        false,
      ),
      ('a member who chose', member, read(chosen: true), false),
      ('signed out', const SignedOut(), read(fromEmail: true), false),
      ('loading', const SessionLoading(), const NameUnread(), false),
    ];
    for (final (what, session, name, asks) in cases) {
      test('$what: ${asks ? 'asks' : 'does not ask'}', () {
        expect(asksName(session, name), asks);
      });
    }
  });

  group('YourNameCubit', () {
    late StreamController<AuthState> auth;
    late FakeNameRepository server;
    late MemoryPostponements device;

    setUp(() {
      auth = StreamController<AuthState>.broadcast();
      server = FakeNameRepository();
      device = MemoryPostponements();
    });
    tearDown(() => auth.close());

    YourNameCubit started() => YourNameCubit(server, device, auth.stream);

    test('reads the name of whoever signs in', () {
      fakeAsync((async) {
        final cubit = started();
        expect(cubit.state, const TypeMatcher<NameUnread>());
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        expect(
          cubit.state,
          isA<NameRead>()
              .having((n) => n.userId, 'userId', 'lea')
              .having((n) => n.name, 'name', 'Lea Brandt')
              .having((n) => n.chosen, 'chosen', false)
              .having((n) => n.fromEmail, 'fromEmail', false),
        );
        auth.add(const AuthState(AuthChangeEvent.signedOut, null));
        async.flushMicrotasks();
        expect(cubit.state, isA<NameUnread>());
        unawaited(cubit.close());
      });
    });

    test("reads again when the account changes: Apple's name comes late", () {
      fakeAsync((async) {
        final cubit = started();
        server.row = (name: 'x7k2pq9mzd', chosen: false, fromEmail: true);
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        expect((cubit.state as NameRead).fromEmail, isTrue);
        auth.add(signedInAs('lea', event: AuthChangeEvent.tokenRefreshed));
        async.flushMicrotasks();
        expect(server.reads, 1, reason: 'a token refresh reads nothing');
        server.row = (name: 'Lea Brandt', chosen: false, fromEmail: false);
        auth.add(signedInAs('lea', event: AuthChangeEvent.userUpdated));
        async.flushMicrotasks();
        expect((cubit.state as NameRead).name, 'Lea Brandt');
        unawaited(cubit.close());
      });
    });

    test('a failed read can be retried, and is on the next auth event', () {
      fakeAsync((async) {
        final cubit = started();
        server.readError = Exception('offline');
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        expect(cubit.state, unread(failed: true));
        server.readError = null;
        unawaited(cubit.retry());
        async.flushMicrotasks();
        expect(cubit.state, isA<NameRead>());

        server.readError = Exception('offline');
        auth.add(signedInAs('peter'));
        async.flushMicrotasks();
        expect(cubit.state, unread(failed: true));
        server.readError = null;
        auth.add(signedInAs('peter', event: AuthChangeEvent.tokenRefreshed));
        async.flushMicrotasks();
        expect(cubit.state, isA<NameRead>());
        unawaited(cubit.close());
      });
    });

    test('a read for a user who signed out meanwhile is dropped', () {
      fakeAsync((async) {
        final cubit = started();
        auth
          ..add(signedInAs('lea'))
          ..add(const AuthState(AuthChangeEvent.signedOut, null));
        async.flushMicrotasks();
        expect(cubit.state, isA<NameUnread>());
        unawaited(cubit.close());
      });
    });

    test('save sends the normalized name and shows it chosen', () {
      fakeAsync((async) {
        final cubit = started();
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        unawaited(cubit.save('  Lea   🌻 '));
        async.flushMicrotasks();
        expect(server.saved, ['Lea 🌻']);
        expect(
          cubit.state,
          isA<NameRead>()
              .having((n) => n.name, 'name', 'Lea 🌻')
              .having((n) => n.chosen, 'chosen', true)
              .having((n) => n.fromEmail, 'fromEmail', false),
        );
        unawaited(cubit.close());
      });
    });

    test('a refused save throws and changes nothing', () {
      fakeAsync((async) {
        final cubit = started();
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        final before = cubit.state;
        server.saveError = const NameOffline();
        Object? thrown;
        unawaited(cubit.save('Lea').catchError((Object e) => thrown = e));
        async.flushMicrotasks();
        expect(thrown, isA<NameOffline>());
        expect(cubit.state, same(before));
        unawaited(cubit.close());
      });
    });

    test('postpone is kept on the device for that user', () {
      fakeAsync((async) {
        final cubit = started();
        server.row = (name: 'lea.brandt87', chosen: false, fromEmail: true);
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        unawaited(cubit.postpone());
        async.flushMicrotasks();
        expect((cubit.state as NameRead).postponed, isTrue);
        expect(device.postponed, {'lea'});
        unawaited(cubit.close());

        // The next start reads it back.
        final again = YourNameCubit(server, device, auth.stream);
        auth.add(signedInAs('lea'));
        async.flushMicrotasks();
        expect((again.state as NameRead).postponed, isTrue);
        unawaited(again.close());
      });
    });
  });
}

Matcher unread({bool failed = false}) =>
    isA<NameUnread>().having((n) => n.failed, 'failed', failed);
