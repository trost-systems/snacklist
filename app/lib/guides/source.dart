import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/guides/model.dart';
import 'package:http/http.dart' as http;

/// How asking the site for a guides page went.
sealed class const GuideAnswer();

final class const GuideLoaded(final GuideContent content) extends GuideAnswer;

/// A 404: the site no longer has this guide (or never had it).
final class const GuideMissing() extends GuideAnswer;

/// No usable answer (offline, a timeout, a 5xx, a file this app cannot
/// read): worth another try.
final class const GuideFailed() extends GuideAnswer;

/// The guides' JSON on snacklist.app, which the site build writes next to
/// their pages (`site/guide-data.mjs`). A plain GET, no cookies; the site
/// serves `/data/` to any origin, so the web app reads it too.
final class GuideSource(
  final http.Client client, {
  final String base = guidesBaseUrl,
}) {
  static const timeout = Duration(seconds: 15);

  /// Larger bodies are not read: a long guide is a few dozen KB.
  static const maxBytes = 1024 * 1024;

  Future<GuideAnswer> load(GuideRef ref) async {
    final http.Response response;
    try {
      response = await client
          .get(Uri.parse('$base${ref.dataPath}'))
          .timeout(timeout);
    } on Object {
      return const GuideFailed();
    }
    if (response.statusCode == 404) {
      return const GuideMissing();
    }
    if (response.statusCode != 200 || response.bodyBytes.length > maxBytes) {
      return const GuideFailed();
    }
    final String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } on FormatException {
      return const GuideFailed();
    }
    return switch (parseGuideContent(ref, body)) {
      final content? => GuideLoaded(content),
      null => const GuideFailed(),
    };
  }
}
