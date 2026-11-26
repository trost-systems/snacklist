import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/core/guides.dart';
import 'package:http/http.dart' as http;

/// The guide lists on snacklist.app; each guide is a slug below its list.
const guidesDePath = '/de/anleitungen';
const guidesEnPath = '/en/guides';

/// The page on snacklist.app for the guide route at [path]. A link to a
/// page's Markdown twin (`<page>.md`) is the page itself, and so is one
/// with a trailing slash.
Uri guidePage(String path) =>
    Uri.parse(guidesBaseUrl + path.replaceFirst(RegExp(r'(\.md|/+)$'), ''));

/// The guide list of [page]'s language.
String guideIndexOf(Uri page) =>
    page.path.startsWith(guidesEnPath) ? guidesEnPath : guidesDePath;

/// A guide as the site serves it.
sealed class const GuideFetch();

/// The page's Markdown, without the twin's footer of alternate URLs.
final class const GuideShown(final String markdown) implements GuideFetch;

/// The site has no such page (404): a draft, a removed slug, a typo.
final class const GuideMissing() implements GuideFetch;

/// No answer, another status, a timeout or a body over [guideMaxBytes].
final class const GuideFailed() implements GuideFetch;

/// The largest twin is about 10 KB; a body over this is not read.
const guideMaxBytes = 256 * 1024;
const guideTimeout = Duration(seconds: 10);

/// Reads [page]'s Markdown twin, the production-gated text the page shows
/// (`markdownTwin` in `site/agent.mjs`).
Future<GuideFetch> fetchGuide(http.Client client, Uri page) async {
  final twin = page.replace(path: '${page.path}.md');
  try {
    return await _read(client, twin).timeout(guideTimeout);
  } on Exception {
    return const GuideFailed();
  }
}

Future<GuideFetch> _read(http.Client client, Uri twin) async {
  final response = await client.send(http.Request('GET', twin));
  if (response.statusCode == 404) {
    unawaited(response.stream.drain<void>());
    return const GuideMissing();
  }
  if (response.statusCode != 200 ||
      (response.contentLength ?? 0) > guideMaxBytes) {
    unawaited(response.stream.drain<void>());
    return const GuideFailed();
  }
  final bytes = <int>[];
  await for (final chunk in response.stream) {
    bytes.addAll(chunk);
    if (bytes.length > guideMaxBytes) {
      return const GuideFailed();
    }
  }
  return GuideShown(_withoutFooter(utf8.decode(bytes)));
}

/// The twin ends with a rule and the page's canonical and alternate URLs,
/// for agents; the page itself does not show them.
String _withoutFooter(String markdown) {
  final footer = markdown.lastIndexOf('\n---\n\nCanonical URL: ');
  return footer == -1 ? markdown : markdown.substring(0, footer);
}
