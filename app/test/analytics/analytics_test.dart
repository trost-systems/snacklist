import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/consent_version.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativePostHog native;
  late FlagsServer server;
  late MemoryAnalyticsStore store;
  late Analytics analytics;

  setUp(() async {
    native = NativePostHog()..install();
    server = FlagsServer();
    store = MemoryAnalyticsStore();
    analytics = await loadedAnalytics(store, server: server);
  });

  /// The bodies of the flag requests made without the SDK.
  List<Object?> sharedRequests() => [for (final r in server.requests) r.body];

  tearDown(() => analytics.close());

  group('consent', () {
    test('a fresh install has not decided and is asked', () {
      expect(analytics.state.consent, isNull);
      expect(analytics.asksConsent, isTrue);
    });

    test('before the decision the SDK is not even set up; only the shared '
        'flags are asked for', () async {
      analytics
        ..setUser(customer)
        ..track('item_ticked')
        ..captureException(StateError('boom'), StackTrace.current);
      await analytics.flush();
      await pumpEventQueue();
      expect(native.calls, isEmpty, reason: 'no setup, no event');
      expect(sharedRequests(), [sharedFlagsBody]);
    });

    test('yes sets the SDK up and sends one first_open per install', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await analytics.decide(granted: true);
      await analytics.flush();
      expect(native.methods.where((m) => m == 'setup'), hasLength(1));
      expect(native.names, ['first_open']);
      expect(store.firstOpen, store.id);

      // The next start of the same install sends none.
      final again = await loadedAnalytics(store);
      again.setUser(customer);
      await again.decide(granted: true);
      await again.flush();
      expect(native.names, ['first_open']);
      expect(again.asksConsent, isFalse);
      await again.close();
    });

    test('no never sets the SDK up, now or at the next start', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: false);
      analytics
        ..track('item_added', {'source': 'typed'})
        ..captureException(StateError('boom'), null);
      await analytics.flush();
      final again = await loadedAnalytics(store, server: server);
      again.setUser(customer);
      await again.flush();
      await pumpEventQueue();
      expect(native.calls, isEmpty);
      expect(sharedRequests(), List.filled(3, sharedFlagsBody));
      expect(store.decided, isFalse);
      expect(again.asksConsent, isFalse);
      await again.close();
    });

    test('turning it off stops the SDK at once', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await analytics.decide(granted: false);
      expect(native.methods.last, 'close');
      final before = native.calls.length;
      analytics
        ..track('item_ticked')
        ..captureException(StateError('boom'), null);
      await analytics.flush();
      expect(native.calls, hasLength(before));
    });

    test('turning it off deletes what the SDK keeps on the device', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      expect(native.forgotten, isEmpty);
      await analytics.decide(granted: false);
      expect(native.forgotten, ['phc_unit_test']);
    });

    test('a start with a stored no deletes it again, without setting the SDK '
        'up', () async {
      store.decided = false;
      final again = await loadedAnalytics(store);
      expect(native.forgotten, ['phc_unit_test']);
      expect(native.calls, isEmpty);
      await again.close();
    });

    test('a later yes from More sends first_open then', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: false);
      await analytics.decide(granted: true);
      await analytics.flush();
      expect(native.names, ['first_open']);
    });

    test('an event right after the yes, while the SDK starts, is sent '
        'with the install id', () async {
      analytics.setUser(customer);
      final yes = analytics.decide(granted: true);
      analytics.track('item_ticked');
      await yes;
      await analytics.flush();
      expect(native.names, containsAll(['first_open', 'item_ticked']));
      expect(
        propsOf(
          native.events.firstWhere((e) => e['event'] == 'item_ticked'),
        )['install_id'],
        store.id,
      );
    });

    test('an event at app start, while the SDK starts, is sent', () async {
      await analytics.decide(granted: true);
      final again = Analytics(testClient(), store, releaseConfig);
      await again.load();
      again
        ..setUser(customer)
        ..track('store_reordered');
      await again.flush();
      expect(native.names.last, 'store_reordered');
      await again.close();
    });

    test('two quick yeses send one first_open', () async {
      analytics.setUser(customer);
      await Future.wait([
        analytics.decide(granted: true),
        analytics.decide(granted: true),
      ]);
      await analytics.flush();
      expect(native.names, ['first_open']);
    });

    test('a no while the SDK starts leaves it stopped', () async {
      analytics.setUser(customer);
      final yes = analytics.decide(granted: true);
      await analytics.decide(granted: false);
      await yes;
      await analytics.flush();
      final lifecycle = native.methods.where(
        (m) => m == 'setup' || m == 'close',
      );
      expect(lifecycle.lastOrNull, isNot('setup'));
      expect(native.names, isEmpty);
      expect(store.id, isNull);
    });

    test('a build without a key never asks and never sends', () async {
      final off = Analytics.off(store);
      await off.load();
      off.setUser(customer);
      expect(off.enabled, isFalse);
      expect(off.asksConsent, isFalse);
      await off.decide(granted: true);
      off.track('item_ticked');
      await off.flush();
      expect(native.calls, isEmpty);
      await off.close();
    });
  });

  // Legal Review 2026-11-01, addendum 12:35: every decision carries the
  // version of the text it was given under; a yes under an older or no
  // version is no decision.
  group('the consent text version', () {
    const kept = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc';

    MemoryAnalyticsStore storedYes(String? version) => MemoryAnalyticsStore()
      ..id = kept
      ..decided = true
      ..textVersion = version
      ..firstOpen = kept;

    for (final (label, version) in [
      ('no version', null),
      ('an older version', '2026-10-30'),
      ('an unknown version', '2027-01-01'),
    ]) {
      test('a yes with $label is asked again and sends only the shared flag '
          'request', () async {
        final older = storedYes(version);
        final own = FlagsServer();
        final a = await loadedAnalytics(older, server: own);
        a
          ..setUser(customer)
          ..track('item_ticked')
          ..captureException(StateError('boom'), StackTrace.current);
        await a.flush();
        await pumpEventQueue();
        expect(a.state.consent, isNull);
        expect(a.asksConsent, isTrue);
        expect(a.flags.isOn('new-thing'), isFalse);
        expect(native.calls, isEmpty, reason: 'no setup, no event');
        expect([for (final r in own.requests) r.body], [sharedFlagsBody]);
        expect(native.forgotten, ['phc_unit_test'], reason: 'as on a no');
        expect(older.id, isNull);
        expect(older.firstOpen, isNull);
        expect(older.decided, isNull, reason: 'asked again at every start');
        expect(older.textVersion, isNull);
        await a.close();
      });
    }

    test(
      'a yes to the current version sends events and asks for flags',
      () async {
        native.served = {'new-thing': true};
        final current = storedYes(consentTextVersion);
        final a = await loadedAnalytics(current);
        a
          ..setUser(customer)
          ..track('item_ticked');
        await a.flush();
        await pumpEventQueue();
        expect(a.state.consent, isTrue);
        expect(a.asksConsent, isFalse);
        expect(native.methods, containsAll(['setup', 'getAllFeatureFlags']));
        expect(native.names, ['item_ticked']);
        expect(a.flags.isOn('new-thing'), isTrue);
        expect(native.forgotten, isEmpty);
        await a.close();
      },
    );

    test('a new yes after the re-ask stores the current version', () async {
      final older = storedYes(null);
      final a = await loadedAnalytics(older);
      a.setUser(customer);
      await a.decide(granted: true);
      await a.flush();
      expect(older.decided, isTrue);
      expect(older.textVersion, consentTextVersion);
      expect(older.id, allOf(isNotNull, isNot(kept)));
      expect(native.names, ['first_open']);
      await a.close();
    });

    test('a no is stored with the version and sends only shared flag '
        'requests', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: false);
      analytics.track('item_ticked');
      await analytics.flush();
      await pumpEventQueue();
      expect(store.decided, isFalse);
      expect(store.textVersion, consentTextVersion);
      expect(native.calls, isEmpty);
      expect(sharedRequests(), List.filled(2, sharedFlagsBody));
    });

    test('a no an older build stored stays a no', () async {
      final older = MemoryAnalyticsStore()..decided = false;
      final a = await loadedAnalytics(older);
      expect(a.state.consent, isFalse);
      expect(a.asksConsent, isFalse);
      expect(native.calls, isEmpty);
      await a.close();
    });

    test('the server gets the version with every answer', () async {
      final versions = <String?>[];
      analytics
        ..recordConsent =
            ({
              required installId,
              required consent,
              required internal,
              required answered,
              required textVersion,
            }) async {
              versions.add(textVersion);
            }
        ..setUser(customer);
      await analytics.decide(granted: true);
      await analytics.decide(granted: false);
      expect(versions, [consentTextVersion, consentTextVersion]);
    });

    test('an outdated yes is not recorded on the server again', () async {
      final recorded = <bool>[];
      final a = await loadedAnalytics(storedYes('2026-10-30'));
      a
        ..recordConsent =
            ({
              required installId,
              required consent,
              required internal,
              required answered,
              required textVersion,
            }) async {
              recorded.add(consent);
            }
        ..setUser(customer);
      await a.flush();
      expect(recorded, isEmpty, reason: 'only a new answer is recorded');
      await a.close();
    });
  });

  group('what the SDK is set up to do', () {
    late Map<Object?, Object?> setup;

    setUp(() async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      setup = native.setup;
    });

    test('only the EU host or a stand-in, personless', () {
      expect(setup['apiKey'], 'phc_unit_test');
      expect(setup['host'], 'https://posthog.invalid');
      expect(setup['personProfiles'], 'never');
    });

    test('nothing it would capture by itself', () {
      expect(setup['captureApplicationLifecycleEvents'], isFalse);
      expect(setup['sessionReplay'], isFalse);
      expect(setup['surveys'], isFalse);
      expect(setup['sendFeatureFlagEvents'], isFalse);
      expect(setup['capturePushNotificationSubscriptions'], isFalse);
      expect(setup['capturePushNotificationOpened'], isFalse);
      expect(setup['rageClickConfig'], containsPair('enabled', false));
    });

    test('native crashes on, its Dart error hooks off', () {
      expect(setup['errorTrackingConfig'], {
        ...setup['errorTrackingConfig']! as Map,
        'captureNativeExceptions': true,
        'captureNativeCrashes': true,
        'captureFlutterErrors': false,
        'capturePlatformDispatcherErrors': false,
        'captureIsolateErrors': false,
      });
    });
  });

  test('the context goes to the SDK as super properties, for native '
      'crash reports', () async {
    Map<String, Object?> registered() => {
      for (final c in native.calls)
        if (c.method == 'register')
          (c.arguments as Map)['key'] as String: (c.arguments as Map)['value']
        else if (c.method == 'unregister')
          (c.arguments as Map)['key'] as String: null,
    };
    await analytics.decide(granted: true);
    await analytics.flush();
    expect(registered(), {
      'install_id': store.id,
      'household_id': null,
      'platform': 'web',
      'app_version': '0.1.0+7',
      'is_internal': false,
      r'$geoip_disable': true,
    });
    analytics.setUser(customer);
    await analytics.markInternalInstall(internal: true);
    await analytics.flush();
    expect(registered(), containsPair('household_id', householdA));
    expect(registered(), containsPair('is_internal', true));
  });

  group('the install id exists only while the answer is yes', () {
    test('a fresh install stores none before the answer', () {
      expect(store.id, isNull);
      expect(store.firstOpen, isNull);
    });

    test('yes stores the SDK distinct id and every event carries it', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      analytics.track('item_ticked');
      await analytics.flush();
      expect(store.id, matches(uuidPattern));
      expect(native.storedId, store.id);
      expect((native.setup['bootstrap']! as Map)['distinctId'], store.id);
      expect(
        [for (final e in native.events) propsOf(e)['install_id']],
        [store.id, store.id],
      );
    });

    test('no stores none', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: false);
      expect(store.id, isNull);
    });

    test('turning it off deletes it; a later yes makes a new one, '
        'also where the SDK kept the old one', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      final first = store.id;

      await analytics.decide(granted: false);
      expect(store.id, isNull);
      expect(store.firstOpen, isNull);
      expect(native.storedId, first, reason: 'the native SDK keeps its own');

      await analytics.decide(granted: true);
      await analytics.flush();
      expect(native.methods, contains('reset'));
      expect(store.id, allOf(isNotNull, isNot(first)));
      expect(native.storedId, store.id);
      expect(native.names, ['first_open', 'first_open']);
      expect(propsOf(native.events.last)['install_id'], store.id);
    });

    test('a stored yes starts the SDK with its id at the next start', () async {
      const kept = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc';
      final older = MemoryAnalyticsStore()
        ..id = kept
        ..decided = true
        ..textVersion = consentTextVersion
        ..firstOpen = kept;
      final a = await loadedAnalytics(older);
      a
        ..setUser(customer)
        ..track('item_ticked');
      await a.flush();
      expect((native.setup['bootstrap']! as Map)['distinctId'], kept);
      expect(native.methods, isNot(contains('reset')));
      expect(older.id, kept);
      expect(native.names, ['item_ticked'], reason: 'no second first_open');
      expect(propsOf(native.events.single)['install_id'], kept);
      await a.close();
    });

    for (final decided in [null, false]) {
      test('an id an older build stored without a yes ($decided) '
          'is deleted at start', () async {
        final older = MemoryAnalyticsStore()
          ..id = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc'
          ..decided = decided
          ..firstOpen = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc';
        final a = await loadedAnalytics(older);
        expect(older.id, isNull);
        expect(older.firstOpen, isNull);
        expect(a.state.consent, decided);
        expect(native.calls, isEmpty);
        await a.close();
      });
    }

    test('a build without a key stores none', () async {
      final fresh = MemoryAnalyticsStore();
      final off = Analytics.off(fresh);
      await off.load();
      expect(fresh.id, isNull);
      await off.close();
    });
  });

  group('signed out', () {
    test('nothing is captured without a user, not even errors', () async {
      await analytics.decide(granted: true);
      analytics
        ..track('item_ticked')
        ..captureException(StateError('login screen'), StackTrace.current);
      await analytics.flush();
      expect(native.events, isEmpty);
    });

    test('nothing after signing out', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      analytics
        ..setUser(null)
        ..track('item_ticked');
      await analytics.flush();
      expect(native.names, ['first_open']);
    });
  });

  group('payload', () {
    late Map<String, Object?> properties;

    setUp(() async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      analytics.track('item_ticked', {
        'actor_role': 'owner',
        'household_size': 2,
      });
      await analytics.flush();
      properties = propsOf(native.events.last);
    });

    test('carries the context and nothing else', () {
      expect(properties.keys.toSet(), {
        'actor_role',
        'household_size',
        'install_id',
        'household_id',
        'platform',
        'app_version',
        'is_internal',
        r'$geoip_disable',
        r'$process_person_profile',
      });
      expect(properties[r'$geoip_disable'], isTrue);
      expect(properties[r'$process_person_profile'], isFalse);
      expect(properties['install_id'], store.id);
      expect(properties['household_id'], householdA);
      expect(properties['is_internal'], isFalse);
      expect(properties['platform'], 'web');
      expect(properties['app_version'], '0.1.0+7');
    });

    test('no household yet sends no household_id', () async {
      analytics
        ..setUser(const AnalyticsUser(email: 'neu@gmail.com'))
        ..track('household_created');
      await analytics.flush();
      expect(propsOf(native.events.last), isNot(contains('household_id')));
    });

    test('the household group goes only with its flag', () async {
      expect(properties, isNot(contains(r'$groups')));
      final grouped = await loadedAnalytics(
        store,
        config: const AnalyticsConfig(
          releaseBuild: true,
          platform: 'ios',
          appVersion: '1.0.0+2',
          householdGroups: true,
        ),
      );
      grouped
        ..setUser(customer)
        ..track('store_reordered');
      await grouped.flush();
      expect(propsOf(native.events.last)[r'$groups'], {
        'household': householdA,
      });
      await grouped.close();
    });
  });

  group('the allow-list', () {
    setUp(() async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
    });

    test('an unknown event is dropped', () async {
      analytics.track('item_name_typed', {'source': 'typed'});
      await analytics.flush();
      expect(native.names, ['first_open']);
    });

    test('an item name in a property is dropped', () async {
      analytics
        ..track('item_added', {'source': 'Hafermilch'})
        ..track('item_ticked', {'name': 'Hafermilch'});
      await analytics.flush();
      expect(native.names, ['first_open']);
    });

    test('the SDK drops what passes Posthog() by Analytics', () async {
      await Posthog().capture(
        eventName: 'item_ticked',
        properties: {'name': 'Hafermilch'},
      );
      await Posthog().screen(screenName: '/join/ABCD-1234');
      await Posthog().captureException(error: StateError('Hafermilch'));
      await analytics.flush();
      expect(native.names, ['first_open']);
    });
  });

  group('is_internal', () {
    Future<bool> internalFor(
      AnalyticsUser user, {
      AnalyticsConfig config = releaseConfig,
      bool install = false,
    }) async {
      final a = await loadedAnalytics(store, config: config);
      await a.markInternalInstall(internal: install);
      a.setUser(user);
      await a.decide(granted: true);
      a.track('store_reordered');
      await a.flush();
      await a.close();
      return propsOf(native.events.last)['is_internal']! as bool;
    }

    test('a customer in a release build is not internal', () async {
      expect(await internalFor(customer), isFalse);
    });

    test('a debug or profile build is internal', () async {
      expect(
        await internalFor(
          customer,
          config: const AnalyticsConfig(
            releaseBuild: false,
            householdGroups: false,
            platform: 'web',
            appVersion: '0.1.0',
          ),
        ),
        isTrue,
      );
    });

    test('a test account is internal', () async {
      for (final email in [
        'peter@fg.test',
        'lea@fg-test.invalid',
        'e2e-1234@example.test',
      ]) {
        expect(
          await internalFor(
            AnalyticsUser(email: email, householdId: householdA),
          ),
          isTrue,
          reason: email,
        );
      }
    });

    test('a listed household is internal', () async {
      expect(
        await internalFor(
          customer,
          config: const AnalyticsConfig(
            releaseBuild: true,
            householdGroups: false,
            platform: 'web',
            appVersion: '0.1.0',
            internalHouseholds: {householdA},
          ),
        ),
        isTrue,
      );
    });

    test('an install marked under More is internal', () async {
      expect(await internalFor(customer, install: true), isTrue);
      expect(store.internal, isTrue);
    });
  });

  test('checkContext refuses an unknown or malformed property', () {
    const id = '0b9f8e3c-1d2a-4c5b-8e7f-123456789abc';
    expect(
      () => checkContext({'install_id': id, r'$ip': '1.2.3.4'}),
      throwsA(isA<RefusedEvent>()),
    );
    expect(
      () => checkContext({'install_id': id, 'household_id': 'Familie Trost'}),
      throwsA(isA<RefusedEvent>()),
    );
    expect(
      () => checkContext({'install_id': id, 'app_version': 'Milch'}),
      throwsA(isA<RefusedEvent>()),
    );
    expect(
      () => checkContext({'install_id': id, r'$geoip_disable': false}),
      throwsA(isA<RefusedEvent>()),
    );
    expect(
      () => checkContext({'platform': 'web'}),
      throwsA(isA<RefusedEvent>()),
    );
  });

  // Job 31: the server keeps each install's answer, so an add over Alexa is
  // counted only after a yes in the app.
  group('the answer reaches the server', () {
    late List<String> recorded;

    Future<void> record({
      required String? installId,
      required bool consent,
      required bool internal,
      required bool answered,
      required String? textVersion,
    }) async {
      recorded.add('$installId $consent $internal $answered');
    }

    setUp(() {
      recorded = [];
      analytics.recordConsent = record;
    });

    test('a yes is recorded under the install id, as an answer', () async {
      analytics.setUser(customer);
      expect(recorded, isEmpty, reason: 'not before the answer');
      await analytics.decide(granted: true);
      expect(recorded, ['${store.id} true false true']);
      // Token refreshes and reloads: nothing new.
      analytics
        ..setUser(customer)
        ..setUser(customer);
      expect(recorded, hasLength(1));
    });

    test(
      'a no is recorded under the id the install had, then without one',
      () async {
        analytics.setUser(customer);
        await analytics.decide(granted: true);
        final id = store.id;
        await analytics.decide(granted: false);
        expect(recorded.last, '$id false false true');
        expect(store.id, isNull, reason: 'job 33b: a no deletes the id');
        // The next start of this install: a no without an id, not an answer.
        final again = await loadedAnalytics(store);
        again
          ..recordConsent = record
          ..setUser(customer);
        expect(recorded.last, 'null false false false');
        await again.close();
      },
    );

    test('a first no on a fresh install has no id', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: false);
      expect(recorded, ['null false false true']);
    });

    test(
      'an answer given signed out is recorded at the next sign-in',
      () async {
        await analytics.decide(granted: true);
        expect(recorded, isEmpty);
        analytics.setUser(customer);
        expect(recorded, ['${store.id} true false false']);
        // Another account on the same install: recorded for it too.
        analytics
          ..setUser(null)
          ..setUser(
            const AnalyticsUser(
              email: 'lea@gmail.com',
              householdId: householdA,
            ),
          );
        expect(recorded, hasLength(2));
      },
    );

    test('marking the install internal records that', () async {
      analytics.setUser(customer);
      await analytics.decide(granted: true);
      await analytics.markInternalInstall(internal: true);
      expect(recorded.last, '${store.id} true true false');
    });

    test('a failed write is tried again on the next change', () async {
      var fail = true;
      analytics
        ..recordConsent =
            ({
              required installId,
              required consent,
              required internal,
              required answered,
              required textVersion,
            }) async {
              if (fail) {
                throw Exception('offline');
              }
              recorded.add('$installId $consent');
            }
        ..setUser(customer);
      await analytics.decide(granted: true);
      await pumpEventQueue();
      fail = false;
      analytics.setUser(customer);
      expect(recorded, ['${store.id} true']);
    });

    test('a build without a key records nothing', () async {
      final off = Analytics(null, store, releaseConfig);
      await off.load();
      off
        ..recordConsent = record
        ..setUser(customer);
      await off.decide(granted: true);
      expect(recorded, isEmpty);
      await off.close();
    });
  });
}
