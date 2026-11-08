import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/pointy_hex.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/hints_cubit.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Provides the List tab's [HintsCubit] for [list] around [child], below
/// its [AddSheetCubit]. Without a [HintStore] the log starts fresh each
/// session.
class const ProvideHints({
  required final ListCubit list,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ObjectKey(list),
    create: (context) {
      final session = context.read<SessionCubit?>()?.state;
      final cubit = HintsCubit(
        context.read<HintStore?>() ?? const _NoHintStore(),
        list,
        platform: HintPlatform.current(
          web: kIsWeb,
          platform: defaultTargetPlatform,
        ),
        kind: session is InHousehold ? session.household.kind : null,
        host: context.read<HintHost?>() ?? const HintHost(),
        analytics: context.read<Analytics?>(),
      );
      unawaited(cubit.load());
      return cubit;
    },
    child: _HintScreen(child: child),
  );
}

class const _NoHintStore() implements HintStore {
  @override
  Future<String?> hintLog(String userId) async => null;

  @override
  Future<void> saveHintLog(String userId, String json) async {}
}

/// Tells the hints what is on screen: the add sheet, a dialog or sheet on
/// the root navigator, the keyboard, another tab or a page over the list,
/// and the household's kind.
class const _HintScreen({required final Widget child}) extends StatefulWidget {
  @override
  State<_HintScreen> createState() => _HintScreenState();
}

class _HintScreenState() extends State<_HintScreen> {
  Popups? _popups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final popups = Popups.maybeOf(context);
    if (popups != _popups) {
      _popups?.removeListener(_tell);
      _popups = popups?..addListener(_tell);
    }
  }

  @override
  void dispose() {
    _popups?.removeListener(_tell);
    super.dispose();
  }

  void _tell() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit?>()?.state;
    final covered =
        (_popups?.open ?? false) ||
        MediaQuery.viewInsetsOf(context).bottom > 0 ||
        context.select<AddSheetCubit, bool>((c) => c.state.open);
    final listHidden =
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true);
    final kind = session is InHousehold ? session.household.kind : null;
    final cubit = context.read<HintsCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        cubit.screen(covered: covered, listHidden: listHidden, kind: kind);
      }
    });
    return widget.child;
  }
}

/// The slot at the top of the list: the checklist while it is open, else a
/// card hint or the callout under Anpassen. Empty without a [HintsCubit].
class const ListHints({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<HintsCubit?>()?.state;
    final shown = switch (state) {
      HintsState(checklist: final checklist?) => (
        const ValueKey('list-hint'),
        ChecklistCard(
          checklist: checklist,
          onDismiss: context.read<HintsCubit>().dismissChecklist,
        ),
      ),
      HintsState(hint: final hint?) when hint.place == HintPlace.card => (
        ValueKey('tip-${hint.id.wire}'),
        HintCard(
          hint: hint,
          onDismiss: () => dismissHint(context),
          onAct: () => actOnHint(context, hint),
        ),
      ),
      HintsState(hint: final hint?) when hint.place == HintPlace.belowEdit => (
        ValueKey('tip-${hint.id.wire}'),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: HintCallout(
            hint: hint,
            pointing: AxisDirection.up,
            onDismiss: () => dismissHint(context),
            onAct: () => actOnHint(context, hint),
          ),
        ),
      ),
      _ => null,
    };
    final switcher = AnimatedSwitcher(
      duration: hlMotion(context, HlDuration.short),
      switchInCurve: HlEasing.standard,
      switchOutCurve: HlEasing.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: switch (shown) {
        (final key, final child) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(
            horizontal: HlSpace.s3,
            vertical: HlSpace.s2,
          ),
          child: child,
        ),
        null => const SizedBox(width: double.infinity),
      },
    );
    final resize = hlMotion(context, HlDuration.medium);
    // A zero-length AnimatedSize finishes inside its own layout and asserts
    // when the checklist changes height with reduced motion.
    return resize == Duration.zero
        ? switcher
        : AnimatedSize(
            duration: resize,
            curve: HlEasing.standard,
            alignment: Alignment.topCenter,
            child: switcher,
          );
  }
}

