// The app shell (List and More) as screens_golden_test.dart and
// rd1_golden_test.dart pump it: a few items on the list, Peter and Lea's
// household, the real router branches.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/shell/shell.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart' show when;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../household/harness.dart' show FakeInvites, FakeSharer;
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';

const shellPhone = Size(390, 844);
const shellDesktop = Size(1280, 800);

/// The 358 px compact design (snacklist-ui-craft).
const shellCompact = Size(358, 780);

Item shellItem(
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
Future<FakeRepository> pumpShell(
  WidgetTester tester,
  Brightness brightness, {
  Size size = shellPhone,
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

  /// PostHog flags on, as a `FLAGS_ON` build has them.
  Set<String> flags = const {},

  /// The status bar's height.
  double top = 0,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..padding = FakeViewPadding(top: top, bottom: inset)
    ..viewPadding = FakeViewPadding(top: top, bottom: inset);
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
      shellItem('1', 'Zahnpasta', 'dm', 'other'),
      shellItem('2', 'Bananen', 'lidl', 'produce', quantity: '6×'),
      shellItem('3', 'Vollmilch', 'lidl', 'chilled', quantity: '2 l'),
      shellItem('4', 'Butter', 'lidl', 'chilled'),
    ],
    if (long)
      for (final (i, name) in _longList.indexed)
        shellItem('l$i', name, 'lidl', 'produce'),
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
          if (flags.isNotEmpty)
            BlocProvider(create: (_) => Flags(forced: flags)),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          localizationsDelegates: appLocalizationsDelegates,
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
