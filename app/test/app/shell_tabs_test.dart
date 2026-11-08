import 'dart:async';
import 'dart:ui' show SemanticsHitTestBehavior, Tristate;

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/review_prompt_trigger.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../review/fakes.dart';

/// The shell as `buildRouter` builds it: List and More as tabs, [rows]
/// items on the list, on a phone whose home indicator or gesture bar takes
/// [inset] px at the bottom.
Future<void> pumpShell(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double inset = 0,
  int rows = 0,
  Locale locale = const Locale('de'),
  double textScale = 1,

  /// The rating prompt the list's trigger feeds, if any.
  ReviewPrompt? reviewPrompt,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..padding = FakeViewPadding(bottom: inset)
    ..viewPadding = FakeViewPadding(bottom: inset);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
      [Household(id: 'home', name: 'Zuhause')],
    ),
  );
  final repo = FakeRepository();
  final at = DateTime.utc(2026, 11, 6, 12);
  for (var i = 0; i < rows; i++) {
    repo.rows['$i'] = Item(
      id: '$i',
      name: 'Artikel $i',
      status: ItemStatus.active,
      createdAt: at,
      updatedAt: at,
      storeId: 'lidl',
      categoryId: 'produce',
      sortKey: i.toDouble(),
    );
  }
  // As the app wires it: the root navigator's popups, for Notices.
  final popups = Popups();
  addTearDown(popups.dispose);
  final router = GoRouter(
    observers: [popups],
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
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: cache),
        RepositoryProvider<PremiumServer>.value(value: purchases.premium),
        if (reviewPrompt != null) RepositoryProvider.value(value: reviewPrompt),
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
}

