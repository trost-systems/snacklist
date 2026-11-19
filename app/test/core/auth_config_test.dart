import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/core/environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// `config/auth.json` holds the public defines of every production build.
void main() {
  final defines = jsonDecode(
    File('config/auth.json').readAsStringSync(),
  ) as Map<String, Object?>;

  /// The iOS client ID lives in two files: the Dart define and the reversed
  /// URL scheme Google redirects back to. A mismatch only fails on a device.
  test('Auth.xcconfig carries the reversed iOS client ID', () {
    final iosClientId = defines['GOOGLE_IOS_CLIENT_ID']! as String;
    final xcconfig = File('ios/Flutter/Auth.xcconfig').readAsStringSync();
    final reversed = RegExp(
      r'^GOOGLE_REVERSED_CLIENT_ID\s*=\s*(\S*)\s*$',
      multiLine: true,
    ).firstMatch(xcconfig)![1];

    expect(reversed, iosClientId.split('.').reversed.join('.'));
  });

  test('APP_URL is an https origin', () {
    final appUrl = Uri.parse(defines['APP_URL']! as String);

    expect(appUrl.scheme, 'https');
    expect(appUrl.host, isNotEmpty);
    expect(appUrl.origin, defines['APP_URL']);
  });

  test('without the defines a build has no app URL to link to', () {
    expect(Environment.appUrl, isEmpty);
  });

  test('every production build passes config/auth.json', () {
    final builds = {
      'fastlane/Fastfile': RegExp(r'flutter\("build"[^)]*\)'),
      '../scripts/vercel.sh': RegExp(r'flutter build web(?:[^\n]*\\\n)*[^\n]*'),
    };
    for (final MapEntry(key: path, value: build) in builds.entries) {
      final commands = build
          .allMatches(File(path).readAsStringSync())
          .map((m) => m[0]!)
          .toList();

      expect(commands, isNotEmpty, reason: path);
      for (final command in commands) {
        expect(
          command,
          contains('--dart-define-from-file=config/auth.json'),
          reason: '$path: $command',
        );
      }
    }
  });
}
