import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/switcher_sheet.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../design/fonts.dart';
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// "Leute einladen" as a page of the switcher sheet.
final _invitePage = find.descendant(
  of: _key('switcher-sheet'),
  matching: _key('invite-sheet'),
);

const _home = Household(
  id: 'home',
  name: 'Zuhause',
  isDefault: true,
  memberCount: 3,
  openCount: 9,
  role: HouseholdRole.owner,
);
const _club = Household(
  id: 'club',
  name: 'Sommerfest',
  memberCount: 12,
  openCount: 1,
);

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _drugstore = HouseholdList(id: 'dm', name: 'Drogerie', position: 1);
const _party = HouseholdList(id: 'party', name: 'Grillen', position: 2);
const _drinks = HouseholdList(id: 'drinks', name: 'Getränke', position: 0);
const _food = HouseholdList(id: 'food', name: 'Essen', position: 1);

typedef _Shell = ({
  TestSession session,
  GoRouter router,
  FakeRepository home,
  FakeRepository club,
  FakeInvites invites,
});

/// The app's shell with Peter in Zuhause (shown, his default, he owns it,
/// three lists) and Sommerfest (two lists).
Future<_Shell> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),

  /// The status bar and the home indicator, as on an iPhone.
  ({double top, double bottom}) insets = (top: 0, bottom: 0),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('de'),
  List<Household> households = const [_home, _club],
  List<JoinRequest> requests = const [],
  List<HouseholdList> homeLists = const [_weekly, _drugstore, _party],
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..padding = FakeViewPadding(top: insets.top, bottom: insets.bottom)
    ..viewPadding = FakeViewPadding(top: insets.top, bottom: insets.bottom);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final cache = DeviceCache(SharedPreferencesAsync());
  final language = LanguageCubit(cache, AppLanguage.de);
  addTearDown(language.close);
  final session = TestSession(
    InHousehold('peter', households.first, households, requests: requests),
  );
  addTearDown(session.close);
  final at = DateTime.utc(2026, 11, 8, 12);
  Item item(String id, String name, String list) => Item(
    id: id,
    name: name,
    listId: list,
    status: ItemStatus.active,
    createdAt: at,
    updatedAt: at,
  );
  final home = FakeRepository()..lists = homeLists;
  home.rows
    ..['milk'] = item('milk', 'Milch', 'weekly')
    ..['soap'] = item('soap', 'Seife', 'dm');
  final club = FakeRepository()..lists = const [_drinks, _food];
  club.rows['wurst'] = item('wurst', 'Bratwurst', 'food');
  final invites = FakeInvites()
    ..memberLists['home'] = const [
      HouseholdMember(
        userId: 'peter',
        displayName: 'Peter',
        role: HouseholdRole.owner,
      ),
      HouseholdMember(userId: 'lea', displayName: 'Lea'),
      HouseholdMember(userId: 'tom', displayName: 'Tom'),
    ]
    ..memberLists['club'] = const [
      HouseholdMember(userId: 'anna', displayName: 'Anna'),
      HouseholdMember(userId: 'peter', displayName: 'Peter'),
    ];
  final servers = {'home': home, 'club': club};
  final popups = Popups();
  addTearDown(popups.dispose);
  final router = GoRouter(
    observers: [popups],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            AppShell(shell: shell, repositories: (id) => servers[id]!),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: listPath, builder: (_, _) => const ListScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: morePath,
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(path: 'join', builder: (_, _) => const Text('JOIN')),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: newHouseholdPath, builder: (_, _) => const Text('NEW')),
    ],
  );
  addTearDown(router.dispose);
  final purchases = TestPurchases(session: session);
  addTearDown(purchases.close);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: cache),
        RepositoryProvider<PremiumServer>.value(value: purchases.premium),
        RepositoryProvider<InviteRepository>.value(value: invites),
        RepositoryProvider<InviteSharer>.value(value: FakeSharer()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: session),
          BlocProvider.value(value: language),
          BlocProvider.value(value: Analytics.off(cache)),
          BlocProvider.value(value: purchases.entitlements),
          BlocProvider.value(value: purchases.purchases),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(brightness),
          locale: locale,
          routerConfig: router,
          builder: (context, child) =>
              NoticesHost(popups: popups, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    session: session,
    router: router,
    home: home,
    club: club,
    invites: invites,
  );
}

