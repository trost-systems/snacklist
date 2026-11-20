import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

const lidlPlus = RetailerApp(
  name: 'Lidl Plus',
  android: 'com.lidl.eci.lidlplus',
  ios: '1238611143',
);
const billaApp = RetailerApp(name: 'BILLA', android: 'at.billa', ios: '1');
const joe = RetailerApp(name: 'jö', android: 'at.joe', ios: '2');
const lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [lidlPlus],
);
const aldiNord = Retailer(
  chain: 'aldi-nord',
  country: 'DE',
  name: 'ALDI Nord',
  apps: [
    RetailerApp(name: 'ALDI Nord', android: 'de.aldiNord.android', ios: '3'),
  ],
);
const aldiSued = Retailer(
  chain: 'aldi-sued',
  country: 'DE',
  name: 'ALDI SÜD',
  apps: [RetailerApp(name: 'ALDI SÜD', android: 'de.aldi_de', ios: '4')],
);
const hofer = Retailer(
  chain: 'aldi-sued',
  country: 'AT',
  name: 'HOFER',
  apps: [RetailerApp(name: 'HOFER', android: 'de.aldi_at', ios: '5')],
);
const billa = Retailer(
  chain: 'billa',
  country: 'AT',
  name: 'BILLA',
  apps: [billaApp, joe],
);
const dino = Retailer(chain: 'dino', country: 'PL', name: 'Dino');

