import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/push/push_target.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/push_taps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../more/more_harness.dart' show FakeSession;

/// docs/PUSH.md, "Tap": a tapped notification opens its household's list.
void main() {
  const homeId = '00000000-0000-4000-8000-000000000001';
  const workId = '00000000-0000-4000-8000-000000000002';
  const goneId = '00000000-0000-4000-8000-000000000003';
  const home = Household(id: homeId, name: 'A', isDefault: true);
  const work = Household(id: workId, name: 'B');
  const user = '00000000-0000-4000-8000-000000000011';
  const inHome = InHousehold(user, home, [home, work]);
  const listB = '00000000-0000-4000-8000-000000000021';

  late StreamController<Session> sessions;
  late StreamController<PushTarget> taps;
  late FakeSession session;
  late ListLinks links;
  late PushTaps pushTaps;
  late int opened;

  void start(Session initial) {
    whenListen(session, sessions.stream, initialState: initial);
    pushTaps = PushTaps(session, links, () => opened++)..follow(taps.stream);
  }

  setUp(() {
    sessions = StreamController<Session>.broadcast();
    taps = StreamController<PushTarget>();
    session = FakeSession();
    when(() => session.switchTo(any())).thenAnswer((_) async {});
    links = ListLinks();
    opened = 0;
  });

  tearDown(() async {
    await pushTaps.cancel();
    await sessions.close();
    await taps.close();
    links.dispose();
  });

  test('a tap in the shown household asks for its list', () async {
    start(inHome);
    taps.add(const PushTarget(householdId: homeId, listId: listB));
    await pumpEventQueue();

    expect(
      links.pending,
      isA<ShowListLink>().having((l) => l.listId, 'id', listB),
    );
    expect(opened, 1);
    verifyNever(() => session.switchTo(any()));
  });

  test("a tap for the user's other household switches there first", () async {
    start(inHome);
    taps.add(const PushTarget(householdId: workId, listId: listB));
    await pumpEventQueue();

    verify(() => session.switchTo(workId)).called(1);
    expect(
      links.pending,
      isA<ShowListLink>().having((l) => l.listId, 'id', listB),
    );
    expect(opened, 1);
  });

  test(
    'a household the user left switches nothing; the shown list stays',
    () async {
      start(inHome);
      taps.add(const PushTarget(householdId: goneId, listId: listB));
      await pumpEventQueue();

      verifyNever(() => session.switchTo(any()));
      expect(opened, 1);
    },
  );

  test('a cold start tap waits for the session, then opens the list', () async {
    start(const SessionLoading());
    taps.add(const PushTarget(householdId: workId, listId: listB));
    await pumpEventQueue();
    expect(links.pending, isNull);
    expect(opened, 0);

    sessions.add(inHome);
    await pumpEventQueue();

    verify(() => session.switchTo(workId)).called(1);
    expect(links.pending, isA<ShowListLink>());
    expect(opened, 1);

    sessions.add(inHome);
    await pumpEventQueue();
    expect(opened, 1, reason: 'a tap opens once');
  });

  test('signed out, the tap is dropped and the gate takes over', () async {
    start(const SessionLoading());
    taps.add(const PushTarget(householdId: homeId, listId: listB));
    sessions.add(const SignedOut());
    await pumpEventQueue();

    expect(links.pending, isNull);
    expect(opened, 1);

    sessions.add(inHome);
    await pumpEventQueue();
    expect(links.pending, isNull, reason: 'not carried to the next sign-in');
    verifyNever(() => session.switchTo(any()));
  });
}
