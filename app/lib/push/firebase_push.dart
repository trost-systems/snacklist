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

  @override
  Future<String?> token() async {
    final messaging = await _messaging;
    // [deleteToken] switched it off; on, a refreshed token arrives itself.
    await messaging.setAutoInitEnabled(true);
    if (platform == PushPlatform.ios) {
      // getToken throws until APNs has given the device its token, which
      // takes a moment after the first permission.
      for (var i = 0; i < 10 && await messaging.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
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
  Future<void> deleteToken() async {
    final messaging = await _messaging;
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