/// Job 313 (SS): linking the household's stores to chains.
void main() {
  late FakeRepository repo;
  late ListCubit cubit;
  var region = 'DE';

  Future<void> settle() => pumpEventQueue();

  setUp(() async {
    region = 'DE';
    repo = FakeRepository()
      ..retailers = const [lidl, aldiNord, aldiSued, hofer, billa, dino]
      ..aliases = const {
        (chain: 'aldi-nord', country: 'DE'): ['aldi'],
        (chain: 'aldi-sued', country: 'DE'): ['aldi', 'aldi süd'],
        (chain: 'aldi-sued', country: 'AT'): ['hofer'],
      };
    cubit = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      grace: Duration.zero,
      region: () => region,
    )..start();
    await settle();
  });

  tearDown(() => cubit.close());

  Store store(String id) => cubit.state.catalog.store(id)!;

  test('matches ask for the phone region, read when asked', () async {
    expect(
      [for (final m in await cubit.matchRetailers('Hofer')) m.retailer.key],
      [(chain: 'aldi-sued', country: 'AT')],
    );
    region = 'AT';
    await cubit.matchRetailers('Billa');
    expect(repo.retailerCountries, ['DE', 'AT']);
  });

  test('fewer than two letters ask nothing', () async {
    expect(await cubit.matchRetailers(' L '), isEmpty);
    expect(repo.retailerCountries, isEmpty);
  });

  test('offline, matching answers none instead of failing', () async {
    repo.online = false;
    expect(await cubit.matchRetailers('Lidl'), isEmpty);
  });

  test(
    "the picker lists the region's chains first, each part by name",
    () async {
      region = 'AT';
      expect(
        [for (final r in await cubit.listRetailers()) '${r.name} ${r.country}'],
        [
          'BILLA AT',
          'HOFER AT',
          'ALDI Nord DE',
          'ALDI SÜD DE',
          'Dino PL',
          'Lidl DE',
        ],
      );
      expect(
        [for (final r in await cubit.listRetailers(country: 'DE')) r.name],
        ['ALDI Nord', 'ALDI SÜD', 'Lidl'],
      );
    },
  );

  test('linking shows at once and stays after the reload', () async {
    final saved = cubit.linkStore('lidl', lidl);
    expect(store('lidl').retailer?.key, lidl.key);
    expect(store('lidl').retailerAnswered, isTrue);
    expect(await saved, isTrue);
    await settle();
    expect(repo.catalogCalls, ['answerStoreRetailer(lidl, lidl, DE, null)']);
    expect(store('lidl').app, lidlPlus);
  });

  test('the picked app is kept per store; the default without one', () async {
    repo.stores = [
      ...repo.stores,
      const Store(id: 'b', name: 'Billa', sortOrder: 30),
    ];
    await cubit.resync();
    await cubit.linkStore('b', billa);
    expect(store('b').app, billaApp);
    expect(await cubit.setStoreApp('b', 'at.joe'), isTrue);
    expect(store('b').app, joe);
    await settle();
    expect(repo.catalogCalls.last, 'answerStoreRetailer(b, billa, AT, at.joe)');
    expect(store('b').retailerApp, 'at.joe');
  });

  test("an app that is not the chain's is refused and undone", () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    await cubit.linkStore('lidl', lidl);
    expect(await cubit.setStoreApp('lidl', 'at.joe'), isFalse);
    await settle();
    expect(store('lidl').retailerApp, isNull);
    expect(store('lidl').app, lidlPlus);
    expect(rejections, [isA<CatalogRejected>()]);
    await sub.cancel();
  });

  test('a store without a chain gets no app', () async {
    expect(await cubit.setStoreApp('dm', 'at.joe'), isFalse);
    expect(repo.catalogCalls, isEmpty);
  });

  test('no unlinks the store and is never asked again', () async {
    await cubit.linkStore('lidl', lidl);
    expect(await cubit.declineStore('lidl'), isTrue);
    await settle();
    expect(store('lidl').retailer, isNull);
    expect(store('lidl').retailerAnswered, isTrue);
    expect(await cubit.retailerQuestions(), isEmpty);
  });

  test('offline, linking and no are refused and change nothing', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.online = false;
    await cubit.resync();
    expect(await cubit.linkStore('lidl', lidl), isFalse);
    expect(await cubit.declineStore('lidl'), isFalse);
    expect(store('lidl').retailer, isNull);
    expect(store('lidl').retailerAnswered, isFalse);
    expect(rejections, [
      isA<StoreNeedsConnection>(),
      isA<StoreNeedsConnection>(),
    ]);
    await sub.cancel();
  });

  test('questions: unlinked, unanswered stores whose chain has an app, all '
      'chains of a shared name', () async {
    repo.stores = [
      ...repo.stores,
      const Store(id: 'a', name: 'Aldi', sortOrder: 30),
      const Store(id: 'd', name: 'Dino', sortOrder: 40),
    ];
    await cubit.resync();
    expect(
      [
        for (final q in await cubit.retailerQuestions())
          '${q.storeId}: ${[for (final c in q.chains) c.chain].join(', ')}',
      ],
      ['lidl: lidl', 'a: aldi-nord, aldi-sued'],
    );
  });

  test('a question answered on this device is not asked again before the '
      'server knows', () async {
    repo.online = false;
    await cubit.resync();
    repo.online = true;
    cubit.emit(
      cubit.state.copyWith(
        catalog: cubit.state.catalog.withStoreRetailer('lidl', null),
      ),
    );
    expect(await cubit.retailerQuestions(), isEmpty);
  });

  test('a store created from a picked chain comes back linked', () async {
    final created = await cubit.addStore('Lid', retailer: lidl);
    expect(created?.retailer?.key, lidl.key);
    await settle();
    expect(repo.catalogCalls, [
      'addStore(Lid)',
      'answerStoreRetailer(new-Lid, lidl, DE, null)',
    ]);
    expect(store('new-Lid').retailer?.key, lidl.key);
  });

  test(
    'picking a chain for a name the household has links that store',
    () async {
      final picked = await cubit.addStore('lidl', retailer: lidl);
      expect(picked?.id, 'lidl');
      expect(picked?.retailer?.key, lidl.key);
      expect(repo.catalogCalls, ['answerStoreRetailer(lidl, lidl, DE, null)']);
    },
  );
}
