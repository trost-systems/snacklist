import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/install_referrer.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  late MemoryPendingStore store;
  late PendingInvite pending;
  late int reads;

  setUp(() {
    store = MemoryPendingStore();
    pending = PendingInvite(store, now: () => now);
    reads = 0;
  });

  Future<InstallReferrer> Function() answer(String? referrer) => () async {
    reads++;
    return (
      referrer: referrer,
      clickedAt: now.subtract(const Duration(hours: 1)),
    );
  };

  Future<InstallReferrer> Function() fail(Exception error) => () {
    reads++;
    return Future.error(error);
  };

  test('the first start takes the invite, as referrer', () async {
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: answer('utm_source=join&invite=ABCD2345'),
    );
    expect(pending.code, 'ABCD2345');
    expect(pending.methodOf('ABCD2345'), JoinMethod.referrer);
    expect(store.saved?.at, now.subtract(const Duration(hours: 1)));
    expect(store.referrerRead, isTrue);
  });

  test('read once: the next start asks no more', () async {
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: answer('utm_source=google-play'),
    );
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: answer('invite=ABCD2345'),
    );
    expect(reads, 1);
    expect(pending.code, isNull);
  });

  test('not on iOS, the web or desktop', () async {
    await takeInstallReferrer(
      store,
      pending,
      android: false,
      read: answer('invite=ABCD2345'),
    );
    expect(reads, 0);
    expect(store.referrerRead, isFalse);
  });

  test('without Play services: nothing, and read', () async {
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: fail(PlatformException(code: 'SERVICE_UNAVAILABLE')),
    );
    expect(pending.code, isNull);
    expect(store.referrerRead, isTrue);
  });

  test("the store's timeout is tried again on the next start", () async {
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: fail(PlatformException(code: 'TIMEOUT')),
    );
    expect(store.referrerRead, isFalse);
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: answer('invite=WXYZ6789'),
    );
    expect(pending.code, 'WXYZ6789');
  });

  test('a store click older than 7 days has lapsed', () async {
    await takeInstallReferrer(
      store,
      pending,
      android: true,
      read: () async => (
        referrer: 'invite=ABCD2345',
        clickedAt: now.subtract(const Duration(days: 9)),
      ),
    );
    expect(pending.code, isNull);
    expect(store.referrerRead, isTrue);
  });
}
