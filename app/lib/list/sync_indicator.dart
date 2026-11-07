import 'dart:async';
import 'dart:math';
import 'dart:ui' show SemanticsHitTestBehavior, lerpDouble;

import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where the indicator is: nothing, the card, the pill in the top bar, or
/// a retry in flight (in the form it was tapped in).
enum SyncPhase() {
  hidden,
  open,
  collapsed,
  busy,
}

sealed class const SyncEvent();

/// The list's [ListState.trouble] changed; null: it syncs again.
final class const TroubleChanged(final SyncTrouble? kind) extends SyncEvent;

/// The card's 3 s are up.
final class const TimerFired() extends SyncEvent;

/// The user scrolled the list.
final class const Scrolled() extends SyncEvent;

/// The user swiped the card up.
final class const SwipedUp() extends SyncEvent;

/// A tap on the card or the pill.
final class const Tapped() extends SyncEvent;

/// The retry a failing tap started is over; [ok]: the list syncs again.
final class const RetryDone({required final bool ok}) extends SyncEvent;

@immutable
final class const SyncView({
  final SyncPhase phase = SyncPhase.hidden,

  /// The trouble shown; kept while hidden, so the leaving form keeps its
  /// face as it fades.
  final SyncTrouble? kind,

  /// While [SyncPhase.busy]: the form the retry was tapped in.
  final SyncPhase from = SyncPhase.collapsed,
}) {
  bool get showsCard =>
      phase == SyncPhase.open ||
      (phase == SyncPhase.busy && from == SyncPhase.open);

  bool get showsPill => phase != SyncPhase.hidden && !showsCard;

  @override
  bool operator ==(Object other) =>
      other is SyncView &&
      other.phase == phase &&
      other.kind == kind &&
      other.from == from;

  @override
  int get hashCode => Object.hash(phase, kind, from);
}

/// Design S2-C3F2 (job 157): the card opens for a new kind of trouble and
/// collapses into the pill after 3 s, on a scroll or on a swipe up. A tap
/// retries a failing sync, and toggles the offline card. The same kind
/// again never reopens it: the list retries every 3 s.
SyncView reduceSync(SyncView view, SyncEvent event) => switch (event) {
  TroubleChanged(kind: null) => SyncView(kind: view.kind),
  TroubleChanged(:final kind)
      when kind == view.kind && view.phase != SyncPhase.hidden =>
    view,
  TroubleChanged(:final kind) => SyncView(phase: SyncPhase.open, kind: kind),
  TimerFired() || Scrolled() || SwipedUp() =>
    view.phase == SyncPhase.open
        ? SyncView(phase: SyncPhase.collapsed, kind: view.kind)
        : view,
  Tapped() => switch (view.phase) {
    SyncPhase.hidden || SyncPhase.busy => view,
    final from when view.kind == SyncTrouble.failing => SyncView(
      phase: SyncPhase.busy,
      kind: view.kind,
      from: from,
    ),
    SyncPhase.open => SyncView(phase: SyncPhase.collapsed, kind: view.kind),
    SyncPhase.collapsed => SyncView(phase: SyncPhase.open, kind: view.kind),
  },
  RetryDone(:final ok) when view.phase == SyncPhase.busy => SyncView(
    phase: ok ? SyncPhase.hidden : SyncPhase.collapsed,
    kind: view.kind,
  ),
  RetryDone() => view,
};

