import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
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
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/shell/shell.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  role: HouseholdRole.owner,
);
const _club = Household(id: 'club', name: 'Sommerfest', memberCount: 12);

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

  /// The PostHog flags on.
  Set<String> flags = const {},
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
  session.householdLists
    ..['home'] = homeLists
    ..['club'] = const [_drinks, _food];
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
          BlocProvider(create: (_) => Flags(forced: flags)),
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

/// The switcher sheet on its first page, the households.
Future<void> _openHouseholds(WidgetTester tester) async {
  await _open(tester);
  await _back(tester);
}

/// What [text] shows, without its leading icon placeholder.
String _shown(Text text) =>
    (text.data ??
            text.textSpan?.toPlainText(includeSemanticsLabels: false) ??
            '')
        .replaceFirst(RegExp(r'^\uFFFC', unicode: true), '')
        .trim();

/// [text] in the row for Siri, Alexa & KI.
Finder _inVoiceRow(String text) => find.descendant(
  of: _key('household-default-row'),
  matching: find.byWidgetPredicate((w) => w is Text && _shown(w) == text),
);

/// The voice row's list line: the list's name, nothing else.
String? _voiceList(WidgetTester tester) => switch (find
    .byKey(const ValueKey('household-default-list-name'))
    .evaluate()
    .firstOrNull
    ?.widget) {
  final Text text => _shown(text),
  _ => null,
};

