import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/section_label.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../analytics/fakes.dart' show MemoryAnalyticsStore, loadedAnalytics;
import 'more_harness.dart';

/// The M-P2 menu (job 85): inset groups, the legal rows in their own group,
/// sign-out alone, the version last, Nutzungsdaten as a page, the update
/// card on top.
void main() {
  setUpAll(fakeSupabase);

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Tall enough that every row is built at once.
  const tall = Size(390, 3000);

  String path(More more) =>
      more.router.routerDelegate.currentConfiguration.uri.toString();

  Element groupOf(WidgetTester tester, String row) => tester.element(
    find.ancestor(of: key(row), matching: find.byType(HlSticker)),
  );

  bool selected(WidgetTester tester, String k) => tester
      .widget<ListTile>(
        find.descendant(
          of: key(k),
          matching: find.byType(ListTile),
          matchRoot: true,
        ),
      )
      .selected;

  bool icon(WidgetTester tester, String row, IconData data) => find
      .descendant(of: key(row), matching: find.byIcon(data))
      .evaluate()
      .isNotEmpty;

  // The list builds lazily: rows below the fold are scrolled to first.
  Future<void> tapKey(WidgetTester tester, String k) async {
    if (key(k).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        key(k),
        100,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  testWidgets('the rows sit in their groups, top to bottom', (tester) async {
    await pumpMore(tester, size: tall);
    for (final group in menuGroups) {
      for (final row in group) {
        expect(
          groupOf(tester, row),
          groupOf(tester, group.first),
          reason: '$row is in the group of ${group.first}',
        );
      }
    }
    final groups = [for (final g in menuGroups) groupOf(tester, g.first)];
    expect(groups.toSet(), hasLength(menuGroups.length), reason: 'apart');
    final tops = [for (final row in menuRows) tester.getRect(key(row)).top];
    expect(tops, [...tops]..sort(), reason: 'in order');
  });

  testWidgets('Archivierte Haushalte joins the household group (flag)', (
    tester,
  ) async {
    await pumpMore(
      tester,
      size: tall,
      routes: [
        GoRoute(
          path: morePath,
          builder: (_, _) => const MoreScreen(showArchived: true),
        ),
      ],
    );
    expect(groupOf(tester, 'more-archived'), groupOf(tester, 'more-invite'));
    expect(
      tester.getRect(key('more-archived')).top,
      greaterThan(tester.getRect(key('more-invite')).top),
    );
  });

  testWidgets('with the decluttered list More has no household rows', (
    tester,
  ) async {
    await pumpMore(
      tester,
      size: tall,
      flags: const {listDeclutterFlag},
      routes: [
        GoRoute(
          path: morePath,
          builder: (_, _) => const MoreScreen(showArchived: true),
        ),
      ],
    );
    expect(key('more-household'), findsNothing);
    expect(key('more-invite'), findsNothing);
    expect(key('more-archived'), findsOneWidget, reason: 'stays in More');
    expect(key('more-access'), findsOneWidget);
    expect(find.text('Leute einladen'), findsNothing);
  });

  testWidgets('without the flag More keeps the household rows', (tester) async {
    await pumpMore(tester, size: tall);
    expect(key('more-household'), findsOneWidget);
    expect(key('more-invite'), findsOneWidget);
  });

  testWidgets('German labels in menu order', (tester) async {
    await pumpMore(tester, size: tall);
    expect(find.text('Mehr'), findsNothing, reason: 'no title (job 474)');
    const labels = [
      'Konto',
      'Snacklist Premium',
      'Leute einladen',
      'Zugänge',
      'Einstellungen',
      'Tipps',
      'Feedback senden',
      'Snacklist bewerten',
      'Hilfe & Kontakt',
      'Impressum',
      'Datenschutzerklärung',
      'Nutzungsbedingungen',
      'Lizenzen',
      'Abmelden',
    ];
    for (final (i, row) in menuRows.indexed) {
      expect(
        find.descendant(of: key(row), matching: find.text(labels[i])),
        findsOneWidget,
        reason: row,
      );
    }
  });

  // Job 206: joining is the household sheet's on the list.
  testWidgets('More offers no join', (tester) async {
    await pumpMore(tester, size: tall);
    // Tall enough that every row is built.
    await tester.scrollUntilVisible(key('more-sign-out'), 200);
    expect(key('more-join'), findsNothing);
    expect(find.textContaining('beitreten'), findsNothing);
  });

  testWidgets('English labels in menu order', (tester) async {
    await pumpMore(tester, size: tall, device: const [Locale('en', 'US')]);
    expect(find.text('More'), findsNothing, reason: 'no title (job 474)');
    const labels = [
      'Account',
      'Snacklist Premium',
      'Invite people',
      'Access',
      'Settings',
      'Tips',
      'Send feedback',
      'Rate Snacklist',
      'Help & contact',
      'Imprint',
      'Privacy policy',
      'Terms of Use',
      'Licenses',
      'Sign out',
    ];
    for (final (i, row) in menuRows.indexed) {
      expect(
        find.descendant(of: key(row), matching: find.text(labels[i])),
        findsOneWidget,
        reason: row,
      );
    }
  });

  testWidgets('every row is its label alone: no hints', (tester) async {
    await pumpMore(tester, size: tall);
    for (final row in menuRows) {
      expect(
        find.descendant(of: key(row), matching: find.byType(Text)),
        findsOneWidget,
        reason: row,
      );
    }
  });

  testWidgets('sign-out is last, plain like Licenses, without a chevron', (
    tester,
  ) async {
    await pumpMore(tester, size: tall);
    final signOut = tester.getRect(key('more-sign-out'));
    for (final row in menuRows.where((r) => r != 'more-sign-out')) {
      expect(tester.getRect(key(row)).bottom, lessThanOrEqualTo(signOut.top));
    }
    Finder icon(String row, IconData data) =>
        find.descendant(of: key(row), matching: find.byIcon(data));
    expect(icon('more-sign-out', Icons.chevron_right), findsNothing);
    expect(icon('more-sign-out', Icons.open_in_new), findsNothing);
    expect(icon('more-settings', Icons.chevron_right), findsOneWidget);
    expect(icon('more-help', Icons.open_in_new), findsOneWidget);
    for (final row in ['more-imprint', 'more-privacy-policy', 'more-terms']) {
      expect(icon(row, Icons.open_in_new), findsOneWidget, reason: row);
    }
    expect(icon('more-licenses', Icons.chevron_right), findsOneWidget);
    TextStyle? label(String row) => tester
        .widget<RichText>(
          find.descendant(of: key(row), matching: find.byType(RichText)).first,
        )
        .text
        .style;
    Color? glyph(String row) => tester
        .widget<Icon>(
          find.descendant(of: key(row), matching: find.byType(Icon)).first,
        )
        .color;
    expect(label('more-sign-out')?.color, label('more-licenses')?.color);
    expect(
      label('more-sign-out')?.fontWeight,
      label('more-licenses')?.fontWeight,
    );
    expect(glyph('more-sign-out'), glyph('more-licenses'));
    expect(glyph('more-sign-out'), isNot(SnacklistColors.light.error));
  });

  testWidgets('the version sits below every row', (tester) async {
    await pumpMore(tester, size: tall);
    final version = tester.getRect(key('more-version'));
    for (final row in menuRows) {
      expect(
        tester.getRect(key(row)).bottom,
        lessThanOrEqualTo(version.top),
        reason: row,
      );
    }
  });

  testWidgets('no switch, no stores or categories on the menu', (tester) async {
    await pumpMore(tester, size: tall);
    expect(find.byType(HexSwitchTile), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(key('more-analytics'), findsNothing);
    expect(find.text('Läden'), findsNothing);
    expect(find.text('Kategorien verwalten'), findsNothing);
  });

  group('The legal rows (DDG §5: the imprint one tap from the tab)', () {
    for (final (device, label) in const [
      (Locale('de', 'DE'), 'Rechtliches'),
      (Locale('en', 'US'), 'Legal'),
    ]) {
      testWidgets('${device.languageCode}: an unlabeled group of their own, '
          'below help, above sign-out', (tester) async {
        await pumpMore(tester, size: tall, device: [device]);
        expect(
          find.descendant(
            of: key('more-screen'),
            matching: find.byType(HlSectionLabel),
          ),
          findsNothing,
          reason: 'no group on More has a label',
        );
        expect(find.text(label.toUpperCase()), findsNothing);
        expect(find.text(label), findsNothing);
        final legal = groupOf(tester, legalRows.first);
        for (final row in legalRows) {
          expect(groupOf(tester, row), legal, reason: '$row is legal');
        }
        Rect box(Element e) =>
            tester.getRect(find.byElementPredicate((x) => x == e));
        final help = box(groupOf(tester, 'more-help'));
        final signOut = box(groupOf(tester, 'more-sign-out'));
        expect(box(legal).top, greaterThan(help.bottom), reason: 'below help');
        expect(box(legal).bottom, lessThan(signOut.top), reason: 'above');
        expect(
          box(legal).top - help.bottom,
          signOut.top - box(legal).bottom,
          reason: 'spaced like the other groups',
        );
        expect(
          [for (final row in legalRows) tester.getRect(key(row)).top],
          orderedEquals(
            [for (final row in legalRows) tester.getRect(key(row)).top]..sort(),
          ),
          reason:
              'Impressum, Datenschutzerklärung, Nutzungsbedingungen, '
              'Lizenzen',
        );
      });
    }

    testWidgets('the legal rows open no page of their own', (tester) async {
      final more = await pumpMore(tester);
      await tapKey(tester, 'more-licenses');
      expect(path(more), morePath, reason: 'licenses is a pushed page');
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('Nutzungsdaten', () {
    Future<More> withAnalytics(
      WidgetTester tester, {
      Size size = tall,
      String location = morePath,
    }) async {
      final analytics = await loadedAnalytics(MemoryAnalyticsStore());
      final more = await pumpMore(
        tester,
        size: size,
        location: location,
        analytics: analytics,
      );
      return more;
    }

    testWidgets('a build that sends usage data lists it with the settings, '
        'apart from the privacy policy', (tester) async {
      await withAnalytics(tester);
      expect(
        groupOf(tester, 'more-usage-data'),
        groupOf(tester, 'more-settings'),
      );
      expect(
        groupOf(tester, 'more-usage-data'),
        isNot(groupOf(tester, 'more-privacy-policy')),
      );
      expect(
        tester.getRect(key('more-usage-data')).top,
        greaterThan(tester.getRect(key('more-settings')).top),
      );
      expect(
        find.descendant(
          of: key('more-usage-data'),
          matching: find.text('Nutzungsdaten'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('more-privacy-policy'),
          matching: find.text('Datenschutzerklärung'),
        ),
        findsOneWidget,
      );
      expect(icon(tester, 'more-usage-data', Icons.chevron_right), isTrue);
    });

    testWidgets('a build without a key has no Nutzungsdaten row', (
      tester,
    ) async {
      await pumpMore(tester, size: tall);
      expect(key('more-settings'), findsOneWidget);
      expect(key('more-usage-data'), findsNothing);
      expect(find.text('Nutzungsdaten'), findsNothing);
    });

    testWidgets('opens by tap with only the switch; back returns to More', (
      tester,
    ) async {
      final more = await withAnalytics(tester, size: const Size(390, 844));
      await tapKey(tester, 'more-usage-data');
      expect(path(more), usageDataPath);
      expect(key('more-usage-data-page'), findsOneWidget);
      expect(find.text('Nutzungsdaten'), findsOneWidget, reason: 'the title');
      expect(key('more-analytics'), findsOneWidget);
      expect(key('more-privacy-policy'), findsNothing, reason: 'no policy');
      expect(find.byType(HlSectionLabel), findsNothing, reason: 'no label');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(path(more), morePath);
      expect(key('more-screen'), findsOneWidget);
    });

    testWidgets('the link $usageDataPath opens it; back goes to More', (
      tester,
    ) async {
      final more = await withAnalytics(
        tester,
        size: const Size(390, 844),
        location: usageDataPath,
      );
      expect(key('more-usage-data-page'), findsOneWidget);
      expect(key('more-screen'), findsNothing, reason: 'alone on a phone');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(path(more), morePath);
      expect(key('more-screen'), findsOneWidget);
    });

    testWidgets('from 840 px it opens beside the list, its row marked', (
      tester,
    ) async {
      final more = await withAnalytics(tester, size: const Size(1024, 1000));
      await tapKey(tester, 'more-usage-data');
      expect(path(more), usageDataPath);
      expect(key('more-screen'), findsOneWidget, reason: 'the list stays');
      expect(key('more-usage-data-page'), findsOneWidget);
      expect(
        tester.getRect(key('more-usage-data-page')).left,
        greaterThan(tester.getRect(key('more-screen')).right),
        reason: 'two panes',
      );
      expect(selected(tester, 'more-usage-data'), isTrue);
      expect(selected(tester, 'more-access'), isFalse);
      expect(find.byType(BackButton), findsNothing, reason: 'nothing to pop');
    });
  });

  testWidgets('the old link $moreLegalPath lands on More', (tester) async {
    final more = await pumpMore(tester, location: moreLegalPath);
    expect(path(more), morePath);
    expect(key('more-screen'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing, reason: 'More itself');
  });

  group('the update card', () {
    testWidgets('is absent while nothing tells of an update', (tester) async {
      await pumpMore(tester, size: tall);
      expect(key('more-update-card'), findsNothing);
    });

    for (final (update, title, body, action) in [
      (const PatchReady(), 'Update bereit', null, 'Neu starten'),
      (
        const StoreVersion('1.4.0'),
        'Neue Version da',
        'Version 1.4.0 ist im Store. Aktualisiere, um alles Neue zu bekommen.',
        'Aktualisieren',
      ),
    ]) {
      testWidgets('${update.runtimeType}: above every row; applies; closes', (
        tester,
      ) async {
        final updates = FakeAppUpdates(update);
        await pumpMore(tester, size: tall, updates: updates);
        final card = key('more-update-card');
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text(title)),
          findsOneWidget,
        );
        if (body != null) {
          expect(
            find.descendant(of: card, matching: find.text(body)),
            findsOneWidget,
          );
        }
        for (final row in menuRows) {
          expect(
            tester.getRect(card).bottom,
            lessThanOrEqualTo(tester.getRect(key(row)).top),
            reason: row,
          );
        }

        await tester.tap(
          find.descendant(of: card, matching: find.text(action)),
        );
        await tester.pumpAndSettle();
        expect(updates.applied, [update]);

        await tester.tap(key('more-update-later'));
        await tester.pumpAndSettle();
        expect(card, findsNothing);
        expect(updates.applied, [update], reason: 'later applies nothing');
        expect(key('menu-account'), findsOneWidget);
      });
    }

    testWidgets('speaks English too', (tester) async {
      await pumpMore(
        tester,
        size: tall,
        device: const [Locale('en', 'US')],
        updates: FakeAppUpdates(const StoreVersion('1.4.0')),
      );
      expect(find.text('New version available'), findsOneWidget);
      expect(
        find.text(
          'Version 1.4.0 is in the store. Update to get everything new.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Later'), findsOneWidget);
    });
  });
}