/// The list's sync trouble over [child], the list: one hex shell that is a
/// card under the top bar while open and folds into a pill in the bar's
/// empty left slot, moving and resizing as one object while its content
/// crossfades. Nothing while the list syncs, pending changes included; no
/// word when it syncs again (screen readers hear one after a retry). The
/// shell floats over the list, so the list never moves.
class const SyncIndicator({
  required final Widget child,

  /// The top bar's row, below the top safe area: the pill centres on it.
  required final double rowTop,
  required final double rowHeight,

  /// Where the card starts, below the top safe area.
  required final double cardTop,
  super.key,
}) extends StatefulWidget {
  /// How long the card stays open on its own.
  static const peek = Duration(seconds: 3);

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState()
    extends State<SyncIndicator>
    with TickerProviderStateMixin {
  late var _view = reduceSync(
    const SyncView(),
    TroubleChanged(context.read<ListCubit>().state.trouble),
  );
  Timer? _collapse;

  /// 0 the card, 1 the pill.
  late final _fold = AnimationController(
    vsync: this,
    value: _view.showsPill ? 1 : 0,
  );

  /// 0 gone, 1 there.
  late final _shown = AnimationController(
    vsync: this,
    value: _view.phase == SyncPhase.hidden ? 0 : 1,
  );

  /// The busy arrows: a turn, or with reduced motion a pulse.
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  var _swipe = 0.0;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Reduced motion: every change is the same short crossfade.
  static const _reducedFade = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _restartTimer(const SyncView(), _view);
  }

  @override
  void dispose() {
    _collapse?.cancel();
    _fold.dispose();
    _shown.dispose();
    _spin.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _dispatch(SyncEvent event) {
    final before = _view;
    final after = reduceSync(before, event);
    if (after == before || !mounted) {
      return;
    }
    setState(() => _view = after);
    _restartTimer(before, after);
    final reduced = _reduced;
    if (after.phase == SyncPhase.hidden) {
      // Backwards: an animateTo 0 ends completed, not dismissed, and the
      // shell would stay.
      _shown.animateBack(
        0,
        duration: reduced ? _reducedFade : HlDuration.medium,
        curve: HlEasing.exit,
      );
    } else {
      final fold = after.showsPill ? 1.0 : 0.0;
      if (_shown.isDismissed) {
        // Nothing to fold from: it arrives in its form.
        _fold.value = fold;
      } else if (_fold.value != fold) {
        _fold.animateTo(
          fold,
          duration: reduced ? _reducedFade : HlDuration.long,
          curve: reduced ? Curves.linear : HlEasing.standard,
        );
      }
      _shown.animateTo(
        1,
        duration: reduced ? _reducedFade : HlDuration.medium,
        curve: HlEasing.standard,
      );
    }
    if (after.phase == SyncPhase.busy) {
      _spin.repeat(reverse: reduced);
    } else {
      _spin.reset();
    }
  }

  void _restartTimer(SyncView before, SyncView after) {
    final opened =
        after.phase == SyncPhase.open &&
        (before.phase != SyncPhase.open || before.kind != after.kind);
    if (opened) {
      _collapse?.cancel();
      _collapse = Timer(
        SyncIndicator.peek,
        () => _dispatch(const TimerFired()),
      );
    } else if (after.phase != SyncPhase.open) {
      _collapse?.cancel();
      _collapse = null;
    }
  }

  Future<void> _tap() async {
    final before = _view;
    _dispatch(const Tapped());
    if (before.phase == SyncPhase.busy || _view.phase != SyncPhase.busy) {
      return;
    }
    final ok = await context.read<ListCubit>().retry();
    if (!mounted) {
      return;
    }
    final settled = _view.phase == SyncPhase.busy && !ok;
    _dispatch(RetryDone(ok: ok));
    if (settled && !_reduced) {
      _nudge.forward(from: 0);
    }
    if (ok || settled) {
      final l10n = AppLocalizations.of(context);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          ok ? l10n.syncSynced : l10n.syncStillFailing,
          Directionality.of(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ListCubit>().state;
    return BlocListener<ListCubit, ListState>(
      listenWhen: (a, b) => a.trouble != b.trouble,
      listener: (_, state) => _dispatch(TroubleChanged(state.trouble)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side =
              ShoppingListView.frameFor(constraints.maxWidth, state).side +
              HlSpace.s4;
          return Stack(
            fit: StackFit.expand,
            children: [
              NotificationListener<UserScrollNotification>(
                // The user's own scrolls only, by drag, wheel or trackpad:
                // a list that moves for a new row is no reason.
                onNotification: (n) {
                  if (n.direction != ScrollDirection.idle &&
                      n.metrics.axis == Axis.vertical) {
                    _dispatch(const Scrolled());
                  }
                  return false;
                },
                child: widget.child,
              ),
              if (_view.kind case final kind?)
                AnimatedBuilder(
                  animation: Listenable.merge([_fold, _shown]),
                  builder: (context, _) => _shell(
                    context,
                    kind,
                    side: side,
                    width: constraints.maxWidth - 2 * side,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The shell at this frame of the fold and of its presence.
  Widget _shell(
    BuildContext context,
    SyncTrouble kind, {
    required double side,
    required double width,
  }) {
    if (_shown.isDismissed) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final reduced = _reduced;
    // Reduced motion: no morph; the form switches at the bottom of a dip in
    // the opacity.
    final fold = reduced ? (_fold.value < 0.5 ? 0.0 : 1.0) : _fold.value;
    final dip = reduced ? (2 * _fold.value - 1).abs() : 1.0;
    final shown = _view.phase != SyncPhase.hidden;
    final top = MediaQuery.paddingOf(context).top;
    final brightness = Theme.of(context).brightness;
    final t = HummlistColors.of(brightness);
    final tone = _tone(kind, brightness);
    final busy = _view.phase == SyncPhase.busy;
    void onTap() => unawaited(_tap());
    final open = _view.showsCard;

    var shell = _node(
      context,
      kind: kind,
      view: _view,
      onTap: onTap,
      child: TextButton(
        key: const ValueKey('sync-indicator'),
        onPressed: onTap,
        style:
            tactileButtonStyle(
              colors: (_) => TactileColors(
                face: tone.face,
                contour: t.border,
                edge: tone.edge,
                focus: t.accent,
              ),
              foreground: WidgetStatePropertyAll(tone.text),
              textStyle: _Pill.wordStyle(context),
            ).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size.zero),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              // 48 px to tap in every form, the pill's 36 included.
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
        child: _Morph(
          fold: fold,
          cardWidth: width,
          pill: Size(_Pill.width(context, kind, width), _Pill.height),
          icon: _StateIcon(
            kind: kind,
            busy: busy,
            spin: _spin,
            color: tone.text,
            size: lerpDouble(_Card.icon, _Pill.icon, fold)!,
          ),
          // A form's content is there from the moment it is the target.
          card: fold < 1 || open
              ? _Card(
                  key: const ValueKey('sync-card'),
                  kind: kind,
                  busy: busy,
                  color: tone.text,
                )
              : null,
          word: fold > 0 || _view.showsPill
              ? MediaQuery.withClampedTextScaling(
                  maxScaleFactor: SyncPillSpace.maxTextScale,
                  child: _Pill(
                    key: const ValueKey('sync-pill'),
                    kind: kind,
                    color: tone.text,
                  ),
                )
              : null,
        ),
      ),
    );
    shell = GestureDetector(
      onVerticalDragStart: open ? (_) => _swipe = 0 : null,
      onVerticalDragUpdate: open
          ? (d) {
              _swipe += d.delta.dy;
              if (_swipe <= -20) {
                _dispatch(const SwipedUp());
              }
            }
          : null,
      child: _Nudge(animation: _nudge, child: shell),
    );
    if (!reduced && _shown.value < 1) {
      // It grows out of where it stands: the card from the bar's left end,
      // the pill from its middle.
      shell = Transform.scale(
        scale: lerpDouble(lerpDouble(0.92, 0.6, fold), 1, _shown.value),
        alignment: Alignment.lerp(Alignment.topLeft, Alignment.center, fold),
        child: shell,
      );
    }
    return Positioned(
      left: side,
      top: lerpDouble(
        top + widget.cardTop,
        top + widget.rowTop + (widget.rowHeight - HlSize.target) / 2,
        fold,
      ),
      // A leaving shell is out of the semantics tree and takes no taps.
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: Opacity(opacity: _shown.value * dip, child: shell),
        ),
      ),
    );
  }
}

/// A short shake of the shell after a retry that failed again.
class const _Nudge({
  required final Animation<double> animation,
  required final Widget child,
}) extends StatelessWidget {
  static final _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -4), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 4, end: -2), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -2, end: 0), weight: 25),
  ]);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => animation.isAnimating
        ? Transform.translate(
            offset: Offset(_offset.evaluate(animation), 0),
            child: child,
          )
        : child!,
    child: child,
  );
}

