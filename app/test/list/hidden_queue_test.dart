// Job 169b: changes queued in one household reach the server while the
// user shows another, after a switch and after a restart, without opening
// the first household again.
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../household/harness.dart';
import 'fake_repository.dart';

const _home = Household(id: 'home', name: 'Zuhause', isDefault: true);
const _club = Household(id: 'club', name: 'Sommerfest');

typedef _World = ({
  DeviceCache cache,
  TestSession session,
  Map<String, FakeRepository> servers,
});

/// A device that knows Peter's two households; it keeps lists only of
/// households it knows.
Future<DeviceCache> _device() async {
  final cache = DeviceCache(SharedPreferencesAsync());
  await cache.remember('peter', households: const [_home, _club]);
  return cache;
}

Future<_World> _pump(WidgetTester tester, {required Household shown}) async {
  final cache = await _device();
  final analytics = Analytics.off(cache);
  addTearDown(analytics.close);
  final session = TestSession(
    InHousehold('peter', shown, const [_home, _club]),
  );
  addTearDown(session.close);
  final servers = {'home': FakeRepository(), 'club': FakeRepository()};
  await tester.pumpWidget(
    RepositoryProvider.value(
      value: cache,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: session),
          BlocProvider.value(value: analytics),
        ],
        child: MaterialApp(
          home: ListScope(
            repositories: (id) => servers[id]!,
            child: const SizedBox(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (cache: cache, session: session, servers: servers);
}

ListCubit _shownList(WidgetTester tester) =>
    BlocProvider.of<ListCubit>(tester.element(find.byType(SizedBox)));

List<String> _names(FakeRepository server) => [
  for (final row in server.rows.values) row.name,
];

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('an add queued offline in Zuhause is sent after a switch to '
      "Sommerfest, once online, and Zuhause's list closes", (tester) async {
    final w = await _pump(tester, shown: _home);
    final home = w.servers['home']!..online = false;
    _shownList(tester).addEntry(parseEntry('Brot'));
    await tester.pumpAndSettle();
    expect(_names(home), isEmpty);

    await w.session.switchTo('club');
    await tester.pumpAndSettle();
    expect(_shownList(tester).state.pending, isEmpty, reason: 'Sommerfest');
    home.online = true;
    // The list's own 3 s retry; no network watch in tests.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(_names(home), ['Brot']);
    expect(_names(w.servers['club']!), isEmpty);
    expect(home.unwatches, 1, reason: "Zuhause's list closed once sent");
    expect((await w.cache.list('peter', 'home').load())?.pending, isEmpty);
  });

  testWidgets('switching back while it still sends shows the same list, so '
      'one list owns the queue', (tester) async {
    final w = await _pump(tester, shown: _home);
    final home = w.servers['home']!..online = false;
    final before = _shownList(tester)..addEntry(parseEntry('Brot'));
    await tester.pumpAndSettle();
    await w.session.switchTo('club');
    await tester.pumpAndSettle();
    await w.session.switchTo('home');
    await tester.pumpAndSettle();
    expect(_shownList(tester), same(before));
    expect(home.watches, 1);
    home.online = true;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(_names(home), ['Brot']);
    expect(home.sent.whereType<AddItem>(), hasLength(1));
  });

  testWidgets('a start sends what another household left queued on this '
      'device', (tester) async {
    final at = DateTime.utc(2026, 11, 8, 12);
    await (await _device())
        .list('peter', 'home')
        .save(
          ListSnapshot(
            catalog: const Catalog(),
            server: const [],
            pending: [
              AddItem(
                Item(
                  id: 'brot',
                  name: 'Brot',
                  status: ItemStatus.active,
                  createdAt: at,
                  updatedAt: at,
                ),
              ),
            ],
          ),
        );
    final w = await _pump(tester, shown: _club);
    await tester.pumpAndSettle();
    expect(_names(w.servers['home']!), ['Brot']);
    expect(w.servers['home']!.unwatches, 1, reason: 'closed once sent');
    expect((await w.cache.list('peter', 'home').load())?.pending, isEmpty);
    expect(w.servers['club']!.unwatches, 0, reason: 'the shown list stays');
  });
}
