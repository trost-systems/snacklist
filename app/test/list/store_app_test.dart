import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:flutter_test/flutter_test.dart';

const lidlPlus = RetailerApp(
  name: 'Lidl Plus',
  android: 'com.lidl.eci.lidlplus',
  ios: '1238611143',
);
const rewe = RetailerApp(
  name: 'REWE',
  android: 'de.rewe.app.mobile',
  ios: '714121079',
  universalLink: 'https://www.rewe.de/shop',
);
const edeka = RetailerApp(
  name: 'EDEKA',
  android: 'de.edeka.genuss',
  ios: '1272688648',
  scheme: 'edeka',
);
const kaufland = RetailerApp(
  name: 'Kaufland',
  android: 'com.kaufland.Kaufland',
  ios: '1087780386',
  scheme: 'com.kaufland.iosapp',
);
const both = RetailerApp(
  name: 'REWE',
  android: 'de.rewe.app.mobile',
  ios: '714121079',
  universalLink: 'https://www.rewe.de/shop',
  scheme: 'rewe',
);
const lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [lidlPlus],
);

/// Takes what it is told to take; records every attempt in order.
final class _Opener(final bool Function(String target) takes)
    implements StoreAppOpener {
  final tried = <String>[];

  @override
  Future<bool> launchPackage(String package) async {
    tried.add('package:$package');
    return takes(package);
  }

  @override
  Future<bool> openLink(Uri url, {required bool appOnly}) async {
    tried.add(appOnly ? 'app-only:$url' : '$url');
    return takes('$url');
  }
}