/// The face colours of a trouble: offline navy with light text, failing
/// honey with navy text (job 157's tone 1).
({Color face, Color text, Color edge}) _tone(
  SyncTrouble kind,
  Brightness brightness,
) {
  final t = HummlistColors.of(brightness);
  return switch (kind) {
    SyncTrouble.offline => (
      // Dark mode's inverse is the page itself; the lighter navy stands off.
      face: brightness == Brightness.light ? t.inverse : t.surfaceEdge,
      text: t.onInverse,
      edge: t.edge,
    ),
    SyncTrouble.failing => (face: t.honey, text: t.onHoney, edge: t.honeyEdge),
  };
}

/// The shell's one semantics node: the full sentence, so the pill says as
/// much as the card. Offline toggles the card; failing retries.
Widget _node(
  BuildContext context, {
  required SyncTrouble kind,
  required SyncView view,
  required VoidCallback onTap,
  required Widget child,
}) {
  final l10n = AppLocalizations.of(context);
  final busy = view.phase == SyncPhase.busy;
  return Semantics(
    container: true,
    button: true,
    // The rows under it keep their tappable web elements otherwise.
    hitTestBehavior: SemanticsHitTestBehavior.opaque,
    label: busy
        ? l10n.syncRetrying
        : switch (kind) {
            SyncTrouble.offline => l10n.syncOfflineLabel,
            SyncTrouble.failing => l10n.syncFailingLabel,
          },
    hint: switch (kind) {
      _ when busy => null,
      SyncTrouble.failing => l10n.retry,
      SyncTrouble.offline when !view.showsCard => l10n.syncDetails,
      SyncTrouble.offline => null,
    },
    expanded: kind == SyncTrouble.offline ? view.showsCard : null,
    onTap: busy ? null : onTap,
    excludeSemantics: true,
    child: child,
  );
}

