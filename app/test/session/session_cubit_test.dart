import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as auth_types
    show Session;
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

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

    test('kind, role and Premium come with each household', () async {
      server
        ..kinds['club'] = 'club'
        ..premium.add('home')
        ..member('lea', 'club', 'Sommerfest');
      await cubit.refresh();
      final [home, club] = (cubit.state as InHousehold).households;
      expect(
        (home.kind, home.role, home.premium),
        (null, HouseholdRole.owner, true),
      );
      expect(
        (club.kind, club.role, club.premium),
        (HouseholdKind.club, HouseholdRole.owner, false),
      );
      expect(Household.fromJson(home.toJson())?.premium, isTrue);
      expect(Household.fromJson(club.toJson())?.kind, HouseholdKind.club);
    });

    group('no longer in a household (job 169b W2, Legal N-114)', () {
      late List<LostHousehold> lost;

      /// What [lost] told: the household and whether it was a removal.
      List<(String, bool)> told() => [
        for (final l in lost) (l.name, l.removal != null),
      ];

      setUp(() {
        lost = [];
        cubit.lostHouseholds.listen(lost.add);
      });

      const removedFromClub = ('Sommerfest', true);

      test('removed from the household shown: the default shows, and the '
          '30 days are told', () async {
        cache.households['peter'] = (households: [_home, _club], shown: 'club');
        await cubit.refresh();
        expect(cubit.state, _shows('club'));
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        expect(cubit.state, _shows('home', households: ['home']));
        expect(told(), [removedFromClub]);
      });

      test('removed from another household: the one shown stays', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        expect(cubit.state, _shows('home', households: ['home']));
        expect(told(), [removedFromClub]);
      });

      test('removed from the last one: onboarding, and it is told', () async {
        await cubit.refresh();
        server
          ..removedBySomeone('peter', 'club')
          ..removedBySomeone('peter', 'home');
        await cubit.refresh();
        await pumpEventQueue();
        expect(cubit.state, isA<NeedsHousehold>());
        expect(told(), unorderedEquals([removedFromClub, ('Zuhause', true)]));
      });

      test('a removal is told once, however often the app reloads', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await Future.wait([cubit.refresh(), cubit.refresh()]);
        await cubit.refresh();
        await pumpEventQueue();
        expect(told(), [removedFromClub]);
      });

      test('and once per device once seen: not again after a restart or a '
          'sign-out and in again', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        await cubit.removalsTold('peter', [?lost.single.removal]);
        await cubit.close();
        final restarted = SessionCubit(server, cache);
        addTearDown(restarted.close);
        final toldAfter = <LostHousehold>[];
        restarted.lostHouseholds.listen(toldAfter.add);
        _signIn(auth);
        await pumpEventQueue();
        await auth.signOut();
        auth.user = _user;
        _signIn(auth);
        await pumpEventQueue();
        expect(cache.forgotten, 1, reason: 'the sign-out forgot the cache');
        expect(restarted.state, _shows('home'));
        expect(told(), [removedFromClub]);
        expect(toldAfter, isEmpty);
      });

      test('not seen before a restart (held behind the analytics consent, '
          'then the app was killed): told again', () async {
        server.removedBySomeone('peter', 'club');
        _signIn(auth);
        await pumpEventQueue();
        expect(told(), [removedFromClub]);
        expect(
          cache.toldRemovalsOf['peter'] ?? const <String>{},
          isEmpty,
          reason: 'only the notice shown marks it told',
        );
        await cubit.close();
        final restarted = SessionCubit(server, cache);
        addTearDown(restarted.close);
        final toldAfter = <LostHousehold>[];
        restarted.lostHouseholds.listen(toldAfter.add);
        _signIn(auth);
        await pumpEventQueue();
        expect([for (final l in toldAfter) l.name], ['Sommerfest']);
        await restarted.removalsTold('peter', [?toldAfter.single.removal]);
        expect(cache.toldRemovalsOf['peter'], hasLength(1));
      });

      test('a removal the server forgot (30 days on) leaves the device '
          'too', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        await cubit.removalsTold('peter', [?lost.single.removal]);
        expect(cache.toldRemovalsOf['peter'], hasLength(1));
        server.removals['peter']?.clear();
        await cubit.refresh();
        expect(cache.toldRemovalsOf['peter'] ?? const <String>{}, isEmpty);
      });

      test('two notices seen at once are both kept', () async {
        await cubit.refresh();
        server
          ..removedBySomeone('peter', 'club')
          ..removedBySomeone('peter', 'home');
        await cubit.refresh();
        await pumpEventQueue();
        await Future.wait([
          for (final l in lost) cubit.removalsTold('peter', [?l.removal]),
        ]);
        expect(cache.toldRemovalsOf['peter'], hasLength(2));
      });

      test('signing in on a new device tells a removal of the last 30 '
          'days', () async {
        server.removedBySomeone('peter', 'club');
        _signIn(auth);
        await pumpEventQueue();
        expect(cubit.state, _shows('home', households: ['home']));
        expect(told(), [removedFromClub]);
      });

      test('removed again after rejoining: told again', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        server
          ..member('peter', 'club', 'Sommerfest')
          ..removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        expect(told(), [removedFromClub, removedFromClub]);
      });

      test('left on another device: told, without the 30 days', () async {
        await cubit.refresh();
        server.leftElsewhere('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        expect(cubit.state, _shows('home', households: ['home']));
        expect(told(), [('Sommerfest', false)]);
      });

      test('a server without my_household_removals: told without the '
          '30 days', () async {
        server.missing.add('my_household_removals');
        await cubit.refresh();
        server.removedBySomeone('peter', 'club');
        await cubit.refresh();
        await pumpEventQueue();
        expect(cubit.state, _shows('home', households: ['home']));
        expect(told(), [('Sommerfest', false)]);
      });

      test('the default moves on the server: the new default shows', () async {
        await cubit.refresh();
        server.removedBySomeone('peter', 'home');
        await cubit.refresh();
        final state = cubit.state as InHousehold;
        expect(state, _shows('club'));
        expect(state.defaultHousehold.id, 'club');
      });

      test('leaving on this device is not told', () async {
        await cubit.refresh();
        await cubit.leave('club');
        await pumpEventQueue();
        expect(told(), isEmpty);
      });
    });

    test('a switch while a reload is out wins', () async {
      await cubit.refresh();
      final reload = cubit.refresh();
      await cubit.switchTo('club');
      await reload;
      expect(cubit.state, _shows('club'));
    });

    group('reorderHouseholds (job 229)', () {
      List<String> cached() => [
        for (final h
            in cache.households['peter']?.households ?? const <Household>[])
          h.id,
      ];

      test('the new order shows at once, then the server and the device '
          'keep it', () async {
        await cubit.refresh();
        final reorder = cubit.reorderHouseholds(['club', 'home']);
        expect(cubit.state, _shows('home', households: ['club', 'home']));
        await reorder;
        expect(server.memberships['peter'], ['club', 'home']);
        expect(cached(), ['club', 'home']);
        await cubit.refresh();
        expect(cubit.state, _shows('home', households: ['club', 'home']));
      });

      test('a refusal puts the order back and is thrown', () async {
        await cubit.refresh();
        server.missing.add('reorder_households');
        await expectLater(
          cubit.reorderHouseholds(['club', 'home']),
          throwsA(isA<HouseholdError>()),
        );
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(cached(), ['home', 'club']);
      });

      test('a reload out while reordering does not bring the old order '
          'back', () async {
        await cubit.refresh();
        server.holdReads = Completer();
        final reload = cubit.refresh();
        await pumpEventQueue();
        await cubit.reorderHouseholds(['club', 'home']);
        server.holdReads?.complete();
        await reload;
        expect(cubit.state, _shows('home', households: ['club', 'home']));
      });
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
        expect(
          state.household.role,
          HouseholdRole.owner,
          reason: 'its role stays: an owner keeps the admin controls',
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
        cubit.createHousehold('Eltern', stores: const [NewStore('REWE')]),
        _problem(HouseholdProblem.offline),
      );
      final id = await cubit.createHousehold(
        'Eltern',
        stores: const [NewStore('REWE')],
      );
      expect(server.memberships['peter'], ['home', 'club', id]);
      final requests = {
        for (final c in server.calls.where((c) => c.contains('create')))
          (jsonDecode(c.substring(c.indexOf(' ') + 1)) as Map)['p_request_id'],
      };
      expect(requests, hasLength(1), reason: 'the same request id');
    });

    group('stores of a chain (job 321)', () {
      const lidl = NewStore('Lidl', chain: (chain: 'lidl', country: 'DE'));
      const hofer = NewStore(
        'Hofer',
        chain: (chain: 'aldi-sued', country: 'AT'),
      );
      const baecker = NewStore('Bäcker Kühn');

      test('are made with the household, then linked to their chain', () async {
        await cubit.refresh();
        final id = await cubit.createHousehold(
          'Eltern',
          stores: const [lidl, baecker, hofer],
        );
        expect(server.households[id]?.stores, ['Lidl', 'Bäcker Kühn', 'Hofer']);
        expect(server.households[id]?.chains, {
          'Lidl': 'lidl/DE',
          'Hofer': 'aldi-sued/AT',
        });
        expect(
          server.calls.where((c) => c.startsWith('rpc/add_store')),
          hasLength(2),
          reason: 'the plain store is asked about later, not linked',
        );
        expect(cubit.state, _shows(id));
      });

      test('a chain the server no longer has leaves its store plain', () async {
        await cubit.refresh();
        server.unknownChains.add('aldi-sued/AT');
        final id = await cubit.createHousehold(
          'Eltern',
          stores: const [hofer, lidl],
        );
        expect(server.households[id]?.chains, {'Lidl': 'lidl/DE'});
        expect(cubit.state, _shows(id));
      });

      test(
        'a retry after a lost answer links them in the one household',
        () async {
          await cubit.refresh();
          server.dropAnswerTo.add('add_store');
          await expectLater(
            cubit.createHousehold('Eltern', stores: const [lidl]),
            _problem(HouseholdProblem.offline),
          );
          final id = await cubit.createHousehold(
            'Eltern',
            stores: const [lidl],
          );
          expect(server.memberships['peter'], ['home', 'club', id]);
          expect(server.households[id]?.stores, ['Lidl']);
          expect(server.households[id]?.chains, {'Lidl': 'lidl/DE'});
          expect(cubit.state, _shows(id));
        },
      );
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

    test('the server refuses a 21st household', () async {
      for (var i = 0; i < 18; i++) {
        await cubit.createHousehold('H$i');
      }
      await expectLater(
        cubit.createHousehold('Zu viel'),
        _problem(HouseholdProblem.tooManyHouseholds),
      );
    });

    test(
      'the server refuses joining a 21st household (job 173, 200)',
      () async {
        server
          ..member('mia', 'mia', 'Mias WG')
          ..invites['ABCD2345'] = 'mia';
        for (var i = 0; i < 18; i++) {
          await cubit.createHousehold('H$i');
        }
        await expectLater(
          cubit.join('ABCD2345'),
          _problem(HouseholdProblem.tooManyHouseholds),
        );
        expect(server.memberships['peter'], isNot(contains('mia')));
      },
    );

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

    test('a switch while a reload keeps its answer on the device '
        'stays', () async {
      final gated = _GatedCache();
      final cubit = SessionCubit(server, gated);
      addTearDown(cubit.close);
      await cubit.refresh();
      final saving = Completer<void>();
      final gate = gated.gate = Completer<void>();
      gated.onRemember = saving.complete;
      final reload = cubit.refresh();
      await saving.future;
      final switched = cubit.switchTo('club');
      gate.complete();
      await reload;
      await switched;
      expect(cubit.state, _shows('club'));
      expect(gated.households['peter']?.shown, 'club');
    });

    test('a reload out when the user signs out does not bring their '
        'household back', () async {
      final hold = server.holdReads = Completer<void>();
      _signIn(auth);
      await pumpEventQueue();
      expect(server.calls.last, startsWith('rpc/my_households'));
      await auth.signOut();
      await pumpEventQueue();
      hold.complete();
      await pumpEventQueue();
      expect(cubit.state, isA<SignedOut>());
      expect(cache.households, isEmpty);
      server.holdReads = null;
      auth.user = _user;
      _signIn(auth);
      await pumpEventQueue();
      expect(cubit.state, _shows('home'), reason: 'signing in again loads');
    });

    test('a reload out when the account is deleted does not bring its '
        'household back', () async {
      final gated = _GatedCache();
      final cubit = SessionCubit(server, gated);
      addTearDown(cubit.close);
      final hold = server.holdReads = Completer<void>();
      _signIn(auth);
      await pumpEventQueue();
      final forgetting = gated.forgetGate = Completer<void>();
      final states = <Session>[];
      cubit.stream.listen(states.add);
      final deleted = cubit.accountDeleted(
        const AccountDeletedNotice(removeAppleManually: false),
      );
      hold.complete();
      await pumpEventQueue();
      forgetting.complete();
      await deleted;
      await pumpEventQueue();
      expect(states, isNot(contains(isA<InHousehold>())));
      expect(
        cubit.state,
        isA<SignedOut>().having((s) => s.deleted, 'deleted', isNotNull),
      );
      expect(gated.households, isEmpty);
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

  group("a start asks until the server's households show (job 222):", () {
    const retry = Duration(seconds: 3);
    const lea = User(
      id: 'lea',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-22T12:00:00Z',
    );

    /// Another account's session, with or without a sign-out before it.
    void signInLea() => auth
      ..user = lea
      ..states.add(
        AuthState(
          AuthChangeEvent.signedIn,
          auth_types.Session(
            accessToken: 'jwt',
            tokenType: 'bearer',
            user: lea,
          ),
        ),
      );

    /// Under fake time, signed out of the group's server at the end.
    void started(
      void Function(FakeAsync async, FakeHouseholds server, SessionCubit cubit)
      body,
    ) => fakeAsync((async) {
      final server = FakeHouseholds(auth)
        ..member('peter', 'home', 'Zuhause')
        ..member('peter', 'club', 'Sommerfest');
      final cubit = SessionCubit(server, cache);
      body(async, server, cubit);
      unawaited(cubit.close());
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });

    test('a read that failed is sent again after 3 s, and again', () {
      started((async, server, cubit) {
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(retry);
        expect(cubit.state, isA<SessionLoading>());
        server.failReads = false;
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(const Duration(milliseconds: 1));
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
        final reads = server.calls.length;
        async.elapse(retry * 3);
        expect(server.calls, hasLength(reads));
      });
    });

    test('a first read overtaken by a second one that failed is sent '
        'again: its own answer was dropped as the older one', () {
      started((async, server, cubit) {
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(server.calls.last, startsWith('rpc/my_households'));
        // The session's token refreshed meanwhile: the same user again.
        server
          ..holdReads = null
          ..failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        hold.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<SessionLoading>());
        expect(async.pendingTimers, hasLength(1), reason: 'one asking');

        async.elapse(retry);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
      });
    });

    test("the same with the device's households showing: a reload on "
        "coming back failed, the start's answer was dropped", () {
      started((async, server, cubit) {
        cache.only('peter', _home);
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home']));
        server
          ..holdReads = null
          ..failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.failReads = false;
        hold.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home']));

        async.elapse(retry);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
      });
    });

    test('a first read overtaken by a second one that answered is not '
        'sent again', () {
      started((async, server, cubit) {
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        server.holdReads = null;
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        hold.complete();
        async.flushMicrotasks();
        final reads = server.calls.length;
        async.elapse(retry * 3);
        expect(server.calls, hasLength(reads));
      });
    });

    test('an account without a household has its answer too: nothing is '
        'asked again', () {
      started((async, server, cubit) {
        server.memberships['peter']!.clear();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, isA<NeedsHousehold>());
        expect(async.pendingTimers, isEmpty);
        // The session's token refreshed: the same user again.
        _signIn(auth);
        async.elapse(retry * 3);
        expect(
          server.calls.where((c) => c.startsWith('rpc/my_households')),
          hasLength(1),
        );
      });
    });

    test('an answer that shows but is not kept on the device (the write '
        'failed) is read again after 3 s, until it is kept', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.failWrites = 2;
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(cache.households, isEmpty);
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 2);
        expect(cache.households, isEmpty);
        async.elapse(retry);
        expect(reads(), 3);
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty, reason: 'kept: no more');
        async.elapse(retry * 3);
        expect(reads(), 3);
      });
    });

    test("the same for a reload's answer while the start still asks: the "
        'asking goes on until an answer is kept', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        cache.failWrites = 1;
        async.elapse(const Duration(seconds: 1));
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(cache.households, isEmpty);
        expect(reads(), 2);
        async.elapse(const Duration(seconds: 2));
        expect(reads(), 3, reason: "3 s after the start's read failed");
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty, reason: 'kept: no more');
      });
    });

    // Review 5: the device write takes time, and something happens meanwhile.
    test("a reload's answer still being written when the 3 s are over does "
        'not end the asking: the read is sent, and its answer is kept', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 2900));
        cache.failWrites = 1;
        final hold = cache.holdWrites = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 100));
        expect(reads(), 3, reason: "3 s after the start's read failed");
        async.elapse(const Duration(milliseconds: 400));
        // The reload's write fails, the one behind it works.
        hold.complete();
        cache.holdWrites = null;
        async.flushMicrotasks();
        expect(cache.failWrites, 0);
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty, reason: 'kept: no more');
        async.elapse(retry * 3);
        expect(reads(), 3);
      });
    });

    test("the start's read that fails while a reload's answer is being "
        'written is sent again 3 s later when that write fails', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        server.holdReads = null;
        cache.failWrites = 1;
        final hold = cache.holdWrites = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        cache.holdWrites = null;
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        first.completeError(StateError('connection lost'));
        async.flushMicrotasks();
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households, isEmpty);
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3, reason: "3 s after the start's read failed");
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty, reason: 'kept: no more');
      });
    });

    test("an auth event while the start's own answer is being written "
        'sends a read: its answer is kept when that write fails', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.failWrites = 1;
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 1);
        // The session's token refreshed: the same user again.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        // The start's write fails, the one behind it works.
        hold.complete();
        cache.holdWrites = null;
        async.flushMicrotasks();
        expect(cache.failWrites, 0);
        expect(cache.households['peter']?.households, hasLength(2));
        async.elapse(retry * 3);
        expect(reads(), 2, reason: 'kept: no more');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an answer kept on the device after a newer read was sent ends the '
        'asking too: that read, failed, is not sent again', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 2900));
        final hold = cache.holdWrites = Completer<void>();
        unawaited(cubit.refresh());
        async.flushMicrotasks();
        cache.holdWrites = null;
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        server.failReads = true;
        async.elapse(const Duration(milliseconds: 100));
        expect(reads(), 3, reason: "3 s after the start's read failed");
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households['peter']?.households, hasLength(2));
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'kept: no more');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test("the same after the start's answer was dropped: a reload that fails "
        "while the newest one's answer is being written starts no asking", () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        server.holdReads = null;
        final hold = cache.holdWrites = Completer<void>();
        unawaited(cubit.refresh());
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        first.complete();
        async.flushMicrotasks();
        cache.holdWrites = null;
        server.failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        expect(reads(), 3);
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households['peter']?.households, hasLength(2));
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'kept: no more');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an answer kept on the device after a sign-out does not count when '
        'the same account is back by then: its new read, failed, is sent '
        'again', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        unawaited(auth.signOut());
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        server.failReads = true;
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        hold.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        server.failReads = false;
        async.elapse(retry);
        expect(reads(), 3, reason: '3 s after the new read failed');
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('nor when another account was signed in meanwhile and its households '
        "still show: the first one's new read, failed, is sent again", () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.member('lea', 'flat', 'WG');
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        signInLea();
        async.flushMicrotasks();
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );
        server.failReads = true;
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 3);
        hold.complete();
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(retry);
        expect(reads(), 4, reason: '3 s after the new read failed');
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      "a reload sent while the start's own answer is being written starts "
      'no asking when it fails: the start has its answer once it is kept',
      () {
        started((async, server, cubit) {
          int reads() => server.calls
              .where((c) => c.startsWith('rpc/my_households'))
              .length;
          final hold = cache.holdWrites = Completer<void>();
          _signIn(auth);
          async.flushMicrotasks();
          expect(cubit.state, _shows('home', households: ['home', 'club']));
          cache.holdWrites = null;
          server.failReads = true;
          unawaited(cubit.refresh().catchError((Object _) {}));
          async.flushMicrotasks();
          hold.complete();
          async.flushMicrotasks();
          expect(cache.households['peter']?.households, hasLength(2));
          expect(async.pendingTimers, isEmpty, reason: 'answered and kept');
          async.elapse(retry * 3);
          expect(reads(), 2);
        });
      },
    );

    test('the same for a token refresh during that write: its read, failed, '
        'is not sent again once the answer is kept', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2, reason: 'not kept yet: the event sends a read');
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households['peter']?.households, hasLength(2));
        async.elapse(retry * 3);
        expect(reads(), 2);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the same for the answer of a read that was sent again: a reload '
        'that fails while it is being written starts no asking', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        final hold = cache.holdWrites = Completer<void>();
        async.elapse(retry);
        expect(reads(), 2);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        server.failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty, reason: 'answered and kept');
        async.elapse(retry * 3);
        expect(reads(), 3);
      });
    });

    test('an answer kept on the device when another account is signed in '
        'already (its event still to come) does not count for the first', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        auth.user = lea;
        hold.complete();
        async.flushMicrotasks();
        expect(cache.households['peter']?.households, hasLength(2));
        expect(async.pendingTimers, isEmpty);
        // The first account again, before the other's event came.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        async.elapse(retry * 3);
        expect(reads(), 2, reason: 'kept: no more');
      });
    });

    test('a reload after the start whose answer is not kept on the device '
        'starts no asking', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.failWrites = 1;
        Object? error;
        unawaited(cubit.refresh().catchError((Object e) => error = e));
        async.flushMicrotasks();
        expect(error, isStateError);
        expect(async.pendingTimers, isEmpty);
        // The session's token refreshed: the same user again.
        _signIn(auth);
        async.elapse(retry * 2);
        expect(reads(), 2);
      });
    });

    test('a write that fails after another account signed in over the first '
        'starts no asking for theirs', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.member('lea', 'flat', 'WG');
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        signInLea();
        async.flushMicrotasks();
        expect(cache.households['lea']?.households, hasLength(1));
        cache.failWrites = 1;
        hold.complete();
        async.flushMicrotasks();
        expect(cache.failWrites, 0, reason: "the first one's write failed");
        expect(async.pendingTimers, isEmpty);
        // Their token refreshed.
        signInLea();
        async.elapse(retry * 2);
        expect(reads(), 2);
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );
      });
    });

    // Review 1: each read takes longer than the 3 s, as on weak reception.
    test('a slow read overtaken after 3 s by a second one: the second '
        "one's answer shows when it comes, and no third read drops it", () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 3200));
        // The session's token refreshed meanwhile: the same user again.
        final second = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        // A third read would not answer in this test.
        server.holdReads = Completer<void>();
        async.elapse(const Duration(milliseconds: 300));
        first.complete();
        async.elapse(const Duration(milliseconds: 3200));
        expect(cubit.state, isA<SessionLoading>());
        second.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 2);
        async.elapse(retry * 3);
        expect(reads(), 2, reason: 'answered: no more');
      });
    });

    test("the same with the device's households showing and a reload on "
        'coming back as the second read', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.only('peter', _home);
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 3200));
        final second = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        expect(reads(), 2);
        server.holdReads = Completer<void>();
        async.elapse(const Duration(milliseconds: 300));
        first.complete();
        async.elapse(const Duration(milliseconds: 3200));
        expect(cubit.state, _shows('home', households: ['home']));
        second.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 2);
      });
    });

    test('a first read that never answers, overtaken by a second one that '
        'failed: asked again 3 s after that one, the first is not waited '
        'for', () {
      started((async, server, cubit) {
        server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The session's token refreshed meanwhile: the same user again.
        server
          ..holdReads = null
          ..failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;

        async.elapse(retry - const Duration(milliseconds: 1));
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(const Duration(milliseconds: 1));
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('a second read still out when the 3 s are over is waited for, and '
        'asked again 3 s later once it failed', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.only('peter', _home);
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 3200));
        final second = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.holdReads = null;
        async.elapse(const Duration(milliseconds: 300));
        // 3.5 s: dropped as the older one. The 3 s after it end at 6.5 s.
        first.complete();
        async.elapse(const Duration(milliseconds: 3200));
        // 6.7 s: the second read is still out, so nothing was sent at 6.5 s.
        expect(reads(), 2);
        second.completeError(StateError('connection lost'));
        async.elapse(const Duration(milliseconds: 2799));
        expect(reads(), 2);
        expect(cubit.state, _shows('home', households: ['home']));
        // 9.5 s: three more seconds, and nothing is out.
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
      });
    });

    // Review 3: as before this job, where the retry never looked at reads.
    test('a read that failed is sent again after 3 s also while a second '
        'read is out: that one is not waited for', () {
      started((async, server, cubit) {
        server.failReads = true;
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The session's token refreshed meanwhile: a read that never answers.
        server
          ..failReads = false
          ..holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        server.holdReads = null;

        async.elapse(const Duration(milliseconds: 1999));
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(const Duration(milliseconds: 1));
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('a second read that is out but no longer the newest (an order '
        'change was refused meanwhile) is not waited for: its answer would '
        'be dropped too', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // A reload on coming back that never answers.
        server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(seconds: 1));
        // 2 s: dropped as the older one. The 3 s after it end at 5 s.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        server
          ..holdReads = null
          ..missing.add('reorder_households');
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 1999));
        expect(reads(), 2);
        expect(cubit.state, _shows('home', households: ['home', 'club']));

        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    // Review 6's rows: the order change is still on its way when the 3 s
    // after the dropped answer end. A read then answers the old order.
    test('after an answer dropped by an order change, the 3 s pass without a '
        'read while the order change is on its way: the old order does not '
        'come back', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first; the request takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped as the old order.
        first.complete();
        for (var ms = 1000; ms < 8200; ms += 100) {
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 1, reason: 'at ${ms + 100} ms');
        }
        // 8.2 s: the server has the order, and the order change reloads.
        sent.complete();
        async.flushMicrotasks();
        expect(reads(), 2);
        expect(cubit.state, _shows('home', households: ['club', 'home']));
        expect(server.memberships['peter'], ['club', 'home']);
        async.elapse(retry * 3);
        expect(reads(), 2, reason: 'answered: no more');
      });
    });

    test('after an answer dropped by an order change that the server then '
        'refuses, the households are read within 3 s of the refusal', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server
          ..holdReads = null
          ..missing.add('reorder_households');
        final sent = server.holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped. Its 3 s end at 4 s and at 7 s.
        first.complete();
        async.elapse(const Duration(milliseconds: 4500));
        expect(reads(), 1);
        expect(cubit.state, _shows('home', households: ['club', 'home']));
        // 5.5 s: refused, the order is back.
        sent.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 1);

        async.elapse(const Duration(milliseconds: 1500));
        expect(reads(), 2, reason: 'at 7 s');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    // Review 7's rows: the other way to a read, an auth event.
    for (final event in ['a token refresh', 'an offline token refresh']) {
      test('after an answer dropped by an order change, $event sends no read '
          'while the order change is on its way', () {
        started((async, server, cubit) {
          int reads() => server.calls
              .where((c) => c.startsWith('rpc/my_households'))
              .length;
          cache.households['peter'] = (
            households: [_home, _club],
            shown: 'home',
          );
          final first = server.holdReads = Completer<void>();
          _signIn(auth);
          async.elapse(const Duration(milliseconds: 200));
          server.holdReads = null;
          // Sommerfest dragged first; the request takes 8 s.
          final sent = server.holdReorder = Completer<void>();
          unawaited(cubit.reorderHouseholds(['club', 'home']));
          async.elapse(const Duration(milliseconds: 800));
          // 1 s: the start's answer, dropped as the old order.
          first.complete();
          async.elapse(const Duration(seconds: 1));
          // 2 s: the auth event.
          if (event == 'a token refresh') {
            _signIn(auth);
          } else {
            auth.states.addError(
              AuthRetryableFetchException(message: 'offline'),
            );
          }
          for (var ms = 2000; ms < 8200; ms += 100) {
            async.elapse(const Duration(milliseconds: 100));
            expect(
              cubit.state,
              _shows('home', households: ['club', 'home']),
              reason: 'at ${ms + 100} ms',
            );
            expect(
              [for (final h in cache.households['peter']!.households) h.id],
              ['club', 'home'],
              reason: 'the device at ${ms + 100} ms',
            );
            expect(reads(), 1, reason: 'at ${ms + 100} ms');
          }
          // 8.2 s: the server has the order, and the order change reloads.
          sent.complete();
          async.elapse(retry * 3);
          expect(reads(), 2, reason: 'answered: no more');
          expect(cubit.state, _shows('home', households: ['club', 'home']));
          expect(server.memberships['peter'], ['club', 'home']);
        });
      });
    }

    // The account's end ends the wait too: from there an auth event reads
    // whatever is on its way, as it did before this job.
    test('the account deleted after an answer dropped by an order change: a '
        'token refresh before the device signed out is not held by the order '
        'change, as before', () {
      fakeAsync((async) {
        final gated = _GatedCache()
          ..households['peter'] = (households: [_home, _club], shown: 'home');
        final server = FakeHouseholds(auth)
          ..member('peter', 'home', 'Zuhause')
          ..member('peter', 'club', 'Sommerfest');
        final cubit = SessionCubit(server, gated);
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first; the request takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped as the old order.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        // 2 s: the server deleted the account; the device has not signed
        // out yet.
        final forgetting = gated.forgetGate = Completer<void>();
        unawaited(
          cubit.accountDeleted(
            const AccountDeletedNotice(removeAppleManually: false),
          ),
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(reads(), 1);
        // 2.5 s: the token refreshed.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);

        forgetting.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        sent.complete();
        async.elapse(retry * 3);
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 2, reason: 'signed out: no more');
        unawaited(cubit.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an order change started after the answer was dropped, while it is '
        'written to the device and on its way: nothing is read', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // A reload that fails passes the start's read.
        server
          ..holdReads = null
          ..failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped. Its 3 s end at 4 s.
        first.complete();
        async.elapse(const Duration(milliseconds: 2900));
        expect(reads(), 2);
        // 3.9 s: Sommerfest dragged first. The device takes 2 s to keep the
        // order, the request 5 s more.
        final write = cache.holdWrites = Completer<void>();
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        cache.holdWrites = null;
        for (var ms = 3900; ms < 10900; ms += 100) {
          if (ms == 5900) {
            write.complete();
          }
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 2, reason: 'at ${ms + 100} ms');
        }
        // 10.9 s: the server has the order, and the order change reloads.
        sent.complete();
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'answered: no more');
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
      });
    });

    test('two order changes one behind the other: nothing is read until the '
        'second is answered, and its order stays', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        const garden = Household(id: 'garden', name: 'Garten');
        cache.households['peter'] = (
          households: [_home, _club, garden],
          shown: 'home',
        );
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        final one = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home', 'garden']));
        async.elapse(const Duration(milliseconds: 300));
        unawaited(cubit.reorderHouseholds(['garden', 'club', 'home']));
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: the start's answer, dropped. Its 3 s end at 4, 7 and 10 s.
        first.complete();
        async.elapse(const Duration(seconds: 4));
        // 5 s: the server has the first order; the second goes out.
        final two = server.holdReorder = Completer<void>();
        one.complete();
        for (var ms = 5000; ms < 12000; ms += 100) {
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['garden', 'club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 1, reason: 'at ${ms + 100} ms');
        }
        expect(server.memberships['peter'], ['club', 'home', 'garden']);
        // 12 s: the server has the second order, and it reloads.
        two.complete();
        async.elapse(retry * 3);
        expect(reads(), 2, reason: 'answered: no more');
        expect(
          cubit.state,
          _shows('home', households: ['garden', 'club', 'home']),
        );
        expect(server.memberships['peter'], ['garden', 'club', 'home']);
      });
    });

    test('after an answer dropped by an order change that the server never '
        'answers, the households are read within 3 s of the 15 s', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server
          ..holdReads = null
          ..holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped. Its 3 s end at 4, 7, 10, 13 and
        // 16 s; the order change gives up at 15.2 s.
        first.complete();
        async.elapse(const Duration(milliseconds: 14100));
        expect(reads(), 1, reason: 'at 15.1 s');
        expect(cubit.state, _shows('home', households: ['club', 'home']));
        async.elapse(const Duration(milliseconds: 200));
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 1, reason: 'at 15.3 s');

        async.elapse(const Duration(milliseconds: 700));
        expect(reads(), 2, reason: 'at 16 s');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('an order change that changes nothing holds nothing: a dropped '
        'answer is asked again after 3 s', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // A reload that fails passes the start's read.
        server
          ..holdReads = null
          ..failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 300));
        // 0.5 s: the row dropped where it was.
        unawaited(cubit.reorderHouseholds(['home', 'club']));
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: the start's answer, dropped. Its 3 s end at 4 s.
        first.complete();
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3, reason: 'at 4 s');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('a start read that failed is sent again after 3 s also while an '
        'order change is on its way, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server
          ..member('peter', 'garden', 'Garten')
          ..failReads = true;
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.failReads = false;
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 2700));
        expect(reads(), 1);
        async.elapse(const Duration(milliseconds: 200));
        expect(reads(), 2, reason: 'at 3.1 s');
        expect(
          cubit.state,
          isA<InHousehold>().having(
            (s) => {for (final h in s.households) h.id},
            'households',
            {'home', 'club', 'garden'},
          ),
        );
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        expect(reads(), 3, reason: "the order change's own reload");
        expect(async.pendingTimers, isEmpty);
      });
    });

    // Review 8's rows: an order change holds nothing but the asking after a
    // dropped answer, and what ends that wait ends it during one too.
    test('a start read that fails while an order change is already on its '
        'way is sent again after 3 s, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first; the request takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's read fails. Its 3 s end at 4 s.
        first.completeError(StateError('connection lost'));
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 2, reason: 'at 4 s');
        expect(
          cubit.state,
          isA<InHousehold>().having(
            (s) => {for (final h in s.households) h.id},
            'households',
            {'home', 'club', 'garden'},
          ),
        );
        async.elapse(const Duration(milliseconds: 4200));
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        expect(reads(), 3, reason: "the order change's own reload");
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an order change started while an older reload is still out, after '
        'the answer was dropped: nothing is read until it is answered', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // 0.2 s: a reload that takes 20 s passes the start's read.
        final reload = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(milliseconds: 800));
        server.holdReads = null;
        // 1 s: the start's answer, dropped. Its 3 s end at 4, 7 and 10 s.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        expect(reads(), 2);
        // 2 s: Sommerfest dragged first; the request takes 7.5 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        for (var ms = 2000; ms < 9500; ms += 100) {
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 2, reason: 'at ${ms + 100} ms');
        }
        // 9.5 s: the server has the order, and the order change reloads.
        sent.complete();
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'answered: no more');
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        // 20 s: the old reload's answer is dropped.
        async.elapse(const Duration(milliseconds: 1500));
        reload.complete();
        async.elapse(retry * 3);
        expect(reads(), 3);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
      });
    });

    test('signed out and in again while an order change is on its way after '
        'a dropped answer: the new start reads at once, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // Sommerfest dragged first; the server refuses it after 8 s.
        server
          ..holdReads = null
          ..missing.add('reorder_households');
        final sent = server.holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 300));
        // 0.5 s: the start's answer, dropped as the old order.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: signed out.
        unawaited(auth.signOut());
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 1);
        // 2 s: signed in again.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        async.elapse(const Duration(milliseconds: 6200));
        // 8.2 s: refused.
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(reads(), 2, reason: 'answered: no more');
      });
    });

    test('another account signed in while an order change is on its way '
        'after a dropped answer, and the first one back over theirs: read '
        'for at once, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server
          ..member('peter', 'garden', 'Garten')
          ..member('lea', 'flat', 'WG');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // Sommerfest dragged first; the server never answers.
        server
          ..holdReads = null
          ..holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 300));
        // 0.5 s: the start's answer, dropped as the old order.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: the other account.
        signInLea();
        async.elapse(const Duration(seconds: 2));
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );
        expect(reads(), 2);
        // 3 s: the first one again.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 3);
        final peters = isA<InHousehold>()
            .having((s) => s.userId, 'user', 'peter')
            .having((s) => s.households.map((h) => h.id), 'households', [
              'home',
              'club',
              'garden',
            ]);
        expect(cubit.state, peters);
        // 15.2 s: the order change gives up.
        async.elapse(retry * 6);
        expect(cubit.state, peters);
        expect(reads(), 3, reason: 'answered: no more');
      });
    });

    test('the account deleted after a dropped answer, no order change: each '
        'token refresh before the device signed out sends its read, also '
        'while the one before is out, as before', () {
      fakeAsync((async) {
        final gated = _GatedCache()
          ..households['peter'] = (households: [_home, _club], shown: 'home');
        final server = FakeHouseholds(auth)
          ..member('peter', 'home', 'Zuhause')
          ..member('peter', 'club', 'Sommerfest');
        final cubit = SessionCubit(server, gated);
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // A reload that fails passes the start's read.
        server
          ..holdReads = null
          ..failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        expect(reads(), 2);
        // 2 s: the server deleted the account; the device has not signed
        // out yet.
        final forgetting = gated.forgetGate = Completer<void>();
        unawaited(
          cubit.accountDeleted(
            const AccountDeletedNotice(removeAppleManually: false),
          ),
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(reads(), 2);
        // 2.5 s: the token refreshed; its read does not answer.
        server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        expect(reads(), 3);
        // 2.7 s: and again.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 4);

        forgetting.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        async.elapse(retry * 3);
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 4, reason: 'signed out: no more');
        unawaited(cubit.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    // Review 9's rows: the wait at each of its two doors (an auth event, the
    // timer), and review 8's rows with more on its way: a second order
    // change, an older reload, a device slow to forget the session.
    test('an order change started while an older reload is still out, after '
        'the answer was dropped: a token refresh reads nothing either', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // 0.2 s: a reload that takes 20 s passes the start's read.
        final reload = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(milliseconds: 800));
        server.holdReads = null;
        // 1 s: the start's answer, dropped. Its 3 s end at 4, 7 and 10 s.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        // 2 s: Sommerfest dragged first; the request takes 7.5 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(seconds: 1));
        // 3 s: the token refreshed.
        _signIn(auth);
        for (var ms = 3000; ms < 9500; ms += 100) {
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 2, reason: 'at ${ms + 100} ms');
        }
        // 9.5 s: the server has the order, and the order change reloads.
        sent.complete();
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'answered: no more');
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        // 20 s: the old reload's answer is dropped.
        async.elapse(const Duration(milliseconds: 1500));
        reload.complete();
        async.elapse(retry * 3);
        expect(reads(), 3);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
      });
    });

    test('an order change started while an older reload is still out, after '
        'the answer was dropped, and refused: the households are read '
        'within 3 s of the refusal', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // 0.2 s: a reload that takes 20 s passes the start's read.
        final reload = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(milliseconds: 800));
        server.holdReads = null;
        // 1 s: the start's answer, dropped. Its 3 s end at 4, 7 and 10 s.
        first.complete();
        async.elapse(const Duration(seconds: 1));
        // 2 s: Sommerfest dragged first; the server refuses it after 7.5 s.
        server.missing.add('reorder_households');
        final sent = server.holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        for (var ms = 2000; ms < 9500; ms += 100) {
          async.elapse(const Duration(milliseconds: 100));
          expect(
            cubit.state,
            _shows('home', households: ['club', 'home']),
            reason: 'at ${ms + 100} ms',
          );
          expect(reads(), 2, reason: 'at ${ms + 100} ms');
        }
        // 9.5 s: refused, and the row is back.
        sent.complete();
        async.elapse(const Duration(milliseconds: 499));
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3, reason: 'at 10 s');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        // 20 s: the old reload's answer is dropped.
        async.elapse(const Duration(seconds: 10));
        reload.complete();
        async.elapse(retry * 3);
        expect(reads(), 3, reason: 'answered: no more');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
      });
    });

    test('a start read that fails while two order changes are on their way '
        'is sent again after 3 s, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first and back again; the server takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 200));
        unawaited(cubit.reorderHouseholds(['home', 'club']));
        async.elapse(const Duration(milliseconds: 600));
        // 1 s: the start's read fails. Its 3 s end at 4 s.
        first.completeError(StateError('connection lost'));
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 2, reason: 'at 4 s');
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        async.elapse(const Duration(milliseconds: 4200));
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(reads(), 3, reason: "the second order change's own reload");
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a start read that fails while an order change is on its way and '
        'an older reload is still out is sent again after 3 s, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // 0.2 s: a reload that takes 20 s passes the start's read.
        final reload = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // 0.4 s: Sommerfest dragged first; the request takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 600));
        // 1 s: the start's read fails. Its 3 s end at 4 s.
        first.completeError(StateError('connection lost'));
        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3, reason: 'at 4 s');
        expect(
          cubit.state,
          isA<InHousehold>().having(
            (s) => {for (final h in s.households) h.id},
            'households',
            {'home', 'club', 'garden'},
          ),
        );
        async.elapse(const Duration(milliseconds: 4400));
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        expect(reads(), 4, reason: "the order change's own reload");
        // 20 s: the old reload's answer is dropped.
        async.elapse(const Duration(milliseconds: 2600));
        reload.complete();
        async.elapse(retry * 3);
        expect(reads(), 4);
        expect(
          cubit.state,
          _shows('home', households: ['club', 'home', 'garden']),
        );
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the account deleted after a dropped answer while a reload is out: '
        'each token refresh before the device signed out sends its read, as '
        'before', () {
      fakeAsync((async) {
        final gated = _GatedCache()
          ..households['peter'] = (households: [_home, _club], shown: 'home');
        final server = FakeHouseholds(auth)
          ..member('peter', 'home', 'Zuhause')
          ..member('peter', 'club', 'Sommerfest');
        final cubit = SessionCubit(server, gated);
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // A reload that fails passes the start's read.
        server
          ..holdReads = null
          ..failReads = true;
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(milliseconds: 800));
        // 1 s: the start's answer, dropped.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1.5 s: a reload that does not answer.
        server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(milliseconds: 500));
        expect(reads(), 3);
        // 2 s: the server deleted the account; the device has not signed
        // out yet.
        final forgetting = gated.forgetGate = Completer<void>();
        unawaited(
          cubit.accountDeleted(
            const AccountDeletedNotice(removeAppleManually: false),
          ),
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(reads(), 3);
        // 2.5 s: the token refreshed; its read does not answer.
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        expect(reads(), 4);
        // 2.7 s: and again.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 5);

        forgetting.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        async.elapse(retry * 3);
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 5, reason: 'signed out: no more');
        unawaited(cubit.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('signed out and in again before the device forgot the session, '
        'while an order change is on its way after a dropped answer: the '
        'new start reads at once, as before', () {
      fakeAsync((async) {
        final gated = _GatedCache()
          ..households['peter'] = (households: [_home, _club], shown: 'home');
        final server = FakeHouseholds(auth)
          ..member('peter', 'home', 'Zuhause')
          ..member('peter', 'club', 'Sommerfest')
          ..member('peter', 'garden', 'Garten');
        final cubit = SessionCubit(server, gated);
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        // Sommerfest dragged first; the server refuses it after 8 s.
        server
          ..holdReads = null
          ..missing.add('reorder_households');
        final sent = server.holdReorder = Completer<void>();
        unawaited(
          cubit.reorderHouseholds(['club', 'home']).catchError((Object _) {}),
        );
        async.elapse(const Duration(milliseconds: 300));
        // 0.5 s: the start's answer, dropped as the old order.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: signed out; the device takes 0.5 s to forget the session.
        final forgetting = gated.forgetGate = Completer<void>();
        unawaited(auth.signOut());
        async.elapse(const Duration(milliseconds: 200));
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 1);
        // 1.2 s: signed in again.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        async.elapse(const Duration(milliseconds: 300));
        forgetting.complete();
        async.elapse(const Duration(milliseconds: 6700));
        // 8.2 s: refused.
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(reads(), 2, reason: 'answered: no more');
        unawaited(cubit.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('signed out and in again while two order changes are on their way '
        'after a dropped answer: the new start reads at once, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server.member('peter', 'garden', 'Garten');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first and back again; the server takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 100));
        unawaited(cubit.reorderHouseholds(['home', 'club']));
        async.elapse(const Duration(milliseconds: 200));
        // 0.5 s: the start's answer, dropped as an old order.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: signed out.
        unawaited(auth.signOut());
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state, isA<SignedOut>());
        expect(reads(), 1);
        // 2 s: signed in again.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        async.elapse(const Duration(milliseconds: 6200));
        // 8.2 s: the server has both.
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(reads(), 3, reason: "the second order change's own reload");
      });
    });

    test('another account signed in while two order changes are on their '
        'way after a dropped answer, and the first one back over theirs: '
        'read for at once, as before', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.households['peter'] = (households: [_home, _club], shown: 'home');
        server
          ..member('peter', 'garden', 'Garten')
          ..member('lea', 'flat', 'WG');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 200));
        server.holdReads = null;
        // Sommerfest dragged first and back again; the server takes 8 s.
        final sent = server.holdReorder = Completer<void>();
        unawaited(cubit.reorderHouseholds(['club', 'home']));
        async.elapse(const Duration(milliseconds: 100));
        unawaited(cubit.reorderHouseholds(['home', 'club']));
        async.elapse(const Duration(milliseconds: 200));
        // 0.5 s: the start's answer, dropped as an old order.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 1 s: the other account.
        signInLea();
        async.elapse(const Duration(seconds: 2));
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );
        expect(reads(), 2);
        // 3 s: the first one again.
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        async.elapse(const Duration(milliseconds: 5200));
        // 8.2 s: the server has both.
        sent.complete();
        async.elapse(retry * 3);
        expect(
          cubit.state,
          _shows('home', households: ['home', 'club', 'garden']),
        );
        expect(reads(), 4, reason: "the second order change's own reload");
      });
    });

    // Review 6: what shows changes while the answer is written to the device.
    test('a household switched to while the start answer is written to the '
        'device: the answer counts, and nothing more is read', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final hold = cache.holdWrites = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        cache.holdWrites = null;
        unawaited(cubit.switchTo('club'));
        async.flushMicrotasks();
        expect(cubit.state, _shows('club', households: ['home', 'club']));
        hold.complete();
        async.elapse(const Duration(seconds: 10));
        expect(reads(), 1);
        expect(cubit.state, _shows('club', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty);
      });
    });

    // Review 3's rows: the second read is already out when the first fails.
    test('a read that failed while a second one was already out is sent '
        'again 3 s later all the same', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The session's token refreshed meanwhile: a read that never answers.
        server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        server.holdReads = null;
        first.completeError(StateError('connection lost'));

        async.elapse(retry - const Duration(milliseconds: 1));
        expect(reads(), 2);
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    // Review 4: a failure while the first failure's asking is armed.
    test('a second read that failed while the asking was armed is sent again '
        '3 s later too, whatever else is out', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.failReads = true;
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The session's token refreshed: a second read, which fails too.
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        expect(reads(), 2);
        // 2 s: a reload on coming back that never answers.
        server
          ..failReads = false
          ..holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.holdReads = null;

        async.elapse(const Duration(milliseconds: 1999));
        expect(reads(), 3);
        expect(cubit.state, isA<SessionLoading>());
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 4, reason: '3 s after the second failure');
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('the newest reload is waited for as long as it is out, not for 3 s '
        'only', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.only('peter', _home);
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        final second = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.elapse(const Duration(seconds: 1));
        server.holdReads = null;
        // 2 s: dropped as the older one. It looks again at 5, 8 and 11 s.
        first.complete();
        async.elapse(const Duration(seconds: 8));
        expect(reads(), 2);
        // 10 s.
        second.completeError(StateError('connection lost'));
        async.elapse(const Duration(milliseconds: 999));
        expect(reads(), 2);
        expect(cubit.state, _shows('home', households: ['home']));
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('a reload that starts within the 3 s after an answer was dropped '
        'is waited for too', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        cache.only('peter', _home);
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 500));
        // The session's token refreshed meanwhile: that read fails at once.
        server
          ..holdReads = null
          ..failReads = true;
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        server.failReads = false;
        // 1.5 s: dropped as the older one, and nothing is out. The 3 s after
        // it end at 4.5 s.
        first.complete();
        async.elapse(const Duration(milliseconds: 1500));
        // 3 s: a reload on coming back.
        final third = server.holdReads = Completer<void>();
        unawaited(cubit.refresh());
        async.flushMicrotasks();
        // A fourth read would never answer.
        server.holdReads = Completer<void>();
        async.elapse(const Duration(seconds: 3));
        expect(reads(), 3, reason: 'nothing sent at 4.5 s');
        expect(cubit.state, _shows('home', households: ['home']));
        third.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        async.elapse(retry * 2);
        expect(reads(), 3);
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    // Review 4: before this job a start whose read had come back, shown or
    // dropped, read no more. So after a dropped answer nothing may pass the
    // newest reload: no other read of the start that failed, no auth event.
    test('an answer was dropped and another read of the start failed: the '
        'newest reload is still waited for, not passed', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 500));
        // The session's token refreshed, twice.
        final second = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 500));
        final third = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 500));
        // A fourth read would never answer.
        server.holdReads = Completer<void>();
        // 1.5 s: dropped as an older one.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        // 2 s. The 3 s after it end at 5 s.
        second.completeError(StateError('connection lost'));
        async.elapse(retry);
        expect(reads(), 3, reason: 'nothing sent at 5 s');
        async.elapse(retry);
        // 8 s.
        third.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        async.elapse(retry * 2);
        expect(reads(), 3);
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test("an answer was dropped and the session's token refreshed while the "
        'newest reload is out: no read is sent, that reload is waited for', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 250));
        final second = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 250));
        // A third read would never answer.
        server.holdReads = Completer<void>();
        // 0.5 s: dropped as the older one.
        first.complete();
        async.elapse(const Duration(milliseconds: 1500));
        // 2 s.
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 750));
        expect(reads(), 2);
        expect(cubit.state, isA<SessionLoading>());
        second.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        async.elapse(retry * 2);
        expect(reads(), 2);
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('another account signed in over a start that waits, and the first '
        'one back over theirs: read for at once, their reload is not waited '
        'for', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.member('lea', 'flat', 'WG');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 250));
        // Reads that never answer: the token's refresh, then the other
        // account's start.
        server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(milliseconds: 250));
        // 0.5 s: dropped as the older one.
        first.complete();
        async.elapse(const Duration(milliseconds: 500));
        signInLea();
        async.elapse(const Duration(seconds: 1));
        expect(reads(), 3);

        server.holdReads = null;
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 4);
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'peter').having(
            (s) => s.households.map((h) => h.id),
            'households',
            ['home', 'club'],
          ),
        );
      });
    });

    test('signed out while the read was out: nothing is sent again', () {
      started((async, server, cubit) {
        server.failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        unawaited(auth.signOut());
        async.flushMicrotasks();
        final reads = server.calls.length;
        async.elapse(retry * 3);
        expect(cubit.state, isA<SignedOut>());
        expect(server.calls, hasLength(reads));
      });
    });

    test("another account signed in while the first one's read was out: "
        'that read coming back ends no asking for theirs', () {
      started((async, server, cubit) {
        server.member('lea', 'flat', 'WG');
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        unawaited(auth.signOut());
        async.flushMicrotasks();
        server
          ..holdReads = null
          ..failReads = true;
        signInLea();
        async.flushMicrotasks();
        server.failReads = false;
        hold.complete();
        async.flushMicrotasks();
        expect(cubit.state, isNot(isA<InHousehold>()));

        async.elapse(retry);
        expect(
          cubit.state,
          isA<InHousehold>()
              .having((s) => s.userId, 'user', 'lea')
              .having((s) => s.household.id, 'shown', 'flat'),
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test("another account signed in while the first one's read was out, "
        'which then failed: their own asking goes on', () {
      started((async, server, cubit) {
        server.member('lea', 'flat', 'WG');
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        server
          ..holdReads = null
          ..failReads = true;
        signInLea();
        async.flushMicrotasks();
        server.failReads = false;
        async.elapse(const Duration(seconds: 1));
        hold.completeError(StateError('connection lost'));
        async.elapse(const Duration(milliseconds: 1999));
        expect(cubit.state, isNot(isA<InHousehold>()));

        async.elapse(const Duration(milliseconds: 1));
        expect(
          cubit.state,
          isA<InHousehold>()
              .having((s) => s.userId, 'user', 'lea')
              .having((s) => s.household.id, 'shown', 'flat'),
          reason: "3 s after their read failed, not ended by the first one's",
        );
        expect(async.pendingTimers, isEmpty, reason: 'answered: no more');
      });
    });

    test('another account signed in over the first, whose read had failed: '
        "the first one's asking reads nothing for theirs", () {
      started((async, server, cubit) {
        server
          ..member('lea', 'flat', 'WG')
          ..failReads = true;
        _signIn(auth);
        async.flushMicrotasks();
        server.failReads = false;
        signInLea();
        async.flushMicrotasks();
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );

        final reads = server.calls.length;
        async.elapse(retry * 3);
        expect(server.calls, hasLength(reads));
      });
    });

    test('the same after a dropped answer: the asking it armed reads nothing '
        'for the account signed in over the first', () {
      started((async, server, cubit) {
        server.member('lea', 'flat', 'WG');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The session's token refreshed meanwhile: a read that never answers.
        server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // 2 s: dropped as the older one. The 3 s after it end at 5 s.
        server.holdReads = null;
        first.complete();
        async.elapse(const Duration(seconds: 1));
        signInLea();
        async.flushMicrotasks();
        expect(
          cubit.state,
          isA<InHousehold>().having((s) => s.userId, 'user', 'lea'),
        );

        final reads = server.calls.length;
        async.elapse(retry * 3);
        expect(server.calls, hasLength(reads));
      });
    });

    // Review 5's surviving mutants.
    test('an auth event while the start waits for the newest reload does not '
        'start the 3 s over', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        final second = server.holdReads = Completer<void>();
        unawaited(cubit.refresh().catchError((Object _) {}));
        async.flushMicrotasks();
        server.holdReads = null;
        first.complete();
        async.elapse(const Duration(seconds: 2));
        // The session's token refreshed: the same user again.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 2, reason: 'the newest reload is out');
        second.completeError(StateError('connection lost'));
        async.elapse(const Duration(milliseconds: 999));
        expect(reads(), 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(reads(), 3, reason: '3 s after the answer was dropped');
        expect(cubit.state, _shows('home', households: ['home', 'club']));
      });
    });

    test('a dropped answer that comes back after another account signed in '
        'is forgotten: the first, signing in again, is read at once', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        server.member('lea', 'flat', 'WG');
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // The other account's read does not answer in this test.
        server.holdReads = Completer<void>();
        signInLea();
        async.flushMicrotasks();
        expect(reads(), 2);
        first.complete();
        async.elapse(const Duration(seconds: 1));
        server.holdReads = null;
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 3);
        expect(cubit.state, _shows('home', households: ['home', 'club']));
      });
    });

    test('a sign-out forgets a dropped answer: the next start has seen '
        'nothing, so an auth event sends a read although one is out', () {
      started((async, server, cubit) {
        int reads() =>
            server.calls.where((c) => c.startsWith('rpc/my_households')).length;
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.elapse(const Duration(seconds: 1));
        // No later read answers in this test.
        server.holdReads = Completer<void>();
        unawaited(cubit.refresh());
        async.flushMicrotasks();
        first.complete();
        async.flushMicrotasks();
        unawaited(auth.signOut());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        auth.user = _user;
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 3);
        // The session's token refreshed: the same user again.
        _signIn(auth);
        async.flushMicrotasks();
        expect(reads(), 4);
      });
    });

    test('once the answer is kept, the asking of a dropped answer looks for '
        'nothing more, also while a later reload is out', () {
      started((async, server, cubit) {
        final first = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        final second = server.holdReads = Completer<void>();
        unawaited(cubit.refresh());
        async.flushMicrotasks();
        first.complete();
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        second.complete();
        async.flushMicrotasks();
        expect(cubit.state, _shows('home', households: ['home', 'club']));
        // A later reload does not answer in this test.
        server.holdReads = Completer<void>();
        unawaited(cubit.refresh());
        async.elapse(retry);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('signed out while the read was out, which then failed: nothing is '
        'asked again', () {
      started((async, server, cubit) {
        final hold = server.holdReads = Completer<void>();
        _signIn(auth);
        async.flushMicrotasks();
        unawaited(auth.signOut());
        async.flushMicrotasks();
        hold.completeError(StateError('connection lost'));
        async.flushMicrotasks();
        expect(cubit.state, isA<SignedOut>());
        expect(async.pendingTimers, isEmpty);
      });
    });

    // Real time: closing does not end under fake time.
    test('closed while the read was out, which then failed: nothing is '
        'asked again', () async {
      final server = FakeHouseholds(auth)..member('peter', 'home', 'Zuhause');
      final armed = <Duration>[];
      await runZoned(
        () async {
          final cubit = SessionCubit(server, cache);
          final hold = server.holdReads = Completer<void>();
          _signIn(auth);
          await pumpEventQueue();
          expect(server.calls.last, startsWith('rpc/my_households'));
          await cubit.close();
          hold.completeError(StateError('connection lost'));
          await pumpEventQueue();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, f) {
            armed.add(duration);
            return parent.createTimer(zone, duration, f);
          },
        ),
      );
      expect(armed.where((d) => d == retry), isEmpty);
    });
    test('a read that failed while the cubit was closing: the asking it '
        'armed sends nothing once closed', () async {
      final server = FakeHouseholds(auth)..member('peter', 'home', 'Zuhause');
      final armed = <void Function()>[];
      await runZoned(
        () async {
          final cubit = SessionCubit(server, cache);
          final hold = server.holdReads = Completer<void>();
          _signIn(auth);
          await pumpEventQueue();
          final closing = cubit.close();
          hold.completeError(StateError('connection lost'));
          await closing;
          await pumpEventQueue();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, f) {
            if (duration != retry) {
              return parent.createTimer(zone, duration, f);
            }
            // Fired below, by hand.
            armed.add(f);
            return parent.createTimer(zone, Duration.zero, () {});
          },
        ),
      );
      expect(armed, hasLength(1), reason: 'failed before the close ended');
      final reads = server.calls.length;
      armed.single();
      await pumpEventQueue();
      expect(server.calls, hasLength(reads));
    });
  });

  group('join approval (job 169b W3 M)', () {
    late FakeHouseholds server;
    late SessionCubit cubit;

    /// Realtime on join requests, by user: call one to say a request
    /// changed.
    late Map<String, void Function()> watching;
    late List<JoinDecision> told;

    setUp(() {
      watching = {};
      told = [];
      server = FakeHouseholds(auth)
        ..member('peter', 'home', 'Zuhause')
        ..member('lea', 'club', 'Sommerfest')
        ..approval.add('club')
        ..invites['CLUB2345'] = 'club';
      cubit = SessionCubit(
        server,
        cache,
        watchJoinRequests: (user, onChange) {
          watching[user] = onChange;
          return () async => watching.remove(user);
        },
      );
      cubit.joinDecisions.listen(told.add);
    });
    tearDown(() => cubit.close());

    List<JoinRequest> requestsOf(Session s) => switch (s) {
      InHousehold(:final requests) ||
      NeedsHousehold(:final requests) => requests,
      _ => const [],
    };

    test(
      'a join answered requested switches nothing and lists the request',
      () async {
        await cubit.refresh();
        final answer = await cubit.join('CLUB2345');
        expect(
          answer,
          isA<JoinRequested>().having(
            (a) => a.householdId,
            'household',
            'club',
          ),
        );
        expect(cubit.state, _shows('home', households: ['home']));
        expect(
          [
            for (final r in requestsOf(cubit.state))
              (r.householdId, r.householdName),
          ],
          [('club', 'Sommerfest')],
        );
        expect(watching.keys, [
          'peter',
        ], reason: 'realtime follows the request');
      },
    );

    test('a join within a day of a decline is refused as such and files '
        'no request', () async {
      server.declinedRecently.add('club');
      await cubit.refresh();
      await expectLater(
        cubit.join('CLUB2345'),
        _problem(HouseholdProblem.declinedRecently),
      );
      expect(cubit.state, _shows('home', households: ['home']));
      expect(requestsOf(cubit.state), isEmpty);
    });

    test('without a household the user waits in onboarding', () async {
      server
        ..memberships['peter']!.clear()
        ..households['home']!.members.clear();
      await cubit.refresh();
      expect(cubit.state, isA<NeedsHousehold>());
      await cubit.join('CLUB2345');
      expect(
        cubit.state,
        isA<NeedsHousehold>().having(
          (s) => [for (final r in s.requests) r.householdId],
          'requests',
          ['club'],
        ),
      );
    });

    test(
      'approved over realtime: the household shows and it is said',
      () async {
        await cubit.refresh();
        await cubit.join('CLUB2345');
        server.decide(server.requests.keys.single, approve: true);
        watching['peter']!();
        await pumpEventQueue();
        expect(cubit.state, _shows('club', households: ['home', 'club']));
        expect(requestsOf(cubit.state), isEmpty);
        expect(told, [(household: 'Sommerfest', approved: true)]);
        expect(watching, isEmpty, reason: 'nothing left to follow');
      },
    );

    test('approved while away: the refresh on resume finds it', () async {
      await cubit.refresh();
      await cubit.join('CLUB2345');
      server.decide(server.requests.keys.single, approve: true);
      await cubit.refresh();
      await pumpEventQueue();
      expect(cubit.state, _shows('club'));
      expect(told, [(household: 'Sommerfest', approved: true)]);
    });

    test('declined: the household shown stays and it is said', () async {
      await cubit.refresh();
      await cubit.join('CLUB2345');
      server.decide(server.requests.keys.single, approve: false);
      watching['peter']!();
      await pumpEventQueue();
      expect(cubit.state, _shows('home', households: ['home']));
      expect(requestsOf(cubit.state), isEmpty);
      expect(told, [(household: 'Sommerfest', approved: false)]);
    });

    test('two refreshes at once tell a decision once', () async {
      await cubit.refresh();
      await cubit.join('CLUB2345');
      server.decide(server.requests.keys.single, approve: true);
      await Future.wait([cubit.refresh(), cubit.refresh()]);
      await pumpEventQueue();
      expect(told, hasLength(1));
    });

    test('withdrawn: gone on the server, and no decision is said', () async {
      await cubit.refresh();
      await cubit.join('CLUB2345');
      await cubit.withdrawJoinRequest('club');
      await pumpEventQueue();
      expect(server.requests, isEmpty);
      expect(requestsOf(cubit.state), isEmpty);
      expect(told, isEmpty);
      expect(watching, isEmpty);
    });

    test('a server without join requests keeps the session working', () async {
      final old = FakeHouseholds(auth)
        ..member('peter', 'home', 'Zuhause')
        ..missing.add('my_join_requests');
      final oldCubit = SessionCubit(old, cache);
      addTearDown(oldCubit.close);
      await oldCubit.refresh();
      expect(
        old.calls.any((c) => c.startsWith('rpc/my_join_requests')),
        isTrue,
      );
      expect(oldCubit.state, _shows('home'));
    });

    test('join_approval comes from my_households', () async {
      server.member('peter', 'verein', 'Verein');
      server.approval.add('verein');
      await cubit.refresh();
      final state = cubit.state as InHousehold;
      expect(
        {for (final h in state.households) h.id: h.joinApproval},
        {'home': false, 'verein': true},
      );
      expect(
        Household.fromJson(state.households.last.toJson())?.joinApproval,
        isTrue,
      );
    });
  });
}

/// Holds its next [remember] until [gate] completes, after [onRemember],
/// and its next [forget] until [forgetGate] completes. Writes land in call
/// order, as DeviceCache's do.
class _GatedCache() extends MemorySessionCache {
  Completer<void>? gate;
  Completer<void>? forgetGate;
  void Function()? onRemember;
  var _last = Future<void>.value();

  @override
  Future<void> remember(
    String userId, {
    required List<Household> households,
    String? shown,
  }) async {
    final held = gate;
    gate = null;
    if (held != null) {
      onRemember?.call();
    }
    final previous = _last;
    final done = Completer<void>();
    _last = done.future;
    await previous;
    await held?.future;
    await super.remember(userId, households: households, shown: shown);
    done.complete();
  }

  @override
  Future<void> forget() async {
    final held = forgetGate;
    forgetGate = null;
    await held?.future;
    await super.forget();
  }
}
