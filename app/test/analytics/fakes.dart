import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/posthog_client.dart';
import 'package:family_groceries/analytics/posthog_platform_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';

/// The iOS and Android side of posthog_flutter: answers its method channel
/// as the native SDKs do and keeps every call Dart made. The real
/// `Posthog()` runs in front of it, `beforeSend` included, so [events] is
/// what the native SDK would send.
class NativePostHog() {
  final calls = <MethodCall>[];

  /// The distinct id the native SDK keeps on the device; it survives
  /// `close()`, and a bootstrap seeds it only while there is none.
  String? storedId;

  /// The flags PostHog would serve.
  var served = <String, bool>{};

  /// While set, a flag read waits for it: an answer still on its way.
  Completer<void>? flagsHold;

  /// The person properties the next flag request carries
  /// (`setPersonPropertiesForFlags`).
  final flagProperties = <String, Object?>{};

  /// Flags PostHog serves on top of [served] for [flagProperties], as a
  /// release condition on a person property would.
  Map<String, bool> Function(Map<String, Object?> properties)? targeting;

  /// The project tokens MainActivity was asked to forget the SDK's state
  /// for (`familygroceries/posthog`).
  final forgotten = <String>[];

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(
        const MethodChannel('posthog_flutter'),
        _answer,
      )
      ..setMockMethodCallHandler(posthogStateChannel, (call) async {
        forgotten.add((call.arguments as Map)['projectToken'] as String);
        return null;
      });
  }

  Future<Object?> _answer(MethodCall call) async {
    calls.add(call);
    final arguments = call.arguments;
    switch (call.method) {
      case 'setup':
        final bootstrap = (arguments as Map)['bootstrap'];
        final seed = bootstrap is Map
            ? bootstrap['distinctId'] as String?
            : null;
        storedId ??= seed ?? const Uuid().v7();
      case 'reset':
        storedId = const Uuid().v7();
      case 'distinctId':
        return storedId;
      case 'setPersonPropertiesForFlags':
        flagProperties.addAll(
          Map<String, Object?>.from(
            (arguments as Map)['userProperties'] as Map,
          ),
        );
      case 'resetPersonPropertiesForFlags':
        flagProperties.clear();
      case 'getAllFeatureFlags':
        await flagsHold?.future;
        final flags = {...served, ...?targeting?.call(flagProperties)};
        return [
          for (final MapEntry(:key, :value) in flags.entries)
            {'key': key, 'enabled': value},
        ];
    }
    return null;
  }

  /// The names of the methods called, in order.
  List<String> get methods => [for (final c in calls) c.method];

  /// Every event handed to the native SDK: `event` and `properties`.
  List<Map<String, Object?>> get events => [
    for (final call in calls)
      if (call.method == 'capture' || call.method == 'captureException')
        {
          'event': call.method == 'capture'
              ? (call.arguments as Map)['eventName']
              : r'$exception',
          'properties': Map<String, Object?>.from(
            (call.arguments as Map)['properties'] as Map? ?? const {},
          ),
        },
  ];

  /// The names of [events].
  List<String> get names => [for (final e in events) e['event']! as String];

  /// The setup arguments of the last setup.
  Map<Object?, Object?> get setup =>
      calls.lastWhere((c) => c.method == 'setup').arguments as Map;
}

/// One request [FlagsServer] received.
typedef FlagsRequest = ({String method, Uri url, Object? body});

/// PostHog's `/flags` as [PostHogClient.sharedFlags] reaches it, without the
/// SDK: keeps every request and answers with [served].
class FlagsServer() {
  final requests = <FlagsRequest>[];

  /// The flags PostHog would serve.
  var served = <String, bool>{};

  /// Replaces the answer [served] makes (a quota or error answer).
  Map<String, Object?>? answer;

  var status = 200;

  /// No network: every request fails.
  var offline = false;

  /// While set, answers to the requests that come wait for it.
  Completer<void>? hold;