class _Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add((event, properties));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Job 313 (DL1): what a tap on a store's app key opens, per platform.
void main() {
  group('the plan', () {
    List<String> plan(RetailerApp? app, StoreAppPlatform platform) => [
      for (final step in storeAppPlan(app, platform))
        switch (step) {
          LaunchPackage(:final package) =>
            'package:$package ${step.outcome.wire}',
          OpenLink(:final url, :final appOnly) =>
            '${appOnly ? 'app-only:' : ''}$url ${step.outcome.wire}',
        },
    ];

    test('Android: the app, then Play, then Play on the web', () {
      const play =
          'https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus';
      expect(plan(lidlPlus, StoreAppPlatform.android), [
        'package:com.lidl.eci.lidlplus app',
        'market://details?id=com.lidl.eci.lidlplus store_page',
        '$play store_page',
      ]);
    });

    test('iOS with a universal link: it, for an app only, then the App '
        'Store', () {
      expect(plan(rewe, StoreAppPlatform.ios), [
        'app-only:https://www.rewe.de/shop app',
        'itms-apps://apps.apple.com/app/id714121079 store_page',
      ]);
    });

    test('iOS with a URL scheme: its bare root, for any app, then the App '
        'Store', () {
      expect(plan(edeka, StoreAppPlatform.ios), [
        'edeka:// app',
        'itms-apps://apps.apple.com/app/id1272688648 store_page',
      ]);
    });

    test('a dotted scheme keeps its dots and gets nothing after //', () {
      expect(plan(kaufland, StoreAppPlatform.ios), [
        'com.kaufland.iosapp:// app',
        'itms-apps://apps.apple.com/app/id1087780386 store_page',
      ]);
    });

    test('iOS with both: the universal link first, then the scheme', () {
      expect(plan(both, StoreAppPlatform.ios), [
        'app-only:https://www.rewe.de/shop app',
        'rewe:// app',
        'itms-apps://apps.apple.com/app/id714121079 store_page',
      ]);
    });

    test('a scheme stays off Android and the web app: the package opens on '
        'Android, and a browser would show an error for a missing app', () {
      for (final platform in [
        StoreAppPlatform.android,
        StoreAppPlatform.iphoneBrowser,
        StoreAppPlatform.other,
      ]) {
        expect(plan(edeka, platform), isNot(contains(startsWith('edeka:'))));
      }
    });

    test('iOS without either: the App Store at once', () {
      expect(plan(lidlPlus, StoreAppPlatform.ios), [
        'itms-apps://apps.apple.com/app/id1238611143 store_page',
      ]);
    });

    test("the web app on an iPhone: the App Store's web page", () {
      expect(plan(lidlPlus, StoreAppPlatform.iphoneBrowser), [
        'https://apps.apple.com/app/id1238611143 store_page',
      ]);
    });

    test("the web app elsewhere and desktops: Play's web page, never the "
        "chain's own site (Legal N-296)", () {
      const play =
          'https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus';
      expect(plan(lidlPlus, StoreAppPlatform.other), ['$play store_page']);
    });

    test('nothing without an app, on every platform', () {
      for (final platform in StoreAppPlatform.values) {
        expect(plan(null, platform), isEmpty);
      }
    });
  });

  group('running it', () {
    test('iOS: an installed app takes its scheme, a missing one falls '
        'through to the App Store', () async {
      final steps = storeAppPlan(edeka, StoreAppPlatform.ios);
      final installed = _Opener((t) => t == 'edeka://');
      expect(await runStoreAppPlan(steps, installed), StoreAppOutcome.app);
      expect(installed.tried, ['edeka://']);

      final missing = _Opener((t) => t.startsWith('itms-apps:'));
      expect(await runStoreAppPlan(steps, missing), StoreAppOutcome.storePage);
      expect(missing.tried, [
        'edeka://',
        'itms-apps://apps.apple.com/app/id1272688648',
      ]);
    });

    final steps = storeAppPlan(lidlPlus, StoreAppPlatform.android);

    test('stops at the first step that opens', () async {
      final opener = _Opener((_) => true);
      expect(await runStoreAppPlan(steps, opener), StoreAppOutcome.app);
      expect(opener.tried, ['package:com.lidl.eci.lidlplus']);
    });

    test('goes on to the next when one does not', () async {
      final opener = _Opener((t) => t.startsWith('https:'));
      expect(await runStoreAppPlan(steps, opener), StoreAppOutcome.storePage);
      expect(opener.tried, [
        'package:com.lidl.eci.lidlplus',
        'market://details?id=com.lidl.eci.lidlplus',
        'https://play.google.com/store/apps/details?id=com.lidl.eci.lidlplus',
      ]);
    });

    test('answers null when none opens', () async {
      expect(await runStoreAppPlan(steps, _Opener((_) => false)), isNull);
    });
  });

  group('openStoreApp', () {
    const store = Store(
      id: 's',
      name: 'Lidl am Markt',
      sortOrder: 10,
      retailer: lidl,
    );

    for (final source in StoreAppSource.values) {
      test('reports the chain, its country, what opened and the tap '
          '(${source.wire}), never the store', () async {
        final tracked = _Tracked();
        final outcome = await openStoreApp(
          store,
          opener: _Opener((t) => t.startsWith('market:')),
          analytics: tracked,
          source: source,
          platform: StoreAppPlatform.android,
        );
        expect(outcome, StoreAppOutcome.storePage);
        final (event, properties) = tracked.events.single;
        expect(event, 'store_app_opened');
        expect(properties, {
          'chain': 'lidl',
          'country': 'DE',
          'outcome': 'store_page',
          'source': source.wire,
        });
        expect(() => checkEvent(event, properties), returnsNormally);
      });
    }

    test('reports nothing when nothing opened', () async {
      final tracked = _Tracked();
      expect(
        await openStoreApp(
          store,
          opener: _Opener((_) => false),
          analytics: tracked,
          source: StoreAppSource.header,
          platform: StoreAppPlatform.ios,
        ),
        isNull,
      );
      expect(tracked.events, isEmpty);
    });

    test('opens nothing for a store without a chain', () async {
      final opener = _Opener((_) => true);
      expect(
        await openStoreApp(
          const Store(id: 's', name: 'Wochenmarkt', sortOrder: 10),
          opener: opener,
          source: StoreAppSource.store,
        ),
        isNull,
      );
      expect(opener.tried, isEmpty);
    });
  });
}
