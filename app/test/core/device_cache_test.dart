import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/list/catalog/catalog_loader.dart';
import 'package:family_groceries/list/item_icons_remote.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/usage_log.dart';
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
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.list('peter', 'home').save(snapshot);
    expect(
      (await cache.householdsOf('peter'))?.households.single.name,
      'Zuhause',
    );
    expect(
      (await cache.list('peter', 'home').load())?.toJson(),
      snapshot.toJson(),
    );
    expect(await cache.list('lea', 'home').load(), isNull);
  });

  test('a later save replaces the list, changed rows included', () async {
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.list('peter', 'home').save(snapshot);
    final ticked = ListSnapshot(
      catalog: const Catalog(),
      server: [
        snapshot.server.single.copyWith(status: ItemStatus.bought),
        Item(
          id: 'bread',
          name: 'Brot',
          status: ItemStatus.active,
          createdAt: DateTime.utc(2026, 10, 23),
          updatedAt: DateTime.utc(2026, 10, 23),
        ),
      ],
      pending: const [],
    );
    await cache.list('peter', 'home').save(ticked);
    final back = await cache.list('peter', 'home').load();
    expect(back?.toJson(), ticked.toJson());
    expect(back?.server.first.status, ItemStatus.bought);
  });

  test('a save that is skipped does not encode the list', () async {
    await cache.remember('peter', households: [home], shown: home.id);
    final counted = _CountedSnapshot(
      catalog: snapshot.catalog,
      server: snapshot.server,
      pending: snapshot.pending,
    );
    _encodes = 0;
    await cache.list('peter', 'work').save(counted);
    expect(await cache.list('peter', 'work').load(), isNull);
    expect(_encodes, 0);
    await cache.list('peter', 'home').save(counted);
    expect(_encodes, 1);
  });

  test('each household keeps its list across switches (job 169b)', () async {
    await cache.remember('peter', households: [home, work], shown: 'home');
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', households: [home, work], shown: 'work');
    final back = await cache.householdsOf('peter');
    expect(back?.shown, 'work');
    expect([for (final h in back!.households) h.name], ['Zuhause', 'Büro']);
    expect(
      (await cache.list('peter', 'home').load())?.toJson(),
      snapshot.toJson(),
    );
    await cache.list('peter', 'home').save(snapshot);
    expect(
      await cache.list('peter', 'home').load(),
      isNotNull,
      reason: 'a list switched away from still saves its state',
    );
  });

  test('a household left drops its list only', () async {
    await cache.remember('peter', households: [home, work], shown: 'home');
    await cache.list('peter', 'home').save(snapshot);
    await cache.list('peter', 'work').save(snapshot);
    await cache.remember('peter', households: [work], shown: 'work');
    expect(await cache.list('peter', 'home').load(), isNull);
    expect(await cache.list('peter', 'work').load(), isNotNull);

    await cache.list('peter', 'home').save(snapshot);
    expect(
      await cache.list('peter', 'home').load(),
      isNull,
      reason: 'a list closing late cannot write the left household back',
    );
  });

  test('the defaults and counts survive a restart', () async {
    const club = Household(
      id: 'club',
      name: 'Sommerfest',
      isDefault: true,
      memberCount: 12,
    );
    await cache.remember('peter', households: [home, club], shown: 'home');
    final back = (await cache.householdsOf('peter'))!.households.last;
    expect(back.isDefault, isTrue);
    expect(back.memberCount, 12);
  });

  test("a cache from before job 169b is the user's one household", () async {
    await SharedPreferencesAsync().setString(
      'household.peter',
      '{"id":"home","name":"Zuhause"}',
    );
    final back = await cache.householdsOf('peter');
    expect(back?.shown, 'home');
    expect(back?.households.single.name, 'Zuhause');
  });

  test('leaving every household drops the lists', () async {
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', households: const []);
    expect(await cache.householdsOf('peter'), isNull);
    expect(await cache.list('peter', 'home').load(), isNull);
  });

  test("signing out forgets each user's trip (job 234)", () async {
    await cache.saveKeptTrips('peter', '{"running":null}');
    await cache.saveKeptTrips('lea', '{"running":null}');
    expect(await cache.keptTrips('peter'), '{"running":null}');
    await cache.forget();
    expect(await cache.keptTrips('peter'), isNull);
    expect(await cache.keptTrips('lea'), isNull);
  });

  test('signing out forgets every user', () async {
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.remember('lea', households: [home], shown: home.id);
    await cache.list('peter', 'home').save(snapshot);
    await cache.forget();
    expect(await cache.householdsOf('peter'), isNull);
    expect(await cache.householdsOf('lea'), isNull);
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
      await cache.remember('peter', households: [home], shown: home.id);
      expect(await cache.list('peter', 'home').loadSeen(), isNull);
      await cache.list('peter', 'home').saveSeen(mark);
      final back = await cache.list('peter', 'home').loadSeen();
      expect(back?.until, mark.until);
      expect(back?.ids, {'a'});
      expect(await cache.list('lea', 'home').loadSeen(), isNull);
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });

    test('go with the household and on sign-out', () async {
      await cache.remember('peter', households: [home], shown: home.id);
      await cache.list('peter', 'home').saveSeen(mark);
      await cache.remember('peter', households: [home], shown: home.id);
      expect(
        await cache.list('peter', 'home').loadSeen(),
        isNotNull,
        reason: 'remembering the same household keeps it',
      );
      await cache.remember('peter', households: [work], shown: work.id);
      expect(
        await cache.list('peter', 'home').loadSeen(),
        isNull,
        reason: 'a household left takes its marks',
      );

      await cache.list('peter', 'work').saveSeen(mark);
      await cache.forget();
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });
  });

  test('list prefs are kept per user and household', () async {
    const prefs = ListPrefs(
      folded: {'s1', noStoreKey},
      hintDismissed: true,
      shownList: 'l2',
    );
    await cache.remember('peter', households: [home], shown: home.id);
    expect(await cache.list('peter', 'home').loadPrefs(), isNull);
    await cache.list('peter', 'home').savePrefs(prefs);
    expect(
      (await cache.list('peter', 'home').loadPrefs())?.toJson(),
      prefs.toJson(),
    );
    expect(await cache.list('lea', 'home').loadPrefs(), isNull);
    await cache.list('peter', 'work').savePrefs(prefs);
    expect(
      await cache.list('peter', 'work').loadPrefs(),
      isNull,
      reason: 'not a household of the user',
    );
  });

  test('analytics state is per install and survives sign-outs', () async {
    expect(await cache.installId(), isNull);
    expect(await cache.consent(), isNull);
    await cache.saveInstallId('id-1');
    await cache.saveConsent(granted: false, textVersion: '2026-11-01');
    await cache.saveFirstOpenSentFor('id-1');
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.forget();
    expect(await cache.installId(), 'id-1');
    expect(await cache.consent(), isFalse);
    expect(await cache.firstOpenSentFor(), 'id-1');

    await cache.forgetInstallId();
    expect(await cache.installId(), isNull);
    expect(await cache.firstOpenSentFor(), isNull);
    expect(await cache.consent(), isFalse, reason: 'the answer stays');
    expect(await cache.consentTextVersion(), '2026-11-01');

    await cache.forgetConsent();
    expect(await cache.consent(), isNull);
    expect(await cache.consentTextVersion(), isNull);
  });

  test('the internal-install mark of older builds is deleted', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool('analytics.internal', true);
    await cache.forgetInternalInstallMark();
    expect(await prefs.containsKey('analytics.internal'), isFalse);
  });

  test("the tester groups are one user's, until forgotten", () async {
    expect(await cache.testerGroups('peter'), isNull);
    await cache.saveTesterGroups('peter', {'internal', 'beta-de'});
    expect(await cache.testerGroups('peter'), {'beta-de', 'internal'});
    expect(await cache.testerGroups('lea'), isNull, reason: 'not hers');
    await cache.saveTesterGroups('lea', {});
    expect(await cache.testerGroups('lea'), isEmpty);
    expect(await cache.testerGroups('peter'), isNull, reason: 'replaced');
    await cache.forgetTesterGroups();
    expect(await cache.testerGroups('lea'), isNull);
  });

  test('the shared flags are kept across sign-outs and the deletion of the '
      'install id; a corrupt value reads as none', () async {
    expect(await cache.sharedFlags(), isEmpty);
    await cache.saveSharedFlags({'grocery-log': true, 'trip-mode': false});
    await cache.remember('peter', households: [home], shown: home.id);
    await cache.forget();
    await cache.forgetInstallId();
    expect(await cache.sharedFlags(), {
      'grocery-log': true,
      'trip-mode': false,
    });

    final prefs = SharedPreferencesAsync();
    await prefs.setString('analytics.shared_flags', '{"a": true, "b": 1}');
    expect(await cache.sharedFlags(), {'a': true});
    for (final corrupt in ['[true]', 'not json', '"x"']) {
      await prefs.setString('analytics.shared_flags', corrupt);
      expect(await cache.sharedFlags(), isEmpty, reason: corrupt);
    }
  });

  test('the hint log is kept per user and survives sign-outs', () async {
    expect(await cache.hintLog('peter'), isNull);
    await cache.saveHintLog('peter', '{"active_days": 2}');
    await cache.remember('peter', households: const []);
    await cache.forget();
    expect(await cache.hintLog('peter'), '{"active_days": 2}');
    expect(await cache.hintLog('lea'), isNull);
  });

  test('told removals are kept per user and survive sign-outs', () async {
    expect(await cache.toldRemovals('peter'), isEmpty);
    await cache.rememberToldRemovals('peter', {'club 2026-11-10T19:00:01Z'});
    await cache.forget();
    expect(await cache.toldRemovals('peter'), {'club 2026-11-10T19:00:01Z'});
    expect(await cache.toldRemovals('lea'), isEmpty);
    await cache.rememberToldRemovals('peter', {});
    expect(await cache.toldRemovals('peter'), isEmpty);
  });

  test(
    'a postponed name step is kept per user and survives sign-outs',
    () async {
      expect(await cache.postponedNameFor('lea'), isFalse);
      await cache.savePostponedName('lea');
      await cache.forget();
      expect(await cache.postponedNameFor('lea'), isTrue);
      expect(await cache.postponedNameFor('peter'), isFalse);
    },
  );

  test("job 80's dismissed tips come back as the hint log's", () async {
    await SharedPreferencesAsync().setString(
      'tips.peter',
      '["edit-long-press"]',
    );
    expect(
      UsageLog.parse(
        await cache.hintLog('peter'),
        now: DateTime(2026),
      ).of(HintId.editLongPress).dismissed,
      isTrue,
    );
    await cache.saveHintLog('peter', '{"active_days": 2}');
    expect(await cache.hintLog('peter'), '{"active_days": 2}');
  });

  test('unreadable dismissed tips count as none', () async {
    await SharedPreferencesAsync().setString('tips.peter', '{"no": 1}');
    expect(await cache.hintLog('peter'), isNull);
    await SharedPreferencesAsync().setString('tips.peter', 'not json');
    expect(await cache.hintLog('peter'), isNull);
  });

  test(
    'the item icon table is kept per device and survives sign-outs',
    () async {
      expect(await cache.cachedItemIcons(), isNull);
      final checkedAt = DateTime.utc(2026, 11, 6, 8, 30);
      await cache.saveCachedItemIcons(
        CachedItemIcons(
          checkedAt: checkedAt,
          body: '{"schema":1}',
          etag: '"a"',
        ),
      );
      await cache.remember('peter', households: const []);
      await cache.forget();
      final cached = await cache.cachedItemIcons();
      expect(cached?.checkedAt, checkedAt);
      expect(cached?.body, '{"schema":1}');
      expect(cached?.etag, '"a"');

      await cache.saveCachedItemIcons(CachedItemIcons(checkedAt: checkedAt));
      expect((await cache.cachedItemIcons())?.body, isNull);
    },
  );

  test('an unreadable item icon cache counts as none', () async {
    await SharedPreferencesAsync().setString('itemicons.cache', '{"body": 1}');
    expect(await cache.cachedItemIcons(), isNull);
    await SharedPreferencesAsync().setString('itemicons.cache', 'not json');
    expect(await cache.cachedItemIcons(), isNull);
  });

  test('the catalog check is kept per device and survives sign-outs', () async {
    expect(await cache.cachedCatalogDelta(), isNull);
    final checkedAt = DateTime.utc(2026, 11, 16, 8);
    await cache.saveCachedCatalogDelta(
      CachedCatalogDelta(
        checkedAt: checkedAt,
        base: '0123456789abcdef',
        body: '{"full":false}',
      ),
    );
    await cache.remember('peter', households: const []);
    await cache.forget();
    final cached = await cache.cachedCatalogDelta();
    expect(cached?.checkedAt, checkedAt);
    expect(cached?.base, '0123456789abcdef');
    expect(cached?.body, '{"full":false}');

    await SharedPreferencesAsync().setString('catalog.delta', '{"base": 1}');
    expect(await cache.cachedCatalogDelta(), isNull);
  });

  test('the rating prompt counters survive sign-outs', () async {
    expect(await cache.reviewState(), isNull);
    await cache.saveReviewState('{"items_added":3}');
    await cache.remember('peter', households: const []);
    await cache.forget();
    expect(await cache.reviewState(), '{"items_added":3}');
  });
}

var _encodes = 0;

class const _CountedSnapshot({
  required super.catalog,
  required super.server,
  required super.pending,
}) extends ListSnapshot {
  @override
  String encode() {
    _encodes++;
    return super.encode();
  }
}
