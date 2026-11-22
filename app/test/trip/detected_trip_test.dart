import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/log/model.dart' hide TripSource;
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/trip/detection.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'list_trip_widget_test.dart' show Shop, pumpList;

/// The detection server: what `my_trip_detection` answers, and the calls.
class FakeDetection(var TripDetection answer)
    implements TripDetectionRepository {
  final calls = <String>[];
  var fetches = 0;

  /// How many fetches fail before one answers.
  var fetchFailures = 0;

  /// The next fetch waits for it, when set.
  Completer<void>? fetchGate;
  var setOnFails = false;

  @override
  Future<TripDetection> fetch() async {
    fetches++;
    final seen = answer;
    await fetchGate?.future;
    if (fetchFailures > 0) {
      fetchFailures--;
      throw Exception('offline');
    }
    return seen;
  }

  @override
  Future<void> setOn({required bool on}) async {
    calls.add('set $on');
    if (setOnFails) {
      throw Exception('offline');
    }
    answer = answer.copyWith(on: on);
  }

  @override
  Future<void> seenCard() async {
    calls.add('seen');
    answer = answer.copyWith(cardSeen: true);
  }
}

/// A Verlauf entry of the detected trip [session] at Lidl, from [by]'s
/// ticks.
Trip detected(String id, List<String> by, {String? session}) => Trip(
  id: id,
  day: DateTime(2026, 11, 14),
  items: const [TripItem(name: 'Milch')],
  createdAt: DateTime(2026, 11, 14),
  storeId: 'lidl',
  storeName: 'Lidl',
  sessionId: session,
  detectedBy: by,
);

/// `trip_session` for another member's detected trip: no clock times.
FinishedTrip theirs(String id) => FinishedTrip.fromJson({
  'id': id,
  ...const {
    'household_id': 'home',
    'started_at': null,
    'ended_at': null,
    'pauses': null,
    'active_seconds': 840,
    'end_reason': 'detected',
    'source': 'detected',
    'detected_by': ['lea'],
    'walked': true,
    'mine': false,
    'currency': 'EUR',
    'shopped_on': '2026-11-14',
    'lines': null,
    'bought': 3,
    'stores': ['Lidl'],
  },
});

