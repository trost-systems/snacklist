import 'dart:async';

import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The steps the progress counts: every screen of the guided start a user
/// can see, in order. They share one page, [OnboardingSteps].
const countedSteps = [
  OnboardingStep.usage,
  OnboardingStep.who,
  OnboardingStep.name,
  OnboardingStep.stores,
  OnboardingStep.need,
  OnboardingStep.account,
  OnboardingStep.invite,
];

/// The app bar of [step]: the step its back button returns to (none on the
/// first question), and whether it has the X that leaves the guided start
/// (the invite step has „Später“ instead).
({OnboardingStep? back, bool exit}) _chrome(OnboardingStep step) =>
    switch (step) {
      OnboardingStep.usage || OnboardingStep.who => (back: null, exit: true),
      OnboardingStep.name => (back: OnboardingStep.who, exit: true),
      OnboardingStep.stores => (back: OnboardingStep.name, exit: true),
      OnboardingStep.need => (back: OnboardingStep.stores, exit: true),
      OnboardingStep.account => (back: OnboardingStep.need, exit: true),
      OnboardingStep.invite => (back: null, exit: false),
      // Pages of their own, never in the shell.
      OnboardingStep.join || OnboardingStep.setup => (back: null, exit: true),
    };

/// The counted steps' one page (job 454): the app bar titled with the
/// progress („Schritt 3 von 7“, which always fits the bar), the bar under
/// it, and the step's [body]. Only the body changes between steps: the old
/// one slides out and fades as the new one comes in, from the right going
/// on and from the left going back; a 120 ms fade instead with reduced
/// motion.
class const OnboardingSteps({
  required final OnboardingStep step,

  /// The screen of a step, an [OnboardingStepLayout].
  required final Widget Function(OnboardingStep) body,
  super.key,
}) extends StatefulWidget {
  @override
  State<OnboardingSteps> createState() => _OnboardingStepsState();
}

