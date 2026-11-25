import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';
import 'guided_start_test.dart' show answered;

const _steps = [
  OnboardingStep.usage,
  OnboardingStep.who,
  OnboardingStep.name,
  OnboardingStep.stores,
  OnboardingStep.need,
  OnboardingStep.account,
  OnboardingStep.invite,
];

Future<void> _show(WidgetTester tester, OnboardingStep step) async {
  if (step == OnboardingStep.usage) {
    await pumpOnboarding(
      tester,
      location: '/',
      session: const SignedOut(),
      consentAnswered: false,
    );
    await tapKey(tester, 'start-go');
  } else {
    await pumpOnboarding(
      tester,
      location: '/start/${step.name}',
      draft: answered(step),
    );
  }
}

void main() {
  testWidgets('the bar is in the same place on every counted step, short or '
      'tall', (tester) async {
    final bars = <OnboardingStep, Rect>{};
    final lists = <OnboardingStep, double>{};
    for (final step in _steps) {
      await _show(tester, step);
      bars[step] = tester.getRect(find.byType(LinearProgressIndicator));
      final list = find.byKey(ValueKey('onboarding-${step.name}'));
      if (list.evaluate().isNotEmpty) {
        lists[step] = tester.getSize(list.first).height;
      }
    }
    final first = bars[_steps.first]!;
    for (final MapEntry(:key, :value) in bars.entries) {
      expect(value.top, first.top, reason: '$key');
      expect(value.left, first.left, reason: '$key');
      expect(value.width, first.width, reason: '$key');
    }
    // The steps differ in height, which moved the bar when it sat in the
    // centred list.
    expect(lists.values.toSet().length, greaterThan(1));
  });
}