void main() {
  setUpAll(() async {
    await fakeSupabase();
    // Real glyphs: the test font's square ones are far wider.
    await loadAppFonts();
  });

  final tabs = find.byKey(const ValueKey('tab-list'));
  final more = find.byKey(const ValueKey('tab-more'));
  final field = find.byKey(const ValueKey('add-item-field'));
  final hint = find.byKey(const ValueKey('add-sheet-hint'));

  /// The pill: both tabs and its inset inside the contour.
  Rect pill(WidgetTester tester) {
    final (list, right) = (tester.getRect(tabs), tester.getRect(more));
    return Rect.fromLTRB(
      list.left - 14,
      list.top,
      right.right + 14,
      list.bottom,
    );
  }

  /// The add field's hex.
  Rect hex(WidgetTester tester) => tester.getRect(
    find.ancestor(
      of: field,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is ShapeDecoration,
      ),
    ),
  );

  bool tabsReachable(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(
        find.ancestor(of: tabs, matching: find.byType(IgnorePointer)),
      )
      .every((w) => !w.ignoring);

  double opacity(WidgetTester tester, Finder of) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: of, matching: find.byType(AnimatedOpacity)).first,
      )
      .opacity;

  testWidgets('the tabs slide away while the sheet is open and come back; '
      'the field stays put', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, inset: 34);
    expect(tabsReachable(tester), isTrue);
    expect(find.semantics.byLabel(RegExp('^Liste')), findsOne);
    expect(opacity(tester, hint), 0);
    final tabsTop = tester.getTopLeft(tabs).dy;
    final fieldAt = hex(tester);

    await tester.tap(field);
    await tester.enterText(field, 'Milch');
    await tester.pumpAndSettle();
    expect(tabsReachable(tester), isFalse, reason: 'not tappable');
    expect(
      tester.getTopLeft(tabs).dy,
      greaterThan(tabsTop),
      reason: 'slid down',
    );
    expect(opacity(tester, tabs), 0, reason: 'faded out');
    expect(
      find.semantics.byLabel(RegExp('^Liste')),
      findsNothing,
      reason: 'out of semantics',
    );
    expect(opacity(tester, hint), 1, reason: 'the hint in their place');
    expect(hex(tester), fieldAt, reason: 'the field did not move');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabsReachable(tester), isTrue);
    expect(tester.getTopLeft(tabs).dy, tabsTop);
    expect(hex(tester), fieldAt);
    semantics.dispose();
  });

  for (final (phone, inset, gap) in const [
    ('an iPhone', 34.0, 26.0),
    ('an Android phone with a gesture bar', 24.0, 16.0),
    ('a screen without an inset', 0.0, 12.0),
  ]) {
    testWidgets('on $phone the pill floats centred, $gap px above the '
        'bottom edge', (tester) async {
      await pumpShell(tester, inset: inset);
      final rect = pill(tester);
      expect(rect.height, 52);
      expect(rect.bottom, 844 - gap);
      expect(rect.width, greaterThanOrEqualTo(236));
      expect(rect.left, greaterThan(HlSpace.s4));
      expect(rect.left, 390 - rect.right, reason: 'centred');
      // The add field sits right above it, clear of it.
      final above = hex(tester);
      expect(above.bottom, lessThanOrEqualTo(rect.top));
      expect(rect.top - above.bottom, lessThan(HlSpace.s4));
    });
  }

  testWidgets('rows run on behind the pill; a tap beside it leaves them '
      'alone', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, inset: 34, rows: 30);
    final rect = pill(tester);
    final beside = Offset(8, rect.center.dy);
    final behind = find
        .byType(ItemRow)
        .evaluate()
        .where((e) => tester.getRect(find.byWidget(e.widget)).contains(beside));
    expect(behind, hasLength(1), reason: 'a row runs on under the band');
    final hidden = (behind.single.widget as ItemRow).item.name;
    await tester.tapAt(beside);
    await tester.pumpAndSettle();
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
    // click first: an opaque node over the band blocks it.
    final band = find.ancestor(
      of: tabs,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.hitTestBehavior == SemanticsHitTestBehavior.opaque,
      ),
    );
    expect(tester.getRect(band).contains(beside), isTrue);
    semantics.dispose();

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
    final lastRow = find
        .byType(ItemRow)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
        .reduce((a, b) => a > b ? a : b);
    expect(lastRow, lessThan(hex(tester).top));
  });

  testWidgets('with the keyboard up there is no band: the field sits on the '
      'keyboard', (tester) async {
    await pumpShell(tester, inset: 34);
    await tester.tap(field);
    // As iOS reports it: the keyboard covers the home indicator.
    tester.view
      ..padding = FakeViewPadding.zero
      ..viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tabs, findsNothing);
    expect(hint, findsNothing);
    final above = hex(tester);
    expect(above.bottom, lessThanOrEqualTo(844 - 300));
    expect(above.bottom, greaterThan(844 - 300 - HlSpace.s4));

    tester.view
      ..padding = const FakeViewPadding(bottom: 34)
      ..viewInsets = FakeViewPadding.zero;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs, findsOneWidget, reason: 'back with the keyboard gone');
  });

  testWidgets('screen readers hear a tab bar with the selected tab', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester);
    SemanticsData data(Finder tab) =>
        tester.getSemantics(tab).getSemanticsData();
    expect(data(tabs).label, startsWith('Liste'));
    expect(data(tabs).flagsCollection.isSelected, Tristate.isTrue);
    expect(data(more).label, startsWith('Mehr'));
    expect(data(more).flagsCollection.isSelected, Tristate.isFalse);
    expect(data(tabs).role, SemanticsRole.tab);
    expect(data(tabs).hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester.getSemantics(tabs).parent?.getSemanticsData().role,
      SemanticsRole.tabBar,
    );
    // The whole height of the pill is the target, not just the hex.
    for (final tab in [tabs, more]) {
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));
    }

    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(data(more).flagsCollection.isSelected, Tristate.isTrue);
    expect(data(tabs).flagsCollection.isSelected, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('a tab takes the keyboard: focus ring, Enter and Space', (
    tester,
  ) async {
    await pumpShell(tester);
    Finder ring(Finder tab) => find.descendant(
      of: tab,
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.foregroundPainter != null,
      ),
    );
    FocusNode node(Finder tab) => Focus.of(
      tester.element(
        find.descendant(of: tab, matching: find.byType(Center)).first,
      ),
    );
    expect(ring(more), findsNothing);
    node(more).requestFocus();
    await tester.pumpAndSettle();
    expect(ring(more), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-screen')), findsOneWidget);

    node(tabs).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
  });

  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets('large text fits the pill at 320 px, $locale', (tester) async {
      await pumpShell(
        tester,
        size: const Size(320, 640),
        inset: 34,
        locale: locale,
        textScale: 2,
      );
      for (final label
          in locale.languageCode == 'de'
              ? ['Liste', 'Mehr']
              : ['List', 'More']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
          reason: '$label shows in full',
        );
      }
      final rect = pill(tester);
      expect(rect.height, 52);
      expect(rect.left, greaterThanOrEqualTo(HlSpace.s4));
      expect(rect.right, lessThanOrEqualTo(320 - HlSpace.s4));
    });
  }

  testWidgets('on its side a phone keeps the pill; a tablet has the rail', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(812, 375), inset: 21);
    expect(pill(tester).bottom, 375 - 13);
    expect(find.byType(NavigationRail), findsNothing);

    await pumpShell(tester, size: const Size(1024, 768));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Liste'), findsOneWidget);
  });

  testWidgets('switching to More closes the sheet', (tester) async {
    await pumpShell(tester, size: const Size(1000, 800));
    await tester.tap(field);
    await tester.enterText(field, 'Milch');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-sheet')), findsOneWidget);
    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-sheet')), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('closing the sheet, then More and back to the list, leaves '
      'the sheet closed', (tester) async {
    await pumpShell(tester);
    await tester.tap(field);
    await tester.enterText(field, 'Milch');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('add-sheet'));
    expect(sheet, findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-list')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  group('the rating prompt in the shell', () {
    late FakeStoreReview review;

    /// A due store-build install, the list's three rows ticked off.
    Future<void> finishTrip(WidgetTester tester) async {
      review = FakeStoreReview();
      final now = DateTime.now();
      final store = MemoryReviewStore()
        ..json = ReviewCounters(
          firstLaunch: now.subtract(const Duration(days: 30)),
          activeDays: 5,
          completedTrips: 4,
          itemsAdded: 60,
        ).toJson();
      await pumpShell(
        tester,
        rows: 3,
        reviewPrompt: ReviewPrompt(
          store,
          review,
          channel: BuildChannel.store,
          version: Future.value('1.4.0'),
        ),
      );
      final cubit = tester.element(find.byType(ListScreen)).read<ListCubit>();
      cubit.state.items.keys.toList().forEach(cubit.tick);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('left alone on the list, it asks', (tester) async {
      await finishTrip(tester);
      await tester.pump(ReviewPromptTrigger.idle);
      await tester.pump();
      expect(review.requests, 1);
    });

    testWidgets('a tap on the tab bar within the 3 s asks nothing', (
      tester,
    ) async {
      await finishTrip(tester);
      await tester.tap(more);
      await tester.pump(ReviewPromptTrigger.idle);
      await tester.pumpAndSettle();
      expect(review.requests, 0);
    });

    testWidgets('a dialog open on the root navigator holds it back', (
      tester,
    ) async {
      await finishTrip(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ListScreen)),
          builder: (_) => const AlertDialog(),
        ),
      );
      await tester.pump();
      await tester.pump(ReviewPromptTrigger.idle);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(review.requests, 0);
    });

    testWidgets('with the List tab hidden it never asks', (tester) async {
      await finishTrip(tester);
      GoRouter.of(tester.element(find.byType(ListScreen))).go(morePath);
      await tester.pump();
      await tester.pump(ReviewPromptTrigger.idle);
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(review.requests, 0);
    });
  });
}
