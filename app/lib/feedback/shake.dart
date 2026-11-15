import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/feedback/annotator.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_sheet.dart';
import 'package:family_groceries/feedback/screen_capture.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Phones shake; a browser or a desktop window can't (job 138).
bool shakeSupported({required bool web, required TargetPlatform platform}) =>
    !web &&
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

/// Whether this device shakes for feedback: [shakeSupported] here.
bool get shakeHere =>
    shakeSupported(web: kIsWeb, platform: defaultTargetPlatform);

/// Tells a shake from walking, a bump or putting the phone down: at least
/// [peaks] swings over [threshold] g within [window], then nothing for
/// [cooldown] (job 138).
class ShakeDetector() {
  /// In g, gravity included: a phone at rest reads 1.
  static const threshold = 2.7;
  static const peaks = 3;
  static const window = Duration(milliseconds: 800);
  static const cooldown = Duration(milliseconds: 1500);
  static const _gravity = 9.81;

  final _peaks = Queue<DateTime>();
  var _above = false;
  DateTime? _quietUntil;

  /// Takes one sample; true when it completes a shake.
  bool add(AccelerometerEvent sample) {
    final g =
        math.sqrt(
          sample.x * sample.x + sample.y * sample.y + sample.z * sample.z,
        ) /
        _gravity;
    final above = g > threshold;
    // A swing is one peak however many samples it spans.
    final rising = above && !_above;
    _above = above;
    final at = sample.timestamp;
    if (!rising || (_quietUntil?.isAfter(at) ?? false)) {
      return false;
    }
    _peaks.add(at);
    while (at.difference(_peaks.first) > window) {
      _peaks.removeFirst();
    }
    if (_peaks.length < peaks) {
      return false;
    }
    _peaks.clear();
    _quietUntil = at.add(cooldown);
    return true;
  }
}

/// The Einstellungen switch "Schütteln für Feedback": on until switched
/// off, kept on the device.
class ShakeSetting(final DeviceCache _cache) extends Cubit<bool> {
  this : super(true) {
    unawaited(_load());
  }

  Future<void> _load() async {
    final on = await _cache.shakeToFeedback();
    if (!isClosed && on != state) {
      emit(on);
    }
  }

  void set({required bool on}) {
    emit(on);
    unawaited(_cache.saveShakeToFeedback(on: on));
  }
}

/// A shake on a signed-in screen asks whether to report a problem with it
/// (job 267). Listens only while [enabled], on iOS and Android, with the
/// app in front.
class const ShakeToFeedback({
  required final bool enabled,
  required final Widget child,
  super.key,

  /// The accelerometer; fake samples in tests. A broadcast stream: a
  /// household switch builds this widget again, which listens again.
  final Stream<AccelerometerEvent>? samples,
}) extends StatefulWidget {
  @override
  State<ShakeToFeedback> createState() => _ShakeToFeedbackState();
}

class _ShakeToFeedbackState() extends State<ShakeToFeedback> {
  final _detector = ShakeDetector();
  AppLifecycleListener? _lifecycle;
  StreamSubscription<AccelerometerEvent>? _subscription;

  /// A shake's questions, annotator or form are open.
  var _running = false;

  /// Enabled, on a phone, with the app in front (null: no lifecycle report
  /// yet, at startup). A rebuild while inactive or hidden must not listen.
  bool get _listens =>
      widget.enabled &&
      shakeHere &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _listen,
      onInactive: _stop,
      onHide: _stop,
    );
    _listen();
  }

  @override
  void didUpdateWidget(ShakeToFeedback old) {
    super.didUpdateWidget(old);
    if (_listens) {
      _listen();
    } else {
      _stop();
    }
  }

  void _listen() {
    if (!_listens) {
      return;
    }
    _subscription ??=
        (widget.samples ??
                accelerometerEventStream(
                  samplingPeriod: SensorInterval.gameInterval,
                ))
            .listen(
              _onSample,
              // A phone without an accelerometer: no shake, nothing else.
              onError: (Object _) => _stop(),
              cancelOnError: true,
            );
  }

  void _stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _onSample(AccelerometerEvent sample) {
    if (_detector.add(sample) &&
        mounted &&
        !_running &&
        !Popups.openAbove(context)) {
      _running = true;
      unawaited(reportFromShake(context).whenComplete(() => _running = false));
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What the shake sheet's buttons answer.
enum _ShakeChoice() {
  withScreenshot,
  without,
}

/// A shake: picture the screen as it is, ask in a bottom sheet, then mark
/// up the picture (with it) and open the form with the screen's name.
Future<void> reportFromShake(BuildContext context) async {
  final screen = context.read<ScreenTracker>().current;
  final image = await context.read<ScreenCapture>().grab();
  try {
    if (!context.mounted) {
      return;
    }
    final choice = await showModalBottomSheet<_ShakeChoice>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      sheetAnimationStyle: AnimationStyle(
        curve: HlEasing.standard,
        reverseCurve: HlEasing.exit,
        duration: hlMotion(context, HlDuration.medium),
        reverseDuration: hlMotion(context, HlDuration.short),
      ),
      builder: (_) => ShakeSheet(withScreenshot: image != null),
    );
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case _ShakeChoice.without:
        await showFeedbackSheet(
          context,
          entryPoint: FeedbackEntryPoint.shake,
          screen: screen,
        );
      case _ShakeChoice.withScreenshot when image != null:
        final png = await annotateScreenshot(context, image);
        if (png != null && context.mounted) {
          await showFeedbackSheet(
            context,
            entryPoint: FeedbackEntryPoint.shake,
            screen: screen,
            screenshot: png,
          );
        }
      case _ShakeChoice.withScreenshot || null:
        break;
    }
  } finally {
    image?.dispose();
  }
}

/// "Problem mit diesem Bildschirm melden?": with a screenshot (when one
/// could be taken) or without; ✕ or a tap beside closes it.
class const ShakeSheet({required final bool withScreenshot, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    const label = TextStyle(
      fontFamily: HlFont.sans,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    );
    const buttonSize = Size.fromHeight(52);
    return SingleChildScrollView(
      child: Padding(
        key: const ValueKey('shake-sheet'),
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s5,
          HlSpace.s2,
          HlSpace.s2,
          HlSpace.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: HlSpace.s3),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.feedbackShakeTitle,
                        style: const TextStyle(
                          fontFamily: HlFont.display,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('shake-close'),
                  tooltip: l10n.feedbackClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: HlSpace.s4,
                right: HlSpace.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (withScreenshot) ...[
                    FilledButton.icon(
                      key: const ValueKey('shake-with-screenshot'),
                      style: FilledButton.styleFrom(
                        minimumSize: buttonSize,
                        textStyle: label,
                      ),
                      onPressed: () =>
                          Navigator.of(context)
                              .pop(_ShakeChoice.withScreenshot),
                      icon: const Icon(Icons.screenshot_outlined),
                      label: Text(l10n.feedbackShakeWithScreenshot),
                    ),
                    const SizedBox(height: HlSpace.s3),
                  ],
                  OutlinedButton.icon(
                    key: const ValueKey('shake-without'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: buttonSize,
                      textStyle: label,
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(_ShakeChoice.without),
                    icon: const Icon(Icons.edit_note),
                    label: Text(l10n.feedbackShakeWithout),
                  ),
                  const SizedBox(height: HlSpace.s4),
                  Text(
                    l10n.feedbackShakeOffHint,
                    key: const ValueKey('shake-off-hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: t.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
