import 'dart:async';

import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/push/push_plugin.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging on iOS and Android, configured from the build's
/// defines; null on the web, on Linux and in a build without them (no push,
/// docs/PUSH.md).
PushPlugin? pushPluginFor({
  required bool web,
  required TargetPlatform platform,
}) {
  final app = switch ((web, platform)) {
    (false, TargetPlatform.iOS) => (
      platform: PushPlatform.ios,
      appId: Environment.firebaseIosAppId,
      apiKey: Environment.firebaseIosApiKey,
    ),
    (false, TargetPlatform.android) => (
      platform: PushPlatform.android,
      appId: Environment.firebaseAndroidAppId,
      apiKey: Environment.firebaseAndroidApiKey,
    ),
    _ => null,
  };
  if (app == null ||
      app.appId.isEmpty ||
      app.apiKey.isEmpty ||
      Environment.firebaseProjectId.isEmpty ||
      Environment.firebaseMessagingSenderId.isEmpty) {
    return null;
  }
  return FirebasePush(
    app.platform,
    FirebaseOptions(
      apiKey: app.apiKey,
      appId: app.appId,
      messagingSenderId: Environment.firebaseMessagingSenderId,
      projectId: Environment.firebaseProjectId,
    ),
  );
}

/// The one file that touches Firebase. It is initialized on first use, so a
/// user who never opts in never starts it (PushRegistration asks only then).
class FirebasePush(
  @override final PushPlatform platform,
  final FirebaseOptions _options,
) implements PushPlugin {
  Future<FirebaseMessaging>? _started;

  /// The last [deleteToken], which may still run after its caller's timeout
  /// gave up on it (iOS waits for APNs first). [token] waits for it, so a
  /// late delete cannot take the token registered after it.
  Future<void>? _deleting;

  Future<FirebaseMessaging> get _messaging => _started ??= _start();

  Future<FirebaseMessaging> _start() async {
    try {
      await Firebase.initializeApp(options: _options);
      return FirebaseMessaging.instance;
    } on Object {
      // The next call tries again.
      _started = null;
      rethrow;
    }
  }

  static PushPermission _of(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.notDetermined => PushPermission.undetermined,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
      };

  @override
  Future<PushPermission> permission() async =>
      _of(await (await _messaging).getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async =>
      _of(await (await _messaging).requestPermission());

  /// Turns auto-init on ([deleteToken] switched it off; on, a refreshed
  /// token arrives itself). On iOS it then waits for the APNs token:
  /// getToken and deleteToken throw until APNs has given the device one, and
  /// the plugin asks APNs for it only while auto-init is on.
  Future<void> _autoInitOn(FirebaseMessaging messaging) async {
    await messaging.setAutoInitEnabled(true);
    if (platform == PushPlatform.ios) {
      for (var i = 0; i < 10 && await messaging.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Future<String?> token() async {
    final messaging = await _messaging;
    if (_deleting case final deleting?) {
      await deleting;
    }
    await _autoInitOn(messaging);
    // Registration tokens are the server's contract (docs/PUSH.md); moving
    // to the installation ids that replace them is a later job.
    // ignore: deprecated_member_use -- see above.
    return await messaging.getToken();
  }

  @override
  Stream<String> get tokenRefreshes =>
      Stream.fromFuture(_messaging).asyncExpand(
        // ignore: deprecated_member_use -- see [token].
        (messaging) => messaging.onTokenRefresh,
      );

  @override
  Future<void> deleteToken() {
    final deleting = _delete();
    _deleting = deleting.then((_) {}, onError: (Object _) {});
    return deleting;
  }

  Future<void> _delete() async {
    final messaging = await _messaging;
    if (platform == PushPlatform.ios) {
      // After a restart with auto-init off (a sign-out that could not
      // delete), iOS has no APNs token, and the delete would fail each time.
      await _autoInitOn(messaging);
    }
    // Left on, Android makes a new token at the next start.
    await messaging.setAutoInitEnabled(false);
    // ignore: deprecated_member_use -- see [token].
    await messaging.deleteToken();
  }

  @override
  Future<Map<String, Object?>?> initialMessage() async =>
      (await (await _messaging).getInitialMessage())?.data;

  @override
  Stream<Map<String, Object?>> get openedMessages =>
      Stream.fromFuture(_messaging)
          .asyncExpand((_) => FirebaseMessaging.onMessageOpenedApp)
          .map((m) => m.data);
}
