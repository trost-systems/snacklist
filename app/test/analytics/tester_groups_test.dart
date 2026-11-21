import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/tester_groups.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

class _Session(super.initialState) extends TestSession {
  void show(Session session) => emit(session);
}

class _Server() implements TesterGroupsSource {
  var groups = <String>{};
  var offline = false;
  var reads = 0;

  /// While set, answers wait for it.
  Completer<void>? hold;

  @override
  Future<Set<String>> mine() async {
    reads++;
    final answer = {...groups};
    await hold?.future;
    if (!offline) {
      return answer;
    }
    throw StateError('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryAnalyticsStore store;
  late Analytics analytics;
  late _Server server;
  late _Session session;
  late TesterGroupsSync sync;

  const home = Household(id: 'home', name: 'Zuhause');
  const peter = InHousehold('peter', home, [home]);

  setUp(() async {
    store = MemoryAnalyticsStore();
    analytics = await loadedAnalytics(store);
    server = _Server();
    session = _Session(const SessionLoading());
    sync = TesterGroupsSync(server, store, analytics)..follow(session);
  });

  tearDown(() async {
    await sync.close();
    await session.close();
    await analytics.close();
  });

  test('at sign-in the server says internal: the user is internal and the '
      'groups are kept', () async {
    server.groups = {'internal'};
    expect(analytics.internalNow, isFalse);
    session.show(peter);
    await pumpEventQueue();
    expect(analytics.state.testerGroups, {'internal'});
    expect(analytics.internalNow, isTrue);
    expect(store.keptGroups?.user, 'peter');
    expect(store.keptGroups?.groups, {'internal'});
  });

  test('offline, the kept groups of the same user stand', () async {
    store.keptGroups = (user: 'peter', groups: {'beta-de'});
    server.offline = true;
    session.show(peter);
    await pumpEventQueue();
    expect(analytics.state.testerGroups, {'beta-de'});
  });

  test("another user's kept groups are not used", () async {
    store.keptGroups = (user: 'lea', groups: {'internal'});
    server.offline = true;
    session.show(peter);
    await pumpEventQueue();
    expect(analytics.state.testerGroups, isEmpty);
    expect(analytics.internalNow, isFalse);
  });

  test('back from the background it reads again: removed from the group, '
      'no longer internal', () async {
    server.groups = {'internal'};
    session.show(peter);
    await pumpEventQueue();
    server.groups = {};
    [AppLifecycleState.inactive, AppLifecycleState.resumed].forEach(
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged,
    );
    await pumpEventQueue();
    expect(server.reads, 1, reason: 'a focus loss is no return');
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged,
    );
    await pumpEventQueue();
    expect(server.reads, 2);
    expect(analytics.internalNow, isFalse);
    expect(store.keptGroups?.groups, isEmpty);
  });

  test('an answer that comes after the sign-out reaches neither analytics '
      'nor the device', () async {
    server
      ..groups = {'internal'}
      ..hold = Completer<void>();
    session.show(peter);
    await pumpEventQueue();
    session.show(const SignedOut());
    await pumpEventQueue();
    server.hold!.complete();
    await pumpEventQueue();
    expect(analytics.state.testerGroups, isEmpty);
    expect(store.keptGroups, isNull);
  });

  test('a sign-out drops the groups on the device', () async {
    server.groups = {'internal'};
    session.show(peter);
    await pumpEventQueue();
    session.show(const SignedOut());
    await pumpEventQueue();
    expect(analytics.state.testerGroups, isEmpty);
    expect(store.keptGroups, isNull);
  });
}
