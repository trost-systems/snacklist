import 'package:device_info_plus/device_info_plus.dart';
import 'package:family_groceries/analytics/setup.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What a note carries besides the text (docs/FEEDBACK.md): enough to
/// reproduce a problem, nothing from the list. Each field fits the
/// database's check on `public.feedback`.
@immutable
class const FeedbackContext({
  /// `0.1.0`, from package_info_plus like More's version line.
  required final String appVersion,

  /// The build number, `1023`; `none` when the platform has none.
  required final String build,

  /// ios, android, web, linux, macos, windows.
  required final String platform,

  /// `Android 14 (SDK 34)`, `iOS 18.1`; on the web the browser family and
  /// OS, `Chrome on Android`, never the user agent.
  required final String osVersion,

  /// The app's language: `de` or `en`.
  required final String locale,

  /// A name from `screenNames`.
  required final String screen,

  /// The analytics rules (internal.dart); the database adds test accounts.
  required final bool isInternal,

  /// The household shown when the note was written (job 169b); the server
  /// keeps it if the sender is a member, else files the note under their
  /// default household.
  final String? householdId,
});

/// The build and device facts of [FeedbackContext], read once.
@immutable
class const DeviceFacts({
  required final String appVersion,
  required final String build,
  required final String platform,
  required final String osVersion,
});

/// Where [DeviceFacts] come from; a fake in tests.
abstract interface class FeedbackDevice() {
  Future<DeviceFacts> read();
}

/// package_info_plus and device_info_plus, cached after the first read;
/// never throws (what can't be read is `unknown`).
class PluginFeedbackDevice() implements FeedbackDevice {
  Future<DeviceFacts>? _facts;

  @override
  Future<DeviceFacts> read() => _facts ??= _read();

  static Future<DeviceFacts> _read() async {
    final (info, os) = await (_packageInfo(), _osVersion()).wait;
    return DeviceFacts(
      appVersion: fitField(info?.version ?? '', 32),
      build: fitField(info?.buildNumber ?? '', 16, empty: 'none'),
      platform: platformName(web: kIsWeb, platform: defaultTargetPlatform),
      osVersion: fitField(os, 64),
    );
  }

  static Future<PackageInfo?> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } on Object {
      return null;
    }
  }

  static Future<String> _osVersion() async {
    try {
      return switch (await DeviceInfoPlugin().deviceInfo) {
        WebBrowserInfo(:final userAgent) => webOsVersion(userAgent ?? ''),
        AndroidDeviceInfo(:final version) =>
          'Android ${version.release} (SDK ${version.sdkInt})',
        IosDeviceInfo(:final systemName, :final systemVersion) =>
          '$systemName $systemVersion',
        MacOsDeviceInfo(:final majorVersion, :final minorVersion) =>
          'macOS $majorVersion.$minorVersion',
        LinuxDeviceInfo(:final prettyName) => prettyName,
        WindowsDeviceInfo(:final productName, :final displayVersion) =>
          '$productName $displayVersion',
        _ => 'unknown',
      };
    } on Object {
      return 'unknown';
    }
  }
}

/// [text] without control characters, trimmed, at most [max] characters;
/// [empty] when nothing is left.
String fitField(String text, int max, {String empty = 'unknown'}) {
  final clean = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (clean.isEmpty) {
    return empty;
  }
  final runes = clean.runes;
  return runes.length <= max
      ? clean
      : String.fromCharCodes(runes.take(max)).trim();
}

/// The browser family and OS of a user agent, `Safari on iOS`; nothing
/// else of it (versions, device, extensions) is kept.
String webOsVersion(String userAgent) {
  bool has(String part) => userAgent.contains(part);
  final browser = has('Edg/') || has('EdgA/') || has('EdgiOS/')
      ? 'Edge'
      : has('SamsungBrowser/')
      ? 'Samsung Internet'
      : has('OPR/') || has('OPiOS/')
      ? 'Opera'
      : has('Firefox/') || has('FxiOS/')
      ? 'Firefox'
      : has('Chrome/') || has('CriOS/') || has('Chromium/')
      ? 'Chrome'
      : has('Safari/')
      ? 'Safari'
      : 'Browser';
  final os = has('Android')
      ? 'Android'
      : has('iPhone') || has('iPad') || has('iPod')
      ? 'iOS'
      : has('CrOS')
      ? 'ChromeOS'
      : has('Mac OS X') || has('Macintosh')
      ? 'macOS'
      : has('Windows')
      ? 'Windows'
      : has('Linux')
      ? 'Linux'
      : 'unknown OS';
  return '$browser on $os';
}
