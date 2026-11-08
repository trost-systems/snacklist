import 'dart:async';

import 'dart:convert';

import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:supabase_flutter/supabase_flutter.dart'
    as auth_types
    show Session;

import 'fake_auth.dart';
import 'fake_households.dart';

const _user = User(
  id: 'peter',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-22T12:00:00Z',
);

const _home = Household(id: 'home', name: 'Zuhause', isDefault: true);
const _club = Household(id: 'club', name: 'Sommerfest');

void _signIn(FakeAuth auth) => auth.states.add(
  AuthState(
    AuthChangeEvent.initialSession,
    auth_types.Session(accessToken: 'jwt', tokenType: 'bearer', user: _user),
  ),
);

Matcher _shows(String id, {List<String>? households}) => isA<InHousehold>()
    .having((s) => s.userId, 'user', 'peter')
    .having((s) => s.household.id, 'shown', id)
    .having(
      (s) => [for (final h in s.households) h.id],
      'households',
      households ?? anything,
    );

Matcher _problem(HouseholdProblem problem) =>
    throwsA(isA<HouseholdError>().having((e) => e.problem, 'problem', problem));

void main() {
  late FakeAuth auth;
  late MemorySessionCache cache;

  setUp(() {
    auth = FakeAuth()..user = _user;
    cache = MemorySessionCache();
  });

  tearDown(() => auth.close());

  group('offline', () {
    late SessionCubit cubit;

    setUp(() => cubit = SessionCubit(FakeClient(auth), cache));
    tearDown(() => cubit.close());

    test('with a cached household opens it', () async {
      cache.only('peter', _home);
      _signIn(auth);
      await pumpEventQueue();
      expect(cubit.state, _shows('home'));
    });

    test('with two cached households opens the one shown last', () async {
      cache.households['peter'] = (households: [_home, _club], shown: 'club');
      _signIn(auth);
      await pumpEventQueue();
      expect(cubit.state, _shows('club', households: ['home', 'club']));
    });

    test('a cached household opens before the server is asked', () async {
      final whileAsking = <Session>[];
      await cubit.close();
      cubit = SessionCubit(
        FakeClient(auth, onQuery: () => whileAsking.add(cubit.state)),
        cache,
      );
      cache.only('peter', _home);
      _signIn(auth);
      await pumpEventQueue();
      expect(whileAsking.first, isA<InHousehold>());
    });

    test('without a cached household keeps loading', () async {
      _signIn(auth);
      await pumpEventQueue();
      expect(cubit.state, isA<SessionLoading>());
    });

    test('a token refresh that fails does not sign out', () async {
      cache.only('peter', _home);
      auth.states.addError(AuthRetryableFetchException(message: 'offline'));
      await pumpEventQueue();
      expect(cubit.state, isA<InHousehold>());
    });

    test('switching works and the next start opens that household', () async {
      cache.households['peter'] = (households: [_home, _club], shown: 'home');
      _signIn(auth);
      await pumpEventQueue();
      await cubit.switchTo('club');
      expect(cubit.state, _shows('club'));
      expect(cache.households['peter']?.shown, 'club');
    });

    test('signing out forgets the cache', () async {
      cache.only('peter', _home);
      _signIn(auth);
      await pumpEventQueue();
      auth.states.add(const AuthState(AuthChangeEvent.signedOut, null));
      await pumpEventQueue();
      expect(cubit.state, isA<SignedOut>());
      expect(cache.households, isEmpty);
    });
  });

  group('online', () {
    late FakeHouseholds server;
    late SessionCubit cubit;

    setUp(() {
      server = FakeHouseholds(auth)
        ..member('peter', 'home', 'Zuhause', open: 3)
        ..member('peter', 'club', 'Sommerfest')
        ..member('lea', 'home', 'Zuhause');
      cubit = SessionCubit(server, cache);
    });
    tearDown(() => cubit.close());

    test('the default household shows first, with all of them', () async {
      await cubit.refresh();
      final state = cubit.state as InHousehold;
      expect(state, _shows('home', households: ['home', 'club']));
      expect(state.defaultHousehold.id, 'home');
      expect(state.household.memberCount, 2);
      expect(state.household.openCount, 3);
      expect(cache.households['peter']?.households, hasLength(2));
    });

    test('the household shown last on this device shows while the user is '
        'in it', () async {
      cache.households['peter'] = (households: [_home, _club], shown: 'club');
      await cubit.refresh();
      expect(cubit.state, _shows('club'));
      cache.households['peter'] = (households: [_home], shown: 'gone');
      await cubit.refresh();
      expect(cubit.state, _shows('club'), reason: 'the one shown now stays');
    });

    test('a household left elsewhere falls back to the default', () async {
      cache.households['peter'] = (households: [_home, _club], shown: 'club');
      await cubit.refresh();
      server.memberships['peter']!.remove('club');
      await cubit.refresh();
      expect(cubit.state, _shows('home', households: ['home']));
    });

    test('a switch while a reload is out wins', () async {
      await cubit.refresh();
      final reload = cubit.refresh();
      await cubit.switchTo('club');
      await reload;
      expect(cubit.state, _shows('club'));
    });

    test('switching to a household the user is not in does nothing', () async {
      await cubit.refresh();
      await cubit.switchTo('elsewhere');
      expect(cubit.state, _shows('home'));
    });

    test('setDefault moves the default, not the household shown', () async {
      await cubit.refresh();
      await cubit.setDefault('club');
      final state = cubit.state as InHousehold;
      expect(server.defaults['peter'], 'club');
      expect(state.defaultHousehold.id, 'club');
      expect(state, _shows('home'));
    });

    test('rename renames for everyone', () async {
      await cubit.refresh();
      await cubit.rename('home', '  Wohnung ');
      expect(server.households['home']!.name, 'Wohnung');
      expect((cubit.state as InHousehold).household.name, 'Wohnung');
    });

    test('leaving another household keeps the one shown', () async {
      await cubit.refresh();
      await cubit.leave('club');
      expect(cubit.state, _shows('home', households: ['home']));
      expect(
        server.calls.last,
        startsWith('rpc/my_households'),
        reason: 'reloaded after leaving',
      );
    });

    test('leaving the household shown shows the new default', () async {
      await cubit.refresh();
      await cubit.leave('home');
      final state = cubit.state as InHousehold;
      expect(state, _shows('club', households: ['club']));
      expect(state.defaultHousehold.id, 'club');
      expect(server.households['home']!.members, [
        'lea',
      ], reason: 'Lea keeps the list');
    });

    test(
      'a left household is gone even when the reload after it fails',
      () async {
        await cubit.refresh();
        server.failReads = true;
        await cubit.leave('home');
        final state = cubit.state as InHousehold;
        expect(state, _shows('club', households: ['club']));
        expect(
          state.defaultHousehold.id,
          'club',
          reason: 'as the server moves it',
        );
        expect(cache.households['peter']?.households.map((h) => h.id), [
          'club',
        ]);
        await cubit.leave('club');
        expect(cubit.state, isA<NeedsHousehold>());
      },
    );

    test('leaving the last household goes to onboarding', () async {
      await cubit.refresh();
      await cubit.leave('club');
      await cubit.leave('home');
      expect(cubit.state, isA<NeedsHousehold>());
      expect(cache.households, isEmpty);
    });

    test('leave sends the archive choice', () async {
      await cubit.refresh();
      await cubit.leave('club', archive: true);
      expect(
        jsonDecode(
          server.calls
              .singleWhere((c) => c.contains('leave'))
              .split(' ')
              .skip(1)
              .join(' '),
        ),
        {'p_household': 'club', 'p_archive': true},
      );
    });

    test('a create shows the new household beside the others', () async {
      await cubit.refresh();
      final id = await cubit.createHousehold('Eltern', kind: 'family');
      expect(cubit.state, _shows(id, households: ['home', 'club', id]));
      final sent = server.calls.singleWhere((c) => c.contains('create'));
      expect(sent, contains('"p_kind":"family"'));
      expect(sent, contains('"p_request_id":'));
    });

    test('a create retried after a lost answer is one household', () async {
      await cubit.refresh();
      server.dropNextAnswer = true;
      await expectLater(
        cubit.createHousehold('Eltern', stores: const ['REWE']),
        _problem(HouseholdProblem.offline),
      );
      final id = await cubit.createHousehold('Eltern', stores: const ['REWE']);
      expect(server.memberships['peter'], ['home', 'club', id]);
      final requests = {
        for (final c in server.calls.where((c) => c.contains('create')))
          (jsonDecode(c.substring(c.indexOf(' ') + 1)) as Map)['p_request_id'],
      };
      expect(requests, hasLength(1), reason: 'the same request id');
    });

    test('a create retried after a failed reload is one household', () async {
      await cubit.refresh();
      server.failReads = true;
      await expectLater(cubit.createHousehold('Eltern'), throwsA(anything));
      server.failReads = false;
      final id = await cubit.createHousehold('Eltern');
      expect(server.memberships['peter'], ['home', 'club', id]);
      expect(cubit.state, _shows(id));
    });

    test('onboarding can create several households one after the other '
        '(job 168)', () async {
      final first = await cubit.createHousehold('Zuhause 2', kind: 'partner');
      final second = await cubit.createHousehold('Eltern', kind: 'family');
      expect(first, isNot(second));
      expect(cubit.state, _shows(second));
      expect(server.memberships['peter'], containsAll([first, second]));
    });

    test('the server refuses an 11th household', () async {
      for (var i = 0; i < 8; i++) {
        await cubit.createHousehold('H$i');
      }
      await expectLater(
        cubit.createHousehold('Zu viel'),
        _problem(HouseholdProblem.tooManyHouseholds),
      );
    });

    test('a join adds the household and shows it', () async {
      server
        ..member('mia', 'mia', 'Mias WG')
        ..invites['ABCD2345'] = 'mia';
      await cubit.refresh();
      await cubit.join('abcd-2345');
      expect(cubit.state, _shows('mia', households: ['home', 'club', 'mia']));
    });

    test('joining a household the user is in shows it', () async {
      server.invites['ABCD2345'] = 'club';
      await cubit.refresh();
      await cubit.join('ABCD2345');
      expect(cubit.state, _shows('club', households: ['home', 'club']));
    });

    test(
      'a reload that started before an unarchive does not hide it',
      () async {
        await cubit.refresh();
        final hold = server.holdReads = Completer<void>();
        final stale = cubit.refresh();
        await pumpEventQueue();
        expect(server.calls.last, startsWith('rpc/my_households'));
        server.holdReads = null;
        await cubit.unarchive('old');
        hold.complete();
        await stale;
        expect(cubit.state, _shows('old', households: ['home', 'club', 'old']));
      },
    );

    test(
      'an unarchive whose reload failed shows it on the next reload',
      () async {
        await cubit.refresh();
        server.failReads = true;
        await expectLater(
          cubit.unarchive('old'),
          throwsA(isA<HouseholdError>()),
        );
        server.failReads = false;
        await cubit.refresh();
        expect(cubit.state, _shows('old', households: ['home', 'club', 'old']));
      },
    );

    test(
      'an unarchive whose reload never answered shows it after a restart',
      () async {
        await cubit.refresh();
        server.failReads = true;
        await expectLater(
          cubit.unarchive('old'),
          throwsA(isA<HouseholdError>()),
        );
        server.failReads = false;
        // The page reloads (web) or the app restarts: a new cubit, same device.
        final restarted = SessionCubit(server, cache);
        addTearDown(restarted.close);
        _signIn(auth);
        await pumpEventQueue();
        expect(
          restarted.state,
          _shows('old', households: ['home', 'club', 'old']),
        );
      },
    );

    test('a reload that answers while a household to show is being kept on the '
        'device does not undo it', () async {
      final gated = _GatedCache();
      final cubit = SessionCubit(server, gated);
      addTearDown(cubit.close);
      await cubit.refresh();
      await cubit.switchTo('club');
      final hold = server.holdReads = Completer<void>();
      final stale = cubit.refresh();
      await pumpEventQueue();
      server
        ..holdReads = null
        ..member('peter', 'new', 'Neu');
      final gate = gated.gate = Completer<void>();
      gated.onRemember = () => scheduleMicrotask(() async {
        hold.complete();
        await stale;
        gate.complete();
      });
      await cubit.refresh(show: 'new');
      expect(cubit.state, _shows('new'));
      expect(gated.households['peter']?.shown, 'new');
    });

    test('unarchiving adds the household and shows it', () async {
      await cubit.refresh();
      await cubit.unarchive('old');
      expect(cubit.state, _shows('old', households: ['home', 'club', 'old']));
      expect(
        server.calls.singleWhere((c) => c.contains('unarchive')),
        contains('"p_mode":"add"'),
      );
    });
  });
}

/// Holds its next [remember] until [gate] completes, after [onRemember].
class _GatedCache() extends MemorySessionCache {
  Completer<void>? gate;
  void Function()? onRemember;

  @override
  Future<void> remember(
    String userId, {
    required List<Household> households,
    String? shown,
  }) async {
    if (gate case final held?) {
      gate = null;
      onRemember?.call();
      await held.future;
    }
    await super.remember(userId, households: households, shown: shown);
  }
}
