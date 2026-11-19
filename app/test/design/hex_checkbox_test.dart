import 'dart:ui' show CheckedState;

import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _theme = appTheme(Brightness.light);

/// A tile that keeps its own value, as a screen would.
class const _Opt({final bool enabled = true}) extends StatefulWidget {
  @override
  State<_Opt> createState() => _OptState();
}

class _OptState() extends State<_Opt> {
  var _on = false;

  @override
  Widget build(BuildContext context) => HexCheckboxListTile(
    key: const ValueKey('tile'),
    title: const Text('Kontakt'),
    value: _on,
    onChanged: widget.enabled ? (on) => setState(() => _on = on) : null,
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: _theme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final tile = find.byKey(const ValueKey('tile'));

  testWidgets('is one labelled check box; a tap on the row or box flips it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Opt()));
    var data = tester.getSemantics(tile).getSemanticsData();
    expect(data.label, 'Kontakt');
    expect(data.flagsCollection.isChecked, CheckedState.isFalse);

    await tester.tap(find.text('Kontakt'));
    await tester.pumpAndSettle();
    data = tester.getSemantics(tile).getSemanticsData();
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);

    await tester.tap(find.byType(HexCheckbox));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(tile).getSemanticsData().flagsCollection.isChecked,
      CheckedState.isFalse,
    );
  });

  testWidgets('disabled, it ignores taps', (tester) async {
    await tester.pumpWidget(_app(const _Opt(enabled: false)));
    await tester.tap(find.byType(HexCheckbox));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(tile).getSemanticsData().flagsCollection.isChecked,
      CheckedState.isFalse,
    );
  });

  testWidgets('the box is a 48 dp target', (tester) async {
    await tester.pumpWidget(_app(HexCheckbox(value: true, onChanged: (_) {})));
    expect(tester.getSize(find.byType(HexCheckbox)).shortestSide, 48);
  });
}
