import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/PUSH.md, "Native": without these the OS never hands out a token.
void main() {
  test('iOS has the APNs entitlement', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(
      entitlements,
      matches(RegExp(r'<key>aps-environment</key>\s*<string>development<')),
    );
  });

  test('Android may ask for notifications (Android 13 and later)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains(
        '<uses-permission '
        'android:name="android.permission.POST_NOTIFICATIONS"/>',
      ),
    );
  });

  test('release builds pass the Firebase defines through', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();
    final workflow = File('../.github/workflows/release.yml')
        .readAsStringSync();
    for (final name in [
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_IOS_APP_ID',
      'FIREBASE_IOS_API_KEY',
      'FIREBASE_ANDROID_APP_ID',
      'FIREBASE_ANDROID_API_KEY',
    ]) {
      expect(fastfile, contains(name), reason: name);
      expect(workflow, contains('$name: \${{ vars.$name }}'), reason: name);
    }
  });
}
