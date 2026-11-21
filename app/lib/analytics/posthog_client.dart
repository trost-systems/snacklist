import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/posthog_platform.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' show Client;
import 'package:posthog_flutter/posthog_flutter.dart';

/// The one distinct id every install without an analytics yes shares for
/// its flag requests ([PostHogClient.sharedFlags], Legal §18 FL1'). Never
/// an id of this install: nothing about it is stored or sent.
const sharedFlagsId = 'no-consent';

/// Whether the shared flag request also carries `is_internal` and
/// `tester_groups` for an internal user or one in a tester group, so
/// testers get their flags without an analytics yes. Legal rejected it
/// (N-313): it stays false (docs/ANALYTICS.md, "Tester groups without
/// consent", job 337).
const sharedFlagsCarryTesterGroups = false;

/// What may go to PostHog for [event] with [properties], or null to drop
/// it: `Analytics`' gate, run on every Dart-side event before the SDK adds
/// its own properties.
typedef Admit = Map<String, Object>? Function(
  String event,
  Map<String, Object> properties,
);

/// PostHog for one project, the only file that talks to it
/// (docs/ANALYTICS.md, "How it is built"). After a yes: the posthog_flutter
/// SDK (posthog-js under it on the web), set up only then. Without one:
/// [sharedFlags], one plain request, since the SDK keeps device ids on the
/// device and sends them with its flag requests.
class PostHogClient({
  required final String host,
  required final String projectKey,

  /// For [sharedFlags]; tests hand in a fake server.
  Client? http,
}) {
  final Client _http = http ?? Client();

  /// Sets the SDK up, seeding [installId] as its distinct id when it has
  /// none stored, and returns the distinct id it uses. Every Dart-side event
  /// passes [admit] first; [onFlags] runs when flags arrive.
  Future<String> start({
    required String? installId,
    required Admit admit,
    required void Function() onFlags,
  }) async {
    await loadPostHogJs(
      host: host,
      projectKey: projectKey,
      installId: installId,
    );
    final config = PostHogConfig(projectKey)
      ..host = host
      ..personProfiles = PostHogPersonProfiles.never
      ..captureApplicationLifecycleEvents = false
      ..sendFeatureFlagEvent = false
      ..sessionReplay = false
      ..surveys = false
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..beforeSend = [(event) => _admitted(event, admit)]
      ..onFeatureFlags = onFlags
      ..bootstrap = installId == null
          ? null
          : PostHogBootstrapConfig(distinctId: installId);
    config.rageClickConfig.enabled = false;
    // Dart errors come through Analytics.captureException, which scrubs them
    // with the error at hand; the SDK's own Dart hooks would hand beforeSend
    // only strings. Native crashes never reach Dart (docs/ANALYTICS.md).
    config.errorTrackingConfig
      ..captureNativeExceptions = true
      ..captureNativeCrashes = true;
    await Posthog().setup(config);
    return await Posthog().getDistinctId();
  }

  static PostHogEvent? _admitted(PostHogEvent event, Admit admit) {
    final properties = admit(event.event, event.properties ?? const {});
    if (properties == null) {
      return null;
    }
    return event
      ..properties = properties
      ..userProperties = null
      ..userPropertiesSetOnce = null;
  }

  /// Drops the stored distinct id for a new one and returns it.
  Future<String> newDistinctId() async {
    await Posthog().reset();
    return await Posthog().getDistinctId();
  }

  /// Super properties, added by the SDK to every event it sends, the ones
  /// it builds natively (crash reports) included; null removes one.
  Future<void> register(Map<String, Object?> properties) => Future.wait([
    for (final MapEntry(:key, :value) in properties.entries)
      if (value == null)
        Posthog().unregister(key)
      else
        Posthog().register(key, value),
  ]);

  Future<void> capture(String event, Map<String, Object> properties) =>
      Posthog().capture(eventName: event, properties: properties);

  Future<void> captureException(
    Object error,
    StackTrace? stack,
    Map<String, Object> properties,
  ) => Posthog().captureException(
    error: error,
    stackTrace: stack,
    properties: properties,
  );

  /// The flags PostHog evaluated for this install, by key.
  Future<Map<String, bool>> flags() async {
    final results = await Posthog().getAllFeatureFlags();
    return {
      for (final flag in results ?? const <PostHogFeatureFlagResult>[])
        flag.key: flag.enabled,
    };
  }

  /// Person properties for flag targeting only: they go with each flag
  /// request and make no person profile. Waits for the flags they select.
  Future<void> flagProperties(Map<String, Object> properties) =>
      Posthog().setPersonPropertiesForFlags(properties);

  Future<void> flush() => Posthog().flush();

  /// Stops the SDK and deletes what it keeps on the device, ids and queued
  /// events included; [start] sets it up again.
  Future<void> stop() async {
    // posthog_flutter's web handler drops `reloadFeatureFlags: false`, and
    // posthog-js would ask for flags with the install id after the no; its
    // `close` does nothing there. Memory only on the web, and the next start
    // sends `is_internal` again.
    if (!kIsWeb) {
      await Posthog().resetPersonPropertiesForFlags(reloadFeatureFlags: false);
    }
    await Posthog().close();
    await forget();
  }

  /// Deletes what a stopped SDK left on the device.
  Future<void> forget() => forgetPostHogState(projectKey);

  /// The flags PostHog evaluates for [sharedFlagsId], by key, or null
  /// without a usable answer. Sends the project key, that id, [platform],
  /// [appVersion] and [targeting] (empty unless
  /// [sharedFlagsCarryTesterGroups]) as flag properties (which make no
  /// person profile) and no GeoIP lookup; no cookies, no SDK. Never throws.
  Future<Map<String, bool>?> sharedFlags({
    required String platform,
    required String appVersion,
    Map<String, Object> targeting = const {},
  }) async {
    try {
      final response = await _http
          .post(
            Uri.parse(host).resolve('/flags/?v=2'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'token': projectKey,
              'distinct_id': sharedFlagsId,
              'person_properties': {
                'platform': platform,
                'app_version': appVersion,
                ...targeting,
              },
              'geoip_disable': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      return _servedFlags(jsonDecode(response.body));
    } on Object {
      return null;
    }
  }

  /// The flags of a `/flags/?v=2` answer. Null for one computed with errors
  /// or over the quota: PostHog then serves flags off that may be on.
  static Map<String, bool>? _servedFlags(Object? answer) => switch (answer) {
    {'errorsWhileComputingFlags': true} => null,
    {'quotaLimited': final List<Object?> limited}
        when limited.contains('feature_flags') =>
      null,
    {'flags': final Map<String, Object?> flags} => {
      for (final MapEntry(:key, :value) in flags.entries)
        if (value case {'enabled': final bool enabled}) key: enabled,
    },
    _ => null,
  };
}
