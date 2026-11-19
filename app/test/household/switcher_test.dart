import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/join_decision_notices.dart';
import 'package:family_groceries/household/removed_notice.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/shell/shell.dart';
import 'package:flutter/rendering.dart';
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

typedef _Shell = ({
  TestSession session,
  GoRouter router,
  Popups popups,
  FakeRepository repo,
});

/// The two tabs as `buildRouter` has them, the list showing [rows] open
/// items, Peter in Zuhause (shown, his default) and Sommerfest.
Future<_Shell> _pumpShell(
  WidgetTester tester, {
  int rows = 2,
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('de'),
  List<JoinRequest> requests = const [],
  List<Member>? members,
  List<HouseholdList> lists = const [],
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
    InHousehold('peter', _home, const [_home, _club], requests: requests),
  );
  addTearDown(session.close);
  final repo = FakeRepository();
  if (members != null) {
    repo.members = members;
  }
  repo.lists = lists;
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
        RepositoryProvider<InviteRepository>.value(value: FakeInvites()),
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
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme(Brightness.light),
          locale: locale,
          routerConfig: router,
          builder: (context, child) => NoticesHost(
            popups: popups,
            child: RemovedNotices(
              router: router,
              child: JoinDecisionNotices(router: router, child: child!),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session: session, router: router, popups: popups, repo: repo);
}

String _location(_Shell s) =>
    s.router.routerDelegate.currentConfiguration.uri.toString();

/// The partner news text's own height, which the capsule would clip.
double _textHeight(WidgetTester tester) {
  final text = tester.renderObject<RenderParagraph>(_key('new-items-subtitle'));
  return text.getMaxIntrinsicHeight(text.size.width);
}

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

  testWidgets('every row invites to its household, on the root navigator', (
    tester,
  ) async {
    final s = await _pumpShell(tester);
    await _openSheet(tester);
    expect(_key('household-invite-home'), findsOneWidget);
    expect(find.byTooltip('Leute in Sommerfest einladen'), findsOneWidget);
    await tester.tap(_key('household-invite-club'));
    await tester.pumpAndSettle();
    expect(_key('invite-sheet'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('invite-sheet'),
        matching: find.text('Sommerfest'),
      ),
      findsOneWidget,
    );
    expect(s.popups.open, isTrue);
    expect(
      (s.session.state as InHousehold).household.id,
      'home',
      reason: 'inviting switches nothing',
    );
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
    expect(_location(s), joinCodePath);
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

  group("a partner's new adds beside the chip (job 173)", () {
    /// Lea's add, newer than what the list showed on open.
    Future<void> leaAdds(WidgetTester tester, FakeRepository repo) async {
      final tea = repo.rows['tee'] = Item(
        listId: repo.firstList,
        id: 'tee',
        name: 'Tee',
        status: ItemStatus.active,
        createdAt: DateTime.utc(2026, 11, 9),
        updatedAt: DateTime.utc(2026, 11, 9),
        addedBy: 'lea',
      );
      repo.emitItem!(tea);
      await tester.pump();
      await tester.pump();
    }

    for (final size in const [Size(390, 844), Size(360, 780)]) {
      testWidgets('show whole below the chip at ${size.width.round()} px', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final s = await _pumpShell(tester, size: size);
        await s.session.rename('home', 'Familie Brandt');
        await tester.pumpAndSettle();
        await leaAdds(tester, s.repo);

        final line = _key('new-items-subtitle');
        expect(
          tester.renderObject<RenderParagraph>(line).didExceedMaxLines,
          isFalse,
          reason: 'the whole line shows',
        );
        expect(find.bySemanticsLabel('1 neu von Lea'), findsOneWidget);
        final chipName = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: _key('household-chip'),
            matching: find.text('Familie Brandt'),
          ),
        );
        expect(chipName.didExceedMaxLines, isFalse, reason: 'the chip too');
        final chip = tester.getRect(_key('household-chip'));
        final status = tester.getRect(_key('list-status'));
        final edit = tester.getRect(_key('list-edit'));
        expect(status.left, chip.left, reason: 'right below the chip');
        expect(status.top, greaterThanOrEqualTo(chip.bottom));
        expect(status.overlaps(edit), isFalse);
        expect(status.right, lessThanOrEqualTo(size.width));

        final order = [
          for (final node in tester.semantics.simulatedAccessibilityTraversal())
            node.label,
        ];
        expect(
          order.indexOf('1 neu von Lea'),
          lessThan(order.indexOf('Tee\nNeu')),
          reason: 'read before the rows, not after the last one',
        );
        await tester.tap(_key('list-status'));
        await tester.pump();
        expect(s.repo.sent, isEmpty, reason: 'a tap on it ticks nothing off');
        expect(tester.takeException(), isNull);
        handle.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 5));
      });
    }

    testWidgets('a two-word name takes a second line rather than '
        'ellipsizing at 360 px', (tester) async {
      final s = await _pumpShell(
        tester,
        size: const Size(360, 780),
        members: const [
          Member(id: 'peter', displayName: 'Peter'),
          Member(id: 'lea', displayName: 'Christina Müller-Lüdenscheidt'),
        ],
      );
      await leaAdds(tester, s.repo);

      final line = tester.renderObject<RenderParagraph>(
        _key('new-items-subtitle'),
      );
      expect(line.didExceedMaxLines, isFalse, reason: 'the whole name');
      expect(
        _textHeight(tester),
        lessThanOrEqualTo(
          tester.getRect(_key('list-status')).height - 2 * HlBorder.width,
        ),
        reason: 'both lines inside the capsule',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets("a long name at large text leaves a store's count and fold "
        'key clear', (tester) async {
      const name = 'Maximilian-Alexander von Hohenzollern-Sigmaringen';
      final s = await _pumpShell(
        tester,
        size: const Size(360, 780),
        textScale: 1.5,
        members: const [
          Member(id: 'peter', displayName: 'Peter'),
          Member(id: 'lea', displayName: name),
        ],
      );
      await leaAdds(tester, s.repo);

      final status = tester.getRect(_key('list-status'));
      final divider = find.byKey(const ValueKey('store-none'));
      final fold = tester.getRect(
        find.descendant(of: divider, matching: find.byIcon(Icons.expand_more)),
      );
      final count = tester.getRect(
        find.descendant(
          of: divider,
          matching: find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                RegExp(r'^\d+ Artikel').hasMatch(w.text.toPlainText()),
          ),
        ),
      );
      // Whichever row passes under it: the capsule ends left of the column
      // where a store divider has its count and fold key.
      expect(status.right, lessThanOrEqualTo(fold.left), reason: 'fold key');
      expect(status.right, lessThanOrEqualTo(count.left), reason: 'count');
      expect(
        tester
            .renderObject<RenderParagraph>(_key('new-items-subtitle'))
            .didExceedMaxLines,
        isTrue,
        reason: 'the long name ellipsizes',
      );
      expect(
        _textHeight(tester),
        lessThanOrEqualTo(status.height - 2 * HlBorder.width),
        reason: 'no line cut off by the capsule at large text',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets('with several lists, below the tabs', (tester) async {
      final s = await _pumpShell(
        tester,
        lists: const [
          HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
          HouseholdList(id: 'party', name: 'Sommerfest', position: 1),
        ],
      );
      await leaAdds(tester, s.repo);

      final tabs = tester.getRect(_key('list-tabs'));
      final status = tester.getRect(_key('list-status'));
      expect(status.top, greaterThanOrEqualTo(tabs.bottom));
      expect(find.text('1 neu von Lea'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets('stay in the bar where it has room', (tester) async {
      final s = await _pumpShell(tester, size: const Size(1366, 1024));
      await s.session.rename('home', 'Familie Brandt');
      await tester.pumpAndSettle();
      await leaAdds(tester, s.repo);

      final chip = tester.getRect(_key('household-chip'));
      final status = tester.getRect(_key('list-status'));
      final edit = tester.getRect(_key('list-edit'));
      expect(status.top, chip.top);
      expect(status.left, greaterThan(chip.right));
      expect(status.right, lessThan(edit.left));
      expect(find.text('1 neu von Lea'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    });
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

  group('a join request waiting (job 169b W3 M)', () {
    const verein = JoinRequest(
      id: 'r1',
      householdId: 'verein',
      householdName: 'Verein',
    );

    testWidgets('shows greyed, with no switching into it', (tester) async {
      final s = await _pumpShell(tester, requests: const [verein]);
      await _openSheet(tester);
      final row = _key('household-request-verein');
      expect(
        find.descendant(of: row, matching: find.text('Verein')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Anfrage offen')),
        findsOneWidget,
      );
      expect(
        tester.widget<ListTile>(row).textColor,
        SnacklistColors.light.textMuted,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect((s.session.state as InHousehold).household.id, 'home');
      expect(find.text('Anfrage für „Verein“ zurückziehen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(s.session.withdrawn, isEmpty);
      expect(row, findsOneWidget);
    });

    testWidgets('a tap offers to withdraw it', (tester) async {
      final s = await _pumpShell(tester, requests: const [verein]);
      await _openSheet(tester);
      await tester.tap(_key('household-request-verein'));
      await tester.pumpAndSettle();
      await tester.tap(_key('join-request-withdraw-confirm'));
      await tester.pumpAndSettle();
      expect(s.session.withdrawn, ['verein']);
      expect(_key('household-request-verein'), findsNothing);
      expect(_key('household-sheet'), findsOneWidget);
    });

    for (final (approved, text) in const [
      (true, 'Du bist jetzt in „Verein“.'),
      (false, 'Deine Anfrage für „Verein“ wurde nicht angenommen.'),
    ]) {
      testWidgets('the decision is told: approved $approved', (tester) async {
        final s = await _pumpShell(tester);
        s.session.decidedOn.add((household: 'Verein', approved: approved));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(text), findsOneWidget);
      });
    }
  });
  group('removed by someone else (Legal N-114)', () {
    for (final (locale, text) in const [
      (
        'de',
        'Du wurdest aus dem Haushalt „Sommerfest“ entfernt. 30 Tage lang '
            'kommst du über alte Einladungen nicht zurück. Beitreten kannst '
            'du in dieser Zeit nur über eine neue Einladung vom Hauptadmin '
            'oder einem Admin.',
      ),
      (
        'en',
        'You were removed from the household “Sommerfest”. For 30 days, old '
            "invites won't let you back in. In that time you can only rejoin "
            'through a new invite from the owner or an admin.',
      ),
    ]) {
      for (final size in const [Size(358, 780), Size(390, 844)]) {
        testWidgets('the 30-day rule is told, $locale, ${size.width} px', (
          tester,
        ) async {
          final s = await _pumpShell(
            tester,
            locale: Locale(locale),
            size: size,
          );
          s.session.lost.add((
            userId: 'peter',
            name: _club.name,
            removal: 'club 1',
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text(text), findsOneWidget);
          expect(s.session.toldRemovals, [
            ['club 1'],
          ], reason: 'shown, so told');
          final shown = tester.getRect(find.text(text));
          expect(shown.top, greaterThanOrEqualTo(0));
          expect(shown.bottom, lessThanOrEqualTo(size.height));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
          expect(find.text(text), findsOneWidget, reason: 'still readable');
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
          await tester.pumpAndSettle();
          expect(find.text(text), findsNothing);
        });
      }
    }

    testWidgets('a household gone otherwise is told without the 30 days', (
      tester,
    ) async {
      final s = await _pumpShell(tester);
      s.session.lost.add((userId: 'peter', name: _club.name, removal: null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Du bist nicht mehr Mitglied von „Sommerfest“.'),
        findsOneWidget,
      );
      expect(find.textContaining('30 Tage'), findsNothing);
    });
  });
}
