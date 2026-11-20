import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../purchases/fakes.dart' show FakePremiumServer;
import 'fakes.dart';
import 'harness.dart';

/// Job 199 H1: Free shows the last 4 weeks (from 16 October on, today being
/// Thursday 12 November 2026); older trips are kept, counted and shown with
/// Premium.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));
  Finder dayCell(String day) => key('log-day-$day');
  const lockedTitle = 'Ältere Einkäufe siehst du mit Snacklist Premium';

  final inWindow = trip(2026, 10, 16, store: 'lidl', items: ['Hafer']);
  final justOut = trip(2026, 10, 15, store: 'rewe', items: ['Kaffee']);
  final old = trip(2026, 9, 13, store: 'dm', items: ['Seife']);
  final recent = trip(2026, 11, 10, store: 'lidl');
  final all = [recent, inWindow, justOut, old];

  Future<void> previousMonth(WidgetTester tester) async {
    await tester.tap(key('log-month-previous'));
    await tester.pumpAndSettle();
  }

  testWidgets('Free: the trips of the last 4 weeks; older ones are not '
      'listed but counted in one locked row that opens the Premium page', (
    tester,
  ) async {
    final history = await pumpHistory(tester, trips: all, premium: false);
    expect(key('log-trip-${recent.id}'), findsOneWidget);
    expect(key('log-trip-${inWindow.id}'), findsOneWidget);
    expect(key('log-trip-${justOut.id}'), findsNothing);
    expect(key('log-trip-${old.id}'), findsNothing);
    expect(find.text('Kaffee'), findsNothing);
    expect(find.text('Seife'), findsNothing);

    await tester.scrollUntilVisible(key('log-journal-locked'), 100);
    expect(
      find.descendant(
        of: key('log-journal-locked'),
        matching: find.text('2 ältere Einkäufe'),
      ),
      findsOneWidget,
    );
    expect(find.text(lockedTitle), findsOneWidget);
    expect(
      key('log-calendar-locked'),
      findsNothing,
      reason: 'November has no locked day',
    );
    await tester.ensureVisible(key('log-locked-premium'));
    await tester.pumpAndSettle();
    await tester.tap(key('log-locked-premium'));
    await tester.pumpAndSettle();
    expect(find.text('premium-page:history'), findsOneWidget);
    expect(history.router.state.uri.path, '/more/lifetime');
  });

  testWidgets('Free, G2: the store view ends in the same locked row', (
    tester,
  ) async {
    await pumpHistory(tester, trips: all, premium: false);
    await tester.tap(key('log-view-toggle'));
    await tester.pumpAndSettle();
    expect(key('log-trip-${old.id}'), findsNothing);
    await tester.scrollUntilVisible(key('log-stores-locked'), 100);
    expect(
      find.descendant(
        of: key('log-stores-locked'),
        matching: find.text('2 ältere Einkäufe'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Free: days before the window are locked: no dots, no button, '
      'said so; the hint shows once under that month; the month before is '
      'not reachable', (tester) async {
    final handle = tester.ensureSemantics();
    final history = await pumpHistory(tester, trips: all, premium: false);
    await previousMonth(tester);
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(
      tester.widget<IconButton>(key('log-month-previous')).onPressed,
      isNull,
    );

    expect(key('log-dot-2026-10-15-0'), findsNothing, reason: 'locked');
    expect(
      key('log-dot-2026-10-16-0'),
      findsOneWidget,
      reason: 'in the window',
    );
    final locked = tester.getSemantics(dayCell('2026-10-15'));
    expect(
      locked.label,
      'Donnerstag, 15. Oktober, ältere Einkäufe mit '
      'Snacklist Premium',
    );
    expect(locked.flagsCollection.isButton, isFalse);
    expect(locked.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(
      tester.getSemantics(dayCell('2026-10-16')).flagsCollection.isButton,
      isTrue,
    );

    expect(key('log-calendar-locked'), findsOneWidget);
    expect(
      find.descendant(
        of: key('log-calendar-locked'),
        matching: find.text(lockedTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('log-calendar'),
        matching: find.text(lockedTitle),
      ),
      findsNothing,
      reason: 'under the calendar, not in it',
    );

    await tester.tap(dayCell('2026-10-15'));
    await tester.pumpAndSettle();
    expect(key('log-day-filter'), findsNothing, reason: 'not tappable');
    expect(history.trips.fetches, 1);
    handle.dispose();
  });

  testWidgets('Premium: the full history, a 60-day-old trip too, and no lock '
      'anywhere', (tester) async {
    await pumpHistory(tester, trips: all);
    await tester.scrollUntilVisible(key('log-trip-${old.id}'), 100);
    expect(key('log-trip-${justOut.id}'), findsOneWidget);
    expect(find.text(lockedTitle), findsNothing);
    await tester.drag(key('log-journal'), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await previousMonth(tester);
    await previousMonth(tester);
    expect(find.text('September 2026'), findsOneWidget);
    expect(key('log-dot-2026-09-13-0'), findsOneWidget);
    expect(
      tester.widget<IconButton>(key('log-month-previous')).onPressed,
      isNull,
      reason: "the oldest trip's month",
    );
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    await tester.tap(key('log-view-toggle'));
    await tester.pumpAndSettle();
    expect(key('log-stores-locked'), findsNothing);
  });

  /// Before sales start nothing may say „bald verfügbar“ or „kaufst du in
  /// der iPhone- oder Android-App“ (job 87): the row is its title and count,
  /// and opens the Premium page exactly when More lists it.
  Future<void> expectQuietRow(
    WidgetTester tester, {
    required bool opens,
  }) async {
    await tester.scrollUntilVisible(key('log-journal-locked'), 100);
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: key('log-journal-locked'),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(texts, [lockedTitle, '2 ältere Einkäufe']);
    expect(find.textContaining('bald verfügbar'), findsNothing);
    expect(find.textContaining('Bald verfügbar'), findsNothing);
    expect(find.textContaining('kaufst du'), findsNothing);
    expect(key('log-locked-premium'), opens ? findsOneWidget : findsNothing);
    expect(
      find.descendant(
        of: key('log-journal-locked'),
        matching: find.byIcon(Icons.chevron_right),
      ),
      opens ? findsOneWidget : findsNothing,
    );
    final handle = tester.ensureSemantics();
    final row = tester.getSemantics(find.text(lockedTitle));
    expect(row.flagsCollection.isButton, opens);
    handle.dispose();
  }

  for (final (name, offer, noSale, opens) in [
    ('offer off', false, null, false),
    (
      'offer on, store build without purchases',
      true,
      const PurchasesNotYet(),
      false,
    ),
    (
      'offer on, web build (More lists it there)',
      true,
      const PurchasesUnsupported(),
      true,
    ),
    ('offer on, store build that sells', true, null, true),
  ]) {
    testWidgets('locked row before sales start, $name: only title and count, '
        '${opens ? '' : 'not '}a button', (tester) async {
      await pumpHistory(
        tester,
        trips: all,
        premium: false,
        premiumServer: FakePremiumServer(offer: offer),
        noSale: noSale,
      );
      await expectQuietRow(tester, opens: opens);
    });
  }

  testWidgets('sales starting while the tab is kept alive: the row becomes '
      'a button once the tab is back', (tester) async {
    final server = FakePremiumServer(offer: false);
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpHistory(
      tester,
      trips: all,
      premium: false,
      premiumServer: server,
      shown: shown,
    );
    await expectQuietRow(tester, opens: false);
    server.offer = true;
    shown.value = false;
    await tester.pumpAndSettle();
    shown.value = true;
    await tester.pumpAndSettle();
    await expectQuietRow(tester, opens: true);
  });

  testWidgets('offer unreadable: plain text, as More hides Premium then', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      trips: all,
      premium: false,
      premiumServer: FakePremiumServer()..offerFails = true,
    );
    await expectQuietRow(tester, opens: false);
  });

  testWidgets('Free logs a trip older than 4 weeks: it is saved, then counted '
      'as locked, not listed', (tester) async {
    final history = await pumpHistory(tester, trips: [recent], premium: false);
    expect(find.text(lockedTitle), findsNothing);
    await tester.tap(key('log-add'));
    await tester.pumpAndSettle();
    await tester.tap(key('trip-store-lidl'));
    await tester.enterText(key('trip-item-name-0'), 'Mehl');
    await tester.tap(key('trip-day-other'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(InputDatePickerFormField),
        matching: find.byType(TextField),
      ),
      '01.09.2026',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(key('trip-save'));
    await tester.pumpAndSettle();

    final saved = history.trips.saved.single;
    expect(saved.day, DateTime(2026, 9));
    expect(saved.items.single.name, 'Mehl');
    expect(key('log-trip-${saved.id}'), findsNothing);
    await tester.scrollUntilVisible(key('log-journal-locked'), 100);
    expect(find.text('1 älterer Einkauf'), findsOneWidget);
  });

  group('paywall-cs1 (job 327)', () {
    Finder pageList() => find.descendant(
      of: key('lifetime-screen'),
      matching: find.byType(Scrollable),
    );

    Future<void> openFromLock(WidgetTester tester) async {
      await tester.scrollUntilVisible(key('log-journal-locked'), 100);
      await tester.ensureVisible(key('log-locked-premium'));
      await tester.pumpAndSettle();
      await tester.tap(key('log-locked-premium'));
      await tester.pumpAndSettle();
    }

    for (final offer in [true, false]) {
      testWidgets('offer ${offer ? 'on' : 'off'}: the locked row opens the '
          'Premium page over Verlauf; closing it shows Verlauf again', (
        tester,
      ) async {
        final history = await pumpHistory(
          tester,
          trips: all,
          premium: false,
          premiumServer: FakePremiumServer(offer: offer),
          flags: {paywallCs1Flag},
          sells: true,
        );
        await openFromLock(tester);
        expect(key('lifetime-screen'), findsOneWidget);
        expect(key('log-journal'), findsNothing, reason: 'covered');
        expect(find.textContaining('premium-page:'), findsNothing);
        expect(history.router.state.uri.path, '/', reason: 'Verlauf stays');
        expect(
          [
            for (final (event, properties) in history.analytics.events)
              '$event $properties',
          ],
          offer ? ['paywall_viewed {entry_point: history}'] : isEmpty,
          reason: 'sent only where the page offers a plan',
        );

        await tester.tap(key('paywall-close'));
        await tester.pumpAndSettle();
        expect(key('lifetime-screen'), findsNothing);
        expect(key('log-journal-locked'), findsOneWidget);
        expect(find.text('2 ältere Einkäufe'), findsOneWidget);
        expect(history.router.state.uri.path, '/');
      });
    }

    testWidgets('a purchase from the paywall closes it, and Verlauf shows the '
        'older trips without the lock', (tester) async {
      final history = await pumpHistory(
        tester,
        trips: all,
        premium: false,
        flags: {paywallCs1Flag},
        sells: true,
        size: const Size(390, 1400),
      );
      await openFromLock(tester);
      await tester.scrollUntilVisible(
        key('premium-buy-yearly'),
        200,
        scrollable: pageList(),
      );
      await tester.tap(key('premium-buy-yearly'));
      await tester.pump();
      final purchases = history.purchases!;
      expect(purchases.repository.calls, ['buy peter yearly']);
      expect(key('lifetime-screen'), findsOneWidget, reason: 'unlocking');

      // The webhook's row arrives; the server then reads the whole history.
      history.trips.premium = true;
      purchases.unlock();
      await tester.pumpAndSettle();
      expect(key('lifetime-screen'), findsNothing, reason: 'closed by itself');
      expect(find.text(lockedTitle), findsNothing);
      await tester.scrollUntilVisible(key('log-trip-${old.id}'), 100);
      expect(key('log-trip-${justOut.id}'), findsOneWidget);
    });

    testWidgets("the calendar's hint under a locked month opens it too", (
      tester,
    ) async {
      await pumpHistory(
        tester,
        trips: all,
        premium: false,
        premiumServer: FakePremiumServer(offer: false),
        flags: {paywallCs1Flag},
        sells: true,
      );
      await previousMonth(tester);
      await tester.tap(
        find.descendant(
          of: key('log-calendar-locked'),
          matching: key('log-locked-premium'),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('lifetime-screen'), findsOneWidget);
    });
  });
}
