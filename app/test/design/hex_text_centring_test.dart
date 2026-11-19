import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/hex_pill.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fonts.dart';

/// Text in a hex sits in its middle (Peter, job 148): the ink of a line of
/// capitals is as far from the face's top as from its bottom, in a field
/// (typed text and hint), a pill row and a button.
void main() {
  setUpAll(loadAppFonts);
  const scale = 3.0;
  final boundary = GlobalKey();

  /// Where the ink of [text]'s glyphs starts and ends, in logical pixels,
  /// inside [face]: dark pixels in the columns of [text], rows clear of the
  /// face's contour.
  Future<(double, double)> inkRows(
    WidgetTester tester,
    Rect face,
    Rect text,
  ) async {
    final image = (await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: scale);
      final bytes = await image.toByteData();
      return (image.width, bytes!);
    }))!;
    final (width, bytes) = image;
    final origin = tester.getTopLeft(find.byKey(boundary));
    int px(double v, double o) => ((v - o) * scale).round();
    const inset = HlBorder.width + 2;
    final (top, bottom) = (
      px(face.top + inset, origin.dy),
      px(face.bottom - inset, origin.dy),
    );
    int? first;
    int? last;
    for (var y = top; y < bottom; y++) {
      for (
        var x = px(text.left, origin.dx);
        x < px(text.right, origin.dx);
        x++
      ) {
        final i = (y * width + x) * 4;
        final luminance =
            (bytes.getUint8(i) +
                bytes.getUint8(i + 1) +
                bytes.getUint8(i + 2)) /
            3;
        if (luminance < 160) {
          first ??= y;
          last = y;
          break;
        }
      }
    }
    expect(first, isNotNull, reason: 'no ink in $face');
    return (origin.dy + first! / scale, origin.dy + (last! + 1) / scale);
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(width: 300, child: child),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void centred(Rect face, (double, double) ink, String what) {
    final (above, below) = (ink.$1 - face.top, face.bottom - ink.$2);
    expect(
      (above - below).abs(),
      // Bricolage's capitals sit 0.67 px above the middle of their line at
      // 17 px; before job 148 the edit sheet's text sat 2.3 px low and the
      // store search's 4 px.
      lessThanOrEqualTo(1.5),
      reason:
          '$what: ${above.toStringAsFixed(2)} px above the ink, '
          '${below.toStringAsFixed(2)} below',
    );
  }

  Future<void> field(
    WidgetTester tester,
    String what, {
    String text = 'HOME',
    String? hint,
    double fontSize = 16,
    Widget? prefixIcon,
    bool tight = false,
    TextAlignVertical? align,
  }) async {
    await pump(
      tester,
      TextField(
        controller: TextEditingController(text: text),
        style: TextStyle(fontSize: fontSize),
        textAlignVertical: align,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefixIcon,
          constraints: tight
              ? const BoxConstraints.tightFor(height: HlSize.target)
              : null,
        ),
      ),
    );
    final face = tester.getRect(find.byType(InputDecorator));
    final glyphs = tester.getRect(
      text.isEmpty ? find.text(hint!) : find.byType(EditableText),
    );
    final ink = await inkRows(tester, face, glyphs);
    centred(face, ink, what);
  }

  testWidgets('in a hex field', (tester) => field(tester, 'field'));

  testWidgets("in the edit sheet's 48 dp fields, typed and hinted", (
    tester,
  ) async {
    for (final align in [null, TextAlignVertical.center]) {
      await field(
        tester,
        'typed $align',
        fontSize: 18,
        tight: true,
        align: align,
      );
      await field(
        tester,
        'hint $align',
        text: '',
        hint: 'HOME',
        fontSize: 18,
        tight: true,
        align: align,
      );
    }
  });

  testWidgets('in a field with a leading icon', (tester) async {
    await field(
      tester,
      'search',
      prefixIcon: const Icon(Icons.search, size: 20),
      tight: true,
    );
  });

  testWidgets('in a pill row', (tester) async {
    await pump(
      tester,
      // In a row, as the screens set it: on its own the title would span the
      // pill, contour included.
      const HexPill(child: Row(children: [PillTitle('HOME')])),
    );
    final face = tester.getRect(find.byType(InkWell));
    final ink = await inkRows(tester, face, tester.getRect(find.text('HOME')));
    centred(face, ink, 'pill');
  });

  testWidgets('in a button', (tester) async {
    await pump(
      tester,
      Center(
        child: FilledButton(onPressed: () {}, child: const Text('HOME')),
      ),
    );
    final button = tester.getRect(find.byType(FilledButton));
    // The face rests on its edge: it is the button less the edge.
    final face = Rect.fromLTRB(
      button.left,
      button.top,
      button.right,
      button.bottom - (raisedFaces ? HlDepth.edge : 0),
    );
    final ink = await inkRows(tester, face, tester.getRect(find.text('HOME')));
    centred(face, ink, 'button');
  });

  test('a hex field is an outline, a rounded one is not', () {
    expect(const ContourInputBorder().isOutline, isTrue);
    expect(
      const ContourInputBorder(shape: FieldShape.rounded).isOutline,
      isFalse,
    );
  });
}
