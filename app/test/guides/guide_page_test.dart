import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:family_groceries/guides/source.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../core/fake_launcher.dart';

void main() {
  String fixture(String name) =>
      File('test/guides/fixtures/$name').readAsStringSync();
  final siri = fixture('siri-kurzbefehl.json');
  final index = fixture('index.json');

  late GoRouter router;
  late List<http.Request> requests;

  /// The guide routes behind a stand-in for the app's start at `/`, opened
  /// at [at] as a link opens them; [answer] is snacklist.app.
  Future<void> pump(
    WidgetTester tester, {
    required String at,
    required FutureOr<http.Response> Function(http.Request) answer,
    double width = 358,
    Locale locale = const Locale('de'),
  }) async {
    tester.view
      ..physicalSize = Size(width, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    requests = [];
    router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('start')),
        ...guideRoutes(),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => GuideSource(
          MockClient((request) async {
            requests.add(request);
            return await answer(request);
          }),
        ),
        child: MaterialApp.router(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routerConfig: router,
        ),
      ),
    );
  }

  http.Response json(String body) =>
      http.Response.bytes(utf8.encode(body), 200);

  http.Response site(http.Request request) => switch (request.url.path) {
    '/data/guides/de/siri-kurzbefehl.json' => json(siri),
    '/data/guides/de/index.json' => json(index),
    _ => http.Response('', 404),
  };

  /// Where the user is, a pushed page included.
  String location() => router.state.uri.toString();

  testWidgets("a guide link loads the guide of its URL's language", (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await pump(
      tester,
      at: '/de/anleitungen/siri-kurzbefehl',
      answer: (_) => answer.future,
      locale: const Locale('en'),
    );
    expect(find.byKey(const ValueKey('guide-loading')), findsOneWidget);
    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.toString(),
      'https://snacklist.app/data/guides/de/siri-kurzbefehl.json',
    );
    expect(requests.single.headers.keys, isNot(contains('cookie')));
    answer.complete(json(siri));
    await tester.pumpAndSettle();
    expect(find.text('Snacklist per Siri: Kurzbefehl einrichten'), findsOne);
    expect(find.text('Was du brauchst'), findsOne);
    expect(find.text('Öffne die Snacklist-App.'), findsOne);
    expect(find.textContaining('↓ Diktierter Text'), findsOne);
  });

  testWidgets('on a phone each table row is a card with its headers', (
    tester,
  ) async {
    await pump(tester, at: '/de/anleitungen/siri-kurzbefehl', answer: site);
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsNothing);
    // „Du sagst“ heads the first column of both tables, once per row.
    expect(find.text('Du sagst').evaluate().length, greaterThan(2));
    expect(find.text('Milch, zwei Gurken und Klopapier'), findsOne);
  });

  testWidgets('where it fits, a table is a grid', (tester) async {
    await pump(
      tester,
      at: '/de/anleitungen/siri-kurzbefehl',
      answer: site,
      width: 900,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsWidgets);
    expect(
      find.descendant(of: find.byType(Table), matching: find.text('Du sagst')),
      findsOne,
    );
  });

  testWidgets('offline: the error, and a retry loads it', (tester) async {
    var online = false;
    await pump(
      tester,
      at: '/de/anleitungen/siri-kurzbefehl',
      answer: (request) =>
          online ? site(request) : throw const SocketException('offline'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-failed')), findsOne);
    expect(
      find.text('Die Anleitung konnte nicht geladen werden. Bist du online?'),
      findsOne,
    );
    online = true;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Snacklist per Siri: Kurzbefehl einrichten'), findsOne);
    expect(requests, hasLength(2));
  });

  testWidgets('a server error or a file the app cannot read is an error', (
    tester,
  ) async {
    for (final response in [
      http.Response('', 503),
      json('{"schema": 2}'),
      http.Response('<!doctype html>', 200),
    ]) {
      await pump(
        tester,
        at: '/de/anleitungen/siri-kurzbefehl',
        answer: (_) => response,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-failed')), findsOne);
    }
  });

  testWidgets('a guide that is gone says so and leads to all guides', (
    tester,
  ) async {
    await pump(tester, at: '/de/anleitungen/fruehere-anleitung', answer: site);
    await tester.pumpAndSettle();
    expect(find.text('Diese Anleitung gibt es nicht mehr.'), findsOne);
    await tester.tap(find.text('Alle Anleitungen'));
    await tester.pumpAndSettle();
    expect(location(), '/de/anleitungen');
    expect(find.text('Anleitungen'), findsOne);
    expect(find.text('Snacklist per Siri: Kurzbefehl einrichten'), findsOne);
  });

  testWidgets('the index opens a guide; back returns to it', (tester) async {
    await pump(tester, at: '/de/anleitungen', answer: site);
    await tester.pumpAndSettle();
    final siriEntry = find.text('Snacklist per Siri: Kurzbefehl einrichten');
    await tester.ensureVisible(siriEntry);
    await tester.pumpAndSettle();
    await tester.tap(siriEntry);
    await tester.pumpAndSettle();
    expect(location(), '/de/anleitungen/siri-kurzbefehl');
    expect(find.text('Was du brauchst'), findsOne);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(location(), '/de/anleitungen');
  });

  testWidgets('closing a guide opened by a link goes to the start', (
    tester,
  ) async {
    await pump(tester, at: '/de/anleitungen/siri-kurzbefehl', answer: site);
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guide-close')));
    await tester.pumpAndSettle();
    expect(location(), '/');
    expect(find.text('start'), findsOne);
  });

  group('links', () {
    Future<void> open(WidgetTester tester) async {
      await pump(tester, at: '/de/anleitungen/siri-kurzbefehl', answer: site);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Zurück nach oben'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('another guide opens in the app, above this one', (
      tester,
    ) async {
      final launcher = fakeLauncher();
      await open(tester);
      await tester.tapOnText(find.textRange.ofSubstring('die Alexa-Anleitung'));
      await tester.pumpAndSettle();
      expect(location(), '/de/anleitungen/alexa');
      expect(requests.last.url.path, '/data/guides/de/alexa.json');
      expect(launcher.opened, isEmpty);
      expect(find.byType(BackButton), findsOne);
    });

    testWidgets('a page that is no guide opens in the system browser', (
      tester,
    ) async {
      final launcher = fakeLauncher();
      await open(tester);
      await tester.tapOnText(find.textRange.ofSubstring('Datenschutz'));
      await tester.pumpAndSettle();
      expect(launcher.opened, [
        (
          'https://snacklist.app/datenschutz',
          PreferredLaunchMode.externalApplication,
        ),
      ]);
      expect(location(), '/de/anleitungen/siri-kurzbefehl');
    });

    Map<String, Object?> paragraph(String text, [String? href]) => {
      'type': 'paragraph',
      'text': [
        {'text': text, 'href': ?href},
      ],
    };
    final anchors = jsonEncode({
      'schema': 1,
      'locale': 'de',
      'slug': 'anker',
      'title': 'Anker',
      'blocks': [
        paragraph('Zum Ende', '#ende'),
        for (var i = 0; i < 30; i++) paragraph('Absatz $i'),
        {
          'type': 'heading',
          'level': 2,
          'id': 'ende',
          'text': [
            {'text': 'Das Ende'},
          ],
        },
        for (var i = 0; i < 30; i++) paragraph('Danach $i'),
      ],
    });
    testWidgets('an anchor scrolls to its heading', (tester) async {
      await pump(
        tester,
        at: '/de/anleitungen/anker',
        answer: (_) => json(anchors),
      );
      await tester.pumpAndSettle();
      final heading = find.text('Das Ende', skipOffstage: false);
      expect(tester.getTopLeft(heading).dy, greaterThan(760));
      await tester.tapOnText(find.textRange.ofSubstring('Zum Ende'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading).dy, inInclusiveRange(0, 160));
    });

    testWidgets('a link with a #section opens the guide there', (tester) async {
      await pump(
        tester,
        at: '/de/anleitungen/anker#ende',
        answer: (_) => json(anchors),
      );
      await tester.pumpAndSettle();
      final heading = find.text('Das Ende', skipOffstage: false);
      expect(tester.getTopLeft(heading).dy, inInclusiveRange(0, 160));
    });

    testWidgets('a link the app will not follow is text', (tester) async {
      final launcher = fakeLauncher();
      await open(tester);
      await tester.tapOnText(find.textRange.ofSubstring('kein Link'));
      await tester.pumpAndSettle();
      expect(launcher.opened, isEmpty);
      expect(location(), '/de/anleitungen/siri-kurzbefehl');
    });
  });
}
