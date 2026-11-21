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

  group('targeting by is_internal and tester_groups', () {
    late Analytics analytics;

    setUp(() async {
      native.targeting = (properties) => {
        'internal-only': properties['is_internal'] == true,
        'beta-de-only': '${properties['tester_groups']}'
            .split(',')
            .contains('beta-de'),
      };
      analytics = await start();
    });

    List<Object?> sent() => [
      for (final c in native.calls)
        if (c.method == 'setPersonPropertiesForFlags')
          (c.arguments as Map)['userProperties'],
    ];

    test('after the yes PostHog evaluates flags with is_internal and '
        'tester_groups, as flag properties only', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(sent(), [
        {'is_internal': false, 'tester_groups': ''},
      ]);
      expect(analytics.flags.isOn('internal-only'), isFalse);
      expect(native.methods, isNot(contains('setPersonProperties')));
      expect(native.methods, isNot(contains('identify')));
    });

    test(
      'in the group internal: sent again once, and the flags follow',
      () async {
        analytics.setUser(customer);
        await analytics.decide(granted: true);
        await pumpEventQueue();
        analytics.setTesterGroups({'internal'});
        await pumpEventQueue();
        expect(analytics.flags.isOn('internal-only'), isTrue);
        // Context registered again without a change sends nothing new.
        analytics
          ..testerHousehold = null
          ..setTesterGroups({'internal'});
        await pumpEventQueue();
        analytics.setTesterGroups({});
        await pumpEventQueue();
        expect(sent(), [
          {'is_internal': false, 'tester_groups': ''},
          {'is_internal': true, 'tester_groups': 'internal'},
          {'is_internal': false, 'tester_groups': ''},
        ]);
        expect(analytics.flags.isOn('internal-only'), isFalse);
      },
    );

    test('an opt-in group targets its flag without making the user '
        'internal', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      analytics.setTesterGroups({'internal', 'beta-de', 'alexa'});
      await pumpEventQueue();
      analytics.setTesterGroups({'beta-de'});
      await pumpEventQueue();
      expect(sent().skip(1), [
        {'is_internal': true, 'tester_groups': 'alexa,beta-de,internal'},
        {'is_internal': false, 'tester_groups': 'beta-de'},
      ]);
      expect(analytics.flags.isOn('beta-de-only'), isTrue);
      expect(analytics.flags.isOn('internal-only'), isFalse);
    });

    test('a no clears it; the next yes sends it again', () async {
      analytics
        ..setUser(customer)
        ..setTesterGroups({'internal'});
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
        reason: 'no is_internal, no tester_groups',
      );
      await analytics.decide(granted: true);
      await pumpEventQueue();
      expect(native.flagProperties, {
        'is_internal': true,
        'tester_groups': 'internal',
      });
      expect(analytics.flags.isOn('internal-only'), isTrue);
    });
  });

  group('shared flags with tester groups (off until Legal answers)', () {
    const switchedOn = AnalyticsConfig(
      releaseBuild: true,
      householdGroups: false,
      platform: 'web',
      appVersion: '0.1.0+7',
      sharedFlagsTargeting: true,
    );

    Future<Analytics> startWith(AnalyticsConfig config) async {
      final analytics = await loadedAnalytics(
        store,
        server: server,
        config: config,
      );
      opened.add(analytics);
      await pumpEventQueue();
      return analytics;
    }

    test('switched off (the build default), a tester without consent asks '
        'exactly as everyone else', () async {
      decidedNo();
      final analytics = await startWith(releaseConfig);
      analytics
        ..setUser(customer)
        ..setTesterGroups({'internal', 'beta-de'});
      await pumpEventQueue();
      expect(server.requests, hasLength(1));
      expect(server.requests.single.body, sharedFlagsBody);
    });

    test('switched on, a tester without consent asks again with '
        'is_internal and tester_groups, no id', () async {
      decidedNo();
      server.served = {'beta-only': false};
      final analytics = await startWith(switchedOn);
      analytics.setUser(customer);
      await pumpEventQueue();
      expect(server.requests.single.body, sharedFlagsBody);
      server.served = {'beta-only': true};
      analytics.setTesterGroups({'beta-de'});
      await pumpEventQueue();
      expect(server.requests, hasLength(2));
      expect(server.requests.last.body, {
        ...sharedFlagsBody,
        'person_properties': {
          'platform': 'web',
          'app_version': '0.1.0+7',
          'is_internal': false,
          'tester_groups': 'beta-de',
        },
      });
      expect(analytics.flags.isOn('beta-only'), isTrue);
      expect(store.sharedFlagValues, {
        'beta-only': false,
      }, reason: "the device keeps only everyone's answer");
      expect(native.calls, isEmpty, reason: 'no SDK, no event');
      expect(store.id, isNull);
    });

    test('switched on, a customer outside every group asks exactly as '
        'before', () async {
      final analytics = await startWith(switchedOn);
      analytics
        ..setUser(customer)
        ..setTesterGroups({});
      await pumpEventQueue();
      expect(server.requests, hasLength(1));
      expect(server.requests.single.body, sharedFlagsBody);
    });
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
