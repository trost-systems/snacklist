import 'package:family_groceries/guides/guide_link.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where [href] on the Alexa guide leads, in words.
String? leads(String href) =>
    switch (resolveGuideLink(guidePage('/de/anleitungen/alexa'), href)) {
      OpenGuide(:final location) => 'guide $location',
      OpenScreen(:final location) => 'screen $location',
      ScrollTo(:final fragment) => 'scroll "$fragment"',
      OpenOutside(:final url) => 'outside $url',
      null => null,
    };

void main() {
  const cases = {
    // Guides and the guide lists stay in the app.
    'https://snacklist.app/en/guides/claude': 'guide /en/guides/claude',
    'https://snacklist.app/en/guides': 'guide /en/guides',
    'https://www.snacklist.app/de/anleitungen/': 'guide /de/anleitungen',
    '/de/anleitungen/siri-kurzbefehl': 'guide /de/anleitungen/siri-kurzbefehl',
    'siri-kurzbefehl': 'guide /de/anleitungen/siri-kurzbefehl',
    'https://snacklist.app/en/guides/claude.md': 'guide /en/guides/claude',
    'https://snacklist.app/en/guides/claude?x=1#step':
        'guide /en/guides/claude',
    // This page: a section of it, or nothing to do.
    'https://snacklist.app/de/anleitungen/alexa#snacklist-erreichen':
        'scroll "snacklist-erreichen"',
    '#snacklist-erreichen': 'scroll "snacklist-erreichen"',
    'https://snacklist.app/de/anleitungen/alexa': 'scroll ""',
    // The app's own screens go there.
    'https://app.snacklist.app/more/invites': 'screen /more/invites',
    'https://app.snacklist.app/join/ABCD2345': 'screen /join/ABCD2345',
    'https://app.snacklist.app/more/lifetime?from=guide':
        'screen /more/lifetime?from=guide',
    'https://app.snacklist.app/history': 'screen /history',
    // Everything unclaimed opens the browser, which keeps it.
    'https://claude.ai': 'outside https://claude.ai',
    'https://snacklist.app/datenschutz':
        'outside https://snacklist.app/datenschutz',
    'https://snacklist.app/de/changelog':
        'outside https://snacklist.app/de/changelog',
    'https://app.snacklist.app/': 'outside https://app.snacklist.app/',
    'https://app.snacklist.app/login':
        'outside https://app.snacklist.app/login',
    'https://app.snacklist.app/de/anleitungen/alexa':
        'outside https://app.snacklist.app/de/anleitungen/alexa',
    'https://evil.example/de/anleitungen/alexa':
        'outside https://evil.example/de/anleitungen/alexa',
    'https://snacklist.app.evil.example/en/guides':
        'outside https://snacklist.app.evil.example/en/guides',
    'mailto:hallo@snacklist.app': 'outside mailto:hallo@snacklist.app',
    'http://[::1': null,
  };
  for (final MapEntry(key: href, value: target) in cases.entries) {
    test('$href: ${target ?? 'no link'}', () {
      expect(leads(href), target);
    });
  }
}
