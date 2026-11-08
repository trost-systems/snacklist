import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../design/fonts.dart';
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

const _home = Household(
  id: 'home',
  name: 'Zuhause',
  isDefault: true,
  memberCount: 2,
  openCount: 9,
);
const _club = Household(
  id: 'club',
  name: 'Sommerfest',
  memberCount: 12,
  openCount: 1,
);

typedef _Shell = ({TestSession session, GoRouter router, Popups popups});

/// The two tabs as `buildRouter` has them, the list showing [rows] open
/// items, Peter in Zuhause (shown, his default) and Sommerfest.
Future<_Shell> _pumpShell(
  WidgetTester tester, {
  int rows = 2,
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('de'),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final cache = DeviceCache(SharedPreferencesAsync());
  final language = LanguageCubit(cache, AppLanguage.de);
  addTearDown(language.close);
  final session = TestSession(
    const InHousehold('peter', _home, [_home, _club]),
  );
  addTearDown(session.close);
  final repo = FakeRepository();
  final at = DateTime.utc(2026, 11, 8, 12);
  for (var i = 0; i < rows; i++) {
    repo.rows['$i'] = Item(
      id: '$i',
      name: 'Artikel $i',
      status: ItemStatus.active,
      createdAt: at,
      updatedAt: at,
    );
  }
  // Sommerfest's list has its own item, so a list for the wrong household
  // shows.
  final club = FakeRepository();
  club.rows['wurst'] = Item(
    id: 'wurst',
    name: 'Bratwurst',
    status: ItemStatus.active,
    createdAt: at,
    updatedAt: at,
  );
  final servers = {'home': repo, 'club': club};
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(Brightness.light),
          locale: locale,
          routerConfig: router,
          builder: (context, child) =>
              NoticesHost(popups: popups, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session: session, router: router, popups: popups);
}

String _location(_Shell s) =>
    s.router.routerDelegate.currentConfiguration.uri.toString();

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_key('household-chip'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await fakeSupabase();
    await loadAppFonts();
  });

  testWidgets('the chip names the shown household and opens the sheet on '
      'the root navigator', (tester) async {
    final s = await _pumpShell(tester);
    expect(
      find.descendant(
        of: _key('household-chip'),
        matching: find.text('Zuhause'),
      ),
      findsOneWidget,
    );
    await _openSheet(tester);
    expect(_key('household-sheet'), findsOneWidget);
    expect(s.popups.open, isTrue, reason: 'Notices see it');
    expect(find.text('Deine Haushalte'), findsOneWidget);
    // The shown list's live count, not the server's last one.
    expect(find.text('2 Mitglieder · 2 offen'), findsOneWidget);
    expect(find.text('12 Mitglieder · 1 offen'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('household-row-home'),
        matching: _key('household-current'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('household-row-club'),
        matching: _key('household-current'),
      ),
      findsNothing,
    );
    expect(s.session.refreshes, 1, reason: 'fresh counts');
  });

  testWidgets('a row switches the list to that household', (tester) async {
    final s = await _pumpShell(tester);
    expect(find.text('Artikel 0'), findsOneWidget);
    expect(find.text('Bratwurst'), findsNothing);
    final before = tester.element(find.byType(ListScreen)).read<ListCubit>();
    await _openSheet(tester);
    await tester.tap(_key('household-row-club'));
    await tester.pumpAndSettle();
    expect(_key('household-sheet'), findsNothing);
    expect((s.session.state as InHousehold).household.id, 'club');
    expect(
      find.descendant(
        of: _key('household-chip'),
        matching: find.text('Sommerfest'),
      ),
      findsOneWidget,
    );
    expect(
      tester.element(find.byType(ListScreen)).read<ListCubit>(),
      isNot(same(before)),
      reason: 'a new list for the new household',
    );
    expect(find.text('Bratwurst'), findsOneWidget, reason: "Sommerfest's");
    expect(find.text('Artikel 0'), findsNothing, reason: "Zuhause's");
  });

  testWidgets('Neuer Haushalt opens the create step', (tester) async {
    final s = await _pumpShell(tester);
    await _openSheet(tester);
    await tester.tap(_key('household-new'));
    await tester.pumpAndSettle();
    expect(_location(s), newHouseholdPath);
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('Mit Code beitreten opens the join screen', (tester) async {
    final s = await _pumpShell(tester);
    await _openSheet(tester);
    await tester.tap(_key('household-join'));
    await tester.pumpAndSettle();
    expect(_location(s), moreJoinPath);
  });

  testWidgets('the footer names the default; its picker moves it', (
    tester,
  ) async {
    final s = await _pumpShell(tester);
    await _openSheet(tester);
    expect(find.text('Siri, Alexa & KI nutzen: Zuhause'), findsOneWidget);
    await tester.tap(_key('household-default-row'));
    await tester.pumpAndSettle();
    expect(_key('household-default-picker'), findsOneWidget);
    await tester.tap(_key('household-default-club'));
    await tester.pumpAndSettle();
    expect(s.session.defaults, ['club']);
    expect(_key('household-default-picker'), findsNothing);
    expect(find.text('Siri, Alexa & KI nutzen: Sommerfest'), findsOneWidget);
    expect(
      (s.session.state as InHousehold).household.id,
      'home',
      reason: 'the shown household stays',
    );
  });

  testWidgets('a long name ellipsizes; the bar keeps Anpassen whole', (
    tester,
  ) async {
    final s = await _pumpShell(tester, size: const Size(358, 640));
    await s.session.rename('home', 'Familie Trost-Brandt in der Waldstraße');
    await tester.pumpAndSettle();
    final chip = tester.getRect(_key('household-chip'));
    final edit = tester.getRect(_key('list-edit'));
    expect(chip.right, lessThan(edit.left));
    expect(find.text('Anpassen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an everyday name shows whole on a 390 px phone', (tester) async {
    final s = await _pumpShell(tester);
    await s.session.rename('home', 'Unser Haushalt');
    await tester.pumpAndSettle();
    final name = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: _key('household-chip'),
        matching: find.text('Unser Haushalt'),
      ),
    );
    expect(name.didExceedMaxLines, isFalse);
  });

  testWidgets('large text at 358 px fits the bar', (tester) async {
    await _pumpShell(tester, size: const Size(358, 640), textScale: 2);
    final chip = tester.getRect(_key('household-chip'));
    final edit = tester.getRect(_key('list-edit'));
    expect(chip.right, lessThan(edit.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('in English', (tester) async {
    await _pumpShell(tester, locale: const Locale('en'));
    await _openSheet(tester);
    expect(find.text('Your households'), findsOneWidget);
    expect(find.text('2 members · 2 open'), findsOneWidget);
    expect(find.text('New household'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Siri, Alexa & AI use: Zuhause'), findsOneWidget);
  });
}
