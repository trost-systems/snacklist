import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenNameOf', () {
    const cases = {
      '/': 'list',
      '/?invite=ABCD2345': 'list',
      '/more': 'more',
      '/edit': 'stores',
      '/edit/none': 'stores',
      '/edit/3f0c-Hafermilch': 'stores',
      '/more/usage-data': 'usage_data',
      // Gone in job 85: the switch moved, the legal rows sit on More.
      '/more/privacy': 'other',
      '/more/access': 'access',
      '/more/account': 'account',
      '/more/settings': 'settings',
      '/more/lifetime': 'lifetime',
      '/more/household': 'household',
      '/households/new': 'new_household',
      '/more/settings/language': 'language',
      '/settings': 'access',
      '/settings?section=account': 'account',
      '/settings?section=Milch': 'access',
      '/login?invite=ABCD2345': 'login',
      '/welcome': 'welcome',
      '/analytics-consent': 'analytics_consent',
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

    test('list, then More: the list (AC3)', () {
      expect(visited(['/', '/more']).feedbackScreen, 'list');
    });

    test('More pages in between do not count', () {
      expect(
        visited(['/', '/more', '/more/account', '/more']).feedbackScreen,
        'list',
      );
      expect(
        visited(['/', '/more', '/more/access', '/more']).feedbackScreen,
        'list',
      );
    });

    test('opened beside a More page (wide): that page', () {
      expect(visited(['/', '/more/account']).feedbackScreen, 'account');
    });

    test('a join link before More: join, without the code', () {
      expect(visited(['/join/ABCD2345', '/', '/more']).feedbackScreen, 'list');
      expect(visited(['/join/ABCD2345', '/more']).feedbackScreen, 'join');
    });

    test('straight to More (a reload there): more', () {
      expect(visited(['/more']).feedbackScreen, 'more');
    });
  });
}
