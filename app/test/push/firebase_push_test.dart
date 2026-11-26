import 'dart:async';

import 'package:family_groceries/push/firebase_push.dart';
import 'package:family_groceries/push/push_plugin.dart';
// ast-grep-ignore: firebase-only-in-firebase-push -- tests FirebasePush itself
import 'package:firebase_core/firebase_core.dart';
// ast-grep-ignore: firebase-only-in-firebase-push -- its core mocks
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The iOS side of firebase_messaging as the plugin behaves (17.1.0): it asks
/// APNs for the device token only while auto-init is on, and the token comes
/// back a moment later.
class FakeApple() {
  var autoInit = false;
  var pollsUntilApns = 2;
  String? apnsToken;
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'Messaging#setAutoInitEnabled':
        autoInit = (call.arguments as Map)['enabled'] as bool;
        return {'isAutoInitEnabled': autoInit};
      case 'Messaging#getAPNSToken':
        if (autoInit && --pollsUntilApns <= 0) {
          apnsToken = 'apns';
        }
        return {'token': apnsToken};
      case 'Messaging#getToken':
        return {'token': 'fcm'};
      case 'Messaging#deleteToken':
        return null;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  // The plugin's Dart side checks for the APNs token on Apple platforms only.
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  late FakeApple apple;
  late FirebasePush push;

  setUp(() {
    apple = FakeApple();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_messaging'),
          apple.handle,
        );
    push = FirebasePush(
      PushPlatform.ios,
      // The options setupFirebaseCoreMocks answers with.
      const FirebaseOptions(
        apiKey: '123',
        appId: '123',
        messagingSenderId: '123',
        projectId: '123',
      ),
    );
  });

  testWidgets('the token waits for APNs, which needs auto-init on', (
    tester,
  ) async {
    final token = push.token();
    await tester.pump(const Duration(seconds: 2));

    expect(await token, 'fcm');
    expect(
      apple.calls.indexOf('Messaging#getToken'),
      greaterThan(apple.calls.lastIndexOf('Messaging#getAPNSToken')),
    );
  }, variant: ios);

  testWidgets('after a restart with auto-init off, the token is deleted '
      '(the catch-up of an offline sign-out)', (tester) async {
    final deleted = push.deleteToken();
    await tester.pump(const Duration(seconds: 2));
    await deleted;

    expect(apple.calls, contains('Messaging#deleteToken'));
    expect(apple.autoInit, isFalse, reason: 'no new token at the next start');
  }, variant: ios);

  testWidgets('a delete its caller gave up on cannot take the next token', (
    tester,
  ) async {
    apple.pollsUntilApns = 8; // APNs answers after about 3.5 s.
    final abandoned = expectLater(
      push.deleteToken().timeout(const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 3));
    await abandoned;

    final token = push.token();
    await tester.pump(const Duration(seconds: 2));

    expect(await token, 'fcm');
    expect(
      apple.calls.lastIndexOf('Messaging#getToken'),
      greaterThan(apple.calls.lastIndexOf('Messaging#deleteToken')),
    );
    expect(apple.autoInit, isTrue, reason: 'refreshed tokens still arrive');
  }, variant: ios);
}
