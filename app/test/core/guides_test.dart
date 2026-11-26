import 'package:family_groceries/core/deep_links.dart';
import 'package:family_groceries/core/guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Job 462: these open in the system browser. A claimed one would come
  /// straight back to the app on Android, which has no page for it.
  test('the site pages the app opens in the browser are not claimed', () {
    for (final language in ['de', 'en']) {
      for (final url in [
        imprintUrl(language),
        privacyPolicyUrl(language),
        termsUrl(language),
        supportUrl(language),
        changelogUrl(language, '1.4.1'),
      ]) {
        expect(LinkHost.site.hosts, contains(url.host), reason: '$url');
        expect(claims(LinkHost.site, url.path), isFalse, reason: '$url');
      }
    }
  });
}
