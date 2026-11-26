import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/pop_if_current.dart';
import 'package:family_groceries/design/hex_segmented.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/screen_capture.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the annotator on [image], the frozen screen: the user paints on it
/// with a pen, rectangles and text, and covers what nobody should see
/// (job 267, job 290). BetterFeedback shows it scaled
/// down and takes the PNG; the marks are our own layer on it. The PNG of
/// what they marked, or null when they closed it. For a report (job 281)
/// [forReport] starts with the cover tool, first among the tools, under the
/// report's hint.
Future<Uint8List?> annotateScreenshot(
  BuildContext context,
  ui.Image image, {
  bool forReport = false,
}) =>
    // A popup route: the shake stays quiet while it shows (`Popups`).
    showGeneralDialog<Uint8List>(
      context: context,
      pageBuilder: (_, _, _) => Annotator(image: image, forReport: forReport),
    );

/// What the user can do on the screenshot.
enum AnnotateTool() {
  /// Free drawing.
  pen,

  /// A frame dragged open.
  rectangle,

  /// A line of text where the user tapped.
  text,

  /// A filled, opaque box dragged open over what nobody should see.
  cover,
}

/// A mark on the screenshot, in its own coordinates. Undo takes the last
/// one back, whatever its tool.
sealed class const _Mark();

final class const _Stroke(final List<Offset> points) extends _Mark;

final class const _Frame(final Rect rect) extends _Mark;

/// Painted into the PNG's pixels, so the upload holds none of what lies
/// under it (Legal condition C1, N-267).
final class const _Cover(final Rect rect) extends _Mark;

final class const _Words(final Offset at, final String text) extends _Mark;

/// The annotator page: [image] scaled down under the marks, the tools and
/// Fertig below.
///
/// BetterFeedback's own pen comes with a tool column whose "navigate" mode
/// drops the pen strokes from view and from the PNG, a second undo for the
/// strokes only and a bin; none of it can be switched off. So the pen is
/// ours too, BetterFeedback stays in navigate mode (no painter of its own),
/// and its column is covered: one set of tools, one undo, and the PNG holds
/// exactly the marks shown.
class const Annotator({
  required final ui.Image image,

  /// Starts with [AnnotateTool.cover], first among the tools.
  final bool forReport = false,
  super.key,
}) extends StatefulWidget {
  @override
  State<Annotator> createState() => _AnnotatorState();
}

class _AnnotatorState() extends State<Annotator> {
  late var _tool = widget.forReport ? AnnotateTool.cover : AnnotateTool.pen;
  final _marks = <_Mark>[];

  /// The stroke being drawn or the frame being dragged open.
  _Mark? _drawing;

  /// Where the drag began: a frame or cover spans from it to the pointer,
  /// whichever way the pointer goes.
  Offset? _anchor;

  /// Where the text being typed goes.
  Offset? _typingAt;
  final _typing = TextEditingController();
  final _typingFocus = FocusNode();

  /// Ties the field being typed in, which lies above BetterFeedback, to
  /// [_typingAt] on the scaled-down canvas.
  final _typingLink = LayerLink();

  Uint8List? _result;
  FeedbackController? _controller;

  /// BetterFeedback's capture: hands the PNG to [_start]'s callback and hides.
  OnSubmit? _submit;
  Timer? _closing;

  /// The tools' height, measured offstage before BetterFeedback is built:
  /// it reads its sheet's share of the screen once, on its first build.
  double? _toolsHeight;

  /// The screenshot with our marks, as BetterFeedback shows it.
  final _canvas = GlobalKey(debugLabel: 'annotator-canvas');

  /// BetterFeedback's show and hide animation, and a frame.
  static const _hideAnimation = Duration(milliseconds: 320);

  /// Our own handle on the screenshot, alive as long as this page: the
  /// caller's may be disposed while the page still paints (ScreenCapture
  /// drops the picture of the screen before More once the router leaves
  /// More).
  late final ui.Image _image;

  @override
  void initState() {
    super.initState();
    _image = widget.image.clone();
  }

  @override
  void dispose() {
    _image.dispose();
    _closing?.cancel();
    _controller?.removeListener(_onController);
    _typing.dispose();
    _typingFocus.dispose();
    super.dispose();
  }

  void _start(FeedbackController controller) {
    if (_controller != null) {
      return;
    }
    _controller = controller..addListener(_onController);
    controller.show((feedback) => _result = feedback.screenshot);
  }