/// The state icon; spinning sync arrows while a retry is in flight.
class const _StateIcon({
  required final SyncTrouble kind,
  required final bool busy,
  required final Animation<double> spin,
  required final Color color,
  required final double size,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Icon(
        switch (kind) {
          SyncTrouble.offline => Icons.cloud_off,
          SyncTrouble.failing => Icons.sync_problem,
        },
        color: color,
        size: size,
      );
    }
    final arrows = Icon(Icons.sync, color: color, size: size);
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.35).animate(spin),
            child: arrows,
          )
        // Material's sync arrows turn anticlockwise.
        : RotationTransition(
            turns: Tween<double>(begin: 0, end: -1).animate(spin),
            child: arrows,
          );
  }
}

/// The folded form's word, right of the icon: the pill sits in the top
/// bar's empty left slot, 36 px to see, 48 px to tap.
class const _Pill({
  required final SyncTrouble kind,
  required final Color color,
  super.key,
}) extends StatelessWidget {
  /// The face and its edge.
  static const height = 36.0;

  static const _pad = HlHex.tip * height + HlSpace.s2;
  static const icon = 18.0;
  static const _gap = HlSpace.s1 + 2;

  /// Where the icon sits in the pill.
  static const iconLeft = _pad;

  /// Anpassen at its widest and the bar's gaps before it, the partner's
  /// capsule's included (it shrinks to fit).
  static const _anpassen = 160.0 + 2 * HlSpace.s2;

  static TextStyle wordStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      );

  static String _word(AppLocalizations l10n, SyncTrouble kind) =>
      switch (kind) {
        SyncTrouble.offline => l10n.syncOffline,
        SyncTrouble.failing => l10n.syncFailingWord,
      };

  /// As wide as the word sets, but never into Anpassen's room: there the
  /// word shrinks (320 px at large text).
  static double width(BuildContext context, SyncTrouble kind, double row) {
    final word = TextPainter(
      text: TextSpan(
        text: _word(AppLocalizations.of(context), kind),
        style: wordStyle(context),
      ),
      textScaler: MediaQuery.textScalerOf(context)
          .clamp(maxScaleFactor: SyncPillSpace.maxTextScale),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final natural = 2 * _pad + icon + _gap + word.width.ceilToDouble();
    word.dispose();
    return min(natural, max(HlSize.target, row - _anpassen));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: _pad + icon + _gap, right: _pad),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _word(AppLocalizations.of(context), kind),
          maxLines: 1,
          style: wordStyle(context).copyWith(color: color),
        ),
      ),
    ),
  );
}

