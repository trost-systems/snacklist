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
    expect(store.saved, (code: 'ABCD2345', at: clock));
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
      await cache.savePendingInvite((code: 'ABCD2345', at: at));
      expect(await cache.pendingInvite(), (code: 'ABCD2345', at: at));
      await cache.savePendingInvite(null);
      expect(await cache.pendingInvite(), isNull);
    });

    test('a signed-out start (which forgets) keeps it', () async {
      final at = DateTime.utc(2026, 10, 30, 12, 5);
      await cache.savePendingInvite((code: 'ABCD2345', at: at));
      await cache.remember(
        'u',
        households: const [Household(id: 'h', name: 'H')],
      );
      await cache.forget();
      expect(await cache.householdsOf('u'), isNull);
      expect(await cache.pendingInvite(), (code: 'ABCD2345', at: at));
    });

    test('an unreadable value counts as none', () async {
      await SharedPreferencesAsync().setString('invite.pending', '{"code":1}');
      expect(await cache.pendingInvite(), isNull);
      await SharedPreferencesAsync().setString('invite.pending', 'nope');
      expect(await cache.pendingInvite(), isNull);
    });
  });
}
