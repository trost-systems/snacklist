import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/annotator.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';

Finder key(String k) => find.byKey(ValueKey(k));

/// A plain white screen to mark up.
Future<ui.Image> blankScreen(WidgetTester tester, Size size) async =>
    (await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
      return recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
    }))!;

/// The RGBA pixels of [png].
Future<({int width, int height, ByteData pixels})> decode(
  WidgetTester tester,
  Uint8List png,
) async => (await tester.runAsync(() async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = (await codec.getNextFrame()).image;
  final data = await frame.toByteData();
  return (width: frame.width, height: frame.height, pixels: data!);
}))!;

/// Pumps the annotator over a page with [brightness] and opens it on a
/// white screen; the value its route pops with lands in the record.
Future<({Future<Uint8List?> result, Size size})> open(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('de'),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final size = tester.view.physicalSize;
  final image = await blankScreen(tester, size);
  late Future<Uint8List?> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness),
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('go'),
              onPressed: () => result = annotateScreenshot(context, image),
              child: const SizedBox.square(dimension: 48),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(key('go'));
  await tester.pumpAndSettle();
  return (result: result, size: size);
}

/// [fraction] of the way across the screenshot as it shows, scaled down.
Offset at(WidgetTester tester, Offset fraction) {
  final shown = tester.getRect(key('annotator-canvas'));
  return shown.topLeft +
      Offset(shown.width * fraction.dx, shown.height * fraction.dy);
}