/// [text] laid out whole: every line it needs, none cut.
void _unclipped(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(
      paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.01,
    ),
  );
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
    expect(
      find.descendant(
        of: find.ancestor(
          of: _key('switcher-household-name'),
          matching: find.byType(Row),
        ),
        matching: find.textContaining('offen'),
      ),
      findsNothing,
      reason: 'no count of open items for the household (job 474)',
    );
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
      expect(
        tester.getRect(renew).bottom,
        greaterThan(size.height - insets.bottom),
      );
      final before = tester.getRect(renew).top;
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
        before - tester.getRect(renew).top,
        greaterThan(0),
        reason: 'the sheet scrolled',
      );
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

  group('household controls moved from More (job 258)', () {
    testWidgets('rename: an empty name is refused, a new one saved', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _open(tester);
      await tester.tap(_key('switcher-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('household-rename-field'), '   ');
      await tester.tap(_key('household-rename-save'));
      await tester.pumpAndSettle();
      expect(_key('household-rename-dialog'), findsOneWidget);
      expect(s.session.renames, isEmpty);
      await tester.enterText(_key('household-rename-field'), 'Wohnung ');
      await tester.tap(_key('household-rename-save'));
      await tester.pumpAndSettle();
      expect(s.session.renames, [('home', 'Wohnung')]);
    });

    testWidgets('leave: cancel leaves nothing, confirm leaves and closes the '
        'sheet', (tester) async {
      final s = await _pump(tester);
      await _open(tester);
      await tester.ensureVisible(_key('switcher-leave'));
      await tester.tap(_key('switcher-leave'));
      await tester.pumpAndSettle();
      expect(_key('household-leave-dialog'), findsOneWidget);
      await tester.tap(_key('household-leave-cancel'));
      await tester.pumpAndSettle();
      expect(s.session.leaves, isEmpty);
      expect(_key('switcher-sheet'), findsOneWidget);

      await tester.ensureVisible(_key('switcher-leave'));
      await tester.tap(_key('switcher-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-confirm'));
      await tester.pumpAndSettle();
      expect(s.session.leaves, [('home', false)]);
      expect(_key('switcher-sheet'), findsNothing);
    });

    testWidgets('leave closes the sheet also when the reload after it is '
        'slow (the page fades out first)', (tester) async {
      final s = await _pump(tester);
      s.session.afterLeave = Completer<void>();
      await _open(tester);
      await tester.ensureVisible(_key('switcher-leave'));
      await tester.tap(_key('switcher-leave'));
      await tester.pumpAndSettle();
      await tester.tap(_key('household-leave-confirm'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      s.session.afterLeave!.complete();
      await tester.pumpAndSettle();
      expect(s.session.leaves, [('home', false)]);
      expect(_key('switcher-sheet'), findsNothing);
    });

    testWidgets('leave: a double tap opens one dialog', (tester) async {
      await _pump(tester);
      await _open(tester);
      await tester.ensureVisible(_key('switcher-leave'));
      await tester.tap(_key('switcher-leave'));
      await tester.tap(_key('switcher-leave'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_key('household-leave-dialog'), findsOneWidget);
    });

    testWidgets('join approval: owner sees the switch, a plain member '
        'does not', (tester) async {
      await _pump(tester);
      await _open(tester);
      await tester.ensureVisible(_key('join-approval-switch'));
      expect(_key('join-approval-switch'), findsOneWidget);
      await _back(tester);
      await tester.tap(_key('household-row-club'));
      await tester.pumpAndSettle();
      expect(_key('join-approval-switch'), findsNothing);
    });

    for (final (locale, toggle, hint) in [
      (
        const Locale('de'),
        'Beitritte bestätigen',
        'Neue Leute warten, bis ein Admin sie aufnimmt.',
      ),
      (
        const Locale('en'),
        'Confirm new members',
        'New people wait until an admin lets them in.',
      ),
    ]) {
      testWidgets('join approval: the switch and its explainer are one stop '
          '(job 474, $locale)', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, locale: locale);
        await _open(tester);
        await tester.ensureVisible(_key('join-approval-switch'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(_key('join-approval-switch')),
          isSemantics(
            label: '$toggle\n$hint',
            hasToggledState: true,
            hasTapAction: true,
          ),
        );
        expect(
          find.semantics.byPredicate(
            (n) => n.label.contains(hint) && !n.label.contains(toggle),
          ),
          findsNothing,
          reason: 'no stop of its own for the explainer',
        );
        semantics.dispose();
      });
    }

    testWidgets('the household reads without a count of open items; its '
        'lists keep theirs (job 474)', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      await _open(tester);
      final labels = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.label)
          .toList();
      final name = labels.indexOf('Zuhause');
      expect(name, isNot(-1), reason: '$labels');
      expect(labels[name + 1], isNot(contains('offen')), reason: '$labels');
      expect(
        labels.where((l) => RegExp(r'\n(\d+ offen|nichts offen)$').hasMatch(l)),
        isNotEmpty,
        reason: 'each list still says its open items: $labels',
      );
      semantics.dispose();
    });

    testWidgets('currency: shown with the prices flag, any member picks', (
      tester,
    ) async {
      await _pump(tester, flags: const {pricesFlag});
      await _open(tester);
      await tester.ensureVisible(_key('household-currency'));
      await tester.tap(_key('household-currency'));
      await tester.pumpAndSettle();
      expect(_key('currency-picker'), findsOneWidget);
    });

    testWidgets('currency: hidden without the prices flag', (tester) async {
      await _pump(tester);
      await _open(tester);
      expect(_key('household-currency'), findsNothing);
    });
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

  group('Siri, Alexa & KI (job 248)', () {
    const voice = {defaultListFlag};

    testWidgets('one row names the label, the default household and its '
        'list', (tester) async {
      final semantics = tester.ensureSemantics();
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      expect(_inVoiceRow('Siri, Alexa & KI nutzen:'), findsOneWidget);
      expect(_inVoiceRow('Zuhause'), findsOneWidget);
      expect(_voiceList(tester), 'Wocheneinkauf');
      expect(_key('household-default-list-row'), findsNothing);
      expect(
        tester.getSemantics(_key('household-default-row')).label,
        matches(
          RegExp(
            r'^Siri, Alexa & KI nutzen:\s+Haushalt: Zuhause\s+Liste: Wocheneinkauf$',
          ),
        ),
      );
      semantics.dispose();
      expect(s.session.defaults, isEmpty);
    });

    testWidgets('a home marks the household and a checklist the list, also '
        'when the household has one list', (tester) async {
      await _pump(tester, flags: voice, homeLists: const [_weekly]);
      await _openHouseholds(tester);
      String line(String name) => find
          .descendant(
            of: _key('household-default-row'),
            matching: find.byWidgetPredicate(
              (w) => w is Text && _shown(w) == name,
            ),
          )
          .evaluate()
          .map(
            (e) => (e.widget as Text).textSpan!.toPlainText(
              includeSemanticsLabels: false,
            ),
          )
          .single;
      expect(line('Zuhause'), '\uFFFC Zuhause');
      expect(line('Wocheneinkauf'), '\uFFFC Wocheneinkauf');
    });

    testWidgets('each name line has its icon centred on the text at 130 % '
        'text', (tester) async {
      await _pump(
        tester,
        flags: voice,
        homeLists: const [_weekly],
        textScale: 1.3,
      );
      await _openHouseholds(tester);
      for (final name in ['Zuhause', 'Wocheneinkauf']) {
        final line = find.descendant(
          of: _key('household-default-row'),
          matching: find.byWidgetPredicate(
            (w) => w is Text && _shown(w) == name,
          ),
        );
        final icon = find.descendant(of: line, matching: find.byType(Icon));
        final box = tester.getRect(line);
        final centre = tester.getCenter(icon).dy;
        expect(
          (centre - box.center.dy).abs(),
          lessThan(2),
          reason: '$name: icon centre $centre, line ${box.center.dy}',
        );
      }
    });

    testWidgets('in English the row reads "add to" and names household and '
        'list', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, flags: voice, locale: const Locale('en'));
      await _openHouseholds(tester);
      expect(
        tester.getSemantics(_key('household-default-row')).label,
        matches(
          RegExp(
            r'^Siri, Alexa & AI add to:\s+Household: Zuhause\s+List: '
            r'Wocheneinkauf$',
          ),
        ),
      );
      semantics.dispose();
    });

    testWidgets('with the list flag off the row names no list', (tester) async {
      await _pump(tester);
      await _openHouseholds(tester);
      expect(_inVoiceRow('Zuhause'), findsOneWidget);
      expect(_voiceList(tester), isNull);
      expect(_key('household-default-list-row'), findsNothing);
    });

    testWidgets('household, then its list: both saved, the row names them', (
      tester,
    ) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      expect(find.text('Standard für Siri, Alexa & KI'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('switcher-back'),
          matching: find.text('Haushalte'),
        ),
        findsOneWidget,
      );
      expect(_rowTitles(tester, 'voice-household-'), ['Zuhause', 'Sommerfest']);
      expect(
        find.descendant(
          of: _key('voice-household-home'),
          matching: _key('voice-current'),
        ),
        findsOneWidget,
        reason: 'the default is checked',
      );

      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      expect(find.text('Liste für Siri, Alexa & KI'), findsOneWidget);
      expect(
        find.text(
          'Was du sagst, ohne eine Liste zu nennen, landet in „Sommerfest“ '
          'auf dieser Liste.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('switcher-back'),
          matching: find.text('Siri, Alexa & KI'),
        ),
        findsOneWidget,
      );
      expect(_rowTitles(tester, 'voice-list-'), ['Getränke', 'Essen']);
      expect(
        find.descendant(
          of: _key('voice-list-drinks'),
          matching: _key('voice-current'),
        ),
        findsOneWidget,
        reason: "Sommerfest's pick so far",
      );
      expect(s.session.defaults, isEmpty, reason: 'nothing saved yet');

      await tester.tap(_key('voice-list-food'));
      await tester.pumpAndSettle();
      expect(_key('switcher-households'), findsOneWidget);
      expect(s.session.listPicks, ['food']);
      expect(s.session.defaults, ['club']);
      expect(_inVoiceRow('Sommerfest'), findsOneWidget);
      expect(_voiceList(tester), 'Essen');
    });

    testWidgets('back from the lists goes to the households step and saves '
        'nothing, with the back row and the system back', (tester) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      await _back(tester);
      expect(_key('switcher-voice-households'), findsOneWidget);

      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-lists-club'), findsOneWidget);
      await _systemBack(tester);
      expect(_key('switcher-voice-households'), findsOneWidget);
      await _systemBack(tester);
      expect(_key('switcher-households'), findsOneWidget);
      expect(_inVoiceRow('Zuhause'), findsOneWidget);
      expect(s.session.defaults, isEmpty);
      expect(s.session.listPicks, isEmpty);
    });

    testWidgets('another list of the default household: the row names it, '
        'the household is not saved again', (tester) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      expect(_rowTitles(tester, 'voice-list-'), [
        'Wocheneinkauf',
        'Drogerie',
        'Grillen',
      ]);
      await tester.tap(_key('voice-list-dm'));
      await tester.pumpAndSettle();
      expect(_key('switcher-households'), findsOneWidget);
      expect(_inVoiceRow('Zuhause'), findsOneWidget);
      expect(_voiceList(tester), 'Drogerie');
      expect(s.session.listPicks, ['dm']);
      expect(s.session.defaults, isEmpty);
    });

    testWidgets('with the list flag off a household is saved at once', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      expect(_key('switcher-households'), findsOneWidget);
      expect(s.session.defaults, ['club']);
      expect(s.session.listPicks, isEmpty);
      expect(_inVoiceRow('Sommerfest'), findsOneWidget);
    });

    testWidgets('a refused list pick is told; the list step stays', (
      tester,
    ) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      s.session.fail = HouseholdProblem.offline;
      await tester.tap(_key('voice-list-food'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_key('switcher-voice-lists-club'), findsOneWidget);
      expect(s.session.defaults, isEmpty, reason: 'the list failed first');

      // The snackbar covers Essen.
      await tester.tap(_key('voice-list-drinks'));
      await tester.pumpAndSettle();
      expect(s.session.listPicks, ['food', 'drinks']);
      expect(s.session.defaults, ['club'], reason: 'a second tap saves');
    });

    testWidgets('picking the default household again saves no household', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      expect(_key('switcher-households'), findsOneWidget);
      expect(s.session.defaults, isEmpty);
    });

    testWidgets('the default reads as selected to screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      bool selected(String key) =>
          tester.getSemantics(_key(key)).flagsCollection.isSelected ==
          Tristate.isTrue;
      expect(selected('voice-household-home'), isTrue);
      expect(selected('voice-household-club'), isFalse);
      semantics.dispose();
    });

    testWidgets('a refused lists load is told; the household step stays and '
        'a second tap goes on', (tester) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      s.session.fail = HouseholdProblem.offline;
      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_key('switcher-voice-households'), findsOneWidget);
      // The snackbar covers Sommerfest.
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-lists-home'), findsOneWidget);
      expect(s.session.defaults, isEmpty);
    });

    testWidgets('a spinner shows on the household while its lists load', (
      tester,
    ) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      final hold = s.session.hold = Completer<void>();
      await tester.tap(_key('voice-household-club'));
      await tester.pump();
      expect(
        find.descendant(
          of: _key('voice-household-club'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      s.session.hold = null;
      hold.complete();
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-lists-club'), findsOneWidget);
    });

    testWidgets('back right after a household opened its lists: the '
        'household step still takes taps', (tester) async {
      await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-club'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(_key('switcher-back'));
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-households'), findsOneWidget);
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-lists-home'), findsOneWidget);
    });

    testWidgets('back and into the step again while a household loads: the '
        'old answer goes nowhere, the step takes taps', (tester) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      final hold = s.session.hold = Completer<void>();
      await tester.tap(_key('voice-household-club'));
      await tester.pump();
      await tester.tap(_key('switcher-back'));
      await tester.pump(const Duration(milliseconds: 30));
      // Mid-animation the row may be off its hit area: call its tap.
      tester
          .widget<ListTile>(_key('household-default-row').first)
          .onTap
          ?.call();
      await tester.pump(const Duration(milliseconds: 30));
      s.session.hold = null;
      hold.complete();
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-households'), findsOneWidget);
      expect(_key('switcher-voice-lists-club'), findsNothing);
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      expect(_key('switcher-voice-lists-home'), findsOneWidget);
    });

    testWidgets('an answer after the user went back does not move the sheet', (
      tester,
    ) async {
      final s = await _pump(tester, flags: voice);
      await _openHouseholds(tester);
      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      final hold = s.session.hold = Completer<void>();
      await tester.tap(_key('voice-household-club'));
      await tester.pump();
      await tester.tap(_key('switcher-back'));
      await tester.pump(const Duration(milliseconds: 50));
      s.session.hold = null;
      hold.complete();
      await tester.pumpAndSettle();
      expect(_key('switcher-households'), findsOneWidget);
      expect(_key('switcher-voice-lists-club'), findsNothing);

      await tester.tap(_key('household-default-row'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice-household-club'));
      await tester.pumpAndSettle();
      final save = s.session.hold = Completer<void>();
      await tester.tap(_key('voice-list-food'));
      await tester.pump();
      await tester.tap(_key('switcher-back'));
      await tester.pump(const Duration(milliseconds: 50));
      s.session.hold = null;
      save.complete();
      await tester.pumpAndSettle();
      expect(
        _key('switcher-voice-households'),
        findsOneWidget,
        reason: 'the save lands, the sheet stays where the user went',
      );
      expect(s.session.listPicks, ['food']);
      expect(s.session.defaults, ['club']);
    });

    testWidgets('200 % text on 320 x 568: long names wrap, none cut', (
      tester,
    ) async {
      const household = 'Ferienwohnung Ostsee Familie Brandt';
      const list = 'Wocheneinkauf für das ganze Wochenende';
      final s = await _pump(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        flags: voice,
        homeLists: const [
          HouseholdList(id: 'long', name: list, position: 0),
          _drugstore,
        ],
      );
      await s.session.rename('home', household);
      await tester.pumpAndSettle();
      await _openHouseholds(tester);
      final row = _key('household-default-row');
      await tester.scrollUntilVisible(
        row,
        100,
        scrollable: find
            .descendant(
              of: _key('switcher-households'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _unclipped(tester, _inVoiceRow('Siri, Alexa & KI nutzen:'));
      _unclipped(tester, _inVoiceRow(household));
      _unclipped(tester, _inVoiceRow(list));

      Future<void> reach(String page, String key) async {
        await tester.scrollUntilVisible(
          _key(key),
          100,
          scrollable: find
              .descendant(of: _key(page), matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(row);
      await tester.pumpAndSettle();
      await reach('switcher-voice-households', 'voice-household-home');
      _unclipped(
        tester,
        find.descendant(
          of: _key('voice-household-home'),
          matching: find.text(household),
        ),
      );
      await tester.tap(_key('voice-household-home'));
      await tester.pumpAndSettle();
      await reach('switcher-voice-lists-home', 'voice-list-long');
      _unclipped(
        tester,
        find.descendant(of: _key('voice-list-long'), matching: find.text(list)),
      );
      expect(tester.takeException(), isNull);
    });
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

  group('screenshots (job 248)', () {
    for (final scale in const [1.0, 2.0]) {
      for (final (locale, brightness) in const [
        (Locale('de'), Brightness.light),
        (Locale('en'), Brightness.dark),
      ]) {
        final shot =
            'goldens/switcher-voice-${locale.languageCode}-${(scale * 100).round()}';
        testWidgets('$shot: the row, the household step, the list step', (
          tester,
        ) async {
          final s = await _pump(
            tester,
            size: const Size(320, 568),
            insets: (top: 20, bottom: 0),
            textScale: scale,
            brightness: brightness,
            locale: locale,
            flags: const {defaultListFlag},
            homeLists: const [
              HouseholdList(
                id: 'long',
                name: 'Wocheneinkauf für das ganze Wochenende',
                position: 0,
              ),
              _drugstore,
            ],
          );
          await s.session.rename('home', 'Ferienwohnung Ostsee Familie Brandt');
          await tester.pumpAndSettle();
          await _openHouseholds(tester);
          await tester.scrollUntilVisible(
            _key('household-default-row'),
            100,
            scrollable: find
                .descendant(
                  of: _key('switcher-households'),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          final screen = find.byType(MaterialApp);
          await expectLater(screen, matchesGoldenFile('$shot-1-row.png'));
          Future<void> reach(String page, String key) async {
            await tester.scrollUntilVisible(
              _key(key),
              100,
              scrollable: find
                  .descendant(of: _key(page), matching: find.byType(Scrollable))
                  .first,
            );
            await tester.pumpAndSettle();
          }

          await tester.tap(_key('household-default-row'));
          await tester.pumpAndSettle();
          await reach('switcher-voice-households', 'voice-household-club');
          await expectLater(
            screen,
            matchesGoldenFile('$shot-2-households.png'),
          );
          await tester.tap(_key('voice-household-club'));
          await tester.pumpAndSettle();
          await reach('switcher-voice-lists-club', 'voice-list-food');
          await expectLater(screen, matchesGoldenFile('$shot-3-lists.png'));
          await tester.tap(_key('voice-list-food'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            _key('household-default-row'),
            100,
            scrollable: find
                .descendant(
                  of: _key('switcher-households'),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await expectLater(screen, matchesGoldenFile('$shot-4-saved.png'));
        });
      }
    }
  });

  group('screenshots (job 258)', () {
    for (final locale in const [Locale('de'), Locale('en')]) {
      final shot = 'goldens/switcher-household-${locale.languageCode}';
      testWidgets('$shot: the household page with the moved controls', (
        tester,
      ) async {
        await _pump(
          tester,
          insets: (top: 47.0, bottom: 34.0),
          locale: locale,
          flags: const {pricesFlag},
        );
        await _open(tester);
        final screen = find.byType(MaterialApp);
        await expectLater(screen, matchesGoldenFile('$shot-top.png'));
        await tester.dragFrom(
          tester.getCenter(_key('switcher-household-name')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        await expectLater(screen, matchesGoldenFile('$shot-end.png'));
      });
    }
  });

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
