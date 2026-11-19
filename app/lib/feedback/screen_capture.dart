import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:family_groceries/shell/router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The longest side of a screenshot in pixels: a phone's at 1.5x, and a
/// tablet's no larger, so the PNG stays well under the bucket's 2 MiB.
const _maxShotSide = 1400.0;

/// The pixel ratio a screenshot of a [size] screen is taken at.
double shotPixelRatio(Size size) =>
    math.min(1.5, _maxShotSide / math.max(1, size.longestSide));

/// Takes pictures of the app for feedback (job 267): the live screen at a
/// shake, and the screen shown before the user switched to More, for
/// More's "Bildschirmfoto hinzufügen". [wrap] goes around the whole app.
class ScreenCapture() {
  final _boundary = GlobalKey(debugLabel: 'screen-capture');
  ui.Image? _beforeMore;

  /// The app inside the boundary pictures are taken of.
  Widget wrap(Widget child) => RepaintBoundary(key: _boundary, child: child);

  /// The screen after the frame being drawn; null when there is no app to
  /// picture or the engine could not.
  Future<ui.Image?> grab() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      return null;
    }
    try {
      return await boundary.toImage(pixelRatio: shotPixelRatio(boundary.size));
    } on Object {
      return null;
    }
  }

  /// The screen shown before More; kept until the user leaves More.
  ui.Image? get beforeMore => _beforeMore;

  /// Pictures the screen the user is about to leave for More.
  Future<void> grabBeforeMore() async {
    final image = await grab();
    _beforeMore?.dispose();
    _beforeMore = image;
  }

  /// The router moved to [location]: out of More, the picture is stale.
  void visit(Uri location) {
    if (!inMoreTab(location)) {
      _beforeMore?.dispose();
      _beforeMore = null;
    }
  }

  void dispose() {
    _beforeMore?.dispose();
    _beforeMore = null;
  }
}