/// Holds the pill's width in the top bar while there is trouble, so the
/// partner's "neu von" capsule never runs under it.
class const SyncPillSpace({
  /// The top bar's row width.
  required final double row,
  super.key,
}) extends StatelessWidget {
  /// The bar's and the pill's: large text still fits the 52 high bar.
  static const maxTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final kind = context.select<ListCubit, SyncTrouble?>(
      (c) => c.state.trouble,
    );
    return kind == null
        ? const SizedBox.shrink()
        : SizedBox(width: _Pill.width(context, kind, row));
  }
}

/// The open form's text right of the icon: a bold title and one line;
/// failing adds the retry hex.
class const _Card({
  required final SyncTrouble kind,
  required final bool busy,
  required final Color color,
  super.key,
}) extends StatelessWidget {
  static const icon = 24.0;
  static const iconLeft = HlSpace.s5 + 2;

  /// The face's least height.
  static const minHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failing = kind == SyncTrouble.failing;
    return Padding(
      // The tips grow with the card's height: the text keeps clear of them
      // at large text sizes, the icon and the retry hex sit where the card
      // is widest.
      padding: EdgeInsets.fromLTRB(
        iconLeft + icon + HlSpace.s3,
        HlSpace.s2 + 2,
        failing ? HlSpace.s5 - 2 : HlSpace.s6 + HlSpace.s2,
        HlSpace.s2 + 2,
      ),
      child: Row(
        spacing: HlSpace.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  failing ? l10n.syncFailing : l10n.syncOffline,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  failing ? l10n.syncFailingLine : l10n.syncOfflineLine,
                  // Not the button's bold label style.
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (failing)
            // The shell is the button, for taps, screen readers and the
            // keyboard; this is its visible cue.
            AnimatedOpacity(
              key: const ValueKey('sync-retry'),
              opacity: busy ? 0.45 : 1,
              duration: hlMotion(context, HlDuration.short),
              child: const _RetryCue(),
            ),
        ],
      ),
    );
  }
}

/// A raised hex with the retry arrow, drawn as the theme's secondary button.
class const _RetryCue() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return TactileFace(
      states: const {},
      colors: TactileColors(
        face: t.surfaceRaised,
        contour: t.border,
        edge: t.surfaceEdge,
        focus: t.accent,
      ),
      child: SizedBox(
        width: 52,
        height: 40,
        child: Padding(
          // Centred on the face, above its edge.
          padding: const EdgeInsets.only(bottom: HlDepth.edge),
          child: Icon(Icons.refresh, size: 20, color: t.text),
        ),
      ),
    );
  }
}

enum _Part() {
  card,
  word,
  icon,
}

/// The shell's content at one point of the fold: the card's text laid out
/// at the card's width, the pill's word at the pill's size, each as it
/// stands when the fold ends, so nothing reflows on the way. It takes the
/// size between the two forms, crossfades them and moves the one icon
/// between their places, all clipped to the hex face.
class const _Morph({
  /// 0 the card, 1 the pill.
  required final double fold,
  required final double cardWidth,

  /// The pill's face and edge.
  required final Size pill,
  required final Widget icon,
  final Widget? card,
  final Widget? word,
}) extends SlottedMultiChildRenderObjectWidget<_Part, RenderBox> {
  @override
  Iterable<_Part> get slots => _Part.values;

  @override
  Widget? childForSlot(_Part slot) => switch (slot) {
    _Part.card => card,
    _Part.word => word,
    _Part.icon => icon,
  };

  @override
  _RenderMorph createRenderObject(BuildContext context) =>
      _RenderMorph(fold: fold, cardWidth: cardWidth, pill: pill);

  @override
  void updateRenderObject(BuildContext context, _RenderMorph renderObject) =>
      renderObject
        ..fold = fold
        ..cardWidth = cardWidth
        ..pill = pill;
}

