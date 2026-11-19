import 'dart:ui' show CheckedState, Tristate;

import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/hex_switch.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/rendering.dart' show SemanticsData;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// One theme for every pump: a new one would animate the theme change.
final _theme = appTheme(Brightness.light);

Widget _app(Widget child, {bool reducedMotion = false}) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// A switch tile that keeps its own value, as a screen would.
class const _Toggle({final bool enabled = true}) extends StatefulWidget {
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState() extends State<_Toggle> {
  var _on = false;

  @override
  Widget build(BuildContext context) => HexSwitchTile(
    key: const ValueKey('tile'),
    title: const Text('Dunkel'),
    value: _on,
    onChanged: widget.enabled ? (on) => setState(() => _on = on) : null,
  );
}

void main() {
  final tile = find.byKey(const ValueKey('tile'));

  SemanticsData semantics(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  group('HexSwitchTile', () {
    testWidgets('is one labelled switch; a tap anywhere flips it', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _Toggle()));
      var data = semantics(tester, tile);
      expect(data.label, 'Dunkel');
      expect(data.flagsCollection.isToggled, Tristate.isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);

      await tester.tap(find.text('Dunkel'));
      await tester.pumpAndSettle();
      data = semantics(tester, tile);
      expect(data.flagsCollection.isToggled, Tristate.isTrue);

      await tester.tap(find.byType(HexSwitch));
      await tester.pumpAndSettle();
      expect(
        semantics(tester, tile).flagsCollection.isToggled,
        Tristate.isFalse,
        reason: 'the switch itself flips it too',
      );
    });

    testWidgets('disabled, it shows its value and ignores taps', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _Toggle(enabled: false)));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final data = semantics(tester, tile);
      expect(data.flagsCollection.isToggled, Tristate.isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    });

    testWidgets('the row and the switch are at least 48 dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _Toggle()));
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(HlSize.target));
      expect(
        tester.getSize(find.byType(HexSwitch)).height,
        greaterThanOrEqualTo(HlSize.target),
      );
    });
  });

  group('HexSwitch', () {
    testWidgets('space flips a focused switch', (tester) async {
      var on = false;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => HexSwitch(
              value: on,
              autofocus: true,
              onChanged: (value) => setState(() => on = value),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(on, isTrue);
    });

    testWidgets('the thumb travels; with reduced motion it jumps', (
      tester,
    ) async {
      Widget at({required bool on, required bool reduced}) => _app(
        HexSwitch(value: on, onChanged: (_) {}),
        reducedMotion: reduced,
      );
      await tester.pumpWidget(at(on: false, reduced: false));
      await tester.pumpWidget(at(on: true, reduced: false));
      await tester.pump(HlDuration.medium ~/ 2);
      expect(tester.hasRunningAnimations, isTrue, reason: 'mid-travel');
      await tester.pump(HlDuration.medium);
      expect(tester.hasRunningAnimations, isFalse, reason: 'settled in time');

      await tester.pumpWidget(at(on: true, reduced: true));
      await tester.pumpWidget(at(on: false, reduced: true));
      expect(tester.hasRunningAnimations, isFalse, reason: 'one frame');
    });
  });

  group('HexRadioTile', () {
    testWidgets('is a radio of its group; a tap on the row picks it', (
      tester,
    ) async {
      String? picked = 'de';
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => RadioGroup<String?>(
              groupValue: picked,
              onChanged: (value) => setState(() => picked = value),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HexRadioTile<String?>(
                    key: ValueKey('de'),
                    value: 'de',
                    title: Text('Deutsch'),
                  ),
                  HexRadioTile<String?>(
                    key: ValueKey('en'),
                    value: 'en',
                    title: Text('English'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      SemanticsData row(String k) => semantics(tester, find.byKey(ValueKey(k)));
      expect(row('en').label, 'English');
      expect(row('en').flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(row('de').flagsCollection.isChecked, CheckedState.isTrue);
      expect(row('en').flagsCollection.isChecked, CheckedState.isFalse);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(picked, 'en');
      expect(row('en').flagsCollection.isChecked, CheckedState.isTrue);
      expect(row('de').flagsCollection.isChecked, CheckedState.isFalse);
      expect(
        tester.getSize(find.byKey(const ValueKey('en'))).height,
        greaterThanOrEqualTo(HlSize.target),
      );
    });
  });

  group('HexSegmented', () {
    Widget segmented({
      required int value,
      required ValueChanged<int>? onChanged,
      bool reduced = false,
    }) => _app(
      HexSegmented<int>(
        label: 'Darstellung',
        value: value,
        onChanged: onChanged,
        segments: const [
          HexSegment(value: 0, label: 'System', key: ValueKey('s0')),
          HexSegment(value: 1, label: 'Hell', key: ValueKey('s1')),
          HexSegment(value: 2, label: 'Dunkel', key: ValueKey('s2')),
        ],
      ),
      reducedMotion: reduced,
    );

    final indicator = find.byType(FractionallySizedBox);

    testWidgets('shows all options; a tap picks; the picked one is checked', (
      tester,
    ) async {
      var value = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => segmented(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      for (final (i, label) in ['System', 'Hell', 'Dunkel'].indexed) {
        final data = semantics(tester, find.byKey(ValueKey('s$i')));
        expect(data.label, label);
        expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(
          data.flagsCollection.isChecked,
          i == 0 ? CheckedState.isTrue : CheckedState.isFalse,
        );
        expect(tester.getSize(find.byKey(ValueKey('s$i'))).height, 48);
      }
      await tester.tap(find.text('Dunkel'));
      await tester.pumpAndSettle();
      expect(value, 2);
      expect(
        semantics(
          tester,
          find.byKey(const ValueKey('s2')),
        ).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      expect(
        semantics(
          tester,
          find.byKey(const ValueKey('s0')),
        ).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
    });

    testWidgets('the arrow keys move the pick from the focused segment', (
      tester,
    ) async {
      var value = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => segmented(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(value, 1);
    });

    testWidgets('without onChanged nothing picks', (tester) async {
      await tester.pumpWidget(segmented(value: 1, onChanged: null));
      await tester.tap(find.text('Dunkel'));
      await tester.pumpAndSettle();
      final data = semantics(tester, find.byKey(const ValueKey('s1')));
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    });

    testWidgets('the indicator slides; with reduced motion it jumps', (
      tester,
    ) async {
      Widget at({required int value, required bool reduced}) =>
          segmented(value: value, onChanged: (_) {}, reduced: reduced);
      await tester.pumpWidget(at(value: 0, reduced: false));
      final from = tester.getTopLeft(indicator).dx;
      await tester.pumpWidget(at(value: 2, reduced: false));
      await tester.pump(HlDuration.medium ~/ 2);
      final mid = tester.getTopLeft(indicator).dx;
      expect(mid, greaterThan(from));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(indicator).dx, greaterThan(mid));

      await tester.pumpWidget(at(value: 2, reduced: true));
      final end = tester.getTopLeft(indicator).dx;
      await tester.pumpWidget(at(value: 0, reduced: true));
      await tester.pump();
      expect(tester.getTopLeft(indicator).dx, from);
      expect(end, greaterThan(from));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
