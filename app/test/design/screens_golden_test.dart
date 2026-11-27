// Goldens of key screens in the Snacklist theme (design job 52), light and
// dark at a phone size, with the real fonts. After a deliberate look change:
//   flutter test --update-goldens test/design/screens_golden_test.dart
import 'dart:async';
import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/name_dialog.dart';
import 'package:family_groceries/list/sync_indicator.dart';
import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/start_screen.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/push/push_registration.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

import '../analytics/fakes.dart' show MemoryAnalyticsStore, loadedAnalytics;
import '../household/harness.dart' show FakeInvites, MemoryOnboardingStore;
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import '../push/household_add_alert_test.dart' show FakePrefs;
import '../push/push_registration_test.dart'
    show FakePushPlugin, FakePushTokens, MemoryPushStore, Sessions;
import '../session/fake_auth.dart';
import '../settings/shopping_day_test.dart'
    show FakePush, FakeShoppingDayServer;
import 'fonts.dart';
import 'shell_harness.dart';

/// The sign-in screen with Google and Apple, the e-mail field focused.
Future<void> _pumpLogin(WidgetTester tester, Brightness brightness) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = shellPhone;
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
          localizationsDelegates: appLocalizationsDelegates,
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

/// The signed-out start screen with "I already have an account" and the
/// paste-invite button below the primary action.
Future<void> _pumpStart(
  WidgetTester tester,
  Brightness brightness, {
  String lang = 'de',
  double textScale = 1,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = shellPhone;
  addTearDown(tester.view.reset);
  final onboarding = OnboardingCubit(MemoryOnboardingStore());
  addTearDown(onboarding.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: onboarding,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(brightness),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(lang),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const StartScreen(),
      ),
    ),
  );
  final context = tester.element(find.byType(StartScreen));
  await tester.runAsync(
    () => precacheImage(
      AssetImage('assets/brand/mark-${brightness.name}.png'),
      context,
    ),
  );
  await tester.pumpAndSettle();
}

