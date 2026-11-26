import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/PUSH.md, "Native": without these the OS never hands out a token.
void main() {
  // development is Xcode's value for debug builds; the store build is signed
  // with the App Store profile's production, which the next test checks.
  test('iOS has the APNs entitlement', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(
      entitlements,
      matches(RegExp(r'<key>aps-environment</key>\s*<string>development<')),
    );
  });

  test('the TestFlight build is checked for production APNs', () {
    final fastfile = File('fastlane/Fastfile').readAsStringSync();
    final beta = fastfile.substring(
      fastfile.indexOf('lane :beta do'),
      fastfile.indexOf('upload? ? upload_ipa'),
    );
    expect(beta, contains('scripts/ios-push-entitlements.py"), ipa)'));
  });

  test('iOS has the remote-notification background mode', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      info,
      matches(
        RegExp(
          r'<key>UIBackgroundModes</key>\s*<array>[^/]*'
          '<string>remote-notification</string>',
        ),
      ),
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
