import 'package:family_groceries/core/screen_names.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenNameOf', () {
    const cases = {
      '/': 'list',
      '/?invite=ABCD2345': 'list',
      '/more': 'more',
      '/history': 'history',
      '/edit': 'stores',
      '/edit/none': 'stores',
      '/edit/3f0c-Hafermilch': 'stores',
      '/more/usage-data': 'usage_data',
      '/more/tips': 'tips',
      // Gone in job 85: the switch moved, the legal rows sit on More.
      '/more/privacy': 'other',
      '/more/access': 'access',
      '/more/account': 'account',
      '/more/settings': 'settings',
      '/more/lifetime': 'lifetime',
      '/more/household': 'household',
      '/more/feedback': 'feedback',
      '/more/feedback/0b8c1f0e-1d2a-4c55-9e1f-3a4b5c6d7e8f': 'feedback_note',
      '/more/feedback/a/b': 'other',
      '/households/new': 'new_household',
      '/more/settings/language': 'language',
      '/settings': 'access',
      '/settings?section=account': 'account',
      '/settings?section=Milch': 'access',
      '/login?invite=ABCD2345': 'login',
      '/welcome': 'welcome',
      '/analytics-consent': 'analytics_consent',
      '/your-name?invite=ABCD2345': 'your_name',
      '/oauth/consent?authorization_id=abc': 'oauth_consent',
      '/join/ABCD2345': 'join',
      '/join/Milch%20und%20Brot': 'join',
      '/Hafermilch': 'other',
      '/more/Hafermilch': 'other',
    };
    for (final MapEntry(key: location, value: name) in cases.entries) {
      test('$location is $name', () {
        expect(screenNameOf(Uri.parse(location)), name);
      });
    }

    test('every name fits the database and is in screenNames', () {
      final pattern = RegExp(r'^[a-z][a-z_]{0,39}$');
      for (final name in {...cases.values, ...screenNames}) {
        expect(screenNames, contains(name));
        expect(pattern.hasMatch(name), isTrue, reason: name);
      }
    });

    test('a path parameter never reaches the name', () {
      for (final code in ['ABCD2345', 'abcd', 'list', 'more_x']) {
        expect(screenNameOf(Uri.parse('/join/$code')), 'join');
      }
    });
  });

  group('ScreenTracker', () {
    ScreenTracker visited(List<String> locations) {
      final tracker = ScreenTracker();
      for (final location in locations) {
        tracker.visit(Uri.parse(location));
      }
      return tracker;
    }

    test('the screen on show, More included', () {
      expect(visited(['/']).current, 'list');
      expect(visited(['/', '/more']).current, 'more');
      expect(visited(['/', '/more', '/more/account']).current, 'account');
    });

    test('a join link: join, without the code', () {
      expect(visited(['/join/ABCD2345']).current, 'join');
    });
  });
}
