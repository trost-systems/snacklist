import 'package:family_groceries/core/early_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late TextEditingController input;
  late FocusNode focus;
  late List<String> changes;

  setUp(() {
    input = TextEditingController();
    focus = FocusNode();
    changes = [];
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
  });

  Future<void> field(WidgetTester tester, {int? maxLength}) async {
    addTearDown(EarlyKeys().dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: input,
            focusNode: focus,
            maxLength: maxLength,
            onChanged: changes.add,
          ),
        ),
      ),
    );
  }

  Future<void> focusWithoutFrame(WidgetTester tester) async {
    focus.requestFocus();
    await tester.idle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, String c) =>
      tester.sendKeyEvent(key, character: c);

  testWidgets('a key between focus and the next frame is typed', (
    tester,
  ) async {
    await field(tester);
    await focusWithoutFrame(tester);
    await press(tester, LogicalKeyboardKey.keyB, 'B');
    await press(tester, LogicalKeyboardKey.keyR, 'r');
    expect(input.text, 'Br');
    expect(changes, ['B', 'Br']);
  });

  testWidgets('after the frame the keys are left to the text input', (
    tester,
  ) async {
    await field(tester);
    focus.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyB, 'B');
    expect(input.text, isEmpty);
    expect(changes, isEmpty);
  });

  testWidgets('a key is typed again after the next focus', (tester) async {
    await field(tester);
    focus.requestFocus();
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    await focusWithoutFrame(tester);
    await press(tester, LogicalKeyboardKey.keyB, 'B');
    expect(input.text, 'B');
  });

  testWidgets('the field formatters apply', (tester) async {
    await field(tester, maxLength: 1);
    await focusWithoutFrame(tester);
    await press(tester, LogicalKeyboardKey.keyB, 'B');
    await press(tester, LogicalKeyboardKey.keyR, 'r');
    expect(input.text, 'B');
  });

  testWidgets('shortcuts and control keys are not typed', (tester) async {
    await field(tester);
    await focusWithoutFrame(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await press(tester, LogicalKeyboardKey.keyA, 'a');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await press(tester, LogicalKeyboardKey.backspace, '\b');
    expect(input.text, isEmpty);
  });

  testWidgets('AltGr types its character', (tester) async {
    await field(tester);
    await focusWithoutFrame(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
    await press(tester, LogicalKeyboardKey.keyQ, '@');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(input.text, '@');
  });
}
