import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tells [onWidth] its child's width after each layout that changed it,
/// after the frame: listeners may rebuild then.
class const MeasuredWidth({
  required final ValueChanged<double>? onWidth,
  super.child,
  super.key,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredWidth(onWidth);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    if (renderObject is _RenderMeasuredWidth) {
      renderObject.onWidth = onWidth;
    }
  }
}

class _RenderMeasuredWidth(var ValueChanged<double>? onWidth)
    extends RenderProxyBox {
  double? _told;

  @override
  void performLayout() {
    super.performLayout();
    final width = size.width;
    if (width != _told) {
      _told = width;
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => onWidth?.call(width),
      );
    }
  }
}