void main() {
  setUpAll(loadAppFonts);
  Finder key(String k) => find.byKey(ValueKey(k));
  const flags = {tripModeFlag, groceryLogFlag, learnedOrderFlag};

  testWidgets('Verlauf: one line under the store of a detected trip, by '
      'whose ticks; none for the others', (tester) async {
    final shop = await pumpList(
      tester,
      flags: flags,
      seed: (repo) => repo
        ..members = const [
          Member(id: 'peter', displayName: 'Peter'),
          Member(id: 'lea', displayName: 'Lea'),
          Member(id: 'anna', displayName: 'Anna'),
        ]
        ..remoteAdd('Milch', storeId: 'lidl'),
      logged: [
        detected('own', ['peter']),
        detected('lea', ['lea']),
        detected('both', ['lea', 'peter']),
        detected('two', ['lea', 'anna']),
        Trip(
          id: 'plain',
          day: DateTime(2026, 11, 14),
          items: const [TripItem(name: 'Brot')],
          createdAt: DateTime(2026, 11, 14),
          storeId: 'lidl',
          storeName: 'Lidl',
        ),
      ],
    );
    shop.router.go(historyPath);
    await tester.pumpAndSettle();
    String line(String id) =>
        tester.widget<Text>(key('log-trip-detected-$id')).data!;
    expect(line('own'), 'Aus deinen Häkchen erkannt');
    expect(line('lea'), 'Aus den Häkchen von Lea erkannt');
    expect(line('both'), 'Aus deinen Häkchen und denen von Lea erkannt');
    expect(line('two'), 'Aus den Häkchen von Lea und Anna erkannt');
    expect(key('log-trip-detected-plain'), findsNothing);
  });

  group("another member's detected trip", () {
    Future<Shop> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      double textScale = 1,
    }) async {
      final shop = await pumpList(
        tester,
        flags: flags,
        size: size,
        textScale: textScale,
        logged: [
          detected('log-d', ['lea'], session: 'trip-d'),
        ],
      );
      shop.sessions.fetched['trip-d'] = theirs('trip-d');
      shop.router.go(historyPath);
      await tester.pumpAndSettle();
      await tester.tap(key('log-trip-log-d'));
      await tester.pumpAndSettle();
      return shop;
    }

    testWidgets('its page shows the day without clock times, and „Kein '
        'Einkauf“ instead of the delete', (tester) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(key('trip-summary-when')).data,
        'Sa., 14. Nov. · Lidl',
      );
      expect(find.text('14 Min. eingekauft'), findsOneWidget);
      expect(key('trip-remove'), findsOneWidget);
      expect(find.text('Kein Einkauf'), findsOneWidget);
      expect(key('trip-summary-delete'), findsNothing);
    });

    for (final (width, scale) in [(390.0, 1.0), (358.0, 2.0)]) {
      testWidgets('at $width px and ${scale * 100} % text the title and „Kein '
          'Einkauf“ read in full', (tester) async {
        await open(tester, size: Size(width, 844), textScale: scale);
        expect(tester.takeException(), isNull);
        void whole(Finder finder, String what) {
          final p = tester.renderObject<RenderParagraph>(finder);
          expect(p.didExceedMaxLines, isFalse, reason: '$what cut');
          expect(
            p.size.width,
            greaterThanOrEqualTo(
              p.softWrap ? 0 : p.getMaxIntrinsicWidth(double.infinity) - 0.5,
            ),
            reason: '$what ellipsized',
          );
          expect(
            p.size.height,
            greaterThanOrEqualTo(p.getMaxIntrinsicHeight(p.size.width) - 0.5),
            reason: '$what clipped',
          );
        }

        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Geplant und gekauft'),
        );
        whole(title, 'the title');
        final bar = tester.getRect(find.byType(AppBar));
        expect(
          bar.contains(tester.getRect(title).topLeft) &&
              bar.contains(
                tester.getRect(title).bottomRight - const Offset(1, 1),
              ),
          isTrue,
          reason: 'the title inside its bar',
        );
        whole(
          find.descendant(
            of: key('trip-remove'),
            matching: find.text('Kein Einkauf'),
          ),
          '„Kein Einkauf“',
        );
      });
    }

    testWidgets('„Kein Einkauf“ asks, removes it, goes back to Verlauf and '
        'says „Entfernt“', (tester) async {
      final shop = await open(tester);
      await tester.tap(key('trip-remove'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Kein Einkauf? Die Häkchen bleiben, aber die Reihenfolge lernt '
          'nicht mehr daraus.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(shop.sessions.removed, isEmpty);
      expect(shop.router.state.uri.path, historyTripPath('trip-d'));

      await tester.tap(key('trip-remove'));
      await tester.pumpAndSettle();
      await tester.tap(key('trip-remove-confirm'));
      await tester.pumpAndSettle();
      expect(shop.sessions.removed, ['trip-d']);
      expect(shop.router.state.uri.path, historyPath);
      expect(find.text('Entfernt'), findsOneWidget);
    });
  });

  group('the first-trip card', () {
    TripDetection unseen({String household = 'home'}) => TripDetection(
      on: true,
      cardSeen: false,
      firstTrip: FirstDetectedTrip(
        id: 'trip-d',
        householdId: household,
        storeName: 'Lidl',
      ),
    );

    Future<(FakeDetection, TripDetectionCubit)> pump(
      WidgetTester tester,
      TripDetection answer, {
      Set<String> shown = flags,
    }) async {
      final server = FakeDetection(answer);
      final detection = TripDetectionCubit(
        () => server,
        enabled: () => shown.contains(learnedOrderFlag),
      );
      addTearDown(detection.close);
      await detection.refresh();
      final shop = await pumpList(tester, flags: shown, detection: detection);
      shop.sessions.fetched['trip-d'] = theirs('trip-d');
      return (server, detection);
    }

    testWidgets('shows once: „Verstanden“ sees it for good', (tester) async {
      final (server, detection) = await pump(tester, unseen());
      expect(key('detected-card'), findsOneWidget);
      expect(find.text('Einkauf bei Lidl erkannt'), findsOneWidget);
      await tester.tap(find.text('Verstanden'));
      await tester.pumpAndSettle();
      expect(server.calls, ['seen']);
      expect(key('detected-card'), findsNothing);
      await detection.refresh();
      await tester.pumpAndSettle();
      expect(key('detected-card'), findsNothing, reason: 'the server agrees');
    });

    testWidgets('a trip without a store: a plain title', (tester) async {
      await pump(
        tester,
        const TripDetection(
          on: true,
          cardSeen: false,
          firstTrip: FirstDetectedTrip(
            id: 'trip-d',
            householdId: 'home',
            storeName: null,
          ),
        ),
      );
      expect(find.text('Einkauf erkannt'), findsOneWidget);
      expect(find.textContaining('Ohne Laden'), findsNothing);
    });

    testWidgets('„Ansehen“ sees it and opens the trip', (tester) async {
      final (server, _) = await pump(tester, unseen());
      await tester.tap(find.text('Ansehen'));
      await tester.pumpAndSettle();
      expect(server.calls, ['seen']);
      expect(key('trip-summary'), findsOneWidget);
      expect(key('trip-remove'), findsOneWidget);
    });

    testWidgets('none when seen, for a trip in another household, or with '
        'the flag off', (tester) async {
      await pump(tester, unseen().copyWith(cardSeen: true));
      expect(key('detected-card'), findsNothing);
      await pump(tester, unseen(household: 'club'));
      expect(key('detected-card'), findsNothing);
      await pump(tester, unseen(), shown: const {tripModeFlag});
      expect(key('detected-card'), findsNothing);
    });

    testWidgets('none with learned-order on but grocery-log or trip-mode off', (
      tester,
    ) async {
      await pump(
        tester,
        unseen(),
        shown: const {learnedOrderFlag, tripModeFlag},
      );
      expect(key('detected-card'), findsNothing, reason: 'no Verlauf');
      expect(find.textContaining('im Verlauf'), findsNothing);
      await pump(
        tester,
        unseen(),
        shown: const {learnedOrderFlag, groceryLogFlag},
      );
      expect(key('detected-card'), findsNothing, reason: 'no trip mode');
      await pump(tester, unseen(), shown: const {learnedOrderFlag});
      expect(key('detected-card'), findsNothing, reason: 'neither');
    });
  });

  group('the Settings switch', () {
    Future<FakeDetection> pump(
      WidgetTester tester, {
      required bool on,
      bool flag = true,
      void Function(FakeDetection server)? before,
    }) async {
      final server = FakeDetection(TripDetection(on: on, cardSeen: true));
      before?.call(server);
      final detection = TripDetectionCubit(() => server, enabled: () => flag);
      final shown = Flags(forced: {if (flag) learnedOrderFlag});
      addTearDown(detection.close);
      addTearDown(shown.close);
      await detection.refresh();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: shown),
            BlocProvider.value(value: detection),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: const Scaffold(body: DetectTripsSettings()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('shows what the server says and switches it', (tester) async {
      final server = await pump(tester, on: true);
      expect(find.text('Einkäufe aus meinen Häkchen erkennen'), findsOneWidget);
      expect(
        find.text('Nutzt nur, wann du abhakst. Kein Standort.'),
        findsOneWidget,
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(key('settings-detect-trips')),
        isSemantics(isToggled: true),
      );
      await tester.tap(key('settings-detect-trips'));
      await tester.pumpAndSettle();
      expect(server.calls, ['set false']);
      expect(
        tester.getSemantics(key('settings-detect-trips')),
        isSemantics(isToggled: false),
      );
      handle.dispose();
    });

    testWidgets('a switch the server refuses goes back and says so', (
      tester,
    ) async {
      final server = await pump(tester, on: true);
      server.setOnFails = true;
      final handle = tester.ensureSemantics();
      await tester.tap(key('settings-detect-trips'));
      await tester.pumpAndSettle();
      expect(server.calls, contains('set false'));
      expect(
        find.text('Die Änderung konnte nicht gespeichert werden.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(key('settings-detect-trips')),
        isSemantics(isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('unknown at the start: opening Settings asks again', (
      tester,
    ) async {
      final server = await pump(
        tester,
        on: true,
        before: (server) => server.fetchFailures = 1,
      );
      expect(server.fetches, 2);
      expect(key('settings-detect-trips'), findsOneWidget);
    });

    testWidgets('the flag off: no switch, nothing asked', (tester) async {
      await pump(tester, on: true, flag: false);
      expect(key('settings-detect-trips'), findsNothing);
    });
  });

  test('a read that started before a switch does not undo it', () async {
    final server = FakeDetection(const TripDetection(on: true, cardSeen: true));
    final detection = TripDetectionCubit(() => server, enabled: () => true);
    addTearDown(detection.close);
    await detection.refresh();
    final gate = server.fetchGate = Completer<void>();
    final reading = detection.refresh();
    await detection.setOn(on: false);
    gate.complete();
    await reading;
    expect(detection.state?.on, isFalse);
  });
}
