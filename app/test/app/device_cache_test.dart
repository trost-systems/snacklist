import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late DeviceCache cache;
  const home = Household(id: 'home', name: 'Zuhause');
  const work = Household(id: 'work', name: 'Büro');
  final snapshot = ListSnapshot(
    catalog: const Catalog(),
    server: [
      Item(
        id: 'milk',
        name: 'Milch',
        status: ItemStatus.active,
        createdAt: DateTime.utc(2026, 10, 22),
        updatedAt: DateTime.utc(2026, 10, 22),
      ),
    ],
    pending: const [DeleteItem('milk')],
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    cache = DeviceCache(SharedPreferencesAsync());
  });

  test('a list is kept per user and household', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    expect((await cache.household('peter'))?.name, 'Zuhause');
    expect(
      (await cache.list('peter', 'home').load())?.toJson(),
      snapshot.toJson(),
    );
    expect(await cache.list('lea', 'home').load(), isNull);
  });

  test('moving to another household drops the old list', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', work);
    expect(await cache.list('peter', 'home').load(), isNull);

    await cache.list('peter', 'home').save(snapshot);
    expect(
      await cache.list('peter', 'home').load(),
      isNull,
      reason: 'a list closing late cannot write the old household back',
    );
  });

  test('leaving every household drops the lists', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', null);
    expect(await cache.household('peter'), isNull);
    expect(await cache.list('peter', 'home').load(), isNull);
  });

  test('signing out forgets every user', () async {
    await cache.remember('peter', home);
    await cache.remember('lea', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.forget();
    expect(await cache.household('peter'), isNull);
    expect(await cache.household('lea'), isNull);
    expect(await cache.list('peter', 'home').load(), isNull);
    await cache.list('peter', 'home').save(snapshot);
    expect(await cache.list('peter', 'home').load(), isNull);
  });

  group('seen marks', () {
    final mark = SeenMark(
      until: DateTime.utc(2026, 10, 22, 12),
      ids: const {'a'},
    );

    test('are kept per user and household', () async {
      await cache.remember('peter', home);
      expect(await cache.list('peter', 'home').loadSeen(), isNull);
      await cache.list('peter', 'home').saveSeen(mark);
      final back = await cache.list('peter', 'home').loadSeen();
      expect(back?.until, mark.until);
      expect(back?.ids, {'a'});
      expect(await cache.list('lea', 'home').loadSeen(), isNull);
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });

    test('go with the household and on sign-out', () async {
      await cache.remember('peter', home);
      await cache.list('peter', 'home').saveSeen(mark);
      await cache.remember('peter', home);
      expect(
        await cache.list('peter', 'home').loadSeen(),
        isNotNull,
        reason: 'remembering the same household keeps it',
      );
      await cache.remember('peter', work);
      expect(await cache.list('peter', 'home').loadSeen(), isNull);

      await cache.list('peter', 'work').saveSeen(mark);
      await cache.forget();
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });
  });

  test('analytics state is per install and survives sign-outs', () async {
    expect(await cache.installId(), isNull);
    expect(await cache.consent(), isNull);
    expect(await cache.internalInstall(), isFalse);
    await cache.saveInstallId('id-1');
    await cache.saveConsent(granted: false, textVersion: '2026-11-01');
    await cache.saveFirstOpenSentFor('id-1');
    await cache.saveInternalInstall(internal: true);
    await cache.remember('peter', home);
    await cache.forget();
    expect(await cache.installId(), 'id-1');
    expect(await cache.consent(), isFalse);
    expect(await cache.firstOpenSentFor(), 'id-1');
    expect(await cache.internalInstall(), isTrue);

    await cache.forgetInstallId();
    expect(await cache.installId(), isNull);
    expect(await cache.firstOpenSentFor(), isNull);
    expect(await cache.consent(), isFalse, reason: 'the answer stays');
    expect(await cache.consentTextVersion(), '2026-11-01');
    expect(await cache.internalInstall(), isTrue);

    await cache.forgetConsent();
    expect(await cache.consent(), isNull);
    expect(await cache.consentTextVersion(), isNull);
    expect(await cache.internalInstall(), isTrue);
  });

  test('dismissed tips are kept per user and survive sign-outs', () async {
    expect(await cache.dismissedTips('peter'), isEmpty);
    await cache.saveDismissedTips('peter', {'edit-long-press', 'siri'});
    await cache.remember('peter', null);
    await cache.forget();
    expect(await cache.dismissedTips('peter'), {'edit-long-press', 'siri'});
    expect(await cache.dismissedTips('lea'), isEmpty);
  });

  test('unreadable dismissed tips count as none', () async {
    await SharedPreferencesAsync().setString('tips.peter', '{"no": 1}');
    expect(await cache.dismissedTips('peter'), isEmpty);
    await SharedPreferencesAsync().setString('tips.peter', 'not json');
    expect(await cache.dismissedTips('peter'), isEmpty);
  });
}
