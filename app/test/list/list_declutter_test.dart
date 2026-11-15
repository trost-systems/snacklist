import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/price_views.dart';
import 'package:family_groceries/list/list_view/summary_block.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/tips/hint_views.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import '../more/more_harness.dart';
import 'fake_repository.dart';

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _diy = HouseholdList(id: 'diy', name: 'Baumarkt', position: 1);

Price _price(int cents) => Price(
  unitMicros: cents * microsPerCent,
  basis: PriceBasis.unit,
  per: PricePer.piece,
  currency: 'EUR',
  // The list reads the device's clock, and a price counts on its day only.
  pricedAt: DateTime.now(),
);

/// Job 229, flag `list-declutter`: the list's header without list tabs, one
/// switcher for household and list, a see-through header the list scrolls
/// under, and the total as a row of the list.
void main() {
  setUpAll(() async {
    await fakeSupabase();
    // Real glyphs: widths and line heights depend on them.
    await loadAppFonts();
  });
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);

  /// The app on the list tab, on two lists with [rows] open items on the
  /// shown one, all at Lidl.
  Future<More> pumpList(
    WidgetTester tester, {
    Set<String> flags = const {listDeclutterFlag},
    int rows = 3,
    Size size = const Size(390, 844),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    AppLanguage? language,

    /// The status bar and the home indicator, as on an iPhone.
    ({double top, double bottom}) insets = (top: 0, bottom: 0),
    void Function(FakeRepository repo)? seed,
  }) {
    tester.view
      ..padding = FakeViewPadding(top: insets.top, bottom: insets.bottom)
      ..viewPadding = FakeViewPadding(top: insets.top, bottom: insets.bottom);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    return pumpMore(
      tester,
      location: listPath,
      app: true,
      size: size,
      deviceBrightness: brightness,
      language: language,
      flags: flags,
      seed: (repo) {
        repo
          ..lists = const [_weekly, _diy]
          ..remoteAdd('Schrauben', listId: 'diy');
        for (var i = 0; i < rows; i++) {
          repo.remoteAdd('Artikel $i', storeId: 'lidl');
        }
        seed?.call(repo);
      },
    );
  }

  testWidgets('flag off: the household chip and the list tabs, as before', (
    tester,
  ) async {
    await pumpList(tester, flags: const {});
    expect(key('household-chip'), findsOneWidget);
    expect(key('list-tabs'), findsOneWidget);
    expect(key('list-switcher'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('flag on: no list tabs; one switcher names the household over '
      'the shown list', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    expect(key('list-tabs'), findsNothing);
    expect(key('household-chip'), findsNothing);
    final switcher = key('list-switcher');
    expect(
      find.descendant(of: switcher, matching: find.text('Zuhause')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: switcher, matching: find.text('Wocheneinkauf')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: switcher, matching: find.byIcon(Icons.unfold_more)),
      findsOneWidget,
    );
    final household = tester.getRect(find.text('Zuhause'));
    final list = tester.getRect(find.text('Wocheneinkauf'));
    expect(household.bottom, lessThanOrEqualTo(list.top + 1));
    expect(tester.getSize(switcher).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(switcher),
      matchesSemantics(
        label: 'Wocheneinkauf · Zuhause',
        hint: 'Liste oder Haushalt wechseln',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a tap on the switcher opens the switcher sheet', (tester) async {
    await pumpList(tester);
    await tester.tap(key('list-switcher'));
    await tester.pumpAndSettle();
    expect(key('switcher-sheet'), findsOneWidget);
  });

  testWidgets('one household and one list: the switcher still shows', (
    tester,
  ) async {
    await pumpMore(
      tester,
      location: listPath,
      app: true,
      flags: {listDeclutterFlag},
      seed: (repo) => repo
        ..lists = const [
          HouseholdList(
            id: 'main',
            name: 'Einkaufsliste',
            position: 0,
            seedKey: 'main',
          ),
        ]
        ..remoteAdd('Milch'),
    );
    expect(
      find.descendant(
        of: key('list-switcher'),
        matching: find.text('Einkaufsliste'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the header is one clear layer from the screen top; the list '
      'scrolls under it, only the status bar gets a scrim, and rows there '
      'take no taps', (tester) async {
    final app = await pumpList(tester, rows: 30, insets: (top: 47, bottom: 34));
    final layer = tester.getRect(key('list-header-layer'));
    expect(layer.top, 0, reason: 'the status bar area is part of it');
    expect(
      tester.getRect(key('list-switcher')).bottom,
      lessThanOrEqualTo(layer.bottom),
    );
    expect(find.byType(BackdropFilter), findsNothing, reason: 'no blur');
    final scrim = key('list-status-bar-scrim');
    expect(scrim, findsNothing, reason: 'nothing under the clock yet');

    await tester.drag(row('Artikel 5'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final under = [
      for (var i = 0; i < 30; i++)
        if (row('Artikel $i').evaluate().isNotEmpty &&
            tester.getRect(row('Artikel $i')).overlaps(layer))
          'Artikel $i',
    ];
    expect(under, isNotEmpty, reason: 'rows scroll on under the header');
    expect(tester.getRect(scrim), const Rect.fromLTRB(0, 0, 390, 47));
    expect(
      find.descendant(
        of: key('list-header-layer'),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
      reason: 'the scrim is all the layer paints: no face, no edge line',
    );

    // In the gap below the bar, over a row's text.
    final spot = Offset(195, layer.bottom - 2);
    final hidden = under.firstWhere(
      (name) => tester.getRect(row(name)).contains(spot),
    );
    await tester.tapAt(spot);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      app.repo.rows.values.firstWhere((i) => i.name == hidden).status,
      ItemStatus.active,
      reason: 'a tap on the header never ticks $hidden under it',
    );
  });

  testWidgets('the header is an opaque semantics node: on the web rows under '
      'it do not take a click', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester, rows: 30);
    final layer = tester.getRect(key('list-header-layer'));
    // The switcher's node and those above it, top down, in screen pixels.
    final chain = <SemanticsNode>[];
    for (
      SemanticsNode? node = tester.getSemantics(key('list-switcher'));
      node != null;
      node = node.parent
    ) {
      chain.insert(0, node);
    }
    final opaque = <Rect>[];
    var transform = Matrix4.identity();
    // The root's own transform takes logical pixels to physical ones.
    for (final node in chain.skip(1)) {
      if (node.transform case final own?) {
        transform = transform.multiplied(own);
      }
      if (node.getSemanticsData().hitTestBehavior ==
          SemanticsHitTestBehavior.opaque) {
        opaque.add(MatrixUtils.transformRect(transform, node.rect));
      }
    }
    expect(
      opaque.any(
        (r) =>
            (r.left - layer.left).abs() < 1 &&
            (r.top - layer.top).abs() < 1 &&
            (r.right - layer.right).abs() < 1 &&
            (r.bottom - layer.bottom).abs() < 1,
      ),
      isTrue,
      reason: '$opaque',
    );
    semantics.dispose();
  });

  /// How far apart the lightest and darkest pixels of [area] lie, outside
  /// [skip], in luminance from 0 to 1: rows that pass under it at full
  /// strength reach far more than rows blurred or faded out.
  Future<double> contrast(
    WidgetTester tester,
    Rect area, {
    List<Rect> skip = const [],
  }) async {
    final bytes = (await tester.runAsync(() async {
      final image = await captureImage(
        tester.element(find.byType(Scaffold).first),
      );
      final data = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (data!, width);
    }))!;
    final (data, width) = bytes;
    var low = 1.0;
    var high = 0.0;
    for (var y = area.top.ceil(); y < area.bottom.floor(); y++) {
      for (var x = area.left.ceil(); x < area.right.floor(); x++) {
        final at = Offset(x + .5, y + .5);
        if (skip.any((r) => r.contains(at))) {
          continue;
        }
        final i = (y * width + x) * 4;
        final l =
            (0.2126 * data.getUint8(i) +
                0.7152 * data.getUint8(i + 1) +
                0.0722 * data.getUint8(i + 2)) /
            255;
        low = l < low ? l : low;
        high = l > high ? l : high;
      }
    }
    return high - low;
  }

  for (final (name, size, insets) in const [
    ('iPhone', Size(390, 844), (top: 47.0, bottom: 34.0)),
    ('358 px', Size(358, 640), (top: 20.0, bottom: 0.0)),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('$name, ${brightness.name}: rows show at full strength '
          'behind the bar and behind the add field and the tab pill', (
        tester,
      ) async {
        await pumpList(
          tester,
          flags: {listDeclutterFlag, pricesFlag},
          rows: 0,
          size: size,
          insets: insets,
          brightness: brightness,
          // Names that run on under the gap between the bar's buttons.
          seed: (repo) {
            for (var i = 0; i < 30; i++) {
              repo.remoteAdd('Hafermilch ohne Zucker $i', storeId: 'lidl');
            }
          },
        );
        await tester.dragFrom(
          Offset(size.width / 2, size.height / 2),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        final layer = tester.getRect(key('list-header-layer'));
        Rect around(String k) => tester.getRect(key(k)).inflate(8);
        // Below the status bar, beside the bar's buttons.
        final top = await contrast(
          tester,
          Rect.fromLTRB(0, insets.top, size.width, layer.bottom),
          skip: [around('list-switcher'), around('list-edit')],
        );
        // Below the add field's hex, beside and under the tab pill.
        final hex = tester.getRect(key('add-bar-hex'));
        final bottom = await contrast(
          tester,
          Rect.fromLTRB(0, hex.top, size.width, size.height),
          skip: [hex.inflate(4), around('tab-pill')],
        );
        expect(top, greaterThan(0.4), reason: 'rows behind the bar');
        expect(bottom, greaterThan(0.4), reason: 'rows behind the add field');
      });
    }
  }

  for (final (name, size, insets) in const [
    ('iPhone', Size(390, 844), (top: 47.0, bottom: 34.0)),
    ('358 px', Size(358, 640), (top: 20.0, bottom: 0.0)),
  ]) {
    for (final (language, title) in const [
      (AppLanguage.de, 'Einkaufssumme'),
      (AppLanguage.en, 'Shopping total'),
    ]) {
      testWidgets('$name, ${language.code}: at the end the total and the last '
          'row lie above the add field and take taps', (tester) async {
        final app = await pumpList(
          tester,
          flags: {listDeclutterFlag, pricesFlag},
          rows: 20,
          size: size,
          insets: insets,
          language: language,
          brightness: Brightness.dark,
          seed: (repo) => repo
            ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
            ..remoteAdd('Kaffee', status: ItemStatus.bought),
        );
        for (var i = 0; i < 6; i++) {
          await tester.dragFrom(
            Offset(size.width / 2, size.height / 2),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
        }
        final hex = tester.getRect(key('add-bar-hex'));
        final total = tester.getRect(find.byType(SummaryBlock));
        expect(total.bottom, lessThanOrEqualTo(hex.top), reason: '$total');
        expect(total.top, greaterThan(insets.top));
        expect(find.text(title), findsOneWidget);
        final used = key('recently-used');
        expect(tester.getRect(used).bottom, lessThanOrEqualTo(hex.top));
        await tester.tap(used.hitTestable());
        await tester.pumpAndSettle();
        // Open, Zuletzt verwendet's rows scroll clear of the field too.
        await tester.dragFrom(
          Offset(size.width / 2, size.height / 2),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        final kaffee = app.repo.rows.values.firstWhere(
          (i) => i.name == 'Kaffee',
        );
        final coffee = key('used-${kaffee.id}');
        expect(tester.getRect(coffee).bottom, lessThanOrEqualTo(hex.top));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the flag arriving late keeps the scroll position', (
    tester,
  ) async {
    // PostHog answers after the first frames of a cold start.
    await pumpList(tester, flags: const {}, rows: 30);
    await tester.dragFrom(const Offset(195, 422), const Offset(0, -400));
    await tester.pumpAndSettle();
    ScrollPosition list() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = list().pixels;
    expect(before, greaterThan(300));
    tester.element(find.byType(Scaffold).first).read<Flags>().replace({
      listDeclutterFlag: true,
    });
    await tester.pumpAndSettle();
    expect(key('list-switcher'), findsOneWidget);
    expect(list().pixels, greaterThan(300), reason: 'was $before');
  });

  testWidgets('the first row starts below the bar, with no room for tabs', (
    tester,
  ) async {
    await pumpList(tester);
    final layer = tester.getRect(key('list-header-layer'));
    expect(
      tester.getRect(find.byType(ListHints)).top,
      closeTo(layer.bottom, 1),
    );
  });

  group('the total', () {
    final priced = <String>{pricesFlag, listDeclutterFlag};

    void seed(FakeRepository repo) => repo
      ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
      ..remoteAdd('Kaffee', status: ItemStatus.bought);

    testWidgets('is a row after the open items, before Zuletzt verwendet', (
      tester,
    ) async {
      await pumpList(tester, flags: priced, seed: seed);
      final total = find.byType(SummaryBlock);
      expect(total, findsOneWidget);
      final rect = tester.getRect(total);
      for (var i = 0; i < 3; i++) {
        expect(
          tester.getRect(row('Artikel $i')).bottom,
          lessThanOrEqualTo(rect.top),
        );
      }
      expect(tester.getRect(row('Milch')).bottom, lessThanOrEqualTo(rect.top));
      expect(
        rect.bottom,
        lessThanOrEqualTo(tester.getRect(key('recently-used')).top),
      );
      expect(
        tester.getRect(key('add-item-field')).top,
        greaterThan(rect.bottom),
        reason: 'not a bar over the add field',
      );
      expect(find.text('Einkaufssumme'), findsOneWidget);
      // Three Artikel without a price: a floor (job 237).
      expect(
        tester.widget<Text>(key('total-amount')).textSpan?.toPlainText(),
        'mind. 1,19\u00a0€',
      );

      // It scrolls with the list.
      final before = rect.top;
      await tester.drag(row('Artikel 1'), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(tester.getRect(total).top, lessThan(before));
    });

    testWidgets('flag off: the total stays the bar at the bottom', (
      tester,
    ) async {
      await pumpList(tester, flags: const {pricesFlag}, seed: seed);
      final total = find.byType(TotalBar);
      expect(
        find.ancestor(of: total, matching: find.byType(CustomScrollView)),
        findsNothing,
      );
      expect(
        tester.getRect(total).bottom,
        lessThanOrEqualTo(tester.getRect(key('add-item-field')).top),
      );
    });

    testWidgets('358 x 740 with the keyboard up: the price editor fits above '
        'the keyboard and takes taps', (tester) async {
      await pumpList(
        tester,
        flags: priced,
        size: const Size(358, 740),
        rows: 6,
        seed: (repo) => repo.remoteAdd(
          'Wasser',
          storeId: 'lidl',
          quantity: '2 Pack',
          price: _price(69),
        ),
      );
      final chip = find
          .descendant(of: row('Wasser'), matching: find.byType(PriceChip))
          .last;
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip.hitTestable());
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      const visible = Rect.fromLTWH(0, 0, 358, 740 - 300);
      final panel = tester.getRect(find.byType(PricePanel));
      final layer = tester.getRect(key('list-header-layer'));
      expect(panel.top, greaterThanOrEqualTo(layer.bottom), reason: '$panel');
      expect(panel.bottom, lessThanOrEqualTo(visible.bottom), reason: '$panel');
      for (final k in ['price-field', 'price-done', 'price-cancel']) {
        expect(key(k).hitTestable(), findsOneWidget, reason: k);
      }
    });
  });

  for (final scale in const [1.3, 1.6]) {
    for (final brightness in Brightness.values) {
      testWidgets('$scale text, ${brightness.name}: the header fits on '
          '358 px, the switcher keeps both lines', (tester) async {
        await pumpList(
          tester,
          flags: {listDeclutterFlag, pricesFlag},
          size: const Size(358, 740),
          textScale: scale,
          brightness: brightness,
          seed: (repo) =>
              repo.remoteAdd('Milch', storeId: 'lidl', price: _price(119)),
        );
        expect(tester.takeException(), isNull);
        final switcher = key('list-switcher');
        for (final text in ['Zuhause', 'Wocheneinkauf']) {
          final line = find.descendant(of: switcher, matching: find.text(text));
          expect(line, findsOneWidget, reason: text);
          expect(
            tester.getRect(line).bottom,
            lessThanOrEqualTo(tester.getRect(switcher).bottom),
            reason: '$text inside the button',
          );
        }
        expect(tester.getSize(switcher).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(key('list-edit')).right, lessThanOrEqualTo(358));
        await tester.scrollUntilVisible(
          find.byType(SummaryBlock),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in const [Size(358, 760), Size(390, 844)]) {
    testWidgets('130 % text on ${size.width.toInt()} px: the tab pill keeps '
        'Liste, Verlauf and Mehr', (tester) async {
      await pumpList(
        tester,
        flags: {listDeclutterFlag, groceryLogFlag},
        size: size,
        textScale: 1.3,
      );
      for (final (tab, label) in [
        ('tab-list', 'Liste'),
        ('tab-history', 'Verlauf'),
        ('tab-more', 'Mehr'),
      ]) {
        final text = find.descendant(of: key(tab), matching: find.text(label));
        expect(text, findsOneWidget, reason: '$label shows');
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
          reason: '$label is not cut',
        );
      }
    });
  }

  /// A week's list as on Peter's phone (build 1325): dm, Lidl and items
  /// without a store, some priced.
  void weekly(FakeRepository repo) {
    repo
      ..remoteAdd(
        'Windeln',
        storeId: 'dm',
        brand: 'babylove',
        properties: 'Größe 3',
      )
      ..remoteAdd('Zahnpasta', storeId: 'dm', price: _price(195))
      ..remoteAdd('Frikadellen', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd(
        'Milch',
        storeId: 'lidl',
        categoryId: 'chilled',
        quantity: '2',
        price: _price(119),
      )
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Butter', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Bananen', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Gurke', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Tomaten', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Paprika', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Brot', storeId: 'lidl', price: _price(249))
      ..remoteAdd('Töpfchen')
      ..remoteAdd('Glühbirnen')
      ..remoteAdd('Kaffee', status: ItemStatus.bought);
  }

  group('screenshots (job 242)', () {
    for (final (name, size, insets) in const [
      ('iphone', Size(390, 844), (top: 47.0, bottom: 34.0)),
      ('compact', Size(358, 640), (top: 20.0, bottom: 0.0)),
    ]) {
      for (final (language, brightness) in const [
        (AppLanguage.de, Brightness.dark),
        (AppLanguage.en, Brightness.light),
      ]) {
        final shot = 'goldens/declutter-$name-${language.code}';
        testWidgets('$shot: scrolled, and at the end with the total', (
          tester,
        ) async {
          await pumpList(
            tester,
            flags: {listDeclutterFlag, pricesFlag},
            rows: 0,
            size: size,
            insets: insets,
            language: language,
            brightness: brightness,
            seed: weekly,
          );
          final screen = find.byType(Scaffold).first;
          await tester.dragFrom(
            Offset(size.width / 2, size.height / 2),
            const Offset(0, -150),
          );
          await tester.pumpAndSettle();
          await expectLater(screen, matchesGoldenFile('$shot-scrolled.png'));
          for (var i = 0; i < 4; i++) {
            await tester.dragFrom(
              Offset(size.width / 2, size.height / 2),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
          }
          // Back up a little: the total runs on under the add field.
          await tester.dragFrom(
            Offset(size.width / 2, size.height / 2),
            const Offset(0, 60),
          );
          await tester.pumpAndSettle();
          await expectLater(screen, matchesGoldenFile('$shot-end.png'));
        });
      }
    }
  });
}
