// Goldens of key screens in the Hummlist theme (design job 52), light and
// dark at a phone size, with the real fonts. After a deliberate look change:
//   flutter test --update-goldens test/design/screens_golden_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import '../session/fake_auth.dart';
import 'fonts.dart';

const _phone = Size(390, 844);
const _desktop = Size(1280, 800);

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

/// The shell with List and More as the app builds it, a few items on the
/// list, in [brightness].
Future<void> _pumpShell(
  WidgetTester tester,
  Brightness brightness, {
  Size size = _phone,
  bool empty = false,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
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
    initialState: const InHousehold(
      'peter',
      Household(id: 'home', name: 'Zuhause'),
    ),
  );
  final repo = FakeRepository();
  for (final item in [
    if (!empty) ...[
      _item('1', 'Zahnpasta', 'dm', 'other'),
      _item('2', 'Bananen', 'lidl', 'produce', quantity: '6×'),
      _item('3', 'Vollmilch', 'lidl', 'chilled', quantity: '2 l'),
      _item('4', 'Butter', 'lidl', 'chilled'),
    ],
  ]) {
    repo.rows[item.id] = item;
  }
  final router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell, repository: repo),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: listPath, builder: (_, _) => const ListScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: morePath, builder: (_, _) => const MoreScreen()),
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
    RepositoryProvider.value(
      value: cache,
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
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

void main() {
  setUpAll(() async {
    // Supabase listens for deep links; with no plugin the listen fails late,
    // inside whichever test runs then.
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.llfbandit.app_links/events'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
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

    // Job 57: the settings rows as hex pills.
    for (final (name, key) in [
      ('categories', 'more-categories'),
      ('stores', 'more-stores'),
    ]) {
      testWidgets('$name, $mode', (tester) async {
        await pumpMore(tester, theme: ThemeMode.values.byName(mode));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name-$mode.png'),
        );
      });
    }

    testWidgets('store layout, $mode', (tester) async {
      await pumpMore(tester, theme: ThemeMode.values.byName(mode));
      await tester.tap(find.byKey(const ValueKey('more-stores')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('store-row-lidl')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/store-layout-$mode.png'),
      );
    });
  }
}
