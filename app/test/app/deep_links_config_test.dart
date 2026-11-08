import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/app/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 22 and 66: the app URL's paths in [appLinks] open the installed app.
/// Five files must agree with that table, and a mismatch only shows on a
/// device: the iOS entitlement, Android's verified intent filter, the two
/// files the web build serves under `/.well-known/`, and Vercel's rules
/// that serve them as JSON instead of the app's index.html.
void main() {
  final appUrl = Uri.parse(
    (jsonDecode(File('config/auth.json').readAsStringSync())
            as Map<String, Object?>)['APP_URL']!
        as String,
  );
  const teamId = 'VCZSHMZY25';

  String bundleId() => RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
      .allMatches(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      )
      .map((m) => m[1]!)
      .firstWhere((id) => !id.endsWith('Tests'));

  String applicationId() => RegExp(r'applicationId = "([\w.]+)"')
      .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())![1]!;

  test('the iOS app claims applinks for the app URL', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(entitlements, contains('com.apple.developer.associated-domains'));
    expect(entitlements, contains('<string>applinks:${appUrl.host}</string>'));
    // Sign in with Apple stays.
    expect(entitlements, contains('com.apple.developer.applesignin'));
  });

  test('apple-app-site-association names the app and the table', () {
    final aasa = jsonDecode(
      File('web/.well-known/apple-app-site-association').readAsStringSync(),
    ) as Map<String, Object?>;
    final details =
        ((aasa['applinks']! as Map)['details']! as List).single as Map;
    expect(details['appIDs'], ['$teamId.${bundleId()}']);
    expect((details['components']! as List).map((c) => (c as Map)['/']), [
      for (final link in appLinks)
        if (link.prefix) '${link.path}*' else link.path,
    ]);
  });

  test('Android verifies an https filter for the table on the app URL', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final filter = RegExp(
      r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
    ).firstMatch(manifest)![1]!;
    expect(filter, contains('android.intent.action.VIEW'));
    expect(filter, contains('android.intent.category.BROWSABLE'));
    expect(filter, contains('android:scheme="https"'));
    expect(filter, contains('android:host="${appUrl.host}"'));
    final paths = RegExp('android:(path|pathPrefix)="([^"]*)"')
        .allMatches(filter)
        .map((m) => (path: m[2]!, prefix: m[1] == 'pathPrefix'));
    expect(paths, appLinks);
    // The sign-in callback keeps its own filter.
    expect(
      manifest,
      contains(
        'android:scheme="com.hummlist.app" android:host="login-callback"',
      ),
    );
  });

  test(
    'assetlinks.json names the package and the signing keys of RELEASE.md',
    () {
      final links =
          (jsonDecode(
                File('web/.well-known/assetlinks.json').readAsStringSync(),
              ) as List).single
              as Map;
      final target = links['target']! as Map;
      expect(links['relation'], ['delegate_permission/common.handle_all_urls']);
      expect(target['package_name'], applicationId());
      final fingerprints = (target['sha256_cert_fingerprints']! as List)
          .cast<String>();
      final sha256 = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
      expect(fingerprints, everyElement(matches(sha256)));
      // Play App Signing signs what testers install; the upload key what CI
      // builds. Both are in RELEASE.md's "Android signing" table.
      final release = File('../docs/RELEASE.md').readAsStringSync();
      final table = RegExp('`((?:[0-9A-F]{2}:){31}[0-9A-F]{2})`')
          .allMatches(release)
          .map((m) => m[1])
          .toSet();
      expect(fingerprints, hasLength(2));
      expect(table, containsAll(fingerprints));
    },
  );

  test('Vercel serves both files as JSON, not as the app', () {
    final vercel = jsonDecode(File('../vercel.json').readAsStringSync()) as Map;
    final rewrites = (vercel['rewrites']! as List).cast<Map<String, Object?>>();
    final rewrite =
        rewrites.singleWhere(
              (r) => r['destination'] == '/index.html',
            )['source']!
            as String;
    final spa = RegExp('^$rewrite\$');
    // Without the app an invite link opens the static join page (job 169b),
    // which Vercel rewrites before the web app.
    expect(
      rewrites.indexWhere((r) => r['destination'] == '/join/index.html'),
      lessThan(rewrites.indexWhere((r) => r['destination'] == '/index.html')),
    );
    // Every other link opens the web app.
    for (final link in appLinks.where((l) => !l.path.startsWith('/join'))) {
      final path = link.prefix
          ? '${link.path}4f9c2e1a-7b3d-4c8e-9a6f-2d1e0b5c8a7f'
          : link.path;
      expect(spa.hasMatch(path), isTrue, reason: path);
    }
    expect(spa.hasMatch('/.well-known/apple-app-site-association'), isFalse);
    expect(spa.hasMatch('/.well-known/assetlinks.json'), isFalse);
    final headers = (vercel['headers']! as List).cast<Map<String, Object?>>();
    final aasa = headers.singleWhere(
      (h) => h['source'] == '/.well-known/apple-app-site-association',
    );
    expect(aasa['headers'], [
      {'key': 'Content-Type', 'value': 'application/json'},
    ]);
  });
}
