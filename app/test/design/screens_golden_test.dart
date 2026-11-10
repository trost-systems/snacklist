// Goldens of key screens in the Snacklist theme (design job 52), light and
// dark at a phone size, with the real fonts. After a deliberate look change:
//   flutter test --update-goldens test/design/screens_golden_test.dart
import 'dart:async';
import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/list/sync_indicator.dart';
import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart' show when;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

import '../analytics/fakes.dart' show MemoryAnalyticsStore, loadedAnalytics;
import '../household/harness.dart' show FakeInvites, FakeSharer;
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import '../session/fake_auth.dart';
import 'fonts.dart';

const _phone = Size(390, 844);
const _desktop = Size(1280, 800);

/// The 358 px compact design (snacklist-ui-craft).
const _compact = Size(358, 780);

Item _item(
  String id,
  String name,
  String store,
  String category, {
  String? quantity,
}) {
  final at = DateTime.utc(2026, 10, 31, 12);
  return Item(
    id: id,
    name: name,
    quantity: quantity,
    status: ItemStatus.active,
    createdAt: at,
    updatedAt: at,
    storeId: store,
    categoryId: category,
    sortKey: id.hashCode.toDouble(),
  );
}

/// Enough rows that the list scrolls under the add field.
const _longList = [
  'Äpfel',
  'Birnen',
  'Gurke',
  'Tomaten',
  'Paprika',
  'Zucchini',
  'Möhren',
  'Kartoffeln',
  'Zwiebeln',
  'Knoblauch',
  'Salat',
  'Spinat',
  'Brokkoli',
  'Zitronen',
  'Avocado',
  'Ingwer',
];

