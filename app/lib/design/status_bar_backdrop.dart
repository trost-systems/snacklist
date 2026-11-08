import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter/material.dart';

/// Lays [child] out as usual and, once a vertical scroll view in it has
/// scrolled, covers the top safe area over it with the page's surface,
/// ending in a fade: content scrolled up fades out before the clock and
/// battery instead of being cut by a hard line. Unscrolled, and where there
/// is no top inset (desktop, web), nothing is drawn. Takes no taps.
class const StatusBarBackdrop({
  required final Widget child,

  /// The fade below the inset.
  final double fade = HlSpace.s6,
  super.key,
}) extends StatefulWidget {
  @override
  State<StatusBarBackdrop> createState() => _StatusBarBackdropState();
}

class _StatusBarBackdropState() extends State<StatusBarBackdrop> {
  /// How far the content has scrolled, up to [StatusBarBackdrop.fade]: the
  /// backdrop grows in with the content that runs under it.
  var _scrolled = 0.0;

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.vertical) {
      final scrolled = metrics.pixels.clamp(0.0, widget.fade);
      if (scrolled != _scrolled) {
        setState(() => _scrolled = scrolled);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final fade = widget.fade;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final strength = _scrolled / fade;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          // Only the overlay comes and goes with the inset: the child keeps
          // its place in the tree, so turning the phone keeps its state.
          if (top > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top + fade,
              child: IgnorePointer(
                child: strength == 0
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              for (final alpha in const [1.0, 1.0, 0.85, 0.0])
                                surface.withValues(alpha: alpha * strength),
                            ],
                            stops: [
                              0,
                              top / (top + fade),
                              (top + fade / 2) / (top + fade),
                              1,
                            ],
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
