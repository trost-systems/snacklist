import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';
import 'guided_start_test.dart' show answered;

final _l10n = lookupAppLocalizations(const Locale('de'));

final _bar = find.byType(LinearProgressIndicator);
final _title = find.descendant(
  of: find.byType(AppBar),
  matching: find.textContaining('Schritt'),
);
final _next = find.byKey(const ValueKey('onboarding-next'));

double _barValue(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(_bar).value ?? 0;

/// How opaque [finder] is drawn: the product of the fades above it.
double _opacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (final e
      in find
          .ancestor(of: finder, matching: find.byType(FadeTransition))
          .evaluate()) {
    opacity *= (e.widget as FadeTransition).opacity.value;
  }
  for (final e
      in find.ancestor(of: finder, matching: find.byType(Opacity)).evaluate()) {
    opacity *= (e.widget as Opacity).opacity;
  }
  return opacity;
}

/// The chrome that must not move: the bar and the app bar's title.
({Rect bar, Rect title}) _chrome(WidgetTester tester) =>
    (bar: tester.getRect(_bar), title: tester.getRect(_title));

void _expectChromeStill(
  WidgetTester tester,
  ({Rect bar, Rect title}) before,
  String moment,
) {
  final now = _chrome(tester);
  expect(now.bar.top, before.bar.top, reason: 'bar top, $moment');
  expect(now.bar.left, before.bar.left, reason: 'bar left, $moment');
  expect(now.bar.width, before.bar.width, reason: 'bar width, $moment');
  expect(now.title, before.title, reason: 'title, $moment');
}

/// Runs a step change with [act] and checks the chrome stays still, the
/// body slides in from the side [forward] says, and every „Weiter“ sits
/// where it rests on its own step.
Future<void> _change(
  WidgetTester tester, {
  required Future<void> Function() act,
  required String incomingHeading,
  required bool forward,
}) async {
  final before = _chrome(tester);
  final valueBefore = _barValue(tester);
  final nextBefore = _next.evaluate().isEmpty ? null : tester.getRect(_next);

  await act();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  _expectChromeStill(tester, before, 'mid-animation');
  final heading = find.text(incomingHeading);
  final headingMid = tester.getRect(heading).left;
  final nextsMid = [
    for (var i = 0; i < _next.evaluate().length; i++)
      tester.getRect(_next.at(i)),
  ];

  await tester.pumpAndSettle();
  _expectChromeStill(tester, before, 'after');
  final headingAfter = tester.getRect(heading).left;
  if (forward) {
    expect(headingMid, greaterThan(headingAfter), reason: 'in from the right');
    expect(_barValue(tester), greaterThan(valueBefore));
  } else {
    expect(headingMid, lessThan(headingAfter), reason: 'in from the left');
    expect(_barValue(tester), lessThan(valueBefore));
  }
  final nextAfter = _next.evaluate().isEmpty ? null : tester.getRect(_next);
  expect(nextsMid, isNotEmpty);
  for (final rect in nextsMid) {
    expect(
      rect,
      anyOf([?nextBefore, ?nextAfter].map(equals).toList()),
      reason: 'Weiter mid-animation at its resting place',
    );
  }
}

void main() {
  testWidgets('the app bar, the bar and the docked Weiter stay still; only '
      'the body slides, mirrored going back', (tester) async {
    await pumpOnboarding(
      tester,
      location: '/start/who',
      draft: answered(OnboardingStep.who),
    );
    await _change(
      tester,
      act: () => tester.tap(_next),
      incomingHeading: _l10n.nameTitle,
      forward: true,
    );
    await _change(
      tester,
      act: () => tester.tap(find.byType(BackButton)),
      incomingHeading: _l10n.whoTitle,
      forward: false,
    );
  });

  testWidgets('need to account: the chrome stays, the bar advances', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      location: '/start/need',
      draft: answered(OnboardingStep.need),
      session: const SignedOut(),
    );
    await _change(
      tester,
      act: () => tester.tap(_next),
      incomingHeading: _l10n.accountStepTitle,
      forward: true,
    );
  });

  testWidgets('Weiter closes the keyboard in the frame the step changes', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      location: '/start/name',
      draft: answered(OnboardingStep.name),
    );
    final field = find.byKey(const ValueKey('household-name'));
    bool focused() => tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;
    await tester.tap(field);
    await tester.pump();
    expect(focused(), isTrue);

    await tester.tap(_next);
    await tester.pump();
    expect(find.text(_l10n.storesStepTitle), findsOneWidget);
    expect(focused(), isFalse);
    await tester.pumpAndSettle();
  });

  for (final (flag, set) in [
    (
      'disableAnimations',
      (WidgetTester tester) =>
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true),
    ),
    (
      'reduceMotion',
      (WidgetTester tester) =>
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true),
    ),
  ]) {
    testWidgets('$flag: a 120 ms fade, nothing slides', (tester) async {
      set(tester);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpOnboarding(
        tester,
        location: '/start/who',
        draft: answered(OnboardingStep.who),
      );
      final before = _chrome(tester);
      final valueBefore = _barValue(tester);
      final outgoing = find.text(_l10n.whoTitle);
      final incoming = find.text(_l10n.nameTitle);
      final outgoingRest = tester.getRect(outgoing);

      await tester.tap(_next);
      await tester.pump();
      final incomingStart = tester.getRect(incoming);
      for (final ms in [0, 30, 60, 90, 120]) {
        await tester.pump(Duration(milliseconds: ms == 0 ? 0 : 30));
        final at = 'at $ms ms';
        expect(tester.getRect(outgoing), outgoingRest, reason: at);
        expect(tester.getRect(incoming), incomingStart, reason: at);
        _expectChromeStill(tester, before, at);
        if (ms == 60) {
          expect(_opacity(tester, incoming), inExclusiveRange(0, 1));
          expect(_opacity(tester, outgoing), inExclusiveRange(0, 1));
        }
      }
      expect(_opacity(tester, incoming), 1, reason: 'in at 120 ms');
      expect(_opacity(tester, outgoing), 0, reason: 'out at 120 ms');

      await tester.pump(const Duration(milliseconds: 16));
      expect(outgoing, findsNothing, reason: 'gone a frame later');
      expect(tester.getRect(incoming), incomingStart);
      expect(_barValue(tester), greaterThan(valueBefore));
      _expectChromeStill(tester, before, 'after');
      expect(tester.hasRunningAnimations, isFalse);
    });
  }

  testWidgets('during a change screen readers find one Weiter', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnboarding(
      tester,
      location: '/start/who',
      draft: answered(OnboardingStep.who),
    );
    await tester.tap(_next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_next, findsNWidgets(2), reason: 'both steps on screen');
    expect(find.semantics.byLabel(_l10n.onboardingNext), findsOne);
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
