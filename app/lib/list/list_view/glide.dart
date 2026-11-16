import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where the list's rows were painted before a change of layout, and the
/// motion that takes them from there to where the new layout puts them
/// (job 276: the list behind the add sheet and back). Each [Glide] paints
/// its child between the two, by [progress]; one that was not painted
/// before fades in. Only paint moves: no row is laid out again per frame.
class Glides() {
  final _live = <Object, RenderGlide>{};
  var _from = const <Object, Offset>{};

  /// 0 when the change starts, 1 at rest.
  Animation<double> progress = kAlwaysCompleteAnimation;

  /// Notes where every glide is painted now, also halfway through a
  /// motion, as the start of the next one: call it before the change of
  /// layout.
  void snapshot() {
    _from = {
      for (final MapEntry(:key, :value) in _live.entries)
        if (value.attached && value.hasSize)
          key: value.localToGlobal(value.paintShift),
    };
  }
}

/// Makes [glides] reachable for the [Glide]s below.
class const GlideScope({
  required final Glides glides,
  required super.child,
  super.key,
}) extends InheritedWidget {
  static Glides? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlideScope>()?.glides;

  @override
  bool updateShouldNotify(GlideScope oldWidget) => glides != oldWidget.glides;
}

/// A row, or a heading, that glides from where [id] was painted before the
/// change of layout to its place in the new one. Without a [GlideScope]
/// above it paints as its child.
class const Glide({required final Object id, required super.child, super.key})
    extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderGlide(id, GlideScope._of(context));

  @override
  void updateRenderObject(BuildContext context, RenderGlide renderObject) =>
      renderObject.update(id, GlideScope._of(context));
}

/// [Glide]'s render object.
class RenderGlide(Object id, Glides? glides) extends RenderProxyBox {
  var _id = id;
  var _glides = glides;
  Animation<double>? _listening;

  void update(Object id, Glides? glides) {
    if (id != _id || glides != _glides) {
      _unregister();
      _id = id;
      _glides = glides;
      _register();
    }
  }

  void _register() {
    if (!attached) {
      return;
    }
    if (_glides case final glides?) {
      glides._live[_id] = this;
      _listen(glides.progress);
    }
  }

  void _unregister() {
    if (_glides case final glides? when glides._live[_id] == this) {
      glides._live.remove(_id);
    }
    _listen(null);
  }

  void _listen(Animation<double>? progress) {
    if (progress != _listening) {
      _listening?.removeListener(_tick);
      _listening = progress?..addListener(_tick);
    }
  }

  /// Fading in: not painted before the change, and moving.
  bool get _fading => switch (_glides) {
    final glides? =>
      glides.progress.value < 1 && !glides._from.containsKey(_id),
    null => false,
  };

  var _wasFading = false;

  void _tick() {
    if (_fading != _wasFading) {
      _wasFading = _fading;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  // The fade's layer must sit under the viewport's clip layer.
  @override
  bool get alwaysNeedsCompositing => child != null && _fading;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _register();
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }

  /// How far from its layout position it paints now: between where it was
  /// painted before the change and where the layout puts it, so a scroll
  /// during the motion moves the end, never the start.
  Offset get paintShift {
    final glides = _glides;
    final from = glides?._from[_id];
    if (glides == null || from == null || glides.progress.value >= 1) {
      return Offset.zero;
    }
    return (from - localToGlobal(Offset.zero)) * (1 - glides.progress.value);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (_glides case final glides? when _fading) {
      context.pushOpacity(
        offset,
        (255 * glides.progress.value).round(),
        (context, offset) => context.paintChild(child, offset),
      );
      return;
    }
    context.paintChild(child, offset + paintShift);
  }
}