/// The shell with List and More as the app builds it, a few items on the
/// list, in [brightness].
Future<FakeRepository> _pumpShell(
  WidgetTester tester,
  Brightness brightness, {
  Size size = _phone,
  bool empty = false,
  bool long = false,
  Locale locale = const Locale('de'),

  /// The home indicator's or gesture bar's height.
  double inset = 0,

  /// The user's households, the first one shown (job 169b).
  List<Household> households = const [
    Household(id: 'home', name: 'Zuhause', isDefault: true),
  ],
  String initialLocation = listPath,

  /// The household's invites and members; Peter and Lea by default.
  FakeInvites? invites,

  /// Sets the server up further (lists, claims) before the app starts.
  void Function(FakeRepository repo)? seed,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..padding = FakeViewPadding(bottom: inset)
    ..viewPadding = FakeViewPadding(bottom: inset);
  addTearDown(tester.view.reset);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final cache = DeviceCache(SharedPreferencesAsync());
  final language = LanguageCubit(cache, AppLanguage.de);
  addTearDown(language.close);
  final session = FakeSession();
  whenListen(
    session,
    const Stream<Session>.empty(),
    initialState: InHousehold('peter', households.first, households),
  );
  when(session.refresh).thenAnswer((_) => Future.value());
  final repo = FakeRepository();
  for (final item in [
    if (!empty) ...[
      _item('1', 'Zahnpasta', 'dm', 'other'),
      _item('2', 'Bananen', 'lidl', 'produce', quantity: '6×'),
      _item('3', 'Vollmilch', 'lidl', 'chilled', quantity: '2 l'),
      _item('4', 'Butter', 'lidl', 'chilled'),
    ],
    if (long)
      for (final (i, name) in _longList.indexed)
        _item('l$i', name, 'lidl', 'produce'),
  ]) {
    repo.rows[item.id] = item;
  }
  seed?.call(repo);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            AppShell(shell: shell, repositories: (_) => repo),
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
                  GoRoute(
                    path: 'household',
                    builder: (_, _) =>
                        const MoreScreen(page: MorePage.household),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
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
        RepositoryProvider<InviteRepository>.value(
          value:
              invites ??
              (FakeInvites()
                ..memberLists['home'] = const [
                  HouseholdMember(userId: 'peter', displayName: 'Peter'),
                  HouseholdMember(userId: 'lea', displayName: 'Lea'),
                ]),
        ),
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
          theme: appTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// The sign-in screen with Google and Apple, the e-mail field focused.
Future<void> _pumpLogin(WidgetTester tester, Brightness brightness) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _phone;
  addTearDown(tester.view.reset);
  final auth = FakeAuth();
  addTearDown(auth.close);
  final session = SessionCubit(FakeClient(auth), MemorySessionCache());
  addTearDown(session.close);
  auth.states.add(const AuthState(AuthChangeEvent.initialSession, null));
  await tester.pump();
  await tester.pumpWidget(
    RepositoryProvider.value(
      value: SocialSignIn(
        auth,
        flows: const {
          SocialProvider.google: SignInFlow.native,
          SocialProvider.apple: SignInFlow.native,
        },
        native: FakeNativeSignIn(),
      ),
      child: BlocProvider.value(
        value: session,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const LoginScreen(),
        ),
      ),
    ),
  );
  // Asset images decode outside the fake clock: without this the brand mark
  // and Google's G stay empty boxes in the golden.
  final context = tester.element(find.byType(LoginScreen));
  await tester.runAsync(
    () => Future.wait([
      precacheImage(
        AssetImage('assets/brand/mark-${brightness.name}.png'),
        context,
      ),
      precacheImage(const AssetImage('assets/google_g.png'), context),
    ]),
  );
  await tester.pumpAndSettle();
}

/// The edit sheet over an empty screen, for an item with every field set.
Future<void> _pumpEditSheet(WidgetTester tester, Brightness brightness) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _phone;
  addTearDown(tester.view.reset);
  final item = _item('1', 'Vollmilch', 'lidl', 'chilled', quantity: '2');
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEditItemSheet(
                context,
                item: item.copyWith(
                  brand: () => 'Weihenstephan',
                  properties: () => '1,5 %, 1 l',
                ),
                catalog: const Catalog(
                  categories: [
                    Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
                  ],
                  stores: [Store(id: 'lidl', name: 'Lidl', sortOrder: 10)],
                ),
                onCreateStore: (_) async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// An iPhone 15's keyboard with its suggestion bar.
const _keyboard = 336.0;

/// A store's rename dialog over an iPhone's keyboard (job 152); a grey
/// block stands in for the keyboard.
Future<void> _pumpNameDialog(
  WidgetTester tester,
  Brightness brightness,
  Locale locale,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _phone
    ..viewInsets = const FakeViewPadding(bottom: _keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Stack(
            children: [
              Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showNameDialog(
                      context,
                      title: l10n.storeRename('Wochenmarkt'),
                      confirm: l10n.save,
                      label: l10n.storeNameHint,
                      initial: 'Wochenmarkt',
                      maxLength: 40,
                      save: (_) async => true,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: _keyboard,
                  width: double.infinity,
                  child: ColoredBox(color: Color(0xFFD1D3D9)),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await fakeSupabase();
  });

  // Inter is wider than Roboto: at 15 px the two chips took two lines on a
  // 390 px phone, and the sheet grew past half the screen (e2e
  // add-sheet.spec.ts, "the sheet hugs its suggestions").
  testWidgets('the add sheet keeps its two chips on one line at 390 px', (
    tester,
  ) async {
    await _pumpShell(tester, Brightness.light);
    final field = find.byKey(const ValueKey('add-item-field'));
    await tester.tap(field);
    await tester.enterText(field, 'Spülmittel');
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('chip-category'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('chip-store'))).dy,
    );
  });

  testWidgets('at 150 % text the empty list stays clear of the add field', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpShell(
      tester,
      Brightness.light,
      size: const Size(375, 667),
      empty: true,
    );
    final text = tester.getRect(
      find.text('Die Liste ist leer. Tippe unten ein, was fehlt.'),
    );
    final hex = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('add-item-field')),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is ShapeDecoration,
            ),
          )
          .first,
    );
    expect(text.overlaps(hex), isFalse, reason: '$text over $hex');
    expect(
      hex.top - text.bottom,
      greaterThanOrEqualTo(HlSpace.s5),
      reason: 'clear space above the add field',
    );
  });

  testWidgets('the list scrolls under the floating add field', (tester) async {
    await _pumpShell(tester, Brightness.light, long: true);
    final hex = tester.getRect(
      find.ancestor(
        of: find.byKey(const ValueKey('add-item-field')),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is ShapeDecoration,
        ),
      ),
    );
    // The rows' own 16 px inset on both sides.
    expect(hex.left, 16);
    expect(hex.right, _phone.width - 16);
    // A row runs on under the field. A near miss beside the hex counts as
    // a tap on the field and leaves that hidden row alone.
    final under = Offset(8, hex.center.dy);
    final rows = find.byType(ItemRow);
    final behind = rows.evaluate().where(
      (e) => tester.getRect(find.byWidget(e.widget)).contains(under),
    );
    expect(behind, hasLength(1));
    final hidden = (behind.single.widget as ItemRow).item.name;
    await tester.tapAt(under);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('add-item-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('add-sheet-scrim')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is ItemRow &&
            w.item.name == hidden &&
            w.item.status == ItemStatus.active,
      ),
      findsOneWidget,
      reason: '$hidden is still on the list',
    );
    // On the web a row's tappable semantics element would take the browser
    // click before the framework's hit test: an opaque node over the band
    // blocks it.
    final semantics = tester.ensureSemantics();
    final band = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.hitTestBehavior == SemanticsHitTestBehavior.opaque &&
          tester.getRect(find.byWidget(w)).contains(under),
    );
    expect(band, findsOneWidget);
    expect(
      tester.getSemantics(band).getSemanticsData().hitTestBehavior,
      SemanticsHitTestBehavior.opaque,
    );
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('add-sheet-scrim')));
    await tester.pumpAndSettle();
    // Scrolled to the end, the last row stands clear of the field.
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    final lastRow = rows
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
        .reduce((a, b) => a > b ? a : b);
    expect(lastRow, lessThan(hex.top));
  });

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    // Job 57 T2: every single-line field is a hex.
    testWidgets('login, $mode', (tester) async {
      await _pumpLogin(tester, brightness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login-$mode.png'),
      );
    });

    testWidgets('edit sheet, $mode', (tester) async {
      await _pumpEditSheet(tester, brightness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/edit-sheet-$mode.png'),
      );
    });

    for (final lang in ['de', 'en']) {
      // On iOS: no Android selection handle under the caret.
      testWidgets('name dialog, keyboard open, $lang, $mode', (tester) async {
        await _pumpNameDialog(tester, brightness, Locale(lang));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/name-dialog-keyboard-$lang-$mode.png'),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }

    // Job 161: the sync indicator, open and collapsed into the bar.
    for (final (lang, locale) in [
      if (brightness == Brightness.light) ('de', const Locale('de')),
      if (brightness == Brightness.dark) ('en', const Locale('en')),
    ]) {
      for (final kind in SyncTrouble.values) {
        testWidgets('sync $kind, $lang, $mode', (tester) async {
          final repo = await _pumpShell(tester, brightness, locale: locale);
          final cubit = BlocProvider.of<ListCubit>(
            tester.element(find.byKey(const ValueKey('list-header'))),
          );
          switch (kind) {
            case SyncTrouble.offline:
              repo
                ..online = false
                ..emitStatus!(ConnectionStatus.offline);
            case SyncTrouble.failing:
              repo.fetchTrouble = true;
              unawaited(cubit.resync());
          }
          await tester.pump();
          if (kind == SyncTrouble.failing) {
            // Failing shows once the 3 s retry failed too (job 165).
            await tester.pump(const Duration(seconds: 3));
          }
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/sync-${kind.name}-open-$lang-$mode.png'),
          );
          await tester.pump(SyncIndicator.peek);
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/sync-${kind.name}-collapsed-$lang-$mode.png',
            ),
          );
        });
      }
    }

    // Job 169b: the switcher sheet over the list, and the household page.
    const households = [
      Household(
        id: 'home',
        name: 'Zuhause',
        isDefault: true,
        memberCount: 2,
        openCount: 4,
      ),
      Household(id: 'club', name: 'Sommerfest', memberCount: 12, openCount: 7),
      Household(id: 'parents', name: 'Eltern'),
    ];
    testWidgets('household sheet, $mode', (tester) async {
      await _pumpShell(tester, brightness, households: households);
      await tester.tap(find.byKey(const ValueKey('household-chip')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-sheet-$mode.png'),
      );
    });

    testWidgets('household page, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        households: households,
        initialLocation: householdPath,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-page-$mode.png'),
      );
    });

    // Job 169b W2: the owner's view of the members with their roles, and
    // the invite sheet with an active group link and who joined.
    const owned = [
      Household(
        id: 'home',
        name: 'Zuhause',
        isDefault: true,
        memberCount: 4,
        openCount: 4,
        role: HouseholdRole.owner,
        premium: true,
        kind: HouseholdKind.family,
      ),
    ];
    FakeInvites crew() {
      final invites = FakeInvites()
        ..memberLists['home'] = const [
          HouseholdMember(
            userId: 'peter',
            displayName: 'Peter',
            role: HouseholdRole.owner,
          ),
          HouseholdMember(
            userId: 'lea',
            displayName: 'Lea',
            role: HouseholdRole.admin,
          ),
          HouseholdMember(userId: 'mia', displayName: 'Mia'),
          HouseholdMember(userId: 'jonas', displayName: 'Jonas'),
        ]
        ..created.add(
          Invite(
            id: 'group-1',
            code: 'HUMM4825',
            // Local time, as the sheet shows it: the same text in every zone.
            expiresAt: DateTime(2026, 12, 8, 10, 30),
            kind: InviteKind.group,
            maxUses: 50,
            useCount: 2,
          ),
        );
      invites.joinLists['group-1'] = [
        InviteJoin(
          userId: 'mia',
          displayName: 'Mia',
          joinedAt: DateTime.utc(2026, 11, 6, 18),
        ),
        InviteJoin(
          userId: 'jonas',
          displayName: 'Jonas',
          joinedAt: DateTime.utc(2026, 11, 7, 9),
        ),
      ];
      return invites;
    }

    testWidgets('household page with roles, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        households: owned,
        invites: crew(),
        initialLocation: householdPath,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-roles-$mode.png'),
      );
    });

    testWidgets('invite sheet, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        households: owned,
        invites: crew(),
        initialLocation: householdPath,
      );
      await tester.tap(find.byKey(const ValueKey('household-invite')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/invite-sheet-$mode.png'),
      );
    });

    // Job 178 (Legal N-112): the join page hint above the controls at
    // 358 px, the sheet scrolled to its top.
    testWidgets('invite sheet, compact, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        size: _compact,
        households: owned,
        invites: crew(),
        initialLocation: householdPath,
      );
      await tester.tap(find.byKey(const ValueKey('household-invite')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/invite-sheet-compact-$mode.png'),
      );
    });

    // Job 169b K and L: a club's lists as tabs, the party list shown, who
    // brings what under the items.
    void party(FakeRepository repo, {bool many = false}) {
      repo
        ..members = const [
          Member(id: 'peter', displayName: 'Peter'),
          Member(id: 'lea', displayName: 'Lea'),
          Member(id: 'mia', displayName: 'Mia'),
          Member(id: 'tom', displayName: 'Tom'),
        ]
        ..lists = [
          const HouseholdList(id: 'weekly', name: 'Vereinsheim', position: 0),
          const HouseholdList(id: 'party', name: 'Sommerfest', position: 1),
          const HouseholdList(id: 'diy', name: 'Baumarkt', position: 2),
          if (many) ...const [
            HouseholdList(id: 'grill', name: 'Grillabend', position: 3),
            HouseholdList(id: 'xmas', name: 'Weihnachtsfeier', position: 4),
          ],
        ];
      for (final item in [
        _item('p1', 'Kuchen', 'lidl', 'other', quantity: '3'),
        _item('p2', 'Grillwürste', 'lidl', 'chilled', quantity: '40'),
        _item('p3', 'Apfelschorle', 'lidl', 'other', quantity: '2 Kisten'),
        _item('p4', 'Servietten', 'dm', 'other'),
      ]) {
        repo.rows[item.id] = item.copyWith(listId: 'party');
      }
      final at = DateTime.utc(2026, 11, 1, 12);
      for (final (item, user, quantity) in [
        ('p1', 'mia', '2'),
        ('p1', 'peter', '1'),
        ('p2', 'tom', null),
      ]) {
        repo.claims[(item, user)] = Claim(
          itemId: item,
          userId: user,
          quantity: quantity,
          createdAt: at,
        );
      }
    }

    Future<void> showParty(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('list-tab-party')));
      await tester.pumpAndSettle();
    }

    testWidgets('list with tabs, $mode', (tester) async {
      await _pumpShell(tester, brightness, seed: party);
      await showParty(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-tabs-$mode.png'),
      );
    });

    testWidgets('list with tabs, compact, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        size: _compact,
        seed: (repo) => party(repo, many: true),
      );
      await showParty(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-tabs-compact-$mode.png'),
      );
    });

    testWidgets('household page lists, $mode', (tester) async {
      await _pumpShell(
        tester,
        brightness,
        initialLocation: householdPath,
        seed: party,
      );
      await tester.drag(
        find.byKey(const ValueKey('household-page')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-lists-$mode.png'),
      );
    });

    testWidgets('list, $mode', (tester) async {
      await _pumpShell(tester, brightness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-$mode.png'),
      );
    });

    // The honey hex with the cart, no emoji (Peter, job 56 item 31).
    testWidgets('list empty, $mode', (tester) async {
      await _pumpShell(tester, brightness, empty: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-empty-$mode.png'),
      );
    });

    // The list's columns, the explainer and the add field in one frame
    // (job 57 item 27).
    testWidgets('list wide, $mode', (tester) async {
      await _pumpShell(tester, brightness, size: _desktop);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-wide-$mode.png'),
      );
    });

    // The add field floats with the rows' inset; the list scrolls on
    // under it (job 135).
    testWidgets('list scrolled under the add field, $mode', (tester) async {
      await _pumpShell(tester, brightness, long: true);
      await tester.drag(find.text('Zwiebeln'), const Offset(0, -300));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-long-$mode.png'),
      );
    });

    // Job 144: the tabs float as a hex pill above the home indicator
    // (iPhone, 34 px) or the gesture bar (Android, 24 px); the list runs on
    // behind it.
    for (final (phone, size, inset) in const [
      ('iphone', _phone, 34.0),
      ('android', Size(412, 915), 24.0),
    ]) {
      testWidgets('tab pill on $phone, $mode', (tester) async {
        await _pumpShell(
          tester,
          brightness,
          size: size,
          inset: inset,
          long: true,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/shell-pill-$phone-$mode.png'),
        );
      });
    }

    testWidgets('add sheet wide, $mode', (tester) async {
      await _pumpShell(tester, brightness, size: _desktop);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-wide-$mode.png'),
      );
    });

    testWidgets('add sheet, $mode', (tester) async {
      await _pumpShell(tester, brightness);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-$mode.png'),
      );
    });

    // Job 78: the chips share their line with Schließen, also at 358 px.
    testWidgets('add sheet compact, $mode', (tester) async {
      await _pumpShell(tester, brightness, size: _compact);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-compact-$mode.png'),
      );
    });

    // Job 58: "+ Neuer Laden" turned into its field, a name typed.
    testWidgets('add sheet new store, $mode', (tester) async {
      await _pumpShell(tester, brightness);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chip-store')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('store-option-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('store-new-field')),
        'Rewe',
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-new-store-$mode.png'),
      );
    });

    testWidgets('settings, $mode', (tester) async {
      await pumpMore(
        tester,
        location: appSettingsPath,
        theme: ThemeMode.values.byName(mode),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings-$mode.png'),
      );
    });

    // Following the device: System is picked.
    testWidgets('settings following a $mode device', (tester) async {
      await pumpMore(
        tester,
        location: appSettingsPath,
        deviceBrightness: Brightness.values.byName(mode),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings-system-$mode.png'),
      );
    });

    testWidgets('more, $mode', (tester) async {
      await pumpMore(tester, theme: ThemeMode.values.byName(mode));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-$mode.png'),
      );
    });

    // Job 85, M-P2: the store's update card on top of More.
    testWidgets('more with an update, $mode', (tester) async {
      await pumpMore(
        tester,
        theme: ThemeMode.values.byName(mode),
        updates: FakeAppUpdates(const StoreVersion('1.4.0')),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-update-$mode.png'),
      );
    });

    testWidgets('more in English, $mode', (tester) async {
      await pumpMore(
        tester,
        theme: ThemeMode.values.byName(mode),
        device: const [Locale('en', 'US')],
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-en-$mode.png'),
      );
    });

    // Job 85 addendum: the Rechtliches label and its rows, sign-out and the
    // version at the end of More, in a build that sends usage data.
    for (final (lang, device) in const [
      ('de', Locale('de', 'DE')),
      ('en', Locale('en', 'US')),
    ]) {
      testWidgets('more scrolled to the end, $lang, $mode', (tester) async {
        await pumpMore(
          tester,
          theme: ThemeMode.values.byName(mode),
          device: [device],
          analytics: await loadedAnalytics(MemoryAnalyticsStore()),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('more-version')),
          200,
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/more-end-$lang-$mode.png'),
        );
      });
    }

    // In a build that sends usage data, the switch is on this page.
    testWidgets('usage data, $mode', (tester) async {
      await pumpMore(
        tester,
        location: usageDataPath,
        theme: ThemeMode.values.byName(mode),
        analytics: await loadedAnalytics(MemoryAnalyticsStore()),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-usage-data-$mode.png'),
      );
    });

    // Job 57: the settings rows as hex pills; job 78: the List tab's
    // Anpassen, the stores and one store's or no store's details.
    for (final (name, location) in [
      ('stores', editPath),
      ('no-store', storeDetailsPath(null)),
      ('store-details', storeDetailsPath('lidl')),
    ]) {
      testWidgets('$name, $mode', (tester) async {
        await pumpMore(
          tester,
          location: location,
          theme: ThemeMode.values.byName(mode),
          routes: listTabRoutes(),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name-$mode.png'),
        );
      });
    }
  }
}
