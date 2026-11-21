import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/consent_version.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late NativePostHog native;
  late FlagsServer server;
  late MemoryAnalyticsStore store;
  final opened = <Analytics>[];

  setUp(() {
    native = NativePostHog()
      ..install()
      ..served = {'new-thing': true, 'old-thing': false};
    server = FlagsServer();
    store = MemoryAnalyticsStore();
  });

  tearDown(() async {
    for (final analytics in opened) {
      await analytics.close();
    }
    opened.clear();
  });

  /// Analytics on [store] after an app start, its requests answered.
  Future<Analytics> start() async {
    final analytics = await loadedAnalytics(store, server: server);
    opened.add(analytics);
    await pumpEventQueue();
    return analytics;
  }

  /// The native SDK telling Dart that flags arrived.
  Future<void> flagsArrive(Analytics analytics) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'posthog_flutter',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onFeatureFlagsCallback'),
          ),
          (_) {},
        );
    await analytics.flush();
    await pumpEventQueue();
  }

  void decidedNo() => store
    ..decided = false
    ..textVersion = consentTextVersion;

  group('without consent', () {
    for (final (name, before) in [
      ('not asked yet', () {}),
      ('after a no', decidedNo),
    ]) {
      test('$name: a flag is what PostHog serves the one shared id, asked '
          'once, nothing else sent or kept', () async {
        before();
        server.served = {'new-thing': true, 'old-thing': false};
        final analytics = await start();
        analytics.setUser(customer);
        await pumpEventQueue();
        expect(analytics.flags.isOn('new-thing'), isTrue);
        expect(analytics.flags.isOn('old-thing'), isFalse);
        expect(server.requests, hasLength(1));
        final request = server.requests.single;
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://posthog.invalid/flags/?v=2');
        expect(request.body, sharedFlagsBody);
        expect(native.calls, isEmpty, reason: 'no SDK, no event');
        expect(store.id, isNull);
        expect(store.firstOpen, isNull);
        expect(store.sharedFlagValues, {'new-thing': true, 'old-thing': false});
      });
    }

    test(
      'a yes under an older consent text asks for the shared flags',
      () async {
        store
          ..decided = true
          ..textVersion = 'older'
          ..id = '0190e6c2-0000-7000-8000-000000000001';
        server.served = {'new-thing': true};
        final analytics = await start();
        expect(analytics.flags.isOn('new-thing'), isTrue);
        expect(server.requests.single.body, sharedFlagsBody);
        expect(store.id, isNull);
      },
    );

    for (final (name, fail) in <(String, void Function())>[
      ('offline', () => server.offline = true),
      ('a server error', () => server.status = 500),
      (
        'over the quota',
        () => server.answer = {
          'flags': <String, Object?>{},
          'quotaLimited': ['feature_flags'],
        },
      ),
      (
        'errors while computing',
        () => server.answer = {
          'flags': {
            'new-thing': {'key': 'new-thing', 'enabled': false},
          },
          'errorsWhileComputingFlags': true,
        },
      ),
      ('an answer without flags', () => server.answer = {'status': 1}),
    ]) {
      test('$name: the cached flags stay', () async {
        store.sharedFlagValues = {'new-thing': true};
        fail();
        final analytics = await start();
        expect(analytics.flags.isOn('new-thing'), isTrue);
        expect(store.sharedFlagValues, {'new-thing': true});
        expect(server.requests, hasLength(1));
      });
    }

    test('the cached flags show before PostHog answers', () async {
      store.sharedFlagValues = {'new-thing': true};
      server
        ..hold = Completer()
        ..served = {'new-thing': false};
      final analytics = await start();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      server.hold!.complete();
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isFalse);
      expect(store.sharedFlagValues, {'new-thing': false});
    });

    test('an older answer that comes after a newer one is dropped', () async {
      decidedNo();
      final older = server.hold = Completer();
      server.served = {'new-thing': false};
      final analytics = await start();
      final newer = server.hold = Completer();
      server.served = {'new-thing': true};
      await analytics.decide(granted: false);
      await pumpEventQueue();
      expect(server.requests, hasLength(2));
      newer.complete();
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      older.complete();
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      expect(store.sharedFlagValues, {'new-thing': true});
    });

    test('a first start offline, nothing cached: every flag off', () async {
      server.offline = true;
      final analytics = await start();
      expect(analytics.flags.state, isEmpty);
      expect(analytics.flags.isOn('new-thing'), isFalse);
    });

    test('the next start offline serves what was cached', () async {
      server.served = {'new-thing': true};
      await start();
      server.offline = true;
      final again = await start();
      expect(again.flags.isOn('new-thing'), isTrue);
    });
  });

  group('with consent', () {
    test('after the yes a flag is what PostHog served this install', () async {
      server.served = {'new-thing': false, 'shared-thing': true};
      final analytics = await start();
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      expect(analytics.flags.isOn('old-thing'), isFalse);
      expect(analytics.flags.isOn('shared-thing'), isFalse);
      expect(analytics.flags.isOn('unknown'), isFalse);
      expect(native.storedId, store.id);
      expect(anyUuidPattern.hasMatch(store.id!), isTrue);
      expect(server.requests, hasLength(1), reason: 'only before the yes');
    });

    test('the shared flags show until the SDK has an answer', () async {
      server.served = {'new-thing': true};
      native.served = {};
      final analytics = await start();
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      native.served = {'new-thing': false, 'later-thing': true};
      await flagsArrive(analytics);
      expect(analytics.flags.isOn('new-thing'), isFalse);
      expect(analytics.flags.isOn('later-thing'), isTrue);
    });

    test('a shared answer that comes after the yes is dropped', () async {
      server
        ..hold = Completer()
        ..served = {'new-thing': false, 'shared-thing': true};
      final analytics = await start();
      await analytics.decide(granted: true);
      await pumpEventQueue();
      server.hold!.complete();
      await pumpEventQueue();
      expect(analytics.flags.isOn('new-thing'), isTrue);
      expect(analytics.flags.isOn('shared-thing'), isFalse);
    });

    test('flags that arrive later replace the ones read at start', () async {
      final analytics = await start();
      await analytics.decide(granted: true);
      native.served = {'new-thing': false, 'later-thing': true};
      await flagsArrive(analytics);
      expect(analytics.flags.isOn('new-thing'), isFalse);
      expect(analytics.flags.isOn('later-thing'), isTrue);
    });

    test('a stored yes reads the flags at the next start, and asks for no '
        'shared ones', () async {
      final analytics = await start();
      await analytics.decide(granted: true);
      final again = await start();
      expect(again.flags.isOn('new-thing'), isTrue);
      expect(server.requests, hasLength(1));
    });

    test('offline, before any answer, every flag stays off', () async {
      native.served = {};
      server.offline = true;
      final analytics = await start();
      await analytics.decide(granted: true);
      expect(analytics.flags.state, isEmpty);
      expect(analytics.flags.isOn('new-thing'), isFalse);
    });
  });

  test('a no after a yes: the install id goes, the SDK stops, the flags are '
      'the cached shared ones at once, then a fresh answer', () async {
    server.served = {'shared-thing': true};
    final analytics = await start();
    analytics.setUser(customer);
    await analytics.decide(granted: true);
    await pumpEventQueue();
    expect(analytics.flags.isOn('new-thing'), isTrue);
    expect(store.id, isNotNull);
    final sent = native.calls.length;
    server
      ..hold = Completer()
      ..served = {'shared-thing': false, 'other-thing': true};
    await analytics.decide(granted: false);
    expect(analytics.flags.isOn('new-thing'), isFalse);
    expect(analytics.flags.isOn('shared-thing'), isTrue);
    await pumpEventQueue();
    expect(server.requests, hasLength(2));
    expect(server.requests.last.body, sharedFlagsBody);
    expect(store.id, isNull);
    expect(native.methods.skip(sent), contains('close'));
    expect(native.forgotten, ['phc_unit_test']);
    server.hold!.complete();
    await pumpEventQueue();
    expect(analytics.flags.isOn('shared-thing'), isFalse);
    expect(analytics.flags.isOn('other-thing'), isTrue);
    analytics.track('first_open');
    await analytics.flush();
    await pumpEventQueue();
    expect(native.methods.skip(sent), isNot(contains('capture')));
    await flagsArrive(analytics);
    expect(analytics.flags.isOn('new-thing'), isFalse);
  });

  test('identified flags that arrive after the no, before the SDK stops, '
      'do not land', () async {
    server.served = {'shared-thing': true};
    final analytics = await start();
    analytics.setUser(customer);
    await analytics.decide(granted: true);
    await pumpEventQueue();
    native
      ..served = {'late-thing': true}
      ..flagsHold = Completer();
    unawaited(flagsArrive(analytics));
    await pumpEventQueue();
    store.forgetHold = Completer();
    final no = analytics.decide(granted: false);
    await pumpEventQueue();
    native.flagsHold!.complete();
    await pumpEventQueue();
    expect(analytics.flags.isOn('late-thing'), isFalse);
    expect(analytics.flags.isOn('shared-thing'), isFalse);
    store.forgetHold!.complete();
    await no;
    await pumpEventQueue();
    expect(analytics.flags.isOn('late-thing'), isFalse);
    expect(analytics.flags.isOn('shared-thing'), isTrue);
  });

  test('a yes after a no: a new install id, first_open and the flags of '
      'the install', () async {
    decidedNo();
    server.served = {'shared-thing': true};
    final analytics = await start();
    analytics.setUser(customer);
    await analytics.decide(granted: true);
    await pumpEventQueue();
    expect(anyUuidPattern.hasMatch(store.id!), isTrue);
    expect(native.names, ['first_open']);
    expect(analytics.flags.isOn('new-thing'), isTrue);
    expect(analytics.flags.isOn('shared-thing'), isFalse);
  });

  group('targeting by is_internal and build', () {
    late Analytics analytics;

    setUp(() async {
      native.targeting = (properties) => {
        'internal-only': properties['is_internal'] == true,
      };
      analytics = await start();
    });

    List<Object?> sent() => [
      for (final c in native.calls)
        if (c.method == 'setPersonPropertiesForFlags')
          ((c.arguments as Map)['userProperties'] as Map)['is_internal'],
    ];

    test('after the yes PostHog evaluates flags with is_internal and the '
        'build, as flag properties only', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(native.flagProperties, {
        'is_internal': false,
        'platform': 'web',
        'app_version': '0.1.0+7',
        'app_build': 7,
      });
      expect(analytics.flags.isOn('internal-only'), isFalse);
      expect(native.methods, isNot(contains('setPersonProperties')));
      expect(native.methods, isNot(contains('identify')));
    });

    test('marked internal: sent again once, and the flags follow', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      await analytics.markInternalInstall(internal: true);
      await pumpEventQueue();
      expect(analytics.flags.isOn('internal-only'), isTrue);
      // Context registered again without a change sends nothing new.
      analytics.testerHousehold = null;
      await pumpEventQueue();
      await analytics.markInternalInstall(internal: false);
      await pumpEventQueue();
      expect(sent(), [false, true, false]);
      expect(analytics.flags.isOn('internal-only'), isFalse);
    });

    test('a no clears it; the next yes sends it again', () async {
      await analytics.markInternalInstall(internal: true);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      await analytics.decide(granted: false);
      await pumpEventQueue();
      expect(native.methods, contains('resetPersonPropertiesForFlags'));
      expect(native.flagProperties, isEmpty);
      expect(analytics.flags.isOn('internal-only'), isFalse);
      expect(
        server.requests.last.body,
        sharedFlagsBody,
        reason:
            'no is_internal and no app_build: no version condition '
            'matches without consent',
      );
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(native.flagProperties, containsPair('is_internal', true));
      expect(native.flagProperties, containsPair('app_build', 7));
      expect(analytics.flags.isOn('internal-only'), isTrue);
    });
  });

  test('the build number goes only where the version has one', () {
    AnalyticsConfig version(String v) => AnalyticsConfig(
      releaseBuild: true,
      householdGroups: false,
      platform: 'ios',
      appVersion: v,
    );
    expect(version('1.4.0+1414').appBuild, 1414);
    expect(version('1.4.0').appBuild, isNull);
    expect(version('0').appBuild, isNull);
  });

  test('a build without a key has every flag off, cached ones too', () async {
    store.sharedFlagValues = {'new-thing': true};
    final off = Analytics.off(store);
    await off.load();
    await pumpEventQueue();
    expect(off.flags.isOn('new-thing'), isFalse);
    await off.decide(granted: true);
    expect(off.flags.isOn('new-thing'), isFalse);
    await off.close();
  });

  test('a forced flag is on whatever PostHog serves', () async {
    final flags = Flags(forced: {'public-api'});
    expect(flags.isOn('public-api'), isTrue);
    flags.replace({'public-api': false, 'other': true});
    expect(flags.isOn('public-api'), isTrue);
    expect(flags.isOn('other'), isTrue);
    flags.replace(const {});
    expect(flags.isOn('public-api'), isTrue);
    expect(flags.isOn('other'), isFalse);
    await flags.close();
  });
}
