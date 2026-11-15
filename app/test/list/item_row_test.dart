import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/leaving_rows.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Item _item(String name, {String? quantity}) {
  final at = DateTime.utc(2026, 11);
  return Item(
    id: name,
    name: name,
    quantity: quantity,
    status: ItemStatus.active,
    createdAt: at,
    updatedAt: at,
    categoryId: 'produce',
    sortKey: 0,
  );
}

void main() {
  late List<Item> started;
  late List<Item> ticked;
  late LeavingRows leaving;

  setUp(() {
    started = [];
    ticked = [];
    leaving = LeavingRows();
  });
  tearDown(() => leaving.dispose());

  Future<void> pumpRows(
    WidgetTester tester,
    List<Item> items, {
    double width = 390,
    Locale locale = const Locale('de'),
    bool tickers = true,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TickerMode(
              enabled: tickers,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    ItemRow(
                      key: ValueKey(item.id),
                      item: item,
                      category: null,
                      leaving: leaving,
                      fresh: false,
                      last: item == items.last,
                      onVisible: (_) {},
                      onTickStart: started.add,
                      onTick: ticked.add,
                      onEdit: (_) {},
                      onDelete: (_) {},
                    ),
                  const SizedBox(key: ValueKey('below'), height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Finder row(String name) => find.byKey(ValueKey(name));

  StrikePainter? strike(WidgetTester tester, String name) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: row(name), matching: find.byType(CustomPaint)),
      )
      .map((p) => p.foregroundPainter)
      .whereType<StrikePainter>()
      .firstOrNull;

  Finder nameText(String name) => find.descendant(
    of: row(name),
    matching: find.byWidgetPredicate(
      (w) => w is Text && (w.textSpan?.toPlainText() ?? '').endsWith(name),
    ),
  );

  testWidgets('the row reads unchecked, then checked and announces the '
      'tick', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRows(tester, [_item('Milch')]);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Milch')),
      isSemantics(
        label: 'Milch',
        isButton: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    await tester.tap(row('Milch'));
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Milch')),
      isSemantics(
        label: 'Milch',
        isButton: true,
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Milch abgehakt'),
    ]);
    await tester.pumpAndSettle();
    expect(ticked, hasLength(1));
    handle.dispose();
  });

  testWidgets('English announces "ticked off"', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRows(tester, [_item('Milk')], locale: const Locale('en'));
    await tester.tap(row('Milk'));
    await tester.pump();
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Milk ticked off'),
    ]);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('the line draws left to right, then the row closes its gap '
      'and the tick commits once', (tester) async {
    await pumpRows(tester, [_item('Milch'), _item('Brot')]);
    final height = tester.getSize(row('Milch')).height;
    final below = tester.getTopLeft(row('Brot')).dy;
    expect(height, greaterThanOrEqualTo(48), reason: 'a full tap target');
    expect(strike(tester, 'Milch'), isNull, reason: 'no line while open');

    await tester.tap(row('Milch'));
    await tester.pump();
    await tester.pump(HlDuration.short ~/ 2);
    final half = strike(tester, 'Milch')!.progress;
    expect(half, inExclusiveRange(0, 1), reason: 'drawing');
    expect(tester.getSize(row('Milch')).height, height, reason: 'not yet');

    await tester.pump(HlDuration.short ~/ 2);
    expect(
      strike(tester, 'Milch')!.progress,
      closeTo(1, 1e-3),
      reason: 'drawn',
    );
    await tester.pump(HlDuration.medium ~/ 2);
    expect(
      tester.getTopLeft(row('Brot')).dy,
      inExclusiveRange(below - height, below),
      reason: 'the row below moves up with the close',
    );
    expect(ticked, isEmpty, reason: 'the tick waits for the close');

    await tester.tap(row('Milch'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ticked.map((i) => i.name), ['Milch'], reason: 'once');
    expect(tester.getSize(row('Milch')).height, 0, reason: 'gap closed');
  });

  testWidgets('with reduced motion the struck row shows at once, holds, '
      'then ticks without a close', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpRows(tester, [_item('Milch'), _item('Brot')]);
    final height = tester.getSize(row('Milch')).height;

    await tester.tap(row('Milch'));
    await tester.pump();
    expect(strike(tester, 'Milch')!.progress, 1, reason: 'struck at once');
    expect(tester.getSize(row('Milch')).height, height, reason: 'no close');
    expect(ticked, isEmpty, reason: 'the struck row is seen first');

    await tester.pump(HlDuration.medium);
    expect(ticked.map((i) => i.name), ['Milch']);
    expect(tester.getSize(row('Milch')).height, height);
    expect(tester.hasRunningAnimations, isFalse);
  });

  group('a tick is not lost with its row (job 222):', () {
    void reducedMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    for (final reduced in [false, true]) {
      final motion = reduced ? 'reduced motion' : 'motion';
      testWidgets('the tap tells of the tick at once, before any frame, and '
          'once ($motion)', (tester) async {
        if (reduced) {
          reducedMotion(tester);
        }
        await pumpRows(tester, [_item('Milch'), _item('Brot')]);
        await tester.tap(row('Milch'));
        expect(started.map((i) => i.name), ['Milch']);
        expect(ticked, isEmpty, reason: 'the row is seen first');

        await tester.pump();
        await tester.tap(row('Milch'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.pump(rowLeaveDuration);
        expect(started, hasLength(1), reason: 'once');
        expect(ticked.map((i) => i.name), ['Milch']);
      });
    }

    testWidgets("a screen reader's tap tells of the tick at once too", (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpRows(tester, [_item('Milch')]);
      tester.semantics.tap(find.semantics.byLabel('Milch'));
      expect(started.map((i) => i.name), ['Milch']);
      await tester.pumpAndSettle();
      expect(ticked, hasLength(1));
      handle.dispose();
    });

    void hide(WidgetTester tester) => tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);

    void show(WidgetTester tester) => tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    for (final reduced in [false, true]) {
      final motion = reduced ? 'reduced motion' : 'motion';
      testWidgets('a row that goes away while it leaves commits its tick '
          'then, once ($motion)', (tester) async {
        if (reduced) {
          reducedMotion(tester);
        }
        await pumpRows(tester, [_item('Milch'), _item('Brot')]);
        await tester.tap(row('Milch'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(ticked, isEmpty);

        // Scrolled out of the lazy list, its store folded, the list closed.
        await pumpRows(tester, [_item('Brot')]);
        await tester.pump();
        expect(ticked.map((i) => i.name), ['Milch']);

        await tester.pump(rowLeaveDuration);
        expect(ticked, hasLength(1), reason: 'once');
      });

      testWidgets('the app going to the background commits the tick at '
          'once: no frame comes there ($motion)', (tester) async {
        if (reduced) {
          reducedMotion(tester);
        }
        await pumpRows(tester, [_item('Milch'), _item('Brot')]);
        await tester.tap(row('Milch'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(ticked, isEmpty);

        hide(tester);
        expect(ticked.map((i) => i.name), ['Milch']);

        show(tester);
        await tester.pumpAndSettle();
        await tester.pump(rowLeaveDuration);
        expect(ticked, hasLength(1), reason: 'once');
      });
    }

    testWidgets('an app that is only inactive (the app switcher, a call) '
        'commits nothing yet: its frames go on', (tester) async {
      await pumpRows(tester, [_item('Milch'), _item('Brot')]);
      await tester.tap(row('Milch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(ticked, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticked, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(ticked, isEmpty, reason: 'coming back commits nothing either');
      await tester.pump();
      expect(ticked, isEmpty, reason: 'nor does its next frame');
      await tester.pumpAndSettle();
      expect(ticked.map((i) => i.name), ['Milch']);
    });

    testWidgets('a hidden app commits no tick that was not made', (
      tester,
    ) async {
      await pumpRows(tester, [_item('Milch'), _item('Brot')]);
      hide(tester);
      expect(ticked, isEmpty);
      show(tester);
      await tester.tap(row('Milch'));
      await tester.pumpAndSettle();
      expect(ticked.map((i) => i.name), ['Milch']);
      hide(tester);
      expect(ticked, hasLength(1), reason: 'committed already');
      show(tester);
    });

    testWidgets('the tick comes while the row draws no frames (another tab '
        'in front): twice the close after the tap', (tester) async {
      await pumpRows(tester, [_item('Milch'), _item('Brot')]);
      await tester.tap(row('Milch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await pumpRows(tester, [_item('Milch'), _item('Brot')], tickers: false);
      await tester.pump(
        rowLeaveDuration * 2 - const Duration(milliseconds: 101),
      );
      expect(ticked, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(ticked.map((i) => i.name), ['Milch']);

      await pumpRows(tester, [_item('Milch'), _item('Brot')]);
      await tester.pumpAndSettle();
      expect(ticked, hasLength(1), reason: 'once');
    });

    testWidgets('a first frame that comes late cuts nothing off the close: '
        "the tick waits for the row's end", (tester) async {
      await pumpRows(tester, [_item('Milch'), _item('Brot')]);
      await tester.tap(row('Milch'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(rowLeaveDuration - const Duration(milliseconds: 1));
      expect(ticked, isEmpty, reason: 'still closing');
      expect(tester.getSize(row('Milch')).height, greaterThan(0));

      // The animation ends with the first frame after its time.
      await tester.pump(const Duration(milliseconds: 2));
      expect(tester.getSize(row('Milch')).height, 0);
      expect(ticked.map((i) => i.name), ['Milch']);
      await tester.pump(rowLeaveDuration);
      expect(ticked, hasLength(1), reason: 'once');
    });

    testWidgets('a row listens for the app going away only until its tick '
        "is committed: at the row's end, in the background, with the row", (
      tester,
    ) async {
      final listening = <Object>{};
      void track(ObjectEvent event) {
        if (event.object is AppLifecycleListener) {
          switch (event) {
            case ObjectCreated():
              listening.add(event.object);
            case ObjectDisposed():
              listening.remove(event.object);
          }
        }
      }

      FlutterMemoryAllocations.instance.addListener(track);
      addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(track),
      );
      final rows = [_item('Milch'), _item('Brot'), _item('Eier')];
      await pumpRows(tester, rows);

      await tester.tap(row('Milch'));
      await tester.pump();
      expect(listening, hasLength(1));
      await tester.pump(rowLeaveDuration + const Duration(milliseconds: 1));
      expect(ticked, hasLength(1));
      expect(listening, isEmpty, reason: "the row's end");

      await tester.tap(row('Brot'));
      await tester.pump();
      expect(listening, hasLength(1));
      hide(tester);
      expect(ticked, hasLength(2));
      expect(listening, isEmpty, reason: 'the background');
      show(tester);

      await tester.tap(row('Eier'));
      await tester.pump();
      expect(listening, hasLength(1));
      await pumpRows(tester, rows.sublist(0, 2));
      await tester.pump();
      expect(ticked, hasLength(3));
      expect(listening, isEmpty, reason: 'the row');
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the line is as wide as the name with its quantity, not the '
      'row', (tester) async {
    await pumpRows(tester, [_item('Milch', quantity: '2')]);
    await tester.tap(row('Milch'));
    await tester.pump();
    await tester.pump(HlDuration.short);
    final text = tester.getSize(nameText('Milch'));
    final lines = strike(tester, 'Milch')!.lines(text);
    expect(lines, hasLength(1));
    expect(
      lines.single.width,
      closeTo(text.width + 2 * StrikePainter.overhang, 1),
    );
    expect(
      lines.single.width,
      lessThan(tester.getSize(row('Milch')).width / 2),
    );
    await tester.pumpAndSettle();
  });

  testWidgets("a name on two lines gets a line under each line's own "
      'width', (tester) async {
    const name = 'Laktosefreie Vollmilch extra lange Haltbarkeit Bio';
    await pumpRows(tester, [_item(name)], width: 260);
    await tester.tap(row(name));
    await tester.pump();
    await tester.pump(HlDuration.short);
    final text = tester.getSize(nameText(name));
    final painter = strike(tester, name)!;
    final lines = painter.lines(text);
    expect(lines.length, greaterThanOrEqualTo(2));
    for (final line in lines) {
      expect(
        line.width,
        lessThanOrEqualTo(text.width + 2 * StrikePainter.overhang + 1),
      );
    }
    expect(lines[1].top, greaterThan(lines[0].top));

    await tester.pumpAndSettle();
  });
}
