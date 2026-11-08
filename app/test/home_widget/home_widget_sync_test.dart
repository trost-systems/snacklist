import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'widget_payload_test.dart' show item, listOf;

class FakePublisher() implements WidgetPublisher {
  final published = <Map<String, Object?>>[];
  var fail = false;

  @override
  Future<void> publish(String json) async {
    if (fail) {
      throw StateError('no plugin');
    }
    published.add(jsonDecode(json) as Map<String, Object?>);
  }

  List<Object?> get states => [for (final p in published) p['state']];

  List<Object?> names([int at = -1]) => [
    for (final i
        in published[at < 0 ? published.length + at : at]['items']!
            as List<Object?>)
      (i! as Map<String, Object?>)['name'],
  ];
}

class Sessions(super.initialState) extends Cubit<Session> {
  void set(Session session) => emit(session);
}

class Lists() extends Cubit<ListState> {
  this : super(const ListState());

  void set(ListState state) => emit(state);
}

const home = Household(id: 'home', name: 'Zuhause');
const inHome = InHousehold('peter', home, [home]);

void main() {
  group('with a fake list', () {
    test('signed out, without a household, then the list', () {
      fakeAsync((async) {
        final publisher = FakePublisher();
        final sync = HomeWidgetSync(publisher);
        final sessions = Sessions(const SessionLoading());
        sync.follow(sessions);
        async.elapse(const Duration(seconds: 2));
        expect(publisher.published, isEmpty, reason: 'still loading');

        sessions.set(const SignedOut());
        async.elapse(const Duration(seconds: 2));
        sessions.set(const NeedsHousehold('peter'));
        async.elapse(const Duration(seconds: 2));
        sessions.set(inHome);
        final lists = Lists();
        sync.followList('home', lists);
        async.elapse(const Duration(seconds: 2));
        expect(publisher.states, [
          'signedOut',
          'noHousehold',
        ], reason: 'nothing until the list is loaded');

        lists.set(listOf([item('Brot')]));
        async.elapse(const Duration(seconds: 2));
        expect(publisher.states.last, 'ready');
        expect(publisher.names(), ['Brot']);
      });
    });

    test('debounced, and only what changed', () {
      fakeAsync((async) {
        final publisher = FakePublisher();
        final sync = HomeWidgetSync(publisher)..follow(Sessions(inHome));
        final lists = Lists();
        sync.followList('home', lists);

        lists.set(listOf([item('Brot')]));
        async.elapse(const Duration(milliseconds: 500));
        lists.set(listOf([item('Brot'), item('Milch')]));
        async.elapse(const Duration(milliseconds: 400));
        expect(publisher.published, isEmpty, reason: 'debounced');
        async.elapse(const Duration(milliseconds: 200));
        expect(publisher.published, hasLength(1));
        expect(publisher.names(), ['Brot', 'Milch'], reason: 'the latest');

        // A resync with the same rows, or a connection change.
        lists
          ..set(listOf([item('Brot'), item('Milch')]))
          ..set(
            listOf([item('Brot'), item('Milch')])
                .copyWith(connection: .offline),
          );
        async.elapse(const Duration(seconds: 2));
        expect(publisher.published, hasLength(1));
      });
    });

    test('never the list of another household', () {
      fakeAsync((async) {
        final publisher = FakePublisher();
        final sessions = Sessions(inHome);
        final sync = HomeWidgetSync(publisher)..follow(sessions);
        final old = Lists()..set(listOf([item('Brot')]));
        sync.followList('home', old);
        async.elapse(const Duration(seconds: 2));

        sessions.set(
          const InHousehold('peter', Household(id: 'other', name: 'WG'), [
            Household(id: 'other', name: 'WG'),
          ]),
        );
        old.set(listOf([item('Brot'), item('Milch')]));
        async.elapse(const Duration(seconds: 2));
        expect(publisher.published, hasLength(1));

        sync.followList('other', Lists()..set(listOf([item('Tee')])));
        async.elapse(const Duration(seconds: 2));
        expect(publisher.names(), ['Tee']);
      });
    });

    test('a failed write is written again with the next change', () {
      fakeAsync((async) {
        final publisher = FakePublisher()..fail = true;
        final sync = HomeWidgetSync(publisher)
          ..follow(Sessions(const SignedOut()));
        final lists = Lists();
        sync.followList('home', lists);
        async.elapse(const Duration(seconds: 2));
        expect(publisher.published, isEmpty);

        publisher.fail = false;
        lists.set(listOf([item('Brot')]));
        async.elapse(const Duration(seconds: 2));
        expect(publisher.states, ['signedOut']);
      });
    });
  });

  group('with the list cubit', () {
    late FakeRepository repo;
    late MemoryListCache cache;
    late FakePublisher publisher;
    late Sessions sessions;
    late HomeWidgetSync sync;
    late ListCubit cubit;

    Future<void> settle() async {
      await pumpEventQueue();
      await sync.idle;
    }

    setUp(() {
      repo = FakeRepository();
      cache = MemoryListCache();
      publisher = FakePublisher();
      sessions = Sessions(inHome);
      sync = HomeWidgetSync(publisher, debounce: Duration.zero)
        ..follow(sessions);
    });

    tearDown(() async {
      sync.close();
      await cubit.close();
    });

    Future<void> start() async {
      cubit = ListCubit(repo, cache, userId: 'peter')..start();
      sync.followList('home', cubit);
      await settle();
    }

    test(
      "add, tick, a partner's change and sign-out reach the widget",
      () async {
        await start();
        expect(publisher.published.last, containsPair('open', 0));

        cubit.addEntry(parseEntry('2 Milch'));
        await settle();
        expect(publisher.published.last, containsPair('open', 1));
        expect((publisher.published.last['items']! as List<Object?>).single, {
          'name': 'Milch',
          'quantity': '2',
          'store': null,
        });

        final milk = cubit.state.items.values.single;
        repo.emitItem!(
          Item(
            id: 'brot',
            name: 'Brot',
            status: ItemStatus.active,
            storeId: 'dm',
            categoryId: 'other',
            createdAt: DateTime.utc(2026, 11),
            updatedAt: DateTime.utc(2026, 11),
            addedBy: 'lea',
          ),
        );
        await settle();
        expect(publisher.names(), ['Brot', 'Milch']);
        expect(
          (publisher.published.last['items']! as List<Object?>).first,
          containsPair('store', 'dm'),
        );

        cubit.tick(milk.id);
        await settle();
        expect(publisher.published.last, containsPair('open', 1));
        expect(publisher.names(), ['Brot']);

        sessions.set(const SignedOut());
        await settle();
        expect(publisher.states.last, 'signedOut');
      },
    );

    test('offline, the cached list goes out at the start', () async {
      repo.online = false;
      cache.saved = ListSnapshot(
        catalog: Catalog(stores: repo.stores),
        server: [item('Kaffee', store: 'lidl')],
        pending: const [],
      );
      await start();
      expect(publisher.states, ['ready']);
      expect(publisher.names(), ['Kaffee']);
      expect(
        (publisher.published.single['items']! as List<Object?>).single,
        containsPair('store', 'Lidl'),
      );
    });
  });
}
