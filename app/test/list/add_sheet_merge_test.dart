import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// [ListCubit.mergeTyped]: a match row's tap in the add sheet merges what is
/// typed into the open item it matched.
void main() {
  group('a typed amount merged into the open item from the add sheet', () {
    late FakeRepository repo;
    late ListCubit cubit;
    late List<Rejected> refused;

    Future<void> settle() => pumpEventQueue();

    setUp(() async {
      repo = FakeRepository();
      cubit = ListCubit(
        repo,
        MemoryListCache(),
        userId: 'peter',
        grace: Duration.zero,
      )..start();
      await settle();
      refused = [];
      final sub = cubit.rejections.listen(refused.add);
      addTearDown(sub.cancel);
    });

    tearDown(() => cubit.close());

    test('adds the amounts up and fills only details the item lacks', () async {
      final milch = (cubit.addEntry(parseEntry('2 Milch')) as Added).item.id;
      await settle();
      final merged = cubit.mergeTyped(
        milch,
        const ParsedEntry(
          name: 'Milch',
          quantity: '3',
          brand: 'Weihenstephan',
          properties: 'laktosefrei',
        ),
      );
      expect(merged?.quantity, '5');
      expect(merged?.brand, 'Weihenstephan');
      expect(merged?.properties, 'laktosefrei');
      await settle();
      expect(repo.rows[milch]!.quantity, '5');
      expect(repo.rows[milch]!.brand, 'Weihenstephan');
      expect(
        cubit
            .mergeTyped(milch, const ParsedEntry(name: 'Milch', quantity: '1'))
            ?.properties,
        'laktosefrei',
        reason: 'none typed keeps the details',
      );
      await settle();

      cubit.mergeTyped(
        milch,
        const ParsedEntry(
          name: 'Milch',
          quantity: '1',
          brand: 'Bärenmarke',
          properties: 'bio',
        ),
      );
      await settle();
      expect(repo.rows[milch]!.quantity, '7');
      expect(repo.rows[milch]!.properties, 'laktosefrei');
      expect(
        repo.rows[milch]!.brand,
        'Weihenstephan',
        reason: 'a merge never overwrites what the item has',
      );
      expect(refused, isEmpty);
    });

    test('an item ticked or gone meanwhile is refused and nothing is '
        'sent', () async {
      final brot = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      final eier = (cubit.addEntry(parseEntry('Eier')) as Added).item.id;
      await settle();
      cubit
        ..tick(brot)
        ..delete(eier);
      await settle();
      final sent = repo.sent.length;

      expect(cubit.mergeTyped(brot, const ParsedEntry(name: 'Brot')), isNull);
      expect(cubit.mergeTyped(eier, const ParsedEntry(name: 'Eier')), isNull);
      await settle();
      expect(refused, [isA<MergeRefused>(), isA<MergeRefused>()]);
      expect(
        [for (final r in refused) (r as MergeRefused).name],
        ['Brot', 'Eier'],
      );
      expect(repo.sent, hasLength(sent));
    });

    test('an amount too long to merge is refused and the item keeps '
        'its own', () async {
      final klopapier = (cubit.addEntry(
        const Entry(
          'Klopapier',
          'Großpackung mit vielen '
              'Rollen',
        ),
      ) as Added).item.id;
      await settle();
      expect(
        cubit.mergeTyped(
          klopapier,
          const ParsedEntry(
            name: 'Klopapier',
            quantity: 'Kleinpackung mit vielen Rollen',
          ),
        ),
        isNull,
      );
      await settle();
      expect(refused.single, isA<MergeRefused>());
      expect(repo.rows[klopapier]!.quantity, 'Großpackung mit vielen Rollen');
      expect(cubit.state.pending, isEmpty);
    });
  });
}
