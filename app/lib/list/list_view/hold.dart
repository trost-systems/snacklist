import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A press on [child] held for [holdDelay] calls [onHold] at once, while
/// still held. A finger may drift by the touch slop and still hold; past it
/// the press scrolls instead. Screen readers get a row's hold from the
/// row's own semantics node; a store divider's hold does nothing.
class const Hold({
  required final VoidCallback onHold,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// How long a press is held (prototype: 300 ms). On web the engine holds
  /// a press on a tappable semantics node, as a row or a store divider is,
  /// back for 200 ms before the app sees it (its click debouncer,
  /// `pointer_binding.dart`), so it waits 100 ms more: 300 ms for the user.
  static const holdDelay = Duration(milliseconds: kIsWeb ? 100 : 300);

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    excludeFromSemantics: true,
    gestures: {
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: holdDelay,
              debugOwner: this,
            ),
            (recognizer) => recognizer.onLongPress = onHold,
          ),
    },
    child: child,
  );
}