  /// BetterFeedback hid itself: after Fertig with the PNG, after ✕ or back
  /// with none.
  void _onController() {
    if (_controller?.isVisible ?? true) {
      setState(() {});
      return;
    }
    _controller?.removeListener(_onController);
    // BetterFeedback animates its chrome away and disposes its animation
    // only after its ticker: popped mid-way it asserts.
    // Its animation starts on the next frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _closing = Timer(_hideAnimation, () {
        popIfCurrent(context, _result);
      }),
    );
  }

  void _pick(AnnotateTool tool) {
    _commitText();
    setState(() => _tool = tool);
  }

  void _undo() {
    _commitText();
    if (_marks.isNotEmpty) {
      setState(_marks.removeLast);
    }
  }

  void _done() {
    _commitText();
    if (_submit case final submit?) {
      unawaited(submit(''));
    }
  }

  void _close() => _controller?.hide();

  void _drawFrom(Offset at) => setState(() {
    _anchor = at;
    _drawing = switch (_tool) {
      AnnotateTool.pen => _Stroke([at]),
      AnnotateTool.rectangle => _Frame(Rect.fromPoints(at, at)),
      AnnotateTool.cover => _Cover(Rect.fromPoints(at, at)),
      AnnotateTool.text => null,
    };
  });

  void _drawTo(Offset at) => setState(
    () => _drawing = switch ((_drawing, _anchor)) {
      (_Stroke(:final points), _) => _Stroke([...points, at]),
      (_Frame(), final anchor?) => _Frame(Rect.fromPoints(anchor, at)),
      (_Cover(), final anchor?) => _Cover(Rect.fromPoints(anchor, at)),
      (final other, _) => other,
    },
  );

  void _drawEnd() => setState(() {
    switch (_drawing) {
      case final _Stroke stroke:
        _marks.add(stroke);
      case final _Frame frame when frame.rect.shortestSide > 4:
        _marks.add(frame);
      case final _Cover cover when cover.rect.shortestSide > 4:
        _marks.add(cover);
      case _:
    }
    _drawing = null;
    _anchor = null;
  });

  void _typeAt(Offset at) {
    _commitText();
    setState(() => _typingAt = at);
    _typingFocus.requestFocus();
  }

  void _commitText() {
    final at = _typingAt;
    if (at == null) {
      return;
    }
    final text = _typing.text.trim();
    setState(() {
      if (text.isNotEmpty) {
        _marks.add(_Words(at, text));
      }
      _typingAt = null;
      _typing.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final media = MediaQuery.of(context);
    final tools = _Tools(
      tool: _tool,
      forReport: widget.forReport,
      canUndo: _marks.isNotEmpty || _typingAt != null,
      onPick: _pick,
      onUndo: _undo,
      onDone: _done,
      onClose: _close,
    );
    final measured = _toolsHeight;
    if (measured == null) {
      return ColoredBox(
        color: t.surfaceSunken,
        // Loose: the tools' own height, not the screen's.
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Offstage(
            child: _MeasuredHeight(
              onHeight: (height) {
                if (mounted) {
                  setState(() => _toolsHeight = height);
                }
              },
              child: tools,
            ),
          ),
        ),
      );
    }
    final sheetHeight = math.min(
      0.5 * media.size.height,
      measured + media.padding.bottom,
    );
    // A new theme on every build: BetterFeedback's overlay rebuilds (and so
    // shows our new marks) only when its theme changes.
    final feedbackTheme = FeedbackThemeData(
      background: t.surfaceSunken,
      feedbackSheetColor: t.surfaceRaised,
      feedbackSheetHeight: sheetHeight / media.size.height,
      activeFeedbackModeColor: t.brand,
      drawColors: [t.tomato],
      sheetIsDraggable: false,
      brightness: Theme.of(context).brightness,
    );
    final feedback = BetterFeedback(
      theme: feedbackTheme,
      darkTheme: feedbackTheme,
      localeOverride: Localizations.localeOf(context),
      localizationsDelegates: appLocalizationsDelegates,
      pixelRatio: shotPixelRatio(media.size),
      mode: FeedbackMode.navigate,
      // Its sheet only keeps the room for our tools, which lie above it,
      // outside the semantics its covered column is kept out of.
      feedbackBuilder: (_, submit, _) {
        _submit = submit;
        return const SizedBox.shrink();
      },
      child: Builder(
        builder: (context) {
          final controller = BetterFeedback.of(context);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _start(controller),
          );
          return _layer(t);
        },
      ),
    );
    // Back closes like ✕, through BetterFeedback's hide animation.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Framed(
            canvas: _canvas,
            color: t.surfaceSunken,
            sheetHeight: sheetHeight,
            // Its covered column, and the canvas with nothing to read.
            child: ExcludeSemantics(child: feedback),
          ),
          // Outside the excluded subtree: the web types through the field's
          // semantics node.
          if (_typingAt case final at?)
            Positioned(
              left: 0,
              top: 0,
              width: math.max(120, media.size.width - at.dx),
              child: CompositedTransformFollower(
                link: _typingLink,
                showWhenUnlinked: false,
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    key: const ValueKey('annotator-text'),
                    autofillHints: null,
                    controller: _typing,
                    focusNode: _typingFocus,
                    style: _words(t),
                    cursorColor: t.tomato,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _commitText(),
                    // The app's field contour would frame the words.
                    decoration:
                        InputDecoration.collapsed(
                          hintText: l10n.feedbackAnnotateTextHint,
                        ).copyWith(
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: sheetHeight,
            child: tools,
          ),
        ],
      ),
    );
  }

  /// The screenshot, our marks and the gestures that make them; what
  /// BetterFeedback captures. Its scaling applies to the gestures too, so
  /// their positions are the screenshot's own.
  Widget _layer(SnacklistColors t) {
    final words = _words(t);
    return KeyedSubtree(
      key: const ValueKey('annotator-canvas'),
      child: Stack(
        key: _canvas,
        fit: StackFit.expand,
        children: [
          RawImage(image: _image, fit: BoxFit.fill),
          CustomPaint(painter: _Lines([..._marks, ?_drawing], t.tomato, t.ink)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _tool == AnnotateTool.text
                ? null
                : (d) => _drawFrom(d.localPosition),
            onPanUpdate: _tool == AnnotateTool.text
                ? null
                : (d) => _drawTo(d.localPosition),
            onPanEnd: _tool == AnnotateTool.text ? null : (_) => _drawEnd(),
            onTapUp: _tool == AnnotateTool.text
                ? (d) => _typeAt(d.localPosition)
                : null,
          ),
          for (final mark in _marks)
            if (mark case _Words(:final at, :final text))
              Positioned(
                left: at.dx,
                top: at.dy,
                child: Text(text, style: words),
              ),
          // Where the field being typed in shows, scaled down with this.
          if (_typingAt case final at?)
            Positioned(
              left: at.dx,
              top: at.dy,
              child: CompositedTransformTarget(link: _typingLink),
            ),
        ],
      ),
    );
  }
}