/// The dictation hint above the add bar, pointing at the microphone; empty
/// for any other hint or while [hidden].
class const AddBarHint({required final bool hidden, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hint = context.watch<HintsCubit?>()?.state.hint;
    return AnimatedSwitcher(
      duration: hlMotion(context, HlDuration.short),
      child: hint != null && hint.place == HintPlace.aboveAddBar && !hidden
          ? HintCallout(
              key: ValueKey('tip-${hint.id.wire}'),
              hint: hint,
              pointing: AxisDirection.down,
              onDismiss: () => dismissHint(context),
              onAct: () => actOnHint(context, hint),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// X on the List tab's hint: hidden for good, and where to read it again.
void dismissHint(BuildContext context) {
  context.read<HintsCubit>().dismiss();
  Notices.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).hintDismissedNotice),
        duration: const Duration(seconds: 3),
        persist: false,
      ),
    );
}

/// The List tab's hint's button.
void actOnHint(BuildContext context, Hint hint) {
  context.read<HintsCubit>().act();
  if (hint.action case final action?) {
    openHintAction(context, action);
  }
}

/// Opens what [action] is about.
void openHintAction(BuildContext context, HintAction action) =>
    switch (action) {
      HintAction.invite => context.go(invitesPath),
      HintAction.access => context.go(accessPath),
      HintAction.addHousehold => context.read<HintHost?>()?.addHousehold?.call(
        context,
      ),
    };

/// One hint as a flat card: icon, title, text, its button if it has one,
/// and an X that hides it for good. Flat: only the X and the button are
/// tappable, so it does not stand off the page like a button.
class const HintCard({
  required final Hint hint,
  required final VoidCallback onAct,

  /// Null for no X (More → Tipps).
  final VoidCallback? onDismiss,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: HlSticker(
      depth: StickerDepth.flat,
      child: _HintContent(hint: hint, onAct: onAct, onDismiss: onDismiss),
    ),
  );
}

/// One hint as a flat callout whose tip points at the control it is about:
/// up at Anpassen, down at the microphone.
class const HintCallout({
  required final Hint hint,
  required final AxisDirection pointing,
  required final VoidCallback onAct,
  required final VoidCallback onDismiss,
  super.key,
}) extends StatelessWidget {
  /// From the callout's end edge to its tip's middle: under Anpassen, or
  /// over the microphone at the add bar's end.
  static const tipFromEnd = 52.0;

  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: t.surfaceRaised,
            shape: CalloutBorder(
              side: BorderSide(color: t.border, width: HlBorder.width),
              up: pointing == AxisDirection.up,
              tipFromEnd: tipFromEnd,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: pointing == AxisDirection.up ? CalloutBorder.tipHeight : 0,
              bottom: pointing == AxisDirection.down
                  ? CalloutBorder.tipHeight
                  : 0,
            ),
            child: _HintContent(hint: hint, onAct: onAct, onDismiss: onDismiss),
          ),
        ),
      ),
    );
  }
}

/// A rounded box with the 2 px contour and a small tip on its top ([up])
/// or bottom edge, [tipFromEnd] from its end edge.
@immutable
class const CalloutBorder({
  required final BorderSide side,
  required final bool up,
  required final double tipFromEnd,
}) extends ShapeBorder {
  static const tipHeight = 8.0;
  static const _tipHalfWidth = 9.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final box = Rect.fromLTRB(
      rect.left,
      rect.top + (up ? tipHeight : 0),
      rect.right,
      rect.bottom - (up ? 0 : tipHeight),
    );
    final x = textDirection == TextDirection.rtl
        ? rect.left + tipFromEnd
        : rect.right - tipFromEnd;
    final edge = up ? box.top : box.bottom;
    final point = up ? rect.top : rect.bottom;
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(HlRadius.m)),
      )
      ..moveTo(x - _tipHalfWidth, edge)
      ..lineTo(x, point)
      ..lineTo(x + _tipHalfWidth, edge)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outline = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left,
            rect.top + (up ? tipHeight : 0),
            rect.right,
            rect.bottom - (up ? 0 : tipHeight),
          ),
          const Radius.circular(HlRadius.m),
        ),
      ),
      getOuterPath(rect, textDirection: textDirection),
    );
    canvas.drawPath(outline, side.toPaint()..strokeJoin = StrokeJoin.round);
  }

  @override
  ShapeBorder scale(double t) =>
      CalloutBorder(side: side.scale(t), up: up, tipFromEnd: tipFromEnd);
}