Future<void> _open(WidgetTester tester) async {
  final context = tester.element(find.byType(ListScreen));
  // As the list header's switcher does (list_screen.dart).
  unawaited(showSwitcherSheet(context));
  await tester.pumpAndSettle();
}

ListCubit _shownList(WidgetTester tester) =>
    tester.element(find.byType(ListScreen)).read<ListCubit>();

/// The names of the switcher's rows of [prefix] (`switcher-list-`,
/// `household-row-`), top to bottom.
List<String> _rowTitles(WidgetTester tester, String prefix) {
  final tiles = tester.widgetList<ListTile>(
    find.byWidgetPredicate(
      (w) =>
          w is ListTile &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(prefix) &&
          !(w.key! as ValueKey<String>).value.endsWith('-new'),
    ),
  );
  final rows = [
    for (final tile in tiles)
      (tester.getTopLeft(find.byWidget(tile)).dy, (tile.title! as Text).data!),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final r in rows) r.$2];
}

/// Holds [from] down, then drags it [rows] rows down (negative: up).
Future<void> _drag(WidgetTester tester, Finder from, double rows) async {
  final height = tester.getSize(from).height;
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(0, height * rows / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The custom actions of the row [row] finds, by label.
List<String> _actions(WidgetTester tester, FinderBase<SemanticsNode> row) => [
  for (final id
      in row.evaluate().single.getSemanticsData().customSemanticsActionIds ??
          const <int>[])
    ?CustomSemanticsAction.getAction(id)?.label,
];

Future<void> _back(WidgetTester tester) async {
  await tester.tap(_key('switcher-back'));
  await tester.pumpAndSettle();
}

/// Android's back button.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await fakeSupabase();
    await loadAppFonts();
  });

  testWidgets('opens on the shown household: its name with Einladen, the '
      'members row, its lists with the shown one checked', (tester) async {
    await _pump(tester);
    await _open(tester);
    expect(_key('switcher-sheet'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('switcher-household-name'),
        matching: find.text('Zuhause'),
      ),
      findsOneWidget,
    );
    expect(find.text('2 offen'), findsOneWidget, reason: 'open items now');
    expect(
      find.descendant(
        of: _key('switcher-invite'),
        matching: find.text('Einladen'),
      ),
      findsOneWidget,
    );
    expect(find.text('Haushalte'), findsOneWidget, reason: 'the back row');
    expect(find.text('3 Mitglieder'), findsOneWidget);
    expect(_rowTitles(tester, 'switcher-list-'), [
      'Wocheneinkauf',
      'Drogerie',
      'Grillen',
    ]);
    expect(
      find.descendant(
        of: _key('switcher-list-weekly'),
        matching: _key('switcher-list-current'),
      ),
      findsOneWidget,
    );
    expect(_key('switcher-list-new'), findsOneWidget);
    // The name row has no icon in front: the name starts at the rows' text.
    final name = tester.getTopLeft(
      find.descendant(
        of: _key('switcher-household-name'),
        matching: find.text('Zuhause'),
      ),
    );
    final listText = tester.getTopLeft(
      find.descendant(
        of: _key('switcher-list-weekly'),
        matching: find.text('Wocheneinkauf'),
      ),
    );
    expect(name.dx, lessThan(listText.dx));
  });

  testWidgets('households > household > members, and back with the back row '
      'and the system back', (tester) async {
    await _pump(tester);
    await _open(tester);
    await _back(tester);
    expect(_key('switcher-households'), findsOneWidget);
    expect(find.text('Deine Haushalte'), findsOneWidget);
    expect(_key('household-new'), findsOneWidget);
    expect(_key('household-join'), findsOneWidget);
    expect(_key('household-default-row'), findsOneWidget);

    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _key('switcher-household-name'),
        matching: find.text('Sommerfest'),
      ),
      findsOneWidget,
    );
    expect(_rowTitles(tester, 'switcher-list-'), ['Getränke', 'Essen']);
    expect(
      _key('switcher-list-current'),
      findsNothing,
      reason: 'no list of Sommerfest is on screen',
    );
    expect(
      (tester.state(find.byType(MaterialApp)).context.read<SessionCubit>().state
              as InHousehold)
          .household
          .id,
      'home',
      reason: 'opening a household switches nothing',
    );

    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    expect(find.text('Mitglieder'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Peter (du)'), findsOneWidget);
    expect(find.text('Sommerfest'), findsOneWidget, reason: 'the back row');

    await _back(tester);
    expect(_key('switcher-lists-page'), findsOneWidget);
    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    await _systemBack(tester);
    expect(_key('switcher-lists-page'), findsOneWidget);
    expect(find.text('Sommerfest'), findsOneWidget);
    await _systemBack(tester);
    expect(_key('switcher-households'), findsOneWidget);
    await _systemBack(tester);
    expect(_key('switcher-sheet'), findsNothing, reason: 'then it closes');
  });

  testWidgets('household rows have no invite button; a chevron, the check on '
      'the shown one', (tester) async {
    await _pump(tester);
    await _open(tester);
    await _back(tester);
    expect(find.byKey(const ValueKey('household-invite-home')), findsNothing);
    expect(find.byKey(const ValueKey('household-invite-club')), findsNothing);
    expect(find.byIcon(Icons.person_add_outlined), findsNothing);
    for (final id in ['home', 'club']) {
      expect(
        find.descendant(
          of: _key('household-row-$id'),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: _key('household-row-home'),
        matching: _key('household-current'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a list of the shown household shows; the sheet closes', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester);
    await tester.tap(_key('switcher-list-dm'));
    await tester.pumpAndSettle();
    expect(_key('switcher-sheet'), findsNothing);
    expect(_shownList(tester).state.shownList?.id, 'dm');
    expect((s.session.state as InHousehold).household.id, 'home');
    expect(find.text('Seife'), findsOneWidget);
    expect(find.text('Milch'), findsNothing);
  });

  testWidgets('a list of another household: that household and that list '
      'show', (tester) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    final held = tester.element(_key('switcher-lists-page')).read<ListCubit>();
    await tester.tap(_key('switcher-list-food'));
    await tester.pumpAndSettle();
    expect(_key('switcher-sheet'), findsNothing);
    expect((s.session.state as InHousehold).household.id, 'club');
    expect(
      _shownList(tester),
      same(held),
      reason: 'the list the sheet opened is the one shown now',
    );
    expect(_shownList(tester).state.shownList?.id, 'food');
    expect(find.text('Bratwurst'), findsOneWidget);
    expect(held.isClosed, isFalse);
  });

  testWidgets('a household opened and left again closes its list', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    final held = tester.element(_key('switcher-lists-page')).read<ListCubit>();
    expect(held.isClosed, isFalse);
    await _back(tester);
    expect(held.isClosed, isTrue, reason: 'nothing queued: closed at once');
  });

  testWidgets("a refused change to another household's list is told", (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    s.club.reject = true;
    await _drag(tester, _key('switcher-list-food'), -1);
    expect(
      find.text('Die Änderung konnte nicht gespeichert werden.'),
      findsOneWidget,
    );
    expect(_rowTitles(tester, 'switcher-list-'), ['Getränke', 'Essen']);
  });

  testWidgets(
    'a tap beside the sheet closes it from an inner page',
    (tester) async {
      await _pump(tester);
      await _open(tester);
      await tester.tap(_key('switcher-members'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 10));
      await tester.pumpAndSettle();
      expect(_key('switcher-sheet'), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('long-press then drag orders the lists; the server keeps it', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester);
    await _drag(tester, _key('switcher-list-weekly'), 1);
    expect(s.home.catalogCalls, contains('moveList(weekly, 1)'));
    expect([for (final l in s.home.lists) l.id], ['dm', 'weekly', 'party']);
    expect(_rowTitles(tester, 'switcher-list-'), [
      'Drogerie',
      'Wocheneinkauf',
      'Grillen',
    ]);
    expect(
      find.byKey(const ValueKey('list-up')),
      findsNothing,
      reason: 'the menu has no move entries',
    );
    await tester.tap(_key('switcher-list-actions-party'));
    await tester.pumpAndSettle();
    expect(_key('list-rename'), findsOneWidget);
    expect(_key('list-delete'), findsOneWidget);
    expect(find.text('Nach oben'), findsNothing);
    expect(find.text('Nach unten'), findsNothing);
  });

  testWidgets('a quick tap on a list is no drag', (tester) async {
    final s = await _pump(tester);
    await _open(tester);
    await tester.tap(_key('switcher-list-party'));
    await tester.pumpAndSettle();
    expect(s.home.catalogCalls, isNot(contains(startsWith('moveList'))));
    expect(_shownList(tester).state.shownList?.id, 'party');
  });

  testWidgets('long-press then drag orders the households; the session '
      'keeps it', (tester) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    await _drag(tester, _key('household-row-club'), -1.6);
    expect(s.session.reorders, [
      ['club', 'home'],
    ]);
    expect(
      [for (final h in (s.session.state as InHousehold).households) h.id],
      ['club', 'home'],
    );
    expect(_rowTitles(tester, 'household-row-'), ['Sommerfest', 'Zuhause']);
  });

  testWidgets('a refused household order goes back and is told', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    s.session.fail = HouseholdProblem.offline;
    await _drag(tester, _key('household-row-club'), -1.6);
    expect(_rowTitles(tester, 'household-row-'), ['Zuhause', 'Sommerfest']);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('screen readers move lists and households with Nach oben and '
      'Nach unten', (tester) async {
    final handle = tester.ensureSemantics();
    final s = await _pump(tester);
    await _open(tester);
    const up = CustomSemanticsAction(label: 'Nach oben');
    const down = CustomSemanticsAction(label: 'Nach unten');
    final first = find.semantics.byLabel(RegExp('^Wocheneinkauf'));
    final last = find.semantics.byLabel(RegExp('^Grillen'));
    expect(_actions(tester, first), ['Nach unten']);
    expect(_actions(tester, last), ['Nach oben']);
    expect(
      _actions(tester, find.semantics.byLabel(RegExp('^Drogerie'))),
      unorderedEquals(['Nach oben', 'Nach unten']),
    );
    expect(
      first.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'one node: the row picks the list and moves',
    );
    tester.semantics.customAction(first, down);
    await tester.pumpAndSettle();
    expect(s.home.catalogCalls, contains('moveList(weekly, 1)'));
    expect(_rowTitles(tester, 'switcher-list-'), [
      'Drogerie',
      'Wocheneinkauf',
      'Grillen',
    ]);

    await _back(tester);
    tester.semantics.customAction(
      find.semantics.byLabel(RegExp('^Sommerfest')),
      up,
    );
    await tester.pumpAndSettle();
    expect(s.session.reorders, [
      ['club', 'home'],
    ]);
    handle.dispose();
  });

  testWidgets('Einladen opens the invite page of that household in the '
      'sheet; back reaches its members with the new invite', (tester) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    await tester.tap(_key('switcher-invite'));
    await tester.pumpAndSettle();
    expect(_invitePage, findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'no 2nd sheet');
    expect(
      find.descendant(of: _invitePage, matching: find.text('Sommerfest')),
      findsOneWidget,
    );
    await tester.tap(_key('invite-new'));
    await tester.pumpAndSettle();
    expect(s.invites.created, hasLength(1));
    await _back(tester);
    expect(_key('switcher-members-page'), findsOneWidget);
    expect(find.text('OFFENE EINLADUNGEN'), findsOneWidget);
    await _back(tester);
    expect(find.text('12 Mitglieder · 1 Einladung offen'), findsOneWidget);
  });

  testWidgets('members page: open invites are withdrawn; Leute einladen '
      'opens the invite page, back returns', (tester) async {
    final s = await _pump(tester);
    final invite = await s.invites.create('home');
    await s.invites.create('home');
    await _open(tester);
    expect(find.text('3 Mitglieder · 2 Einladungen offen'), findsOneWidget);
    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    expect(find.text('OFFENE EINLADUNGEN'), findsOneWidget);
    expect(find.text('Code ${invite.code}'), findsOneWidget);
    await tester.tap(_key('switcher-invite-revoke-${invite.id}'));
    await tester.pumpAndSettle();
    expect(s.invites.revoked, [invite.id]);
    expect(find.text('Code ${invite.code}'), findsNothing);
    await _back(tester);
    expect(find.text('3 Mitglieder · 1 Einladung offen'), findsOneWidget);

    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    await tester.tap(_key('switcher-members-invite'));
    await tester.pumpAndSettle();
    expect(_invitePage, findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'no 2nd sheet');
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: _key('switcher-back'),
              matching: find.byType(Text),
            ),
          )
          .data,
      'Mitglieder',
    );
    await _systemBack(tester);
    expect(_key('switcher-members-page'), findsOneWidget);
    expect(_invitePage, findsNothing);
  });

  for (final (name, size, insets, scale) in const [
    ('iPhone', Size(390, 844), (top: 47.0, bottom: 34.0), 1.0),
    ('iPhone SE', Size(375, 667), (top: 20.0, bottom: 0.0), 1.0),
    ('358 px at 130 % text', Size(358, 640), (top: 24.0, bottom: 0.0), 1.3),
  ]) {
    testWidgets('$name: the invite page stays below the status bar with the '
        'drag handle and Schließen; it scrolls inside the sheet', (
      tester,
    ) async {
      final s = await _pump(
        tester,
        size: size,
        insets: insets,
        textScale: scale,
      );
      // As on Peter's phone: the group link's card with its QR code.
      await s.invites.create('home', kind: InviteKind.group);
      await _open(tester);
      await tester.tap(_key('switcher-members'));
      await tester.pumpAndSettle();
      await tester.tap(_key('switcher-members-invite'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(insets.top), reason: '$sheet');
      expect(sheet.bottom, size.height);
      final close = _key('switcher-close');
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close).top, greaterThan(insets.top));
      expect(_key('switcher-back').hitTestable(), findsOneWidget);
      // The group link's last action, below the fold on every phone.
      final renew = _key('invite-group-renew');
      expect(renew.hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        renew,
        200,
        scrollable: find
            .descendant(of: _invitePage, matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(renew);
      await tester.pumpAndSettle();
      expect(renew.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(renew).bottom,
        lessThanOrEqualTo(size.height - insets.bottom),
      );
      expect(tester.getRect(close).top, greaterThan(insets.top));
      expect(tester.takeException(), isNull);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  }

  testWidgets('Schließen closes the sheet from every page', (tester) async {
    await _pump(tester);
    for (final open in [
      <String>[],
      ['switcher-members'],
      ['switcher-members', 'switcher-members-invite'],
    ]) {
      await _open(tester);
      for (final k in open) {
        await tester.tap(_key(k));
        await tester.pumpAndSettle();
      }
      await tester.tap(_key('switcher-close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing, reason: '$open');
    }
  });

  testWidgets('the owner removes a member after confirming', (tester) async {
    final s = await _pump(tester);
    await _open(tester);
    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    expect(_key('member-actions-peter'), findsNothing, reason: 'not oneself');
    await tester.tap(_key('member-actions-lea'));
    await tester.pumpAndSettle();
    expect(_key('member-makeAdmin'), findsOneWidget);
    await tester.tap(_key('member-remove'));
    await tester.pumpAndSettle();
    expect(_key('member-remove-dialog'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(s.invites.removed, isEmpty, reason: 'cancel keeps Lea');

    await tester.tap(_key('member-actions-lea'));
    await tester.pumpAndSettle();
    await tester.tap(_key('member-remove'));
    await tester.pumpAndSettle();
    await tester.tap(_key('member-remove-confirm'));
    await tester.pumpAndSettle();
    expect(s.invites.removed, [('home', 'lea')]);
    expect(find.text('Lea'), findsNothing);
    expect(find.text('Tom'), findsOneWidget);
  });

  testWidgets('a plain member removes nobody', (tester) async {
    await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    await tester.tap(_key('switcher-members'));
    await tester.pumpAndSettle();
    expect(find.text('Anna'), findsOneWidget);
    expect(_key('member-actions-anna'), findsNothing);
  });

  testWidgets('one household: back reaches Neuer Haushalt', (tester) async {
    final s = await _pump(tester, households: const [_home]);
    await _open(tester);
    expect(_key('switcher-household-name'), findsOneWidget);
    await _back(tester);
    await tester.tap(_key('household-new'));
    await tester.pumpAndSettle();
    expect(
      s.router.routerDelegate.currentConfiguration.uri.toString(),
      newHouseholdPath,
    );
  });

  testWidgets('a join request waiting shows on the first page and can be '
      'withdrawn', (tester) async {
    final s = await _pump(
      tester,
      requests: const [
        JoinRequest(id: 'r1', householdId: 'wg', householdName: 'WG'),
      ],
    );
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-request-wg'));
    await tester.pumpAndSettle();
    await tester.tap(_key('join-request-withdraw-confirm'));
    await tester.pumpAndSettle();
    expect(s.session.withdrawn, ['wg']);
  });

  testWidgets('Neue Liste adds a list to the household on the page', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester);
    await _back(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    await tester.tap(_key('switcher-list-new'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('name-dialog-field'), 'Deko');
    await tester.tap(_key('name-dialog-confirm'));
    await tester.pumpAndSettle();
    expect(
      [for (final l in s.club.lists) l.name],
      ['Getränke', 'Essen', 'Deko'],
    );
    expect([for (final l in s.home.lists) l.name], hasLength(3));
  });

  testWidgets('a long page scrolls inside the sheet', (tester) async {
    await _pump(
      tester,
      size: const Size(358, 640),
      textScale: 1.3,
      homeLists: [
        for (var i = 0; i < 16; i++)
          HouseholdList(id: 'l$i', name: 'Liste $i', position: i),
      ],
    );
    await _open(tester);
    final sheet = find.descendant(
      of: _key('switcher-sheet'),
      matching: find.byType(Scrollable),
    );
    expect(_key('switcher-list-new').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      _key('switcher-list-new'),
      200,
      scrollable: sheet.first,
    );
    await tester.tap(_key('switcher-list-new'));
    await tester.pumpAndSettle();
    expect(_key('name-dialog-field'), findsOneWidget);
  });

  for (final (scale, brightness, locale) in const [
    (1.3, Brightness.light, Locale('de')),
    (1.6, Brightness.dark, Locale('en')),
    (1.6, Brightness.light, Locale('de')),
  ]) {
    testWidgets('every page fits at ${(scale * 100).round()} % text, '
        '${brightness.name}, ${locale.languageCode}', (tester) async {
      final s = await _pump(
        tester,
        size: const Size(358, 700),
        textScale: scale,
        brightness: brightness,
        locale: locale,
      );
      await s.invites.create('home');
      await s.session.rename('home', 'Familie Trost-Brandt in der Waldstraße');
      await tester.pumpAndSettle();
      await _open(tester);
      final invite = tester.getSize(_key('switcher-invite'));
      expect(invite.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(_key('switcher-back')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(_key('switcher-members'));
      await tester.pumpAndSettle();
      await _back(tester);
      await _back(tester);
      expect(_key('switcher-households'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('screenshots (job 242)', () {
    for (final (name, size, insets) in const [
      ('iphone', Size(390, 844), (top: 47.0, bottom: 34.0)),
      ('compact', Size(358, 640), (top: 20.0, bottom: 0.0)),
    ]) {
      for (final (locale, brightness) in const [
        (Locale('de'), Brightness.dark),
        (Locale('en'), Brightness.light),
      ]) {
        final shot = 'goldens/switcher-invite-$name-${locale.languageCode}';
        testWidgets('$shot: the invite page, top and scrolled to its end', (
          tester,
        ) async {
          final s = await _pump(
            tester,
            size: size,
            insets: insets,
            brightness: brightness,
            locale: locale,
          );
          // „gültig bis“ shows local time: the same on CI (UTC) and here.
          s.invites.created.add(
            Invite(
              id: 'group',
              code: 'GRUPPE42',
              expiresAt: DateTime(2026, 12, 8, 10, 30).toUtc(),
              kind: InviteKind.group,
              maxUses: 50,
            ),
          );
          await _open(tester);
          await tester.tap(_key('switcher-members'));
          await tester.pumpAndSettle();
          await tester.tap(_key('switcher-members-invite'));
          await tester.pumpAndSettle();
          final screen = find.byType(MaterialApp);
          await expectLater(screen, matchesGoldenFile('$shot-top.png'));
          await tester.dragFrom(
            tester.getCenter(_invitePage),
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
          await expectLater(screen, matchesGoldenFile('$shot-end.png'));
        });
      }
    }
  });
}
