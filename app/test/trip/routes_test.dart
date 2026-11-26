import 'package:family_groceries/core/screen_names.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
    Household(id: 'home', name: 'Zuhause'),
  ]);

  test('a trip summary is a screen of its own, without its id', () {
    for (final path in [tripSummaryPath('abc'), historyTripPath('abc')]) {
      expect(screenNameOf(Uri.parse(path)), 'trip_summary');
    }
    expect(screenNames, contains('trip_summary'));
    expect(screenNameOf(Uri.parse('/trip')), 'other');
  });

  test('signed in, a trip summary stays where it is', () {
    for (final path in [tripSummaryPath('abc'), historyTripPath('abc')]) {
      expect(authRedirect(home, Uri.parse(path)), isNull);
    }
  });

  // Job 462: a trip link opens the app; sign-in continues there.
  test('signed out, a trip summary link waits for sign-in', () {
    expect(
      authRedirect(const SignedOut(), Uri.parse(tripSummaryPath('abc'))),
      '/login?next=%2Ftrip%2Fabc',
    );
  });
}
