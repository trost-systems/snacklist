import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'harness.dart';

void main() {
  var clock = DateTime.utc(2026, 10, 30, 12);
  DateTime now() => clock;

  setUp(() => clock = DateTime.utc(2026, 10, 30, 12));

  test('a link code is kept, normalized, and stored', () async {
    final store = MemoryPendingStore();
    PendingInvite(store, now: now).remember('abcd-2345');
    await pumpEventQueue();
    expect(store.saved, (code: 'ABCD2345', at: clock, via: JoinMethod.link));
  });

  test('a pasted or referred code keeps its way until it is answered', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABCD2345', via: JoinMethod.paste)
      ..remember('ABCD2345');
    expect(pending.methodOf('abcd-2345'), JoinMethod.paste);
    expect(pending.methodOf('WXYZ6789'), JoinMethod.link);
    pending.clear();
    expect(pending.methodOf('ABCD2345'), JoinMethod.link);
  });

  test("a referrer's code lapses 7 days after the store click", () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember(
        'ABCD2345',
        via: JoinMethod.referrer,
        at: clock.subtract(const Duration(days: 8)),
      );
    expect(pending.code, isNull);
  });

  group('a pasted text', () {
    for (final (text, code) in [
      ('https://app.hummlist.com/join/ABCD2345', 'ABCD2345'),
      ('https://app.hummlist.com/join/abcd-2345?x=1', 'ABCD2345'),
      ('https://app.hummlist.com/?invite=WXYZ6789', 'WXYZ6789'),
      ('http://localhost:8080/#/join/WXYZ6789', 'WXYZ6789'),
      ('  ABCD2345\n', 'ABCD2345'),
      ('abcd-2345', 'ABCD2345'),
      ('ABCD 2345', 'ABCD2345'),
      (
        'Komm in unseren Hummlist-Haushalt: '
            'https://app.hummlist.com/join/ABCD2345 · Code: ABCD2345',
        'ABCD2345',
      ),
      ('Komm dazu! Code: ABCD2345', null),
      ('ABCD23456', null),
      ('IIII0000', null),
      ('https://app.hummlist.com/join/ABC', null),
      ('', null),
      ('Milch, Brot, Eier', null),
    ]) {
      test('${text.trim().isEmpty ? '(empty)' : text} -> $code', () {
        expect(inviteCodeIn(text), code);
      });
    }
  });

  group('an install referrer', () {
    for (final (referrer, code) in [
      ('invite=ABCD2345', 'ABCD2345'),
      ('utm_source=join&invite=abcd-2345', 'ABCD2345'),
      ('invite%3DABCD2345', null),
      ('utm_source=google-play&utm_medium=organic', null),
      ('invite=IIII0000', null),
      ('invite=%E0%A4%A', null),
      ('', null),
      (null, null),
    ]) {
      test('$referrer -> $code', () {
        expect(inviteInReferrer(referrer), code);
      });
    }
  });

  test('a code the server could never make is not kept', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABC123')
      ..remember('IIII0000')
      ..remember('');
    expect(pending.code, isNull);
  });

  test('it lasts 7 days, like the invite', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABCD2345');
    clock = clock.add(const Duration(days: 6, hours: 23));
    expect(pending.code, 'ABCD2345');
    clock = clock.add(const Duration(hours: 1));
    expect(pending.code, isNull);
  });

  test('a cold start reads it back (the app was killed meanwhile)', () async {
    final store = MemoryPendingStore();
    PendingInvite(store, now: now).remember('ABCD2345');
    await pumpEventQueue();
    final restarted = await PendingInvite.load(store, now: now);
    expect(restarted.code, 'ABCD2345');
  });

  test('an answered code is not kept again while the router still sees '
      'it', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABCD2345')
      ..clear()
      ..remember('ABCD2345');
    expect(pending.code, isNull);
    // Another link is.
    pending.remember('WXYZ6789');
    expect(pending.code, 'WXYZ6789');
  });

  test('a refused code answers the pending invite only if it is that one', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABCD2345')
      ..refused('ZZZZ2345');
    expect(pending.code, 'ABCD2345');
    pending.refused('abcd-2345');
    expect(pending.code, isNull);
  });

  test('after a sign-out nothing is pending and a link counts again', () {
    final pending = PendingInvite(MemoryPendingStore(), now: now)
      ..remember('ABCD2345')
      ..clear()
      ..signedOut();
    expect(pending.code, isNull);
    pending.remember('ABCD2345');
    expect(pending.code, 'ABCD2345');
    pending.signedOut();
    expect(pending.code, isNull);
  });

  group('DeviceCache', () {
    late DeviceCache cache;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      cache = DeviceCache(SharedPreferencesAsync());
    });

    test('keeps it across a restart', () async {
      final at = DateTime.utc(2026, 10, 30, 12, 5);
      await cache.savePendingInvite((
        code: 'ABCD2345',
        at: at,
        via: JoinMethod.paste,
      ));
      expect(await cache.pendingInvite(), (
        code: 'ABCD2345',
        at: at,
        via: JoinMethod.paste,
      ));
      await cache.savePendingInvite(null);
      expect(await cache.pendingInvite(), isNull);
    });

    test('a signed-out start (which forgets) keeps it', () async {
      final at = DateTime.utc(2026, 10, 30, 12, 5);
      await cache.savePendingInvite((
        code: 'ABCD2345',
        at: at,
        via: JoinMethod.paste,
      ));
      await cache.remember(
        'u',
        households: const [Household(id: 'h', name: 'H')],
      );
      await cache.forget();
      expect(await cache.householdsOf('u'), isNull);
      expect(await cache.pendingInvite(), (
        code: 'ABCD2345',
        at: at,
        via: JoinMethod.paste,
      ));
    });

    test('one kept before the way was stored came from a link', () async {
      await SharedPreferencesAsync().setString(
        'invite.pending',
        '{"code":"ABCD2345","at":"2026-10-30T12:05:00.000Z"}',
      );
      expect((await cache.pendingInvite())?.via, JoinMethod.link);
    });

    test('the install referrer is read once per install', () async {
      expect(await cache.installReferrerRead(), isFalse);
      await cache.saveInstallReferrerRead();
      await cache.forget();
      expect(await cache.installReferrerRead(), isTrue);
    });

    test('an unreadable value counts as none', () async {
      await SharedPreferencesAsync().setString('invite.pending', '{"code":1}');
      expect(await cache.pendingInvite(), isNull);
      await SharedPreferencesAsync().setString('invite.pending', 'nope');
      expect(await cache.pendingInvite(), isNull);
    });
  });
}