class _OnboardingStepsState()
    extends State<OnboardingSteps>
    with SingleTickerProviderStateMixin {
  // Preserve: with the platform's reduced motion a normal controller would
  // run the 120 ms fade at 5 %.
  late final _transition =
      AnimationController(
        vsync: this,
        value: 1,
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _outgoing = null);
        }
      });

  /// Counts step changes: every visit of a step is a fresh screen, as a new
  /// route was.
  var _visit = 0;
  ({OnboardingStep step, int visit})? _outgoing;
  var _back = false;
  var _reduced = false;

  @override
  void didUpdateWidget(OnboardingSteps old) {
    super.didUpdateWidget(old);
    if (old.step == widget.step) {
      return;
    }
    // The keyboard closes as the step leaves, not after (OB-Q1).
    FocusManager.instance.primaryFocus?.unfocus();
    _outgoing = (step: old.step, visit: _visit);
    _visit++;
    _back = countedSteps.indexOf(widget.step) < countedSteps.indexOf(old.step);
    _reduced = _reduceMotion(context);
    _transition.duration = Duration(milliseconds: _reduced ? 120 : 300);
    _transition.forward(from: 0);
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  Widget _layer(
    ({OnboardingStep step, int visit}) layer, {
    required bool incoming,
  }) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final distance = 28.0 * (_back ? -1 : 1) * (rtl ? -1 : 1);
    final standard = _transition.drive(CurveTween(curve: HlEasing.standard));
    final (Animation<double> opacity, Animation<double> x) = switch ((
      incoming,
      _reduced,
    )) {
      (true, false) => (
        _transition.drive(
          CurveTween(curve: const Interval(0.3, 1, curve: Cubic(0, 0, 0, 1))),
        ),
        standard.drive(Tween<double>(begin: distance, end: 0)),
      ),
      (false, false) => (
        _transition.drive(
          Tween<double>(begin: 1, end: 0).chain(
            CurveTween(
              curve: const Interval(0, 0.3, curve: Cubic(0.3, 0, 1, 1)),
            ),
          ),
        ),
        standard.drive(Tween<double>(begin: 0, end: -distance)),
      ),
      (true, true) => (_transition, const AlwaysStoppedAnimation<double>(0)),
      (false, true) => (
        ReverseAnimation(_transition),
        const AlwaysStoppedAnimation<double>(0),
      ),
    };
    // The same widgets in and out, so the outgoing screen keeps its state.
    return KeyedSubtree(
      key: ValueKey(layer),
      child: IgnorePointer(
        ignoring: !incoming,
        // One „Weiter“ for screen readers. A new route scope, as a new page
        // gave: the web focuses the new step's heading, the apps announce
        // the change.
        child: ExcludeSemantics(
          excluding: !incoming,
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: FadeTransition(
              opacity: opacity,
              alwaysIncludeSemantics: true,
              child: _BodyOffset(x: x, child: widget.body(layer.step)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (:back, :exit) = _chrome(widget.step);
    void goBack() {
      if (back != null) {
        // Before the step changes: the arrow stays on screen, and a focus
        // it still holds when the new step's route scope appears keeps the
        // web from focusing the step's heading.
        FocusManager.instance.primaryFocus?.unfocus();
        context.read<OnboardingCubit>().at(back);
      }
    }

    return PopScope(
      // Android's back without a step to return to: signed out to the
      // first screen, the route under every step. Signed in, that screen
      // („Schon ein Konto? Anmelden“) is not theirs, and a pop runs no
      // redirect, so back stays on the step.
      canPop: back == null && context.watch<SessionCubit>().state is SignedOut,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(onboardingProgressText(context, widget.step)),
          automaticallyImplyLeading: false,
          // The slot stays when there is no back, so the title does not
          // move between steps.
          leading: back == null
              ? const SizedBox.shrink()
              : BackButton(onPressed: goBack),
          actions: [if (exit) const OnboardingExitButton()],
        ),
        body: Column(
          children: [
            _PinnedHeader(OnboardingProgress(step: widget.step)),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_outgoing case final outgoing?)
                    _layer(outgoing, incoming: false),
                  _layer((step: widget.step, visit: _visit), incoming: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.reduceMotionOf(context);

/// How far a step's body is moved sideways, for [OnboardingStepLayout].
class const _BodyOffset({
  required final Animation<double> x,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_BodyOffset old) => old.x != x;
}

/// [child] under the app bar, in the steps' 420-wide column and side
/// padding: the same place on every step, whatever the body's height.
class const _PinnedHeader(final Widget child) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: child,
      ),
    ),
  );
}

/// A counted step's screen: its [body], which slides between steps, and
/// the [footer] docked under it (the step's buttons), which only fades and
/// stays above the keyboard.
class const OnboardingStepLayout({
  required final Widget body,
  final Widget? footer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final x =
        context.dependOnInheritedWidgetOfExactType<_BodyOffset>()?.x ??
        const AlwaysStoppedAnimation<double>(0);
    return Column(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: x,
            builder: (_, body) =>
                Transform.translate(offset: Offset(x.value, 0), child: body),
            child: body,
          ),
        ),
        if (footer case final footer?)
          SafeArea(
            top: false,
            child: Center(
              child: SizedBox(
                width: 420,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: footer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One counted step's [OnboardingStepLayout]: the step's question as the
/// heading (it wraps) over [children] in one centred list, at most 420
/// wide, and the [footer] docked under it.
class const OnboardingStepPage({
  required final OnboardingStep step,
  required final List<Widget> children,

  /// The question; none where [children] bring their own heading.
  final String? title,
  final Widget? footer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => OnboardingStepLayout(
    footer: footer,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          key: ValueKey('onboarding-${step.name}'),
          // Clear of the home indicator when no footer is.
          padding: const EdgeInsets.all(24).add(
            EdgeInsets.only(
              bottom: footer == null ? MediaQuery.paddingOf(context).bottom : 0,
            ),
          ),
          shrinkWrap: true,
          children: [
            if (title case final title?) ...[
              OnboardingHeading(title),
              const SizedBox(height: HlSpace.s3),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// „Schritt 3 von 7“.
String onboardingProgressText(BuildContext context, OnboardingStep step) =>
    AppLocalizations.of(
      context,
    ).onboardingProgress(countedSteps.indexOf(step) + 1, countedSteps.length);

/// The bar under „Schritt 3 von 7“ (the app bar's title, which screen
/// readers read). It moves to a new step's value without overshoot.
class const OnboardingProgress({required final OnboardingStep step, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final reduced = _reduceMotion(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          end: (countedSteps.indexOf(step) + 1) / countedSteps.length,
        ),
        duration: Duration(milliseconds: reduced ? 120 : 300),
        curve: reduced ? Curves.linear : HlEasing.standard,
        builder: (_, value, _) => LinearProgressIndicator(
          value: value,
          borderRadius: BorderRadius.circular(HlRadius.s),
        ),
      ),
    );
  }
}

/// A step's question, the page's heading.
class const OnboardingHeading(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// What the leave dialog chose.
enum _Leave() {
  signIn,
  signOut,
  discard,
}

/// The X on every step of the guided start: leave it to sign in instead
/// (signed out; the progress stays on the device), sign out (signed in),
/// or drop the progress.
class const OnboardingExitButton({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('onboarding-exit'),
    tooltip: AppLocalizations.of(context).onboardingExit,
    icon: const Icon(Icons.close),
    onPressed: () => unawaited(_leave(context)),
  );

  Future<void> _leave(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final session = context.read<SessionCubit>();
    final onboarding = context.read<OnboardingCubit>();
    final signedIn = session.state is! SignedOut;
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const ValueKey('onboarding-exit-dialog'),
        title: Text(l10n.onboardingExitTitle),
        content: Text(l10n.onboardingExitBody),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: HlSpace.s2,
        actions: [
          TextButton(
            key: const ValueKey('onboarding-exit-discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialog).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, _Leave.discard),
            child: Text(l10n.onboardingExitDiscard),
          ),
          if (signedIn)
            TextButton(
              key: const ValueKey('onboarding-exit-sign-out'),
              onPressed: () => Navigator.pop(dialog, _Leave.signOut),
              child: Text(l10n.signOut),
            )
          else
            TextButton(
              key: const ValueKey('onboarding-exit-sign-in'),
              onPressed: () => Navigator.pop(dialog, _Leave.signIn),
              child: Text(l10n.onboardingExitLogIn),
            ),
          FilledButton.tonal(
            key: const ValueKey('onboarding-exit-stay'),
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.onboardingExitStay),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case _Leave.signIn:
        goToSignIn(context);
      case _Leave.signOut:
        await session.signOut();
      case _Leave.discard:
        onboarding.discard();
      case null:
        break;
    }
  }
}