class _RenderMorph({
  required double fold,
  required double cardWidth,
  required Size pill,
}) extends RenderBox with SlottedContainerRenderObjectMixin<_Part, RenderBox> {
  var _fold = fold;
  var _cardWidth = cardWidth;
  var _pill = pill;

  /// The card's text goes in the first part of the fold, the pill's word
  /// comes in the rest; the other way round on the way back.
  static const _cardOut = Interval(0, 0.3);
  static const _wordIn = Interval(0.55, 1);

  static const _shape = HexBorder();
  final _clip = LayerHandle<ClipPathLayer>();
  final _opacities = {
    for (final part in _Part.values) part: LayerHandle<OpacityLayer>(),
  };

  double get fold => _fold;
  set fold(double value) {
    if (value != _fold) {
      final fading = _fading;
      _fold = value;
      markNeedsLayout();
      if (_fading != fading) {
        markNeedsCompositingBitsUpdate();
      }
    }
  }

  /// A fading part paints into its own opacity layer, which a clip on the
  /// canvas would not reach.
  bool get _fading => _Part.values.any((part) {
    final opacity = _opacity(part);
    return opacity > 0 && opacity < 1;
  });

  @override
  bool get alwaysNeedsCompositing => _fading;

  double get cardWidth => _cardWidth;
  set cardWidth(double value) {
    if (value != _cardWidth) {
      _cardWidth = value;
      markNeedsLayout();
    }
  }

  Size get pill => _pill;
  set pill(Size value) {
    if (value != _pill) {
      _pill = value;
      markNeedsLayout();
    }
  }

  double _opacity(_Part part) => switch (part) {
    _Part.card => 1 - _cardOut.transform(_fold.clamp(0, 1)),
    _Part.word => _wordIn.transform(_fold.clamp(0, 1)),
    _Part.icon => 1,
  };

  BoxConstraints get _cardConstraints => BoxConstraints(
    minWidth: _cardWidth,
    maxWidth: _cardWidth,
    minHeight: _Card.minHeight,
  );

  Size _sizeFor(Size? card, BoxConstraints constraints) {
    final open = card == null
        ? _pill
        : Size(_cardWidth, card.height + HlDepth.edge);
    return constraints.constrain(Size.lerp(open, _pill, _fold)!);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(
    childForSlot(_Part.card)?.getDryLayout(_cardConstraints),
    constraints,
  );

  @override
  void performLayout() {
    final card = childForSlot(_Part.card);
    final word = childForSlot(_Part.word);
    final icon = childForSlot(_Part.icon);
    card?.layout(_cardConstraints, parentUsesSize: true);
    word?.layout(
      BoxConstraints.tight(Size(_pill.width, _pill.height - HlDepth.edge)),
      parentUsesSize: true,
    );
    icon?.layout(const BoxConstraints(), parentUsesSize: true);
    size = _sizeFor(card?.size, constraints);
    // The face is the shell less its edge, and the label moves up by half
    // the edge to sit on it (tactileButtonStyle): centred here is centred
    // on the face.
    for (final child in [?card, ?word]) {
      (child.parentData! as BoxParentData).offset = Offset(
        0,
        (size.height - child.size.height) / 2,
      );
    }
    if (icon != null) {
      (icon.parentData! as BoxParentData).offset = Offset(
        lerpDouble(_Card.iconLeft, _Pill.iconLeft, _fold)!,
        (size.height - icon.size.height) / 2,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final face = Rect.fromLTRB(
      0,
      HlDepth.edge / 2,
      size.width,
      size.height - HlDepth.edge / 2,
    );
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      _shape.pathFor(face, outset: -HlBorder.width),
      (context, offset) {
        for (final part in _Part.values) {
          final child = childForSlot(part);
          final opacity = _opacity(part);
          final handle = _opacities[part]!;
          if (child == null || opacity == 0) {
            handle.layer = null;
            continue;
          }
          final at = offset + (child.parentData! as BoxParentData).offset;
          if (opacity == 1) {
            handle.layer = null;
            context.paintChild(child, at);
          } else {
            handle.layer = context.pushOpacity(
              at,
              (opacity * 255).round(),
              (context, offset) => context.paintChild(child, offset),
              oldLayer: handle.layer,
            );
          }
        }
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final part in _Part.values.reversed) {
      final child = childForSlot(part);
      if (child == null || _opacity(part) == 0) {
        continue;
      }
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as BoxParentData).offset,
        position: position,
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      );
      if (hit) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _clip.layer = null;
    for (final handle in _opacities.values) {
      handle.layer = null;
    }
    super.dispose();
  }
}
