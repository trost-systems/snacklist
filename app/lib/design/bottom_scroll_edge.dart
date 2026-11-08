import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Lays [child] out as usual and, while a vertical scroll view in it has
/// content below the fold, fades the page's surface in over the bottom
/// padding (the floating controls there) and [fade] above it: rows running
/// on under the add field and the tab pill fade out instead of showing
/// half-hidden between them. Where the content ends above the padding,
/// nothing is drawn. Takes no taps.
class const BottomScrollEdge({
  required final Widget child,

  /// The fade above the bottom padding.
  final double fade = HlSpace.s4,
  super.key,
}) extends StatefulWidget {
  @override
  State<BottomScrollEdge> createState() => _BottomScrollEdgeState();
}

class _BottomScrollEdgeState() extends State<BottomScrollEdge> {
  /// How much content lies below the fold, up to [_ramp]: the edge grows in
  /// with the content that runs under it. Scroll metrics change during
  /// layout, so this only repaints the edge.
  final _below = ValueNotifier<double>(0);

  static const _ramp = HlSpace.s5;

  @override
  void dispose() {
    _below.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    if (depth == 0 && metrics.axis == Axis.vertical) {
      _below.value = metrics.extentAfter.clamp(0.0, _ramp);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final fade = widget.fade;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.depth),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (bottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottom + fade,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Edge(
                      below: _below,
                      surface: Theme.of(context).scaffoldBackgroundColor,
                      fade: fade,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The surface, transparent at the top, nearly opaque from [fade] down.
class _Edge({
  required final ValueListenable<double> below,
  required final Color surface,
  required final double fade,
}) extends CustomPainter {
  this : super(repaint: below);

  @override
  void paint(Canvas canvas, Size size) {
    final strength = below.value / _BottomScrollEdgeState._ramp;
    if (strength == 0) {
      return;
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (final alpha in const [0.0, 0.7, 0.97, 0.97])
              surface.withValues(alpha: alpha * strength),
          ],
          stops: [0, fade / 2 / size.height, fade / size.height, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Edge oldDelegate) =>
      oldDelegate.below != below ||
      oldDelegate.surface != surface ||
      oldDelegate.fade != fade;
}