/// The edit sheet over an empty screen, for an item with every field set.
Future<void> _pumpEditSheet(WidgetTester tester, Brightness brightness) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = shellPhone;
  addTearDown(tester.view.reset);
  final item = shellItem('1', 'Vollmilch', 'lidl', 'chilled', quantity: '2');
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      localizationsDelegates: appLocalizationsDelegates,
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
    ..physicalSize = shellPhone
    ..viewInsets = const FakeViewPadding(bottom: _keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(brightness),
      localizationsDelegates: appLocalizationsDelegates,
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
    await pumpShell(tester, Brightness.light);
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
    await pumpShell(
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
    await pumpShell(tester, Brightness.light, long: true);
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
    expect(hex.right, shellPhone.width - 16);
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

    testWidgets('start, $mode', (tester) async {
      await _pumpStart(tester, brightness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/start-$mode.png'),
      );
    });

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
          final repo = await pumpShell(tester, brightness, locale: locale);
          final cubit = BlocProvider.of<ListCubit>(
            tester.element(find.byKey(const ValueKey('list-header'))),
          );
          switch (kind) {
            case SyncTrouble.offline:
              // A live channel drops: a first join that fails gets its
              // whole timeout, with the list online (job 212).
              repo
                ..online = false
                ..emitStatus!(ConnectionStatus.online)
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
      Household(id: 'home', name: 'Zuhause', isDefault: true, memberCount: 2),
      Household(id: 'club', name: 'Sommerfest', memberCount: 12),
      Household(id: 'parents', name: 'Eltern'),
    ];
    testWidgets('household sheet, $mode', (tester) async {
      await pumpShell(tester, brightness, households: households);
      await tester.tap(find.byKey(const ValueKey('household-chip')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-sheet-$mode.png'),
      );
    });

    // Job 474: the households without a count of open items, in English.
    testWidgets('household sheet in English, $mode', (tester) async {
      await pumpShell(
        tester,
        brightness,
        households: households,
        locale: const Locale('en'),
      );
      await tester.tap(find.byKey(const ValueKey('household-chip')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/household-sheet-en-$mode.png'),
      );
    });

    testWidgets('household page, $mode', (tester) async {
      await pumpShell(
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
      await pumpShell(
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
      await pumpShell(
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
      await pumpShell(
        tester,
        brightness,
        size: shellCompact,
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
        shellItem('p1', 'Kuchen', 'lidl', 'other', quantity: '3'),
        shellItem('p2', 'Grillwürste', 'lidl', 'chilled', quantity: '40'),
        shellItem('p3', 'Apfelschorle', 'lidl', 'other', quantity: '2 Kisten'),
        shellItem('p4', 'Servietten', 'dm', 'other'),
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
      await pumpShell(tester, brightness, seed: party);
      await showParty(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-tabs-$mode.png'),
      );
    });

    testWidgets('list with tabs, compact, $mode', (tester) async {
      await pumpShell(
        tester,
        brightness,
        size: shellCompact,
        seed: (repo) => party(repo, many: true),
      );
      await showParty(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-tabs-compact-$mode.png'),
      );
    });

    testWidgets('household page lists, $mode', (tester) async {
      await pumpShell(
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
      await pumpShell(tester, brightness);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-$mode.png'),
      );
    });

    // The honey hex with the cart, no emoji (Peter, job 56 item 31).
    testWidgets('list empty, $mode', (tester) async {
      await pumpShell(tester, brightness, empty: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-empty-$mode.png'),
      );
    });

    // The list's columns, the explainer and the add field in one frame
    // (job 57 item 27).
    testWidgets('list wide, $mode', (tester) async {
      await pumpShell(tester, brightness, size: shellDesktop);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/list-wide-$mode.png'),
      );
    });

    // The add field floats with the rows' inset; the list scrolls on
    // under it (job 135).
    testWidgets('list scrolled under the add field, $mode', (tester) async {
      await pumpShell(tester, brightness, long: true);
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
      ('iphone', shellPhone, 34.0),
      ('android', Size(412, 915), 24.0),
    ]) {
      testWidgets('tab pill on $phone, $mode', (tester) async {
        await pumpShell(
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
      await pumpShell(tester, brightness, size: shellDesktop);
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
      await pumpShell(tester, brightness);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-$mode.png'),
      );
    });

    // Job 288, flag `add-feedback-list`: no chip row, the list's top bar
    // away and its rows up to the status bar.
    testWidgets('add sheet feedback, $mode', (tester) async {
      await pumpShell(
        tester,
        brightness,
        flags: {addFeedbackListFlag},
        top: 47,
      );
      await tester.tap(find.byKey(const ValueKey('add-item-field')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-feedback-$mode.png'),
      );
    });

    // Job 288: the added item's details, store and category among them.
    testWidgets('add sheet feedback details, $mode', (tester) async {
      await pumpShell(
        tester,
        brightness,
        flags: {addFeedbackListFlag},
        top: 47,
      );
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Joghurt');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('added-quantity')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add-sheet-feedback-details-$mode.png'),
      );
    });

    // Job 78: the chips share their line with Schließen, also at 358 px.
    testWidgets('add sheet compact, $mode', (tester) async {
      await pumpShell(tester, brightness, size: shellCompact);
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
      await pumpShell(tester, brightness);
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

    // Job 85 addendum: the legal rows, sign-out and the
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

    // Job 463: More with the Mitteilungen row, below Einstellungen.
    testWidgets('more with notifications, $mode', (tester) async {
      final alert = HouseholdAddAlert(null, FakePrefs());
      addTearDown(alert.close);
      await pumpMore(
        tester,
        theme: ThemeMode.values.byName(mode),
        flags: const {pushHouseholdAddFlag},
        householdAdd: alert,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('more-notifications')),
        200,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-notifications-row-$mode.png'),
      );
    });

    // Job 463: Mitteilungen in a phone build with push, both flags on:
    // the household-add switches, then the shopping-day reminder.
    testWidgets('notifications, $mode', (tester) async {
      final sessions = Sessions();
      final plugin = FakePushPlugin();
      final push = PushRegistration(
        plugin,
        MemoryPushStore(),
        FakePushTokens(sessions),
      );
      final alert = HouseholdAddAlert(push, FakePrefs());
      addTearDown(() async {
        await alert.close();
        await push.close();
        await plugin.close();
        await sessions.close();
      });
      await pumpMore(
        tester,
        location: notificationsPath,
        theme: ThemeMode.values.byName(mode),
        flags: const {pushHouseholdAddFlag, shoppingDayFlag},
        householdAdd: alert,
        shoppingDay: FakePush().service(FakeShoppingDayServer({2, 5})),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more-notifications-$mode.png'),
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

  group('paste invite sits apart from the row above it', () {
    for (final lang in ['de', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('start, $lang, text x$scale', (tester) async {
          await _pumpStart(
            tester,
            Brightness.light,
            lang: lang,
            textScale: scale,
          );
          final above = tester.getRect(
            find.byKey(const ValueKey('start-log-in')),
          );
          final paste = tester.getRect(
            find.byKey(const ValueKey('invite-paste')),
          );
          expect(paste.top - above.bottom, greaterThanOrEqualTo(HlSpace.s2));
        });
      }
    }
  });
}
