import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Types the keys that reach a web text field before its DOM input does.
///
/// With semantics on, a tap focuses a field's `<input>` at once, but the
/// engine hands that input to the app only with the next frame's semantics
/// update, and then writes the app's text over it (`semantics/text_field.dart`,
/// `update()` -> `activate`). A key typed in between was lost: "rot" for
/// "Brot" (DECISIONS, Job 34). Flutter's own key events do arrive in that
/// gap, so from a field's focus to the end of the next frame this types them
/// into the field. Afterwards the input delivers them, as always.
class EarlyKeys() {
  this {
    FocusManager.instance.addListener(_focusChanged);
    HardwareKeyboard.instance.addHandler(_key);
  }

  FocusNode? _focused;

  /// The field that just gained focus, until the end of the next frame.
  EditableTextState? _field;

  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    HardwareKeyboard.instance.removeHandler(_key);
  }

  void _focusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node == _focused) {
      return;
    }
    _focused = node;
    final field = node?.context?.findAncestorStateOfType<EditableTextState>();
    if (field == null ||
        field.widget.focusNode != node ||
        field.widget.readOnly) {
      _field = null;
      return;
    }
    _field = field;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_field == field) {
        _field = null;
      }
    });
  }

  bool _key(KeyEvent event) {
    final field = _field;
    final character = event.character;
    final keyboard = HardwareKeyboard.instance;
    if (field == null ||
        !field.mounted ||
        event is! KeyDownEvent ||
        character == null ||
        character.runes.any((c) => c < 0x20 || c == 0x7f) ||
        // AltGr (Ctrl+Alt on Windows) types @ and € on a German keyboard.
        (keyboard.isControlPressed && !keyboard.isAltPressed) ||
        keyboard.isMetaPressed) {
      return false;
    }
    final value = field.textEditingValue;
    final at = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    field.userUpdateTextEditingValue(
      value.replaced(at, character),
      SelectionChangedCause.keyboard,
    );
    return true;
  }
}
