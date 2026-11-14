import 'dart:async';

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The running trip above the add field (job 234, TM1's slim strip): the
/// stopwatch, whether it runs, pause or resume, and Beenden. Dark in both
/// themes, so it reads as the trip's and not as one more list row.
class const TripStrip({
  required final RunningTrip trip,

  /// The newest tick of the trip; an auto-paused trip ends there.
  required final DateTime? lastTick,

  /// The stopwatch at a moment.
  required final Duration Function(DateTime now) elapsed,
  required final VoidCallback onPause,
  required final VoidCallback onResume,
  required final VoidCallback onEnd,
  final DateTime Function() clock = DateTime.now,
  super.key,
}) extends StatefulWidget {
  static const height = 52.0;

  @override
  State<TripStrip> createState() => _TripStripState();
}

class _TripStripState() extends State<TripStrip> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final trip = widget.trip;
    final now = widget.clock();
    final paused = trip.paused;
    final autoPaused = autoPause(trip) != null;
    // Auto-paused, Beenden ends at the last tick, which the label names.
    final lastText = DateFormat.Hm(locale)
        .format(endAt(trip, widget.lastTick, now).toLocal());
    final elapsed = widget.elapsed(now);
    final label = switch ((paused, autoPaused)) {
      (_, true) => l10n.shopAutoPaused(lastText),
      (true, false) => l10n.shopPaused,
      (false, _) => l10n.shopRunning,
    };
    final onInverse = t.onInverse;
    final spoken = '$label, ${l10n.shopClockLabel(elapsed.inMinutes)}';
    final status = Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Row(
          spacing: HlSpace.s2,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paused ? onInverse.withValues(alpha: 0.4) : t.mint,
              ),
            ),
            Text(
              stopwatch(elapsed),
              key: const ValueKey('trip-strip-clock'),
              style: HlType.label.copyWith(
                color: onInverse,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HlType.caption.copyWith(
                  color: onInverse.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final pause = Semantics(
      button: true,
      label: paused ? l10n.shopResume : l10n.shopPause,
      excludeSemantics: true,
      onTap: paused ? widget.onResume : widget.onPause,
      child: IconButton(
        key: const ValueKey('trip-strip-pause'),
        onPressed: paused ? widget.onResume : widget.onPause,
        style: IconButton.styleFrom(
          backgroundColor: onInverse.withValues(alpha: 0.14),
          foregroundColor: onInverse,
          shape: const HexBorder(),
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
      ),
    );
    final end = TextButton(
      key: const ValueKey('trip-strip-end'),
      onPressed: widget.onEnd,
      style: TextButton.styleFrom(
        backgroundColor: t.honey,
        foregroundColor: t.onHoney,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: HlSpace.s4),
      ),
      child: Text(autoPaused ? l10n.shopEndAt(lastText) : l10n.shopEnd),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HlSpace.s4,
          0,
          HlSpace.s4,
          HlSpace.s2,
        ),
        child: DecoratedBox(
          key: const ValueKey('trip-strip'),
          decoration: BoxDecoration(
            color: t.inverse,
            borderRadius: BorderRadius.circular(HlRadius.s),
            // The dark page and the dark strip need the contour to part.
            border: theme.brightness == Brightness.dark
                ? Border.all(color: t.border, width: HlBorder.width)
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TripStrip.height),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                HlSpace.s3,
                HlSpace.s1,
                HlSpace.s1,
                HlSpace.s1,
              ),
              child: autoPaused
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: HlSpace.s1,
                          ),
                          child: status,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: HlSpace.s2,
                          children: [pause, end],
                        ),
                      ],
                    )
                  : Row(
                      spacing: HlSpace.s2,
                      children: [
                        Expanded(child: status),
                        pause,
                        end,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The stopwatch's face: `m:ss`, `h:mm:ss` from an hour on.
String stopwatch(Duration d) {
  final seconds = d.isNegative ? 0 : d.inSeconds;
  final h = seconds ~/ 3600;
  final m = seconds ~/ 60 % 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