Future<void> drag(WidgetTester tester, List<Offset> fractions) async {
  final gesture = await tester.startGesture(at(tester, fractions.first));
  for (final f in fractions.skip(1)) {
    await gesture.moveTo(at(tester, f));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

/// Taps Fertig and waits for BetterFeedback's capture.
Future<Uint8List?> done(WidgetTester tester, Future<Uint8List?> result) async {
  await tester.tap(key('annotator-done'));
  Uint8List? png;
  var finished = false;
  unawaited(
    result.then((value) {
      png = value;
      finished = true;
    }),
  );
  // BetterFeedback waits, captures (real async) and animates away.
  for (var i = 0; i < 200 && !finished; i++) {
    await tester.runAsync(
      // ast-grep-ignore: no-wall-time-wait-in-tests -- runAsync: engine work
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(finished, isTrue, reason: 'the route popped');
  return png;
}

void main() {
  final tomato = SnacklistColors.of(Brightness.light).tomato;

  bool isTomato(ByteData pixels, int width, Offset p) {
    final i = (p.dy.round() * width + p.dx.round()) * 4;
    final (r, g, b) = (
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
    return (r - (tomato.r * 255).round()).abs() < 40 &&
        (g - (tomato.g * 255).round()).abs() < 40 &&
        (b - (tomato.b * 255).round()).abs() < 40;
  }

  testWidgets('pen, rectangle and text all end up in the PNG', (tester) async {
    final (:result, :size) = await open(tester);

    // The pen is the first tool: a stroke across the top.
    await drag(tester, const [
      Offset(0.1, 0.1),
      Offset(0.3, 0.1),
      Offset(0.5, 0.1),
    ]);

    await tester.tap(key('annotator-tool-rectangle'));
    await tester.pumpAndSettle();
    await drag(tester, const [
      Offset(0.2, 0.4),
      Offset(0.5, 0.5),
      Offset(0.8, 0.6),
    ]);

    await tester.tap(key('annotator-tool-text'));
    await tester.pumpAndSettle();
    await tester.tapAt(at(tester, const Offset(0.1, 0.8)));
    await tester.pumpAndSettle();
    await tester.enterText(key('annotator-text'), 'Hier hakt es');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Hier hakt es'), findsOneWidget);

    final png = await done(tester, result);
    expect(png, isNotNull);
    final (:width, :height, :pixels) = await decode(tester, png!);
    final scale = width / size.width;
    expect(height / size.height, closeTo(scale, 0.01));
    expect(scale, 1.5, reason: 'a phone at 1.5x');
    Offset px(double x, double y) =>
        Offset(x * size.width * scale, y * size.height * scale);
    expect(isTomato(pixels, width, px(0.3, 0.1)), isTrue, reason: 'pen');
    expect(isTomato(pixels, width, px(0.5, 0.4)), isTrue, reason: 'frame');
    expect(
      isTomato(pixels, width, px(0.5, 0.5)),
      isFalse,
      reason: "the frame's inside stays clear",
    );
    var text = false;
    for (var x = 0.1; x < 0.5 && !text; x += 0.004) {
      for (var y = 0.8; y < 0.83 && !text; y += 0.002) {
        text = isTomato(pixels, width, px(x, y));
      }
    }
    expect(text, isTrue, reason: 'the words');
    expect(
      isTomato(pixels, width, px(0.9, 0.3)),
      isFalse,
      reason: 'unmarked stays as it was',
    );
  });

  testWidgets('the field being typed in is a focused text field for screen '
      'readers and the web, where the user tapped, as large as its mark', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (:result, size: _) = await open(tester);
    await tester.tap(key('annotator-tool-text'));
    await tester.pumpAndSettle();
    final tapped = at(tester, const Offset(0.2, 0.3));
    await tester.tapAt(tapped);
    await tester.pumpAndSettle();
    // The web build types through this node; inside excluded semantics
    // there is none and typing does nothing (review 0, must-fix 2).
    final node = tester.getSemantics(
      find.descendant(
        of: key('annotator-text'),
        matching: find.byType(EditableText),
      ),
    );
    expect(node.flagsCollection.isTextField, isTrue);
    expect(node.flagsCollection.isFocused, Tristate.isTrue);
    final field = tester.getRect(key('annotator-text'));
    expect(field.topLeft.dx, closeTo(tapped.dx, 1));
    expect(field.topLeft.dy, closeTo(tapped.dy, 1));

    await tester.enterText(key('annotator-text'), 'Hier');
    final typing = tester.getRect(find.text('Hier'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Hier')).height,
      closeTo(typing.height, 1),
      reason: 'typed and committed text show at one scale',
    );
    expect(await done(tester, result), isNotNull);
    semantics.dispose();
  });

  testWidgets('a pen stroke stays in the PNG whatever the user taps before '
      'Fertig', (tester) async {
    // Every control the user can reach but Fertig and the ones that take
    // marks back or close: undo, clear (a bin) and ✕.
    Finder controls() => find
        .descendant(
          of: find.byType(Annotator),
          matching: find.byWidgetPredicate(
            (w) => switch (w) {
              Text(:final data) => data != 'Fertig',
              IconButton(icon: Icon(:final icon)) => ![
                Icons.undo,
                Icons.delete,
                Icons.delete_outline,
                Icons.close,
              ].contains(icon),
              _ => false,
            },
          ),
        )
        .hitTestable();

    var tried = 0;
    for (var i = 0; ; i++) {
      final (:result, :size) = await open(tester);
      final count = controls().evaluate().length;
      if (i >= count) {
        await done(tester, result);
        break;
      }
      await drag(tester, const [
        Offset(0.1, 0.1),
        Offset(0.3, 0.1),
        Offset(0.5, 0.1),
      ]);
      final control = controls().at(i);
      final what = control.evaluate().single.widget;
      await tester.tap(control);
      await tester.pumpAndSettle();
      final png = await done(tester, result);
      final (:width, height: _, :pixels) = await decode(tester, png!);
      final scale = width / size.width;
      expect(
        isTomato(
          pixels,
          width,
          Offset(0.3 * size.width * scale, 0.1 * size.height * scale),
        ),
        isTrue,
        reason: 'the pen stroke after tapping control $i ($what)',
      );
      tried++;
    }
    expect(tried, greaterThanOrEqualTo(3), reason: 'the tools were tapped');
  });

  testWidgets('undo takes the last rectangle back', (tester) async {
    final (:result, :size) = await open(tester);
    await tester.tap(key('annotator-tool-rectangle'));
    await tester.pumpAndSettle();
    await drag(tester, const [Offset(0.2, 0.2), Offset(0.6, 0.4)]);
    await tester.tap(key('annotator-undo'));
    await tester.pumpAndSettle();
    final png = await done(tester, result);
    final (:width, :height, :pixels) = await decode(tester, png!);
    final scale = width / size.width;
    expect(
      isTomato(
        pixels,
        width,
        Offset(0.4 * size.width * scale, 0.2 * size.height * scale),
      ),
      isFalse,
    );
  });

  testWidgets('✕ gives no picture', (tester) async {
    final (:result, size: _) = await open(tester, brightness: Brightness.dark);
    await tester.tap(key('annotator-close'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(key('annotator-canvas'), findsNothing);
  });

  testWidgets('back closes like ✕, with no picture', (tester) async {
    final (:result, size: _) = await open(tester);
    await drag(tester, const [Offset(0.1, 0.1), Offset(0.5, 0.1)]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(key('annotator-canvas'), findsNothing);
  });

  testWidgets('✕, undo and Fertig are 48 px targets, and at 160 % text the '
      'tools keep one label size', (tester) async {
    // Label widths need the app's own fonts, not the test font's boxes.
    await tester.runAsync(loadAppFonts);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    for (final k in ['annotator-close', 'annotator-undo', 'annotator-done']) {
      final size = tester.getSize(key(k));
      expect(size.width, greaterThanOrEqualTo(48), reason: k);
      expect(size.height, greaterThanOrEqualTo(48), reason: k);
    }
    final labels = [
      for (final word in ['Stift', 'Rechteck', 'Text'])
        tester.getRect(find.text(word)).height,
    ];
    expect(labels.toSet(), hasLength(1), reason: 'no label shrinks: $labels');
  }, variant: TargetPlatformVariant.all());

  testWidgets('one set of tools, every word from the ARB, in English too', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, locale: const Locale('en'));
    for (final word in ['Pen', 'Rectangle', 'Text', 'Done']) {
      expect(find.text(word).hitTestable(), findsOneWidget, reason: word);
      expect(find.bySemanticsLabel(word), findsOneWidget, reason: word);
    }
    // BetterFeedback's own column (its pen modes, undo, bin, colour) is
    // neither in reach nor read out.
    for (final word in ['View', 'Navigate', 'Draw', 'Navigieren', 'Malen']) {
      expect(find.text(word).hitTestable(), findsNothing, reason: word);
      expect(find.bySemanticsLabel(word), findsNothing, reason: word);
    }
    for (final icon in [Icons.undo, Icons.close]) {
      expect(find.byIcon(icon).hitTestable(), findsOneWidget, reason: '$icon');
    }
    expect(find.byIcon(Icons.delete).hitTestable(), findsNothing);
    semantics.dispose();
  });
}
