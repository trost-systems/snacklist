import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 22, 66 and 462: the links in [appLinks] open the installed app.
/// Several files must agree with that table, and a mismatch only shows on a
/// device: the iOS entitlement, Android's verified intent filters, the two
/// files each host serves under `/.well-known/` (the web app's from
/// `web/`, the site's from `site/public/`), and Vercel's rules that serve
/// the web app's as JSON instead of the app's index.html.
void main() {
  final appUrl = Uri.parse(
    (jsonDecode(File('config/auth.json').readAsStringSync())
            as Map<String, Object?>)['APP_URL']!
        as String,
  );
  const teamId = 'VCZSHMZY25';
  // Job 174: the Hummlist build stays installed until Snacklist replaces it,
  // so its app id stays next to Snacklist's on the app host. The site is
  // Snacklist's only.
  const hummlistId = 'com.hummlist.app';

  test('the app URL is a host of the app links', () {
    expect(LinkHost.app.hosts, contains(appUrl.host));
  });

  String bundleId() => RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
      .allMatches(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      )
      .map((m) => m[1]!)
      .firstWhere((id) => !id.endsWith('Tests'));

  String applicationId() => RegExp(r'applicationId = "([\w.]+)"')
      .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())![1]!;

  List<AppLink> rowsOf(LinkHost host) => [
    for (final link in appLinks)
      if (link.host == host) link,
  ];

  test('the iOS app claims applinks for every host, and only those', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(entitlements, contains('com.apple.developer.associated-domains'));
    final claimed = RegExp('<string>applinks:([^<]+)</string>')
        .allMatches(entitlements)
        .map((m) => m[1])
        .toSet();
    expect(claimed, {for (final host in LinkHost.values) ...host.hosts});
    // Sign in with Apple stays.
    expect(entitlements, contains('com.apple.developer.applesignin'));
  });

  Map<Object?, Object?> aasaDetails(String path) {
    final aasa =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    return ((aasa['applinks']! as Map)['details']! as List).single as Map;
  }

  List<String> components(List<AppLink> rows) => [
    for (final link in rows)
      if (link.prefix) '${link.path}*' else link.path,
  ];

  test("the web app's apple-app-site-association: both apps, its rows", () {
    final details = aasaDetails('web/.well-known/apple-app-site-association');
    expect(details['appIDs'], ['$teamId.${bundleId()}', '$teamId.$hummlistId']);
    expect(
      (details['components']! as List).map((c) => (c as Map)['/']),
      components(rowsOf(LinkHost.app)),
    );
  });

  test("the site's apple-app-site-association: Snacklist, the guides", () {
    final details = aasaDetails(
      '../site/public/.well-known/apple-app-site-association',
    );
    expect(details['appIDs'], ['$teamId.${bundleId()}']);
    expect(
      (details['components']! as List).map((c) => (c as Map)['/']),
      components(rowsOf(LinkHost.site)),
    );
  });

  test('Android verifies one https filter per host group, unmixed', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final filters = RegExp(
      r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
    ).allMatches(manifest).map((m) => m[1]!).toList();
    // Android pairs every host of a filter with every path of it: a host
    // group shares a filter with no other group's paths.
    expect(filters, hasLength(LinkHost.values.length));
    for (final host in LinkHost.values) {
      final filter = filters.singleWhere(
        (f) => f.contains('android:host="${host.hosts.first}"'),
        orElse: () => fail('no verified filter for ${host.name}'),
      );
      expect(filter, contains('android.intent.action.VIEW'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
      expect(filter, contains('android:scheme="https"'));
      expect(
        RegExp('android:host="([^"]*)"')
            .allMatches(filter)
            .map((m) => m[1])
            .toSet(),
        host.hosts.toSet(),
      );
      final paths = RegExp('android:(path|pathPrefix)="([^"]*)"')
          .allMatches(filter)
          .map((m) => (host: host, path: m[2]!, prefix: m[1] == 'pathPrefix'));
      expect(paths, rowsOf(host));
    }
    // The sign-in callback keeps its own filter.
    expect(
      manifest,
      contains(
        'android:scheme="com.snacklist.app" android:host="login-callback"',
      ),
    );
  });

  List<Map<String, Object?>> statements(String path) =>
      (jsonDecode(File(path).readAsStringSync()) as List)
          .cast<Map<String, Object?>>();

  test(
    'assetlinks.json names the package and the signing keys of RELEASE.md',
    () {
      final all = statements('web/.well-known/assetlinks.json');
      final targets = [for (final s in all) s['target']! as Map];
      for (final statement in all) {
        expect(statement['relation'], [
          'delegate_permission/common.handle_all_urls',
        ]);
      }
      expect(targets.map((t) => t['package_name']), [
        applicationId(),
        hummlistId,
      ]);
      // Each app has its own Play app-signing key; both share the upload key.
      // Play App Signing signs what testers install; the upload key what CI
      // builds. All three SHA-256 values are in RELEASE.md's "Android signing"
      // table.
      final sha256 = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
      final snacklist = (targets.first['sha256_cert_fingerprints']! as List)
          .cast<String>();
      final hummlist = (targets.last['sha256_cert_fingerprints']! as List)
          .cast<String>();
      expect(snacklist, everyElement(matches(sha256)));
      expect(hummlist, everyElement(matches(sha256)));
      expect(snacklist, hasLength(2));
      expect(hummlist, hasLength(2));
      expect(snacklist.toSet().intersection(hummlist.toSet()), hasLength(1));
      final release = File('../docs/RELEASE.md').readAsStringSync();
      final table = RegExp('`((?:[0-9A-F]{2}:){31}[0-9A-F]{2})`')
          .allMatches(release)
          .map((m) => m[1])
          .toSet();
      expect(table, containsAll(snacklist));
      expect(table, containsAll(hummlist));
    },
  );

  test("the site's assetlinks.json is the web app's Snacklist statement", () {
    expect(statements('../site/public/.well-known/assetlinks.json'), [
      statements('web/.well-known/assetlinks.json').first,
    ]);
  });

  test("Vercel serves the web app's files as JSON, not as the app", () {
    final vercel = jsonDecode(File('../vercel.json').readAsStringSync()) as Map;
    final rewrites = (vercel['rewrites']! as List).cast<Map<String, Object?>>();
    int indexOf(String destination) =>
        rewrites.indexWhere((r) => r['destination'] == destination);
    final rewrite = rewrites[indexOf('/index.html')]['source']! as String;
    final spa = RegExp('^$rewrite\$');
    // Without the app an invite link opens the static join page (job 169b),
    // which Vercel rewrites before the web app.
    expect(indexOf('/join/index.html'), lessThan(indexOf('/index.html')));
    // Every other link opens the web app.
    for (final link in rowsOf(LinkHost.app)) {
      final path = link.prefix
          ? '${link.path}4f9c2e1a-7b3d-4c8e-9a6f-2d1e0b5c8a7f'
          : link.path;
      if (path.startsWith('/join/')) {
        continue;
      }
      expect(spa.hasMatch(path), isTrue, reason: path);
    }
    expect(spa.hasMatch('/.well-known/apple-app-site-association'), isFalse);
    expect(spa.hasMatch('/.well-known/assetlinks.json'), isFalse);
    // Older iOS versions ask at the root: the same file, rewritten there
    // (Apple follows no redirect) before the web app would take it.
    final root = rewrites.indexWhere(
      (r) => r['source'] == '/apple-app-site-association',
    );
    expect(
      rewrites[root]['destination'],
      '/.well-known/apple-app-site-association',
    );
    expect(root, lessThan(indexOf('/index.html')));
    final headers = (vercel['headers']! as List).cast<Map<String, Object?>>();
    for (final source in [
      '/.well-known/apple-app-site-association',
      '/apple-app-site-association',
    ]) {
      expect(headers.singleWhere((h) => h['source'] == source)['headers'], [
        {'key': 'Content-Type', 'value': 'application/json'},
      ], reason: source);
    }
  });
}