/// A text mark's style, in the screenshot's own coordinates.
TextStyle _words(SnacklistColors t) => TextStyle(
  fontFamily: HlFont.sans,
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: t.tomato,
  backgroundColor: t.surface.withValues(alpha: 0.85),
);

/// Shows BetterFeedback with [canvas], the screenshot, centred and its tool
/// column (see [Annotator]) covered with [color], the background, which
/// takes the pointers there. Works from where BetterFeedback lays the
/// canvas out in each frame, so it follows its show and hide animation.
class const _Framed({
  required final GlobalKey canvas,
  required final Color color,
  required final double sheetHeight,
  required super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFramed(canvas, color, sheetHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    if (renderObject is _RenderFramed) {
      renderObject
        ..canvas = canvas
        ..color = color
        ..sheetHeight = sheetHeight
        ..markNeedsPaint();
    }
  }
}

class _RenderFramed(
  var GlobalKey canvas,
  var Color color,
  var double sheetHeight,
) extends RenderProxyBox {
  /// How far right the canvas moves to sit in the middle, and what is
  /// covered right of it; nothing before it shows scaled down.
  ({double shift, Rect cover}) get _frame {
    final child = this.child;
    final shown = switch (canvas.currentContext?.findRenderObject()) {
      final RenderBox box when child != null && box.attached && box.hasSize =>
        MatrixUtils.transformRect(
          box.getTransformTo(child),
          Offset.zero & box.size,
        ),
      _ => null,
    };
    if (shown == null || shown.right >= size.width) {
      return (shift: 0, cover: Rect.zero);
    }
    final shift = (size.width - shown.right - shown.left) / 2;
    return (
      shift: shift,
      cover: Rect.fromLTRB(
        shown.right + shift,
        0,
        size.width,
        size.height - sheetHeight,
      ),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    final (:shift, :cover) = _frame;
    if (cover.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    final child = this.child;
    return child != null &&
        result.addWithPaintOffset(
          offset: Offset(shift, 0),
          position: position,
          hitTest: (result, position) =>
              child.hitTest(result, position: position),
        );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    transform.translateByDouble(_frame.shift, 0, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final (:shift, :cover) = _frame;
    final paint = Paint()..color = color;
    context.canvas.drawRect(offset & size, paint);
    if (child case final child?) {
      context.paintChild(child, offset + Offset(shift, 0));
    }
    context.canvas.drawRect(cover.shift(offset), paint);
  }
}

/// The strokes, frames and covers among [marks].
class const _Lines(
  final List<_Mark> marks,
  final Color color,
  final Color cover,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final mark in marks) {
      switch (mark) {
        case _Stroke(:final points):
          canvas.drawPath(
            Path()..addPolygon(points, false),
            paint..strokeWidth = 5,
          );
        case _Frame(:final rect):
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(6)),
            paint..strokeWidth = 4,
          );
        // Square and not anti-aliased: no corner or edge lets through a
        // blend of what lies under it.
        case _Cover(:final rect):
          canvas.drawRect(
            rect,
            Paint()
              ..color = cover
              ..isAntiAlias = false,
          );
        case _Words():
      }
    }
  }

  @override
  bool shouldRepaint(_Lines old) =>
      !listEquals(old.marks, marks) || old.color != color || old.cover != cover;
}

