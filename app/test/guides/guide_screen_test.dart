import 'dart:io';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:family_groceries/guides/guide_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

String fixture(String name) =>
    File('test/guides/fixtures/$name.md').readAsStringSync();

void main() {
  late List<Uri> loaded;
  late List<Uri> outside;

  /// The app at [at] with the guide routes, the list at `/` and an app
  /// screen; [pages] answers each guide page by its path.
  Future<GoRouter> pump(
    WidgetTester tester,
    String at,
    GuideFetch Function(String path) pages,
  ) async {
    loaded = [];
    outside = [];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget guide(GoRouterState state) => GuideScreen(
      page: guidePage(state.uri.path),
      load: (page) async {
        loaded.add(page);
        return pages(page.path);
      },
      openOutside: (url) async => outside.add(url),
    );
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('list-screen')),
        GoRoute(
          path: '/more/invites',
          builder: (_, _) => const Text('invites-screen'),
        ),
        for (final path in [
          guidesDePath,
          '$guidesDePath/:slug',
          guidesEnPath,
          '$guidesEnPath/:slug',
        ])
          GoRoute(path: path, builder: (_, state) => guide(state)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: appTheme(Brightness.light),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Finder text(String text) => find.textContaining(text, findRichText: true);

  String location(GoRouter router) => router.state.uri.toString();

  testWidgets('a guide shows its headings, lists, tables and code', (
    tester,
  ) async {
    await pump(
      tester,
      '/de/anleitungen/siri-kurzbefehl',
      (_) => GuideShown(fixture('de-anleitungen-siri-kurzbefehl')),
    );
    expect(loaded, [
      Uri.parse('https://snacklist.app/de/anleitungen/siri-kurzbefehl'),
    ]);
    expect(text('Snacklist per Siri: Kurzbefehl einrichten'), findsOneWidget);
    expect(find.bySemanticsLabel('Was du brauchst'), findsOneWidget);
    // A list in a list item: the dictation action's settings.
    expect(text('Aufnahme beenden:'), findsOneWidget);
    // Code, selectable, a line of its own.
    expect(
      find.text(
        'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/voice?format=text',
      ),
      findsOneWidget,
    );
    expect(find.byType(SelectionArea), findsWidgets);
  });

  testWidgets('a table is a block per row, each cell under its header', (
    tester,
  ) async {
    await pump(
      tester,
      '/de/anleitungen/alexa',
      (_) => GuideShown(fixture('de-anleitungen-alexa')),
    );
    // Five rows of „So kannst du sprechen“, each with both headers.
    expect(find.text('Du sagst'), findsNWidgets(5));
    expect(find.text('Auf der Liste'), findsNWidgets(5));
    final said = text('füg zwei Liter Milch hinzu');
    await tester.ensureVisible(said);
    expect(
      tester.getTopLeft(said).dy,
      greaterThan(tester.getTopLeft(find.text('Du sagst').at(2)).dy),
    );
    expect(text('2 l Milch'), findsOneWidget);
    expect(find.text('Was hilft'), findsNWidgets(10));
  });

  testWidgets('a link to another guide opens it in the app, back returns', (
    tester,
  ) async {
    final router = await pump(
      tester,
      '/en/guides',
      (path) => GuideShown(
        path == '/en/guides'
            ? fixture('en-guides')
            : fixture('en-guides-claude'),
      ),
    );
    await tester.tapOnText(
      find.textRange.ofSubstring('Connect Snacklist to Claude'),
    );
    await tester.pumpAndSettle();
    expect(location(router), '/en/guides/claude');
    expect(text('Claude can read your Snacklist'), findsOneWidget);
    expect(outside, isEmpty);
    await tester.tap(find.byKey(const ValueKey('guide-back')));
    await tester.pumpAndSettle();
    expect(location(router), '/en/guides');
  });

  testWidgets('any other link opens the system browser', (tester) async {
    final router = await pump(
      tester,
      '/de/anleitungen/alexa',
      (_) => GuideShown(fixture('de-anleitungen-alexa')),
    );
    await tester.ensureVisible(text('Alles Weitere steht in der'));
    await tester.pumpAndSettle();
    // The second is the link; the first is Amazon's, in the bullet above.
    await tester.tapOnText(
      find.textRange.ofSubstring('Datenschutzerklärung').at(1),
    );
    await tester.pumpAndSettle();
    expect(outside, [Uri.parse('https://snacklist.app/datenschutz')]);
    expect(location(router), '/de/anleitungen/alexa');
  });

  testWidgets('a link to an app screen goes there', (tester) async {
    final router = await pump(
      tester,
      '/de/anleitungen',
      (_) => const GuideShown(
        '# Anleitungen\n\nLade jemanden über '
        '[Einladungen](https://app.snacklist.app/more/invites) ein.',
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('Einladungen'));
    await tester.pumpAndSettle();
    expect(location(router), '/more/invites');
    expect(outside, isEmpty);
  });

  testWidgets('a link to a section of the page scrolls to its heading', (
    tester,
  ) async {
    await pump(
      tester,
      '/de/anleitungen/alexa',
      (_) => GuideShown(fixture('de-anleitungen-alexa')),
    );
    const section = 'Damit dein Satz beim Snacklist-Skill ankommt';
    final link = text('(siehe $section)');
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    final heading = find.bySemanticsLabel(section);
    expect(tester.getTopLeft(heading).dy, lessThan(0));
    await tester.tapOnText(find.textRange.ofSubstring(section).last);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(heading).dy;
    expect(top, inInclusiveRange(0, 844 / 2));
    expect(outside, isEmpty);
  });

  testWidgets('back on the first screen opens the list', (tester) async {
    final router = await pump(
      tester,
      '/de/anleitungen/alexa',
      (_) => GuideShown(fixture('de-anleitungen-alexa')),
    );
    await tester.tap(find.byKey(const ValueKey('guide-back')));
    await tester.pumpAndSettle();
    expect(location(router), '/');
    expect(find.text('list-screen'), findsOneWidget);
  });

  testWidgets('a guide the site does not have leads to the guide list', (
    tester,
  ) async {
    final router = await pump(
      tester,
      '/de/anleitungen/gibts-nicht',
      (path) => path == '/de/anleitungen'
          ? GuideShown(fixture('en-guides'))
          : const GuideMissing(),
    );
    expect(find.text('Diese Anleitung gibt es nicht (mehr).'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-all')));
    await tester.pumpAndSettle();
    expect(location(router), '/de/anleitungen');
    expect(find.byKey(const ValueKey('guide-shown')), findsOneWidget);
  });

  testWidgets('a missing guide list offers no way to itself', (tester) async {
    await pump(tester, '/en/guides', (_) => const GuideMissing());
    expect(find.byKey(const ValueKey('guide-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-all')), findsNothing);
  });

  testWidgets('a failed load shows a retry, which loads again', (tester) async {
    var fail = true;
    await pump(
      tester,
      '/de/anleitungen/alexa',
      (_) => fail
          ? const GuideFailed()
          : GuideShown(fixture('de-anleitungen-alexa')),
    );
    expect(find.byKey(const ValueKey('guide-failed')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('guide-retry')));
    await tester.pumpAndSettle();
    expect(loaded, hasLength(2));
    expect(text('Snacklist per Alexa'), findsOneWidget);
  });
}
