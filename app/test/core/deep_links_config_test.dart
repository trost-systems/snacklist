import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 22, 66 and 462: the app URL's paths in [appLinks] and snacklist.app's
/// in [siteLinks] open the installed app. The files must agree with those
/// tables, and a mismatch only shows on a device: the iOS entitlement,
/// Android's two verified intent filters, the files the web build and the
/// site serve under `/.well-known/`, and Vercel's rules that serve them as
/// JSON instead of the app's index.html or the site's 404 page.
void main() {
  final appUrl = Uri.parse(
    (jsonDecode(File('config/auth.json').readAsStringSync())
            as Map<String, Object?>)['APP_URL']!
        as String,
  );
  const teamId = 'VCZSHMZY25';
  // Job 174: the Hummlist build stays installed until Snacklist replaces it,
  // so its app id and its host stay next to Snacklist's.
  const hummlistId = 'com.hummlist.app';
  final hosts = {...appLinkHosts, appUrl.host};

  test('APP_URL is one of the app hosts', () {
    expect(appLinkHosts, contains(appUrl.host));
  });

  List<String> components(String file) {
    final aasa = jsonDecode(File(file).readAsStringSync()) as Map;
    final details =
        ((aasa['applinks']! as Map)['details']! as List).single as Map;
    return [
      for (final c in details['components']! as List)
        (c as Map)['/']! as String,
    ];
  }

  List<String> table(List<AppLink> links) => [
    for (final link in links)
      if (link.prefix) '${link.path}*' else link.path,
  ];

  /// The verified intent filters of the manifest: their hosts and paths.
  List<({Set<String> hosts, List<AppLink> paths, String xml})> filters() {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    return [
      for (final m in RegExp(
        r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
      ).allMatches(manifest))
        (
          xml: m[1]!,
          hosts: {
            for (final h in RegExp('android:host="([^"]*)"').allMatches(m[1]!))
              h[1]!,
          },
          paths: [
            for (final p in RegExp(
              'android:(path|pathPrefix)="([^"]*)"',
            ).allMatches(m[1]!))
              (path: p[2]!, prefix: p[1] == 'pathPrefix'),
          ],
        ),
    ];
  }

  String bundleId() => RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
      .allMatches(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      )
      .map((m) => m[1]!)
      .firstWhere((id) => !id.endsWith('Tests'));

  String applicationId() => RegExp(r'applicationId = "([\w.]+)"')
      .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())![1]!;

  test('the iOS app claims applinks for the app URL and the site', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(entitlements, contains('com.apple.developer.associated-domains'));
    final claimed = RegExp('<string>applinks:([^<]*)</string>')
        .allMatches(entitlements)
        .map((m) => m[1]);
    // Not www.snacklist.app: it redirects, and Apple does not follow that.
    expect(claimed, unorderedEquals({...hosts, siteLinkHost}));
    // Sign in with Apple stays.
    expect(entitlements, contains('com.apple.developer.applesignin'));
  });

  test('apple-app-site-association names the app and the table', () {
    final aasa = jsonDecode(
      File('web/.well-known/apple-app-site-association').readAsStringSync(),
    ) as Map<String, Object?>;
    final details =
        ((aasa['applinks']! as Map)['details']! as List).single as Map;
    expect(details['appIDs'], ['$teamId.${bundleId()}', '$teamId.$hummlistId']);
    expect(
      components('web/.well-known/apple-app-site-association'),
      table(appLinks),
    );
  });

  test(
    "the site's apple-app-site-association names Snacklist and the guides",
    () {
      const file = '../site/public/.well-known/apple-app-site-association';
      final aasa = jsonDecode(File(file).readAsStringSync()) as Map;
      final details =
          ((aasa['applinks']! as Map)['details']! as List).single as Map;
      expect(details['appIDs'], ['$teamId.${bundleId()}']);
      expect(components(file), table(siteLinks));
    },
  );

  // A filter's hosts and paths combine, so each host's table needs its own
  // filter: one filter would claim /list on snacklist.app.
  test('Android verifies one https filter per host table', () {
    final verified = filters();
    expect(verified.map((f) => f.hosts), [
      hosts,
      {siteLinkHost},
    ]);
    expect(verified.map((f) => f.paths), [appLinks, siteLinks]);
    for (final filter in verified) {
      expect(filter.xml, contains('android.intent.action.VIEW'));
      expect(filter.xml, contains('android.intent.category.BROWSABLE'));
      expect(
        RegExp('android:scheme="([^"]*)"')
            .allMatches(filter.xml)
            .map((m) => m[1]),
        everyElement('https'),
      );
    }
    // The sign-in callback keeps its own filter.
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains(
        'android:scheme="com.snacklist.app" android:host="login-callback"',
      ),
    );
  });

  test("the site's assetlinks.json is the app's Snacklist statement", () {
    final app = jsonDecode(
      File('web/.well-known/assetlinks.json').readAsStringSync(),
    ) as List;
    final site = jsonDecode(
      File('../site/public/.well-known/assetlinks.json').readAsStringSync(),
    );
    expect(site, [
      app.singleWhere(
        (s) =>
            ((s as Map)['target']! as Map)['package_name'] == applicationId(),
      ),
    ]);
  });

  test(
    'assetlinks.json names the package and the signing keys of RELEASE.md',
    () {
      final statements = (jsonDecode(
        File('web/.well-known/assetlinks.json').readAsStringSync(),
      ) as List).cast<Map<String, Object?>>();
      final targets = [for (final s in statements) s['target']! as Map];
      for (final statement in statements) {
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
    expect(spa.hasMatch('/apple-app-site-association'), isTrue);
    expectServesAasa(vercel, before: '/index.html');
  });

  test('the site serves its association files as JSON', () {
    final vercel =
        jsonDecode(File('../site/vercel.json').readAsStringSync()) as Map;
    expectServesAasa(vercel);
    // No redirect for every host catches them (the hummlist.com ones are
    // for that host).
    final redirects = (vercel['redirects']! as List)
        .cast<Map<String, Object?>>();
    for (final redirect in redirects) {
      if (redirect['has'] == null) {
        final source = RegExp('^${redirect['source']}\$');
        expect(source.hasMatch('/apple-app-site-association'), isFalse);
        expect(source.hasMatch('/.well-known/assetlinks.json'), isFalse);
      }
    }
  });
}

/// Both of [vercel]'s AASA paths are JSON, and the root one is the
/// `.well-known` file, rewritten before the rewrite to [before].
void expectServesAasa(Map<Object?, Object?> vercel, {String? before}) {
  const file = '/.well-known/apple-app-site-association';
  final rewrites = (vercel['rewrites']! as List).cast<Map<String, Object?>>();
  final root = rewrites.indexWhere(
    (r) => r['source'] == '/apple-app-site-association',
  );
  expect(root, isNot(-1));
  expect(rewrites[root]['destination'], file);
  if (before != null) {
    expect(
      root,
      lessThan(rewrites.indexWhere((r) => r['destination'] == before)),
    );
  }
  final headers = (vercel['headers']! as List).cast<Map<String, Object?>>();
  for (final path in [file, '/apple-app-site-association']) {
    expect(headers.singleWhere((h) => h['source'] == path)['headers'], [
      {'key': 'Content-Type', 'value': 'application/json'},
    ], reason: path);
  }
}
