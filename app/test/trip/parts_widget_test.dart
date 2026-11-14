import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/trip/ask_sheet.dart';
import 'package:family_groceries/trip/ended_card.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/summary_view.dart';
import 'package:family_groceries/trip/trip_strip.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import '../purchases/fakes.dart' show FakePremiumServer;

const lidl = Store(id: 'lidl', name: 'Lidl', sortOrder: 10);
const rewe = Store(id: 'rewe', name: 'Rewe', sortOrder: 20);
const catalog = Catalog(
  stores: [lidl, rewe],
  members: [
    Member(id: 'peter', displayName: 'Peter'),
    Member(id: 'lea', displayName: 'Lea'),
  ],
);

final start = DateTime(2026, 11, 14, 10);

Finder key(String k) => find.byKey(ValueKey(k));

/// [child] in the app's theme at the compact width, a stand-in Premium
/// page at its path.
Future<GoRouter> pumpPart(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(358, 760),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Locale locale = const Locale('de'),
  bool offer = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/more/lifetime',
        builder: (_, state) => Scaffold(
          body: Text('premium-page:${state.uri.queryParameters['from']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepositoryProvider<PremiumServer>.value(
      value: FakePremiumServer(offer: offer),
      child: MaterialApp.router(
        routerConfig: router,
        theme: appTheme(brightness),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

RunningTrip running({List<TripPause> pauses = const []}) => RunningTrip(
  id: 'trip-1',
  householdId: 'h',
  listId: null,
  startedAt: start,
  source: TripSource.ask,
  snapshot: const {},
  pauses: pauses,
);

TripLine line(
  String key, {
  bool planned = true,
  bool bought = true,
  Store? store = lidl,
  int? plannedCents,
  int? paidCents,
  bool byOther = false,
  String? addedBy,
  bool marked = false,
}) => TripLine(
  key: key,
  name: key,
  planned: planned,
  bought: bought,
  storeId: store?.id,
  storeName: store?.name,
  plannedCents: plannedCents,
  paidCents: paidCents,
  byOther: byOther,
  addedBy: addedBy,
  markedPlanned: marked,
);

FinishedTrip finished({
  List<TripLine>? lines,
  int bought = 0,
  TripEnd end = TripEnd.user,
  Duration active = const Duration(minutes: 25),
}) => FinishedTrip(
  id: 'trip-1',
  householdId: 'h',
  startedAt: start,
  endedAt: start.add(active),
  active: active,
  end: end,
  source: TripSource.ask,
  currency: 'EUR',
  lines: lines,
  bought: lines?.where((l) => l.bought).length ?? bought,
  day: DateTime(2026, 11, 14),
  stores: const ['Lidl', 'Rewe'],
);

/// Lidl: Milch planned 1,29 € paid 1,49 €, Brot planned not bought,
/// Käse an extra by Lea without a price; Rewe: Äpfel planned without a
/// price, Eis an own extra paid 3,00 €.
final shop = [
  line('Milch', plannedCents: 129, paidCents: 149),
  line('Brot', bought: false, plannedCents: 200),
  line('Äpfel', store: rewe),
  line('Käse', planned: false, byOther: true, addedBy: 'lea'),
  line('Eis', planned: false, store: rewe, paidCents: 300),
];

void main() {
  setUpAll(loadAppFonts);

  group('strip', () {
    Future<List<String>> pumpStrip(
      WidgetTester tester, {
      List<TripPause> pauses = const [],
      DateTime? lastTick,
    }) async {
      final calls = <String>[];
      var now = start.add(const Duration(minutes: 3, seconds: 7));
      await pumpPart(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: TripStrip(
            trip: running(pauses: pauses),
            lastTick: lastTick,
            elapsed: (at) => at.difference(start),
            clock: () => now,
            onPause: () => calls.add('pause'),
            onResume: () => calls.add('resume'),
            onEnd: () => calls.add('end'),
          ),
        ),
      );
      now = now.add(const Duration(seconds: 1));
      return calls;
    }

    testWidgets('running: the stopwatch ticks each second; pause and end', (
      tester,
    ) async {
      final calls = await pumpStrip(tester);
      expect(find.text('3:07'), findsOneWidget);
      expect(find.text('Einkauf läuft'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3:08'), findsOneWidget);
      await tester.tap(key('trip-strip-pause'));
      await tester.tap(find.text('Beenden'));
      expect(calls, ['pause', 'end']);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Einkauf läuft, seit 3 Minuten'),
        findsOneWidget,
        reason: 'the clock is read by the minute, not every second',
      );
      handle.dispose();
    });

    testWidgets('paused: resume is offered', (tester) async {
      final calls = await pumpStrip(
        tester,
        pauses: [TripPause(from: start.add(const Duration(minutes: 1)))],
      );
      expect(find.text('Pausiert'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Weiter'), findsOneWidget);
      handle.dispose();
      await tester.tap(key('trip-strip-pause'));
      expect(calls, ['resume']);
    });

    testWidgets('auto-paused: it says since when and ends at the last tick', (
      tester,
    ) async {
      final last = DateTime(2026, 11, 14, 10, 6);
      final calls = await pumpStrip(
        tester,
        lastTick: last,
        pauses: [
          TripPause(from: last.add(const Duration(minutes: 45)), auto: true),
        ],
      );
      expect(find.text('Pause · seit 10:06 nichts abgehakt'), findsOneWidget);
      await tester.tap(find.text('Beenden um 10:06'));
      expect(calls, ['end']);
    });

    test('the stopwatch face', () {
      expect(stopwatch(const Duration(seconds: 5)), '0:05');
      expect(stopwatch(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(stopwatch(const Duration(hours: 1, seconds: 3)), '1:00:03');
      expect(stopwatch(const Duration(seconds: -4)), '0:00');
    });
  });

  group('ask sheet', () {
    Future<AskAnswer?> ask(
      WidgetTester tester,
      Future<void> Function() act,
    ) async {
      AskAnswer? answer;
      await pumpPart(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answer = await showTripAsk(context, itemName: 'Milch'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Milch abgehakt'), findsOneWidget);
      expect(find.text('Kaufst du gerade ein?'), findsOneWidget);
      await act();
      await tester.pumpAndSettle();
      expect(find.text('Kaufst du gerade ein?'), findsNothing);
      return answer;
    }

    testWidgets('Ja', (tester) async {
      expect(
        await ask(tester, () => tester.tap(key('trip-ask-yes'))),
        AskAnswer.yes,
      );
    });

    testWidgets('Nein', (tester) async {
      expect(
        await ask(tester, () => tester.tap(key('trip-ask-no'))),
        AskAnswer.no,
      );
    });

    testWidgets('Zurücknehmen', (tester) async {
      expect(
        await ask(tester, () => tester.tap(find.text('Zurücknehmen'))),
        AskAnswer.takeBack,
      );
    });

    testWidgets('a scrim tap is Nein', (tester) async {
      expect(
        await ask(tester, () => tester.tapAt(const Offset(10, 10))),
        AskAnswer.no,
      );
    });
  });

  testWidgets('ended card: keep going, summary, close', (tester) async {
    final calls = <String>[];
    await pumpPart(
      tester,
      TripEndedCard(
        endedAt: DateTime(2026, 11, 14, 10, 6),
        onKeepGoing: () => calls.add('keep'),
        onShowSummary: () => calls.add('summary'),
        onDismiss: () => calls.add('dismiss'),
      ),
    );
    expect(find.text('Einkauf automatisch beendet'), findsOneWidget);
    expect(
      find.text(
        '4 Stunden lang wurde nichts abgehakt. Er endet beim letzten '
        'Abhaken um 10:06.',
      ),
      findsOneWidget,
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Einkauf automatisch beendet')),
      isSemantics(isHeader: true, isButton: false),
      reason: 'the title is a heading, not merged into the card',
    );
    expect(
      tester.getSemantics(key('trip-ended-dismiss')),
      isSemantics(label: 'Schließen', isButton: true),
    );
    expect(find.bySemanticsLabel(RegExp('^4 Stunden lang')), findsOneWidget);
    handle.dispose();
    await tester.tap(find.text('Doch weiter'));
    await tester.tap(find.text('Übersicht ansehen'));
    await tester.tap(key('trip-ended-dismiss'));
    expect(calls, ['keep', 'summary', 'dismiss']);
  });

  group('summary', () {
    testWidgets('the duration rounds as the times do; seconds are under a '
        'minute', (tester) async {
      for (final (active, title) in [
        (const Duration(seconds: 20), 'Unter 1 Min. eingekauft'),
        (const Duration(seconds: 40), '1 Min. eingekauft'),
        (const Duration(minutes: 24, seconds: 40), '25 Min. eingekauft'),
        (const Duration(minutes: 64, seconds: 20), '1 Std. 4 Min. eingekauft'),
      ]) {
        await pumpPart(
          tester,
          TripSummaryView(
            trip: finished(lines: shop, active: active),
            catalog: catalog,
            prices: true,
          ),
        );
        expect(find.text(title), findsOneWidget, reason: '$active');
      }
    });

    testWidgets('a section per store, with amounts and what they leave out', (
      tester,
    ) async {
      final marks = <(String, bool)>[];
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: shop),
          catalog: catalog,
          prices: true,
          onMark: (l, on) => marks.add((l.key, on)),
        ),
      );
      expect(
        find.text('Sa., 14. Nov., 10:00 bis 10:25 · Lidl · Rewe'),
        findsOneWidget,
      );
      expect(find.text('25 Min. eingekauft'), findsOneWidget);
      expect(
        find.text('2 von 3 von der Liste gekauft · 2 zusätzlich'),
        findsOneWidget,
      );
      final lidlSection = key('trip-section-Lidl');
      String texts(Finder of) => tester
          .widgetList<Text>(
            find.descendant(of: of, matching: find.byType(Text)),
          )
          .map((t) => (t.data ?? '').replaceAll('\u00a0', ' '))
          .join('|');
      final lidlText = texts(lidlSection);
      expect(lidlText, contains('1,49 € · geplant 1,29 € · 0,20 € mehr'));
      expect(lidlText, contains('nicht gekauft'));
      expect(lidlText, contains('von Lea'));
      expect(
        lidlText,
        contains('Geplant 1,29 € · 0,20 € mehr · bei 1 Artikel'),
      );
      expect(lidlText, contains('1 ohne Preis'));
      await tester.scrollUntilVisible(key('trip-section-Rewe'), 200);
      final reweText = texts(key('trip-section-Rewe'));
      expect(reweText, contains('3,00 €'));
      expect(reweText, contains('1 ohne Preis'));
      expect(reweText, contains('1 ohne geplanten Preis'));
      await tester.scrollUntilVisible(key('trip-summary-total'), 200);
      final total = texts(key('trip-summary-total'));
      expect(total, contains('Insgesamt bezahlt'));
      expect(total, contains('4,49 €'));
      expect(total, contains('2 ohne Preis'));
      expect(
        find.textContaining('Bezahlt zählt nur Artikel mit Preis'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(key('trip-mark-Käse'), -200);
      await tester.tap(key('trip-mark-Käse'));
      expect(marks, [('Käse', true)]);
      expect(
        key('trip-mark-Milch'),
        findsNothing,
        reason: 'planned rows have nothing to mark',
      );
    });

    testWidgets('screen readers: a heading per store, each part its own node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(
            lines: [
              ...shop.take(4),
              line('Eis', planned: false, store: rewe, marked: true),
            ],
          ),
          catalog: catalog,
          prices: true,
          onMark: (_, _) {},
        ),
        size: const Size(358, 2400),
      );
      for (final store in ['Lidl', 'Rewe']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(store)),
          isSemantics(isHeader: true, isButton: false, hasToggledState: false),
          reason: '$store alone is the heading, not its section',
        );
      }
      expect(
        find.bySemanticsLabel('Beim Start auf der Liste'),
        findsNWidgets(2),
      );
      expect(
        find.bySemanticsLabel('2 Artikel'),
        findsNWidgets(2),
        reason: 'the counts are their own nodes; marked Eis counts as planned',
      );
      expect(
        find.bySemanticsLabel(RegExp('^„War geplant“ zählt')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^gekauft\nMilch\n')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Brot\nnicht gekauft\$')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(key('trip-mark-Käse')),
        isSemantics(
          label: 'War geplant',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(key('trip-mark-Eis')),
        isSemantics(label: 'War geplant', isButton: true, isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('without the prices flag: no amounts anywhere', (tester) async {
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: shop),
          catalog: catalog,
          prices: false,
        ),
      );
      expect(find.textContaining('€'), findsNothing);
      expect(find.textContaining('Bezahlt'), findsNothing);
      expect(find.textContaining('ohne Preis'), findsNothing);
      expect(find.text('Milch'), findsOneWidget);
    });

    testWidgets('an empty start list: "Ohne Liste losgegangen"', (
      tester,
    ) async {
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: [line('Eis', planned: false)]),
          catalog: catalog,
          prices: false,
        ),
      );
      expect(find.text('Ohne Liste losgegangen · 1 gekauft'), findsOneWidget);
    });

    testWidgets('an automatic end says so', (tester) async {
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: shop, end: TripEnd.auto),
          catalog: catalog,
          prices: false,
        ),
      );
      expect(
        find.text('Beendet beim letzten Abhaken um 10:25, automatisch.'),
        findsOneWidget,
      );
    });

    testWidgets('fresh: keep shopping, done, and a retry while unsaved', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: shop),
          catalog: catalog,
          prices: false,
          onKeepShopping: () => calls.add('keep'),
          onDone: () => calls.add('done'),
          onRetrySave: () => calls.add('retry'),
        ),
      );
      expect(find.text('Der Einkauf ist noch nicht gespeichert.'), findsOne);
      await tester.tap(key('trip-summary-retry'));
      await tester.scrollUntilVisible(key('trip-summary-done'), 200);
      await tester.ensureVisible(key('trip-summary-keep-shopping'));
      await tester.tap(key('trip-summary-keep-shopping'));
      await tester.ensureVisible(key('trip-summary-done'));
      await tester.tap(key('trip-summary-done'));
      expect(calls, ['retry', 'keep', 'done']);
    });

    for (final offer in [true, false]) {
      testWidgets('Free: the count and the card, '
          '${offer ? 'with' : 'without'} the Premium button', (tester) async {
        final router = await pumpPart(
          tester,
          TripSummaryView(
            trip: finished(bought: 4),
            catalog: catalog,
            prices: true,
          ),
          offer: offer,
        );
        await tester.pumpAndSettle();
        expect(find.text('4 Artikel abgehakt'), findsOneWidget);
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('Was war geplant, was kam dazu?'),
          ),
          isSemantics(isHeader: true),
          reason: 'the heading alone, the body its own node',
        );
        expect(
          find.bySemanticsLabel(RegExp('^Snacklist Premium zeigt')),
          findsOneWidget,
        );
        handle.dispose();
        expect(find.text('Milch'), findsNothing);
        expect(find.textContaining('€'), findsNothing);
        expect(
          key('trip-locked-premium'),
          offer ? findsOneWidget : findsNothing,
        );
        if (offer) {
          await tester.tap(key('trip-locked-premium'));
          await tester.pumpAndSettle();
          expect(router.state.uri.path, '/more/lifetime');
        }
      });
    }
  });

  group('fits at 358 px with 130 % text', () {
    for (final brightness in Brightness.values) {
      for (final locale in const [Locale('de'), Locale('en')]) {
        final name = '${brightness.name}, ${locale.languageCode}';
        testWidgets('strip, card and summary: $name', (tester) async {
          final last = DateTime(2026, 11, 14, 10, 6);
          await pumpPart(
            tester,
            ListView(
              children: [
                TripEndedCard(
                  endedAt: last,
                  onKeepGoing: () {},
                  onShowSummary: () {},
                  onDismiss: () {},
                ),
                for (final pauses in [
                  const <TripPause>[],
                  [TripPause(from: last, auto: true)],
                ])
                  TripStrip(
                    trip: running(pauses: pauses),
                    lastTick: last,
                    elapsed: (_) => const Duration(hours: 1, minutes: 2),
                    onPause: () {},
                    onResume: () {},
                    onEnd: () {},
                  ),
                SizedBox(
                  height: 1400,
                  child: TripSummaryView(
                    trip: finished(lines: shop),
                    catalog: catalog,
                    prices: true,
                    onMark: (_, _) {},
                    onKeepShopping: () {},
                    onDone: () {},
                    onRetrySave: () {},
                  ),
                ),
              ],
            ),
            brightness: brightness,
            locale: locale,
            textScale: 1.3,
          );
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
        testWidgets('Free summary and ask sheet: $name', (tester) async {
          await pumpPart(
            tester,
            Column(
              children: [
                Expanded(
                  child: TripSummaryView(
                    trip: finished(bought: 3),
                    catalog: catalog,
                    prices: true,
                  ),
                ),
                const TripAskSheet(itemName: 'Hafermilch Barista'),
              ],
            ),
            size: const Size(358, 1200),
            brightness: brightness,
            locale: locale,
            textScale: 1.3,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