  late final http.Client client = MockClient((request) async {
    requests.add((
      method: request.method,
      url: request.url,
      body: jsonDecode(request.body),
    ));
    // What PostHog had when the request came, answered once [hold] lets go.
    final (status, offline) = (this.status, this.offline);
    final body = jsonEncode(
      answer ??
          {
            'flags': {
              for (final MapEntry(:key, :value) in served.entries)
                key: {'key': key, 'enabled': value},
            },
            'errorsWhileComputingFlags': false,
          },
    );
    await hold?.future;
    if (offline) {
      throw http.ClientException('offline', request.url);
    }
    return http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json'},
    );
  });
}

/// The properties of one of [NativePostHog.events].
Map<String, Object?> propsOf(Map<String, Object?> event) =>
    event['properties']! as Map<String, Object?>;

/// An install's analytics storage that lives as long as the test.
class MemoryAnalyticsStore() implements AnalyticsStore {
  String? id;
  bool? decided;

  /// The consent text version [decided] was given under.
  String? textVersion;
  String? firstOpen;
  var internal = false;

  /// The flags cached from shared requests.
  var sharedFlagValues = <String, bool>{};

  @override
  Future<String?> installId() async => id;

  @override
  Future<void> saveInstallId(String id) async => this.id = id;

  /// While set, deleting the install id waits for it.
  Completer<void>? forgetHold;

  @override
  Future<void> forgetInstallId() async {
    await forgetHold?.future;
    id = null;
    firstOpen = null;
  }

  @override
  Future<bool?> consent() async => decided;

  @override
  Future<String?> consentTextVersion() async => textVersion;

  @override
  Future<void> saveConsent({
    required bool granted,
    required String textVersion,
  }) async {
    decided = granted;
    this.textVersion = textVersion;
  }

  @override
  Future<void> forgetConsent() async {
    decided = null;
    textVersion = null;
  }

  @override
  Future<String?> firstOpenSentFor() async => firstOpen;

  @override
  Future<void> saveFirstOpenSentFor(String installId) async =>
      firstOpen = installId;

  @override
  Future<bool> internalInstall() async => internal;

  @override
  Future<void> saveInternalInstall({required bool internal}) async =>
      this.internal = internal;

  @override
  Future<Map<String, bool>> sharedFlags() async => sharedFlagValues;

  @override
  Future<void> saveSharedFlags(Map<String, bool> values) async =>
      sharedFlagValues = {...values};
}

const releaseConfig = AnalyticsConfig(
  releaseBuild: true,
  householdGroups: false,
  platform: 'web',
  appVersion: '0.1.0+7',
);

/// The whole body of a flag request without consent for [releaseConfig].
const sharedFlagsBody = {
  'token': 'phc_unit_test',
  'distinct_id': 'no-consent',
  'person_properties': {'platform': 'web', 'app_version': '0.1.0+7'},
  'geoip_disable': true,
};

const householdA = '11111111-2222-3333-4444-555555555555';

/// A signed-in customer in household A.
const customer = AnalyticsUser(
  email: 'kunde@gmail.com',
  householdId: householdA,
);

/// The SDK for a stand-in project on a host that can't be reached; flag
/// requests without the SDK go to [server] (one serving nothing by default).
PostHogClient testClient([FlagsServer? server]) => PostHogClient(
  host: 'https://posthog.invalid',
  projectKey: 'phc_unit_test',
  http: (server ?? FlagsServer()).client,
);

/// A loaded [Analytics] on the SDK and [store], for a release build; its
/// SDK start (after a stored yes) has finished.
Future<Analytics> loadedAnalytics(
  MemoryAnalyticsStore store, {
  AnalyticsConfig config = releaseConfig,
  FlagsServer? server,
}) async {
  final analytics = Analytics(testClient(server), store, config);
  await analytics.load();
  await analytics.flush();
  return analytics;
}
