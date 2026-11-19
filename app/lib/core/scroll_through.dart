import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A band floating over a page, such as the add bar or the tab pill: a mouse
/// wheel or trackpad scroll over it goes to what lies under it in [under],
/// as if the band were not there. Taps stay the band's.
///
/// The band and the page are siblings (a Scaffold's bottom bar and body), so
/// hit testing stops at the band and a scroll over it would reach no
/// Scrollable. The event goes through the pointer-signal resolver as usual:
/// a scrollable inside the band that claims it first keeps it.
class const ScrollThrough({
  required final GlobalKey under,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Listener(onPointerSignal: _forward, child: child);

  void _forward(PointerSignalEvent event) {
    final page = under.currentContext?.findRenderObject();
    if (event is! PointerScrollEvent || page is! RenderBox || !page.attached) {
      return;
    }
    final result = BoxHitTestResult()
      ..addWithPaintTransform(
        transform: page.getTransformTo(null),
        position: event.position,
        hitTest: (result, position) => page.hitTest(result, position: position),
      );
    for (final entry in result.path) {
      entry.target.handleEvent(event.transformed(entry.transform), entry);
    }
  }
}