class const _HintContent({
  required final Hint hint,
  required final VoidCallback onAct,
  required final VoidCallback? onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: HlSpace.s3,
        end: onDismiss == null ? HlSpace.s3 : 0,
        top: HlSpace.s1,
        bottom: HlSpace.s1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HlSpace.s3,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: HlSpace.s3),
            child: Icon(hint.icon, size: 22, color: t.brand),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HlSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: HlSpace.s1,
                children: [
                  MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: HlSpace.s1,
                      children: [
                        Text(
                          hint.title(l10n),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        Text(
                          hint.body(l10n),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: t.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hint.action case final action?)
                    Padding(
                      padding: const EdgeInsets.only(top: HlSpace.s2),
                      child: OutlinedButton(
                        key: ValueKey('tip-action-${hint.id.wire}'),
                        onPressed: onAct,
                        child: Text(action.label(l10n)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onDismiss case final dismiss?)
            IconButton(
              key: const ValueKey('tip-dismiss'),
              onPressed: dismiss,
              tooltip: l10n.tipDismiss,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: Icon(Icons.close, size: 20, color: t.textMuted),
            ),
        ],
      ),
    );
  }
}

/// „Erste Schritte“: what is done and what is open, an X that hides it for
/// the household. It takes the gesture card's place, whose sentence („Tippen
/// hakt ab · Halten bearbeitet“) is now the first shop's line.
class const ChecklistCard({
  required final Checklist checklist,
  required final VoidCallback onDismiss,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = HummlistColors.of(Theme.of(context).brightness);
    final done = checklist.entries.where((e) => e.done).length;
    final kind = (checklist.kind ?? HouseholdKind.other).name;
    return Semantics(
      container: true,
      child: HlSticker(
        depth: StickerDepth.flat,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: HlSpace.s3,
            top: HlSpace.s1,
            bottom: HlSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: HlSpace.s3,
                children: [
                  Icon(Icons.flag_outlined, size: 22, color: t.brand),
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.checklistTitle,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                            ),
                          ),
                          Text(
                            l10n.checklistProgress(
                              done,
                              checklist.entries.length,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('list-hint-dismiss'),
                    onPressed: onDismiss,
                    tooltip: l10n.checklistDismiss,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: Icon(Icons.close, size: 20, color: t.textMuted),
                  ),
                ],
              ),
              for (final (:step, done: isDone) in checklist.entries)
                _ChecklistRow(
                  key: ValueKey('checklist-${step.wire}'),
                  done: isDone,
                  title: switch (step) {
                    ChecklistStep.started =>
                      checklist.joined
                          ? l10n.checklistJoined
                          : l10n.checklistStarted,
                    ChecklistStep.invite => l10n.checklistInvite(kind),
                    ChecklistStep.firstShop => l10n.checklistShop,
                    ChecklistStep.assistant => l10n.checklistAssistant,
                  },
                  line: switch (step) {
                    ChecklistStep.started => null,
                    ChecklistStep.invite => l10n.checklistInviteBody(kind),
                    ChecklistStep.firstShop => l10n.listHint,
                    ChecklistStep.assistant => l10n.checklistAssistantBody,
                  },
                  action: switch (step) {
                    ChecklistStep.invite => (
                      l10n.hintInviteAction,
                      () => context.go(invitesPath),
                    ),
                    ChecklistStep.assistant => (
                      l10n.checklistOpen,
                      () => context.go(accessPath),
                    ),
                    ChecklistStep.started || ChecklistStep.firstShop => null,
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _ChecklistRow({
  required final bool done,
  required final String title,
  required final String? line,
  required final (String, VoidCallback)? action,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HummlistColors.of(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: HlSpace.s2,
        end: HlSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HlSpace.s3,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: HlSpace.s1),
            child: PointyHex(
              face: done ? t.mintSoft : t.surfaceSunken,
              size: 22,
              child: done ? Icon(Icons.check, size: 14, color: t.text) : null,
            ),
          ),
          // Title and line are nodes of their own, not parts of the card's
          // label: the web finds the line by its text, as it found the
          // gesture card's sentence.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  child: Text(
                    title,
                    semanticsLabel: done
                        ? AppLocalizations.of(context).checklistDone(title)
                        : null,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: done ? FontWeight.w400 : FontWeight.w600,
                      color: done ? t.textMuted : t.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (line case final line? when !done)
                  Semantics(
                    container: true,
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: t.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if ((done, action) case (false, (final label, final onPressed)?))
            OutlinedButton(onPressed: onPressed, child: Text(label)),
        ],
      ),
    );
  }
}
