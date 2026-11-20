import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = Household(id: 'home', name: 'Zuhause', isDefault: true);
  const work = Household(id: 'work', name: 'Büro');
  const inHome = InHousehold('peter', home, [home, work]);
  const inWork = InHousehold('peter', work, [home, work]);

  group('a join or household switch holds the rating prompt back', () {
    test('a switch to another household is one', () {
      expect(joinedOrSwitched(inHome, inWork), isTrue);
    });

    test('a first household, joined or made, is one', () {
      expect(joinedOrSwitched(const NeedsHousehold('peter'), inHome), isTrue);
    });

    test('the same household refreshed is none', () {
      expect(
        joinedOrSwitched(inHome, const InHousehold('peter', home, [home])),
        isFalse,
      );
    });

    test('a start or a sign-in is none', () {
      expect(joinedOrSwitched(const SessionLoading(), inHome), isFalse);
      expect(joinedOrSwitched(const SignedOut(), inHome), isFalse);
    });

    test('leaving every household is none', () {
      expect(joinedOrSwitched(inHome, const NeedsHousehold('peter')), isFalse);
    });
  });

  group('a sent bug note holds it back', () {
    const sending = FeedbackState(
      message: 'Absturz',
      category: FeedbackCategory.bug,
      status: FeedbackStatus.sending,
    );

    test('once, when it is sent', () {
      final sent = sending.copyWith(status: FeedbackStatus.sent);
      expect(bugNoteSent(sending, sent), isTrue);
      expect(bugNoteSent(sent, sent), isFalse);
    });

    test('an idea or a failed send is none', () {
      final idea = sending.copyWith(category: () => FeedbackCategory.idea);
      expect(
        bugNoteSent(idea, idea.copyWith(status: FeedbackStatus.sent)),
        isFalse,
      );
      expect(
        bugNoteSent(sending, sending.copyWith(status: FeedbackStatus.failed)),
        isFalse,
      );
    });
  });
}