/// Below the screenshot: ✕, what to do and Fertig, then Stift / Rechteck /
/// Text / Verdecken and Undo.
class const _Tools({
  required final AnnotateTool tool,

  /// The cover tool first, under the report's hint.
  required final bool forReport,
  required final bool canUndo,
  required final ValueChanged<AnnotateTool> onPick,
  required final VoidCallback onUndo,
  required final VoidCallback onDone,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final coverSegment = HexSegment(
      key: const ValueKey('annotator-tool-cover'),
      value: AnnotateTool.cover,
      label: l10n.feedbackToolCover,
      icon: Icons.rectangle,
    );
    return Material(
      color: t.surfaceRaised,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HlSpace.s4,
              HlSpace.s3,
              HlSpace.s4,
              HlSpace.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('annotator-close'),
                      tooltip: l10n.close,
                      constraints: const BoxConstraints.tightFor(
                        width: HlSize.target,
                        height: HlSize.target,
                      ),
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: HlSpace.s1),
                    Expanded(
                      child: Text(
                        forReport
                            ? l10n.reportScreenshotHelp
                            : l10n.feedbackAnnotateHint,
                        style: TextStyle(fontSize: 15, color: t.textMuted),
                      ),
                    ),
                    const SizedBox(width: HlSpace.s3),
                    FilledButton(
                      key: const ValueKey('annotator-done'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 52),
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: HlSpace.s5,
                        ),
                        textStyle: const TextStyle(
                          fontFamily: HlFont.sans,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onDone,
                      child: Text(l10n.feedbackAnnotateDone),
                    ),
                  ],
                ),
                const SizedBox(height: HlSpace.s3),
                Row(
                  children: [
                    Expanded(
                      child: HexSegmented<AnnotateTool>(
                        label: l10n.feedbackAnnotateTools,
                        value: tool,
                        onChanged: onPick,
                        segments: [
                          if (forReport) coverSegment,
                          HexSegment(
                            key: const ValueKey('annotator-tool-pen'),
                            value: AnnotateTool.pen,
                            label: l10n.feedbackToolPen,
                            icon: Icons.edit_outlined,
                          ),
                          HexSegment(
                            key: const ValueKey('annotator-tool-rectangle'),
                            value: AnnotateTool.rectangle,
                            label: l10n.feedbackToolRectangle,
                            icon: Icons.crop_square,
                          ),
                          HexSegment(
                            key: const ValueKey('annotator-tool-text'),
                            value: AnnotateTool.text,
                            label: l10n.feedbackToolText,
                            icon: Icons.title,
                          ),
                          if (!forReport) coverSegment,
                        ],
                      ),
                    ),
                    const SizedBox(width: HlSpace.s1),
                    IconButton(
                      key: const ValueKey('annotator-undo'),
                      tooltip: l10n.feedbackAnnotateUndo,
                      constraints: const BoxConstraints.tightFor(
                        width: HlSize.target,
                        height: HlSize.target,
                      ),
                      onPressed: canUndo ? onUndo : null,
                      icon: const Icon(Icons.undo),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tells [onHeight] its child's height after a layout that changed it,
/// after the frame.
class const _MeasuredHeight({
  required final ValueChanged<double> onHeight,
  super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    if (renderObject is _RenderMeasuredHeight) {
      renderObject.onHeight = onHeight;
    }
  }
}

class _RenderMeasuredHeight(var ValueChanged<double> onHeight)
    extends RenderProxyBox {
  double? _told;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height != _told) {
      _told = height;
      SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
    }
  }
}
